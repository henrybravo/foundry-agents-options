# Publishes shared\skills\trail-review as a Foundry skill, attaches it to
# a Foundry toolbox, and points the hosted agents (01-04) at that toolbox
# through TRAIL_TOOLBOX_ENDPOINT. Redeploy the agents afterwards
# (scripts\deploy.ps1) so the new env var reaches them. Later skill edits
# need only this script: the toolbox serves the skill's default version.
# -ProjectEndpoint picks the Foundry project that hosts the skill and
# toolbox; the default is the agents' own project. When the toolbox lives in
# another Foundry resource than the agents, each agent identity gets
# Foundry User on that resource.
# -Clear removes TRAIL_TOOLBOX_ENDPOINT so the agents use the bundled skill.
# Run: pwsh scripts\publish-skill.ps1 [-ProjectEndpoint <url>] [-Clear]
[CmdletBinding()]
param(
    [string] $ProjectEndpoint,
    [string] $Skill = 'trail-review',
    [string] $Toolbox = 'trail-toolbox',
    [switch] $Clear
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$hosted = @{
    '01-langgraph-deepagents' = 'trail-deepagents'
    '02-langgraph-workflow'   = 'trail-langgraph-workflow'
    '03-maf-workflow'         = 'trail-maf-workflow'
    '04-maf-harness'          = 'trail-maf-harness'
}
$foundryUser = '53ca6127-db72-4b80-b1b0-d745d6d5456d'   # built-in role ID

function Invoke-Azd([string[]] $Arguments) {
    Write-Host "azd $($Arguments -join ' ')" -ForegroundColor DarkGray
    & azd @Arguments --no-prompt
    if ($LASTEXITCODE -ne 0) {
        throw "azd $($Arguments[0..2] -join ' ') failed"
    }
}

function Test-Azd([string[]] $Arguments) {
    & azd @Arguments --no-prompt *> $null
    $LASTEXITCODE -eq 0
}

function Set-AgentEnv([string] $Value) {
    foreach ($folder in $hosted.Keys) {
        $cwd = Join-Path $root $folder
        if ($Value) {
            azd env set TRAIL_TOOLBOX_ENDPOINT $Value -C $cwd --no-prompt
        }
        else {
            azd env set TRAIL_TOOLBOX_ENDPOINT '' -C $cwd --no-prompt
        }
        if ($LASTEXITCODE -ne 0) { throw "azd env set failed in $folder" }
    }
}

function Get-AccountId([string] $Endpoint) {
    $account = ([uri] $Endpoint).Host.Split('.')[0]
    $id = az cognitiveservices account list `
        --query "[?name=='$account'].id | [0]" -o tsv
    if (-not $id) { throw "Foundry resource '$account' not found" }
    $id.Trim()
}

if ($Clear) {
    Set-AgentEnv ''
    Write-Host ('Cleared TRAIL_TOOLBOX_ENDPOINT; redeploy to use the ' +
        'bundled skill.')
    return
}

$agentEndpoint = (azd env get-value FOUNDRY_PROJECT_ENDPOINT `
        -C (Join-Path $root '01-langgraph-deepagents')).Trim()
if (-not $ProjectEndpoint) { $ProjectEndpoint = $agentEndpoint }
$ep = $ProjectEndpoint.TrimEnd('/')
$skillDir = Join-Path $root "shared\skills\$Skill"

# Each update becomes the skill's new default version.
if (Test-Azd @('ai', 'skill', 'show', $Skill, '-p', $ep)) {
    Invoke-Azd @(
        'ai', 'skill', 'update', $Skill, '--file', $skillDir, '-p', $ep
    )
}
else {
    Invoke-Azd @(
        'ai', 'skill', 'create', $Skill, '--file', $skillDir, '-p', $ep
    )
}

if (-not (Test-Azd @(
            'ai', 'toolbox', 'show', $Toolbox, '--project-endpoint', $ep
        ))) {
    $definition = Join-Path ([IO.Path]::GetTempPath()) "$Toolbox.yaml"
    @(
        'description: Trail review demo toolbox that serves the trail-review skill'
        'skills:'
        "  - name: $Skill"
    ) | Set-Content $definition -Encoding utf8NoBOM
    Invoke-Azd @(
        'ai', 'toolbox', 'create', $Toolbox, '--from-file', $definition,
        '--project-endpoint', $ep
    )
}

# The consumer endpoint serves the toolbox's default version.
$mcp = "$ep/toolboxes/$Toolbox/mcp?api-version=v1"
Set-AgentEnv $mcp
Write-Host "TRAIL_TOOLBOX_ENDPOINT = $mcp" -ForegroundColor Green

# Agent identities reach their own project implicitly; another Foundry
# resource needs an explicit role assignment.
$scope = Get-AccountId $ep
if ($scope -eq (Get-AccountId $agentEndpoint)) { return }

foreach ($name in $hosted.Values) {
    $agent = az rest --method get --resource https://ai.azure.com `
        --url "$agentEndpoint/agents/$name" --uri-parameters api-version=v1 |
        ConvertFrom-Json
    $principal = $agent.versions.latest.instance_identity.principal_id
    $existing = az role assignment list --assignee $principal --scope $scope `
        --role $foundryUser --query '[0].id' -o tsv
    if ($existing) { continue }
    az role assignment create --assignee-object-id $principal `
        --assignee-principal-type ServicePrincipal --role $foundryUser `
        --scope $scope -o none
    if ($LASTEXITCODE -ne 0) { throw "Role assignment failed for $name" }
    Write-Host "Granted Foundry User on the toolbox resource to $name"
}

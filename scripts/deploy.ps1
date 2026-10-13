# Deploys the five Trail review demo agents into ONE shared Foundry project.
# Without -ProjectId, 01 provisions a new project (azd up) and the others
# attach to it; with -ProjectId, all attach to that existing project.
# 00-prompt-agent always deploys last: it is a prompt agent without code,
# so it needs the project and model deployments to exist first.
# -Model picks the model deployment each agent version uses. With several
# models, every agent gets one version per model, deployed in the given
# order; the last model becomes the latest (default) version.
# Uses the current Azure CLI sign-in. The first run records its subscription
# and tenant in each azd environment; later runs switch to that subscription
# and refuse to run against any other. -Subscription/-TenantId override.
# -ProjectName names the new Foundry project and its resource group
# (default foundry-agent-options); without it azd would name the project
# after the first agent's folder. Ignored when -ProjectId is given.
# -SkipProvision runs only 'azd deploy' (new agent versions, no ARM changes)
# once the project and model deployments exist.
# Run: pwsh scripts\deploy.ps1
#      pwsh scripts\deploy.ps1 -Model gpt-6-sol,gpt-5.6-sol,gpt-5.4-mini
#      pwsh scripts\deploy.ps1 -SkipProvision
[CmdletBinding(SupportsShouldProcess)]
param(
    [string] $Location = 'swedencentral',
    [string] $Subscription,
    [string] $TenantId,
    [string] $ProjectId,
    [string] $ProjectName = 'foundry-agent-options',
    [string[]] $Agent = @(
        '00-prompt-agent',
        '01-langgraph-deepagents',
        '02-langgraph-workflow',
        '03-maf-workflow',
        '04-maf-harness'
    ),
    # Deployment names declared in 01-langgraph-deepagents\azure.yaml.
    [string[]] $Model = @('gpt-5.4-mini'),
    [switch] $SkipProvision
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$Agent = @($Agent | ForEach-Object { $_ -split ',' } | Where-Object { $_ })
$prompt = '00-prompt-agent'
$Agent = @($Agent | Sort-Object { $_ -eq $prompt })
$Model = @($Model | ForEach-Object { $_ -split ',' } |
    ForEach-Object { $_.Trim() } | Where-Object { $_ })

function Invoke-Azd([string] $Folder, [string[]] $Arguments) {
    $cwd = Join-Path $root $Folder
    $line = "azd $($Arguments -join ' ')  [$Folder]"
    Write-Host $line -ForegroundColor DarkGray
    if ($PSCmdlet.ShouldProcess($Folder, "azd $($Arguments -join ' ')")) {
        & azd @Arguments -C $cwd --no-prompt
        if ($LASTEXITCODE -ne 0) { throw "azd failed in $Folder" }
    }
}

function Get-ProjectId([string] $Folder) {
    $id = azd env get-value AZURE_AI_PROJECT_ID -C (Join-Path $root $Folder)
    if ($LASTEXITCODE -ne 0 -or -not $id) {
        throw "No AZURE_AI_PROJECT_ID in $Folder"
    }
    $id.Trim()
}

function Get-ProjectEndpoint([string] $ProjectId) {
    # https://<account>.services.ai.azure.com/api/projects/<project>, derived
    # from /subscriptions/<s>/resourceGroups/<g>/providers/<p>/accounts/<a>/projects/<n>
    $parts = $ProjectId -split '/'
    "https://$($parts[8]).services.ai.azure.com/api/projects/$($parts[10])"
}

function Add-SharedProject([string] $Folder, [string] $ProjectId) {
    # Newer azure.ai.agents extension versions (seen with 1.0.0-beta.19) expand
    # ${FOUNDRY_PROJECT_ENDPOINT} in the manifest before 'ai project add'
    # runs, so set it first from the shared project's ARM ID.
    Invoke-Azd $Folder @(
        'env', 'set', 'FOUNDRY_PROJECT_ENDPOINT', (Get-ProjectEndpoint $ProjectId)
    )
    Invoke-Azd $Folder @(
        'ai', 'project', 'add', '--project-id', $ProjectId, '--force'
    )
}

function Initialize-ProjectEnv {
    # azd names the Foundry project and resource group after the environment,
    # so give 01 an environment named for the demo. Reuse it on re-runs.
    if ($ProjectId -or $SkipProvision) { return }
    $first = '01-langgraph-deepagents'
    $existing = @(azd env list -o json -C (Join-Path $root $first) --no-prompt 2>$null |
        ConvertFrom-Json | Where-Object { $_.Name -eq $ProjectName })
    if ($existing.Count -gt 0) {
        Invoke-Azd $first @('env', 'select', $ProjectName)
    }
    else {
        Invoke-Azd $first @('env', 'new', $ProjectName)
    }
}

function Get-DeclaredModel {
    # Deployment names from the ai-project block of 01's azure.yaml.
    $yaml = Get-Content -Raw (
        Join-Path $root '01-langgraph-deepagents\azure.yaml'
    )
    $block = [regex]::Match(
        $yaml, '(?ms)^\s+deployments:\s*$(.*?)^\s{4}\S'
    ).Groups[1].Value
    [regex]::Matches($block, '(?m)^\s{14}name:\s*(\S+)') |
        ForEach-Object { $_.Groups[1].Value }
}

function Invoke-PromptDeploy([string] $ModelName) {
    # A prompt agent names its model in azure.yaml, and azd does not expand
    # env vars there, so swap the value for this deploy and restore it.
    $yamlPath = Join-Path $root "$prompt\azure.yaml"
    $original = Get-Content $yamlPath -Raw
    $swapped = $original -replace '(?m)^(        model:) \S+',
        "`${1} $ModelName"
    try {
        Set-Content $yamlPath $swapped -NoNewline -Encoding utf8NoBOM
        Invoke-Azd $prompt @('deploy')
    }
    finally {
        Set-Content $yamlPath $original -NoNewline -Encoding utf8NoBOM
    }
}

function Get-AzdValue([string] $Folder, [string] $Name) {
    $value = azd env get-value $Name -C (Join-Path $root $Folder) 2>$null
    if ($LASTEXITCODE -eq 0 -and $value) { "$value".Trim() }
}

function Assert-AzContext {
    # Default to what 01's azd environment already targets, so later runs
    # cannot drift to another subscription.
    $first = '01-langgraph-deepagents'
    if (-not $Subscription) {
        $script:Subscription = Get-AzdValue $first 'AZURE_SUBSCRIPTION_ID'
    }
    if (-not $TenantId) {
        $script:TenantId = Get-AzdValue $first 'AZURE_TENANT_ID'
    }

    $query = '{id:id,tenant:tenantId,user:user.name}'
    $active = az account show --query $query -o json | ConvertFrom-Json
    if (-not $active) { throw 'Not signed in. Run: az login' }
    if ($Subscription -and $active.id -ne $Subscription) {
        az account set --subscription $Subscription 2>$null
        $active = az account show --query $query -o json | ConvertFrom-Json
    }
    if (-not $Subscription) { $script:Subscription = $active.id }
    if (-not $TenantId) { $script:TenantId = $active.tenant }
    if ($active.id -ne $Subscription -or $active.tenant -ne $TenantId) {
        throw (
            "Azure CLI is on $($active.id) ($($active.user)), expected " +
            "$Subscription in tenant $TenantId. Run: az login --tenant " +
            "$TenantId; az account set --subscription $Subscription"
        )
    }
    Write-Host "Deploying as $($active.user) to $Subscription" `
        -ForegroundColor Green
}

$declared = @(Get-DeclaredModel)
foreach ($m in $Model) {
    if ($m -notin $declared) {
        throw "Unknown model '$m'. Declared: $($declared -join ', ')"
    }
}

Assert-AzContext
& (Join-Path $PSScriptRoot 'sync-shared.ps1')
Initialize-ProjectEnv

foreach ($folder in $Agent) {
    Invoke-Azd $folder @('env', 'set', 'AZURE_SUBSCRIPTION_ID', $Subscription)
    Invoke-Azd $folder @('env', 'set', 'AZURE_TENANT_ID', $TenantId)
    Invoke-Azd $folder @('env', 'set', 'AZURE_LOCATION', $Location)
}

$sharedId = $ProjectId
$firstPass = -not $SkipProvision
foreach ($m in $Model) {
    Write-Host "Model: $m" -ForegroundColor Green
    foreach ($folder in $Agent) {
        Invoke-Azd $folder @(
            'env', 'set', 'AZURE_AI_MODEL_DEPLOYMENT_NAME', $m
        )
        if ($folder -eq $prompt) {
            if ($firstPass -and $sharedId) {
                Add-SharedProject $folder $sharedId
            }
            Invoke-PromptDeploy $m
            continue
        }
        if (-not $firstPass) {
            # Project and model deployments exist; only a new agent version.
            Invoke-Azd $folder @('deploy')
            continue
        }

        if ($sharedId) {
            Add-SharedProject $folder $sharedId
        }

        Invoke-Azd $folder @('up')

        if (-not $sharedId -and -not $WhatIfPreference) {
            $sharedId = Get-ProjectId $folder
            Write-Host "Shared project: $sharedId" -ForegroundColor Green
        }
    }
    $firstPass = $false
}

foreach ($folder in $Agent) {
    Invoke-Azd $folder @('ai', 'agent', 'show')
}

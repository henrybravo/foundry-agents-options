# Connects Application Insights to the shared Foundry project so hosted
# agent traces appear under Agents > Traces. Idempotent; safe to re-run.
# Run after deploy.ps1: pwsh scripts\enable-tracing.ps1
[CmdletBinding()]
param(
    [string] $ConnectionName = 'appinsights-tracing'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$arm = 'https://management.azure.com'

function Invoke-Az([string[]] $Arguments) {
    $out = & az @Arguments --only-show-errors
    if ($LASTEXITCODE -ne 0) {
        throw "az $($Arguments[0..1] -join ' ') failed"
    }
    $out
}

# az is a .cmd wrapper on Windows, so JSON bodies go through a file.
function Invoke-ArmPut([string] $Url, [hashtable] $Body, [string] $Query) {
    $file = New-TemporaryFile
    try {
        $Body | ConvertTo-Json -Compress -Depth 5 |
            Set-Content $file -Encoding utf8NoBOM
        Invoke-Az @(
            'rest', '--method', 'put', '--url', $Url,
            '--body', "@$file", '--query', $Query, '-o', 'tsv'
        )
    }
    finally { Remove-Item $file -ErrorAction SilentlyContinue }
}

$first = Join-Path $root '01-langgraph-deepagents'
$projectId = (azd env get-value AZURE_AI_PROJECT_ID -C $first).Trim()
$location = (azd env get-value AZURE_LOCATION -C $first).Trim()
if (-not $projectId) { throw 'Deploy first: no AZURE_AI_PROJECT_ID in 01.' }
$Subscription = ($projectId -split '/')[2]

$active = Invoke-Az @('account', 'show', '--query', 'id', '-o', 'tsv')
if ($active -ne $Subscription) {
    throw "Azure CLI is on $active, the project is in $Subscription. " +
        "Run: az account set --subscription $Subscription"
}
$group = ($projectId -split '/')[4]
$suffix = ($projectId -split '/')[8] -replace '^cog-', ''

$workspace = "log-trail-$suffix"
Write-Host "Log Analytics workspace $workspace" -ForegroundColor DarkGray
$workspaceId = Invoke-Az @(
    'monitor', 'log-analytics', 'workspace', 'create',
    '-g', $group, '-n', $workspace, '-l', $location,
    '--query', 'id', '-o', 'tsv'
)

$insights = "appi-trail-$suffix"
$insightsId = "/subscriptions/$Subscription/resourceGroups/$group" +
    "/providers/Microsoft.Insights/components/$insights"
Write-Host "Application Insights $insights" -ForegroundColor DarkGray
$connectionString = Invoke-ArmPut "$arm${insightsId}?api-version=2020-02-02" @{
    location   = $location
    kind       = 'web'
    properties = @{
        Application_Type    = 'web'
        WorkspaceResourceId = $workspaceId
    }
} 'properties.ConnectionString'

Write-Host "Project connection $ConnectionName" -ForegroundColor DarkGray
$url = "$arm$projectId/connections/${ConnectionName}?api-version=2025-06-01"
Invoke-ArmPut $url @{
    properties = @{
        category      = 'AppInsights'
        target        = $insightsId
        authType      = 'ApiKey'
        isSharedToAll = $false
        credentials   = @{ key = $connectionString }
        metadata      = @{ ApiType = 'Azure'; ResourceId = $insightsId }
    }
} 'name' | Out-Null

Write-Host "Tracing connected to $insights. Redeploy the agents" `
    '(pwsh scripts\deploy.ps1); traces then show in the portal within' `
    'a few minutes of each call.' -ForegroundColor Green

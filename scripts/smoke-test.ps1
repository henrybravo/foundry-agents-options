# Builds each agent offline (no model calls, no Azure access) to prove the
# code, dependencies, and shared skill wiring load. Uses a placeholder
# project endpoint. Run: pwsh scripts\smoke-test.ps1
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent

$env:FOUNDRY_PROJECT_ENDPOINT =
    'https://example.services.ai.azure.com/api/projects/demo'
$env:AZURE_AI_MODEL_DEPLOYMENT_NAME = 'gpt-5.4-mini'

$checks = [ordered]@{
    '01-langgraph-deepagents' = @'
from agent import build_agent
from utils import build_chat_model
graph = build_agent(build_chat_model())
print("nodes:", sorted(graph.get_graph().nodes))
'@
    '02-langgraph-workflow' = @'
from main import create_graph
graph = create_graph()
print("nodes:", list(graph.get_graph().nodes))
'@
    '03-maf-workflow' = @'
from main import build_agent
agent = build_agent()
print("agent:", type(agent).__name__, agent.name)
'@
    '04-maf-harness' = @'
from azure.identity import DefaultAzureCredential
from main import build_agent
agent = build_agent(DefaultAzureCredential())
print("agent:", type(agent).__name__, agent.name)
print("providers:", [type(p).__name__ for p in agent.context_providers])
'@
}

$failed = @()
foreach ($name in $checks.Keys) {
    $src = Get-ChildItem (Join-Path $root "$name\src") -Directory |
        Select-Object -First 1
    Push-Location $src.FullName
    try {
        Write-Host "==> $name"
        $checks[$name] | & .venv\Scripts\python.exe -
        if ($LASTEXITCODE -ne 0) { $failed += $name }
    }
    finally {
        Pop-Location
    }
}

if ($failed) { throw "Smoke test failed: $($failed -join ', ')" }
Write-Host 'All four agents build.'

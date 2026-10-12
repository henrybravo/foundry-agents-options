# Runs the shared trail-review eval suite (evals\eval.yaml) against each demo agent
# with the beta 'azd ai agent eval' commands, one eval run per agent.
# -Generate first rebuilds the suite with 'azd ai agent eval generate':
# a synthetic dataset plus a rubric evaluator, generated from
# evals\agent-instruction.md (takes about 10-15 minutes).
# -Rubric uses evals\eval-rubric.yaml (built-ins plus the generated rubric
# evaluator); the rubric must be registered in the project first
# ('azd ai agent eval update --evaluator-only').
# Each run gets a temp copy of the config, because 'eval run' writes the
# agent name and version back into the file it reads.
# Run: pwsh scripts\eval.ps1
#      pwsh scripts\eval.ps1 -Agent 00-prompt-agent,04-maf-harness -NoWait
#      pwsh scripts\eval.ps1 -Generate
[CmdletBinding()]
param(
    [string[]] $Agent = @(
        '00-prompt-agent',
        '01-langgraph-deepagents',
        '02-langgraph-workflow',
        '03-maf-workflow',
        '04-maf-harness'
    ),
    [string] $EvalModel = 'gpt-5.4-mini',
    [switch] $Generate,
    [switch] $Rubric,
    [switch] $NoWait
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$evals = Join-Path $root 'evals'
$Agent = @($Agent | ForEach-Object { $_ -split ',' } | Where-Object { $_ })
$services = @{
    '00-prompt-agent'         = 'trail-prompt-agent'
    '01-langgraph-deepagents' = 'trail-deepagents'
    '02-langgraph-workflow'   = 'trail-langgraph-workflow'
    '03-maf-workflow'         = 'trail-maf-workflow'
    '04-maf-harness'          = 'trail-maf-harness'
}

if ($Generate) {
    # Generates into evals\: trail-generated.jsonl is replaced by the new
    # dataset and eval-rubric.yaml by the new suite definition.
    $cwd = Join-Path $root '00-prompt-agent'
    $out = Join-Path $evals 'eval-rubric.yaml'
    & azd ai agent eval generate -C $cwd --no-prompt `
        --agent trail-prompt-agent `
        --gen-instruction-file (Join-Path $evals 'agent-instruction.md') `
        --evaluator builtin.task_adherence `
        --evaluator builtin.intent_resolution `
        --eval-model $EvalModel --name trail-review `
        --out-file $out --reset-defaults
    if ($LASTEXITCODE -ne 0) { throw 'eval generate failed' }
}

$config = if ($Rubric) { 'eval-rubric.yaml' } else { 'eval.yaml' }
$template = Get-Content (Join-Path $evals $config) -Raw
# Rewrite relative local_uri values to absolute paths so the temp copy
# works from every agent folder.
$template = [regex]::Replace($template, '(?m)(local_uri:\s*)(\S+)', {
    param($m)
    $rel = $m.Groups[2].Value -replace '^\.\.[\\/]evals[\\/]', ''
    if ([IO.Path]::IsPathRooted($rel)) { return $m.Value }
    $m.Groups[1].Value + (Join-Path $evals $rel)
})

foreach ($folder in $Agent) {
    $svc = $services[$folder]
    if (-not $svc) { throw "Unknown agent folder: $folder" }
    $tmp = Join-Path $env:TEMP "trail-eval-$svc.yaml"
    $cfg = $template -replace '(?m)^(    name:\s*)trail-[\w-]+', "`${1}$svc"
    $cfg = $cfg -replace '(?m)^    version:\s*"\d+"\r?\n', ''
    Set-Content $tmp $cfg -NoNewline
    Write-Host "`n=== eval $svc ($folder)" -ForegroundColor Cyan
    $cmd = @('ai', 'agent', 'eval', 'run', '--agent', $svc,
        '--config', $tmp, '--name', "trail-review-$svc",
        '-C', (Join-Path $root $folder), '--no-prompt')
    if ($NoWait) { $cmd += '--no-wait' }
    & azd @cmd
    if ($LASTEXITCODE -ne 0) { Write-Warning "eval run failed for $svc" }
}

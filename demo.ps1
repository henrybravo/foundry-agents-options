# Sends the same group hike proposal to each Trail review demo agent and prints
# the reviews side by side. Only the agent name changes between calls.
# -Model calls the newest agent version pinned to that model deployment
# (deploy one version per model with scripts\deploy.ps1 -Model a,b,c).
# Run: pwsh .\demo.ps1            (hosted agents on Foundry)
#      pwsh .\demo.ps1 -Model gpt-6-sol
#      pwsh .\demo.ps1 -Local -Agent 01-langgraph-deepagents
#        (agent started first with: azd ai agent run -C <folder>)
# Each agent's stdout is also saved to demo-results\<time>-<agent>-<model>.md
# (override the folder with -OutDir).
[CmdletBinding(PositionalBinding = $false)]
param(
    # Folder names; a comma list also works via pwsh -File.
    [string[]] $Agent = @(
        '00-prompt-agent',
        '01-langgraph-deepagents',
        '02-langgraph-workflow',
        '03-maf-workflow',
        '04-maf-harness'
    ),
    [string] $Proposal = (
        Join-Path $PSScriptRoot 'shared\sample\trail-plan.md'
    ),
    # Model deployment name; omit to call each agent's latest version.
    [string] $Model,
    [switch] $Local,
    # Each run writes <yyyyMMdd-HHmmss>-<agent>-<model>.md here.
    [string] $OutDir = (Join-Path $PSScriptRoot 'demo-results'),
    # Catches "-Agent a, b" from pwsh -File, which arrives as "a," and "b".
    [Parameter(ValueFromRemainingArguments)]
    [string[]] $MoreAgent = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$names = @{
    '00-prompt-agent'         = 'trail-prompt-agent'
    '01-langgraph-deepagents' = 'trail-deepagents'
    '02-langgraph-workflow'   = 'trail-langgraph-workflow'
    '03-maf-workflow'         = 'trail-maf-workflow'
    '04-maf-harness'          = 'trail-maf-harness'
}

$Agent = @(@($Agent) + @($MoreAgent) | ForEach-Object { $_ -split ',' } |
    ForEach-Object { $_.Trim() } | Where-Object { $_ })
foreach ($folder in $Agent) {
    if (-not $names.ContainsKey($folder)) {
        throw "Unknown agent '$folder'. Use: $($names.Keys -join ', ')"
    }
}
if ($Local -and $Model) {
    throw ('-Model selects a hosted agent version; a local agent uses ' +
        'the model in its azd env (AZURE_AI_MODEL_DEPLOYMENT_NAME).')
}

function Get-AgentVersion([string] $Folder, [string] $Name) {
    # Returns the newest version (optionally pinned to $Model) and its model.
    $endpoint = azd env get-value FOUNDRY_PROJECT_ENDPOINT `
        -C (Join-Path $PSScriptRoot $Folder)
    if ($LASTEXITCODE -ne 0 -or -not $endpoint) {
        throw "No FOUNDRY_PROJECT_ENDPOINT in $Folder; deploy it first."
    }
    $url = "$($endpoint.Trim())/agents/$Name/versions"
    # az is a .cmd wrapper, so query parameters cannot contain '&'.
    $json = az rest --method get --url $url --resource https://ai.azure.com `
        --uri-parameters api-version=v1 limit=100
    if ($LASTEXITCODE -ne 0) { throw "Cannot list versions of $Name" }

    $versions = ($json | ConvertFrom-Json).data | ForEach-Object {
        $vars = $_.definition.PSObject.Properties['environment_variables']
        [pscustomobject]@{
            Version = [int] $_.version
            # Hosted agents get it as an env var; prompt agents name it.
            Model   = if ($vars) {
                $vars.Value.AZURE_AI_MODEL_DEPLOYMENT_NAME
            }
            else { $_.definition.model }
        }
    }
    if ($Model) { $versions = $versions | Where-Object Model -EQ $Model }
    $versions | Sort-Object Version -Descending | Select-Object -First 1
}

$message = "Review this group hike proposal.`n`n" +
    (Get-Content $Proposal -Raw)
# azd drops everything after the first newline of a positional message when
# it forwards it to the agents extension, so send a Responses body file.
$bodyFile = Join-Path ([IO.Path]::GetTempPath()) 'trail-demo-body.json'
@{ input = $message } | ConvertTo-Json |
    Set-Content $bodyFile -Encoding utf8NoBOM

foreach ($folder in $Agent) {
    $name = $names[$folder]
    if ($Local -and $folder -eq '00-prompt-agent') {
        Write-Warning 'A prompt agent has no code to run locally; skipped.'
        continue
    }
    $invokeArgs = @(
        'ai', 'agent', 'invoke', $name, '--input-file', $bodyFile,
        '-C', (Join-Path $PSScriptRoot $folder),
        '--new-session'
    )
    if ($Local) { $invokeArgs += '--local' }

    Write-Host ''
    Write-Host "=== $name ($folder)" -ForegroundColor Cyan
    $suffix = if ($Local) { ' --local' } else { '' }
    if (-not $Local) {
        $picked = Get-AgentVersion $folder $name
        if (-not $picked) {
            Write-Warning (
                "No version of $name uses '$Model'. Deploy one with: " +
                "pwsh scripts\deploy.ps1 -Agent $folder -Model $Model"
            )
            continue
        }
        Write-Host "Version $($picked.Version), model $($picked.Model)" `
            -ForegroundColor Cyan
        if ($Model) {
            # azd derives the protocol only for the latest version; all four
            # agents speak Responses.
            $invokeArgs += @(
                '--version', "$($picked.Version)", '--protocol', 'responses'
            )
            $suffix = " --version $($picked.Version)"
        }
    }
    Write-Host "azd ai agent invoke $name --input-file <proposal>$suffix" `
        -ForegroundColor DarkGray
    $started = Get-Date
    $timer = [Diagnostics.Stopwatch]::StartNew()
    & azd @invokeArgs | Tee-Object -Variable captured
    $exitCode = $LASTEXITCODE
    $timer.Stop()
    $summary = '--- {0:n1}s, exit {1}' -f $timer.Elapsed.TotalSeconds,
        $exitCode
    Write-Host $summary -ForegroundColor DarkGray

    if ($Local) {
        $modelUsed = azd env get-value AZURE_AI_MODEL_DEPLOYMENT_NAME `
            -C (Join-Path $PSScriptRoot $folder) 2>$null
        if ($LASTEXITCODE -ne 0 -or -not $modelUsed) { $modelUsed = 'local' }
        $versionUsed = 'local'
    }
    else {
        $modelUsed = $picked.Model
        $versionUsed = $picked.Version
    }
    if (-not $modelUsed) { $modelUsed = 'unknown' }

    New-Item -ItemType Directory -Force $OutDir | Out-Null
    $stamp = $started.ToString('yyyyMMdd-HHmmss')
    $fileName = "$stamp-$name-$modelUsed.md" -replace '[\\/:*?"<>|\s]', '_'
    $ansi = [char] 27 + '\[[0-9;?]*[A-Za-z]'
    $body = ($captured | ForEach-Object { "$_" } |
        ForEach-Object { $_ -replace $ansi, '' }) -join "`n"
    # Drop azd's trailing "Next:" hint; it is console advice, not output.
    $body = ($body -replace '(?s)\r?\n\s*Next:\s*\r?\n.*$', '').TrimEnd()
    $lines = @($body -split "`n")
    $first = 0..($lines.Count - 1) |
        Where-Object { $lines[$_] -match '^\[[^\]]+\] ' } |
        Select-Object -First 1
    $last = 0..($lines.Count - 1) |
        Where-Object { $lines[$_] -match '^Client elapsed' } |
        Select-Object -First 1
    $fence = '```'
    $parts = @(
        "# $name ($modelUsed)"
        ''
        "- Agent: $name ($folder)"
        "- Model: $modelUsed"
        "- Version: $versionUsed"
        "- Started: $($started.ToString('yyyy-MM-dd HH:mm:ss'))"
        ('- Elapsed: {0:n1}s, exit {1}' -f $timer.Elapsed.TotalSeconds,
            $exitCode)
        ''
    )
    if ($null -ne $first -and $null -ne $last -and $first -lt $last) {
        # Render the agent reply as markdown; keep azd plumbing in fences.
        $reply = $lines[$first..($last - 1)]
        $reply[0] = $reply[0] -replace '^\[[^\]]+\] ', ''
        $reply = $reply -join "`n"
        $head = $lines[0..($first - 1)] -join "`n"
        $tail = $lines[$last..($lines.Count - 1)] -join "`n"
        $parts += @(
            '## Invocation', '', "${fence}text"
            $head
            $fence, ''
            $reply, ''
            '## Timing', '', "${fence}text"
            $tail
            $fence, ''
        )
    } else {
        $parts += @('## Output', '', "${fence}text", ($lines -join "`n"), $fence, '')
    }
    $report = $parts -join "`n"
    $reportPath = Join-Path $OutDir $fileName
    Set-Content $reportPath -Value $report -Encoding utf8NoBOM
    Write-Host "Saved $reportPath" -ForegroundColor DarkGray
}



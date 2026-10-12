# Copies the canonical shared\skills tree and shared\toolbox_skills.py into
# every hosted agent's source folder so each code-deploy package ships the
# same SKILL.md and toolbox loader. 04 loads toolbox skills natively and
# gets only the skills; folders without src (the prompt agent) are skipped.
# -Check verifies the copies match without writing.
# Run: pwsh scripts\sync-shared.ps1 [-Check]
[CmdletBinding()]
param([switch] $Check)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$source = Join-Path $root 'shared\skills'
$loader = Join-Path $root 'shared\toolbox_skills.py'
$nativeToolbox = @('04-maf-harness')

function Get-TreeHash([string] $Path) {
    Get-ChildItem $Path -Recurse -File | Sort-Object FullName | ForEach-Object {
        $rel = $_.FullName.Substring($Path.Length).TrimStart('\')
        $rel + ':' + (Get-FileHash $_.FullName -Algorithm SHA256).Hash
    }
}

$expected = (Get-TreeHash $source) -join "`n"
$drift = @()
foreach ($agent in Get-ChildItem $root -Directory -Filter '0*') {
    $srcRoot = Join-Path $agent.FullName 'src'
    if (-not (Test-Path $srcRoot)) { continue }
    $src = Get-ChildItem $srcRoot -Directory | Select-Object -First 1
    $target = Join-Path $src.FullName 'skills'
    $loaderTarget = Join-Path $src.FullName 'toolbox_skills.py'
    $wantLoader = $agent.Name -notin $nativeToolbox
    if ($Check) {
        $actual = if (Test-Path $target) {
            (Get-TreeHash $target) -join "`n"
        }
        if ($actual -ne $expected) { $drift += $agent.Name }
        if ($wantLoader -and (-not (Test-Path $loaderTarget) -or
                (Get-FileHash $loaderTarget).Hash -ne
                (Get-FileHash $loader).Hash)) {
            $drift += "$($agent.Name) (toolbox_skills.py)"
        }
        continue
    }
    if ($wantLoader) { Copy-Item $loader $loaderTarget -Force }
    if (Test-Path $target) { Remove-Item $target -Recurse -Force }
    New-Item -ItemType Directory $target -Force | Out-Null
    Copy-Item (Join-Path $source '*') $target -Recurse -Force
    Write-Host "Synced skills -> $($agent.Name)"
}

function Get-PromptInstructionsYaml([string] $Yaml) {
    # A prompt agent has no code package, so its azure.yaml carries the
    # skill and its reference files inline in the instructions.
    $skillDir = Join-Path $source 'trail-review'
    $skill = Get-Content (Join-Path $skillDir 'SKILL.md') -Raw
    $body = ($skill -replace '(?s)^---.*?\r?\n---\r?\n', '').Trim()
    $parts = @(
        ('You review group hike proposals. Follow the trail-review ' +
        'skill below for every review request. Its reference files ' +
        'follow the skill. Follow its steps and its output format ' +
        'exactly. Return only the review result.'),
        "# Skill: trail-review`n`n$body"
    )
    $refs = Get-ChildItem (Join-Path $skillDir 'references') -File |
        Sort-Object Name
    foreach ($ref in $refs) {
        $parts += "# File: references/$($ref.Name)`n`n" +
            (Get-Content $ref.FullName -Raw).Trim()
    }
    $lines = (($parts -join "`n`n") -replace "`r`n", "`n") -split "`n"
    $indented = $lines | ForEach-Object {
        if ($_) { (' ' * 12) + $_ } else { '' }
    }
    $block = "        instructions: |-`n" + ($indented -join "`n") + "`n"
    $pattern = '(?ms)^        instructions:.*?\n(?=[ ]{0,8}\S)'
    [regex]::Replace(($Yaml -replace "`r`n", "`n"), $pattern,
        { param($m) $block })
}

$promptYaml = Join-Path $root '00-prompt-agent\azure.yaml'
if (Test-Path $promptYaml) {
    $current = (Get-Content $promptYaml -Raw) -replace "`r`n", "`n"
    $wanted = Get-PromptInstructionsYaml $current
    if ($Check) {
        if ($current -ne $wanted) { $drift += '00-prompt-agent (azure.yaml)' }
    }
    else {
        Set-Content $promptYaml $wanted -NoNewline -Encoding utf8NoBOM
        Write-Host 'Synced skills -> 00-prompt-agent (instructions)'
    }
}

if ($Check) {
    if ($drift) {
        throw "Skill copies differ from shared: $($drift -join ', ')"
    }
    Write-Host 'All agent skill copies match shared\skills.'
}

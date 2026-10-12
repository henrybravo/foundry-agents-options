# Parses every Mermaid block in a Markdown file with mermaid + jsdom in WSL.
# Run: pwsh scripts\validate-mermaid.ps1 [-Path docs\demo-walkthrough.md]
[CmdletBinding()]
param(
    [string]$Path = (Join-Path $PSScriptRoot '..\docs\demo-walkthrough.md'),
    [string]$OutDir = (Join-Path $env:TEMP 'trail-mermaid-check')
)
$ErrorActionPreference = 'Stop'

$text = Get-Content -Raw -LiteralPath $Path
$blocks = [regex]::Matches($text, '(?s)```mermaid\r?\n(.*?)```')
if ($blocks.Count -eq 0) { throw "No mermaid blocks in $Path" }

New-Item -ItemType Directory -Force $OutDir | Out-Null
Get-ChildItem $OutDir -Filter 'diagram-*.mmd' | Remove-Item
$i = 0
foreach ($b in $blocks) {
    $i++
    $file = Join-Path $OutDir "diagram-$i.mmd"
    Set-Content -LiteralPath $file -Value $b.Groups[1].Value -NoNewline
}

# Windows npm fails on TLS here and WSL lacks Chromium libraries, so the
# check parses with mermaid under jsdom. Parsing catches syntax errors;
# it does not check layout.
$js = @'
const fs = require("fs");
const { JSDOM } = require("jsdom");
const dom = new JSDOM("<!doctype html><body></body>");
global.window = dom.window;
global.document = dom.window.document;
global.DOMParser = dom.window.DOMParser;
(async () => {
  const mermaid = (await import("mermaid")).default;
  mermaid.initialize({ startOnLoad: false });
  let fail = 0;
  const files = fs.readdirSync(process.argv[2])
    .filter((f) => /^diagram-\d+\.mmd$/.test(f)).sort();
  for (const f of files) {
    const src = fs.readFileSync(`${process.argv[2]}/${f}`, "utf8");
    try {
      await mermaid.parse(src);
      console.log(`OK   ${f}`);
    } catch (e) {
      fail = 1;
      console.log(`FAIL ${f}\n${e.message}`);
    }
  }
  process.exit(fail);
})();
'@
Set-Content -LiteralPath (Join-Path $OutDir 'check.cjs') `
    -Value ($js -replace "`r`n", "`n") -NoNewline
$wslDir = (wsl wslpath -a ($OutDir -replace '\\', '/')).Trim()
$sh = 'd=~/.cache/trail-mermaid; mkdir -p $d && cd $d && ' +
    '([ -d node_modules/mermaid ] || (npm init -y >/dev/null && ' +
    'npm i --silent mermaid jsdom)) && ' +
    "cp '$wslDir/check.cjs' `$d/check.cjs && node `$d/check.cjs '$wslDir'"
Set-Content -LiteralPath (Join-Path $OutDir 'check.sh') -Value $sh -NoNewline
wsl bash "$wslDir/check.sh"
if ($LASTEXITCODE -ne 0) { throw "Mermaid validation failed" }
Write-Host "All $($blocks.Count) diagrams parsed"

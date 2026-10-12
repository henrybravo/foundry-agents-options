# Installs each agent's locked Python dependencies into its Windows .venv by
# downloading Windows wheels through WSL. Use when the Windows TLS stack
# cannot reach files.pythonhosted.org.
# Run: pwsh scripts\install-deps-via-wsl.ps1
[CmdletBinding()]
param(
    [string[]] $Agent = @(
        '01-langgraph-deepagents',
        '02-langgraph-workflow',
        '03-maf-workflow',
        '04-maf-harness'
    ),
    [string] $Distro = 'Ubuntu-24.04'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent

function ConvertTo-WslPath([string] $Path) {
    $full = [IO.Path]::GetFullPath($Path)
    $drive = $full.Substring(0, 1).ToLower()
    '/mnt/' + $drive + ($full.Substring(2) -replace '\\', '/')
}

$uv = '/tmp/uvenv/bin/uv'
$bootstrap = "test -x $uv || " +
    "(python3 -m venv /tmp/uvenv && /tmp/uvenv/bin/pip install -q uv)"
wsl -d $Distro -- bash -lc $bootstrap

foreach ($name in $Agent) {
    $src = Get-ChildItem (Join-Path $root "$name\src") -Directory |
        Select-Object -First 1
    Push-Location $src.FullName
    try {
        if (-not (Test-Path .venv)) { uv venv --python 3.13 -q .venv }
        $req = Join-Path $src.FullName 'requirements.txt'
        if (-not (Test-Path $req)) {
            $req = Join-Path $env:TEMP "$name-requirements.txt"
            uv export --frozen --no-hashes --no-emit-project -q -o $req
        }
        $site = Join-Path $src.FullName '.venv\Lib\site-packages'
        $cmd = "$uv pip install -q --python-platform x86_64-pc-windows-msvc " +
            "--python-version 3.13 --target '$(ConvertTo-WslPath $site)' " +
            "-r '$(ConvertTo-WslPath $req)'"
        Write-Host "==> $name"
        wsl -d $Distro -- bash -lc $cmd
        if ($LASTEXITCODE -ne 0) { throw "Dependency install failed: $name" }
    }
    finally {
        Pop-Location
    }
}

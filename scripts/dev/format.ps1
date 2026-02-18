$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "../..")
Set-Location $repoRoot

$targets = @("scripts", "scenes")
$venvGdformat = Join-Path $repoRoot ".venv/Scripts/gdformat.exe"

if (Test-Path $venvGdformat) {
    & $venvGdformat @targets
    exit $LASTEXITCODE
}

$gdformatCmd = Get-Command gdformat -ErrorAction SilentlyContinue
if ($gdformatCmd) {
    & $gdformatCmd.Source @targets
    exit $LASTEXITCODE
}

Write-Error "gdformat not found. Install with 'python -m pip install -r requirements-dev.txt' (venv) or 'pipx install gdtoolkit'."
exit 1

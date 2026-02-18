$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "../..")
Set-Location $repoRoot

$targets = @("scripts", "scenes")
$venvGdlint = Join-Path $repoRoot ".venv/Scripts/gdlint.exe"

if (Test-Path $venvGdlint) {
    & $venvGdlint @targets
    exit $LASTEXITCODE
}

$gdlintCmd = Get-Command gdlint -ErrorAction SilentlyContinue
if ($gdlintCmd) {
    & $gdlintCmd.Source @targets
    exit $LASTEXITCODE
}

Write-Error "gdlint not found. Install with 'python -m pip install -r requirements-dev.txt' (venv) or 'pipx install gdtoolkit'."
exit 1

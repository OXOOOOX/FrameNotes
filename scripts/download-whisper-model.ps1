param(
    [ValidateSet("tiny", "base", "small", "medium", "large-v3")]
    [string]$Model = "medium"
)

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$venvPython = Join-Path $repoRoot ".venv\Scripts\python.exe"

if (-not (Test-Path $venvPython)) {
    throw "Project Python environment not found. Run: python -m venv .venv"
}

& $venvPython (Join-Path $PSScriptRoot "download-whisper-model.py") `
    --model $Model `
    --output-root (Join-Path $repoRoot ".models")

exit $LASTEXITCODE

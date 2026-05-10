param(
    [Parameter(Mandatory = $true)]
    [string]$FramesJson,

    [int]$MaxFrames = 24
)

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$venvPython = Join-Path $repoRoot ".venv\Scripts\python.exe"

if (-not (Test-Path $venvPython)) {
    throw "Project Python environment not found. Run: python -m venv .venv"
}

& $venvPython (Join-Path $PSScriptRoot "build-multimodal-package.py") `
    $FramesJson `
    --max-frames $MaxFrames

exit $LASTEXITCODE

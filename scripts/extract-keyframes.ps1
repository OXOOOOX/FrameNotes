param(
    [Parameter(Mandatory = $true)]
    [string]$Video,

    [string]$OutputRoot = "analysis",

    [double]$SceneThreshold = 0.18,

    [int]$FallbackInterval = 20
)

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$venvPython = Join-Path $repoRoot ".venv\Scripts\python.exe"

if (-not (Test-Path $venvPython)) {
    throw "Project Python environment not found. Run: python -m venv .venv"
}

& $venvPython (Join-Path $PSScriptRoot "extract-keyframes.py") `
    $Video `
    --output-root (Join-Path $repoRoot $OutputRoot) `
    --scene-threshold $SceneThreshold `
    --fallback-interval $FallbackInterval

exit $LASTEXITCODE

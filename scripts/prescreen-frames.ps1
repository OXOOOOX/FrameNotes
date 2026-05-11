param(
    [Parameter(Mandatory=$true)]
    [string]$FrameReviewJson,

    [string]$Transcript,

    [int]$Window = 3
)

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$venvPython = Join-Path $repoRoot ".venv\Scripts\python.exe"

if (-not (Test-Path $venvPython)) {
    throw "Project Python environment not found. Run: python -m venv .venv"
}

$args = @(
    (Join-Path $PSScriptRoot "prescreen-frames.py"),
    (Resolve-Path -LiteralPath $FrameReviewJson).Path,
    "--window", $Window
)

if ($Transcript) {
    $args += @("--transcript", (Resolve-Path -LiteralPath $Transcript).Path)
}

& $venvPython @args
exit $LASTEXITCODE

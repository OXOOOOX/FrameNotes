param(
    [Parameter(Mandatory = $true)]
    [string]$SelectedFramesJson,

    [switch]$ExtractDense,

    [double]$Window = 4,

    [double]$Fps = 1
)

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$venvPython = Join-Path $repoRoot ".venv\Scripts\python.exe"
$selectedPath = Resolve-Path -LiteralPath $SelectedFramesJson

if (-not (Test-Path $venvPython)) {
    throw "Project Python environment not found. Run: python -m venv .venv"
}

$args = @(
    (Join-Path $PSScriptRoot "refine-frames.py"),
    $selectedPath.Path,
    "--window", $Window,
    "--fps", $Fps
)

if ($ExtractDense) {
    $args += "--extract-dense"
}

& $venvPython @args
exit $LASTEXITCODE

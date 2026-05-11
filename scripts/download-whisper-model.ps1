param(
    [ValidateSet("tiny", "base", "small", "medium", "large-v3")]
    [string]$Model = "medium",

    [switch]$AutoDownload
)

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$venvPython = Join-Path $repoRoot ".venv\Scripts\python.exe"

$modelsDir = Join-Path $HOME ".cache\framenotes\models"
$targetDir = Join-Path $modelsDir "faster-whisper-$Model"
$modelBin = Join-Path $targetDir "model.bin"

if (Test-Path $modelBin) {
    Write-Host "Model already cached: $targetDir"
    exit 0
}

if (-not (Test-Path $venvPython)) {
    throw "Project Python environment not found. Run: python -m venv .venv"
}

if ($AutoDownload) {
    Write-Host "Auto-downloading faster-whisper model '$Model' from HuggingFace..."
} else {
    Write-Host ""
    Write-Host "=============================================="
    Write-Host "  Faster-Whisper model '$Model' not found."
    Write-Host ""
    Write-Host "  [A] Auto-download from HuggingFace (may be slow in China)"
    Write-Host "  [M] Manual download from mirror (recommended in China)"
    Write-Host ""
    Write-Host "  Manual steps:"
    Write-Host "    1. Visit: https://hf-mirror.com/Systran/faster-whisper-$Model"
    Write-Host "    2. Download all files"
    Write-Host "    3. Place them in:"
    Write-Host "       $targetDir"
    Write-Host ""
    $choice = Read-Host "  Choose [A/M]"
    Write-Host "=============================================="
    Write-Host ""

    if ($choice -ne "A" -and $choice -ne "a") {
        Write-Host "Manual download selected. After placing files in:"
        Write-Host "  $targetDir"
        Write-Host "re-run this script or the pipeline."
        exit 0
    }
}

& $venvPython (Join-Path $PSScriptRoot "download-whisper-model.py") `
    --model $Model `
    --output-root $modelsDir

exit $LASTEXITCODE

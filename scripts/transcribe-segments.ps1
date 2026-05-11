param(
    [Parameter(Mandatory = $true)]
    [string]$Audio,

    [Parameter(Mandatory = $true)]
    [string[]]$Range,

    [double]$Padding = 8,

    [string]$Model = "medium",

    [ValidateSet("auto", "zh", "en", "hi", "ja", "ko", "fr", "de", "es")]
    [string]$Language = "auto",

    [ValidateSet("auto", "cpu", "cuda")]
    [string]$Device = "auto"
)

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$venvPython = Join-Path $repoRoot ".venv\Scripts\python.exe"
$audioPath = Resolve-Path -LiteralPath $Audio
$modelArg = $Model
$modelsDir = Join-Path $HOME ".cache\framenotes\models"
$localModelPath = Join-Path $modelsDir "faster-whisper-$Model"

if (-not (Test-Path $venvPython)) {
    throw "Project Python environment not found. Run: python -m venv .venv"
}

if (Test-Path (Join-Path $localModelPath "model.bin")) {
    $modelArg = $localModelPath
} else {
    Write-Host ""
    Write-Host "=============================================="
    Write-Host "  Faster-Whisper model '$Model' not found at:"
    Write-Host "    $localModelPath"
    Write-Host ""
    Write-Host "  Manual download (recommended in China):"
    Write-Host "    https://hf-mirror.com/Systran/faster-whisper-$Model"
    Write-Host "    Place all files in the directory shown above."
    Write-Host "=============================================="
    Write-Host ""
}

$deviceArg = $Device
if ($Device -eq "auto") {
    $deviceInfoText = & $venvPython (Join-Path $PSScriptRoot "detect-asr-device.py")
    $deviceInfo = $deviceInfoText | ConvertFrom-Json
    $deviceArg = $deviceInfo.recommended_device
    Write-Host "ASR device: $deviceArg"
}

$args = @(
    (Join-Path $PSScriptRoot "transcribe-segments.py"),
    $audioPath.Path,
    "--padding", $Padding,
    "--model", $modelArg,
    "--language", $Language,
    "--device", $deviceArg
)

foreach ($item in $Range) {
    $args += @("--range", $item)
}

& $venvPython @args
exit $LASTEXITCODE

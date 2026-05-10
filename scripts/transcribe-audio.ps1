param(
    [Parameter(Mandatory = $true)]
    [string]$Audio,

    [string]$Model = "medium",

    [ValidateSet("auto", "zh", "en", "ja", "ko", "fr", "de", "es")]
    [string]$Language = "auto",

    [ValidateSet("auto", "cpu", "cuda")]
    [string]$Device = "auto"
)

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$venvPython = Join-Path $repoRoot ".venv\Scripts\python.exe"
$audioPath = Resolve-Path -LiteralPath $Audio
$modelArg = $Model
$localModelPath = Join-Path $repoRoot ".models\faster-whisper-$Model"

if (Test-Path (Join-Path $localModelPath "model.bin")) {
    $modelArg = $localModelPath
}

$deviceArg = $Device
if ($Device -eq "auto") {
    $deviceInfoText = & $venvPython (Join-Path $PSScriptRoot "detect-asr-device.py")
    $deviceInfo = $deviceInfoText | ConvertFrom-Json
    $deviceArg = $deviceInfo.recommended_device
    Write-Host "ASR device: $deviceArg"
}

if (-not (Test-Path $venvPython)) {
    throw "Project Python environment not found. Run: python -m venv .venv"
}

& $venvPython (Join-Path $PSScriptRoot "transcribe-audio.py") `
    $audioPath.Path `
    --model $modelArg `
    --language $Language `
    --device $deviceArg

exit $LASTEXITCODE

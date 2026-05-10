param(
    [ValidateSet("medium", "small", "large-v3")]
    [string]$Model = "medium"
)

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$venvPython = Join-Path $repoRoot ".venv\Scripts\python.exe"
$gpus = Get-CimInstance Win32_VideoController | Select-Object -ExpandProperty Name
$hasNvidia = ($gpus | Where-Object { $_ -match "NVIDIA" }) -ne $null

Write-Host "CUDA ASR setup"
Write-Host "Detected GPU(s): $($gpus -join '; ')"

if (-not $hasNvidia) {
    Write-Host "No NVIDIA GPU detected. CUDA setup is not recommended on this machine."
    Write-Host "Use CPU ASR instead:"
    Write-Host "  .\scripts\transcribe-audio.ps1 -Audio <audio.wav> -Model $Model -Language auto"
    exit 0
}

if (-not (Test-Path $venvPython)) {
    throw "Project Python environment not found. Run: python -m venv .venv"
}

Write-Host ""
Write-Host "NVIDIA GPU detected."
Write-Host "Recommendation: run the CPU pipeline first. CUDA setup downloads extra NVIDIA runtime packages and can take time."
Write-Host ""
Write-Host "Installing CUDA runtime dependencies for faster-whisper..."

& $venvPython -m pip install -U faster-whisper nvidia-cublas-cu12 nvidia-cudnn-cu12
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

Write-Host ""
Write-Host "Ensuring local faster-whisper model exists..."
powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "download-whisper-model.ps1") -Model $Model
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

Write-Host ""
Write-Host "CUDA ASR dependencies installed."
Write-Host "Test command:"
Write-Host "  .\scripts\transcribe-audio.ps1 -Audio <audio.wav> -Model $Model -Language auto -Device cuda"

param(
    [string]$Video,

    [ValidateSet("preview", "final")]
    [string]$Purpose = "final"
)

$ErrorActionPreference = "Stop"

function Format-GB {
    param([double]$Bytes)
    return "{0:N1} GB" -f ($Bytes / 1GB)
}

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$venvPython = Join-Path $repoRoot ".venv\Scripts\python.exe"
$computer = Get-CimInstance Win32_ComputerSystem
$processor = Get-CimInstance Win32_Processor | Select-Object -First 1
$gpus = Get-CimInstance Win32_VideoController | Select-Object -ExpandProperty Name
$hasNvidia = ($gpus | Where-Object { $_ -match "NVIDIA" }) -ne $null
$asrDevice = "cpu"
$cudaAvailable = $false
if (Test-Path $venvPython) {
    try {
        $deviceInfoText = & $venvPython (Join-Path $PSScriptRoot "detect-asr-device.py")
        $deviceInfo = $deviceInfoText | ConvertFrom-Json
        $cudaAvailable = [bool]$deviceInfo.cuda_available
        $asrDevice = $deviceInfo.recommended_device
    } catch {
        $cudaAvailable = $false
        $asrDevice = "cpu"
    }
}
$totalRamGb = [math]::Round($computer.TotalPhysicalMemory / 1GB, 1)

$durationSeconds = $null
if ($Video) {
    $videoPath = Resolve-Path -LiteralPath $Video
    $ffprobe = Get-ChildItem -Path "$env:LOCALAPPDATA\Microsoft\WinGet\Packages" -Filter ffprobe.exe -Recurse -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $ffprobe) {
        $ffprobe = "ffprobe"
    }
    $durationText = & $ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 $videoPath.Path
    $durationSeconds = [double]$durationText
}

$models = @(
    [pscustomobject]@{
        Model = "small"
        Download = "~0.5 GB"
        RecommendedMemory = "2-3 GB available"
        UseCase = "Fast preview, rough notes, low-memory machines"
        RuntimeRatio = 0.20
    },
    [pscustomobject]@{
        Model = "medium"
        Download = "~1.5 GB"
        RecommendedMemory = "5-6 GB available"
        UseCase = "Formal notes, better English terms, better mixed-language ASR"
        RuntimeRatio = 0.57
    }
)

if ($totalRamGb -lt 8) {
    $recommended = "small"
    $reason = "total RAM is below 8 GB"
} elseif ($totalRamGb -lt 12) {
    $recommended = if ($Purpose -eq "preview") { "small" } else { "small" }
    $reason = "RAM is moderate; small is safer"
} elseif ($Purpose -eq "preview") {
    $recommended = "small"
    $reason = "preview mode favors speed"
} else {
    $recommended = "medium"
    $reason = "this machine has enough RAM for medium and final notes benefit from better terminology"
}

Write-Host "ASR model recommendation"
Write-Host "Machine: $($processor.Name)"
Write-Host "CPU: $($processor.NumberOfCores) cores / $($processor.NumberOfLogicalProcessors) logical processors"
Write-Host "RAM: $totalRamGb GB"
Write-Host "GPU: $($gpus -join '; ')"
if ($cudaAvailable) {
    Write-Host "GPU ASR: CUDA is available in this Python environment. The pipeline will prefer CUDA."
} elseif ($hasNvidia) {
    Write-Host "GPU ASR: NVIDIA GPU detected, but CUDA ASR is not configured. First run should use CPU; CUDA can be configured later."
} else {
    Write-Host "GPU ASR: no NVIDIA GPU detected. CPU transcription is recommended for new users."
}
Write-Host ""
Write-Host "Model options:"
foreach ($model in $models) {
    $estimate = ""
    if ($durationSeconds) {
        $seconds = [math]::Round($durationSeconds * $model.RuntimeRatio)
        $estimate = "; estimated runtime on this machine: ~{0:N0}s" -f $seconds
    }
    Write-Host "- $($model.Model): first download $($model.Download), memory $($model.RecommendedMemory)$estimate"
    Write-Host "  $($model.UseCase)"
}
Write-Host ""
Write-Host "Recommended: $recommended ($reason)"
Write-Host "recommended_model=$recommended"
Write-Host "recommended_device=$asrDevice"

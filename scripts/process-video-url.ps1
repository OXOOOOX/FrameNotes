param(
    [Parameter(Mandatory = $true)]
    [string]$Url,

    [ValidateSet("auto", "zh", "en", "ja", "ko", "fr", "de", "es")]
    [string]$Language = "auto",

    [string]$AsrModel = "auto",

    [ValidateSet("auto", "cpu", "cuda")]
    [string]$AsrDevice = "auto",

    [int]$MaxFrames = 24,

    [double]$FrameReviewWindow = 4,

    [double]$FrameReviewFps = 1,

    [switch]$SkipDownload,

    [switch]$SkipAsr
)

$ErrorActionPreference = "Stop"

function Write-Stage {
    param(
        [int]$Current,
        [int]$Total,
        [string]$Message
    )
    Write-Host "[STAGE] $Current/$Total $Message"
}

function Start-PipelineStage {
    param(
        [int]$Current,
        [int]$Total,
        [string]$Message
    )
    Write-Stage $Current $Total $Message
    return Get-Date
}

function Add-PipelineStage {
    param(
        [System.Collections.ArrayList]$Stages,
        [string]$Name,
        [datetime]$StartedAt,
        [hashtable]$Artifacts = @{}
    )
    $endedAt = Get-Date
    [void]$Stages.Add([ordered]@{
        name = $Name
        started_at = $StartedAt.ToUniversalTime().ToString("o")
        ended_at = $endedAt.ToUniversalTime().ToString("o")
        duration_seconds = [math]::Round(($endedAt - $StartedAt).TotalSeconds, 2)
        artifacts = $Artifacts
    })
}

function Invoke-Checked {
    param(
        [scriptblock]$Command,
        [string]$FailureMessage
    )

    & $Command
    if ($LASTEXITCODE -ne 0) {
        throw $FailureMessage
    }
}

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$pipelineStartedAt = Get-Date
$pipelineStages = [System.Collections.ArrayList]::new()

$stageTotal = 6

if ($SkipDownload) {
    Write-Host "[STAGE] Skip Download (using existing video)"
    $video = Get-ChildItem -Path (Join-Path $repoRoot "media") -Filter *.mp4 -Recurse -File |
        Where-Object { $_.Name -notmatch "\.f\d+\.mp4$" } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if (-not $video) {
        throw "SkipDownload: no existing MP4 found under media."
    }
    Write-Host "      video: $($video.FullName)"
} else {
    $stageStart = Start-PipelineStage 1 $stageTotal "Downloading video"
    Invoke-Checked { powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "download-video.ps1") $Url } "Video download failed."

    $video = Get-ChildItem -Path (Join-Path $repoRoot "media") -Filter *.mp4 -Recurse -File |
        Where-Object { $_.Name -notmatch "\.f\d+\.mp4$" } |
        Where-Object { $_.LastWriteTime -ge $stageStart.AddSeconds(-2) } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if (-not $video) {
        $video = Get-ChildItem -Path (Join-Path $repoRoot "media") -Filter *.mp4 -Recurse -File |
            Where-Object { $_.Name -notmatch "\.f\d+\.mp4$" } |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1
    }
    if (-not $video) {
        throw "No downloaded MP4 found under media."
    }
    Write-Host "      video: $($video.FullName)"
    Add-PipelineStage $pipelineStages "download" $stageStart @{ video = $video.FullName }
}

$stageStart = Start-PipelineStage 2 $stageTotal "Extracting scene-change keyframes"
$keyframeOutput = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "extract-keyframes.ps1") -Video $video.FullName
if ($LASTEXITCODE -ne 0) {
    throw "Keyframe extraction failed."
}

$analysisDirPath = $keyframeOutput | Where-Object { $_ -like "*\analysis\*" -or $_ -like "*:/Users/*" } | Select-Object -First 1
$analysisDir = if ($analysisDirPath) { Get-Item -LiteralPath $analysisDirPath } else { $null }
if (-not $analysisDir) {
    throw "Keyframe extraction did not report an analysis directory."
}
$framesJson = Get-Item -LiteralPath (Join-Path $analysisDir.FullName "frames.json")
if (-not $framesJson) {
    throw "No frames.json found in this run's analysis directory."
}
Write-Host "      frames: $($framesJson.FullName)"
Add-PipelineStage $pipelineStages "keyframes" $stageStart @{ analysis = $analysisDir.FullName; frames_json = $framesJson.FullName }

$stageStart = Start-PipelineStage 3 $stageTotal "Building multimodal frame package"
$packageOutput = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "build-multimodal-package.ps1") -FramesJson $framesJson.FullName -MaxFrames $MaxFrames
if ($LASTEXITCODE -ne 0) {
    throw "Multimodal package build failed."
}
$promptPath = $packageOutput | Where-Object { $_ -like "*.md" } | Select-Object -First 1
$selectedFramesPath = $packageOutput | Where-Object { $_ -like "*.json" } | Select-Object -First 1
Add-PipelineStage $pipelineStages "multimodal_package" $stageStart @{ prompt = $promptPath; selected_frames = $selectedFramesPath }

$stageStart = Start-PipelineStage 4 $stageTotal "Preparing agent frame review package"
$frameReviewOutput = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "refine-frames.ps1") -SelectedFramesJson $selectedFramesPath -ExtractDense -Window $FrameReviewWindow -Fps $FrameReviewFps
if ($LASTEXITCODE -ne 0) {
    throw "Frame review package build failed."
}
$frameReviewPath = $frameReviewOutput | Where-Object { $_ -like "*frame_review.json" } | Select-Object -First 1
$frameReviewPromptPath = $frameReviewOutput | Where-Object { $_ -like "*frame_review_prompt.md" } | Select-Object -First 1
$denseCandidatesPath = $frameReviewOutput | Where-Object { $_ -like "*dense_candidates" } | Select-Object -First 1
Add-PipelineStage $pipelineStages "frame_review_package" $stageStart @{
    frame_review = $frameReviewPath
    prompt = $frameReviewPromptPath
    dense_candidates = $denseCandidatesPath
}

Write-Host "      生成审查用预览帧 (720p)"
$previewResult = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "downsample-review-frames.ps1") -FrameReviewJson $frameReviewPath
if ($LASTEXITCODE -ne 0) {
    Write-Warning "Preview frame generation failed; review will use original frames"
}
Write-Host "      预览帧生成完成"

if ($SkipAsr) {
    Write-Host "[STAGE] Skip ASR (using existing transcript)"
    $latestAudioDir = Get-ChildItem -Path (Join-Path $repoRoot "analysis") -Directory -Filter "*_audio_*" |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if (-not $latestAudioDir) {
        throw "SkipAsr: no existing audio directory found under analysis."
    }
    $audioPath = Join-Path $latestAudioDir.FullName "audio.wav"
    $audio = if (Test-Path -LiteralPath $audioPath) { Get-Item -LiteralPath $audioPath } else { $null }
    $transcript = Get-ChildItem -Path $latestAudioDir.FullName -Filter transcript.txt -File |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    $transcriptJson = Get-ChildItem -Path $latestAudioDir.FullName -Filter transcript.json -File |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if (-not $transcriptJson) {
        throw "SkipAsr: no transcript.json found in $($latestAudioDir.FullName)"
    }
    Write-Host "      using transcript: $($transcript.FullName)"
    Add-PipelineStage $pipelineStages "audio" (Get-Date) @{ audio = if ($audio) { $audio.FullName } else { $null }; skipped = $true }
    Add-PipelineStage $pipelineStages "asr" (Get-Date) @{ transcript = if ($transcript) { $transcript.FullName } else { $null }; transcript_json = $transcriptJson.FullName; model = "skipped"; device = "skipped"; skipped = $true }
} else {
    $stageStart = Start-PipelineStage 5 $stageTotal "Extracting audio for ASR"
    $audioOutput = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "extract-audio.ps1") -Video $video.FullName
    if ($LASTEXITCODE -ne 0) {
        throw "Audio extraction failed."
    }
    $audioPath = $audioOutput | Where-Object { $_ -like "*.wav" } | Select-Object -Last 1
    $audio = if ($audioPath) { Get-Item -LiteralPath $audioPath } else { $null }
    if (-not $audio) {
        throw "No audio.wav was produced by audio extraction."
    }
    Write-Host "      audio: $($audio.FullName)"
    Add-PipelineStage $pipelineStages "audio" $stageStart @{ audio = $audio.FullName }

    if ($AsrModel -eq "auto") {
        Write-Host "      choosing ASR model based on this machine"
        $recommendation = powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "recommend-asr-model.ps1") -Video $video.FullName -Purpose final
        $recommendation | ForEach-Object { Write-Host "      $_" }
        $recommendedLine = $recommendation | Where-Object { $_ -like "recommended_model=*" } | Select-Object -Last 1
        $recommendedDeviceLine = $recommendation | Where-Object { $_ -like "recommended_device=*" } | Select-Object -Last 1
        $AsrModel = ($recommendedLine -replace "recommended_model=", "").Trim()
        if ($AsrDevice -eq "auto" -and $recommendedDeviceLine) {
            $AsrDevice = ($recommendedDeviceLine -replace "recommended_device=", "").Trim()
        }
        if (-not $AsrModel) {
            $AsrModel = "medium"
        }
    }

    $modelsDir = Join-Path $HOME ".cache\framenotes\models"
    if ($AsrModel -notmatch "[\\/]" -and -not (Test-Path (Join-Path $modelsDir "faster-whisper-$AsrModel\model.bin"))) {
        Write-Host "      local ASR model not found; downloading faster-whisper-$AsrModel"
        Invoke-Checked { powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "download-whisper-model.ps1") -Model $AsrModel -AutoDownload } "ASR model download failed."
    }

    $stageStart = Start-PipelineStage 6 $stageTotal "Running ASR with faster-whisper model '$AsrModel'"
    Invoke-Checked { powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "transcribe-audio.ps1") -Audio $audio.FullName -Model $AsrModel -Language $Language -Device $AsrDevice } "ASR transcription failed."

    $transcript = Get-ChildItem -Path $audio.DirectoryName -Filter transcript.txt -File |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    $transcriptJson = Get-ChildItem -Path $audio.DirectoryName -Filter transcript.json -File |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if (-not $transcript) {
        Write-Warning "ASR completed but no transcript.txt was found."
    }
    if (-not $transcriptJson) {
        Write-Warning "ASR completed but no transcript.json was found."
    }
    Add-PipelineStage $pipelineStages "asr" $stageStart @{ transcript = if ($transcript) { $transcript.FullName } else { $null }; transcript_json = if ($transcriptJson) { $transcriptJson.FullName } else { $null }; model = $AsrModel; device = $AsrDevice }
}

$prescreenStageStart = Get-Date
Write-Host "      pre-screening frames via text LLM (skip obvious rejects)"
if ($transcriptJson) {
    $prescreenResult = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "prescreen-frames.ps1") -FrameReviewJson $frameReviewPath -Transcript $transcriptJson.FullName
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Frame pre-screening failed; all frames will go to multimodal review"
    }
} else {
    Write-Warning "No transcript available; skipping pre-screen"
}
Add-PipelineStage $pipelineStages "prescreen" $prescreenStageStart @{ frame_review = $frameReviewPath }

$pipelineManifest = [ordered]@{
    url = $Url
    started_at = $pipelineStartedAt.ToUniversalTime().ToString("o")
    ended_at = (Get-Date).ToUniversalTime().ToString("o")
    duration_seconds = [math]::Round(((Get-Date) - $pipelineStartedAt).TotalSeconds, 2)
    video = $video.FullName
    analysis = $framesJson.DirectoryName
    audio_dir = $audio.DirectoryName
    transcript = if ($transcript) { $transcript.FullName } else { $null }
    stages = $pipelineStages
}
$pipelinePath = Join-Path $framesJson.DirectoryName "pipeline.json"
$pipelineManifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $pipelinePath -Encoding UTF8

Write-Host "Done."
if ($transcript) { Write-Host "      transcript: $($transcript.FullName)" }
Write-Host "      analysis: $($framesJson.DirectoryName)"
Write-Host "      pipeline: $pipelinePath"

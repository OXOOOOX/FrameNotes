param(
    [Parameter(Mandatory=$true)]
    [string]$FrameReviewJson,
    [int]$MaxWidth = 1280,
    [int]$MaxHeight = 720
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $FrameReviewJson)) {
    throw "frame_review.json not found: $FrameReviewJson"
}

$review = Get-Content -LiteralPath $FrameReviewJson -Raw -Encoding UTF8 | ConvertFrom-Json
$analysisDir = Split-Path -Parent $FrameReviewJson
$previewDir = Join-Path $analysisDir "preview_frames"
New-Item -ItemType Directory -Force -Path $previewDir | Out-Null

$ffmpegPath = (Get-Command ffmpeg -ErrorAction SilentlyContinue).Source
if (-not $ffmpegPath) {
    throw "ffmpeg not found on PATH"
}

$count = 0
foreach ($frame in $review.frames) {
    $srcPath = Join-Path $analysisDir ($frame.frame_path -replace '/', '\')
    if (-not (Test-Path -LiteralPath $srcPath)) {
        Write-Warning "Missing frame: $srcPath"
        continue
    }

    $previewName = "preview_$($frame.index.ToString('00000')).jpg"
    $previewPath = Join-Path $previewDir $previewName

    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $null = & $ffmpegPath -hide_banner -loglevel error -y -i $srcPath -vf "scale='min($MaxWidth,iw)':'min($MaxHeight,ih)':force_original_aspect_ratio=decrease" -q:v 2 $previewPath
    if ($LASTEXITCODE -eq 0) {
        $frame | Add-Member -NotePropertyName preview_path -NotePropertyValue "preview_frames/$previewName" -Force
        $count++
    }
    $ErrorActionPreference = $prevEAP
}

# Also downsample replacement candidates
foreach ($frame in $review.frames) {
    foreach ($candidate in $frame.review.replacement_candidates) {
        $candSrc = Join-Path $analysisDir ($candidate.path -replace '/', '\')
        if (-not (Test-Path -LiteralPath $candSrc)) { continue }

        $relDir = Split-Path -Parent $candidate.path
        $candPreviewDir = Join-Path $previewDir ($relDir -replace '/', '\')
        New-Item -ItemType Directory -Force -Path $candPreviewDir | Out-Null

        $candName = Split-Path -Leaf $candidate.path
        $candPreviewPath = Join-Path $candPreviewDir "preview_$candName"

        $prevEAP = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        $null = & $ffmpegPath -hide_banner -loglevel error -y -i $candSrc -vf "scale='min($MaxWidth,iw)':'min($MaxHeight,ih)':force_original_aspect_ratio=decrease" -q:v 2 $candPreviewPath

        if ($LASTEXITCODE -eq 0) {
            $candidate | Add-Member -NotePropertyName preview_path -NotePropertyValue (Join-Path (Join-Path "preview_frames" $relDir) "preview_$candName").Replace('\','/') -Force
        }
        $ErrorActionPreference = $prevEAP
    }
}

$outPath = Join-Path $analysisDir "frame_review.json"
$review | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $outPath -Encoding UTF8

Write-Host "Downsampled $count review frames to $previewDir"
Write-Host "Updated: $outPath"
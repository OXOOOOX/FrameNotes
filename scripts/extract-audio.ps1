param(
    [Parameter(Mandatory = $true)]
    [string]$Video,

    [string]$OutputRoot = "analysis",

    [int]$SampleRate = 16000
)

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$videoPath = Resolve-Path -LiteralPath $Video
$ffmpeg = Get-ChildItem -Path "$env:LOCALAPPDATA\Microsoft\WinGet\Packages" -Filter ffmpeg.exe -Recurse -File -ErrorAction SilentlyContinue |
    Select-Object -First 1 -ExpandProperty FullName

if (-not $ffmpeg) {
    $ffmpeg = "ffmpeg"
}

$stamp = [DateTime]::UtcNow.ToString("yyyyMMddTHHmmssZ")
$safeName = [IO.Path]::GetFileNameWithoutExtension($videoPath.Path) -replace '[^\p{L}\p{Nd}._-]+', '_'
if ($safeName.Length -gt 80) {
    $safeName = $safeName.Substring(0, 80)
}

$outputDir = Join-Path (Join-Path $repoRoot $OutputRoot) "$safeName`_audio_$stamp"
New-Item -ItemType Directory -Path $outputDir | Out-Null

$audioPath = Join-Path $outputDir "audio.wav"

& $ffmpeg `
    -hide_banner `
    -i $videoPath.Path `
    -vn `
    -ac 1 `
    -ar $SampleRate `
    -c:a pcm_s16le `
    $audioPath

if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

$manifest = @{
    source_video = $videoPath.Path
    audio = "audio.wav"
    sample_rate = $SampleRate
    channels = 1
    created_at = $stamp
}

$manifest | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $outputDir "audio.json") -Encoding UTF8

Write-Output $outputDir
Write-Output $audioPath

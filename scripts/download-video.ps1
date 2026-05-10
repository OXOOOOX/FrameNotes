param(
    [Parameter(Mandatory = $true)]
    [string]$Url,

    [string]$OutputRoot = "media",

    [ValidateSet("none", "edge", "chrome", "firefox")]
    [string]$CookiesFromBrowser = "none"
)

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$outputPath = Join-Path $repoRoot $OutputRoot
$venvPython = Join-Path $repoRoot ".venv\Scripts\python.exe"
$wingetFfmpeg = Get-ChildItem -Path "$env:LOCALAPPDATA\Microsoft\WinGet\Packages" -Filter ffmpeg.exe -Recurse -File -ErrorAction SilentlyContinue |
    Select-Object -First 1 -ExpandProperty DirectoryName

if (-not (Test-Path $venvPython)) {
    throw "Project Python environment not found. Run: python -m venv .venv; .\.venv\Scripts\python.exe -m pip install -U yt-dlp"
}

New-Item -ItemType Directory -Force -Path $outputPath | Out-Null

$template = "%(extractor)s/%(title).120B [%(id)s]/%(title).120B [%(id)s].%(ext)s"
$args = @(
    "-m", "yt_dlp",
    "--paths", $outputPath,
    "--output", $template,
    "--no-overwrites",
    "--no-mtime",
    "--write-info-json",
    "--write-thumbnail",
    "--write-subs",
    "--write-auto-subs",
    "--sub-langs", "zh-CN,zh-Hans,zh-Hant,en",
    "--keep-video",
    "--merge-output-format", "mp4"
)

if ($wingetFfmpeg) {
    $args += @("--ffmpeg-location", $wingetFfmpeg)
}

if ($CookiesFromBrowser -ne "none") {
    $args += @("--cookies-from-browser", $CookiesFromBrowser)
}

$args += $Url

& $venvPython @args
exit $LASTEXITCODE

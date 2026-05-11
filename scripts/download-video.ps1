param(
    [Parameter(Mandatory = $true)]
    [string]$Url,

    [string]$OutputRoot = "media",

    [ValidateSet("none", "edge", "chrome", "firefox")]
    [string]$CookiesFromBrowser = "none",

    [string]$Cookies = ""
)

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$outputPath = Join-Path $repoRoot $OutputRoot
$venvPython = Join-Path $repoRoot ".venv\Scripts\python.exe"
$repoCookies = Join-Path $repoRoot "cookies.txt"
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
    "--merge-output-format", "mp4",
    "--format", "bestvideo[height<=1080]+bestaudio/best[height<=1080]/best"
)

if ($wingetFfmpeg) {
    $args += @("--ffmpeg-location", $wingetFfmpeg)
}

if ($Cookies) {
    $args += @("--cookies", $Cookies)
}
elseif ($CookiesFromBrowser -ne "none") {
    $args += @("--cookies-from-browser", $CookiesFromBrowser)
}
elseif (Test-Path $repoCookies) {
    Write-Host "      using cookies.txt from repo root"
    $args += @("--cookies", $repoCookies)
}

$args += $Url

& $venvPython @args
exit $LASTEXITCODE
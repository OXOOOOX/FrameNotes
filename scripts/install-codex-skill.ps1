param(
    [string]$CodexHome = $env:CODEX_HOME
)

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$sourceSkill = Join-Path $repoRoot "skills\framenotes"

if (-not $CodexHome) {
    $CodexHome = Join-Path $HOME ".codex"
}

$skillsRoot = Join-Path $CodexHome "skills"
$targetSkill = Join-Path $skillsRoot "framenotes"
$targetAgents = Join-Path $targetSkill "agents"

if (-not (Test-Path -LiteralPath (Join-Path $sourceSkill "SKILL.md"))) {
    throw "Source skill not found: $sourceSkill"
}

New-Item -ItemType Directory -Force -Path $targetSkill | Out-Null
New-Item -ItemType Directory -Force -Path $targetAgents | Out-Null

Copy-Item -LiteralPath (Join-Path $sourceSkill "SKILL.md") -Destination (Join-Path $targetSkill "SKILL.md") -Force
Copy-Item -LiteralPath (Join-Path $sourceSkill "agents\openai.yaml") -Destination (Join-Path $targetAgents "openai.yaml") -Force

$installedSkill = Join-Path $targetSkill "SKILL.md"
$content = Get-Content -LiteralPath $installedSkill -Raw -Encoding UTF8
$versionMatch = [regex]::Match($content, 'version:\s*"([^"]+)"')
$version = if ($versionMatch.Success) { $versionMatch.Groups[1].Value } else { "unknown" }
$content = $content -replace '\.\\scripts\\', "$repoRoot\scripts\"
$content = $content -replace '\./scripts/', "$repoRoot/scripts/"
# Handle the "find a folder containing scripts/..." heuristic for the installed case
$content = $content -replace 'find a folder containing `scripts/process-video-url\.ps1` and use that as the working directory\.', "the scripts are installed at ``$repoRoot\scripts\``. For generated media/analysis output, use the current project's working directory."
$utf8NoBom = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText($installedSkill, $content, $utf8NoBom)

Write-Host "Installed FrameNotes skill (v$version):"
Write-Host "      $targetSkill"

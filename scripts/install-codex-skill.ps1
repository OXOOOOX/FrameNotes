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

Write-Host "Installed FrameNotes skill:"
Write-Host "      $targetSkill"

param(
    [Parameter(Mandatory = $true)]
    [string]$Markdown,

    [string]$Output,

    [string]$NamePrefix
)

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$python = Join-Path $repoRoot ".venv\Scripts\python.exe"
$mdPath = Resolve-Path -LiteralPath $Markdown

if (-not (Test-Path $python)) {
    throw "Project Python environment not found. Run: python -m venv .venv"
}

$args = @(
    (Join-Path $PSScriptRoot "export-tutorial-docx.py"),
    $mdPath.Path
)

if ($Output) {
    $args += @("--output", $Output)
}

if ($NamePrefix) {
    $args += @("--name-prefix", $NamePrefix)
}

& $python @args
exit $LASTEXITCODE

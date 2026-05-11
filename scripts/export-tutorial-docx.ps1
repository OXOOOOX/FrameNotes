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

# Auto-install python-docx if missing
$docxCheck = & $python -c "import docx; print('ok')" 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "      Installing python-docx..."
    & $python -m pip install -q python-docx
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to install python-docx. Run: .\.venv\Scripts\pip.exe install python-docx"
    }
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

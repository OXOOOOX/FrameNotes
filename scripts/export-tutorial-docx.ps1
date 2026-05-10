param(
    [Parameter(Mandatory = $true)]
    [string]$Markdown,

    [string]$Output,

    [string]$NamePrefix
)

$ErrorActionPreference = "Stop"

$python = "C:\Users\23479\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe"
$mdPath = Resolve-Path -LiteralPath $Markdown

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

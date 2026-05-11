param(
    [Parameter(Mandatory = $true)]
    [string]$Docx
)

$ErrorActionPreference = "Stop"

$docxPath = Resolve-Path -LiteralPath $Docx
$pdfPath = [IO.Path]::ChangeExtension($docxPath.Path, ".pdf")
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$python = Join-Path $repoRoot ".venv\Scripts\python.exe"

if (-not (Test-Path $python)) {
    throw "Project Python environment not found. Run: python -m venv .venv"
}

# Ensure python-docx and docx2pdf are available
& $python -m pip install -q python-docx docx2pdf 2>$null

$script = @"
import sys
from pathlib import Path
from docx2pdf import convert

convert(sys.argv[1], sys.argv[2])
"@

& $python -c $script $docxPath.Path $pdfPath
if ($LASTEXITCODE -ne 0) {
    Write-Warning "docx2pdf failed; trying Word COM fallback..."
    $word = New-Object -ComObject Word.Application
    $word.Visible = $false
    try {
        $doc = $word.Documents.Open($docxPath.Path)
        $doc.SaveAs([ref]$pdfPath, [ref]17)
        $doc.Close()
    } finally {
        $word.Quit()
    }
}

if (Test-Path -LiteralPath $pdfPath) {
    Write-Host $pdfPath
} else {
    throw "PDF export failed."
}

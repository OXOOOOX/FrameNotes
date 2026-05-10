param(
    [Parameter(Mandatory = $true)]
    [string]$Text,

    [int]$MaxLength = 80
)

$safe = $Text -replace '[^\p{L}\p{Nd}._-]+', '_'
$safe = $safe.Trim('_', '.', '-')
if ($safe.Length -gt $MaxLength) {
    $safe = $safe.Substring(0, $MaxLength).Trim('_', '.', '-')
}
if (-not $safe) {
    $safe = "tutorial"
}
Write-Output $safe

param([Parameter(Mandatory=$true)][string]$DocumentPath)
$ErrorActionPreference = 'Stop'
$docxPath = [IO.Path]::GetFullPath($DocumentPath)
$pdfPath = [IO.Path]::ChangeExtension($docxPath, '.pdf')
$word = $null
$document = $null
$ownsInstance = $false
try {
    $word = New-Object -ComObject Word.Application
    $ownsInstance = ($word.Documents.Count -eq 0)
    if (-not $ownsInstance) { throw 'The automation instance contains existing documents; refusing to alter it.' }
    $word.Visible = $false
    $word.DisplayAlerts = 0
    $document = $word.Documents.Open($docxPath, $false, $true, $false)
    $document.Fields.Update() | Out-Null
    $document.Repaginate()
    $pages = $document.ComputeStatistics(2)
    $document.ExportAsFixedFormat($pdfPath, 17, $false, 0, 0, 1, 1, 0, $false, $true, 1)
    Write-Output "Exported $pages pages to $pdfPath"
} finally {
    if ($null -ne $document) { $document.Close(0); [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($document) }
    if ($null -ne $word) {
        if ($ownsInstance) { $word.Quit() }
        [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($word)
    }
}

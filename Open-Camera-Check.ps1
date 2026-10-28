$ErrorActionPreference = 'Stop'
$runtime = Join-Path $PSScriptRoot 'runtime\Bonsai.exe'
$workflow = Join-Path $PSScriptRoot 'controller\Camera-Tracking-Check.bonsai'
if (-not (Test-Path -LiteralPath $runtime) -or -not (Test-Path -LiteralPath $workflow)) {
    throw 'Run Restore-Environment.ps1 and prepare_sources.py first.'
}
# Opens for inspection only. Press F5 in Bonsai only when ready to open the camera.
Start-Process -FilePath $runtime -ArgumentList ('"' + $workflow + '"') -WorkingDirectory (Split-Path $workflow) -WindowStyle Normal | Out-Null

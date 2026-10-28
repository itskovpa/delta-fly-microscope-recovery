$ErrorActionPreference = 'Stop'
$runtime = Join-Path $PSScriptRoot 'runtime\Bonsai.exe'
$workflow = Join-Path $PSScriptRoot 'offline\Offline-Demo.bonsai'
if (-not (Test-Path -LiteralPath $runtime) -or -not (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'runtime\Extensions\Recovery.Offline.dll'))) {
    throw 'Run Restore-Environment.ps1 and offline\Build-Offline.ps1 first.'
}
# Interactive editor is intentionally visible. Only the synthetic workflow is started.
Start-Process -FilePath $runtime -ArgumentList @(('"' + $workflow + '"'), '--start') -WorkingDirectory (Split-Path $workflow) -WindowStyle Normal | Out-Null

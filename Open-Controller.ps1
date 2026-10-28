$ErrorActionPreference = 'Stop'
$runtime = Join-Path $PSScriptRoot 'runtime\Bonsai.exe'
$workflow = Join-Path $PSScriptRoot 'controller\Delta-Controller.bonsai'
if (-not (Test-Path -LiteralPath $runtime)) { throw 'Run Restore-Environment.ps1 first.' }
New-Item -ItemType Directory -Force -Path (Join-Path $PSScriptRoot 'controller\recordings') | Out-Null
# Opens for inspection only. No --start: F5 on this workflow can immediately move the robot.
Start-Process -FilePath $runtime -ArgumentList ('"' + $workflow + '"') -WorkingDirectory (Split-Path $workflow) -WindowStyle Normal | Out-Null

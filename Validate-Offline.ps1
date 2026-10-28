$ErrorActionPreference = 'Stop'
Push-Location $PSScriptRoot
try {
    & python -X utf8 prepare_sources.py
    if ($LASTEXITCODE -ne 0) { throw 'Source preparation failed.' }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File offline\Build-Offline.ps1
    if ($LASTEXITCODE -ne 0) { throw 'Offline extension build failed.' }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File validation\Build-Validator.ps1
    if ($LASTEXITCODE -ne 0) { throw 'Validator build failed.' }
    & validation\bin\CompileWorkflow.exe runtime originals\DeltaX2Move2PashaModifyed_Last_3cameras.bonsai originals\Bonsai\ImageSta\DeltaX2Move2PashaModifyed_Last_3cameras.bonsai controller\Delta-Controller.bonsai offline\Offline-Demo.bonsai offline\Offline-SelfTest.bonsai offline\Offline-SelfTest-Apr13.bonsai
    if ($LASTEXITCODE -ne 0) { throw 'Workflow compilation failed.' }
    foreach ($variant in @('april10','april13')) {
        & python -X utf8 validation\run_offline_test.py --variant $variant
        if ($LASTEXITCODE -ne 0) { throw "Synthetic test failed: $variant" }
    }
} finally { Pop-Location }

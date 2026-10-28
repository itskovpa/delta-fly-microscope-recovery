param()
$ErrorActionPreference = 'Stop'
$recoveryRoot = $PSScriptRoot
$runtimePath = Join-Path $recoveryRoot 'runtime'
$downloadPath = Join-Path $recoveryRoot 'downloads'
New-Item -ItemType Directory -Force -Path $runtimePath,$downloadPath | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $recoveryRoot 'logs') | Out-Null
$env:NUGET_PACKAGES = Join-Path $recoveryRoot 'package-cache'
$env:DOTNET_CLI_TELEMETRY_OPTOUT = '1'
& dotnet restore (Join-Path $recoveryRoot 'environment\RestorePackages.csproj') --locked-mode --verbosity minimal
if ($LASTEXITCODE -ne 0) { throw 'Pinned NuGet package restoration failed.' }
$feedPath = Join-Path $recoveryRoot 'package-feed'
New-Item -ItemType Directory -Force -Path $feedPath | Out-Null
Get-ChildItem -LiteralPath $env:NUGET_PACKAGES -Recurse -Filter '*.nupkg' -File | Copy-Item -Destination $feedPath -Force
$portableZip = Join-Path $downloadPath 'Bonsai-2.7.1.zip'
if (-not (Test-Path -LiteralPath $portableZip)) {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -UseBasicParsing -Uri 'https://github.com/bonsai-rx/bonsai/releases/download/2.7.1/Bonsai.zip' -OutFile $portableZip
}
$expectedPortableHash = 'FCFAAD8449F647A138A4D5030AE1F9FEA073E11B877F3A494F354AD318455295'
if ((Get-FileHash -LiteralPath $portableZip -Algorithm SHA256).Hash -ne $expectedPortableHash) {
    throw 'The portable archive differs from the official release downloaded during recovery.'
}
if (-not (Test-Path -LiteralPath (Join-Path $runtimePath 'Bonsai.exe'))) {
    Expand-Archive -LiteralPath $portableZip -DestinationPath $runtimePath
}
Copy-Item -LiteralPath (Join-Path $recoveryRoot 'environment\Bonsai.config') -Destination $runtimePath -Force
Copy-Item -LiteralPath (Join-Path $recoveryRoot 'environment\NuGet.config') -Destination $runtimePath -Force
Push-Location $runtimePath
try {
    $restoreProcess = Start-Process -FilePath (Join-Path $runtimePath 'Bonsai.exe') -ArgumentList '--no-editor' -WorkingDirectory $runtimePath -WindowStyle Hidden -Wait -PassThru -RedirectStandardOutput (Join-Path $recoveryRoot 'logs\bootstrap.stdout.log') -RedirectStandardError (Join-Path $recoveryRoot 'logs\bootstrap.stderr.log')
    [xml]$restoredConfig = Get-Content -LiteralPath (Join-Path $runtimePath 'Bonsai.config') -Raw
    if (-not $restoredConfig.PackageConfiguration.AssemblyLocations.AssemblyLocation) { throw 'Restoration did not register any assemblies.' }
    foreach ($package in $restoredConfig.PackageConfiguration.Packages.Package) {
        $packageFolder = Join-Path $runtimePath ('Packages\' + $package.id + '.' + $package.version)
        if (-not (Test-Path -LiteralPath $packageFolder)) { throw "Missing restored package: $packageFolder" }
    }
    foreach ($entry in $restoredConfig.PackageConfiguration.AssemblyLocations.AssemblyLocation) {
        if (-not (Test-Path -LiteralPath (Join-Path $runtimePath $entry.location))) { throw "Missing restored assembly: $($entry.location)" }
    }
    $nativeCore = Join-Path $runtimePath 'Packages\OpenCV.Net.3.4.1\runtimes\win-x64\native\vc14\bin\opencv_core2413.dll'
    if (-not (Test-Path -LiteralPath $nativeCore)) { throw 'The x64 OpenCV native runtime is missing.' }
    if ($restoreProcess.ExitCode -ne 0) {
        # 2.7.1 ConsoleBootstrapper awaits an OnlyOnFaulted continuation, which is
        # cancelled when installation succeeds. Require all files above AND a
        # successful subsequent startup; never accept the first exit code alone.
        Write-Host 'Package files verified. Rechecking startup after legacy bootstrapper installation.'
        $recheckProcess = Start-Process -FilePath (Join-Path $runtimePath 'Bonsai.exe') -ArgumentList '--no-editor' -WorkingDirectory $runtimePath -WindowStyle Hidden -Wait -PassThru -RedirectStandardOutput (Join-Path $recoveryRoot 'logs\bootstrap-recheck.stdout.log') -RedirectStandardError (Join-Path $recoveryRoot 'logs\bootstrap-recheck.stderr.log')
        if ($recheckProcess.ExitCode -ne 0) { throw "Bonsai startup recheck failed: $($recheckProcess.ExitCode)" }
    }
} finally { Pop-Location }
Write-Host 'Bonsai 2.7.1 recovery environment restored. No workflow was started.'

$ErrorActionPreference = 'Stop'
$compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
$recoveryPath = Split-Path $PSScriptRoot
New-Item -ItemType Directory -Force -Path (Join-Path $recoveryPath 'runtime\Extensions') | Out-Null
Push-Location $PSScriptRoot
try {
    & $compiler /nologo /target:library /platform:x64 /optimize+ /out:..\runtime\Extensions\Recovery.Offline.dll /reference:..\package-cache\bonsai.core\2.7.1\lib\net462\Bonsai.Core.dll /reference:..\package-cache\opencv.net\3.4.1\lib\net462\OpenCV.Net.dll /reference:..\package-cache\rx-interfaces\2.2.5\lib\net45\System.Reactive.Interfaces.dll /reference:..\package-cache\rx-core\2.2.5\lib\net45\System.Reactive.Core.dll /reference:..\package-cache\rx-linq\2.2.5\lib\net45\System.Reactive.Linq.dll OfflineProbe.cs
    if ($LASTEXITCODE -ne 0) { throw 'Offline probe compilation failed.' }
} finally { Pop-Location }

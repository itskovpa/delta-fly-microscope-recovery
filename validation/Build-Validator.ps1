$ErrorActionPreference = 'Stop'
$compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
$output = Join-Path $PSScriptRoot 'bin\CompileWorkflow.exe'
New-Item -ItemType Directory -Force -Path (Split-Path $output) | Out-Null
Push-Location $PSScriptRoot
try {
    # CSC treats commas in /reference paths as separators, even when quoted.
    & $compiler /nologo /target:exe /platform:x64 /optimize+ /reference:..\package-cache\bonsai.core\2.7.1\lib\net462\Bonsai.Core.dll /out:bin\CompileWorkflow.exe CompileWorkflow.cs
    if ($LASTEXITCODE -ne 0) { throw "Validator compilation failed with exit code $LASTEXITCODE." }
} finally { Pop-Location }
Write-Host "Built $output"

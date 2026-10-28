# Portable Bonsai package validation. Return codes: 0 = pass; 1 = validation or test failure.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2

function Get-ContainedPath {
    param([string]$BasePath, [string]$RelativePath)
    if ([string]::IsNullOrWhiteSpace($RelativePath) -or [IO.Path]::IsPathRooted($RelativePath)) {
        throw "Expected a relative path, got '$RelativePath'."
    }
    $base = [IO.Path]::GetFullPath($BasePath)
    $full = [IO.Path]::GetFullPath((Join-Path $base $RelativePath))
    $prefix = $base.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    if (-not $full.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Path escapes its package directory: '$RelativePath'."
    }
    return $full
}

function Assert-Portable {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

try {
    if ($PSVersionTable.PSEdition -ne 'Desktop' -or $PSVersionTable.PSVersion -lt [Version]'5.1') {
        throw 'Run this checker with Windows PowerShell 5.1 (powershell.exe).'
    }

    $root = [IO.Path]::GetFullPath($PSScriptRoot)
    $runtime = Join-Path $root 'runtime'
    $offline = Join-Path $root 'offline'
    $logs = Join-Path $root 'logs'
    if (-not (Test-Path -LiteralPath $logs -PathType Container)) {
        New-Item -ItemType Directory -Path $logs -Force | Out-Null
    }

    $bonsaiExe = Join-Path $runtime 'Bonsai.exe'
    $configPath = Join-Path $runtime 'Bonsai.config'
    Assert-Portable (Test-Path -LiteralPath $bonsaiExe -PathType Leaf) 'Missing runtime/Bonsai.exe.'
    Assert-Portable (Test-Path -LiteralPath $configPath -PathType Leaf) 'Missing runtime/Bonsai.config.'
    $version = [Diagnostics.FileVersionInfo]::GetVersionInfo($bonsaiExe).ProductVersion
    Assert-Portable ($version -eq '2.7.1') "Bonsai ProductVersion must be 2.7.1; found '$version'."

    $config = [System.Xml.XmlDocument]::new()
    $config.XmlResolver = $null
    $config.Load($configPath)
    $packages = @($config.SelectNodes('/PackageConfiguration/Packages/Package'))
    $references = @($config.SelectNodes('/PackageConfiguration/AssemblyReferences/AssemblyReference'))
    $locations = @($config.SelectNodes('/PackageConfiguration/AssemblyLocations/AssemblyLocation'))
    $libraries = @($config.SelectNodes('/PackageConfiguration/LibraryFolders/LibraryFolder'))
    Assert-Portable ($packages.Count -eq 27) "Expected 27 configured packages; found $($packages.Count)."
    Assert-Portable ($references.Count -eq 14) "Expected 14 assembly references; found $($references.Count)."
    Assert-Portable ($locations.Count -eq 27) "Expected 27 assembly locations; found $($locations.Count)."
    Assert-Portable ($libraries.Count -eq 2) "Expected 2 native library folders; found $($libraries.Count)."

    $packageIds = @{}
    foreach ($package in $packages) {
        $id = $package.GetAttribute('id')
        $packageVersion = $package.GetAttribute('version')
        $parsedVersion = $null
        Assert-Portable (-not [string]::IsNullOrWhiteSpace($id)) 'A package entry has no id.'
        Assert-Portable ([Version]::TryParse($packageVersion, [ref]$parsedVersion)) "Invalid package version for '$id': '$packageVersion'."
        Assert-Portable (-not $packageIds.ContainsKey($id)) "Duplicate package id '$id'."
        $packageIds[$id] = $packageVersion
        $packageDirectory = Get-ContainedPath $runtime ("Packages\{0}.{1}" -f $id, $packageVersion)
        Assert-Portable (Test-Path -LiteralPath $packageDirectory -PathType Container) "Missing installed package '$id' version '$packageVersion'."
    }
    Assert-Portable ($packageIds['Bonsai'] -eq '2.7.1') 'Bonsai package version must be 2.7.1.'
    $installedPackageCount = @(Get-ChildItem -LiteralPath (Join-Path $runtime 'Packages') -Directory).Count
    Assert-Portable ($installedPackageCount -eq 27) "Expected 27 installed package folders; found $installedPackageCount."

    $assemblyPaths = @{}
    foreach ($location in $locations) {
        $name = $location.GetAttribute('assemblyName')
        $relativePath = $location.GetAttribute('location')
        Assert-Portable (-not [string]::IsNullOrWhiteSpace($name)) 'An assembly location has no assemblyName.'
        Assert-Portable (-not $assemblyPaths.ContainsKey($name)) "Duplicate assembly location '$name'."
        $path = Get-ContainedPath $runtime $relativePath
        Assert-Portable (Test-Path -LiteralPath $path -PathType Leaf) "Missing assembly: $relativePath"
        $assemblyPaths[$name] = $path
    }
    $referenceNames = @{}
    foreach ($reference in $references) {
        $name = $reference.GetAttribute('assemblyName')
        Assert-Portable (-not [string]::IsNullOrWhiteSpace($name)) 'An assembly reference has no assemblyName.'
        Assert-Portable (-not $referenceNames.ContainsKey($name)) "Duplicate assembly reference '$name'."
        Assert-Portable ($assemblyPaths.ContainsKey($name)) "No assembly location is configured for reference '$name'."
        $referenceNames[$name] = $true
    }
    foreach ($library in $libraries) {
        $relativePath = $library.GetAttribute('path')
        $path = Get-ContainedPath $runtime $relativePath
        Assert-Portable (Test-Path -LiteralPath $path -PathType Container) "Missing native library folder: $relativePath"
    }
    Write-Host 'PASS runtime: Bonsai 2.7.1; 27 packages, 14 references, 27 assemblies, 2 native folders.'

    $manifestPath = Join-Path $root 'PACKAGE-MANIFEST.json'
    if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
        $manifest = [IO.File]::ReadAllText($manifestPath) | ConvertFrom-Json
        $filesProperty = $manifest.PSObject.Properties['files']
        Assert-Portable ($null -ne $filesProperty -and $filesProperty.Value -is [array]) 'PACKAGE-MANIFEST.json must contain a files array.'
        $manifestFiles = $filesProperty.Value
        $seenFiles = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($entry in $manifestFiles) {
            $relativePath = [string]$entry.path
            Assert-Portable (-not [string]::IsNullOrWhiteSpace($relativePath)) 'A manifest file has no path.'
            Assert-Portable ($seenFiles.Add($relativePath)) "Duplicate manifest path '$relativePath'."
            $path = Get-ContainedPath $root $relativePath
            Assert-Portable (Test-Path -LiteralPath $path -PathType Leaf) "Manifest file is missing: $relativePath"
            $expectedBytes = 0L
            Assert-Portable ([long]::TryParse([string]$entry.bytes, [ref]$expectedBytes) -and $expectedBytes -ge 0) "Invalid byte count for '$relativePath'."
            Assert-Portable ($entry.sha256 -match '^[0-9A-Fa-f]{64}$') "Invalid SHA256 for '$relativePath'."
            $item = Get-Item -LiteralPath $path
            Assert-Portable ($item.Length -eq $expectedBytes) "Byte count mismatch for '$relativePath'."
            $actualHash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
            Assert-Portable ($actualHash -ieq [string]$entry.sha256) "SHA256 mismatch for '$relativePath'."
        }
        Write-Host "PASS manifest: $($manifestFiles.Count) file hashes verified."
    } else {
        Write-Host 'INFO manifest: PACKAGE-MANIFEST.json not present; hash check skipped.'
    }

    $compiler = Join-Path $root 'validation\CompileWorkflow.exe'
    if (-not (Test-Path -LiteralPath $compiler -PathType Leaf)) {
        $compiler = Join-Path $root 'validation\bin\CompileWorkflow.exe'
    }
    Assert-Portable (Test-Path -LiteralPath $compiler -PathType Leaf) 'Missing validation/CompileWorkflow.exe and validation/bin/CompileWorkflow.exe.'

    $workflowPaths = @(
        (Join-Path $root 'controller\Delta-Controller.bonsai'),
        (Join-Path $root 'controller\Camera-Tracking-Check.bonsai'),
        (Join-Path $offline 'Offline-Demo.bonsai'),
        (Join-Path $offline 'Offline-SelfTest.bonsai'),
        (Join-Path $offline 'Offline-SelfTest-Apr13.bonsai')
    )
    foreach ($workflow in $workflowPaths) {
        Assert-Portable (Test-Path -LiteralPath $workflow -PathType Leaf) "Missing workflow: $workflow"
    }
    $quotedWorkflows = ($workflowPaths | ForEach-Object { '"' + $_ + '"' }) -join ' '
    $compileArgs = '"{0}" {1}' -f $runtime, $quotedWorkflows
    $compileOut = Join-Path $logs 'portable-compile.stdout.log'
    $compileErr = Join-Path $logs 'portable-compile.stderr.log'
    $compileProcess = Start-Process -FilePath $compiler -ArgumentList $compileArgs -WorkingDirectory $root -PassThru -Wait -WindowStyle Hidden -RedirectStandardOutput $compileOut -RedirectStandardError $compileErr
    Assert-Portable ($compileProcess.ExitCode -eq 0) "Compile-only workflow validation failed (exit $($compileProcess.ExitCode)); see portable-compile logs."
    Write-Host 'PASS compile-only: 5 workflows; controllers were not executed.'

    $resultPath = Join-Path $offline 'offline-test-result.json'
    $variants = @(
        @{ Name = 'april10'; Workflow = 'Offline-SelfTest.bonsai' },
        @{ Name = 'april13'; Workflow = 'Offline-SelfTest-Apr13.bonsai' }
    )
    foreach ($variant in $variants) {
        if (Test-Path -LiteralPath $resultPath -PathType Leaf) {
            Remove-Item -LiteralPath $resultPath -Force
        }
        $workflow = Join-Path $offline $variant.Workflow
        $stdout = Join-Path $logs ("portable-offline-{0}.stdout.log" -f $variant.Name)
        $stderr = Join-Path $logs ("portable-offline-{0}.stderr.log" -f $variant.Name)
        $resultOutput = Join-Path $logs ("portable-offline-test-result-{0}.json" -f $variant.Name)
        $arguments = '"{0}" --no-editor' -f $workflow
        $process = Start-Process -FilePath $bonsaiExe -ArgumentList $arguments -WorkingDirectory $offline -PassThru -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr
        $null = $process.Handle
        try {
            if (-not $process.WaitForExit(20000)) {
                $process.Kill()
                $process.WaitForExit()
                throw "Offline workflow '$($variant.Name)' timed out after 20 seconds; only the spawned Bonsai process was stopped. See logs."
            }
            $process.WaitForExit()
            $process.Refresh()
            $exitCode = $process.ExitCode
            Assert-Portable ($null -ne $exitCode -and $exitCode -eq 0) "Offline workflow '$($variant.Name)' exited with '$exitCode'; see logs."
        } finally {
            $process.Dispose()
        }
        Assert-Portable (Test-Path -LiteralPath $resultPath -PathType Leaf) "Offline workflow '$($variant.Name)' produced no assertion result. See logs."
        $result = [IO.File]::ReadAllText($resultPath) | ConvertFrom-Json
        Assert-Portable ($result.passed -is [bool] -and $result.passed) "Offline workflow '$($variant.Name)' did not pass its assertions."
        $expected = @{ synthetic_frames = 80; blank_frames = 8; tracking_commands = 72; max_command_error = 0 }
        foreach ($key in $expected.Keys) {
            $property = $result.PSObject.Properties[$key]
            Assert-Portable ($null -ne $property -and $property.Value -eq $expected[$key]) "Offline workflow '$($variant.Name)' expected $key=$($expected[$key]); found '$($property.Value)'."
        }
        Assert-Portable ($result.PSObject.Properties['hardware_access'] -and $result.hardware_access -eq $false) "Offline workflow '$($variant.Name)' did not confirm hardware_access=false."
        foreach ($key in @('errors', 'error', 'error_count', 'errors_count')) {
            $property = $result.PSObject.Properties[$key]
            if ($null -eq $property -or $null -eq $property.Value) { continue }
            $value = $property.Value
            $hasErrors = if ($value -is [array]) { $value.Count -gt 0 } elseif ($value -is [bool]) { $value } elseif ($value -is [ValueType]) { $value -ne 0 } else { -not [string]::IsNullOrWhiteSpace([string]$value) }
            Assert-Portable (-not $hasErrors) "Offline workflow '$($variant.Name)' reports errors in '$key'."
        }
        $result | Add-Member -NotePropertyName variant -NotePropertyValue $variant.Name -Force
        [IO.File]::WriteAllText($resultOutput, ($result | ConvertTo-Json -Depth 8), [System.Text.UTF8Encoding]::new($false))
        Write-Host ("PASS offline {0}: 80 frames, 8 blank, 72 commands, max error 0." -f $variant.Name)
    }

    Write-Host "PASS portable package check. Logs and per-variant results: $logs"
    exit 0
} catch {
    [Console]::Error.WriteLine('FAIL portable package check: ' + $_.Exception.Message)
    exit 1
}

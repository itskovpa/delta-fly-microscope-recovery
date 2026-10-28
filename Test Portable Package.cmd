@echo off
setlocal
pushd "%~dp0"
if errorlevel 1 (
    echo Could not open the Recovery folder.
    pause
    exit /b 1
)

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Test-Portable.ps1"
set "RESULT=%ERRORLEVEL%"
echo.
if "%RESULT%"=="0" (
    echo Portable package check passed.
) else (
    echo Portable package check failed with exit code %RESULT%.
)
popd
pause
exit /b %RESULT%

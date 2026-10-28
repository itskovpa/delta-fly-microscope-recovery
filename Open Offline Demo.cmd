@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Open-Offline-Demo.ps1"
if errorlevel 1 pause

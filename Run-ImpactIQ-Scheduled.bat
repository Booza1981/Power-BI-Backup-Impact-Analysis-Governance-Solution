@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Run-ImpactIQ-Scheduled.ps1"
exit /b %ERRORLEVEL%

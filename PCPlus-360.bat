@echo off
:: PC Plus Computing 360 Diagnostic Suite Launcher
:: Double-click this file to run the diagnostic tool
powershell.exe -STA -NoProfile -ExecutionPolicy Bypass -File "%~dp0PCPlus-360.ps1"
pause

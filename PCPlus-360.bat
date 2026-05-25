@echo off
:: PC Plus Computing 360 Diagnostic Suite Launcher
:: Double-click this file to run the diagnostic tool
powershell.exe -STA -NoProfile -ExecutionPolicy Bypass -File "%~dp0PCPlus-360.ps1"
if %ERRORLEVEL% neq 0 (
    echo.
    echo ERROR: Script exited with error code %ERRORLEVEL%
    echo Check PCPlus360-debug.log for details.
    echo.
    pause
)

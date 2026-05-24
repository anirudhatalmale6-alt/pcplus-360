@echo off
:: PC Plus Computing - Desktop Badge (BGInfo-style) Launcher
:: Applies a branded info overlay to the customer's desktop wallpaper
::
:: Usage:
::   PCPlus-DesktopBadge.bat                  - Install badge
::   PCPlus-DesktopBadge.bat remove           - Remove badge and restore wallpaper
::   PCPlus-DesktopBadge.bat "Customer Name"  - Install with customer name
::

set "SCRIPT=%~dp0PCPlus-DesktopBadge.ps1"

if /i "%~1"=="remove" (
    powershell.exe -STA -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -Remove
) else if not "%~1"=="" (
    powershell.exe -STA -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -CustomerName "%~1"
) else (
    powershell.exe -STA -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%"
)
pause

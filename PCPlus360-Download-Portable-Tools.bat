@echo off
title PC Plus 360 - Portable Tools Downloader
echo.
echo   PC Plus 360 - Portable Tools Downloader
echo   PC Plus Computing ^| 604-760-1662 ^| 236-500-2700
echo.
echo   This will download portable diagnostic tools to C:\PCPlus360\Tools
echo   Some tools may trigger antivirus alerts - this is normal for security tools.
echo.
echo   To include password recovery tools, add: -IncludePasswordTools
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0PCPlus360-Download-Portable-Tools.ps1" %*
pause

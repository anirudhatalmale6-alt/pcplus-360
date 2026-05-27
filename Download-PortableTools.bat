@echo off
title PC Plus 360 - Portable Tools Downloader
echo.
echo   PC Plus 360 - Portable Tools Downloader
echo   PC Plus Computing ^| 604-760-1662 ^| 236-500-2700
echo.
echo   Launching PowerShell script...
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Download-PortableTools.ps1" %*

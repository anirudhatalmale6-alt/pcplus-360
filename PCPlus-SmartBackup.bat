@echo off
title PC Plus Computing 360 - Smart Backup ^& Restore
cd /d "%~dp0"
PowerShell.exe -ExecutionPolicy Bypass -File "%~dp0PCPlus-SmartBackup.ps1" %*

@echo off
:: PC Plus Computing - Hardware & Security Audit Launcher
powershell.exe -STA -NoProfile -ExecutionPolicy Bypass -File "%~dp0PCPlus-SecurityAudit.ps1"
pause

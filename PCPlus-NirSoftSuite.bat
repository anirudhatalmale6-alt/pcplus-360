@echo off
:: PC Plus Computing - NirSoft Portable Tools Suite
echo.
echo ============================================================
echo  PC PLUS 360 - NIRSOFT PORTABLE TOOLS SUITE
echo ============================================================
echo.
echo Place NirSoft .exe files in: tools\nirsoft\
echo.
set /p CUST="Customer Name: "
if "%CUST%"=="" set CUST=Customer
set /p TECH="Technician Name: "
if "%TECH%"=="" set TECH=PC Plus Technician
echo.
set /p PRIVACY="Include browser history/activity? (Y/N) [N]: "
if /i "%PRIVACY%"=="Y" (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0PCPlus-NirSoftSuite.ps1" -CustomerName "%CUST%" -TechnicianName "%TECH%" -IncludeBrowserHistory -IncludeLastActivity
) else (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0PCPlus-NirSoftSuite.ps1" -CustomerName "%CUST%" -TechnicianName "%TECH%"
)
pause

@echo off
:: PC Plus Computing - Wear & Tear Life Report Launcher
echo.
echo ============================================================
echo  PC PLUS 360 - WEAR ^& TEAR LIFE REPORT
echo ============================================================
echo.
echo This report analyzes storage health, battery wear, thermal
echo history, and component aging to forecast remaining lifespan.
echo.
set /p CUST="Customer Name: "
if "%CUST%"=="" set CUST=Customer
set /p TECH="Technician Name: "
if "%TECH%"=="" set TECH=PC Plus Technician
echo.
set /p JSON="Export JSON for ReportCard? (Y/N) [N]: "
if /i "%JSON%"=="Y" (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0PCPlus360-Wear-And-Tear-Life-Report.ps1" -CustomerName "%CUST%" -TechnicianName "%TECH%" -OpenReport -JsonOutput
) else (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0PCPlus360-Wear-And-Tear-Life-Report.ps1" -CustomerName "%CUST%" -TechnicianName "%TECH%" -OpenReport
)
echo.
echo Report complete. Press any key to exit...
set /p _=

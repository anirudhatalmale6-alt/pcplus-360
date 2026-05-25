@echo off
:: PC Plus Computing - Advanced RAM Isolation Test Launcher
echo.
echo ============================================================
echo  PC PLUS 360 - ADVANCED RAM ISOLATION TEST
echo ============================================================
echo.
set /p MODE="Select mode (Quick/Standard/Deep) [Standard]: "
if "%MODE%"=="" set MODE=Standard
set /p CUST="Customer Name: "
if "%CUST%"=="" set CUST=Customer
set /p TECH="Technician Name: "
if "%TECH%"=="" set TECH=PC Plus Technician
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0PCPlus-RAMIsolation.ps1" -Mode %MODE% -CustomerName "%CUST%" -TechnicianName "%TECH%"
pause

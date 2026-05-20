@echo off
:: PC Plus Computing - Deep Windows Performance & Integrity Test
echo.
echo ============================================================
echo  PC PLUS 360 - DEEP WINDOWS PERFORMANCE ^& INTEGRITY TEST
echo ============================================================
echo.
echo Modes:
echo   Quick    - Basic checks (5 min)
echo   Standard - Full scan with SFC/DISM/CHKDSK (15-20 min)
echo   Deep     - Extended scan with 90-day event history (20-30 min)
echo.
set /p MODE="Select mode (Quick/Standard/Deep) [Standard]: "
if "%MODE%"=="" set MODE=Standard
set /p CUST="Customer Name: "
if "%CUST%"=="" set CUST=Customer
set /p TECH="Technician Name: "
if "%TECH%"=="" set TECH=PC Plus Technician
echo.
set /p REPAIR="Run repair mode? (Y/N) [N]: "
if /i "%REPAIR%"=="Y" (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0PCPlus-WindowsDeepTest.ps1" -Mode %MODE% -CustomerName "%CUST%" -TechnicianName "%TECH%" -RunRepair
) else (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0PCPlus-WindowsDeepTest.ps1" -Mode %MODE% -CustomerName "%CUST%" -TechnicianName "%TECH%"
)
pause

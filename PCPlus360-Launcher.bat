@echo off
:: PC Plus Computing 360 - Dashboard Launcher
:: Launches the WebView2 dashboard (the new UI)
::
:: If the compiled exe exists, runs it directly.
:: Otherwise falls back to building from source.

set "EXEPATH=%~dp0Launcher\dist\PCPlus360Launcher.exe"

if exist "%EXEPATH%" (
    start "" "%EXEPATH%"
    exit /b 0
)

:: Try alternative locations
set "EXEPATH2=%~dp0Launcher\publish\PCPlus360Launcher.exe"
if exist "%EXEPATH2%" (
    start "" "%EXEPATH2%"
    exit /b 0
)

:: Exe not found - try to build
echo PC Plus 360 Dashboard Launcher not found.
echo.
echo Attempting to build from source...
echo (Requires .NET 8 SDK - https://dotnet.microsoft.com/download/dotnet/8.0)
echo.

dotnet --version >nul 2>&1
if errorlevel 1 (
    echo ERROR: .NET 8 SDK not installed.
    echo.
    echo Option 1: Install .NET 8 SDK and run this again
    echo Option 2: Download pre-built exe from GitHub Actions
    echo Option 3: Run the classic launcher: PCPlus-360.bat
    echo.
    pause
    exit /b 1
)

pushd "%~dp0Launcher"
call build.bat
popd

if exist "%~dp0Launcher\dist\PCPlus360Launcher.exe" (
    echo.
    echo Build successful! Launching...
    start "" "%~dp0Launcher\dist\PCPlus360Launcher.exe"
) else (
    echo.
    echo Build failed. Use the classic launcher instead: PCPlus-360.bat
    pause
)

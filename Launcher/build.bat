@echo off
echo ============================================
echo   PC Plus 360 Launcher - Build Script
echo ============================================
echo.

:: Check for .NET SDK
dotnet --version >nul 2>&1
if errorlevel 1 (
    echo ERROR: .NET 8 SDK not found. Install from https://dotnet.microsoft.com/download/dotnet/8.0
    pause
    exit /b 1
)

echo [1/3] Restoring packages...
dotnet restore PCPlus360Launcher.sln
if errorlevel 1 (
    echo ERROR: Package restore failed.
    pause
    exit /b 1
)

echo.
echo [2/3] Publishing Release build...
dotnet publish PCPlus360Launcher\PCPlus360Launcher.csproj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -o dist
if errorlevel 1 (
    echo ERROR: Build failed.
    pause
    exit /b 1
)

echo.
echo [3/3] Build complete!
echo.
echo Output: dist\PCPlus360Launcher.exe
echo.
echo Place the exe so that ..\PCPlus360-Dashboard.html is accessible
echo relative to the exe location.
echo.
pause

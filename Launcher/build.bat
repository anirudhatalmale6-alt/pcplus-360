@echo off
echo ============================================
echo   PC Plus 360 Launcher - Build Script
echo ============================================
echo.

:: Always run from the Launcher directory regardless of where called from
pushd "%~dp0"

:: Check for .NET SDK
dotnet --version >nul 2>&1
if errorlevel 1 (
    echo ERROR: .NET SDK not found. Install from https://dotnet.microsoft.com/download/dotnet/8.0
    popd
    pause
    exit /b 1
)

echo [1/3] Restoring packages...
dotnet restore "%~dp0PCPlus360Launcher.sln"
if errorlevel 1 (
    echo ERROR: Package restore failed.
    popd
    pause
    exit /b 1
)

echo.
echo [2/3] Publishing Release build...
dotnet publish "%~dp0PCPlus360Launcher\PCPlus360Launcher.csproj" -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -o "%~dp0dist"
if errorlevel 1 (
    echo ERROR: Build failed.
    pause
    exit /b 1
)

echo.
echo [3/3] Build complete!
echo.
echo Output: %~dp0dist\PCPlus360Launcher.exe
echo.
popd
pause

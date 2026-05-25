<#
.SYNOPSIS
    PC Plus 360 - Customer Machine Cleanup / Uninstall
.DESCRIPTION
    Removes all PC Plus 360 artifacts from a customer's machine:
    - Desktop Badge (restores original wallpaper)
    - Reports folder (C:\PCPlus360)
    - Scheduled tasks created by PC Plus
    Designed to be run when a customer no longer wants PC Plus tools on their PC.
.NOTES
    Company:  PC Plus Computing
    Phone:    604-760-1662 | 236-500-2700
.EXAMPLE
    PowerShell.exe -ExecutionPolicy Bypass -File .\PCPlus-Cleanup.ps1
#>

$ErrorActionPreference = 'Continue'

trap {
    Write-Host ""
    Write-Host "  UNEXPECTED ERROR: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "  Line: $($_.InvocationInfo.ScriptLineNumber)" -ForegroundColor DarkGray
    Write-Host ""
    Read-Host "  Press Enter to exit"
    break
}

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-IsAdmin)) {
    try {
        Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$($MyInvocation.MyCommand.Definition)`"" -Verb RunAs
    } catch {
        Write-Host "  ERROR: Administrator privileges required." -ForegroundColor Red
        Read-Host "  Press Enter to exit"
    }
    exit
}

Clear-Host
Write-Host ""
Write-Host "  ╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "  ║                                                              ║" -ForegroundColor Cyan
Write-Host "  ║     PC Plus 360 - Customer Machine Cleanup                   ║" -ForegroundColor Cyan
Write-Host "  ║     PC Plus Computing | 604-760-1662                         ║" -ForegroundColor Cyan
Write-Host "  ║                                                              ║" -ForegroundColor Cyan
Write-Host "  ╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""
Write-Host "  This will remove all PC Plus 360 artifacts from this computer:" -ForegroundColor White
Write-Host "    - Desktop Badge (restore original wallpaper)" -ForegroundColor Gray
Write-Host "    - Reports folder (C:\PCPlus360)" -ForegroundColor Gray
Write-Host "    - RAM Isolation data (C:\PCPlus360\RAM-Isolation)" -ForegroundColor Gray
Write-Host "    - Scheduled tasks (PC Plus badge refresh)" -ForegroundColor Gray
Write-Host ""

$confirm = Read-Host "  Type YES to proceed with cleanup"
if ($confirm -ne "YES") {
    Write-Host ""
    Write-Host "  Cleanup cancelled." -ForegroundColor Yellow
    Read-Host "  Press Enter to exit"
    exit
}

Write-Host ""
$removed = 0

# 1. Remove Desktop Badge
Write-Host "  [1/4] Desktop Badge..." -ForegroundColor Cyan -NoNewline
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$badgeScript = Join-Path $ScriptDir "PCPlus-DesktopBadge.ps1"
if (Test-Path $badgeScript) {
    try {
        & $badgeScript -Remove -Silent
        Write-Host " Removed" -ForegroundColor Green
        $removed++
    } catch {
        Write-Host " Error: $($_.Exception.Message)" -ForegroundColor Red
    }
} else {
    # Manual badge removal
    $badgePath = "$env:APPDATA\PCPlus360\badge-wallpaper.bmp"
    $backupPath = "$env:APPDATA\PCPlus360\original-wallpaper-path.txt"
    if (Test-Path $backupPath) {
        try {
            $originalPath = Get-Content $backupPath -Raw
            $originalPath = $originalPath.Trim()
            Add-Type -TypeDefinition @"
using System.Runtime.InteropServices;
public class WallpaperHelper {
    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern int SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
}
"@
            [WallpaperHelper]::SystemParametersInfo(0x0014, 0, $originalPath, 0x01 -bor 0x02) | Out-Null
            Remove-Item $badgePath -Force -ErrorAction SilentlyContinue
            Remove-Item $backupPath -Force -ErrorAction SilentlyContinue
            Write-Host " Removed" -ForegroundColor Green
            $removed++
        } catch {
            Write-Host " Error: $($_.Exception.Message)" -ForegroundColor Red
        }
    } else {
        Write-Host " Not installed" -ForegroundColor DarkGray
    }
}

# 2. Remove scheduled tasks
Write-Host "  [2/4] Scheduled tasks..." -ForegroundColor Cyan -NoNewline
$taskNames = @("PCPlus360-BadgeRefresh", "PCPlus360-Badge-WallpaperWatch")
$taskRemoved = 0
foreach ($tn in $taskNames) {
    try {
        $task = Get-ScheduledTask -TaskName $tn -ErrorAction SilentlyContinue
        if ($task) {
            Unregister-ScheduledTask -TaskName $tn -Confirm:$false -ErrorAction Stop
            $taskRemoved++
        }
    } catch {}
}
if ($taskRemoved -gt 0) {
    Write-Host " Removed $taskRemoved task(s)" -ForegroundColor Green
    $removed++
} else {
    Write-Host " None found" -ForegroundColor DarkGray
}

# 3. Remove reports folder
Write-Host "  [3/4] Reports & data (C:\PCPlus360)..." -ForegroundColor Cyan -NoNewline
if (Test-Path "C:\PCPlus360") {
    try {
        Remove-Item "C:\PCPlus360" -Recurse -Force -ErrorAction Stop
        Write-Host " Removed" -ForegroundColor Green
        $removed++
    } catch {
        Write-Host " Error: $($_.Exception.Message)" -ForegroundColor Red
    }
} else {
    Write-Host " Not found" -ForegroundColor DarkGray
}

# 4. Remove AppData folder
Write-Host "  [4/4] App data ($env:APPDATA\PCPlus360)..." -ForegroundColor Cyan -NoNewline
$appDataDir = "$env:APPDATA\PCPlus360"
if (Test-Path $appDataDir) {
    try {
        Remove-Item $appDataDir -Recurse -Force -ErrorAction Stop
        Write-Host " Removed" -ForegroundColor Green
        $removed++
    } catch {
        Write-Host " Error: $($_.Exception.Message)" -ForegroundColor Red
    }
} else {
    Write-Host " Not found" -ForegroundColor DarkGray
}

Write-Host ""
Write-Host ("=" * 60) -ForegroundColor Cyan
if ($removed -gt 0) {
    Write-Host "  Cleanup complete. $removed item(s) removed." -ForegroundColor Green
} else {
    Write-Host "  Nothing to clean up - PC Plus 360 was not installed on this machine." -ForegroundColor Yellow
}
Write-Host ("=" * 60) -ForegroundColor Cyan
Write-Host ""

Read-Host "  Press Enter to exit"

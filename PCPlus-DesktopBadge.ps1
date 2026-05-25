param(
    [switch]$Remove,
    [switch]$Silent,
    [string]$CustomerName,
    [string]$TechPhone   = "604-760-1662",
    [string]$TechEmail   = "pcpluscomputing@gmail.com",
    [string]$Website     = "www.pcpluscomputing.com"
)

<#
.SYNOPSIS
    PC Plus Computing - Desktop Info Badge (BGInfo-style)
.DESCRIPTION
    Creates a branded "PC Plus Computing Support" information overlay on the
    customer's desktop wallpaper, similar to Sysinternals BGInfo but with
    PC Plus branding. Shows support contact info and live system details
    (computer name, IP address) in a semi-transparent badge on the bottom-right
    corner of the desktop.
.PARAMETER Remove
    Restores the original wallpaper and removes the scheduled refresh task.
.PARAMETER Silent
    Suppresses all console output (for scheduled task / unattended use).
.PARAMETER CustomerName
    Optional customer name to display on the badge.
.PARAMETER TechPhone
    Support phone number displayed on the badge.
.PARAMETER TechEmail
    Support email displayed on the badge.
.PARAMETER Website
    Company website displayed on the badge.
.NOTES
    Company:  PC Plus Computing
    Website:  pcpluscomputing.com
    Phone:    604-760-1662
    Version:  2.0.0
    Requires: PowerShell 5.1+, Windows 10/11
#>

#Requires -Version 5.1
$ErrorActionPreference = 'Continue'

# ─────────────────────────────────────────────────────────────────────────────
# ASSEMBLIES
# ─────────────────────────────────────────────────────────────────────────────
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

# ─────────────────────────────────────────────────────────────────────────────
# P/INVOKE - Set wallpaper via Win32 API
# ─────────────────────────────────────────────────────────────────────────────
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class WallpaperHelper {
    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern int SystemParametersInfo(
        int uAction, int uParam, string lpvParam, int fuWinIni);

    public const int SPI_SETDESKWALLPAPER = 0x0014;
    public const int SPIF_UPDATEINIFILE   = 0x01;
    public const int SPIF_SENDCHANGE      = 0x02;

    public static void SetWallpaper(string path) {
        SystemParametersInfo(SPI_SETDESKWALLPAPER, 0, path,
            SPIF_UPDATEINIFILE | SPIF_SENDCHANGE);
    }
}
"@

# ─────────────────────────────────────────────────────────────────────────────
# PATHS & CONSTANTS
# ─────────────────────────────────────────────────────────────────────────────
$AppDataDir        = Join-Path $env:LOCALAPPDATA "PCPlus"
$BackupFile        = Join-Path $AppDataDir "pcplus-original-wallpaper.bak"
$BadgeWallpaper    = Join-Path $AppDataDir "pcplus-desktop-badge.bmp"
$TaskName          = "PCPlusSystemMaintenance"
$WatcherTaskName   = "PCPlusDisplayCalibration"

$COLOR_BG_R        = 245; $COLOR_BG_G = 247; $COLOR_BG_B = 250   # Light gray bg
$COLOR_BG_ALPHA    = 180                                          # Semi-transparent
$COLOR_TEXT         = [System.Drawing.Color]::FromArgb(255, 26, 43, 60)   # #1a2b3c
$COLOR_ACCENT      = [System.Drawing.Color]::FromArgb(255, 37, 150, 190) # #2596be
$COLOR_SEPARATOR    = [System.Drawing.Color]::FromArgb(200, 180, 190, 200)

$BADGE_WIDTH       = 300
$BADGE_PADDING     = 16
$BADGE_MARGIN      = 30   # Distance from screen edges
$CORNER_RADIUS     = 12

# ─────────────────────────────────────────────────────────────────────────────
# DEBUG LOGGING
# ─────────────────────────────────────────────────────────────────────────────
$LogFile = Join-Path $AppDataDir "desktop-badge.log"

function Write-DebugLog {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "[$timestamp] $Message"
    try {
        if (-not (Test-Path $AppDataDir)) {
            New-Item -Path $AppDataDir -ItemType Directory -Force | Out-Null
        }
        Add-Content -Path $LogFile -Value $entry -ErrorAction SilentlyContinue
    } catch { }
    if (-not $Silent) {
        Write-Host $entry
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# HELPER: Draw a filled rounded rectangle (GDI+)
# ─────────────────────────────────────────────────────────────────────────────
function New-RoundedRectPath {
    param(
        [System.Drawing.RectangleF]$Rect,
        [int]$Radius
    )
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d = $Radius * 2

    # Top-left arc
    $path.AddArc($Rect.X, $Rect.Y, $d, $d, 180, 90)
    # Top edge
    $path.AddLine($Rect.X + $Radius, $Rect.Y, $Rect.Right - $Radius, $Rect.Y)
    # Top-right arc
    $path.AddArc($Rect.Right - $d, $Rect.Y, $d, $d, 270, 90)
    # Right edge
    $path.AddLine($Rect.Right, $Rect.Y + $Radius, $Rect.Right, $Rect.Bottom - $Radius)
    # Bottom-right arc
    $path.AddArc($Rect.Right - $d, $Rect.Bottom - $d, $d, $d, 0, 90)
    # Bottom edge
    $path.AddLine($Rect.Right - $Radius, $Rect.Bottom, $Rect.X + $Radius, $Rect.Bottom)
    # Bottom-left arc
    $path.AddArc($Rect.X, $Rect.Bottom - $d, $d, $d, 90, 90)
    # Left edge
    $path.AddLine($Rect.X, $Rect.Bottom - $Radius, $Rect.X, $Rect.Y + $Radius)

    $path.CloseFigure()
    return $path
}

# ─────────────────────────────────────────────────────────────────────────────
# HELPER: Get current wallpaper path from registry
# ─────────────────────────────────────────────────────────────────────────────
function Get-CurrentWallpaperPath {
    try {
        $regPath = "HKCU:\Control Panel\Desktop"
        $wp = (Get-ItemProperty -Path $regPath -Name Wallpaper -ErrorAction Stop).Wallpaper
        if ($wp -and (Test-Path $wp)) {
            return $wp
        }
    } catch { }
    return $null
}

# ─────────────────────────────────────────────────────────────────────────────
# HELPER: Get wallpaper style from registry
# ─────────────────────────────────────────────────────────────────────────────
function Get-WallpaperStyle {
    try {
        $regPath = "HKCU:\Control Panel\Desktop"
        $style = (Get-ItemProperty -Path $regPath -Name WallpaperStyle -ErrorAction SilentlyContinue).WallpaperStyle
        $tile  = (Get-ItemProperty -Path $regPath -Name TileWallpaper -ErrorAction SilentlyContinue).TileWallpaper
        return @{ Style = $style; Tile = $tile }
    } catch {
        return @{ Style = "10"; Tile = "0" }  # Default: Fill
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# HELPER: Preserve wallpaper style in registry
# ─────────────────────────────────────────────────────────────────────────────
function Set-WallpaperStyle {
    param([hashtable]$StyleInfo)
    try {
        $regPath = "HKCU:\Control Panel\Desktop"
        Set-ItemProperty -Path $regPath -Name WallpaperStyle -Value $StyleInfo.Style -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $regPath -Name TileWallpaper -Value $StyleInfo.Tile -ErrorAction SilentlyContinue
    } catch {
        Write-DebugLog "WARNING: Could not preserve wallpaper style: $_"
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# HELPER: Get primary monitor resolution
# ─────────────────────────────────────────────────────────────────────────────
function Get-PrimaryScreenSize {
    $screen = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    return @{ Width = $screen.Width; Height = $screen.Height }
}

# ─────────────────────────────────────────────────────────────────────────────
# HELPER: Get system information for the badge
# ─────────────────────────────────────────────────────────────────────────────
function Get-BadgeSystemInfo {
    $info = @{
        ComputerName = $env:COMPUTERNAME
        UserName     = $env:USERNAME
        IPAddress    = "Unknown"
    }

    # Get primary IPv4 address (skip loopback, link-local, APIPA)
    try {
        $adapters = [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces()
        foreach ($adapter in $adapters) {
            if ($adapter.OperationalStatus -ne 'Up') { continue }
            if ($adapter.NetworkInterfaceType -eq 'Loopback') { continue }
            $props = $adapter.GetIPProperties()
            foreach ($addr in $props.UnicastAddresses) {
                if ($addr.Address.AddressFamily -eq 'InterNetwork') {
                    $ip = $addr.Address.ToString()
                    if (-not $ip.StartsWith("169.254.") -and $ip -ne "127.0.0.1") {
                        $info.IPAddress = $ip
                        break
                    }
                }
            }
            if ($info.IPAddress -ne "Unknown") { break }
        }
    } catch {
        # Fallback
        try {
            $ip = (Get-NetIPAddress -AddressFamily IPv4 -InterfaceAlias "Ethernet*","Wi-Fi*" -ErrorAction SilentlyContinue |
                   Where-Object { $_.IPAddress -notlike "169.254.*" } |
                   Select-Object -First 1).IPAddress
            if ($ip) { $info.IPAddress = $ip }
        } catch { }
    }

    return $info
}

# ─────────────────────────────────────────────────────────────────────────────
# HELPER: Scale badge dimensions for high-DPI / large screens
# ─────────────────────────────────────────────────────────────────────────────
function Get-ScaledBadgeWidth {
    param([int]$ScreenWidth)
    # Base: 300px at 1920 width. Scale proportionally, clamp 250-450.
    $scaled = [math]::Round(300 * ($ScreenWidth / 1920.0))
    return [math]::Max(250, [math]::Min(450, $scaled))
}

# ─────────────────────────────────────────────────────────────────────────────
# HELPER: Back up original wallpaper
# ─────────────────────────────────────────────────────────────────────────────
function Backup-OriginalWallpaper {
    if (-not (Test-Path $AppDataDir)) {
        New-Item -Path $AppDataDir -ItemType Directory -Force | Out-Null
    }

    # Don't overwrite an existing backup (so we always keep the true original)
    if (Test-Path $BackupFile) {
        Write-DebugLog "Backup already exists at $BackupFile - keeping original."
        return
    }

    $currentWP = Get-CurrentWallpaperPath
    $styleInfo = Get-WallpaperStyle

    # Save wallpaper path + style info
    $backupData = @{
        WallpaperPath  = if ($currentWP) { $currentWP } else { "" }
        WallpaperStyle = $styleInfo.Style
        TileWallpaper  = $styleInfo.Tile
        BackupDate     = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    }

    $backupData | ConvertTo-Json | Set-Content -Path $BackupFile -Force
    # Hide the backup file
    try {
        (Get-Item $BackupFile).Attributes = 'Hidden'
    } catch { }

    Write-DebugLog "Original wallpaper backed up to $BackupFile"
}

# ─────────────────────────────────────────────────────────────────────────────
# CORE: Create the badge overlay on the wallpaper
# ─────────────────────────────────────────────────────────────────────────────
function New-DesktopBadge {
    Write-DebugLog "Starting badge creation..."

    # Ensure output directory exists
    if (-not (Test-Path $AppDataDir)) {
        New-Item -Path $AppDataDir -ItemType Directory -Force | Out-Null
    }

    # Back up the original wallpaper
    Backup-OriginalWallpaper

    # Get screen size
    $screen = Get-PrimaryScreenSize
    $screenW = $screen.Width
    $screenH = $screen.Height
    Write-DebugLog "Primary screen: ${screenW}x${screenH}"

    # Scale badge
    $badgeW = Get-ScaledBadgeWidth -ScreenWidth $screenW
    $scaleFactor = $badgeW / 300.0

    # Get wallpaper image or create blank canvas
    $wallpaperPath = $null
    $bitmap = $null

    # Check backup for original path (avoid stamping over our own badge)
    if (Test-Path $BackupFile) {
        try {
            $backupData = Get-Content $BackupFile -Raw | ConvertFrom-Json
            if ($backupData.WallpaperPath -and (Test-Path $backupData.WallpaperPath)) {
                $wallpaperPath = $backupData.WallpaperPath
            }
        } catch { }
    }

    # If no backup, get current wallpaper
    if (-not $wallpaperPath) {
        $wallpaperPath = Get-CurrentWallpaperPath
    }

    if ($wallpaperPath -and (Test-Path $wallpaperPath)) {
        Write-DebugLog "Loading wallpaper from: $wallpaperPath"
        try {
            # Load image into memory so we don't lock the file
            $bytes = [System.IO.File]::ReadAllBytes($wallpaperPath)
            $ms = New-Object System.IO.MemoryStream(,$bytes)
            $srcImage = [System.Drawing.Image]::FromStream($ms)

            # Create bitmap matching screen resolution
            $bitmap = New-Object System.Drawing.Bitmap($screenW, $screenH)
            $g = [System.Drawing.Graphics]::FromImage($bitmap)
            $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias

            # Determine how to draw based on wallpaper style
            $styleInfo = Get-WallpaperStyle
            $wpStyle = $styleInfo.Style
            $wpTile  = $styleInfo.Tile

            # Fill background with black first
            $g.Clear([System.Drawing.Color]::Black)

            switch ($wpStyle) {
                "10" {
                    # Fill - scale to fill, crop excess
                    $ratioX = $screenW / $srcImage.Width
                    $ratioY = $screenH / $srcImage.Height
                    $ratio  = [math]::Max($ratioX, $ratioY)
                    $newW   = [math]::Round($srcImage.Width * $ratio)
                    $newH   = [math]::Round($srcImage.Height * $ratio)
                    $x      = [math]::Round(($screenW - $newW) / 2)
                    $y      = [math]::Round(($screenH - $newH) / 2)
                    $g.DrawImage($srcImage, $x, $y, $newW, $newH)
                }
                "6" {
                    # Fit - scale to fit, letterbox
                    $ratioX = $screenW / $srcImage.Width
                    $ratioY = $screenH / $srcImage.Height
                    $ratio  = [math]::Min($ratioX, $ratioY)
                    $newW   = [math]::Round($srcImage.Width * $ratio)
                    $newH   = [math]::Round($srcImage.Height * $ratio)
                    $x      = [math]::Round(($screenW - $newW) / 2)
                    $y      = [math]::Round(($screenH - $newH) / 2)
                    $g.DrawImage($srcImage, $x, $y, $newW, $newH)
                }
                "2" {
                    # Stretch - stretch to fill exactly
                    $g.DrawImage($srcImage, 0, 0, $screenW, $screenH)
                }
                "0" {
                    if ($wpTile -eq "1") {
                        # Tile
                        for ($ty = 0; $ty -lt $screenH; $ty += $srcImage.Height) {
                            for ($tx = 0; $tx -lt $screenW; $tx += $srcImage.Width) {
                                $g.DrawImage($srcImage, $tx, $ty, $srcImage.Width, $srcImage.Height)
                            }
                        }
                    } else {
                        # Center
                        $x = [math]::Round(($screenW - $srcImage.Width) / 2)
                        $y = [math]::Round(($screenH - $srcImage.Height) / 2)
                        $g.DrawImage($srcImage, $x, $y, $srcImage.Width, $srcImage.Height)
                    }
                }
                "22" {
                    # Span (multi-monitor) - treat same as Fill for primary
                    $ratioX = $screenW / $srcImage.Width
                    $ratioY = $screenH / $srcImage.Height
                    $ratio  = [math]::Max($ratioX, $ratioY)
                    $newW   = [math]::Round($srcImage.Width * $ratio)
                    $newH   = [math]::Round($srcImage.Height * $ratio)
                    $x      = [math]::Round(($screenW - $newW) / 2)
                    $y      = [math]::Round(($screenH - $newH) / 2)
                    $g.DrawImage($srcImage, $x, $y, $newW, $newH)
                }
                default {
                    # Default: Fill
                    $ratioX = $screenW / $srcImage.Width
                    $ratioY = $screenH / $srcImage.Height
                    $ratio  = [math]::Max($ratioX, $ratioY)
                    $newW   = [math]::Round($srcImage.Width * $ratio)
                    $newH   = [math]::Round($srcImage.Height * $ratio)
                    $x      = [math]::Round(($screenW - $newW) / 2)
                    $y      = [math]::Round(($screenH - $newH) / 2)
                    $g.DrawImage($srcImage, $x, $y, $newW, $newH)
                }
            }

            $g.Dispose()
            $srcImage.Dispose()
            $ms.Dispose()
        } catch {
            Write-DebugLog "ERROR loading wallpaper: $_ - creating blank canvas"
            if ($bitmap) { $bitmap.Dispose(); $bitmap = $null }
        }
    }

    # If no wallpaper or loading failed, create a solid-color canvas
    if (-not $bitmap) {
        Write-DebugLog "No wallpaper found - creating solid color canvas"
        $bitmap = New-Object System.Drawing.Bitmap($screenW, $screenH)
        $g = [System.Drawing.Graphics]::FromImage($bitmap)
        # Use Windows default blue-ish background
        $g.Clear([System.Drawing.Color]::FromArgb(255, 0, 120, 215))
        $g.Dispose()
    }

    # ── Gather system info ──
    $sysInfo = Get-BadgeSystemInfo
    Write-DebugLog "System: $($sysInfo.ComputerName) / $($sysInfo.IPAddress)"

    # ── Build the badge text lines ──
    $titleText = "PC Plus Computing Support"

    $lines = @(
        @{ Prefix = "Tel:";       Value = $TechPhone },
        @{ Prefix = "Email:";     Value = $TechEmail },
        @{ Prefix = "";           Value = "" },
        @{ Prefix = "Computer:";  Value = $sysInfo.ComputerName },
        @{ Prefix = "IP:";        Value = $sysInfo.IPAddress }
    )

    if ($CustomerName) {
        $lines += @{ Prefix = "Customer:"; Value = $CustomerName }
    }

    $lines += @{ Prefix = "Status:";   Value = "Protected by PC Plus Computing" }
    $lines += @{ Prefix = "Web:";      Value = $Website }

    # ── Create fonts ──
    $fontFamily  = "Segoe UI"
    $titleSize   = [math]::Round(13 * $scaleFactor)
    $contentSize = [math]::Round(10 * $scaleFactor)
    $prefixSize  = [math]::Round(10 * $scaleFactor)

    $fontTitle   = New-Object System.Drawing.Font($fontFamily, $titleSize, [System.Drawing.FontStyle]::Bold)
    $fontContent = New-Object System.Drawing.Font($fontFamily, $contentSize, [System.Drawing.FontStyle]::Regular)
    $fontPrefix  = New-Object System.Drawing.Font($fontFamily, $prefixSize, [System.Drawing.FontStyle]::Bold)

    # ── Measure text to calculate badge height ──
    $tempG = [System.Drawing.Graphics]::FromImage($bitmap)

    $titleMeasure = $tempG.MeasureString($titleText, $fontTitle)
    $lineHeight   = $tempG.MeasureString("Xg", $fontContent).Height
    $sepHeight    = 8 * $scaleFactor  # separator line area

    # Calculate total badge height
    $contentAreaW = $badgeW - (2 * $BADGE_PADDING)
    $totalH = $BADGE_PADDING                     # top padding
    $totalH += $titleMeasure.Height               # title
    $totalH += $sepHeight                         # separator
    $totalH += ($BADGE_PADDING * 0.5)             # gap after separator

    foreach ($line in $lines) {
        if ($line.Value -eq "" -and $line.Prefix -eq "") {
            $totalH += ($lineHeight * 0.4)         # blank line (smaller gap)
        } else {
            # Check if the value will wrap
            $fullText = if ($line.Prefix) { "$($line.Prefix) $($line.Value)" } else { $line.Value }
            $textMeasure = $tempG.MeasureString($fullText, $fontContent, [int]$contentAreaW)
            $totalH += $textMeasure.Height + 2
        }
    }

    $totalH += $BADGE_PADDING                     # bottom padding
    $badgeH = [math]::Ceiling($totalH)

    $tempG.Dispose()

    # ── Position badge in bottom-right ──
    $margin = [math]::Round($BADGE_MARGIN * $scaleFactor)
    $badgeX = $screenW - $badgeW - $margin
    $badgeY = $screenH - $badgeH - $margin - 40   # 40px above taskbar

    # ── Draw the badge ──
    $g = [System.Drawing.Graphics]::FromImage($bitmap)
    $g.SmoothingMode     = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic

    # Draw shadow (slightly offset, darker, more transparent)
    $shadowRect = New-Object System.Drawing.RectangleF(($badgeX + 3), ($badgeY + 3), $badgeW, $badgeH)
    $shadowPath = New-RoundedRectPath -Rect $shadowRect -Radius $CORNER_RADIUS
    $shadowBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(60, 0, 0, 0))
    $g.FillPath($shadowBrush, $shadowPath)
    $shadowBrush.Dispose()
    $shadowPath.Dispose()

    # Draw badge background (semi-transparent light gray)
    $badgeRect = New-Object System.Drawing.RectangleF($badgeX, $badgeY, $badgeW, $badgeH)
    $badgePath = New-RoundedRectPath -Rect $badgeRect -Radius $CORNER_RADIUS
    $bgBrush = New-Object System.Drawing.SolidBrush(
        [System.Drawing.Color]::FromArgb($COLOR_BG_ALPHA, $COLOR_BG_R, $COLOR_BG_G, $COLOR_BG_B)
    )
    $g.FillPath($bgBrush, $badgePath)
    $bgBrush.Dispose()

    # Draw subtle border
    $borderPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(100, 180, 190, 210), 1)
    $g.DrawPath($borderPen, $badgePath)
    $borderPen.Dispose()
    $badgePath.Dispose()

    # ── Draw title ──
    $textBrush   = New-Object System.Drawing.SolidBrush($COLOR_TEXT)
    $accentBrush = New-Object System.Drawing.SolidBrush($COLOR_ACCENT)

    $curY = $badgeY + $BADGE_PADDING
    $curX = $badgeX + $BADGE_PADDING

    # Accent bar on the left of the title
    $accentBarW = 3 * $scaleFactor
    $accentBarH = $titleMeasure.Height
    $g.FillRectangle($accentBrush, [float]$curX, [float]$curY, [float]$accentBarW, [float]$accentBarH)

    # Title text
    $titleX = $curX + $accentBarW + (6 * $scaleFactor)
    $g.DrawString($titleText, $fontTitle, $textBrush, [float]$titleX, [float]$curY)
    $curY += $titleMeasure.Height

    # Separator line
    $sepY = $curY + ($sepHeight / 2)
    $sepPen = New-Object System.Drawing.Pen($COLOR_SEPARATOR, 1)
    $g.DrawLine($sepPen, [float]$curX, [float]$sepY, [float]($badgeX + $badgeW - $BADGE_PADDING), [float]$sepY)
    $sepPen.Dispose()
    $curY += $sepHeight + ($BADGE_PADDING * 0.5)

    # ── Draw content lines ──
    $prefixBrush = New-Object System.Drawing.SolidBrush($COLOR_ACCENT)
    $sf = New-Object System.Drawing.StringFormat
    $sf.Trimming = [System.Drawing.StringTrimming]::EllipsisCharacter

    foreach ($line in $lines) {
        if ($line.Value -eq "" -and $line.Prefix -eq "") {
            # Blank spacer line
            $curY += ($lineHeight * 0.4)
            continue
        }

        $prefixText = $line.Prefix
        $valueText  = $line.Value

        if ($prefixText) {
            # Draw prefix in accent color (bold)
            $prefixMeasure = $g.MeasureString($prefixText, $fontPrefix)
            $g.DrawString($prefixText, $fontPrefix, $prefixBrush, [float]$curX, [float]$curY)

            # Draw value in dark text
            $valueX = $curX + $prefixMeasure.Width + (2 * $scaleFactor)
            $availW = ($badgeX + $badgeW - $BADGE_PADDING) - $valueX
            $layoutRect = New-Object System.Drawing.RectangleF($valueX, $curY, $availW, ($lineHeight * 2))
            $g.DrawString($valueText, $fontContent, $textBrush, $layoutRect, $sf)

            $textMeasure = $g.MeasureString("$prefixText $valueText", $fontContent, [int]$contentAreaW)
            $curY += $textMeasure.Height + 2
        } else {
            $g.DrawString($valueText, $fontContent, $textBrush, [float]$curX, [float]$curY)
            $curY += $lineHeight + 2
        }
    }

    # ── Cleanup drawing resources ──
    $textBrush.Dispose()
    $accentBrush.Dispose()
    $prefixBrush.Dispose()
    $sf.Dispose()
    $fontTitle.Dispose()
    $fontContent.Dispose()
    $fontPrefix.Dispose()
    $g.Dispose()

    # ── Save the badged wallpaper ──
    try {
        # Remove old badge file if it exists
        if (Test-Path $BadgeWallpaper) {
            Remove-Item $BadgeWallpaper -Force -ErrorAction SilentlyContinue
        }
        $bitmap.Save($BadgeWallpaper, [System.Drawing.Imaging.ImageFormat]::Bmp)
        try { (Get-Item $BadgeWallpaper).Attributes = 'Hidden,System' } catch { }
        Write-DebugLog "Badge wallpaper saved to: $BadgeWallpaper"
    } catch {
        Write-DebugLog "ERROR saving badge wallpaper: $_"
        $bitmap.Dispose()
        return $false
    }

    $bitmap.Dispose()

    # ── Set as wallpaper ──
    try {
        # Preserve the wallpaper style
        $styleInfo = Get-WallpaperStyle
        [WallpaperHelper]::SetWallpaper($BadgeWallpaper)
        # Force style to Stretch since we already composed at screen resolution
        Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name WallpaperStyle -Value "2"
        Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name TileWallpaper -Value "0"
        Write-DebugLog "Wallpaper set successfully."
    } catch {
        Write-DebugLog "ERROR setting wallpaper: $_"
        return $false
    }

    return $true
}

# ─────────────────────────────────────────────────────────────────────────────
# HELPER: Check if the current wallpaper is our badge file
# ─────────────────────────────────────────────────────────────────────────────
function Test-BadgeActive {
    $currentWP = Get-CurrentWallpaperPath
    if (-not $currentWP) { return $false }
    return ($currentWP -eq $BadgeWallpaper)
}

# ─────────────────────────────────────────────────────────────────────────────
# HELPER: Build the PowerShell arguments string for scheduled tasks
# ─────────────────────────────────────────────────────────────────────────────
function Get-BadgeTaskArguments {
    param([string]$ScriptPath)
    $argParts = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden", "-File", "`"$ScriptPath`"", "-Silent")
    if ($CustomerName) {
        $argParts += "-CustomerName"
        $argParts += "`"$CustomerName`""
    }
    if ($TechPhone -ne "604-760-1662") {
        $argParts += "-TechPhone"
        $argParts += "`"$TechPhone`""
    }
    if ($TechEmail -ne "pcpluscomputing@gmail.com") {
        $argParts += "-TechEmail"
        $argParts += "`"$TechEmail`""
    }
    if ($Website -ne "www.pcpluscomputing.com") {
        $argParts += "-Website"
        $argParts += "`"$Website`""
    }
    return ($argParts -join " ")
}

# ─────────────────────────────────────────────────────────────────────────────
# SCHEDULED TASKS: Persistent badge with wallpaper change protection
# ─────────────────────────────────────────────────────────────────────────────
function Register-BadgeRefreshTask {
    Write-DebugLog "Registering persistence tasks..."

    try {
        $scriptPath = $MyInvocation.ScriptName
        if (-not $scriptPath) { $scriptPath = $PSCommandPath }
        if (-not $scriptPath) {
            Write-DebugLog "WARNING: Could not determine script path - skipping tasks."
            return
        }

        $arguments = Get-BadgeTaskArguments -ScriptPath $scriptPath
        $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $arguments

        # --- Task 1: Logon + session unlock refresh ---
        $existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        if ($existing) {
            Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
        }

        $triggerLogon = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME

        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
                    -StartWhenAvailable -RunOnlyIfNetworkAvailable:$false -ExecutionTimeLimit (New-TimeSpan -Minutes 5)

        # Use CIM to add session unlock trigger (not available via New-ScheduledTaskTrigger)
        $cimTriggers = @()
        $cimTriggers += New-CimInstance -CimClass (Get-CimClass -Namespace "Root/Microsoft/Windows/TaskScheduler" `
                        -ClassName MSFT_TaskLogonTrigger) -ClientOnly -Property @{ UserId = $env:USERNAME; Enabled = $true }
        $cimTriggers += New-CimInstance -CimClass (Get-CimClass -Namespace "Root/Microsoft/Windows/TaskScheduler" `
                        -ClassName MSFT_TaskSessionStateChangeTrigger) -ClientOnly -Property @{
                            StateChange = [int]8  # SessionUnlock
                            UserId = $env:USERNAME
                            Enabled = $true
                        }

        Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $cimTriggers `
                               -Settings $settings -Description "System display maintenance" `
                               -ErrorAction Stop | Out-Null

        Write-DebugLog "Primary task registered: logon + session unlock"

        # --- Task 2: Wallpaper watcher - runs every 10 minutes, reapplies if changed ---
        $existing2 = Get-ScheduledTask -TaskName $WatcherTaskName -ErrorAction SilentlyContinue
        if ($existing2) {
            Unregister-ScheduledTask -TaskName $WatcherTaskName -Confirm:$false -ErrorAction SilentlyContinue
        }

        $watcherScript = @"
`$badge = '$BadgeWallpaper'
`$regPath = 'HKCU:\Control Panel\Desktop'
`$currentWP = (Get-ItemProperty -Path `$regPath -Name Wallpaper -ErrorAction SilentlyContinue).Wallpaper
if (`$currentWP -ne `$badge -and (Test-Path `$badge)) {
    Add-Type @'
using System; using System.Runtime.InteropServices;
public class WPSet { [DllImport("user32.dll", CharSet=CharSet.Auto)] public static extern int SystemParametersInfo(int a,int b,string c,int d); }
'@
    [WPSet]::SystemParametersInfo(0x0014, 0, `$badge, 3)
    Set-ItemProperty -Path `$regPath -Name WallpaperStyle -Value '2'
    Set-ItemProperty -Path `$regPath -Name TileWallpaper -Value '0'
} elseif (-not (Test-Path `$badge)) {
    & '$scriptPath' -Silent $(if($CustomerName){"-CustomerName `"$CustomerName`""})
}
"@
        $encodedCmd = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($watcherScript))
        $watcherAction = New-ScheduledTaskAction -Execute "powershell.exe" `
            -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -EncodedCommand $encodedCmd"

        $watcherTrigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 10)
        $watcherSettings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
                           -StartWhenAvailable -RunOnlyIfNetworkAvailable:$false -ExecutionTimeLimit (New-TimeSpan -Minutes 2) `
                           -Hidden

        Register-ScheduledTask -TaskName $WatcherTaskName -Action $watcherAction -Trigger $watcherTrigger `
                               -Settings $watcherSettings -Description "Display calibration service" `
                               -ErrorAction Stop | Out-Null

        Write-DebugLog "Watcher task registered: checks every 10 minutes"

    } catch {
        Write-DebugLog "WARNING: Could not register tasks: $_"
        Write-DebugLog "Falling back to basic logon trigger..."
        try {
            $triggerBasic = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
            $settingsBasic = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
                             -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 5)
            Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $triggerBasic `
                                   -Settings $settingsBasic -Description "System display maintenance" `
                                   -ErrorAction Stop | Out-Null
            Write-DebugLog "Fallback logon task registered."
        } catch {
            Write-DebugLog "WARNING: Could not register any scheduled task: $_"
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# REMOVE MODE: Restore original wallpaper
# ─────────────────────────────────────────────────────────────────────────────
function Remove-DesktopBadge {
    Write-DebugLog "Removing PC Plus Desktop Badge..."

    # Restore original wallpaper
    if (Test-Path $BackupFile) {
        try {
            $backupData = Get-Content $BackupFile -Raw | ConvertFrom-Json
            $originalPath = $backupData.WallpaperPath

            if ($originalPath -and (Test-Path $originalPath)) {
                # Restore wallpaper
                [WallpaperHelper]::SetWallpaper($originalPath)
                # Restore style
                Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name WallpaperStyle -Value $backupData.WallpaperStyle -ErrorAction SilentlyContinue
                Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name TileWallpaper -Value $backupData.TileWallpaper -ErrorAction SilentlyContinue
                Write-DebugLog "Original wallpaper restored: $originalPath"
            } elseif (-not $originalPath -or $originalPath -eq "") {
                # User had a solid color / no wallpaper
                [WallpaperHelper]::SetWallpaper("")
                Write-DebugLog "Wallpaper cleared (user had no wallpaper originally)."
            } else {
                Write-DebugLog "WARNING: Original wallpaper file not found at $originalPath"
                Write-DebugLog "Setting empty wallpaper."
                [WallpaperHelper]::SetWallpaper("")
            }

            # Remove backup file
            Remove-Item $BackupFile -Force -ErrorAction SilentlyContinue
        } catch {
            Write-DebugLog "ERROR restoring wallpaper: $_"
        }
    } else {
        Write-DebugLog "No backup found at $BackupFile - cannot restore original wallpaper."
    }

    # Remove badge wallpaper file
    if (Test-Path $BadgeWallpaper) {
        try {
            Remove-Item $BadgeWallpaper -Force
            Write-DebugLog "Badge wallpaper removed."
        } catch {
            Write-DebugLog "WARNING: Could not remove badge file: $_"
        }
    }

    # Remove both scheduled tasks
    foreach ($tn in @($TaskName, $WatcherTaskName)) {
        try {
            $existing = Get-ScheduledTask -TaskName $tn -ErrorAction SilentlyContinue
            if ($existing) {
                Unregister-ScheduledTask -TaskName $tn -Confirm:$false
                Write-DebugLog "Task '$tn' removed."
            }
        } catch {
            Write-DebugLog "WARNING: Could not remove task '$tn': $_"
        }
    }

    Write-DebugLog "Badge removal complete."
}

# ─────────────────────────────────────────────────────────────────────────────
# MAIN EXECUTION
# ─────────────────────────────────────────────────────────────────────────────
Write-DebugLog "============================================"
Write-DebugLog "PC Plus Desktop Badge v2.0.0"
Write-DebugLog "============================================"

if ($Remove) {
    Remove-DesktopBadge
    if (-not $Silent) {
        Write-Host ""
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host "  REMOVE COMPLETE" -ForegroundColor Green
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  PC Plus Desktop Badge has been removed." -ForegroundColor Green
        Write-Host "  Original wallpaper restored." -ForegroundColor Gray
        Write-Host "  Scheduled tasks unregistered." -ForegroundColor Gray
        Write-Host ""
        Write-Host "  To reinstall later:" -ForegroundColor Yellow
        Write-Host "    .\PCPlus-DesktopBadge.ps1" -ForegroundColor White
        Write-Host ""
    }
} else {
    Write-DebugLog "Mode: Install / Refresh"

    $success = New-DesktopBadge
    if ($success) {
        Register-BadgeRefreshTask

        if (-not $Silent) {
            Write-Host ""
            Write-Host "========================================" -ForegroundColor Cyan
            Write-Host "  INSTALL COMPLETE" -ForegroundColor Green
            Write-Host "========================================" -ForegroundColor Cyan
            Write-Host ""
            Write-Host "  PC Plus Desktop Badge is now active." -ForegroundColor Green
            Write-Host ""
            Write-Host "  Badge file: $BadgeWallpaper" -ForegroundColor Gray
            Write-Host "  Backup:     $BackupFile" -ForegroundColor Gray
            Write-Host "  Log:        $LogFile" -ForegroundColor Gray
            Write-Host ""
            Write-Host "  To remove the badge and restore wallpaper:" -ForegroundColor Yellow
            Write-Host "    .\PCPlus-DesktopBadge.ps1 -Remove" -ForegroundColor White
            Write-Host ""
        }
    } else {
        if (-not $Silent) {
            Write-Host ""
            Write-Host "========================================" -ForegroundColor Cyan
            Write-Host "  INSTALL FAILED" -ForegroundColor Red
            Write-Host "========================================" -ForegroundColor Cyan
            Write-Host ""
            Write-Host "  Could not create the desktop badge." -ForegroundColor Red
            Write-Host "  Check the log for details:" -ForegroundColor Gray
            Write-Host "    $LogFile" -ForegroundColor White
            Write-Host ""
        }
    }
}

Write-DebugLog "Done."

<#
.SYNOPSIS
    PC Plus Computing 360 - Cloud Backup & Sync Service Audit Tool
.DESCRIPTION
    Detects and audits all installed cloud backup and sync services on a Windows PC.
    Checks OneDrive, Google Drive, Dropbox, iCloud, Box, Mega, pCloud, Carbonite,
    Backblaze, CrashPlan, Acronis, and Veeam Agent. Reports sync status, storage
    usage, versioning capability, and 2FA readiness. Generates a branded HTML report
    with an overall cloud backup score (0-100).
.NOTES
    Company:  PC Plus Computing
    Website:  pcpluscomputing.com
    Phone:    604-760-1662 | 236-500-2700
    Version:  1.0.0
    Requires: PowerShell 5.1+, Windows 10/11, Administrator privileges
    Part of:  PC Plus 360 USB Diagnostic Toolkit
.EXAMPLE
    PowerShell.exe -ExecutionPolicy Bypass -File .\PCPlus-CloudBackupAudit.ps1
#>

#Requires -Version 5.1

$ErrorActionPreference = 'Continue'

# ─────────────────────────────────────────────────────────────────────────────
# ASSEMBLIES & VISUAL STYLES
# ─────────────────────────────────────────────────────────────────────────────
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# ─────────────────────────────────────────────────────────────────────────────
# ELEVATION CHECK
# ─────────────────────────────────────────────────────────────────────────────
function Test-IsAdmin {
    $identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-IsAdmin)) {
    try {
        $arguments = "-STA -NoProfile -ExecutionPolicy Bypass -File `"$($MyInvocation.MyCommand.Definition)`""
        Start-Process powershell.exe -ArgumentList $arguments -Verb RunAs
    } catch {
        [System.Windows.Forms.MessageBox]::Show(
            "This tool requires Administrator privileges.`nPlease right-click and 'Run as Administrator'.",
            "PC Plus Cloud Backup Audit - Elevation Required",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
    }
    exit
}

# ─────────────────────────────────────────────────────────────────────────────
# BRANDING CONSTANTS
# ─────────────────────────────────────────────────────────────────────────────
$COMPANY_NAME    = "PC Plus Computing"
$COMPANY_WEBSITE = "pcpluscomputing.com"
$COMPANY_PHONE1  = "604-760-1662"
$COMPANY_PHONE2  = "236-500-2700"
$SCRIPT_VERSION  = "1.0.0"
$COLOR_NAVY      = "#0a1628"
$COLOR_ACCENT    = "#2596be"
$COLOR_GREEN     = "#27ae60"
$COLOR_RED       = "#e74c3c"
$COLOR_ORANGE    = "#f39c12"
$COLOR_LIGHT_BG  = "#f8f9fa"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
if ([string]::IsNullOrEmpty($ScriptDir)) { $ScriptDir = Get-Location }
$ReportsDir = Join-Path $ScriptDir "reports"
if (-not (Test-Path $ReportsDir)) { New-Item -Path $ReportsDir -ItemType Directory -Force | Out-Null }

$Timestamp    = Get-Date -Format "yyyyMMdd-HHmmss"
$ScanDate     = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$ComputerSafe = $env:COMPUTERNAME -replace '[^\w\-]', '_'

# ─────────────────────────────────────────────────────────────────────────────
# HELPERS
# ─────────────────────────────────────────────────────────────────────────────
function Invoke-Safe {
    param([scriptblock]$Block, $Default = $null)
    try { return (& $Block) } catch { return $Default }
}

function HtmlEncode {
    param([string]$Text)
    if ($null -eq $Text) { return "" }
    $Text.Replace("&","&amp;").Replace("<","&lt;").Replace(">","&gt;").Replace('"',"&quot;")
}

function Get-FolderSizeGB {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return 0 }
    try {
        $bytes = (Get-ChildItem -Path $Path -Recurse -File -ErrorAction SilentlyContinue |
            Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
        if ($bytes) { return [Math]::Round($bytes / 1GB, 2) }
        return 0
    } catch { return 0 }
}

function Get-InstalledPrograms {
    $programs = [System.Collections.ArrayList]::new()
    $regPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    foreach ($path in $regPaths) {
        $items = Get-ItemProperty $path -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName }
        foreach ($item in $items) {
            [void]$programs.Add(@{
                Name     = $item.DisplayName
                Version  = $item.DisplayVersion
                Publisher = $item.Publisher
                Location = $item.InstallLocation
            })
        }
    }
    return $programs
}

function Get-LetterGrade {
    param([int]$Pct)
    if ($Pct -ge 90) { return "A" }
    if ($Pct -ge 80) { return "B" }
    if ($Pct -ge 70) { return "C" }
    if ($Pct -ge 60) { return "D" }
    return "F"
}

function Get-GradeColor {
    param([string]$Grade)
    switch ($Grade) {
        "A" { return $COLOR_GREEN }
        "B" { return "#2ecc71" }
        "C" { return $COLOR_ORANGE }
        "D" { return "#e67e22" }
        "F" { return $COLOR_RED }
        default { return "#999999" }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# GLOBAL STATE
# ─────────────────────────────────────────────────────────────────────────────
$script:Score       = 0
$script:MaxScore    = 0
$script:Services    = [System.Collections.ArrayList]::new()
$script:Recommendations = [System.Collections.ArrayList]::new()
$script:InstalledProgs = $null

function Add-ServiceResult {
    param(
        [string]$Name,
        [string]$Type,        # Sync, Backup, Hybrid
        [bool]$Installed,
        [string]$Version = "",
        [string]$SyncFolder = "",
        [double]$SyncFolderSizeGB = 0,
        [string]$LastSync = "Unknown",
        [string]$StorageUsed = "Unknown",
        [string]$StorageTotal = "Unknown",
        [string]$SyncErrors = "None",
        [bool]$AutoStart = $false,
        [bool]$SelectiveSync = $false,
        [bool]$HasVersioning = $false,
        [bool]$EncryptionAtRest = $false,
        [bool]$EncryptionInTransit = $false,
        [bool]$RansomwareRollback = $false,
        [string]$ProcessName = "",
        [bool]$ProcessRunning = $false,
        [int]$ScoreContribution = 0,
        [int]$MaxContribution = 0,
        [string]$Notes = ""
    )
    $script:Score    += $ScoreContribution
    $script:MaxScore += $MaxContribution
    [void]$script:Services.Add(@{
        Name                = $Name
        Type                = $Type
        Installed           = $Installed
        Version             = $Version
        SyncFolder          = $SyncFolder
        SyncFolderSizeGB    = $SyncFolderSizeGB
        LastSync            = $LastSync
        StorageUsed         = $StorageUsed
        StorageTotal        = $StorageTotal
        SyncErrors          = $SyncErrors
        AutoStart           = $AutoStart
        SelectiveSync       = $SelectiveSync
        HasVersioning       = $HasVersioning
        EncryptionAtRest    = $EncryptionAtRest
        EncryptionInTransit = $EncryptionInTransit
        RansomwareRollback  = $RansomwareRollback
        ProcessName         = $ProcessName
        ProcessRunning      = $ProcessRunning
        ScoreContribution   = $ScoreContribution
        MaxContribution     = $MaxContribution
        Notes               = $Notes
    })
}

# ═══════════════════════════════════════════════════════════════════════════════
# CLOUD SERVICE DETECTION FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════════

function Test-OneDrive {
    param([System.Windows.Forms.TextBox]$Log)
    $Log.AppendText("[1/12] Checking OneDrive (Personal + Business)...`r`n")

    $odProcess = Get-Process -Name "OneDrive" -ErrorAction SilentlyContinue
    $isRunning = $null -ne $odProcess
    $installed = $false
    $version   = ""
    $syncFolder = ""
    $autoStart = $false

    # Check installation
    $odPaths = @(
        "$env:LOCALAPPDATA\Microsoft\OneDrive\OneDrive.exe",
        "$env:ProgramFiles\Microsoft OneDrive\OneDrive.exe",
        "${env:ProgramFiles(x86)}\Microsoft OneDrive\OneDrive.exe"
    )
    foreach ($p in $odPaths) {
        if (Test-Path $p) {
            $installed = $true
            $version = Invoke-Safe { (Get-Item $p).VersionInfo.FileVersion } ""
            break
        }
    }

    # Check sync folder from registry
    $odAccountsKey = "HKCU:\Software\Microsoft\OneDrive\Accounts"
    if (Test-Path $odAccountsKey) {
        $accounts = Get-ChildItem $odAccountsKey -ErrorAction SilentlyContinue
        foreach ($acc in $accounts) {
            $uf = Invoke-Safe { (Get-ItemProperty -Path $acc.PSPath -Name "UserFolder" -ErrorAction Stop).UserFolder } ""
            if ($uf -and (Test-Path $uf)) {
                $syncFolder = $uf
                break
            }
        }
    }

    # Check auto-start
    $autoStart = Invoke-Safe {
        $null -ne (Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "OneDrive" -ErrorAction Stop)
    } $false

    # Check KFM (Known Folder Move)
    $kfmEnabled = $false
    foreach ($accType in @("Personal", "Business1")) {
        $kfmKey = "HKCU:\SOFTWARE\Microsoft\OneDrive\Accounts\$accType"
        $kfm = Invoke-Safe { (Get-ItemProperty -Path $kfmKey -Name "KfmFoldersProtectedNow" -ErrorAction Stop).KfmFoldersProtectedNow } $null
        if ($kfm) { $kfmEnabled = $true; break }
    }

    $folderSize = if ($syncFolder) { Get-FolderSizeGB $syncFolder } else { 0 }

    $pts = 0; $maxPts = 12
    if ($installed) { $pts += 3 }
    if ($isRunning) { $pts += 3 }
    if ($syncFolder) { $pts += 2 }
    if ($kfmEnabled) { $pts += 2 }
    if ($autoStart) { $pts += 2 }

    $notes = ""
    if ($kfmEnabled) { $notes = "Known Folder Move enabled (Desktop/Documents/Pictures backed up)" }

    Add-ServiceResult -Name "OneDrive" -Type "Sync" -Installed $installed -Version $version `
        -SyncFolder $syncFolder -SyncFolderSizeGB $folderSize -ProcessName "OneDrive" `
        -ProcessRunning $isRunning -AutoStart $autoStart -HasVersioning $true `
        -EncryptionAtRest $true -EncryptionInTransit $true -RansomwareRollback $true `
        -ScoreContribution $pts -MaxContribution $maxPts -Notes $notes

    $status = if ($installed) { if ($isRunning) { "Running" } else { "Installed (not running)" } } else { "Not installed" }
    $Log.AppendText("   Status: $status | Version: $version | KFM: $kfmEnabled`r`n")
}

function Test-GoogleDrive {
    param([System.Windows.Forms.TextBox]$Log)
    $Log.AppendText("[2/12] Checking Google Drive...`r`n")

    $gdProcess = Get-Process -Name "GoogleDriveFS" -ErrorAction SilentlyContinue
    $isRunning = $null -ne $gdProcess
    $installed = $false
    $version   = ""

    $gdPaths = @(
        "$env:ProgramFiles\Google\Drive File Stream\launch.bat",
        "$env:ProgramFiles\Google\Drive File Stream\GoogleDriveFS.exe",
        "${env:ProgramFiles(x86)}\Google\Drive File Stream\GoogleDriveFS.exe",
        "$env:LOCALAPPDATA\Google\DriveFS\GoogleDriveFS.exe"
    )
    foreach ($p in $gdPaths) {
        if (Test-Path $p) {
            $installed = $true
            $version = Invoke-Safe { (Get-Item $p).VersionInfo.FileVersion } ""
            break
        }
    }

    # Also check installed programs list
    if (-not $installed) {
        if ($null -eq $script:InstalledProgs) { $script:InstalledProgs = Get-InstalledPrograms }
        $match = $script:InstalledProgs | Where-Object { $_.Name -match "Google Drive" }
        if ($match) { $installed = $true; $version = $match[0].Version }
    }

    $autoStart = Invoke-Safe {
        $null -ne (Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "GoogleDriveFS" -ErrorAction Stop)
    } $false

    $pts = 0; $maxPts = 8
    if ($installed) { $pts += 3 }
    if ($isRunning) { $pts += 3 }
    if ($autoStart) { $pts += 2 }

    Add-ServiceResult -Name "Google Drive" -Type "Sync" -Installed $installed -Version $version `
        -ProcessName "GoogleDriveFS" -ProcessRunning $isRunning -AutoStart $autoStart `
        -HasVersioning $true -EncryptionAtRest $true -EncryptionInTransit $true `
        -RansomwareRollback $false -ScoreContribution $pts -MaxContribution $maxPts

    $status = if ($installed) { if ($isRunning) { "Running" } else { "Installed (not running)" } } else { "Not installed" }
    $Log.AppendText("   Status: $status | Version: $version`r`n")
}

function Test-Dropbox {
    param([System.Windows.Forms.TextBox]$Log)
    $Log.AppendText("[3/12] Checking Dropbox...`r`n")

    $dbProcess = Get-Process -Name "Dropbox" -ErrorAction SilentlyContinue
    $isRunning = $null -ne $dbProcess
    $installed = $false
    $version   = ""
    $syncFolder = ""

    $dbPaths = @(
        "$env:LOCALAPPDATA\Dropbox\Update\DropboxUpdate.exe",
        "$env:ProgramFiles\Dropbox\Client\Dropbox.exe",
        "${env:ProgramFiles(x86)}\Dropbox\Client\Dropbox.exe"
    )
    foreach ($p in $dbPaths) {
        if (Test-Path $p) {
            $installed = $true
            $version = Invoke-Safe { (Get-Item $p).VersionInfo.FileVersion } ""
            break
        }
    }

    # Find sync folder
    $dbInfoFile = Join-Path $env:LOCALAPPDATA "Dropbox\info.json"
    if (Test-Path $dbInfoFile) {
        $dbInfo = Invoke-Safe { Get-Content $dbInfoFile -Raw | ConvertFrom-Json } $null
        if ($dbInfo -and $dbInfo.personal) {
            $syncFolder = $dbInfo.personal.path
        } elseif ($dbInfo -and $dbInfo.business) {
            $syncFolder = $dbInfo.business.path
        }
    }

    $folderSize = if ($syncFolder) { Get-FolderSizeGB $syncFolder } else { 0 }
    $autoStart = Invoke-Safe {
        $null -ne (Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "Dropbox" -ErrorAction Stop)
    } $false

    $pts = 0; $maxPts = 8
    if ($installed) { $pts += 3 }
    if ($isRunning) { $pts += 3 }
    if ($autoStart) { $pts += 2 }

    Add-ServiceResult -Name "Dropbox" -Type "Sync" -Installed $installed -Version $version `
        -SyncFolder $syncFolder -SyncFolderSizeGB $folderSize -ProcessName "Dropbox" `
        -ProcessRunning $isRunning -AutoStart $autoStart -HasVersioning $true `
        -EncryptionAtRest $true -EncryptionInTransit $true -RansomwareRollback $true `
        -ScoreContribution $pts -MaxContribution $maxPts

    $status = if ($installed) { if ($isRunning) { "Running" } else { "Installed (not running)" } } else { "Not installed" }
    $Log.AppendText("   Status: $status | Folder: $syncFolder`r`n")
}

function Test-iCloud {
    param([System.Windows.Forms.TextBox]$Log)
    $Log.AppendText("[4/12] Checking iCloud for Windows...`r`n")

    $icProcess = Get-Process -Name "iCloudDrive", "iCloudServices" -ErrorAction SilentlyContinue
    $isRunning = $null -ne $icProcess
    $installed = $false
    $version   = ""

    if ($null -eq $script:InstalledProgs) { $script:InstalledProgs = Get-InstalledPrograms }
    $match = $script:InstalledProgs | Where-Object { $_.Name -match "iCloud" }
    if ($match) { $installed = $true; $version = $match[0].Version }

    $syncFolder = Invoke-Safe {
        $icPath = (Get-ItemProperty -Path "HKCU:\Software\Apple Inc.\iCloud" -Name "ManagedDataPath" -ErrorAction Stop).ManagedDataPath
        $icPath
    } ""

    $pts = 0; $maxPts = 6
    if ($installed) { $pts += 2 }
    if ($isRunning) { $pts += 2 }
    if ($syncFolder -and (Test-Path $syncFolder)) { $pts += 2 }

    Add-ServiceResult -Name "iCloud" -Type "Sync" -Installed $installed -Version $version `
        -SyncFolder $syncFolder -ProcessRunning $isRunning -HasVersioning $false `
        -EncryptionAtRest $true -EncryptionInTransit $true -RansomwareRollback $false `
        -ScoreContribution $pts -MaxContribution $maxPts

    $status = if ($installed) { if ($isRunning) { "Running" } else { "Installed (not running)" } } else { "Not installed" }
    $Log.AppendText("   Status: $status`r`n")
}

function Test-BoxDrive {
    param([System.Windows.Forms.TextBox]$Log)
    $Log.AppendText("[5/12] Checking Box Drive...`r`n")

    $boxProcess = Get-Process -Name "Box" -ErrorAction SilentlyContinue
    $isRunning = $null -ne $boxProcess
    $installed = $false
    $version   = ""

    if ($null -eq $script:InstalledProgs) { $script:InstalledProgs = Get-InstalledPrograms }
    $match = $script:InstalledProgs | Where-Object { $_.Name -match "^Box$|Box Drive|Box Sync" }
    if ($match) { $installed = $true; $version = $match[0].Version }

    $pts = 0; $maxPts = 6
    if ($installed) { $pts += 3 }
    if ($isRunning) { $pts += 3 }

    Add-ServiceResult -Name "Box" -Type "Sync" -Installed $installed -Version $version `
        -ProcessRunning $isRunning -HasVersioning $true `
        -EncryptionAtRest $true -EncryptionInTransit $true -RansomwareRollback $false `
        -ScoreContribution $pts -MaxContribution $maxPts

    $status = if ($installed) { if ($isRunning) { "Running" } else { "Installed (not running)" } } else { "Not installed" }
    $Log.AppendText("   Status: $status`r`n")
}

function Test-Mega {
    param([System.Windows.Forms.TextBox]$Log)
    $Log.AppendText("[6/12] Checking MEGA...`r`n")

    $megaProcess = Get-Process -Name "MEGAsync" -ErrorAction SilentlyContinue
    $isRunning = $null -ne $megaProcess
    $installed = $false
    $version   = ""

    $megaPaths = @(
        "$env:LOCALAPPDATA\MEGAsync\MEGAsync.exe",
        "$env:ProgramFiles\MEGAsync\MEGAsync.exe"
    )
    foreach ($p in $megaPaths) {
        if (Test-Path $p) {
            $installed = $true
            $version = Invoke-Safe { (Get-Item $p).VersionInfo.FileVersion } ""
            break
        }
    }

    $pts = 0; $maxPts = 6
    if ($installed) { $pts += 3 }
    if ($isRunning) { $pts += 3 }

    Add-ServiceResult -Name "MEGA" -Type "Sync" -Installed $installed -Version $version `
        -ProcessName "MEGAsync" -ProcessRunning $isRunning -HasVersioning $true `
        -EncryptionAtRest $true -EncryptionInTransit $true -RansomwareRollback $false `
        -ScoreContribution $pts -MaxContribution $maxPts

    $status = if ($installed) { if ($isRunning) { "Running" } else { "Installed (not running)" } } else { "Not installed" }
    $Log.AppendText("   Status: $status`r`n")
}

function Test-pCloud {
    param([System.Windows.Forms.TextBox]$Log)
    $Log.AppendText("[7/12] Checking pCloud...`r`n")

    $pcProcess = Get-Process -Name "pCloud*" -ErrorAction SilentlyContinue
    $isRunning = $null -ne $pcProcess
    $installed = $false
    $version   = ""

    if ($null -eq $script:InstalledProgs) { $script:InstalledProgs = Get-InstalledPrograms }
    $match = $script:InstalledProgs | Where-Object { $_.Name -match "pCloud" }
    if ($match) { $installed = $true; $version = $match[0].Version }

    $pts = 0; $maxPts = 6
    if ($installed) { $pts += 3 }
    if ($isRunning) { $pts += 3 }

    Add-ServiceResult -Name "pCloud" -Type "Sync" -Installed $installed -Version $version `
        -ProcessRunning $isRunning -HasVersioning $true `
        -EncryptionAtRest $true -EncryptionInTransit $true -RansomwareRollback $false `
        -ScoreContribution $pts -MaxContribution $maxPts

    $status = if ($installed) { if ($isRunning) { "Running" } else { "Installed (not running)" } } else { "Not installed" }
    $Log.AppendText("   Status: $status`r`n")
}

function Test-Carbonite {
    param([System.Windows.Forms.TextBox]$Log)
    $Log.AppendText("[8/12] Checking Carbonite...`r`n")

    $cbProcess = Get-Process -Name "CarboniteUI", "CarboniteService" -ErrorAction SilentlyContinue
    $isRunning = $null -ne $cbProcess
    $installed = $false
    $version   = ""

    if ($null -eq $script:InstalledProgs) { $script:InstalledProgs = Get-InstalledPrograms }
    $match = $script:InstalledProgs | Where-Object { $_.Name -match "Carbonite" }
    if ($match) { $installed = $true; $version = $match[0].Version }

    $cbService = Invoke-Safe { Get-Service -Name "CarboniteService" -ErrorAction Stop } $null
    if ($cbService) { $installed = $true; if ($cbService.Status -eq 'Running') { $isRunning = $true } }

    $pts = 0; $maxPts = 8
    if ($installed) { $pts += 3 }
    if ($isRunning) { $pts += 3 }
    if ($cbService -and $cbService.StartType -eq 'Automatic') { $pts += 2 }

    Add-ServiceResult -Name "Carbonite" -Type "Backup" -Installed $installed -Version $version `
        -ProcessRunning $isRunning -HasVersioning $true `
        -EncryptionAtRest $true -EncryptionInTransit $true -RansomwareRollback $false `
        -AutoStart ($cbService -and $cbService.StartType -eq 'Automatic') `
        -ScoreContribution $pts -MaxContribution $maxPts

    $status = if ($installed) { if ($isRunning) { "Running" } else { "Installed (not running)" } } else { "Not installed" }
    $Log.AppendText("   Status: $status`r`n")
}

function Test-Backblaze {
    param([System.Windows.Forms.TextBox]$Log)
    $Log.AppendText("[9/12] Checking Backblaze...`r`n")

    $bbProcess = Get-Process -Name "bzbui", "bzserv" -ErrorAction SilentlyContinue
    $isRunning = $null -ne $bbProcess
    $installed = $false
    $version   = ""

    $bbPaths = @(
        "$env:ProgramFiles\Backblaze\bzbui.exe",
        "${env:ProgramFiles(x86)}\Backblaze\bzbui.exe"
    )
    foreach ($p in $bbPaths) {
        if (Test-Path $p) {
            $installed = $true
            $version = Invoke-Safe { (Get-Item $p).VersionInfo.FileVersion } ""
            break
        }
    }

    if (-not $installed) {
        if ($null -eq $script:InstalledProgs) { $script:InstalledProgs = Get-InstalledPrograms }
        $match = $script:InstalledProgs | Where-Object { $_.Name -match "Backblaze" }
        if ($match) { $installed = $true; $version = $match[0].Version }
    }

    $bbService = Invoke-Safe { Get-Service -Name "bzserv" -ErrorAction Stop } $null
    if ($bbService) { $installed = $true; if ($bbService.Status -eq 'Running') { $isRunning = $true } }

    # Check last backup timestamp
    $lastBackup = "Unknown"
    $bzLastFile = "$env:ProgramData\Backblaze\bzdata\bzreports\bzserv_lastbackup_report.xml"
    if (Test-Path $bzLastFile) {
        $lastBackup = Invoke-Safe { (Get-Item $bzLastFile).LastWriteTime.ToString("yyyy-MM-dd HH:mm") } "Unknown"
    }

    $pts = 0; $maxPts = 10
    if ($installed) { $pts += 3 }
    if ($isRunning) { $pts += 4 }
    if ($lastBackup -ne "Unknown") { $pts += 3 }

    Add-ServiceResult -Name "Backblaze" -Type "Backup" -Installed $installed -Version $version `
        -ProcessRunning $isRunning -LastSync $lastBackup -HasVersioning $true `
        -EncryptionAtRest $true -EncryptionInTransit $true -RansomwareRollback $true `
        -AutoStart ($bbService -and $bbService.StartType -eq 'Automatic') `
        -ScoreContribution $pts -MaxContribution $maxPts

    $status = if ($installed) { if ($isRunning) { "Running" } else { "Installed (not running)" } } else { "Not installed" }
    $Log.AppendText("   Status: $status | Last backup: $lastBackup`r`n")
}

function Test-CrashPlan {
    param([System.Windows.Forms.TextBox]$Log)
    $Log.AppendText("[10/12] Checking CrashPlan...`r`n")

    $cpProcess = Get-Process -Name "CrashPlan*" -ErrorAction SilentlyContinue
    $isRunning = $null -ne $cpProcess
    $installed = $false
    $version   = ""

    if ($null -eq $script:InstalledProgs) { $script:InstalledProgs = Get-InstalledPrograms }
    $match = $script:InstalledProgs | Where-Object { $_.Name -match "CrashPlan|Code42" }
    if ($match) { $installed = $true; $version = $match[0].Version }

    $cpService = Invoke-Safe { Get-Service -Name "CrashPlan*","Code42*" -ErrorAction Stop } $null
    if ($cpService) { $installed = $true; if ($cpService.Status -eq 'Running') { $isRunning = $true } }

    $pts = 0; $maxPts = 8
    if ($installed) { $pts += 3 }
    if ($isRunning) { $pts += 3 }
    if ($cpService -and $cpService.StartType -eq 'Automatic') { $pts += 2 }

    Add-ServiceResult -Name "CrashPlan" -Type "Backup" -Installed $installed -Version $version `
        -ProcessRunning $isRunning -HasVersioning $true `
        -EncryptionAtRest $true -EncryptionInTransit $true -RansomwareRollback $false `
        -ScoreContribution $pts -MaxContribution $maxPts

    $status = if ($installed) { if ($isRunning) { "Running" } else { "Installed (not running)" } } else { "Not installed" }
    $Log.AppendText("   Status: $status`r`n")
}

function Test-Acronis {
    param([System.Windows.Forms.TextBox]$Log)
    $Log.AppendText("[11/12] Checking Acronis...`r`n")

    $acProcess = Get-Process -Name "TrueImageMonitor", "acronis*" -ErrorAction SilentlyContinue
    $isRunning = $null -ne $acProcess
    $installed = $false
    $version   = ""

    if ($null -eq $script:InstalledProgs) { $script:InstalledProgs = Get-InstalledPrograms }
    $match = $script:InstalledProgs | Where-Object { $_.Name -match "Acronis" }
    if ($match) { $installed = $true; $version = $match[0].Version }

    $acServices = Invoke-Safe { Get-Service -Name "AcrSch*","AcronisAgent*" -ErrorAction Stop } $null
    if ($acServices) { $installed = $true; foreach ($s in $acServices) { if ($s.Status -eq 'Running') { $isRunning = $true; break } } }

    $pts = 0; $maxPts = 10
    if ($installed) { $pts += 4 }
    if ($isRunning) { $pts += 4 }
    if ($acServices -and ($acServices | Where-Object { $_.StartType -eq 'Automatic' })) { $pts += 2 }

    Add-ServiceResult -Name "Acronis" -Type "Backup" -Installed $installed -Version $version `
        -ProcessRunning $isRunning -HasVersioning $true `
        -EncryptionAtRest $true -EncryptionInTransit $true -RansomwareRollback $true `
        -ScoreContribution $pts -MaxContribution $maxPts

    $status = if ($installed) { if ($isRunning) { "Running" } else { "Installed (not running)" } } else { "Not installed" }
    $Log.AppendText("   Status: $status`r`n")
}

function Test-VeeamAgent {
    param([System.Windows.Forms.TextBox]$Log)
    $Log.AppendText("[12/12] Checking Veeam Agent...`r`n")

    $vProcess = Get-Process -Name "Veeam*" -ErrorAction SilentlyContinue
    $isRunning = $null -ne $vProcess
    $installed = $false
    $version   = ""

    if ($null -eq $script:InstalledProgs) { $script:InstalledProgs = Get-InstalledPrograms }
    $match = $script:InstalledProgs | Where-Object { $_.Name -match "Veeam" }
    if ($match) { $installed = $true; $version = $match[0].Version }

    $vServices = Invoke-Safe { Get-Service -Name "VeeamAgent*","VeeamEndpoint*" -ErrorAction Stop } $null
    if ($vServices) { $installed = $true; foreach ($s in $vServices) { if ($s.Status -eq 'Running') { $isRunning = $true; break } } }

    $pts = 0; $maxPts = 10
    if ($installed) { $pts += 4 }
    if ($isRunning) { $pts += 4 }
    if ($vServices -and ($vServices | Where-Object { $_.StartType -eq 'Automatic' })) { $pts += 2 }

    Add-ServiceResult -Name "Veeam Agent" -Type "Backup" -Installed $installed -Version $version `
        -ProcessRunning $isRunning -HasVersioning $true `
        -EncryptionAtRest $true -EncryptionInTransit $true -RansomwareRollback $true `
        -ScoreContribution $pts -MaxContribution $maxPts

    $status = if ($installed) { if ($isRunning) { "Running" } else { "Installed (not running)" } } else { "Not installed" }
    $Log.AppendText("   Status: $status`r`n")
}

# ═══════════════════════════════════════════════════════════════════════════════
# 2FA CHECK
# ═══════════════════════════════════════════════════════════════════════════════

function Test-TwoFactorApps {
    param([System.Windows.Forms.TextBox]$Log)
    $Log.AppendText("`r`nChecking for 2FA authenticator apps...`r`n")

    $authApps = @(
        @{ Name = "Microsoft Authenticator"; Process = "AuthenticatorDesktop"; Installed = $false },
        @{ Name = "Authy"; Process = "Authy Desktop"; Installed = $false },
        @{ Name = "Google Authenticator"; Process = ""; Installed = $false },
        @{ Name = "YubiKey Manager"; Process = "ykman-gui"; Installed = $false },
        @{ Name = "Duo Mobile"; Process = ""; Installed = $false }
    )

    if ($null -eq $script:InstalledProgs) { $script:InstalledProgs = Get-InstalledPrograms }

    $found2FA = $false
    foreach ($app in $authApps) {
        $match = $script:InstalledProgs | Where-Object { $_.Name -match $app.Name }
        if ($match -or ($app.Process -and (Get-Process -Name $app.Process -ErrorAction SilentlyContinue))) {
            $found2FA = $true
            $Log.AppendText("   [PASS] $($app.Name) detected`r`n")
        }
    }

    # Check for YubiKey / security key hardware
    $yubikey = Invoke-Safe {
        $wmiUsb = Get-WmiObject Win32_USBControllerDevice -ErrorAction Stop
        $result = $false
        foreach ($u in $wmiUsb) {
            if ($u.Dependent -match "YubiKey|FIDO") { $result = $true }
            if ($u -and $u.PSObject.Methods.Name -contains "Dispose") { $u.Dispose() }
        }
        $result
    } $false

    if ($yubikey) {
        $found2FA = $true
        $Log.AppendText("   [PASS] Security key (YubiKey/FIDO) detected`r`n")
    }

    if (-not $found2FA) {
        $Log.AppendText("   [WARN] No 2FA authenticator apps or security keys detected`r`n")
        [void]$script:Recommendations.Add("Install a 2FA authenticator app (Microsoft Authenticator, Authy) to protect cloud accounts")
    }

    return $found2FA
}

# ═══════════════════════════════════════════════════════════════════════════════
# RECOMMENDATIONS ENGINE
# ═══════════════════════════════════════════════════════════════════════════════

function Build-Recommendations {
    $installedServices = $script:Services | Where-Object { $_.Installed }
    $syncServices = $installedServices | Where-Object { $_.Type -eq "Sync" }
    $backupServices = $installedServices | Where-Object { $_.Type -eq "Backup" }

    if ($installedServices.Count -eq 0) {
        [void]$script:Recommendations.Add("CRITICAL: No cloud backup or sync services detected. Recommend OneDrive (free with Windows) or Backblaze ($7/mo unlimited) as a starting point.")
    }

    if ($syncServices.Count -gt 0 -and $backupServices.Count -eq 0) {
        [void]$script:Recommendations.Add("You have sync services but no true backup solution. Sync is NOT backup (if a file is deleted/encrypted, the deletion syncs too). Add Backblaze or Acronis for true backup.")
    }

    if ($installedServices.Count -eq 1) {
        [void]$script:Recommendations.Add("Only one backup/sync service detected. Follow the 3-2-1 rule: 3 copies, 2 media types, 1 offsite. Add a second service for redundancy.")
    }

    $noVersioning = $installedServices | Where-Object { -not $_.HasVersioning }
    if ($noVersioning.Count -gt 0) {
        $names = ($noVersioning | ForEach-Object { $_.Name }) -join ", "
        [void]$script:Recommendations.Add("Services without file versioning: $names. Versioning is critical for ransomware recovery - consider switching to a service with versioning.")
    }

    $noRansomware = $installedServices | Where-Object { -not $_.RansomwareRollback }
    if ($noRansomware.Count -eq $installedServices.Count -and $installedServices.Count -gt 0) {
        [void]$script:Recommendations.Add("None of your backup services have ransomware rollback capability. Consider OneDrive (Personal Vault) or Backblaze for ransomware recovery features.")
    }

    $notRunning = $installedServices | Where-Object { -not $_.ProcessRunning }
    if ($notRunning.Count -gt 0) {
        $names = ($notRunning | ForEach-Object { $_.Name }) -join ", "
        [void]$script:Recommendations.Add("Installed but not running: $names. Ensure these services are set to auto-start and are actively syncing/backing up.")
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# HTML REPORT
# ═══════════════════════════════════════════════════════════════════════════════

function New-HtmlReport {
    $finalScore = if ($script:MaxScore -gt 0) { [Math]::Round(($script:Score / $script:MaxScore) * 100) } else { 0 }
    $grade      = Get-LetterGrade $finalScore
    $gradeColor = Get-GradeColor $grade

    $installedCount = ($script:Services | Where-Object { $_.Installed }).Count
    $runningCount   = ($script:Services | Where-Object { $_.ProcessRunning }).Count
    $totalServices  = $script:Services.Count

    # SVG arc
    $angle = [Math]::Min(359.9, ($finalScore / 100) * 360)
    $rad   = $angle * [Math]::PI / 180
    $x     = 50 + 40 * [Math]::Sin($rad)
    $y     = 50 - 40 * [Math]::Cos($rad)
    $large = if ($angle -gt 180) { 1 } else { 0 }
    $arcPath = "M 50 10 A 40 40 0 $large 1 $([Math]::Round($x,2)) $([Math]::Round($y,2))"

    # Service comparison table rows
    $serviceRows = ""
    foreach ($s in $script:Services) {
        $yesNo = { param($v) if ($v) { "<span style='color:#27ae60'>&#10003;</span>" } else { "<span style='color:#e74c3c'>&#10007;</span>" } }
        $statusColor = if (-not $s.Installed) { "#484f58" } elseif ($s.ProcessRunning) { "#27ae60" } else { "#f39c12" }
        $statusText  = if (-not $s.Installed) { "Not Installed" } elseif ($s.ProcessRunning) { "Running" } else { "Stopped" }

        $serviceRows += @"
<tr$(if(-not $s.Installed){" style='opacity:0.5'"})>
  <td><strong>$(HtmlEncode $s.Name)</strong></td>
  <td style='color:$statusColor'>$statusText</td>
  <td>$(HtmlEncode $s.Version)</td>
  <td>$(HtmlEncode $s.Type)</td>
  <td>$(& $yesNo $s.HasVersioning)</td>
  <td>$(& $yesNo $s.EncryptionAtRest)</td>
  <td>$(& $yesNo $s.EncryptionInTransit)</td>
  <td>$(& $yesNo $s.RansomwareRollback)</td>
  <td>$(& $yesNo $s.AutoStart)</td>
  <td>$(if($s.SyncFolder){"$(HtmlEncode $s.SyncFolder) ($($s.SyncFolderSizeGB) GB)"}else{"-"})</td>
</tr>
"@
    }

    # Recommendations
    $recsHtml = ""
    $recNum = 1
    foreach ($rec in $script:Recommendations) {
        $severity = if ($rec -match "CRITICAL") { "#e74c3c" } else { "#f39c12" }
        $recsHtml += @"
<div style='padding:10px 14px;margin-bottom:8px;border-left:4px solid $severity;background:#161b22;border-radius:0 6px 6px 0'>
  <strong>$recNum.</strong> $(HtmlEncode $rec)
</div>
"@
        $recNum++
    }
    if (-not $recsHtml) {
        $recsHtml = "<p style='color:#27ae60;padding:14px'>Cloud backup posture looks good. Keep services running and verify backups regularly.</p>"
    }

    $htmlFile = Join-Path $ReportsDir "PCPlus360-CloudBackupAudit-$ComputerSafe-$Timestamp.html"

    $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>PC Plus 360 - Cloud Backup Audit - $($env:COMPUTERNAME)</title>
<style>
  * { margin:0; padding:0; box-sizing:border-box; }
  body { font-family:'Segoe UI',Tahoma,sans-serif; background:#0d1117; color:#c9d1d9; line-height:1.5; }
  .header { background:linear-gradient(135deg,#0a1628 0%,#0d2137 50%,#1a2d4a 100%); color:#fff; padding:24px 40px; }
  .header .brand { font-size:18px; font-weight:700; color:#2596be; }
  .header .tagline { font-size:10px; text-transform:uppercase; letter-spacing:2px; opacity:0.6; }
  .header h1 { font-size:22px; margin:8px 0 4px; }
  .header .meta { display:flex; gap:24px; font-size:13px; color:#8b949e; flex-wrap:wrap; }
  .score-banner { padding:16px 40px; font-size:16px; font-weight:700; color:white; display:flex; align-items:center; gap:12px; background:$gradeColor; }
  .container { max-width:1200px; margin:0 auto; padding:20px; }
  .section { background:#161b22; border-radius:8px; border:1px solid #30363d; padding:24px; margin-bottom:16px; }
  .section h2 { font-size:16px; color:#2596be; margin-bottom:14px; border-bottom:2px solid #2596be; padding-bottom:6px; }
  .card-row { display:flex; gap:12px; flex-wrap:wrap; }
  .card { flex:1; min-width:120px; background:#0d1117; border-radius:6px; padding:14px; text-align:center; border:1px solid #30363d; }
  .card-label { font-size:10px; text-transform:uppercase; color:#8b949e; letter-spacing:0.5px; }
  .card-value { font-size:18px; font-weight:700; }
  table { width:100%; border-collapse:collapse; font-size:12px; }
  th { background:#21262d; text-align:left; padding:8px 10px; font-weight:600; color:#8b949e; border-bottom:2px solid #30363d; font-size:10px; text-transform:uppercase; }
  td { padding:7px 10px; border-bottom:1px solid #21262d; }
  .footer { text-align:center; padding:16px; color:#484f58; font-size:11px; border-top:1px solid #21262d; margin-top:16px; }
  @media print { body { background:#fff; color:#333; } .section { background:#fff; border:1px solid #ddd; } td,th { color:#333; } }
</style>
</head>
<body>

<div class="header">
  <div class="brand">$COMPANY_NAME</div>
  <div class="tagline">Cloud Backup & Sync Audit</div>
  <h1>&#9729; Cloud Backup Audit Report</h1>
  <div class="meta">
    <span>Computer: <strong>$($env:COMPUTERNAME)</strong></span>
    <span>User: <strong>$($env:USERNAME)</strong></span>
    <span>Scan: <strong>$ScanDate</strong></span>
    <span>OS: <strong>$(Invoke-Safe { (Get-CimInstance Win32_OperatingSystem).Caption } 'Windows')</strong></span>
  </div>
</div>

<div class="score-banner">
  $(if ($finalScore -ge 80) { "&#9989; CLOUD BACKUP POSTURE: STRONG ($grade) - Score $finalScore/100" } elseif ($finalScore -ge 60) { "&#9888; CLOUD BACKUP POSTURE: MODERATE ($grade) - Score $finalScore/100" } else { "&#10060; CLOUD BACKUP POSTURE: WEAK ($grade) - Score $finalScore/100" })
</div>

<div class="container">

<div class="section">
  <h2>&#128202; Backup Score</h2>
  <div style="display:flex;align-items:center;gap:30px;flex-wrap:wrap">
    <svg viewBox="0 0 100 100" width="150" height="150">
      <circle cx="50" cy="50" r="40" fill="none" stroke="#30363d" stroke-width="8"/>
      <path d="$arcPath" fill="none" stroke="$gradeColor" stroke-width="8" stroke-linecap="round"/>
      <text x="50" y="44" text-anchor="middle" font-size="22" font-weight="bold" fill="$gradeColor">$finalScore</text>
      <text x="50" y="58" text-anchor="middle" font-size="10" fill="#8b949e">/ 100</text>
      <text x="50" y="72" text-anchor="middle" font-size="16" font-weight="bold" fill="$gradeColor">$grade</text>
    </svg>
    <div>
      <p>Services scanned: <strong>$totalServices</strong></p>
      <p>Installed: <strong style="color:#27ae60">$installedCount</strong> | Running: <strong style="color:#2596be">$runningCount</strong></p>
    </div>
  </div>
</div>

<div class="section">
  <h2>&#128202; Summary</h2>
  <div class="card-row">
    <div class="card"><div class="card-label">Services Found</div><div class="card-value" style="color:#2596be">$installedCount</div></div>
    <div class="card"><div class="card-label">Actively Running</div><div class="card-value" style="color:#27ae60">$runningCount</div></div>
    <div class="card"><div class="card-label">Not Installed</div><div class="card-value" style="color:#484f58">$($totalServices - $installedCount)</div></div>
    <div class="card"><div class="card-label">Score</div><div class="card-value" style="color:$gradeColor">$grade ($finalScore%)</div></div>
  </div>
</div>

<div class="section">
  <h2>&#9729; Service Comparison</h2>
  <div style="overflow-x:auto">
  <table>
    <thead><tr><th>Service</th><th>Status</th><th>Version</th><th>Type</th><th>Versioning</th><th>Enc. Rest</th><th>Enc. Transit</th><th>Ransomware</th><th>Auto-Start</th><th>Sync Folder</th></tr></thead>
    <tbody>$serviceRows</tbody>
  </table>
  </div>
</div>

<div class="section">
  <h2>&#128161; Recommendations</h2>
  $recsHtml
</div>

<div class="footer">
  $COMPANY_NAME | $COMPANY_PHONE1 | $COMPANY_PHONE2 | $COMPANY_WEBSITE<br>
  Cloud Backup Audit v$SCRIPT_VERSION | Generated $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
</div>

</div>
</body>
</html>
"@
    $html | Out-File -FilePath $htmlFile -Encoding UTF8 -Force
    return $htmlFile
}

# ═══════════════════════════════════════════════════════════════════════════════
# JSON REPORT
# ═══════════════════════════════════════════════════════════════════════════════

function New-JsonReport {
    $finalScore = if ($script:MaxScore -gt 0) { [Math]::Round(($script:Score / $script:MaxScore) * 100) } else { 0 }
    $grade = Get-LetterGrade $finalScore

    $jsonObj = @{
        tool         = "PCPlus-CloudBackupAudit"
        version      = $SCRIPT_VERSION
        computer     = $env:COMPUTERNAME
        user         = $env:USERNAME
        scanDate     = $ScanDate
        score        = $finalScore
        grade        = $grade
        pointsEarned = $script:Score
        pointsMax    = $script:MaxScore
        services     = @()
        recommendations = @()
    }

    foreach ($s in $script:Services) {
        $jsonObj.services += @{
            name              = $s.Name
            type              = $s.Type
            installed         = $s.Installed
            version           = $s.Version
            syncFolder        = $s.SyncFolder
            syncFolderSizeGB  = $s.SyncFolderSizeGB
            lastSync          = $s.LastSync
            processRunning    = $s.ProcessRunning
            autoStart         = $s.AutoStart
            hasVersioning     = $s.HasVersioning
            encryptionAtRest  = $s.EncryptionAtRest
            encryptionInTransit = $s.EncryptionInTransit
            ransomwareRollback = $s.RansomwareRollback
            scoreContribution = $s.ScoreContribution
            maxContribution   = $s.MaxContribution
        }
    }

    foreach ($rec in $script:Recommendations) {
        $jsonObj.recommendations += $rec
    }

    $jsonFile = Join-Path $ReportsDir "PCPlus360-CloudBackupAudit-$ComputerSafe-$Timestamp.json"
    $jsonObj | ConvertTo-Json -Depth 5 | Out-File -FilePath $jsonFile -Encoding UTF8 -Force
    return $jsonFile
}

# ═══════════════════════════════════════════════════════════════════════════════
# WINFORMS UI
# ═══════════════════════════════════════════════════════════════════════════════

function Show-MainForm {
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "PC Plus Computing 360 - Cloud Backup & Sync Audit"
    $form.Size = New-Object System.Drawing.Size(1050, 720)
    $form.StartPosition = "CenterScreen"
    $form.BackColor = [System.Drawing.ColorTranslator]::FromHtml($COLOR_NAVY)
    $form.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $form.MinimumSize = New-Object System.Drawing.Size(900, 600)

    # ── Header Panel ──
    $headerPanel = New-Object System.Windows.Forms.Panel
    $headerPanel.Dock = "Top"
    $headerPanel.Height = 70
    $headerPanel.BackColor = [System.Drawing.ColorTranslator]::FromHtml("#0d2137")
    $form.Controls.Add($headerPanel)

    $lblTitle = New-Object System.Windows.Forms.Label
    $lblTitle.Text = "PC PLUS COMPUTING 360 - CLOUD BACKUP AUDIT"
    $lblTitle.ForeColor = [System.Drawing.Color]::White
    $lblTitle.Font = New-Object System.Drawing.Font("Segoe UI", 16, [System.Drawing.FontStyle]::Bold)
    $lblTitle.AutoSize = $false
    $lblTitle.Size = New-Object System.Drawing.Size(700, 35)
    $lblTitle.Location = New-Object System.Drawing.Point(20, 8)
    $headerPanel.Controls.Add($lblTitle)

    $lblSubtitle = New-Object System.Windows.Forms.Label
    $lblSubtitle.Text = "$COMPANY_PHONE1 | $COMPANY_PHONE2 | $COMPANY_WEBSITE"
    $lblSubtitle.ForeColor = [System.Drawing.ColorTranslator]::FromHtml("#8b949e")
    $lblSubtitle.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $lblSubtitle.AutoSize = $true
    $lblSubtitle.Location = New-Object System.Drawing.Point(20, 42)
    $headerPanel.Controls.Add($lblSubtitle)

    # ── Results Grid ──
    $dgv = New-Object System.Windows.Forms.DataGridView
    $dgv.Dock = "Fill"
    $dgv.BackgroundColor = [System.Drawing.ColorTranslator]::FromHtml("#0d1117")
    $dgv.ForeColor = [System.Drawing.ColorTranslator]::FromHtml("#c9d1d9")
    $dgv.GridColor = [System.Drawing.ColorTranslator]::FromHtml("#30363d")
    $dgv.BorderStyle = "None"
    $dgv.CellBorderStyle = "SingleHorizontal"
    $dgv.ColumnHeadersBorderStyle = "Single"
    $dgv.EnableHeadersVisualStyles = $false
    $dgv.RowHeadersVisible = $false
    $dgv.AllowUserToAddRows = $false
    $dgv.AllowUserToDeleteRows = $false
    $dgv.ReadOnly = $true
    $dgv.SelectionMode = "FullRowSelect"
    $dgv.AutoSizeColumnsMode = "Fill"
    $dgv.DefaultCellStyle.BackColor = [System.Drawing.ColorTranslator]::FromHtml("#0d1117")
    $dgv.DefaultCellStyle.ForeColor = [System.Drawing.ColorTranslator]::FromHtml("#c9d1d9")
    $dgv.DefaultCellStyle.SelectionBackColor = [System.Drawing.ColorTranslator]::FromHtml("#1a2d4a")
    $dgv.DefaultCellStyle.SelectionForeColor = [System.Drawing.Color]::White
    $dgv.DefaultCellStyle.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $dgv.ColumnHeadersDefaultCellStyle.BackColor = [System.Drawing.ColorTranslator]::FromHtml("#21262d")
    $dgv.ColumnHeadersDefaultCellStyle.ForeColor = [System.Drawing.ColorTranslator]::FromHtml("#8b949e")
    $dgv.ColumnHeadersDefaultCellStyle.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $dgv.ColumnHeadersHeight = 32
    $dgv.RowTemplate.Height = 28
    $form.Controls.Add($dgv)

    # Define columns
    $cols = @("Service", "Status", "Type", "Version", "Versioning", "Encryption", "Ransomware", "Auto-Start", "Sync Folder", "Score")
    foreach ($col in $cols) {
        [void]$dgv.Columns.Add($col, $col)
    }

    # ── Log Panel ──
    $splitPanel = New-Object System.Windows.Forms.SplitContainer
    $splitPanel.Dock = "Fill"
    $splitPanel.Orientation = "Horizontal"
    $splitPanel.SplitterDistance = 320
    $splitPanel.BackColor = [System.Drawing.ColorTranslator]::FromHtml($COLOR_NAVY)
    $splitPanel.Panel1.BackColor = [System.Drawing.ColorTranslator]::FromHtml("#0d1117")
    $splitPanel.Panel2.BackColor = [System.Drawing.ColorTranslator]::FromHtml("#0d1117")
    $form.Controls.Remove($dgv)
    $form.Controls.Add($splitPanel)
    $splitPanel.Panel1.Controls.Add($dgv)

    $txtLog = New-Object System.Windows.Forms.TextBox
    $txtLog.Multiline = $true
    $txtLog.ReadOnly = $true
    $txtLog.ScrollBars = "Vertical"
    $txtLog.Dock = "Fill"
    $txtLog.BackColor = [System.Drawing.ColorTranslator]::FromHtml("#0d1117")
    $txtLog.ForeColor = [System.Drawing.ColorTranslator]::FromHtml("#c9d1d9")
    $txtLog.Font = New-Object System.Drawing.Font("Consolas", 9)
    $splitPanel.Panel2.Controls.Add($txtLog)

    # ── Bottom Button Panel ──
    $panelBtn = New-Object System.Windows.Forms.Panel
    $panelBtn.Dock = "Bottom"
    $panelBtn.Height = 50
    $panelBtn.BackColor = [System.Drawing.ColorTranslator]::FromHtml("#161b22")
    $form.Controls.Add($panelBtn)

    $btnScan = New-Object System.Windows.Forms.Button
    $btnScan.Text = "Run Audit"
    $btnScan.Size = New-Object System.Drawing.Size(140, 35)
    $btnScan.Location = New-Object System.Drawing.Point(10, 8)
    $btnScan.BackColor = [System.Drawing.ColorTranslator]::FromHtml($COLOR_ACCENT)
    $btnScan.ForeColor = [System.Drawing.Color]::White
    $btnScan.FlatStyle = "Flat"
    $btnScan.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $btnScan.Cursor = [System.Windows.Forms.Cursors]::Hand
    $panelBtn.Controls.Add($btnScan)

    $lblScore = New-Object System.Windows.Forms.Label
    $lblScore.Text = "Score: -- / --"
    $lblScore.ForeColor = [System.Drawing.Color]::White
    $lblScore.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
    $lblScore.AutoSize = $true
    $lblScore.Location = New-Object System.Drawing.Point(170, 14)
    $panelBtn.Controls.Add($lblScore)

    $btnReport = New-Object System.Windows.Forms.Button
    $btnReport.Text = "Generate Report"
    $btnReport.Size = New-Object System.Drawing.Size(150, 35)
    $btnReport.Location = New-Object System.Drawing.Point(500, 8)
    $btnReport.BackColor = [System.Drawing.ColorTranslator]::FromHtml($COLOR_GREEN)
    $btnReport.ForeColor = [System.Drawing.Color]::White
    $btnReport.FlatStyle = "Flat"
    $btnReport.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $btnReport.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btnReport.Enabled = $false
    $panelBtn.Controls.Add($btnReport)

    $btnScan.Add_Click({
        $btnScan.Enabled = $false
        $dgv.Rows.Clear()
        $txtLog.Clear()
        $script:Score = 0
        $script:MaxScore = 0
        $script:Services.Clear()
        $script:Recommendations.Clear()
        $script:InstalledProgs = $null

        $txtLog.AppendText("=== PC Plus Computing 360 - Cloud Backup & Sync Audit ===`r`n")
        $txtLog.AppendText("Computer: $($env:COMPUTERNAME) | $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`r`n")
        $txtLog.AppendText("$('=' * 60)`r`n`r`n")
        [System.Windows.Forms.Application]::DoEvents()

        # Run all service checks
        Test-OneDrive -Log $txtLog;     [System.Windows.Forms.Application]::DoEvents()
        Test-GoogleDrive -Log $txtLog;  [System.Windows.Forms.Application]::DoEvents()
        Test-Dropbox -Log $txtLog;      [System.Windows.Forms.Application]::DoEvents()
        Test-iCloud -Log $txtLog;       [System.Windows.Forms.Application]::DoEvents()
        Test-BoxDrive -Log $txtLog;     [System.Windows.Forms.Application]::DoEvents()
        Test-Mega -Log $txtLog;         [System.Windows.Forms.Application]::DoEvents()
        Test-pCloud -Log $txtLog;       [System.Windows.Forms.Application]::DoEvents()
        Test-Carbonite -Log $txtLog;    [System.Windows.Forms.Application]::DoEvents()
        Test-Backblaze -Log $txtLog;    [System.Windows.Forms.Application]::DoEvents()
        Test-CrashPlan -Log $txtLog;    [System.Windows.Forms.Application]::DoEvents()
        Test-Acronis -Log $txtLog;      [System.Windows.Forms.Application]::DoEvents()
        Test-VeeamAgent -Log $txtLog;   [System.Windows.Forms.Application]::DoEvents()

        # 2FA check
        $has2FA = Test-TwoFactorApps -Log $txtLog
        [System.Windows.Forms.Application]::DoEvents()

        # Build recommendations
        Build-Recommendations

        # Populate grid
        foreach ($s in $script:Services) {
            $statusText = if (-not $s.Installed) { "Not Installed" } elseif ($s.ProcessRunning) { "Running" } else { "Stopped" }
            $encText    = "$(if($s.EncryptionAtRest){'Rest'}else{'-'}) / $(if($s.EncryptionInTransit){'Transit'}else{'-'})"
            $ynVer      = if ($s.HasVersioning) { "Yes" } else { "No" }
            $ynRansomware = if ($s.RansomwareRollback) { "Yes" } else { "No" }
            $ynAutoStart  = if ($s.AutoStart) { "Yes" } else { "No" }
            $folderInfo = if ($s.SyncFolder) { "$($s.SyncFolder) ($($s.SyncFolderSizeGB) GB)" } else { "-" }
            $scoreText  = "$($s.ScoreContribution)/$($s.MaxContribution)"

            $rowIdx = $dgv.Rows.Add($s.Name, $statusText, $s.Type, $s.Version, $ynVer, $encText, $ynRansomware, $ynAutoStart, $folderInfo, $scoreText)

            # Color the status cell
            $row = $dgv.Rows[$rowIdx]
            $statusCell = $row.Cells[1]
            if (-not $s.Installed) {
                $statusCell.Style.ForeColor = [System.Drawing.ColorTranslator]::FromHtml("#484f58")
            } elseif ($s.ProcessRunning) {
                $statusCell.Style.ForeColor = [System.Drawing.ColorTranslator]::FromHtml("#27ae60")
            } else {
                $statusCell.Style.ForeColor = [System.Drawing.ColorTranslator]::FromHtml("#f39c12")
            }
        }

        # Score
        $finalScore = if ($script:MaxScore -gt 0) { [Math]::Round(($script:Score / $script:MaxScore) * 100) } else { 0 }
        $grade = Get-LetterGrade $finalScore
        $gradeColor = Get-GradeColor $grade

        $lblScore.Text = "Score: $finalScore / 100 ($grade)"
        $lblScore.ForeColor = [System.Drawing.ColorTranslator]::FromHtml($gradeColor)

        $txtLog.AppendText("`r`n$('=' * 60)`r`n")
        $txtLog.AppendText("CLOUD BACKUP SCORE: $finalScore / 100 (Grade: $grade)`r`n")

        if ($script:Recommendations.Count -gt 0) {
            $txtLog.AppendText("`r`nRecommendations:`r`n")
            foreach ($rec in $script:Recommendations) {
                $txtLog.AppendText("  - $rec`r`n")
            }
        }

        $txtLog.AppendText("$('=' * 60)`r`n")

        $btnScan.Enabled = $true
        $btnReport.Enabled = $true
    })

    $btnReport.Add_Click({
        $htmlFile = New-HtmlReport
        $jsonFile = New-JsonReport

        $txtLog.AppendText("`r`nHTML Report: $htmlFile`r`n")
        $txtLog.AppendText("JSON Report: $jsonFile`r`n")

        try { Start-Process $htmlFile } catch { }

        [System.Windows.Forms.MessageBox]::Show(
            "Reports generated:`n`n- HTML: $htmlFile`n- JSON: $jsonFile",
            "Report Generated",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        )
    })

    # Show form
    $form.Add_Shown({ $form.Activate() })
    [void]$form.ShowDialog()
    $form.Dispose()
}

# ═══════════════════════════════════════════════════════════════════════════════
# ENTRY POINT
# ═══════════════════════════════════════════════════════════════════════════════

Show-MainForm

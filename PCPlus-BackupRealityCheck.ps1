<#
.SYNOPSIS
    PC Plus Computing - Backup Reality Check & Ransomware Recovery Readiness
.DESCRIPTION
    Validates all backup methods on a Windows PC, scores ransomware recovery
    readiness, and generates a branded HTML report. Checks Windows Backup,
    System Restore, VSS, cloud sync (OneDrive/GDrive/Dropbox), third-party
    backup software, recovery partition, and 3-2-1 rule compliance.
.NOTES
    Company:  PC Plus Computing
    Phone:    604-760-1662 | 236-500-2700
    Website:  pcpluscomputing.com
    Version:  1.0.0
    Requires: PowerShell 5.1+, Windows 10/11, Administrator privileges
.EXAMPLE
    PowerShell.exe -ExecutionPolicy Bypass -File .\PCPlus-BackupRealityCheck.ps1
#>

#Requires -Version 5.1
$ErrorActionPreference = 'Continue'

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
        $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$($MyInvocation.MyCommand.Definition)`""
        Start-Process powershell.exe -ArgumentList $arguments -Verb RunAs
    } catch {
        Write-Host "ERROR: This tool requires Administrator privileges." -ForegroundColor Red
        Write-Host "Please right-click and select 'Run as Administrator'." -ForegroundColor Yellow
    }
    exit
}

trap {
    Write-Host ""
    Write-Host "  UNEXPECTED ERROR: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "  Line: $($_.InvocationInfo.ScriptLineNumber)" -ForegroundColor DarkGray
    Write-Host ""
    Read-Host "  Press Enter to exit"
    break
}

# ─────────────────────────────────────────────────────────────────────────────
# BRANDING
# ─────────────────────────────────────────────────────────────────────────────
$COMPANY_NAME    = "PC Plus Computing"
$COMPANY_PHONE   = "604-760-1662 | 236-500-2700"
$COMPANY_WEBSITE = "pcpluscomputing.com"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
if ([string]::IsNullOrEmpty($ScriptDir)) { $ScriptDir = Get-Location }
$ReportDir = Join-Path $ScriptDir "reports"
if (-not (Test-Path $ReportDir)) { New-Item -ItemType Directory -Path $ReportDir -Force | Out-Null }

$Timestamp   = Get-Date -Format "yyyyMMdd-HHmmss"
$ComputerSafe = $env:COMPUTERNAME -replace '[^\w\-]', '_'
$HtmlFile    = Join-Path $ReportDir "PCPlus-BackupRealityCheck-$ComputerSafe-$Timestamp.html"

# ─────────────────────────────────────────────────────────────────────────────
# HELPERS
# ─────────────────────────────────────────────────────────────────────────────
function Write-Section {
    param([string]$Title)
    Write-Host ""
    Write-Host ("=" * 70) -ForegroundColor Cyan
    Write-Host "  $Title" -ForegroundColor Cyan
    Write-Host ("=" * 70) -ForegroundColor Cyan
}

function Write-Check {
    param([string]$Label, [string]$Value, [string]$Status = "INFO")
    $color = switch ($Status) {
        "PASS" { "Green" }
        "WARN" { "Yellow" }
        "FAIL" { "Red" }
        default { "White" }
    }
    Write-Host "  [$(($Status).PadRight(4))] " -ForegroundColor $color -NoNewline
    Write-Host "$Label : " -ForegroundColor Gray -NoNewline
    Write-Host "$Value" -ForegroundColor $color
}

function HtmlEncode {
    param([string]$Text)
    if ($null -eq $Text) { return "" }
    $Text.Replace("&","&amp;").Replace("<","&lt;").Replace(">","&gt;").Replace('"',"&quot;")
}

function Get-DaysAgo {
    param([datetime]$Date)
    return [math]::Round(((Get-Date) - $Date).TotalDays, 1)
}

function Get-AgeStatus {
    param([double]$Days)
    if ($Days -le 7)  { return "PASS" }
    if ($Days -le 30) { return "WARN" }
    return "FAIL"
}

function Get-AgeLabel {
    param([double]$Days)
    if ($Days -le 1)   { return "Today" }
    if ($Days -le 7)   { return "$([math]::Floor($Days)) days ago (OK)" }
    if ($Days -le 30)  { return "$([math]::Floor($Days)) days ago (Getting old)" }
    if ($Days -le 90)  { return "$([math]::Floor($Days)) days ago (STALE)" }
    return "$([math]::Floor($Days)) days ago (CRITICAL)" }

# ─────────────────────────────────────────────────────────────────────────────
# DATA COLLECTION
# ─────────────────────────────────────────────────────────────────────────────
$results = @{
    ComputerName   = $env:COMPUTERNAME
    ScanDate       = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Score          = 0
    MaxScore       = 100
    Findings       = New-Object System.Collections.ArrayList
    WindowsBackup  = @{}
    SystemRestore  = @{}
    VSS            = @{}
    OneDrive       = @{}
    GoogleDrive    = @{}
    Dropbox        = @{}
    ThirdParty     = @{}
    RecoveryPart   = @{}
    Ransomware     = @{}
    BackupAge      = @{}
}

$score = 0

# ─────────────────────────────────────────────────────────────────────────────
# 1. WINDOWS BACKUP / FILE HISTORY
# ─────────────────────────────────────────────────────────────────────────────
Write-Section "Windows Backup / File History"

$wb = @{ Enabled = $false; LastBackupDate = "N/A"; DestinationHealth = "N/A"; Details = "" }

try {
    # Check File History via registry
    $fhKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\FileHistory"
    $fhEnabled = $false
    if (Test-Path $fhKey) {
        $protVal = (Get-ItemProperty -Path $fhKey -Name "ProtectedUpToTime" -ErrorAction SilentlyContinue).ProtectedUpToTime
        if ($protVal) { $fhEnabled = $true }
    }

    # Also check via fhmanagew
    try {
        $fhStatus = & fhmanagew.exe -status 2>&1
        if ($fhStatus -match "File History is on" -or $fhStatus -match "turned on") {
            $fhEnabled = $true
        }
    } catch { }

    # Check WBAdmin for system-level backups
    $wbadminResult = $null
    try {
        $wbadminResult = & wbadmin.exe get versions 2>&1
    } catch { }

    $lastBackupDate = $null
    if ($wbadminResult) {
        foreach ($line in $wbadminResult) {
            if ($line -match "Backup time:\s*(.+)") {
                try {
                    $parsed = [datetime]::Parse($Matches[1].Trim())
                    if ($null -eq $lastBackupDate -or $parsed -gt $lastBackupDate) {
                        $lastBackupDate = $parsed
                    }
                } catch { }
            }
        }
    }

    if ($fhEnabled) {
        $wb.Enabled = $true
        Write-Check "File History" "Enabled" "PASS"
    } else {
        Write-Check "File History" "Not enabled or not configured" "WARN"
    }

    if ($lastBackupDate) {
        $wb.LastBackupDate = $lastBackupDate.ToString("yyyy-MM-dd HH:mm")
        $daysAgo = Get-DaysAgo $lastBackupDate
        Write-Check "Last Windows Backup" (Get-AgeLabel $daysAgo) (Get-AgeStatus $daysAgo)
    } else {
        Write-Check "Last Windows Backup" "No Windows Backup history found" "WARN"
    }

    # Check backup target drives
    try {
        $backupTargets = Get-WmiObject -Class Win32_Volume -ErrorAction SilentlyContinue |
            Where-Object { $_.Label -match "backup|archive|bak" -or $_.DriveType -eq 2 } |
            Select-Object DriveLetter, Label, Capacity, FreeSpace
        if ($backupTargets) {
            $wb.DestinationHealth = "External/backup drive detected"
            foreach ($bt in $backupTargets) {
                $lbl = if ($bt.Label) { $bt.Label } else { "Removable" }
                Write-Check "Backup Drive" "$($bt.DriveLetter) - $lbl" "PASS"
            }
        } else {
            $wb.DestinationHealth = "No dedicated backup drive detected"
        }
    } catch {
        $wb.DestinationHealth = "Could not enumerate volumes"
    }

    $wb.Details = "FileHistory=$($wb.Enabled), LastBackup=$($wb.LastBackupDate)"
} catch {
    $wb.Details = "Error checking Windows Backup: $($_.Exception.Message)"
    Write-Check "Windows Backup" "Error checking status" "FAIL"
}

$results.WindowsBackup = $wb

# ─────────────────────────────────────────────────────────────────────────────
# 2. SYSTEM RESTORE
# ─────────────────────────────────────────────────────────────────────────────
Write-Section "System Restore"

$sr = @{ Enabled = $false; PointCount = 0; OldestPoint = "N/A"; NewestPoint = "N/A"; Details = "" }

try {
    $srStatus = Get-WmiObject -Class Win32_OperatingSystem -ErrorAction SilentlyContinue
    $srEnabled = $false

    # Check if System Restore is enabled on system drive
    try {
        $srConfig = Get-ComputerRestorePoint -ErrorAction SilentlyContinue
        if ($null -ne $srConfig) {
            $srEnabled = $true
            $sr.PointCount = @($srConfig).Count
            if ($sr.PointCount -gt 0) {
                $sorted = $srConfig | Sort-Object -Property CreationTime
                $oldest = $sorted[0]
                $newest = $sorted[$sorted.Count - 1]
                try {
                    $oldDate = [Management.ManagementDateTimeConverter]::ToDateTime($oldest.CreationTime)
                    $newDate = [Management.ManagementDateTimeConverter]::ToDateTime($newest.CreationTime)
                    $sr.OldestPoint = $oldDate.ToString("yyyy-MM-dd HH:mm")
                    $sr.NewestPoint = $newDate.ToString("yyyy-MM-dd HH:mm")
                } catch {
                    $sr.OldestPoint = $oldest.CreationTime
                    $sr.NewestPoint = $newest.CreationTime
                }
            }
        }
    } catch { }

    # Also verify via vssadmin
    try {
        $vssCheck = & vssadmin.exe list shadowstorage 2>&1
        if ($vssCheck -and -not ($vssCheck -match "Error")) {
            $srEnabled = $true
        }
    } catch { }

    $sr.Enabled = $srEnabled

    if ($srEnabled) {
        Write-Check "System Restore" "Enabled" "PASS"
        Write-Check "Restore Points" "$($sr.PointCount) found" $(if ($sr.PointCount -ge 2) { "PASS" } else { "WARN" })
        if ($sr.OldestPoint -ne "N/A") {
            Write-Check "Oldest Point" $sr.OldestPoint "INFO"
            Write-Check "Newest Point" $sr.NewestPoint "INFO"
        }
    } else {
        Write-Check "System Restore" "Not enabled or no restore points" "FAIL"
    }

    $sr.Details = "Enabled=$($sr.Enabled), Points=$($sr.PointCount)"
} catch {
    $sr.Details = "Error checking System Restore: $($_.Exception.Message)"
    Write-Check "System Restore" "Error checking" "FAIL"
}

$results.SystemRestore = $sr

# ─────────────────────────────────────────────────────────────────────────────
# 3. SHADOW COPIES (VSS)
# ─────────────────────────────────────────────────────────────────────────────
Write-Section "Volume Shadow Copies (VSS)"

$vss = @{ CopiesPresent = $false; Count = 0; TotalSizeGB = 0; MaxSizeGB = 0; Details = "" }

try {
    $shadows = $null
    try {
        $shadows = Get-WmiObject -Class Win32_ShadowCopy -ErrorAction SilentlyContinue
    } catch { }

    if ($shadows) {
        $vss.CopiesPresent = $true
        $vss.Count = @($shadows).Count
        Write-Check "Shadow Copies" "$($vss.Count) found" "PASS"
    } else {
        Write-Check "Shadow Copies" "None found" "WARN"
    }

    # Shadow storage allocation
    try {
        $storageOut = & vssadmin.exe list shadowstorage 2>&1
        foreach ($line in $storageOut) {
            if ($line -match "Used Shadow Copy Storage space:\s*(.+)") {
                $vss.Details += "Used: $($Matches[1].Trim()); "
            }
            if ($line -match "Maximum Shadow Copy Storage space:\s*(.+)") {
                $vss.Details += "Max: $($Matches[1].Trim()); "
            }
            if ($line -match "Allocated Shadow Copy Storage space:\s*(.+)") {
                $vss.Details += "Allocated: $($Matches[1].Trim()); "
            }
        }
        if ($vss.Details) {
            Write-Check "VSS Storage" $vss.Details.TrimEnd("; ") "INFO"
        }
    } catch { }
} catch {
    $vss.Details = "Error: $($_.Exception.Message)"
    Write-Check "VSS" "Error checking shadow copies" "FAIL"
}

$results.VSS = $vss

# ─────────────────────────────────────────────────────────────────────────────
# 4. ONEDRIVE SYNC
# ─────────────────────────────────────────────────────────────────────────────
Write-Section "OneDrive Sync"

$od = @{ Installed = $false; SignedIn = $false; SyncActive = $false; KFMEnabled = $false; Path = ""; Details = "" }

try {
    # Check if OneDrive process is running
    $odProcess = Get-Process -Name "OneDrive" -ErrorAction SilentlyContinue
    $od.Installed = $null -ne $odProcess
    if ($odProcess) { $od.SyncActive = $true }

    # Check OneDrive installation
    $odPaths = @(
        "$env:LOCALAPPDATA\Microsoft\OneDrive\OneDrive.exe",
        "$env:ProgramFiles\Microsoft OneDrive\OneDrive.exe",
        "${env:ProgramFiles(x86)}\Microsoft OneDrive\OneDrive.exe"
    )
    foreach ($p in $odPaths) {
        if (Test-Path $p) { $od.Installed = $true; break }
    }

    # Check OneDrive account registry
    $odAccountsKey = "HKCU:\SOFTWARE\Microsoft\OneDrive\Accounts"
    if (Test-Path $odAccountsKey) {
        $accounts = Get-ChildItem $odAccountsKey -ErrorAction SilentlyContinue
        foreach ($acc in $accounts) {
            $userFolder = (Get-ItemProperty -Path $acc.PSPath -Name "UserFolder" -ErrorAction SilentlyContinue).UserFolder
            if ($userFolder -and (Test-Path $userFolder)) {
                $od.SignedIn = $true
                $od.Path = $userFolder
            }
        }
    }

    # Check Known Folder Move (KFM) - Desktop, Documents, Pictures
    $kfmKey = "HKCU:\SOFTWARE\Microsoft\OneDrive\Accounts\Personal"
    if (Test-Path $kfmKey) {
        $kfmDesktop = (Get-ItemProperty -Path $kfmKey -Name "KfmFoldersProtectedNow" -ErrorAction SilentlyContinue).KfmFoldersProtectedNow
        if ($kfmDesktop) { $od.KFMEnabled = $true }
    }
    # Also check Business account
    $kfmBizKey = "HKCU:\SOFTWARE\Microsoft\OneDrive\Accounts\Business1"
    if (Test-Path $kfmBizKey) {
        $kfmBiz = (Get-ItemProperty -Path $kfmBizKey -Name "KfmFoldersProtectedNow" -ErrorAction SilentlyContinue).KfmFoldersProtectedNow
        if ($kfmBiz) { $od.KFMEnabled = $true }
    }

    if ($od.Installed) {
        Write-Check "OneDrive" "Installed" "PASS"
    } else {
        Write-Check "OneDrive" "Not installed" "WARN"
    }
    if ($od.SignedIn) {
        Write-Check "Signed In" "Yes - $($od.Path)" "PASS"
    } elseif ($od.Installed) {
        Write-Check "Signed In" "Not signed in" "WARN"
    }
    if ($od.SyncActive) {
        Write-Check "Sync Status" "Process running" "PASS"
    } elseif ($od.Installed) {
        Write-Check "Sync Status" "Process not running" "WARN"
    }
    if ($od.KFMEnabled) {
        Write-Check "Known Folder Move" "Enabled (Desktop/Documents/Pictures backed up)" "PASS"
    } elseif ($od.Installed -and $od.SignedIn) {
        Write-Check "Known Folder Move" "Not enabled" "WARN"
    }

    $od.Details = "Installed=$($od.Installed), SignedIn=$($od.SignedIn), Sync=$($od.SyncActive), KFM=$($od.KFMEnabled)"
} catch {
    $od.Details = "Error: $($_.Exception.Message)"
    Write-Check "OneDrive" "Error checking" "FAIL"
}

$results.OneDrive = $od

# ─────────────────────────────────────────────────────────────────────────────
# 5. GOOGLE DRIVE
# ─────────────────────────────────────────────────────────────────────────────
Write-Section "Google Drive"

$gd = @{ Installed = $false; SyncActive = $false; Path = ""; Details = "" }

try {
    $gdProcess = Get-Process -Name "GoogleDriveFS" -ErrorAction SilentlyContinue
    if ($gdProcess) {
        $gd.Installed = $true
        $gd.SyncActive = $true
    }

    # Check common install locations
    $gdPaths = @(
        "$env:ProgramFiles\Google\Drive File Stream\launch.bat",
        "$env:ProgramFiles\Google\Drive File Stream\GoogleDriveFS.exe",
        "${env:ProgramFiles(x86)}\Google\Drive File Stream\GoogleDriveFS.exe",
        "$env:LOCALAPPDATA\Google\DriveFS\GoogleDriveFS.exe"
    )
    foreach ($p in $gdPaths) {
        if (Test-Path $p) { $gd.Installed = $true; break }
    }

    # Check for Google Drive virtual drive (G:\ typically)
    $gdDrives = Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue |
        Where-Object { $_.Description -match "Google" -or $_.Root -match "Google" }
    if ($gdDrives) {
        $gd.SyncActive = $true
        $gd.Path = ($gdDrives | Select-Object -First 1).Root
    }

    if ($gd.Installed) {
        Write-Check "Google Drive" "Installed" "PASS"
    } else {
        Write-Check "Google Drive" "Not installed" "INFO"
    }
    if ($gd.SyncActive) {
        Write-Check "Sync Status" "Active" "PASS"
    } elseif ($gd.Installed) {
        Write-Check "Sync Status" "Not running" "WARN"
    }

    $gd.Details = "Installed=$($gd.Installed), Sync=$($gd.SyncActive)"
} catch {
    $gd.Details = "Error: $($_.Exception.Message)"
    Write-Check "Google Drive" "Error checking" "FAIL"
}

$results.GoogleDrive = $gd

# ─────────────────────────────────────────────────────────────────────────────
# 6. DROPBOX
# ─────────────────────────────────────────────────────────────────────────────
Write-Section "Dropbox"

$db = @{ Installed = $false; SyncActive = $false; Path = ""; Details = "" }

try {
    $dbProcess = Get-Process -Name "Dropbox" -ErrorAction SilentlyContinue
    if ($dbProcess) {
        $db.Installed = $true
        $db.SyncActive = $true
    }

    # Check common locations
    $dbPaths = @(
        "$env:LOCALAPPDATA\Dropbox\Dropbox.exe",
        "$env:APPDATA\Dropbox\bin\Dropbox.exe",
        "$env:ProgramFiles\Dropbox\Client\Dropbox.exe",
        "${env:ProgramFiles(x86)}\Dropbox\Client\Dropbox.exe"
    )
    foreach ($p in $dbPaths) {
        if (Test-Path $p) { $db.Installed = $true; break }
    }

    # Check for Dropbox folder
    $dbInfoPath = "$env:LOCALAPPDATA\Dropbox\info.json"
    if (Test-Path $dbInfoPath) {
        $db.Installed = $true
        try {
            $dbInfo = Get-Content $dbInfoPath -Raw -ErrorAction SilentlyContinue | ConvertFrom-Json
            if ($dbInfo.personal.path) { $db.Path = $dbInfo.personal.path }
            elseif ($dbInfo.business.path) { $db.Path = $dbInfo.business.path }
        } catch { }
    }

    if ($db.Installed) {
        Write-Check "Dropbox" "Installed" "PASS"
    } else {
        Write-Check "Dropbox" "Not installed" "INFO"
    }
    if ($db.SyncActive) {
        Write-Check "Sync Status" "Active" "PASS"
    } elseif ($db.Installed) {
        Write-Check "Sync Status" "Not running" "WARN"
    }

    $db.Details = "Installed=$($db.Installed), Sync=$($db.SyncActive)"
} catch {
    $db.Details = "Error: $($_.Exception.Message)"
    Write-Check "Dropbox" "Error checking" "FAIL"
}

$results.Dropbox = $db

# ─────────────────────────────────────────────────────────────────────────────
# 7. THIRD-PARTY BACKUP SOFTWARE
# ─────────────────────────────────────────────────────────────────────────────
Write-Section "Third-Party Backup Software"

$tp = @{ DetectedSoftware = New-Object System.Collections.ArrayList; Details = "" }

$backupProducts = @(
    @{ Name = "Acronis";     Process = "TrueImageMonitor"; Service = "AcrSch2Svc";   Paths = @("$env:ProgramFiles\Acronis","${env:ProgramFiles(x86)}\Acronis") }
    @{ Name = "Veeam Agent"; Process = "VeeamAgent";       Service = "VeeamEndpointBackupSvc"; Paths = @("$env:ProgramFiles\Veeam") }
    @{ Name = "Carbonite";   Process = "CarboniteUI";      Service = "CarboniteService"; Paths = @("$env:ProgramFiles\Carbonite","${env:ProgramFiles(x86)}\Carbonite") }
    @{ Name = "Backblaze";   Process = "bzbui";            Service = "backblaze";    Paths = @("$env:ProgramFiles\Backblaze","${env:ProgramFiles(x86)}\Backblaze","$env:ProgramData\Backblaze") }
    @{ Name = "CrashPlan";   Process = "CrashPlanDesktop"; Service = "CrashPlanService"; Paths = @("$env:ProgramFiles\CrashPlan","${env:ProgramFiles(x86)}\CrashPlan") }
    @{ Name = "Macrium Reflect"; Process = "ReflectUI";    Service = "ReflectService"; Paths = @("$env:ProgramFiles\Macrium") }
    @{ Name = "EaseUS Todo Backup"; Process = "TbService"; Service = "EaseUS Agent"; Paths = @("$env:ProgramFiles\EaseUS","${env:ProgramFiles(x86)}\EaseUS") }
    @{ Name = "Paragon Backup"; Process = "ParagonBackup"; Service = "ParagonService"; Paths = @("$env:ProgramFiles\Paragon Software") }
    @{ Name = "AOMEI Backupper"; Process = "ABService";    Service = "ABService";    Paths = @("$env:ProgramFiles\AOMEI","${env:ProgramFiles(x86)}\AOMEI") }
    @{ Name = "MSP360 (CloudBerry)"; Process = "CloudBerryBackup"; Service = "CloudBerry Backup Service"; Paths = @("$env:ProgramFiles\MSP360","$env:ProgramFiles\CloudBerryLab") }
    @{ Name = "IDrive";      Process = "IDriveETray";      Service = "IDriveService"; Paths = @("$env:ProgramFiles\IDrive","${env:ProgramFiles(x86)}\IDrive") }
    @{ Name = "Windows Server Backup"; Process = "";       Service = "wbengine";     Paths = @() }
)

foreach ($product in $backupProducts) {
    $found = $false
    $method = ""

    # Check process
    if ($product.Process -and (Get-Process -Name $product.Process -ErrorAction SilentlyContinue)) {
        $found = $true
        $method = "Running process"
    }

    # Check service
    if (-not $found -and $product.Service) {
        $svc = Get-Service -Name $product.Service -ErrorAction SilentlyContinue
        if ($svc) {
            $found = $true
            $method = "Service: $($svc.Status)"
        }
    }

    # Check install paths
    if (-not $found) {
        foreach ($p in $product.Paths) {
            if (Test-Path $p) {
                $found = $true
                $method = "Installed at $p"
                break
            }
        }
    }

    if ($found) {
        [void]$tp.DetectedSoftware.Add(@{ Name = $product.Name; Method = $method })
        Write-Check $product.Name $method "PASS"
    }
}

if ($tp.DetectedSoftware.Count -eq 0) {
    Write-Check "Third-Party Backup" "No third-party backup software detected" "WARN"
}

$tp.Details = "Found $($tp.DetectedSoftware.Count) backup products"
$results.ThirdParty = $tp

# ─────────────────────────────────────────────────────────────────────────────
# 8. RECOVERY PARTITION
# ─────────────────────────────────────────────────────────────────────────────
Write-Section "Recovery Partition"

$rp = @{ Present = $false; Healthy = $false; SizeMB = 0; Details = "" }

try {
    # Check WinRE status
    try {
        $reagentc = & reagentc.exe /info 2>&1
        foreach ($line in $reagentc) {
            if ($line -match "Windows RE status:\s*(Enabled|Disabled)") {
                if ($Matches[1] -eq "Enabled") {
                    $rp.Present = $true
                    $rp.Healthy = $true
                }
            }
        }
    } catch { }

    # Check for recovery partitions via WMI
    try {
        $recParts = Get-WmiObject -Class Win32_Partition -ErrorAction SilentlyContinue |
            Where-Object { $_.Type -match "Recovery" -or $_.Type -match "OEM" }
        if ($recParts) {
            $rp.Present = $true
            foreach ($part in $recParts) {
                $rp.SizeMB += [math]::Round($part.Size / 1MB, 0)
            }
        }
    } catch { }

    if ($rp.Present -and $rp.Healthy) {
        Write-Check "Recovery Partition" "Present and healthy (WinRE enabled)" "PASS"
    } elseif ($rp.Present) {
        Write-Check "Recovery Partition" "Present but WinRE may be disabled" "WARN"
    } else {
        Write-Check "Recovery Partition" "Not detected" "FAIL"
    }

    if ($rp.SizeMB -gt 0) {
        Write-Check "Recovery Size" "$($rp.SizeMB) MB" "INFO"
    }

    $rp.Details = "Present=$($rp.Present), Healthy=$($rp.Healthy), Size=$($rp.SizeMB)MB"
} catch {
    $rp.Details = "Error: $($_.Exception.Message)"
    Write-Check "Recovery Partition" "Error checking" "FAIL"
}

$results.RecoveryPart = $rp

# ─────────────────────────────────────────────────────────────────────────────
# 9. RANSOMWARE READINESS ASSESSMENT
# ─────────────────────────────────────────────────────────────────────────────
Write-Section "Ransomware Recovery Readiness"

$rr = @{
    SeparateDrive       = $false
    VersionedBackups    = $false
    AirGapped           = $false
    ThreeTwoOneCompliant = $false
    ControlledFolderAccess = $false
    Details             = ""
    Recommendations     = New-Object System.Collections.ArrayList
}

try {
    # Check if backups are on a separate drive/network
    $separateDriveDetected = $false
    # Check for USB/external drives
    try {
        $usbDisks = Get-WmiObject -Class Win32_DiskDrive -ErrorAction SilentlyContinue |
            Where-Object { $_.InterfaceType -eq "USB" -or $_.MediaType -match "External" }
        if ($usbDisks) { $separateDriveDetected = $true }
    } catch { }
    # Check for network drives
    $netDrives = Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue |
        Where-Object { $_.Root -match '^\\\\'  }
    if ($netDrives) { $separateDriveDetected = $true }
    $rr.SeparateDrive = $separateDriveDetected

    if ($rr.SeparateDrive) {
        Write-Check "Separate Backup Drive" "External or network drive detected" "PASS"
    } else {
        Write-Check "Separate Backup Drive" "No separate backup destination found" "FAIL"
        [void]$rr.Recommendations.Add("Connect an external USB drive or network share for backups")
    }

    # Check for versioned backups
    $hasVersioning = $false
    if ($wb.Enabled) { $hasVersioning = $true }  # File History has versioning
    if ($vss.CopiesPresent) { $hasVersioning = $true }
    if ($od.SignedIn) { $hasVersioning = $true }  # OneDrive has version history
    foreach ($sw in $tp.DetectedSoftware) {
        if ($sw.Name -match "Acronis|Veeam|Macrium|Backblaze|CrashPlan|Carbonite") {
            $hasVersioning = $true
        }
    }
    $rr.VersionedBackups = $hasVersioning

    if ($rr.VersionedBackups) {
        Write-Check "Versioned Backups" "Can roll back to previous versions" "PASS"
    } else {
        Write-Check "Versioned Backups" "No versioning detected" "FAIL"
        [void]$rr.Recommendations.Add("Enable File History or use backup software with versioning")
    }

    # Air-gapped backup detection (external drive not currently connected, or cloud with offline archive)
    $rr.AirGapped = $false
    foreach ($sw in $tp.DetectedSoftware) {
        if ($sw.Name -match "Backblaze|CrashPlan|Carbonite|IDrive") {
            $rr.AirGapped = $true  # Cloud-only backups are effectively air-gapped from local ransomware
        }
    }
    # If OneDrive/GDrive/Dropbox are synced, they provide some air-gap
    if ($od.SignedIn -or $gd.SyncActive -or $db.SyncActive) {
        # Cloud sync is partial - ransomware can encrypt synced files, but versioning helps
        # We mark this as partial
    }

    if ($rr.AirGapped) {
        Write-Check "Air-Gapped Backup" "Cloud backup service detected (off-site)" "PASS"
    } else {
        Write-Check "Air-Gapped Backup" "No air-gapped or cloud-only backup detected" "WARN"
        [void]$rr.Recommendations.Add("Consider a cloud-only backup service (Backblaze, CrashPlan) for air-gapped protection")
    }

    # 3-2-1 Rule: 3 copies, 2 different media, 1 off-site
    $backupMethodCount = 0
    $localMethods = 0
    $cloudMethods = 0

    if ($wb.Enabled) { $backupMethodCount++; $localMethods++ }
    if ($sr.Enabled -and $sr.PointCount -gt 0) { $backupMethodCount++; $localMethods++ }
    if ($od.SignedIn) { $backupMethodCount++; $cloudMethods++ }
    if ($gd.SyncActive) { $backupMethodCount++; $cloudMethods++ }
    if ($db.SyncActive) { $backupMethodCount++; $cloudMethods++ }
    foreach ($sw in $tp.DetectedSoftware) { $backupMethodCount++ }

    $has3Copies = $backupMethodCount -ge 3
    $has2Media  = ($localMethods -ge 1) -and ($cloudMethods -ge 1 -or $separateDriveDetected)
    $has1Offsite = $cloudMethods -ge 1 -or $rr.AirGapped
    $rr.ThreeTwoOneCompliant = $has3Copies -and $has2Media -and $has1Offsite

    if ($rr.ThreeTwoOneCompliant) {
        Write-Check "3-2-1 Backup Rule" "COMPLIANT" "PASS"
    } else {
        $missing = New-Object System.Collections.ArrayList
        if (-not $has3Copies)  { [void]$missing.Add("need 3+ backup copies (have $backupMethodCount)") }
        if (-not $has2Media)   { [void]$missing.Add("need 2+ different media types") }
        if (-not $has1Offsite) { [void]$missing.Add("need 1+ off-site backup") }
        Write-Check "3-2-1 Backup Rule" "NOT COMPLIANT: $($missing -join '; ')" "FAIL"
        [void]$rr.Recommendations.Add("Achieve 3-2-1 compliance: $($missing -join '; ')")
    }

    # Controlled Folder Access (Windows Defender ransomware protection)
    try {
        $cfaStatus = Get-MpPreference -ErrorAction SilentlyContinue
        if ($cfaStatus.EnableControlledFolderAccess -eq 1) {
            $rr.ControlledFolderAccess = $true
            Write-Check "Controlled Folder Access" "ENABLED (Ransomware Protection active)" "PASS"
        } else {
            Write-Check "Controlled Folder Access" "DISABLED" "WARN"
            [void]$rr.Recommendations.Add("Enable Controlled Folder Access in Windows Security > Ransomware Protection")
        }
    } catch {
        Write-Check "Controlled Folder Access" "Could not check (Defender may not be primary AV)" "WARN"
    }

    $rr.Details = "SepDrive=$($rr.SeparateDrive), Versioned=$($rr.VersionedBackups), AirGap=$($rr.AirGapped), 321=$($rr.ThreeTwoOneCompliant), CFA=$($rr.ControlledFolderAccess)"
} catch {
    $rr.Details = "Error: $($_.Exception.Message)"
    Write-Check "Ransomware Readiness" "Error during assessment" "FAIL"
}

$results.Ransomware = $rr

# ─────────────────────────────────────────────────────────────────────────────
# 10. BACKUP AGE ANALYSIS
# ─────────────────────────────────────────────────────────────────────────────
Write-Section "Backup Age Analysis"

$ba = @{ MostRecentBackupDate = $null; DaysOld = $null; AgeCategory = "UNKNOWN"; AllBackupDates = New-Object System.Collections.ArrayList }

try {
    # Gather all known backup dates
    if ($wb.LastBackupDate -ne "N/A") {
        try {
            $d = [datetime]::Parse($wb.LastBackupDate)
            [void]$ba.AllBackupDates.Add(@{ Source = "Windows Backup"; Date = $d })
        } catch { }
    }

    if ($sr.NewestPoint -ne "N/A") {
        try {
            $d = [datetime]::Parse($sr.NewestPoint)
            [void]$ba.AllBackupDates.Add(@{ Source = "System Restore"; Date = $d })
        } catch { }
    }

    # Check File History recent files
    $fhPath = "$env:LOCALAPPDATA\Microsoft\Windows\FileHistory\Configuration\Config1.xml"
    if (Test-Path $fhPath) {
        $fhModified = (Get-Item $fhPath).LastWriteTime
        [void]$ba.AllBackupDates.Add(@{ Source = "File History Config"; Date = $fhModified })
    }

    # OneDrive last sync approximation
    if ($od.Path -and (Test-Path $od.Path)) {
        $odLastMod = (Get-Item $od.Path).LastWriteTime
        [void]$ba.AllBackupDates.Add(@{ Source = "OneDrive Folder"; Date = $odLastMod })
    }

    # Find the most recent backup of any kind
    $validDates = @($ba.AllBackupDates | Where-Object { $null -ne $_.Date })
    if ($validDates.Count -gt 0) {
        $sorted = $validDates | Sort-Object { $_.Date } -Descending
        $newest = $sorted[0]
        $ba.MostRecentBackupDate = $newest.Date
        $ba.DaysOld = Get-DaysAgo $newest.Date

        if ($ba.DaysOld -le 1)     { $ba.AgeCategory = "CURRENT" }
        elseif ($ba.DaysOld -le 7) { $ba.AgeCategory = "RECENT" }
        elseif ($ba.DaysOld -le 30){ $ba.AgeCategory = "AGING" }
        elseif ($ba.DaysOld -le 90){ $ba.AgeCategory = "STALE" }
        else                       { $ba.AgeCategory = "CRITICAL" }

        $ageStatus = Get-AgeStatus $ba.DaysOld
        Write-Check "Most Recent Backup" "$($newest.Source) - $(Get-AgeLabel $ba.DaysOld)" $ageStatus

        foreach ($entry in $sorted) {
            if ($entry -ne $newest) {
                $dOld = Get-DaysAgo $entry.Date
                Write-Check "  $($entry.Source)" (Get-AgeLabel $dOld) (Get-AgeStatus $dOld)
            }
        }
    } else {
        $ba.AgeCategory = "NO_BACKUPS"
        Write-Check "Backup Age" "NO BACKUPS FOUND - CRITICAL RISK" "FAIL"
    }
} catch {
    Write-Check "Backup Age" "Error analyzing: $($_.Exception.Message)" "FAIL"
}

$results.BackupAge = $ba

# ─────────────────────────────────────────────────────────────────────────────
# SCORING
# ─────────────────────────────────────────────────────────────────────────────
Write-Section "Backup Reality Score"

# Has any backup at all: +20
$hasAnyBackup = $wb.Enabled -or ($sr.Enabled -and $sr.PointCount -gt 0) -or
                $od.SignedIn -or $gd.SyncActive -or $db.SyncActive -or
                ($tp.DetectedSoftware.Count -gt 0)
if ($hasAnyBackup) { $score += 20 }

# Backup is recent (<7 days): +20
if ($ba.DaysOld -ne $null -and $ba.DaysOld -le 7) { $score += 20 }

# Multiple backup methods: +15
$methodCount = 0
if ($wb.Enabled) { $methodCount++ }
if ($od.SignedIn) { $methodCount++ }
if ($gd.SyncActive) { $methodCount++ }
if ($db.SyncActive) { $methodCount++ }
$methodCount += $tp.DetectedSoftware.Count
if ($methodCount -ge 2) { $score += 15 }

# Off-site/cloud backup: +15
if ($od.SignedIn -or $gd.SyncActive -or $db.SyncActive -or $rr.AirGapped) { $score += 15 }

# System restore points exist: +10
if ($sr.Enabled -and $sr.PointCount -gt 0) { $score += 10 }

# Versioned backups: +10
if ($rr.VersionedBackups) { $score += 10 }

# Air-gapped backup: +10
if ($rr.AirGapped) { $score += 10 }

$results.Score = $score

# Grade calculation
$grade = if ($score -ge 85) { "A - Excellent" }
         elseif ($score -ge 70) { "B - Good" }
         elseif ($score -ge 50) { "C - Needs Improvement" }
         elseif ($score -ge 30) { "D - Poor" }
         else { "F - Critical Risk" }

$gradeColor = if ($score -ge 70) { "Green" }
              elseif ($score -ge 50) { "Yellow" }
              else { "Red" }

Write-Host ""
Write-Host "  BACKUP REALITY SCORE: $score / 100  [$grade]" -ForegroundColor $gradeColor
Write-Host ""

# Score breakdown
$breakdownItems = @(
    @{ Label = "Has any backup at all";   Points = 20; Earned = $(if ($hasAnyBackup) { 20 } else { 0 }) }
    @{ Label = "Backup is recent (<7d)";  Points = 20; Earned = $(if ($ba.DaysOld -ne $null -and $ba.DaysOld -le 7) { 20 } else { 0 }) }
    @{ Label = "Multiple backup methods";  Points = 15; Earned = $(if ($methodCount -ge 2) { 15 } else { 0 }) }
    @{ Label = "Off-site/cloud backup";    Points = 15; Earned = $(if ($od.SignedIn -or $gd.SyncActive -or $db.SyncActive -or $rr.AirGapped) { 15 } else { 0 }) }
    @{ Label = "System restore points";    Points = 10; Earned = $(if ($sr.Enabled -and $sr.PointCount -gt 0) { 10 } else { 0 }) }
    @{ Label = "Versioned backups";        Points = 10; Earned = $(if ($rr.VersionedBackups) { 10 } else { 0 }) }
    @{ Label = "Air-gapped backup";        Points = 10; Earned = $(if ($rr.AirGapped) { 10 } else { 0 }) }
)

foreach ($item in $breakdownItems) {
    $earnedStr = "$($item.Earned)/$($item.Points)"
    $st = if ($item.Earned -eq $item.Points) { "PASS" } elseif ($item.Earned -gt 0) { "WARN" } else { "FAIL" }
    Write-Check $item.Label $earnedStr $st
}

# ─────────────────────────────────────────────────────────────────────────────
# HTML REPORT
# ─────────────────────────────────────────────────────────────────────────────
Write-Section "Generating HTML Report"

$scoreColor = if ($score -ge 70) { "#16a34a" } elseif ($score -ge 50) { "#f59e0b" } else { "#dc2626" }

# Build backup method rows
$methodRows = ""
$allMethods = @()
if ($wb.Enabled) { $allMethods += @{ Name="Windows Backup / File History"; Status="Enabled"; Detail=$wb.Details } }
if ($sr.Enabled) { $allMethods += @{ Name="System Restore"; Status="$($sr.PointCount) points"; Detail="Oldest: $($sr.OldestPoint), Newest: $($sr.NewestPoint)" } }
if ($vss.CopiesPresent) { $allMethods += @{ Name="Volume Shadow Copies"; Status="$($vss.Count) copies"; Detail=$vss.Details } }
if ($od.Installed) { $allMethods += @{ Name="OneDrive"; Status=$(if($od.SignedIn){"Signed In"}else{"Installed only"}); Detail="KFM=$($od.KFMEnabled), Sync=$($od.SyncActive)" } }
if ($gd.Installed) { $allMethods += @{ Name="Google Drive"; Status=$(if($gd.SyncActive){"Active"}else{"Installed"}); Detail=$gd.Details } }
if ($db.Installed) { $allMethods += @{ Name="Dropbox"; Status=$(if($db.SyncActive){"Active"}else{"Installed"}); Detail=$db.Details } }
foreach ($sw in $tp.DetectedSoftware) { $allMethods += @{ Name=$sw.Name; Status="Detected"; Detail=$sw.Method } }

foreach ($m in $allMethods) {
    $cls = if ($m.Status -match "Enabled|Active|Signed|Detected|points") { "pass" } else { "warn" }
    $methodRows += "<tr><td>$(HtmlEncode $m.Name)</td><td class='$cls'>$(HtmlEncode $m.Status)</td><td>$(HtmlEncode $m.Detail)</td></tr>`n"
}
if ($allMethods.Count -eq 0) {
    $methodRows = "<tr><td colspan='3' class='fail'>No backup methods detected</td></tr>"
}

# Build ransomware rows
$rrChecks = @(
    @{ Check="Backups on separate drive/network"; Result=$(if($rr.SeparateDrive){"Yes"}else{"No"}); Class=$(if($rr.SeparateDrive){"pass"}else{"fail"}) }
    @{ Check="Versioned backups (can roll back)"; Result=$(if($rr.VersionedBackups){"Yes"}else{"No"}); Class=$(if($rr.VersionedBackups){"pass"}else{"fail"}) }
    @{ Check="Air-gapped / cloud-only backup"; Result=$(if($rr.AirGapped){"Yes"}else{"No"}); Class=$(if($rr.AirGapped){"pass"}else{"warn"}) }
    @{ Check="3-2-1 backup rule compliance"; Result=$(if($rr.ThreeTwoOneCompliant){"Compliant"}else{"Not Compliant"}); Class=$(if($rr.ThreeTwoOneCompliant){"pass"}else{"fail"}) }
    @{ Check="Controlled Folder Access"; Result=$(if($rr.ControlledFolderAccess){"Enabled"}else{"Disabled"}); Class=$(if($rr.ControlledFolderAccess){"pass"}else{"warn"}) }
)
$rrRows = ""
foreach ($r in $rrChecks) {
    $rrRows += "<tr><td>$(HtmlEncode $r.Check)</td><td class='$($r.Class)'>$(HtmlEncode $r.Result)</td></tr>`n"
}

# Build recommendations
$recList = ""
if ($rr.Recommendations.Count -gt 0) {
    foreach ($rec in $rr.Recommendations) {
        $recList += "<li>$(HtmlEncode $rec)</li>`n"
    }
} else {
    $recList = "<li>No critical recommendations - backup posture is healthy</li>"
}

# Score breakdown rows
$scoreRows = ""
foreach ($item in $breakdownItems) {
    $cls = if ($item.Earned -eq $item.Points) { "pass" } elseif ($item.Earned -gt 0) { "warn" } else { "fail" }
    $scoreRows += "<tr><td>$(HtmlEncode $item.Label)</td><td class='$cls'>$($item.Earned) / $($item.Points)</td></tr>`n"
}

# Backup age rows
$ageRows = ""
if ($ba.AllBackupDates.Count -gt 0) {
    $sortedDates = $ba.AllBackupDates | Sort-Object { $_.Date } -Descending
    foreach ($entry in $sortedDates) {
        $dOld = Get-DaysAgo $entry.Date
        $cls = if ($dOld -le 7) { "pass" } elseif ($dOld -le 30) { "warn" } else { "fail" }
        $ageRows += "<tr><td>$(HtmlEncode $entry.Source)</td><td>$($entry.Date.ToString('yyyy-MM-dd HH:mm'))</td><td class='$cls'>$(Get-AgeLabel $dOld)</td></tr>`n"
    }
} else {
    $ageRows = "<tr><td colspan='3' class='fail'>No backup dates found</td></tr>"
}

# Recovery partition row
$rpStatus = if ($rp.Present -and $rp.Healthy) { "Healthy" } elseif ($rp.Present) { "Present (WinRE may be disabled)" } else { "Not Detected" }
$rpClass  = if ($rp.Present -and $rp.Healthy) { "pass" } elseif ($rp.Present) { "warn" } else { "fail" }

$html = @"
<!DOCTYPE html><html><head><meta charset="utf-8"><title>PC Plus - Backup Reality Check</title>
<style>
body{font-family:'Segoe UI',Arial,sans-serif;background:#f3f8fb;margin:0;color:#163247}
.header{background:linear-gradient(135deg,#0d4b71,#2596be);color:white;padding:34px 34px 28px 34px}
.header h1{margin:0;font-size:32px;letter-spacing:-0.5px}.header p{margin:8px 0 0 0;font-size:14px;opacity:.85}
.container{padding:24px;max-width:1100px;margin:0 auto}
.card{background:white;border-radius:16px;padding:22px;margin-bottom:18px;box-shadow:0 8px 22px rgba(13,75,113,.12)}
.card h2{margin-top:0;color:#0d4b71;font-size:20px;border-bottom:2px solid #e3edf3;padding-bottom:10px}
.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(200px,1fr));gap:14px}
.metric{background:#eaf7fc;border-left:6px solid #2596be;border-radius:12px;padding:14px}
.metric b{display:block;color:#0d4b71;font-size:11px;text-transform:uppercase;margin-bottom:4px}
.metric span{font-size:17px;font-weight:700}
.score-box{text-align:center;padding:20px}
.score{font-size:72px;font-weight:800;color:$scoreColor;margin:8px 0;line-height:1}
.grade{font-size:22px;font-weight:600;color:#0d4b71}
table{width:100%;border-collapse:collapse;font-size:13px;margin-top:10px}
th{background:#0d4b71;color:white;padding:10px;text-align:left}
td{border-bottom:1px solid #dbe8ef;padding:9px;vertical-align:top}
tr:hover{background:#f0f7fc}
.pass{color:#16a34a;font-weight:700}.warn{color:#f59e0b;font-weight:700}.fail{color:#dc2626;font-weight:700}
.badge{display:inline-block;padding:6px 14px;border-radius:999px;font-weight:700;font-size:13px}
.badge-pass{background:#dcfce7;color:#16a34a}.badge-warn{background:#fef3c7;color:#92400e}.badge-fail{background:#fee2e2;color:#dc2626}
.notice{background:#fff7ed;border-left:6px solid #f59e0b;padding:14px;border-radius:12px;margin:12px 0}
.notice-danger{background:#fef2f2;border-left:6px solid #dc2626;padding:14px;border-radius:12px;margin:12px 0}
.notice-success{background:#f0fdf4;border-left:6px solid #16a34a;padding:14px;border-radius:12px;margin:12px 0}
ul{margin:8px 0;padding-left:22px}li{margin-bottom:6px}
.footer{text-align:center;padding:20px;color:#64748b;font-size:12px;border-top:1px solid #e3edf3;margin-top:20px}
@media print{.header{-webkit-print-color-adjust:exact;print-color-adjust:exact}}
</style></head><body>
<div class="header">
<h1>Backup Reality Check &amp; Ransomware Recovery Readiness</h1>
<p>$COMPANY_NAME | $COMPANY_PHONE | $COMPANY_WEBSITE</p>
</div>
<div class="container">

<div class="card">
<h2>Overview</h2>
<div class="grid">
<div class="metric"><b>Computer</b><span>$($env:COMPUTERNAME)</span></div>
<div class="metric"><b>Scan Date</b><span>$(Get-Date -Format 'yyyy-MM-dd HH:mm')</span></div>
<div class="metric"><b>Backup Methods</b><span>$($allMethods.Count) detected</span></div>
<div class="metric"><b>Most Recent</b><span>$(if($ba.MostRecentBackupDate){$ba.MostRecentBackupDate.ToString('yyyy-MM-dd')}else{'None found'})</span></div>
</div>
<div class="score-box">
<div class="score">$score / 100</div>
<div class="grade">$grade</div>
</div>
</div>

<div class="card">
<h2>Score Breakdown</h2>
<table><tr><th>Criteria</th><th>Points</th></tr>
$scoreRows
</table>
</div>

<div class="card">
<h2>Backup Methods Detected</h2>
<table><tr><th>Method</th><th>Status</th><th>Details</th></tr>
$methodRows
</table>
</div>

<div class="card">
<h2>Backup Age Timeline</h2>
<table><tr><th>Source</th><th>Date</th><th>Age</th></tr>
$ageRows
</table>
</div>

<div class="card">
<h2>Recovery Partition</h2>
<table>
<tr><th>Status</th><td class="$rpClass">$rpStatus</td></tr>
<tr><th>Size</th><td>$(if($rp.SizeMB -gt 0){"$($rp.SizeMB) MB"}else{"N/A"})</td></tr>
</table>
</div>

<div class="card">
<h2>Ransomware Recovery Readiness</h2>
<table><tr><th>Check</th><th>Result</th></tr>
$rrRows
</table>
</div>

<div class="card">
<h2>Recommendations</h2>
$(if($rr.Recommendations.Count -gt 0){'<div class="notice-danger"><strong>Action Required:</strong>'}else{'<div class="notice-success"><strong>Good posture:</strong>'})
<ul>
$recList
</ul>
</div>
</div>

<div class="card">
<h2>What is the 3-2-1 Backup Rule?</h2>
<div class="notice">
<p><strong>3</strong> copies of your data (1 primary + 2 backups)<br>
<strong>2</strong> different types of media (e.g., local drive + cloud)<br>
<strong>1</strong> off-site copy (cloud backup or remote location)</p>
<p>This is the industry gold standard for data protection against ransomware, hardware failure, theft, and natural disasters.</p>
</div>
</div>

</div>
<div class="footer">$COMPANY_NAME | $COMPANY_PHONE | $COMPANY_WEBSITE | 30+ Years in Service | 4.9 Google Rating | #1 Best Rated in Surrey</div>
</body></html>
"@

try {
    Set-Content -Path $HtmlFile -Value $html -Encoding UTF8 -ErrorAction Stop
    Write-Check "HTML Report" $HtmlFile "PASS"
} catch {
    $altFile = $HtmlFile -replace '\.html$', "-$(Get-Random -Maximum 9999).html"
    try {
        Set-Content -Path $altFile -Value $html -Encoding UTF8 -ErrorAction Stop
        Write-Check "HTML Report" $altFile "PASS"
        $HtmlFile = $altFile
    } catch {
        Write-Check "HTML Report" "Could not save: $($_.Exception.Message)" "FAIL"
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# SUMMARY
# ─────────────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host ("=" * 70) -ForegroundColor Cyan
Write-Host "  SCAN COMPLETE" -ForegroundColor Cyan
Write-Host ("=" * 70) -ForegroundColor Cyan
Write-Host ""
Write-Host "  Score:  $score / 100  [$grade]" -ForegroundColor $gradeColor
Write-Host "  Report: $HtmlFile" -ForegroundColor White
Write-Host ""
Write-Host "  $COMPANY_NAME | $COMPANY_PHONE | $COMPANY_WEBSITE" -ForegroundColor Gray
Write-Host ""

# Open report
try {
    Start-Process $HtmlFile
} catch { }

Write-Host "Press any key to exit..." -ForegroundColor Gray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

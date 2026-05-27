<#
.SYNOPSIS
    PC Plus Computing 360 - Smart Backup & Restore
.DESCRIPTION
    Technician-friendly backup and restore tool. Safely backs up user data,
    browser profiles, email, business apps, drivers, and Windows settings
    before repair, reinstall, or hardware replacement. Generates verification
    reports and supports selective restore.
.NOTES
    Company:  PC Plus Computing
    Website:  pcpluscomputing.com
    Phone:    604-760-1662 | 236-500-2700
    Version:  1.0.0
    Requires: PowerShell 5.1+, Windows 10/11, Administrator privileges
    Part of:  PC Plus 360 USB Diagnostic Toolkit
.EXAMPLE
    PowerShell.exe -ExecutionPolicy Bypass -File .\PCPlus-SmartBackup.ps1
    PowerShell.exe -ExecutionPolicy Bypass -File .\PCPlus-SmartBackup.ps1 -Silent -Customer "John Smith" -Destination "E:\Backups"
#>

param(
    [switch]$Silent,
    [string]$Customer = "",
    [string]$Destination = ""
)

#Requires -Version 5.1

$ErrorActionPreference = 'Continue'
$COMPANY      = "PC Plus Computing"
$PHONE        = "604-760-1662 | 236-500-2700"
$WEBSITE      = "pcpluscomputing.com"
$VERSION      = "1.0.0"
$COLOR_NAVY   = "#0a1628"
$COLOR_SIDEBAR = "#0d1b2a"
$COLOR_ACCENT = "#2596be"
$COLOR_GREEN  = "#27ae60"
$COLOR_RED    = "#e74c3c"
$COLOR_ORANGE = "#f39c12"
$COLOR_CARD   = "#111d2e"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
if ([string]::IsNullOrEmpty($ScriptDir)) { $ScriptDir = Get-Location }

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

function Test-IsAdmin {
    $identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-IsAdmin)) {
    try {
        Start-Process powershell.exe -ArgumentList "-STA -NoProfile -ExecutionPolicy Bypass -File `"$($MyInvocation.MyCommand.Definition)`"" -Verb RunAs
    } catch {
        [System.Windows.Forms.MessageBox]::Show("This tool requires Administrator privileges.", "$COMPANY - Smart Backup", "OK", "Warning")
    }
    exit
}

# ─────────────────────────────────────────────────────────────────────────────
# JUNK / EXCLUSION PATTERNS
# ─────────────────────────────────────────────────────────────────────────────
$ExcludeDirs = @(
    'AppData\Local\Temp', 'AppData\Local\Microsoft\Windows\INetCache',
    'AppData\Local\Microsoft\Windows\Explorer', 'AppData\Local\CrashDumps',
    'AppData\Local\Google\Chrome\User Data\Default\Cache',
    'AppData\Local\Google\Chrome\User Data\Default\Code Cache',
    'AppData\Local\Google\Chrome\User Data\Default\Service Worker',
    'AppData\Local\Microsoft\Edge\User Data\Default\Cache',
    'AppData\Local\Microsoft\Edge\User Data\Default\Code Cache',
    'AppData\Local\Mozilla\Firefox\Profiles\*.default*\cache2',
    'AppData\Local\Packages', 'AppData\Local\D3DSCache',
    'AppData\Local\IconCache.db', '$Recycle.Bin', 'OneDrive\.~*'
)

$ExcludeExtensions = @('.tmp', '.log', '.dmp', '.etl', '.bak', '.old')

# ─────────────────────────────────────────────────────────────────────────────
# DETECTION FUNCTIONS
# ─────────────────────────────────────────────────────────────────────────────
function Get-UserProfiles {
    $profiles = @()
    $usersDir = "$env:SystemDrive\Users"
    $skip = @('Default', 'Default User', 'Public', 'All Users')
    foreach ($dir in (Get-ChildItem $usersDir -Directory -ErrorAction SilentlyContinue)) {
        if ($skip -contains $dir.Name) { continue }
        if (-not (Test-Path (Join-Path $dir.FullName "NTUSER.DAT"))) { continue }
        $profiles += @{
            Name = $dir.Name
            Path = $dir.FullName
            SID  = try { (New-Object System.Security.Principal.NTAccount($dir.Name)).Translate([System.Security.Principal.SecurityIdentifier]).Value } catch { "" }
        }
    }
    return $profiles
}

function Get-FolderSizeEstimate {
    param([string]$Path, [string[]]$Exclude = @())
    if (-not (Test-Path $Path)) { return 0 }
    try {
        $bytes = (Get-ChildItem -Path $Path -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object {
                $fullName = $_.FullName
                $dominated = $false
                foreach ($ex in $Exclude) {
                    if ($fullName -like "*$ex*") { $dominated = $true; break }
                }
                -not $dominated
            } |
            Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
        if ($bytes) { return $bytes }
    } catch { }
    return 0
}

function Format-Size {
    param([long]$Bytes)
    if ($Bytes -ge 1GB) { return "{0:N1} GB" -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return "{0:N1} MB" -f ($Bytes / 1MB) }
    if ($Bytes -ge 1KB) { return "{0:N0} KB" -f ($Bytes / 1KB) }
    return "$Bytes bytes"
}

function Test-OneDrivePlaceholder {
    param([string]$FilePath)
    try {
        $attr = [System.IO.File]::GetAttributes($FilePath)
        if ($attr -band 0x400000) { return $true }
        $fi = New-Object System.IO.FileInfo($FilePath)
        if ($fi.Attributes -band [System.IO.FileAttributes]::ReparsePoint) { return $true }
    } catch { }
    return $false
}

function Find-OutlookPST {
    param([string]$UserPath)
    $pstFiles = @()
    $searchPaths = @(
        (Join-Path $UserPath "Documents\Outlook Files"),
        (Join-Path $UserPath "AppData\Local\Microsoft\Outlook"),
        (Join-Path $UserPath "Documents")
    )
    foreach ($sp in $searchPaths) {
        if (Test-Path $sp) {
            Get-ChildItem -Path $sp -Filter "*.pst" -Recurse -ErrorAction SilentlyContinue |
                ForEach-Object { $pstFiles += $_.FullName }
        }
    }
    $pstFiles | Select-Object -Unique
}

function Find-OSTFiles {
    param([string]$UserPath)
    $ostPath = Join-Path $UserPath "AppData\Local\Microsoft\Outlook"
    if (Test-Path $ostPath) {
        Get-ChildItem -Path $ostPath -Filter "*.ost" -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName }
    }
}

function Find-ThunderbirdProfiles {
    param([string]$UserPath)
    $tbPath = Join-Path $UserPath "AppData\Roaming\Thunderbird\Profiles"
    if (Test-Path $tbPath) { return $tbPath }
    return $null
}

function Find-BusinessApps {
    param([string]$UserPath)
    $found = @()
    $qbPaths = @(
        "$env:SystemDrive\Users\Public\Documents\Intuit\QuickBooks",
        (Join-Path $UserPath "Documents\QuickBooks"),
        "$env:ProgramData\Intuit"
    )
    foreach ($p in $qbPaths) {
        if (Test-Path $p) { $found += @{ Name = "QuickBooks"; Path = $p } }
    }
    $sagePaths = @(
        "$env:ProgramData\Sage",
        (Join-Path $UserPath "Documents\Sage"),
        "$env:ProgramData\Sage Software"
    )
    foreach ($p in $sagePaths) {
        if (Test-Path $p) { $found += @{ Name = "Sage"; Path = $p } }
    }
    $taxPaths = @(
        (Join-Path $UserPath "Documents\TurboTax"),
        (Join-Path $UserPath "Documents\TaxCycle"),
        (Join-Path $UserPath "Documents\UFile"),
        (Join-Path $UserPath "Documents\H&R Block")
    )
    foreach ($p in $taxPaths) {
        if (Test-Path $p) { $found += @{ Name = "Tax Software"; Path = $p } }
    }
    return $found
}

# ─────────────────────────────────────────────────────────────────────────────
# BACKUP ENGINE
# ─────────────────────────────────────────────────────────────────────────────
function Copy-WithVerification {
    param(
        [string]$Source,
        [string]$DestBase,
        [string]$RelativeTo,
        [ref]$Stats,
        [ref]$Log,
        [System.Windows.Forms.ProgressBar]$Progress = $null
    )

    if (-not (Test-Path $Source)) {
        $Stats.Value.Skipped++
        return
    }

    $files = Get-ChildItem -Path $Source -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object {
            $fn = $_.FullName
            $skip = $false
            foreach ($ex in $ExcludeDirs) {
                if ($fn -like "*\$ex\*" -or $fn -like "*\$ex") { $skip = $true; break }
            }
            if (-not $skip -and $ExcludeExtensions -contains $_.Extension.ToLower()) { $skip = $true }
            if (-not $skip) { $skip = Test-OneDrivePlaceholder $fn }
            -not $skip
        }

    $total = @($files).Count
    $i = 0

    foreach ($file in $files) {
        $i++
        if ($Progress -and $total -gt 0) {
            $pct = [Math]::Min(100, [Math]::Floor(($i / $total) * 100))
            try { $Progress.Value = $pct } catch { }
        }

        try {
            $relPath = $file.FullName
            if ($RelativeTo -and $relPath.StartsWith($RelativeTo, [System.StringComparison]::OrdinalIgnoreCase)) {
                $relPath = $relPath.Substring($RelativeTo.Length).TrimStart('\', '/')
            }
            $destFile = Join-Path $DestBase $relPath
            $destDir  = Split-Path $destFile -Parent
            if (-not (Test-Path $destDir)) { New-Item -Path $destDir -ItemType Directory -Force | Out-Null }

            Copy-Item -Path $file.FullName -Destination $destFile -Force -ErrorAction Stop
            $Stats.Value.Copied++
            $Stats.Value.BytesCopied += $file.Length

            if (Test-Path $destFile) {
                $srcHash  = (Get-FileHash -Path $file.FullName -Algorithm MD5 -ErrorAction SilentlyContinue).Hash
                $destHash = (Get-FileHash -Path $destFile -Algorithm MD5 -ErrorAction SilentlyContinue).Hash
                if ($srcHash -and $destHash -and $srcHash -ne $destHash) {
                    $Stats.Value.VerifyFailed++
                    $Log.Value += "[VERIFY FAIL] $($file.FullName)"
                }
            }
        } catch {
            $Stats.Value.Failed++
            $Log.Value += "[FAIL] $($file.FullName): $($_.Exception.Message)"
        }
    }
}

function Backup-UserFolders {
    param([string]$UserPath, [string]$UserName, [string]$BackupRoot, [string[]]$Folders, [ref]$Stats, [ref]$Log, [System.Windows.Forms.ProgressBar]$Progress)
    foreach ($folder in $Folders) {
        $src = Join-Path $UserPath $folder
        if (Test-Path $src) {
            $dest = Join-Path $BackupRoot "UserData\$UserName\$folder"
            Copy-WithVerification -Source $src -DestBase $dest -RelativeTo $src -Stats $Stats -Log $Log -Progress $Progress
        }
    }
}

function Backup-BrowserData {
    param([string]$UserPath, [string]$UserName, [string]$BackupRoot, [ref]$Stats, [ref]$Log)

    $dest = Join-Path $BackupRoot "BrowserData\$UserName"

    $chromeBM = Join-Path $UserPath "AppData\Local\Google\Chrome\User Data\Default\Bookmarks"
    if (Test-Path $chromeBM) {
        $d = Join-Path $dest "Chrome"
        New-Item $d -ItemType Directory -Force | Out-Null
        Copy-Item $chromeBM (Join-Path $d "Bookmarks") -Force -ErrorAction SilentlyContinue
        $Stats.Value.Copied++
    }

    $edgeBM = Join-Path $UserPath "AppData\Local\Microsoft\Edge\User Data\Default\Bookmarks"
    if (Test-Path $edgeBM) {
        $d = Join-Path $dest "Edge"
        New-Item $d -ItemType Directory -Force | Out-Null
        Copy-Item $edgeBM (Join-Path $d "Bookmarks") -Force -ErrorAction SilentlyContinue
        $Stats.Value.Copied++
    }

    $ffProfiles = Join-Path $UserPath "AppData\Roaming\Mozilla\Firefox\Profiles"
    if (Test-Path $ffProfiles) {
        $ffDest = Join-Path $dest "Firefox"
        Get-ChildItem $ffProfiles -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            $places = Join-Path $_.FullName "places.sqlite"
            if (Test-Path $places) {
                $pd = Join-Path $ffDest $_.Name
                New-Item $pd -ItemType Directory -Force | Out-Null
                Copy-Item $places (Join-Path $pd "places.sqlite") -Force -ErrorAction SilentlyContinue
                $Stats.Value.Copied++
            }
        }
    }
}

function Backup-EmailData {
    param([string]$UserPath, [string]$UserName, [string]$BackupRoot, [ref]$Stats, [ref]$Log)
    $dest = Join-Path $BackupRoot "Email\$UserName"

    $pstFiles = Find-OutlookPST $UserPath
    foreach ($pst in $pstFiles) {
        $pstDest = Join-Path $dest "Outlook"
        New-Item $pstDest -ItemType Directory -Force | Out-Null
        try {
            Copy-Item $pst (Join-Path $pstDest (Split-Path $pst -Leaf)) -Force -ErrorAction Stop
            $Stats.Value.Copied++
            $Stats.Value.BytesCopied += (Get-Item $pst).Length
        } catch {
            $Stats.Value.Failed++
            $Log.Value += "[FAIL] PST: $pst - $($_.Exception.Message)"
        }
    }

    $ostFiles = Find-OSTFiles $UserPath
    if ($ostFiles) {
        $ostReport = Join-Path $dest "OST-Locations.txt"
        New-Item (Split-Path $ostReport -Parent) -ItemType Directory -Force | Out-Null
        $ostFiles | Out-File $ostReport -Encoding UTF8
        $Stats.Value.Copied++
    }

    $tbPath = Find-ThunderbirdProfiles $UserPath
    if ($tbPath) {
        $tbDest = Join-Path $dest "Thunderbird"
        Copy-WithVerification -Source $tbPath -DestBase $tbDest -RelativeTo $tbPath -Stats $Stats -Log $Log
    }
}

function Backup-WindowsSettings {
    param([string]$BackupRoot, [ref]$Stats, [ref]$Log)
    $dest = Join-Path $BackupRoot "WindowsSettings"
    New-Item $dest -ItemType Directory -Force | Out-Null

    try {
        $wifiXml = & netsh wlan export profile folder="$dest" key=clear 2>&1
        $Stats.Value.Copied++
        $Log.Value += "[OK] Wi-Fi profiles exported"
    } catch {
        $Log.Value += "[FAIL] Wi-Fi export: $($_.Exception.Message)"
    }

    try {
        Get-Printer -ErrorAction SilentlyContinue |
            Select-Object Name, DriverName, PortName, Shared, PrinterStatus |
            ConvertTo-Csv -NoTypeInformation |
            Out-File (Join-Path $dest "Printers.csv") -Encoding UTF8
        $Stats.Value.Copied++
    } catch {
        $Log.Value += "[FAIL] Printer list: $($_.Exception.Message)"
    }

    try {
        Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" |
            Select-Object ProductName, DisplayVersion, CurrentBuild, RegisteredOwner, ProductId |
            ConvertTo-Csv -NoTypeInformation |
            Out-File (Join-Path $dest "WindowsProduct.csv") -Encoding UTF8
        $Stats.Value.Copied++
    } catch { }

    try {
        Get-WmiObject Win32_NetworkAdapterConfiguration -Filter "IPEnabled=True" -ErrorAction SilentlyContinue |
            Select-Object Description, IPAddress, IPSubnet, DefaultIPGateway, DNSServerSearchOrder, DHCPEnabled, MACAddress |
            ConvertTo-Csv -NoTypeInformation |
            Out-File (Join-Path $dest "NetworkAdapters.csv") -Encoding UTF8
        $Stats.Value.Copied++
    } catch { }

    try {
        $compInfo = @{
            ComputerName = $env:COMPUTERNAME
            Domain       = (Get-WmiObject Win32_ComputerSystem -ErrorAction SilentlyContinue).Domain
            Workgroup    = (Get-WmiObject Win32_ComputerSystem -ErrorAction SilentlyContinue).Workgroup
            UserName     = $env:USERNAME
        }
        $compInfo | ConvertTo-Json | Out-File (Join-Path $dest "ComputerInfo.json") -Encoding UTF8
        $Stats.Value.Copied++
    } catch { }

    try {
        Get-WmiObject Win32_Product -ErrorAction SilentlyContinue |
            Select-Object Name, Version, Vendor, InstallDate |
            Sort-Object Name |
            ConvertTo-Csv -NoTypeInformation |
            Out-File (Join-Path $dest "InstalledSoftware.csv") -Encoding UTF8
        $Stats.Value.Copied++
    } catch {
        try {
            Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
                             "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue |
                Where-Object { $_.DisplayName } |
                Select-Object DisplayName, DisplayVersion, Publisher, InstallDate |
                Sort-Object DisplayName |
                ConvertTo-Csv -NoTypeInformation |
                Out-File (Join-Path $dest "InstalledSoftware.csv") -Encoding UTF8
            $Stats.Value.Copied++
        } catch { }
    }
}

function Backup-Drivers {
    param([string]$BackupRoot, [ref]$Stats, [ref]$Log)
    $dest = Join-Path $BackupRoot "Drivers"
    New-Item $dest -ItemType Directory -Force | Out-Null

    try {
        $pnpOutput = & pnputil /export-driver * "$dest" 2>&1 | Out-String
        $Stats.Value.Copied++
        $Log.Value += "[OK] Third-party drivers exported"
    } catch {
        $Log.Value += "[FAIL] Driver export: $($_.Exception.Message)"
    }
}

function Backup-SecurityData {
    param([string]$BackupRoot, [ref]$Stats, [ref]$Log)
    $dest = Join-Path $BackupRoot "SecurityData"
    New-Item $dest -ItemType Directory -Force | Out-Null

    try {
        $blStatus = & manage-bde -status 2>&1 | Out-String
        $blStatus | Out-File (Join-Path $dest "BitLocker-Status.txt") -Encoding UTF8

        $blKeys = & manage-bde -protectors -get C: 2>&1 | Out-String
        $blKeys | Out-File (Join-Path $dest "BitLocker-RecoveryKeys.txt") -Encoding UTF8
        $Stats.Value.Copied++
    } catch { }

    try {
        $defStatus = Get-MpComputerStatus -ErrorAction SilentlyContinue
        if ($defStatus) {
            $defStatus | Select-Object AntivirusEnabled, RealTimeProtectionEnabled, AntivirusSignatureLastUpdated, QuickScanEndTime |
                ConvertTo-Csv -NoTypeInformation |
                Out-File (Join-Path $dest "WindowsDefender.csv") -Encoding UTF8
            $Stats.Value.Copied++
        }
    } catch { }

    try {
        Get-NetFirewallProfile -ErrorAction SilentlyContinue |
            Select-Object Name, Enabled, DefaultInboundAction, DefaultOutboundAction |
            ConvertTo-Csv -NoTypeInformation |
            Out-File (Join-Path $dest "FirewallProfiles.csv") -Encoding UTF8
        $Stats.Value.Copied++
    } catch { }

    try {
        Get-LocalUser -ErrorAction SilentlyContinue |
            Select-Object Name, Enabled, LastLogon, PasswordRequired, Description |
            ConvertTo-Csv -NoTypeInformation |
            Out-File (Join-Path $dest "LocalUsers.csv") -Encoding UTF8
        $Stats.Value.Copied++
    } catch { }
}

function Backup-RepairEvidence {
    param([string]$BackupRoot, [ref]$Stats, [ref]$Log)
    $dest = Join-Path $BackupRoot "RepairEvidence"
    New-Item $dest -ItemType Directory -Force | Out-Null

    try {
        $sysInfo = & systeminfo 2>&1 | Out-String
        $sysInfo | Out-File (Join-Path $dest "SystemInfo.txt") -Encoding UTF8
        $Stats.Value.Copied++
    } catch { }

    try {
        Get-PhysicalDisk -ErrorAction SilentlyContinue |
            Select-Object FriendlyName, MediaType, HealthStatus, OperationalStatus, Size |
            ConvertTo-Csv -NoTypeInformation |
            Out-File (Join-Path $dest "DiskHealth.csv") -Encoding UTF8
        $Stats.Value.Copied++
    } catch { }

    try {
        Get-WinEvent -LogName System -MaxEvents 200 -ErrorAction SilentlyContinue |
            Select-Object TimeCreated, LevelDisplayName, Id, ProviderName, Message |
            Export-Csv (Join-Path $dest "EventLog-System.csv") -NoTypeInformation -Encoding UTF8
        Get-WinEvent -LogName Application -MaxEvents 200 -ErrorAction SilentlyContinue |
            Select-Object TimeCreated, LevelDisplayName, Id, ProviderName, Message |
            Export-Csv (Join-Path $dest "EventLog-Application.csv") -NoTypeInformation -Encoding UTF8
        $Stats.Value.Copied++
    } catch { }

    try {
        Get-CimInstance Win32_StartupCommand -ErrorAction SilentlyContinue |
            Select-Object Name, Command, Location, User |
            ConvertTo-Csv -NoTypeInformation |
            Out-File (Join-Path $dest "StartupApps.csv") -Encoding UTF8
        $Stats.Value.Copied++
    } catch { }

    try {
        Get-Service | Select-Object Name, DisplayName, Status, StartType |
            ConvertTo-Csv -NoTypeInformation |
            Out-File (Join-Path $dest "RunningServices.csv") -Encoding UTF8
        $Stats.Value.Copied++
    } catch { }

    try {
        Get-PnpDevice -PresentOnly -Status ERROR, DEGRADED, UNKNOWN -ErrorAction SilentlyContinue |
            Select-Object Class, FriendlyName, Status, InstanceId |
            ConvertTo-Csv -NoTypeInformation |
            Out-File (Join-Path $dest "ProblemDevices.csv") -Encoding UTF8
        $Stats.Value.Copied++
    } catch { }
}

# ─────────────────────────────────────────────────────────────────────────────
# RESTORE ENGINE
# ─────────────────────────────────────────────────────────────────────────────
function Restore-UserFolders {
    param([string]$BackupRoot, [string]$TargetUser, [string[]]$Folders, [ref]$Stats, [ref]$Log, [System.Windows.Forms.ProgressBar]$Progress)

    $targetPath = "$env:SystemDrive\Users\$TargetUser"
    if (-not (Test-Path $targetPath)) {
        $Log.Value += "[FAIL] Target user path not found: $targetPath"
        return
    }

    $userDataDir = Join-Path $BackupRoot "UserData"
    $backupUsers = Get-ChildItem $userDataDir -Directory -ErrorAction SilentlyContinue

    foreach ($bu in $backupUsers) {
        foreach ($folder in $Folders) {
            $src = Join-Path $bu.FullName $folder
            if (Test-Path $src) {
                $dest = Join-Path $targetPath $folder
                Copy-WithVerification -Source $src -DestBase $dest -RelativeTo $src -Stats $Stats -Log $Log -Progress $Progress
            }
        }
    }
}

function Restore-BrowserBookmarks {
    param([string]$BackupRoot, [string]$TargetUser, [ref]$Stats, [ref]$Log)
    $targetPath = "$env:SystemDrive\Users\$TargetUser"
    $browserDir = Join-Path $BackupRoot "BrowserData"

    $backupUsers = Get-ChildItem $browserDir -Directory -ErrorAction SilentlyContinue
    foreach ($bu in $backupUsers) {
        $chromeBM = Join-Path $bu.FullName "Chrome\Bookmarks"
        if (Test-Path $chromeBM) {
            $chromeDest = Join-Path $targetPath "AppData\Local\Google\Chrome\User Data\Default"
            if (Test-Path $chromeDest) {
                Copy-Item $chromeBM (Join-Path $chromeDest "Bookmarks") -Force -ErrorAction SilentlyContinue
                $Stats.Value.Copied++
            }
        }

        $edgeBM = Join-Path $bu.FullName "Edge\Bookmarks"
        if (Test-Path $edgeBM) {
            $edgeDest = Join-Path $targetPath "AppData\Local\Microsoft\Edge\User Data\Default"
            if (Test-Path $edgeDest) {
                Copy-Item $edgeBM (Join-Path $edgeDest "Bookmarks") -Force -ErrorAction SilentlyContinue
                $Stats.Value.Copied++
            }
        }
    }
}

function Restore-WiFiProfiles {
    param([string]$BackupRoot, [ref]$Stats, [ref]$Log)
    $wifiDir = Join-Path $BackupRoot "WindowsSettings"
    $xmlFiles = Get-ChildItem $wifiDir -Filter "Wi-Fi-*.xml" -ErrorAction SilentlyContinue
    foreach ($xml in $xmlFiles) {
        try {
            & netsh wlan add profile filename="$($xml.FullName)" 2>&1 | Out-Null
            $Stats.Value.Copied++
            $Log.Value += "[OK] Wi-Fi restored: $($xml.BaseName)"
        } catch {
            $Log.Value += "[FAIL] Wi-Fi restore: $($xml.BaseName)"
        }
    }
}

function Restore-Drivers {
    param([string]$BackupRoot, [ref]$Stats, [ref]$Log)
    $driverDir = Join-Path $BackupRoot "Drivers"
    if (-not (Test-Path $driverDir)) { return }
    $infFiles = Get-ChildItem $driverDir -Filter "*.inf" -Recurse -ErrorAction SilentlyContinue
    foreach ($inf in $infFiles) {
        try {
            & pnputil /add-driver "$($inf.FullName)" /install 2>&1 | Out-Null
            $Stats.Value.Copied++
        } catch {
            $Stats.Value.Failed++
        }
    }
    $Log.Value += "[OK] Driver restore attempted for $(@($infFiles).Count) drivers"
}

# ─────────────────────────────────────────────────────────────────────────────
# REPORT GENERATION
# ─────────────────────────────────────────────────────────────────────────────
function Generate-BackupReport {
    param([string]$BackupRoot, [string]$CustomerName, [hashtable]$Stats, [string[]]$LogEntries, [string]$Mode)

    $reportPath = Join-Path $BackupRoot "PCPlus-Backup-Report.html"
    $timestamp  = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $compName   = $env:COMPUTERNAME

    $logHtml = ""
    foreach ($entry in $LogEntries) {
        $color = "#c9d1d9"
        if ($entry -like "*FAIL*") { $color = "#e74c3c" }
        elseif ($entry -like "*OK*") { $color = "#27ae60" }
        elseif ($entry -like "*VERIFY*") { $color = "#f39c12" }
        $logHtml += "<div style='color:$color;font-family:Consolas;font-size:12px;padding:2px 0;'>$entry</div>`n"
    }

    $html = @"
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>PC Plus Backup Report - $CustomerName</title>
<style>
body { background: #0a1628; color: #c9d1d9; font-family: 'Segoe UI', Arial, sans-serif; margin: 0; padding: 20px; }
.header { background: #0d1b2a; padding: 20px; border-radius: 8px; margin-bottom: 20px; display: flex; justify-content: space-between; align-items: center; }
.header h1 { color: #2596be; margin: 0; font-size: 22px; }
.header .info { text-align: right; font-size: 13px; color: #8b949e; }
.card { background: #111d2e; border-radius: 8px; padding: 16px; margin-bottom: 16px; border-left: 4px solid #2596be; }
.card h2 { color: #2596be; margin: 0 0 10px 0; font-size: 16px; }
.stat { display: inline-block; background: #0d1b2a; border-radius: 6px; padding: 12px 20px; margin: 4px; text-align: center; }
.stat .num { font-size: 24px; font-weight: bold; color: #27ae60; }
.stat .label { font-size: 11px; color: #8b949e; text-transform: uppercase; }
.stat.fail .num { color: #e74c3c; }
.stat.warn .num { color: #f39c12; }
.footer { text-align: center; color: #484f58; font-size: 11px; margin-top: 30px; padding-top: 15px; border-top: 1px solid #1a2332; }
</style>
</head>
<body>
<div class="header">
    <div>
        <h1>PC PLUS COMPUTING - $($Mode.ToUpper()) REPORT</h1>
        <div style="color:#8b949e;font-size:13px;margin-top:4px;">Secure - Protect - Optimize</div>
    </div>
    <div class="info">
        <div><strong>Customer:</strong> $CustomerName</div>
        <div><strong>Computer:</strong> $compName</div>
        <div><strong>Date:</strong> $timestamp</div>
    </div>
</div>

<div class="card">
    <h2>Summary</h2>
    <div class="stat"><div class="num">$($Stats.Copied)</div><div class="label">Files Copied</div></div>
    <div class="stat fail"><div class="num">$($Stats.Failed)</div><div class="label">Failed</div></div>
    <div class="stat warn"><div class="num">$($Stats.VerifyFailed)</div><div class="label">Verify Failed</div></div>
    <div class="stat"><div class="num">$($Stats.Skipped)</div><div class="label">Skipped</div></div>
    <div class="stat"><div class="num">$(Format-Size $Stats.BytesCopied)</div><div class="label">Total Size</div></div>
</div>

<div class="card">
    <h2>Backup Location</h2>
    <div style="font-family:Consolas;font-size:13px;">$BackupRoot</div>
</div>

<div class="card">
    <h2>Activity Log</h2>
    $logHtml
</div>

<div class="footer">
    $COMPANY | $PHONE | $WEBSITE<br>
    Smart Backup v$VERSION | Report generated $timestamp
</div>
</body>
</html>
"@

    $html | Out-File $reportPath -Encoding UTF8
    return $reportPath
}

# ─────────────────────────────────────────────────────────────────────────────
# WINFORMS UI
# ─────────────────────────────────────────────────────────────────────────────
function Show-BackupUI {
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "$COMPANY 360 - Smart Backup & Restore"
    $form.Size = New-Object System.Drawing.Size(900, 720)
    $form.StartPosition = "CenterScreen"
    $form.BackColor = [System.Drawing.ColorTranslator]::FromHtml($COLOR_NAVY)
    $form.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $form.MinimumSize = New-Object System.Drawing.Size(800, 600)

    $headerPanel = New-Object System.Windows.Forms.Panel
    $headerPanel.Dock = "Top"
    $headerPanel.Height = 60
    $headerPanel.BackColor = [System.Drawing.ColorTranslator]::FromHtml($COLOR_SIDEBAR)
    $form.Controls.Add($headerPanel)

    $lblTitle = New-Object System.Windows.Forms.Label
    $lblTitle.Text = "PC PLUS COMPUTING 360 - SMART BACKUP & RESTORE"
    $lblTitle.ForeColor = [System.Drawing.Color]::White
    $lblTitle.Font = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
    $lblTitle.AutoSize = $true
    $lblTitle.Location = New-Object System.Drawing.Point(16, 8)
    $headerPanel.Controls.Add($lblTitle)

    $lblSub = New-Object System.Windows.Forms.Label
    $lblSub.Text = "Protect customer data before repair, reinstall, or upgrade"
    $lblSub.ForeColor = [System.Drawing.ColorTranslator]::FromHtml("#8b949e")
    $lblSub.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $lblSub.AutoSize = $true
    $lblSub.Location = New-Object System.Drawing.Point(16, 34)
    $headerPanel.Controls.Add($lblSub)

    $tabControl = New-Object System.Windows.Forms.TabControl
    $tabControl.Dock = "Fill"
    $tabControl.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $form.Controls.Add($tabControl)

    # ── BACKUP TAB ──
    $tabBackup = New-Object System.Windows.Forms.TabPage
    $tabBackup.Text = "  Backup  "
    $tabBackup.BackColor = [System.Drawing.ColorTranslator]::FromHtml($COLOR_NAVY)
    $tabControl.TabPages.Add($tabBackup)

    $backupPanel = New-Object System.Windows.Forms.Panel
    $backupPanel.Dock = "Fill"
    $backupPanel.AutoScroll = $true
    $backupPanel.Padding = New-Object System.Windows.Forms.Padding(16)
    $tabBackup.Controls.Add($backupPanel)

    $y = 10

    $lblCustomer = New-Object System.Windows.Forms.Label
    $lblCustomer.Text = "Customer Name:"
    $lblCustomer.ForeColor = [System.Drawing.Color]::White
    $lblCustomer.Location = New-Object System.Drawing.Point(10, $y)
    $lblCustomer.AutoSize = $true
    $backupPanel.Controls.Add($lblCustomer)

    $txtCustomer = New-Object System.Windows.Forms.TextBox
    $txtCustomer.Size = New-Object System.Drawing.Size(250, 24)
    $txtCustomer.Location = New-Object System.Drawing.Point(140, ($y - 2))
    $txtCustomer.BackColor = [System.Drawing.ColorTranslator]::FromHtml("#0d1117")
    $txtCustomer.ForeColor = [System.Drawing.ColorTranslator]::FromHtml("#c9d1d9")
    $txtCustomer.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $backupPanel.Controls.Add($txtCustomer)
    $y += 35

    $lblDest = New-Object System.Windows.Forms.Label
    $lblDest.Text = "Backup To:"
    $lblDest.ForeColor = [System.Drawing.Color]::White
    $lblDest.Location = New-Object System.Drawing.Point(10, $y)
    $lblDest.AutoSize = $true
    $backupPanel.Controls.Add($lblDest)

    $txtDest = New-Object System.Windows.Forms.TextBox
    $txtDest.Size = New-Object System.Drawing.Size(550, 24)
    $txtDest.Location = New-Object System.Drawing.Point(140, ($y - 2))
    $txtDest.BackColor = [System.Drawing.ColorTranslator]::FromHtml("#0d1117")
    $txtDest.ForeColor = [System.Drawing.ColorTranslator]::FromHtml("#c9d1d9")
    $txtDest.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $backupPanel.Controls.Add($txtDest)

    $btnBrowse = New-Object System.Windows.Forms.Button
    $btnBrowse.Text = "Browse..."
    $btnBrowse.Size = New-Object System.Drawing.Size(80, 26)
    $btnBrowse.Location = New-Object System.Drawing.Point(700, ($y - 3))
    $btnBrowse.BackColor = [System.Drawing.ColorTranslator]::FromHtml($COLOR_ACCENT)
    $btnBrowse.ForeColor = [System.Drawing.Color]::White
    $btnBrowse.FlatStyle = "Flat"
    $btnBrowse.Cursor = [System.Windows.Forms.Cursors]::Hand
    $backupPanel.Controls.Add($btnBrowse)

    $btnBrowse.Add_Click({
        $fbd = New-Object System.Windows.Forms.FolderBrowserDialog
        $fbd.Description = "Select backup destination"
        if ($fbd.ShowDialog() -eq "OK") { $txtDest.Text = $fbd.SelectedPath }
    })
    $y += 40

    $lblProfiles = New-Object System.Windows.Forms.Label
    $lblProfiles.Text = "User Profiles Found:"
    $lblProfiles.ForeColor = [System.Drawing.ColorTranslator]::FromHtml($COLOR_ACCENT)
    $lblProfiles.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $lblProfiles.Location = New-Object System.Drawing.Point(10, $y)
    $lblProfiles.AutoSize = $true
    $backupPanel.Controls.Add($lblProfiles)
    $y += 24

    $profiles = Get-UserProfiles
    $profileChecks = @()
    foreach ($p in $profiles) {
        $cb = New-Object System.Windows.Forms.CheckBox
        $cb.Text = "$($p.Name)  ($($p.Path))"
        $cb.ForeColor = [System.Drawing.Color]::White
        $cb.Checked = $true
        $cb.Location = New-Object System.Drawing.Point(30, $y)
        $cb.AutoSize = $true
        $cb.Tag = $p
        $backupPanel.Controls.Add($cb)
        $profileChecks += $cb
        $y += 24
    }
    $y += 10

    $lblCategories = New-Object System.Windows.Forms.Label
    $lblCategories.Text = "What to Backup:"
    $lblCategories.ForeColor = [System.Drawing.ColorTranslator]::FromHtml($COLOR_ACCENT)
    $lblCategories.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $lblCategories.Location = New-Object System.Drawing.Point(10, $y)
    $lblCategories.AutoSize = $true
    $backupPanel.Controls.Add($lblCategories)
    $y += 24

    $categories = @(
        @{ Name = "Desktop, Documents, Downloads, Pictures, Videos, Music"; Key = "userfolders"; Default = $true },
        @{ Name = "Browser Bookmarks (Chrome, Edge, Firefox)"; Key = "browser"; Default = $true },
        @{ Name = "Email Data (Outlook PST, OST locations, Thunderbird)"; Key = "email"; Default = $true },
        @{ Name = "Business Apps (QuickBooks, Sage, Tax Software)"; Key = "business"; Default = $true },
        @{ Name = "Windows Settings (Wi-Fi, Printers, Software List, Network)"; Key = "winsettings"; Default = $true },
        @{ Name = "Driver Backup (Third-party drivers)"; Key = "drivers"; Default = $true },
        @{ Name = "Security Data (BitLocker, Defender, Firewall, Users)"; Key = "security"; Default = $true },
        @{ Name = "Repair Evidence (SystemInfo, Disk Health, Event Logs, Startup, Services)"; Key = "evidence"; Default = $true }
    )

    $catChecks = @{}
    foreach ($cat in $categories) {
        $cb = New-Object System.Windows.Forms.CheckBox
        $cb.Text = $cat.Name
        $cb.ForeColor = [System.Drawing.Color]::White
        $cb.Checked = $cat.Default
        $cb.Location = New-Object System.Drawing.Point(30, $y)
        $cb.AutoSize = $true
        $backupPanel.Controls.Add($cb)
        $catChecks[$cat.Key] = $cb
        $y += 24
    }
    $y += 16

    $progressBar = New-Object System.Windows.Forms.ProgressBar
    $progressBar.Size = New-Object System.Drawing.Size(760, 16)
    $progressBar.Location = New-Object System.Drawing.Point(10, $y)
    $progressBar.Style = "Continuous"
    $progressBar.Minimum = 0
    $progressBar.Maximum = 100
    $backupPanel.Controls.Add($progressBar)
    $y += 24

    $lblStatus = New-Object System.Windows.Forms.Label
    $lblStatus.Text = "Ready. Select options and click Start Backup."
    $lblStatus.ForeColor = [System.Drawing.ColorTranslator]::FromHtml("#8b949e")
    $lblStatus.Location = New-Object System.Drawing.Point(10, $y)
    $lblStatus.Size = New-Object System.Drawing.Size(760, 20)
    $backupPanel.Controls.Add($lblStatus)
    $y += 30

    $btnSelectAll = New-Object System.Windows.Forms.Button
    $btnSelectAll.Text = "Select All"
    $btnSelectAll.Size = New-Object System.Drawing.Size(100, 35)
    $btnSelectAll.Location = New-Object System.Drawing.Point(10, $y)
    $btnSelectAll.BackColor = [System.Drawing.ColorTranslator]::FromHtml("#484f58")
    $btnSelectAll.ForeColor = [System.Drawing.Color]::White
    $btnSelectAll.FlatStyle = "Flat"
    $btnSelectAll.Cursor = [System.Windows.Forms.Cursors]::Hand
    $backupPanel.Controls.Add($btnSelectAll)

    $btnSelectAll.Add_Click({
        foreach ($cb in $catChecks.Values) { $cb.Checked = $true }
        foreach ($cb in $profileChecks) { $cb.Checked = $true }
    })

    $btnStartBackup = New-Object System.Windows.Forms.Button
    $btnStartBackup.Text = "START BACKUP"
    $btnStartBackup.Size = New-Object System.Drawing.Size(200, 40)
    $btnStartBackup.Location = New-Object System.Drawing.Point(300, $y)
    $btnStartBackup.BackColor = [System.Drawing.ColorTranslator]::FromHtml($COLOR_GREEN)
    $btnStartBackup.ForeColor = [System.Drawing.Color]::White
    $btnStartBackup.FlatStyle = "Flat"
    $btnStartBackup.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
    $btnStartBackup.Cursor = [System.Windows.Forms.Cursors]::Hand
    $backupPanel.Controls.Add($btnStartBackup)

    $btnEstimate = New-Object System.Windows.Forms.Button
    $btnEstimate.Text = "Estimate Size"
    $btnEstimate.Size = New-Object System.Drawing.Size(120, 35)
    $btnEstimate.Location = New-Object System.Drawing.Point(130, $y)
    $btnEstimate.BackColor = [System.Drawing.ColorTranslator]::FromHtml($COLOR_ACCENT)
    $btnEstimate.ForeColor = [System.Drawing.Color]::White
    $btnEstimate.FlatStyle = "Flat"
    $btnEstimate.Cursor = [System.Windows.Forms.Cursors]::Hand
    $backupPanel.Controls.Add($btnEstimate)

    $btnEstimate.Add_Click({
        $lblStatus.Text = "Estimating backup size..."
        $lblStatus.ForeColor = [System.Drawing.ColorTranslator]::FromHtml($COLOR_ORANGE)
        [System.Windows.Forms.Application]::DoEvents()

        $totalBytes = [long]0
        $userFolders = @("Desktop", "Documents", "Downloads", "Pictures", "Videos", "Music")
        foreach ($cb in $profileChecks) {
            if (-not $cb.Checked) { continue }
            $prof = $cb.Tag
            if ($catChecks["userfolders"].Checked) {
                foreach ($f in $userFolders) {
                    $totalBytes += Get-FolderSizeEstimate (Join-Path $prof.Path $f)
                }
            }
        }
        $lblStatus.Text = "Estimated backup size: $(Format-Size $totalBytes) (user folders only, actual may vary)"
        $lblStatus.ForeColor = [System.Drawing.ColorTranslator]::FromHtml($COLOR_GREEN)
    })

    # ── BACKUP ACTION ──
    $btnStartBackup.Add_Click({
        $customerName = $txtCustomer.Text.Trim()
        if (-not $customerName) {
            [System.Windows.Forms.MessageBox]::Show("Please enter a customer name.", "Missing Info", "OK", "Warning")
            return
        }
        $destRoot = $txtDest.Text.Trim()
        if (-not $destRoot -or -not (Test-Path (Split-Path $destRoot -Qualifier -ErrorAction SilentlyContinue) -ErrorAction SilentlyContinue)) {
            [System.Windows.Forms.MessageBox]::Show("Please select a valid backup destination.", "Missing Info", "OK", "Warning")
            return
        }

        $backupFolder = Join-Path $destRoot "$($customerName -replace '[^\w\-]','_')_$($env:COMPUTERNAME)_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        New-Item $backupFolder -ItemType Directory -Force | Out-Null

        $stats = @{ Copied = 0; Failed = 0; Skipped = 0; VerifyFailed = 0; BytesCopied = [long]0 }
        $logEntries = @()
        $statsRef = [ref]$stats
        $logRef = [ref]$logEntries

        $btnStartBackup.Enabled = $false
        $btnEstimate.Enabled = $false
        $progressBar.Value = 0

        $selectedProfiles = $profileChecks | Where-Object { $_.Checked } | ForEach-Object { $_.Tag }
        $totalSteps = ($catChecks.Values | Where-Object { $_.Checked }).Count
        $step = 0
        $userFolders = @("Desktop", "Documents", "Downloads", "Pictures", "Videos", "Music")

        foreach ($prof in $selectedProfiles) {
            if ($catChecks["userfolders"].Checked) {
                $step++
                $lblStatus.Text = "Backing up user folders for $($prof.Name)..."
                $lblStatus.ForeColor = [System.Drawing.ColorTranslator]::FromHtml($COLOR_ACCENT)
                [System.Windows.Forms.Application]::DoEvents()
                Backup-UserFolders -UserPath $prof.Path -UserName $prof.Name -BackupRoot $backupFolder -Folders $userFolders -Stats $statsRef -Log $logRef -Progress $progressBar
                $logEntries += "[OK] User folders backed up for $($prof.Name)"
            }

            if ($catChecks["browser"].Checked) {
                $lblStatus.Text = "Backing up browser data for $($prof.Name)..."
                [System.Windows.Forms.Application]::DoEvents()
                Backup-BrowserData -UserPath $prof.Path -UserName $prof.Name -BackupRoot $backupFolder -Stats $statsRef -Log $logRef
                $logEntries += "[OK] Browser data backed up for $($prof.Name)"
            }

            if ($catChecks["email"].Checked) {
                $lblStatus.Text = "Backing up email data for $($prof.Name)..."
                [System.Windows.Forms.Application]::DoEvents()
                Backup-EmailData -UserPath $prof.Path -UserName $prof.Name -BackupRoot $backupFolder -Stats $statsRef -Log $logRef
                $logEntries += "[OK] Email data backed up for $($prof.Name)"
            }

            if ($catChecks["business"].Checked) {
                $lblStatus.Text = "Backing up business apps for $($prof.Name)..."
                [System.Windows.Forms.Application]::DoEvents()
                $bizApps = Find-BusinessApps $prof.Path
                foreach ($app in $bizApps) {
                    $bizDest = Join-Path $backupFolder "BusinessApps\$($prof.Name)\$($app.Name)"
                    Copy-WithVerification -Source $app.Path -DestBase $bizDest -RelativeTo $app.Path -Stats $statsRef -Log $logRef
                    $logEntries += "[OK] $($app.Name) backed up for $($prof.Name)"
                }
            }
        }

        if ($catChecks["winsettings"].Checked) {
            $lblStatus.Text = "Backing up Windows settings..."
            [System.Windows.Forms.Application]::DoEvents()
            Backup-WindowsSettings -BackupRoot $backupFolder -Stats $statsRef -Log $logRef
        }

        if ($catChecks["drivers"].Checked) {
            $lblStatus.Text = "Backing up drivers..."
            [System.Windows.Forms.Application]::DoEvents()
            Backup-Drivers -BackupRoot $backupFolder -Stats $statsRef -Log $logRef
        }

        if ($catChecks["security"].Checked) {
            $lblStatus.Text = "Backing up security data..."
            [System.Windows.Forms.Application]::DoEvents()
            Backup-SecurityData -BackupRoot $backupFolder -Stats $statsRef -Log $logRef
        }

        if ($catChecks["evidence"].Checked) {
            $lblStatus.Text = "Collecting repair evidence..."
            [System.Windows.Forms.Application]::DoEvents()
            Backup-RepairEvidence -BackupRoot $backupFolder -Stats $statsRef -Log $logRef
        }

        $progressBar.Value = 100
        $reportPath = Generate-BackupReport -BackupRoot $backupFolder -CustomerName $customerName -Stats $stats -LogEntries $logEntries -Mode "Backup"

        $summary = "Backup complete! Copied: $($stats.Copied) | Failed: $($stats.Failed) | Size: $(Format-Size $stats.BytesCopied)"
        $lblStatus.Text = $summary
        $lblStatus.ForeColor = [System.Drawing.ColorTranslator]::FromHtml($COLOR_GREEN)

        $btnStartBackup.Enabled = $true
        $btnEstimate.Enabled = $true

        [System.Windows.Forms.MessageBox]::Show(
            "$summary`n`nBackup saved to:`n$backupFolder`n`nReport: $reportPath",
            "Backup Complete", "OK", "Information"
        )

        Start-Process "explorer.exe" -ArgumentList $backupFolder
    })

    # ── RESTORE TAB ──
    $tabRestore = New-Object System.Windows.Forms.TabPage
    $tabRestore.Text = "  Restore  "
    $tabRestore.BackColor = [System.Drawing.ColorTranslator]::FromHtml($COLOR_NAVY)
    $tabControl.TabPages.Add($tabRestore)

    $restorePanel = New-Object System.Windows.Forms.Panel
    $restorePanel.Dock = "Fill"
    $restorePanel.AutoScroll = $true
    $restorePanel.Padding = New-Object System.Windows.Forms.Padding(16)
    $tabRestore.Controls.Add($restorePanel)

    $ry = 10

    $lblRestoreFrom = New-Object System.Windows.Forms.Label
    $lblRestoreFrom.Text = "Restore From:"
    $lblRestoreFrom.ForeColor = [System.Drawing.Color]::White
    $lblRestoreFrom.Location = New-Object System.Drawing.Point(10, $ry)
    $lblRestoreFrom.AutoSize = $true
    $restorePanel.Controls.Add($lblRestoreFrom)

    $txtRestoreFrom = New-Object System.Windows.Forms.TextBox
    $txtRestoreFrom.Size = New-Object System.Drawing.Size(550, 24)
    $txtRestoreFrom.Location = New-Object System.Drawing.Point(140, ($ry - 2))
    $txtRestoreFrom.BackColor = [System.Drawing.ColorTranslator]::FromHtml("#0d1117")
    $txtRestoreFrom.ForeColor = [System.Drawing.ColorTranslator]::FromHtml("#c9d1d9")
    $txtRestoreFrom.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $restorePanel.Controls.Add($txtRestoreFrom)

    $btnRestoreBrowse = New-Object System.Windows.Forms.Button
    $btnRestoreBrowse.Text = "Browse..."
    $btnRestoreBrowse.Size = New-Object System.Drawing.Size(80, 26)
    $btnRestoreBrowse.Location = New-Object System.Drawing.Point(700, ($ry - 3))
    $btnRestoreBrowse.BackColor = [System.Drawing.ColorTranslator]::FromHtml($COLOR_ACCENT)
    $btnRestoreBrowse.ForeColor = [System.Drawing.Color]::White
    $btnRestoreBrowse.FlatStyle = "Flat"
    $btnRestoreBrowse.Cursor = [System.Windows.Forms.Cursors]::Hand
    $restorePanel.Controls.Add($btnRestoreBrowse)

    $btnRestoreBrowse.Add_Click({
        $fbd = New-Object System.Windows.Forms.FolderBrowserDialog
        $fbd.Description = "Select backup folder to restore from"
        if ($fbd.ShowDialog() -eq "OK") { $txtRestoreFrom.Text = $fbd.SelectedPath }
    })
    $ry += 40

    $lblRestoreTo = New-Object System.Windows.Forms.Label
    $lblRestoreTo.Text = "Restore To User:"
    $lblRestoreTo.ForeColor = [System.Drawing.Color]::White
    $lblRestoreTo.Location = New-Object System.Drawing.Point(10, $ry)
    $lblRestoreTo.AutoSize = $true
    $restorePanel.Controls.Add($lblRestoreTo)

    $cmbRestoreUser = New-Object System.Windows.Forms.ComboBox
    $cmbRestoreUser.Size = New-Object System.Drawing.Size(250, 24)
    $cmbRestoreUser.Location = New-Object System.Drawing.Point(140, ($ry - 2))
    $cmbRestoreUser.BackColor = [System.Drawing.ColorTranslator]::FromHtml("#0d1117")
    $cmbRestoreUser.ForeColor = [System.Drawing.ColorTranslator]::FromHtml("#c9d1d9")
    $cmbRestoreUser.DropDownStyle = "DropDownList"
    foreach ($p in $profiles) { [void]$cmbRestoreUser.Items.Add($p.Name) }
    if ($cmbRestoreUser.Items.Count -gt 0) { $cmbRestoreUser.SelectedIndex = 0 }
    $restorePanel.Controls.Add($cmbRestoreUser)
    $ry += 40

    $lblRestoreCats = New-Object System.Windows.Forms.Label
    $lblRestoreCats.Text = "What to Restore:"
    $lblRestoreCats.ForeColor = [System.Drawing.ColorTranslator]::FromHtml($COLOR_ACCENT)
    $lblRestoreCats.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $lblRestoreCats.Location = New-Object System.Drawing.Point(10, $ry)
    $lblRestoreCats.AutoSize = $true
    $restorePanel.Controls.Add($lblRestoreCats)
    $ry += 24

    $restoreCats = @(
        @{ Name = "Desktop, Documents, Downloads, Pictures, Videos, Music"; Key = "userfolders" },
        @{ Name = "Browser Bookmarks"; Key = "browser" },
        @{ Name = "Outlook PST Files"; Key = "email" },
        @{ Name = "Business Apps (QuickBooks, Sage, Tax)"; Key = "business" },
        @{ Name = "Wi-Fi Profiles"; Key = "wifi" },
        @{ Name = "Drivers"; Key = "drivers" }
    )

    $restoreChecks = @{}
    foreach ($cat in $restoreCats) {
        $cb = New-Object System.Windows.Forms.CheckBox
        $cb.Text = $cat.Name
        $cb.ForeColor = [System.Drawing.Color]::White
        $cb.Checked = $true
        $cb.Location = New-Object System.Drawing.Point(30, $ry)
        $cb.AutoSize = $true
        $restorePanel.Controls.Add($cb)
        $restoreChecks[$cat.Key] = $cb
        $ry += 24
    }
    $ry += 16

    $restoreProgress = New-Object System.Windows.Forms.ProgressBar
    $restoreProgress.Size = New-Object System.Drawing.Size(760, 16)
    $restoreProgress.Location = New-Object System.Drawing.Point(10, $ry)
    $restoreProgress.Style = "Continuous"
    $restorePanel.Controls.Add($restoreProgress)
    $ry += 24

    $lblRestoreStatus = New-Object System.Windows.Forms.Label
    $lblRestoreStatus.Text = "Select a backup folder and click Start Restore."
    $lblRestoreStatus.ForeColor = [System.Drawing.ColorTranslator]::FromHtml("#8b949e")
    $lblRestoreStatus.Location = New-Object System.Drawing.Point(10, $ry)
    $lblRestoreStatus.Size = New-Object System.Drawing.Size(760, 20)
    $restorePanel.Controls.Add($lblRestoreStatus)
    $ry += 30

    $btnStartRestore = New-Object System.Windows.Forms.Button
    $btnStartRestore.Text = "START RESTORE"
    $btnStartRestore.Size = New-Object System.Drawing.Size(200, 40)
    $btnStartRestore.Location = New-Object System.Drawing.Point(300, $ry)
    $btnStartRestore.BackColor = [System.Drawing.ColorTranslator]::FromHtml($COLOR_ORANGE)
    $btnStartRestore.ForeColor = [System.Drawing.Color]::White
    $btnStartRestore.FlatStyle = "Flat"
    $btnStartRestore.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
    $btnStartRestore.Cursor = [System.Windows.Forms.Cursors]::Hand
    $restorePanel.Controls.Add($btnStartRestore)

    $btnStartRestore.Add_Click({
        $backupRoot = $txtRestoreFrom.Text.Trim()
        if (-not $backupRoot -or -not (Test-Path $backupRoot)) {
            [System.Windows.Forms.MessageBox]::Show("Please select a valid backup folder.", "Missing Info", "OK", "Warning")
            return
        }
        $targetUser = $cmbRestoreUser.SelectedItem
        if (-not $targetUser) {
            [System.Windows.Forms.MessageBox]::Show("Please select a target user.", "Missing Info", "OK", "Warning")
            return
        }

        $confirm = [System.Windows.Forms.MessageBox]::Show(
            "Restore data from:`n$backupRoot`n`nTo user: $targetUser`n`nExisting files will NOT be deleted. Only backed up files will be copied back. Continue?",
            "Confirm Restore", "YesNo", "Question"
        )
        if ($confirm -ne "Yes") { return }

        $stats = @{ Copied = 0; Failed = 0; Skipped = 0; VerifyFailed = 0; BytesCopied = [long]0 }
        $logEntries = @()
        $statsRef = [ref]$stats
        $logRef = [ref]$logEntries

        $btnStartRestore.Enabled = $false
        $restoreProgress.Value = 0
        $userFolders = @("Desktop", "Documents", "Downloads", "Pictures", "Videos", "Music")

        if ($restoreChecks["userfolders"].Checked) {
            $lblRestoreStatus.Text = "Restoring user folders..."
            $lblRestoreStatus.ForeColor = [System.Drawing.ColorTranslator]::FromHtml($COLOR_ACCENT)
            [System.Windows.Forms.Application]::DoEvents()
            Restore-UserFolders -BackupRoot $backupRoot -TargetUser $targetUser -Folders $userFolders -Stats $statsRef -Log $logRef -Progress $restoreProgress
        }

        if ($restoreChecks["browser"].Checked) {
            $lblRestoreStatus.Text = "Restoring browser bookmarks..."
            [System.Windows.Forms.Application]::DoEvents()
            Restore-BrowserBookmarks -BackupRoot $backupRoot -TargetUser $targetUser -Stats $statsRef -Log $logRef
        }

        if ($restoreChecks["email"].Checked) {
            $lblRestoreStatus.Text = "Restoring email data..."
            [System.Windows.Forms.Application]::DoEvents()
            $emailDir = Join-Path $backupRoot "Email"
            if (Test-Path $emailDir) {
                $targetDocs = "$env:SystemDrive\Users\$targetUser\Documents\Outlook Files"
                New-Item $targetDocs -ItemType Directory -Force | Out-Null
                Get-ChildItem $emailDir -Filter "*.pst" -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
                    Copy-Item $_.FullName (Join-Path $targetDocs $_.Name) -Force -ErrorAction SilentlyContinue
                    $stats.Copied++
                }
            }
        }

        if ($restoreChecks["wifi"].Checked) {
            $lblRestoreStatus.Text = "Restoring Wi-Fi profiles..."
            [System.Windows.Forms.Application]::DoEvents()
            Restore-WiFiProfiles -BackupRoot $backupRoot -Stats $statsRef -Log $logRef
        }

        if ($restoreChecks["drivers"].Checked) {
            $lblRestoreStatus.Text = "Restoring drivers..."
            [System.Windows.Forms.Application]::DoEvents()
            Restore-Drivers -BackupRoot $backupRoot -Stats $statsRef -Log $logRef
        }

        $restoreProgress.Value = 100
        $reportPath = Generate-BackupReport -BackupRoot $backupRoot -CustomerName "Restore" -Stats $stats -LogEntries $logEntries -Mode "Restore"

        $summary = "Restore complete! Files restored: $($stats.Copied) | Failed: $($stats.Failed)"
        $lblRestoreStatus.Text = $summary
        $lblRestoreStatus.ForeColor = [System.Drawing.ColorTranslator]::FromHtml($COLOR_GREEN)
        $btnStartRestore.Enabled = $true

        [System.Windows.Forms.MessageBox]::Show($summary, "Restore Complete", "OK", "Information")
    })

    $form.Add_Shown({ $form.Activate() })
    [void]$form.ShowDialog()
    $form.Dispose()
}

# ─────────────────────────────────────────────────────────────────────────────
# ENTRY POINT
# ─────────────────────────────────────────────────────────────────────────────
if ($Silent -and $Customer -and $Destination) {
    $backupFolder = Join-Path $Destination "$($Customer -replace '[^\w\-]','_')_$($env:COMPUTERNAME)_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    New-Item $backupFolder -ItemType Directory -Force | Out-Null
    $stats = @{ Copied = 0; Failed = 0; Skipped = 0; VerifyFailed = 0; BytesCopied = [long]0 }
    $logEntries = @()
    $statsRef = [ref]$stats
    $logRef = [ref]$logEntries
    $userFolders = @("Desktop", "Documents", "Downloads", "Pictures", "Videos", "Music")

    foreach ($prof in (Get-UserProfiles)) {
        Backup-UserFolders -UserPath $prof.Path -UserName $prof.Name -BackupRoot $backupFolder -Folders $userFolders -Stats $statsRef -Log $logRef
        Backup-BrowserData -UserPath $prof.Path -UserName $prof.Name -BackupRoot $backupFolder -Stats $statsRef -Log $logRef
        Backup-EmailData -UserPath $prof.Path -UserName $prof.Name -BackupRoot $backupFolder -Stats $statsRef -Log $logRef
    }
    Backup-WindowsSettings -BackupRoot $backupFolder -Stats $statsRef -Log $logRef
    Backup-Drivers -BackupRoot $backupFolder -Stats $statsRef -Log $logRef
    Backup-SecurityData -BackupRoot $backupFolder -Stats $statsRef -Log $logRef
    Backup-RepairEvidence -BackupRoot $backupFolder -Stats $statsRef -Log $logRef

    Generate-BackupReport -BackupRoot $backupFolder -CustomerName $Customer -Stats $stats -LogEntries $logEntries -Mode "Backup" | Out-Null
    Write-Output "Backup complete: $($stats.Copied) files, $(Format-Size $stats.BytesCopied). Saved to: $backupFolder"
} else {
    Show-BackupUI
}

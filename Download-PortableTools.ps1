<#
.SYNOPSIS
    PC Plus 360 - Portable Diagnostic Tools Downloader
.DESCRIPTION
    Downloads free portable diagnostic tools from official sources, extracts
    ZIP archives, and organizes executables into category folders matching the
    PC Plus 360 USB toolkit structure. Re-runnable: skips tools that already
    exist, or re-downloads if the -Force switch is used.
.NOTES
    Company:  PC Plus Computing
    Website:  pcpluscomputing.com
    Phone:    604-760-1662 | 236-500-2700
    Version:  1.0.0
    Requires: PowerShell 5.1+, Windows 10/11, Internet connection
    Part of:  PC Plus 360 USB Diagnostic Toolkit
.PARAMETER Force
    Re-download all tools even if they already exist locally.
.PARAMETER SkipSysinternals
    Skip the Sysinternals Suite download (useful if already extracted).
.EXAMPLE
    PowerShell.exe -ExecutionPolicy Bypass -File .\Download-PortableTools.ps1
.EXAMPLE
    PowerShell.exe -ExecutionPolicy Bypass -File .\Download-PortableTools.ps1 -Force
#>

param(
    [switch]$Force,
    [switch]$SkipSysinternals
)

#Requires -Version 5.1

$ErrorActionPreference = 'Continue'

trap {
    Write-Host ""
    Write-Host "  UNEXPECTED ERROR: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "  Line: $($_.InvocationInfo.ScriptLineNumber)" -ForegroundColor DarkGray
    Write-Host ""
    Read-Host "  Press Enter to exit"
    break
}

# ─────────────────────────────────────────────────────────────────────────────
# TLS CONFIGURATION
# ─────────────────────────────────────────────────────────────────────────────
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ─────────────────────────────────────────────────────────────────────────────
# PATHS
# ─────────────────────────────────────────────────────────────────────────────
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
if ([string]::IsNullOrEmpty($ScriptDir)) { $ScriptDir = Get-Location }
$ToolsDir    = Join-Path $ScriptDir "Tools"
$TempDir     = Join-Path $ScriptDir "_downloads"
$SysintDir   = Join-Path $TempDir   "Sysinternals"

if (-not (Test-Path $ToolsDir)) { New-Item -Path $ToolsDir -ItemType Directory -Force | Out-Null }
if (-not (Test-Path $TempDir))  { New-Item -Path $TempDir  -ItemType Directory -Force | Out-Null }

# ─────────────────────────────────────────────────────────────────────────────
# COUNTERS
# ─────────────────────────────────────────────────────────────────────────────
$script:CountDownloaded = 0
$script:CountExtracted  = 0
$script:CountSkipped    = 0
$script:CountFailed     = 0
$script:CountManual     = 0
$script:FailedTools     = @()
$script:ManualTools     = @()

# ─────────────────────────────────────────────────────────────────────────────
# BRANDING BANNER
# ─────────────────────────────────────────────────────────────────────────────
function Show-Banner {
    Clear-Host
    Write-Host ""
    Write-Host "  ╔══════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "  ║                                                                  ║" -ForegroundColor Cyan
    Write-Host "  ║     PC Plus 360 - Portable Tools Downloader                      ║" -ForegroundColor Cyan
    Write-Host "  ║     PC Plus Computing | 604-760-1662 | 236-500-2700              ║" -ForegroundColor Cyan
    Write-Host "  ║     pcpluscomputing.com                                          ║" -ForegroundColor Cyan
    Write-Host "  ║                                                                  ║" -ForegroundColor Cyan
    Write-Host "  ╚══════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Downloads portable diagnostic tools from official sources" -ForegroundColor Gray
    Write-Host "  and organizes them into the Tools\ category folders." -ForegroundColor Gray
    Write-Host ""
    if ($Force) {
        Write-Host "  MODE: FORCE RE-DOWNLOAD (all tools will be re-downloaded)" -ForegroundColor Yellow
    } else {
        Write-Host "  MODE: Smart Update (existing tools will be skipped)" -ForegroundColor Green
    }
    Write-Host ""
}

# ─────────────────────────────────────────────────────────────────────────────
# HELPER FUNCTIONS
# ─────────────────────────────────────────────────────────────────────────────
function Write-Status {
    param(
        [string]$Message,
        [string]$Status,
        [ConsoleColor]$Color = [ConsoleColor]::White
    )
    Write-Host "  $Message" -ForegroundColor White -NoNewline
    Write-Host " $Status" -ForegroundColor $Color
}

function Write-Section {
    param([string]$Title, [string]$Icon = "")
    Write-Host ""
    Write-Host "  ────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host "  $Icon $Title" -ForegroundColor Cyan
    Write-Host "  ────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
}

function Write-ToolAction {
    param(
        [string]$ToolName,
        [string]$Action,
        [ConsoleColor]$Color = [ConsoleColor]::Green
    )
    $pad = $ToolName.PadRight(28)
    Write-Host "    $pad" -ForegroundColor White -NoNewline
    Write-Host "[$Action]" -ForegroundColor $Color
}

function Ensure-Folder {
    param([string]$FolderPath)
    if (-not (Test-Path $FolderPath)) {
        New-Item -Path $FolderPath -ItemType Directory -Force | Out-Null
    }
    return $FolderPath
}

function Get-CategoryPath {
    param([string]$CategoryName)
    $path = Join-Path $ToolsDir $CategoryName
    return (Ensure-Folder $path)
}

function Test-ToolExists {
    param(
        [string]$CategoryName,
        [string[]]$FileNames
    )
    $catPath = Join-Path $ToolsDir $CategoryName
    foreach ($fn in $FileNames) {
        $fp = Join-Path $catPath $fn
        if (Test-Path $fp) { return $true }
    }
    return $false
}

function Download-File {
    param(
        [string]$Url,
        [string]$OutPath,
        [string]$ToolName
    )
    try {
        $webClient = New-Object System.Net.WebClient
        $webClient.Headers.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36")
        Write-Host "      Downloading... " -ForegroundColor DarkGray -NoNewline
        $webClient.DownloadFile($Url, $OutPath)
        $sizeMB = [Math]::Round((Get-Item $OutPath).Length / 1MB, 2)
        Write-Host "${sizeMB} MB" -ForegroundColor DarkGray
        $script:CountDownloaded++
        return $true
    } catch {
        Write-Host "FAILED" -ForegroundColor Red
        Write-Host "      Error: $($_.Exception.Message)" -ForegroundColor DarkRed
        $script:CountFailed++
        $script:FailedTools += "$ToolName ($Url)"
        return $false
    } finally {
        if ($webClient) { $webClient.Dispose() }
    }
}

function Extract-Zip {
    param(
        [string]$ZipPath,
        [string]$DestPath
    )
    try {
        if (-not (Test-Path $DestPath)) {
            New-Item -Path $DestPath -ItemType Directory -Force | Out-Null
        }
        Expand-Archive -Path $ZipPath -DestinationPath $DestPath -Force
        $script:CountExtracted++
        return $true
    } catch {
        Write-Host "      Extract failed: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

function Copy-ToolFile {
    param(
        [string]$SourcePath,
        [string]$DestFolder,
        [string]$FileName = ""
    )
    if ([string]::IsNullOrEmpty($FileName)) {
        $FileName = Split-Path -Leaf $SourcePath
    }
    $dest = Join-Path $DestFolder $FileName
    if (Test-Path $SourcePath) {
        Copy-Item -Path $SourcePath -Destination $dest -Force
        return $true
    }
    return $false
}

# Copy a file from a source folder, trying multiple possible names
function Copy-ToolFromSource {
    param(
        [string]$SourceFolder,
        [string[]]$PossibleNames,
        [string]$DestFolder
    )
    foreach ($name in $PossibleNames) {
        $src = Join-Path $SourceFolder $name
        if (Test-Path $src) {
            Copy-Item -Path $src -Destination (Join-Path $DestFolder $name) -Force
            return $name
        }
    }
    return $null
}

# ─────────────────────────────────────────────────────────────────────────────
# DOWNLOAD + DISTRIBUTE: SYSINTERNALS SUITE
# ─────────────────────────────────────────────────────────────────────────────
function Download-SysinternalsSuite {
    Write-Section "Microsoft Sysinternals Suite" "MSFT"

    $zipPath = Join-Path $TempDir "SysinternalsSuite.zip"
    $extractPath = $SysintDir

    # Download the full suite
    $needsDownload = $Force -or -not (Test-Path $extractPath) -or ((Get-ChildItem $extractPath -ErrorAction SilentlyContinue).Count -eq 0)

    if ($needsDownload) {
        Write-Host "    Downloading Sysinternals Suite (all-in-one ~45 MB)..." -ForegroundColor White
        $ok = Download-File -Url "https://download.sysinternals.com/files/SysinternalsSuite.zip" -OutPath $zipPath -ToolName "Sysinternals Suite"
        if ($ok) {
            Write-Host "      Extracting suite..." -ForegroundColor DarkGray
            Extract-Zip -ZipPath $zipPath -DestPath $extractPath
        } else {
            Write-Host "    Sysinternals download failed. Skipping all Sysinternals tools." -ForegroundColor Red
            return
        }
    } else {
        Write-Host "    Sysinternals Suite already extracted. Distributing tools..." -ForegroundColor DarkGray
    }

    # Distribute Sysinternals tools into category folders
    $sysMap = @{
        "System Information" = @(
            @("Coreinfo64.exe", "Coreinfo.exe"),
            @("PsInfo64.exe", "PsInfo.exe"),
            @("Clockres64.exe", "Clockres.exe"),
            @("Bginfo64.exe", "Bginfo.exe")
        )
        "Security & Malware" = @(
            @("Autoruns64.exe", "Autoruns.exe"),
            @("autorunsc64.exe", "autorunsc.exe"),
            @("sigcheck64.exe", "sigcheck.exe"),
            @("Sysmon64.exe", "Sysmon.exe"),
            @("accesschk64.exe", "accesschk.exe"),
            @("AccessEnum.exe"),
            @("ShareEnum64.exe", "ShareEnum.exe"),
            @("efsdump.exe")
        )
        "Network & Connectivity" = @(
            @("tcpview64.exe", "tcpview.exe", "Tcpview.exe"),
            @("psping64.exe", "psping.exe"),
            @("tcpvcon64.exe", "tcpvcon.exe"),
            @("Whois64.exe", "whois64.exe", "whois.exe"),
            @("portmon.exe", "Portmon.exe")
        )
        "Process & Memory" = @(
            @("procexp64.exe", "procexp.exe"),
            @("Procmon64.exe", "Procmon.exe"),
            @("RAMMap64.exe", "RAMMap.exe"),
            @("vmmap64.exe", "vmmap.exe"),
            @("handle64.exe", "handle.exe"),
            @("Listdlls64.exe", "Listdlls.exe"),
            @("pslist64.exe", "pslist.exe"),
            @("pskill64.exe", "pskill.exe"),
            @("pssuspend64.exe", "pssuspend.exe"),
            @("procdump64.exe", "procdump.exe"),
            @("CPUSTRES64.EXE", "CPUSTRES.EXE"),
            @("Testlimit64.exe", "Testlimit.exe")
        )
        "Disk & Storage" = @(
            @("DiskView64.exe", "DiskView.exe", "Diskview.exe"),
            @("disk2vhd64.exe", "disk2vhd.exe"),
            @("Diskmon64.exe", "Diskmon.exe"),
            @("sdelete64.exe", "sdelete.exe"),
            @("Contig64.exe", "Contig.exe"),
            @("du64.exe", "du.exe"),
            @("sync64.exe", "sync.exe")
        )
        "Registry & File System" = @(
            @("regjump.exe", "RegJump.exe"),
            @("streams64.exe", "streams.exe"),
            @("junction64.exe", "junction.exe"),
            @("strings64.exe", "strings.exe"),
            @("FindLinks64.exe", "FindLinks.exe"),
            @("hex2dec64.exe", "hex2dec.exe"),
            @("movefile64.exe", "movefile.exe"),
            @("pendmoves64.exe", "pendmoves.exe")
        )
        "Active Directory" = @(
            @("ADExplorer64.exe", "ADExplorer.exe"),
            @("ADInsight64.exe", "ADInsight.exe"),
            @("PsGetsid64.exe", "PsGetsid.exe"),
            @("PsLoggedon64.exe", "PsLoggedon.exe"),
            @("logonsessions64.exe", "logonsessions.exe"),
            @("Ldmdump.exe")
        )
        "Remote & Administration" = @(
            @("PsExec64.exe", "PsExec.exe"),
            @("ShellRunas.exe"),
            @("PsService64.exe", "PsService.exe"),
            @("psshutdown64.exe", "psshutdown.exe"),
            @("Autologon64.exe", "Autologon.exe"),
            @("dbgview64.exe", "Dbgview.exe"),
            @("RDCMan.exe"),
            @("PsPasswd64.exe", "PsPasswd.exe")
        )
        "Event Logs & Monitoring" = @(
            @("ZoomIt64.exe", "ZoomIt.exe"),
            @("Sysmon64.exe")
        )
    }

    $totalCopied = 0
    foreach ($category in $sysMap.Keys) {
        $catPath = Get-CategoryPath $category
        $copiedInCat = 0

        foreach ($names in $sysMap[$category]) {
            $found = Copy-ToolFromSource -SourceFolder $extractPath -PossibleNames $names -DestFolder $catPath
            if ($found) { $copiedInCat++ }
        }

        $totalCopied += $copiedInCat
        if ($copiedInCat -gt 0) {
            Write-ToolAction "$category" "$copiedInCat tools placed" Green
        }
    }

    Write-Host ""
    Write-Host "    Sysinternals: $totalCopied tools distributed across categories" -ForegroundColor Green
}

# ─────────────────────────────────────────────────────────────────────────────
# DOWNLOAD: NIRSOFT TOOLS
# ─────────────────────────────────────────────────────────────────────────────
function Download-NirSoftTools {
    Write-Section "NirSoft Utilities" "NS"

    $nirDestFolder   = Get-CategoryPath "NirSoft"
    $nirCategoryDest = @{
        "Network & Connectivity"     = Get-CategoryPath "Network & Connectivity"
        "Browser & Internet"         = Get-CategoryPath "Browser & Internet"
        "Data Recovery & Forensics"  = Get-CategoryPath "Data Recovery & Forensics"
        "Event Logs & Monitoring"    = Get-CategoryPath "Event Logs & Monitoring"
        "Registry & File System"     = Get-CategoryPath "Registry & File System"
        "System Information"         = Get-CategoryPath "System Information"
        "Hardware Stress Testing"    = Get-CategoryPath "Hardware Stress Testing"
        "Process & Memory"           = Get-CategoryPath "Process & Memory"
    }

    # NirSoft tool definitions: name, zip slug, exe name, also-copy-to category
    $nirTools = @(
        @{ Name="BrowsingHistoryView";  Zip="browsinghistoryview.zip";  Exe="BrowsingHistoryView.exe";  Cat="Browser & Internet" }
        @{ Name="ChromeCacheView";       Zip="chromecacheview.zip";      Exe="ChromeCacheView.exe";       Cat="Browser & Internet" }
        @{ Name="EdgeCookiesView";       Zip="edgecookiesview.zip";      Exe="EdgeCookiesView.exe";       Cat="Browser & Internet" }
        @{ Name="BrowserDownloadsView";  Zip="browserdownloadsview.zip"; Exe="BrowserDownloadsView.exe";  Cat="Browser & Internet" }
        @{ Name="MozillaCacheView";      Zip="mozillacacheview.zip";     Exe="MozillaCacheView.exe";      Cat="Browser & Internet" }
        @{ Name="VideoCacheView";        Zip="videocacheview.zip";       Exe="VideoCacheView.exe";        Cat="Browser & Internet" }
        @{ Name="CurrPorts";             Zip="cports.zip";               Exe="cports.exe";                Cat="Network & Connectivity" }
        @{ Name="WirelessNetView";       Zip="wirelessnetview.zip";      Exe="WirelessNetView.exe";       Cat="Network & Connectivity" }
        @{ Name="NetworkInterfacesView"; Zip="networkinterfacesview.zip";Exe="NetworkInterfacesView.exe"; Cat="Network & Connectivity" }
        @{ Name="NetworkTrafficView";    Zip="networktrafficview.zip";   Exe="NetworkTrafficView.exe";    Cat="Network & Connectivity" }
        @{ Name="SmartSniff";            Zip="smsniff.zip";              Exe="smsniff.exe";               Cat="Network & Connectivity" }
        @{ Name="WebSiteSniffer";        Zip="websitesniffer.zip";       Exe="WebSiteSniffer.exe";        Cat="Network & Connectivity" }
        @{ Name="DNSQuerySniffer";       Zip="dnsquerysniffer.zip";      Exe="DNSQuerySniffer.exe";       Cat="Network & Connectivity" }
        @{ Name="USBDeview";             Zip="usbdeview.zip";            Exe="USBDeview.exe";             Cat="Event Logs & Monitoring" }
        @{ Name="USBLogView";            Zip="usblogview.zip";           Exe="USBLogView.exe";            Cat="Event Logs & Monitoring" }
        @{ Name="FullEventLogView";      Zip="fulleventlogview.zip";     Exe="FullEventLogView.exe";      Cat="Event Logs & Monitoring" }
        @{ Name="LastActivityView";      Zip="lastactivityview.zip";     Exe="LastActivityView.exe";      Cat="Data Recovery & Forensics" }
        @{ Name="ShellBagsView";         Zip="shellbagsview.zip";        Exe="ShellBagsView.exe";         Cat="Data Recovery & Forensics" }
        @{ Name="ExecutedProgramsList";  Zip="executedprogramslist.zip"; Exe="ExecutedProgramsList.exe";  Cat="Data Recovery & Forensics" }
        @{ Name="JumpListsView";         Zip="jumplistsview.zip";        Exe="JumpListsView.exe";         Cat="Data Recovery & Forensics" }
        @{ Name="RecentFilesView";       Zip="recentfilesview.zip";      Exe="RecentFilesView.exe";       Cat="Data Recovery & Forensics" }
        @{ Name="SearchMyFiles";         Zip="searchmyfiles.zip";        Exe="SearchMyFiles.exe";         Cat="Registry & File System" }
        @{ Name="OpenedFilesView";       Zip="openedfilesview.zip";      Exe="OpenedFilesView.exe";       Cat="Registry & File System" }
        @{ Name="FolderChangesView";     Zip="folderchangesview.zip";    Exe="FolderChangesView.exe";     Cat="Registry & File System" }
        @{ Name="BlueScreenView";        Zip="bluescreenview.zip";       Exe="BlueScreenView.exe";        Cat="Hardware Stress Testing" }
        @{ Name="BluetoothView";         Zip="bluetoothview.zip";        Exe="BluetoothView.exe";         Cat="System Information" }
        @{ Name="DevManView";            Zip="devmanview.zip";           Exe="DevManView.exe";            Cat="System Information" }
        @{ Name="DriverView";            Zip="driverview.zip";           Exe="DriverView.exe";            Cat="System Information" }
        @{ Name="WifiInfoView";          Zip="wifiinfoview.zip";         Exe="WifiInfoView.exe";          Cat="System Information" }
        @{ Name="BatteryInfoView";       Zip="batteryinfoview.zip";      Exe="BatteryInfoView.exe";       Cat="System Information" }
        @{ Name="AppCrashView";          Zip="appcrashview.zip";         Exe="AppCrashView.exe";          Cat="Process & Memory" }
        @{ Name="WinCrashReport";        Zip="wincrashreport.zip";       Exe="WinCrashReport.exe";        Cat="Process & Memory" }
        @{ Name="WhatIsHang";            Zip="whatishang.zip";           Exe="WhatIsHang.exe";            Cat="Process & Memory" }
    )

    $nirTotal   = $nirTools.Count
    $nirCurrent = 0

    foreach ($tool in $nirTools) {
        $nirCurrent++
        $progress = "[$nirCurrent/$nirTotal]"

        # Check if already exists in NirSoft folder or category folder
        $nirExePath = Join-Path $nirDestFolder $tool.Exe
        $catExePath = Join-Path $nirCategoryDest[$tool.Cat] $tool.Exe

        if (-not $Force -and ((Test-Path $nirExePath) -or (Test-Path $catExePath))) {
            Write-ToolAction "$progress $($tool.Name)" "EXISTS - skipped" DarkGray
            $script:CountSkipped++
            continue
        }

        # Download
        $url     = "https://www.nirsoft.net/utils/$($tool.Zip)"
        $zipDest = Join-Path $TempDir $tool.Zip
        $extDest = Join-Path $TempDir ("nirsoft_" + $tool.Name)

        Write-Host "    $progress $($tool.Name)" -ForegroundColor White
        $ok = Download-File -Url $url -OutPath $zipDest -ToolName $tool.Name

        if ($ok) {
            # Extract
            if (Test-Path $extDest) { Remove-Item $extDest -Recurse -Force }
            $extracted = Extract-Zip -ZipPath $zipDest -DestPath $extDest

            if ($extracted) {
                $exeSrc = Join-Path $extDest $tool.Exe
                # Some NirSoft ZIPs put files in a subfolder
                if (-not (Test-Path $exeSrc)) {
                    $found = Get-ChildItem -Path $extDest -Filter $tool.Exe -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
                    if ($found) { $exeSrc = $found.FullName }
                }

                if (Test-Path $exeSrc) {
                    # Copy to NirSoft folder
                    Copy-Item -Path $exeSrc -Destination $nirExePath -Force
                    # Also copy to category folder
                    if ($nirCategoryDest.ContainsKey($tool.Cat)) {
                        Copy-Item -Path $exeSrc -Destination $catExePath -Force
                    }
                    Write-ToolAction "  -> placed in" "NirSoft/ + $($tool.Cat)/" Green
                } else {
                    Write-Host "      Warning: $($tool.Exe) not found in extracted archive" -ForegroundColor Yellow
                }
            }

            # Clean up temp extraction
            if (Test-Path $extDest) { Remove-Item $extDest -Recurse -Force -ErrorAction SilentlyContinue }
            if (Test-Path $zipDest) { Remove-Item $zipDest -Force -ErrorAction SilentlyContinue }
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# DOWNLOAD: STANDALONE TOOLS (Third-party)
# ─────────────────────────────────────────────────────────────────────────────
function Download-StandaloneTools {
    Write-Section "Standalone Third-Party Tools" "3P"

    # ── CPU-Z ────────────────────────────────────────────────────────────────
    $cpuzCategory = Get-CategoryPath "System Information"
    $cpuzExists = Get-ChildItem -Path $cpuzCategory -Filter "cpuz*" -ErrorAction SilentlyContinue | Where-Object { $_.Extension -eq ".exe" }

    if (-not $Force -and $cpuzExists) {
        Write-ToolAction "CPU-Z" "EXISTS - skipped" DarkGray
        $script:CountSkipped++
    } else {
        Write-Host "    CPU-Z (Portable)" -ForegroundColor White
        # CPU-Z download: the portable ZIP URL pattern from CPUID
        $cpuzUrl = "https://download.cpuid.com/cpu-z/cpu-z_2.12-en.zip"
        $cpuzZip = Join-Path $TempDir "cpu-z.zip"
        $cpuzExt = Join-Path $TempDir "cpu-z"

        $ok = Download-File -Url $cpuzUrl -OutPath $cpuzZip -ToolName "CPU-Z"
        if ($ok) {
            Extract-Zip -ZipPath $cpuzZip -DestPath $cpuzExt
            # Look for the 64-bit exe
            $cpuzExe = Get-ChildItem -Path $cpuzExt -Filter "cpuz_x64.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
            if (-not $cpuzExe) {
                $cpuzExe = Get-ChildItem -Path $cpuzExt -Filter "cpuz*.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
            }
            if ($cpuzExe) {
                Copy-Item -Path $cpuzExe.FullName -Destination (Join-Path $cpuzCategory $cpuzExe.Name) -Force
                Write-ToolAction "  -> placed in" "System Information/" Green
            } else {
                Write-Host "      Warning: cpuz exe not found in archive" -ForegroundColor Yellow
            }
            # Clean up
            Remove-Item $cpuzExt -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item $cpuzZip -Force -ErrorAction SilentlyContinue
        }
    }

    # ── HWMonitor ────────────────────────────────────────────────────────────
    $hwmCategory = Get-CategoryPath "System Information"
    $hwmExists = Get-ChildItem -Path $hwmCategory -Filter "HWMonitor*" -ErrorAction SilentlyContinue | Where-Object { $_.Extension -eq ".exe" }

    if (-not $Force -and $hwmExists) {
        Write-ToolAction "HWMonitor" "EXISTS - skipped" DarkGray
        $script:CountSkipped++
    } else {
        Write-Host "    HWMonitor (Portable)" -ForegroundColor White
        $hwmUrl = "https://download.cpuid.com/hwmonitor/hwmonitor_1.55.zip"
        $hwmZip = Join-Path $TempDir "hwmonitor.zip"
        $hwmExt = Join-Path $TempDir "hwmonitor"

        $ok = Download-File -Url $hwmUrl -OutPath $hwmZip -ToolName "HWMonitor"
        if ($ok) {
            Extract-Zip -ZipPath $hwmZip -DestPath $hwmExt
            $hwmExe = Get-ChildItem -Path $hwmExt -Filter "HWMonitor_x64.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
            if (-not $hwmExe) {
                $hwmExe = Get-ChildItem -Path $hwmExt -Filter "HWMonitor*.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
            }
            if ($hwmExe) {
                Copy-Item -Path $hwmExe.FullName -Destination (Join-Path $hwmCategory $hwmExe.Name) -Force
                Write-ToolAction "  -> placed in" "System Information/" Green
            }
            Remove-Item $hwmExt -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item $hwmZip -Force -ErrorAction SilentlyContinue
        }
    }

    # ── GPU-Z ────────────────────────────────────────────────────────────────
    $gpuzCategory = Get-CategoryPath "System Information"
    $gpuzExists = Get-ChildItem -Path $gpuzCategory -Filter "GPU-Z*" -ErrorAction SilentlyContinue | Where-Object { $_.Extension -eq ".exe" }

    if (-not $Force -and $gpuzExists) {
        Write-ToolAction "GPU-Z" "EXISTS - skipped" DarkGray
        $script:CountSkipped++
    } else {
        Write-Host "    GPU-Z" -ForegroundColor White
        Write-Host "      Dynamic download link - requires manual download" -ForegroundColor Yellow
        Write-Host "      Please download from: https://www.techpowerup.com/gpuz/" -ForegroundColor Yellow
        Write-Host "      Place GPU-Z.exe in: Tools\System Information\" -ForegroundColor Yellow
        $script:CountManual++
        $script:ManualTools += "GPU-Z -> https://www.techpowerup.com/gpuz/"
    }

    # ── HWiNFO64 ─────────────────────────────────────────────────────────────
    $hwinfoCategory = Get-CategoryPath "System Information"
    $hwinfoExists = Get-ChildItem -Path $hwinfoCategory -Filter "HWiNFO*" -ErrorAction SilentlyContinue | Where-Object { $_.Extension -eq ".exe" }

    if (-not $Force -and $hwinfoExists) {
        Write-ToolAction "HWiNFO64" "EXISTS - skipped" DarkGray
        $script:CountSkipped++
    } else {
        Write-Host "    HWiNFO64" -ForegroundColor White
        Write-Host "      Dynamic download link - requires manual download" -ForegroundColor Yellow
        Write-Host "      Please download from: https://www.hwinfo.com/download/" -ForegroundColor Yellow
        Write-Host "      Download the PORTABLE version (ZIP), extract HWiNFO64.exe" -ForegroundColor Yellow
        Write-Host "      Place in: Tools\System Information\" -ForegroundColor Yellow
        $script:CountManual++
        $script:ManualTools += "HWiNFO64 -> https://www.hwinfo.com/download/"
    }

    # ── CrystalDiskInfo ──────────────────────────────────────────────────────
    $cdiCategory = Get-CategoryPath "System Information"
    $cdiExists = Get-ChildItem -Path $cdiCategory -Filter "*DiskInfo*" -ErrorAction SilentlyContinue | Where-Object { $_.Extension -eq ".exe" }

    if (-not $Force -and $cdiExists) {
        Write-ToolAction "CrystalDiskInfo" "EXISTS - skipped" DarkGray
        $script:CountSkipped++
    } else {
        Write-Host "    CrystalDiskInfo" -ForegroundColor White
        Write-Host "      Dynamic download link - requires manual download" -ForegroundColor Yellow
        Write-Host "      Please download from: https://crystalmark.info/en/download/" -ForegroundColor Yellow
        Write-Host "      Download the PORTABLE version (ZIP), extract DiskInfo64.exe" -ForegroundColor Yellow
        Write-Host "      Place in: Tools\System Information\" -ForegroundColor Yellow
        $script:CountManual++
        $script:ManualTools += "CrystalDiskInfo -> https://crystalmark.info/en/download/"
    }

    # ── AdwCleaner ───────────────────────────────────────────────────────────
    $adwCategory = Get-CategoryPath "Security & Malware"
    $adwPath = Join-Path $adwCategory "adwcleaner.exe"

    if (-not $Force -and (Test-Path $adwPath)) {
        Write-ToolAction "AdwCleaner" "EXISTS - skipped" DarkGray
        $script:CountSkipped++
    } else {
        Write-Host "    AdwCleaner (Malwarebytes)" -ForegroundColor White
        $adwUrl = "https://adwcleaner.malwarebytes.com/adwcleaner?channel=release"
        $ok = Download-File -Url $adwUrl -OutPath $adwPath -ToolName "AdwCleaner"
        if ($ok) {
            Write-ToolAction "  -> placed in" "Security & Malware/" Green
        }
    }

    # ── Rufus ────────────────────────────────────────────────────────────────
    $rufusCategory = Get-CategoryPath "Disk & Storage"
    $rufusExists = Get-ChildItem -Path $rufusCategory -Filter "rufus*" -ErrorAction SilentlyContinue | Where-Object { $_.Extension -eq ".exe" }

    if (-not $Force -and $rufusExists) {
        Write-ToolAction "Rufus" "EXISTS - skipped" DarkGray
        $script:CountSkipped++
    } else {
        Write-Host "    Rufus (Portable USB Creator)" -ForegroundColor White
        # Rufus provides direct download links on GitHub
        $rufusUrl = "https://github.com/pbatard/rufus/releases/download/v4.6/rufus-4.6p.exe"
        $rufusDest = Join-Path $rufusCategory "rufus-4.6p.exe"

        $ok = Download-File -Url $rufusUrl -OutPath $rufusDest -ToolName "Rufus"
        if ($ok) {
            Write-ToolAction "  -> placed in" "Disk & Storage/" Green
        }
    }

    # ── TestDisk / PhotoRec ──────────────────────────────────────────────────
    $recCategory = Get-CategoryPath "Data Recovery & Forensics"
    $tdExists = Get-ChildItem -Path $recCategory -Filter "testdisk*" -ErrorAction SilentlyContinue | Where-Object { $_.Extension -eq ".exe" }

    if (-not $Force -and $tdExists) {
        Write-ToolAction "TestDisk/PhotoRec" "EXISTS - skipped" DarkGray
        $script:CountSkipped++
    } else {
        Write-Host "    TestDisk / PhotoRec (CGSecurity)" -ForegroundColor White
        $tdUrl = "https://www.cgsecurity.org/testdisk-7.2.win64.zip"
        $tdZip = Join-Path $TempDir "testdisk.zip"
        $tdExt = Join-Path $TempDir "testdisk"

        $ok = Download-File -Url $tdUrl -OutPath $tdZip -ToolName "TestDisk/PhotoRec"
        if ($ok) {
            Extract-Zip -ZipPath $tdZip -DestPath $tdExt
            # Find the executables
            $tdExeFiles = @("testdisk_win.exe", "photorec_win.exe", "qphotorec_win.exe", "fidentify_win.exe")
            foreach ($exeName in $tdExeFiles) {
                $foundExe = Get-ChildItem -Path $tdExt -Filter $exeName -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($foundExe) {
                    Copy-Item -Path $foundExe.FullName -Destination (Join-Path $recCategory $exeName) -Force
                }
            }
            Write-ToolAction "  -> placed in" "Data Recovery & Forensics/" Green

            Remove-Item $tdExt -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item $tdZip -Force -ErrorAction SilentlyContinue
        }
    }

    # ── OpenHardwareMonitor ──────────────────────────────────────────────────
    $ohmCategory = Get-CategoryPath "Hardware Stress Testing"
    $ohmPath = Join-Path $ohmCategory "OpenHardwareMonitor.exe"

    if (-not $Force -and (Test-Path $ohmPath)) {
        Write-ToolAction "OpenHardwareMonitor" "EXISTS - skipped" DarkGray
        $script:CountSkipped++
    } else {
        Write-Host "    OpenHardwareMonitor" -ForegroundColor White
        $ohmUrl = "https://openhardwaremonitor.org/files/openhardwaremonitor-v0.9.6.zip"
        $ohmZip = Join-Path $TempDir "openhardwaremonitor.zip"
        $ohmExt = Join-Path $TempDir "openhardwaremonitor"

        $ok = Download-File -Url $ohmUrl -OutPath $ohmZip -ToolName "OpenHardwareMonitor"
        if ($ok) {
            Extract-Zip -ZipPath $ohmZip -DestPath $ohmExt
            $ohmExe = Get-ChildItem -Path $ohmExt -Filter "OpenHardwareMonitor.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($ohmExe) {
                # Copy exe and DLL dependencies
                $ohmSrcDir = Split-Path -Parent $ohmExe.FullName
                Copy-Item -Path $ohmExe.FullName -Destination $ohmPath -Force
                # Copy supporting files if they exist
                Get-ChildItem -Path $ohmSrcDir -Filter "*.dll" -ErrorAction SilentlyContinue | ForEach-Object {
                    Copy-Item -Path $_.FullName -Destination (Join-Path $ohmCategory $_.Name) -Force
                }
                Get-ChildItem -Path $ohmSrcDir -Filter "*.sys" -ErrorAction SilentlyContinue | ForEach-Object {
                    Copy-Item -Path $_.FullName -Destination (Join-Path $ohmCategory $_.Name) -Force
                }
                Write-ToolAction "  -> placed in" "Hardware Stress Testing/" Green
            }
            Remove-Item $ohmExt -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item $ohmZip -Force -ErrorAction SilentlyContinue
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# CLEANUP TEMP
# ─────────────────────────────────────────────────────────────────────────────
function Clean-TempFiles {
    Write-Host ""
    Write-Host "  Cleaning up temporary downloads..." -ForegroundColor DarkGray
    # Remove individual ZIP files (keep Sysinternals extracted for future runs)
    Get-ChildItem -Path $TempDir -Filter "*.zip" -File -ErrorAction SilentlyContinue | ForEach-Object {
        Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
    }
    # Remove temp extraction folders (not Sysinternals)
    Get-ChildItem -Path $TempDir -Directory -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -ne "Sysinternals"
    } | ForEach-Object {
        Remove-Item $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# SUMMARY REPORT
# ─────────────────────────────────────────────────────────────────────────────
function Show-Summary {
    Write-Host ""
    Write-Host "  ╔══════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "  ║                       DOWNLOAD SUMMARY                           ║" -ForegroundColor Cyan
    Write-Host "  ╚══════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""

    $totalOps = $script:CountDownloaded + $script:CountSkipped + $script:CountFailed + $script:CountManual

    Write-Host "    Downloaded:       " -ForegroundColor White -NoNewline
    Write-Host "$($script:CountDownloaded)" -ForegroundColor Green

    Write-Host "    Extracted:        " -ForegroundColor White -NoNewline
    Write-Host "$($script:CountExtracted)" -ForegroundColor Green

    Write-Host "    Skipped (exist):  " -ForegroundColor White -NoNewline
    Write-Host "$($script:CountSkipped)" -ForegroundColor DarkGray

    Write-Host "    Manual required:  " -ForegroundColor White -NoNewline
    if ($script:CountManual -gt 0) {
        Write-Host "$($script:CountManual)" -ForegroundColor Yellow
    } else {
        Write-Host "0" -ForegroundColor Green
    }

    Write-Host "    Failed:           " -ForegroundColor White -NoNewline
    if ($script:CountFailed -gt 0) {
        Write-Host "$($script:CountFailed)" -ForegroundColor Red
    } else {
        Write-Host "0" -ForegroundColor Green
    }

    Write-Host ""

    # Show manual download list
    if ($script:ManualTools.Count -gt 0) {
        Write-Host "  ── Manual Downloads Required ──────────────────────────────────" -ForegroundColor Yellow
        foreach ($mt in $script:ManualTools) {
            Write-Host "    - $mt" -ForegroundColor Yellow
        }
        Write-Host ""
    }

    # Show failed tools
    if ($script:FailedTools.Count -gt 0) {
        Write-Host "  ── Failed Downloads ──────────────────────────────────────────" -ForegroundColor Red
        foreach ($ft in $script:FailedTools) {
            Write-Host "    - $ft" -ForegroundColor Red
        }
        Write-Host ""
    }

    # Tools folder size
    try {
        $totalSize = (Get-ChildItem -Path $ToolsDir -Recurse -File -ErrorAction SilentlyContinue |
            Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
        if ($totalSize) {
            $sizeMB = [Math]::Round($totalSize / 1MB, 1)
            Write-Host "    Tools folder size: $sizeMB MB" -ForegroundColor Gray
        }
    } catch {}

    # Category breakdown
    Write-Host ""
    Write-Host "  ── Tools per Category ────────────────────────────────────────" -ForegroundColor DarkGray
    Get-ChildItem -Path $ToolsDir -Directory -ErrorAction SilentlyContinue | Sort-Object Name | ForEach-Object {
        $exeCount = (Get-ChildItem -Path $_.FullName -Filter "*.exe" -File -ErrorAction SilentlyContinue).Count
        $catName = $_.Name.PadRight(32)
        if ($exeCount -gt 0) {
            Write-Host "    $catName" -ForegroundColor White -NoNewline
            Write-Host "$exeCount exe(s)" -ForegroundColor Green
        } else {
            Write-Host "    $catName" -ForegroundColor DarkGray -NoNewline
            Write-Host "empty" -ForegroundColor DarkGray
        }
    }

    Write-Host ""
    Write-Host "  ────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host "  PC Plus Computing | 604-760-1662 | 236-500-2700" -ForegroundColor Cyan
    Write-Host "  pcpluscomputing.com" -ForegroundColor Cyan
    Write-Host "  ────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host ""
}

# ─────────────────────────────────────────────────────────────────────────────
# MAIN EXECUTION
# ─────────────────────────────────────────────────────────────────────────────
$startTime = Get-Date

Show-Banner

Write-Host "  Target: $ToolsDir" -ForegroundColor Gray
Write-Host "  Temp:   $TempDir" -ForegroundColor Gray
Write-Host ""

# Step 1: Sysinternals Suite
if (-not $SkipSysinternals) {
    Download-SysinternalsSuite
} else {
    Write-Host ""
    Write-Host "  [SKIPPED] Sysinternals Suite (use without -SkipSysinternals to include)" -ForegroundColor DarkGray
}

# Step 2: NirSoft Tools
Download-NirSoftTools

# Step 3: Standalone third-party tools
Download-StandaloneTools

# Step 4: Cleanup
Clean-TempFiles

# Step 5: Summary
$elapsed = (Get-Date) - $startTime
Show-Summary

Write-Host "  Completed in $([Math]::Round($elapsed.TotalSeconds, 1)) seconds" -ForegroundColor Gray
Write-Host ""
Read-Host "  Press Enter to exit"

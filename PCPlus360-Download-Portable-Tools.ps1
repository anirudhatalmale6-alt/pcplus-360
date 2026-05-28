<#
PC Plus 360 Portable Tools Downloader
Author: PC Plus Computing
Purpose:
  Downloads and organizes selected portable repair, audit, forensic, networking,
  disk, hardware, Windows repair, Sysinternals, and NirSoft tools into category folders.

Important:
  - Run PowerShell as Administrator when possible.
  - Some password/security tools may trigger antivirus alerts. Use only with customer authorization.
  - Some vendors change download URLs. If a direct download fails, the report includes the official page.
  - Tools are downloaded from official vendor/source pages where possible.

Default output:
  C:\PCPlus360\Tools

Examples:
  .\PCPlus360-Download-Portable-Tools.ps1
  .\PCPlus360-Download-Portable-Tools.ps1 -RootPath "D:\Tools\PCPlus360"
  .\PCPlus360-Download-Portable-Tools.ps1 -IncludePasswordTools
#>

[CmdletBinding()]
param(
    [string]$RootPath = "C:\PCPlus360\Tools",
    [switch]$IncludePasswordTools,
    [switch]$SkipExtraction
)

$ErrorActionPreference = "Continue"

# Force TLS 1.2+
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

$DownloadRoot = Join-Path $RootPath "_Downloads"
$ReportPath   = Join-Path $RootPath "PCPlus360_Download_Report.csv"
$ReadmePath   = Join-Path $RootPath "README_PCPlus360_Toolkit.txt"

$Categories = @(
    @{ Name="01-SystemInformation"; Info="System inventory, drivers, services, startup, event logs, USB history, crash and BSOD review." },
    @{ Name="02-Networking"; Info="Ports, connections, WiFi diagnostics, DNS tools, ping monitoring, MAC lookup, packet and traffic visibility." },
    @{ Name="03-PasswordSecurity"; Info="Credential recovery tools for authorized customer work only. These may trigger antivirus alerts." },
    @{ Name="04-BrowserInternet"; Info="Browser history, cache, downloads, add-ons, and web activity troubleshooting." },
    @{ Name="05-ForensicsInvestigation"; Info="User activity, execution history, recent files, shellbags, jump lists, and registry change evidence." },
    @{ Name="06-DiskFilesystem"; Info="File search, hashing, SMART checks, folder monitoring, links, streams, and disk file-system review." },
    @{ Name="07-RegistryTools"; Info="Registry search, offline registry analysis, DLL registration review, and registry change tracking." },
    @{ Name="08-WiFiBluetooth"; Info="Bluetooth discovery, WiFi scanning, and wireless troubleshooting utilities." },
    @{ Name="09-CommandLineAutomation"; Info="Automation, monitor control, sound control, wake-on-LAN, and technician scripting utilities." },
    @{ Name="10-SystemInfo-CPU-GPU-Hardware"; Info="CPU, GPU, motherboard, sensors, RAM, temperatures, voltages, and full hardware diagnostics." },
    @{ Name="11-FanControl-Thermal"; Info="Fan curves, GPU fan control, overheating diagnosis, and thermal management tools." },
    @{ Name="12-DiskRepair-Recovery"; Info="SMART, surface scan, SSD/HDD testing, bad-sector detection, partition recovery, and deleted-file recovery." },
    @{ Name="13-StressTesting-Benchmarks"; Info="CPU, GPU, RAM, disk, and full-system load testing for stability and repair validation." },
    @{ Name="14-WindowsRepair"; Info="SFC/DISM helpers, Windows repair suites, driver repair, and common Windows issue remediation." },
    @{ Name="15-Sysinternals"; Info="Microsoft advanced diagnostics: Process Explorer, Autoruns, Procmon, TCPView, PsExec, RAMMap, Disk2vhd." },
    @{ Name="16-MalwareSecurityCleanup"; Info="Adware, malware, second-opinion scanners, and portable cleanup utilities." },
    @{ Name="17-NetworkForensics"; Info="Network discovery, packet capture, IP scanning, DFIR collection, and security investigation tools." },
    @{ Name="18-Documentation"; Info="Reports, notes, downloaded page references, and technician documentation." }
)

function New-SafeDirectory {
    param([string]$Path)
    if (!(Test-Path $Path)) { New-Item -ItemType Directory -Path $Path -Force | Out-Null }
}

function Get-SafeFileName {
    param([string]$Name)
    $invalid = [IO.Path]::GetInvalidFileNameChars() -join ''
    $regex = "[{0}]" -f [Regex]::Escape($invalid)
    return ($Name -replace $regex, "_")
}

function Invoke-DownloadFile {
    param(
        [string]$Url,
        [string]$Destination,
        [string]$OfficialPage
    )

    try {
        Write-Host "Downloading: $Url" -ForegroundColor Cyan
        Invoke-WebRequest -Uri $Url -OutFile $Destination -UseBasicParsing -TimeoutSec 120
        if ((Test-Path $Destination) -and ((Get-Item $Destination).Length -gt 0)) {
            return @{ Success=$true; Message="Downloaded" }
        }
        return @{ Success=$false; Message="File empty or missing" }
    }
    catch {
        return @{ Success=$false; Message=$_.Exception.Message }
    }
}

function Expand-DownloadedArchive {
    param(
        [string]$FilePath,
        [string]$DestinationFolder
    )

    if ($SkipExtraction) { return "Skipped extraction" }

    $ext = [IO.Path]::GetExtension($FilePath).ToLowerInvariant()
    if ($ext -ne ".zip") { return "Not a ZIP" }

    try {
        $extractFolder = Join-Path $DestinationFolder "_Extracted"
        New-SafeDirectory $extractFolder
        Expand-Archive -Path $FilePath -DestinationPath $extractFolder -Force

        # Copy EXE files from extracted content into the category folder root for easy launcher use.
        Get-ChildItem -Path $extractFolder -Recurse -Filter *.exe -ErrorAction SilentlyContinue | ForEach-Object {
            $target = Join-Path $DestinationFolder $_.Name
            Copy-Item $_.FullName $target -Force
        }
        return "Extracted ZIP and copied EXE files"
    }
    catch {
        return "Extraction failed: $($_.Exception.Message)"
    }
}

# Folder creation
New-SafeDirectory $RootPath
New-SafeDirectory $DownloadRoot
foreach ($cat in $Categories) { New-SafeDirectory (Join-Path $RootPath $cat.Name) }

# Toolkit README with background info
$readme = @()
$readme += "PC Plus 360 Portable Toolkit"
$readme += "Generated: $(Get-Date)"
$readme += ""
$readme += "Purpose: organized technician toolkit for repair, diagnostics, audits, security checks, ransomware investigation, Windows repair, hardware testing, and MSP support."
$readme += ""
$readme += "Important safety notes:"
$readme += "- Password recovery tools must only be used with written/customer authorization."
$readme += "- Some security tools may be detected as PUA/hacktools by antivirus."
$readme += "- Stress testing can overheat unstable systems. Monitor temperatures carefully."
$readme += "- Disk repair/recovery tools should be used carefully. Clone failing disks before heavy scans where possible."
$readme += ""
$readme += "Categories:"
foreach ($cat in $Categories) { $readme += "$($cat.Name): $($cat.Info)" }
$readme | Set-Content -Path $ReadmePath -Encoding UTF8

# Tool list
# DirectUrl is preferred. OfficialPage is included for reference and fallback.
$Tools = @(
    # 01 System Information - NirSoft
    @{ Category="01-SystemInformation"; Name="ProduKey"; DirectUrl="https://www.nirsoft.net/utils/produkey-x64.zip"; OfficialPage="https://www.nirsoft.net/utils/product_cd_key_viewer.html"; PasswordTool=$true },
    @{ Category="01-SystemInformation"; Name="DriverView"; DirectUrl="https://www.nirsoft.net/utils/driverview-x64.zip"; OfficialPage="https://www.nirsoft.net/utils/driverview.html"; PasswordTool=$false },
    @{ Category="01-SystemInformation"; Name="ServiWin"; DirectUrl="https://www.nirsoft.net/utils/serviwin-x64.zip"; OfficialPage="https://www.nirsoft.net/utils/serviwin.html"; PasswordTool=$false },
    @{ Category="01-SystemInformation"; Name="WhatInStartup"; DirectUrl="https://www.nirsoft.net/utils/whatinstartup-x64.zip"; OfficialPage="https://www.nirsoft.net/utils/what_run_in_startup.html"; PasswordTool=$false },
    @{ Category="01-SystemInformation"; Name="LastActivityView"; DirectUrl="https://www.nirsoft.net/utils/lastactivityview.zip"; OfficialPage="https://www.nirsoft.net/utils/computer_activity_view.html"; PasswordTool=$false },
    @{ Category="01-SystemInformation"; Name="USBDeview"; DirectUrl="https://www.nirsoft.net/utils/usbdeview-x64.zip"; OfficialPage="https://www.nirsoft.net/utils/usb_devices_view.html"; PasswordTool=$false },
    @{ Category="01-SystemInformation"; Name="BlueScreenView"; DirectUrl="https://www.nirsoft.net/utils/bluescreenview-x64.zip"; OfficialPage="https://www.nirsoft.net/utils/blue_screen_view.html"; PasswordTool=$false },
    @{ Category="01-SystemInformation"; Name="FullEventLogView"; DirectUrl="https://www.nirsoft.net/utils/fulleventlogview-x64.zip"; OfficialPage="https://www.nirsoft.net/utils/full_event_log_view.html"; PasswordTool=$false },
    @{ Category="01-SystemInformation"; Name="AppCrashView"; DirectUrl="https://www.nirsoft.net/utils/appcrashview.zip"; OfficialPage="https://www.nirsoft.net/utils/app_crash_view.html"; PasswordTool=$false },
    @{ Category="01-SystemInformation"; Name="OpenedFilesView"; DirectUrl="https://www.nirsoft.net/utils/ofview-x64.zip"; OfficialPage="https://www.nirsoft.net/utils/opened_files_view.html"; PasswordTool=$false },

    # 02 Networking - NirSoft
    @{ Category="02-Networking"; Name="CurrPorts"; DirectUrl="https://www.nirsoft.net/utils/cports-x64.zip"; OfficialPage="https://www.nirsoft.net/utils/cports.html"; PasswordTool=$false },
    @{ Category="02-Networking"; Name="WirelessNetView"; DirectUrl="https://www.nirsoft.net/utils/wirelessnetview.zip"; OfficialPage="https://www.nirsoft.net/utils/wireless_network_view.html"; PasswordTool=$false },
    @{ Category="02-Networking"; Name="WifiInfoView"; DirectUrl="https://www.nirsoft.net/utils/wifiinfoview-x64.zip"; OfficialPage="https://www.nirsoft.net/utils/wifi_information_view.html"; PasswordTool=$false },
    @{ Category="02-Networking"; Name="DNSDataView"; DirectUrl="https://www.nirsoft.net/utils/dnsdataview.zip"; OfficialPage="https://www.nirsoft.net/utils/dns_records_viewer.html"; PasswordTool=$false },
    @{ Category="02-Networking"; Name="SmartSniff"; DirectUrl="https://www.nirsoft.net/utils/smsniff-x64.zip"; OfficialPage="https://www.nirsoft.net/utils/smsniff.html"; PasswordTool=$false },
    @{ Category="02-Networking"; Name="NetworkTrafficView"; DirectUrl="https://www.nirsoft.net/utils/networktrafficview-x64.zip"; OfficialPage="https://www.nirsoft.net/utils/network_traffic_view.html"; PasswordTool=$false },
    @{ Category="02-Networking"; Name="PingInfoView"; DirectUrl="https://www.nirsoft.net/utils/pinginfoview.zip"; OfficialPage="https://www.nirsoft.net/utils/multiple_ping_tool.html"; PasswordTool=$false },
    @{ Category="02-Networking"; Name="WakeMeOnLan"; DirectUrl="https://www.nirsoft.net/utils/wakemeonlan-x64.zip"; OfficialPage="https://www.nirsoft.net/utils/wake_on_lan.html"; PasswordTool=$false },
    @{ Category="02-Networking"; Name="MACAddressView"; DirectUrl="https://www.nirsoft.net/utils/macaddressview.zip"; OfficialPage="https://www.nirsoft.net/utils/mac_address_lookup.html"; PasswordTool=$false },
    @{ Category="02-Networking"; Name="AdapterWatch"; DirectUrl="https://www.nirsoft.net/utils/awatch.zip"; OfficialPage="https://www.nirsoft.net/utils/network_adapter_monitor.html"; PasswordTool=$false },

    # 03 Password/Security - NirSoft
    @{ Category="03-PasswordSecurity"; Name="WebBrowserPassView"; DirectUrl="https://www.nirsoft.net/toolsdownload/webbrowserpassview.zip"; OfficialPage="https://www.nirsoft.net/utils/web_browser_password.html"; PasswordTool=$true },
    @{ Category="03-PasswordSecurity"; Name="WirelessKeyView"; DirectUrl="https://www.nirsoft.net/toolsdownload/wirelesskeyview-x64.zip"; OfficialPage="https://www.nirsoft.net/utils/wireless_key.html"; PasswordTool=$true },
    @{ Category="03-PasswordSecurity"; Name="VaultPasswordView"; DirectUrl="https://www.nirsoft.net/toolsdownload/vaultpasswordview.zip"; OfficialPage="https://www.nirsoft.net/utils/vault_password_view.html"; PasswordTool=$true },
    @{ Category="03-PasswordSecurity"; Name="RouterPassView"; DirectUrl="https://www.nirsoft.net/toolsdownload/routerpassview.zip"; OfficialPage="https://www.nirsoft.net/utils/router_password_recovery.html"; PasswordTool=$true },
    @{ Category="03-PasswordSecurity"; Name="CredentialsFileView"; DirectUrl="https://www.nirsoft.net/toolsdownload/credentialsfileview-x64.zip"; OfficialPage="https://www.nirsoft.net/utils/credentials_file_view.html"; PasswordTool=$true },
    @{ Category="03-PasswordSecurity"; Name="EncryptedRegView"; DirectUrl="https://www.nirsoft.net/toolsdownload/encryptedregview-x64.zip"; OfficialPage="https://www.nirsoft.net/utils/encrypted_registry_view.html"; PasswordTool=$true },
    @{ Category="03-PasswordSecurity"; Name="RemoteDesktopPassView"; DirectUrl="https://www.nirsoft.net/toolsdownload/rdpv.zip"; OfficialPage="https://www.nirsoft.net/utils/remote_desktop_password.html"; PasswordTool=$true },

    # 04 Browser Internet
    @{ Category="04-BrowserInternet"; Name="BrowsingHistoryView"; DirectUrl="https://www.nirsoft.net/utils/browsinghistoryview-x64.zip"; OfficialPage="https://www.nirsoft.net/utils/browsing_history_view.html"; PasswordTool=$false },
    @{ Category="04-BrowserInternet"; Name="BrowserDownloadsView"; DirectUrl="https://www.nirsoft.net/utils/browserdownloadsview-x64.zip"; OfficialPage="https://www.nirsoft.net/utils/browserdownloadsview.html"; PasswordTool=$false },
    @{ Category="04-BrowserInternet"; Name="BrowserAddonsView"; DirectUrl="https://www.nirsoft.net/utils/browseraddonsview.zip"; OfficialPage="https://www.nirsoft.net/utils/web_browser_addons_view.html"; PasswordTool=$false },
    @{ Category="04-BrowserInternet"; Name="ChromeCacheView"; DirectUrl="https://www.nirsoft.net/utils/chromecacheview.zip"; OfficialPage="https://www.nirsoft.net/utils/chrome_cache_view.html"; PasswordTool=$false },
    @{ Category="04-BrowserInternet"; Name="MozillaCacheView"; DirectUrl="https://www.nirsoft.net/utils/mozillacacheview.zip"; OfficialPage="https://www.nirsoft.net/utils/mozilla_cache_viewer.html"; PasswordTool=$false },
    @{ Category="04-BrowserInternet"; Name="VideoCacheView"; DirectUrl="https://www.nirsoft.net/utils/videocacheview.zip"; OfficialPage="https://www.nirsoft.net/utils/video_cache_view.html"; PasswordTool=$false },

    # 05 Forensics
    @{ Category="05-ForensicsInvestigation"; Name="ExecutedProgramsList"; DirectUrl="https://www.nirsoft.net/utils/executedprogramslist.zip"; OfficialPage="https://www.nirsoft.net/utils/executed_programs_list.html"; PasswordTool=$false },
    @{ Category="05-ForensicsInvestigation"; Name="UserAssistView"; DirectUrl="https://www.nirsoft.net/utils/userassistview.zip"; OfficialPage="https://www.nirsoft.net/utils/userassist_view.html"; PasswordTool=$false },
    @{ Category="05-ForensicsInvestigation"; Name="RecentFilesView"; DirectUrl="https://www.nirsoft.net/utils/recentfilesview.zip"; OfficialPage="https://www.nirsoft.net/utils/recent_files_view.html"; PasswordTool=$false },
    @{ Category="05-ForensicsInvestigation"; Name="ShellBagsView"; DirectUrl="https://www.nirsoft.net/utils/shellbagsview.zip"; OfficialPage="https://www.nirsoft.net/utils/shell_bags_view.html"; PasswordTool=$false },
    @{ Category="05-ForensicsInvestigation"; Name="JumpListsView"; DirectUrl="https://www.nirsoft.net/utils/jumplistsview.zip"; OfficialPage="https://www.nirsoft.net/utils/jump_lists_view.html"; PasswordTool=$false },
    @{ Category="05-ForensicsInvestigation"; Name="RegistryChangesView"; DirectUrl="https://www.nirsoft.net/utils/registrychangesview-x64.zip"; OfficialPage="https://www.nirsoft.net/utils/registry_changes_view.html"; PasswordTool=$false },

    # 06 Disk Filesystem
    @{ Category="06-DiskFilesystem"; Name="SearchMyFiles"; DirectUrl="https://www.nirsoft.net/utils/searchmyfiles-x64.zip"; OfficialPage="https://www.nirsoft.net/utils/search_my_files.html"; PasswordTool=$false },
    @{ Category="06-DiskFilesystem"; Name="HashMyFiles"; DirectUrl="https://www.nirsoft.net/utils/hashmyfiles-x64.zip"; OfficialPage="https://www.nirsoft.net/utils/hash_my_files.html"; PasswordTool=$false },
    @{ Category="06-DiskFilesystem"; Name="DiskSmartView"; DirectUrl="https://www.nirsoft.net/utils/disksmartview-x64.zip"; OfficialPage="https://www.nirsoft.net/utils/disk_smart_view.html"; PasswordTool=$false },
    @{ Category="06-DiskFilesystem"; Name="FolderChangesView"; DirectUrl="https://www.nirsoft.net/utils/folderchangesview-x64.zip"; OfficialPage="https://www.nirsoft.net/utils/folder_changes_view.html"; PasswordTool=$false },
    @{ Category="06-DiskFilesystem"; Name="NTFSLinksView"; DirectUrl="https://www.nirsoft.net/utils/ntfslinksview.zip"; OfficialPage="https://www.nirsoft.net/utils/ntfs_links_view.html"; PasswordTool=$false },
    @{ Category="06-DiskFilesystem"; Name="AlternateStreamView"; DirectUrl="https://www.nirsoft.net/utils/alternatestreamview-x64.zip"; OfficialPage="https://www.nirsoft.net/utils/alternate_data_streams.html"; PasswordTool=$false },

    # 07 Registry
    @{ Category="07-RegistryTools"; Name="RegScanner"; DirectUrl="https://www.nirsoft.net/utils/regscanner-x64.zip"; OfficialPage="https://www.nirsoft.net/utils/regscanner.html"; PasswordTool=$false },
    @{ Category="07-RegistryTools"; Name="OfflineRegistryFinder"; DirectUrl="https://www.nirsoft.net/utils/offlineregistryfinder-x64.zip"; OfficialPage="https://www.nirsoft.net/utils/offline_registry_finder.html"; PasswordTool=$false },
    @{ Category="07-RegistryTools"; Name="RegDllView"; DirectUrl="https://www.nirsoft.net/utils/regdllview-x64.zip"; OfficialPage="https://www.nirsoft.net/utils/registered_dll_view.html"; PasswordTool=$false },

    # 08 WiFi Bluetooth
    @{ Category="08-WiFiBluetooth"; Name="BluetoothView"; DirectUrl="https://www.nirsoft.net/utils/bluetoothview.zip"; OfficialPage="https://www.nirsoft.net/utils/bluetooth_viewer.html"; PasswordTool=$false },
    @{ Category="08-WiFiBluetooth"; Name="BluetoothCL"; DirectUrl="https://www.nirsoft.net/utils/bluetoothcl.zip"; OfficialPage="https://www.nirsoft.net/utils/bluetooth_command_line_tools.html"; PasswordTool=$false },

    # 09 Command Line Automation
    @{ Category="09-CommandLineAutomation"; Name="NirCmd"; DirectUrl="https://www.nirsoft.net/utils/nircmd-x64.zip"; OfficialPage="https://www.nirsoft.net/utils/nircmd.html"; PasswordTool=$false },
    @{ Category="09-CommandLineAutomation"; Name="MultiMonitorTool"; DirectUrl="https://www.nirsoft.net/utils/multimonitortool-x64.zip"; OfficialPage="https://www.nirsoft.net/utils/multi_monitor_tool.html"; PasswordTool=$false },
    @{ Category="09-CommandLineAutomation"; Name="SoundVolumeView"; DirectUrl="https://www.nirsoft.net/utils/soundvolumeview-x64.zip"; OfficialPage="https://www.nirsoft.net/utils/sound_volume_view.html"; PasswordTool=$false },
    @{ Category="09-CommandLineAutomation"; Name="ControlMyMonitor"; DirectUrl="https://www.nirsoft.net/utils/controlmymonitor.zip"; OfficialPage="https://www.nirsoft.net/utils/control_my_monitor.html"; PasswordTool=$false },
    @{ Category="09-CommandLineAutomation"; Name="WakeMeOnStandBy"; DirectUrl="https://www.nirsoft.net/utils/wakemeonstandby.zip"; OfficialPage="https://www.nirsoft.net/utils/wake_on_stand_by.html"; PasswordTool=$false },

    # 10 Hardware/System Info
    @{ Category="10-SystemInfo-CPU-GPU-Hardware"; Name="CPU-Z"; DirectUrl="https://download.cpuid.com/cpu-z/cpu-z_2.15-en.zip"; OfficialPage="https://www.cpuid.com/softwares/cpu-z.html"; PasswordTool=$false },
    @{ Category="10-SystemInfo-CPU-GPU-Hardware"; Name="GPU-Z"; DirectUrl=""; OfficialPage="https://www.techpowerup.com/gpuz/"; PasswordTool=$false },
    @{ Category="10-SystemInfo-CPU-GPU-Hardware"; Name="HWiNFO64"; DirectUrl="https://www.hwinfo.com/files/hwi64.zip"; OfficialPage="https://www.hwinfo.com/download/"; PasswordTool=$false },
    @{ Category="10-SystemInfo-CPU-GPU-Hardware"; Name="HWMonitor"; DirectUrl="https://download.cpuid.com/hwmonitor/hwmonitor_1.55.zip"; OfficialPage="https://www.cpuid.com/softwares/hwmonitor.html"; PasswordTool=$false },
    @{ Category="10-SystemInfo-CPU-GPU-Hardware"; Name="LibreHardwareMonitor"; DirectUrl="https://github.com/LibreHardwareMonitor/LibreHardwareMonitor/releases/latest/download/LibreHardwareMonitor-net472.zip"; OfficialPage="https://github.com/LibreHardwareMonitor/LibreHardwareMonitor"; PasswordTool=$false },
    @{ Category="10-SystemInfo-CPU-GPU-Hardware"; Name="OpenHardwareMonitor"; DirectUrl="https://openhardwaremonitor.org/files/openhardwaremonitor-v0.9.6.zip"; OfficialPage="https://openhardwaremonitor.org/"; PasswordTool=$false },
    @{ Category="10-SystemInfo-CPU-GPU-Hardware"; Name="Speccy Portable"; DirectUrl=""; OfficialPage="https://www.ccleaner.com/speccy/download/portable"; PasswordTool=$false },

    # 11 Fan Control Thermal
    @{ Category="11-FanControl-Thermal"; Name="Fan Control"; DirectUrl="https://github.com/Rem0o/FanControl.Releases/releases/latest/download/FanControl.zip"; OfficialPage="https://getfancontrol.com/"; PasswordTool=$false },
    @{ Category="11-FanControl-Thermal"; Name="OpenHardwareMonitor"; DirectUrl="https://openhardwaremonitor.org/files/openhardwaremonitor-v0.9.6.zip"; OfficialPage="https://openhardwaremonitor.org/"; PasswordTool=$false },
    @{ Category="11-FanControl-Thermal"; Name="SpeedFan"; DirectUrl=""; OfficialPage="http://www.almico.com/speedfan.php"; PasswordTool=$false },
    @{ Category="11-FanControl-Thermal"; Name="MSI Afterburner"; DirectUrl=""; OfficialPage="https://www.msi.com/Landing/afterburner/graphics-cards"; PasswordTool=$false },
    @{ Category="11-FanControl-Thermal"; Name="Argus Monitor"; DirectUrl=""; OfficialPage="https://www.argusmonitor.com/"; PasswordTool=$false },

    # 12 Disk Repair Recovery
    @{ Category="12-DiskRepair-Recovery"; Name="CrystalDiskInfo"; DirectUrl="https://sourceforge.net/projects/crystaldiskinfo/files/latest/download"; OfficialPage="https://crystalmark.info/en/software/crystaldiskinfo/"; PasswordTool=$false },
    @{ Category="12-DiskRepair-Recovery"; Name="CrystalDiskMark"; DirectUrl="https://sourceforge.net/projects/crystaldiskmark/files/latest/download"; OfficialPage="https://crystalmark.info/en/software/crystaldiskmark/"; PasswordTool=$false },
    @{ Category="12-DiskRepair-Recovery"; Name="smartmontools"; DirectUrl="https://sourceforge.net/projects/smartmontools/files/latest/download"; OfficialPage="https://www.smartmontools.org/"; PasswordTool=$false },
    @{ Category="12-DiskRepair-Recovery"; Name="GSmartControl"; DirectUrl="https://sourceforge.net/projects/gsmartcontrol/files/latest/download"; OfficialPage="https://gsmartcontrol.shaduri.dev/"; PasswordTool=$false },
    @{ Category="12-DiskRepair-Recovery"; Name="TestDisk PhotoRec"; DirectUrl="https://www.cgsecurity.org/testdisk-7.2.win.zip"; OfficialPage="https://www.cgsecurity.org/wiki/TestDisk_Download"; PasswordTool=$false },
    @{ Category="12-DiskRepair-Recovery"; Name="Victoria HDD"; DirectUrl=""; OfficialPage="https://hdd.by/victoria/"; PasswordTool=$false },
    @{ Category="12-DiskRepair-Recovery"; Name="HDDScan"; DirectUrl=""; OfficialPage="https://hddscan.com/"; PasswordTool=$false },
    @{ Category="12-DiskRepair-Recovery"; Name="Recuva Portable"; DirectUrl=""; OfficialPage="https://www.ccleaner.com/recuva/download/portable"; PasswordTool=$false },

    # 13 Stress Testing Benchmarks
    @{ Category="13-StressTesting-Benchmarks"; Name="Prime95"; DirectUrl="https://www.mersenne.org/ftp_root/gimps/p95v308b20.win64.zip"; OfficialPage="https://www.mersenne.org/download/"; PasswordTool=$false },
    @{ Category="13-StressTesting-Benchmarks"; Name="HeavyLoad"; DirectUrl="https://www.jam-software.com/heavyload/HeavyLoad.zip"; OfficialPage="https://www.jam-software.com/heavyload"; PasswordTool=$false },
    @{ Category="13-StressTesting-Benchmarks"; Name="OCCT"; DirectUrl=""; OfficialPage="https://www.ocbase.com/"; PasswordTool=$false },
    @{ Category="13-StressTesting-Benchmarks"; Name="FurMark 2"; DirectUrl=""; OfficialPage="https://geeks3d.com/furmark/"; PasswordTool=$false },
    @{ Category="13-StressTesting-Benchmarks"; Name="MemTest86"; DirectUrl=""; OfficialPage="https://www.memtest86.com/download.htm"; PasswordTool=$false },
    @{ Category="13-StressTesting-Benchmarks"; Name="Cinebench"; DirectUrl=""; OfficialPage="https://www.maxon.net/en/downloads/cinebench-downloads"; PasswordTool=$false },

    # 14 Windows Repair
    @{ Category="14-WindowsRepair"; Name="DISMTools"; DirectUrl="https://github.com/CodingWonders/DISMTools/releases/latest/download/DISMTools.zip"; OfficialPage="https://github.com/CodingWonders/DISMTools"; PasswordTool=$false },
    @{ Category="14-WindowsRepair"; Name="DriverStore Explorer"; DirectUrl="https://github.com/lostindark/DriverStoreExplorer/releases/latest/download/DriverStoreExplorer.v0.11.92.zip"; OfficialPage="https://github.com/lostindark/DriverStoreExplorer"; PasswordTool=$false },
    @{ Category="14-WindowsRepair"; Name="BleachBit Portable"; DirectUrl="https://download.bleachbit.org/BleachBit-4.6.2-portable.zip"; OfficialPage="https://www.bleachbit.org/download/windows"; PasswordTool=$false },
    @{ Category="14-WindowsRepair"; Name="Autoruns"; DirectUrl="https://download.sysinternals.com/files/Autoruns.zip"; OfficialPage="https://learn.microsoft.com/en-us/sysinternals/downloads/autoruns"; PasswordTool=$false },
    @{ Category="14-WindowsRepair"; Name="Tweaking Windows Repair"; DirectUrl=""; OfficialPage="https://www.tweaking.com/content/page/windows_repair_all_in_one.html"; PasswordTool=$false },
    @{ Category="14-WindowsRepair"; Name="FixWin 11"; DirectUrl=""; OfficialPage="https://www.thewindowsclub.com/fixwin-for-windows-10"; PasswordTool=$false },
    @{ Category="14-WindowsRepair"; Name="SFCFix"; DirectUrl=""; OfficialPage="https://www.sysnative.com/forums/downloads/sfcfix/"; PasswordTool=$false },
    @{ Category="14-WindowsRepair"; Name="Snappy Driver Installer Origin"; DirectUrl=""; OfficialPage="https://www.snappy-driver-installer.org/"; PasswordTool=$false },

    # 15 Sysinternals
    @{ Category="15-Sysinternals"; Name="Sysinternals Suite"; DirectUrl="https://download.sysinternals.com/files/SysinternalsSuite.zip"; OfficialPage="https://learn.microsoft.com/en-us/sysinternals/downloads/sysinternals-suite"; PasswordTool=$false },
    @{ Category="15-Sysinternals"; Name="Process Explorer"; DirectUrl="https://download.sysinternals.com/files/ProcessExplorer.zip"; OfficialPage="https://learn.microsoft.com/en-us/sysinternals/downloads/process-explorer"; PasswordTool=$false },
    @{ Category="15-Sysinternals"; Name="Autoruns"; DirectUrl="https://download.sysinternals.com/files/Autoruns.zip"; OfficialPage="https://learn.microsoft.com/en-us/sysinternals/downloads/autoruns"; PasswordTool=$false },
    @{ Category="15-Sysinternals"; Name="TCPView"; DirectUrl="https://download.sysinternals.com/files/TCPView.zip"; OfficialPage="https://learn.microsoft.com/en-us/sysinternals/downloads/tcpview"; PasswordTool=$false },
    @{ Category="15-Sysinternals"; Name="Process Monitor"; DirectUrl="https://download.sysinternals.com/files/ProcessMonitor.zip"; OfficialPage="https://learn.microsoft.com/en-us/sysinternals/downloads/procmon"; PasswordTool=$false },
    @{ Category="15-Sysinternals"; Name="PsExec/PsTools"; DirectUrl="https://download.sysinternals.com/files/PSTools.zip"; OfficialPage="https://learn.microsoft.com/en-us/sysinternals/downloads/psexec"; PasswordTool=$false },
    @{ Category="15-Sysinternals"; Name="RAMMap"; DirectUrl="https://download.sysinternals.com/files/RAMMap.zip"; OfficialPage="https://learn.microsoft.com/en-us/sysinternals/downloads/rammap"; PasswordTool=$false },
    @{ Category="15-Sysinternals"; Name="Disk2vhd"; DirectUrl="https://download.sysinternals.com/files/Disk2vhd.zip"; OfficialPage="https://learn.microsoft.com/en-us/sysinternals/downloads/disk2vhd"; PasswordTool=$false },

    # 16 Malware cleanup
    @{ Category="16-MalwareSecurityCleanup"; Name="AdwCleaner"; DirectUrl="https://downloads.malwarebytes.com/file/adwcleaner"; OfficialPage="https://www.malwarebytes.com/adwcleaner"; PasswordTool=$false },
    @{ Category="16-MalwareSecurityCleanup"; Name="ESET Online Scanner"; DirectUrl="https://download.eset.com/com/eset/tools/online_scanner/latest/esetonlinescanner.exe"; OfficialPage="https://www.eset.com/int/home/online-scanner/"; PasswordTool=$false },
    @{ Category="16-MalwareSecurityCleanup"; Name="Emsisoft Emergency Kit"; DirectUrl="https://dl.emsisoft.com/EmsisoftEmergencyKit.exe"; OfficialPage="https://www.emsisoft.com/en/home/emergencykit/"; PasswordTool=$false },
    @{ Category="16-MalwareSecurityCleanup"; Name="Kaspersky Virus Removal Tool"; DirectUrl="https://devbuilds.s.kaspersky-labs.com/devbuilds/KVRT/latest/full/KVRT.exe"; OfficialPage="https://www.kaspersky.com/downloads/free-virus-removal-tool"; PasswordTool=$false },
    @{ Category="16-MalwareSecurityCleanup"; Name="Sophos Scan and Clean"; DirectUrl=""; OfficialPage="https://www.sophos.com/en-us/free-tools/virus-removal-tool"; PasswordTool=$false },

    # 17 Network Forensics
    @{ Category="17-NetworkForensics"; Name="Nmap Portable"; DirectUrl="https://nmap.org/dist/nmap-7.95-win32.zip"; OfficialPage="https://nmap.org/download.html"; PasswordTool=$false },
    @{ Category="17-NetworkForensics"; Name="Advanced IP Scanner"; DirectUrl="https://download.advanced-ip-scanner.com/download/files/Advanced_IP_Scanner_2.5.4594.1.exe"; OfficialPage="https://www.advanced-ip-scanner.com/"; PasswordTool=$false },
    @{ Category="17-NetworkForensics"; Name="Angry IP Scanner"; DirectUrl="https://github.com/angryip/ipscan/releases/download/3.9.1/ipscan-win64-3.9.1.exe"; OfficialPage="https://angryip.org/"; PasswordTool=$false },
    @{ Category="17-NetworkForensics"; Name="TCPView"; DirectUrl="https://download.sysinternals.com/files/TCPView.zip"; OfficialPage="https://learn.microsoft.com/en-us/sysinternals/downloads/tcpview"; PasswordTool=$false },
    @{ Category="17-NetworkForensics"; Name="Wireshark"; DirectUrl=""; OfficialPage="https://www.wireshark.org/download.html"; PasswordTool=$false },
    @{ Category="17-NetworkForensics"; Name="Velociraptor"; DirectUrl=""; OfficialPage="https://docs.velociraptor.app/downloads/"; PasswordTool=$false }
)

$Report = New-Object System.Collections.Generic.List[object]

foreach ($tool in $Tools) {
    if ($tool.PasswordTool -and -not $IncludePasswordTools) {
        $Report.Add([pscustomobject]@{
            Category=$tool.Category; Tool=$tool.Name; Status="Skipped"; Detail="Password/security tool skipped. Re-run with -IncludePasswordTools."; OfficialPage=$tool.OfficialPage; DownloadUrl=$tool.DirectUrl; File=""
        })
        continue
    }

    $categoryPath = Join-Path $RootPath $tool.Category
    New-SafeDirectory $categoryPath

    if ([string]::IsNullOrWhiteSpace($tool.DirectUrl)) {
        $noteFile = Join-Path $categoryPath ((Get-SafeFileName $tool.Name) + " - Official Download Page.url")
        "[InternetShortcut]`r`nURL=$($tool.OfficialPage)" | Set-Content -Path $noteFile -Encoding ASCII
        $Report.Add([pscustomobject]@{
            Category=$tool.Category; Tool=$tool.Name; Status="Manual"; Detail="No stable direct link added. Official page shortcut created."; OfficialPage=$tool.OfficialPage; DownloadUrl=""; File=$noteFile
        })
        continue
    }

    $uri = [Uri]$tool.DirectUrl
    $fileName = Split-Path $uri.AbsolutePath -Leaf
    if ([string]::IsNullOrWhiteSpace($fileName) -or $fileName -eq "download") {
        $fileName = (Get-SafeFileName $tool.Name) + ".download"
    }
    $dest = Join-Path $categoryPath $fileName
    $result = Invoke-DownloadFile -Url $tool.DirectUrl -Destination $dest -OfficialPage $tool.OfficialPage

    $extractStatus = ""
    if ($result.Success) {
        $extractStatus = Expand-DownloadedArchive -FilePath $dest -DestinationFolder $categoryPath
        $status = "Downloaded"
    } else {
        $status = "Failed"
        $shortcut = Join-Path $categoryPath ((Get-SafeFileName $tool.Name) + " - Official Download Page.url")
        "[InternetShortcut]`r`nURL=$($tool.OfficialPage)" | Set-Content -Path $shortcut -Encoding ASCII
    }

    $Report.Add([pscustomobject]@{
        Category=$tool.Category
        Tool=$tool.Name
        Status=$status
        Detail=($result.Message + $(if ($extractStatus) { " | $extractStatus" } else { "" }))
        OfficialPage=$tool.OfficialPage
        DownloadUrl=$tool.DirectUrl
        File=$dest
    })
}

$Report | Export-Csv -Path $ReportPath -NoTypeInformation -Encoding UTF8

Write-Host ""
Write-Host "PC Plus 360 toolkit download completed." -ForegroundColor Green
Write-Host "Root folder: $RootPath" -ForegroundColor Green
Write-Host "Report: $ReportPath" -ForegroundColor Green
Write-Host ""

# Per-category summary
Write-Host "=== CATEGORY SUMMARY ===" -ForegroundColor Cyan
$downloaded = ($Report | Where-Object { $_.Status -eq "Downloaded" }).Count
$manual     = ($Report | Where-Object { $_.Status -eq "Manual" }).Count
$failed     = ($Report | Where-Object { $_.Status -eq "Failed" }).Count
$skipped    = ($Report | Where-Object { $_.Status -eq "Skipped" }).Count
Write-Host "  Downloaded: $downloaded | Manual: $manual | Failed: $failed | Skipped (password): $skipped" -ForegroundColor White
Write-Host ""

foreach ($cat in $Categories) {
    $catTools = $Report | Where-Object { $_.Category -eq $cat.Name }
    $catDownloaded = ($catTools | Where-Object { $_.Status -eq "Downloaded" }).Count
    $catManual = ($catTools | Where-Object { $_.Status -eq "Manual" }).Count
    $catFailed = ($catTools | Where-Object { $_.Status -eq "Failed" }).Count
    $catTotal = $catTools.Count

    $catPath = Join-Path $RootPath $cat.Name
    $exeCount = 0
    if (Test-Path $catPath) {
        $exeCount = (Get-ChildItem -Path $catPath -Filter "*.exe" -Recurse -ErrorAction SilentlyContinue).Count
    }

    $color = if ($exeCount -gt 0) { "Green" } elseif ($catManual -gt 0) { "Yellow" } else { "Red" }
    $padName = $cat.Name.PadRight(38)
    Write-Host "  $padName" -ForegroundColor White -NoNewline
    Write-Host "$exeCount exe(s)" -ForegroundColor $color -NoNewline
    if ($catManual -gt 0) { Write-Host " | $catManual manual" -ForegroundColor Yellow -NoNewline }
    if ($catFailed -gt 0) { Write-Host " | $catFailed failed" -ForegroundColor Red -NoNewline }
    Write-Host ""
}

Write-Host ""
if ($manual -gt 0) {
    Write-Host "Manual downloads needed: check .url shortcut files in each category folder." -ForegroundColor Yellow
}
Write-Host "To include NirSoft password recovery tools, run again with: -IncludePasswordTools" -ForegroundColor Yellow
Write-Host ""
Write-Host "PC Plus Computing | 604-760-1662 | 236-500-2700 | pcpluscomputing.com" -ForegroundColor Cyan

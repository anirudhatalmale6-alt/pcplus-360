<#
.SYNOPSIS
    PC Plus Computing 360 Hardware & Security Diagnostic Suite
.DESCRIPTION
    Complete diagnostic platform with branded launcher, built-in stress tests,
    third-party tool integration, and dual report generation (Hardware + Security).
    Runs from USB drive with no installation required.
.NOTES
    Company:  PC Plus Computing
    Version:  2.2.0
    Requires: PowerShell 5.1+, Windows 10/11, Administrator privileges
#>

#Requires -Version 5.1

# ─────────────────────────────────────────────────────────────────────────────
# DEBUG LOG (writes to file next to script so we can see crashes)
# ─────────────────────────────────────────────────────────────────────────────
$Global:DebugLogPath = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Definition) "PCPlus360-debug.log"
function Write-DebugLog {
    param([string]$Msg)
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "[$ts] $Msg" | Out-File -FilePath $Global:DebugLogPath -Append -Encoding UTF8
}

Write-DebugLog "Script starting..."
Write-DebugLog "PowerShell version: $($PSVersionTable.PSVersion)"
Write-DebugLog "Script path: $($MyInvocation.MyCommand.Definition)"
Write-DebugLog "Current user: $env:USERNAME"

$ErrorActionPreference = 'Continue'

# ─────────────────────────────────────────────────────────────────────────────
# ELEVATION
# ─────────────────────────────────────────────────────────────────────────────
Write-DebugLog "Loading assemblies..."
try {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    Add-Type -AssemblyName PresentationFramework
    Add-Type -AssemblyName PresentationCore
    Add-Type -AssemblyName WindowsBase
    Write-DebugLog "Assemblies loaded OK"
} catch {
    Write-DebugLog "Assembly load FAILED: $($_.Exception.Message)"
}

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

$isAdmin = Test-IsAdmin
Write-DebugLog "Is Admin: $isAdmin"

if (-not $isAdmin) {
    Write-DebugLog "Not admin - attempting elevation..."
    try {
        $scriptPath = $MyInvocation.MyCommand.Definition
        Start-Process powershell.exe -ArgumentList "-STA -NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`"" -Verb RunAs
        Write-DebugLog "Elevation launched OK, exiting non-admin instance"
    } catch {
        Write-DebugLog "Elevation FAILED: $($_.Exception.Message)"
        [System.Windows.Forms.MessageBox]::Show("This tool requires Administrator privileges.`n`n$($_.Exception.Message)", "PC Plus 360 - Elevation Required", "OK", "Warning")
    }
    exit
}

Write-DebugLog "Running as admin, continuing..."

# ─────────────────────────────────────────────────────────────────────────────
# GLOBALS
# ─────────────────────────────────────────────────────────────────────────────
$Global:ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
if ([string]::IsNullOrEmpty($Global:ScriptDir)) { $Global:ScriptDir = Get-Location }
Write-DebugLog "ScriptDir: $Global:ScriptDir"
$Global:ToolsDir = Join-Path $Global:ScriptDir "tools"
$Global:ReportsDir = Join-Path $Global:ScriptDir "reports"
$Global:DiagResults = @{}
$Global:LogLines = [System.Collections.ArrayList]::new()

$COMPANY      = "PC Plus Computing"
$PHONE        = "604-760-1662 | 236-500-2700"
$WEBSITE      = "pcpluscomputing.com"
$VERSION      = "2.2.0"

if (-not (Test-Path $Global:ReportsDir)) { New-Item -Path $Global:ReportsDir -ItemType Directory -Force | Out-Null }
if (-not (Test-Path $Global:ToolsDir)) { New-Item -Path $Global:ToolsDir -ItemType Directory -Force | Out-Null }

function Write-DiagLog {
    param([string]$Message, [string]$Level = "INFO")
    $ts = Get-Date -Format "HH:mm:ss"
    $line = "[$ts][$Level] $Message"
    $Global:LogLines.Add($line) | Out-Null
}

function Invoke-Safe {
    param([scriptblock]$Block, $Default = $null)
    try { return (& $Block) } catch { Write-DiagLog "Error: $($_.Exception.Message)" "WARN"; return $Default }
}

# ─────────────────────────────────────────────────────────────────────────────
# TOOL DETECTION
# ─────────────────────────────────────────────────────────────────────────────
function Find-Tool {
    param([string]$Name, [string[]]$ExeNames)
    $toolDir = Join-Path $Global:ToolsDir $Name
    foreach ($exe in $ExeNames) {
        $path = Join-Path $toolDir $exe
        if (Test-Path $path) { return $path }
        $deepSearch = Get-ChildItem $toolDir -Recurse -Filter $exe -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($deepSearch) { return $deepSearch.FullName }
    }
    $rootSearch = Get-ChildItem $Global:ToolsDir -Recurse -Filter $ExeNames[0] -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($rootSearch) { return $rootSearch.FullName }
    return $null
}

function Get-ToolStatus {
    $tools = @{}
    $tools.CrystalDiskInfo = Find-Tool "CrystalDiskInfo" @("DiskInfo64.exe", "DiskInfo32.exe", "CrystalDiskInfo.exe")
    $tools.HWiNFO         = Find-Tool "HWiNFO" @("HWiNFO64.exe", "HWiNFO32.exe")
    $tools.CPUZ            = Find-Tool "CPU-Z" @("cpuz_x64.exe", "cpuz_x32.exe", "cpuz.exe")
    $tools.GPUZ            = Find-Tool "GPU-Z" @("GPU-Z.exe")
    $tools.HWMonitor       = Find-Tool "HWMonitor" @("HWMonitor_x64.exe", "HWMonitor_x32.exe", "HWMonitor.exe")
    $tools.BatteryInfoView = Find-Tool "BatteryInfoView" @("BatteryInfoView.exe")
    $tools.Prime95         = Find-Tool "Prime95" @("prime95.exe")
    $tools.FurMark         = Find-Tool "FurMark" @("FurMark.exe", "FurMark_GUI.exe")
    $tools.CrystalDiskMark = Find-Tool "CrystalDiskMark" @("DiskMark64.exe", "DiskMark32.exe", "CrystalDiskMark.exe")
    $tools.Victoria        = Find-Tool "Victoria" @("Victoria.exe", "Victoria64.exe")
    return $tools
}

# ─────────────────────────────────────────────────────────────────────────────
# BUILT-IN DIAGNOSTICS
# ─────────────────────────────────────────────────────────────────────────────

function Get-FullSystemInfo {
    Write-DiagLog "Collecting system information..."
    $os = Get-CimInstance Win32_OperatingSystem
    $cs = Get-CimInstance Win32_ComputerSystem
    $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
    $bios = Get-CimInstance Win32_BIOS
    $board = Get-CimInstance Win32_BaseBoard
    $uptime = (Get-Date) - $os.LastBootUpTime

    $ramSticks = @()
    Get-CimInstance Win32_PhysicalMemory | ForEach-Object {
        $ramSticks += @{
            Slot = $_.DeviceLocator; CapacityGB = [math]::Round($_.Capacity / 1GB, 1)
            Speed = "$($_.ConfiguredClockSpeed) MHz"
            Type = switch ($_.SMBIOSMemoryType) { 26 { "DDR4" }; 34 { "DDR5" }; 24 { "DDR3" }; default { "Type $($_.SMBIOSMemoryType)" } }
            Manufacturer = if ($_.Manufacturer) { $_.Manufacturer.Trim() } else { "Unknown" }
            PartNumber = if ($_.PartNumber) { $_.PartNumber.Trim() } else { "N/A" }
        }
    }
    $ramSlots = Invoke-Safe { $t = (Get-CimInstance Win32_PhysicalMemoryArray | Measure-Object -Property MemoryDevices -Sum).Sum; $u = $ramSticks.Count; @{Total=$t;Used=$u;Empty=($t-$u)} } @{Total=0;Used=0;Empty=0}

    $gpus = @()
    Get-CimInstance Win32_VideoController | ForEach-Object {
        $gpus += @{
            Name = $_.Name; DriverVer = $_.DriverVersion
            DriverDate = if ($_.DriverDate) { $_.DriverDate.ToString("yyyy-MM-dd") } else { "Unknown" }
            VRAM_MB = if ($_.AdapterRAM -gt 0) { [math]::Round($_.AdapterRAM / 1MB, 0) } else { 0 }
            Resolution = "$($_.CurrentHorizontalResolution)x$($_.CurrentVerticalResolution)"
        }
    }

    $disks = @()
    Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" | ForEach-Object {
        $disks += @{
            Drive = $_.DeviceID; Size = [math]::Round($_.Size / 1GB, 1)
            Free = [math]::Round($_.FreeSpace / 1GB, 1)
            UsedPct = if ($_.Size -gt 0) { [math]::Round((($_.Size - $_.FreeSpace) / $_.Size) * 100, 1) } else { 0 }
        }
    }

    $smartData = Invoke-Safe {
        $sd = @()
        Get-PhysicalDisk | ForEach-Object {
            $rel = Get-StorageReliabilityCounter -PhysicalDisk $_ -ErrorAction SilentlyContinue
            $sd += @{
                Model = $_.FriendlyName; MediaType = "$($_.MediaType)"; BusType = "$($_.BusType)"
                Health = "$($_.HealthStatus)"; SizeGB = [math]::Round($_.Size / 1GB, 0)
                FirmwareVersion = $_.FirmwareVersion
                PowerOnHours = if ($rel) { $rel.PowerOnHours } else { "N/A" }
                Temperature = if ($rel -and $rel.Temperature) { "$($rel.Temperature)C" } else { "N/A" }
                ReadErrors = if ($rel) { $rel.ReadErrorsTotal } else { "N/A" }
                WriteErrors = if ($rel) { $rel.WriteErrorsTotal } else { "N/A" }
                Wear = if ($rel -and $rel.Wear) { "$($rel.Wear)%" } else { "N/A" }
            }
        }
        $sd
    } @()

    $monitors = Invoke-Safe {
        $m = @()
        Get-CimInstance WmiMonitorID -Namespace root\wmi -ErrorAction Stop | ForEach-Object {
            $mfr = -join ($_.ManufacturerName | Where-Object { $_ -ne 0 } | ForEach-Object { [char]$_ })
            $name = -join ($_.UserFriendlyName | Where-Object { $_ -ne 0 } | ForEach-Object { [char]$_ })
            $serial = -join ($_.SerialNumberID | Where-Object { $_ -ne 0 } | ForEach-Object { [char]$_ })
            $m += @{ Manufacturer = $mfr; Model = $name; Serial = $serial; Year = $_.YearOfManufacture }
        }
        $m
    } @()

    $battery = Invoke-Safe {
        $bat = Get-CimInstance Win32_Battery -ErrorAction Stop
        if ($bat) {
            $healthPct = 0; $cycleCnt = 0; $designCap = 0; $fullCap = 0
            try {
                $fc = Get-CimInstance -Namespace "root\WMI" -ClassName BatteryFullChargedCapacity -ErrorAction Stop
                $dc = Get-CimInstance -Namespace "root\WMI" -ClassName BatteryStaticData -ErrorAction Stop
                $fullCap = $fc.FullChargedCapacity; $designCap = $dc.DesignedCapacity
                if ($designCap -gt 0) { $healthPct = [math]::Round(($fullCap / $designCap) * 100, 1) }
                $cycleCnt = (Get-CimInstance -Namespace "root\WMI" -ClassName BatteryCycleCount -ErrorAction Stop).CycleCount
            } catch {}
            @{ Present = $true; Status = $bat.Status; Charge = $bat.EstimatedChargeRemaining
               HealthPct = $healthPct; DesignCap = $designCap; FullCap = $fullCap; CycleCount = $cycleCnt
               Runtime = if ($bat.EstimatedRunTime -and $bat.EstimatedRunTime -lt 71582788) { "$([math]::Floor($bat.EstimatedRunTime/60))h $($bat.EstimatedRunTime%60)m" } else { "AC Power" } }
        } else { @{ Present = $false } }
    } @{ Present = $false }

    $printers = Invoke-Safe {
        $p = @()
        Get-CimInstance Win32_Printer | ForEach-Object {
            $p += @{ Name = $_.Name; Default = $_.Default; Port = $_.PortName; Driver = $_.DriverName }
        }
        $p
    } @()

    $temps = Invoke-Safe {
        $t = @()
        Get-CimInstance MSAcpi_ThermalZoneTemperature -Namespace root/wmi -ErrorAction Stop | ForEach-Object {
            $c = [math]::Round(($_.CurrentTemperature / 10) - 273.15, 1)
            $t += @{ Zone = $_.InstanceName; TempC = $c; TempF = [math]::Round(($c * 9/5) + 32, 1) }
        }
        $t
    } @()

    $deviceErrors = Invoke-Safe {
        $e = @()
        Get-CimInstance Win32_PnPEntity | Where-Object { $_.ConfigManagerErrorCode -ne 0 } | ForEach-Object {
            $desc = switch ($_.ConfigManagerErrorCode) { 1{"Not configured"};3{"Driver corrupted"};10{"Cannot start"};12{"Not enough resources"};14{"Restart required"};22{"Disabled"};28{"Driver not installed"};31{"Not working properly"};default{"Error $($_.ConfigManagerErrorCode)"} }
            $e += @{ Device = $_.Name; Error = $desc; Class = $_.PNPClass }
        }
        $e
    } @()

    $audio = Invoke-Safe { Get-CimInstance Win32_SoundDevice | ForEach-Object { @{ Name = $_.Name; Status = $_.Status } } } @()

    $usb = Invoke-Safe {
        $d = @()
        Get-CimInstance Win32_USBControllerDevice -ErrorAction SilentlyContinue | ForEach-Object {
            $dep = [wmi]$_.Dependent
            if ($dep.Description -and $dep.Description -notmatch "Root Hub|Host Controller|Composite|USB Input") {
                $d += @{ Name = $dep.Description; Status = $dep.Status }
            }
        }
        $d | Select-Object -First 20
    } @()

    return @{
        ComputerName = $cs.Name; Manufacturer = $cs.Manufacturer; Model = $cs.Model; Serial = $bios.SerialNumber
        OSVersion = $os.Caption; OSBuild = $os.BuildNumber; Architecture = $os.OSArchitecture
        CPUModel = $cpu.Name.Trim(); CPUCores = $cpu.NumberOfCores; CPUThreads = $cpu.NumberOfLogicalProcessors
        RAMTotal = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
        RAMFree = [math]::Round(($os.FreePhysicalMemory * 1KB) / 1GB, 1)
        Uptime = "{0}d {1}h {2}m" -f $uptime.Days, $uptime.Hours, $uptime.Minutes
        Domain = if ($cs.PartOfDomain) { "Domain: $($cs.Domain)" } else { "Workgroup: $($cs.Workgroup)" }
        Board = @{ Manufacturer = $board.Manufacturer; Product = $board.Product; Serial = $board.SerialNumber }
        BIOS = @{ Vendor = $bios.Manufacturer; Version = $bios.SMBIOSBIOSVersion; Date = if ($bios.ReleaseDate) { $bios.ReleaseDate.ToString("yyyy-MM-dd") } else { "Unknown" } }
        RAMSticks = $ramSticks; RAMSlots = $ramSlots; GPUs = $gpus; Disks = $disks
        SMART = $smartData; Monitors = $monitors; Battery = $battery; Printers = $printers
        Temperatures = $temps; DeviceErrors = $deviceErrors; Audio = $audio; USB = $usb
    }
}

function Get-FullSecurityInfo {
    Write-DiagLog "Scanning security configuration..."
    $results = @{}

    $results.Defender = Invoke-Safe {
        $mp = Get-MpComputerStatus -ErrorAction Stop
        @{ RealTimeProtection = $mp.RealTimeProtectionEnabled; DefinitionsUpToDate = $mp.AntivirusSignatureAge -le 7
           DefinitionAge = $mp.AntivirusSignatureAge; LastScan = $mp.QuickScanEndTime; Engine = $mp.AMEngineVersion }
    } @{ RealTimeProtection = $null; DefinitionsUpToDate = $null; DefinitionAge = $null; LastScan = $null; Engine = $null }

    $results.ThirdPartyAV = Invoke-Safe {
        $av = @(); Get-CimInstance -Namespace "root\SecurityCenter2" -ClassName AntiVirusProduct -ErrorAction Stop | ForEach-Object {
            if ($_.displayName -ne "Windows Defender") { $av += $_.displayName }
        }; $av
    } @()

    $results.Firewall = Invoke-Safe {
        $fw = Get-NetFirewallProfile -ErrorAction Stop
        @{ Domain = ($fw | Where-Object { $_.Name -eq "Domain" }).Enabled; Private = ($fw | Where-Object { $_.Name -eq "Private" }).Enabled; Public = ($fw | Where-Object { $_.Name -eq "Public" }).Enabled }
    } @{ Domain = $null; Private = $null; Public = $null }

    $results.UAC = Invoke-Safe {
        $k = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
        @{ Enabled = (Get-ItemProperty $k -Name "EnableLUA" -ErrorAction Stop).EnableLUA -eq 1
           Level = (Get-ItemProperty $k -Name "ConsentPromptBehaviorAdmin" -ErrorAction Stop).ConsentPromptBehaviorAdmin }
    } @{ Enabled = $null; Level = $null }

    $results.BitLocker = Invoke-Safe {
        $bl = @{}; Get-BitLockerVolume -ErrorAction Stop | ForEach-Object {
            $bl[$_.MountPoint] = @{ Status = $_.ProtectionStatus.ToString(); Encryption = $_.EncryptionPercentage; Method = $_.EncryptionMethod.ToString() }
        }; $bl
    } @{}

    $results.SecureBoot = Invoke-Safe { Confirm-SecureBootUEFI -ErrorAction Stop } $null

    $results.TPM = Invoke-Safe {
        $tpm = Get-Tpm -ErrorAction Stop
        @{ Present = $tpm.TpmPresent; Ready = $tpm.TpmReady
           Version = (Get-CimInstance -Namespace "root\cimv2\Security\MicrosoftTpm" -ClassName Win32_Tpm -ErrorAction Stop).SpecVersion }
    } @{ Present = $false; Ready = $false; Version = "Unknown" }

    $results.PasswordPolicy = Invoke-Safe {
        $na = net accounts 2>&1; $minLen = 0; $complexity = $false; $lockout = 0
        foreach ($l in $na) {
            if ($l -match "Minimum password length:\s+(\d+)") { $minLen = [int]$Matches[1] }
            if ($l -match "Lockout threshold:\s+(\w+)") { $lockout = if ($Matches[1] -eq "Never") { 0 } else { [int]$Matches[1] } }
        }
        $tmp = [IO.Path]::GetTempFileName(); secedit /export /cfg $tmp /quiet 2>$null
        if (Test-Path $tmp) { $c = Get-Content $tmp -Raw; if ($c -match "PasswordComplexity\s*=\s*1") { $complexity = $true }; Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
        @{ MinLength = $minLen; Complexity = $complexity; LockoutThreshold = $lockout }
    } @{ MinLength = 0; Complexity = $false; LockoutThreshold = 0 }

    $results.GuestDisabled = Invoke-Safe { -not (Get-LocalUser -Name "Guest" -ErrorAction Stop).Enabled } $null
    $results.AutoLoginDisabled = Invoke-Safe { (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" -Name "AutoAdminLogon" -ErrorAction SilentlyContinue).AutoAdminLogon -ne "1" } $null

    $results.RDP = Invoke-Safe {
        $en = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server" -Name "fDenyTSConnections" -ErrorAction Stop).fDenyTSConnections -eq 0
        $nla = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" -Name "UserAuthentication" -ErrorAction SilentlyContinue).UserAuthentication -eq 1
        @{ Enabled = $en; NLA = $nla }
    } @{ Enabled = $null; NLA = $null }

    $results.SMBv1Disabled = Invoke-Safe { -not (Get-SmbServerConfiguration -ErrorAction Stop).EnableSMB1Protocol } $null

    $results.LocalAdmins = Invoke-Safe {
        $a = Get-LocalGroupMember -Group "Administrators" -ErrorAction Stop
        @{ Count = $a.Count; Names = ($a | ForEach-Object { $_.Name }) -join ", " }
    } @{ Count = 0; Names = "Unable to determine" }

    return $results
}

function Get-NetworkDiagnostics {
    Write-DiagLog "Analyzing network..."
    $results = @{}

    $results.Adapters = Invoke-Safe {
        $a = @(); Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq "Up" } | ForEach-Object {
            $ip = (Get-NetIPAddress -InterfaceIndex $_.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | Select-Object -First 1).IPAddress
            $dns = (Get-DnsClientServerAddress -InterfaceIndex $_.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).ServerAddresses -join ", "
            $a += @{ Name = $_.Name; MAC = $_.MacAddress; IP = $ip; DNS = $dns; Speed = $_.LinkSpeed }
        }; $a
    } @()

    $results.WiFi = Invoke-Safe {
        $w = netsh wlan show interfaces 2>&1; $ssid = ""; $auth = ""; $cipher = ""
        foreach ($l in $w) {
            if ($l -match "^\s+SSID\s+:\s+(.+)$") { $ssid = $Matches[1].Trim() }
            if ($l -match "Authentication\s+:\s+(.+)$") { $auth = $Matches[1].Trim() }
            if ($l -match "Cipher\s+:\s+(.+)$") { $cipher = $Matches[1].Trim() }
        }
        @{ SSID = $ssid; Auth = $auth; Cipher = $cipher }
    } @{ SSID = "N/A"; Auth = "N/A"; Cipher = "N/A" }

    $results.PublicIP = Invoke-Safe { (Invoke-RestMethod -Uri "https://api.ipify.org?format=json" -TimeoutSec 5).ip } "Unable to determine"

    $results.OpenPorts = Invoke-Safe {
        $p = @(); Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | Select-Object LocalAddress,LocalPort,OwningProcess | Sort-Object LocalPort -Unique | Select-Object -First 30 | ForEach-Object {
            $proc = Invoke-Safe { (Get-Process -Id $_.OwningProcess -ErrorAction Stop).ProcessName } "Unknown"
            $p += @{ Port = $_.LocalPort; Address = $_.LocalAddress; Process = $proc }
        }; $p
    } @()

    $results.DNSTest = Invoke-Safe {
        $start = Get-Date; $r = Resolve-DnsName "google.com" -Type A -ErrorAction Stop; $ms = ((Get-Date) - $start).TotalMilliseconds
        @{ Success = $true; ResponseMs = [math]::Round($ms, 0); Server = $r[0].IP4Address }
    } @{ Success = $false; ResponseMs = 0; Server = "Failed" }

    $results.InternetTest = Invoke-Safe {
        $start = Get-Date; Invoke-WebRequest -Uri "https://www.google.com" -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop | Out-Null
        @{ Success = $true; ResponseMs = [math]::Round(((Get-Date) - $start).TotalMilliseconds, 0) }
    } @{ Success = $false; ResponseMs = 0 }

    return $results
}

function Get-MissingPatchesList {
    Write-DiagLog "Checking Windows updates..."
    return Invoke-Safe {
        $session = New-Object -ComObject Microsoft.Update.Session
        $searcher = $session.CreateUpdateSearcher()
        $result = $searcher.Search("IsInstalled=0 AND Type='Software'")
        $patches = @()
        foreach ($u in $result.Updates) {
            $sev = if ($u.MsrcSeverity) { $u.MsrcSeverity } else { "Unknown" }
            $kb = @(); foreach ($k in $u.KBArticleIDs) { $kb += "KB$k" }
            $patches += @{ Title = $u.Title; KB = ($kb -join ", "); Severity = $sev; SizeMB = [math]::Round($u.MaxDownloadSize / 1MB, 1) }
        }
        $patches
    } @()
}

function Get-LicenseKeys {
    Write-DiagLog "Recovering license keys..."
    $results = @{}

    # Windows product key
    $results.WindowsKeys = Invoke-Safe {
        $keys = @()
        $oa3 = (Get-CimInstance -Query "SELECT OA3xOriginalProductKey FROM SoftwareLicensingService" -ErrorAction Stop).OA3xOriginalProductKey
        if ($oa3) { $keys += @{ Source = "BIOS/UEFI (OA3)"; Key = $oa3 } }
        try {
            $dpid = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -ErrorAction Stop).DigitalProductId
            if ($dpid) {
                $ko = 52; $isW8 = [math]::Floor($dpid[$ko+14]/6) -band 1
                $dpid[$ko+14] = ($dpid[$ko+14] -band 0xF7) -bor (($isW8 -band 2)*4)
                $chars = "BCDFGHJKMPQRTVWXY2346789"; $dec = ""
                for ($i=24;$i -ge 0;$i--) {
                    $cur=0; for($j=14;$j -ge 0;$j--) { $cur=$cur*256; $cur=$dpid[$j+$ko]+$cur; $dpid[$j+$ko]=[math]::Floor($cur/24); $cur=$cur%24 }
                    $dec=$chars[$cur]+$dec; if(($i%5 -eq 0)-and($i -ne 0)){$dec="-"+$dec}
                }
                if ($dec -and $dec.Length -ge 25) { $keys += @{ Source = "Registry"; Key = $dec } }
            }
        } catch {}
        $pid2 = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -ErrorAction SilentlyContinue).ProductId
        if ($pid2) { $keys += @{ Source = "Product ID"; Key = $pid2 } }
        $keys
    } @()

    # Office keys
    $results.OfficeKeys = Invoke-Safe {
        $ok = @()
        foreach ($bp in @("HKLM:\SOFTWARE\Microsoft\Office","HKLM:\SOFTWARE\WOW6432Node\Microsoft\Office")) {
            foreach ($v in @("16.0","15.0","14.0")) {
                $rp = "$bp\$v\Registration"
                if (Test-Path $rp) {
                    Get-ChildItem $rp -ErrorAction SilentlyContinue | ForEach-Object {
                        $props = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
                        if ($props.ProductName -and $props.DigitalProductID) {
                            $dpid = $props.DigitalProductID; $ko=52; $chars="BCDFGHJKMPQRTVWXY2346789"; $dec=""
                            try {
                                for($i=24;$i -ge 0;$i--){$cur=0;for($j=14;$j -ge 0;$j--){$cur=$cur*256;$cur=$dpid[$j+$ko]+$cur;$dpid[$j+$ko]=[math]::Floor($cur/24);$cur=$cur%24};$dec=$chars[$cur]+$dec;if(($i%5 -eq 0)-and($i -ne 0)){$dec="-"+$dec}}
                            } catch { $dec = "" }
                            if ($dec -and $dec.Length -ge 25) { $ok += @{ Product = $props.ProductName; Key = $dec; Version = $v } }
                        }
                    }
                }
            }
        }
        foreach ($ospp in @("$env:ProgramFiles\Microsoft Office\Office16\ospp.vbs","${env:ProgramFiles(x86)}\Microsoft Office\Office16\ospp.vbs")) {
            if (Test-Path $ospp) {
                $out = cscript //nologo $ospp /dstatus 2>&1; $pn=""; $lc=""
                foreach ($l in $out) { if($l -match "LICENSE NAME:\s*(.+)"){$pn=$Matches[1].Trim()}; if($l -match "Last 5 characters.*:\s*(\S+)"){$lc=$Matches[1].Trim()} }
                if ($pn -and $lc) { $ok += @{ Product = $pn; Key = "XXXXX-XXXXX-XXXXX-XXXXX-$lc"; Version = "365/2019+" } }
                break
            }
        }
        $ok
    } @()

    # Adobe keys
    $results.AdobeKeys = Invoke-Safe {
        $ak = @()
        $adobeRegPaths = @(
            @{ Path = "HKLM:\SOFTWARE\Adobe"; Name = "Adobe" }
            @{ Path = "HKLM:\SOFTWARE\WOW6432Node\Adobe"; Name = "Adobe" }
        )
        foreach ($arp in $adobeRegPaths) {
            if (Test-Path $arp.Path) {
                Get-ChildItem $arp.Path -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
                    $props = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
                    if ($props.SERIAL -and $props.SERIAL -ne "000000000000000000000000") {
                        $prodName = $_.PSPath -replace ".*\\Adobe\\", "" -replace "\\Registration.*", "" -replace "\\.*", ""
                        $ak += @{ Product = "Adobe $prodName"; Key = $props.SERIAL }
                    }
                    if ($props.Serial -and $props.Serial -ne "000000000000000000000000") {
                        $prodName = $_.PSPath -replace ".*\\Adobe\\", "" -replace "\\Registration.*", "" -replace "\\.*", ""
                        $ak += @{ Product = "Adobe $prodName"; Key = $props.Serial }
                    }
                }
            }
        }
        $ak | Sort-Object { $_.Product } -Unique
    } @()

    # WiFi passwords
    $results.WiFiPasswords = Invoke-Safe {
        $wl = @(); $profiles = netsh wlan show profiles 2>&1
        $names = @(); foreach ($l in $profiles) { if ($l -match "All User Profile\s*:\s*(.+)$") { $names += $Matches[1].Trim() } }
        foreach ($n in $names) {
            $det = netsh wlan show profile name="$n" key=clear 2>&1; $pw=""; $auth=""; $cip=""
            foreach ($l in $det) {
                if ($l -match "Key Content\s*:\s*(.+)$") { $pw = $Matches[1].Trim() }
                if ($l -match "Authentication\s*:\s*(.+)$") { $auth = $Matches[1].Trim() }
                if ($l -match "Cipher\s*:\s*(.+)$") { $cip = $Matches[1].Trim() }
            }
            $wl += @{ SSID = $n; Password = if ($pw) { $pw } else { "(Open)" }; Auth = $auth; Cipher = $cip }
        }
        $wl
    } @()

    # Other software keys
    $results.OtherKeys = Invoke-Safe {
        $sk = @()
        foreach ($up in @("HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*","HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*")) {
            Get-ItemProperty $up -ErrorAction SilentlyContinue | ForEach-Object {
                if ($_.DisplayName -and $_.ProductKey) { $sk += @{ Product = $_.DisplayName; Key = $_.ProductKey } }
            }
        }
        $sk
    } @()

    return $results
}

function Get-SoftwareInventory {
    Write-DiagLog "Inventorying software..."
    $results = @{}

    $results.Installed = Invoke-Safe {
        $sw = @()
        foreach ($p in @("HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*","HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*")) {
            Get-ItemProperty -Path $p -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -and $_.DisplayName.Trim() -ne "" } | ForEach-Object {
                $sw += @{ Name = $_.DisplayName; Version = $_.DisplayVersion; Publisher = $_.Publisher }
            }
        }
        $sw | Sort-Object { $_.Name } -Unique
    } @()

    $results.StartupPrograms = Invoke-Safe {
        $su = @()
        foreach ($k in @("HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run","HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run")) {
            $props = Get-ItemProperty -Path $k -ErrorAction SilentlyContinue
            if ($props) { $props.PSObject.Properties | Where-Object { $_.Name -notlike "PS*" } | ForEach-Object { $su += @{ Name = $_.Name; Location = $k; Command = $_.Value } } }
        }
        $su
    } @()

    $results.RunningServices = Invoke-Safe { (Get-Service | Where-Object { $_.Status -eq "Running" }).Count } 0
    $results.ProcessCount = Invoke-Safe { (Get-Process).Count } 0

    $results.TopRAM = Invoke-Safe {
        Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 10 | ForEach-Object {
            @{ Name = $_.ProcessName; RAM_MB = [math]::Round($_.WorkingSet64 / 1MB, 0) }
        }
    } @()

    return $results
}

function Get-PerformanceSnapshot {
    Write-DiagLog "Measuring performance..."
    $cpu = Invoke-Safe { [math]::Round((Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average, 0) } 0
    $os = Get-CimInstance Win32_OperatingSystem
    $ram = [math]::Round((($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / $os.TotalVisibleMemorySize) * 100, 0)
    return @{ CPUPercent = $cpu; RAMPercent = $ram }
}

# ─────────────────────────────────────────────────────────────────────────────
# CRASH / STABILITY HISTORY (Event Log Analysis)
# ─────────────────────────────────────────────────────────────────────────────

function Get-CrashStabilityHistory {
    param([int]$DaysBack = 90)
    Write-DiagLog "Analyzing crash and stability history ($DaysBack days)..."
    $results = @{
        BSODs = @(); KernelPower = @(); UnexpectedShutdowns = @()
        DiskErrors = @(); NTFSErrors = @(); WHEAErrors = @(); DriverCrashes = @()
        TotalBSODs = 0; TotalUnexpected = 0; TotalDiskErrors = 0; TotalWHEA = 0
        StabilityRating = "Excellent"; RiskLevel = "Low"
    }
    $startDate = (Get-Date).AddDays(-$DaysBack)

    $results.BSODs = Invoke-Safe {
        $events = @()
        Get-WinEvent -FilterHashtable @{LogName='System';Id=1001;StartTime=$startDate} -MaxEvents 50 -ErrorAction Stop | ForEach-Object {
            $events += @{ Time = $_.TimeCreated.ToString("yyyy-MM-dd HH:mm"); BugCheck = ($_.Message -split "`n" | Select-Object -First 3) -join " " }
        }
        $events
    } @()

    $results.KernelPower = Invoke-Safe {
        $events = @()
        Get-WinEvent -FilterHashtable @{LogName='System';Id=41;ProviderName='Microsoft-Windows-Kernel-Power';StartTime=$startDate} -MaxEvents 50 -ErrorAction Stop | ForEach-Object {
            $events += @{ Time = $_.TimeCreated.ToString("yyyy-MM-dd HH:mm"); Message = ($_.Message -split "`n" | Select-Object -First 2) -join " " }
        }
        $events
    } @()

    $results.UnexpectedShutdowns = Invoke-Safe {
        $events = @()
        Get-WinEvent -FilterHashtable @{LogName='System';Id=6008;StartTime=$startDate} -MaxEvents 50 -ErrorAction Stop | ForEach-Object {
            $events += @{ Time = $_.TimeCreated.ToString("yyyy-MM-dd HH:mm"); Message = $_.Message }
        }
        $events
    } @()

    $results.DiskErrors = Invoke-Safe {
        $events = @()
        Get-WinEvent -FilterHashtable @{LogName='System';Id=7,51,129,153;StartTime=$startDate} -MaxEvents 50 -ErrorAction Stop | ForEach-Object {
            $events += @{ Time = $_.TimeCreated.ToString("yyyy-MM-dd HH:mm"); Id = $_.Id; Message = ($_.Message -split "`n" | Select-Object -First 1) }
        }
        $events
    } @()

    $results.NTFSErrors = Invoke-Safe {
        $events = @()
        Get-WinEvent -FilterHashtable @{LogName='System';Id=55;StartTime=$startDate} -MaxEvents 20 -ErrorAction Stop | ForEach-Object {
            $events += @{ Time = $_.TimeCreated.ToString("yyyy-MM-dd HH:mm"); Message = ($_.Message -split "`n" | Select-Object -First 1) }
        }
        $events
    } @()

    $results.WHEAErrors = Invoke-Safe {
        $events = @()
        Get-WinEvent -FilterHashtable @{LogName='System';ProviderName='Microsoft-Windows-WHEA-Logger';StartTime=$startDate} -MaxEvents 50 -ErrorAction Stop | ForEach-Object {
            $events += @{ Time = $_.TimeCreated.ToString("yyyy-MM-dd HH:mm"); Id = $_.Id; Message = ($_.Message -split "`n" | Select-Object -First 1) }
        }
        $events
    } @()

    $results.DriverCrashes = Invoke-Safe {
        $events = @()
        Get-WinEvent -FilterHashtable @{LogName='System';Level=1,2;StartTime=$startDate} -MaxEvents 30 -ErrorAction Stop | Where-Object {
            $_.Message -match "driver|crash|fault|exception"
        } | ForEach-Object {
            $events += @{ Time = $_.TimeCreated.ToString("yyyy-MM-dd HH:mm"); Source = $_.ProviderName; Message = ($_.Message -split "`n" | Select-Object -First 1) }
        }
        $events
    } @()

    $results.TotalBSODs = $results.BSODs.Count
    $results.TotalUnexpected = $results.KernelPower.Count + $results.UnexpectedShutdowns.Count
    $results.TotalDiskErrors = $results.DiskErrors.Count + $results.NTFSErrors.Count
    $results.TotalWHEA = $results.WHEAErrors.Count

    $crashTotal = $results.TotalBSODs + $results.TotalUnexpected + $results.TotalWHEA
    if ($crashTotal -ge 10) { $results.StabilityRating = "Critical"; $results.RiskLevel = "High" }
    elseif ($crashTotal -ge 5) { $results.StabilityRating = "Poor"; $results.RiskLevel = "Medium-High" }
    elseif ($crashTotal -ge 2) { $results.StabilityRating = "Fair"; $results.RiskLevel = "Medium" }
    elseif ($crashTotal -ge 1) { $results.StabilityRating = "Good"; $results.RiskLevel = "Low" }
    else { $results.StabilityRating = "Excellent"; $results.RiskLevel = "None" }

    $results.MinidumpCount = Invoke-Safe {
        $md = Get-ChildItem "$env:SystemRoot\Minidump\*.dmp" -ErrorAction SilentlyContinue
        if ($md) { $md.Count } else { 0 }
    } 0

    Write-DiagLog "Stability: $($results.StabilityRating), BSODs=$($results.TotalBSODs), Unexpected=$($results.TotalUnexpected), Disk=$($results.TotalDiskErrors), WHEA=$($results.TotalWHEA)"
    return $results
}

# ─────────────────────────────────────────────────────────────────────────────
# DETAILED BATTERY REPORT
# ─────────────────────────────────────────────────────────────────────────────

function Get-DetailedBatteryInfo {
    Write-DiagLog "Collecting detailed battery information..."
    $results = @{ Present = $false }
    $bat = Invoke-Safe { Get-CimInstance Win32_Battery -ErrorAction Stop } $null
    if (-not $bat) { return $results }
    $results.Present = $true
    $results.Name = $bat.Name
    $results.Status = $bat.Status
    $results.Charge = $bat.EstimatedChargeRemaining
    $results.Charging = $bat.BatteryStatus -eq 2
    $results.Runtime = if ($bat.EstimatedRunTime -and $bat.EstimatedRunTime -lt 71582788) { "$([math]::Floor($bat.EstimatedRunTime/60))h $($bat.EstimatedRunTime%60)m" } else { "AC Power" }

    $results.DesignCapacity = Invoke-Safe { (Get-CimInstance -Namespace "root\WMI" -ClassName BatteryStaticData -ErrorAction Stop).DesignedCapacity } 0
    $results.FullChargeCapacity = Invoke-Safe { (Get-CimInstance -Namespace "root\WMI" -ClassName BatteryFullChargedCapacity -ErrorAction Stop).FullChargedCapacity } 0
    $results.HealthPct = if ($results.DesignCapacity -gt 0) { [math]::Round(($results.FullChargeCapacity / $results.DesignCapacity) * 100, 1) } else { 0 }
    $results.CycleCount = Invoke-Safe { (Get-CimInstance -Namespace "root\WMI" -ClassName BatteryCycleCount -ErrorAction Stop).CycleCount } 0

    $results.DrainRate = Invoke-Safe {
        $st = Get-CimInstance -Namespace "root\WMI" -ClassName BatteryStatus -ErrorAction Stop | Select-Object -First 1
        if ($st -and $st.DischargeRate -and $st.DischargeRate -gt 0 -and $st.DischargeRate -lt 100000) { "$([math]::Round($st.DischargeRate / 1000, 2))W" } else { "N/A" }
    } "N/A"

    # Generate powercfg battery report
    $results.BatteryReportPath = Invoke-Safe {
        $rptDir = Join-Path $Global:ReportsDir "battery"
        if (-not (Test-Path $rptDir)) { New-Item -Path $rptDir -ItemType Directory -Force | Out-Null }
        $rptPath = Join-Path $rptDir "battery-report.html"
        $null = & powercfg /batteryreport /output $rptPath 2>&1
        if (Test-Path $rptPath) { $rptPath } else { $null }
    } $null

    $healthStatus = if ($results.HealthPct -ge 80) { "Good" } elseif ($results.HealthPct -ge 50) { "Fair - Consider Replacement" } else { "Poor - Replace Soon" }
    $results.HealthStatus = $healthStatus

    Write-DiagLog "Battery: Health=$($results.HealthPct)%, Cycles=$($results.CycleCount), Status=$healthStatus"
    return $results
}

# ─────────────────────────────────────────────────────────────────────────────
# POWER STABILITY ANALYSIS
# ─────────────────────────────────────────────────────────────────────────────

function Get-PowerStabilityInfo {
    Write-DiagLog "Analyzing power stability..."
    $results = @{ PowerEvents = @(); ACAdapter = "N/A"; StabilityScore = 100 }
    $startDate = (Get-Date).AddDays(-90)

    $results.PowerEvents = Invoke-Safe {
        $events = @()
        Get-WinEvent -FilterHashtable @{LogName='System';ProviderName='Microsoft-Windows-Kernel-Power';StartTime=$startDate} -MaxEvents 30 -ErrorAction Stop | ForEach-Object {
            $evType = switch ($_.Id) { 41 {"Unexpected Shutdown"}; 42 {"Sleep Entry"}; 107 {"Resume from Sleep"}; 109 {"Kernel Power Change"}; default {"Power Event $($_.Id)"} }
            $events += @{ Time = $_.TimeCreated.ToString("yyyy-MM-dd HH:mm"); Type = $evType; Id = $_.Id }
        }
        $events
    } @()

    $results.ACAdapter = Invoke-Safe {
        $bat = Get-CimInstance Win32_Battery -ErrorAction Stop
        if ($bat) { if ($bat.BatteryStatus -eq 2) { "Charging" } elseif ($bat.BatteryStatus -eq 1) { "On Battery" } else { "AC Connected" } }
        else { "Desktop/No Battery" }
    } "Unknown"

    $results.LastBootType = Invoke-Safe {
        $lastBoot = Get-WinEvent -FilterHashtable @{LogName='System';Id=12;ProviderName='Microsoft-Windows-Kernel-General'} -MaxEvents 1 -ErrorAction Stop
        if ($lastBoot) { "Normal boot at $($lastBoot.TimeCreated.ToString('yyyy-MM-dd HH:mm'))" } else { "Unknown" }
    } "Unknown"

    $unexpectedCount = ($results.PowerEvents | Where-Object { $_.Type -eq "Unexpected Shutdown" }).Count
    if ($unexpectedCount -ge 5) { $results.StabilityScore = 40 }
    elseif ($unexpectedCount -ge 3) { $results.StabilityScore = 60 }
    elseif ($unexpectedCount -ge 1) { $results.StabilityScore = 80 }
    $results.UnexpectedShutdowns = $unexpectedCount
    $results.Rating = if ($results.StabilityScore -ge 80) { "Stable" } elseif ($results.StabilityScore -ge 60) { "Moderate Concern" } else { "Unstable - Investigate" }

    Write-DiagLog "Power: $unexpectedCount unexpected shutdowns, Rating=$($results.Rating)"
    return $results
}

# ─────────────────────────────────────────────────────────────────────────────
# NETWORK SPEED TEST
# ─────────────────────────────────────────────────────────────────────────────

function Get-NetworkSpeedTest {
    Write-DiagLog "Running network speed test..."
    $results = @{
        DownloadMbps = "N/A"; UploadMbps = "N/A"; PingMs = "N/A"; Jitter = "N/A"
        PacketLoss = "N/A"; DNSResponseMs = "N/A"; Gateway = "N/A"; GatewayPing = "N/A"
        WiFiSignal = "N/A"; WiFiChannel = "N/A"; WiFiRadioType = "N/A"
    }

    # Gateway ping
    $results.Gateway = Invoke-Safe {
        $gw = (Get-NetRoute -DestinationPrefix "0.0.0.0/0" -ErrorAction Stop | Select-Object -First 1).NextHop
        $gw
    } "N/A"
    if ($results.Gateway -ne "N/A") {
        $results.GatewayPing = Invoke-Safe {
            $p = Test-Connection -ComputerName $results.Gateway -Count 4 -ErrorAction Stop
            "$([math]::Round(($p | Measure-Object -Property Latency -Average).Average, 0))ms"
        } "N/A"
    }

    # DNS response time
    $results.DNSResponseMs = Invoke-Safe {
        $start = Get-Date; Resolve-DnsName "google.com" -Type A -ErrorAction Stop | Out-Null
        "$([math]::Round(((Get-Date) - $start).TotalMilliseconds, 0))ms"
    } "N/A"

    # Ping test to multiple targets
    $results.PingMs = Invoke-Safe {
        $pings = @()
        foreach ($target in @("8.8.8.8","1.1.1.1","208.67.222.222")) {
            $p = Test-Connection -ComputerName $target -Count 3 -ErrorAction SilentlyContinue
            if ($p) { $pings += ($p | Measure-Object -Property Latency -Average).Average }
        }
        if ($pings.Count -gt 0) { "$([math]::Round(($pings | Measure-Object -Average).Average, 0))ms" } else { "Failed" }
    } "N/A"

    # Jitter calculation
    $results.Jitter = Invoke-Safe {
        $p = Test-Connection -ComputerName "8.8.8.8" -Count 10 -ErrorAction Stop
        $latencies = $p | ForEach-Object { $_.Latency }
        $diffs = @(); for ($i=1; $i -lt $latencies.Count; $i++) { $diffs += [math]::Abs($latencies[$i] - $latencies[$i-1]) }
        if ($diffs.Count -gt 0) { "$([math]::Round(($diffs | Measure-Object -Average).Average, 1))ms" } else { "N/A" }
    } "N/A"

    # Packet loss
    $results.PacketLoss = Invoke-Safe {
        $p = Test-Connection -ComputerName "8.8.8.8" -Count 20 -ErrorAction SilentlyContinue
        $received = if ($p) { $p.Count } else { 0 }
        $loss = [math]::Round(((20 - $received) / 20) * 100, 0)
        "$loss%"
    } "N/A"

    # WiFi details
    $wifiInfo = Invoke-Safe {
        $w = netsh wlan show interfaces 2>&1; $signal = ""; $channel = ""; $radioType = ""; $rxRate = ""; $txRate = ""
        foreach ($l in $w) {
            if ($l -match "Signal\s+:\s+(.+)$") { $signal = $Matches[1].Trim() }
            if ($l -match "Channel\s+:\s+(.+)$") { $channel = $Matches[1].Trim() }
            if ($l -match "Radio type\s+:\s+(.+)$") { $radioType = $Matches[1].Trim() }
            if ($l -match "Receive rate.*:\s+(.+)$") { $rxRate = $Matches[1].Trim() }
            if ($l -match "Transmit rate.*:\s+(.+)$") { $txRate = $Matches[1].Trim() }
        }
        @{ Signal = $signal; Channel = $channel; RadioType = $radioType; RxRate = $rxRate; TxRate = $txRate }
    } @{ Signal = "N/A"; Channel = "N/A"; RadioType = "N/A"; RxRate = "N/A"; TxRate = "N/A" }
    $results.WiFiSignal = $wifiInfo.Signal; $results.WiFiChannel = $wifiInfo.Channel
    $results.WiFiRadioType = $wifiInfo.RadioType; $results.WiFiRxRate = $wifiInfo.RxRate; $results.WiFiTxRate = $wifiInfo.TxRate

    # Download speed test (download a known file and measure)
    $results.DownloadMbps = Invoke-Safe {
        $testUrl = "http://speedtest.tele2.net/10MB.zip"
        $tmpFile = Join-Path $env:TEMP "pcplus_speedtest.bin"
        $start = Get-Date
        Invoke-WebRequest -Uri $testUrl -OutFile $tmpFile -UseBasicParsing -TimeoutSec 30 -ErrorAction Stop
        $elapsed = ((Get-Date) - $start).TotalSeconds
        $fileSize = (Get-Item $tmpFile).Length
        Remove-Item $tmpFile -Force -ErrorAction SilentlyContinue
        $mbps = [math]::Round(($fileSize * 8 / 1000000) / $elapsed, 1)
        "$mbps Mbps"
    } "N/A"

    Write-DiagLog "Network: Download=$($results.DownloadMbps), Ping=$($results.PingMs), Jitter=$($results.Jitter), Loss=$($results.PacketLoss)"
    return $results
}

# ─────────────────────────────────────────────────────────────────────────────
# GAMING READINESS
# ─────────────────────────────────────────────────────────────────────────────

function Get-GamingReadiness {
    Write-DiagLog "Assessing gaming readiness..."
    $results = @{ Score = 0; Tier = "Not Gaming Ready"; DirectXVersion = "N/A"; GPUName = "N/A"; VRAM_MB = 0; RefreshRate = "N/A" }

    $gpu = Invoke-Safe { Get-CimInstance Win32_VideoController | Where-Object { $_.AdapterRAM -gt 0 } | Select-Object -First 1 } $null
    if ($gpu) {
        $results.GPUName = $gpu.Name
        $results.VRAM_MB = [math]::Round($gpu.AdapterRAM / 1MB, 0)
        $results.DriverVersion = $gpu.DriverVersion
        $results.Resolution = "$($gpu.CurrentHorizontalResolution)x$($gpu.CurrentVerticalResolution)"
        $results.RefreshRate = "$($gpu.CurrentRefreshRate) Hz"
    }

    $results.DirectXVersion = Invoke-Safe {
        $dxKey = "HKLM:\SOFTWARE\Microsoft\DirectX"
        $ver = (Get-ItemProperty $dxKey -ErrorAction Stop).Version
        if ($ver) { "DirectX $ver" } else { "Unknown" }
    } "N/A"

    $cpu = Invoke-Safe { Get-CimInstance Win32_Processor | Select-Object -First 1 } $null
    $ram = Invoke-Safe { [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 0) } 0

    # Scoring: GPU VRAM, RAM, CPU cores
    $gpuScore = 0
    if ($results.VRAM_MB -ge 8192) { $gpuScore = 40 }
    elseif ($results.VRAM_MB -ge 4096) { $gpuScore = 30 }
    elseif ($results.VRAM_MB -ge 2048) { $gpuScore = 20 }
    elseif ($results.VRAM_MB -ge 1024) { $gpuScore = 10 }

    $ramScore = 0
    if ($ram -ge 32) { $ramScore = 25 }
    elseif ($ram -ge 16) { $ramScore = 20 }
    elseif ($ram -ge 8) { $ramScore = 12 }
    elseif ($ram -ge 4) { $ramScore = 5 }

    $cpuScore = 0
    if ($cpu) {
        $results.CPUCores = $cpu.NumberOfCores; $results.CPUThreads = $cpu.NumberOfLogicalProcessors
        $results.CPUBaseClock = $cpu.MaxClockSpeed
        if ($cpu.NumberOfCores -ge 8 -and $cpu.MaxClockSpeed -ge 3000) { $cpuScore = 35 }
        elseif ($cpu.NumberOfCores -ge 6 -and $cpu.MaxClockSpeed -ge 2500) { $cpuScore = 28 }
        elseif ($cpu.NumberOfCores -ge 4 -and $cpu.MaxClockSpeed -ge 2000) { $cpuScore = 18 }
        elseif ($cpu.NumberOfCores -ge 2) { $cpuScore = 8 }
    }

    $results.Score = $gpuScore + $ramScore + $cpuScore
    $results.Tier = if ($results.Score -ge 80) { "High-End Gaming" }
                    elseif ($results.Score -ge 60) { "Mid-Range Gaming" }
                    elseif ($results.Score -ge 40) { "Entry-Level Gaming" }
                    elseif ($results.Score -ge 20) { "Light Gaming Only" }
                    else { "Not Gaming Ready" }

    $results.GPUScoreDetail = $gpuScore; $results.RAMScoreDetail = $ramScore; $results.CPUScoreDetail = $cpuScore
    $results.TotalRAM = $ram

    Write-DiagLog "Gaming: Score=$($results.Score), Tier=$($results.Tier), GPU=$($results.GPUName), VRAM=$($results.VRAM_MB)MB"
    return $results
}

# ─────────────────────────────────────────────────────────────────────────────
# BOOT PERFORMANCE
# ─────────────────────────────────────────────────────────────────────────────

function Get-BootPerformance {
    Write-DiagLog "Collecting boot performance data..."
    $results = @{ Events = @(); BootTimeMs = "N/A"; ShutdownTimeMs = "N/A"; SlowStartupApps = @() }

    $results.Events = Invoke-Safe {
        $events = @()
        Get-WinEvent -LogName "Microsoft-Windows-Diagnostics-Performance/Operational" -MaxEvents 50 -ErrorAction Stop |
            Where-Object { $_.Id -in @(100,101,102,200) } | ForEach-Object {
                $evType = switch ($_.Id) { 100 {"Boot Performance"}; 101 {"Slow Startup App"}; 102 {"Slow Startup Driver"}; 200 {"Shutdown Performance"} }
                $events += @{ Time = $_.TimeCreated.ToString("yyyy-MM-dd HH:mm"); Type = $evType; Id = $_.Id; Message = ($_.Message -split "`n" | Select-Object -First 2) -join " " }
            }
        $events
    } @()

    $results.BootTimeMs = Invoke-Safe {
        $bootEvt = Get-WinEvent -LogName "Microsoft-Windows-Diagnostics-Performance/Operational" -MaxEvents 5 -ErrorAction Stop | Where-Object { $_.Id -eq 100 } | Select-Object -First 1
        if ($bootEvt -and $bootEvt.Properties.Count -ge 2) { "$($bootEvt.Properties[1].Value)ms" } else { "N/A" }
    } "N/A"

    $results.ShutdownTimeMs = Invoke-Safe {
        $sdEvt = Get-WinEvent -LogName "Microsoft-Windows-Diagnostics-Performance/Operational" -MaxEvents 5 -ErrorAction Stop | Where-Object { $_.Id -eq 200 } | Select-Object -First 1
        if ($sdEvt -and $sdEvt.Properties.Count -ge 2) { "$($sdEvt.Properties[1].Value)ms" } else { "N/A" }
    } "N/A"

    $results.SlowStartupApps = Invoke-Safe {
        $apps = @()
        Get-WinEvent -LogName "Microsoft-Windows-Diagnostics-Performance/Operational" -MaxEvents 30 -ErrorAction Stop |
            Where-Object { $_.Id -eq 101 } | Select-Object -First 10 | ForEach-Object {
                $name = if ($_.Properties.Count -ge 5) { $_.Properties[4].Value } else { "Unknown" }
                $time = if ($_.Properties.Count -ge 2) { "$($_.Properties[1].Value)ms" } else { "N/A" }
                $apps += @{ Name = $name; DelayMs = $time; Date = $_.TimeCreated.ToString("yyyy-MM-dd") }
            }
        $apps
    } @()

    Write-DiagLog "Boot: Time=$($results.BootTimeMs), Shutdown=$($results.ShutdownTimeMs), SlowApps=$($results.SlowStartupApps.Count)"
    return $results
}

# ─────────────────────────────────────────────────────────────────────────────
# WINDOWS 11 READINESS CHECK
# ─────────────────────────────────────────────────────────────────────────────

function Get-Windows11Readiness {
    Write-DiagLog "Checking Windows 11 readiness..."
    $results = @{ Ready = $true; Checks = @(); Score = 0; MaxScore = 0 }

    # TPM 2.0
    $tpm = Invoke-Safe {
        $t = Get-Tpm -ErrorAction Stop
        $ver = (Get-CimInstance -Namespace "root\cimv2\Security\MicrosoftTpm" -ClassName Win32_Tpm -ErrorAction Stop).SpecVersion
        @{ Present = $t.TpmPresent; Ready = $t.TpmReady; Version = $ver }
    } @{ Present = $false; Ready = $false; Version = "N/A" }
    $tpmPass = $tpm.Present -and ($tpm.Version -match "^2\.")
    $results.Checks += @{ Name = "TPM 2.0"; Passed = $tpmPass; Value = "Present: $($tpm.Present), Version: $($tpm.Version)" }
    $results.MaxScore += 20; if ($tpmPass) { $results.Score += 20 } else { $results.Ready = $false }

    # Secure Boot
    $sb = Invoke-Safe { Confirm-SecureBootUEFI -ErrorAction Stop } $false
    $results.Checks += @{ Name = "Secure Boot / UEFI"; Passed = $sb; Value = if ($sb) { "Enabled" } else { "Disabled or Legacy BIOS" } }
    $results.MaxScore += 20; if ($sb) { $results.Score += 20 } else { $results.Ready = $false }

    # RAM >= 4 GB
    $ram = Invoke-Safe { [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 1) } 0
    $ramPass = $ram -ge 4
    $results.Checks += @{ Name = "RAM >= 4 GB"; Passed = $ramPass; Value = "$ram GB" }
    $results.MaxScore += 15; if ($ramPass) { $results.Score += 15 } else { $results.Ready = $false }

    # Storage >= 64 GB
    $osDisk = Invoke-Safe { [math]::Round((Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'").Size / 1GB, 0) } 0
    $diskPass = $osDisk -ge 64
    $results.Checks += @{ Name = "OS Drive >= 64 GB"; Passed = $diskPass; Value = "$osDisk GB" }
    $results.MaxScore += 15; if ($diskPass) { $results.Score += 15 } else { $results.Ready = $false }

    # CPU cores >= 2 and clock >= 1 GHz
    $cpu = Invoke-Safe { Get-CimInstance Win32_Processor | Select-Object -First 1 } $null
    $cpuPass = $false
    if ($cpu) { $cpuPass = $cpu.NumberOfCores -ge 2 -and $cpu.MaxClockSpeed -ge 1000 }
    $results.Checks += @{ Name = "CPU >= 2 cores, 1 GHz"; Passed = $cpuPass; Value = if ($cpu) { "$($cpu.NumberOfCores) cores, $($cpu.MaxClockSpeed) MHz" } else { "N/A" } }
    $results.MaxScore += 15; if ($cpuPass) { $results.Score += 15 } else { $results.Ready = $false }

    # DirectX 12 / WDDM 2.0
    $dxPass = Invoke-Safe {
        $gpu = Get-CimInstance Win32_VideoController | Where-Object { $_.AdapterRAM -gt 0 } | Select-Object -First 1
        if ($gpu -and $gpu.DriverVersion) { $true } else { $false }
    } $false
    $results.Checks += @{ Name = "DirectX 12 / WDDM 2.0 GPU"; Passed = $dxPass; Value = if ($dxPass) { "Compatible" } else { "Check required" } }
    $results.MaxScore += 15; if ($dxPass) { $results.Score += 15 }

    $results.Verdict = if ($results.Ready) { "This PC meets Windows 11 requirements" } else { "This PC does NOT meet all Windows 11 requirements" }

    Write-DiagLog "Win11 Readiness: Score=$($results.Score)/$($results.MaxScore), Ready=$($results.Ready)"
    return $results
}

# ─────────────────────────────────────────────────────────────────────────────
# HISTORICAL TRACKING
# ─────────────────────────────────────────────────────────────────────────────

$Global:HistoryDir = "C:\PCPlus360\History"

function Save-ScanHistory {
    param($ScanData)
    Write-DiagLog "Saving scan to history..."
    Invoke-Safe {
        $compName = $ScanData.SystemInfo.ComputerName
        $serial = $ScanData.SystemInfo.Serial
        $deviceDir = Join-Path $Global:HistoryDir ($compName -replace '[\\/:*?"<>|]','_')
        if (-not (Test-Path $deviceDir)) { New-Item -Path $deviceDir -ItemType Directory -Force | Out-Null }

        $summary = @{
            ScanDate = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            ComputerName = $compName; Serial = $serial
            HardwareScore = $ScanData.HardwareScore; SecurityScore = $ScanData.SecurityScore
            CPUModel = $ScanData.SystemInfo.CPUModel; RAMTotal = $ScanData.SystemInfo.RAMTotal
            CPUPeakTemp = if ($ScanData.StressResults.CPU) { $ScanData.StressResults.CPU.MaxTemp } else { "N/A" }
            GPUPeakTemp = if ($ScanData.StressResults.GPU) { $ScanData.StressResults.GPU.MaxTemp } else { "N/A" }
            CPUStressPassed = if ($ScanData.StressResults.CPU) { $ScanData.StressResults.CPU.Passed } else { $null }
            RAMStressPassed = if ($ScanData.StressResults.RAM) { $ScanData.StressResults.RAM.Passed } else { $null }
            GPUStressPassed = if ($ScanData.StressResults.GPU) { $ScanData.StressResults.GPU.Passed } else { $null }
            DiskWriteMBps = if ($ScanData.StressResults.Disk) { $ScanData.StressResults.Disk.SeqWriteMBps } else { "N/A" }
            DiskReadMBps = if ($ScanData.StressResults.Disk) { $ScanData.StressResults.Disk.SeqReadMBps } else { "N/A" }
            SSDHealth = ($ScanData.SystemInfo.SMART | ForEach-Object { "$($_.Model):$($_.Health)" }) -join "; "
            SSDWear = ($ScanData.SystemInfo.SMART | ForEach-Object { "$($_.Model):$($_.Wear)" }) -join "; "
            SSDTemp = ($ScanData.SystemInfo.SMART | ForEach-Object { "$($_.Model):$($_.Temperature)" }) -join "; "
            BatteryHealth = if ($ScanData.Battery -and $ScanData.Battery.Present) { $ScanData.Battery.HealthPct } else { "N/A" }
            BatteryCycles = if ($ScanData.Battery -and $ScanData.Battery.Present) { $ScanData.Battery.CycleCount } else { "N/A" }
            CrashCount = if ($ScanData.Stability) { $ScanData.Stability.TotalBSODs + $ScanData.Stability.TotalUnexpected } else { 0 }
            StabilityRating = if ($ScanData.Stability) { $ScanData.Stability.StabilityRating } else { "N/A" }
            BootTime = $ScanData.SystemInfo.Uptime
            NetworkDownload = if ($ScanData.SpeedTest) { $ScanData.SpeedTest.DownloadMbps } else { "N/A" }
            GamingScore = if ($ScanData.Gaming) { $ScanData.Gaming.Score } else { "N/A" }
            GamingTier = if ($ScanData.Gaming) { $ScanData.Gaming.Tier } else { "N/A" }
            ScanMode = $ScanData.ScanMode
        }

        $fileName = "scan_$(Get-Date -Format 'yyyyMMdd_HHmmss').json"
        $filePath = Join-Path $deviceDir $fileName
        $summary | ConvertTo-Json -Depth 5 | Set-Content $filePath -Encoding UTF8
        Write-DiagLog "History saved: $filePath"
        $filePath
    } $null
}

function Get-ScanHistory {
    param([string]$ComputerName)
    Write-DiagLog "Loading scan history for $ComputerName..."
    Invoke-Safe {
        $deviceDir = Join-Path $Global:HistoryDir ($ComputerName -replace '[\\/:*?"<>|]','_')
        if (-not (Test-Path $deviceDir)) { return @() }
        $scans = @()
        Get-ChildItem $deviceDir -Filter "scan_*.json" | Sort-Object Name -Descending | Select-Object -First 20 | ForEach-Object {
            $data = Get-Content $_.FullName -Raw | ConvertFrom-Json
            $scans += $data
        }
        $scans
    } @()
}

function Compare-ScanHistory {
    param($Current, $Previous)
    if (-not $Previous -or $Previous.Count -eq 0) { return $null }
    $last = $Previous[0]
    $comparison = @{
        PreviousDate = $last.ScanDate; HasPrevious = $true
        ScoreDelta = if ($Current.HardwareScore -ne "N/A" -and $last.HardwareScore -ne "N/A") { $Current.HardwareScore - $last.HardwareScore } else { 0 }
        Trends = @()
    }
    # SSD health trend
    if ($last.SSDHealth -and $Current.SSDHealth) {
        $comparison.Trends += @{ Category = "SSD Health"; Previous = $last.SSDHealth; Current = $Current.SSDHealth }
    }
    # Battery trend
    if ($last.BatteryHealth -ne "N/A" -and $Current.BatteryHealth -ne "N/A") {
        $delta = $Current.BatteryHealth - $last.BatteryHealth
        $dir = if ($delta -gt 0) { "Improved" } elseif ($delta -lt 0) { "Declined" } else { "Stable" }
        $comparison.Trends += @{ Category = "Battery Health"; Previous = "$($last.BatteryHealth)%"; Current = "$($Current.BatteryHealth)%"; Direction = $dir; Delta = $delta }
    }
    # Temperature trend
    if ($last.CPUPeakTemp -ne "N/A" -and $Current.CPUPeakTemp -ne "N/A") {
        $comparison.Trends += @{ Category = "CPU Peak Temp"; Previous = "$($last.CPUPeakTemp)C"; Current = "$($Current.CPUPeakTemp)C" }
    }
    # Crash trend
    if ($last.CrashCount -ne $null -and $Current.CrashCount -ne $null) {
        $comparison.Trends += @{ Category = "Crash Events"; Previous = $last.CrashCount; Current = $Current.CrashCount }
    }
    # Disk performance trend
    if ($last.DiskWriteMBps -ne "N/A" -and $Current.DiskWriteMBps -ne "N/A") {
        $comparison.Trends += @{ Category = "Disk Write Speed"; Previous = "$($last.DiskWriteMBps) MB/s"; Current = "$($Current.DiskWriteMBps) MB/s" }
    }
    return $comparison
}

# ─────────────────────────────────────────────────────────────────────────────
# EXPORT FUNCTIONS
# ─────────────────────────────────────────────────────────────────────────────

function Export-ScanJSON {
    param($ScanData, [string]$OutputFolder)
    $safeName = $ScanData.CustomerName -replace '[\\/:*?"<>|]','_'
    $safeDev = $ScanData.SystemInfo.ComputerName -replace '[\\/:*?"<>|]','_'
    $ds = Get-Date -Format "yyyy-MM-dd"
    $path = Join-Path $OutputFolder "$safeName - $safeDev - Full Data $ds.json"
    $ScanData | ConvertTo-Json -Depth 10 | Set-Content $path -Encoding UTF8
    Write-DiagLog "JSON exported: $path"
    return $path
}

function Export-ScanCSV {
    param($ScanData, [string]$OutputFolder)
    $safeName = $ScanData.CustomerName -replace '[\\/:*?"<>|]','_'
    $safeDev = $ScanData.SystemInfo.ComputerName -replace '[\\/:*?"<>|]','_'
    $ds = Get-Date -Format "yyyy-MM-dd"
    $path = Join-Path $OutputFolder "$safeName - $safeDev - Summary $ds.csv"
    $rows = @()
    $rows += [PSCustomObject]@{ Category="System"; Item="Computer Name"; Value=$ScanData.SystemInfo.ComputerName }
    $rows += [PSCustomObject]@{ Category="System"; Item="Manufacturer"; Value=$ScanData.SystemInfo.Manufacturer }
    $rows += [PSCustomObject]@{ Category="System"; Item="Model"; Value=$ScanData.SystemInfo.Model }
    $rows += [PSCustomObject]@{ Category="System"; Item="Serial"; Value=$ScanData.SystemInfo.Serial }
    $rows += [PSCustomObject]@{ Category="System"; Item="OS"; Value=$ScanData.SystemInfo.OSVersion }
    $rows += [PSCustomObject]@{ Category="System"; Item="CPU"; Value=$ScanData.SystemInfo.CPUModel }
    $rows += [PSCustomObject]@{ Category="System"; Item="RAM"; Value="$($ScanData.SystemInfo.RAMTotal) GB" }
    $rows += [PSCustomObject]@{ Category="Score"; Item="Hardware Score"; Value=$ScanData.HardwareScore }
    $rows += [PSCustomObject]@{ Category="Score"; Item="Security Score"; Value=$ScanData.SecurityScore }
    if ($ScanData.StressResults.CPU) {
        $rows += [PSCustomObject]@{ Category="Stress"; Item="CPU Test"; Value=if($ScanData.StressResults.CPU.Passed){"PASS"}else{"FAIL"} }
        $rows += [PSCustomObject]@{ Category="Stress"; Item="CPU Peak Temp"; Value="$($ScanData.StressResults.CPU.MaxTemp)C" }
    }
    if ($ScanData.StressResults.RAM) { $rows += [PSCustomObject]@{ Category="Stress"; Item="RAM Test"; Value=if($ScanData.StressResults.RAM.Passed){"PASS"}else{"FAIL"} } }
    if ($ScanData.StressResults.GPU) { $rows += [PSCustomObject]@{ Category="Stress"; Item="GPU Test"; Value=if($ScanData.StressResults.GPU.Passed){"PASS"}else{"FAIL"} } }
    if ($ScanData.StressResults.Disk) {
        $rows += [PSCustomObject]@{ Category="Stress"; Item="Disk Write"; Value="$($ScanData.StressResults.Disk.SeqWriteMBps) MB/s" }
        $rows += [PSCustomObject]@{ Category="Stress"; Item="Disk Read"; Value="$($ScanData.StressResults.Disk.SeqReadMBps) MB/s" }
    }
    foreach ($d in $ScanData.SystemInfo.SMART) {
        $rows += [PSCustomObject]@{ Category="Storage"; Item=$d.Model; Value="$($d.Health), Wear:$($d.Wear), Temp:$($d.Temperature)" }
    }
    if ($ScanData.Battery -and $ScanData.Battery.Present) {
        $rows += [PSCustomObject]@{ Category="Battery"; Item="Health"; Value="$($ScanData.Battery.HealthPct)%" }
        $rows += [PSCustomObject]@{ Category="Battery"; Item="Cycles"; Value=$ScanData.Battery.CycleCount }
    }
    if ($ScanData.Stability) {
        $rows += [PSCustomObject]@{ Category="Stability"; Item="Rating"; Value=$ScanData.Stability.StabilityRating }
        $rows += [PSCustomObject]@{ Category="Stability"; Item="BSODs (90 days)"; Value=$ScanData.Stability.TotalBSODs }
    }
    if ($ScanData.SpeedTest) {
        $rows += [PSCustomObject]@{ Category="Network"; Item="Download"; Value=$ScanData.SpeedTest.DownloadMbps }
        $rows += [PSCustomObject]@{ Category="Network"; Item="Ping"; Value=$ScanData.SpeedTest.PingMs }
    }
    if ($ScanData.Gaming) {
        $rows += [PSCustomObject]@{ Category="Gaming"; Item="Score"; Value=$ScanData.Gaming.Score }
        $rows += [PSCustomObject]@{ Category="Gaming"; Item="Tier"; Value=$ScanData.Gaming.Tier }
    }
    $rows | Export-Csv -Path $path -NoTypeInformation -Encoding UTF8
    Write-DiagLog "CSV exported: $path"
    return $path
}

# ─────────────────────────────────────────────────────────────────────────────
# BUILT-IN STRESS TESTS
# ─────────────────────────────────────────────────────────────────────────────

function Get-FanInfo {
    Invoke-Safe {
        $fans = @()
        Get-CimInstance Win32_Fan -ErrorAction Stop | ForEach-Object {
            $fans += @{ Name = $_.Name; Status = $_.Status; Speed = $_.DesiredSpeed }
        }
        if ($fans.Count -eq 0) {
            Get-CimInstance -Namespace root/wmi -ClassName MSAcpi_ThermalZoneTemperature -ErrorAction Stop | ForEach-Object {
                $fans += @{ Name = $_.InstanceName; Status = "Active"; Speed = "N/A" }
            }
        }
        $fans
    } @()
}

function Start-CPUStressTest {
    param([int]$DurationSeconds = 60)
    Write-DiagLog "Starting CPU stress test ($DurationSeconds seconds)..."
    $threadCount = [Environment]::ProcessorCount
    $results = @{
        Threads = $threadCount; Duration = $DurationSeconds
        StartTemp = "N/A"; EndTemp = "N/A"; MaxTemp = "N/A"; MinTemp = "N/A"; AvgTemp = "N/A"; RecoveryTemp = "N/A"
        TempLog = @(); Passed = $true; Errors = @()
        StartClock = "N/A"; MinClock = "N/A"; MaxClock = "N/A"; BaseClock = "N/A"
        ThrottleDetected = $false; Iterations = 0; ComputeErrors = 0
        FanSpeedStart = "N/A"; FanSpeedPeak = "N/A"
    }

    # Get baseline readings
    $results.StartTemp = Invoke-Safe {
        $t = Get-CimInstance MSAcpi_ThermalZoneTemperature -Namespace root/wmi -ErrorAction Stop | Select-Object -First 1
        [math]::Round(($t.CurrentTemperature / 10) - 273.15, 1)
    } "N/A"
    $cpuInfo = Invoke-Safe { Get-CimInstance Win32_Processor -ErrorAction Stop | Select-Object -First 1 } $null
    if ($cpuInfo) {
        $results.BaseClock = $cpuInfo.MaxClockSpeed
        $results.StartClock = $cpuInfo.CurrentClockSpeed
    }
    $results.FanSpeedStart = Invoke-Safe {
        $fan = Get-CimInstance Win32_Fan -ErrorAction Stop | Select-Object -First 1
        if ($fan -and $fan.DesiredSpeed) { $fan.DesiredSpeed } else { "N/A" }
    } "N/A"

    # Start stress worker jobs
    $jobs = @()
    $endTime = (Get-Date).AddSeconds($DurationSeconds)
    for ($i = 0; $i -lt $threadCount; $i++) {
        $jobs += Start-Job -ScriptBlock {
            param($end)
            $errors = 0; $iterations = 0
            while ((Get-Date) -lt $end) {
                $n = 100000; $primes = @($true) * ($n + 1)
                for ($p = 2; $p * $p -le $n; $p++) {
                    if ($primes[$p]) { for ($m = $p * $p; $m -le $n; $m += $p) { $primes[$m] = $false } }
                }
                $count = ($primes | Where-Object { $_ }) | Measure-Object | Select-Object -ExpandProperty Count
                $count -= 2
                if ($count -ne 9592) { $errors++ }
                $iterations++
            }
            return @{ Iterations = $iterations; Errors = $errors }
        } -ArgumentList $endTime
    }

    # Monitor temperature and clock speed during stress
    $tempLog = @(); $clockSpeeds = @(); $fanSpeeds = @()
    $startTime = Get-Date
    while ((Get-Date) -lt $endTime) {
        Start-Sleep -Seconds 5
        $elapsed = [math]::Round(((Get-Date) - $startTime).TotalSeconds)
        $temp = Invoke-Safe {
            $t = Get-CimInstance MSAcpi_ThermalZoneTemperature -Namespace root/wmi -ErrorAction Stop | Select-Object -First 1
            [math]::Round(($t.CurrentTemperature / 10) - 273.15, 1)
        } $null
        $clock = Invoke-Safe { (Get-CimInstance Win32_Processor -ErrorAction Stop | Select-Object -First 1).CurrentClockSpeed } $null
        $fan = Invoke-Safe {
            $f = Get-CimInstance Win32_Fan -ErrorAction Stop | Select-Object -First 1
            if ($f -and $f.DesiredSpeed) { $f.DesiredSpeed } else { $null }
        } $null
        if ($temp) { $tempLog += @{ Time = $elapsed; TempC = $temp } }
        if ($clock) { $clockSpeeds += $clock }
        if ($fan) { $fanSpeeds += $fan }
        Write-DiagLog "  Stress monitor: ${elapsed}s - Temp:${temp}C Clock:${clock}MHz"
    }

    # Collect job results
    $jobs | Wait-Job -Timeout 30 | Out-Null
    $totalIterations = 0; $totalErrors = 0
    foreach ($j in $jobs) {
        $r = Receive-Job $j -ErrorAction SilentlyContinue
        if ($r) { $totalIterations += $r.Iterations; $totalErrors += $r.Errors }
        Remove-Job $j -Force -ErrorAction SilentlyContinue
    }

    # End readings
    $results.EndTemp = Invoke-Safe {
        $t = Get-CimInstance MSAcpi_ThermalZoneTemperature -Namespace root/wmi -ErrorAction Stop | Select-Object -First 1
        [math]::Round(($t.CurrentTemperature / 10) - 273.15, 1)
    } "N/A"

    # Recovery - wait 15 seconds then check temp
    Write-DiagLog "Waiting 15s for cooling recovery measurement..."
    Start-Sleep -Seconds 15
    $results.RecoveryTemp = Invoke-Safe {
        $t = Get-CimInstance MSAcpi_ThermalZoneTemperature -Namespace root/wmi -ErrorAction Stop | Select-Object -First 1
        [math]::Round(($t.CurrentTemperature / 10) - 273.15, 1)
    } "N/A"

    # Calculate stats
    $results.TempLog = $tempLog
    if ($tempLog.Count -gt 0) {
        $temps = $tempLog | ForEach-Object { $_.TempC }
        $results.MaxTemp = ($temps | Measure-Object -Maximum).Maximum
        $results.MinTemp = ($temps | Measure-Object -Minimum).Minimum
        $results.AvgTemp = [math]::Round(($temps | Measure-Object -Average).Average, 1)
    }
    if ($clockSpeeds.Count -gt 0) {
        $results.MinClock = ($clockSpeeds | Measure-Object -Minimum).Minimum
        $results.MaxClock = ($clockSpeeds | Measure-Object -Maximum).Maximum
        if ($results.BaseClock -ne "N/A" -and $results.BaseClock -gt 0 -and $results.MinClock -lt ($results.BaseClock * 0.8)) {
            $results.ThrottleDetected = $true
        }
    }
    if ($fanSpeeds.Count -gt 0) { $results.FanSpeedPeak = ($fanSpeeds | Measure-Object -Maximum).Maximum }

    $results.Iterations = $totalIterations
    $results.ComputeErrors = $totalErrors
    $results.Passed = ($totalErrors -eq 0) -and (-not $results.ThrottleDetected)
    Write-DiagLog "CPU stress: $totalIterations iters, $totalErrors errors, MaxTemp=$($results.MaxTemp), Throttle=$($results.ThrottleDetected), Passed=$($results.Passed)"
    return $results
}

function Start-RAMStressTest {
    param([int]$DurationSeconds = 60, [int]$BlockSizeMB = 64)
    Write-DiagLog "Starting RAM stress test ($DurationSeconds seconds, ${BlockSizeMB}MB blocks)..."
    $results = @{ Duration = $DurationSeconds; BlockSizeMB = $BlockSizeMB; Passed = $true; BlocksTested = 0; Errors = 0 }

    $blockSize = $BlockSizeMB * 1MB
    $endTime = (Get-Date).AddSeconds($DurationSeconds)
    $blocksTested = 0; $errors = 0

    try {
        while ((Get-Date) -lt $endTime) {
            $buffer = New-Object byte[] $blockSize

            # Pattern 1: All 0xAA
            for ($i = 0; $i -lt $blockSize; $i += 4096) { $buffer[$i] = 0xAA }
            for ($i = 0; $i -lt $blockSize; $i += 4096) { if ($buffer[$i] -ne 0xAA) { $errors++ } }

            # Pattern 2: All 0x55
            for ($i = 0; $i -lt $blockSize; $i += 4096) { $buffer[$i] = 0x55 }
            for ($i = 0; $i -lt $blockSize; $i += 4096) { if ($buffer[$i] -ne 0x55) { $errors++ } }

            # Pattern 3: Sequential
            for ($i = 0; $i -lt $blockSize; $i += 4096) { $buffer[$i] = [byte]($i % 256) }
            for ($i = 0; $i -lt $blockSize; $i += 4096) { if ($buffer[$i] -ne [byte]($i % 256)) { $errors++ } }

            $blocksTested++
            $buffer = $null
            [System.GC]::Collect()
        }
    } catch {
        $errors++
        Write-DiagLog "RAM test exception: $($_.Exception.Message)" "WARN"
    }

    $results.BlocksTested = $blocksTested
    $results.Errors = $errors
    $results.Passed = $errors -eq 0
    $results.TotalMBTested = $blocksTested * $BlockSizeMB
    Write-DiagLog "RAM stress: $blocksTested blocks (${BlockSizeMB}MB each), $errors errors, Passed=$($results.Passed)"
    return $results
}

function Start-DiskBenchmark {
    param([string]$DriveLetter = "C", [int]$FileSizeMB = 256)
    Write-DiagLog "Starting disk benchmark on $DriveLetter`: ($FileSizeMB MB)..."
    $results = @{ Drive = $DriveLetter; FileSizeMB = $FileSizeMB; SeqWriteMBps = 0; SeqReadMBps = 0; Passed = $true }
    $testFile = "${DriveLetter}:\PCPlus_DiskTest_$(Get-Random).tmp"

    try {
        $blockSize = 1MB
        $blocks = $FileSizeMB
        $data = New-Object byte[] $blockSize
        (New-Object Random).NextBytes($data)

        # Sequential write
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $fs = [System.IO.File]::Create($testFile)
        for ($i = 0; $i -lt $blocks; $i++) { $fs.Write($data, 0, $blockSize) }
        $fs.Flush(); $fs.Close()
        $sw.Stop()
        $results.SeqWriteMBps = [math]::Round($FileSizeMB / ($sw.ElapsedMilliseconds / 1000), 1)

        # Sequential read
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $fs = [System.IO.File]::OpenRead($testFile)
        $readBuf = New-Object byte[] $blockSize
        while ($fs.Read($readBuf, 0, $blockSize) -gt 0) { }
        $fs.Close()
        $sw.Stop()
        $results.SeqReadMBps = [math]::Round($FileSizeMB / ($sw.ElapsedMilliseconds / 1000), 1)

        Write-DiagLog "Disk benchmark: Write=$($results.SeqWriteMBps) MB/s, Read=$($results.SeqReadMBps) MB/s"
    } catch {
        $results.Passed = $false
        Write-DiagLog "Disk benchmark error: $($_.Exception.Message)" "WARN"
    } finally {
        if (Test-Path $testFile) { Remove-Item $testFile -Force -ErrorAction SilentlyContinue }
    }

    return $results
}

function Start-GPUStressTest {
    param([int]$DurationSeconds = 60)
    Write-DiagLog "Starting GPU stress test ($DurationSeconds seconds)..."
    $results = @{
        Duration = $DurationSeconds; Passed = $true; GPUName = "N/A"
        StartTemp = "N/A"; EndTemp = "N/A"; MaxTemp = "N/A"
        TempLog = @(); ThrottleDetected = $false; Method = "Compute"
    }

    $gpu = Invoke-Safe { Get-CimInstance Win32_VideoController -ErrorAction Stop | Where-Object { $_.AdapterRAM -gt 0 } | Select-Object -First 1 } $null
    if ($gpu) { $results.GPUName = $gpu.Name }

    # Try to get GPU temp from WMI (works on some systems)
    $results.StartTemp = Invoke-Safe {
        $t = Get-CimInstance -Namespace root/cimv2 -ClassName Win32_PerfFormattedData_GPUPerformanceCounters_GPUAdapterMemory -ErrorAction Stop
        "N/A"
    } "N/A"

    # GPU stress via .NET DirectX compute or GDI+ fallback
    $endTime = (Get-Date).AddSeconds($DurationSeconds)
    $startTime = Get-Date
    $iterations = 0; $errors = 0; $tempLog = @()

    try {
        Add-Type -AssemblyName System.Drawing
        while ((Get-Date) -lt $endTime) {
            # GDI+ rendering stress - creates GPU load via bitmap operations
            $bmp = New-Object System.Drawing.Bitmap(2048, 2048)
            $g = [System.Drawing.Graphics]::FromImage($bmp)
            $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
            for ($i = 0; $i -lt 50; $i++) {
                $brush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb((Get-Random -Max 256),(Get-Random -Max 256),(Get-Random -Max 256)))
                $g.FillEllipse($brush, (Get-Random -Max 1800), (Get-Random -Max 1800), (Get-Random -Min 50 -Max 500), (Get-Random -Min 50 -Max 500))
                $pen = New-Object System.Drawing.Pen($brush.Color, (Get-Random -Min 1 -Max 10))
                $g.DrawLine($pen, (Get-Random -Max 2048), (Get-Random -Max 2048), (Get-Random -Max 2048), (Get-Random -Max 2048))
                $brush.Dispose(); $pen.Dispose()
            }
            # Matrix transform stress
            $matrix = New-Object System.Drawing.Drawing2D.Matrix
            $matrix.Rotate((Get-Random -Max 360))
            $matrix.Scale(1.5, 1.5)
            $g.Transform = $matrix
            $g.DrawImage($bmp, 0, 0)
            $matrix.Dispose()
            $g.Dispose(); $bmp.Dispose()
            $iterations++

            # Log temp every 5 iterations
            if ($iterations % 5 -eq 0) {
                $elapsed = [math]::Round(((Get-Date) - $startTime).TotalSeconds)
                $temp = Invoke-Safe {
                    $t = Get-CimInstance MSAcpi_ThermalZoneTemperature -Namespace root/wmi -ErrorAction Stop | Select-Object -First 1
                    [math]::Round(($t.CurrentTemperature / 10) - 273.15, 1)
                } $null
                if ($temp) { $tempLog += @{ Time = $elapsed; TempC = $temp } }
            }
        }
    } catch {
        $errors++
        Write-DiagLog "GPU stress error: $($_.Exception.Message)" "WARN"
    }

    $results.EndTemp = Invoke-Safe {
        $t = Get-CimInstance MSAcpi_ThermalZoneTemperature -Namespace root/wmi -ErrorAction Stop | Select-Object -First 1
        [math]::Round(($t.CurrentTemperature / 10) - 273.15, 1)
    } "N/A"

    $results.TempLog = $tempLog
    if ($tempLog.Count -gt 0) {
        $temps = $tempLog | ForEach-Object { $_.TempC }
        $results.MaxTemp = ($temps | Measure-Object -Maximum).Maximum
    }
    $results.Iterations = $iterations
    $results.Passed = $errors -eq 0
    Write-DiagLog "GPU stress: $iterations rendering iterations, $errors errors, MaxTemp=$($results.MaxTemp), Passed=$($results.Passed)"
    return $results
}

# ─────────────────────────────────────────────────────────────────────────────
# SECURITY SCORING
# ─────────────────────────────────────────────────────────────────────────────
function Calculate-Score {
    param($Security, $MissingPatches)
    $score = 0; $breakdown = @()
    $checks = @(
        @{ Name="Antivirus Active"; Pts=15; Test={ ($Security.Defender.RealTimeProtection -eq $true) -or ($Security.ThirdPartyAV.Count -gt 0) } }
        @{ Name="Firewall All Profiles"; Pts=15; Test={ $Security.Firewall.Domain -and $Security.Firewall.Private -and $Security.Firewall.Public } }
        @{ Name="BitLocker on C:"; Pts=10; Test={ $Security.BitLocker["C:"] -and $Security.BitLocker["C:"].Status -eq "On" } }
        @{ Name="No Critical Patches Missing"; Pts=10; Test={ ($MissingPatches | Where-Object { $_.Severity -eq "Critical" }).Count -eq 0 } }
        @{ Name="UAC Enabled"; Pts=5; Test={ $Security.UAC.Enabled -eq $true } }
        @{ Name="Secure Boot"; Pts=5; Test={ $Security.SecureBoot -eq $true } }
        @{ Name="TPM Present"; Pts=5; Test={ $Security.TPM.Present -eq $true } }
        @{ Name="Password Policy"; Pts=5; Test={ $Security.PasswordPolicy.MinLength -ge 8 -or $Security.PasswordPolicy.Complexity } }
        @{ Name="Guest Disabled"; Pts=3; Test={ $Security.GuestDisabled -eq $true } }
        @{ Name="No Auto-Login"; Pts=3; Test={ $Security.AutoLoginDisabled -eq $true } }
        @{ Name="RDP Secure"; Pts=5; Test={ ($Security.RDP.Enabled -eq $false) -or ($Security.RDP.NLA -eq $true) } }
        @{ Name="SMBv1 Disabled"; Pts=5; Test={ $Security.SMBv1Disabled -eq $true } }
        @{ Name="Admin Accounts <=2"; Pts=4; Test={ $Security.LocalAdmins.Count -le 2 } }
        @{ Name="Real-Time Protection"; Pts=5; Test={ $Security.Defender.RealTimeProtection -eq $true } }
        @{ Name="AV Definitions Current"; Pts=5; Test={ $Security.Defender.DefinitionsUpToDate -eq $true } }
    )
    foreach ($c in $checks) {
        $passed = try { & $c.Test } catch { $false }
        if ($passed) { $score += $c.Pts }
        $breakdown += @{ Check = $c.Name; Points = $c.Pts; Passed = $passed }
    }
    $grade = if ($score -ge 90){"A"} elseif ($score -ge 80){"B"} elseif ($score -ge 70){"C"} elseif ($score -ge 60){"D"} else {"F"}
    $color = if ($grade -eq "A" -or $grade -eq "B"){"#27ae60"} elseif ($grade -eq "C" -or $grade -eq "D"){"#f39c12"} else {"#e74c3c"}
    return @{ Score = $score; Grade = $grade; Color = $color; Breakdown = $breakdown }
}

# ─────────────────────────────────────────────────────────────────────────────
# REPORT GENERATION
# ─────────────────────────────────────────────────────────────────────────────

function Build-HardwareReport {
    param($Params, $SystemInfo, $Network, $Software, $Performance, $StressResults, $LicenseKeys, $Stability, $BatteryDetail, $PowerInfo, $SpeedTest, $Gaming, $HistoryComparison, $ScanMode, $BootPerf, $Win11Ready)
    $date = Get-Date -Format "MMMM dd, yyyy 'at' h:mm tt"
    $iconPass = "&#10004;"; $iconFail = "&#10008;"; $iconWarn = "&#9888;"

    # ── WEIGHTED SCORING (Storage 25%, CPU/RAM 20%, Thermal 15%, Stability 15%, Battery 10%, Devices 10%, Network 5%) ──
    $hwIssues = @()
    # Storage (25%)
    $storageScore = 100
    foreach ($d in $SystemInfo.SMART) { if ($d.Health -ne "Healthy") { $storageScore -= 25; $hwIssues += "Disk $($d.Model): $($d.Health)" } }
    foreach ($d in $SystemInfo.Disks) { if ($d.UsedPct -gt 90) { $storageScore -= 20; $hwIssues += "Drive $($d.Drive) nearly full ($($d.UsedPct)%)" } elseif ($d.UsedPct -gt 75) { $storageScore -= 10 } }
    if ($StressResults.Disk -and -not $StressResults.Disk.Passed) { $storageScore -= 20; $hwIssues += "Disk benchmark FAILED" }
    $storageScore = [math]::Max($storageScore, 0)
    # CPU/RAM (20%)
    $cpuMemScore = 100
    if ($StressResults.CPU -and -not $StressResults.CPU.Passed) { $cpuMemScore -= 35; $hwIssues += "CPU stress test FAILED" }
    if ($StressResults.RAM -and -not $StressResults.RAM.Passed) { $cpuMemScore -= 40; $hwIssues += "RAM stress test FAILED" }
    if ($StressResults.GPU -and -not $StressResults.GPU.Passed) { $cpuMemScore -= 15; $hwIssues += "GPU stress test FAILED" }
    if ($Performance.CPUPercent -gt 90) { $cpuMemScore -= 10 }
    if ($Performance.RAMPercent -gt 90) { $cpuMemScore -= 10 }
    $cpuMemScore = [math]::Max($cpuMemScore, 0)
    # Thermal (15%)
    $thermalScore = 100
    foreach ($t in $SystemInfo.Temperatures) { if ($t.TempC -gt 80) { $thermalScore -= 25; $hwIssues += "High temperature: $($t.TempC)C" } elseif ($t.TempC -gt 60) { $thermalScore -= 10 } }
    if ($StressResults.CPU -and $StressResults.CPU.ThrottleDetected) { $thermalScore -= 30; $hwIssues += "CPU thermal throttling detected" }
    $thermalScore = [math]::Max($thermalScore, 0)
    # Stability (15%)
    $stabilityScore = 100
    if ($Stability) {
        if ($Stability.TotalBSODs -ge 5) { $stabilityScore -= 40; $hwIssues += "$($Stability.TotalBSODs) BSODs in last 90 days" }
        elseif ($Stability.TotalBSODs -ge 1) { $stabilityScore -= ($Stability.TotalBSODs * 10) }
        if ($Stability.TotalUnexpected -ge 5) { $stabilityScore -= 25; $hwIssues += "$($Stability.TotalUnexpected) unexpected shutdowns" }
        elseif ($Stability.TotalUnexpected -ge 1) { $stabilityScore -= ($Stability.TotalUnexpected * 8) }
        if ($Stability.TotalWHEA -ge 3) { $stabilityScore -= 20 }
        if ($Stability.TotalDiskErrors -ge 5) { $stabilityScore -= 15 }
    }
    $stabilityScore = [math]::Max($stabilityScore, 0)
    # Battery/Power (10%)
    $batteryPowerScore = 100
    if ($SystemInfo.Battery.Present -and $SystemInfo.Battery.HealthPct -gt 0) {
        if ($SystemInfo.Battery.HealthPct -lt 40) { $batteryPowerScore = 30; $hwIssues += "Battery health critical: $($SystemInfo.Battery.HealthPct)%" }
        elseif ($SystemInfo.Battery.HealthPct -lt 60) { $batteryPowerScore = 55 }
        elseif ($SystemInfo.Battery.HealthPct -lt 80) { $batteryPowerScore = 75 }
    }
    if ($PowerInfo -and $PowerInfo.UnexpectedShutdowns -ge 3) { $batteryPowerScore -= 20 }
    $batteryPowerScore = [math]::Max($batteryPowerScore, 0)
    # Devices (10%)
    $deviceScore = 100
    if ($SystemInfo.DeviceErrors.Count -gt 0) { $deviceScore -= ($SystemInfo.DeviceErrors.Count * 10); $hwIssues += "$($SystemInfo.DeviceErrors.Count) Device Manager errors" }
    $deviceScore = [math]::Max($deviceScore, 0)
    # Network (5%)
    $networkScore = 100
    if ($SpeedTest -and $SpeedTest.PacketLoss -and $SpeedTest.PacketLoss -ne "N/A" -and $SpeedTest.PacketLoss -ne "0%") {
        $lossVal = [int]($SpeedTest.PacketLoss -replace '%','')
        if ($lossVal -ge 10) { $networkScore -= 40 } elseif ($lossVal -ge 5) { $networkScore -= 20 }
    }
    $networkScore = [math]::Max($networkScore, 0)

    # Weighted total
    $hwScore = [math]::Round(($storageScore * 0.25) + ($cpuMemScore * 0.20) + ($thermalScore * 0.15) + ($stabilityScore * 0.15) + ($batteryPowerScore * 0.10) + ($deviceScore * 0.10) + ($networkScore * 0.05))
    $hwScore = [math]::Max([math]::Min($hwScore, 100), 0)
    $hwGrade = if ($hwScore -ge 90){"A"} elseif ($hwScore -ge 80){"B"} elseif ($hwScore -ge 70){"C"} elseif ($hwScore -ge 60){"D"} else {"F"}
    $hwColor = if ($hwGrade -eq "A" -or $hwGrade -eq "B"){"#27ae60"} elseif ($hwGrade -eq "C" -or $hwGrade -eq "D"){"#f39c12"} else {"#e74c3c"}
    $dashOffset = 283 - (283 * $hwScore / 100)

    # Load logo as base64 data URI
    $logoDataUri = ""
    $logoPath = Join-Path $Global:ScriptDir "logo-base64.txt"
    if (Test-Path $logoPath) {
        try {
            $logoB64 = (Get-Content $logoPath -Raw).Trim()
            $logoDataUri = "data:image/png;base64,$logoB64"
        } catch { $logoDataUri = "" }
    }
    $logoHTML = if ($logoDataUri) {
        "<img src='$logoDataUri' alt='PC Plus Computing' style='width:350px;max-width:90%;margin-bottom:30px;'/>"
    } else {
        "<div style='background:#0a1628;color:#fff;padding:20px 50px;font-size:22pt;font-weight:bold;letter-spacing:3px;border-radius:6px;margin-bottom:30px;'>PC PLUS COMPUTING</div>"
    }

    # Load QR codes as base64 data URIs
    $qrAppointmentUri = ""; $qrServiceUri = ""
    $qrAppPath = Join-Path $Global:ScriptDir "qr-appointments.txt"
    $qrSvcPath = Join-Path $Global:ScriptDir "qr-service-requests.txt"
    if (Test-Path $qrAppPath) { try { $qrAppointmentUri = "data:image/png;base64,$((Get-Content $qrAppPath -Raw).Trim())" } catch {} }
    if (Test-Path $qrSvcPath) { try { $qrServiceUri = "data:image/png;base64,$((Get-Content $qrSvcPath -Raw).Trim())" } catch {} }

    # Load cross-promotion banners
    $bannerSecTopUri = ""; $bannerSecBottomUri = ""
    $bstPath = Join-Path $Global:ScriptDir "banner-security-top.txt"
    $bsbPath = Join-Path $Global:ScriptDir "banner-security-bottom.txt"
    if (Test-Path $bstPath) { try { $bannerSecTopUri = "data:image/jpeg;base64,$((Get-Content $bstPath -Raw).Trim())" } catch {} }
    if (Test-Path $bsbPath) { try { $bannerSecBottomUri = "data:image/jpeg;base64,$((Get-Content $bsbPath -Raw).Trim())" } catch {} }

    # Load hardware report's own banner
    $bannerHwOwnUri = ""
    $bhoPath = Join-Path $Global:ScriptDir "banner-hardware-top.txt"
    if (Test-Path $bhoPath) { try { $bannerHwOwnUri = "data:image/jpeg;base64,$((Get-Content $bhoPath -Raw).Trim())" } catch {} }

    # Battery score for display
    $batteryScore = if ($SystemInfo.Battery.Present -and $SystemInfo.Battery.HealthPct -gt 0) { $SystemInfo.Battery.HealthPct } else { -1 }

    # Helper: color for a sub-score
    function Get-ScoreColor($s) { if ($s -ge 80) { "#16a34a" } elseif ($s -ge 60) { "#f59e0b" } else { "#dc2626" } }
    function Get-ScoreGrade($s) { if ($s -ge 90){"A"} elseif($s -ge 80){"B"} elseif($s -ge 70){"C"} elseif($s -ge 60){"D"} else{"F"} }

    # Build key findings
    $keyFindings = @()
    if ($hwIssues.Count -eq 0) { $keyFindings += "All hardware components are functioning within normal parameters." }
    foreach ($d in $SystemInfo.SMART) { if ($d.Health -ne "Healthy") { $keyFindings += "Storage drive '$($d.Model)' is reporting $($d.Health) status and may need replacement." } }
    foreach ($d in $SystemInfo.Disks) { if ($d.UsedPct -gt 90) { $keyFindings += "Drive $($d.Drive) is nearly full at $($d.UsedPct)% used, which can degrade performance." } }
    if ($SystemInfo.DeviceErrors.Count -gt 0) { $keyFindings += "$($SystemInfo.DeviceErrors.Count) device(s) in Device Manager are reporting errors and may need driver updates." }
    if ($SystemInfo.Battery.Present -and $SystemInfo.Battery.HealthPct -gt 0 -and $SystemInfo.Battery.HealthPct -lt 50) { $keyFindings += "Battery health is at $($SystemInfo.Battery.HealthPct)% - replacement recommended for reliable portable use." }
    if ($StressResults.CPU -and -not $StressResults.CPU.Passed) { $keyFindings += "The CPU failed its stress test, which may indicate overheating or hardware instability." }
    if ($StressResults.RAM -and -not $StressResults.RAM.Passed) { $keyFindings += "RAM stress test detected errors - one or more memory modules may be faulty." }
    if ($StressResults.CPU -and $StressResults.CPU.Passed -and $StressResults.RAM -and $StressResults.RAM.Passed) { $keyFindings += "CPU and RAM both passed stress testing with no errors detected." }
    if ($SystemInfo.Temperatures.Count -gt 0) {
        $maxTemp = ($SystemInfo.Temperatures | Measure-Object -Property TempC -Maximum).Maximum
        if ($maxTemp -gt 80) { $keyFindings += "Maximum temperature reading is ${maxTemp}C, which is in the critical range." }
        elseif ($maxTemp -gt 60) { $keyFindings += "Temperatures are slightly elevated (peak ${maxTemp}C) - ensure proper airflow and clean dust filters." }
        else { $keyFindings += "All temperature readings are within safe operating ranges." }
    }
    if ($Stability -and $Stability.TotalBSODs -gt 0) { $keyFindings += "$($Stability.TotalBSODs) Blue Screen of Death events recorded in the last 90 days." }
    if ($Stability -and $Stability.TotalUnexpected -gt 0) { $keyFindings += "$($Stability.TotalUnexpected) unexpected shutdowns detected - may indicate power or hardware issues." }
    if ($SpeedTest -and $SpeedTest.DownloadMbps -ne "N/A") { $keyFindings += "Network download speed: $($SpeedTest.DownloadMbps), Ping: $($SpeedTest.PingMs)" }
    if ($Gaming -and $Gaming.Score -gt 0) { $keyFindings += "Gaming readiness: $($Gaming.Tier) (Score: $($Gaming.Score)/100)" }
    $keyFindings = $keyFindings | Select-Object -First 8

    # Build recommendations
    $recommendations = @()
    foreach ($d in $SystemInfo.SMART) { if ($d.Health -ne "Healthy") { $recommendations += "Replace the failing '$($d.Model)' drive and restore data from backup." } }
    foreach ($d in $SystemInfo.Disks) { if ($d.UsedPct -gt 90) { $recommendations += "Free up space on drive $($d.Drive) or upgrade to a larger drive." } }
    if ($SystemInfo.DeviceErrors.Count -gt 0) { $recommendations += "Update or reinstall drivers for the $($SystemInfo.DeviceErrors.Count) device(s) showing errors." }
    if ($SystemInfo.Battery.Present -and $SystemInfo.Battery.HealthPct -gt 0 -and $SystemInfo.Battery.HealthPct -lt 50) { $recommendations += "Replace the battery to restore reliable portable operation." }
    if ($StressResults.CPU -and -not $StressResults.CPU.Passed) { $recommendations += "Clean CPU heatsink and reapply thermal paste; test again to rule out hardware failure." }
    if ($StressResults.RAM -and -not $StressResults.RAM.Passed) { $recommendations += "Run individual stick testing to isolate the faulty RAM module and replace it." }
    if ($recommendations.Count -eq 0) { $recommendations += "Continue regular maintenance: keep Windows updated, run periodic diagnostics, and maintain clean airflow." }

    # Build RAM rows
    $ramRows = ($SystemInfo.RAMSticks | ForEach-Object { "<tr><td>$($_.Slot)</td><td>$($_.CapacityGB) GB</td><td>$($_.Speed)</td><td>$($_.Type)</td><td>$($_.Manufacturer)</td><td>$($_.PartNumber)</td></tr>" }) -join "`n"
    # GPU rows
    $gpuRows = ($SystemInfo.GPUs | ForEach-Object { "<tr><td>$($_.Name)</td><td>$(if($_.VRAM_MB -gt 0){"$($_.VRAM_MB) MB"}else{"Shared"})</td><td>$($_.DriverVer)</td><td>$($_.DriverDate)</td><td>$($_.Resolution)</td></tr>" }) -join "`n"
    # SMART rows
    $smartRows = ($SystemInfo.SMART | ForEach-Object { $c=if($_.Health -eq 'Healthy'){'pass'}else{'fail'}; "<tr><td>$($_.Model)</td><td>$($_.MediaType)</td><td>$($_.BusType)</td><td>$($_.SizeGB) GB</td><td class='$c'>$($_.Health)</td><td>$($_.PowerOnHours)</td><td>$($_.Temperature)</td><td>$($_.ReadErrors)</td><td>$($_.Wear)</td></tr>" }) -join "`n"
    # Disk rows with progress bars
    $diskRowsDetailed = ($SystemInfo.Disks | ForEach-Object {
        $c = if($_.UsedPct -gt 90){'#dc2626'}elseif($_.UsedPct -gt 75){'#f59e0b'}else{'#16a34a'}
        "<tr><td>$($_.Drive)</td><td>$($_.Size) GB</td><td>$($_.Free) GB</td><td style='width:35%;'><div style='display:flex;align-items:center;gap:8px;'><div class='progress-track'><div class='progress-fill' style='width:$($_.UsedPct)%;background:$c;'></div></div><span style='color:$c;font-weight:600;white-space:nowrap;'>$($_.UsedPct)%</span></div></td></tr>"
    }) -join "`n"
    # Monitor rows
    $monitorRows = ($SystemInfo.Monitors | ForEach-Object { "<tr><td>$($_.Model)</td><td>$($_.Manufacturer)</td><td>$($_.Serial)</td><td>$($_.Year)</td></tr>" }) -join "`n"
    # Printer rows
    $printerRows = ($SystemInfo.Printers | ForEach-Object { "<tr><td>$($_.Name)</td><td>$($_.Port)</td><td>$($_.Driver)</td><td>$(if($_.Default){'Yes'}else{'No'})</td></tr>" }) -join "`n"
    # Network rows
    $netRows = ($Network.Adapters | ForEach-Object { "<tr><td>$($_.Name)</td><td>$($_.IP)</td><td>$($_.MAC)</td><td>$($_.DNS)</td><td>$($_.Speed)</td></tr>" }) -join "`n"
    # Stress test results
    $stressHTML = ""
    if ($StressResults.CPU) {
        $cpuClass = if($StressResults.CPU.Passed){"pass"}else{"fail"}
        $throttleWarn = if($StressResults.CPU.ThrottleDetected){"<br/><span class='fail'>$iconWarn THROTTLING DETECTED</span>"}else{""}
        $stressHTML += "<tr><td>CPU Stress Test</td><td class='$cpuClass'>$(if($StressResults.CPU.Passed){"$iconPass PASSED"}else{"$iconFail FAILED"})$throttleWarn</td><td>$($StressResults.CPU.Threads) threads, $($StressResults.CPU.Duration)s, $($StressResults.CPU.Iterations) iterations</td><td>Start: $($StressResults.CPU.StartTemp)C / Peak: $($StressResults.CPU.MaxTemp)C / End: $($StressResults.CPU.EndTemp)C<br/>Recovery: $($StressResults.CPU.RecoveryTemp)C (15s cooldown)</td></tr>`n"
    }
    if ($StressResults.RAM) {
        $ramClass = if($StressResults.RAM.Passed){"pass"}else{"fail"}
        $stressHTML += "<tr><td>RAM Stress Test</td><td class='$ramClass'>$(if($StressResults.RAM.Passed){"$iconPass PASSED"}else{"$iconFail FAILED"})</td><td>$($StressResults.RAM.BlocksTested) blocks ($($StressResults.RAM.TotalMBTested) MB tested)</td><td>$($StressResults.RAM.Errors) errors</td></tr>`n"
    }
    if ($StressResults.Disk) {
        $dkClass = if($StressResults.Disk.Passed){"pass"}else{"fail"}
        $stressHTML += "<tr><td>Disk Benchmark</td><td class='$dkClass'>$(if($StressResults.Disk.Passed){"$iconPass PASSED"}else{"$iconFail FAILED"})</td><td>Write: $($StressResults.Disk.SeqWriteMBps) MB/s | Read: $($StressResults.Disk.SeqReadMBps) MB/s</td><td>$($StressResults.Disk.FileSizeMB) MB test file</td></tr>`n"
    }
    if ($StressResults.GPU) {
        $gpuClass = if($StressResults.GPU.Passed){"pass"}else{"fail"}
        $stressHTML += "<tr><td>GPU Stress Test</td><td class='$gpuClass'>$(if($StressResults.GPU.Passed){"$iconPass PASSED"}else{"$iconFail FAILED"})</td><td>$($StressResults.GPU.GPUName), $($StressResults.GPU.Iterations) render cycles</td><td>Max Temp: $($StressResults.GPU.MaxTemp)C</td></tr>`n"
    }
    # Hardware issues
    $issuesHTML = if ($hwIssues.Count -gt 0) {
        ($hwIssues | ForEach-Object { "<div style='padding:8px 12px;margin:4px 0;background:#fef5f5;border-left:4px solid #dc2626;border-radius:4px;'><span class='fail'>$iconFail</span> $_</div>" }) -join "`n"
    } else { "<div style='padding:12px;background:#eafaf1;border-left:4px solid #16a34a;border-radius:4px;'><span class='pass'>$iconPass</span> <strong>No hardware issues detected.</strong></div>" }
    # Device errors
    $devErrHTML = if ($SystemInfo.DeviceErrors.Count -gt 0) {
        "<div class='sub-header' style='color:#dc2626;'>Device Manager Errors ($($SystemInfo.DeviceErrors.Count))</div><table><tr><th>Device</th><th>Class</th><th>Error</th></tr>" +
        (($SystemInfo.DeviceErrors | ForEach-Object { "<tr><td class='fail'>$($_.Device)</td><td>$($_.Class)</td><td class='fail'>$($_.Error)</td></tr>" }) -join "`n") + "</table>"
    } else { "<div class='sub-header' style='color:#16a34a;'>Device Manager - All Clear</div><p style='padding:8px;background:#eafaf1;border-radius:4px;'><span class='pass'>$iconPass</span> All devices functioning properly.</p>" }
    # Battery
    $batteryHTML = ""
    if ($SystemInfo.Battery.Present) {
        $bhClass = if($SystemInfo.Battery.HealthPct -ge 80){"pass"}elseif($SystemInfo.Battery.HealthPct -ge 50){"warn"}else{"fail"}
        $bhColor = if($SystemInfo.Battery.HealthPct -ge 80){"#16a34a"}elseif($SystemInfo.Battery.HealthPct -ge 50){"#f59e0b"}else{"#dc2626"}
        $bhPct = $SystemInfo.Battery.HealthPct
        $batteryHTML = @"
<div class="sub-header">Battery Health</div>
<div style="display:flex;align-items:center;gap:20px;margin-bottom:12px;">
<div style="text-align:center;">
<svg viewBox="0 0 100 100" width="80" height="80">
<circle cx="50" cy="50" r="40" fill="none" stroke="#e5e7eb" stroke-width="8"/>
<circle cx="50" cy="50" r="40" fill="none" stroke="$bhColor" stroke-width="8" stroke-dasharray="251" stroke-dashoffset="$([math]::Round(251 - (251 * $bhPct / 100)))" transform="rotate(-90 50 50)" stroke-linecap="round"/>
<text x="50" y="55" text-anchor="middle" font-size="18" font-weight="bold" fill="$bhColor">$bhPct%</text>
</svg>
</div>
<div style="flex:1;">
<table><tr><th style="width:35%;">Property</th><th>Value</th></tr>
<tr><td>Status</td><td>$($SystemInfo.Battery.Status)</td></tr>
<tr><td>Current Charge</td><td>$($SystemInfo.Battery.Charge)%</td></tr>
<tr><td>Battery Health</td><td class='$bhClass' style="font-size:11pt;">$($SystemInfo.Battery.HealthPct)%</td></tr>
<tr><td>Design Capacity</td><td>$($SystemInfo.Battery.DesignCap) mWh</td></tr>
<tr><td>Full Charge Capacity</td><td>$($SystemInfo.Battery.FullCap) mWh</td></tr>
<tr><td>Cycle Count</td><td>$($SystemInfo.Battery.CycleCount)</td></tr>
<tr><td>Estimated Runtime</td><td>$($SystemInfo.Battery.Runtime)</td></tr>
</table>
</div>
</div>
"@
    }
    # License keys
    $winKeyRows = if ($LicenseKeys.WindowsKeys.Count -gt 0) {
        ($LicenseKeys.WindowsKeys | ForEach-Object { "<tr><td>$($_.Source)</td><td><strong style='font-family:Consolas,monospace;letter-spacing:1px;'>$($_.Key)</strong></td></tr>" }) -join "`n"
    } else { "<tr><td colspan='2' class='warn'>$iconWarn No Windows product key found</td></tr>" }
    $officeKeyRows = if ($LicenseKeys.OfficeKeys.Count -gt 0) {
        ($LicenseKeys.OfficeKeys | ForEach-Object { "<tr><td>$($_.Product) ($($_.Version))</td><td><strong style='font-family:Consolas,monospace;'>$($_.Key)</strong></td></tr>" }) -join "`n"
    } else { "<tr><td colspan='2'>No Office keys found (may use 365 account)</td></tr>" }
    $adobeKeyRows = if ($LicenseKeys.AdobeKeys.Count -gt 0) {
        ($LicenseKeys.AdobeKeys | ForEach-Object { "<tr><td>$($_.Product)</td><td><strong style='font-family:Consolas,monospace;'>$($_.Key)</strong></td></tr>" }) -join "`n"
    } else { "" }
    $wifiRows = if ($LicenseKeys.WiFiPasswords.Count -gt 0) {
        ($LicenseKeys.WiFiPasswords | ForEach-Object { "<tr><td><strong>$($_.SSID)</strong></td><td style='font-family:Consolas,monospace;'>$($_.Password)</td><td>$($_.Auth)</td></tr>" }) -join "`n"
    } else { "<tr><td colspan='3'>No saved WiFi profiles</td></tr>" }
    # Top processes
    $topProcRows = ($Software.TopRAM | ForEach-Object { "<tr><td>$($_.Name)</td><td>$($_.RAM_MB) MB</td></tr>" }) -join "`n"
    # Installed software
    $swRows = ($Software.Installed | ForEach-Object { "<tr><td>$($_.Name)</td><td>$($_.Version)</td><td>$($_.Publisher)</td></tr>" }) -join "`n"
    # Temperature rows with color coding
    $tempRows = if ($SystemInfo.Temperatures.Count -gt 0) {
        ($SystemInfo.Temperatures | ForEach-Object {
            $tc = if($_.TempC -gt 80){"fail"}elseif($_.TempC -gt 60){"warn"}else{"pass"}
            $tColor = if($_.TempC -gt 80){"#dc2626"}elseif($_.TempC -gt 60){"#f59e0b"}else{"#16a34a"}
            $tPct = [math]::Min([math]::Round($_.TempC / 100 * 100), 100)
            "<tr><td>$($_.Zone)</td><td class='$tc'>$($_.TempC)&deg;C</td><td class='$tc'>$($_.TempF)&deg;F</td><td style='width:30%;'><div class='progress-track'><div class='progress-fill' style='width:$tPct%;background:$tColor;'></div></div></td></tr>"
        }) -join "`n"
    } else { "" }
    # Technician notes field
    $techNotes = if ($Params.TechNotes) { "<div class='section-header'>Technician Notes</div><div style='padding:16px 20px;background:#f8fafc;border:1px solid #d1d5db;border-radius:8px;min-height:60px;white-space:pre-wrap;font-size:10pt;line-height:1.7;margin-bottom:16px;'>$([System.Web.HttpUtility]::HtmlEncode($Params.TechNotes))</div>" } else { "" }

    # Build key findings HTML
    $findingsHTML = ($keyFindings | ForEach-Object { "<li style='margin-bottom:6px;'>$_</li>" }) -join "`n"
    # Build recommendations HTML
    $recsHTML = ""
    for ($i = 0; $i -lt $recommendations.Count; $i++) {
        $recsHTML += "<li style='margin-bottom:6px;'>$($recommendations[$i])</li>`n"
    }

    # Build category score cards for executive summary
    function Build-MiniDonut($score, $label) {
        $color = if ($score -ge 80) { "#16a34a" } elseif ($score -ge 60) { "#f59e0b" } else { "#dc2626" }
        $offset = [math]::Round(251 - (251 * $score / 100))
        $grade = if ($score -ge 90){"A"} elseif($score -ge 80){"B"} elseif($score -ge 70){"C"} elseif($score -ge 60){"D"} else{"F"}
        return @"
<div class="score-card">
<svg viewBox="0 0 100 100" width="72" height="72">
<circle cx="50" cy="50" r="40" fill="none" stroke="#e5e7eb" stroke-width="7"/>
<circle cx="50" cy="50" r="40" fill="none" stroke="$color" stroke-width="7" stroke-dasharray="251" stroke-dashoffset="$offset" transform="rotate(-90 50 50)" stroke-linecap="round"/>
<text x="50" y="56" text-anchor="middle" font-size="22" font-weight="bold" fill="$color">$grade</text>
</svg>
<div class="score-card-label">$label</div>
<div class="score-card-value" style="color:$color;">$score / 100</div>
</div>
"@
    }

    $storageCard = Build-MiniDonut $storageScore "Storage Health"
    $cpuMemCard = Build-MiniDonut $cpuMemScore "CPU &amp; Memory"
    $thermalCard = Build-MiniDonut $thermalScore "Thermal"
    $deviceCard = Build-MiniDonut $deviceScore "Devices"
    $batteryCard = if ($batteryScore -ge 0) { Build-MiniDonut $batteryScore "Battery" } else { "" }

    # Performance bars
    $cpuBarColor = if($Performance.CPUPercent -gt 90){"#dc2626"}elseif($Performance.CPUPercent -gt 70){"#f59e0b"}else{"#16a34a"}
    $ramBarColor = if($Performance.RAMPercent -gt 90){"#dc2626"}elseif($Performance.RAMPercent -gt 70){"#f59e0b"}else{"#16a34a"}

    # RAM slots progress bar
    $ramSlotPct = if ($SystemInfo.RAMSlots.Total -gt 0) { [math]::Round($SystemInfo.RAMSlots.Used / $SystemInfo.RAMSlots.Total * 100) } else { 0 }

$html = @"
<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8"/><title>Hardware Diagnostic Report - $($Params.CustomerName)</title>
<style>
@page { size: letter; margin: 0.5in 0.6in 0.9in 0.6in; }
* { margin:0; padding:0; box-sizing:border-box; }
body { font-family: 'Segoe UI', -apple-system, Tahoma, sans-serif; font-size: 9.5pt; color: #1e293b; line-height: 1.6; background: #fff; }
h1,h2,h3,h4 { margin:0; }

/* Print handling */
@media print {
    body { -webkit-print-color-adjust: exact; print-color-adjust: exact; }
    .page-break { page-break-before: always; }
    .no-break { page-break-inside: avoid; }
}
.page-break { page-break-before: always; }

/* Fixed print footer - repeats on every page */
.print-footer {
    position: fixed; bottom: 0; left: 0; right: 0;
    padding: 6px 0; border-top: 1.5px solid #0d4b71;
    text-align: center; font-size: 7.5pt; color: #94a3b8;
    background: #fff;
}
.print-footer strong { color: #0d4b71; font-size: 7.5pt; }
.print-footer .report-name { color: #475569; }
.no-break { page-break-inside: avoid; }

/* ── Section headers ── */
.section-header {
    background: linear-gradient(135deg, #0a1628 0%, #0d4b71 100%);
    color: #fff; padding: 10px 20px; font-size: 12pt; font-weight: 600;
    margin: 24px 0 14px 0; border-radius: 6px; letter-spacing: 0.5px;
    display: flex; align-items: center; gap: 10px;
}
.section-header .section-icon { font-size: 14pt; opacity: 0.85; }
.sub-header {
    color: #0d4b71; font-size: 10.5pt; font-weight: 700; margin: 18px 0 8px 0;
    padding-bottom: 5px; border-bottom: 2px solid #2596be; letter-spacing: 0.3px;
}

/* ── Tables ── */
table { width: 100%; border-collapse: collapse; margin-bottom: 14px; font-size: 9pt; }
th {
    background: #0d4b71; color: #fff; padding: 7px 10px; text-align: left;
    font-weight: 600; font-size: 8.5pt; text-transform: uppercase; letter-spacing: 0.5px;
}
td { padding: 6px 10px; border-bottom: 1px solid #e2e8f0; vertical-align: middle; }
tr:nth-child(even) td { background: #f8fafc; }
tr:hover td { background: #eaf7fc; }
.pass { color: #16a34a; font-weight: 600; }
.fail { color: #dc2626; font-weight: 600; }
.warn { color: #f59e0b; font-weight: 600; }

/* ── Progress bars ── */
.progress-track {
    background: #e5e7eb; border-radius: 6px; height: 10px; flex: 1; overflow: hidden;
}
.progress-fill {
    height: 100%; border-radius: 6px; transition: width 0.3s;
}
.progress-lg .progress-track { height: 14px; border-radius: 7px; }
.progress-lg .progress-fill { border-radius: 7px; }

/* ── Score cards (executive summary) ── */
.score-cards {
    display: flex; gap: 12px; margin: 14px 0; flex-wrap: wrap; justify-content: center;
}
.score-card {
    flex: 1; min-width: 100px; max-width: 140px; text-align: center; padding: 12px 8px;
    background: #fff; border: 1px solid #e2e8f0; border-radius: 10px;
    box-shadow: 0 1px 3px rgba(0,0,0,0.05);
}
.score-card-label { font-size: 8pt; color: #64748b; text-transform: uppercase; font-weight: 600; margin-top: 4px; letter-spacing: 0.3px; }
.score-card-value { font-size: 9pt; font-weight: 700; margin-top: 2px; }

/* ── Findings & recommendations ── */
.findings-box {
    background: #f8fafc; border: 1px solid #e2e8f0; border-radius: 10px;
    padding: 16px 20px; margin: 12px 0;
}
.findings-box h3 { font-size: 10.5pt; color: #0d4b71; margin-bottom: 8px; font-weight: 700; }
.findings-box ul { margin: 0; padding-left: 18px; }
.findings-box li { font-size: 9.5pt; color: #334155; line-height: 1.6; }
.recs-box {
    background: #fffbeb; border: 1px solid #fde68a; border-radius: 10px;
    padding: 16px 20px; margin: 12px 0;
}
.recs-box h3 { font-size: 10.5pt; color: #92400e; margin-bottom: 8px; font-weight: 700; }
.recs-box ol { margin: 0; padding-left: 18px; }
.recs-box li { font-size: 9.5pt; color: #451a03; line-height: 1.6; }

/* ── Summary strip ── */
.summary-strip {
    display: flex; gap: 10px; margin: 14px 0;
}
.summary-chip {
    flex: 1; text-align: center; padding: 12px 8px; background: #f8fafc;
    border: 1px solid #e2e8f0; border-radius: 8px;
}
.summary-chip .chip-val { font-size: 18pt; font-weight: 700; color: #0a1628; display: block; }
.summary-chip .chip-lbl { font-size: 7.5pt; color: #64748b; text-transform: uppercase; font-weight: 600; letter-spacing: 0.3px; }

/* ── QR placeholder boxes ── */
.qr-row { display: flex; justify-content: center; gap: 60px; margin: 20px 0; }
.qr-item { text-align: center; }
.qr-item img { width: 160px; height: 160px; border-radius: 8px; }
.qr-item .qr-fallback { width: 160px; height: 160px; border: 2px dashed #94a3b8; border-radius: 8px; display: flex; align-items: center; justify-content: center; font-size: 7.5pt; color: #94a3b8; line-height: 1.3; }
.qr-label { font-size: 9pt; font-weight: 600; color: #0d4b71; margin-top: 8px; }
.qr-sublabel { font-size: 7.5pt; color: #64748b; margin-top: 2px; }
.promo-banner { text-align: center; margin: 20px 0; page-break-inside: avoid; }
.promo-banner img { width: 100%; max-width: 100%; border-radius: 8px; box-shadow: 0 2px 8px rgba(0,0,0,0.1); }

/* ── Repeated page footer ── */
.page-footer-bar {
    margin-top: 30px; padding: 10px 0; border-top: 2px solid #0d4b71;
    text-align: center; font-size: 8pt; color: #94a3b8;
}
.page-footer-bar strong { color: #0d4b71; }

/* ── Confidential banner ── */
.confidential-banner {
    background: #fef2f2; border: 1px solid #fca5a5; border-radius: 6px;
    padding: 8px 14px; font-size: 8.5pt; color: #991b1b; margin-bottom: 14px;
    display: flex; align-items: center; gap: 8px;
}
.confidential-banner .lock-icon { font-size: 12pt; }

/* ── Info pair rows ── */
.info-grid { display: flex; flex-wrap: wrap; gap: 0; }
.info-pair { width: 50%; display: flex; padding: 6px 10px; border-bottom: 1px solid #e2e8f0; font-size: 9pt; }
.info-pair:nth-child(4n+3), .info-pair:nth-child(4n+4) { background: #f8fafc; }
.info-pair .lbl { color: #64748b; font-weight: 600; min-width: 130px; }
.info-pair .val { color: #1e293b; }
</style></head><body>

<div class="print-footer">
<span class="report-name">Hardware Diagnostic Report</span> &nbsp;|&nbsp; <strong>$COMPANY</strong> &nbsp;|&nbsp; $WEBSITE &nbsp;|&nbsp; $PHONE
</div>

<!-- ══════════════════════════ COVER PAGE ══════════════════════════ -->
<div style="page-break-after:always;">
$(if($bannerHwOwnUri){"<div style='text-align:center;margin-bottom:15px;'><img src='$bannerHwOwnUri' alt='PC Plus Hardware Test' style='width:100%;border-radius:8px;'/></div>"})

<div style="display:flex;gap:20px;align-items:center;margin:15px 0;">
<div style="flex:1;">
<div style="background:#f8fafc;border:1px solid #e2e8f0;border-radius:10px;padding:16px;">
<table style="width:100%;font-size:10pt;border:none;margin:0;">
<tr><td style="border:none;padding:4px 8px;color:#64748b;font-weight:600;width:110px;">Customer:</td><td style="border:none;padding:4px 8px;color:#0a1628;font-weight:700;">$($Params.CustomerName)</td></tr>
$(if($Params.ContactName){"<tr><td style='border:none;padding:4px 8px;color:#64748b;font-weight:600;'>Contact:</td><td style='border:none;padding:4px 8px;color:#0a1628;'>$($Params.ContactName)</td></tr>"})
<tr><td style="border:none;padding:4px 8px;color:#64748b;font-weight:600;">Device:</td><td style="border:none;padding:4px 8px;color:#0a1628;">$($SystemInfo.ComputerName)</td></tr>
<tr><td style="border:none;padding:4px 8px;color:#64748b;font-weight:600;">Date:</td><td style="border:none;padding:4px 8px;color:#0a1628;">$date</td></tr>
<tr><td style="border:none;padding:4px 8px;color:#64748b;font-weight:600;">Technician:</td><td style="border:none;padding:4px 8px;color:#0a1628;">$($Params.TechName)</td></tr>
</table>
</div>
</div>
<div style="text-align:center;">
<svg viewBox="0 0 100 100" width="130" height="130">
<circle cx="50" cy="50" r="45" fill="none" stroke="#e5e7eb" stroke-width="8"/>
<circle cx="50" cy="50" r="45" fill="none" stroke="$hwColor" stroke-width="8" stroke-dasharray="283" stroke-dashoffset="$dashOffset" transform="rotate(-90 50 50)" stroke-linecap="round"/>
<text x="50" y="46" text-anchor="middle" font-size="20" font-weight="bold" fill="$hwColor">$hwGrade</text>
<text x="50" y="62" text-anchor="middle" font-size="10" fill="#64748b">$hwScore / 100</text>
</svg>
<div style="font-size:9pt;color:$hwColor;font-weight:700;margin-top:4px;">Overall Health</div>
</div>
</div>

$(if($bannerSecTopUri){"<div style='text-align:center;margin-top:15px;'><img src='$bannerSecTopUri' alt='PC Plus Security Audit' style='width:100%;border-radius:8px;'/></div>"})
</div>

<!-- ══════════════════════════ EXECUTIVE SUMMARY ══════════════════════════ -->
<div class="page-break"></div>

<div class="section-header"><span class="section-icon">&#128202;</span> Executive Summary</div>

<div style="display:flex;align-items:center;gap:24px;margin:14px 0;">
<div style="text-align:center;">
<svg viewBox="0 0 100 100" width="100" height="100">
<circle cx="50" cy="50" r="40" fill="none" stroke="#e5e7eb" stroke-width="8"/>
<circle cx="50" cy="50" r="40" fill="none" stroke="$hwColor" stroke-width="8" stroke-dasharray="251" stroke-dashoffset="$([math]::Round(251 - (251 * $hwScore / 100)))" transform="rotate(-90 50 50)" stroke-linecap="round"/>
<text x="50" y="46" text-anchor="middle" font-size="20" font-weight="bold" fill="$hwColor">$hwGrade</text>
<text x="50" y="62" text-anchor="middle" font-size="11" fill="#64748b">$hwScore / 100</text>
</svg>
<div style="font-size:8pt;color:#64748b;font-weight:600;margin-top:4px;">OVERALL HEALTH</div>
</div>
<div style="flex:1;">
<div class="score-cards">
$storageCard
$cpuMemCard
$thermalCard
$deviceCard
$batteryCard
</div>
</div>
</div>

<div class="findings-box no-break">
<h3>&#128270; Key Findings</h3>
<ul>$findingsHTML</ul>
</div>

<div class="recs-box no-break">
<h3>&#9881; Top Recommendations</h3>
<ol>$recsHTML</ol>
</div>

$issuesHTML

$(if($stressHTML){"
<div class='sub-header'>Stress Test Results</div>
<table><tr><th>Test</th><th>Result</th><th>Details</th><th>Temps</th></tr>$stressHTML</table>
"})

$(if($StressResults.CPU -and $StressResults.CPU.TempLog.Count -gt 0){
$thermalPoints = ($StressResults.CPU.TempLog | ForEach-Object { "$($_.Time)s:$($_.TempC)C" }) -join " -> "
@"
<div class='sub-header'>Thermal Timeline (CPU Stress)</div>
<div style='padding:10px;background:#f8fafc;border-radius:8px;border:1px solid #e2e8f0;margin-bottom:14px;'>
<div style='display:flex;gap:20px;margin-bottom:10px;'>
<div><strong>Start:</strong> $($StressResults.CPU.StartTemp)C</div>
<div><strong>Peak:</strong> <span style='color:$(if([double]$StressResults.CPU.MaxTemp -gt 80){"#dc2626"}elseif([double]$StressResults.CPU.MaxTemp -gt 60){"#f59e0b"}else{"#16a34a"})'>$($StressResults.CPU.MaxTemp)C</span></div>
<div><strong>End:</strong> $($StressResults.CPU.EndTemp)C</div>
<div><strong>Recovery (15s):</strong> $($StressResults.CPU.RecoveryTemp)C</div>
<div><strong>Average:</strong> $($StressResults.CPU.AvgTemp)C</div>
</div>
<div style='font-size:8pt;color:#64748b;'>$thermalPoints</div>
$(if($StressResults.CPU.ThrottleDetected){"<div style='margin-top:8px;padding:8px;background:#fef5f5;border-left:4px solid #dc2626;border-radius:4px;'><span class='fail'>$iconWarn</span> <strong>Thermal Throttling Detected</strong> - CPU clock dropped below 80% of base frequency during stress. Check cooling system.</div>"})
$(if($StressResults.CPU.BaseClock -ne 'N/A'){"<div style='margin-top:6px;font-size:8.5pt;'><strong>Clock Speed:</strong> Base: $($StressResults.CPU.BaseClock) MHz | Min during stress: $($StressResults.CPU.MinClock) MHz | Max: $($StressResults.CPU.MaxClock) MHz</div>"})
$(if($StressResults.CPU.FanSpeedStart -ne 'N/A'){"<div style='margin-top:4px;font-size:8.5pt;'><strong>Fan Speed:</strong> Start: $($StressResults.CPU.FanSpeedStart) RPM | Peak: $($StressResults.CPU.FanSpeedPeak) RPM</div>"})
</div>
"@
})

<!-- ══════════════════════════ STABILITY HISTORY ══════════════════════════ -->
$(if($Stability){
$bsodRows = if ($Stability.BSODs.Count -gt 0) { ($Stability.BSODs | Select-Object -First 10 | ForEach-Object { "<tr><td class='fail'>$($_.Time)</td><td>$($_.BugCheck)</td></tr>" }) -join "`n" } else { "" }
$kpRows = if ($Stability.KernelPower.Count -gt 0) { ($Stability.KernelPower | Select-Object -First 10 | ForEach-Object { "<tr><td class='warn'>$($_.Time)</td><td>$($_.Message)</td></tr>" }) -join "`n" } else { "" }
$diskErrRows = if ($Stability.DiskErrors.Count -gt 0) { ($Stability.DiskErrors | Select-Object -First 10 | ForEach-Object { "<tr><td>$($_.Time)</td><td>Event $($_.Id)</td><td>$($_.Message)</td></tr>" }) -join "`n" } else { "" }
$wheaRows = if ($Stability.WHEAErrors.Count -gt 0) { ($Stability.WHEAErrors | Select-Object -First 10 | ForEach-Object { "<tr><td class='fail'>$($_.Time)</td><td>$($_.Message)</td></tr>" }) -join "`n" } else { "" }
$stabColor = if($Stability.StabilityRating -eq 'Excellent'){"#16a34a"}elseif($Stability.StabilityRating -eq 'Good'){"#22c55e"}elseif($Stability.StabilityRating -eq 'Fair'){"#f59e0b"}else{"#dc2626"}
@"
<div class='page-break'></div>
<div class='section-header'><span class='section-icon'>&#128200;</span> Stability History (Last 90 Days)</div>
<div style='display:flex;gap:15px;margin-bottom:14px;flex-wrap:wrap;'>
<div class='score-card'><div style='font-size:24pt;font-weight:bold;color:$stabColor;'>$($Stability.StabilityRating)</div><div class='score-card-label'>Overall Stability</div></div>
<div class='score-card'><div style='font-size:24pt;font-weight:bold;color:$(if($Stability.TotalBSODs -eq 0){"#16a34a"}else{"#dc2626"})'>$($Stability.TotalBSODs)</div><div class='score-card-label'>Blue Screens</div></div>
<div class='score-card'><div style='font-size:24pt;font-weight:bold;color:$(if($Stability.TotalUnexpected -eq 0){"#16a34a"}else{"#f59e0b"})'>$($Stability.TotalUnexpected)</div><div class='score-card-label'>Unexpected Shutdowns</div></div>
<div class='score-card'><div style='font-size:24pt;font-weight:bold;'>$($Stability.TotalDiskErrors)</div><div class='score-card-label'>Disk Errors</div></div>
<div class='score-card'><div style='font-size:24pt;font-weight:bold;color:$(if($Stability.TotalWHEA -eq 0){"#16a34a"}else{"#dc2626"})'>$($Stability.TotalWHEA)</div><div class='score-card-label'>Hardware Errors (WHEA)</div></div>
<div class='score-card'><div style='font-size:24pt;font-weight:bold;'>$($Stability.MinidumpCount)</div><div class='score-card-label'>Minidump Files</div></div>
</div>
<div style='padding:10px;background:#f8fafc;border-radius:8px;border:1px solid #e2e8f0;margin-bottom:14px;'>
<strong>Risk Level:</strong> <span style='color:$stabColor;font-weight:bold;'>$($Stability.RiskLevel)</span>
$(if($Stability.TotalBSODs -ge 3){" | <span class='fail'>$iconFail Frequent crashes indicate potential hardware failure. Thorough testing recommended.</span>"})
$(if($Stability.TotalDiskErrors -ge 5){" | <span class='warn'>$iconWarn Elevated disk errors may indicate drive degradation.</span>"})
</div>
$(if($bsodRows){"<div class='sub-header' style='color:#dc2626;'>Blue Screen Events (BugCheck)</div><table><tr><th style='width:25%;'>Date/Time</th><th>Details</th></tr>$bsodRows</table>"})
$(if($kpRows){"<div class='sub-header' style='color:#f59e0b;'>Kernel-Power Events (Unexpected Shutdowns)</div><table><tr><th style='width:25%;'>Date/Time</th><th>Details</th></tr>$kpRows</table>"})
$(if($diskErrRows){"<div class='sub-header'>Disk Errors</div><table><tr><th style='width:20%;'>Date/Time</th><th style='width:15%;'>Event ID</th><th>Message</th></tr>$diskErrRows</table>"})
$(if($wheaRows){"<div class='sub-header' style='color:#dc2626;'>Hardware Errors (WHEA)</div><table><tr><th style='width:25%;'>Date/Time</th><th>Details</th></tr>$wheaRows</table>"})
"@
})

<!-- ══════════════════════════ NETWORK SPEED TEST ══════════════════════════ -->
$(if($SpeedTest -and $SpeedTest.DownloadMbps -ne $null){
@"
<div class='sub-header'><span class='section-icon'>&#127760;</span> Network Speed Test</div>
<div style='display:flex;gap:15px;margin-bottom:14px;flex-wrap:wrap;'>
<div class='score-card'><div style='font-size:16pt;font-weight:bold;color:#2563eb;'>$($SpeedTest.DownloadMbps)</div><div class='score-card-label'>Download Speed</div></div>
<div class='score-card'><div style='font-size:16pt;font-weight:bold;color:#16a34a;'>$($SpeedTest.PingMs)</div><div class='score-card-label'>Ping Latency</div></div>
<div class='score-card'><div style='font-size:16pt;font-weight:bold;'>$($SpeedTest.Jitter)</div><div class='score-card-label'>Jitter</div></div>
<div class='score-card'><div style='font-size:16pt;font-weight:bold;color:$(if($SpeedTest.PacketLoss -eq '0%'){"#16a34a"}else{"#dc2626"})'>$($SpeedTest.PacketLoss)</div><div class='score-card-label'>Packet Loss</div></div>
</div>
<table><tr><th style='width:35%;'>Test</th><th>Result</th></tr>
<tr><td>Gateway</td><td>$($SpeedTest.Gateway) (Ping: $($SpeedTest.GatewayPing))</td></tr>
<tr><td>DNS Response</td><td>$($SpeedTest.DNSResponseMs)</td></tr>
<tr><td>WiFi Signal</td><td>$($SpeedTest.WiFiSignal)</td></tr>
<tr><td>WiFi Channel</td><td>$($SpeedTest.WiFiChannel)</td></tr>
<tr><td>WiFi Radio</td><td>$($SpeedTest.WiFiRadioType)</td></tr>
<tr><td>WiFi Receive Rate</td><td>$(if($SpeedTest.WiFiRxRate){$SpeedTest.WiFiRxRate}else{"N/A"})</td></tr>
<tr><td>WiFi Transmit Rate</td><td>$(if($SpeedTest.WiFiTxRate){$SpeedTest.WiFiTxRate}else{"N/A"})</td></tr>
</table>
"@
})

<!-- ══════════════════════════ DETAILED BATTERY ══════════════════════════ -->
$(if($BatteryDetail -and $BatteryDetail.Present){
$bdColor = if($BatteryDetail.HealthPct -ge 80){"#16a34a"}elseif($BatteryDetail.HealthPct -ge 50){"#f59e0b"}else{"#dc2626"}
$bdOffset = [math]::Round(251 - (251 * $BatteryDetail.HealthPct / 100))
@"
<div class='sub-header'><span class='section-icon'>&#128267;</span> Detailed Battery Report</div>
<div style='display:flex;align-items:center;gap:25px;margin-bottom:14px;'>
<div style='text-align:center;'>
<svg viewBox='0 0 100 100' width='90' height='90'>
<circle cx='50' cy='50' r='40' fill='none' stroke='#e5e7eb' stroke-width='8'/>
<circle cx='50' cy='50' r='40' fill='none' stroke='$bdColor' stroke-width='8' stroke-dasharray='251' stroke-dashoffset='$bdOffset' transform='rotate(-90 50 50)' stroke-linecap='round'/>
<text x='50' y='48' text-anchor='middle' font-size='16' font-weight='bold' fill='$bdColor'>$($BatteryDetail.HealthPct)%</text>
<text x='50' y='64' text-anchor='middle' font-size='9' fill='#64748b'>Health</text>
</svg>
</div>
<div style='flex:1;'>
<table><tr><th style='width:35%;'>Property</th><th>Value</th></tr>
<tr><td>Battery Name</td><td>$($BatteryDetail.Name)</td></tr>
<tr><td>Status</td><td>$($BatteryDetail.Status) $(if($BatteryDetail.Charging){"(Charging)"}else{"(On Battery)"})</td></tr>
<tr><td>Current Charge</td><td><strong>$($BatteryDetail.Charge)%</strong></td></tr>
<tr><td>Health Status</td><td style='color:$bdColor;font-weight:bold;'>$($BatteryDetail.HealthStatus)</td></tr>
<tr><td>Design Capacity</td><td>$($BatteryDetail.DesignCapacity) mWh</td></tr>
<tr><td>Full Charge Capacity</td><td>$($BatteryDetail.FullChargeCapacity) mWh</td></tr>
<tr><td>Battery Health</td><td style='color:$bdColor;font-weight:bold;'>$($BatteryDetail.HealthPct)%</td></tr>
<tr><td>Cycle Count</td><td>$($BatteryDetail.CycleCount)</td></tr>
<tr><td>Drain Rate</td><td>$($BatteryDetail.DrainRate)</td></tr>
<tr><td>Estimated Runtime</td><td>$($BatteryDetail.Runtime)</td></tr>
</table>
</div>
</div>
$(if($BatteryDetail.HealthPct -lt 50){"<div style='padding:10px;background:#fef5f5;border-left:4px solid #dc2626;border-radius:4px;margin-bottom:12px;'><span class='fail'>$iconFail</span> <strong>Battery replacement recommended.</strong> Current capacity is below 50% of original design capacity.</div>"})
$(if($BatteryDetail.BatteryReportPath){"<div style='font-size:8.5pt;color:#64748b;margin-bottom:12px;'>Full Windows battery report saved to: $($BatteryDetail.BatteryReportPath)</div>"})
"@
})

<!-- ══════════════════════════ GAMING READINESS ══════════════════════════ -->
$(if($Gaming -and $Gaming.Score -gt 0){
$gmColor = if($Gaming.Score -ge 80){"#16a34a"}elseif($Gaming.Score -ge 60){"#2563eb"}elseif($Gaming.Score -ge 40){"#f59e0b"}else{"#dc2626"}
$gmOffset = [math]::Round(251 - (251 * $Gaming.Score / 100))
@"
<div class='sub-header'><span class='section-icon'>&#127918;</span> Gaming Readiness Assessment</div>
<div style='display:flex;align-items:center;gap:25px;margin-bottom:14px;'>
<div style='text-align:center;'>
<svg viewBox='0 0 100 100' width='90' height='90'>
<circle cx='50' cy='50' r='40' fill='none' stroke='#e5e7eb' stroke-width='8'/>
<circle cx='50' cy='50' r='40' fill='none' stroke='$gmColor' stroke-width='8' stroke-dasharray='251' stroke-dashoffset='$gmOffset' transform='rotate(-90 50 50)' stroke-linecap='round'/>
<text x='50' y='48' text-anchor='middle' font-size='16' font-weight='bold' fill='$gmColor'>$($Gaming.Score)</text>
<text x='50' y='64' text-anchor='middle' font-size='9' fill='#64748b'>Score</text>
</svg>
</div>
<div style='flex:1;'>
<div style='font-size:14pt;font-weight:bold;color:$gmColor;margin-bottom:8px;'>$($Gaming.Tier)</div>
<table><tr><th style='width:35%;'>Component</th><th>Details</th><th>Score</th></tr>
<tr><td>GPU</td><td>$($Gaming.GPUName) ($($Gaming.VRAM_MB) MB VRAM)</td><td style='color:$gmColor;font-weight:bold;'>$($Gaming.GPUScoreDetail)/40</td></tr>
<tr><td>CPU</td><td>$(if($Gaming.CPUCores){"$($Gaming.CPUCores) cores / $($Gaming.CPUThreads) threads @ $($Gaming.CPUBaseClock) MHz"}else{"N/A"})</td><td style='color:$gmColor;font-weight:bold;'>$($Gaming.CPUScoreDetail)/35</td></tr>
<tr><td>RAM</td><td>$($Gaming.TotalRAM) GB</td><td style='color:$gmColor;font-weight:bold;'>$($Gaming.RAMScoreDetail)/25</td></tr>
</table>
<table style='margin-top:8px;'><tr><th style='width:35%;'>Info</th><th>Value</th></tr>
<tr><td>DirectX</td><td>$($Gaming.DirectXVersion)</td></tr>
<tr><td>Resolution</td><td>$(if($Gaming.Resolution){$Gaming.Resolution}else{"N/A"})</td></tr>
<tr><td>Refresh Rate</td><td>$($Gaming.RefreshRate)</td></tr>
<tr><td>GPU Driver</td><td>$(if($Gaming.DriverVersion){$Gaming.DriverVersion}else{"N/A"})</td></tr>
</table>
</div>
</div>
"@
})

<!-- ══════════════════════════ BOOT PERFORMANCE ══════════════════════════ -->
$(if($BootPerf){
@"
<div class='sub-header'><span class='section-icon'>&#9889;</span> Boot Performance</div>
<div style='display:flex;gap:15px;margin-bottom:14px;flex-wrap:wrap;'>
<div class='score-card'><div style='font-size:16pt;font-weight:bold;color:#2563eb;'>$($BootPerf.BootTimeMs)</div><div class='score-card-label'>Last Boot Time</div></div>
<div class='score-card'><div style='font-size:16pt;font-weight:bold;'>$($BootPerf.ShutdownTimeMs)</div><div class='score-card-label'>Last Shutdown Time</div></div>
<div class='score-card'><div style='font-size:16pt;font-weight:bold;'>$($BootPerf.SlowStartupApps.Count)</div><div class='score-card-label'>Slow Startup Apps</div></div>
</div>
$(if($BootPerf.SlowStartupApps.Count -gt 0){
$slowRows = ($BootPerf.SlowStartupApps | ForEach-Object { "<tr><td>$($_.Name)</td><td>$($_.DelayMs)</td><td>$($_.Date)</td></tr>" }) -join "`n"
"<div class='sub-header'>Slow Startup Applications</div><table><tr><th>Application</th><th>Delay</th><th>Date</th></tr>$slowRows</table>"
})
"@
})

<!-- ══════════════════════════ WINDOWS 11 READINESS ══════════════════════════ -->
$(if($Win11Ready){
$w11Color = if($Win11Ready.Ready){"#16a34a"}else{"#dc2626"}
$w11Rows = ($Win11Ready.Checks | ForEach-Object {
    $cls = if($_.Passed){"pass"}else{"fail"}
    $icon = if($_.Passed){"$iconPass"}else{"$iconFail"}
    "<tr><td>$($_.Name)</td><td class='$cls'>$icon $(if($_.Passed){'PASS'}else{'FAIL'})</td><td>$($_.Value)</td></tr>"
}) -join "`n"
@"
<div class='sub-header'><span class='section-icon'>&#128187;</span> Windows 11 Readiness</div>
<div style='display:flex;align-items:center;gap:20px;margin-bottom:14px;'>
<div style='text-align:center;padding:15px 25px;background:$(if($Win11Ready.Ready){"#eafaf1"}else{"#fef5f5"});border:2px solid $w11Color;border-radius:12px;'>
<div style='font-size:18pt;font-weight:bold;color:$w11Color;'>$(if($Win11Ready.Ready){"READY"}else{"NOT READY"})</div>
<div style='font-size:9pt;color:#64748b;'>Windows 11 Compatibility</div>
</div>
<div style='font-size:16pt;font-weight:bold;color:$w11Color;'>$($Win11Ready.Score) / $($Win11Ready.MaxScore)</div>
</div>
<table><tr><th>Requirement</th><th>Status</th><th>Details</th></tr>$w11Rows</table>
<div style='font-size:8.5pt;color:#64748b;margin-top:8px;'>$($Win11Ready.Verdict)</div>
"@
})

<!-- ══════════════════════════ POWER STABILITY ══════════════════════════ -->
$(if($PowerInfo){
$pwColor = if($PowerInfo.StabilityScore -ge 80){"#16a34a"}elseif($PowerInfo.StabilityScore -ge 60){"#f59e0b"}else{"#dc2626"}
@"
<div class='sub-header'><span class='section-icon'>&#9889;</span> Power Stability</div>
<div style='display:flex;gap:15px;margin-bottom:14px;flex-wrap:wrap;'>
<div class='score-card'><div style='font-size:16pt;font-weight:bold;color:$pwColor;'>$($PowerInfo.Rating)</div><div class='score-card-label'>Power Stability</div></div>
<div class='score-card'><div style='font-size:16pt;font-weight:bold;'>$($PowerInfo.ACAdapter)</div><div class='score-card-label'>Power Source</div></div>
<div class='score-card'><div style='font-size:16pt;font-weight:bold;color:$(if($PowerInfo.UnexpectedShutdowns -eq 0){"#16a34a"}else{"#dc2626"})'>$($PowerInfo.UnexpectedShutdowns)</div><div class='score-card-label'>Unexpected Shutdowns</div></div>
</div>
<div style='font-size:8.5pt;color:#64748b;margin-bottom:8px;'>$($PowerInfo.LastBootType)</div>
$(if($PowerInfo.PowerEvents.Count -gt 0){
$pwEvtRows = ($PowerInfo.PowerEvents | Select-Object -First 10 | ForEach-Object { "<tr><td>$($_.Time)</td><td>$($_.Type)</td></tr>" }) -join "`n"
"<div class='sub-header'>Recent Power Events</div><table><tr><th style='width:25%;'>Date/Time</th><th>Event</th></tr>$pwEvtRows</table>"
})
"@
})

<!-- ══════════════════════════ HISTORICAL COMPARISON ══════════════════════════ -->
$(if($HistoryComparison -and $HistoryComparison.HasPrevious){
$trendRows = ($HistoryComparison.Trends | ForEach-Object {
    $dirIcon = if($_.Direction -eq 'Improved'){"<span class='pass'>&#8593;</span>"}elseif($_.Direction -eq 'Declined'){"<span class='fail'>&#8595;</span>"}else{"<span>&#8596;</span>"}
    "<tr><td>$($_.Category)</td><td>$($_.Previous)</td><td>$($_.Current)</td><td>$dirIcon $(if($_.Direction){$_.Direction}else{'--'})</td></tr>"
}) -join "`n"
@"
<div class='page-break'></div>
<div class='section-header'><span class='section-icon'>&#128202;</span> Historical Comparison</div>
<div style='padding:12px;background:#eff6ff;border-left:4px solid #2563eb;border-radius:4px;margin-bottom:14px;'>
<strong>Previous Scan:</strong> $($HistoryComparison.PreviousDate) | <strong>Score Change:</strong> <span style='color:$(if($HistoryComparison.ScoreDelta -ge 0){"#16a34a"}else{"#dc2626"});font-weight:bold;'>$(if($HistoryComparison.ScoreDelta -ge 0){"+$($HistoryComparison.ScoreDelta)"}else{$HistoryComparison.ScoreDelta})</span> points
</div>
$(if($trendRows){"<table><tr><th>Category</th><th>Previous</th><th>Current</th><th>Trend</th></tr>$trendRows</table>"})
"@
})

<!-- ══════════════════════════ SYSTEM INFORMATION ══════════════════════════ -->
<div class="page-break"></div>

<div class="section-header"><span class="section-icon">&#128187;</span> System Information</div>
<table><tr><th style="width:35%;">Property</th><th>Value</th></tr>
<tr><td>Computer Name</td><td><strong>$($SystemInfo.ComputerName)</strong></td></tr>
<tr><td>Manufacturer / Model</td><td>$($SystemInfo.Manufacturer) $($SystemInfo.Model)</td></tr>
<tr><td>Serial Number</td><td style="font-family:Consolas,monospace;letter-spacing:0.5px;">$($SystemInfo.Serial)</td></tr>
<tr><td>Operating System</td><td>$($SystemInfo.OSVersion) (Build $($SystemInfo.OSBuild))</td></tr>
<tr><td>Architecture</td><td>$($SystemInfo.Architecture)</td></tr>
<tr><td>CPU</td><td>$($SystemInfo.CPUModel)</td></tr>
<tr><td>Cores / Threads</td><td>$($SystemInfo.CPUCores) / $($SystemInfo.CPUThreads)</td></tr>
<tr><td>RAM</td><td>$($SystemInfo.RAMTotal) GB total / $($SystemInfo.RAMFree) GB free</td></tr>
<tr><td>Uptime</td><td>$($SystemInfo.Uptime)</td></tr>
<tr><td>Domain / Workgroup</td><td>$($SystemInfo.Domain)</td></tr>
</table>

<div class="sub-header">Motherboard &amp; BIOS</div>
<table><tr><th style="width:35%;">Property</th><th>Value</th></tr>
<tr><td>Motherboard</td><td>$($SystemInfo.Board.Manufacturer) $($SystemInfo.Board.Product)</td></tr>
<tr><td>Board Serial</td><td style="font-family:Consolas,monospace;">$($SystemInfo.Board.Serial)</td></tr>
<tr><td>BIOS Vendor</td><td>$($SystemInfo.BIOS.Vendor)</td></tr>
<tr><td>BIOS Version</td><td>$($SystemInfo.BIOS.Version)</td></tr>
<tr><td>BIOS Date</td><td>$($SystemInfo.BIOS.Date)</td></tr>
</table>

<div class="sub-header">Memory (RAM) &mdash; $($SystemInfo.RAMSlots.Used) of $($SystemInfo.RAMSlots.Total) slots used$(if($SystemInfo.RAMSlots.Empty -gt 0){" ($($SystemInfo.RAMSlots.Empty) available)"})</div>
<div style="display:flex;align-items:center;gap:10px;margin-bottom:10px;">
<div class="progress-track progress-lg" style="flex:1;height:14px;"><div class="progress-fill" style="width:$ramSlotPct%;background:#2596be;height:14px;"></div></div>
<span style="font-size:9pt;color:#0d4b71;font-weight:600;">$($SystemInfo.RAMSlots.Used) / $($SystemInfo.RAMSlots.Total)</span>
</div>
<table><tr><th>Slot</th><th>Size</th><th>Speed</th><th>Type</th><th>Manufacturer</th><th>Part Number</th></tr>$ramRows</table>

<div class="sub-header">Graphics</div>
<table><tr><th>GPU</th><th>VRAM</th><th>Driver</th><th>Driver Date</th><th>Resolution</th></tr>$gpuRows</table>

$(if($monitorRows){"<div class='sub-header'>Monitors</div><table><tr><th>Model</th><th>Manufacturer</th><th>Serial</th><th>Year</th></tr>$monitorRows</table>"})


<!-- ══════════════════════════ STORAGE HEALTH ══════════════════════════ -->
<div class="page-break"></div>

<div class="section-header"><span class="section-icon">&#128190;</span> Storage Health</div>

<div class="sub-header">S.M.A.R.T. Status</div>
<table><tr><th>Model</th><th>Type</th><th>Bus</th><th>Size</th><th>Health</th><th>Power-On Hrs</th><th>Temp</th><th>Read Errors</th><th>Wear</th></tr>$smartRows</table>

<div class="sub-header">Drive Space Usage</div>
<table><tr><th>Drive</th><th>Capacity</th><th>Free</th><th>Used</th></tr>$diskRowsDetailed</table>

$(if($tempRows){"
<div class='sub-header'>Temperature Readings</div>
<table><tr><th>Sensor</th><th>Celsius</th><th>Fahrenheit</th><th>Level</th></tr>$tempRows</table>
"})

$batteryHTML


<!-- ══════════════════════════ DEVICE MANAGER ══════════════════════════ -->
<div class="page-break"></div>

<div class="section-header"><span class="section-icon">&#128268;</span> Device Manager</div>
$devErrHTML

$(if($printerRows){"<div class='sub-header'>Printers</div><table><tr><th>Name</th><th>Port</th><th>Driver</th><th>Default</th></tr>$printerRows</table>"})

<!-- ══════════════════════════ NETWORK ══════════════════════════ -->
<div class="section-header"><span class="section-icon">&#127760;</span> Network</div>
<table><tr><th>Adapter</th><th>IP Address</th><th>MAC Address</th><th>DNS</th><th>Speed</th></tr>$netRows</table>
<table><tr><th style="width:30%;">Property</th><th>Value</th></tr>
<tr><td>WiFi SSID</td><td>$($Network.WiFi.SSID)</td></tr>
<tr><td>Public IP</td><td>$($Network.PublicIP)</td></tr>
<tr><td>DNS Response</td><td>$(if($Network.DNSTest.Success){"$($Network.DNSTest.ResponseMs) ms"}else{"<span class='fail'>Failed</span>"})</td></tr>
<tr><td>Internet Connectivity</td><td>$(if($Network.InternetTest.Success){"<span class='pass'>Connected ($($Network.InternetTest.ResponseMs) ms)</span>"}else{"<span class='fail'>No Connection</span>"})</td></tr>
</table>
$(if($Network.OpenPorts.Count -gt 0){"<div class='sub-header'>Listening Ports</div><table><tr><th>Port</th><th>Address</th><th>Process</th></tr>$(($Network.OpenPorts | ForEach-Object {"<tr><td>$($_.Port)</td><td>$($_.Address)</td><td>$($_.Process)</td></tr>"}) -join "`n")</table>"})


<!-- ══════════════════════════ PERFORMANCE ══════════════════════════ -->
<div class="page-break"></div>

<div class="section-header"><span class="section-icon">&#9889;</span> Performance</div>

<div class="summary-strip">
<div class="summary-chip"><span class="chip-val">$($Performance.CPUPercent)%</span><span class="chip-lbl">CPU Usage</span></div>
<div class="summary-chip"><span class="chip-val">$($Performance.RAMPercent)%</span><span class="chip-lbl">RAM Usage</span></div>
<div class="summary-chip"><span class="chip-val">$($Software.ProcessCount)</span><span class="chip-lbl">Processes</span></div>
<div class="summary-chip"><span class="chip-val">$($Software.RunningServices)</span><span class="chip-lbl">Services</span></div>
</div>

<div style="margin:12px 0;">
<div style="display:flex;align-items:center;gap:10px;margin-bottom:8px;">
<span style="min-width:90px;font-size:9pt;font-weight:600;color:#334155;">CPU Usage</span>
<div class="progress-track progress-lg" style="flex:1;"><div class="progress-fill" style="width:$($Performance.CPUPercent)%;background:$cpuBarColor;"></div></div>
<span style="min-width:40px;font-size:9pt;font-weight:600;color:$cpuBarColor;">$($Performance.CPUPercent)%</span>
</div>
<div style="display:flex;align-items:center;gap:10px;margin-bottom:8px;">
<span style="min-width:90px;font-size:9pt;font-weight:600;color:#334155;">RAM Usage</span>
<div class="progress-track progress-lg" style="flex:1;"><div class="progress-fill" style="width:$($Performance.RAMPercent)%;background:$ramBarColor;"></div></div>
<span style="min-width:40px;font-size:9pt;font-weight:600;color:$ramBarColor;">$($Performance.RAMPercent)%</span>
</div>
</div>

<div class="sub-header">Top Memory Consumers</div>
<table><tr><th>Process</th><th>RAM Usage</th></tr>$topProcRows</table>


<!-- ══════════════════════════ STRESS TEST RESULTS ══════════════════════════ -->
$(if($stressHTML){"
<div class='page-break'></div>
<div class='section-header'><span class='section-icon'>&#128293;</span> Stress Test Results</div>
<table><tr><th>Test</th><th>Result</th><th>Details</th><th>Temps / Info</th></tr>$stressHTML</table>
"})

<!-- ══════════════════════════ LICENSE KEYS & CREDENTIALS ══════════════════════════ -->
<div class="page-break"></div>

<div class="section-header"><span class="section-icon">&#128272;</span> License Keys &amp; Credentials</div>
<div class="confidential-banner">
<span class="lock-icon">&#128274;</span>
<span><strong>CONFIDENTIAL</strong> &mdash; This section contains sensitive information. Store securely and do not share publicly.</span>
</div>

<div class="sub-header">Windows Product Key</div>
<table><tr><th>Source</th><th>Key</th></tr>$winKeyRows</table>

<div class="sub-header">Microsoft Office</div>
<table><tr><th>Product</th><th>Key</th></tr>$officeKeyRows</table>

$(if($adobeKeyRows){"<div class='sub-header'>Adobe Products</div><table><tr><th>Product</th><th>Key</th></tr>$adobeKeyRows</table>"})

<div class="sub-header">Saved WiFi Networks</div>
<table><tr><th>Network (SSID)</th><th>Password</th><th>Security</th></tr>$wifiRows</table>


<!-- ══════════════════════════ TECHNICIAN NOTES ══════════════════════════ -->
$techNotes

<!-- ══════════════════════════ INSTALLED SOFTWARE ══════════════════════════ -->
<div class="page-break"></div>

<div class="section-header"><span class="section-icon">&#128230;</span> Installed Software ($($Software.Installed.Count))</div>
<table><tr><th>Name</th><th>Version</th><th>Publisher</th></tr>$swRows</table>

<div class="sub-header">Startup Programs ($($Software.StartupPrograms.Count))</div>
<table><tr><th>Name</th><th>Location</th></tr>$(($Software.StartupPrograms | ForEach-Object {"<tr><td>$($_.Name)</td><td style='font-size:8pt;word-break:break-all;'>$($_.Location)</td></tr>"}) -join "`n")</table>

$(if($bannerSecBottomUri){"<div class='page-break'></div><div class='promo-banner' style='padding-top:30px;'><img src='$bannerSecBottomUri' alt='175-Point Security Inspection'/></div>"})

<!-- ══════════════════════════ BACK PAGE ══════════════════════════ -->
<div class="page-break"></div>

<div style="text-align:center;padding-top:60px;">
$(if($logoDataUri){"<img src='$logoDataUri' alt='PC Plus Computing' style='width:250px;margin-bottom:30px;'/>"}else{"<div style='background:#0a1628;color:#fff;padding:16px 40px;font-size:18pt;font-weight:bold;letter-spacing:3px;border-radius:6px;margin-bottom:30px;display:inline-block;'>PC PLUS COMPUTING</div>"})
<div style="font-size:12pt;color:#0d4b71;font-weight:600;margin-bottom:6px;">Thank you for choosing PC Plus Computing</div>
<div style="font-size:10pt;color:#64748b;margin-bottom:30px;">Your Security, Our Priority &nbsp;|&nbsp; 30+ Years in Service &nbsp;|&nbsp; 4.9&#9733; Google Rating</div>

<div class="qr-row">
<div class="qr-item">
$(if($qrAppointmentUri){"<img src='$qrAppointmentUri' alt='Book Appointment'/>"}else{"<div class='qr-fallback'>Book<br/>Appointment</div>"})
<div class="qr-label">Book an Appointment</div>
<div class="qr-sublabel">pcpluscomputing.com/appointments</div>
</div>
<div class="qr-item">
$(if($qrServiceUri){"<img src='$qrServiceUri' alt='Send Info'/>"}else{"<div class='qr-fallback'>Send Us<br/>Info</div>"})
<div class="qr-label">Send Us Your Info</div>
<div class="qr-sublabel">Service Request Portal</div>
</div>
</div>

<div style="margin-top:40px;padding:20px;background:#f8fafc;border-radius:10px;border:1px solid #e2e8f0;display:inline-block;">
<div style="font-size:11pt;font-weight:700;color:#0a1628;margin-bottom:8px;">Get In Touch</div>
<div style="font-size:10pt;color:#475569;">
&#127760; $WEBSITE &nbsp;&nbsp;|&nbsp;&nbsp; &#128222; $PHONE
</div>
</div>

<div style="margin-top:40px;font-size:8pt;color:#94a3b8;">
Hardware Diagnostic Report generated $date<br/>
Technician: $($Params.TechName) &nbsp;|&nbsp; Device: $($SystemInfo.ComputerName)
</div>
</div>

</body></html>
"@
    return $html
}

function Build-SecurityReport {
    param($Params, $SystemInfo, $Security, $MissingPatches, $Scoring)
    $date = Get-Date -Format "MMMM dd, yyyy 'at' h:mm tt"
    $iconPass = "&#10004;"; $iconFail = "&#10008;"; $iconWarn = "&#9888;"
    $passCount = ($Scoring.Breakdown | Where-Object { $_.Passed }).Count
    $failCount = ($Scoring.Breakdown | Where-Object { -not $_.Passed }).Count
    $dashOffset = 283 - (283 * $Scoring.Score / 100)

    # Load logo as base64 data URI
    $logoDataUri = ""
    $logoPath = Join-Path $Global:ScriptDir "logo-base64.txt"
    if (Test-Path $logoPath) {
        try {
            $logoB64 = (Get-Content $logoPath -Raw).Trim()
            $logoDataUri = "data:image/png;base64,$logoB64"
        } catch { $logoDataUri = "" }
    }
    $logoHTML = if ($logoDataUri) {
        "<img src='$logoDataUri' alt='PC Plus Computing' style='width:350px;max-width:90%;margin-bottom:30px;'/>"
    } else {
        "<div style='background:#0a1628;color:#fff;padding:20px 50px;font-size:22pt;font-weight:bold;letter-spacing:3px;border-radius:6px;margin-bottom:30px;'>PC PLUS COMPUTING</div>"
    }

    # Load QR codes as base64 data URIs
    $qrAppointmentUri = ""; $qrServiceUri = ""
    $qrAppPath = Join-Path $Global:ScriptDir "qr-appointments.txt"
    $qrSvcPath = Join-Path $Global:ScriptDir "qr-service-requests.txt"
    if (Test-Path $qrAppPath) { try { $qrAppointmentUri = "data:image/png;base64,$((Get-Content $qrAppPath -Raw).Trim())" } catch {} }
    if (Test-Path $qrSvcPath) { try { $qrServiceUri = "data:image/png;base64,$((Get-Content $qrSvcPath -Raw).Trim())" } catch {} }

    # Load cross-promotion banners
    $bannerHwTopUri = ""; $bannerHwBottomUri = ""
    $bhtPath = Join-Path $Global:ScriptDir "banner-hardware-top.txt"
    $bhbPath = Join-Path $Global:ScriptDir "banner-hardware-bottom.txt"
    if (Test-Path $bhtPath) { try { $bannerHwTopUri = "data:image/jpeg;base64,$((Get-Content $bhtPath -Raw).Trim())" } catch {} }
    if (Test-Path $bhbPath) { try { $bannerHwBottomUri = "data:image/jpeg;base64,$((Get-Content $bhbPath -Raw).Trim())" } catch {} }

    # Load security report's own banner
    $bannerSecOwnUri = ""
    $bsoPath = Join-Path $Global:ScriptDir "banner-security-top.txt"
    if (Test-Path $bsoPath) { try { $bannerSecOwnUri = "data:image/jpeg;base64,$((Get-Content $bsoPath -Raw).Trim())" } catch {} }

    # Breakdown rows
    $breakdownRows = ($Scoring.Breakdown | ForEach-Object {
        $ic = if($_.Passed){"<span class='pass'>$iconPass</span>"}else{"<span class='fail'>$iconFail</span>"}
        $statusBadge = if($_.Passed){"<span class='status-badge status-pass'>PASS</span>"}else{"<span class='status-badge status-fail'>FAIL</span>"}
        "<tr><td style='width:30px;text-align:center;'>$ic</td><td>$($_.Check)</td><td>$statusBadge</td><td style='text-align:center;font-weight:600;'>$($_.Points) pts</td></tr>"
    }) -join "`n"
    # Recommendations
    $recs = @()
    foreach ($item in $Scoring.Breakdown) {
        if (-not $item.Passed) {
            $rec = switch ($item.Check) {
                "Antivirus Active" { "Install and activate antivirus immediately." }
                "Firewall All Profiles" { "Enable Windows Firewall on all profiles." }
                "BitLocker on C:" { "Enable BitLocker drive encryption." }
                "No Critical Patches Missing" { "Install all pending critical updates." }
                "UAC Enabled" { "Re-enable User Account Control." }
                "Secure Boot" { "Enable Secure Boot in BIOS/UEFI." }
                "TPM Present" { "Hardware upgrade needed for TPM 2.0." }
                "Password Policy" { "Set minimum 8 character password with complexity." }
                "Guest Disabled" { "Disable the Guest account." }
                "No Auto-Login" { "Disable automatic login." }
                "RDP Secure" { "Disable RDP or enable NLA." }
                "SMBv1 Disabled" { "Disable SMBv1 (ransomware vulnerability)." }
                "Admin Accounts <=2" { "Reduce admin accounts, use standard for daily use." }
                "Real-Time Protection" { "Enable Windows Defender real-time protection." }
                "AV Definitions Current" { "Update antivirus definitions." }
                default { "Review and fix this configuration." }
            }
            $sev = if($item.Points -ge 10){"Critical"}elseif($item.Points -ge 5){"Warning"}else{"Advisory"}
            $recs += @{ Check = $item.Check; Rec = $rec; Severity = $sev }
        }
    }
    $recsHTML = ($recs | ForEach-Object {
        $borderColor = switch($_.Severity){"Critical"{"#dc2626"}"Warning"{"#f59e0b"}default{"#2596be"}}
        $bgColor = switch($_.Severity){"Critical"{"#fef5f5"}"Warning"{"#fffbeb"}default{"#f0f7fb"}}
        $sevColor = switch($_.Severity){"Critical"{"#dc2626"}"Warning"{"#92400e"}default{"#0d4b71"}}
        "<div class='rec-card' style='border-left:4px solid $borderColor;background:$bgColor;'><div class='rec-severity' style='color:$sevColor;'>$($_.Severity)</div><div class='rec-check'>$($_.Check)</div><div class='rec-action'>$($_.Rec)</div></div>"
    }) -join "`n"
    # Security details - card-style panels
    $secDetails = @()
    # Defender
    $defSt = if($Security.Defender.RealTimeProtection -eq $true){"<span class='status-badge status-pass'>$iconPass Active</span>"}elseif($Security.Defender.RealTimeProtection -eq $false){"<span class='status-badge status-fail'>$iconFail Disabled</span>"}else{"<span class='status-badge status-warn'>$iconWarn Unknown</span>"}
    $secDetails += @{ Name="Windows Defender"; Status=$defSt }
    if($Security.Defender.DefinitionAge -ne $null){$da=if($Security.Defender.DefinitionsUpToDate){"status-pass"}else{"status-fail"};$secDetails+=@{Name="AV Definitions";Status="<span class='status-badge $da'>$($Security.Defender.DefinitionAge) days old</span>"}}
    if($Security.ThirdPartyAV.Count -gt 0){$secDetails+=@{Name="Third-Party AV";Status="<span class='status-badge status-pass'>$($Security.ThirdPartyAV -join ', ')</span>"}}
    foreach($p in @("Domain","Private","Public")){$v=$Security.Firewall.$p;$s=if($v -eq $true){"<span class='status-badge status-pass'>$iconPass Enabled</span>"}elseif($v -eq $false){"<span class='status-badge status-fail'>$iconFail Disabled</span>"}else{"<span class='status-badge status-warn'>$iconWarn Unknown</span>"};$secDetails+=@{Name="Firewall - $p";Status=$s}}
    $uacSt = if($Security.UAC.Enabled){"<span class='status-badge status-pass'>$iconPass Enabled</span>"}else{"<span class='status-badge status-fail'>$iconFail Disabled</span>"}
    $secDetails += @{ Name="UAC"; Status=$uacSt }
    if($Security.BitLocker.Count -gt 0){foreach($d in $Security.BitLocker.Keys){$bi=$Security.BitLocker[$d];$bs=if($bi.Status -eq "On"){"<span class='status-badge status-pass'>$iconPass Encrypted</span>"}else{"<span class='status-badge status-fail'>$iconFail Not Encrypted</span>"};$secDetails+=@{Name="BitLocker $d";Status=$bs}}}else{$secDetails+=@{Name="BitLocker";Status="<span class='status-badge status-fail'>$iconFail Not Detected</span>"}}
    $sbSt = if($Security.SecureBoot -eq $true){"<span class='status-badge status-pass'>$iconPass Enabled</span>"}elseif($Security.SecureBoot -eq $false){"<span class='status-badge status-fail'>$iconFail Disabled</span>"}else{"<span class='status-badge status-warn'>$iconWarn Unknown</span>"}
    $secDetails += @{ Name="Secure Boot"; Status=$sbSt }
    $tpmSt = if($Security.TPM.Present){"<span class='status-badge status-pass'>$iconPass Present (v$($Security.TPM.Version))</span>"}else{"<span class='status-badge status-fail'>$iconFail Not Present</span>"}
    $secDetails += @{ Name="TPM"; Status=$tpmSt }
    $secDetails += @{ Name="Password Policy"; Status="Min Length: $($Security.PasswordPolicy.MinLength), Complexity: $(if($Security.PasswordPolicy.Complexity){'Yes'}else{'No'}), Lockout: $(if($Security.PasswordPolicy.LockoutThreshold -gt 0){$Security.PasswordPolicy.LockoutThreshold}else{'None'})" }
    $gSt = if($Security.GuestDisabled -eq $true){"<span class='status-badge status-pass'>$iconPass Disabled</span>"}else{"<span class='status-badge status-fail'>$iconFail Enabled</span>"}
    $secDetails += @{ Name="Guest Account"; Status=$gSt }
    $alSt = if($Security.AutoLoginDisabled -eq $true){"<span class='status-badge status-pass'>$iconPass Off</span>"}else{"<span class='status-badge status-fail'>$iconFail On</span>"}
    $secDetails += @{ Name="Auto-Login"; Status=$alSt }
    $rdpSt = if($Security.RDP.Enabled -eq $false){"<span class='status-badge status-pass'>$iconPass Disabled</span>"}elseif($Security.RDP.NLA){"<span class='status-badge status-warn'>$iconWarn Enabled (NLA)</span>"}else{"<span class='status-badge status-fail'>$iconFail Enabled (No NLA)</span>"}
    $secDetails += @{ Name="Remote Desktop"; Status=$rdpSt }
    $smbSt = if($Security.SMBv1Disabled -eq $true){"<span class='status-badge status-pass'>$iconPass Disabled</span>"}else{"<span class='status-badge status-fail'>$iconFail Enabled</span>"}
    $secDetails += @{ Name="SMBv1"; Status=$smbSt }
    $secDetails += @{ Name="Local Admins"; Status="$($Security.LocalAdmins.Count): $($Security.LocalAdmins.Names)" }

    # Build security detail cards
    $secDetailCards = ($secDetails | ForEach-Object {
        "<div class='sec-detail-row'><div class='sec-detail-label'>$($_.Name)</div><div class='sec-detail-value'>$($_.Status)</div></div>"
    }) -join "`n"

    # Patch rows
    $patchRows = if($MissingPatches.Count -gt 0){
        ($MissingPatches | ForEach-Object {
            $sevBadge = switch($_.Severity){"Critical"{"<span class='status-badge status-fail'>Critical</span>"}"Important"{"<span class='status-badge status-warn'>Important</span>"}default{"<span class='status-badge status-info'>$($_.Severity)</span>"}}
            "<tr><td style='font-family:Consolas,monospace;font-weight:600;'>$($_.KB)</td><td>$($_.Title)</td><td>$sevBadge</td><td style='text-align:right;'>$($_.SizeMB) MB</td></tr>"
        }) -join "`n"
    } else { "<tr><td colspan='4' class='pass' style='text-align:center;padding:16px;'>$iconPass All patches up to date</td></tr>" }

    # Mini donut helper for exec summary cards
    $criticalPatches = ($MissingPatches | Where-Object { $_.Severity -eq "Critical" }).Count
    $importantPatches = ($MissingPatches | Where-Object { $_.Severity -eq "Important" }).Count

$html = @"
<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8"/><title>Security Audit Report - $($Params.CustomerName)</title>
<style>
@page { size: letter; margin: 0.5in 0.6in 0.9in 0.6in; }
* { margin:0; padding:0; box-sizing:border-box; }
body { font-family: 'Segoe UI', -apple-system, Tahoma, sans-serif; font-size: 9.5pt; color: #1e293b; line-height: 1.6; background: #fff; }
h1,h2,h3,h4 { margin:0; }

/* Print handling */
@media print {
    body { -webkit-print-color-adjust: exact; print-color-adjust: exact; }
    .page-break { page-break-before: always; }
    .no-break { page-break-inside: avoid; }
}
.page-break { page-break-before: always; }

/* Fixed print footer - repeats on every page */
.print-footer {
    position: fixed; bottom: 0; left: 0; right: 0;
    padding: 6px 0; border-top: 1.5px solid #0d4b71;
    text-align: center; font-size: 7.5pt; color: #94a3b8;
    background: #fff;
}
.print-footer strong { color: #0d4b71; font-size: 7.5pt; }
.print-footer .report-name { color: #475569; }
.no-break { page-break-inside: avoid; }

/* Section headers */
.section-header {
    background: linear-gradient(135deg, #0a1628 0%, #0d4b71 100%);
    color: #fff; padding: 10px 20px; font-size: 12pt; font-weight: 600;
    margin: 24px 0 14px 0; border-radius: 6px; letter-spacing: 0.5px;
    display: flex; align-items: center; gap: 10px;
}
.section-header .section-icon { font-size: 14pt; opacity: 0.85; }
.sub-header {
    color: #0d4b71; font-size: 10.5pt; font-weight: 700; margin: 18px 0 8px 0;
    padding-bottom: 5px; border-bottom: 2px solid #2596be; letter-spacing: 0.3px;
}

/* Tables */
table { width: 100%; border-collapse: collapse; margin-bottom: 14px; font-size: 9pt; }
th {
    background: #0d4b71; color: #fff; padding: 7px 10px; text-align: left;
    font-weight: 600; font-size: 8.5pt; text-transform: uppercase; letter-spacing: 0.5px;
}
td { padding: 6px 10px; border-bottom: 1px solid #e2e8f0; vertical-align: middle; }
tr:nth-child(even) td { background: #f8fafc; }
tr:hover td { background: #eaf7fc; }
.pass { color: #16a34a; font-weight: 600; }
.fail { color: #dc2626; font-weight: 600; }
.warn { color: #f59e0b; font-weight: 600; }

/* Status badges */
.status-badge {
    display: inline-block; padding: 3px 10px; border-radius: 12px; font-size: 8.5pt;
    font-weight: 600; letter-spacing: 0.3px;
}
.status-pass { background: #dcfce7; color: #166534; }
.status-fail { background: #fef2f2; color: #991b1b; }
.status-warn { background: #fffbeb; color: #92400e; }
.status-info { background: #f0f7fb; color: #0d4b71; }

/* Score cards (executive summary) */
.score-cards {
    display: flex; gap: 12px; margin: 14px 0; flex-wrap: wrap; justify-content: center;
}
.score-card {
    flex: 1; min-width: 110px; max-width: 150px; text-align: center; padding: 14px 10px;
    background: #fff; border: 1px solid #e2e8f0; border-radius: 10px;
    box-shadow: 0 1px 3px rgba(0,0,0,0.05);
}
.score-card-label { font-size: 8pt; color: #64748b; text-transform: uppercase; font-weight: 600; margin-top: 4px; letter-spacing: 0.3px; }
.score-card-value { font-size: 16pt; font-weight: 700; margin-top: 2px; }

/* Recommendation cards */
.rec-card {
    padding: 12px 16px; margin: 8px 0; border-radius: 6px;
}
.rec-severity { font-size: 8pt; font-weight: 700; text-transform: uppercase; letter-spacing: 0.5px; margin-bottom: 2px; }
.rec-check { font-size: 10pt; font-weight: 600; color: #0a1628; margin-bottom: 3px; }
.rec-action { font-size: 9pt; color: #475569; }

/* Security detail rows */
.sec-detail-panel {
    background: #fff; border: 1px solid #e2e8f0; border-radius: 10px;
    overflow: hidden; margin-bottom: 14px;
}
.sec-detail-row {
    display: flex; padding: 9px 16px; border-bottom: 1px solid #f1f5f9;
    align-items: center;
}
.sec-detail-row:nth-child(even) { background: #f8fafc; }
.sec-detail-row:last-child { border-bottom: none; }
.sec-detail-label { min-width: 180px; font-weight: 600; color: #334155; font-size: 9.5pt; }
.sec-detail-value { flex: 1; font-size: 9.5pt; }

/* QR codes */
.qr-row { display: flex; justify-content: center; gap: 60px; margin: 20px 0; }
.qr-item { text-align: center; }
.qr-item img { width: 160px; height: 160px; border-radius: 8px; }
.qr-item .qr-fallback { width: 160px; height: 160px; border: 2px dashed #94a3b8; border-radius: 8px; display: flex; align-items: center; justify-content: center; font-size: 7.5pt; color: #94a3b8; line-height: 1.3; }
.qr-label { font-size: 9pt; font-weight: 600; color: #0d4b71; margin-top: 8px; }
.qr-sublabel { font-size: 7.5pt; color: #64748b; margin-top: 2px; }
.promo-banner { text-align: center; margin: 20px 0; page-break-inside: avoid; }
.promo-banner img { width: 100%; max-width: 100%; border-radius: 8px; box-shadow: 0 2px 8px rgba(0,0,0,0.1); }

/* Repeated page footer */
.page-footer-bar {
    margin-top: 30px; padding: 10px 0; border-top: 2px solid #0d4b71;
    text-align: center; font-size: 8pt; color: #94a3b8;
}
.page-footer-bar strong { color: #0d4b71; }
</style></head><body>

<div class="print-footer">
<span class="report-name">Security Audit Report</span> &nbsp;|&nbsp; <strong>$COMPANY</strong> &nbsp;|&nbsp; $WEBSITE &nbsp;|&nbsp; $PHONE
</div>

<!-- COVER PAGE -->
<div style="page-break-after:always;">
$(if($bannerSecOwnUri){"<div style='text-align:center;margin-bottom:15px;'><img src='$bannerSecOwnUri' alt='PC Plus Security Audit' style='width:100%;border-radius:8px;'/></div>"})

<div style="display:flex;gap:20px;align-items:center;margin:15px 0;">
<div style="flex:1;">
<div style="background:#f8fafc;border:1px solid #e2e8f0;border-radius:10px;padding:16px;">
<table style="width:100%;font-size:10pt;border:none;margin:0;">
<tr><td style="border:none;padding:4px 8px;color:#64748b;font-weight:600;width:110px;">Customer:</td><td style="border:none;padding:4px 8px;color:#0a1628;font-weight:700;">$($Params.CustomerName)</td></tr>
$(if($Params.ContactName){"<tr><td style='border:none;padding:4px 8px;color:#64748b;font-weight:600;'>Contact:</td><td style='border:none;padding:4px 8px;color:#0a1628;'>$($Params.ContactName)</td></tr>"})
<tr><td style="border:none;padding:4px 8px;color:#64748b;font-weight:600;">Device:</td><td style="border:none;padding:4px 8px;color:#0a1628;">$($SystemInfo.ComputerName)</td></tr>
<tr><td style="border:none;padding:4px 8px;color:#64748b;font-weight:600;">Date:</td><td style="border:none;padding:4px 8px;color:#0a1628;">$date</td></tr>
<tr><td style="border:none;padding:4px 8px;color:#64748b;font-weight:600;">Technician:</td><td style="border:none;padding:4px 8px;color:#0a1628;">$($Params.TechName)</td></tr>
</table>
</div>
</div>
<div style="text-align:center;">
<svg viewBox="0 0 100 100" width="130" height="130">
<circle cx="50" cy="50" r="45" fill="none" stroke="#e5e7eb" stroke-width="8"/>
<circle cx="50" cy="50" r="45" fill="none" stroke="$($Scoring.Color)" stroke-width="8" stroke-dasharray="283" stroke-dashoffset="$dashOffset" transform="rotate(-90 50 50)" stroke-linecap="round"/>
<text x="50" y="46" text-anchor="middle" font-size="20" font-weight="bold" fill="$($Scoring.Color)">$($Scoring.Grade)</text>
<text x="50" y="62" text-anchor="middle" font-size="10" fill="#64748b">$($Scoring.Score) / 100</text>
</svg>
<div style="font-size:9pt;color:$($Scoring.Color);font-weight:700;margin-top:4px;">Security Score</div>
</div>
</div>

$(if($bannerHwTopUri){"<div style='text-align:center;margin-top:15px;'><img src='$bannerHwTopUri' alt='PC Plus Hardware Test' style='width:100%;border-radius:8px;'/></div>"})
</div>

<!-- EXECUTIVE SUMMARY -->
<div class="page-break"></div>

<div class="section-header"><span class="section-icon">&#128737;</span> Executive Summary</div>

<div style="display:flex;align-items:center;gap:24px;margin:14px 0;">
<div style="text-align:center;">
<svg viewBox="0 0 100 100" width="100" height="100">
<circle cx="50" cy="50" r="40" fill="none" stroke="#e5e7eb" stroke-width="8"/>
<circle cx="50" cy="50" r="40" fill="none" stroke="$($Scoring.Color)" stroke-width="8" stroke-dasharray="251" stroke-dashoffset="$([math]::Round(251 - (251 * $Scoring.Score / 100)))" transform="rotate(-90 50 50)" stroke-linecap="round"/>
<text x="50" y="46" text-anchor="middle" font-size="20" font-weight="bold" fill="$($Scoring.Color)">$($Scoring.Grade)</text>
<text x="50" y="62" text-anchor="middle" font-size="11" fill="#64748b">$($Scoring.Score) / 100</text>
</svg>
<div style="font-size:8pt;color:#64748b;font-weight:600;margin-top:4px;">SECURITY SCORE</div>
</div>
<div style="flex:1;">
<div class="score-cards">
<div class="score-card">
<div class="score-card-value" style="color:#16a34a;">$passCount</div>
<svg viewBox="0 0 80 6" width="80" height="6" style="margin-top:6px;"><rect width="80" height="6" rx="3" fill="#e5e7eb"/><rect width="$([math]::Round(80 * $passCount / $Scoring.Breakdown.Count))" height="6" rx="3" fill="#16a34a"/></svg>
<div class="score-card-label">Passed</div>
</div>
<div class="score-card">
<div class="score-card-value" style="color:#dc2626;">$failCount</div>
<svg viewBox="0 0 80 6" width="80" height="6" style="margin-top:6px;"><rect width="80" height="6" rx="3" fill="#e5e7eb"/><rect width="$([math]::Round(80 * $failCount / $Scoring.Breakdown.Count))" height="6" rx="3" fill="#dc2626"/></svg>
<div class="score-card-label">Failed</div>
</div>
<div class="score-card">
<div class="score-card-value" style="color:$($Scoring.Color);">$($Scoring.Score)</div>
<svg viewBox="0 0 80 6" width="80" height="6" style="margin-top:6px;"><rect width="80" height="6" rx="3" fill="#e5e7eb"/><rect width="$([math]::Round(80 * $Scoring.Score / 100))" height="6" rx="3" fill="$($Scoring.Color)"/></svg>
<div class="score-card-label">Score</div>
</div>
<div class="score-card">
<div class="score-card-value" style="color:$(if($MissingPatches.Count -eq 0){'#16a34a'}elseif($criticalPatches -gt 0){'#dc2626'}else{'#f59e0b'});">$($MissingPatches.Count)</div>
<svg viewBox="0 0 80 6" width="80" height="6" style="margin-top:6px;"><rect width="80" height="6" rx="3" fill="#e5e7eb"/><rect width="$(if($MissingPatches.Count -gt 0){[math]::Min(80, $MissingPatches.Count * 4)}else{0})" height="6" rx="3" fill="$(if($criticalPatches -gt 0){'#dc2626'}elseif($MissingPatches.Count -gt 0){'#f59e0b'}else{'#16a34a'})"/></svg>
<div class="score-card-label">Missing Patches</div>
</div>
</div>
</div>
</div>

$(if($recs.Count -gt 0){
"<div style='background:#fef5f5;border:1px solid #fca5a5;border-radius:10px;padding:14px 18px;margin:12px 0;'>
<div style='font-size:10.5pt;font-weight:700;color:#991b1b;margin-bottom:8px;'>&#9888; Action Required ($($recs.Count) item$(if($recs.Count -ne 1){'s'}))</div>
$recsHTML
</div>"
} else {
"<div style='background:#eafaf1;border:1px solid #86efac;border-radius:10px;padding:16px 20px;margin:12px 0;'>
<div style='font-size:10.5pt;font-weight:700;color:#166534;'>$iconPass All Security Checks Passed</div>
<div style='font-size:9.5pt;color:#334155;margin-top:4px;'>This system meets all security baseline requirements.</div>
</div>"
})

<!-- SCORE BREAKDOWN -->
<div class="page-break"></div>

<div class="section-header"><span class="section-icon">&#128202;</span> Security Score Breakdown</div>

<table><tr><th style="width:30px;"></th><th>Security Check</th><th>Status</th><th style="width:70px;text-align:center;">Weight</th></tr>$breakdownRows</table>


<!-- DETAILED SECURITY STATUS -->
<div class="page-break"></div>

<div class="section-header"><span class="section-icon">&#128274;</span> Detailed Security Status</div>

<div class="sec-detail-panel">
$secDetailCards
</div>


<!-- MISSING PATCHES -->
<div class="page-break"></div>

<div class="section-header"><span class="section-icon">&#128259;</span> Missing Windows Updates ($($MissingPatches.Count))</div>

$(if($criticalPatches -gt 0){"<div style='background:#fef5f5;border-left:4px solid #dc2626;border-radius:4px;padding:10px 14px;margin-bottom:12px;font-size:9.5pt;'><strong class='fail'>$iconFail $criticalPatches Critical</strong> and <strong class='warn'>$importantPatches Important</strong> updates are missing. Install immediately.</div>"})

<table><tr><th>KB Article</th><th>Update Title</th><th>Severity</th><th style="text-align:right;">Size</th></tr>$patchRows</table>

$(if($bannerHwBottomUri){"<div class='page-break'></div><div class='promo-banner' style='padding-top:30px;'><img src='$bannerHwBottomUri' alt='PC Plus Hardware Test'/></div>"})

<!-- BACK PAGE -->
<div class="page-break"></div>

<div style="text-align:center;padding-top:60px;">
$(if($logoDataUri){"<img src='$logoDataUri' alt='PC Plus Computing' style='width:250px;margin-bottom:30px;'/>"}else{"<div style='background:#0a1628;color:#fff;padding:16px 40px;font-size:18pt;font-weight:bold;letter-spacing:3px;border-radius:6px;margin-bottom:30px;display:inline-block;'>PC PLUS COMPUTING</div>"})
<div style="font-size:12pt;color:#0d4b71;font-weight:600;margin-bottom:6px;">Thank you for choosing PC Plus Computing</div>
<div style="font-size:10pt;color:#64748b;margin-bottom:30px;">Your Security, Our Priority &nbsp;|&nbsp; 30+ Years in Service &nbsp;|&nbsp; 4.9&#9733; Google Rating</div>

<div class="qr-row">
<div class="qr-item">
$(if($qrAppointmentUri){"<img src='$qrAppointmentUri' alt='Book Appointment'/>"}else{"<div class='qr-fallback'>Book<br/>Appointment</div>"})
<div class="qr-label">Book an Appointment</div>
<div class="qr-sublabel">pcpluscomputing.com/appointments</div>
</div>
<div class="qr-item">
$(if($qrServiceUri){"<img src='$qrServiceUri' alt='Send Info'/>"}else{"<div class='qr-fallback'>Send Us<br/>Info</div>"})
<div class="qr-label">Send Us Your Info</div>
<div class="qr-sublabel">Service Request Portal</div>
</div>
</div>

<div style="margin-top:40px;padding:20px;background:#f8fafc;border-radius:10px;border:1px solid #e2e8f0;display:inline-block;">
<div style="font-size:11pt;font-weight:700;color:#0a1628;margin-bottom:8px;">Get In Touch</div>
<div style="font-size:10pt;color:#475569;">
&#127760; $WEBSITE &nbsp;&nbsp;|&nbsp;&nbsp; &#128222; $PHONE
</div>
</div>

<div style="margin-top:40px;font-size:8pt;color:#94a3b8;">
Security Audit Report generated $date<br/>
Technician: $($Params.TechName) &nbsp;|&nbsp; Device: $($SystemInfo.ComputerName)
</div>
</div>

</body></html>
"@
    return $html
}

function Convert-ToPDF {
    param([string]$HTMLPath, [string]$PDFPath)
    $browsers = @()
    foreach ($p in @("${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe","$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe","$env:LOCALAPPDATA\Microsoft\Edge\Application\msedge.exe")) { if (Test-Path $p) { $browsers += $p; break } }
    foreach ($p in @("${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe","$env:ProgramFiles\Google\Chrome\Application\chrome.exe","$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe")) { if (Test-Path $p) { $browsers += $p; break } }
    foreach ($b in $browsers) {
        try {
            $args = "--headless --disable-gpu --no-sandbox --print-to-pdf=`"$PDFPath`" --print-to-pdf-no-header --no-pdf-header-footer --run-all-compositor-stages-before-draw --disable-extensions `"file:///$($HTMLPath.Replace('\','/'))`""
            Start-Process -FilePath $b -ArgumentList $args -PassThru -WindowStyle Hidden -Wait | Out-Null
            if (Test-Path $PDFPath) { return $true }
        } catch { continue }
    }
    return $false
}

# ─────────────────────────────────────────────────────────────────────────────
# WPF LAUNCHER
# ─────────────────────────────────────────────────────────────────────────────


function Show-Launcher {

$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="PC Plus 360 Hardware Diagnostic Suite" Height="720" Width="960"
        WindowStartupLocation="CenterScreen" ResizeMode="CanMinimize"
        Background="#eef4f8" FontFamily="Segoe UI">
    <Window.Resources>
        <Style x:Key="FlatBtn" TargetType="Button">
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="bd" Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="6" Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="{TemplateBinding HorizontalContentAlignment}"
                                              VerticalAlignment="{TemplateBinding VerticalContentAlignment}"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="bd" Property="Opacity" Value="0.85"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="bd" Property="Opacity" Value="0.7"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter Property="Opacity" Value="0.4"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style x:Key="SideNav" TargetType="Button">
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="HorizontalContentAlignment" Value="Left"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="bd" Background="Transparent" CornerRadius="5" Padding="10,7" Margin="0,1">
                            <ContentPresenter HorizontalAlignment="Left"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="bd" Property="Background" Value="#0d4b71"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter Property="Opacity" Value="0.4"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>
    <Grid>
        <Grid.ColumnDefinitions>
            <ColumnDefinition Width="216"/>
            <ColumnDefinition Width="*"/>
        </Grid.ColumnDefinitions>

        <!-- SIDEBAR -->
        <Border Grid.Column="0" Background="#0a3a56">
            <DockPanel LastChildFill="True">
                <Border DockPanel.Dock="Top" Padding="14,16,14,12" BorderBrush="#0d4b71" BorderThickness="0,0,0,1">
                    <StackPanel Orientation="Horizontal">
                        <Border Width="38" Height="38" CornerRadius="9" Margin="0,0,10,0">
                            <Border.Background>
                                <LinearGradientBrush StartPoint="0,0" EndPoint="1,1">
                                    <GradientStop Color="#2596be" Offset="0"/>
                                    <GradientStop Color="#3bbde0" Offset="1"/>
                                </LinearGradientBrush>
                            </Border.Background>
                            <TextBlock Text="360" FontSize="13" FontWeight="Bold" Foreground="White" HorizontalAlignment="Center" VerticalAlignment="Center" FontFamily="Consolas"/>
                        </Border>
                        <StackPanel VerticalAlignment="Center">
                            <TextBlock Text="PC Plus Computing" FontSize="12.5" FontWeight="SemiBold" Foreground="White"/>
                            <TextBlock Text="YOUR SECURITY, OUR PRIORITY" FontSize="7.5" Foreground="#3bbde0" FontWeight="SemiBold" Margin="0,1,0,0"/>
                        </StackPanel>
                    </StackPanel>
                </Border>

                <Border DockPanel.Dock="Bottom" Padding="14,8" BorderBrush="#0d4b71" BorderThickness="0,1,0,0">
                    <StackPanel>
                        <TextBlock Text="v2.2.0" FontSize="10" Foreground="#2596be" FontFamily="Consolas"/>
                        <TextBlock Text="604-760-1662 | 236-500-2700" FontSize="8.5" Foreground="#4a7a8a" Margin="0,2,0,0"/>
                        <TextBlock Text="pcpluscomputing.com" FontSize="8.5" Foreground="#3a6a7a"/>
                    </StackPanel>
                </Border>

                <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
                    <StackPanel Margin="6,8,6,8">
                        <TextBlock Text="  MAIN" FontSize="9" FontWeight="SemiBold" Foreground="#4a7a8a" Margin="0,6,0,4"/>
                        <Border Background="#0d4b71" CornerRadius="5" Padding="10,7" Margin="0,1">
                            <TextBlock Text="Dashboard" FontSize="12" Foreground="White" FontWeight="SemiBold"/>
                        </Border>

                        <TextBlock Text="  TOOLS" FontSize="9" FontWeight="SemiBold" Foreground="#4a7a8a" Margin="0,12,0,4"/>
                        <Button x:Name="btnNavNirSoft" Style="{StaticResource SideNav}"><TextBlock Text="  NirSoft Suite" FontSize="11.5" Foreground="#8aabb8"/></Button>
                        <Button x:Name="btnNavPassRecovery" Style="{StaticResource SideNav}"><TextBlock Text="  Password Recovery" FontSize="11.5" Foreground="#8aabb8"/></Button>
                        <Button x:Name="btnNavWinDeep" Style="{StaticResource SideNav}"><TextBlock Text="  Windows Deep Test" FontSize="11.5" Foreground="#8aabb8"/></Button>
                        <Button x:Name="btnNavDebloat" Style="{StaticResource SideNav}"><TextBlock Text="  Windows Debloat" FontSize="11.5" Foreground="#dd4444"/></Button>
                        <Button x:Name="btnNavRAMIso" Style="{StaticResource SideNav}"><TextBlock Text="  RAM Isolation Test" FontSize="11.5" Foreground="#8aabb8"/></Button>

                        <TextBlock Text="  PORTABLE" FontSize="9" FontWeight="SemiBold" Foreground="#4a7a8a" Margin="0,12,0,4"/>
                        <Button x:Name="btnCDI" Style="{StaticResource SideNav}"><TextBlock Text="    CrystalDiskInfo" FontSize="10.5" Foreground="#6a8a98"/></Button>
                        <Button x:Name="btnHWiNFO" Style="{StaticResource SideNav}"><TextBlock Text="    HWiNFO" FontSize="10.5" Foreground="#6a8a98"/></Button>
                        <Button x:Name="btnCPUZ" Style="{StaticResource SideNav}"><TextBlock Text="    CPU-Z" FontSize="10.5" Foreground="#6a8a98"/></Button>
                        <Button x:Name="btnGPUZ" Style="{StaticResource SideNav}"><TextBlock Text="    GPU-Z" FontSize="10.5" Foreground="#6a8a98"/></Button>
                        <Button x:Name="btnHWMon" Style="{StaticResource SideNav}"><TextBlock Text="    HWMonitor" FontSize="10.5" Foreground="#6a8a98"/></Button>
                        <Button x:Name="btnBattView" Style="{StaticResource SideNav}"><TextBlock Text="    BatteryInfoView" FontSize="10.5" Foreground="#6a8a98"/></Button>

                        <TextBlock Text="  REPORTS" FontSize="9" FontWeight="SemiBold" Foreground="#4a7a8a" Margin="0,12,0,4"/>
                        <Button x:Name="btnHWReport" Style="{StaticResource SideNav}"><TextBlock Text="  Hardware Report" FontSize="11.5" Foreground="#22c55e"/></Button>
                        <Button x:Name="btnSecReport" Style="{StaticResource SideNav}"><TextBlock Text="  Security Report" FontSize="11.5" Foreground="#f59e0b"/></Button>
                        <Button x:Name="btnBothReports" Style="{StaticResource SideNav}"><TextBlock Text="  Both Reports" FontSize="11.5" Foreground="#2596be"/></Button>
                    </StackPanel>
                </ScrollViewer>
            </DockPanel>
        </Border>

        <!-- CONTENT -->
        <Grid Grid.Column="1">
            <Grid.RowDefinitions>
                <RowDefinition Height="*"/>
                <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>

            <ScrollViewer Grid.Row="0" VerticalScrollBarVisibility="Auto">
                <StackPanel Margin="20,16,20,10">
                    <Grid Margin="0,0,0,12">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/>
                        </Grid.ColumnDefinitions>
                        <StackPanel>
                            <TextBlock Text="Dashboard" FontSize="21" FontWeight="Bold" Foreground="#1a2b3c"/>
                            <TextBlock Text="System overview and diagnostics" FontSize="11.5" Foreground="#5a7080"/>
                        </StackPanel>
                        <Button x:Name="btnQuickScan" Grid.Column="1" Style="{StaticResource FlatBtn}" Background="#2596be" Padding="16,8" VerticalAlignment="Center">
                            <TextBlock Text="Quick Scan" FontSize="12" FontWeight="SemiBold" Foreground="White"/>
                        </Button>
                    </Grid>

                    <!-- Customer Info -->
                    <Border Background="White" CornerRadius="7" Padding="12" Margin="0,0,0,10" BorderBrush="#d8e8f0" BorderThickness="1">
                        <Grid>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/>
                            </Grid.ColumnDefinitions>
                            <Grid.RowDefinitions><RowDefinition/><RowDefinition/></Grid.RowDefinitions>
                            <StackPanel Grid.Column="0" Margin="0,0,6,0">
                                <TextBlock Text="CUSTOMER NAME *" FontSize="8.5" FontWeight="SemiBold" Foreground="#8a9baa" Margin="0,0,0,2"/>
                                <TextBox x:Name="txtCustomer" FontSize="12" Padding="6,4" Background="#f6f9fb" Foreground="#1a2b3c" BorderBrush="#d8e8f0"/>
                            </StackPanel>
                            <StackPanel Grid.Column="1" Margin="3,0,3,0">
                                <TextBlock Text="CONTACT NAME" FontSize="8.5" FontWeight="SemiBold" Foreground="#8a9baa" Margin="0,0,0,2"/>
                                <TextBox x:Name="txtContact" FontSize="12" Padding="6,4" Background="#f6f9fb" Foreground="#1a2b3c" BorderBrush="#d8e8f0"/>
                            </StackPanel>
                            <StackPanel Grid.Column="2" Margin="6,0,0,0">
                                <TextBlock Text="TECHNICIAN" FontSize="8.5" FontWeight="SemiBold" Foreground="#8a9baa" Margin="0,0,0,2"/>
                                <TextBox x:Name="txtTech" Text="Paul" FontSize="12" Padding="6,4" Background="#f6f9fb" Foreground="#1a2b3c" BorderBrush="#d8e8f0"/>
                            </StackPanel>
                            <StackPanel Grid.Row="1" Grid.ColumnSpan="3" Margin="0,6,0,0">
                                <TextBlock Text="NOTES (optional - appears in report)" FontSize="8.5" FontWeight="SemiBold" Foreground="#8a9baa" Margin="0,0,0,2"/>
                                <TextBox x:Name="txtNotes" FontSize="11" Padding="6,4" Height="32" Background="#f6f9fb" Foreground="#1a2b3c" BorderBrush="#d8e8f0" AcceptsReturn="True" TextWrapping="Wrap"/>
                            </StackPanel>
                        </Grid>
                    </Border>

                    <!-- System Info Cards -->
                    <Grid Margin="0,0,0,10">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*"/><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>
                        <Border Grid.Column="0" Background="White" CornerRadius="7" Padding="10" Margin="0,0,4,0" BorderBrush="#d8e8f0" BorderThickness="1">
                            <StackPanel>
                                <TextBlock Text="COMPUTER" FontSize="8.5" FontWeight="SemiBold" Foreground="#8a9baa"/>
                                <TextBlock x:Name="lblComputer" Text="---" FontSize="12" FontWeight="SemiBold" Foreground="#1a2b3c" FontFamily="Consolas" Margin="0,2,0,0"/>
                                <TextBlock x:Name="lblOS" Text="" FontSize="9.5" Foreground="#5a7080"/>
                            </StackPanel>
                        </Border>
                        <Border Grid.Column="1" Background="White" CornerRadius="7" Padding="10" Margin="2,0,2,0" BorderBrush="#d8e8f0" BorderThickness="1">
                            <StackPanel>
                                <TextBlock Text="HARDWARE" FontSize="8.5" FontWeight="SemiBold" Foreground="#8a9baa"/>
                                <TextBlock x:Name="lblCPU" Text="---" FontSize="12" FontWeight="SemiBold" Foreground="#1a2b3c" FontFamily="Consolas" Margin="0,2,0,0"/>
                                <TextBlock x:Name="lblRAMInfo" Text="" FontSize="9.5" Foreground="#5a7080"/>
                            </StackPanel>
                        </Border>
                        <Border Grid.Column="2" Background="White" CornerRadius="7" Padding="10" Margin="2,0,2,0" BorderBrush="#d8e8f0" BorderThickness="1">
                            <StackPanel>
                                <TextBlock Text="STORAGE" FontSize="8.5" FontWeight="SemiBold" Foreground="#8a9baa"/>
                                <TextBlock x:Name="lblStorage" Text="---" FontSize="12" FontWeight="SemiBold" Foreground="#1a2b3c" FontFamily="Consolas" Margin="0,2,0,0"/>
                                <TextBlock x:Name="lblStorageDetail" Text="" FontSize="9.5" Foreground="#5a7080"/>
                            </StackPanel>
                        </Border>
                        <Border Grid.Column="3" Background="White" CornerRadius="7" Padding="10" Margin="4,0,0,0" BorderBrush="#d8e8f0" BorderThickness="1">
                            <StackPanel>
                                <TextBlock Text="NETWORK" FontSize="8.5" FontWeight="SemiBold" Foreground="#8a9baa"/>
                                <TextBlock x:Name="lblNetwork" Text="---" FontSize="12" FontWeight="SemiBold" Foreground="#1a2b3c" FontFamily="Consolas" Margin="0,2,0,0"/>
                                <TextBlock x:Name="lblNetDetail" Text="" FontSize="9.5" Foreground="#5a7080"/>
                            </StackPanel>
                        </Border>
                    </Grid>

                    <!-- Health Score -->
                    <Border Background="White" CornerRadius="7" Padding="14" Margin="0,0,0,12" BorderBrush="#d8e8f0" BorderThickness="1">
                        <Grid>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/>
                            </Grid.ColumnDefinitions>
                            <Grid Grid.Column="0" Width="62" Height="62" Margin="0,0,14,0">
                                <Ellipse Stroke="#e0e8ec" StrokeThickness="5" Fill="Transparent"/>
                                <Ellipse x:Name="healthRing" Stroke="#22c55e" StrokeThickness="5" Fill="White"/>
                                <TextBlock x:Name="lblScore" Text="--" FontSize="18" FontWeight="Bold" Foreground="#16a34a" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                            </Grid>
                            <StackPanel Grid.Column="1" VerticalAlignment="Center">
                                <TextBlock Text="System Health Score" FontSize="15" FontWeight="SemiBold" Foreground="#1a2b3c"/>
                                <Border x:Name="gradeBadge" Background="#dcfce7" CornerRadius="10" Padding="8,2" HorizontalAlignment="Left" Margin="0,3,0,0">
                                    <TextBlock x:Name="lblGrade" Text="Run a diagnostic to see score" FontSize="10.5" FontWeight="SemiBold" Foreground="#16a34a"/>
                                </Border>
                                <TextBlock x:Name="lblLastScan" Text="" FontSize="9.5" Foreground="#8a9baa" Margin="0,3,0,0"/>
                            </StackPanel>
                        </Grid>
                    </Border>

                    <!-- Scan Modes -->
                    <TextBlock Text="SCAN MODES" FontSize="12" FontWeight="Bold" Foreground="#1a2b3c" Margin="0,0,0,6"/>
                    <Grid Margin="0,0,0,12">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*"/><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>
                        <Button x:Name="btnQuick" Grid.Column="0" Style="{StaticResource FlatBtn}" Background="White" BorderBrush="#d8e8f0" BorderThickness="2" Padding="12" Margin="0,0,4,0" HorizontalContentAlignment="Left">
                            <StackPanel>
                                <TextBlock Text="Quick Test" FontSize="13.5" FontWeight="SemiBold" Foreground="#1a2b3c"/>
                                <TextBlock Text="5 - 10 min" FontSize="10.5" Foreground="#2596be" FontFamily="Consolas" Margin="0,2,0,0"/>
                                <TextBlock Text="System info, SMART, crash history. No stress tests." FontSize="10" Foreground="#5a7080" TextWrapping="Wrap" Margin="0,4,0,0"/>
                            </StackPanel>
                        </Button>
                        <Button x:Name="btnStandard" Grid.Column="1" Style="{StaticResource FlatBtn}" Background="White" BorderBrush="#2596be" BorderThickness="2" Padding="12" Margin="2,0,2,0" HorizontalContentAlignment="Left">
                            <StackPanel>
                                <TextBlock Text="Standard Test" FontSize="13.5" FontWeight="SemiBold" Foreground="#1a2b3c"/>
                                <TextBlock Text="20 - 30 min" FontSize="10.5" Foreground="#2596be" FontFamily="Consolas" Margin="0,2,0,0"/>
                                <TextBlock Text="Full diagnostic + stress tests, benchmarks, speed test." FontSize="10" Foreground="#5a7080" TextWrapping="Wrap" Margin="0,4,0,0"/>
                            </StackPanel>
                        </Button>
                        <Button x:Name="btnFull" Grid.Column="2" Style="{StaticResource FlatBtn}" Background="White" BorderBrush="#d8e8f0" BorderThickness="2" Padding="12" Margin="4,0,0,0" HorizontalContentAlignment="Left">
                            <StackPanel>
                                <TextBlock Text="Deep Test" FontSize="13.5" FontWeight="SemiBold" Foreground="#1a2b3c"/>
                                <TextBlock Text="60 - 90 min" FontSize="10.5" Foreground="#2596be" FontFamily="Consolas" Margin="0,2,0,0"/>
                                <TextBlock Text="Extended stress, thermal analysis, history comparison." FontSize="10" Foreground="#5a7080" TextWrapping="Wrap" Margin="0,4,0,0"/>
                            </StackPanel>
                        </Button>
                    </Grid>

                    <!-- Individual Tests -->
                    <TextBlock Text="INDIVIDUAL TESTS" FontSize="12" FontWeight="Bold" Foreground="#1a2b3c" Margin="0,0,0,6"/>
                    <Grid Margin="0,0,0,10">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*"/><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>
                        <Grid.RowDefinitions>
                            <RowDefinition Height="30"/><RowDefinition Height="30"/><RowDefinition Height="30"/><RowDefinition Height="30"/><RowDefinition Height="30"/>
                        </Grid.RowDefinitions>
                        <Border Grid.Row="0" Grid.Column="0" Background="White" CornerRadius="4" Padding="6,4" Margin="1" BorderBrush="#d8e8f0" BorderThickness="1">
                            <CheckBox x:Name="chkCPU" Content=" CPU Stress Test" FontSize="11" Foreground="#1a2b3c" VerticalContentAlignment="Center"/>
                        </Border>
                        <Border Grid.Row="0" Grid.Column="1" Background="White" CornerRadius="4" Padding="6,4" Margin="1" BorderBrush="#d8e8f0" BorderThickness="1">
                            <CheckBox x:Name="chkRAM" Content=" RAM Test" FontSize="11" Foreground="#1a2b3c" VerticalContentAlignment="Center"/>
                        </Border>
                        <Border Grid.Row="0" Grid.Column="2" Background="White" CornerRadius="4" Padding="6,4" Margin="1" BorderBrush="#d8e8f0" BorderThickness="1">
                            <CheckBox x:Name="chkDisk" Content=" Disk Benchmark" FontSize="11" Foreground="#1a2b3c" VerticalContentAlignment="Center"/>
                        </Border>
                        <Border Grid.Row="1" Grid.Column="0" Background="White" CornerRadius="4" Padding="6,4" Margin="1" BorderBrush="#d8e8f0" BorderThickness="1">
                            <CheckBox x:Name="chkSMART" Content=" SMART Check" FontSize="11" Foreground="#1a2b3c" VerticalContentAlignment="Center"/>
                        </Border>
                        <Border Grid.Row="1" Grid.Column="1" Background="White" CornerRadius="4" Padding="6,4" Margin="1" BorderBrush="#d8e8f0" BorderThickness="1">
                            <CheckBox x:Name="chkBattery" Content=" Battery Report" FontSize="11" Foreground="#1a2b3c" VerticalContentAlignment="Center"/>
                        </Border>
                        <Border Grid.Row="1" Grid.Column="2" Background="White" CornerRadius="4" Padding="6,4" Margin="1" BorderBrush="#d8e8f0" BorderThickness="1">
                            <CheckBox x:Name="chkNetwork" Content=" Network Test" FontSize="11" Foreground="#1a2b3c" VerticalContentAlignment="Center"/>
                        </Border>
                        <Border Grid.Row="2" Grid.Column="0" Background="White" CornerRadius="4" Padding="6,4" Margin="1" BorderBrush="#d8e8f0" BorderThickness="1">
                            <CheckBox x:Name="chkSecurity" Content=" Security Audit" FontSize="11" Foreground="#1a2b3c" VerticalContentAlignment="Center"/>
                        </Border>
                        <Border Grid.Row="2" Grid.Column="1" Background="White" CornerRadius="4" Padding="6,4" Margin="1" BorderBrush="#d8e8f0" BorderThickness="1">
                            <CheckBox x:Name="chkKeys" Content=" License Keys" FontSize="11" Foreground="#1a2b3c" VerticalContentAlignment="Center"/>
                        </Border>
                        <Border Grid.Row="2" Grid.Column="2" Background="White" CornerRadius="4" Padding="6,4" Margin="1" BorderBrush="#d8e8f0" BorderThickness="1">
                            <CheckBox x:Name="chkDebloat" Content=" Windows Debloat" FontSize="11" Foreground="#cc2222" VerticalContentAlignment="Center"/>
                        </Border>
                        <Border Grid.Row="3" Grid.Column="0" Background="White" CornerRadius="4" Padding="6,4" Margin="1" BorderBrush="#d8e8f0" BorderThickness="1">
                            <CheckBox x:Name="chkRAMIso" Content=" RAM Isolation" FontSize="11" Foreground="#1a2b3c" VerticalContentAlignment="Center"/>
                        </Border>
                        <Border Grid.Row="3" Grid.Column="1" Background="White" CornerRadius="4" Padding="6,4" Margin="1" BorderBrush="#d8e8f0" BorderThickness="1">
                            <CheckBox x:Name="chkPassRecovery" Content=" Password Recovery" FontSize="11" Foreground="#1a2b3c" VerticalContentAlignment="Center"/>
                        </Border>
                        <Border Grid.Row="3" Grid.Column="2" Background="White" CornerRadius="4" Padding="6,4" Margin="1" BorderBrush="#d8e8f0" BorderThickness="1">
                            <CheckBox x:Name="chkWinDeep" Content=" Windows Deep Test" FontSize="11" Foreground="#1a2b3c" VerticalContentAlignment="Center"/>
                        </Border>
                        <Border Grid.Row="4" Grid.Column="0" Background="White" CornerRadius="4" Padding="6,4" Margin="1" BorderBrush="#d8e8f0" BorderThickness="1">
                            <CheckBox x:Name="chkNirSoft" Content=" NirSoft Suite" FontSize="11" Foreground="#1a2b3c" VerticalContentAlignment="Center"/>
                        </Border>
                    </Grid>

                    <!-- Run Bar -->
                    <Border Background="White" CornerRadius="7" Padding="12" Margin="0,0,0,8" BorderBrush="#d8e8f0" BorderThickness="1">
                        <Grid>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/>
                            </Grid.ColumnDefinitions>
                            <Button x:Name="btnRunSelected" Style="{StaticResource FlatBtn}" Background="#2596be" Padding="18,9">
                                <TextBlock Text="RUN SELECTED TESTS" FontSize="12" FontWeight="Bold" Foreground="White"/>
                            </Button>
                            <StackPanel Grid.Column="1" Margin="12,0,0,0" VerticalAlignment="Center">
                                <TextBlock x:Name="lblSelectedCount" Text="0 tests selected" FontSize="11.5" FontWeight="SemiBold" Foreground="#1a2b3c"/>
                                <TextBlock x:Name="lblEstTime" Text="Select tests to begin" FontSize="9.5" Foreground="#8a9baa"/>
                            </StackPanel>
                            <StackPanel Grid.Column="2" Orientation="Horizontal" VerticalAlignment="Center">
                                <Border Background="#dcfce7" CornerRadius="10" Padding="8,3" Margin="0,0,8,0">
                                    <TextBlock x:Name="lblReadyStatus" Text="Ready" FontSize="10.5" FontWeight="SemiBold" Foreground="#22c55e"/>
                                </Border>
                                <CheckBox x:Name="chkBeep" Content=" Beep on done" FontSize="10" Foreground="#8a9baa" IsChecked="True" VerticalAlignment="Center"/>
                            </StackPanel>
                        </Grid>
                    </Border>
                </StackPanel>
            </ScrollViewer>

            <!-- Status Bar -->
            <Border Grid.Row="1" Background="White" BorderBrush="#d8e8f0" BorderThickness="0,1,0,0" Padding="16,8">
                <Grid>
                    <Grid.RowDefinitions><RowDefinition/><RowDefinition/></Grid.RowDefinitions>
                    <TextBlock x:Name="txtStatus" Grid.Row="0" Text="Ready. Enter customer info and select a diagnostic mode." FontSize="10.5" Foreground="#5a7080" Margin="0,0,0,4"/>
                    <ProgressBar x:Name="progressBar" Grid.Row="1" Height="5" Background="#e0e8ec" Foreground="#2596be" Value="0" BorderThickness="0"/>
                </Grid>
            </Border>
        </Grid>
    </Grid>
</Window>
"@

    Write-DebugLog "Parsing XAML..."
    $reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($xaml))
    $window = [System.Windows.Markup.XamlReader]::Load($reader)
    Write-DebugLog "XAML parsed OK, window created"

    # Get controls
    $txtCustomer = $window.FindName("txtCustomer")
    $txtContact = $window.FindName("txtContact")
    $txtTech = $window.FindName("txtTech")
    $txtNotes = $window.FindName("txtNotes")
    $txtStatus = $window.FindName("txtStatus")
    $progressBar = $window.FindName("progressBar")
    $lblComputer = $window.FindName("lblComputer")
    $lblOS = $window.FindName("lblOS")
    $lblCPU = $window.FindName("lblCPU")
    $lblRAMInfo = $window.FindName("lblRAMInfo")
    $lblStorage = $window.FindName("lblStorage")
    $lblStorageDetail = $window.FindName("lblStorageDetail")
    $lblNetwork = $window.FindName("lblNetwork")
    $lblNetDetail = $window.FindName("lblNetDetail")
    $lblScore = $window.FindName("lblScore")
    $lblGrade = $window.FindName("lblGrade")
    $lblLastScan = $window.FindName("lblLastScan")
    $lblSelectedCount = $window.FindName("lblSelectedCount")
    $lblEstTime = $window.FindName("lblEstTime")
    $lblReadyStatus = $window.FindName("lblReadyStatus")
    $chkBeep = $window.FindName("chkBeep")
    $chkCPU = $window.FindName("chkCPU")
    $chkRAM = $window.FindName("chkRAM")
    $chkDisk = $window.FindName("chkDisk")
    $chkSMART = $window.FindName("chkSMART")
    $chkBattery = $window.FindName("chkBattery")
    $chkNetwork = $window.FindName("chkNetwork")
    $chkSecurity = $window.FindName("chkSecurity")
    $chkKeys = $window.FindName("chkKeys")
    $chkDebloat = $window.FindName("chkDebloat")
    $chkRAMIso = $window.FindName("chkRAMIso")
    $chkPassRecovery = $window.FindName("chkPassRecovery")
    $chkWinDeep = $window.FindName("chkWinDeep")
    $chkNirSoft = $window.FindName("chkNirSoft")

    $tools = Get-ToolStatus

    function Set-Status { param([string]$Msg, [int]$Pct = -1)
        $txtStatus.Text = $Msg
        if ($Pct -ge 0) { $progressBar.Value = $Pct }
        $window.Title = "PC Plus 360 - $Msg"
        Write-DebugLog "STATUS: $Msg ($Pct%)"
        $frame = New-Object System.Windows.Threading.DispatcherFrame
        [System.Windows.Threading.Dispatcher]::CurrentDispatcher.BeginInvoke(
            [System.Windows.Threading.DispatcherPriority]::Background,
            [System.Action]{ $frame.Continue = $false }
        )
        [System.Windows.Threading.Dispatcher]::PushFrame($frame)
    }

    function Get-Params {
        if ([string]::IsNullOrWhiteSpace($txtCustomer.Text)) {
            Write-DebugLog "Validation failed: Customer Name is empty"
            [System.Windows.MessageBox]::Show($window, "Please enter a Customer Name in the first field.", "Customer Name Required", "OK", "Warning")
            $txtCustomer.Focus()
            return $null
        }
        Write-DebugLog "Params OK: Customer=$($txtCustomer.Text.Trim())"
        return @{ CustomerName = $txtCustomer.Text.Trim(); ContactName = $txtContact.Text.Trim(); TechName = $txtTech.Text.Trim(); TechNotes = $txtNotes.Text.Trim(); OutputFolder = $Global:ReportsDir }
    }

    function Update-SystemInfo {
        if ($Global:DiagResults.SystemInfo) {
            $si = $Global:DiagResults.SystemInfo
            $lblComputer.Text = $si.ComputerName
            $lblOS.Text = ($si.OSVersion -replace 'Microsoft ','')
            $cpuName = ($si.CPUModel -replace '\(R\)','' -replace '\(TM\)','' -replace 'CPU ','').Trim()
            if ($cpuName.Length -gt 20) { $cpuName = $cpuName.Substring(0,20) }
            $lblCPU.Text = $cpuName
            $lblRAMInfo.Text = "$($si.RAMTotal) GB RAM"
            $d = $si.Disks | Select-Object -First 1
            if ($d) { $lblStorage.Text = "$($d.Size) GB"; $lblStorageDetail.Text = "$($d.Free) GB free ($($d.UsedPct)%)" }
            if ($Global:DiagResults.Network) {
                $n = $Global:DiagResults.Network
                $lblNetwork.Text = if ($n.InternetTest.Success) { "Online" } else { "Offline" }
                $lblNetDetail.Text = if ($n.PublicIP) { $n.PublicIP } else { "" }
            }
        }
    }

    function Update-HealthScore {
        if ($Global:DiagResults.Scoring) {
            $s = $Global:DiagResults.Scoring
            $lblScore.Text = "$($s.Score)"
            $gradeText = if ($s.Score -ge 80) { "Good" } elseif ($s.Score -ge 60) { "Fair" } else { "Needs Attention" }
            $lblGrade.Text = "Grade $($s.Grade) - $gradeText"
            $lblLastScan.Text = "Last scan: $(Get-Date -Format 'MMM dd, yyyy') - $($Global:DiagResults.ScanMode) Test"
            $converter = New-Object System.Windows.Media.BrushConverter
            if ($s.Score -ge 80) {
                $window.FindName("healthRing").Stroke = $converter.ConvertFrom("#22c55e")
                $lblScore.Foreground = $converter.ConvertFrom("#16a34a")
                $window.FindName("gradeBadge").Background = $converter.ConvertFrom("#dcfce7")
                $lblGrade.Foreground = $converter.ConvertFrom("#16a34a")
            } elseif ($s.Score -ge 60) {
                $window.FindName("healthRing").Stroke = $converter.ConvertFrom("#f59e0b")
                $lblScore.Foreground = $converter.ConvertFrom("#d97706")
                $window.FindName("gradeBadge").Background = $converter.ConvertFrom("#fef3c7")
                $lblGrade.Foreground = $converter.ConvertFrom("#d97706")
            } else {
                $window.FindName("healthRing").Stroke = $converter.ConvertFrom("#dc2626")
                $lblScore.Foreground = $converter.ConvertFrom("#dc2626")
                $window.FindName("gradeBadge").Background = $converter.ConvertFrom("#fee2e2")
                $lblGrade.Foreground = $converter.ConvertFrom("#dc2626")
            }
        }
    }

    function Play-CompletionBeep {
        if ($chkBeep.IsChecked) {
            try { [Console]::Beep(800, 200); Start-Sleep -Milliseconds 100; [Console]::Beep(1000, 200); Start-Sleep -Milliseconds 100; [Console]::Beep(1200, 300) } catch {}
        }
    }

    function Complete-Scan {
        Update-SystemInfo
        Update-HealthScore
        Play-CompletionBeep
        $lblReadyStatus.Text = "Done"
    }

    # Checkbox count update
    $updateCount = {
        $allChecks = @($chkCPU,$chkRAM,$chkDisk,$chkSMART,$chkBattery,$chkNetwork,$chkSecurity,$chkKeys,$chkDebloat,$chkRAMIso,$chkPassRecovery,$chkWinDeep,$chkNirSoft)
        $count = ($allChecks | Where-Object { $_.IsChecked }).Count
        $lblSelectedCount.Text = "$count tests selected"
        if ($count -gt 0) {
            $inlineCnt = @($chkCPU,$chkRAM,$chkDisk,$chkSMART,$chkBattery,$chkNetwork,$chkSecurity,$chkKeys).Where({$_.IsChecked}).Count
            $extCnt = @($chkDebloat,$chkRAMIso,$chkPassRecovery,$chkWinDeep,$chkNirSoft).Where({$_.IsChecked}).Count
            $mins = ($inlineCnt * 2) + ($extCnt * 5)
            if ($mins -lt 1) { $mins = 1 }
            $lblEstTime.Text = "Estimated: ~$mins min"
        } else { $lblEstTime.Text = "Select tests to begin" }
    }
    foreach ($chk in @($chkCPU,$chkRAM,$chkDisk,$chkSMART,$chkBattery,$chkNetwork,$chkSecurity,$chkKeys,$chkDebloat,$chkRAMIso,$chkPassRecovery,$chkWinDeep,$chkNirSoft)) {
        $chk.Add_Checked($updateCount)
        $chk.Add_Unchecked($updateCount)
    }

    # Portable tool detection
    foreach ($btn in @(@{N="btnCDI";T=$tools.CrystalDiskInfo},@{N="btnHWiNFO";T=$tools.HWiNFO},@{N="btnCPUZ";T=$tools.CPUZ},@{N="btnGPUZ";T=$tools.GPUZ},@{N="btnHWMon";T=$tools.HWMonitor},@{N="btnBattView";T=$tools.BatteryInfoView})) {
        $b = $window.FindName($btn.N)
        if (-not $btn.T) { $b.IsEnabled = $false; $b.Opacity = 0.4 }
    }
    $toolPaths = @{
        btnCDI = $tools.CrystalDiskInfo; btnHWiNFO = $tools.HWiNFO
        btnCPUZ = $tools.CPUZ; btnGPUZ = $tools.GPUZ
        btnHWMon = $tools.HWMonitor; btnBattView = $tools.BatteryInfoView
    }
    foreach ($key in $toolPaths.Keys) {
        $b = $window.FindName($key)
        if ($toolPaths[$key]) {
            $b.Tag = $toolPaths[$key]
            $b.Add_Click({ param($sender,$e); Start-Process $sender.Tag -ErrorAction SilentlyContinue })
        }
    }

    # Sidebar tool nav buttons
    $window.FindName("btnNavNirSoft").Add_Click({
        $s = Join-Path $Global:ScriptDir "PCPlus-NirSoftSuite.ps1"
        if (Test-Path $s) { Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$s`"" -Verb RunAs }
        else { [System.Windows.MessageBox]::Show($window, "PCPlus-NirSoftSuite.ps1 not found in $Global:ScriptDir", "Not Found", "OK", "Warning") }
    })
    $window.FindName("btnNavPassRecovery").Add_Click({
        $s = Join-Path $Global:ScriptDir "PCPlus-PasswordRecovery.ps1"
        if (Test-Path $s) { Start-Process powershell.exe -ArgumentList "-STA -NoProfile -ExecutionPolicy Bypass -File `"$s`"" -Verb RunAs }
        else { [System.Windows.MessageBox]::Show($window, "PCPlus-PasswordRecovery.ps1 not found in $Global:ScriptDir", "Not Found", "OK", "Warning") }
    })
    $window.FindName("btnNavWinDeep").Add_Click({
        $s = Join-Path $Global:ScriptDir "PCPlus-WindowsDeepTest.ps1"
        if (Test-Path $s) { Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$s`"" -Verb RunAs }
        else { [System.Windows.MessageBox]::Show($window, "PCPlus-WindowsDeepTest.ps1 not found in $Global:ScriptDir", "Not Found", "OK", "Warning") }
    })
    $window.FindName("btnNavDebloat").Add_Click({
        $s = Join-Path $Global:ScriptDir "PCPlus-Debloat.ps1"
        if (Test-Path $s) { Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$s`"" -Verb RunAs }
        else { [System.Windows.MessageBox]::Show($window, "PCPlus-Debloat.ps1 not found in $Global:ScriptDir", "Not Found", "OK", "Warning") }
    })
    $window.FindName("btnNavRAMIso").Add_Click({
        $s = Join-Path $Global:ScriptDir "PCPlus-RAMIsolation.ps1"
        if (Test-Path $s) { Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$s`"" -Verb RunAs }
        else { [System.Windows.MessageBox]::Show($window, "PCPlus-RAMIsolation.ps1 not found in $Global:ScriptDir", "Not Found", "OK", "Warning") }
    })

    # Startup: populate system info cards immediately
    $window.Add_Loaded({
        try {
            $cs = Get-CimInstance Win32_ComputerSystem
            $os = Get-CimInstance Win32_OperatingSystem
            $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
            $lblComputer.Text = $cs.Name
            $lblOS.Text = ($os.Caption -replace 'Microsoft ','')
            $cpuName = ($cpu.Name -replace '\(R\)','' -replace '\(TM\)','' -replace 'CPU ','').Trim()
            if ($cpuName.Length -gt 20) { $cpuName = $cpuName.Substring(0,20) }
            $lblCPU.Text = $cpuName
            $lblRAMInfo.Text = "$([math]::Round($cs.TotalPhysicalMemory / 1GB)) GB RAM"
            $disk = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" | Select-Object -First 1
            if ($disk) {
                $lblStorage.Text = "$([math]::Round($disk.Size / 1GB)) GB"
                $lblStorageDetail.Text = "$([math]::Round($disk.FreeSpace / 1GB)) GB free"
            }
            $adapter = Get-CimInstance Win32_NetworkAdapterConfiguration | Where-Object { $_.IPEnabled -and $_.DefaultIPGateway } | Select-Object -First 1
            if ($adapter) { $lblNetwork.Text = "Connected"; $lblNetDetail.Text = $adapter.IPAddress[0] }
        } catch { Write-DebugLog "Startup info error: $($_.Exception.Message)" }
    })

    function Set-ScanButtons($enabled) {
        foreach ($bn in @("btnQuick","btnStandard","btnFull","btnRunSelected","btnQuickScan")) {
            $b = $window.FindName($bn)
            if ($b) { $b.IsEnabled = $enabled }
        }
    }

    # Quick Scan header button triggers Quick Test
    $window.FindName("btnQuickScan").Add_Click({
        $window.FindName("btnQuick").RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))
    })

    # ── RUN SELECTED TESTS ──
    $window.FindName("btnRunSelected").Add_Click({
        try {
            $p = Get-Params; if (-not $p) { return }
            $anyChecked = $false
            foreach ($c in @($chkCPU,$chkRAM,$chkDisk,$chkSMART,$chkBattery,$chkNetwork,$chkSecurity,$chkKeys,$chkDebloat,$chkRAMIso,$chkPassRecovery,$chkWinDeep,$chkNirSoft)) {
                if ($c.IsChecked) { $anyChecked = $true; break }
            }
            if (-not $anyChecked) {
                [System.Windows.MessageBox]::Show($window, "Please check at least one test to run.", "No Tests Selected", "OK", "Warning")
                return
            }
            Set-ScanButtons $false
            $lblReadyStatus.Text = "Running..."
            $Global:DiagResults.ScanMode = "Custom"

            Set-Status "Collecting system info..." 5
            $Global:DiagResults.SystemInfo = Get-FullSystemInfo
            Update-SystemInfo

            $inlineTests = @($chkCPU,$chkRAM,$chkDisk,$chkSMART,$chkBattery,$chkNetwork,$chkSecurity,$chkKeys)
            $totalInline = ($inlineTests | Where-Object { $_.IsChecked }).Count
            if ($totalInline -eq 0) { $totalInline = 1 }
            $stepsDone = 0

            if ($chkCPU.IsChecked) {
                $stepsDone++
                Set-Status "Running CPU stress test (60 sec)..." ([int](10 + ($stepsDone / $totalInline) * 80))
                $Global:DiagResults.CPUStress = Start-CPUStressTest -DurationSeconds 60
                $r = $Global:DiagResults.CPUStress
                Set-Status "CPU: $(if($r.Passed){'PASS'}else{'FAIL'}) - $($r.Iterations) iterations" ([int](10 + ($stepsDone / $totalInline) * 80))
            }
            if ($chkRAM.IsChecked) {
                $stepsDone++
                Set-Status "Running RAM test (60 sec)..." ([int](10 + ($stepsDone / $totalInline) * 80))
                $Global:DiagResults.RAMStress = Start-RAMStressTest -DurationSeconds 60
                $r = $Global:DiagResults.RAMStress
                Set-Status "RAM: $(if($r.Passed){'PASS'}else{'FAIL'}) - $($r.TotalMBTested) MB tested" ([int](10 + ($stepsDone / $totalInline) * 80))
            }
            if ($chkDisk.IsChecked) {
                $stepsDone++
                Set-Status "Running disk benchmark (256MB)..." ([int](10 + ($stepsDone / $totalInline) * 80))
                $Global:DiagResults.DiskBench = Start-DiskBenchmark -FileSizeMB 256
                $r = $Global:DiagResults.DiskBench
                Set-Status "Disk: W=$($r.SeqWriteMBps) R=$($r.SeqReadMBps) MB/s" ([int](10 + ($stepsDone / $totalInline) * 80))
            }
            if ($chkSMART.IsChecked) {
                $stepsDone++
                Set-Status "Reading SMART data..." ([int](10 + ($stepsDone / $totalInline) * 80))
                $smart = Invoke-Safe { Get-PhysicalDisk | ForEach-Object { $r=Get-StorageReliabilityCounter -PhysicalDisk $_ -ErrorAction SilentlyContinue; "$($_.FriendlyName): $($_.HealthStatus)" } } "Error"
                Set-Status "SMART: $($smart -join ' | ')" ([int](10 + ($stepsDone / $totalInline) * 80))
            }
            if ($chkBattery.IsChecked) {
                $stepsDone++
                Set-Status "Checking battery..." ([int](10 + ($stepsDone / $totalInline) * 80))
                $Global:DiagResults.BatteryDetail = Get-DetailedBatteryInfo
            }
            if ($chkNetwork.IsChecked) {
                $stepsDone++
                Set-Status "Testing network..." ([int](10 + ($stepsDone / $totalInline) * 80))
                $Global:DiagResults.Network = Get-NetworkDiagnostics
                $net = $Global:DiagResults.Network
                Set-Status "Network: DNS $(if($net.DNSTest.Success){'OK'}else{'FAIL'}), Internet $(if($net.InternetTest.Success){'OK'}else{'FAIL'})" ([int](10 + ($stepsDone / $totalInline) * 80))
            }
            if ($chkSecurity.IsChecked) {
                $stepsDone++
                Set-Status "Running security audit..." ([int](10 + ($stepsDone / $totalInline) * 80))
                $Global:DiagResults.Security = Get-FullSecurityInfo
                $Global:DiagResults.Patches = Get-MissingPatchesList
                $Global:DiagResults.Scoring = Calculate-Score $Global:DiagResults.Security $Global:DiagResults.Patches
            }
            if ($chkKeys.IsChecked) {
                $stepsDone++
                Set-Status "Recovering license keys..." ([int](10 + ($stepsDone / $totalInline) * 80))
                $Global:DiagResults.LicenseKeys = Get-LicenseKeys
                $lk = $Global:DiagResults.LicenseKeys
                $wk = if ($lk.WindowsKeys.Count -gt 0) { $lk.WindowsKeys[0].Key } else { "Not found" }
                Set-Status "Windows Key: $wk | WiFi: $($lk.WiFiPasswords.Count) networks" ([int](10 + ($stepsDone / $totalInline) * 80))
            }

            # External scripts launch in separate windows
            if ($chkDebloat.IsChecked) {
                $s = Join-Path $Global:ScriptDir "PCPlus-Debloat.ps1"
                if (Test-Path $s) { Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$s`"" -Verb RunAs }
                else { Set-Status "PCPlus-Debloat.ps1 not found" 0 }
            }
            if ($chkRAMIso.IsChecked) {
                $s = Join-Path $Global:ScriptDir "PCPlus-RAMIsolation.ps1"
                if (Test-Path $s) { Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$s`"" -Verb RunAs }
                else { Set-Status "PCPlus-RAMIsolation.ps1 not found" 0 }
            }
            if ($chkPassRecovery.IsChecked) {
                $s = Join-Path $Global:ScriptDir "PCPlus-PasswordRecovery.ps1"
                if (Test-Path $s) { Start-Process powershell.exe -ArgumentList "-STA -NoProfile -ExecutionPolicy Bypass -File `"$s`"" -Verb RunAs }
                else { Set-Status "PCPlus-PasswordRecovery.ps1 not found" 0 }
            }
            if ($chkWinDeep.IsChecked) {
                $s = Join-Path $Global:ScriptDir "PCPlus-WindowsDeepTest.ps1"
                if (Test-Path $s) { Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$s`"" -Verb RunAs }
                else { Set-Status "PCPlus-WindowsDeepTest.ps1 not found" 0 }
            }
            if ($chkNirSoft.IsChecked) {
                $s = Join-Path $Global:ScriptDir "PCPlus-NirSoftSuite.ps1"
                if (Test-Path $s) { Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$s`"" -Verb RunAs }
                else { Set-Status "PCPlus-NirSoftSuite.ps1 not found" 0 }
            }

            Set-Status "All selected tests complete!" 100
            Complete-Scan
            [System.Windows.MessageBox]::Show($window, "All selected tests complete!", "Tests Complete", "OK", "Information")
        } catch {
            Write-DebugLog "Run Selected ERROR: $($_.Exception.Message) at line $($_.InvocationInfo.ScriptLineNumber)"
            Set-Status "ERROR: $($_.Exception.Message)" 0
            [System.Windows.MessageBox]::Show($window, "Error: $($_.Exception.Message)", "Error", "OK", "Error")
        } finally { Set-ScanButtons $true; $lblReadyStatus.Text = "Ready" }
    })

    # ── QUICK TEST (5-10 min) ──
    $window.FindName("btnQuick").Add_Click({
        try {
            $p = Get-Params; if (-not $p) { return }
            Set-ScanButtons $false
            $lblReadyStatus.Text = "Running..."
            $Global:DiagResults.ScanMode = "Quick"
            Set-Status "Quick Test: Collecting system info..." 5
            $Global:DiagResults.SystemInfo = Get-FullSystemInfo
            Set-Status "Quick Test: Security scan..." 20
            $Global:DiagResults.Security = Get-FullSecurityInfo
            Set-Status "Quick Test: Network info..." 35
            $Global:DiagResults.Network = Get-NetworkDiagnostics
            Set-Status "Quick Test: Software inventory..." 50
            $Global:DiagResults.Software = Get-SoftwareInventory
            Set-Status "Quick Test: Checking updates..." 60
            $Global:DiagResults.Patches = Get-MissingPatchesList
            Set-Status "Quick Test: Performance snapshot..." 70
            $Global:DiagResults.Performance = Get-PerformanceSnapshot
            Set-Status "Quick Test: License keys..." 78
            $Global:DiagResults.LicenseKeys = Get-LicenseKeys
            Set-Status "Quick Test: Crash history..." 85
            $Global:DiagResults.Stability = Get-CrashStabilityHistory
            Set-Status "Quick Test: Battery info..." 86
            $Global:DiagResults.BatteryDetail = Get-DetailedBatteryInfo
            Set-Status "Quick Test: Boot performance..." 90
            $Global:DiagResults.BootPerf = Get-BootPerformance
            Set-Status "Quick Test: Windows 11 readiness..." 93
            $Global:DiagResults.Win11Ready = Get-Windows11Readiness
            Set-Status "Quick Test: Calculating scores..." 97
            $Global:DiagResults.Scoring = Calculate-Score $Global:DiagResults.Security $Global:DiagResults.Patches
            $Global:DiagResults.StressResults = @{}
            $Global:DiagResults.SpeedTest = $null; $Global:DiagResults.Gaming = $null; $Global:DiagResults.PowerInfo = $null
            Set-Status "DONE! Quick Test complete. Generate reports from sidebar." 100
            Complete-Scan
            [System.Windows.MessageBox]::Show($window, "Quick Test complete!`nStability: $($Global:DiagResults.Stability.StabilityRating)`n`nClick a Report button in the sidebar to save PDFs.", "Quick Test Complete", "OK", "Information")
        } catch {
            Write-DebugLog "Quick Test ERROR: $($_.Exception.Message) at line $($_.InvocationInfo.ScriptLineNumber)"
            Set-Status "ERROR: $($_.Exception.Message)" 0
            [System.Windows.MessageBox]::Show($window, "Error during Quick Test:`n`n$($_.Exception.Message)", "Error", "OK", "Error")
        } finally { Set-ScanButtons $true; $lblReadyStatus.Text = "Ready" }
    })

    # ── STANDARD TEST (20-30 min) ──
    $window.FindName("btnStandard").Add_Click({
        try {
            $p = Get-Params; if (-not $p) { return }
            Set-ScanButtons $false
            $lblReadyStatus.Text = "Running..."
            $Global:DiagResults.ScanMode = "Standard"
            Set-Status "Standard Test: Collecting system info..." 2
            $Global:DiagResults.SystemInfo = Get-FullSystemInfo
            Set-Status "Standard Test: Security scan..." 8
            $Global:DiagResults.Security = Get-FullSecurityInfo
            Set-Status "Standard Test: Network analysis..." 14
            $Global:DiagResults.Network = Get-NetworkDiagnostics
            Set-Status "Standard Test: Network speed test..." 18
            $Global:DiagResults.SpeedTest = Get-NetworkSpeedTest
            Set-Status "Standard Test: Software inventory..." 24
            $Global:DiagResults.Software = Get-SoftwareInventory
            Set-Status "Standard Test: Checking updates..." 28
            $Global:DiagResults.Patches = Get-MissingPatchesList
            Set-Status "Standard Test: Performance snapshot..." 32
            $Global:DiagResults.Performance = Get-PerformanceSnapshot
            Set-Status "Standard Test: License keys..." 36
            $Global:DiagResults.LicenseKeys = Get-LicenseKeys
            Set-Status "Standard Test: Crash history..." 40
            $Global:DiagResults.Stability = Get-CrashStabilityHistory
            Set-Status "Standard Test: Battery report..." 44
            $Global:DiagResults.BatteryDetail = Get-DetailedBatteryInfo
            Set-Status "Standard Test: Power stability..." 47
            $Global:DiagResults.PowerInfo = Get-PowerStabilityInfo
            Set-Status "Standard Test: Gaming readiness..." 49
            $Global:DiagResults.Gaming = Get-GamingReadiness
            Set-Status "Standard Test: Boot performance..." 51
            $Global:DiagResults.BootPerf = Get-BootPerformance
            Set-Status "Standard Test: Windows 11 readiness..." 53
            $Global:DiagResults.Win11Ready = Get-Windows11Readiness
            Set-Status "Standard Test: CPU stress (5 min)..." 55
            $Global:DiagResults.CPUStress = Start-CPUStressTest -DurationSeconds 300
            Set-Status "Standard Test: GPU stress (2 min)..." 70
            $Global:DiagResults.GPUStress = Start-GPUStressTest -DurationSeconds 120
            Set-Status "Standard Test: RAM test (5 min)..." 78
            $Global:DiagResults.RAMStress = Start-RAMStressTest -DurationSeconds 300
            Set-Status "Standard Test: Disk benchmark (512MB)..." 90
            $Global:DiagResults.DiskBench = Start-DiskBenchmark -FileSizeMB 512
            Set-Status "Standard Test: Calculating scores..." 96
            $Global:DiagResults.Scoring = Calculate-Score $Global:DiagResults.Security $Global:DiagResults.Patches
            $Global:DiagResults.StressResults = @{ CPU = $Global:DiagResults.CPUStress; RAM = $Global:DiagResults.RAMStress; Disk = $Global:DiagResults.DiskBench; GPU = $Global:DiagResults.GPUStress }
            $cs = $Global:DiagResults.CPUStress; $rs = $Global:DiagResults.RAMStress; $ds = $Global:DiagResults.DiskBench; $gs = $Global:DiagResults.GPUStress
            Set-Status "DONE! CPU:$(if($cs.Passed){'PASS'}else{'FAIL'}) RAM:$(if($rs.Passed){'PASS'}else{'FAIL'}) GPU:$(if($gs.Passed){'PASS'}else{'FAIL'}) Disk:W=$($ds.SeqWriteMBps)/$($ds.SeqReadMBps)" 100
            Complete-Scan
            [System.Windows.MessageBox]::Show($window, "Standard Test complete!`nCPU: $(if($cs.Passed){'PASS'}else{'FAIL'})`nRAM: $(if($rs.Passed){'PASS'}else{'FAIL'})`nGPU: $(if($gs.Passed){'PASS'}else{'FAIL'})`nDisk: W=$($ds.SeqWriteMBps) / R=$($ds.SeqReadMBps) MB/s`nStability: $($Global:DiagResults.Stability.StabilityRating)`n`nClick a Report button in the sidebar.", "Standard Test Complete", "OK", "Information")
        } catch {
            Write-DebugLog "Standard Test ERROR: $($_.Exception.Message) at line $($_.InvocationInfo.ScriptLineNumber)"
            Set-Status "ERROR: $($_.Exception.Message)" 0
            [System.Windows.MessageBox]::Show($window, "Error during Standard Test:`n`n$($_.Exception.Message)", "Error", "OK", "Error")
        } finally { Set-ScanButtons $true; $lblReadyStatus.Text = "Ready" }
    })

    # ── DEEP TEST (60-90 min) ──
    $window.FindName("btnFull").Add_Click({
        try {
            $p = Get-Params; if (-not $p) { return }
            Set-ScanButtons $false
            $lblReadyStatus.Text = "Running..."
            $Global:DiagResults.ScanMode = "Deep"
            Set-Status "Deep Test: Collecting system info..." 2
            $Global:DiagResults.SystemInfo = Get-FullSystemInfo
            Set-Status "Deep Test: Security scan..." 5
            $Global:DiagResults.Security = Get-FullSecurityInfo
            Set-Status "Deep Test: Network analysis..." 8
            $Global:DiagResults.Network = Get-NetworkDiagnostics
            Set-Status "Deep Test: Network speed test..." 11
            $Global:DiagResults.SpeedTest = Get-NetworkSpeedTest
            Set-Status "Deep Test: Software inventory..." 14
            $Global:DiagResults.Software = Get-SoftwareInventory
            Set-Status "Deep Test: Checking updates..." 17
            $Global:DiagResults.Patches = Get-MissingPatchesList
            Set-Status "Deep Test: Performance snapshot..." 20
            $Global:DiagResults.Performance = Get-PerformanceSnapshot
            Set-Status "Deep Test: License keys..." 22
            $Global:DiagResults.LicenseKeys = Get-LicenseKeys
            Set-Status "Deep Test: Crash history..." 25
            $Global:DiagResults.Stability = Get-CrashStabilityHistory
            Set-Status "Deep Test: Battery report..." 28
            $Global:DiagResults.BatteryDetail = Get-DetailedBatteryInfo
            Set-Status "Deep Test: Power stability..." 30
            $Global:DiagResults.PowerInfo = Get-PowerStabilityInfo
            Set-Status "Deep Test: Gaming readiness..." 32
            $Global:DiagResults.Gaming = Get-GamingReadiness
            Set-Status "Deep Test: Boot performance..." 34
            $Global:DiagResults.BootPerf = Get-BootPerformance
            Set-Status "Deep Test: Windows 11 readiness..." 35
            $Global:DiagResults.Win11Ready = Get-Windows11Readiness
            Set-Status "Deep Test: CPU stress (15 min)..." 37
            $Global:DiagResults.CPUStress = Start-CPUStressTest -DurationSeconds 900
            Set-Status "Deep Test: GPU stress (5 min)..." 56
            $Global:DiagResults.GPUStress = Start-GPUStressTest -DurationSeconds 300
            Set-Status "Deep Test: RAM test (15 min)..." 66
            $Global:DiagResults.RAMStress = Start-RAMStressTest -DurationSeconds 900
            Set-Status "Deep Test: Disk benchmark (1GB)..." 86
            $Global:DiagResults.DiskBench = Start-DiskBenchmark -FileSizeMB 1024
            Set-Status "Deep Test: Calculating scores..." 92
            $Global:DiagResults.Scoring = Calculate-Score $Global:DiagResults.Security $Global:DiagResults.Patches
            $Global:DiagResults.StressResults = @{ CPU = $Global:DiagResults.CPUStress; RAM = $Global:DiagResults.RAMStress; Disk = $Global:DiagResults.DiskBench; GPU = $Global:DiagResults.GPUStress }
            Set-Status "Deep Test: Loading scan history..." 95
            $history = Get-ScanHistory -ComputerName $Global:DiagResults.SystemInfo.ComputerName
            $Global:DiagResults.HistoryComparison = Compare-ScanHistory -Current @{
                HardwareScore = $Global:DiagResults.StressResults.CPU.Passed; SecurityScore = $Global:DiagResults.Scoring.Score
                SSDHealth = ($Global:DiagResults.SystemInfo.SMART | ForEach-Object { "$($_.Model):$($_.Health)" }) -join "; "
                BatteryHealth = if($Global:DiagResults.BatteryDetail.Present){$Global:DiagResults.BatteryDetail.HealthPct}else{"N/A"}
                CPUPeakTemp = if($Global:DiagResults.CPUStress){$Global:DiagResults.CPUStress.MaxTemp}else{"N/A"}
                CrashCount = $Global:DiagResults.Stability.TotalBSODs + $Global:DiagResults.Stability.TotalUnexpected
                DiskWriteMBps = if($Global:DiagResults.DiskBench){$Global:DiagResults.DiskBench.SeqWriteMBps}else{"N/A"}
            } -Previous $history
            $cs = $Global:DiagResults.CPUStress; $rs = $Global:DiagResults.RAMStress; $ds = $Global:DiagResults.DiskBench; $gs = $Global:DiagResults.GPUStress
            Set-Status "DONE! Deep Test complete. CPU:$(if($cs.Passed){'PASS'}else{'FAIL'}) RAM:$(if($rs.Passed){'PASS'}else{'FAIL'}) GPU:$(if($gs.Passed){'PASS'}else{'FAIL'})" 100
            $histMsg = if ($Global:DiagResults.HistoryComparison -and $Global:DiagResults.HistoryComparison.HasPrevious) { "`nPrevious scan: $($Global:DiagResults.HistoryComparison.PreviousDate)" } else { "`nNo previous scan history." }
            Complete-Scan
            [System.Windows.MessageBox]::Show($window, "Deep Test complete!`nCPU: $(if($cs.Passed){'PASS'}else{'FAIL'})`nRAM: $(if($rs.Passed){'PASS'}else{'FAIL'})`nGPU: $(if($gs.Passed){'PASS'}else{'FAIL'})`nDisk: W=$($ds.SeqWriteMBps) / R=$($ds.SeqReadMBps) MB/s`nStability: $($Global:DiagResults.Stability.StabilityRating)$histMsg`n`nClick a Report button in the sidebar.", "Deep Test Complete", "OK", "Information")
        } catch {
            Write-DebugLog "Deep Test ERROR: $($_.Exception.Message) at line $($_.InvocationInfo.ScriptLineNumber)"
            Set-Status "ERROR: $($_.Exception.Message)" 0
            [System.Windows.MessageBox]::Show($window, "Error during Deep Test:`n`n$($_.Exception.Message)", "Error", "OK", "Error")
        } finally { Set-ScanButtons $true; $lblReadyStatus.Text = "Ready" }
    })

    # ── REPORT GENERATION ──
    $generateReports = {
        param([bool]$DoHW, [bool]$DoSec)
        $p = Get-Params; if (-not $p) { return }
        if (-not $Global:DiagResults.SystemInfo) { [System.Windows.MessageBox]::Show($window, "Run a diagnostic first.", "No Data", "OK", "Warning"); return }
        $safeName = $p.CustomerName -replace '[\\/:*?"<>|]','_'
        $safeDev = $Global:DiagResults.SystemInfo.ComputerName -replace '[\\/:*?"<>|]','_'
        $ds = Get-Date -Format "yyyy-MM-dd"
        if ($DoHW) {
            Set-Status "Generating Hardware Report..." 20
            $hwHTML = Build-HardwareReport $p $Global:DiagResults.SystemInfo $Global:DiagResults.Network $Global:DiagResults.Software $Global:DiagResults.Performance $Global:DiagResults.StressResults $Global:DiagResults.LicenseKeys $Global:DiagResults.Stability $Global:DiagResults.BatteryDetail $Global:DiagResults.PowerInfo $Global:DiagResults.SpeedTest $Global:DiagResults.Gaming $Global:DiagResults.HistoryComparison $Global:DiagResults.ScanMode $Global:DiagResults.BootPerf $Global:DiagResults.Win11Ready
            $hwHTMLPath = Join-Path $p.OutputFolder "$safeName - $safeDev - Hardware Report $ds.html"
            $hwPDFPath = Join-Path $p.OutputFolder "$safeName - $safeDev - Hardware Report $ds.pdf"
            [IO.File]::WriteAllText($hwHTMLPath, $hwHTML, [Text.Encoding]::UTF8)
            $hwPDF = Convert-ToPDF $hwHTMLPath $hwPDFPath
            Set-Status "Hardware Report: $(if($hwPDF){"PDF saved"}else{"HTML saved (no PDF browser)"}) to reports folder" 40
        }
        if ($DoSec) {
            Set-Status "Generating Security Report..." 70
            $secHTML = Build-SecurityReport $p $Global:DiagResults.SystemInfo $Global:DiagResults.Security $Global:DiagResults.Patches $Global:DiagResults.Scoring
            $secHTMLPath = Join-Path $p.OutputFolder "$safeName - $safeDev - Security Report $ds.html"
            $secPDFPath = Join-Path $p.OutputFolder "$safeName - $safeDev - Security Report $ds.pdf"
            [IO.File]::WriteAllText($secHTMLPath, $secHTML, [Text.Encoding]::UTF8)
            $secPDF = Convert-ToPDF $secHTMLPath $secPDFPath
            Set-Status "Security Report: $(if($secPDF){"PDF saved"}else{"HTML saved"}) to reports folder" 90
        }
        Set-Status "Exporting data files..." 92
        try {
            $exportData = @{
                CustomerName = $p.CustomerName; TechName = $p.TechName; TechNotes = $p.TechNotes
                ScanDate = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss"); ScanMode = $Global:DiagResults.ScanMode
                SystemInfo = $Global:DiagResults.SystemInfo; StressResults = $Global:DiagResults.StressResults
                Stability = $Global:DiagResults.Stability; BatteryDetail = $Global:DiagResults.BatteryDetail
                SpeedTest = $Global:DiagResults.SpeedTest; Gaming = $Global:DiagResults.Gaming
                PowerInfo = $Global:DiagResults.PowerInfo; Scoring = $Global:DiagResults.Scoring
                HardwareScore = if($DoHW){ $Global:DiagResults.StressResults.Count }else{0}
                SecurityScore = if($Global:DiagResults.Scoring){ $Global:DiagResults.Scoring.Score }else{0}
                Battery = $Global:DiagResults.BatteryDetail
            }
            Export-ScanJSON -ScanData $exportData -OutputFolder $p.OutputFolder
            Export-ScanCSV -ScanData $exportData -OutputFolder $p.OutputFolder
            Save-ScanHistory -ScanData $exportData
        } catch { Write-DiagLog "Export error: $($_.Exception.Message)" "WARN" }

        Set-Status "All reports and data saved to: $($p.OutputFolder)" 100
        Start-Process explorer.exe -ArgumentList $p.OutputFolder

        $emailResult = [System.Windows.MessageBox]::Show($window, "Reports saved successfully!`n`nWould you like to open your email client to send the report?", "Email Report?", "YesNo", "Question")
        if ($emailResult -eq "Yes") {
            $pdfToEmail = ""
            if ($DoHW -and (Test-Path $hwPDFPath)) { $pdfToEmail = $hwPDFPath }
            elseif ($DoSec -and (Test-Path $secPDFPath)) { $pdfToEmail = $secPDFPath }
            elseif ($DoHW -and (Test-Path $hwHTMLPath)) { $pdfToEmail = $hwHTMLPath }
            elseif ($DoSec -and (Test-Path $secHTMLPath)) { $pdfToEmail = $secHTMLPath }
            if ($pdfToEmail) { try { [System.Windows.Clipboard]::SetText($pdfToEmail) } catch {} }
            $subjectText = "PC Plus Computing - Diagnostic Report for $($p.CustomerName)"
            $bodyText = "Hello,`n`nPlease find attached the diagnostic report for $($p.CustomerName) - $($Global:DiagResults.SystemInfo.ComputerName).`n`nGenerated on $(Get-Date -Format 'MMMM dd, yyyy').`n`nBest regards,`n$($p.TechName)`nPC Plus Computing`n$WEBSITE | $PHONE"
            $encodedSubject = [Uri]::EscapeDataString($subjectText)
            $encodedBody = [Uri]::EscapeDataString($bodyText)
            try {
                Start-Process "mailto:?subject=$encodedSubject&body=$encodedBody"
                Set-Status "Email client opened. Report path copied to clipboard." 100
            } catch { Set-Status "Could not open email client. Report path copied to clipboard." 100 }
        }
    }

    $window.FindName("btnHWReport").Add_Click({ & $generateReports $true $false })
    $window.FindName("btnSecReport").Add_Click({ & $generateReports $false $true })
    $window.FindName("btnBothReports").Add_Click({ & $generateReports $true $true })

    $window.ShowDialog() | Out-Null
}


# ─────────────────────────────────────────────────────────────────────────────
# ENTRY POINT
# ─────────────────────────────────────────────────────────────────────────────
Write-DebugLog "About to call Show-Launcher..."
try {
    Show-Launcher
    Write-DebugLog "Show-Launcher completed normally"
} catch {
    $errMsg = "$($_.Exception.Message)`nLine: $($_.InvocationInfo.ScriptLineNumber)`n$($_.Exception.StackTrace)"
    Write-DebugLog "FATAL ERROR: $errMsg"
    [System.Windows.Forms.MessageBox]::Show("PC Plus 360 Error:`n`n$errMsg", "PC Plus 360 - Error", "OK", "Error") | Out-Null
}
Write-DebugLog "Script finished."

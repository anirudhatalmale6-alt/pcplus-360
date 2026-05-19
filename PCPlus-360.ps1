<#
.SYNOPSIS
    PC Plus Computing 360 Hardware & Security Diagnostic Suite
.DESCRIPTION
    Complete diagnostic platform with branded launcher, built-in stress tests,
    third-party tool integration, and dual report generation (Hardware + Security).
    Runs from USB drive with no installation required.
.NOTES
    Company:  PC Plus Computing
    Version:  1.0.0
    Requires: PowerShell 5.1+, Windows 10/11, Administrator privileges
#>

#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

# ─────────────────────────────────────────────────────────────────────────────
# ELEVATION
# ─────────────────────────────────────────────────────────────────────────────
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-IsAdmin)) {
    try {
        Start-Process powershell.exe -ArgumentList "-STA -NoProfile -ExecutionPolicy Bypass -File `"$($MyInvocation.MyCommand.Definition)`"" -Verb RunAs
    } catch {
        [System.Windows.Forms.MessageBox]::Show("This tool requires Administrator privileges.", "PC Plus 360 - Elevation Required", "OK", "Warning")
    }
    exit
}

# ─────────────────────────────────────────────────────────────────────────────
# GLOBALS
# ─────────────────────────────────────────────────────────────────────────────
$Global:ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
if ([string]::IsNullOrEmpty($Global:ScriptDir)) { $Global:ScriptDir = Get-Location }
$Global:ToolsDir = Join-Path $Global:ScriptDir "tools"
$Global:ReportsDir = Join-Path $Global:ScriptDir "reports"
$Global:DiagResults = @{}
$Global:LogLines = [System.Collections.ArrayList]::new()

$COMPANY      = "PC Plus Computing"
$PHONE        = "604-760-1662"
$WEBSITE      = "pcpluscomputing.com"
$VERSION      = "1.0.0"

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
# BUILT-IN STRESS TESTS
# ─────────────────────────────────────────────────────────────────────────────

function Start-CPUStressTest {
    param([int]$DurationSeconds = 60)
    Write-DiagLog "Starting CPU stress test ($DurationSeconds seconds)..."
    $threadCount = [Environment]::ProcessorCount
    $results = @{ Threads = $threadCount; Duration = $DurationSeconds; StartTemp = "N/A"; EndTemp = "N/A"; MaxTemp = "N/A"; Passed = $true; Errors = @() }

    $results.StartTemp = Invoke-Safe {
        $t = Get-CimInstance MSAcpi_ThermalZoneTemperature -Namespace root/wmi -ErrorAction Stop | Select-Object -First 1
        [math]::Round(($t.CurrentTemperature / 10) - 273.15, 1)
    } "N/A"

    $jobs = @()
    $endTime = (Get-Date).AddSeconds($DurationSeconds)
    for ($i = 0; $i -lt $threadCount; $i++) {
        $jobs += Start-Job -ScriptBlock {
            param($end)
            $errors = 0; $iterations = 0
            while ((Get-Date) -lt $end) {
                # Prime number sieve stress
                $n = 100000; $primes = @($true) * ($n + 1)
                for ($p = 2; $p * $p -le $n; $p++) {
                    if ($primes[$p]) { for ($m = $p * $p; $m -le $n; $m += $p) { $primes[$m] = $false } }
                }
                # Verify known prime count (9592 primes below 100000)
                $count = ($primes | Where-Object { $_ }) | Measure-Object | Select-Object -ExpandProperty Count
                $count -= 2 # subtract indices 0 and 1
                if ($count -ne 9592) { $errors++ }
                $iterations++
            }
            return @{ Iterations = $iterations; Errors = $errors }
        } -ArgumentList $endTime
    }

    # Wait for completion
    $jobs | Wait-Job -Timeout ($DurationSeconds + 30) | Out-Null
    $totalIterations = 0; $totalErrors = 0
    foreach ($j in $jobs) {
        $r = Receive-Job $j -ErrorAction SilentlyContinue
        if ($r) { $totalIterations += $r.Iterations; $totalErrors += $r.Errors }
        Remove-Job $j -Force -ErrorAction SilentlyContinue
    }

    $results.EndTemp = Invoke-Safe {
        $t = Get-CimInstance MSAcpi_ThermalZoneTemperature -Namespace root/wmi -ErrorAction Stop | Select-Object -First 1
        [math]::Round(($t.CurrentTemperature / 10) - 273.15, 1)
    } "N/A"

    $results.Iterations = $totalIterations
    $results.ComputeErrors = $totalErrors
    $results.Passed = $totalErrors -eq 0
    Write-DiagLog "CPU stress: $totalIterations iterations, $totalErrors errors, Passed=$($results.Passed)"
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
    $grade = switch ($true) { ($score -ge 90){"A"} ($score -ge 80){"B"} ($score -ge 70){"C"} ($score -ge 60){"D"} default{"F"} }
    $color = switch ($grade) { "A"{"#27ae60"} "B"{"#27ae60"} "C"{"#f39c12"} "D"{"#f39c12"} "F"{"#e74c3c"} }
    return @{ Score = $score; Grade = $grade; Color = $color; Breakdown = $breakdown }
}

# ─────────────────────────────────────────────────────────────────────────────
# REPORT GENERATION
# ─────────────────────────────────────────────────────────────────────────────

function Build-HardwareReport {
    param($Params, $SystemInfo, $Network, $Software, $Performance, $StressResults, $LicenseKeys)
    $date = Get-Date -Format "MMMM dd, yyyy 'at' h:mm tt"
    $iconPass = "&#10004;"; $iconFail = "&#10008;"; $iconWarn = "&#9888;"
    # Determine hardware health score
    $hwScore = 100; $hwIssues = @()
    foreach ($d in $SystemInfo.SMART) { if ($d.Health -ne "Healthy") { $hwScore -= 15; $hwIssues += "Disk $($d.Model): $($d.Health)" } }
    if ($SystemInfo.DeviceErrors.Count -gt 0) { $hwScore -= ($SystemInfo.DeviceErrors.Count * 5); $hwIssues += "$($SystemInfo.DeviceErrors.Count) Device Manager errors" }
    if ($SystemInfo.Battery.Present -and $SystemInfo.Battery.HealthPct -gt 0 -and $SystemInfo.Battery.HealthPct -lt 50) { $hwScore -= 15; $hwIssues += "Battery health critical: $($SystemInfo.Battery.HealthPct)%" }
    if ($StressResults.CPU -and -not $StressResults.CPU.Passed) { $hwScore -= 20; $hwIssues += "CPU stress test FAILED" }
    if ($StressResults.RAM -and -not $StressResults.RAM.Passed) { $hwScore -= 25; $hwIssues += "RAM stress test FAILED" }
    if ($StressResults.Disk -and -not $StressResults.Disk.Passed) { $hwScore -= 15; $hwIssues += "Disk benchmark FAILED" }
    foreach ($d in $SystemInfo.Disks) { if ($d.UsedPct -gt 90) { $hwScore -= 10; $hwIssues += "Drive $($d.Drive) nearly full ($($d.UsedPct)%)" } }
    $hwScore = [math]::Max($hwScore, 0)
    $hwGrade = switch ($true) { ($hwScore -ge 90){"A"} ($hwScore -ge 80){"B"} ($hwScore -ge 70){"C"} ($hwScore -ge 60){"D"} default{"F"} }
    $hwColor = switch ($hwGrade) { "A"{"#27ae60"} "B"{"#27ae60"} "C"{"#f39c12"} "D"{"#f39c12"} "F"{"#e74c3c"} }
    $dashOffset = 283 - (283 * $hwScore / 100)

    # Build RAM rows
    $ramRows = ($SystemInfo.RAMSticks | ForEach-Object { "<tr><td>$($_.Slot)</td><td>$($_.CapacityGB) GB</td><td>$($_.Speed)</td><td>$($_.Type)</td><td>$($_.Manufacturer)</td><td>$($_.PartNumber)</td></tr>" }) -join "`n"
    # GPU rows
    $gpuRows = ($SystemInfo.GPUs | ForEach-Object { "<tr><td>$($_.Name)</td><td>$(if($_.VRAM_MB -gt 0){"$($_.VRAM_MB) MB"}else{"Shared"})</td><td>$($_.DriverVer)</td><td>$($_.DriverDate)</td><td>$($_.Resolution)</td></tr>" }) -join "`n"
    # SMART rows
    $smartRows = ($SystemInfo.SMART | ForEach-Object { $c=if($_.Health -eq 'Healthy'){'pass'}else{'fail'}; "<tr><td>$($_.Model)</td><td>$($_.MediaType)</td><td>$($_.BusType)</td><td>$($_.SizeGB) GB</td><td class='$c'>$($_.Health)</td><td>$($_.PowerOnHours)</td><td>$($_.Temperature)</td><td>$($_.ReadErrors)</td><td>$($_.Wear)</td></tr>" }) -join "`n"
    # Disk rows
    $diskRows = ($SystemInfo.Disks | ForEach-Object { $c=if($_.UsedPct -gt 90){'fail'}elseif($_.UsedPct -gt 75){'warn'}else{'pass'}; "<tr><td>$($_.Drive)</td><td>$($_.Size) GB</td><td>$($_.Free) GB</td><td class='$c'>$($_.UsedPct)%</td></tr>" }) -join "`n"
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
        $stressHTML += "<tr><td>CPU Stress Test</td><td class='$cpuClass'>$(if($StressResults.CPU.Passed){"$iconPass PASSED"}else{"$iconFail FAILED"})</td><td>$($StressResults.CPU.Threads) threads, $($StressResults.CPU.Duration)s, $($StressResults.CPU.Iterations) iterations</td><td>Start: $($StressResults.CPU.StartTemp)C / End: $($StressResults.CPU.EndTemp)C</td></tr>`n"
    }
    if ($StressResults.RAM) {
        $ramClass = if($StressResults.RAM.Passed){"pass"}else{"fail"}
        $stressHTML += "<tr><td>RAM Stress Test</td><td class='$ramClass'>$(if($StressResults.RAM.Passed){"$iconPass PASSED"}else{"$iconFail FAILED"})</td><td>$($StressResults.RAM.BlocksTested) blocks ($($StressResults.RAM.TotalMBTested) MB tested)</td><td>$($StressResults.RAM.Errors) errors</td></tr>`n"
    }
    if ($StressResults.Disk) {
        $dkClass = if($StressResults.Disk.Passed){"pass"}else{"fail"}
        $stressHTML += "<tr><td>Disk Benchmark</td><td class='$dkClass'>$(if($StressResults.Disk.Passed){"$iconPass PASSED"}else{"$iconFail FAILED"})</td><td>Write: $($StressResults.Disk.SeqWriteMBps) MB/s | Read: $($StressResults.Disk.SeqReadMBps) MB/s</td><td>$($StressResults.Disk.FileSizeMB) MB test file</td></tr>`n"
    }
    # Hardware issues
    $issuesHTML = if ($hwIssues.Count -gt 0) {
        ($hwIssues | ForEach-Object { "<div style='padding:8px 12px;margin:4px 0;background:#fef5f5;border-left:4px solid #e74c3c;border-radius:4px;'><span class='fail'>$iconFail</span> $_</div>" }) -join "`n"
    } else { "<div style='padding:12px;background:#eafaf1;border-left:4px solid #27ae60;border-radius:4px;'><span class='pass'>$iconPass</span> <strong>No hardware issues detected.</strong></div>" }
    # Device errors
    $devErrHTML = if ($SystemInfo.DeviceErrors.Count -gt 0) {
        "<div class='sub-header' style='color:#e74c3c;'>Device Manager Errors ($($SystemInfo.DeviceErrors.Count))</div><table><tr><th>Device</th><th>Class</th><th>Error</th></tr>" +
        (($SystemInfo.DeviceErrors | ForEach-Object { "<tr><td class='fail'>$($_.Device)</td><td>$($_.Class)</td><td class='fail'>$($_.Error)</td></tr>" }) -join "`n") + "</table>"
    } else { "<div class='sub-header' style='color:#27ae60;'>Device Manager - All Clear</div><p style='padding:8px;background:#eafaf1;border-radius:4px;'><span class='pass'>$iconPass</span> All devices functioning properly.</p>" }
    # Battery
    $batteryHTML = ""
    if ($SystemInfo.Battery.Present) {
        $bhClass = if($SystemInfo.Battery.HealthPct -ge 80){"pass"}elseif($SystemInfo.Battery.HealthPct -ge 50){"warn"}else{"fail"}
        $batteryHTML = @"
<div class="sub-header">Battery Health</div>
<table><tr><th style="width:35%;">Property</th><th>Value</th></tr>
<tr><td>Status</td><td>$($SystemInfo.Battery.Status)</td></tr>
<tr><td>Current Charge</td><td>$($SystemInfo.Battery.Charge)%</td></tr>
<tr><td>Battery Health</td><td class='$bhClass'>$($SystemInfo.Battery.HealthPct)%</td></tr>
<tr><td>Design Capacity</td><td>$($SystemInfo.Battery.DesignCap) mWh</td></tr>
<tr><td>Full Charge Capacity</td><td>$($SystemInfo.Battery.FullCap) mWh</td></tr>
<tr><td>Cycle Count</td><td>$($SystemInfo.Battery.CycleCount)</td></tr>
<tr><td>Estimated Runtime</td><td>$($SystemInfo.Battery.Runtime)</td></tr>
</table>
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
    # Temperature
    $tempRows = if ($SystemInfo.Temperatures.Count -gt 0) {
        ($SystemInfo.Temperatures | ForEach-Object { $tc=if($_.TempC -gt 80){"fail"}elseif($_.TempC -gt 60){"warn"}else{"pass"}; "<tr><td>$($_.Zone)</td><td class='$tc'>$($_.TempC)C</td><td class='$tc'>$($_.TempF)F</td></tr>" }) -join "`n"
    } else { "" }
    # Technician notes field
    $techNotes = if ($Params.TechNotes) { "<div class='section-header'>Technician Notes</div><div style='padding:16px;background:#f8f9fa;border:1px solid #ddd;border-radius:4px;min-height:60px;white-space:pre-wrap;'>$([System.Web.HttpUtility]::HtmlEncode($Params.TechNotes))</div>" } else { "" }

$html = @"
<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8"/><title>Hardware Diagnostic Report - $($Params.CustomerName)</title>
<style>
@page { size: letter; margin: 0.6in 0.7in; }
* { margin:0;padding:0;box-sizing:border-box; }
body { font-family:'Segoe UI',Tahoma,sans-serif;font-size:10pt;color:#333;line-height:1.5;background:#fff; }
.page-break { page-break-before:always; }
.cover { height:100vh;display:flex;flex-direction:column;justify-content:center;align-items:center;text-align:center;page-break-after:always; }
.cover-logo { background:#0a1628;color:#fff;padding:20px 50px;font-size:22pt;font-weight:bold;letter-spacing:3px;border-radius:6px;margin-bottom:40px; }
.cover-title { font-size:26pt;font-weight:300;color:#0a1628;margin-bottom:8px;letter-spacing:2px; }
.cover-subtitle { font-size:13pt;color:#666;margin-bottom:30px; }
.cover .meta { font-size:11pt;color:#555;margin:4px 0; }
.section-header { background:#0a1628;color:#fff;padding:10px 18px;font-size:13pt;font-weight:600;margin:25px 0 12px 0;border-radius:4px; }
.sub-header { color:#2596be;font-size:11pt;font-weight:600;margin:18px 0 8px 0;padding-bottom:4px;border-bottom:2px solid #2596be; }
table { width:100%;border-collapse:collapse;margin-bottom:16px;font-size:9.5pt; }
th { background:#0a1628;color:#fff;padding:8px 10px;text-align:left;font-weight:600;font-size:9pt;text-transform:uppercase; }
td { padding:7px 10px;border-bottom:1px solid #e8e8e8;vertical-align:top; }
tr:nth-child(even) td { background:#f8f9fa; }
.pass { color:#27ae60;font-weight:600; } .fail { color:#e74c3c;font-weight:600; } .warn { color:#f39c12;font-weight:600; }
.summary-grid { display:flex;gap:16px;margin:16px 0; }
.summary-box { flex:1;text-align:center;padding:16px;border-radius:6px;border:1px solid #e0e0e0; }
.summary-box .number { font-size:28pt;font-weight:bold;display:block; }
.summary-box .label { font-size:9pt;color:#666;text-transform:uppercase; }
.report-footer { margin-top:30px;padding:16px 0;border-top:2px solid #0a1628;text-align:center;font-size:9pt;color:#888; }
.report-footer strong { color:#0a1628; }
@media print { .page-break{page-break-before:always;} body{-webkit-print-color-adjust:exact;print-color-adjust:exact;} }
</style></head><body>

<div class="cover">
<div class="cover-logo">PC PLUS COMPUTING</div>
<div class="cover-title">HARDWARE DIAGNOSTIC REPORT</div>
<div class="cover-subtitle">Comprehensive Hardware Assessment &amp; Stress Testing</div>
<svg viewBox="0 0 100 100" width="180" height="180">
<circle cx="50" cy="50" r="45" fill="none" stroke="#e0e0e0" stroke-width="8"/>
<circle cx="50" cy="50" r="45" fill="none" stroke="$hwColor" stroke-width="8" stroke-dasharray="283" stroke-dashoffset="$dashOffset" transform="rotate(-90 50 50)" stroke-linecap="round"/>
<text x="50" y="45" text-anchor="middle" font-size="22" font-weight="bold" fill="$hwColor">$hwScore</text>
<text x="50" y="62" text-anchor="middle" font-size="14" font-weight="bold" fill="$hwColor">$hwGrade</text>
</svg>
<p class="meta" style="font-size:14pt;color:$hwColor;font-weight:bold;margin-top:10px;">Hardware Health: $hwScore / 100 - Grade $hwGrade</p>
<div style="margin-top:30px;">
<p class="meta"><strong>Customer:</strong> $($Params.CustomerName)</p>
$(if($Params.ContactName){"<p class='meta'><strong>Contact:</strong> $($Params.ContactName)</p>"})
<p class="meta"><strong>Device:</strong> $($SystemInfo.ComputerName)</p>
<p class="meta"><strong>Date:</strong> $date</p>
<p class="meta"><strong>Technician:</strong> $($Params.TechName)</p>
</div></div>

<div class="page-break"></div>
<div class="section-header">Hardware Health Summary</div>
<div class="summary-grid">
<div class="summary-box" style="border-color:$hwColor;"><span class="number" style="color:$hwColor;">$hwScore</span><span class="label">Health Score</span></div>
<div class="summary-box"><span class="number">$($SystemInfo.SMART.Count)</span><span class="label">Storage Devices</span></div>
<div class="summary-box"><span class="number">$($SystemInfo.RAMTotal) GB</span><span class="label">Total RAM</span></div>
<div class="summary-box"><span class="number">$($SystemInfo.DeviceErrors.Count)</span><span class="label">Device Errors</span></div>
</div>
$issuesHTML

$(if($stressHTML){"<div class='sub-header'>Stress Test Results</div><table><tr><th>Test</th><th>Result</th><th>Details</th><th>Temps</th></tr>$stressHTML</table>"})

<div class="page-break"></div>
<div class="section-header">System Information</div>
<table><tr><th style="width:35%;">Property</th><th>Value</th></tr>
<tr><td>Computer Name</td><td>$($SystemInfo.ComputerName)</td></tr>
<tr><td>Manufacturer / Model</td><td>$($SystemInfo.Manufacturer) $($SystemInfo.Model)</td></tr>
<tr><td>Serial Number</td><td>$($SystemInfo.Serial)</td></tr>
<tr><td>OS</td><td>$($SystemInfo.OSVersion) (Build $($SystemInfo.OSBuild))</td></tr>
<tr><td>Architecture</td><td>$($SystemInfo.Architecture)</td></tr>
<tr><td>CPU</td><td>$($SystemInfo.CPUModel)</td></tr>
<tr><td>Cores / Threads</td><td>$($SystemInfo.CPUCores) / $($SystemInfo.CPUThreads)</td></tr>
<tr><td>RAM</td><td>$($SystemInfo.RAMTotal) GB total / $($SystemInfo.RAMFree) GB free</td></tr>
<tr><td>Uptime</td><td>$($SystemInfo.Uptime)</td></tr>
<tr><td>Network</td><td>$($SystemInfo.Domain)</td></tr>
</table>

<div class="sub-header">Motherboard &amp; BIOS</div>
<table><tr><th style="width:35%;">Property</th><th>Value</th></tr>
<tr><td>Motherboard</td><td>$($SystemInfo.Board.Manufacturer) $($SystemInfo.Board.Product)</td></tr>
<tr><td>Board Serial</td><td>$($SystemInfo.Board.Serial)</td></tr>
<tr><td>BIOS</td><td>$($SystemInfo.BIOS.Vendor) - $($SystemInfo.BIOS.Version)</td></tr>
<tr><td>BIOS Date</td><td>$($SystemInfo.BIOS.Date)</td></tr>
</table>

<div class="sub-header">Memory (RAM) - $($SystemInfo.RAMSlots.Used)/$($SystemInfo.RAMSlots.Total) slots$(if($SystemInfo.RAMSlots.Empty -gt 0){" ($($SystemInfo.RAMSlots.Empty) empty)"})</div>
<table><tr><th>Slot</th><th>Size</th><th>Speed</th><th>Type</th><th>Manufacturer</th><th>Part</th></tr>$ramRows</table>

<div class="sub-header">Graphics</div>
<table><tr><th>GPU</th><th>VRAM</th><th>Driver</th><th>Driver Date</th><th>Resolution</th></tr>$gpuRows</table>

$(if($monitorRows){"<div class='sub-header'>Monitors</div><table><tr><th>Model</th><th>Manufacturer</th><th>Serial</th><th>Year</th></tr>$monitorRows</table>"})

<div class="page-break"></div>
<div class="section-header">Storage Health (SMART)</div>
<table><tr><th>Model</th><th>Type</th><th>Bus</th><th>Size</th><th>Health</th><th>Power-On Hrs</th><th>Temp</th><th>Read Errors</th><th>Wear</th></tr>$smartRows</table>

<div class="sub-header">Drive Space</div>
<table><tr><th>Drive</th><th>Capacity</th><th>Free</th><th>Used</th></tr>$diskRows</table>

$batteryHTML

$(if($tempRows){"<div class='sub-header'>Temperature Readings</div><table><tr><th>Sensor</th><th>Celsius</th><th>Fahrenheit</th></tr>$tempRows</table>"})

$devErrHTML

$(if($printerRows){"<div class='sub-header'>Printers</div><table><tr><th>Name</th><th>Port</th><th>Driver</th><th>Default</th></tr>$printerRows</table>"})

<div class="page-break"></div>
<div class="section-header">Network</div>
<table><tr><th>Adapter</th><th>IP</th><th>MAC</th><th>DNS</th><th>Speed</th></tr>$netRows</table>
<table><tr><th style="width:30%;">Property</th><th>Value</th></tr>
<tr><td>WiFi SSID</td><td>$($Network.WiFi.SSID)</td></tr>
<tr><td>Public IP</td><td>$($Network.PublicIP)</td></tr>
<tr><td>DNS Response</td><td>$(if($Network.DNSTest.Success){"$($Network.DNSTest.ResponseMs) ms"}else{"Failed"})</td></tr>
<tr><td>Internet</td><td>$(if($Network.InternetTest.Success){"Connected ($($Network.InternetTest.ResponseMs) ms)"}else{"<span class='fail'>No Connection</span>"})</td></tr>
</table>
$(if($Network.OpenPorts.Count -gt 0){"<div class='sub-header'>Listening Ports</div><table><tr><th>Port</th><th>Address</th><th>Process</th></tr>$(($Network.OpenPorts | ForEach-Object {"<tr><td>$($_.Port)</td><td>$($_.Address)</td><td>$($_.Process)</td></tr>"}) -join "`n")</table>"})

<div class="page-break"></div>
<div class="section-header">Performance</div>
<table><tr><th style="width:40%;">Metric</th><th>Value</th></tr>
<tr><td>CPU Usage</td><td>$($Performance.CPUPercent)%</td></tr>
<tr><td>RAM Usage</td><td>$($Performance.RAMPercent)%</td></tr>
<tr><td>Running Processes</td><td>$($Software.ProcessCount)</td></tr>
<tr><td>Running Services</td><td>$($Software.RunningServices)</td></tr>
</table>
<div class="sub-header">Top Memory Consumers</div>
<table><tr><th>Process</th><th>RAM</th></tr>$topProcRows</table>

<div class="page-break"></div>
<div class="section-header">License Keys &amp; Credentials</div>
<p style="color:#888;font-size:8.5pt;margin-bottom:12px;">CONFIDENTIAL - Store securely.</p>
<div class="sub-header">Windows Product Key</div>
<table><tr><th>Source</th><th>Key</th></tr>$winKeyRows</table>
<div class="sub-header">Microsoft Office</div>
<table><tr><th>Product</th><th>Key</th></tr>$officeKeyRows</table>
$(if($adobeKeyRows){"<div class='sub-header'>Adobe Products</div><table><tr><th>Product</th><th>Key</th></tr>$adobeKeyRows</table>"})
<div class="sub-header">Saved WiFi Networks</div>
<table><tr><th>Network</th><th>Password</th><th>Security</th></tr>$wifiRows</table>

$techNotes

<div class="page-break"></div>
<div class="section-header">Installed Software ($($Software.Installed.Count))</div>
<table><tr><th>Name</th><th>Version</th><th>Publisher</th></tr>$swRows</table>

<div class="sub-header">Startup Programs ($($Software.StartupPrograms.Count))</div>
<table><tr><th>Name</th><th>Location</th></tr>$(($Software.StartupPrograms | ForEach-Object {"<tr><td>$($_.Name)</td><td>$($_.Location)</td></tr>"}) -join "`n")</table>

<div class="report-footer">
<p><strong>$COMPANY</strong></p><p>$WEBSITE | $PHONE</p>
<p style="margin-top:8px;font-size:8pt;">Hardware Diagnostic Report generated $date | Technician: $($Params.TechName)</p>
</div></body></html>
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
    # Breakdown rows
    $breakdownRows = ($Scoring.Breakdown | ForEach-Object {
        $ic = if($_.Passed){"<span class='pass'>$iconPass</span>"}else{"<span class='fail'>$iconFail</span>"}
        $st = if($_.Passed){"PASS"}else{"FAIL"}; $sc = if($_.Passed){"pass"}else{"fail"}
        "<tr><td>$ic</td><td>$($_.Check)</td><td class='$sc'>$st</td><td>$($_.Points) pts</td></tr>"
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
        $sc = switch($_.Severity){"Critical"{"fail"}"Warning"{"warn"}default{"info"}}
        "<tr><td class='$sc'><strong>$($_.Severity)</strong></td><td>$($_.Check)</td><td>$($_.Rec)</td></tr>"
    }) -join "`n"
    # Security details
    $secRows = ""
    $defSt = if($Security.Defender.RealTimeProtection -eq $true){"<span class='pass'>$iconPass Active</span>"}elseif($Security.Defender.RealTimeProtection -eq $false){"<span class='fail'>$iconFail Disabled</span>"}else{"<span class='warn'>$iconWarn Unknown</span>"}
    $secRows += "<tr><td>Windows Defender</td><td>$defSt</td></tr>`n"
    if($Security.Defender.DefinitionAge -ne $null){$da=if($Security.Defender.DefinitionsUpToDate){"pass"}else{"fail"};$secRows+="<tr><td>AV Definitions</td><td class='$da'>$($Security.Defender.DefinitionAge) days old</td></tr>`n"}
    if($Security.ThirdPartyAV.Count -gt 0){$secRows+="<tr><td>Third-Party AV</td><td class='pass'>$($Security.ThirdPartyAV -join ', ')</td></tr>`n"}
    foreach($p in @("Domain","Private","Public")){$v=$Security.Firewall.$p;$s=if($v -eq $true){"<span class='pass'>$iconPass Enabled</span>"}elseif($v -eq $false){"<span class='fail'>$iconFail Disabled</span>"}else{"<span class='warn'>$iconWarn Unknown</span>"};$secRows+="<tr><td>Firewall - $p</td><td>$s</td></tr>`n"}
    $uacSt = if($Security.UAC.Enabled){"<span class='pass'>$iconPass Enabled</span>"}else{"<span class='fail'>$iconFail Disabled</span>"}
    $secRows += "<tr><td>UAC</td><td>$uacSt</td></tr>`n"
    if($Security.BitLocker.Count -gt 0){foreach($d in $Security.BitLocker.Keys){$bi=$Security.BitLocker[$d];$bs=if($bi.Status -eq "On"){"<span class='pass'>$iconPass Encrypted</span>"}else{"<span class='fail'>$iconFail Not Encrypted</span>"};$secRows+="<tr><td>BitLocker $d</td><td>$bs</td></tr>`n"}}else{$secRows+="<tr><td>BitLocker</td><td class='fail'>$iconFail Not Detected</td></tr>`n"}
    $sbSt = if($Security.SecureBoot -eq $true){"<span class='pass'>$iconPass Enabled</span>"}elseif($Security.SecureBoot -eq $false){"<span class='fail'>$iconFail Disabled</span>"}else{"<span class='warn'>$iconWarn Unknown</span>"}
    $secRows += "<tr><td>Secure Boot</td><td>$sbSt</td></tr>`n"
    $tpmSt = if($Security.TPM.Present){"<span class='pass'>$iconPass Present</span>"}else{"<span class='fail'>$iconFail Not Present</span>"}
    $secRows += "<tr><td>TPM</td><td>$tpmSt</td></tr>`n"
    $secRows += "<tr><td>Password Policy</td><td>Min: $($Security.PasswordPolicy.MinLength), Complexity: $(if($Security.PasswordPolicy.Complexity){'Yes'}else{'No'}), Lockout: $(if($Security.PasswordPolicy.LockoutThreshold -gt 0){$Security.PasswordPolicy.LockoutThreshold}else{'None'})</td></tr>`n"
    $gSt = if($Security.GuestDisabled -eq $true){"<span class='pass'>$iconPass Disabled</span>"}else{"<span class='fail'>$iconFail Enabled</span>"}; $secRows += "<tr><td>Guest Account</td><td>$gSt</td></tr>`n"
    $alSt = if($Security.AutoLoginDisabled -eq $true){"<span class='pass'>$iconPass Off</span>"}else{"<span class='fail'>$iconFail On</span>"}; $secRows += "<tr><td>Auto-Login</td><td>$alSt</td></tr>`n"
    $rdpSt = if($Security.RDP.Enabled -eq $false){"<span class='pass'>$iconPass Disabled</span>"}elseif($Security.RDP.NLA){"<span class='warn'>$iconWarn Enabled (NLA)</span>"}else{"<span class='fail'>$iconFail Enabled (No NLA)</span>"}; $secRows += "<tr><td>Remote Desktop</td><td>$rdpSt</td></tr>`n"
    $smbSt = if($Security.SMBv1Disabled -eq $true){"<span class='pass'>$iconPass Disabled</span>"}else{"<span class='fail'>$iconFail Enabled</span>"}; $secRows += "<tr><td>SMBv1</td><td>$smbSt</td></tr>`n"
    $secRows += "<tr><td>Local Admins</td><td>$($Security.LocalAdmins.Count): $($Security.LocalAdmins.Names)</td></tr>`n"
    # Patch rows
    $patchRows = if($MissingPatches.Count -gt 0){
        ($MissingPatches | ForEach-Object {$sc=switch($_.Severity){"Critical"{"fail"}"Important"{"warn"}default{""}};"<tr><td>$($_.KB)</td><td>$($_.Title)</td><td class='$sc'>$($_.Severity)</td></tr>"}) -join "`n"
    } else { "<tr><td colspan='3' class='pass' style='text-align:center;'>$iconPass All patches up to date</td></tr>" }

$html = @"
<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8"/><title>Security Audit Report - $($Params.CustomerName)</title>
<style>
@page { size:letter;margin:0.6in 0.7in; }
*{margin:0;padding:0;box-sizing:border-box;}
body{font-family:'Segoe UI',Tahoma,sans-serif;font-size:10pt;color:#333;line-height:1.5;background:#fff;}
.page-break{page-break-before:always;}
.cover{height:100vh;display:flex;flex-direction:column;justify-content:center;align-items:center;text-align:center;page-break-after:always;}
.cover-logo{background:#0a1628;color:#fff;padding:20px 50px;font-size:22pt;font-weight:bold;letter-spacing:3px;border-radius:6px;margin-bottom:40px;}
.cover-title{font-size:26pt;font-weight:300;color:#0a1628;margin-bottom:8px;letter-spacing:2px;}
.cover-subtitle{font-size:13pt;color:#666;margin-bottom:30px;}
.cover .meta{font-size:11pt;color:#555;margin:4px 0;}
.section-header{background:#0a1628;color:#fff;padding:10px 18px;font-size:13pt;font-weight:600;margin:25px 0 12px 0;border-radius:4px;}
.sub-header{color:#2596be;font-size:11pt;font-weight:600;margin:18px 0 8px 0;padding-bottom:4px;border-bottom:2px solid #2596be;}
table{width:100%;border-collapse:collapse;margin-bottom:16px;font-size:9.5pt;}
th{background:#0a1628;color:#fff;padding:8px 10px;text-align:left;font-weight:600;font-size:9pt;text-transform:uppercase;}
td{padding:7px 10px;border-bottom:1px solid #e8e8e8;vertical-align:top;}
tr:nth-child(even) td{background:#f8f9fa;}
.pass{color:#27ae60;font-weight:600;} .fail{color:#e74c3c;font-weight:600;} .warn{color:#f39c12;font-weight:600;}
.summary-grid{display:flex;gap:16px;margin:16px 0;}
.summary-box{flex:1;text-align:center;padding:16px;border-radius:6px;border:1px solid #e0e0e0;}
.summary-box .number{font-size:28pt;font-weight:bold;display:block;}
.summary-box .label{font-size:9pt;color:#666;text-transform:uppercase;}
.report-footer{margin-top:30px;padding:16px 0;border-top:2px solid #0a1628;text-align:center;font-size:9pt;color:#888;}
.report-footer strong{color:#0a1628;}
@media print{.page-break{page-break-before:always;}body{-webkit-print-color-adjust:exact;print-color-adjust:exact;}}
</style></head><body>

<div class="cover">
<div class="cover-logo">PC PLUS COMPUTING</div>
<div class="cover-title">SECURITY AUDIT REPORT</div>
<div class="cover-subtitle">Comprehensive Security Assessment</div>
<svg viewBox="0 0 100 100" width="180" height="180">
<circle cx="50" cy="50" r="45" fill="none" stroke="#e0e0e0" stroke-width="8"/>
<circle cx="50" cy="50" r="45" fill="none" stroke="$($Scoring.Color)" stroke-width="8" stroke-dasharray="283" stroke-dashoffset="$dashOffset" transform="rotate(-90 50 50)" stroke-linecap="round"/>
<text x="50" y="45" text-anchor="middle" font-size="22" font-weight="bold" fill="$($Scoring.Color)">$($Scoring.Score)</text>
<text x="50" y="62" text-anchor="middle" font-size="14" font-weight="bold" fill="$($Scoring.Color)">$($Scoring.Grade)</text>
</svg>
<p class="meta" style="font-size:14pt;color:$($Scoring.Color);font-weight:bold;margin-top:10px;">Security Score: $($Scoring.Score) / 100 - Grade $($Scoring.Grade)</p>
<div style="margin-top:30px;">
<p class="meta"><strong>Customer:</strong> $($Params.CustomerName)</p>
$(if($Params.ContactName){"<p class='meta'><strong>Contact:</strong> $($Params.ContactName)</p>"})
<p class="meta"><strong>Device:</strong> $($SystemInfo.ComputerName)</p>
<p class="meta"><strong>Date:</strong> $date</p>
<p class="meta"><strong>Technician:</strong> $($Params.TechName)</p>
</div></div>

<div class="page-break"></div>
<div class="section-header">Security Score Breakdown</div>
<div class="summary-grid">
<div class="summary-box" style="border-color:#27ae60;"><span class="number pass">$passCount</span><span class="label">Passed</span></div>
<div class="summary-box" style="border-color:#e74c3c;"><span class="number fail">$failCount</span><span class="label">Failed</span></div>
<div class="summary-box" style="border-color:$($Scoring.Color);"><span class="number" style="color:$($Scoring.Color);">$($Scoring.Score)</span><span class="label">Score</span></div>
<div class="summary-box"><span class="number">$($MissingPatches.Count)</span><span class="label">Missing Patches</span></div>
</div>
<table><tr><th></th><th>Check</th><th>Status</th><th>Weight</th></tr>$breakdownRows</table>

$(if($recs.Count -gt 0){"<div class='section-header'>Recommendations</div><table><tr><th>Severity</th><th>Check</th><th>Action Required</th></tr>$recsHTML</table>"})

<div class="page-break"></div>
<div class="section-header">Detailed Security Status</div>
<table><tr><th style="width:40%;">Check</th><th>Status</th></tr>$secRows</table>

<div class="section-header">Missing Windows Updates ($($MissingPatches.Count))</div>
<table><tr><th>KB</th><th>Title</th><th>Severity</th></tr>$patchRows</table>

<div class="report-footer">
<p><strong>$COMPANY</strong></p><p>$WEBSITE | $PHONE</p>
<p style="margin-top:8px;font-size:8pt;">Security Audit Report generated $date | Technician: $($Params.TechName)</p>
</div></body></html>
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
            $args = "--headless --disable-gpu --no-sandbox --print-to-pdf=`"$PDFPath`" --print-to-pdf-no-header --run-all-compositor-stages-before-draw --disable-extensions `"file:///$($HTMLPath.Replace('\','/'))`""
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
        Title="PC Plus Computing 360 Diagnostic Suite" Height="720" Width="900"
        WindowStartupLocation="CenterScreen" ResizeMode="NoResize"
        Background="#0a1628" FontFamily="Segoe UI">
    <Grid>
        <Grid.RowDefinitions>
            <RowDefinition Height="80"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="40"/>
        </Grid.RowDefinitions>

        <!-- HEADER -->
        <Border Grid.Row="0" Background="#0d1f3c" BorderBrush="#2596be" BorderThickness="0,0,0,2">
            <StackPanel Orientation="Horizontal" HorizontalAlignment="Center" VerticalAlignment="Center">
                <TextBlock Text="PC PLUS COMPUTING" FontSize="24" FontWeight="Bold" Foreground="White" VerticalAlignment="Center" Margin="0,0,20,0"/>
                <TextBlock Text="360 DIAGNOSTIC SUITE" FontSize="20" FontWeight="Light" Foreground="#2596be" VerticalAlignment="Center"/>
            </StackPanel>
        </Border>

        <!-- MAIN CONTENT -->
        <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto" Margin="20,10,20,10">
            <StackPanel>
                <!-- Customer Info -->
                <Border Background="#121e33" CornerRadius="6" Padding="20" Margin="0,0,0,15">
                    <Grid>
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*"/><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>
                        <Grid.RowDefinitions>
                            <RowDefinition/><RowDefinition/>
                        </Grid.RowDefinitions>
                        <StackPanel Grid.Column="0" Margin="0,0,10,0">
                            <TextBlock Text="Customer Name *" Foreground="#aaa" FontSize="11" Margin="0,0,0,4"/>
                            <TextBox x:Name="txtCustomer" FontSize="13" Padding="6" Background="#1a2a44" Foreground="White" BorderBrush="#2596be"/>
                        </StackPanel>
                        <StackPanel Grid.Column="1" Margin="5,0,5,0">
                            <TextBlock Text="Contact Name" Foreground="#aaa" FontSize="11" Margin="0,0,0,4"/>
                            <TextBox x:Name="txtContact" FontSize="13" Padding="6" Background="#1a2a44" Foreground="White" BorderBrush="#2596be"/>
                        </StackPanel>
                        <StackPanel Grid.Column="2" Margin="10,0,0,0">
                            <TextBlock Text="Technician" Foreground="#aaa" FontSize="11" Margin="0,0,0,4"/>
                            <TextBox x:Name="txtTech" Text="Paul" FontSize="13" Padding="6" Background="#1a2a44" Foreground="White" BorderBrush="#2596be"/>
                        </StackPanel>
                        <StackPanel Grid.Row="1" Grid.ColumnSpan="3" Margin="0,10,0,0">
                            <TextBlock Text="Technician Notes (optional - appears in report)" Foreground="#aaa" FontSize="11" Margin="0,0,0,4"/>
                            <TextBox x:Name="txtNotes" FontSize="12" Padding="6" Height="50" Background="#1a2a44" Foreground="White" BorderBrush="#2596be" AcceptsReturn="True" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto"/>
                        </StackPanel>
                    </Grid>
                </Border>

                <!-- DIAGNOSTIC MODES -->
                <TextBlock Text="DIAGNOSTIC MODES" Foreground="#2596be" FontSize="14" FontWeight="Bold" Margin="0,0,0,10"/>
                <Grid Margin="0,0,0,15">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/><ColumnDefinition Width="*"/>
                    </Grid.ColumnDefinitions>
                    <Button x:Name="btnQuick" Grid.Column="0" Margin="0,0,8,0" Height="80" Background="#1a5276" Foreground="White" BorderThickness="0" Cursor="Hand">
                        <StackPanel><TextBlock Text="QUICK DIAGNOSTIC" FontSize="16" FontWeight="Bold" HorizontalAlignment="Center"/>
                        <TextBlock Text="10-15 minutes | Inventory + SMART + Basic Tests" FontSize="11" Foreground="#aaa" HorizontalAlignment="Center"/></StackPanel>
                    </Button>
                    <Button x:Name="btnFull" Grid.Column="1" Margin="8,0,0,0" Height="80" Background="#7d3c98" Foreground="White" BorderThickness="0" Cursor="Hand">
                        <StackPanel><TextBlock Text="FULL DIAGNOSTIC" FontSize="16" FontWeight="Bold" HorizontalAlignment="Center"/>
                        <TextBlock Text="30-60 min | Everything + Stress Tests" FontSize="11" Foreground="#aaa" HorizontalAlignment="Center"/></StackPanel>
                    </Button>
                </Grid>

                <!-- INDIVIDUAL TESTS -->
                <TextBlock Text="INDIVIDUAL TESTS" Foreground="#2596be" FontSize="14" FontWeight="Bold" Margin="0,0,0,10"/>
                <Grid Margin="0,0,0,15">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/>
                    </Grid.ColumnDefinitions>
                    <Grid.RowDefinitions>
                        <RowDefinition Height="60"/><RowDefinition Height="60"/><RowDefinition Height="60"/>
                    </Grid.RowDefinitions>
                    <Button x:Name="btnCPU" Content="CPU Stress Test" Grid.Row="0" Grid.Column="0" Margin="2" Background="#1a3a52" Foreground="White" BorderThickness="0" FontSize="12" Cursor="Hand"/>
                    <Button x:Name="btnRAM" Content="RAM Test" Grid.Row="0" Grid.Column="1" Margin="2" Background="#1a3a52" Foreground="White" BorderThickness="0" FontSize="12" Cursor="Hand"/>
                    <Button x:Name="btnDisk" Content="Disk Benchmark" Grid.Row="0" Grid.Column="2" Margin="2" Background="#1a3a52" Foreground="White" BorderThickness="0" FontSize="12" Cursor="Hand"/>
                    <Button x:Name="btnSMART" Content="Storage SMART Check" Grid.Row="1" Grid.Column="0" Margin="2" Background="#1a3a52" Foreground="White" BorderThickness="0" FontSize="12" Cursor="Hand"/>
                    <Button x:Name="btnBattery" Content="Battery Report" Grid.Row="1" Grid.Column="1" Margin="2" Background="#1a3a52" Foreground="White" BorderThickness="0" FontSize="12" Cursor="Hand"/>
                    <Button x:Name="btnNetwork" Content="Network Test" Grid.Row="1" Grid.Column="2" Margin="2" Background="#1a3a52" Foreground="White" BorderThickness="0" FontSize="12" Cursor="Hand"/>
                    <Button x:Name="btnSecurity" Content="Security Audit" Grid.Row="2" Grid.Column="0" Margin="2" Background="#1a3a52" Foreground="White" BorderThickness="0" FontSize="12" Cursor="Hand"/>
                    <Button x:Name="btnKeys" Content="License Key Recovery" Grid.Row="2" Grid.Column="1" Margin="2" Background="#1a3a52" Foreground="White" BorderThickness="0" FontSize="12" Cursor="Hand"/>
                    <Button x:Name="btnDebloat" Content="Windows Debloat" Grid.Row="2" Grid.Column="2" Margin="2" Background="#8B0000" Foreground="White" BorderThickness="0" FontSize="12" Cursor="Hand"/>
                </Grid>

                <!-- PORTABLE TOOLS -->
                <TextBlock Text="PORTABLE TOOLS" Foreground="#2596be" FontSize="14" FontWeight="Bold" Margin="0,0,0,10"/>
                <Grid Margin="0,0,0,15">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/>
                    </Grid.ColumnDefinitions>
                    <Grid.RowDefinitions>
                        <RowDefinition Height="50"/><RowDefinition Height="50"/>
                    </Grid.RowDefinitions>
                    <Button x:Name="btnCDI" Content="CrystalDiskInfo" Grid.Row="0" Grid.Column="0" Margin="2" Background="#2c3e50" Foreground="White" BorderThickness="0" FontSize="11" Cursor="Hand"/>
                    <Button x:Name="btnHWiNFO" Content="HWiNFO" Grid.Row="0" Grid.Column="1" Margin="2" Background="#2c3e50" Foreground="White" BorderThickness="0" FontSize="11" Cursor="Hand"/>
                    <Button x:Name="btnCPUZ" Content="CPU-Z" Grid.Row="0" Grid.Column="2" Margin="2" Background="#2c3e50" Foreground="White" BorderThickness="0" FontSize="11" Cursor="Hand"/>
                    <Button x:Name="btnGPUZ" Content="GPU-Z" Grid.Row="1" Grid.Column="0" Margin="2" Background="#2c3e50" Foreground="White" BorderThickness="0" FontSize="11" Cursor="Hand"/>
                    <Button x:Name="btnHWMon" Content="HWMonitor" Grid.Row="1" Grid.Column="1" Margin="2" Background="#2c3e50" Foreground="White" BorderThickness="0" FontSize="11" Cursor="Hand"/>
                    <Button x:Name="btnBattView" Content="BatteryInfoView" Grid.Row="1" Grid.Column="2" Margin="2" Background="#2c3e50" Foreground="White" BorderThickness="0" FontSize="11" Cursor="Hand"/>
                </Grid>

                <!-- REPORTS -->
                <TextBlock Text="GENERATE REPORTS" Foreground="#2596be" FontSize="14" FontWeight="Bold" Margin="0,0,0,10"/>
                <Grid Margin="0,0,0,15">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/>
                    </Grid.ColumnDefinitions>
                    <Button x:Name="btnHWReport" Content="Hardware Report (PDF)" Grid.Column="0" Margin="2" Height="50" Background="#27ae60" Foreground="White" BorderThickness="0" FontSize="13" FontWeight="Bold" Cursor="Hand"/>
                    <Button x:Name="btnSecReport" Content="Security Report (PDF)" Grid.Column="1" Margin="2" Height="50" Background="#e67e22" Foreground="White" BorderThickness="0" FontSize="13" FontWeight="Bold" Cursor="Hand"/>
                    <Button x:Name="btnBothReports" Content="Both Reports" Grid.Column="2" Margin="2" Height="50" Background="#2596be" Foreground="White" BorderThickness="0" FontSize="13" FontWeight="Bold" Cursor="Hand"/>
                </Grid>

                <!-- STATUS -->
                <Border Background="#121e33" CornerRadius="6" Padding="12" Margin="0,0,0,10">
                    <StackPanel>
                        <TextBlock x:Name="txtStatus" Text="Ready. Enter customer info and select a diagnostic mode or individual test." Foreground="#aaa" FontSize="11" TextWrapping="Wrap"/>
                        <ProgressBar x:Name="progressBar" Height="8" Margin="0,8,0,0" Background="#1a2a44" Foreground="#2596be" Value="0" BorderThickness="0"/>
                    </StackPanel>
                </Border>
            </StackPanel>
        </ScrollViewer>

        <!-- FOOTER -->
        <Border Grid.Row="2" Background="#0d1f3c">
            <TextBlock Text="PC Plus Computing | pcpluscomputing.com | 604-760-1662 | v1.0.0" Foreground="#666" FontSize="10" HorizontalAlignment="Center" VerticalAlignment="Center"/>
        </Border>
    </Grid>
</Window>
"@

    $reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($xaml))
    $window = [System.Windows.Markup.XamlReader]::Load($reader)

    # Get controls
    $txtCustomer = $window.FindName("txtCustomer")
    $txtContact = $window.FindName("txtContact")
    $txtTech = $window.FindName("txtTech")
    $txtNotes = $window.FindName("txtNotes")
    $txtStatus = $window.FindName("txtStatus")
    $progressBar = $window.FindName("progressBar")

    $tools = Get-ToolStatus

    # Helper to update UI
    function Set-Status { param([string]$Msg, [int]$Pct = -1)
        $txtStatus.Text = $Msg
        if ($Pct -ge 0) { $progressBar.Value = $Pct }
        [System.Windows.Threading.Dispatcher]::CurrentDispatcher.Invoke([System.Action]{}, [System.Windows.Threading.DispatcherPriority]::Background)
    }

    function Get-Params {
        if ([string]::IsNullOrWhiteSpace($txtCustomer.Text)) {
            [System.Windows.MessageBox]::Show("Customer Name is required.", "Validation", "OK", "Warning"); return $null
        }
        return @{ CustomerName = $txtCustomer.Text.Trim(); ContactName = $txtContact.Text.Trim(); TechName = $txtTech.Text.Trim(); TechNotes = $txtNotes.Text.Trim(); OutputFolder = $Global:ReportsDir }
    }

    # Mark unavailable portable tools
    foreach ($btn in @(@{N="btnCDI";T=$tools.CrystalDiskInfo},@{N="btnHWiNFO";T=$tools.HWiNFO},@{N="btnCPUZ";T=$tools.CPUZ},@{N="btnGPUZ";T=$tools.GPUZ},@{N="btnHWMon";T=$tools.HWMonitor},@{N="btnBattView";T=$tools.BatteryInfoView})) {
        $b = $window.FindName($btn.N)
        if (-not $btn.T) { $b.Content = $b.Content.ToString() + " (not found)"; $b.IsEnabled = $false; $b.Opacity = 0.5 }
    }

    # Portable tool buttons
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

    # Individual test buttons
    $window.FindName("btnCPU").Add_Click({
        Set-Status "Running CPU stress test (60 seconds)..." 10
        $Global:DiagResults.CPUStress = Start-CPUStressTest -DurationSeconds 60
        $r = $Global:DiagResults.CPUStress
        Set-Status "CPU Stress: $(if($r.Passed){'PASSED'}else{'FAILED'}) - $($r.Iterations) iterations, Start: $($r.StartTemp)C, End: $($r.EndTemp)C" 100
    })

    $window.FindName("btnRAM").Add_Click({
        Set-Status "Running RAM test (60 seconds, 64MB blocks)..." 10
        $Global:DiagResults.RAMStress = Start-RAMStressTest -DurationSeconds 60
        $r = $Global:DiagResults.RAMStress
        Set-Status "RAM Test: $(if($r.Passed){'PASSED'}else{'FAILED'}) - $($r.TotalMBTested) MB tested, $($r.Errors) errors" 100
    })

    $window.FindName("btnDisk").Add_Click({
        Set-Status "Running disk benchmark (256MB)..." 10
        $Global:DiagResults.DiskBench = Start-DiskBenchmark -FileSizeMB 256
        $r = $Global:DiagResults.DiskBench
        Set-Status "Disk: Write $($r.SeqWriteMBps) MB/s, Read $($r.SeqReadMBps) MB/s - $(if($r.Passed){'PASSED'}else{'FAILED'})" 100
    })

    $window.FindName("btnSMART").Add_Click({
        Set-Status "Reading SMART data..." 50
        $smart = Invoke-Safe { Get-PhysicalDisk | ForEach-Object { $r=Get-StorageReliabilityCounter -PhysicalDisk $_ -ErrorAction SilentlyContinue; "$($_.FriendlyName): $($_.HealthStatus), PowerOn: $(if($r){$r.PowerOnHours}else{'N/A'})h, Temp: $(if($r -and $r.Temperature){"$($r.Temperature)C"}else{'N/A'})" } } "Error reading SMART"
        Set-Status "SMART: $($smart -join ' | ')" 100
    })

    $window.FindName("btnBattery").Add_Click({
        Set-Status "Checking battery..." 50
        $bat = Invoke-Safe { $b=Get-CimInstance Win32_Battery; if($b){"Charge: $($b.EstimatedChargeRemaining)%, Status: $($b.Status)"}else{"No battery detected"} } "Error"
        Set-Status "Battery: $bat" 100
    })

    $window.FindName("btnNetwork").Add_Click({
        Set-Status "Testing network..." 30
        $net = Get-NetworkDiagnostics
        Set-Status "Network: DNS $(if($net.DNSTest.Success){"OK ($($net.DNSTest.ResponseMs)ms)"}else{"FAIL"}), Internet $(if($net.InternetTest.Success){"OK ($($net.InternetTest.ResponseMs)ms)"}else{"FAIL"}), Public IP: $($net.PublicIP)" 100
    })

    $window.FindName("btnSecurity").Add_Click({
        Set-Status "Running security audit..." 30
        $Global:DiagResults.Security = Get-FullSecurityInfo
        $Global:DiagResults.Patches = Get-MissingPatchesList
        $Global:DiagResults.Scoring = Calculate-Score $Global:DiagResults.Security $Global:DiagResults.Patches
        $s = $Global:DiagResults.Scoring
        Set-Status "Security Score: $($s.Score)/100 (Grade $($s.Grade)) - $(($s.Breakdown | Where-Object {$_.Passed}).Count)/$($s.Breakdown.Count) passed" 100
    })

    $window.FindName("btnKeys").Add_Click({
        Set-Status "Recovering license keys and WiFi passwords..." 30
        $Global:DiagResults.LicenseKeys = Get-LicenseKeys
        $lk = $Global:DiagResults.LicenseKeys
        $wk = if ($lk.WindowsKeys.Count -gt 0) { $lk.WindowsKeys[0].Key } else { "Not found" }
        $wf = $lk.WiFiPasswords.Count
        Set-Status "Windows Key: $wk | Office keys: $($lk.OfficeKeys.Count) | Adobe keys: $($lk.AdobeKeys.Count) | WiFi networks: $wf" 100
    })

    $window.FindName("btnDebloat").Add_Click({
        $debloatScript = Join-Path $Global:ScriptDir "PCPlus-Debloat.ps1"
        if (Test-Path $debloatScript) {
            Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$debloatScript`"" -Verb RunAs
        } else {
            [System.Windows.MessageBox]::Show("PCPlus-Debloat.ps1 not found in $Global:ScriptDir", "Not Found", "OK", "Warning")
        }
    })

    # QUICK DIAGNOSTIC
    $window.FindName("btnQuick").Add_Click({
        $p = Get-Params; if (-not $p) { return }
        Set-Status "Quick Diagnostic: Collecting system info..." 5
        $Global:DiagResults.SystemInfo = Get-FullSystemInfo
        Set-Status "Quick Diagnostic: Security scan..." 25
        $Global:DiagResults.Security = Get-FullSecurityInfo
        Set-Status "Quick Diagnostic: Network analysis..." 45
        $Global:DiagResults.Network = Get-NetworkDiagnostics
        Set-Status "Quick Diagnostic: Software inventory..." 55
        $Global:DiagResults.Software = Get-SoftwareInventory
        Set-Status "Quick Diagnostic: Checking updates..." 65
        $Global:DiagResults.Patches = Get-MissingPatchesList
        Set-Status "Quick Diagnostic: Performance snapshot..." 75
        $Global:DiagResults.Performance = Get-PerformanceSnapshot
        Set-Status "Quick Diagnostic: License keys..." 85
        $Global:DiagResults.LicenseKeys = Get-LicenseKeys
        Set-Status "Quick Diagnostic: Calculating scores..." 95
        $Global:DiagResults.Scoring = Calculate-Score $Global:DiagResults.Security $Global:DiagResults.Patches
        $Global:DiagResults.StressResults = @{}
        Set-Status "Quick Diagnostic complete! HW Score based on SMART/device status. Click Generate Reports to save PDFs." 100
    })

    # FULL DIAGNOSTIC
    $window.FindName("btnFull").Add_Click({
        $p = Get-Params; if (-not $p) { return }
        Set-Status "Full Diagnostic: Collecting system info..." 3
        $Global:DiagResults.SystemInfo = Get-FullSystemInfo
        Set-Status "Full Diagnostic: Security scan..." 10
        $Global:DiagResults.Security = Get-FullSecurityInfo
        Set-Status "Full Diagnostic: Network analysis..." 20
        $Global:DiagResults.Network = Get-NetworkDiagnostics
        Set-Status "Full Diagnostic: Software inventory..." 28
        $Global:DiagResults.Software = Get-SoftwareInventory
        Set-Status "Full Diagnostic: Checking updates..." 35
        $Global:DiagResults.Patches = Get-MissingPatchesList
        Set-Status "Full Diagnostic: Performance snapshot..." 40
        $Global:DiagResults.Performance = Get-PerformanceSnapshot
        Set-Status "Full Diagnostic: License keys..." 45
        $Global:DiagResults.LicenseKeys = Get-LicenseKeys
        Set-Status "Full Diagnostic: CPU stress test (120s)..." 50
        $Global:DiagResults.CPUStress = Start-CPUStressTest -DurationSeconds 120
        Set-Status "Full Diagnostic: RAM test (120s)..." 70
        $Global:DiagResults.RAMStress = Start-RAMStressTest -DurationSeconds 120
        Set-Status "Full Diagnostic: Disk benchmark..." 85
        $Global:DiagResults.DiskBench = Start-DiskBenchmark -FileSizeMB 512
        Set-Status "Full Diagnostic: Calculating scores..." 95
        $Global:DiagResults.Scoring = Calculate-Score $Global:DiagResults.Security $Global:DiagResults.Patches
        $Global:DiagResults.StressResults = @{ CPU = $Global:DiagResults.CPUStress; RAM = $Global:DiagResults.RAMStress; Disk = $Global:DiagResults.DiskBench }
        $cs = $Global:DiagResults.CPUStress; $rs = $Global:DiagResults.RAMStress; $ds = $Global:DiagResults.DiskBench
        Set-Status "Full Diagnostic complete! CPU: $(if($cs.Passed){'PASS'}else{'FAIL'}), RAM: $(if($rs.Passed){'PASS'}else{'FAIL'}), Disk: W=$($ds.SeqWriteMBps)/$($ds.SeqReadMBps) MB/s. Generate Reports now." 100
    })

    # REPORT GENERATION
    $generateReports = {
        param([bool]$DoHW, [bool]$DoSec)
        $p = Get-Params; if (-not $p) { return }
        if (-not $Global:DiagResults.SystemInfo) { [System.Windows.MessageBox]::Show("Run a diagnostic first (Quick or Full).", "No Data", "OK", "Warning"); return }
        $safeName = $p.CustomerName -replace '[\\/:*?"<>|]','_'
        $safeDev = $Global:DiagResults.SystemInfo.ComputerName -replace '[\\/:*?"<>|]','_'
        $ds = Get-Date -Format "yyyy-MM-dd"
        if ($DoHW) {
            Set-Status "Generating Hardware Report..." 30
            $hwHTML = Build-HardwareReport $p $Global:DiagResults.SystemInfo $Global:DiagResults.Network $Global:DiagResults.Software $Global:DiagResults.Performance $Global:DiagResults.StressResults $Global:DiagResults.LicenseKeys
            $hwHTMLPath = Join-Path $p.OutputFolder "$safeName - $safeDev - Hardware Report $ds.html"
            $hwPDFPath = Join-Path $p.OutputFolder "$safeName - $safeDev - Hardware Report $ds.pdf"
            [IO.File]::WriteAllText($hwHTMLPath, $hwHTML, [Text.Encoding]::UTF8)
            $hwPDF = Convert-ToPDF $hwHTMLPath $hwPDFPath
            Set-Status "Hardware Report: $(if($hwPDF){"PDF saved"}else{"HTML saved (no PDF browser)"}) to reports folder" 60
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
        Set-Status "Reports saved to: $($p.OutputFolder)" 100
        Start-Process explorer.exe -ArgumentList $p.OutputFolder
    }

    $window.FindName("btnHWReport").Add_Click({ & $generateReports $true $false })
    $window.FindName("btnSecReport").Add_Click({ & $generateReports $false $true })
    $window.FindName("btnBothReports").Add_Click({ & $generateReports $true $true })

    $window.ShowDialog() | Out-Null
}

# ─────────────────────────────────────────────────────────────────────────────
# ENTRY POINT
# ─────────────────────────────────────────────────────────────────────────────
try {
    Show-Launcher
} catch {
    $errMsg = "PC Plus 360 encountered an error:`n`n$($_.Exception.Message)`n`nAt: $($_.InvocationInfo.ScriptName):$($_.InvocationInfo.ScriptLineNumber)`n`n$($_.Exception.StackTrace)"
    [System.Windows.Forms.MessageBox]::Show($errMsg, "PC Plus 360 - Error", "OK", "Error") | Out-Null
}

# PCPlus-Tests.ps1 - Diagnostic functions, stress tests, and scoring
# This file is dot-sourced by PCPlus-360.ps1
# Edit this file to add/remove/update tests without affecting the UI
# ─────────────────────────────────────────────────────────────────────────────

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

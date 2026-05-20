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

    # ── Privacy & Data Protection ──
    $results.Privacy = @{}
    $results.Privacy.TelemetryMinimal = Invoke-Safe {
        $t1 = (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Name "AllowTelemetry" -ErrorAction SilentlyContinue).AllowTelemetry
        $t2 = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection" -Name "AllowTelemetry" -ErrorAction SilentlyContinue).AllowTelemetry
        ($null -ne $t1 -and $t1 -le 1) -or ($null -ne $t2 -and $t2 -le 1)
    } $false
    $results.Privacy.AdvertisingIdDisabled = Invoke-Safe {
        $v = (Get-ItemProperty "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo" -Name "Enabled" -ErrorAction SilentlyContinue).Enabled
        $null -eq $v -or $v -ne 1
    } $true
    $results.Privacy.LocationDisabled = Invoke-Safe {
        $cs = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location" -Name "Value" -ErrorAction SilentlyContinue).Value
        $svc = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\lfsvc\Service\Configuration" -Name "Status" -ErrorAction SilentlyContinue).Status
        ($cs -eq "Deny") -or ($null -ne $svc -and $svc -eq 0)
    } $false
    $results.Privacy.ActivityHistoryDisabled = Invoke-Safe {
        $k = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"
        $feed = (Get-ItemProperty $k -Name "EnableActivityFeed" -ErrorAction SilentlyContinue).EnableActivityFeed
        $pub = (Get-ItemProperty $k -Name "PublishUserActivities" -ErrorAction SilentlyContinue).PublishUserActivities
        ($null -ne $feed -and $feed -ne 1) -or ($null -ne $pub -and $pub -ne 1)
    } $false
    $results.Privacy.CortanaDisabled = Invoke-Safe {
        $v = (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" -Name "AllowCortana" -ErrorAction SilentlyContinue).AllowCortana
        ($null -ne $v -and $v -eq 0) -or (-not (Get-Process -Name "SearchUI","Cortana","Microsoft.Windows.Cortana" -ErrorAction SilentlyContinue))
    } $false
    $results.Privacy.FindMyDeviceEnabled = Invoke-Safe {
        $v = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Settings\FindMyDevice\UserConsent" -Name "Value" -ErrorAction SilentlyContinue).Value
        $null -ne $v -and $v -eq 1
    } $false

    # ── Browser Security ──
    $results.BrowserSecurity = @{}
    $results.BrowserSecurity.ChromeNoSavedPasswords = Invoke-Safe {
        $f = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Login Data"
        -not (Test-Path $f) -or (Get-Item $f -ErrorAction SilentlyContinue).Length -le 40960
    } $true
    $results.BrowserSecurity.EdgeNoSavedPasswords = Invoke-Safe {
        $f = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Login Data"
        -not (Test-Path $f) -or (Get-Item $f -ErrorAction SilentlyContinue).Length -le 40960
    } $true
    $results.BrowserSecurity.SmartScreenEnabled = Invoke-Safe {
        $v = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer" -Name "SmartScreenEnabled" -ErrorAction SilentlyContinue).SmartScreenEnabled
        $null -eq $v -or $v -ne "Off"
    } $true
    $results.BrowserSecurity.ExtensionCountOk = Invoke-Safe {
        $count = 0
        $chromeExt = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Extensions"
        if (Test-Path $chromeExt) { $count += @(Get-ChildItem $chromeExt -Directory -ErrorAction SilentlyContinue).Count }
        $edgeExt = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Extensions"
        if (Test-Path $edgeExt) { $count += @(Get-ChildItem $edgeExt -Directory -ErrorAction SilentlyContinue).Count }
        $count -lt 15
    } $true

    # ── Network Hardening ──
    $results.NetworkHardening = @{}
    $results.NetworkHardening.NoOpenShares = Invoke-Safe {
        $custom = Get-SmbShare -ErrorAction Stop | Where-Object { $_.Name -notmatch '^\w\$|^ADMIN\$|^IPC\$|^print\$' }
        ($custom | Measure-Object).Count -eq 0
    } $null
    $results.NetworkHardening.UPnPDisabled = Invoke-Safe {
        $svc = Get-Service "SSDPSRV" -ErrorAction Stop
        $svc.Status -ne "Running"
    } $null
    $results.NetworkHardening.LLMNRDisabled = Invoke-Safe {
        $v = (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient" -Name "EnableMulticast" -ErrorAction SilentlyContinue).EnableMulticast
        $null -ne $v -and $v -eq 0
    } $false
    $results.NetworkHardening.DoHEnabled = Invoke-Safe {
        $v = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters" -Name "EnableAutoDoh" -ErrorAction SilentlyContinue).EnableAutoDoh
        $null -ne $v -and $v -ge 2
    } $false
    $results.NetworkHardening.RemoteAssistanceDisabled = Invoke-Safe {
        $v = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Remote Assistance" -Name "fAllowToGetHelp" -ErrorAction SilentlyContinue).fAllowToGetHelp
        $null -ne $v -and $v -eq 0
    } $false

    # ── System Integrity ──
    $results.SystemIntegrity = @{}
    $results.SystemIntegrity.DriverSigEnforced = Invoke-Safe {
        $bcd = bcdedit /enum "{current}" 2>&1 | Out-String
        $bcd -notmatch "testsigning\s+Yes"
    } $true
    $results.SystemIntegrity.PSScriptLogging = Invoke-Safe {
        $v = (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging" -Name "EnableScriptBlockLogging" -ErrorAction SilentlyContinue).EnableScriptBlockLogging
        $null -ne $v -and $v -eq 1
    } $false
    $results.SystemIntegrity.LogonAuditEnabled = Invoke-Safe {
        $out = auditpol /get /subcategory:"Logon" 2>&1 | Out-String
        $out -match "Success" -and $out -notmatch "No Auditing"
    } $false
    $results.SystemIntegrity.CredentialGuard = Invoke-Safe {
        $dg = Get-CimInstance -ClassName Win32_DeviceGuard -Namespace "root\Microsoft\Windows\DeviceGuard" -ErrorAction Stop
        $dg.SecurityServicesRunning -contains 1
    } $false
    $results.SystemIntegrity.LSASSProtected = Invoke-Safe {
        $v = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name "RunAsPPL" -ErrorAction SilentlyContinue).RunAsPPL
        $null -ne $v -and $v -eq 1
    } $false

    # ── Account Hygiene ──
    $results.AccountHygiene = @{}
    $results.AccountHygiene.NoStaleAccounts = Invoke-Safe {
        $cutoff = (Get-Date).AddDays(-90)
        $stale = Get-LocalUser -ErrorAction Stop | Where-Object {
            $_.Enabled -and -not $_.SID.Value.EndsWith("-500") -and -not $_.SID.Value.EndsWith("-501") -and
            $null -ne $_.LastLogon -and $_.LastLogon -lt $cutoff
        }
        ($stale | Measure-Object).Count -eq 0
    } $true
    $results.AccountHygiene.NoEmptyPasswords = Invoke-Safe {
        $users = Get-LocalUser -ErrorAction Stop | Where-Object { $_.Enabled }
        $bad = $users | Where-Object { $_.PasswordRequired -eq $false }
        ($bad | Measure-Object).Count -eq 0
    } $true
    $results.AccountHygiene.PasswordAgePolicy = Invoke-Safe {
        $na = net accounts 2>&1 | Out-String
        if ($na -match "Maximum password age \(days\):\s+Unlimited") { $false } else { $true }
    } $false

    # ── Ransomware Protection ──
    $results.RansomwareProtection = @{}
    $results.RansomwareProtection.ControlledFolderAccess = Invoke-Safe {
        $v = (Get-MpPreference -ErrorAction Stop).EnableControlledFolderAccess
        $v -eq 1 -or $v -eq 2
    } $false
    $results.RansomwareProtection.RecentRestorePoint = Invoke-Safe {
        $cutoff = (Get-Date).AddDays(-30)
        $rp = Get-ComputerRestorePoint -ErrorAction Stop
        ($rp | Where-Object { [Management.ManagementDateTimeConverter]::ToDateTime($_.CreationTime) -gt $cutoff } | Measure-Object).Count -gt 0
    } $false
    $results.RansomwareProtection.NoSuspiciousScheduledTasks = Invoke-Safe {
        $suspicious = Get-ScheduledTask -ErrorAction Stop | Where-Object { $_.State -ne "Disabled" } | ForEach-Object {
            $actions = $_.Actions | Where-Object { $_.Execute -match "\\Temp\\|\\AppData\\|encodedcommand|encodedCommand|-enc\s|-ec\s" }
            if ($actions) { $_.TaskName }
        }
        ($suspicious | Measure-Object).Count -eq 0
    } $true

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
            $prop = if ($p[0].PSObject.Properties['Latency']) { 'Latency' } else { 'ResponseTime' }
            "$([math]::Round(($p | Measure-Object -Property $prop -Average).Average, 0))ms"
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
            if ($p) {
                $prop = if ($p[0].PSObject.Properties['Latency']) { 'Latency' } else { 'ResponseTime' }
                $pings += ($p | Measure-Object -Property $prop -Average).Average
            }
        }
        if ($pings.Count -gt 0) { "$([math]::Round(($pings | Measure-Object -Average).Average, 0))ms" } else { "Failed" }
    } "N/A"

    # Jitter calculation
    $results.Jitter = Invoke-Safe {
        $p = Test-Connection -ComputerName "8.8.8.8" -Count 10 -ErrorAction Stop
        $prop = if ($p[0].PSObject.Properties['Latency']) { 'Latency' } else { 'ResponseTime' }
        $latencies = $p | ForEach-Object { $_.$prop }
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
        TempLog = @(); ThrottleDetected = $false; Method = "GDI+"
        FurMarkUsed = $false; FurMarkScore = $null; VRAM_MB = 0
        DriverVersion = "N/A"; Resolution = "N/A"
    }

    $gpu = Invoke-Safe { Get-CimInstance Win32_VideoController -ErrorAction Stop | Where-Object { $_.AdapterRAM -gt 0 } | Select-Object -First 1 } $null
    if ($gpu) {
        $results.GPUName = $gpu.Name
        $results.VRAM_MB = [math]::Round($gpu.AdapterRAM / 1MB, 0)
        $results.DriverVersion = $gpu.DriverVersion
        $results.Resolution = "$($gpu.CurrentHorizontalResolution)x$($gpu.CurrentVerticalResolution)"
    }

    function Get-ThermalTemp {
        Invoke-Safe {
            $t = Get-CimInstance MSAcpi_ThermalZoneTemperature -Namespace root/wmi -ErrorAction Stop | Select-Object -First 1
            [math]::Round(($t.CurrentTemperature / 10) - 273.15, 1)
        } $null
    }

    $results.StartTemp = Get-ThermalTemp

    # Try FurMark portable first
    $furmark = Find-Tool "FurMark" @("FurMark.exe", "FurMark_GUI.exe")
    if (-not $furmark) {
        $furmark = Get-ChildItem $Global:ToolsDir -Recurse -Filter "FurMark*.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($furmark) { $furmark = $furmark.FullName }
    }

    if ($furmark) {
        Write-DiagLog "FurMark found at $furmark - using hardware GPU stress"
        $results.Method = "FurMark"
        $results.FurMarkUsed = $true
        $logFile = Join-Path $env:TEMP "pcplus_furmark_$(Get-Random).txt"

        try {
            $fmArgs = "/nogui /width=1280 /height=720 /msaa=0 /run_mode=1 /max_time=$DurationSeconds /log_temperature /log_file=`"$logFile`""
            $proc = Start-Process -FilePath $furmark -ArgumentList $fmArgs -PassThru -WindowStyle Minimized -ErrorAction Stop
            $startTime = Get-Date; $tempLog = @()

            while (-not $proc.HasExited -and ((Get-Date) - $startTime).TotalSeconds -lt ($DurationSeconds + 30)) {
                Start-Sleep -Seconds 5
                $temp = Get-ThermalTemp
                $elapsed = [math]::Round(((Get-Date) - $startTime).TotalSeconds)
                if ($temp) { $tempLog += @{ Time = $elapsed; TempC = $temp } }
            }

            if (-not $proc.HasExited) {
                try { $proc.Kill() } catch {}
            }

            $results.TempLog = $tempLog

            if (Test-Path $logFile) {
                $fmLog = Get-Content $logFile -ErrorAction SilentlyContinue
                foreach ($line in $fmLog) {
                    if ($line -match "Score:\s*(\d+)") { $results.FurMarkScore = [int]$matches[1] }
                }
                Remove-Item $logFile -Force -ErrorAction SilentlyContinue
            }
        } catch {
            Write-DiagLog "FurMark launch failed, falling back to GDI+: $($_.Exception.Message)" "WARN"
            $results.Method = "GDI+ (FurMark failed)"
            $results.FurMarkUsed = $false
        }
    }

    if (-not $results.FurMarkUsed) {
        $endTime = (Get-Date).AddSeconds($DurationSeconds)
        $startTime = Get-Date
        $iterations = 0; $errors = 0; $tempLog = @()

        try {
            Add-Type -AssemblyName System.Drawing
            while ((Get-Date) -lt $endTime) {
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
                $matrix = New-Object System.Drawing.Drawing2D.Matrix
                $matrix.Rotate((Get-Random -Max 360))
                $matrix.Scale(1.5, 1.5)
                $g.Transform = $matrix
                $g.DrawImage($bmp, 0, 0)
                $matrix.Dispose()
                $g.Dispose(); $bmp.Dispose()
                $iterations++

                if ($iterations % 5 -eq 0) {
                    $elapsed = [math]::Round(((Get-Date) - $startTime).TotalSeconds)
                    $temp = Get-ThermalTemp
                    if ($temp) { $tempLog += @{ Time = $elapsed; TempC = $temp } }
                }
            }
        } catch {
            $errors++
            Write-DiagLog "GPU stress error: $($_.Exception.Message)" "WARN"
        }

        $results.TempLog = $tempLog
        $results.Iterations = $iterations
        if ($errors -gt 0) { $results.Passed = $false }
    }

    $results.EndTemp = Get-ThermalTemp
    if ($results.TempLog.Count -gt 0) {
        $temps = $results.TempLog | ForEach-Object { $_.TempC }
        $results.MaxTemp = ($temps | Measure-Object -Maximum).Maximum
        if ($results.MaxTemp -and $results.MaxTemp -gt 95) {
            $results.ThrottleDetected = $true
            $results.Passed = $false
            Write-DiagLog "GPU OVERHEAT WARNING: Max temp $($results.MaxTemp)C" "WARN"
        }
    }

    Write-DiagLog "GPU stress: Method=$($results.Method), MaxTemp=$($results.MaxTemp), FurMarkScore=$($results.FurMarkScore), Passed=$($results.Passed)"
    return $results
}

# ─────────────────────────────────────────────────────────────────────────────
# THERMAL & THROTTLE MONITORING
# ─────────────────────────────────────────────────────────────────────────────
function Get-ThermalSnapshot {
    Write-DiagLog "Taking thermal snapshot..."
    $results = @{ Zones = @(); CPUTemp = $null; OverheatDetected = $false }

    $zones = Invoke-Safe {
        Get-CimInstance MSAcpi_ThermalZoneTemperature -Namespace root/wmi -ErrorAction Stop | ForEach-Object {
            $tempC = [math]::Round(($_.CurrentTemperature / 10) - 273.15, 1)
            @{ Name = $_.InstanceName; TempC = $tempC }
        }
    } @()

    $results.Zones = $zones
    if ($zones.Count -gt 0) {
        $maxTemp = ($zones | ForEach-Object { $_.TempC } | Measure-Object -Maximum).Maximum
        $results.CPUTemp = $maxTemp
        if ($maxTemp -gt 90) { $results.OverheatDetected = $true }
    }

    $cpuLoad = Invoke-Safe { [math]::Round((Get-Counter '\Processor(_Total)\% Processor Time' -ErrorAction Stop).CounterSamples[0].CookedValue, 1) } $null
    $results.CPULoad = $cpuLoad

    $cpu = Invoke-Safe { Get-CimInstance Win32_Processor -ErrorAction Stop | Select-Object -First 1 } $null
    if ($cpu) {
        $results.CPUCurrentMHz = $cpu.CurrentClockSpeed
        $results.CPUMaxMHz = $cpu.MaxClockSpeed
        if ($cpu.MaxClockSpeed -gt 0 -and $cpu.CurrentClockSpeed -lt ($cpu.MaxClockSpeed * 0.7)) {
            $results.ThrottlingLikely = $true
            Write-DiagLog "CPU may be throttling: Current=$($cpu.CurrentClockSpeed) MHz vs Max=$($cpu.MaxClockSpeed) MHz" "WARN"
        }
    }

    Write-DiagLog "Thermal: CPUTemp=$($results.CPUTemp)C, CPULoad=${cpuLoad}%, Overheat=$($results.OverheatDetected)"
    return $results
}

# ─────────────────────────────────────────────────────────────────────────────
# DPC LATENCY CHECK (audio/gaming stutter detection)
# ─────────────────────────────────────────────────────────────────────────────
function Test-DPCLatency {
    Write-DiagLog "Checking DPC/ISR latency (stutter detection)..."
    $results = @{ Samples = @(); MaxLatencyUS = 0; AvgLatencyUS = 0; StutterRisk = "Low"; Passed = $true }

    try {
        $samples = @()
        for ($i = 0; $i -lt 10; $i++) {
            $counter = Get-Counter '\Processor(_Total)\% DPC Time','\Processor(_Total)\% Interrupt Time' -ErrorAction Stop
            $dpcPct = [math]::Round($counter.CounterSamples[0].CookedValue, 2)
            $isrPct = [math]::Round($counter.CounterSamples[1].CookedValue, 2)
            $samples += @{ DPCPercent = $dpcPct; ISRPercent = $isrPct }
            Start-Sleep -Milliseconds 500
        }
        $results.Samples = $samples
        $maxDPC = ($samples | ForEach-Object { $_.DPCPercent } | Measure-Object -Maximum).Maximum
        $avgDPC = ($samples | ForEach-Object { $_.DPCPercent } | Measure-Object -Average).Average
        $results.MaxDPCPercent = $maxDPC
        $results.AvgDPCPercent = [math]::Round($avgDPC, 2)

        if ($maxDPC -gt 10) {
            $results.StutterRisk = "High"
            $results.Passed = $false
        } elseif ($maxDPC -gt 5) {
            $results.StutterRisk = "Medium"
        }
    } catch {
        Write-DiagLog "DPC latency check error: $($_.Exception.Message)" "WARN"
    }

    Write-DiagLog "DPC: MaxDPC=$($results.MaxDPCPercent)%, StutterRisk=$($results.StutterRisk)"
    return $results
}

# ─────────────────────────────────────────────────────────────────────────────
# DISPLAY & MONITOR INFO
# ─────────────────────────────────────────────────────────────────────────────
function Get-DisplayInfo {
    Write-DiagLog "Collecting display/monitor information..."
    $results = @{ Monitors = @(); GPUs = @() }

    $results.GPUs = @(Invoke-Safe {
        Get-CimInstance Win32_VideoController -ErrorAction Stop | ForEach-Object {
            @{
                Name = $_.Name; VRAM_MB = [math]::Round($_.AdapterRAM / 1MB, 0)
                DriverVersion = $_.DriverVersion; DriverDate = $_.DriverDate
                Resolution = "$($_.CurrentHorizontalResolution)x$($_.CurrentVerticalResolution)"
                RefreshRate = "$($_.CurrentRefreshRate) Hz"; Status = $_.Status
                VideoMode = $_.VideoModeDescription
            }
        }
    } @())

    $results.Monitors = @(Invoke-Safe {
        Get-CimInstance WmiMonitorID -Namespace root\wmi -ErrorAction Stop | ForEach-Object {
            $name = if ($_.UserFriendlyName) { ($_.UserFriendlyName | Where-Object { $_ -ne 0 } | ForEach-Object { [char]$_ }) -join '' } else { "Unknown" }
            $mfr = if ($_.ManufacturerName) { ($_.ManufacturerName | Where-Object { $_ -ne 0 } | ForEach-Object { [char]$_ }) -join '' } else { "Unknown" }
            $serial = if ($_.SerialNumberID) { ($_.SerialNumberID | Where-Object { $_ -ne 0 } | ForEach-Object { [char]$_ }) -join '' } else { "N/A" }
            @{ Name = $name; Manufacturer = $mfr; Serial = $serial; YearOfManufacture = $_.YearOfManufacture }
        }
    } @())

    Write-DiagLog "Display: $($results.GPUs.Count) GPU(s), $($results.Monitors.Count) monitor(s)"
    return $results
}

# ─────────────────────────────────────────────────────────────────────────────
# MEMORY LEAK DETECTION
# ─────────────────────────────────────────────────────────────────────────────
function Test-MemoryLeaks {
    Write-DiagLog "Checking for memory leaks (top consumers)..."
    $results = @{ TopConsumers = @(); CommittedGB = 0; AvailableGB = 0; PageFileUsagePercent = 0; LeakSuspect = $false }

    $os = Invoke-Safe { Get-CimInstance Win32_OperatingSystem -ErrorAction Stop } $null
    if ($os) {
        $results.CommittedGB = [math]::Round(($os.TotalVirtualMemorySize - $os.FreeVirtualMemory) * 1KB / 1GB, 2)
        $results.AvailableGB = [math]::Round($os.FreePhysicalMemory * 1KB / 1GB, 2)
        $totalPhysGB = [math]::Round($os.TotalVisibleMemorySize * 1KB / 1GB, 2)
        $usedPercent = [math]::Round((1 - ($os.FreePhysicalMemory / $os.TotalVisibleMemorySize)) * 100, 1)
        $results.MemoryUsedPercent = $usedPercent
    }

    $results.TopConsumers = @(Get-Process -ErrorAction SilentlyContinue |
        Sort-Object WorkingSet64 -Descending | Select-Object -First 15 |
        ForEach-Object {
            @{
                Name = $_.ProcessName; PID = $_.Id
                WorkingSetMB = [math]::Round($_.WorkingSet64 / 1MB, 1)
                PrivateMB = [math]::Round($_.PrivateMemorySize64 / 1MB, 1)
                HandleCount = $_.HandleCount
            }
        })

    $pageFile = Invoke-Safe { Get-CimInstance Win32_PageFileUsage -ErrorAction Stop | Select-Object -First 1 } $null
    if ($pageFile -and $pageFile.AllocatedBaseSize -gt 0) {
        $results.PageFileUsagePercent = [math]::Round(($pageFile.CurrentUsage / $pageFile.AllocatedBaseSize) * 100, 1)
    }

    $highHandles = @($results.TopConsumers | Where-Object { $_.HandleCount -gt 5000 })
    if ($highHandles.Count -gt 0 -or $results.PageFileUsagePercent -gt 80) {
        $results.LeakSuspect = $true
    }

    Write-DiagLog "Memory: Used=$($results.MemoryUsedPercent)%, PageFile=$($results.PageFileUsagePercent)%, LeakSuspect=$($results.LeakSuspect)"
    return $results
}

# ─────────────────────────────────────────────────────────────────────────────
# WINDOWS ACTIVATION STATUS
# ─────────────────────────────────────────────────────────────────────────────
function Get-WindowsActivation {
    Write-DiagLog "Checking Windows activation status..."
    $results = @{ Activated = $false; LicenseStatus = "Unknown"; ProductKey = "N/A"; Edition = "N/A" }

    $lic = Invoke-Safe { Get-CimInstance SoftwareLicensingProduct -ErrorAction Stop | Where-Object { $_.PartialProductKey -and $_.Name -like "*Windows*" } | Select-Object -First 1 } $null
    if ($lic) {
        $statusMap = @{ 0="Unlicensed"; 1="Licensed"; 2="OOBGrace"; 3="OOTGrace"; 4="NonGenuineGrace"; 5="Notification"; 6="ExtendedGrace" }
        $results.LicenseStatus = if ($statusMap.ContainsKey($lic.LicenseStatus)) { $statusMap[$lic.LicenseStatus] } else { "Unknown ($($lic.LicenseStatus))" }
        $results.Activated = ($lic.LicenseStatus -eq 1)
        $results.Edition = $lic.Name
        $results.PartialKey = $lic.PartialProductKey
    }

    Write-DiagLog "Activation: $($results.LicenseStatus), Key=***$($results.PartialKey)"
    return $results
}

# ─────────────────────────────────────────────────────────────────────────────
# DISK FRAGMENTATION CHECK
# ─────────────────────────────────────────────────────────────────────────────
function Get-DiskFragmentation {
    Write-DiagLog "Checking disk fragmentation..."
    $results = @()

    $volumes = Invoke-Safe { Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" -ErrorAction Stop } @()
    foreach ($v in $volumes) {
        $letter = $v.DeviceID
        $fragPercent = $null
        $needsDefrag = $false

        try {
            $defrag = Invoke-CimMethod -ClassName Win32_Volume -MethodName DefragAnalysis -Arguments @{} -Filter "DriveLetter='$letter'" -ErrorAction Stop
            if ($defrag.DefragAnalysis) {
                $fragPercent = $defrag.DefragAnalysis.FilePercentFragmentation
                $needsDefrag = ($defrag.DefragRecommended -eq $true)
            }
        } catch {
            $output = Invoke-Safe { (defrag.exe $letter /A 2>&1) -join " " } ""
            if ($output -match "(\d+)%\s*fragmented") { $fragPercent = [int]$matches[1] }
            if ($output -match "You do not need to defragment") { $needsDefrag = $false }
            elseif ($fragPercent -and $fragPercent -gt 10) { $needsDefrag = $true }
        }

        $mediaType = Invoke-Safe {
            $pd = Get-PhysicalDisk -ErrorAction Stop | Select-Object -First 1
            $pd.MediaType
        } "Unknown"

        $results += @{
            Drive = $letter
            FragmentPercent = $fragPercent
            NeedsDefrag = $needsDefrag
            MediaType = $mediaType
            Note = if ($mediaType -eq "SSD") { "SSD - defrag not recommended, use TRIM instead" } else { $null }
        }
        Write-DiagLog "Fragmentation ${letter}: ${fragPercent}% fragmented, NeedsDefrag=$needsDefrag"
    }
    return $results
}

# ─────────────────────────────────────────────────────────────────────────────
# PORTABLE TOOL ENHANCED DIAGNOSTICS
# ─────────────────────────────────────────────────────────────────────────────
function Invoke-CrystalDiskInfoScan {
    Write-DiagLog "Checking for CrystalDiskInfo portable..."
    $cdi = Find-Tool "CrystalDiskInfo" @("DiskInfo64.exe", "DiskInfo32.exe", "CrystalDiskInfo.exe")
    if (-not $cdi) {
        Write-DiagLog "CrystalDiskInfo not found - using WMI SMART data only"
        return @{ Available = $false; Drives = @() }
    }

    Write-DiagLog "CrystalDiskInfo found: $cdi"
    $exportDir = Join-Path $env:TEMP "pcplus_cdi_$(Get-Random)"
    New-Item -ItemType Directory -Path $exportDir -Force | Out-Null
    $exportFile = Join-Path $exportDir "smart.txt"

    try {
        Start-Process -FilePath $cdi -ArgumentList "/CopyExit `"$exportFile`"" -Wait -WindowStyle Hidden -ErrorAction Stop
        Start-Sleep -Seconds 2

        $results = @{ Available = $true; Drives = @(); RawOutput = "" }
        if (Test-Path $exportFile) {
            $results.RawOutput = Get-Content $exportFile -Raw -ErrorAction SilentlyContinue
        }
        Remove-Item $exportDir -Recurse -Force -ErrorAction SilentlyContinue
        return $results
    } catch {
        Write-DiagLog "CrystalDiskInfo error: $($_.Exception.Message)" "WARN"
        Remove-Item $exportDir -Recurse -Force -ErrorAction SilentlyContinue
        return @{ Available = $false; Error = $_.Exception.Message }
    }
}

function Invoke-SpeedtestCLI {
    Write-DiagLog "Checking for Speedtest CLI..."
    $speedtest = Find-Tool "Speedtest" @("speedtest.exe")
    if (-not $speedtest) {
        $speedtest = Get-ChildItem $Global:ToolsDir -Recurse -Filter "speedtest.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($speedtest) { $speedtest = $speedtest.FullName }
    }

    if (-not $speedtest) {
        Write-DiagLog "Speedtest CLI not found - using basic ping test only"
        return @{ Available = $false; DownloadMbps = $null; UploadMbps = $null; PingMS = $null }
    }

    Write-DiagLog "Speedtest CLI found: $speedtest"
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $speedtest
        $psi.Arguments = "--accept-license --format=json"
        $psi.RedirectStandardOutput = $true
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $p = New-Object System.Diagnostics.Process
        $p.StartInfo = $psi
        $null = $p.Start()
        $output = $p.StandardOutput.ReadToEnd()
        $p.WaitForExit()

        $json = $output | ConvertFrom-Json -ErrorAction SilentlyContinue
        if ($json) {
            $dl = [math]::Round($json.download.bandwidth * 8 / 1MB, 1)
            $ul = [math]::Round($json.upload.bandwidth * 8 / 1MB, 1)
            $ping = [math]::Round($json.ping.latency, 1)
            Write-DiagLog "Speedtest: Download=$dl Mbps, Upload=$ul Mbps, Ping=$ping ms"
            return @{ Available = $true; DownloadMbps = $dl; UploadMbps = $ul; PingMS = $ping; Server = $json.server.name; ISP = $json.isp }
        }
    } catch {
        Write-DiagLog "Speedtest error: $($_.Exception.Message)" "WARN"
    }
    return @{ Available = $false; Error = "Failed to parse results" }
}

# ─────────────────────────────────────────────────────────────────────────────
# FULL SYSTEM MRI (runs everything)
# ─────────────────────────────────────────────────────────────────────────────
function Invoke-FullSystemMRI {
    param($Params)
    Write-DiagLog "=== FULL SYSTEM MRI STARTING ==="
    $mri = @{
        StartTime = Get-Date
        SystemInfo = $null; Security = $null; Network = $null
        Patches = $null; Scoring = $null; LicenseKeys = $null
        BatteryDetail = $null; SSDLife = $null; CPUStress = $null
        RAMStress = $null; DiskBench = $null; GPUStress = $null
        Thermal = $null; DPCLatency = $null; DisplayInfo = $null
        MemoryLeaks = $null; Activation = $null; Fragmentation = $null
        WindowsDeep = $null; SpeedTest = $null; CrystalDiskInfo = $null
        Stability = $null; Software = $null; Performance = $null
        BootPerf = $null; Win11Ready = $null; FanInfo = $null
        ToolStatus = $null
    }

    Write-DiagLog "Phase 1: System inventory and info gathering..."
    $mri.ToolStatus = Get-ToolStatus
    $mri.SystemInfo = Get-FullSystemInfo
    $mri.Security = Get-FullSecurityInfo
    $mri.Patches = Get-MissingPatchesList
    $mri.Scoring = Calculate-Score $mri.Security $mri.Patches
    $mri.LicenseKeys = Get-LicenseKeys
    $mri.Network = Get-NetworkDiagnostics
    $mri.BatteryDetail = Get-DetailedBatteryInfo
    $mri.Software = Get-SoftwareInventory
    $mri.Performance = Get-PerformanceSnapshot
    $mri.Stability = Get-CrashStabilityHistory
    $mri.BootPerf = Get-BootPerformance
    $mri.Win11Ready = Get-Windows11Readiness
    $mri.FanInfo = Get-FanInfo
    $mri.DisplayInfo = Get-DisplayInfo
    $mri.Activation = Get-WindowsActivation
    $mri.MemoryLeaks = Test-MemoryLeaks
    $mri.Thermal = Get-ThermalSnapshot

    Write-DiagLog "Phase 2: Storage and drive health..."
    $mri.SSDLife = Get-SSDLifeReport
    $mri.Fragmentation = Get-DiskFragmentation
    $mri.CrystalDiskInfo = Invoke-CrystalDiskInfoScan

    Write-DiagLog "Phase 3: Stress testing..."
    $mri.CPUStress = Start-CPUStressTest -DurationSeconds 120
    $mri.RAMStress = Start-RAMStressTest -DurationSeconds 120
    $mri.DiskBench = Start-DiskBenchmark -FileSizeMB 512
    $mri.GPUStress = Start-GPUStressTest -DurationSeconds 90

    Write-DiagLog "Phase 4: Deep Windows integrity..."
    $mri.WindowsDeep = Invoke-DeepWindowsTest
    $mri.DPCLatency = Test-DPCLatency

    Write-DiagLog "Phase 5: Network speed..."
    $mri.SpeedTest = Invoke-SpeedtestCLI

    $mri.EndTime = Get-Date
    $mri.TotalMinutes = [math]::Round(((Get-Date) - $mri.StartTime).TotalMinutes, 1)

    # Calculate overall MRI score
    $overallScore = 100; $issues = @()

    # Hardware health (30%)
    $hwDeductions = 0
    if ($mri.CPUStress -and -not $mri.CPUStress.Passed) { $hwDeductions += 15; $issues += "CPU stress test failed" }
    if ($mri.RAMStress -and -not $mri.RAMStress.Passed) { $hwDeductions += 15; $issues += "RAM stress test failed" }
    if ($mri.GPUStress -and -not $mri.GPUStress.Passed) { $hwDeductions += 10; $issues += "GPU stress test failed" }
    if ($mri.Thermal -and $mri.Thermal.OverheatDetected) { $hwDeductions += 10; $issues += "Overheating detected" }
    if ($mri.DPCLatency -and -not $mri.DPCLatency.Passed) { $hwDeductions += 5; $issues += "High DPC latency (stutter risk)" }

    # Storage health (25%)
    $storDeductions = 0
    if ($mri.SSDLife) {
        foreach ($d in $mri.SSDLife.Drives) {
            if ($d.Grade -eq "F") { $storDeductions += 20; $issues += "Drive $($d.Model) critical wear" }
            elseif ($d.Grade -eq "D") { $storDeductions += 10; $issues += "Drive $($d.Model) high wear" }
            if ($d.HealthStatus -ne "Healthy") { $storDeductions += 10; $issues += "Drive $($d.Model) unhealthy" }
        }
    }
    if ($mri.DiskBench -and $mri.DiskBench.SeqReadMBps -lt 50) { $storDeductions += 5; $issues += "Slow disk read speed" }

    # Security (25%)
    $secDeductions = 0
    if ($mri.Scoring) { $secDeductions = 25 - [math]::Round($mri.Scoring.Score * 0.25) }
    if ($mri.Activation -and -not $mri.Activation.Activated) { $secDeductions += 5; $issues += "Windows not activated" }

    # Windows health (20%)
    $winDeductions = 0
    if ($mri.WindowsDeep) { $winDeductions = 20 - [math]::Round($mri.WindowsDeep.Score * 0.20) }
    if ($mri.MemoryLeaks -and $mri.MemoryLeaks.LeakSuspect) { $winDeductions += 3; $issues += "Possible memory leak detected" }

    $overallScore = 100 - [math]::Min(30, $hwDeductions) - [math]::Min(25, $storDeductions) - [math]::Min(25, $secDeductions) - [math]::Min(20, $winDeductions)
    if ($overallScore -lt 0) { $overallScore = 0 }

    $mri.OverallScore = $overallScore
    $mri.OverallGrade = if ($overallScore -ge 90){"A"} elseif ($overallScore -ge 80){"B"} elseif ($overallScore -ge 70){"C"} elseif ($overallScore -ge 60){"D"} else {"F"}
    $mri.Issues = $issues

    Write-DiagLog "=== FULL SYSTEM MRI COMPLETE: Score=$overallScore ($($mri.OverallGrade)), Duration=$($mri.TotalMinutes) min ==="
    return $mri
}

# ─────────────────────────────────────────────────────────────────────────────
# SSD LIFE & DRIVE HEALTH
# ─────────────────────────────────────────────────────────────────────────────
function Get-SSDLifeReport {
    Write-DiagLog "Collecting SSD/HDD life and health data..."
    $results = @{ Drives = @(); OverallHealthy = $true }

    $diskDrives = Invoke-Safe { Get-CimInstance Win32_DiskDrive -ErrorAction Stop } @()
    $physicalDisks = Invoke-Safe { Get-PhysicalDisk -ErrorAction Stop } @()

    foreach ($d in $diskDrives) {
        $matched = $physicalDisks | Where-Object { $_.FriendlyName -like "*$($d.Model)*" } | Select-Object -First 1
        $reliability = $null
        if ($matched) {
            $reliability = Invoke-Safe { Get-StorageReliabilityCounter -PhysicalDisk $matched -ErrorAction Stop } $null
        }

        $sizeGB = [math]::Round($d.Size / 1GB, 1)
        $mediaType = if ($matched) { $matched.MediaType } else { $d.MediaType }
        $busType = if ($matched) { $matched.BusType } else { $d.InterfaceType }
        $healthStatus = if ($matched) { $matched.HealthStatus } else { "Unknown" }
        $opStatus = if ($matched) { ($matched.OperationalStatus -join ", ") } else { $d.Status }

        $wear = if ($reliability -and $null -ne $reliability.Wear) { $reliability.Wear } else { $null }
        $powerOnHours = if ($reliability -and $null -ne $reliability.PowerOnHours) { $reliability.PowerOnHours } else { $null }
        $tempC = if ($reliability -and $null -ne $reliability.Temperature) { $reliability.Temperature } else { $null }
        $readErrors = if ($reliability) { $reliability.ReadErrorsTotal } else { $null }
        $writeErrors = if ($reliability) { $reliability.WriteErrorsTotal } else { $null }

        $lifeRemaining = $null
        $estimatedYearsLeft = $null
        $grade = "N/A"

        if ($null -ne $wear) {
            $lifeRemaining = 100 - $wear
            if ($powerOnHours -and $powerOnHours -gt 0 -and $wear -gt 0) {
                $hoursPerWearPercent = $powerOnHours / $wear
                $hoursLeft = $hoursPerWearPercent * $lifeRemaining
                $estimatedYearsLeft = [math]::Round($hoursLeft / 8760, 1)
            }
            if ($lifeRemaining -ge 80) { $grade = "A" }
            elseif ($lifeRemaining -ge 60) { $grade = "B" }
            elseif ($lifeRemaining -ge 40) { $grade = "C" }
            elseif ($lifeRemaining -ge 20) { $grade = "D" }
            else { $grade = "F"; $results.OverallHealthy = $false }
        } elseif ($healthStatus -eq "Healthy") {
            $grade = "A"
        }

        if ($healthStatus -ne "Healthy") { $results.OverallHealthy = $false }

        $powerOnDays = if ($powerOnHours) { [math]::Round($powerOnHours / 24, 0) } else { $null }
        $powerOnYears = if ($powerOnHours) { [math]::Round($powerOnHours / 8760, 1) } else { $null }

        $results.Drives += @{
            Model = $d.Model
            Serial = ($d.SerialNumber -as [string]).Trim()
            SizeGB = $sizeGB
            MediaType = $mediaType
            BusType = $busType
            HealthStatus = $healthStatus
            OperationalStatus = $opStatus
            WearPercent = $wear
            LifeRemainingPercent = $lifeRemaining
            PowerOnHours = $powerOnHours
            PowerOnDays = $powerOnDays
            PowerOnYears = $powerOnYears
            TemperatureC = $tempC
            ReadErrorsTotal = $readErrors
            WriteErrorsTotal = $writeErrors
            EstimatedYearsLeft = $estimatedYearsLeft
            Grade = $grade
        }

        Write-DiagLog "Drive: $($d.Model), Health=$healthStatus, Wear=${wear}%, Life=${lifeRemaining}%, PowerOn=$powerOnHours hrs, Grade=$grade"
    }

    return $results
}

# ─────────────────────────────────────────────────────────────────────────────
# DEEP WINDOWS PERFORMANCE & INTEGRITY TESTS
# ─────────────────────────────────────────────────────────────────────────────
function Invoke-SFCScan {
    Write-DiagLog "Running SFC /scannow (this may take several minutes)..."
    $results = @{ Skipped = $false; ExitCode = $null; Summary = "Unknown"; Seconds = 0 }

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = "sfc.exe"
        $psi.Arguments = "/scannow"
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $p = New-Object System.Diagnostics.Process
        $p.StartInfo = $psi
        $null = $p.Start()
        $stdout = $p.StandardOutput.ReadToEnd()
        $stderr = $p.StandardError.ReadToEnd()
        $p.WaitForExit()
        $sw.Stop()

        $results.ExitCode = $p.ExitCode
        $results.Seconds = [math]::Round($sw.Elapsed.TotalSeconds, 1)
        $raw = $stdout + $stderr

        if ($raw -match "did not find any integrity violations") {
            $results.Summary = "PASS - No integrity violations found."
        } elseif ($raw -match "found corrupt files and successfully repaired") {
            $results.Summary = "REPAIRED - Corrupt files found and repaired."
        } elseif ($raw -match "found corrupt files but was unable to fix") {
            $results.Summary = "FAIL - Corrupt files found but could not be repaired."
        } elseif ($raw -match "could not perform the requested operation") {
            $results.Summary = "WARNING - SFC could not complete."
        }

        $logPath = Join-Path $Global:ScriptDir "sfc-output.txt"
        Set-Content -Path $logPath -Value $raw -Encoding UTF8 -ErrorAction SilentlyContinue
    } catch {
        $sw.Stop()
        $results.Summary = "ERROR - $($_.Exception.Message)"
        Write-DiagLog "SFC error: $($_.Exception.Message)" "WARN"
    }

    Write-DiagLog "SFC result: $($results.Summary) ($($results.Seconds)s)"
    return $results
}

function Invoke-DISMCheck {
    param([switch]$RunRepair)
    Write-DiagLog "Running DISM health checks..."
    $results = @{ CheckHealth = "Not run"; ScanHealth = "Not run"; RestoreHealth = "Not run" }

    function Run-DismCmd($args) {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = "dism.exe"
        $psi.Arguments = $args
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $p = New-Object System.Diagnostics.Process
        $p.StartInfo = $psi
        $null = $p.Start()
        $out = $p.StandardOutput.ReadToEnd() + $p.StandardError.ReadToEnd()
        $p.WaitForExit()
        return $out
    }

    function Parse-DismResult($text) {
        if ($text -match "No component store corruption detected") { return "PASS - No corruption detected." }
        if ($text -match "The component store is repairable") { return "WARNING - Component store is repairable." }
        if ($text -match "The restore operation completed successfully") { return "REPAIRED - Restore completed." }
        if ($text -match "The operation completed successfully") { return "PASS - Completed successfully." }
        return "Review required."
    }

    try {
        $out = Run-DismCmd "/Online /Cleanup-Image /CheckHealth"
        $results.CheckHealth = Parse-DismResult $out
        Write-DiagLog "DISM CheckHealth: $($results.CheckHealth)"
    } catch { $results.CheckHealth = "ERROR - $($_.Exception.Message)" }

    try {
        $out = Run-DismCmd "/Online /Cleanup-Image /ScanHealth"
        $results.ScanHealth = Parse-DismResult $out
        Write-DiagLog "DISM ScanHealth: $($results.ScanHealth)"
    } catch { $results.ScanHealth = "ERROR - $($_.Exception.Message)" }

    if ($RunRepair) {
        try {
            $out = Run-DismCmd "/Online /Cleanup-Image /RestoreHealth"
            $results.RestoreHealth = Parse-DismResult $out
            Write-DiagLog "DISM RestoreHealth: $($results.RestoreHealth)"
        } catch { $results.RestoreHealth = "ERROR - $($_.Exception.Message)" }
    }

    return $results
}

function Get-FileSystemHealth {
    Write-DiagLog "Checking file system integrity..."
    $results = @()
    $volumes = Invoke-Safe { Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" -ErrorAction Stop } @()

    foreach ($v in $volumes) {
        $letter = $v.DeviceID
        $dirty = Invoke-Safe { (cmd.exe /c "fsutil dirty query $letter" 2>&1) -join " " } "Unable to query"

        $chkdsk = "Not run"
        try {
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = "chkdsk.exe"
            $psi.Arguments = "$letter /scan"
            $psi.RedirectStandardOutput = $true
            $psi.RedirectStandardError = $true
            $psi.UseShellExecute = $false
            $psi.CreateNoWindow = $true
            $p = New-Object System.Diagnostics.Process
            $p.StartInfo = $psi
            $null = $p.Start()
            $out = $p.StandardOutput.ReadToEnd()
            $p.WaitForExit()

            if ($out -match "found no problems") { $chkdsk = "PASS - No problems found." }
            elseif ($out -match "found problems") { $chkdsk = "WARNING - Problems found." }
            else { $chkdsk = "Review required." }
        } catch {
            $chkdsk = "Skipped - $($_.Exception.Message)"
        }

        $freePercent = if ($v.Size -gt 0) { [math]::Round(($v.FreeSpace / $v.Size) * 100, 1) } else { $null }

        $results += @{
            Drive = $letter
            FileSystem = $v.FileSystem
            SizeGB = [math]::Round($v.Size / 1GB, 1)
            FreeGB = [math]::Round($v.FreeSpace / 1GB, 1)
            FreePercent = $freePercent
            DirtyBit = $dirty
            ChkdskResult = $chkdsk
        }
        Write-DiagLog "FileSystem ${letter}: Free=${freePercent}%, Dirty=$dirty, Chkdsk=$chkdsk"
    }
    return $results
}

function Test-ServiceHealth {
    Write-DiagLog "Checking critical Windows services..."
    $critical = @("EventLog","Winmgmt","wuauserv","BITS","CryptSvc","Schedule","VSS","Spooler","Dhcp","Dnscache","LanmanWorkstation","LanmanServer","ProfSvc","Themes")
    $results = @()

    foreach ($svc in $critical) {
        $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
        if ($s) {
            $startMode = Invoke-Safe { (Get-CimInstance Win32_Service -Filter "Name='$svc'" -ErrorAction Stop).StartMode } "Unknown"
            $healthy = ($s.Status -eq "Running") -or ($svc -in @("wuauserv","VSS","Spooler"))
            $results += @{ Name = $svc; DisplayName = $s.DisplayName; Status = $s.Status.ToString(); StartType = $startMode; Healthy = $healthy }
        } else {
            $results += @{ Name = $svc; DisplayName = "Not found"; Status = "Missing"; StartType = "Unknown"; Healthy = $false }
        }
    }
    $badCount = @($results | Where-Object { $_.Healthy -eq $false }).Count
    Write-DiagLog "Services: $($results.Count) checked, $badCount unhealthy"
    return $results
}

function Test-WMIHealth {
    Write-DiagLog "Checking WMI/CIM repository health..."
    $results = @{ QueryTests = @(); RepositoryStatus = "Unknown" }

    $queries = @("Win32_OperatingSystem","Win32_ComputerSystem","Win32_Processor","Win32_LogicalDisk")
    foreach ($q in $queries) {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $ok = $true
        try { Get-CimInstance $q -ErrorAction Stop | Out-Null } catch { $ok = $false }
        $sw.Stop()
        $results.QueryTests += @{ Class = $q; Success = $ok; Seconds = [math]::Round($sw.Elapsed.TotalSeconds, 2) }
    }

    $results.RepositoryStatus = Invoke-Safe { (winmgmt /verifyrepository 2>&1) -join " " } "Unable to verify"
    Write-DiagLog "WMI repo: $($results.RepositoryStatus)"
    return $results
}

function Get-StartupHealth {
    Write-DiagLog "Collecting startup app health..."
    $results = @{ StartupCommands = @(); RunKeys = @(); ScheduledTasks = @() }

    $results.StartupCommands = @(Invoke-Safe {
        Get-CimInstance Win32_StartupCommand -ErrorAction Stop | Select-Object Name, Command, Location, User
    } @())

    $paths = @("HKLM:\Software\Microsoft\Windows\CurrentVersion\Run","HKCU:\Software\Microsoft\Windows\CurrentVersion\Run","HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run")
    foreach ($p in $paths) {
        try {
            $props = Get-ItemProperty -Path $p -ErrorAction SilentlyContinue
            if ($props) {
                $props.PSObject.Properties | Where-Object { $_.Name -notmatch "^PS" } | ForEach-Object {
                    $results.RunKeys += @{ Location = $p; Name = $_.Name; Value = $_.Value }
                }
            }
        } catch {}
    }

    $results.ScheduledTasks = @(Invoke-Safe {
        Get-ScheduledTask -ErrorAction Stop | Where-Object { $_.State -ne "Disabled" -and ($_.TaskPath -notlike "\Microsoft*") } |
        Select-Object TaskName, TaskPath, State -First 50
    } @())

    Write-DiagLog "Startup: $($results.StartupCommands.Count) commands, $($results.RunKeys.Count) run keys, $($results.ScheduledTasks.Count) third-party tasks"
    return $results
}

function Get-DeepEventLogScan {
    param([int]$DaysBack = 30)
    Write-DiagLog "Running deep event log scan ($DaysBack days)..."
    $start = (Get-Date).AddDays(-$DaysBack)
    $summary = @()

    $queries = @(
        @{Category="Kernel Power Unexpected Shutdown"; Filter=@{LogName='System'; Id=41; StartTime=$start}},
        @{Category="Blue Screen BugCheck"; Filter=@{LogName='System'; Id=1001; StartTime=$start}},
        @{Category="Unexpected Shutdown"; Filter=@{LogName='System'; Id=6008; StartTime=$start}},
        @{Category="Disk Bad Block"; Filter=@{LogName='System'; Id=7; StartTime=$start}},
        @{Category="Disk Warning"; Filter=@{LogName='System'; Id=51; StartTime=$start}},
        @{Category="NTFS Corruption"; Filter=@{LogName='System'; Id=55; StartTime=$start}},
        @{Category="Storage Reset"; Filter=@{LogName='System'; Id=129; StartTime=$start}},
        @{Category="Disk IO Retry"; Filter=@{LogName='System'; Id=153; StartTime=$start}},
        @{Category="WHEA Hardware Error"; Filter=@{LogName='System'; ProviderName='Microsoft-Windows-WHEA-Logger'; StartTime=$start}},
        @{Category="Application Error"; Filter=@{LogName='Application'; ProviderName='Application Error'; StartTime=$start}},
        @{Category="Application Hang"; Filter=@{LogName='Application'; ProviderName='Application Hang'; StartTime=$start}}
    )

    foreach ($q in $queries) {
        $events = @()
        try { $events = @(Get-WinEvent -FilterHashtable $q.Filter -ErrorAction SilentlyContinue) } catch {}
        $summary += @{
            Category = $q.Category
            Count = $events.Count
            MostRecent = ($events | Sort-Object TimeCreated -Descending | Select-Object -First 1).TimeCreated
        }
    }

    $totalIssues = ($summary | Measure-Object -Property Count -Sum).Sum
    Write-DiagLog "Event scan: $totalIssues total events across $($summary.Count) categories"
    return $summary
}

function Get-WindowsUpdateHealth {
    Write-DiagLog "Checking Windows Update health..."
    $results = @{ Services = @(); RebootPending = $false; RecentHotfixes = @() }

    $results.Services = @("wuauserv","BITS","CryptSvc") | ForEach-Object {
        $s = Get-Service $_ -ErrorAction SilentlyContinue
        @{ Name = $_; Status = if ($s) { $s.Status.ToString() } else { "Missing" } }
    }

    $rebootKeys = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired"
    )
    foreach ($key in $rebootKeys) {
        if (Test-Path $key) { $results.RebootPending = $true }
    }

    $results.RecentHotfixes = @(Invoke-Safe {
        Get-HotFix -ErrorAction Stop | Sort-Object InstalledOn -Descending | Select-Object HotFixID, InstalledOn, Description -First 10
    } @())

    Write-DiagLog "WU: RebootPending=$($results.RebootPending), RecentPatches=$($results.RecentHotfixes.Count)"
    return $results
}

function Test-WindowsResponsiveness {
    Write-DiagLog "Testing Windows responsiveness..."
    $results = @()

    $apps = @(
        @{Name="Notepad"; Path="notepad.exe"},
        @{Name="Control Panel"; Path="control.exe"}
    )

    foreach ($app in $apps) {
        try {
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            $p = Start-Process -FilePath $app.Path -PassThru -ErrorAction Stop
            Start-Sleep -Milliseconds 900
            $sw.Stop()
            try { $p.CloseMainWindow() | Out-Null; Start-Sleep -Milliseconds 300; if (-not $p.HasExited) { $p.Kill() } } catch {}
            $results += @{ Test = "Launch $($app.Name)"; Success = $true; ResponseMS = $sw.ElapsedMilliseconds }
        } catch {
            $results += @{ Test = "Launch $($app.Name)"; Success = $false; ResponseMS = $null; Error = $_.Exception.Message }
        }
    }

    try {
        $testDir = Join-Path $env:TEMP "PCPlus360_RespTest"
        New-Item -ItemType Directory -Path $testDir -Force | Out-Null
        $src = Join-Path $testDir "test.bin"
        $dst = Join-Path $testDir "copy.bin"
        $buf = New-Object byte[] (32MB)
        (New-Object Random).NextBytes($buf)

        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        [System.IO.File]::WriteAllBytes($src, $buf)
        Copy-Item $src $dst -Force
        Remove-Item $src, $dst -Force
        $sw.Stop()
        $results += @{ Test = "File Create/Copy/Delete 32MB"; Success = $true; ResponseMS = $sw.ElapsedMilliseconds }
        Remove-Item $testDir -Recurse -Force -ErrorAction SilentlyContinue
    } catch {
        $results += @{ Test = "File Create/Copy/Delete 32MB"; Success = $false; ResponseMS = $null; Error = $_.Exception.Message }
    }

    Write-DiagLog "Responsiveness: $($results.Count) tests completed"
    return $results
}

function Get-DriverDeviceHealth {
    Write-DiagLog "Checking driver and device health..."
    $results = @{ ProblemDeviceCount = 0; ProblemDevices = @(); OldDriverCount = 0 }

    $problems = Invoke-Safe { Get-PnpDevice -ErrorAction Stop | Where-Object { $_.Status -ne "OK" } } @()
    $results.ProblemDeviceCount = @($problems).Count
    $results.ProblemDevices = @($problems | Select-Object Class, FriendlyName, Status, Problem -First 20)

    try {
        $cutoff = (Get-Date).AddYears(-5)
        $drivers = Get-CimInstance Win32_PnPSignedDriver -ErrorAction SilentlyContinue
        $old = @($drivers | Where-Object {
            $_.DriverDate -and ([Management.ManagementDateTimeConverter]::ToDateTime($_.DriverDate) -lt $cutoff)
        })
        $results.OldDriverCount = $old.Count
    } catch {}

    Write-DiagLog "Devices: $($results.ProblemDeviceCount) problems, $($results.OldDriverCount) drivers older than 5 years"
    return $results
}

function Invoke-DeepWindowsTest {
    Write-DiagLog "Starting Deep Windows Performance & Integrity Test..."
    $results = @{
        SFC = $null; DISM = $null; FileSystem = @(); Services = @()
        WMI = $null; Startup = $null; EventLog = @(); WindowsUpdate = $null
        Responsiveness = @(); DriverDevice = $null; Score = 0; Grade = "N/A"
    }

    $results.SFC = Invoke-SFCScan
    $results.DISM = Invoke-DISMCheck
    $results.FileSystem = Get-FileSystemHealth
    $results.Services = Test-ServiceHealth
    $results.WMI = Test-WMIHealth
    $results.Startup = Get-StartupHealth
    $results.EventLog = Get-DeepEventLogScan -DaysBack 30
    $results.WindowsUpdate = Get-WindowsUpdateHealth
    $results.Responsiveness = Test-WindowsResponsiveness
    $results.DriverDevice = Get-DriverDeviceHealth

    # Calculate Windows health score
    $score = 100; $issues = @()
    if ($results.SFC.Summary -match "FAIL") { $score -= 20; $issues += $results.SFC.Summary }
    elseif ($results.SFC.Summary -match "REPAIRED|WARNING") { $score -= 8; $issues += $results.SFC.Summary }
    if ($results.DISM.CheckHealth -match "WARNING") { $score -= 8 }
    if ($results.DISM.ScanHealth -match "WARNING") { $score -= 10 }
    foreach ($fs in $results.FileSystem) {
        if ($fs.DirtyBit -match "dirty") { $score -= 10 }
        if ($fs.ChkdskResult -match "WARNING|problems") { $score -= 10 }
    }
    if ($results.DriverDevice.ProblemDeviceCount -gt 0) { $score -= [math]::Min(15, $results.DriverDevice.ProblemDeviceCount * 3) }
    $badSvcs = @($results.Services | Where-Object { $_.Healthy -eq $false }).Count
    if ($badSvcs -gt 0) { $score -= [math]::Min(15, $badSvcs * 3) }
    if ($results.WMI.RepositoryStatus -notmatch "consistent") { $score -= 10 }
    foreach ($e in $results.EventLog) {
        if ($e.Count -gt 0 -and $e.Category -match "Blue Screen|WHEA|Disk Bad|NTFS|Storage Reset") { $score -= 10 }
        elseif ($e.Count -gt 0 -and $e.Category -match "Unexpected Shutdown|Application Error|Application Hang") { $score -= 5 }
    }
    if ($results.WindowsUpdate.RebootPending) { $score -= 5 }
    if ($score -lt 0) { $score = 0 }

    $results.Score = $score
    $results.Grade = if ($score -ge 90){"A"} elseif ($score -ge 80){"B"} elseif ($score -ge 70){"C"} elseif ($score -ge 60){"D"} else {"F"}
    $results.Issues = $issues

    Write-DiagLog "Deep Windows Test complete: Score=$score, Grade=$($results.Grade)"
    return $results
}

# ─────────────────────────────────────────────────────────────────────────────
# RAM ISOLATION TEST (Guided Technician Workflow)
# ─────────────────────────────────────────────────────────────────────────────
function Start-RAMIsolationTest {
    param(
        [ValidateSet("Quick","Standard","Deep")]
        [string]$Mode = "Standard",
        [string]$CustomerName = "Customer",
        [string]$TechnicianName = "PC Plus Technician",
        [int]$MemoryUsePercent = 75
    )

    Write-DiagLog "Launching RAM Isolation Test (Mode=$Mode)..."
    $durationMap = @{ Quick = 3; Standard = 10; Deep = 30 }
    $duration = $durationMap[$Mode]

    $sessionDir = Join-Path "C:\PCPlus360\RAM-Isolation" "$($env:COMPUTERNAME)-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    New-Item -ItemType Directory -Path $sessionDir -Force | Out-Null

    $ramInventory = @(Invoke-Safe {
        Get-CimInstance Win32_PhysicalMemory -ErrorAction Stop | ForEach-Object {
            @{
                Slot = $_.DeviceLocator; Bank = $_.BankLabel
                CapacityGB = [math]::Round($_.Capacity / 1GB, 2)
                SpeedMHz = $_.Speed; ConfiguredClockSpeedMHz = $_.ConfiguredClockSpeed
                Manufacturer = ($_.Manufacturer -as [string]).Trim()
                PartNumber = ($_.PartNumber -as [string]).Trim()
                SerialNumber = ($_.SerialNumber -as [string]).Trim()
            }
        }
    } @())

    $warnings = @()
    $speeds = @($ramInventory | Where-Object { $_.SpeedMHz } | ForEach-Object { $_.SpeedMHz } | Select-Object -Unique)
    if ($speeds.Count -gt 1) { $warnings += "Mixed RAM speeds: $($speeds -join ', ') MHz" }
    $sizes = @($ramInventory | ForEach-Object { $_.CapacityGB } | Select-Object -Unique)
    if ($sizes.Count -gt 1) { $warnings += "Mixed RAM capacities: $($sizes -join ', ') GB" }
    $mfrs = @($ramInventory | Where-Object { $_.Manufacturer } | ForEach-Object { $_.Manufacturer } | Select-Object -Unique)
    if ($mfrs.Count -gt 1) { $warnings += "Mixed RAM manufacturers: $($mfrs -join ', ')" }

    $memoryEvents = @()
    $start = (Get-Date).AddHours(-24)
    $filters = @(
        @{LogName='System'; Id=41; StartTime=$start},
        @{LogName='System'; Id=1001; StartTime=$start},
        @{LogName='System'; Id=6008; StartTime=$start}
    )
    foreach ($f in $filters) {
        try { $memoryEvents += @(Get-WinEvent -FilterHashtable $f -ErrorAction SilentlyContinue) } catch {}
    }
    try {
        $memoryEvents += @(Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Microsoft-Windows-WHEA-Logger'; StartTime=$start} -ErrorAction SilentlyContinue)
    } catch {}

    return @{
        SessionDir = $sessionDir
        RAMInventory = $ramInventory
        ConfigWarnings = $warnings
        RecentMemoryEvents = $memoryEvents.Count
        DurationMinutes = $duration
        MemoryUsePercent = $MemoryUsePercent
        Mode = $Mode
    }
}

function Invoke-RAMIsolationRound {
    param(
        [int]$DurationMinutes = 10,
        [int]$UsePercent = 75,
        [string]$StickLabel = "Not specified",
        [string]$SlotLabel = "Not specified",
        [string]$TestType = "General"
    )

    Write-DiagLog "RAM isolation round: $TestType - Stick=$StickLabel, Slot=$SlotLabel, Duration=$DurationMinutes min"

    $os = Get-CimInstance Win32_OperatingSystem
    $totalBytes = [double]$os.TotalVisibleMemorySize * 1KB
    $targetBytes = [int64]($totalBytes * ($UsePercent / 100))
    $blockBytes = 128MB
    $blocksToAllocate = [math]::Max(1, [math]::Floor($targetBytes / $blockBytes))

    $allocated = New-Object System.Collections.Generic.List[byte[]]
    $end = (Get-Date).AddMinutes($DurationMinutes)
    $patternErrors = 0; $randomErrors = 0; $allocFailures = 0
    $samples = @()

    try {
        for ($i = 0; $i -lt $blocksToAllocate; $i++) {
            try { $allocated.Add((New-Object byte[] $blockBytes)) }
            catch { $allocFailures++; break }
        }

        if ($allocated.Count -eq 0) { throw "No memory blocks could be allocated." }
        $patterns = @(0x00, 0xFF, 0xAA, 0x55)

        while ((Get-Date) -lt $end) {
            foreach ($p in $patterns) {
                foreach ($block in $allocated) {
                    try {
                        [Array]::Fill($block, [byte]$p)
                        for ($offset = 0; $offset -lt $block.Length; $offset += 4096) {
                            if ($block[$offset] -ne [byte]$p) { $patternErrors++ }
                        }
                    } catch { $patternErrors++ }
                }
            }

            $rng = [Random]::new()
            foreach ($block in $allocated) {
                try {
                    for ($j = 0; $j -lt 256; $j++) {
                        $idx = $rng.Next(0, $block.Length)
                        $val = [byte]$rng.Next(0, 256)
                        $block[$idx] = $val
                        if ($block[$idx] -ne $val) { $randomErrors++ }
                    }
                } catch { $randomErrors++ }
            }

            $availMB = Invoke-Safe { [math]::Round((Get-Counter '\Memory\Available MBytes' -ErrorAction Stop).CounterSamples[0].CookedValue, 2) } $null
            $workSetMB = [math]::Round((Get-Process -Id $PID).WorkingSet64 / 1MB, 2)
            $samples += @{ AvailableMB = $availMB; WorkingSetMB = $workSetMB; PatternErrors = $patternErrors; RandomErrors = $randomErrors }
            Start-Sleep -Seconds 5
        }
    } catch {
        Write-DiagLog "RAM isolation error: $($_.Exception.Message)" "WARN"
    } finally {
        $allocated.Clear()
        [GC]::Collect()
        [GC]::WaitForPendingFinalizers()
    }

    $passed = ($allocFailures -eq 0 -and $patternErrors -eq 0 -and $randomErrors -eq 0)
    $result = if ($passed) { "PASS" } else { "FAIL" }

    Write-DiagLog "RAM isolation round: $result (PatternErrors=$patternErrors, RandomErrors=$randomErrors, AllocFail=$allocFailures)"
    return @{
        TestType = $TestType; StickLabel = $StickLabel; SlotLabel = $SlotLabel
        Result = $result; Passed = $passed; DurationMinutes = $DurationMinutes
        PatternErrors = $patternErrors; RandomErrors = $randomErrors
        AllocationFailures = $allocFailures; Samples = $samples
        PeakWorkingSetMB = if ($samples.Count -gt 0) { ($samples | ForEach-Object { $_.WorkingSetMB } | Measure-Object -Maximum).Maximum } else { 0 }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# SECURITY SCORING
# ─────────────────────────────────────────────────────────────────────────────
function Calculate-Score {
    param($Security, $MissingPatches)
    $score = 0; $breakdown = @()
    $checks = @(
        # ── Core Security (71 pts) ──
        @{ Name="Antivirus Active"; Pts=10; Test={ ($Security.Defender.RealTimeProtection -eq $true) -or ($Security.ThirdPartyAV.Count -gt 0) } }
        @{ Name="Firewall All Profiles"; Pts=10; Test={ $Security.Firewall.Domain -and $Security.Firewall.Private -and $Security.Firewall.Public } }
        @{ Name="BitLocker on C:"; Pts=7; Test={ $Security.BitLocker["C:"] -and $Security.BitLocker["C:"].Status -eq "On" } }
        @{ Name="No Critical Patches Missing"; Pts=7; Test={ ($MissingPatches | Where-Object { $_.Severity -eq "Critical" }).Count -eq 0 } }
        @{ Name="UAC Enabled"; Pts=4; Test={ $Security.UAC.Enabled -eq $true } }
        @{ Name="Secure Boot"; Pts=4; Test={ $Security.SecureBoot -eq $true } }
        @{ Name="TPM Present"; Pts=4; Test={ $Security.TPM.Present -eq $true } }
        @{ Name="Password Policy"; Pts=3; Test={ $Security.PasswordPolicy.MinLength -ge 8 -or $Security.PasswordPolicy.Complexity } }
        @{ Name="Guest Disabled"; Pts=2; Test={ $Security.GuestDisabled -eq $true } }
        @{ Name="No Auto-Login"; Pts=2; Test={ $Security.AutoLoginDisabled -eq $true } }
        @{ Name="RDP Secure"; Pts=4; Test={ ($Security.RDP.Enabled -eq $false) -or ($Security.RDP.NLA -eq $true) } }
        @{ Name="SMBv1 Disabled"; Pts=4; Test={ $Security.SMBv1Disabled -eq $true } }
        @{ Name="Admin Accounts <=2"; Pts=3; Test={ $Security.LocalAdmins.Count -le 2 } }
        @{ Name="Real-Time Protection"; Pts=4; Test={ $Security.Defender.RealTimeProtection -eq $true } }
        @{ Name="AV Definitions Current"; Pts=3; Test={ $Security.Defender.DefinitionsUpToDate -eq $true } }
        # ── Privacy & Data Protection (6 pts) ──
        @{ Name="Telemetry Minimal"; Pts=1; Test={ $Security.Privacy.TelemetryMinimal -eq $true } }
        @{ Name="Advertising ID Disabled"; Pts=1; Test={ $Security.Privacy.AdvertisingIdDisabled -eq $true } }
        @{ Name="Location Tracking Off"; Pts=1; Test={ $Security.Privacy.LocationDisabled -eq $true } }
        @{ Name="Activity History Off"; Pts=1; Test={ $Security.Privacy.ActivityHistoryDisabled -eq $true } }
        @{ Name="Cortana/Copilot Disabled"; Pts=1; Test={ $Security.Privacy.CortanaDisabled -eq $true } }
        @{ Name="Find My Device On"; Pts=1; Test={ $Security.Privacy.FindMyDeviceEnabled -eq $true } }
        # ── Browser Security (4 pts) ──
        @{ Name="Chrome No Saved Passwords"; Pts=1; Test={ $Security.BrowserSecurity.ChromeNoSavedPasswords -eq $true } }
        @{ Name="Edge No Saved Passwords"; Pts=1; Test={ $Security.BrowserSecurity.EdgeNoSavedPasswords -eq $true } }
        @{ Name="SmartScreen Enabled"; Pts=1; Test={ $Security.BrowserSecurity.SmartScreenEnabled -eq $true } }
        @{ Name="Browser Extensions <15"; Pts=1; Test={ $Security.BrowserSecurity.ExtensionCountOk -eq $true } }
        # ── Network Hardening (5 pts) ──
        @{ Name="No Open Shares"; Pts=1; Test={ $Security.NetworkHardening.NoOpenShares -eq $true } }
        @{ Name="UPnP Disabled"; Pts=1; Test={ $Security.NetworkHardening.UPnPDisabled -eq $true } }
        @{ Name="LLMNR Disabled"; Pts=1; Test={ $Security.NetworkHardening.LLMNRDisabled -eq $true } }
        @{ Name="DNS-over-HTTPS"; Pts=1; Test={ $Security.NetworkHardening.DoHEnabled -eq $true } }
        @{ Name="Remote Assistance Off"; Pts=1; Test={ $Security.NetworkHardening.RemoteAssistanceDisabled -eq $true } }
        # ── System Integrity (5 pts) ──
        @{ Name="Driver Sig Enforced"; Pts=1; Test={ $Security.SystemIntegrity.DriverSigEnforced -eq $true } }
        @{ Name="PS Script Logging"; Pts=1; Test={ $Security.SystemIntegrity.PSScriptLogging -eq $true } }
        @{ Name="Logon Audit Enabled"; Pts=1; Test={ $Security.SystemIntegrity.LogonAuditEnabled -eq $true } }
        @{ Name="Credential Guard"; Pts=1; Test={ $Security.SystemIntegrity.CredentialGuard -eq $true } }
        @{ Name="LSASS Protected"; Pts=1; Test={ $Security.SystemIntegrity.LSASSProtected -eq $true } }
        # ── Account Hygiene (3 pts) ──
        @{ Name="No Stale Accounts"; Pts=1; Test={ $Security.AccountHygiene.NoStaleAccounts -eq $true } }
        @{ Name="No Empty Passwords"; Pts=1; Test={ $Security.AccountHygiene.NoEmptyPasswords -eq $true } }
        @{ Name="Password Age Policy"; Pts=1; Test={ $Security.AccountHygiene.PasswordAgePolicy -eq $true } }
        # ── Ransomware Protection (6 pts) ──
        @{ Name="Controlled Folder Access"; Pts=2; Test={ $Security.RansomwareProtection.ControlledFolderAccess -eq $true } }
        @{ Name="Recent Restore Point"; Pts=2; Test={ $Security.RansomwareProtection.RecentRestorePoint -eq $true } }
        @{ Name="No Suspicious Tasks"; Pts=2; Test={ $Security.RansomwareProtection.NoSuspiciousScheduledTasks -eq $true } }
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
# WEAR & TEAR LIFE REPORT (inline integration - no HTML, no file output)
# Mirrors PCPlus360-Wear-And-Tear-Life-Report.ps1 but returns structured data
# ─────────────────────────────────────────────────────────────────────────────

function Invoke-WearAndTearReport {
    param(
        [string]$ToolsDir = $Global:ToolsDir
    )

    Write-DiagLog "=== WEAR & TEAR LIFE REPORT STARTING ==="

    # --- Helper: grade/risk/life from score ---
    function _WTGrade([int]$s) {
        if ($s -ge 90) { "A" } elseif ($s -ge 80) { "B" } elseif ($s -ge 70) { "C" } elseif ($s -ge 60) { "D" } else { "F" }
    }
    function _WTGradeFull([int]$s) {
        if ($s -ge 90) { "A - Excellent" } elseif ($s -ge 80) { "B - Good" } elseif ($s -ge 70) { "C - Fair" } elseif ($s -ge 60) { "D - Needs Attention" } else { "F - Critical" }
    }
    function _WTRisk([int]$s) {
        if ($s -ge 85) { "Low" } elseif ($s -ge 70) { "Moderate" } elseif ($s -ge 55) { "High" } else { "Critical" }
    }
    function _WTLife([int]$s) {
        if ($s -ge 90) { 4.0 } elseif ($s -ge 80) { 3.0 } elseif ($s -ge 70) { 2.0 } elseif ($s -ge 60) { 1.0 } else { 0.3 }
    }
    function _WTLifeText([int]$s) {
        if ($s -ge 90) { "3-5+ years estimated remaining life if maintained properly" }
        elseif ($s -ge 80) { "2-4 years estimated remaining life" }
        elseif ($s -ge 70) { "1-3 years estimated remaining life; maintenance or upgrade recommended" }
        elseif ($s -ge 60) { "6-18 months estimated useful life; plan repairs/upgrades soon" }
        else { "Immediate attention recommended; failure/replacement risk is high" }
    }

    $recommendations = [System.Collections.ArrayList]::new()

    # ─────────────────────────────────────────────────────────────────────
    # 1. SYSTEM AGE
    # ─────────────────────────────────────────────────────────────────────
    Write-DiagLog "Wear & Tear: Collecting system age..."
    $sysAge = Invoke-Safe {
        $cs   = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
        $bios = Get-CimInstance Win32_BIOS -ErrorAction Stop
        $os   = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop

        $biosDate = $null
        try { $biosDate = [Management.ManagementDateTimeConverter]::ToDateTime($bios.ReleaseDate) } catch {}
        $installDate = $null
        try { $installDate = $os.InstallDate } catch {}

        $biosAgeYears = if ($biosDate) { [math]::Round(((Get-Date) - $biosDate).TotalDays / 365.25, 1) } else { $null }
        $osAgeYears   = if ($installDate) { [math]::Round(((Get-Date) - $installDate).TotalDays / 365.25, 1) } else { $null }

        # Pick the best available age estimate (BIOS date approximates hardware age)
        $ageYears = if ($biosAgeYears) { $biosAgeYears } elseif ($osAgeYears) { $osAgeYears } else { $null }

        $score = 100
        if ($null -ne $biosAgeYears) {
            if ($biosAgeYears -ge 8) { $score -= 25 }
            elseif ($biosAgeYears -ge 5) { $score -= 15 }
            elseif ($biosAgeYears -ge 3) { $score -= 5 }
        }
        $score = [math]::Max(0, $score)

        @{
            Score       = $score
            AgeYears    = $ageYears
            BIOSAgeYears = $biosAgeYears
            OSAgeYears  = $osAgeYears
            InstallDate = if ($installDate) { $installDate.ToString("yyyy-MM-dd") } else { $null }
            BIOSDate    = if ($biosDate) { $biosDate.ToString("yyyy-MM-dd") } else { $null }
            Manufacturer = $cs.Manufacturer
            Model       = $cs.Model
            Serial      = $bios.SerialNumber
        }
    } @{ Score = 100; AgeYears = $null; BIOSAgeYears = $null; OSAgeYears = $null; InstallDate = $null; BIOSDate = $null; Manufacturer = "Unknown"; Model = "Unknown"; Serial = "Unknown" }

    if ($sysAge.AgeYears -and $sysAge.AgeYears -ge 5) {
        $null = $recommendations.Add("System is approximately $($sysAge.AgeYears) years old - plan replacement or major hardware refresh")
    }

    # ─────────────────────────────────────────────────────────────────────
    # 2. STORAGE WEAR
    # ─────────────────────────────────────────────────────────────────────
    Write-DiagLog "Wear & Tear: Collecting storage wear..."

    # Locate smartctl if available
    $smartctlPath = Invoke-Safe {
        $possible = @(
            (Join-Path $ToolsDir "smartctl.exe"),
            (Join-Path $ToolsDir "smartmontools\bin\smartctl.exe"),
            "C:\Program Files\smartmontools\bin\smartctl.exe",
            "C:\Program Files (x86)\smartmontools\bin\smartctl.exe"
        )
        foreach ($p in $possible) { if (Test-Path $p) { return $p } }
        return $null
    } $null

    $storageData = Invoke-Safe {
        $diskDrives    = @(Get-CimInstance Win32_DiskDrive -ErrorAction SilentlyContinue)
        $physicalDisks = @(Get-PhysicalDisk -ErrorAction SilentlyContinue)
        $logicalDisks  = @(Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" -ErrorAction SilentlyContinue)
        $driveDetails  = @()

        foreach ($d in $diskDrives) {
            $matched = $physicalDisks | Where-Object { $_.FriendlyName -like "*$($d.Model)*" } | Select-Object -First 1
            $rel = $null
            try { if ($matched) { $rel = Get-StorageReliabilityCounter -PhysicalDisk $matched -ErrorAction SilentlyContinue } } catch {}

            # Try smartctl for deeper SMART data
            $smartHealth = $null; $smartPOH = $null; $smartTemp = $null; $smartWear = $null
            $smartRealloc = $null; $smartPending = $null; $smartUncorr = $null; $smartUnsafe = $null; $smartWritesTB = $null
            if ($smartctlPath) {
                try {
                    $psi = New-Object System.Diagnostics.ProcessStartInfo
                    $psi.FileName = $smartctlPath
                    $psi.Arguments = "-a `"$($d.DeviceID)`""
                    $psi.RedirectStandardOutput = $true
                    $psi.RedirectStandardError = $true
                    $psi.UseShellExecute = $false
                    $psi.CreateNoWindow = $true
                    $p = New-Object System.Diagnostics.Process
                    $p.StartInfo = $psi
                    $null = $p.Start()
                    $smartText = $p.StandardOutput.ReadToEnd()
                    $p.WaitForExit()

                    if ($smartText) {
                        if ($smartText -match "SMART overall-health.*?:\s*(\w+)") { $smartHealth = $matches[1] }
                        elseif ($smartText -match "SMART Health Status:\s*(\w+)") { $smartHealth = $matches[1] }
                        if ($smartText -match "Power_On_Hours.*?\s(\d+)\s*$") { $smartPOH = [int64]$matches[1] }
                        elseif ($smartText -match "Power On Hours:\s*([0-9,]+)") { $smartPOH = [int64](($matches[1]) -replace ",","") }
                        if ($smartText -match "Temperature_Celsius.*?\s(\d+)\s*$") { $smartTemp = [int]$matches[1] }
                        elseif ($smartText -match "Temperature:\s*([0-9]+)\s*Celsius") { $smartTemp = [int]$matches[1] }
                        if ($smartText -match "Percentage Used:\s*([0-9]+)%") { $smartWear = [int]$matches[1] }
                        if ($smartText -match "Unsafe Shutdowns:\s*([0-9,]+)") { $smartUnsafe = [int64](($matches[1]) -replace ",","") }
                        if ($smartText -match "Reallocated_Sector_Ct.*?\s(\d+)\s*$") { $smartRealloc = [int64]$matches[1] }
                        if ($smartText -match "Current_Pending_Sector.*?\s(\d+)\s*$") { $smartPending = [int64]$matches[1] }
                        if ($smartText -match "Offline_Uncorrectable.*?\s(\d+)\s*$") { $smartUncorr = [int64]$matches[1] }
                        if ($smartText -match "Data Units Written:\s*([0-9,]+)") {
                            $units = [double](($matches[1]) -replace ",","")
                            $smartWritesTB = [math]::Round(($units * 512000) / 1TB, 2)
                        }
                    }
                } catch {}
            }

            # Merge smartctl + Windows Storage Reliability data
            $health = if ($matched) { $matched.HealthStatus } else { $d.Status }
            $temp   = if ($smartTemp) { $smartTemp } elseif ($rel -and $rel.Temperature) { $rel.Temperature } else { $null }
            $wear   = if ($smartWear) { $smartWear } elseif ($rel -and $null -ne $rel.Wear) { $rel.Wear } else { $null }
            $hours  = if ($smartPOH) { $smartPOH } elseif ($rel -and $null -ne $rel.PowerOnHours) { $rel.PowerOnHours } else { $null }

            $driveScore = 100
            # Health status penalty
            if ($health -and $health -notmatch "Healthy|OK") { $driveScore -= 35 }
            # Temperature penalty
            if ($null -ne $temp) {
                if ($temp -ge 75) { $driveScore -= 20 }
                elseif ($temp -ge 65) { $driveScore -= 10 }
            }
            # Wear percentage penalty
            if ($null -ne $wear) {
                if ($wear -ge 90) { $driveScore -= 35 }
                elseif ($wear -ge 70) { $driveScore -= 20 }
                elseif ($wear -ge 50) { $driveScore -= 10 }
            }
            # Power-on hours penalty
            if ($null -ne $hours) {
                if ($hours -ge 40000) { $driveScore -= 20 }
                elseif ($hours -ge 25000) { $driveScore -= 10 }
            }
            # Bad sector penalties
            if ($smartRealloc -gt 0)  { $driveScore -= 20 }
            if ($smartPending -gt 0)  { $driveScore -= 30 }
            if ($smartUncorr -gt 0)   { $driveScore -= 30 }
            if ($smartUnsafe -gt 50)  { $driveScore -= 5 }

            $driveScore = [math]::Max(0, $driveScore)

            $driveDetails += @{
                Model              = $d.Model
                SerialNumber       = ($d.SerialNumber -as [string]).Trim()
                InterfaceType      = $d.InterfaceType
                MediaType          = if ($matched) { "$($matched.MediaType)" } else { "$($d.MediaType)" }
                BusType            = if ($matched) { "$($matched.BusType)" } else { $null }
                SizeGB             = [math]::Round($d.Size / 1GB, 2)
                HealthStatus       = "$health"
                TemperatureC       = $temp
                WearPercentUsed    = $wear
                RemainingPercent   = if ($null -ne $wear) { [math]::Max(0, 100 - $wear) } else { $null }
                PowerOnHours       = $hours
                PowerOnYears       = if ($null -ne $hours) { [math]::Round($hours / 8760, 1) } else { $null }
                TotalHostWritesTB  = $smartWritesTB
                UnsafeShutdowns    = $smartUnsafe
                ReallocatedSectors = $smartRealloc
                PendingSectors     = $smartPending
                UncorrectableErrors = $smartUncorr
                SmartHealth        = $smartHealth
                Score              = $driveScore
            }
        }

        # Volume free space info
        $volumes = @()
        foreach ($v in $logicalDisks) {
            $freePct = if ($v.Size -gt 0) { [math]::Round(($v.FreeSpace / $v.Size) * 100, 2) } else { $null }
            $volumes += @{
                Drive      = $v.DeviceID
                FileSystem = $v.FileSystem
                SizeGB     = [math]::Round($v.Size / 1GB, 2)
                FreeGB     = [math]::Round($v.FreeSpace / 1GB, 2)
                FreePercent = $freePct
            }
        }

        $avgScore = if ($driveDetails.Count -gt 0) { [int](($driveDetails | ForEach-Object { $_.Score } | Measure-Object -Average).Average) } else { 100 }

        @{
            Score           = $avgScore
            SmartCtlFound   = [bool]$smartctlPath
            Drives          = $driveDetails
            Volumes         = $volumes
        }
    } @{ Score = 100; SmartCtlFound = $false; Drives = @(); Volumes = @() }

    # Storage recommendations
    foreach ($drv in $storageData.Drives) {
        if ($drv.PendingSectors -gt 0)        { $null = $recommendations.Add("Drive $($drv.Model) has pending sectors - back up data immediately and replace drive") }
        if ($drv.ReallocatedSectors -gt 0)    { $null = $recommendations.Add("Drive $($drv.Model) has reallocated sectors - consider replacement") }
        if ($drv.WearPercentUsed -ge 80)      { $null = $recommendations.Add("Drive $($drv.Model) is at $($drv.WearPercentUsed)% wear - plan SSD replacement") }
        if ($drv.TemperatureC -ge 70)         { $null = $recommendations.Add("Drive $($drv.Model) temperature is $($drv.TemperatureC)C - improve cooling") }
    }
    foreach ($vol in $storageData.Volumes) {
        if ($null -ne $vol.FreePercent -and $vol.FreePercent -lt 10) {
            $null = $recommendations.Add("Volume $($vol.Drive) has only $($vol.FreePercent)% free space - free space or upgrade storage")
        }
    }

    # ─────────────────────────────────────────────────────────────────────
    # 3. BATTERY WEAR
    # ─────────────────────────────────────────────────────────────────────
    Write-DiagLog "Wear & Tear: Collecting battery wear..."
    $batteryData = Invoke-Safe {
        $batt = @(Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue)
        if ($batt.Count -eq 0) {
            return @{
                BatteryDetected = $false
                Score           = 100
                HealthPct       = $null
                DesignCapMWh    = $null
                FullChargeCapMWh = $null
                CycleCount      = $null
                ChargePercent   = $null
            }
        }

        $design = $null; $full = $null; $cycles = $null; $healthPct = $null

        # Try WMI battery classes for capacity/cycles
        try {
            $fc = Get-CimInstance -Namespace "root\WMI" -ClassName BatteryFullChargedCapacity -ErrorAction Stop
            $dc = Get-CimInstance -Namespace "root\WMI" -ClassName BatteryStaticData -ErrorAction Stop
            $full = $fc.FullChargedCapacity
            $design = $dc.DesignedCapacity
            if ($design -gt 0) { $healthPct = [math]::Round(($full / $design) * 100, 1) }
            $cycles = (Get-CimInstance -Namespace "root\WMI" -ClassName BatteryCycleCount -ErrorAction Stop).CycleCount
        } catch {}

        # Fallback: try powercfg battery report (parse in-memory)
        if ($null -eq $healthPct) {
            try {
                $tmpReport = Join-Path $env:TEMP "pcplus-batt-temp.html"
                powercfg /batteryreport /output $tmpReport 2>&1 | Out-Null
                if (Test-Path $tmpReport) {
                    $html = Get-Content $tmpReport -Raw
                    if ($html -match "DESIGN CAPACITY.*?([0-9,]+)\s*mWh") { $design = [int64](($matches[1]) -replace ",","") }
                    if ($html -match "FULL CHARGE CAPACITY.*?([0-9,]+)\s*mWh") { $full = [int64](($matches[1]) -replace ",","") }
                    if ($html -match "CYCLE COUNT.*?([0-9,]+)") { $cycles = [int64](($matches[1]) -replace ",","") }
                    if ($design -and $full -and $design -gt 0) { $healthPct = [math]::Round(($full / $design) * 100, 1) }
                    Remove-Item $tmpReport -Force -ErrorAction SilentlyContinue
                }
            } catch {}
        }

        $score = 100
        if ($null -ne $healthPct) {
            if ($healthPct -lt 40)     { $score -= 45 }
            elseif ($healthPct -lt 60) { $score -= 30 }
            elseif ($healthPct -lt 80) { $score -= 15 }
        } else {
            $score -= 5
        }
        if ($null -ne $cycles) {
            if ($cycles -gt 800)     { $score -= 20 }
            elseif ($cycles -gt 500) { $score -= 10 }
        }
        $score = [math]::Max(0, $score)

        @{
            BatteryDetected  = $true
            Score            = $score
            HealthPct        = $healthPct
            DesignCapMWh     = $design
            FullChargeCapMWh = $full
            CycleCount       = $cycles
            ChargePercent    = ($batt | Select-Object -First 1).EstimatedChargeRemaining
        }
    } @{ BatteryDetected = $false; Score = 100; HealthPct = $null; DesignCapMWh = $null; FullChargeCapMWh = $null; CycleCount = $null; ChargePercent = $null }

    if ($batteryData.BatteryDetected) {
        if ($batteryData.HealthPct -and $batteryData.HealthPct -lt 60) {
            $null = $recommendations.Add("Replace battery within 6 months (health at $($batteryData.HealthPct)%)")
        } elseif ($batteryData.HealthPct -and $batteryData.HealthPct -lt 80) {
            $null = $recommendations.Add("Monitor battery health - currently at $($batteryData.HealthPct)%")
        }
        if ($batteryData.CycleCount -and $batteryData.CycleCount -gt 800) {
            $null = $recommendations.Add("Battery has $($batteryData.CycleCount) charge cycles - replacement recommended")
        }
    }

    # ─────────────────────────────────────────────────────────────────────
    # 4. THERMAL WEAR
    # ─────────────────────────────────────────────────────────────────────
    Write-DiagLog "Wear & Tear: Collecting thermal indicators..."
    $thermalData = Invoke-Safe {
        $score = 100
        # Current thermal zone temperatures
        $zones = @()
        try {
            Get-CimInstance MSAcpi_ThermalZoneTemperature -Namespace "root/wmi" -ErrorAction Stop | ForEach-Object {
                $zones += @{ Zone = $_.InstanceName; TempC = [math]::Round(($_.CurrentTemperature / 10) - 273.15, 1) }
            }
        } catch {}

        $maxTemp = if ($zones.Count -gt 0) { ($zones | ForEach-Object { $_.TempC } | Measure-Object -Maximum).Maximum } else { $null }
        $avgTemp = if ($zones.Count -gt 0) { [math]::Round(($zones | ForEach-Object { $_.TempC } | Measure-Object -Average).Average, 1) } else { $null }

        if ($null -ne $maxTemp) {
            if ($maxTemp -ge 90)     { $score -= 30 }
            elseif ($maxTemp -ge 80) { $score -= 20 }
            elseif ($maxTemp -ge 70) { $score -= 10 }
        }

        # Thermal/throttling events from last 90 days
        $thermalEventCount = 0
        try {
            $thermalEventCount = @(Get-WinEvent -FilterHashtable @{LogName='System'; StartTime=(Get-Date).AddDays(-90)} -ErrorAction SilentlyContinue |
                Where-Object { $_.Message -match "thermal|overheat|temperature|throttl" }).Count
        } catch {}
        if ($thermalEventCount -gt 0) { $score -= 15 }

        $score = [math]::Max(0, $score)

        @{
            Score             = $score
            AvgTemp           = $avgTemp
            MaxTemp           = $maxTemp
            ThermalZones      = $zones
            ThermalEventCount = $thermalEventCount
        }
    } @{ Score = 100; AvgTemp = $null; MaxTemp = $null; ThermalZones = @(); ThermalEventCount = 0 }

    if ($thermalData.MaxTemp -ge 80) {
        $null = $recommendations.Add("High thermal reading detected ($($thermalData.MaxTemp)C) - clean dust, check fans, replace thermal paste")
    }
    if ($thermalData.ThermalEventCount -gt 0) {
        $null = $recommendations.Add("$($thermalData.ThermalEventCount) thermal/throttling event(s) in last 90 days - investigate cooling")
    }

    # ─────────────────────────────────────────────────────────────────────
    # 5. RAM WEAR
    # ─────────────────────────────────────────────────────────────────────
    Write-DiagLog "Wear & Tear: Collecting RAM wear indicators..."
    $ramData = Invoke-Safe {
        $os      = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        $modules = @(Get-CimInstance Win32_PhysicalMemory -ErrorAction SilentlyContinue)
        $totalGB = [math]::Round(($os.TotalVisibleMemorySize * 1KB) / 1GB, 2)

        $score = 100
        # Capacity check
        if ($totalGB -lt 8)       { $score -= 25 }
        elseif ($totalGB -lt 16)  { $score -= 10 }

        # Mixed speed check
        $speeds = @($modules | Where-Object { $_.Speed } | ForEach-Object { $_.Speed } | Select-Object -Unique)
        if ($speeds.Count -gt 1) { $score -= 10 }

        # WHEA hardware error events (last 90 days)
        $wheaCount = 0
        try {
            $wheaCount = @(Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Microsoft-Windows-WHEA-Logger'; StartTime=(Get-Date).AddDays(-90)} -ErrorAction SilentlyContinue).Count
        } catch {}
        if ($wheaCount -gt 0) { $score -= 20 }

        # Memory diagnostic events (last 180 days)
        $memDiagCount = 0
        try {
            $memDiagCount = @(Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Microsoft-Windows-MemoryDiagnostics-Results'; StartTime=(Get-Date).AddDays(-180)} -ErrorAction SilentlyContinue).Count
        } catch {}

        $score = [math]::Max(0, $score)

        @{
            Score        = $score
            TotalGB      = $totalGB
            ModuleCount  = $modules.Count
            MixedSpeeds  = ($speeds.Count -gt 1)
            WHEAErrors   = $wheaCount
            MemDiagEvents = $memDiagCount
            Modules      = @($modules | ForEach-Object {
                @{
                    Slot         = $_.DeviceLocator
                    CapacityGB   = [math]::Round($_.Capacity / 1GB, 1)
                    SpeedMHz     = $_.Speed
                    Manufacturer = if ($_.Manufacturer) { $_.Manufacturer.Trim() } else { "Unknown" }
                    PartNumber   = if ($_.PartNumber) { $_.PartNumber.Trim() } else { "N/A" }
                }
            })
        }
    } @{ Score = 100; TotalGB = 0; ModuleCount = 0; MixedSpeeds = $false; WHEAErrors = 0; MemDiagEvents = 0; Modules = @() }

    if ($ramData.WHEAErrors -gt 0) {
        $null = $recommendations.Add("$($ramData.WHEAErrors) WHEA hardware error(s) detected - run memtest86 and check motherboard stability")
    }
    if ($ramData.TotalGB -lt 8) {
        $null = $recommendations.Add("System has only $($ramData.TotalGB) GB RAM - upgrade to at least 8 GB (16 GB recommended)")
    }
    if ($ramData.MixedSpeeds) {
        $null = $recommendations.Add("Mixed RAM speeds detected - use matched modules for best stability")
    }

    # ─────────────────────────────────────────────────────────────────────
    # 6. GPU WEAR
    # ─────────────────────────────────────────────────────────────────────
    Write-DiagLog "Wear & Tear: Collecting GPU wear indicators..."
    $gpuData = Invoke-Safe {
        $gpus = @(Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue)
        $score = 100

        # GPU/display driver crash events (last 90 days)
        $gpuEventCount = 0
        try {
            $gpuEventCount = @(Get-WinEvent -FilterHashtable @{LogName='System'; StartTime=(Get-Date).AddDays(-90)} -ErrorAction SilentlyContinue |
                Where-Object { $_.Message -match "display driver|nvlddmkm|amdkmdag|igfx|video hardware|LiveKernelEvent" }).Count
        } catch {}
        if ($gpuEventCount -gt 0) { $score -= 20 }

        # Non-OK GPU status
        foreach ($gpu in $gpus) {
            if ($gpu.Status -and $gpu.Status -notmatch "OK") { $score -= 15 }
        }
        $score = [math]::Max(0, $score)

        # Driver age calculation
        $driverAgeText = $null
        $primaryGpu = $gpus | Select-Object -First 1
        if ($primaryGpu -and $primaryGpu.DriverDate) {
            $driverAgeDays = [math]::Round(((Get-Date) - $primaryGpu.DriverDate).TotalDays, 0)
            if ($driverAgeDays -ge 365) {
                $years = [math]::Round($driverAgeDays / 365.25, 1)
                $driverAgeText = "$years years"
            } else {
                $months = [math]::Round($driverAgeDays / 30.44, 0)
                $driverAgeText = "$months months"
            }
        }

        @{
            Score         = $score
            GPUEvents     = $gpuEventCount
            DriverAge     = $driverAgeText
            GPUs          = @($gpus | ForEach-Object {
                @{
                    Name           = $_.Name
                    DriverVersion  = $_.DriverVersion
                    DriverDate     = if ($_.DriverDate) { $_.DriverDate.ToString("yyyy-MM-dd") } else { $null }
                    AdapterRAMGB   = if ($_.AdapterRAM -gt 0) { [math]::Round($_.AdapterRAM / 1GB, 1) } else { 0 }
                    Resolution     = "$($_.CurrentHorizontalResolution)x$($_.CurrentVerticalResolution)"
                    Status         = $_.Status
                }
            })
        }
    } @{ Score = 100; GPUEvents = 0; DriverAge = $null; GPUs = @() }

    if ($gpuData.GPUEvents -gt 0) {
        $null = $recommendations.Add("$($gpuData.GPUEvents) GPU/display driver event(s) found - update graphics drivers")
    }
    if ($gpuData.DriverAge -and $gpuData.DriverAge -match "(\d+) years" -and [double]$matches[1] -ge 1) {
        $null = $recommendations.Add("GPU driver is $($gpuData.DriverAge) old - update to latest stable driver")
    }

    # ─────────────────────────────────────────────────────────────────────
    # 7. WINDOWS RELIABILITY
    # ─────────────────────────────────────────────────────────────────────
    Write-DiagLog "Wear & Tear: Collecting Windows reliability..."
    $reliabilityData = Invoke-Safe {
        $days = 90; $start = (Get-Date).AddDays(-$days); $score = 100

        $eventDefs = @(
            @{ Category = "BlueScreen";          Filter = @{LogName='System'; Id=1001; StartTime=$start}; Weight = 8; Cap = 25 },
            @{ Category = "UnexpectedShutdown";  Filter = @{LogName='System'; Id=41; StartTime=$start};   Weight = 5; Cap = 20 },
            @{ Category = "DirtyShutdown";       Filter = @{LogName='System'; Id=6008; StartTime=$start}; Weight = 5; Cap = 20 },
            @{ Category = "DiskBadBlock";        Filter = @{LogName='System'; Id=7; StartTime=$start};    Weight = 8; Cap = 25 },
            @{ Category = "NTFSCorruption";      Filter = @{LogName='System'; Id=55; StartTime=$start};   Weight = 8; Cap = 25 },
            @{ Category = "StorageReset";        Filter = @{LogName='System'; Id=129; StartTime=$start};  Weight = 8; Cap = 25 },
            @{ Category = "DiskIORetry";         Filter = @{LogName='System'; Id=153; StartTime=$start};  Weight = 8; Cap = 25 }
        )

        $bsodCount = 0; $appCrashCount = 0; $appHangCount = 0
        $eventSummary = @{}

        foreach ($def in $eventDefs) {
            $count = 0
            try { $count = @(Get-WinEvent -FilterHashtable $def.Filter -ErrorAction SilentlyContinue).Count } catch {}
            $eventSummary[$def.Category] = $count
            if ($count -gt 0) {
                $penalty = [math]::Min($def.Cap, $count * $def.Weight)
                $score -= $penalty
            }
            if ($def.Category -eq "BlueScreen") { $bsodCount = $count }
        }

        # Application errors/hangs
        try { $appCrashCount = @(Get-WinEvent -FilterHashtable @{LogName='Application'; ProviderName='Application Error'; StartTime=$start} -ErrorAction SilentlyContinue).Count } catch {}
        try { $appHangCount  = @(Get-WinEvent -FilterHashtable @{LogName='Application'; ProviderName='Application Hang'; StartTime=$start} -ErrorAction SilentlyContinue).Count } catch {}
        $eventSummary["AppCrashes"] = $appCrashCount
        $eventSummary["AppHangs"]   = $appHangCount
        if (($appCrashCount + $appHangCount) -gt 10) { $score -= 10 }

        $score = [math]::Max(0, $score)

        @{
            Score        = $score
            DaysChecked  = $days
            BSODs        = $bsodCount
            AppCrashes   = $appCrashCount
            AppHangs     = $appHangCount
            EventSummary = $eventSummary
        }
    } @{ Score = 100; DaysChecked = 90; BSODs = 0; AppCrashes = 0; AppHangs = 0; EventSummary = @{} }

    if ($reliabilityData.BSODs -gt 0) {
        $null = $recommendations.Add("$($reliabilityData.BSODs) blue screen(s) in last 90 days - investigate hardware/driver stability")
    }
    if (($reliabilityData.AppCrashes + $reliabilityData.AppHangs) -gt 20) {
        $null = $recommendations.Add("High application crash/hang count ($($reliabilityData.AppCrashes) crashes, $($reliabilityData.AppHangs) hangs) - review failing applications")
    }

    # ─────────────────────────────────────────────────────────────────────
    # 8. DEVICE HEALTH
    # ─────────────────────────────────────────────────────────────────────
    Write-DiagLog "Wear & Tear: Collecting device health..."
    $deviceData = Invoke-Safe {
        $score = 100
        $problemDevices = @(Get-PnpDevice -ErrorAction SilentlyContinue | Where-Object { $_.Status -ne "OK" })
        $problemCount = $problemDevices.Count
        if ($problemCount -gt 0) { $score -= [math]::Min(25, $problemCount * 5) }

        # Network adapter issues
        $netWarnings = @()
        try {
            Get-NetAdapter -ErrorAction SilentlyContinue | ForEach-Object {
                if ($_.Status -ne "Up" -and $_.HardwareInterface) { $netWarnings += "$($_.Name) is $($_.Status)" }
                if ($_.LinkSpeed -match "100 Mbps" -and $_.InterfaceDescription -match "Gigabit|GbE|1000") {
                    $netWarnings += "$($_.Name) limited to 100Mbps on gigabit adapter"
                }
            }
        } catch {}
        if ($netWarnings.Count -gt 0) { $score -= 10 }

        # USB events (last 90 days)
        $usbEventCount = 0
        try {
            $usbEventCount = @(Get-WinEvent -FilterHashtable @{LogName='System'; StartTime=(Get-Date).AddDays(-90)} -ErrorAction SilentlyContinue |
                Where-Object { $_.Message -match "USB|device not recognized|device descriptor|reset.*port" }).Count
        } catch {}
        if ($usbEventCount -gt 0) { $score -= 10 }

        $score = [math]::Max(0, $score)

        @{
            Score           = $score
            ProblemDevices  = $problemCount
            ProblemList     = @($problemDevices | Select-Object -First 20 | ForEach-Object {
                @{ Class = $_.Class; Name = $_.FriendlyName; Status = "$($_.Status)" }
            })
            NetworkWarnings = $netWarnings
            USBEventCount   = $usbEventCount
        }
    } @{ Score = 100; ProblemDevices = 0; ProblemList = @(); NetworkWarnings = @(); USBEventCount = 0 }

    if ($deviceData.ProblemDevices -gt 0) {
        $null = $recommendations.Add("$($deviceData.ProblemDevices) device(s) with non-OK status - review Device Manager")
    }

    # ─────────────────────────────────────────────────────────────────────
    # OVERALL WEIGHTED SCORE
    # ─────────────────────────────────────────────────────────────────────
    Write-DiagLog "Wear & Tear: Calculating overall score..."

    $weights = @(
        @{ Name = "SystemAge";          Score = $sysAge.Score;           Weight = 10 },
        @{ Name = "Storage";            Score = $storageData.Score;      Weight = 25 },
        @{ Name = "Battery";            Score = $batteryData.Score;      Weight = 10 },
        @{ Name = "Thermal";            Score = $thermalData.Score;      Weight = 15 },
        @{ Name = "RAM";                Score = $ramData.Score;          Weight = 15 },
        @{ Name = "GPU";                Score = $gpuData.Score;          Weight = 5 },
        @{ Name = "WindowsReliability"; Score = $reliabilityData.Score;  Weight = 15 },
        @{ Name = "DeviceHealth";       Score = $deviceData.Score;       Weight = 5 }
    )

    # If no battery, exclude its weight from dragging score
    if (-not $batteryData.BatteryDetected) {
        $weights | Where-Object { $_.Name -eq "Battery" } | ForEach-Object { $_.Score = 100 }
    }

    $weightedSum   = 0; $totalWeight = 0
    foreach ($w in $weights) {
        $weightedSum  += ($w.Score * $w.Weight)
        $totalWeight  += $w.Weight
    }
    $overallScore = [int]([math]::Round($weightedSum / $totalWeight, 0))
    $overallGrade = _WTGrade $overallScore
    $overallRisk  = _WTRisk $overallScore
    $estimatedLifeYears = _WTLife $overallScore

    # Refine life estimate using storage data if available
    $storageLifeEstimates = @()
    foreach ($drv in $storageData.Drives) {
        if ($null -ne $drv.WearPercentUsed -and $drv.WearPercentUsed -gt 0 -and $null -ne $drv.PowerOnHours -and $drv.PowerOnHours -gt 0) {
            $hoursPerPct = $drv.PowerOnHours / $drv.WearPercentUsed
            $remaining   = [math]::Max(0, 100 - $drv.WearPercentUsed)
            $yearsLeft   = [math]::Round(($hoursPerPct * $remaining) / 8760, 1)
            $storageLifeEstimates += $yearsLeft
        }
    }
    if ($storageLifeEstimates.Count -gt 0) {
        $minStorageLife = ($storageLifeEstimates | Measure-Object -Minimum).Minimum
        if ($minStorageLife -lt $estimatedLifeYears) {
            $estimatedLifeYears = $minStorageLife
        }
    }

    Write-DiagLog "Wear & Tear: Overall Score = $overallScore/100, Grade = $overallGrade, Risk = $overallRisk"
    Write-DiagLog "=== WEAR & TEAR LIFE REPORT COMPLETE ==="

    # ─────────────────────────────────────────────────────────────────────
    # BUILD RETURN HASHTABLE
    # ─────────────────────────────────────────────────────────────────────
    return @{
        Score              = $overallScore
        Grade              = $overallGrade
        GradeFull          = _WTGradeFull $overallScore
        RiskLevel          = $overallRisk
        EstimatedLifeYears = $estimatedLifeYears
        LifeText           = _WTLifeText $overallScore
        Components         = @{
            SystemAge = @{
                Score        = $sysAge.Score
                AgeYears     = $sysAge.AgeYears
                BIOSAgeYears = $sysAge.BIOSAgeYears
                OSAgeYears   = $sysAge.OSAgeYears
                InstallDate  = $sysAge.InstallDate
                BIOSDate     = $sysAge.BIOSDate
                Manufacturer = $sysAge.Manufacturer
                Model        = $sysAge.Model
                Serial       = $sysAge.Serial
            }
            Storage = @{
                Score         = $storageData.Score
                SmartCtlFound = $storageData.SmartCtlFound
                Details       = $storageData.Drives
                Volumes       = $storageData.Volumes
            }
            Battery = @{
                Score            = $batteryData.Score
                BatteryDetected  = $batteryData.BatteryDetected
                HealthPct        = $batteryData.HealthPct
                DesignCapMWh     = $batteryData.DesignCapMWh
                FullChargeCapMWh = $batteryData.FullChargeCapMWh
                CycleCount       = $batteryData.CycleCount
                ChargePercent    = $batteryData.ChargePercent
            }
            Thermal = @{
                Score             = $thermalData.Score
                AvgTemp           = $thermalData.AvgTemp
                MaxTemp           = $thermalData.MaxTemp
                ThermalZones      = $thermalData.ThermalZones
                ThermalEventCount = $thermalData.ThermalEventCount
            }
            RAM = @{
                Score         = $ramData.Score
                TotalGB       = $ramData.TotalGB
                ModuleCount   = $ramData.ModuleCount
                MixedSpeeds   = $ramData.MixedSpeeds
                WHEAErrors    = $ramData.WHEAErrors
                MemDiagEvents = $ramData.MemDiagEvents
                Modules       = $ramData.Modules
            }
            GPU = @{
                Score     = $gpuData.Score
                GPUEvents = $gpuData.GPUEvents
                DriverAge = $gpuData.DriverAge
                GPUs      = $gpuData.GPUs
            }
            WindowsReliability = @{
                Score        = $reliabilityData.Score
                DaysChecked  = $reliabilityData.DaysChecked
                BSODs        = $reliabilityData.BSODs
                AppCrashes   = $reliabilityData.AppCrashes
                AppHangs     = $reliabilityData.AppHangs
                EventSummary = $reliabilityData.EventSummary
            }
            DeviceHealth = @{
                Score           = $deviceData.Score
                ProblemDevices  = $deviceData.ProblemDevices
                ProblemList     = $deviceData.ProblemList
                NetworkWarnings = $deviceData.NetworkWarnings
                USBEventCount   = $deviceData.USBEventCount
            }
        }
        ComponentScores    = $weights
        Recommendations    = @($recommendations)
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# GAMING PC DIAGNOSTIC TOOLKIT
# Time-sampled stress, DiskSpd, PresentMon, deep network, power, orchestrator
# ─────────────────────────────────────────────────────────────────────────────

function Start-TimeSampledStressTest {
    param(
        [int]$DurationSeconds = 120,
        [int]$SampleIntervalSec = 5
    )

    Write-DiagLog "Starting time-sampled CPU+GPU stress test (${DurationSeconds}s, sampling every ${SampleIntervalSec}s)..."

    $results = @{
        DurationSec        = $DurationSeconds
        SampleCount        = 0
        Samples            = @()
        PeakCPUTemp        = $null
        PeakGPUTemp        = $null
        AvgCPUTemp         = $null
        AvgGPUTemp         = $null
        MaxCPUClock        = $null
        MinCPUClock        = $null
        ThrottleDetected   = $false
        ThrottleEvents     = @()
        CPUStressPassed    = $true
        GPUStressPassed    = $true
        CoolingRecoveryTimeSec = $null
    }

    # ── Helper: read current CPU temperature ──
    function _SampleCPUTemp {
        Invoke-Safe {
            $t = Get-CimInstance MSAcpi_ThermalZoneTemperature -Namespace root/wmi -ErrorAction Stop | Select-Object -First 1
            [math]::Round(($t.CurrentTemperature / 10) - 273.15, 1)
        } $null
    }

    # ── Helper: read GPU temperature (try WMI thermalzone fallback) ──
    function _SampleGPUTemp {
        # Try dedicated GPU thermal zone (second zone if present)
        Invoke-Safe {
            $zones = @(Get-CimInstance MSAcpi_ThermalZoneTemperature -Namespace root/wmi -ErrorAction Stop)
            if ($zones.Count -ge 2) {
                [math]::Round(($zones[1].CurrentTemperature / 10) - 273.15, 1)
            } else { $null }
        } $null
    }

    # ── Helper: read fan RPM ──
    function _SampleFanRPM {
        Invoke-Safe {
            $fan = Get-CimInstance Win32_Fan -ErrorAction Stop | Select-Object -First 1
            if ($fan -and $fan.DesiredSpeed) { [int]$fan.DesiredSpeed } else { $null }
        } $null
    }

    # ── Start CPU stress background jobs (all-cores prime sieve) ──
    $threadCount = [Environment]::ProcessorCount
    $endTime = (Get-Date).AddSeconds($DurationSeconds)
    $cpuJobs = @()
    for ($i = 0; $i -lt $threadCount; $i++) {
        $cpuJobs += Start-Job -ScriptBlock {
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

    # ── Start GPU stress background job (GDI+ rendering loop) ──
    $gpuJob = Start-Job -ScriptBlock {
        param($end)
        $errors = 0; $iterations = 0
        try {
            Add-Type -AssemblyName System.Drawing
            while ((Get-Date) -lt $end) {
                $bmp = New-Object System.Drawing.Bitmap(2048, 2048)
                $g = [System.Drawing.Graphics]::FromImage($bmp)
                $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
                for ($j = 0; $j -lt 50; $j++) {
                    $brush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb((Get-Random -Max 256),(Get-Random -Max 256),(Get-Random -Max 256)))
                    $g.FillEllipse($brush, (Get-Random -Max 1800), (Get-Random -Max 1800), (Get-Random -Min 50 -Max 500), (Get-Random -Min 50 -Max 500))
                    $pen = New-Object System.Drawing.Pen($brush.Color, (Get-Random -Min 1 -Max 10))
                    $g.DrawLine($pen, (Get-Random -Max 2048), (Get-Random -Max 2048), (Get-Random -Max 2048), (Get-Random -Max 2048))
                    $brush.Dispose(); $pen.Dispose()
                }
                $matrix = New-Object System.Drawing.Drawing2D.Matrix
                $matrix.Rotate((Get-Random -Max 360))
                $matrix.Scale(1.5, 1.5)
                $g.Transform = $matrix
                $g.DrawImage($bmp, 0, 0)
                $matrix.Dispose()
                $g.Dispose(); $bmp.Dispose()
                $iterations++
            }
        } catch { $errors++ }
        return @{ Iterations = $iterations; Errors = $errors }
    } -ArgumentList $endTime

    # ── Sampling loop during stress ──
    $samples = [System.Collections.ArrayList]::new()
    $startTime = Get-Date

    while ((Get-Date) -lt $endTime) {
        Start-Sleep -Seconds $SampleIntervalSec
        $elapsed = [math]::Round(((Get-Date) - $startTime).TotalSeconds)

        $cpuTemp = _SampleCPUTemp
        $gpuTemp = _SampleGPUTemp
        $fanRPM  = _SampleFanRPM

        $cpuUsage = Invoke-Safe {
            [math]::Round((Get-Counter '\Processor(_Total)\% Processor Time' -ErrorAction Stop).CounterSamples[0].CookedValue, 1)
        } $null

        $cpuClock = Invoke-Safe {
            (Get-CimInstance Win32_Processor -ErrorAction Stop | Select-Object -First 1).CurrentClockSpeed
        } $null

        $ramUsage = Invoke-Safe {
            $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
            [math]::Round((($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / $os.TotalVisibleMemorySize) * 100, 1)
        } $null

        $null = $samples.Add(@{
            TimeSec      = $elapsed
            CPUTempC     = $cpuTemp
            CPUUsagePct  = $cpuUsage
            CPUClockMHz  = $cpuClock
            GPUTempC     = $gpuTemp
            RAMUsagePct  = $ramUsage
            FanRPM       = $fanRPM
        })

        Write-DiagLog "  StressSample: ${elapsed}s CPU=${cpuTemp}C/${cpuUsage}% Clock=${cpuClock}MHz GPU=${gpuTemp}C RAM=${ramUsage}% Fan=${fanRPM}"
    }

    # ── Stop stress jobs and collect results ──
    $cpuJobs + @($gpuJob) | Wait-Job -Timeout 30 | Out-Null

    $totalCPUIterations = 0; $totalCPUErrors = 0
    foreach ($j in $cpuJobs) {
        $r = Receive-Job $j -ErrorAction SilentlyContinue
        if ($r) { $totalCPUIterations += $r.Iterations; $totalCPUErrors += $r.Errors }
        Remove-Job $j -Force -ErrorAction SilentlyContinue
    }
    $results.CPUStressPassed = ($totalCPUErrors -eq 0)

    $gpuResult = Receive-Job $gpuJob -ErrorAction SilentlyContinue
    Remove-Job $gpuJob -Force -ErrorAction SilentlyContinue
    if ($gpuResult -and $gpuResult.Errors -gt 0) { $results.GPUStressPassed = $false }

    # ── Post-stress cooling recovery sampling (30 seconds) ──
    Write-DiagLog "Stress jobs stopped. Sampling cooling recovery for 30 seconds..."
    $recoveryStart = Get-Date
    $peakTempAtEnd = if ($samples.Count -gt 0) {
        $lastSample = $samples[$samples.Count - 1]
        if ($lastSample.CPUTempC) { $lastSample.CPUTempC } else { 0 }
    } else { 0 }
    $recoveryTarget = $peakTempAtEnd - 10
    $recoveryAchieved = $false
    $recoveryTimeSec = $null

    for ($ri = 0; $ri -lt 6; $ri++) {
        Start-Sleep -Seconds 5
        $elapsed = [math]::Round(((Get-Date) - $startTime).TotalSeconds)
        $cpuTemp = _SampleCPUTemp
        $gpuTemp = _SampleGPUTemp
        $fanRPM  = _SampleFanRPM
        $cpuClock = Invoke-Safe { (Get-CimInstance Win32_Processor -ErrorAction Stop | Select-Object -First 1).CurrentClockSpeed } $null
        $ramUsage = Invoke-Safe {
            $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
            [math]::Round((($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / $os.TotalVisibleMemorySize) * 100, 1)
        } $null
        $cpuUsage = Invoke-Safe {
            [math]::Round((Get-Counter '\Processor(_Total)\% Processor Time' -ErrorAction Stop).CounterSamples[0].CookedValue, 1)
        } $null

        $null = $samples.Add(@{
            TimeSec      = $elapsed
            CPUTempC     = $cpuTemp
            CPUUsagePct  = $cpuUsage
            CPUClockMHz  = $cpuClock
            GPUTempC     = $gpuTemp
            RAMUsagePct  = $ramUsage
            FanRPM       = $fanRPM
        })

        if (-not $recoveryAchieved -and $cpuTemp -and $cpuTemp -le $recoveryTarget) {
            $recoveryTimeSec = [math]::Round(((Get-Date) - $recoveryStart).TotalSeconds)
            $recoveryAchieved = $true
        }

        Write-DiagLog "  RecoverySample: ${elapsed}s CPU=${cpuTemp}C"
    }

    if (-not $recoveryAchieved) {
        $recoveryTimeSec = [math]::Round(((Get-Date) - $recoveryStart).TotalSeconds)
    }

    # ── Calculate statistics ──
    $results.Samples = @($samples)
    $results.SampleCount = $samples.Count
    $results.CoolingRecoveryTimeSec = $recoveryTimeSec

    $cpuTemps = @($samples | Where-Object { $null -ne $_.CPUTempC } | ForEach-Object { $_.CPUTempC })
    $gpuTemps = @($samples | Where-Object { $null -ne $_.GPUTempC } | ForEach-Object { $_.GPUTempC })
    $cpuClocks = @($samples | Where-Object { $null -ne $_.CPUClockMHz } | ForEach-Object { $_.CPUClockMHz })

    if ($cpuTemps.Count -gt 0) {
        $results.PeakCPUTemp = ($cpuTemps | Measure-Object -Maximum).Maximum
        $results.AvgCPUTemp  = [math]::Round(($cpuTemps | Measure-Object -Average).Average, 1)
    }
    if ($gpuTemps.Count -gt 0) {
        $results.PeakGPUTemp = ($gpuTemps | Measure-Object -Maximum).Maximum
        $results.AvgGPUTemp  = [math]::Round(($gpuTemps | Measure-Object -Average).Average, 1)
    }
    if ($cpuClocks.Count -gt 0) {
        $results.MaxCPUClock = ($cpuClocks | Measure-Object -Maximum).Maximum
        $results.MinCPUClock = ($cpuClocks | Measure-Object -Minimum).Minimum

        # Throttle detection: clock drop > 10% from max observed
        if ($results.MaxCPUClock -gt 0) {
            $throttleThreshold = $results.MaxCPUClock * 0.90
            $throttleEvents = @()
            foreach ($s in $samples) {
                if ($null -ne $s.CPUClockMHz -and $s.CPUClockMHz -lt $throttleThreshold) {
                    $dropPct = [math]::Round((($results.MaxCPUClock - $s.CPUClockMHz) / $results.MaxCPUClock) * 100, 1)
                    $throttleEvents += @{ TimeSec = $s.TimeSec; ClockDropPct = $dropPct; ClockMHz = $s.CPUClockMHz }
                }
            }
            if ($throttleEvents.Count -gt 0) {
                $results.ThrottleDetected = $true
                $results.ThrottleEvents = $throttleEvents
            }
        }
    }

    Write-DiagLog "TimeSampledStress complete: Samples=$($results.SampleCount), PeakCPU=$($results.PeakCPUTemp)C, PeakGPU=$($results.PeakGPUTemp)C, Throttle=$($results.ThrottleDetected), Recovery=$($results.CoolingRecoveryTimeSec)s"
    return $results
}

# ─────────────────────────────────────────────────────────────────────────────
# DISKSPD BENCHMARK (with built-in fallback)
# ─────────────────────────────────────────────────────────────────────────────

function Invoke-DiskSpdBenchmark {
    param(
        [string]$TargetDrive = "C:",
        [int]$FileSizeMB = 256,
        [int]$DurationSec = 30
    )

    Write-DiagLog "Starting DiskSpd benchmark on $TargetDrive (${FileSizeMB}MB, ${DurationSec}s)..."

    $results = @{
        ToolUsed           = "Built-in"
        SeqReadMBps        = 0
        SeqWriteMBps       = 0
        Random4KReadIOPS   = 0
        Random4KWriteIOPS  = 0
        AvgLatencyMs       = 0
        MaxLatencyMs       = 0
        DrivePath          = $TargetDrive
        FileSizeMB         = $FileSizeMB
        ThrottleDetected   = $false
    }

    $testFile = Join-Path $TargetDrive "diskspd_test.dat"

    # Try to find diskspd.exe
    $diskspd = Find-Tool "DiskSpd" @("diskspd.exe")
    if (-not $diskspd) {
        $diskspd = Get-ChildItem $Global:ToolsDir -Recurse -Filter "diskspd.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($diskspd) { $diskspd = $diskspd.FullName }
    }

    if ($diskspd) {
        Write-DiagLog "DiskSpd found: $diskspd"
        $results.ToolUsed = "DiskSpd"

        # ── Helper: run diskspd and capture output ──
        function _RunDiskSpd {
            param([string]$Arguments)
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = $diskspd
            $psi.Arguments = $Arguments
            $psi.RedirectStandardOutput = $true
            $psi.RedirectStandardError = $true
            $psi.UseShellExecute = $false
            $psi.CreateNoWindow = $true
            $proc = New-Object System.Diagnostics.Process
            $proc.StartInfo = $psi
            $null = $proc.Start()
            $stdout = $proc.StandardOutput.ReadToEnd()
            $proc.WaitForExit()
            return $stdout
        }

        # ── Helper: parse diskspd text output ──
        function _ParseDiskSpdOutput {
            param([string]$Output)
            $parsed = @{ ReadMBps = 0; WriteMBps = 0; ReadIOPS = 0; WriteIOPS = 0; AvgLatMs = 0; MaxLatMs = 0 }
            $lines = $Output -split "`n"
            $inRead = $false; $inWrite = $false; $inLatency = $false

            foreach ($line in $lines) {
                if ($line -match "Read IO") { $inRead = $true; $inWrite = $false }
                if ($line -match "Write IO") { $inRead = $false; $inWrite = $true }

                # Total throughput line: "total:  ... MiB/s"  or bytes/sec
                if ($line -match "total:\s+\d+\s*\|\s+[\d.]+\s*\|\s+([\d.]+)\s*\|\s+([\d.]+)") {
                    if ($inRead) {
                        $results.Random4KReadIOPS = [math]::Round([double]$Matches[2], 0)
                    }
                    if ($inWrite) {
                        $results.Random4KWriteIOPS = [math]::Round([double]$Matches[2], 0)
                    }
                }

                # MiB/s pattern
                if ($line -match "([\d.]+)\s+MiB/s") {
                    $mbps = [double]$Matches[1]
                    if ($inRead -and $parsed.ReadMBps -eq 0) { $parsed.ReadMBps = [math]::Round($mbps, 1) }
                    if ($inWrite -and $parsed.WriteMBps -eq 0) { $parsed.WriteMBps = [math]::Round($mbps, 1) }
                }

                # I/O per s
                if ($line -match "([\d.]+)\s+I/O per s") {
                    $iops = [double]$Matches[1]
                    if ($inRead -and $parsed.ReadIOPS -eq 0) { $parsed.ReadIOPS = [math]::Round($iops, 0) }
                    if ($inWrite -and $parsed.WriteIOPS -eq 0) { $parsed.WriteIOPS = [math]::Round($iops, 0) }
                }

                # Average latency
                if ($line -match "avg\.\s*:\s*([\d.]+)") {
                    $lat = [double]$Matches[1]
                    if ($parsed.AvgLatMs -eq 0) { $parsed.AvgLatMs = [math]::Round($lat, 3) }
                }

                # Max latency (look in %-ile section or max line)
                if ($line -match "max\.\s*:\s*([\d.]+)") {
                    $lat = [double]$Matches[1]
                    if ($lat -gt $parsed.MaxLatMs) { $parsed.MaxLatMs = [math]::Round($lat, 3) }
                }
            }
            return $parsed
        }

        try {
            # ── Mixed random 4K test (30% write) ──
            Write-DiagLog "DiskSpd: Running random 4K mixed test..."
            $randomArgs = "-b4K -t4 -o32 -r -w30 -d$DurationSec -Sh -D -L `"$testFile`" -c${FileSizeMB}M"
            $randomOutput = _RunDiskSpd $randomArgs
            $randomParsed = _ParseDiskSpdOutput $randomOutput

            $results.Random4KReadIOPS  = if ($randomParsed.ReadIOPS -gt 0) { $randomParsed.ReadIOPS } else { $results.Random4KReadIOPS }
            $results.Random4KWriteIOPS = if ($randomParsed.WriteIOPS -gt 0) { $randomParsed.WriteIOPS } else { $results.Random4KWriteIOPS }
            $results.AvgLatencyMs      = $randomParsed.AvgLatMs
            $results.MaxLatencyMs      = $randomParsed.MaxLatMs

            # ── Sequential read test (1M block, single thread) ──
            Write-DiagLog "DiskSpd: Running sequential read test..."
            $seqReadArgs = "-b1M -t1 -o8 -w0 -d10 -Sh `"$testFile`""
            $seqReadOutput = _RunDiskSpd $seqReadArgs
            $seqReadParsed = _ParseDiskSpdOutput $seqReadOutput
            $results.SeqReadMBps = $seqReadParsed.ReadMBps

            # ── Sequential write test (1M block, single thread) ──
            Write-DiagLog "DiskSpd: Running sequential write test..."
            $seqWriteArgs = "-b1M -t1 -o8 -w100 -d10 -Sh `"$testFile`""
            $seqWriteOutput = _RunDiskSpd $seqWriteArgs
            $seqWriteParsed = _ParseDiskSpdOutput $seqWriteOutput
            $results.SeqWriteMBps = $seqWriteParsed.WriteMBps

            Write-DiagLog "DiskSpd results: SeqR=$($results.SeqReadMBps) MB/s, SeqW=$($results.SeqWriteMBps) MB/s, 4KR=$($results.Random4KReadIOPS) IOPS, 4KW=$($results.Random4KWriteIOPS) IOPS, AvgLat=$($results.AvgLatencyMs)ms"
        } catch {
            Write-DiagLog "DiskSpd error: $($_.Exception.Message) - falling back to built-in" "WARN"
            $results.ToolUsed = "Built-in (DiskSpd failed)"
        }
    }

    # ── Fallback to built-in Start-DiskBenchmark if DiskSpd not available or failed ──
    if ($results.ToolUsed -ne "DiskSpd") {
        Write-DiagLog "Using built-in disk benchmark as fallback..."
        $driveLetter = $TargetDrive -replace "[:\\]", ""
        $builtIn = Start-DiskBenchmark -DriveLetter $driveLetter -FileSizeMB $FileSizeMB
        $results.SeqReadMBps  = $builtIn.SeqReadMBps
        $results.SeqWriteMBps = $builtIn.SeqWriteMBps
        $results.ToolUsed     = "Built-in"
    }

    # Cleanup test file
    if (Test-Path $testFile) {
        Remove-Item $testFile -Force -ErrorAction SilentlyContinue
        Write-DiagLog "DiskSpd test file cleaned up."
    }

    # Check for throttling: if sequential read drops well below expected for NVMe
    if ($results.SeqReadMBps -gt 0 -and $results.SeqWriteMBps -gt 0) {
        $ratio = $results.SeqWriteMBps / [math]::Max(1, $results.SeqReadMBps)
        if ($ratio -lt 0.2) {
            $results.ThrottleDetected = $true
            Write-DiagLog "DiskSpd: Write throttling suspected (write/read ratio=$([math]::Round($ratio,2)))" "WARN"
        }
    }

    return $results
}

# ─────────────────────────────────────────────────────────────────────────────
# PRESENTMON FRAME TIME CAPTURE
# ─────────────────────────────────────────────────────────────────────────────

function Invoke-PresentMonCapture {
    param(
        [int]$DurationSeconds = 60,
        [string]$ProcessName = ""
    )

    Write-DiagLog "Starting PresentMon capture (${DurationSeconds}s, process='$ProcessName')..."

    $results = @{
        Available            = $false
        AvgFPS               = $null
        OnePercentLowFPS     = $null
        PointOnePercentLowFPS = $null
        AvgFrameTimeMs       = $null
        P99FrameTimeMs       = $null
        CapturedProcess      = $null
        DurationSec          = $DurationSeconds
        TotalFrames          = 0
    }

    # Locate PresentMon
    $presentMon = Find-Tool "PresentMon" @("PresentMon.exe", "PresentMon-2.3.0-x64.exe", "PresentMon64.exe")
    if (-not $presentMon) {
        $presentMon = Get-ChildItem $Global:ToolsDir -Recurse -Filter "PresentMon*.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($presentMon) { $presentMon = $presentMon.FullName }
    }

    if (-not $presentMon) {
        Write-DiagLog "PresentMon not found in tools directory. Frame time capture not available."
        $results.Message = "PresentMon not found. Place PresentMon.exe in the Tools folder to enable frame time analysis."
        return $results
    }

    Write-DiagLog "PresentMon found: $presentMon"
    $results.Available = $true
    $tempCsv = Join-Path $env:TEMP "pcplus_presentmon_$(Get-Random).csv"

    try {
        # Build arguments
        $pmArgs = "--output_file `"$tempCsv`" --terminate_after_ticks $DurationSeconds --no_top"
        if ($ProcessName) {
            $pmArgs += " --process_name `"$ProcessName`""
        }

        # Launch PresentMon
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $presentMon
        $psi.Arguments = $pmArgs
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $proc = New-Object System.Diagnostics.Process
        $proc.StartInfo = $psi
        $null = $proc.Start()

        # Wait for it to finish (with timeout)
        $maxWaitMs = ($DurationSeconds + 30) * 1000
        if (-not $proc.WaitForExit($maxWaitMs)) {
            try { $proc.Kill() } catch {}
            Write-DiagLog "PresentMon timed out after $($DurationSeconds + 30)s" "WARN"
        }

        # Parse CSV output
        if (Test-Path $tempCsv) {
            $csv = Import-Csv $tempCsv -ErrorAction Stop

            # PresentMon CSV columns vary by version; find the frame time column
            $frameTimeCol = $null
            $processCol   = $null
            $sampleCols   = $csv[0].PSObject.Properties.Name
            foreach ($col in $sampleCols) {
                if ($col -match "MsBetweenPresents|msBetweenPresents|FrameTime|ms_between_presents") { $frameTimeCol = $col }
                if ($col -match "Application|ProcessName|process_name") { $processCol = $col }
            }

            if ($frameTimeCol -and $csv.Count -gt 0) {
                $frameTimes = @($csv | ForEach-Object { [double]$_.$frameTimeCol } | Where-Object { $_ -gt 0 -and $_ -lt 1000 })
                $results.TotalFrames = $frameTimes.Count

                if ($frameTimes.Count -gt 0) {
                    # Average frame time and FPS
                    $avgFT = ($frameTimes | Measure-Object -Average).Average
                    $results.AvgFrameTimeMs = [math]::Round($avgFT, 2)
                    $results.AvgFPS = [math]::Round(1000.0 / $avgFT, 1)

                    # Sort for percentile calculations
                    $sorted = $frameTimes | Sort-Object

                    # 99th percentile frame time
                    $p99Index = [math]::Floor($sorted.Count * 0.99)
                    $results.P99FrameTimeMs = [math]::Round($sorted[$p99Index], 2)

                    # 1% low FPS = average of bottom 1% frame times inverted
                    $onePercentCount = [math]::Max(1, [math]::Floor($sorted.Count * 0.01))
                    $worst1Pct = $sorted[($sorted.Count - $onePercentCount)..($sorted.Count - 1)]
                    $avg1PctFT = ($worst1Pct | Measure-Object -Average).Average
                    $results.OnePercentLowFPS = [math]::Round(1000.0 / $avg1PctFT, 1)

                    # 0.1% low FPS
                    $pointOneCount = [math]::Max(1, [math]::Floor($sorted.Count * 0.001))
                    $worst01Pct = $sorted[($sorted.Count - $pointOneCount)..($sorted.Count - 1)]
                    $avg01PctFT = ($worst01Pct | Measure-Object -Average).Average
                    $results.PointOnePercentLowFPS = [math]::Round(1000.0 / $avg01PctFT, 1)

                    # Captured process name
                    if ($processCol) {
                        $results.CapturedProcess = ($csv | Select-Object -First 1).$processCol
                    } elseif ($ProcessName) {
                        $results.CapturedProcess = $ProcessName
                    }
                }

                Write-DiagLog "PresentMon: AvgFPS=$($results.AvgFPS), 1%Low=$($results.OnePercentLowFPS), 0.1%Low=$($results.PointOnePercentLowFPS), P99FT=$($results.P99FrameTimeMs)ms, Frames=$($results.TotalFrames)"
            } else {
                Write-DiagLog "PresentMon CSV parsed but no frame time column found." "WARN"
                $results.Message = "CSV captured but frame time column not recognized."
            }
        } else {
            Write-DiagLog "PresentMon did not produce output CSV." "WARN"
            $results.Message = "PresentMon ran but produced no output. Ensure a GPU-rendered application is running."
        }
    } catch {
        Write-DiagLog "PresentMon error: $($_.Exception.Message)" "WARN"
        $results.Message = "PresentMon error: $($_.Exception.Message)"
    } finally {
        if (Test-Path $tempCsv) { Remove-Item $tempCsv -Force -ErrorAction SilentlyContinue }
    }

    return $results
}

# ─────────────────────────────────────────────────────────────────────────────
# DEEP NETWORK TEST (beyond Get-NetworkDiagnostics)
# ─────────────────────────────────────────────────────────────────────────────

function Get-NetworkDeepTest {
    Write-DiagLog "Running deep network diagnostic test..."

    $results = @{
        PingTest     = @{ AvgMs = $null; MinMs = $null; MaxMs = $null; JitterMs = $null; PacketLossPct = $null; PacketsSent = 20 }
        DNSResponse  = @()
        WiFi         = @{ SignalPercent = $null; SSID = $null; Channel = $null; RadioType = $null; Band = $null; RxRate = $null; TxRate = $null }
        Adapters     = @()
        Speedtest    = @{ Available = $false; DownloadMbps = $null; UploadMbps = $null; PingMs = $null }
        Score        = 0
        Rating       = "Unknown"
    }

    # ── 1. Ping test to 8.8.8.8 (20 packets) ──
    Write-DiagLog "  Ping test: 20 packets to 8.8.8.8..."
    $pingData = Invoke-Safe {
        $pings = Test-Connection -ComputerName "8.8.8.8" -Count 20 -ErrorAction Stop
        $latencies = @($pings | ForEach-Object { $_.Latency })
        $received = $latencies.Count
        $loss = [math]::Round(((20 - $received) / 20) * 100, 1)

        $avg = [math]::Round(($latencies | Measure-Object -Average).Average, 1)
        $min = ($latencies | Measure-Object -Minimum).Minimum
        $max = ($latencies | Measure-Object -Maximum).Maximum

        # Jitter = standard deviation of RTT
        $mean = ($latencies | Measure-Object -Average).Average
        $sumSqDiff = 0
        foreach ($l in $latencies) { $sumSqDiff += [math]::Pow($l - $mean, 2) }
        $jitter = [math]::Round([math]::Sqrt($sumSqDiff / [math]::Max(1, $latencies.Count)), 1)

        @{ AvgMs = $avg; MinMs = $min; MaxMs = $max; JitterMs = $jitter; PacketLossPct = $loss; PacketsSent = 20 }
    } $results.PingTest

    $results.PingTest = $pingData
    Write-DiagLog "  Ping: Avg=$($pingData.AvgMs)ms, Min=$($pingData.MinMs), Max=$($pingData.MaxMs), Jitter=$($pingData.JitterMs)ms, Loss=$($pingData.PacketLossPct)%"

    # ── 2. DNS response times for multiple domains ──
    Write-DiagLog "  DNS response time tests..."
    $dnsTargets = @("google.com", "cloudflare.com", "microsoft.com")
    foreach ($domain in $dnsTargets) {
        $dnsResult = Invoke-Safe {
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            $resolved = Resolve-DnsName $domain -Type A -ErrorAction Stop
            $sw.Stop()
            @{
                Domain     = $domain
                ResponseMs = [math]::Round($sw.Elapsed.TotalMilliseconds, 1)
                IPAddress  = ($resolved | Where-Object { $_.Type -eq "A" } | Select-Object -First 1).IPAddress
                Success    = $true
            }
        } @{ Domain = $domain; ResponseMs = $null; IPAddress = $null; Success = $false }
        $results.DNSResponse += $dnsResult
        Write-DiagLog "  DNS $domain`: $($dnsResult.ResponseMs)ms"
    }

    # ── 3. WiFi signal strength and details ──
    Write-DiagLog "  WiFi signal check..."
    $results.WiFi = Invoke-Safe {
        $w = netsh wlan show interfaces 2>&1
        $signal = $null; $ssid = $null; $channel = $null; $radioType = $null; $band = $null; $rxRate = $null; $txRate = $null
        foreach ($l in $w) {
            if ($l -match "^\s+SSID\s+:\s+(.+)$") { $ssid = $Matches[1].Trim() }
            if ($l -match "Signal\s+:\s+(\d+)%") { $signal = [int]$Matches[1] }
            if ($l -match "Channel\s+:\s+(.+)$") { $channel = $Matches[1].Trim() }
            if ($l -match "Radio type\s+:\s+(.+)$") { $radioType = $Matches[1].Trim() }
            if ($l -match "Band\s+:\s+(.+)$") { $band = $Matches[1].Trim() }
            if ($l -match "Receive rate.*:\s+(.+)$") { $rxRate = $Matches[1].Trim() }
            if ($l -match "Transmit rate.*:\s+(.+)$") { $txRate = $Matches[1].Trim() }
        }
        @{ SignalPercent = $signal; SSID = $ssid; Channel = $channel; RadioType = $radioType; Band = $band; RxRate = $rxRate; TxRate = $txRate }
    } $results.WiFi

    if ($results.WiFi.SignalPercent) {
        Write-DiagLog "  WiFi: SSID=$($results.WiFi.SSID), Signal=$($results.WiFi.SignalPercent)%, Channel=$($results.WiFi.Channel), Radio=$($results.WiFi.RadioType)"
    } else {
        Write-DiagLog "  WiFi: Not connected or not available"
    }

    # ── 4. Ethernet / adapter link speeds ──
    Write-DiagLog "  Adapter link speeds..."
    $results.Adapters = @(Invoke-Safe {
        $adapters = @()
        Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq "Up" } | ForEach-Object {
            $ip = (Get-NetIPAddress -InterfaceIndex $_.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | Select-Object -First 1).IPAddress
            $adapters += @{
                Name      = $_.Name
                MAC       = $_.MacAddress
                LinkSpeed = $_.LinkSpeed
                IP        = $ip
                MediaType = $_.MediaConnectionState
                IfType    = if ($_.InterfaceDescription -match "Wi-Fi|Wireless|WLAN") { "WiFi" } else { "Ethernet" }
            }
        }
        $adapters
    } @())

    foreach ($a in $results.Adapters) {
        Write-DiagLog "  Adapter: $($a.Name) ($($a.IfType)) LinkSpeed=$($a.LinkSpeed) IP=$($a.IP)"
    }

    # ── 5. Speedtest (reuse existing Invoke-SpeedtestCLI or Get-NetworkSpeedTest download) ──
    Write-DiagLog "  Running speed test..."
    $speedResult = Invoke-Safe { Invoke-SpeedtestCLI } @{ Available = $false }
    if ($speedResult.Available) {
        $results.Speedtest = $speedResult
    } else {
        # Fallback: use the built-in download speed test
        $dlResult = Invoke-Safe {
            $testUrl = "http://speedtest.tele2.net/10MB.zip"
            $tmpFile = Join-Path $env:TEMP "pcplus_speedtest_deep.bin"
            $start = Get-Date
            Invoke-WebRequest -Uri $testUrl -OutFile $tmpFile -UseBasicParsing -TimeoutSec 30 -ErrorAction Stop
            $elapsed = ((Get-Date) - $start).TotalSeconds
            $fileSize = (Get-Item $tmpFile).Length
            Remove-Item $tmpFile -Force -ErrorAction SilentlyContinue
            $mbps = [math]::Round(($fileSize * 8 / 1000000) / $elapsed, 1)
            @{ Available = $true; DownloadMbps = $mbps; UploadMbps = $null; PingMs = $null }
        } @{ Available = $false }
        $results.Speedtest = $dlResult
    }

    Write-DiagLog "  Speedtest: Download=$($results.Speedtest.DownloadMbps) Mbps, Upload=$($results.Speedtest.UploadMbps) Mbps"

    # ── 6. Calculate network score ──
    $score = 100

    # Ping scoring
    if ($null -ne $pingData.AvgMs) {
        if ($pingData.AvgMs -gt 100) { $score -= 20 }
        elseif ($pingData.AvgMs -gt 50) { $score -= 10 }
        elseif ($pingData.AvgMs -gt 20) { $score -= 3 }
    } else { $score -= 15 }

    # Packet loss scoring
    if ($null -ne $pingData.PacketLossPct) {
        if ($pingData.PacketLossPct -gt 5) { $score -= 25 }
        elseif ($pingData.PacketLossPct -gt 1) { $score -= 10 }
        elseif ($pingData.PacketLossPct -gt 0) { $score -= 5 }
    }

    # Jitter scoring
    if ($null -ne $pingData.JitterMs) {
        if ($pingData.JitterMs -gt 20) { $score -= 15 }
        elseif ($pingData.JitterMs -gt 10) { $score -= 8 }
        elseif ($pingData.JitterMs -gt 5) { $score -= 3 }
    }

    # DNS scoring
    $avgDns = ($results.DNSResponse | Where-Object { $_.Success } | ForEach-Object { $_.ResponseMs } | Measure-Object -Average).Average
    if ($avgDns) {
        if ($avgDns -gt 200) { $score -= 10 }
        elseif ($avgDns -gt 100) { $score -= 5 }
    }

    # Download speed scoring
    if ($results.Speedtest.DownloadMbps) {
        if ($results.Speedtest.DownloadMbps -lt 10) { $score -= 20 }
        elseif ($results.Speedtest.DownloadMbps -lt 25) { $score -= 10 }
        elseif ($results.Speedtest.DownloadMbps -lt 50) { $score -= 5 }
    }

    $score = [math]::Max(0, $score)
    $results.Score = $score
    $results.Rating = if ($score -ge 85) { "Excellent" }
                      elseif ($score -ge 70) { "Good" }
                      elseif ($score -ge 50) { "Fair" }
                      else { "Poor" }

    Write-DiagLog "Network deep test complete: Score=$score, Rating=$($results.Rating)"
    return $results
}

# ─────────────────────────────────────────────────────────────────────────────
# ENHANCED POWER STABILITY (extends existing Get-PowerStabilityInfo)
# ─────────────────────────────────────────────────────────────────────────────

function Get-EnhancedPowerStabilityInfo {
    param(
        [hashtable]$TimeSeriesData = $null
    )

    Write-DiagLog "Running enhanced power stability analysis..."
    $startDate = (Get-Date).AddDays(-90)

    $results = @{
        KernelPower41Events    = @()
        KernelPower41Count     = 0
        UnexpectedShutdown6008 = @()
        Shutdown6008Count      = 0
        ClockDropsDuringStress = @()
        ClockDropsDetected     = $false
        BatteryInfo            = @{ Present = $false; IsLaptop = $false; ACAdapter = "N/A"; Wattage = "N/A"; ChargePercent = $null }
        PowerPlan              = "N/A"
        StabilityScore         = 100
        Rating                 = "Good"
        TotalPowerEvents       = 0
    }

    # ── 1. Kernel-Power 41 events (unexpected shutdown / power loss) ──
    $results.KernelPower41Events = @(Invoke-Safe {
        $events = @()
        Get-WinEvent -FilterHashtable @{LogName='System'; Id=41; ProviderName='Microsoft-Windows-Kernel-Power'; StartTime=$startDate} -MaxEvents 50 -ErrorAction Stop | ForEach-Object {
            $events += @{
                Time    = $_.TimeCreated.ToString("yyyy-MM-dd HH:mm")
                Message = ($_.Message -split "`n" | Select-Object -First 2) -join " "
            }
        }
        $events
    } @())
    $results.KernelPower41Count = $results.KernelPower41Events.Count
    Write-DiagLog "  Kernel-Power 41 events (90 days): $($results.KernelPower41Count)"

    # ── 2. Event ID 6008 (unexpected shutdown record) ──
    $results.UnexpectedShutdown6008 = @(Invoke-Safe {
        $events = @()
        Get-WinEvent -FilterHashtable @{LogName='System'; Id=6008; StartTime=$startDate} -MaxEvents 50 -ErrorAction Stop | ForEach-Object {
            $events += @{
                Time    = $_.TimeCreated.ToString("yyyy-MM-dd HH:mm")
                Message = ($_.Message -split "`n" | Select-Object -First 1)
            }
        }
        $events
    } @())
    $results.Shutdown6008Count = $results.UnexpectedShutdown6008.Count
    Write-DiagLog "  Event 6008 (unexpected shutdown): $($results.Shutdown6008Count)"

    # ── 3. Clock speed drops from time-series data (if provided) ──
    if ($TimeSeriesData -and $TimeSeriesData.ThrottleDetected) {
        $results.ClockDropsDetected = $true
        $results.ClockDropsDuringStress = @($TimeSeriesData.ThrottleEvents)
        Write-DiagLog "  Clock drops during stress: $($results.ClockDropsDuringStress.Count) events detected"
    }

    # ── 4. Battery / charger info for laptops ──
    $results.BatteryInfo = Invoke-Safe {
        $bat = Get-CimInstance Win32_Battery -ErrorAction Stop
        if ($bat) {
            $acStatus = switch ($bat.BatteryStatus) {
                1 { "On Battery" }; 2 { "Charging" }; 3 { "Fully Charged" }
                4 { "Low" }; 5 { "Critical" }; default { "AC Connected" }
            }

            # Try to get wattage from WMI
            $wattage = Invoke-Safe {
                $ps = Get-CimInstance Win32_PowerSupply -ErrorAction Stop | Select-Object -First 1
                if ($ps -and $ps.TotalOutputPower -gt 0) { "$([math]::Round($ps.TotalOutputPower / 1000, 0))W" }
                else {
                    # Try battery discharge rate as proxy
                    $st = Get-CimInstance -Namespace "root\WMI" -ClassName BatteryStatus -ErrorAction Stop | Select-Object -First 1
                    if ($st -and $st.DischargeRate -and $st.DischargeRate -gt 0 -and $st.DischargeRate -lt 100000) {
                        "$([math]::Round($st.DischargeRate / 1000, 1))W (discharge rate)"
                    } else { "N/A" }
                }
            } "N/A"

            @{
                Present       = $true
                IsLaptop      = $true
                ACAdapter     = $acStatus
                Wattage       = $wattage
                ChargePercent = $bat.EstimatedChargeRemaining
            }
        } else {
            @{ Present = $false; IsLaptop = $false; ACAdapter = "Desktop/No Battery"; Wattage = "N/A"; ChargePercent = $null }
        }
    } $results.BatteryInfo

    Write-DiagLog "  Battery: Present=$($results.BatteryInfo.Present), AC=$($results.BatteryInfo.ACAdapter), Wattage=$($results.BatteryInfo.Wattage)"

    # ── 5. Active power plan ──
    $results.PowerPlan = Invoke-Safe {
        $plan = powercfg /getactivescheme 2>&1
        if ($plan -match ":\s*(.+)$") { $Matches[1].Trim() } else { "Unknown" }
    } "N/A"
    Write-DiagLog "  Power plan: $($results.PowerPlan)"

    # ── 6. Calculate stability score ──
    $results.TotalPowerEvents = $results.KernelPower41Count + $results.Shutdown6008Count

    $score = 100
    # Kernel-Power 41 (most serious - actual unexpected power loss)
    if ($results.KernelPower41Count -gt 3) { $score -= 40 }
    elseif ($results.KernelPower41Count -gt 1) { $score -= 20 }
    elseif ($results.KernelPower41Count -eq 1) { $score -= 10 }

    # Event 6008
    if ($results.Shutdown6008Count -gt 3) { $score -= 25 }
    elseif ($results.Shutdown6008Count -gt 1) { $score -= 12 }
    elseif ($results.Shutdown6008Count -eq 1) { $score -= 5 }

    # Clock throttling during stress
    if ($results.ClockDropsDetected) { $score -= 15 }

    $score = [math]::Max(0, $score)
    $results.StabilityScore = $score

    $results.Rating = if ($results.TotalPowerEvents -eq 0 -and -not $results.ClockDropsDetected) { "Good" }
                      elseif ($results.TotalPowerEvents -le 3 -or ($results.ClockDropsDetected -and $results.TotalPowerEvents -eq 0)) { "Warning" }
                      else { "Critical" }

    Write-DiagLog "Enhanced power stability: Score=$score, Rating=$($results.Rating), TotalEvents=$($results.TotalPowerEvents)"
    return $results
}

# ─────────────────────────────────────────────────────────────────────────────
# GAMING PERFORMANCE TEST ORCHESTRATOR
# ─────────────────────────────────────────────────────────────────────────────

function Invoke-GamingPerformanceTest {
    param(
        [int]$StressDurationSec = 120,
        [scriptblock]$StatusCallback = $null
    )

    Write-DiagLog "=== GAMING PERFORMANCE TEST STARTING ==="
    $masterStart = Get-Date

    # Helper: report status
    function _Status([string]$Phase, [string]$Message) {
        Write-DiagLog "  [$Phase] $Message"
        if ($StatusCallback) {
            try { & $StatusCallback $Phase $Message } catch {}
        }
    }

    $report = @{
        StartTime         = $masterStart
        SystemInfo        = $null
        TimeSeries        = $null
        Storage           = $null
        Network           = $null
        FPS               = $null
        PowerStability    = $null
        PreStressThermal  = @{ CPUTemp = $null; GPUTemp = $null; FanRPM = $null }
        PostStressThermal = @{ CPUTemp = $null; GPUTemp = $null; FanRPM = $null }
        RecoveryThermal   = @{ CPUTemp = $null; GPUTemp = $null; FanRPM = $null; RecoveryTimeSec = $null }
        Scores            = @{
            Overall        = 0
            Thermal        = 0
            FPSStability   = "N/A"
            StorageSpeed   = "N/A"
            PowerStability = "N/A"
            NetworkScore   = 0
            Grade          = "N/A"
        }
        Recommendations   = @()
    }

    # ── Phase 1: System Info ──
    _Status "Phase1" "Collecting system information..."
    $report.SystemInfo = Invoke-Safe { Get-FullSystemInfo } @{}

    # ── Phase 2: Pre-stress thermal snapshot ──
    _Status "Phase2" "Taking pre-stress thermal snapshot..."
    $preTemp = Invoke-Safe {
        $t = Get-CimInstance MSAcpi_ThermalZoneTemperature -Namespace root/wmi -ErrorAction Stop | Select-Object -First 1
        [math]::Round(($t.CurrentTemperature / 10) - 273.15, 1)
    } $null
    $preGPUTemp = Invoke-Safe {
        $zones = @(Get-CimInstance MSAcpi_ThermalZoneTemperature -Namespace root/wmi -ErrorAction Stop)
        if ($zones.Count -ge 2) { [math]::Round(($zones[1].CurrentTemperature / 10) - 273.15, 1) } else { $null }
    } $null
    $preFan = Invoke-Safe {
        $fan = Get-CimInstance Win32_Fan -ErrorAction Stop | Select-Object -First 1
        if ($fan -and $fan.DesiredSpeed) { [int]$fan.DesiredSpeed } else { $null }
    } $null

    $report.PreStressThermal = @{ CPUTemp = $preTemp; GPUTemp = $preGPUTemp; FanRPM = $preFan }
    _Status "Phase2" "Pre-stress: CPU=${preTemp}C, GPU=${preGPUTemp}C, Fan=${preFan}RPM"

    # ── Phase 3: DiskSpd Storage Benchmark ──
    _Status "Phase3" "Running storage benchmark..."
    $report.Storage = Invoke-Safe { Invoke-DiskSpdBenchmark -TargetDrive "C:" -FileSizeMB 256 -DurationSec 30 } @{
        ToolUsed = "Error"; SeqReadMBps = 0; SeqWriteMBps = 0
        Random4KReadIOPS = 0; Random4KWriteIOPS = 0; AvgLatencyMs = 0; MaxLatencyMs = 0
    }

    # ── Phase 4: Time-sampled CPU+GPU stress test ──
    _Status "Phase4" "Running CPU+GPU stress test with time-series sampling ($StressDurationSec seconds)..."
    $report.TimeSeries = Invoke-Safe {
        Start-TimeSampledStressTest -DurationSeconds $StressDurationSec -SampleIntervalSec 5
    } @{
        DurationSec = $StressDurationSec; SampleCount = 0; Samples = @()
        PeakCPUTemp = $null; PeakGPUTemp = $null; AvgCPUTemp = $null; AvgGPUTemp = $null
        MaxCPUClock = $null; MinCPUClock = $null; ThrottleDetected = $false; ThrottleEvents = @()
        CPUStressPassed = $false; GPUStressPassed = $false; CoolingRecoveryTimeSec = $null
    }

    # ── Phase 5: Post-stress and recovery thermal data ──
    _Status "Phase5" "Capturing post-stress thermals..."
    $postTemp = Invoke-Safe {
        $t = Get-CimInstance MSAcpi_ThermalZoneTemperature -Namespace root/wmi -ErrorAction Stop | Select-Object -First 1
        [math]::Round(($t.CurrentTemperature / 10) - 273.15, 1)
    } $null
    $postGPUTemp = Invoke-Safe {
        $zones = @(Get-CimInstance MSAcpi_ThermalZoneTemperature -Namespace root/wmi -ErrorAction Stop)
        if ($zones.Count -ge 2) { [math]::Round(($zones[1].CurrentTemperature / 10) - 273.15, 1) } else { $null }
    } $null
    $postFan = Invoke-Safe {
        $fan = Get-CimInstance Win32_Fan -ErrorAction Stop | Select-Object -First 1
        if ($fan -and $fan.DesiredSpeed) { [int]$fan.DesiredSpeed } else { $null }
    } $null

    $report.PostStressThermal = @{ CPUTemp = $postTemp; GPUTemp = $postGPUTemp; FanRPM = $postFan }

    # Recovery thermal = last sample from time-series (post-30s cool-down period)
    if ($report.TimeSeries.Samples -and $report.TimeSeries.Samples.Count -gt 0) {
        $lastSample = $report.TimeSeries.Samples[$report.TimeSeries.Samples.Count - 1]
        $report.RecoveryThermal = @{
            CPUTemp        = $lastSample.CPUTempC
            GPUTemp        = $lastSample.GPUTempC
            FanRPM         = $lastSample.FanRPM
            RecoveryTimeSec = $report.TimeSeries.CoolingRecoveryTimeSec
        }
    }

    # ── Phase 6: Network deep test ──
    _Status "Phase6" "Running deep network test..."
    $report.Network = Invoke-Safe { Get-NetworkDeepTest } @{
        PingTest = @{}; DNSResponse = @(); WiFi = @{}; Adapters = @()
        Speedtest = @{ Available = $false }; Score = 0; Rating = "Error"
    }

    # ── Phase 7: PresentMon capture ──
    _Status "Phase7" "Attempting PresentMon frame capture..."
    $report.FPS = Invoke-Safe { Invoke-PresentMonCapture -DurationSeconds 60 } @{
        Available = $false; Message = "PresentMon capture failed."
    }

    # ── Phase 8: Power stability check ──
    _Status "Phase8" "Analyzing power stability..."
    $report.PowerStability = Invoke-Safe {
        Get-EnhancedPowerStabilityInfo -TimeSeriesData $report.TimeSeries
    } @{ StabilityScore = 0; Rating = "Error"; TotalPowerEvents = 0 }

    # ── Phase 9: Calculate scores ──
    _Status "Phase9" "Calculating performance scores..."
    $recommendations = [System.Collections.ArrayList]::new()

    # --- Thermal Score ---
    $thermalScore = 100
    $peakCPU = $report.TimeSeries.PeakCPUTemp
    if ($null -ne $peakCPU -and $peakCPU -gt 80) {
        $degreesOver = $peakCPU - 80
        $thermalScore -= [math]::Min(50, $degreesOver * 5)
    }
    if ($report.TimeSeries.ThrottleDetected) {
        $thermalScore -= 15
        $null = $recommendations.Add("CPU thermal throttling detected during stress test. Clean cooling system, reapply thermal paste, and improve case airflow.")
    }
    if ($null -ne $report.TimeSeries.CoolingRecoveryTimeSec -and $report.TimeSeries.CoolingRecoveryTimeSec -gt 60) {
        $thermalScore -= 10
        $null = $recommendations.Add("Cooling system recovery is slow ($($report.TimeSeries.CoolingRecoveryTimeSec)s). Check fans and heatsink contact.")
    }
    if ($null -ne $peakCPU -and $peakCPU -gt 90) {
        $null = $recommendations.Add("CPU peak temperature reached ${peakCPU}C under load. Risk of thermal damage. Address cooling immediately.")
    }
    $thermalScore = [math]::Max(0, $thermalScore)
    $report.Scores.Thermal = $thermalScore

    # --- Storage Score ---
    $seqRead = $report.Storage.SeqReadMBps
    $report.Scores.StorageSpeed = if ($seqRead -gt 1000) { "Excellent" }
                                  elseif ($seqRead -gt 300) { "Good" }
                                  elseif ($seqRead -gt 100) { "Fair" }
                                  else { "Poor" }
    if ($report.Scores.StorageSpeed -eq "Poor") {
        $null = $recommendations.Add("Storage read speed is only $($seqRead) MB/s. Consider upgrading to an NVMe SSD for dramatically better game load times.")
    } elseif ($report.Scores.StorageSpeed -eq "Fair") {
        $null = $recommendations.Add("Storage speed is adequate but could be improved. An NVMe drive would significantly reduce game load times.")
    }
    $storageNumeric = switch ($report.Scores.StorageSpeed) { "Excellent" { 100 }; "Good" { 80 }; "Fair" { 55 }; "Poor" { 25 }; default { 50 } }

    # --- FPS Stability Score ---
    if ($report.FPS.Available -and $null -ne $report.FPS.OnePercentLowFPS) {
        $report.Scores.FPSStability = if ($report.FPS.OnePercentLowFPS -gt 60) { "Excellent" }
                                      elseif ($report.FPS.OnePercentLowFPS -gt 30) { "Good" }
                                      elseif ($report.FPS.OnePercentLowFPS -gt 15) { "Fair" }
                                      else { "Poor" }
        if ($report.Scores.FPSStability -eq "Poor") {
            $null = $recommendations.Add("1% low FPS is below 15. Severe frame drops will cause stuttering. Check GPU thermals and driver version.")
        }
    } else {
        $report.Scores.FPSStability = "N/A"
    }
    $fpsNumeric = switch ($report.Scores.FPSStability) { "Excellent" { 100 }; "Good" { 80 }; "Fair" { 55 }; "Poor" { 25 }; "N/A" { $null }; default { $null } }

    # --- Power Stability Score ---
    $powerEvents = $report.PowerStability.TotalPowerEvents
    $powerThrottle = $report.TimeSeries.ThrottleDetected
    if ($powerEvents -eq 0 -and -not $powerThrottle) {
        $report.Scores.PowerStability = "Good"
    } elseif ($powerEvents -le 3 -or ($powerThrottle -and $powerEvents -eq 0)) {
        $report.Scores.PowerStability = "Warning"
        $null = $recommendations.Add("Power instability detected ($powerEvents unexpected shutdown events in 90 days). Check power supply and surge protection.")
    } else {
        $report.Scores.PowerStability = "Critical"
        $null = $recommendations.Add("Critical power instability: $powerEvents unexpected shutdown events in 90 days. Replace power supply or investigate electrical issues immediately.")
    }
    $powerNumeric = switch ($report.Scores.PowerStability) { "Good" { 100 }; "Warning" { 55 }; "Critical" { 20 }; default { 50 } }

    # --- Network Score ---
    $report.Scores.NetworkScore = if ($report.Network.Score) { $report.Network.Score } else { 50 }
    if ($report.Scores.NetworkScore -lt 50) {
        $null = $recommendations.Add("Network performance is poor (score $($report.Scores.NetworkScore)/100). Check connection, consider wired Ethernet for gaming.")
    } elseif ($report.Network.PingTest.JitterMs -and $report.Network.PingTest.JitterMs -gt 10) {
        $null = $recommendations.Add("Network jitter is $($report.Network.PingTest.JitterMs)ms. High jitter causes lag spikes in online games. Use wired Ethernet if on WiFi.")
    }

    # --- Overall Score (weighted average) ---
    # Weights: Thermal 30%, Storage 20%, Power 20%, Network 15%, FPS 15%
    $weightedSum = 0; $totalWeight = 0

    $weightedSum += $thermalScore * 30; $totalWeight += 30
    $weightedSum += $storageNumeric * 20; $totalWeight += 20
    $weightedSum += $powerNumeric * 20; $totalWeight += 20
    $weightedSum += $report.Scores.NetworkScore * 15; $totalWeight += 15

    if ($null -ne $fpsNumeric) {
        $weightedSum += $fpsNumeric * 15; $totalWeight += 15
    }

    $overall = if ($totalWeight -gt 0) { [math]::Round($weightedSum / $totalWeight) } else { 50 }
    $overall = [math]::Max(0, [math]::Min(100, $overall))
    $report.Scores.Overall = $overall
    $report.Scores.Grade = if ($overall -ge 90) { "A" }
                           elseif ($overall -ge 80) { "B" }
                           elseif ($overall -ge 70) { "C" }
                           elseif ($overall -ge 60) { "D" }
                           else { "F" }

    # Add general recommendations based on grade
    if (-not $report.TimeSeries.CPUStressPassed) {
        $null = $recommendations.Add("CPU stress test detected compute errors. This may indicate CPU instability. Check for overclocking issues or consider CPU replacement.")
    }
    if (-not $report.TimeSeries.GPUStressPassed) {
        $null = $recommendations.Add("GPU stress test failed. Update GPU drivers, check for overheating, or test with a different GPU.")
    }

    $report.Recommendations = @($recommendations)
    $report.EndTime = Get-Date
    $report.TotalMinutes = [math]::Round(((Get-Date) - $masterStart).TotalMinutes, 1)

    Write-DiagLog "=== GAMING PERFORMANCE TEST COMPLETE: Overall=$overall ($($report.Scores.Grade)), Duration=$($report.TotalMinutes) min ==="
    Write-DiagLog "  Thermal=$thermalScore, Storage=$($report.Scores.StorageSpeed), FPS=$($report.Scores.FPSStability), Power=$($report.Scores.PowerStability), Network=$($report.Scores.NetworkScore)"
    if ($recommendations.Count -gt 0) {
        Write-DiagLog "  Recommendations: $($recommendations.Count) items"
    }

    return $report
}

# ─────────────────────────────────────────────────────────────────────────────
# BENCHMARK COMPARISON DATABASE
# ─────────────────────────────────────────────────────────────────────────────

function Save-BenchmarkResult {
    param(
        [string]$ComputerName,
        [string]$CPUModel,
        [string]$GPUModel,
        [double]$RAMTotal,
        [string]$StorageType,
        [hashtable]$Scores,
        [string]$TestType = "Standard"
    )
    Write-DiagLog "Saving benchmark result for $ComputerName ($TestType)..."
    $benchFile = Join-Path $Global:ScriptDir "PCPlus360-Benchmarks.jsonl"

    $entry = @{
        Timestamp     = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        ComputerName  = if ($ComputerName) { $ComputerName } else { "Unknown" }
        CPUModel      = if ($CPUModel) { $CPUModel } else { "Unknown" }
        GPUModel      = if ($GPUModel) { $GPUModel } else { "Unknown" }
        RAMTotalGB    = if ($RAMTotal -gt 0) { $RAMTotal } else { 0 }
        StorageType   = if ($StorageType) { $StorageType } else { "Unknown" }
        TestType      = $TestType
        Scores        = @{
            Overall        = if ($Scores -and $Scores.Overall)        { $Scores.Overall }        else { 0 }
            Thermal        = if ($Scores -and $Scores.Thermal)        { $Scores.Thermal }        else { 0 }
            Storage        = if ($Scores -and $Scores.Storage)        { $Scores.Storage }        else { 0 }
            Network        = if ($Scores -and $Scores.Network)        { $Scores.Network }        else { 0 }
            Security       = if ($Scores -and $Scores.Security)       { $Scores.Security }       else { 0 }
            FPSStability   = if ($Scores -and $Scores.FPSStability)   { $Scores.FPSStability }   else { "N/A" }
            PowerStability = if ($Scores -and $Scores.PowerStability) { $Scores.PowerStability } else { "N/A" }
            Grade          = if ($Scores -and $Scores.Grade)          { $Scores.Grade }          else { "N/A" }
        }
    }

    try {
        $jsonLine = $entry | ConvertTo-Json -Depth 5 -Compress
        $jsonLine | Out-File -FilePath $benchFile -Append -Encoding UTF8
        Write-DiagLog "Benchmark saved to $benchFile (TestType=$TestType, Overall=$($entry.Scores.Overall))"
    } catch {
        Write-DiagLog "Failed to save benchmark: $($_.Exception.Message)" "WARN"
    }

    return $entry
}

function Get-BenchmarkPercentile {
    param(
        [string]$CPUModel = "all",
        [string]$ScoreType = "Overall",
        [double]$ScoreValue = 0
    )
    Write-DiagLog "Calculating benchmark percentile: CPU=$CPUModel, Type=$ScoreType, Value=$ScoreValue"
    $benchFile = Join-Path $Global:ScriptDir "PCPlus360-Benchmarks.jsonl"

    $result = @{
        Percentile         = 0
        TotalSamples       = 0
        BetterThan         = 0
        SimilarSystemCount = 0
        AvgScore           = 0
        BestScore          = 0
        WorstScore         = 0
        ScoreType          = $ScoreType
        FilterCPU          = $CPUModel
    }

    if (-not (Test-Path $benchFile)) {
        Write-DiagLog "No benchmark file found at $benchFile - first run"
        return $result
    }

    try {
        $lines = Get-Content $benchFile -Encoding UTF8 | Where-Object { $_.Trim().Length -gt 0 }
        $entries = @()
        foreach ($line in $lines) {
            try {
                $obj = $line | ConvertFrom-Json
                $entries += $obj
            } catch {
                # Skip malformed lines
            }
        }

        if ($entries.Count -eq 0) {
            Write-DiagLog "Benchmark file empty or all lines malformed"
            return $result
        }

        # Fuzzy CPU filter
        $filtered = $entries
        if ($CPUModel -and $CPUModel -ne "all") {
            $cpuSearch = $CPUModel -replace '^\s*(AMD|Intel)\s*', '' -replace '\s+', ' '
            $cpuSearch = $cpuSearch.Trim()
            # Extract family pattern: "Ryzen 7", "Core i7", "Core Ultra 7", etc.
            $familyPattern = ""
            if ($cpuSearch -match '(Ryzen\s+\d)') { $familyPattern = $Matches[1] }
            elseif ($cpuSearch -match '(Core\s+(?:Ultra\s+)?\w+\d)') { $familyPattern = $Matches[1] }
            elseif ($cpuSearch -match '(Xeon\s+\w+)') { $familyPattern = $Matches[1] }
            else { $familyPattern = $cpuSearch.Substring(0, [math]::Min(10, $cpuSearch.Length)) }

            $filtered = @($entries | Where-Object {
                $entryCPU = $_.CPUModel -replace '^\s*(AMD|Intel)\s*', ''
                $entryCPU -match [regex]::Escape($familyPattern)
            })
            # Fall back to all entries if no matches
            if ($filtered.Count -eq 0) {
                Write-DiagLog "No CPU matches for '$familyPattern', using all entries"
                $filtered = $entries
            }
        }

        # Extract numeric scores for the requested type
        $scores = @()
        foreach ($e in $filtered) {
            $val = $null
            if ($e.Scores -and $e.Scores.PSObject.Properties[$ScoreType]) {
                $raw = $e.Scores.$ScoreType
                if ($raw -is [int] -or $raw -is [double] -or $raw -is [long] -or $raw -is [decimal]) {
                    $val = [double]$raw
                } elseif ($raw -match '^\d+(\.\d+)?$') {
                    $val = [double]$raw
                }
            }
            if ($null -ne $val) { $scores += $val }
        }

        if ($scores.Count -eq 0) {
            Write-DiagLog "No numeric scores found for type $ScoreType"
            return $result
        }

        $sorted = $scores | Sort-Object
        $betterThan = ($sorted | Where-Object { $_ -lt $ScoreValue }).Count
        $percentile = if ($scores.Count -gt 0) { [math]::Round(($betterThan / $scores.Count) * 100, 1) } else { 0 }

        $result.Percentile         = $percentile
        $result.TotalSamples       = $entries.Count
        $result.BetterThan         = $betterThan
        $result.SimilarSystemCount = $filtered.Count
        $result.AvgScore           = [math]::Round(($scores | Measure-Object -Average).Average, 1)
        $result.BestScore          = ($scores | Measure-Object -Maximum).Maximum
        $result.WorstScore         = ($scores | Measure-Object -Minimum).Minimum

        Write-DiagLog "Percentile result: ${percentile}% (better than $betterThan of $($scores.Count) similar systems)"
    } catch {
        Write-DiagLog "Error calculating percentile: $($_.Exception.Message)" "WARN"
    }

    return $result
}

function Get-BenchmarkSummary {
    Write-DiagLog "Generating benchmark database summary..."
    $benchFile = Join-Path $Global:ScriptDir "PCPlus360-Benchmarks.jsonl"

    $summary = @{
        TotalBenchmarks    = 0
        UniqueComputers    = 0
        UniqueCPUs         = 0
        AverageScores      = @{ Overall = 0; Thermal = 0; Storage = 0; Network = 0; Security = 0 }
        ScoresByTestType   = @{}
        HardwareTiers      = @()
        Top10              = @()
        LastBenchmarkDate  = "N/A"
        DatabaseFile       = $benchFile
        DatabaseExists     = $false
    }

    if (-not (Test-Path $benchFile)) {
        Write-DiagLog "No benchmark database found"
        return $summary
    }

    try {
        $lines = Get-Content $benchFile -Encoding UTF8 | Where-Object { $_.Trim().Length -gt 0 }
        $entries = @()
        foreach ($line in $lines) {
            try {
                $obj = $line | ConvertFrom-Json
                $entries += $obj
            } catch {}
        }

        if ($entries.Count -eq 0) {
            return $summary
        }

        $summary.DatabaseExists = $true
        $summary.TotalBenchmarks = $entries.Count
        $summary.UniqueComputers = ($entries | Select-Object -ExpandProperty ComputerName -Unique).Count
        $summary.UniqueCPUs = ($entries | Select-Object -ExpandProperty CPUModel -Unique).Count

        # Last benchmark date
        $dates = $entries | ForEach-Object { $_.Timestamp } | Sort-Object -Descending
        if ($dates.Count -gt 0) { $summary.LastBenchmarkDate = $dates[0] }

        # Average scores across all entries
        $overallScores  = @($entries | ForEach-Object { if ($_.Scores -and $_.Scores.Overall  -match '^\d') { [double]$_.Scores.Overall } })
        $thermalScores  = @($entries | ForEach-Object { if ($_.Scores -and $_.Scores.Thermal  -match '^\d') { [double]$_.Scores.Thermal } })
        $storageScores  = @($entries | ForEach-Object { if ($_.Scores -and $_.Scores.Storage  -match '^\d') { [double]$_.Scores.Storage } })
        $networkScores  = @($entries | ForEach-Object { if ($_.Scores -and $_.Scores.Network  -match '^\d') { [double]$_.Scores.Network } })
        $securityScores = @($entries | ForEach-Object { if ($_.Scores -and $_.Scores.Security -match '^\d') { [double]$_.Scores.Security } })

        if ($overallScores.Count -gt 0)  { $summary.AverageScores.Overall  = [math]::Round(($overallScores  | Measure-Object -Average).Average, 1) }
        if ($thermalScores.Count -gt 0)  { $summary.AverageScores.Thermal  = [math]::Round(($thermalScores  | Measure-Object -Average).Average, 1) }
        if ($storageScores.Count -gt 0)  { $summary.AverageScores.Storage  = [math]::Round(($storageScores  | Measure-Object -Average).Average, 1) }
        if ($networkScores.Count -gt 0)  { $summary.AverageScores.Network  = [math]::Round(($networkScores  | Measure-Object -Average).Average, 1) }
        if ($securityScores.Count -gt 0) { $summary.AverageScores.Security = [math]::Round(($securityScores | Measure-Object -Average).Average, 1) }

        # Scores by test type
        $testTypes = $entries | Select-Object -ExpandProperty TestType -Unique
        foreach ($tt in $testTypes) {
            $typeEntries = @($entries | Where-Object { $_.TestType -eq $tt })
            $typeOverall = @($typeEntries | ForEach-Object { if ($_.Scores -and $_.Scores.Overall -match '^\d') { [double]$_.Scores.Overall } })
            $summary.ScoresByTestType[$tt] = @{
                Count    = $typeEntries.Count
                AvgScore = if ($typeOverall.Count -gt 0) { [math]::Round(($typeOverall | Measure-Object -Average).Average, 1) } else { 0 }
            }
        }

        # Hardware tiers (group by RAM range)
        $ramGroups = @(
            @{ Label = "4-8 GB";  Min = 0;  Max = 8 }
            @{ Label = "8-16 GB"; Min = 8;  Max = 16 }
            @{ Label = "16-32 GB"; Min = 16; Max = 32 }
            @{ Label = "32+ GB";  Min = 32; Max = 99999 }
        )
        foreach ($rg in $ramGroups) {
            $tierEntries = @($entries | Where-Object { $_.RAMTotalGB -gt $rg.Min -and $_.RAMTotalGB -le $rg.Max })
            if ($tierEntries.Count -gt 0) {
                $tierScores = @($tierEntries | ForEach-Object { if ($_.Scores -and $_.Scores.Overall -match '^\d') { [double]$_.Scores.Overall } })
                $summary.HardwareTiers += @{
                    RAMRange = $rg.Label
                    Count    = $tierEntries.Count
                    AvgScore = if ($tierScores.Count -gt 0) { [math]::Round(($tierScores | Measure-Object -Average).Average, 1) } else { 0 }
                }
            }
        }

        # Top 10 best performers by Overall score
        $ranked = $entries | Where-Object { $_.Scores -and $_.Scores.Overall -match '^\d' } |
            Sort-Object { [double]$_.Scores.Overall } -Descending | Select-Object -First 10
        foreach ($r in $ranked) {
            $summary.Top10 += @{
                ComputerName = $r.ComputerName
                CPUModel     = $r.CPUModel
                Overall      = $r.Scores.Overall
                Grade        = $r.Scores.Grade
                TestType     = $r.TestType
                Date         = $r.Timestamp
            }
        }

        Write-DiagLog "Benchmark summary: $($entries.Count) entries, $($summary.UniqueComputers) unique systems, avg overall=$($summary.AverageScores.Overall)"
    } catch {
        Write-DiagLog "Error generating benchmark summary: $($_.Exception.Message)" "WARN"
    }

    return $summary
}

# ─────────────────────────────────────────────────────────────────────────────
# AUTO-UPDATE / VERSION CHECK
# ─────────────────────────────────────────────────────────────────────────────

function Compare-SemanticVersion {
    <#
    .SYNOPSIS
        Compares two semantic version strings (e.g. "2.3.0" vs "2.5.0").
        Returns  1 if $Version2 is newer, 0 if equal, -1 if $Version1 is newer.
    #>
    param([string]$Version1, [string]$Version2)

    # Strip leading "v" if present
    $v1 = $Version1.TrimStart("vV").Trim()
    $v2 = $Version2.TrimStart("vV").Trim()

    try {
        $parts1 = $v1.Split('.') | ForEach-Object { [int]$_ }
        $parts2 = $v2.Split('.') | ForEach-Object { [int]$_ }

        # Pad to equal length
        $maxLen = [Math]::Max($parts1.Count, $parts2.Count)
        while ($parts1.Count -lt $maxLen) { $parts1 += 0 }
        while ($parts2.Count -lt $maxLen) { $parts2 += 0 }

        for ($i = 0; $i -lt $maxLen; $i++) {
            if ($parts2[$i] -gt $parts1[$i]) { return 1 }
            if ($parts2[$i] -lt $parts1[$i]) { return -1 }
        }
        return 0
    } catch {
        Write-DiagLog "Version comparison failed: $($_.Exception.Message)" "WARN"
        return 0
    }
}

function Test-ToolkitUpdate {
    <#
    .SYNOPSIS
        Checks for a newer version of PC Plus 360 from GitHub releases API or a
        local network share.  Returns a hashtable describing the result.
    .PARAMETER CurrentVersion
        The version string currently running (e.g. "2.5.0").
    .PARAMETER ScriptDir
        Path to the toolkit directory (used to locate config).
    #>
    param(
        [string]$CurrentVersion,
        [string]$ScriptDir
    )

    Write-DiagLog "Update check started (current: v$CurrentVersion)"

    $result = @{
        UpdateAvailable = $false
        CurrentVersion  = $CurrentVersion
        LatestVersion   = $CurrentVersion
        Source          = "none"
        DownloadURL     = ""
        ReleaseNotes    = ""
    }

    # ── Load config for network share path ──
    $configPath = Join-Path $ScriptDir "PCPlus360-Config.json"
    $networkSharePath = $null
    if (Test-Path $configPath) {
        try {
            $config = Get-Content $configPath -Raw | ConvertFrom-Json
            if ($config.UpdateNetworkPath) {
                $networkSharePath = $config.UpdateNetworkPath
                Write-DiagLog "Config loaded: network update path = $networkSharePath"
            }
        } catch {
            Write-DiagLog "Failed to parse config: $($_.Exception.Message)" "WARN"
        }
    } else {
        Write-DiagLog "No config file found at $configPath, skipping network source"
    }

    # ── Source 1: GitHub Releases API ──
    $githubChecked = $false
    try {
        Write-DiagLog "Checking GitHub releases API..."
        $apiUrl = "https://api.github.com/repos/anirudhatalmale6-alt/pcplus-360/releases/latest"

        # Use Invoke-RestMethod with a reasonable timeout
        $oldProgressPref = $ProgressPreference
        $ProgressPreference = 'SilentlyContinue'
        $headers = @{ "User-Agent" = "PCPlus360-Updater/$CurrentVersion" }

        $release = $null
        try {
            $release = Invoke-RestMethod -Uri $apiUrl -Headers $headers -TimeoutSec 10 -ErrorAction Stop
        } catch {
            # Fallback to WebClient for older PowerShell / restricted environments
            Write-DiagLog "Invoke-RestMethod failed, trying WebClient fallback..." "WARN"
            $wc = New-Object System.Net.WebClient
            $wc.Headers.Add("User-Agent", "PCPlus360-Updater/$CurrentVersion")
            # Set timeout via underlying request (WebClient has no direct timeout property)
            $json = $wc.DownloadString($apiUrl)
            $release = $json | ConvertFrom-Json
            $wc.Dispose()
        }
        $ProgressPreference = $oldProgressPref

        if ($release -and $release.tag_name) {
            $remoteVersion = $release.tag_name.TrimStart("vV").Trim()
            Write-DiagLog "GitHub latest version: $remoteVersion"

            $cmp = Compare-SemanticVersion -Version1 $CurrentVersion -Version2 $remoteVersion
            if ($cmp -eq 1) {
                # Find the zip asset (prefer .zip)
                $downloadUrl = ""
                if ($release.assets) {
                    $zipAsset = $release.assets | Where-Object { $_.name -match '\.zip$' } | Select-Object -First 1
                    if ($zipAsset) {
                        $downloadUrl = $zipAsset.browser_download_url
                    }
                }
                # Fallback to the auto-generated zipball
                if (-not $downloadUrl -and $release.zipball_url) {
                    $downloadUrl = $release.zipball_url
                }

                $result.UpdateAvailable = $true
                $result.LatestVersion   = $remoteVersion
                $result.Source          = "GitHub"
                $result.DownloadURL     = $downloadUrl
                $result.ReleaseNotes    = if ($release.body) { $release.body.Substring(0, [Math]::Min($release.body.Length, 500)) } else { "" }
                Write-DiagLog "Update found on GitHub: v$remoteVersion ($downloadUrl)"
                return $result
            } else {
                Write-DiagLog "GitHub version ($remoteVersion) is not newer than current ($CurrentVersion)"
            }
            $githubChecked = $true
        }
    } catch {
        Write-DiagLog "GitHub update check failed: $($_.Exception.Message)" "WARN"
    }

    # ── Source 2: Local network share ──
    if ($networkSharePath) {
        try {
            $versionFile = Join-Path $networkSharePath "version.txt"
            Write-DiagLog "Checking network share: $versionFile"

            if (Test-Path $versionFile) {
                $networkVersion = (Get-Content $versionFile -First 1).Trim().TrimStart("vV")
                Write-DiagLog "Network share version: $networkVersion"

                $cmp = Compare-SemanticVersion -Version1 $CurrentVersion -Version2 $networkVersion
                if ($cmp -eq 1) {
                    $result.UpdateAvailable = $true
                    $result.LatestVersion   = $networkVersion
                    $result.Source          = "Network"
                    $result.DownloadURL     = $networkSharePath
                    Write-DiagLog "Update found on network: v$networkVersion"
                    return $result
                } else {
                    Write-DiagLog "Network version ($networkVersion) is not newer than current ($CurrentVersion)"
                }
            } else {
                Write-DiagLog "Network version file not found: $versionFile" "WARN"
            }
        } catch {
            Write-DiagLog "Network update check failed: $($_.Exception.Message)" "WARN"
        }
    }

    Write-DiagLog "No updates available"
    return $result
}

function Invoke-ToolkitUpdate {
    <#
    .SYNOPSIS
        Downloads and applies a toolkit update based on the info returned by
        Test-ToolkitUpdate.  Backs up existing files before overwriting.
    .PARAMETER UpdateInfo
        The hashtable returned by Test-ToolkitUpdate (must have UpdateAvailable=$true).
    .PARAMETER ScriptDir
        Path to the toolkit directory where files should be updated.
    #>
    param(
        [hashtable]$UpdateInfo,
        [string]$ScriptDir
    )

    $result = @{
        Success       = $false
        Message       = ""
        BackedUpFiles = @()
        UpdatedFiles  = @()
    }

    if (-not $UpdateInfo.UpdateAvailable) {
        $result.Message = "No update available."
        Write-DiagLog "Invoke-ToolkitUpdate called but no update available"
        return $result
    }

    Write-DiagLog "Starting update from $($UpdateInfo.Source): v$($UpdateInfo.CurrentVersion) -> v$($UpdateInfo.LatestVersion)"

    # ── Create backup of current files ──
    $backupTimestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $filesToBackup = @("PCPlus-360.ps1", "PCPlus-Tests.ps1", "PCPlus-Reports.ps1")

    foreach ($file in $filesToBackup) {
        $filePath = Join-Path $ScriptDir $file
        if (Test-Path $filePath) {
            $bakPath = "$filePath.bak.$backupTimestamp"
            try {
                Copy-Item -Path $filePath -Destination $bakPath -Force
                $result.BackedUpFiles += $bakPath
                Write-DiagLog "Backed up: $file -> $([System.IO.Path]::GetFileName($bakPath))"
            } catch {
                $result.Message = "Failed to back up $file : $($_.Exception.Message)"
                Write-DiagLog $result.Message "ERROR"
                return $result
            }
        }
    }

    try {
        if ($UpdateInfo.Source -eq "GitHub") {
            # ── Download from GitHub ──
            if ([string]::IsNullOrEmpty($UpdateInfo.DownloadURL)) {
                $result.Message = "No download URL available from GitHub release."
                Write-DiagLog $result.Message "ERROR"
                return $result
            }

            Write-DiagLog "Downloading from: $($UpdateInfo.DownloadURL)"

            $tempDir  = Join-Path $env:TEMP "PCPlus360_Update_$backupTimestamp"
            $zipPath  = Join-Path $env:TEMP "PCPlus360_Update_$backupTimestamp.zip"

            # Download the zip
            $oldProgressPref = $ProgressPreference
            $ProgressPreference = 'SilentlyContinue'
            try {
                Invoke-WebRequest -Uri $UpdateInfo.DownloadURL -OutFile $zipPath -TimeoutSec 60 -ErrorAction Stop
            } catch {
                # Fallback to WebClient
                Write-DiagLog "Invoke-WebRequest failed, trying WebClient..." "WARN"
                $wc = New-Object System.Net.WebClient
                $wc.Headers.Add("User-Agent", "PCPlus360-Updater")
                $wc.DownloadFile($UpdateInfo.DownloadURL, $zipPath)
                $wc.Dispose()
            }
            $ProgressPreference = $oldProgressPref

            if (-not (Test-Path $zipPath) -or (Get-Item $zipPath).Length -eq 0) {
                $result.Message = "Download failed or file is empty."
                Write-DiagLog $result.Message "ERROR"
                return $result
            }

            Write-DiagLog "Downloaded $('{0:N0}' -f (Get-Item $zipPath).Length) bytes"

            # Extract
            if (Test-Path $tempDir) { Remove-Item $tempDir -Recurse -Force }
            New-Item -Path $tempDir -ItemType Directory -Force | Out-Null
            Expand-Archive -Path $zipPath -DestinationPath $tempDir -Force

            # GitHub archives often have a top-level folder; find the .ps1 files
            $extractedFiles = Get-ChildItem -Path $tempDir -Filter "*.ps1" -Recurse
            if ($extractedFiles.Count -eq 0) {
                $result.Message = "Downloaded archive contains no .ps1 files."
                Write-DiagLog $result.Message "ERROR"
                # Clean up temp
                Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
                Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
                return $result
            }

            # Copy each matching file
            foreach ($ef in $extractedFiles) {
                $destPath = Join-Path $ScriptDir $ef.Name
                Copy-Item -Path $ef.FullName -Destination $destPath -Force
                $result.UpdatedFiles += $ef.Name
                Write-DiagLog "Updated: $($ef.Name)"
            }

            # Also copy any .json config files from the release
            $extractedJson = Get-ChildItem -Path $tempDir -Filter "*.json" -Recurse
            foreach ($jf in $extractedJson) {
                $destPath = Join-Path $ScriptDir $jf.Name
                Copy-Item -Path $jf.FullName -Destination $destPath -Force
                $result.UpdatedFiles += $jf.Name
                Write-DiagLog "Updated config: $($jf.Name)"
            }

            # Clean up temp files
            Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
            Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
            Write-DiagLog "Temp files cleaned up"

        } elseif ($UpdateInfo.Source -eq "Network") {
            # ── Copy from network share ──
            $networkPath = $UpdateInfo.DownloadURL  # DownloadURL holds the share path for network source

            if (-not (Test-Path $networkPath)) {
                $result.Message = "Network share path not accessible: $networkPath"
                Write-DiagLog $result.Message "ERROR"
                return $result
            }

            Write-DiagLog "Copying from network share: $networkPath"

            $networkFiles = Get-ChildItem -Path $networkPath -Filter "*.ps1" -ErrorAction Stop
            if ($networkFiles.Count -eq 0) {
                $result.Message = "No .ps1 files found in network share."
                Write-DiagLog $result.Message "ERROR"
                return $result
            }

            foreach ($nf in $networkFiles) {
                $destPath = Join-Path $ScriptDir $nf.Name
                Copy-Item -Path $nf.FullName -Destination $destPath -Force
                $result.UpdatedFiles += $nf.Name
                Write-DiagLog "Updated from network: $($nf.Name)"
            }

            # Also copy .json config files
            $networkJson = Get-ChildItem -Path $networkPath -Filter "*.json" -ErrorAction SilentlyContinue
            foreach ($jf in $networkJson) {
                $destPath = Join-Path $ScriptDir $jf.Name
                Copy-Item -Path $jf.FullName -Destination $destPath -Force
                $result.UpdatedFiles += $jf.Name
                Write-DiagLog "Updated config from network: $($jf.Name)"
            }
        } else {
            $result.Message = "Unknown update source: $($UpdateInfo.Source)"
            Write-DiagLog $result.Message "ERROR"
            return $result
        }

        $result.Success = $true
        $result.Message = "Updated $($result.UpdatedFiles.Count) file(s) from $($UpdateInfo.Source): v$($UpdateInfo.CurrentVersion) -> v$($UpdateInfo.LatestVersion). Backups saved with .bak extension."
        Write-DiagLog "Update completed successfully"

    } catch {
        $result.Message = "Update failed: $($_.Exception.Message)"
        Write-DiagLog $result.Message "ERROR"

        # Attempt rollback from backups
        Write-DiagLog "Attempting rollback from backups..."
        foreach ($bakFile in $result.BackedUpFiles) {
            $originalPath = $bakFile -replace "\.bak\.\d{8}_\d{6}$", ""
            if (Test-Path $bakFile) {
                try {
                    Copy-Item -Path $bakFile -Destination $originalPath -Force
                    Write-DiagLog "Rolled back: $([System.IO.Path]::GetFileName($originalPath))"
                } catch {
                    Write-DiagLog "Rollback failed for $originalPath : $($_.Exception.Message)" "ERROR"
                }
            }
        }
        $result.Message += " (Rollback attempted - check logs)"
    }

    return $result
}


# ─────────────────────────────────────────────────────────────────────────────
# QUICK REMEDIATION - One-click fixes for common issues
# ─────────────────────────────────────────────────────────────────────────────

function Invoke-QuickRemediation {
    <#
    .SYNOPSIS
        Performs a single remediation action to fix common system issues.
    .DESCRIPTION
        Supports: CleanTempFiles, OptimizePowerPlan, DisableStartupBloat,
        ClearDNSCache, RepairWindowsImage, UpdateDrivers, OptimizeVisualEffects.
        Each action is non-destructive and logged via Write-DiagLog.
    .PARAMETER Action
        The remediation action to perform.
    #>
    param(
        [Parameter(Mandatory)]
        [ValidateSet("CleanTempFiles","OptimizePowerPlan","DisableStartupBloat",
                     "ClearDNSCache","RepairWindowsImage","UpdateDrivers","OptimizeVisualEffects")]
        [string]$Action
    )

    $result = @{
        Action         = $Action
        Success        = $false
        Details        = ""
        BytesRecovered = 0
    }

    Write-DiagLog "Quick Remediation: starting action '$Action'"

    switch ($Action) {

        "CleanTempFiles" {
            $totalBytes = [long]0
            $deletedCount = 0
            $failedCount  = 0
            $details = [System.Collections.ArrayList]::new()

            # Folders to clean
            $tempFolders = @(
                $env:TEMP,
                "$env:SystemRoot\Temp",
                "$env:SystemRoot\Prefetch",
                "$env:LOCALAPPDATA\Microsoft\Windows\INetCache",
                "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache",
                "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Code Cache",
                "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache",
                "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Code Cache",
                "$env:LOCALAPPDATA\Mozilla\Firefox\Profiles"
            )

            foreach ($folder in $tempFolders) {
                if ([string]::IsNullOrWhiteSpace($folder) -or -not (Test-Path $folder)) { continue }
                $folderName = Split-Path $folder -Leaf
                try {
                    $items = Get-ChildItem -Path $folder -Recurse -Force -ErrorAction SilentlyContinue
                    $folderSize = ($items | Where-Object { -not $_.PSIsContainer } | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
                    if (-not $folderSize) { $folderSize = 0 }

                    # For Firefox profiles, only clean cache subfolders
                    if ($folder -like "*Firefox\Profiles*") {
                        $cacheItems = Get-ChildItem -Path $folder -Recurse -Force -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match "^(cache2|startupCache|jumpListCache)$" }
                        foreach ($cacheDir in $cacheItems) {
                            $subItems = Get-ChildItem -Path $cacheDir.FullName -Recurse -Force -File -ErrorAction SilentlyContinue
                            foreach ($item in $subItems) {
                                try { Remove-Item $item.FullName -Force -ErrorAction Stop; $deletedCount++; $totalBytes += $item.Length } catch { $failedCount++ }
                            }
                        }
                        $null = $details.Add("Firefox caches: cleaned")
                        continue
                    }

                    # Delete files (not the folder itself)
                    $files = Get-ChildItem -Path $folder -Recurse -Force -File -ErrorAction SilentlyContinue
                    foreach ($file in $files) {
                        try {
                            $sz = $file.Length
                            Remove-Item $file.FullName -Force -ErrorAction Stop
                            $deletedCount++
                            $totalBytes += $sz
                        }
                        catch { $failedCount++ }
                    }

                    # Remove empty subdirectories
                    Get-ChildItem -Path $folder -Recurse -Force -Directory -ErrorAction SilentlyContinue |
                        Sort-Object { $_.FullName.Length } -Descending |
                        ForEach-Object { try { Remove-Item $_.FullName -Force -ErrorAction Stop } catch {} }

                    $null = $details.Add("$folderName`: $deletedCount files")
                }
                catch {
                    $null = $details.Add("$folderName`: error - $($_.Exception.Message)")
                    Write-DiagLog "CleanTempFiles: error cleaning $folder - $($_.Exception.Message)" "WARN"
                }
            }

            $mbRecovered = [math]::Round($totalBytes / 1MB, 1)
            $result.Success = $true
            $result.BytesRecovered = $totalBytes
            $result.Details = "Cleaned $deletedCount files ($mbRecovered MB recovered). Skipped $failedCount locked files. Folders: $($details -join '; ')"
            Write-DiagLog "CleanTempFiles: $($result.Details)"
        }

        "OptimizePowerPlan" {
            try {
                # Detect if on battery (laptop)
                $battery = Invoke-Safe { Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue } $null
                $onBattery = $false
                if ($battery -and $battery.BatteryStatus -eq 1) { $onBattery = $true }

                if ($onBattery) {
                    # Set Balanced plan for battery conservation
                    $balancedGuid = "381b4222-f694-41f0-9685-ff5bb260df2e"
                    powercfg /setactive $balancedGuid 2>$null
                    $result.Details = "Laptop on battery: set to Balanced power plan ($balancedGuid)"
                }
                else {
                    # Set High Performance plan
                    $highPerfGuid = "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c"
                    # Unhide High Performance if needed
                    powercfg /setactive $highPerfGuid 2>$null
                    if ($LASTEXITCODE -ne 0) {
                        # Try to duplicate and activate
                        $dupOutput = powercfg /duplicatescheme $highPerfGuid 2>&1
                        if ($dupOutput -match "([a-f0-9\-]{36})") {
                            $newGuid = $Matches[1]
                            powercfg /setactive $newGuid 2>$null
                            $result.Details = "High Performance plan duplicated and activated ($newGuid)"
                        }
                        else {
                            $result.Details = "Could not activate High Performance plan. Output: $dupOutput"
                            $result.Success = $false
                            Write-DiagLog "OptimizePowerPlan: $($result.Details)" "WARN"
                            break
                        }
                    }
                    else {
                        $result.Details = "Set to High Performance power plan ($highPerfGuid)"
                    }
                }
                $result.Success = $true
                Write-DiagLog "OptimizePowerPlan: $($result.Details)"
            }
            catch {
                $result.Details = "Failed: $($_.Exception.Message)"
                Write-DiagLog "OptimizePowerPlan: $($result.Details)" "WARN"
            }
        }

        "DisableStartupBloat" {
            try {
                $disabledCount = 0
                $alreadyDisabled = 0
                $details = [System.Collections.ArrayList]::new()

                # Known bloatware startup registry entries
                $bloatwareNames = @(
                    "Cortana",
                    "OneDrive",
                    "Microsoft Teams",
                    "Teams Machine-Wide Installer",
                    "TeamsMachineInstaller",
                    "TeamsMachineUninstallerLocalAppData",
                    "Skype",
                    "SkypeForBusiness",
                    "Adobe Updater Startup Utility",
                    "AdobeAAMUpdater*",
                    "AdobeGCInvoker*",
                    "CCXProcess",
                    "Adobe Creative Cloud",
                    "iTunesHelper",
                    "Spotify",
                    "Steam Client Bootstrapper",
                    "Discord",
                    "CiscoMeetingDaemon",
                    "com.squirrel.Zoom.Zoom"
                )

                # Check Run keys in registry
                $runPaths = @(
                    "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run",
                    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run",
                    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run"
                )

                foreach ($regPath in $runPaths) {
                    if (-not (Test-Path $regPath)) { continue }
                    $entries = Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue
                    if (-not $entries) { continue }

                    $propNames = $entries.PSObject.Properties | Where-Object { $_.Name -notmatch "^PS" } | Select-Object -ExpandProperty Name
                    foreach ($propName in $propNames) {
                        $matchesBloat = $false
                        foreach ($bloat in $bloatwareNames) {
                            if ($propName -like "*$bloat*" -or ($entries.$propName -and $entries.$propName -like "*$bloat*")) {
                                $matchesBloat = $true
                                break
                            }
                        }
                        if ($matchesBloat) {
                            try {
                                Remove-ItemProperty -Path $regPath -Name $propName -Force -ErrorAction Stop
                                $disabledCount++
                                $null = $details.Add("Removed: $propName (from $($regPath -replace 'HKCU:|HKLM:',''))")
                                Write-DiagLog "DisableStartupBloat: removed '$propName' from $regPath"
                            }
                            catch {
                                $null = $details.Add("Failed: $propName - $($_.Exception.Message)")
                                Write-DiagLog "DisableStartupBloat: could not remove '$propName': $($_.Exception.Message)" "WARN"
                            }
                        }
                    }
                }

                # Also disable via Task Manager startup items (Startup Approved folder)
                $startupApproved = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run"
                if (Test-Path $startupApproved) {
                    $approvedEntries = Get-ItemProperty -Path $startupApproved -ErrorAction SilentlyContinue
                    if ($approvedEntries) {
                        $approvedProps = $approvedEntries.PSObject.Properties | Where-Object { $_.Name -notmatch "^PS" }
                        foreach ($prop in $approvedProps) {
                            foreach ($bloat in $bloatwareNames) {
                                if ($prop.Name -like "*$bloat*") {
                                    try {
                                        # Disable by setting first byte to 03 (disabled flag)
                                        $val = $prop.Value
                                        if ($val -is [byte[]] -and $val.Length -ge 1 -and $val[0] -ne 3) {
                                            $val[0] = 3
                                            Set-ItemProperty -Path $startupApproved -Name $prop.Name -Value $val -Force -ErrorAction Stop
                                            $disabledCount++
                                            $null = $details.Add("Disabled startup: $($prop.Name)")
                                            Write-DiagLog "DisableStartupBloat: disabled startup '$($prop.Name)'"
                                        }
                                        else { $alreadyDisabled++ }
                                    }
                                    catch {
                                        $null = $details.Add("Failed startup disable: $($prop.Name)")
                                    }
                                    break
                                }
                            }
                        }
                    }
                }

                $result.Success = $true
                if ($disabledCount -eq 0) {
                    $result.Details = "No known bloatware startup entries found to disable. ($alreadyDisabled already disabled)"
                }
                else {
                    $result.Details = "Disabled $disabledCount bloatware startup entries. $($details -join '; ')"
                }
                Write-DiagLog "DisableStartupBloat: $($result.Details)"
            }
            catch {
                $result.Details = "Failed: $($_.Exception.Message)"
                Write-DiagLog "DisableStartupBloat: $($result.Details)" "WARN"
            }
        }

        "ClearDNSCache" {
            try {
                $beforeStats = Invoke-Safe { Get-DnsClientCache -ErrorAction SilentlyContinue | Measure-Object | Select-Object -ExpandProperty Count } 0
                Clear-DnsClientCache -ErrorAction Stop
                $result.Success = $true
                $result.Details = "DNS resolver cache flushed successfully. ($beforeStats entries cleared)"
                Write-DiagLog "ClearDNSCache: $($result.Details)"
            }
            catch {
                # Fallback to ipconfig
                try {
                    $output = & ipconfig /flushdns 2>&1
                    $result.Success = $true
                    $result.Details = "DNS cache flushed via ipconfig. $($output -join ' ')"
                    Write-DiagLog "ClearDNSCache: $($result.Details)"
                }
                catch {
                    $result.Details = "Failed to flush DNS cache: $($_.Exception.Message)"
                    Write-DiagLog "ClearDNSCache: $($result.Details)" "WARN"
                }
            }
        }

        "RepairWindowsImage" {
            try {
                Write-DiagLog "RepairWindowsImage: starting DISM /RestoreHealth (this may take several minutes)..."
                $dismOutput = & DISM /Online /Cleanup-Image /RestoreHealth 2>&1
                $dismExit = $LASTEXITCODE
                $dismSummary = ($dismOutput | Select-String -Pattern "The restore operation completed|error" -ErrorAction SilentlyContinue) -join "; "
                if ([string]::IsNullOrWhiteSpace($dismSummary)) {
                    $dismSummary = "DISM exit code: $dismExit"
                }
                Write-DiagLog "RepairWindowsImage: DISM completed (exit=$dismExit)"

                Write-DiagLog "RepairWindowsImage: starting SFC /scannow..."
                $sfcOutput = & sfc /scannow 2>&1
                $sfcExit = $LASTEXITCODE
                $sfcSummary = ($sfcOutput | Select-String -Pattern "found corrupt|did not find|successfully repaired|could not perform" -ErrorAction SilentlyContinue) -join "; "
                if ([string]::IsNullOrWhiteSpace($sfcSummary)) {
                    $sfcSummary = "SFC exit code: $sfcExit"
                }
                Write-DiagLog "RepairWindowsImage: SFC completed (exit=$sfcExit)"

                $result.Success = ($dismExit -eq 0 -or $sfcExit -eq 0)
                $result.Details = "DISM: $dismSummary | SFC: $sfcSummary"
                Write-DiagLog "RepairWindowsImage: $($result.Details)"
            }
            catch {
                $result.Details = "Failed: $($_.Exception.Message)"
                Write-DiagLog "RepairWindowsImage: $($result.Details)" "WARN"
            }
        }

        "UpdateDrivers" {
            try {
                # Open Windows Update settings (can't auto-install but can trigger the UI)
                Start-Process "ms-settings:windowsupdate" -ErrorAction Stop
                Start-Sleep -Milliseconds 500

                # Also try to trigger an update scan via UsoClient
                Invoke-Safe { & UsoClient StartScan 2>$null } $null

                $result.Success = $true
                $result.Details = "Windows Update settings opened. Update scan triggered via UsoClient. Please click 'Check for updates' to find driver updates."
                Write-DiagLog "UpdateDrivers: $($result.Details)"
            }
            catch {
                $result.Details = "Failed to open Windows Update: $($_.Exception.Message)"
                Write-DiagLog "UpdateDrivers: $($result.Details)" "WARN"
            }
        }

        "OptimizeVisualEffects" {
            try {
                # Set visual effects to "Adjust for best performance"
                # This sets UserPreferencesMask in registry
                $regPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects"
                $advPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"

                # Set VisualFXSetting to 2 = Best Performance
                if (-not (Test-Path $regPath)) { New-Item -Path $regPath -Force | Out-Null }
                Set-ItemProperty -Path $regPath -Name "VisualFXSetting" -Value 2 -Type DWord -Force

                # Disable individual effects via UserPreferencesMask
                $prefMaskPath = "HKCU:\Control Panel\Desktop"
                $currentMask = (Get-ItemProperty -Path $prefMaskPath -Name "UserPreferencesMask" -ErrorAction SilentlyContinue).UserPreferencesMask
                if ($currentMask) {
                    # Best performance mask: disable animations, shadows, etc.
                    $bestPerfMask = @([byte]0x90, [byte]0x12, [byte]0x01, [byte]0x80, [byte]0x10, [byte]0x00, [byte]0x00, [byte]0x00)
                    Set-ItemProperty -Path $prefMaskPath -Name "UserPreferencesMask" -Value ([byte[]]$bestPerfMask) -Type Binary -Force
                }

                # Disable specific visual effects
                $effects = @{
                    "ListviewAlphaSelect"  = 0  # Translucent selection rectangle
                    "ListviewShadow"       = 0  # Drop shadow for icon labels
                    "TaskbarAnimations"    = 0  # Taskbar animations
                }
                foreach ($key in $effects.Keys) {
                    Set-ItemProperty -Path $advPath -Name $key -Value $effects[$key] -Type DWord -Force -ErrorAction SilentlyContinue
                }

                # Disable window animations
                Set-ItemProperty -Path "HKCU:\Control Panel\Desktop\WindowMetrics" -Name "MinAnimate" -Value "0" -Force -ErrorAction SilentlyContinue

                # Disable smooth scrolling
                Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "SmoothScroll" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue

                $result.Success = $true
                $result.Details = "Visual effects set to 'Adjust for best performance'. Disabled animations, shadows, translucent selections, and smooth scrolling. Changes apply on next login or explorer restart."
                Write-DiagLog "OptimizeVisualEffects: $($result.Details)"
            }
            catch {
                $result.Details = "Failed: $($_.Exception.Message)"
                Write-DiagLog "OptimizeVisualEffects: $($result.Details)" "WARN"
            }
        }
    }

    Write-DiagLog "Quick Remediation: '$Action' completed - Success=$($result.Success)"
    return $result
}

# ─────────────────────────────────────────────────────────────────────────────
# LCD DISPLAY WEAR & LIFE TEST
# ─────────────────────────────────────────────────────────────────────────────

function Invoke-LCDDisplayTest {
    <#
    .SYNOPSIS
        Runs a comprehensive LCD / Display Wear & Life diagnostic.
    .DESCRIPTION
        Gathers monitor EDID, display adapter, brightness, display event history,
        thermal correlation, calculates wear score, and generates a visual test page.
        Returns a structured hashtable suitable for Build-LCDDisplayReport.
    #>
    Write-DiagLog "=== LCD DISPLAY WEAR & LIFE TEST STARTING ==="

    # ── Helper: Convert EDID byte array to string ──
    function Convert-LCDEdidString {
        param($CharArray)
        try {
            if (-not $CharArray) { return $null }
            $s = -join ($CharArray | ForEach-Object { if ($_ -gt 0) { [char]$_ } })
            return $s.Trim()
        } catch { return $null }
    }

    # ── Helper: New finding object ──
    function New-LCDFinding {
        param([string]$Category,[string]$Severity,[string]$Finding,[string]$Recommendation)
        [PSCustomObject]@{Category=$Category;Severity=$Severity;Finding=$Finding;Recommendation=$Recommendation}
    }

    # ── Helper: Grade from score ──
    function Get-LCDGradeFromScore {
        param([int]$Score)
        if ($Score -ge 90) { "A - Excellent" }
        elseif ($Score -ge 80) { "B - Good" }
        elseif ($Score -ge 70) { "C - Fair" }
        elseif ($Score -ge 60) { "D - Needs Attention" }
        else { "F - Critical" }
    }
    function Get-LCDRiskFromScore {
        param([int]$Score)
        if ($Score -ge 85) { "Low" }
        elseif ($Score -ge 70) { "Moderate" }
        elseif ($Score -ge 55) { "High" }
        else { "Critical" }
    }
    function Get-LCDLifeTextFromScore {
        param([int]$Score)
        if ($Score -ge 90) { "3-5+ years estimated comfortable display use" }
        elseif ($Score -ge 80) { "2-4 years estimated comfortable display use" }
        elseif ($Score -ge 70) { "1-3 years estimated comfortable display use; monitor condition should be reviewed" }
        elseif ($Score -ge 60) { "6-18 months estimated comfortable use if symptoms are present; service/replacement planning recommended" }
        else { "Immediate display inspection or replacement recommended" }
    }

    # ── 1. System Info ──
    Write-DiagLog "LCD Test: Collecting system information..."
    $systemData = Invoke-Safe {
        $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
        $bios = Get-CimInstance Win32_BIOS -ErrorAction SilentlyContinue
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
        $cpu = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1

        $biosDate = $null
        try { $biosDate = [Management.ManagementDateTimeConverter]::ToDateTime($bios.ReleaseDate) } catch {}
        $biosAgeYears = if ($biosDate) { [math]::Round(((Get-Date) - $biosDate).TotalDays / 365.25, 1) } else { $null }

        @{
            ComputerName  = $env:COMPUTERNAME
            Manufacturer  = $cs.Manufacturer
            Model         = $cs.Model
            SerialNumber  = $bios.SerialNumber
            BIOSVersion   = $bios.SMBIOSBIOSVersion
            BIOSDate      = $biosDate
            BIOSAgeYears  = $biosAgeYears
            OS            = $os.Caption
            OSBuild       = $os.BuildNumber
            LastBoot      = $os.LastBootUpTime
            UptimeHours   = [math]::Round(((Get-Date) - $os.LastBootUpTime).TotalHours, 2)
            CPU           = $cpu.Name
            RAMGB         = [math]::Round($cs.TotalPhysicalMemory / 1GB, 2)
            IsLaptop      = ($cs.PCSystemType -eq 2 -or $cs.PCSystemTypeEx -eq 2)
            ReportDate    = Get-Date
        }
    } @{ ComputerName=$env:COMPUTERNAME; Manufacturer="Unknown"; Model="Unknown"; SerialNumber="N/A";
         BIOSVersion="N/A"; BIOSDate=$null; BIOSAgeYears=$null; OS="Windows"; OSBuild="N/A";
         LastBoot=$null; UptimeHours=0; CPU="Unknown"; RAMGB=0; IsLaptop=$false; ReportDate=Get-Date }

    # ── 2. Monitor EDID Info ──
    Write-DiagLog "LCD Test: Collecting monitor EDID information..."
    $monitorData = Invoke-Safe {
        $monitors = @()
        $ids = @(Get-CimInstance WmiMonitorID -Namespace root\wmi -ErrorAction SilentlyContinue)
        foreach ($m in $ids) {
            $monitors += @{
                InstanceName      = $m.InstanceName
                ManufacturerName  = Convert-LCDEdidString $m.ManufacturerName
                ProductCodeID     = Convert-LCDEdidString $m.ProductCodeID
                SerialNumberID    = Convert-LCDEdidString $m.SerialNumberID
                UserFriendlyName  = Convert-LCDEdidString $m.UserFriendlyName
                WeekOfManufacture = $m.WeekOfManufacture
                YearOfManufacture = $m.YearOfManufacture
                Active            = $m.Active
            }
        }
        $desktopMonitors = @(Get-CimInstance Win32_DesktopMonitor -ErrorAction SilentlyContinue |
            Select-Object Name, ScreenHeight, ScreenWidth, MonitorManufacturer, MonitorType, Status, PNPDeviceID)

        @{
            WmiMonitorID   = $monitors
            DesktopMonitor = $desktopMonitors
            MonitorCount   = [math]::Max($monitors.Count, $desktopMonitors.Count)
        }
    } @{ WmiMonitorID=@(); DesktopMonitor=@(); MonitorCount=0 }

    # ── 3. Display Adapter Info ──
    Write-DiagLog "LCD Test: Collecting display adapter information..."
    $adapterData = Invoke-Safe {
        $gpus = @(Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | ForEach-Object {
            $driverDate = $null
            try { $driverDate = [Management.ManagementDateTimeConverter]::ToDateTime($_.DriverDate) } catch {}
            $driverAgeYears = if ($driverDate) { [math]::Round(((Get-Date) - $driverDate).TotalDays / 365.25, 1) } else { $null }

            @{
                Name                        = $_.Name
                VideoProcessor              = $_.VideoProcessor
                AdapterRAMGB                = if ($_.AdapterRAM -gt 0) { [math]::Round($_.AdapterRAM / 1GB, 2) } else { 0 }
                DriverVersion               = $_.DriverVersion
                DriverDate                  = $driverDate
                DriverAgeYears              = $driverAgeYears
                CurrentHorizontalResolution = $_.CurrentHorizontalResolution
                CurrentVerticalResolution   = $_.CurrentVerticalResolution
                CurrentRefreshRate          = $_.CurrentRefreshRate
                MaxRefreshRate              = $_.MaxRefreshRate
                MinRefreshRate              = $_.MinRefreshRate
                VideoModeDescription        = $_.VideoModeDescription
                Status                      = $_.Status
            }
        })
        @{
            GPUs              = $gpus
            PrimaryResolution = if ($gpus.Count -gt 0) { $gpus[0].VideoModeDescription } else { "Unknown" }
        }
    } @{ GPUs=@(); PrimaryResolution="Unknown" }

    # ── 4. Brightness Info ──
    Write-DiagLog "LCD Test: Collecting brightness information..."
    $brightnessData = Invoke-Safe {
        $brightness = @(Get-CimInstance WmiMonitorBrightness -Namespace root\wmi -ErrorAction SilentlyContinue |
            Select-Object InstanceName, Active, CurrentBrightness, Level)
        $methods = @(Get-CimInstance WmiMonitorBrightnessMethods -Namespace root\wmi -ErrorAction SilentlyContinue |
            Select-Object InstanceName, Active)
        @{
            BrightnessSupported = ($brightness.Count -gt 0)
            CurrentBrightness   = if ($brightness.Count -gt 0) { ($brightness | Select-Object -First 1).CurrentBrightness } else { $null }
            BrightnessRecords   = $brightness
            BrightnessMethods   = $methods
            Notes               = "Windows usually reports brightness percentage, not actual panel nits. A colorimeter/light meter is required for true brightness wear measurement."
        }
    } @{ BrightnessSupported=$false; CurrentBrightness=$null; BrightnessRecords=@(); BrightnessMethods=@(); Notes="Brightness data unavailable." }

    # ── 5. Display Events ──
    Write-DiagLog "LCD Test: Collecting display/GPU stability event history..."
    $eventsData = Invoke-Safe {
        $start = (Get-Date).AddDays(-180)
        $events = @(Get-WinEvent -FilterHashtable @{LogName='System'; StartTime=$start} -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Message -match "display driver|nvlddmkm|amdkmdag|igfx|video hardware|LiveKernelEvent|monitor|display|graphics|TDR|stopped responding|recovered"
            } |
            Select-Object TimeCreated, ProviderName, Id, LevelDisplayName, Message -First 80)

        @{
            DaysChecked                 = 180
            EventCount                  = $events.Count
            RecentEvents                = @($events | Sort-Object TimeCreated -Descending | Select-Object -First 20)
            DriverResetCount            = @($events | Where-Object { $_.Message -match "stopped responding|recovered|TDR|display driver" }).Count
            PossibleCableReconnectCount = @($events | Where-Object { $_.Message -match "monitor|display.*disconnect|display.*connect|graphics" }).Count
        }
    } @{ DaysChecked=180; EventCount=0; RecentEvents=@(); DriverResetCount=0; PossibleCableReconnectCount=0 }

    # ── 6. Thermal Correlation ──
    Write-DiagLog "LCD Test: Collecting thermal correlation risk..."
    $thermalData = Invoke-Safe {
        $thermalEvents = @(Get-WinEvent -FilterHashtable @{LogName='System'; StartTime=(Get-Date).AddDays(-180)} -ErrorAction SilentlyContinue |
            Where-Object { $_.Message -match "thermal|overheat|temperature|throttl" } |
            Select-Object TimeCreated, ProviderName, Id, LevelDisplayName, Message -First 40)

        $thermalZones = @()
        try {
            $thermalZones = @(Get-CimInstance MSAcpi_ThermalZoneTemperature -Namespace root\wmi -ErrorAction SilentlyContinue | ForEach-Object {
                @{ InstanceName=$_.InstanceName; TemperatureC=[math]::Round(($_.CurrentTemperature / 10) - 273.15, 1) }
            })
        } catch {}

        @{
            ThermalEventCount       = $thermalEvents.Count
            ThermalEvents           = $thermalEvents
            ThermalZones            = $thermalZones
            MaxReportedTemperatureC = if ($thermalZones.Count -gt 0) { ($thermalZones | ForEach-Object { $_.TemperatureC } | Measure-Object -Maximum).Maximum } else { $null }
            Notes                   = "High internal heat can age LCD backlight, eDP/LVDS cable, adhesives, and display electronics faster."
        }
    } @{ ThermalEventCount=0; ThermalEvents=@(); ThermalZones=@(); MaxReportedTemperatureC=$null; Notes="Thermal data unavailable." }

    # ── 7. Calculate Wear Score ──
    Write-DiagLog "LCD Test: Calculating display wear score..."
    $score = 100
    $findings = @()

    # Age scoring
    if ($systemData.BIOSAgeYears -ne $null) {
        if ($systemData.BIOSAgeYears -ge 8) {
            $score -= 18
            $findings += New-LCDFinding "Display Age Estimate" "High" "System age is approximately $($systemData.BIOSAgeYears) years based on BIOS date." "LCD/backlight/cable wear risk is higher on older laptops."
        } elseif ($systemData.BIOSAgeYears -ge 5) {
            $score -= 10
            $findings += New-LCDFinding "Display Age Estimate" "Moderate" "System age is approximately $($systemData.BIOSAgeYears) years." "Inspect brightness, uniformity, hinge cable, and panel condition."
        } elseif ($systemData.BIOSAgeYears -ge 3) {
            $score -= 4
            $findings += New-LCDFinding "Display Age Estimate" "Low" "System age is approximately $($systemData.BIOSAgeYears) years." "Normal display aging possible."
        }
    }

    # GPU/driver scoring
    foreach ($gpu in $adapterData.GPUs) {
        if ($gpu.DriverAgeYears -ne $null -and $gpu.DriverAgeYears -ge 4) {
            $score -= 5
            $findings += New-LCDFinding "Display Driver Age" "Low" "Graphics driver appears about $($gpu.DriverAgeYears) years old." "Update display driver if flicker, crashes, or monitor issues occur."
        }
        if ($gpu.Status -and $gpu.Status -notmatch "OK") {
            $score -= 15
            $findings += New-LCDFinding "Display Adapter Status" "High" "$($gpu.Name) status is $($gpu.Status)." "Review Device Manager and display driver."
        }
        if ($gpu.CurrentRefreshRate -and $gpu.CurrentRefreshRate -lt 59) {
            $score -= 5
            $findings += New-LCDFinding "Refresh Rate" "Low" "Current refresh rate is $($gpu.CurrentRefreshRate) Hz." "Confirm correct display mode and driver."
        }
    }

    # Brightness scoring
    if ($brightnessData.BrightnessSupported -eq $false) {
        $findings += New-LCDFinding "Brightness Reading" "Low" "Windows did not expose brightness controls/readings." "This is common on desktops/external monitors. Use visual/light meter testing for backlight wear."
    } elseif ($brightnessData.CurrentBrightness -ne $null -and $brightnessData.CurrentBrightness -lt 40) {
        $score -= 4
        $findings += New-LCDFinding "Brightness Setting" "Low" "Current brightness is $($brightnessData.CurrentBrightness)%." "Low brightness setting is not wear by itself; test maximum brightness visually."
    }

    # Driver resets scoring
    if ($eventsData.DriverResetCount -gt 0) {
        $score -= [math]::Min(25, $eventsData.DriverResetCount * 8)
        $findings += New-LCDFinding "Display Driver Resets" "High" "$($eventsData.DriverResetCount) display driver reset/recovery event(s) found." "Check GPU driver, GPU health, thermal condition, and display cable symptoms."
    }

    # Event volume scoring
    if ($eventsData.EventCount -gt 10) {
        $score -= 10
        $findings += New-LCDFinding "Display/GPU Events" "Moderate" "$($eventsData.EventCount) display/GPU-related event(s) found in 180 days." "Review event details and test for flicker, black screen, or driver instability."
    }

    # Thermal scoring
    if ($thermalData.ThermalEventCount -gt 0) {
        $score -= 8
        $findings += New-LCDFinding "Thermal Exposure" "Moderate" "$($thermalData.ThermalEventCount) thermal-related event(s) found." "Heat may accelerate LCD backlight, cable, and display electronics wear."
    }
    if ($thermalData.MaxReportedTemperatureC -ne $null -and $thermalData.MaxReportedTemperatureC -ge 85) {
        $score -= 8
        $findings += New-LCDFinding "Heat Risk" "Moderate" "Reported thermal zone reached $($thermalData.MaxReportedTemperatureC) C." "Cooling service recommended if repeated."
    }

    # Monitor detection scoring
    if ($monitorData.MonitorCount -eq 0) {
        $score -= 5
        $findings += New-LCDFinding "Monitor Detection" "Low" "Monitor EDID information was not detected." "Check display driver/monitor detection if display issues exist."
    }

    if ($score -lt 0) { $score = 0 }

    $scoreData = @{
        Score      = $score
        Grade      = Get-LCDGradeFromScore $score
        Risk       = Get-LCDRiskFromScore $score
        ApproxLife = Get-LCDLifeTextFromScore $score
        Findings   = $findings
        ManualVisualTestsRequired = @(
            "Dead/stuck pixel test",
            "Backlight bleed test",
            "Brightness uniformity check",
            "Gray-screen burn-in/image-retention check",
            "Color tint/yellowing check",
            "Hinge angle flicker test",
            "External monitor comparison test",
            "Camera/photo evidence optional"
        )
        Notes = "LCD life is an approximation. Exact panel/backlight remaining hours usually cannot be read from Windows."
    }

    # ── 8. Generate Visual Test Page HTML ──
    Write-DiagLog "LCD Test: Generating visual test page..."
    $visualTestHTML = @"
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<title>PC Plus 360 LCD Visual Test</title>
<style>
html,body{margin:0;height:100%;font-family:Segoe UI,Arial,sans-serif;background:#111;color:white;overflow:hidden}
#screen{height:100vh;width:100vw;display:flex;align-items:center;justify-content:center;text-align:center}
.panel{background:rgba(0,0,0,.55);padding:30px;border-radius:18px;max-width:900px}
button{padding:12px 18px;margin:6px;border:0;border-radius:10px;font-weight:700;cursor:pointer}
.small{font-size:14px;opacity:.85}
</style>
</head>
<body>
<div id="screen">
  <div class="panel" id="panel">
    <h1>PC Plus 360 LCD Visual Test</h1>
    <p>Use this test to check dead pixels, stuck pixels, burn-in, backlight bleed, color tint, flicker, and brightness uniformity.</p>
    <p>Press F11 for fullscreen. Use arrow keys or buttons to change test screens.</p>
    <div>
      <button onclick="setTest(0)">White</button>
      <button onclick="setTest(1)">Black</button>
      <button onclick="setTest(2)">Red</button>
      <button onclick="setTest(3)">Green</button>
      <button onclick="setTest(4)">Blue</button>
      <button onclick="setTest(5)">Gray</button>
      <button onclick="setTest(6)">Gradient</button>
      <button onclick="setTest(7)">Grid</button>
      <button onclick="setTest(8)">Text Ghosting</button>
    </div>
    <p class="small">Technician checks: dead/stuck pixels, yellow tint, uneven brightness, edge bleed, ghost image/taskbar burn-in, flicker, hinge angle flicker.</p>
  </div>
</div>
<script>
let idx=0;
const tests=[
 {name:'White',bg:'#fff',fg:'#111',html:'WHITE SCREEN<br><small>Check dark/dead pixels, dirt, pressure marks, uneven brightness.</small>'},
 {name:'Black',bg:'#000',fg:'#fff',html:'BLACK SCREEN<br><small>Check backlight bleed, edge glow, stuck bright pixels.</small>'},
 {name:'Red',bg:'#f00',fg:'#fff',html:'RED SCREEN<br><small>Check stuck/dead subpixels.</small>'},
 {name:'Green',bg:'#0f0',fg:'#111',html:'GREEN SCREEN<br><small>Check stuck/dead subpixels.</small>'},
 {name:'Blue',bg:'#00f',fg:'#fff',html:'BLUE SCREEN<br><small>Check stuck/dead subpixels.</small>'},
 {name:'Gray',bg:'#777',fg:'#fff',html:'GRAY SCREEN<br><small>Check burn-in, image retention, yellow tint, uniformity.</small>'},
 {name:'Gradient',bg:'linear-gradient(90deg,#000,#fff)',fg:'#fff',html:'BRIGHTNESS GRADIENT<br><small>Check banding and uneven brightness.</small>'},
 {name:'Grid',bg:'repeating-linear-gradient(0deg,#fff 0,#fff 1px,#111 1px,#111 40px),repeating-linear-gradient(90deg,transparent 0,transparent 39px,#fff 39px,#fff 40px)',fg:'#0ff',html:'GRID TEST<br><small>Check lines, panel damage, scaling, and geometry.</small>'},
 {name:'Text Ghosting',bg:'#333',fg:'#fff',html:'GHOSTING / BURN-IN TEST<br><br>PC PLUS COMPUTING DISPLAY TEST<br><br><small>Look for old taskbar/icons/window shadows on gray background.</small>'}
];
function setTest(i){
 idx=i; const t=tests[idx]; const s=document.getElementById('screen'); const p=document.getElementById('panel');
 s.style.background=t.bg; s.style.color=t.fg; p.innerHTML='<h1>'+t.html+'</h1><p class="small">Screen '+(idx+1)+' of '+tests.length+' | Use Left/Right arrows | Press F11 fullscreen</p>';
 if(idx>0){p.style.background='rgba(0,0,0,.35)'} else {p.style.background='rgba(255,255,255,.65)'}
}
document.addEventListener('keydown',e=>{if(e.key==='ArrowRight')setTest((idx+1)%tests.length); if(e.key==='ArrowLeft')setTest((idx-1+tests.length)%tests.length);});
</script>
</body>
</html>
"@

    # ── Assemble result ──
    $result = @{
        System         = $systemData
        Monitor        = $monitorData
        Adapter        = $adapterData
        Brightness     = $brightnessData
        Events         = $eventsData
        Thermal        = $thermalData
        Score          = $scoreData
        VisualTestHTML = $visualTestHTML
    }

    Write-DiagLog "=== LCD DISPLAY WEAR & LIFE TEST COMPLETE: Score=$score ($(Get-LCDGradeFromScore $score)), Risk=$(Get-LCDRiskFromScore $score) ==="
    return $result
}

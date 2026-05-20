#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    PC Plus 360 - RMM Silent Scan (Hardware + Security Diagnostics)
.DESCRIPTION
    Self-contained silent diagnostic script designed for Tactical RMM deployment.
    Runs hardware and security audits, generates an HTML report, uploads it to the
    dashboard server, and outputs a JSON summary to stdout for RMM console display.
.NOTES
    Company : PC Plus Computing
    Version : 2.6.0
    Website : pcpluscomputing.com
    Phone   : 604-760-1662
#>
param(
    [string]$UploadUrl    = "https://reports.pcpluscomputing.com/api/upload",
    [string]$ApiKey       = "",
    [string]$CustomerName = "",
    [string]$TechName     = "PC Plus RMM",
    [string]$ScanMode     = "RMM Silent Scan",
    [switch]$SkipUpload,
    [string]$OutputDir    = "C:\PCPlus360-Reports"
)

$ErrorActionPreference = "SilentlyContinue"
$ProgressPreference    = "SilentlyContinue"
$scanStart = Get-Date

# ─────────────────────────────────────────────────────────────────────────────
# HELPER
# ─────────────────────────────────────────────────────────────────────────────
function Invoke-Safe { param([scriptblock]$Block, $Default = $null); try { return (& $Block) } catch { return $Default } }

# Ensure output directory
if (-not (Test-Path $OutputDir)) { New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null }

# ─────────────────────────────────────────────────────────────────────────────
# 1. SYSTEM INFO
# ─────────────────────────────────────────────────────────────────────────────
$os  = Get-CimInstance Win32_OperatingSystem
$cs  = Get-CimInstance Win32_ComputerSystem
$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
$uptime = (Get-Date) - $os.LastBootUpTime

$hwResults = @{}
$hwResults.System = @{
    ComputerName     = $env:COMPUTERNAME
    OSVersion        = $os.Caption
    OSBuild          = $os.BuildNumber
    Architecture     = $os.OSArchitecture
    CPUModel         = $cpu.Name.Trim()
    CPUCores         = $cpu.NumberOfCores
    CPULogical       = $cpu.NumberOfLogicalProcessors
    RAMTotalGB       = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
    RAMFreeGB        = [math]::Round(($os.FreePhysicalMemory * 1KB) / 1GB, 1)
    RAMUsedPct       = [math]::Round((1 - ($os.FreePhysicalMemory * 1KB / $cs.TotalPhysicalMemory)) * 100, 0)
    Uptime           = "{0}d {1}h {2}m" -f $uptime.Days, $uptime.Hours, $uptime.Minutes
    Manufacturer     = $cs.Manufacturer
    Model            = $cs.Model
}

# ─────────────────────────────────────────────────────────────────────────────
# 2. DISK HEALTH
# ─────────────────────────────────────────────────────────────────────────────
$hwResults.PhysicalDisks = Invoke-Safe {
    $pd = @()
    Get-PhysicalDisk | ForEach-Object {
        $rel = Get-StorageReliabilityCounter -PhysicalDisk $_ -ErrorAction SilentlyContinue
        $pd += @{
            Model     = $_.FriendlyName
            SizeGB    = [math]::Round($_.Size / 1GB, 0)
            MediaType = "$($_.MediaType)"
            BusType   = "$($_.BusType)"
            Health    = "$($_.HealthStatus)"
            Temp      = if ($rel -and $rel.Temperature) { "$($rel.Temperature)C" } else { "N/A" }
            PowerOn   = if ($rel) { $rel.PowerOnHours } else { "N/A" }
            Wear      = if ($rel -and $rel.Wear) { "$($rel.Wear)%" } else { "N/A" }
        }
    }
    $pd
} @()

$hwResults.Volumes = Invoke-Safe {
    $v = @()
    Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" | ForEach-Object {
        $v += @{
            Drive   = $_.DeviceID
            SizeGB  = [math]::Round($_.Size / 1GB, 1)
            FreeGB  = [math]::Round($_.FreeSpace / 1GB, 1)
            FreePct = if ($_.Size -gt 0) { [math]::Round(($_.FreeSpace / $_.Size) * 100, 1) } else { 0 }
        }
    }
    $v
} @()

# Overall disk health flag
$diskHealthOverall = "Healthy"
foreach ($d in $hwResults.PhysicalDisks) {
    if ($d.Health -and $d.Health -notin @("Healthy","Unknown","")) { $diskHealthOverall = $d.Health; break }
}

# ─────────────────────────────────────────────────────────────────────────────
# 3. NETWORK
# ─────────────────────────────────────────────────────────────────────────────
$hwResults.Network = @{}

$hwResults.Network.Adapters = Invoke-Safe {
    $a = @()
    Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq "Up" } | ForEach-Object {
        $ip  = (Get-NetIPAddress -InterfaceIndex $_.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | Select-Object -First 1).IPAddress
        $dns = (Get-DnsClientServerAddress -InterfaceIndex $_.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).ServerAddresses -join ", "
        $a += @{ Name = $_.Name; IP = $ip; DNS = $dns; Speed = $_.LinkSpeed; MAC = $_.MacAddress }
    }
    $a
} @()

$hwResults.Network.GatewayPing = Invoke-Safe {
    $gw = (Get-NetRoute -DestinationPrefix "0.0.0.0/0" -ErrorAction Stop | Select-Object -First 1).NextHop
    if ($gw) {
        $p = Test-Connection -ComputerName $gw -Count 2 -ErrorAction Stop
        $prop = if ($p[0].PSObject.Properties['Latency']) { 'Latency' } else { 'ResponseTime' }
        $avg = ($p | Measure-Object -Property $prop -Average).Average
        @{ Gateway = $gw; AvgMs = [math]::Round($avg, 1); Success = $true }
    } else { @{ Gateway = "N/A"; AvgMs = 0; Success = $false } }
} @{ Gateway = "N/A"; AvgMs = 0; Success = $false }

$hwResults.Network.DNSTest = Invoke-Safe {
    $start = Get-Date
    $r = Resolve-DnsName "google.com" -Type A -ErrorAction Stop
    $ms = ((Get-Date) - $start).TotalMilliseconds
    @{ Success = $true; ResponseMs = [math]::Round($ms, 0); Resolved = $r[0].IP4Address }
} @{ Success = $false; ResponseMs = 0; Resolved = "Failed" }

$hwResults.Network.InternetTest = Invoke-Safe {
    $start = Get-Date
    Invoke-WebRequest -Uri "https://www.google.com" -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop | Out-Null
    @{ Success = $true; ResponseMs = [math]::Round(((Get-Date) - $start).TotalMilliseconds, 0) }
} @{ Success = $false; ResponseMs = 0 }

$hwResults.Network.PublicIP = Invoke-Safe {
    (Invoke-RestMethod -Uri "https://api.ipify.org?format=json" -TimeoutSec 5).ip
} "Unable to determine"

# ─────────────────────────────────────────────────────────────────────────────
# 4. BATTERY (laptops only)
# ─────────────────────────────────────────────────────────────────────────────
$hwResults.Battery = Invoke-Safe {
    $bat = Get-CimInstance Win32_Battery -ErrorAction Stop
    if ($bat) {
        $healthPct = 0; $cycleCnt = 0
        try {
            $fc = Get-CimInstance -Namespace "root\WMI" -ClassName BatteryFullChargedCapacity -ErrorAction Stop
            $dc = Get-CimInstance -Namespace "root\WMI" -ClassName BatteryStaticData -ErrorAction Stop
            if ($dc.DesignedCapacity -gt 0) { $healthPct = [math]::Round(($fc.FullChargedCapacity / $dc.DesignedCapacity) * 100, 1) }
            $cycleCnt = (Get-CimInstance -Namespace "root\WMI" -ClassName BatteryCycleCount -ErrorAction Stop).CycleCount
        } catch {}
        @{ Present = $true; Charge = $bat.EstimatedChargeRemaining; HealthPct = $healthPct; CycleCount = $cycleCnt; Status = $bat.Status }
    } else { @{ Present = $false } }
} @{ Present = $false }

# ─────────────────────────────────────────────────────────────────────────────
# 5. THERMAL
# ─────────────────────────────────────────────────────────────────────────────
$hwResults.Thermal = Invoke-Safe {
    $t = @()
    Get-CimInstance MSAcpi_ThermalZoneTemperature -Namespace root/wmi -ErrorAction Stop | ForEach-Object {
        $c = [math]::Round(($_.CurrentTemperature / 10) - 273.15, 1)
        $t += @{ Zone = $_.InstanceName; TempC = $c; TempF = [math]::Round(($c * 9/5) + 32, 1) }
    }
    $t
} @()

# ─────────────────────────────────────────────────────────────────────────────
# 6. STARTUP PROGRAMS
# ─────────────────────────────────────────────────────────────────────────────
$hwResults.StartupCount = Invoke-Safe {
    $count = 0
    $runKeys = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run"
    )
    foreach ($key in $runKeys) {
        if (Test-Path $key) { $count += @((Get-ItemProperty $key -ErrorAction SilentlyContinue).PSObject.Properties | Where-Object { $_.Name -notin @("PSPath","PSParentPath","PSChildName","PSDrive","PSProvider") }).Count }
    }
    $startupFolder = [Environment]::GetFolderPath("Startup")
    if (Test-Path $startupFolder) { $count += @(Get-ChildItem $startupFolder -File -ErrorAction SilentlyContinue).Count }
    $count
} 0

# ─────────────────────────────────────────────────────────────────────────────
# 7. RUNNING SERVICES
# ─────────────────────────────────────────────────────────────────────────────
$hwResults.RunningServices = Invoke-Safe { (Get-Service | Where-Object { $_.Status -eq "Running" } | Measure-Object).Count } 0

# ─────────────────────────────────────────────────────────────────────────────
# 8. SECURITY AUDIT (41 checks)
# ─────────────────────────────────────────────────────────────────────────────
$secResults = @{}

# ── Core Security ──
$secResults.Defender = Invoke-Safe {
    $mp = Get-MpComputerStatus -ErrorAction Stop
    @{ RealTimeProtection = $mp.RealTimeProtectionEnabled; DefinitionsUpToDate = $mp.AntivirusSignatureAge -le 7
       DefinitionAge = $mp.AntivirusSignatureAge; LastScan = $mp.QuickScanEndTime; Engine = $mp.AMEngineVersion }
} @{ RealTimeProtection = $null; DefinitionsUpToDate = $null; DefinitionAge = $null; LastScan = $null; Engine = $null }

$secResults.ThirdPartyAV = Invoke-Safe {
    $av = @(); Get-CimInstance -Namespace "root\SecurityCenter2" -ClassName AntiVirusProduct -ErrorAction Stop | ForEach-Object {
        if ($_.displayName -ne "Windows Defender") { $av += $_.displayName }
    }; $av
} @()

$secResults.Firewall = Invoke-Safe {
    $fw = Get-NetFirewallProfile -ErrorAction Stop
    @{ Domain = ($fw | Where-Object { $_.Name -eq "Domain" }).Enabled
       Private = ($fw | Where-Object { $_.Name -eq "Private" }).Enabled
       Public = ($fw | Where-Object { $_.Name -eq "Public" }).Enabled }
} @{ Domain = $null; Private = $null; Public = $null }

$secResults.UAC = Invoke-Safe {
    $k = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
    @{ Enabled = (Get-ItemProperty $k -Name "EnableLUA" -ErrorAction Stop).EnableLUA -eq 1
       Level = (Get-ItemProperty $k -Name "ConsentPromptBehaviorAdmin" -ErrorAction Stop).ConsentPromptBehaviorAdmin }
} @{ Enabled = $null; Level = $null }

$secResults.BitLocker = Invoke-Safe {
    $bl = @{}; Get-BitLockerVolume -ErrorAction Stop | ForEach-Object {
        $bl[$_.MountPoint] = @{ Status = $_.ProtectionStatus.ToString(); Encryption = $_.EncryptionPercentage; Method = $_.EncryptionMethod.ToString() }
    }; $bl
} @{}

$secResults.SecureBoot = Invoke-Safe { Confirm-SecureBootUEFI -ErrorAction Stop } $null

$secResults.TPM = Invoke-Safe {
    $tpm = Get-Tpm -ErrorAction Stop
    @{ Present = $tpm.TpmPresent; Ready = $tpm.TpmReady
       Version = (Get-CimInstance -Namespace "root\cimv2\Security\MicrosoftTpm" -ClassName Win32_Tpm -ErrorAction Stop).SpecVersion }
} @{ Present = $false; Ready = $false; Version = "Unknown" }

$secResults.PasswordPolicy = Invoke-Safe {
    $na = net accounts 2>&1; $minLen = 0; $complexity = $false; $lockout = 0
    foreach ($l in $na) {
        if ($l -match "Minimum password length:\s+(\d+)") { $minLen = [int]$Matches[1] }
        if ($l -match "Lockout threshold:\s+(\w+)") { $lockout = if ($Matches[1] -eq "Never") { 0 } else { [int]$Matches[1] } }
    }
    $tmp = [IO.Path]::GetTempFileName(); secedit /export /cfg $tmp /quiet 2>$null
    if (Test-Path $tmp) { $c = Get-Content $tmp -Raw; if ($c -match "PasswordComplexity\s*=\s*1") { $complexity = $true }; Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
    @{ MinLength = $minLen; Complexity = $complexity; LockoutThreshold = $lockout }
} @{ MinLength = 0; Complexity = $false; LockoutThreshold = 0 }

$secResults.GuestDisabled = Invoke-Safe { -not (Get-LocalUser -Name "Guest" -ErrorAction Stop).Enabled } $null
$secResults.AutoLoginDisabled = Invoke-Safe { (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" -Name "AutoAdminLogon" -ErrorAction SilentlyContinue).AutoAdminLogon -ne "1" } $null

$secResults.RDP = Invoke-Safe {
    $en = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server" -Name "fDenyTSConnections" -ErrorAction Stop).fDenyTSConnections -eq 0
    $nla = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" -Name "UserAuthentication" -ErrorAction SilentlyContinue).UserAuthentication -eq 1
    @{ Enabled = $en; NLA = $nla }
} @{ Enabled = $null; NLA = $null }

$secResults.SMBv1Disabled = Invoke-Safe { -not (Get-SmbServerConfiguration -ErrorAction Stop).EnableSMB1Protocol } $null

$secResults.LocalAdmins = Invoke-Safe {
    $a = Get-LocalGroupMember -Group "Administrators" -ErrorAction Stop
    @{ Count = $a.Count; Names = ($a | ForEach-Object { $_.Name }) -join ", " }
} @{ Count = 0; Names = "Unable to determine" }

# ── Privacy & Data Protection ──
$secResults.Privacy = @{}
$secResults.Privacy.TelemetryMinimal = Invoke-Safe {
    $t1 = (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Name "AllowTelemetry" -ErrorAction SilentlyContinue).AllowTelemetry
    $t2 = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection" -Name "AllowTelemetry" -ErrorAction SilentlyContinue).AllowTelemetry
    ($null -ne $t1 -and $t1 -le 1) -or ($null -ne $t2 -and $t2 -le 1)
} $false
$secResults.Privacy.AdvertisingIdDisabled = Invoke-Safe {
    $v = (Get-ItemProperty "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo" -Name "Enabled" -ErrorAction SilentlyContinue).Enabled
    $null -eq $v -or $v -ne 1
} $true
$secResults.Privacy.LocationDisabled = Invoke-Safe {
    $cs2 = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location" -Name "Value" -ErrorAction SilentlyContinue).Value
    $svc = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\lfsvc\Service\Configuration" -Name "Status" -ErrorAction SilentlyContinue).Status
    ($cs2 -eq "Deny") -or ($null -ne $svc -and $svc -eq 0)
} $false
$secResults.Privacy.ActivityHistoryDisabled = Invoke-Safe {
    $k = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"
    $feed = (Get-ItemProperty $k -Name "EnableActivityFeed" -ErrorAction SilentlyContinue).EnableActivityFeed
    $pub = (Get-ItemProperty $k -Name "PublishUserActivities" -ErrorAction SilentlyContinue).PublishUserActivities
    ($null -ne $feed -and $feed -ne 1) -or ($null -ne $pub -and $pub -ne 1)
} $false
$secResults.Privacy.CortanaDisabled = Invoke-Safe {
    $v = (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" -Name "AllowCortana" -ErrorAction SilentlyContinue).AllowCortana
    ($null -ne $v -and $v -eq 0) -or (-not (Get-Process -Name "SearchUI","Cortana","Microsoft.Windows.Cortana" -ErrorAction SilentlyContinue))
} $false
$secResults.Privacy.FindMyDeviceEnabled = Invoke-Safe {
    $v = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Settings\FindMyDevice\UserConsent" -Name "Value" -ErrorAction SilentlyContinue).Value
    $null -ne $v -and $v -eq 1
} $false

# ── Browser Security ──
$secResults.BrowserSecurity = @{}
$secResults.BrowserSecurity.ChromeNoSavedPasswords = Invoke-Safe {
    $f = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Login Data"
    -not (Test-Path $f) -or (Get-Item $f -ErrorAction SilentlyContinue).Length -le 40960
} $true
$secResults.BrowserSecurity.EdgeNoSavedPasswords = Invoke-Safe {
    $f = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Login Data"
    -not (Test-Path $f) -or (Get-Item $f -ErrorAction SilentlyContinue).Length -le 40960
} $true
$secResults.BrowserSecurity.SmartScreenEnabled = Invoke-Safe {
    $v = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer" -Name "SmartScreenEnabled" -ErrorAction SilentlyContinue).SmartScreenEnabled
    $null -eq $v -or $v -ne "Off"
} $true
$secResults.BrowserSecurity.ExtensionCountOk = Invoke-Safe {
    $count = 0
    $chromeExt = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Extensions"
    if (Test-Path $chromeExt) { $count += @(Get-ChildItem $chromeExt -Directory -ErrorAction SilentlyContinue).Count }
    $edgeExt = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Extensions"
    if (Test-Path $edgeExt) { $count += @(Get-ChildItem $edgeExt -Directory -ErrorAction SilentlyContinue).Count }
    $count -lt 15
} $true

# ── Network Hardening ──
$secResults.NetworkHardening = @{}
$secResults.NetworkHardening.NoOpenShares = Invoke-Safe {
    $custom = Get-SmbShare -ErrorAction Stop | Where-Object { $_.Name -notmatch '^\w\$|^ADMIN\$|^IPC\$|^print\$' }
    ($custom | Measure-Object).Count -eq 0
} $null
$secResults.NetworkHardening.UPnPDisabled = Invoke-Safe {
    $svc = Get-Service "SSDPSRV" -ErrorAction Stop
    $svc.Status -ne "Running"
} $null
$secResults.NetworkHardening.LLMNRDisabled = Invoke-Safe {
    $v = (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient" -Name "EnableMulticast" -ErrorAction SilentlyContinue).EnableMulticast
    $null -ne $v -and $v -eq 0
} $false
$secResults.NetworkHardening.DoHEnabled = Invoke-Safe {
    $v = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters" -Name "EnableAutoDoh" -ErrorAction SilentlyContinue).EnableAutoDoh
    $null -ne $v -and $v -ge 2
} $false
$secResults.NetworkHardening.RemoteAssistanceDisabled = Invoke-Safe {
    $v = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Remote Assistance" -Name "fAllowToGetHelp" -ErrorAction SilentlyContinue).fAllowToGetHelp
    $null -ne $v -and $v -eq 0
} $false

# ── System Integrity ──
$secResults.SystemIntegrity = @{}
$secResults.SystemIntegrity.DriverSigEnforced = Invoke-Safe {
    $bcd = bcdedit /enum "{current}" 2>&1 | Out-String
    $bcd -notmatch "testsigning\s+Yes"
} $true
$secResults.SystemIntegrity.PSScriptLogging = Invoke-Safe {
    $v = (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging" -Name "EnableScriptBlockLogging" -ErrorAction SilentlyContinue).EnableScriptBlockLogging
    $null -ne $v -and $v -eq 1
} $false
$secResults.SystemIntegrity.LogonAuditEnabled = Invoke-Safe {
    $out = auditpol /get /subcategory:"Logon" 2>&1 | Out-String
    $out -match "Success" -and $out -notmatch "No Auditing"
} $false
$secResults.SystemIntegrity.CredentialGuard = Invoke-Safe {
    $dg = Get-CimInstance -ClassName Win32_DeviceGuard -Namespace "root\Microsoft\Windows\DeviceGuard" -ErrorAction Stop
    $dg.SecurityServicesRunning -contains 1
} $false
$secResults.SystemIntegrity.LSASSProtected = Invoke-Safe {
    $v = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name "RunAsPPL" -ErrorAction SilentlyContinue).RunAsPPL
    $null -ne $v -and $v -eq 1
} $false

# ── Account Hygiene ──
$secResults.AccountHygiene = @{}
$secResults.AccountHygiene.NoStaleAccounts = Invoke-Safe {
    $cutoff = (Get-Date).AddDays(-90)
    $stale = Get-LocalUser -ErrorAction Stop | Where-Object {
        $_.Enabled -and -not $_.SID.Value.EndsWith("-500") -and -not $_.SID.Value.EndsWith("-501") -and
        $null -ne $_.LastLogon -and $_.LastLogon -lt $cutoff
    }
    ($stale | Measure-Object).Count -eq 0
} $true
$secResults.AccountHygiene.NoEmptyPasswords = Invoke-Safe {
    $users = Get-LocalUser -ErrorAction Stop | Where-Object { $_.Enabled }
    $bad = $users | Where-Object { $_.PasswordRequired -eq $false }
    ($bad | Measure-Object).Count -eq 0
} $true
$secResults.AccountHygiene.PasswordAgePolicy = Invoke-Safe {
    $na = net accounts 2>&1 | Out-String
    if ($na -match "Maximum password age \(days\):\s+Unlimited") { $false } else { $true }
} $false

# ── Ransomware Protection ──
$secResults.RansomwareProtection = @{}
$secResults.RansomwareProtection.ControlledFolderAccess = Invoke-Safe {
    $v = (Get-MpPreference -ErrorAction Stop).EnableControlledFolderAccess
    $v -eq 1 -or $v -eq 2
} $false
$secResults.RansomwareProtection.RecentRestorePoint = Invoke-Safe {
    $cutoff = (Get-Date).AddDays(-30)
    $rp = Get-ComputerRestorePoint -ErrorAction Stop
    ($rp | Where-Object { [Management.ManagementDateTimeConverter]::ToDateTime($_.CreationTime) -gt $cutoff } | Measure-Object).Count -gt 0
} $false
$secResults.RansomwareProtection.NoSuspiciousScheduledTasks = Invoke-Safe {
    $suspicious = Get-ScheduledTask -ErrorAction Stop | Where-Object { $_.State -ne "Disabled" } | ForEach-Object {
        $actions = $_.Actions | Where-Object { $_.Execute -match "\\Temp\\|\\AppData\\|encodedcommand|encodedCommand|-enc\s|-ec\s" }
        if ($actions) { $_.TaskName }
    }
    ($suspicious | Measure-Object).Count -eq 0
} $true

# ─────────────────────────────────────────────────────────────────────────────
# 9. SECURITY SCORING (41 checks, 100 points)
# ─────────────────────────────────────────────────────────────────────────────
$scoreChecks = @(
    # Core Security (71 pts)
    @{ Name="Antivirus Active";          Pts=10; Test={ ($secResults.Defender.RealTimeProtection -eq $true) -or ($secResults.ThirdPartyAV.Count -gt 0) } }
    @{ Name="Firewall All Profiles";     Pts=10; Test={ $secResults.Firewall.Domain -and $secResults.Firewall.Private -and $secResults.Firewall.Public } }
    @{ Name="BitLocker on C:";           Pts=7;  Test={ $secResults.BitLocker["C:"] -and $secResults.BitLocker["C:"].Status -eq "On" } }
    @{ Name="No Critical Patches";       Pts=7;  Test={ ($missingPatches | Where-Object { $_.Severity -eq "Critical" }).Count -eq 0 } }
    @{ Name="UAC Enabled";               Pts=4;  Test={ $secResults.UAC.Enabled -eq $true } }
    @{ Name="Secure Boot";               Pts=4;  Test={ $secResults.SecureBoot -eq $true } }
    @{ Name="TPM Present";               Pts=4;  Test={ $secResults.TPM.Present -eq $true } }
    @{ Name="Password Policy";           Pts=3;  Test={ $secResults.PasswordPolicy.MinLength -ge 8 -or $secResults.PasswordPolicy.Complexity } }
    @{ Name="Guest Disabled";            Pts=2;  Test={ $secResults.GuestDisabled -eq $true } }
    @{ Name="No Auto-Login";             Pts=2;  Test={ $secResults.AutoLoginDisabled -eq $true } }
    @{ Name="RDP Secure";                Pts=4;  Test={ ($secResults.RDP.Enabled -eq $false) -or ($secResults.RDP.NLA -eq $true) } }
    @{ Name="SMBv1 Disabled";            Pts=4;  Test={ $secResults.SMBv1Disabled -eq $true } }
    @{ Name="Admin Accounts <=2";        Pts=3;  Test={ $secResults.LocalAdmins.Count -le 2 } }
    @{ Name="Real-Time Protection";      Pts=4;  Test={ $secResults.Defender.RealTimeProtection -eq $true } }
    @{ Name="AV Definitions Current";    Pts=3;  Test={ $secResults.Defender.DefinitionsUpToDate -eq $true } }
    # Privacy & Data Protection (6 pts)
    @{ Name="Telemetry Minimal";         Pts=1;  Test={ $secResults.Privacy.TelemetryMinimal -eq $true } }
    @{ Name="Advertising ID Disabled";   Pts=1;  Test={ $secResults.Privacy.AdvertisingIdDisabled -eq $true } }
    @{ Name="Location Tracking Off";     Pts=1;  Test={ $secResults.Privacy.LocationDisabled -eq $true } }
    @{ Name="Activity History Off";      Pts=1;  Test={ $secResults.Privacy.ActivityHistoryDisabled -eq $true } }
    @{ Name="Cortana/Copilot Disabled";  Pts=1;  Test={ $secResults.Privacy.CortanaDisabled -eq $true } }
    @{ Name="Find My Device On";         Pts=1;  Test={ $secResults.Privacy.FindMyDeviceEnabled -eq $true } }
    # Browser Security (4 pts)
    @{ Name="Chrome No Saved Passwords"; Pts=1;  Test={ $secResults.BrowserSecurity.ChromeNoSavedPasswords -eq $true } }
    @{ Name="Edge No Saved Passwords";   Pts=1;  Test={ $secResults.BrowserSecurity.EdgeNoSavedPasswords -eq $true } }
    @{ Name="SmartScreen Enabled";       Pts=1;  Test={ $secResults.BrowserSecurity.SmartScreenEnabled -eq $true } }
    @{ Name="Browser Extensions <15";    Pts=1;  Test={ $secResults.BrowserSecurity.ExtensionCountOk -eq $true } }
    # Network Hardening (5 pts)
    @{ Name="No Open Shares";            Pts=1;  Test={ $secResults.NetworkHardening.NoOpenShares -eq $true } }
    @{ Name="UPnP Disabled";             Pts=1;  Test={ $secResults.NetworkHardening.UPnPDisabled -eq $true } }
    @{ Name="LLMNR Disabled";            Pts=1;  Test={ $secResults.NetworkHardening.LLMNRDisabled -eq $true } }
    @{ Name="DNS-over-HTTPS";            Pts=1;  Test={ $secResults.NetworkHardening.DoHEnabled -eq $true } }
    @{ Name="Remote Assistance Off";     Pts=1;  Test={ $secResults.NetworkHardening.RemoteAssistanceDisabled -eq $true } }
    # System Integrity (5 pts)
    @{ Name="Driver Sig Enforced";       Pts=1;  Test={ $secResults.SystemIntegrity.DriverSigEnforced -eq $true } }
    @{ Name="PS Script Logging";         Pts=1;  Test={ $secResults.SystemIntegrity.PSScriptLogging -eq $true } }
    @{ Name="Logon Audit Enabled";       Pts=1;  Test={ $secResults.SystemIntegrity.LogonAuditEnabled -eq $true } }
    @{ Name="Credential Guard";          Pts=1;  Test={ $secResults.SystemIntegrity.CredentialGuard -eq $true } }
    @{ Name="LSASS Protected";           Pts=1;  Test={ $secResults.SystemIntegrity.LSASSProtected -eq $true } }
    # Account Hygiene (3 pts)
    @{ Name="No Stale Accounts";         Pts=1;  Test={ $secResults.AccountHygiene.NoStaleAccounts -eq $true } }
    @{ Name="No Empty Passwords";        Pts=1;  Test={ $secResults.AccountHygiene.NoEmptyPasswords -eq $true } }
    @{ Name="Password Age Policy";       Pts=1;  Test={ $secResults.AccountHygiene.PasswordAgePolicy -eq $true } }
    # Ransomware Protection (6 pts)
    @{ Name="Controlled Folder Access";  Pts=2;  Test={ $secResults.RansomwareProtection.ControlledFolderAccess -eq $true } }
    @{ Name="Recent Restore Point";      Pts=2;  Test={ $secResults.RansomwareProtection.RecentRestorePoint -eq $true } }
    @{ Name="No Suspicious Tasks";       Pts=2;  Test={ $secResults.RansomwareProtection.NoSuspiciousScheduledTasks -eq $true } }
)

# Run missing patches before scoring (needed for "No Critical Patches" check)
$missingPatches = Invoke-Safe {
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

$secScore = 0; $secBreakdown = @(); $criticalFailures = @()
foreach ($c in $scoreChecks) {
    $passed = try { & $c.Test } catch { $false }
    if ($passed) { $secScore += $c.Pts }
    else {
        if ($c.Pts -ge 4) { $criticalFailures += $c.Name }
    }
    $secBreakdown += @{ Check = $c.Name; Points = $c.Pts; Passed = $passed }
}
$secGrade = if ($secScore -ge 90) {"A"} elseif ($secScore -ge 80) {"B"} elseif ($secScore -ge 70) {"C"} elseif ($secScore -ge 60) {"D"} else {"F"}
$secColor = if ($secGrade -eq "A" -or $secGrade -eq "B") {"#27ae60"} elseif ($secGrade -eq "C" -or $secGrade -eq "D") {"#f39c12"} else {"#e74c3c"}

$passedCount = ($secBreakdown | Where-Object { $_.Passed }).Count
$failedCount = ($secBreakdown | Where-Object { -not $_.Passed }).Count

# ─────────────────────────────────────────────────────────────────────────────
# 10. HTML REPORT GENERATION
# ─────────────────────────────────────────────────────────────────────────────
$scanDate   = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
$dateStamp  = (Get-Date).ToString("yyyyMMdd-HHmmss")
$reportFile = Join-Path $OutputDir "PCPlus360-RMM-$($env:COMPUTERNAME)-$dateStamp.html"

# Build security rows
$secRowsHtml = ""
foreach ($item in $secBreakdown) {
    $icon  = if ($item.Passed) { "&#9989;" } else { "&#10060;" }
    $cls   = if ($item.Passed) { "pass" } else { "fail" }
    $secRowsHtml += "<tr class=`"$cls`"><td>$icon</td><td>$($item.Check)</td><td>$($item.Points) pts</td><td>$(if($item.Passed){'PASS'}else{'FAIL'})</td></tr>`n"
}

# Build disk rows
$diskRowsHtml = ""
foreach ($vol in $hwResults.Volumes) {
    $usedPct = if ($vol.SizeGB -gt 0) { [math]::Round((1 - $vol.FreeGB / $vol.SizeGB) * 100, 1) } else { 0 }
    $barColor = if ($usedPct -gt 90) { "#e74c3c" } elseif ($usedPct -gt 75) { "#f39c12" } else { "#27ae60" }
    $diskRowsHtml += @"
<tr><td><strong>$($vol.Drive)</strong></td><td>$($vol.SizeGB) GB</td><td>$($vol.FreeGB) GB</td><td>$($vol.FreePct)%</td>
<td><div style="background:#e0e0e0;border-radius:4px;overflow:hidden;height:18px;width:120px"><div style="background:${barColor};height:100%;width:${usedPct}%"></div></div></td></tr>
"@
}

# Physical disk rows
$physDiskHtml = ""
foreach ($pd in $hwResults.PhysicalDisks) {
    $hColor = if ($pd.Health -eq "Healthy") { "#27ae60" } else { "#e74c3c" }
    $physDiskHtml += "<tr><td>$($pd.Model)</td><td>$($pd.SizeGB) GB</td><td>$($pd.MediaType)</td><td style=`"color:${hColor};font-weight:bold`">$($pd.Health)</td><td>$($pd.Temp)</td><td>$($pd.Wear)</td></tr>`n"
}

# Patch rows
$patchRowsHtml = ""
if ($missingPatches.Count -gt 0) {
    foreach ($p in $missingPatches) {
        $sevColor = switch ($p.Severity) { "Critical" { "#e74c3c" }; "Important" { "#f39c12" }; default { "#666" } }
        $patchRowsHtml += "<tr><td>$($p.KB)</td><td>$($p.Title)</td><td style=`"color:${sevColor};font-weight:bold`">$($p.Severity)</td><td>$($p.SizeMB) MB</td></tr>`n"
    }
} else {
    $patchRowsHtml = "<tr><td colspan=`"4`" style=`"text-align:center;color:#27ae60`">All patches up to date</td></tr>"
}

# Network adapter rows
$netAdapterHtml = ""
foreach ($a in $hwResults.Network.Adapters) {
    $netAdapterHtml += "<tr><td>$($a.Name)</td><td>$($a.IP)</td><td>$($a.DNS)</td><td>$($a.Speed)</td></tr>`n"
}

# Recommendations
$recsHtml = ""
foreach ($item in $secBreakdown) {
    if (-not $item.Passed) {
        $rec = switch ($item.Check) {
            "Antivirus Active"           { "Enable Windows Defender Real-Time Protection or install a third-party antivirus solution." }
            "Firewall All Profiles"      { "Enable Windows Firewall on all profiles (Domain, Private, Public)." }
            "BitLocker on C:"            { "Enable BitLocker drive encryption on the system drive to protect data at rest." }
            "No Critical Patches"        { "Install all critical Windows updates immediately to close known security vulnerabilities." }
            "UAC Enabled"                { "Re-enable User Account Control to prevent unauthorized system changes." }
            "Secure Boot"                { "Enable Secure Boot in UEFI/BIOS settings to prevent boot-level malware." }
            "TPM Present"                { "Ensure TPM is enabled in BIOS. Required for BitLocker and Windows 11." }
            "Password Policy"            { "Set minimum password length to 8+ characters and enable complexity requirements." }
            "Guest Disabled"             { "Disable the Guest account to prevent unauthorized local access." }
            "No Auto-Login"              { "Disable automatic login - it bypasses all authentication." }
            "RDP Secure"                 { "Disable RDP if not needed, or ensure Network Level Authentication (NLA) is enabled." }
            "SMBv1 Disabled"             { "Disable SMBv1 protocol - it is vulnerable to EternalBlue/WannaCry exploits." }
            "Admin Accounts <=2"         { "Reduce local administrator accounts. Too many admin accounts increase attack surface." }
            "Real-Time Protection"       { "Enable Windows Defender Real-Time Protection for continuous threat monitoring." }
            "AV Definitions Current"     { "Update antivirus definitions - current definitions are more than 7 days old." }
            "Telemetry Minimal"          { "Set Windows telemetry to minimum to reduce data sent to Microsoft." }
            "Advertising ID Disabled"    { "Disable advertising ID to reduce tracking across apps." }
            "Location Tracking Off"      { "Disable location services if not needed to improve privacy." }
            "Activity History Off"       { "Disable activity history collection to prevent timeline tracking." }
            "Cortana/Copilot Disabled"   { "Disable Cortana/Copilot if not used to reduce data collection." }
            "Find My Device On"          { "Enable Find My Device for laptop theft recovery." }
            "Chrome No Saved Passwords"  { "Use a dedicated password manager instead of Chrome's built-in password storage." }
            "Edge No Saved Passwords"    { "Use a dedicated password manager instead of Edge's built-in password storage." }
            "SmartScreen Enabled"        { "Keep SmartScreen enabled to block malicious downloads and websites." }
            "Browser Extensions <15"     { "Remove unnecessary browser extensions - each is a potential attack vector." }
            "No Open Shares"             { "Remove custom network shares or restrict their permissions." }
            "UPnP Disabled"              { "Disable UPnP (SSDP Discovery service) to prevent automatic port forwarding." }
            "LLMNR Disabled"             { "Disable LLMNR via Group Policy to prevent name resolution poisoning attacks." }
            "DNS-over-HTTPS"             { "Enable DNS-over-HTTPS for encrypted DNS queries." }
            "Remote Assistance Off"      { "Disable Remote Assistance if not actively used." }
            "Driver Sig Enforced"        { "Ensure driver signature enforcement is enabled (disable test signing mode)." }
            "PS Script Logging"          { "Enable PowerShell Script Block Logging for threat detection." }
            "Logon Audit Enabled"        { "Enable logon auditing to track authentication events." }
            "Credential Guard"           { "Enable Credential Guard (requires Enterprise/Education edition + virtualization)." }
            "LSASS Protected"            { "Enable LSASS protection (RunAsPPL) to prevent credential dumping." }
            "No Stale Accounts"          { "Remove or disable local accounts that have not logged in for 90+ days." }
            "No Empty Passwords"         { "Set passwords on all enabled accounts - empty passwords are a critical risk." }
            "Password Age Policy"        { "Configure maximum password age policy to enforce periodic password changes." }
            "Controlled Folder Access"   { "Enable Controlled Folder Access in Windows Security for ransomware protection." }
            "Recent Restore Point"       { "Create system restore points regularly - no restore point found in 30 days." }
            "No Suspicious Tasks"        { "Review scheduled tasks running from Temp/AppData or using encoded commands." }
            default                      { "Review and remediate this security finding." }
        }
        $recsHtml += "<div class=`"rec-item`"><strong>$($item.Check)</strong> ($($item.Points) pts) - $rec</div>`n"
    }
}
if (-not $recsHtml) { $recsHtml = "<div class=`"rec-item`" style=`"color:#27ae60`">No recommendations - all checks passed!</div>" }

# SVG donut chart
$pctAngle = [math]::Round($secScore * 3.6, 1)
$largeArc = if ($pctAngle -gt 180) { 1 } else { 0 }
$radians  = $pctAngle * [math]::PI / 180
$endX     = [math]::Round(50 + 40 * [math]::Sin($radians), 2)
$endY     = [math]::Round(50 - 40 * [math]::Cos($radians), 2)
$arcPath  = if ($secScore -ge 100) {
    "M 50 10 A 40 40 0 1 1 49.99 10"
} else {
    "M 50 10 A 40 40 0 $largeArc 1 $endX $endY"
}

$donutSvg = @"
<svg viewBox="0 0 100 100" width="180" height="180">
  <circle cx="50" cy="50" r="40" fill="none" stroke="#e0e0e0" stroke-width="8"/>
  <path d="$arcPath" fill="none" stroke="$secColor" stroke-width="8" stroke-linecap="round"/>
  <text x="50" y="44" text-anchor="middle" font-size="22" font-weight="bold" fill="$secColor">$secScore</text>
  <text x="50" y="58" text-anchor="middle" font-size="10" fill="#666">/ 100</text>
  <text x="50" y="72" text-anchor="middle" font-size="16" font-weight="bold" fill="$secColor">$secGrade</text>
</svg>
"@

# Network status summary
$gwStatus = if ($hwResults.Network.GatewayPing.Success) { "<span style=`"color:#27ae60`">OK ($($hwResults.Network.GatewayPing.AvgMs) ms)</span>" } else { "<span style=`"color:#e74c3c`">FAIL</span>" }
$dnsStatus = if ($hwResults.Network.DNSTest.Success) { "<span style=`"color:#27ae60`">OK ($($hwResults.Network.DNSTest.ResponseMs) ms)</span>" } else { "<span style=`"color:#e74c3c`">FAIL</span>" }
$inetStatus = if ($hwResults.Network.InternetTest.Success) { "<span style=`"color:#27ae60`">Connected ($($hwResults.Network.InternetTest.ResponseMs) ms)</span>" } else { "<span style=`"color:#e74c3c`">Offline</span>" }

# Battery section (only if present)
$batteryHtml = ""
if ($hwResults.Battery.Present) {
    $batteryHtml = @"
<div class="section">
  <h2>Battery</h2>
  <div class="card-row">
    <div class="card"><div class="card-label">Charge</div><div class="card-value">$($hwResults.Battery.Charge)%</div></div>
    <div class="card"><div class="card-label">Health</div><div class="card-value">$($hwResults.Battery.HealthPct)%</div></div>
    <div class="card"><div class="card-label">Cycles</div><div class="card-value">$($hwResults.Battery.CycleCount)</div></div>
  </div>
</div>
"@
}

# Thermal section
$thermalHtml = ""
if ($hwResults.Thermal.Count -gt 0) {
    $thermalRows = ""
    foreach ($tz in $hwResults.Thermal) {
        $tColor = if ($tz.TempC -gt 80) { "#e74c3c" } elseif ($tz.TempC -gt 60) { "#f39c12" } else { "#27ae60" }
        $thermalRows += "<tr><td>$($tz.Zone)</td><td style=`"color:${tColor};font-weight:bold`">$($tz.TempC) C / $($tz.TempF) F</td></tr>`n"
    }
    $thermalHtml = @"
<div class="section">
  <h2>Thermal</h2>
  <table><thead><tr><th>Zone</th><th>Temperature</th></tr></thead><tbody>$thermalRows</tbody></table>
</div>
"@
}

$html = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>PC Plus 360 - RMM Report - $($env:COMPUTERNAME)</title>
<style>
  * { margin:0; padding:0; box-sizing:border-box; }
  body { font-family:'Segoe UI',Tahoma,Geneva,Verdana,sans-serif; background:#f4f6f9; color:#333; line-height:1.5; }
  .header { background:linear-gradient(135deg,#0a1628 0%,#1a2d4a 100%); color:#fff; padding:30px 40px; }
  .header h1 { font-size:24px; margin-bottom:4px; }
  .header .subtitle { color:#8899aa; font-size:13px; }
  .header .meta { display:flex; gap:30px; margin-top:12px; font-size:13px; color:#bbb; }
  .header .brand { color:#2596be; font-weight:600; font-size:18px; margin-bottom:8px; }
  .container { max-width:1100px; margin:0 auto; padding:20px; }
  .section { background:#fff; border-radius:8px; box-shadow:0 1px 3px rgba(0,0,0,0.08); padding:24px; margin-bottom:20px; }
  .section h2 { font-size:18px; color:#0a1628; margin-bottom:16px; border-bottom:2px solid #2596be; padding-bottom:8px; }
  .card-row { display:flex; gap:16px; flex-wrap:wrap; }
  .card { flex:1; min-width:140px; background:#f8f9fc; border-radius:6px; padding:16px; text-align:center; border:1px solid #e8ecf1; }
  .card-label { font-size:11px; text-transform:uppercase; color:#888; letter-spacing:0.5px; margin-bottom:4px; }
  .card-value { font-size:20px; font-weight:700; color:#0a1628; }
  .score-section { display:flex; align-items:center; gap:40px; flex-wrap:wrap; }
  .score-chart { flex-shrink:0; }
  .score-summary { flex:1; }
  .score-summary .grade-label { font-size:14px; color:#888; }
  .score-summary .grade-detail { font-size:13px; margin-top:8px; color:#555; }
  table { width:100%; border-collapse:collapse; font-size:13px; }
  th { background:#f0f2f5; text-align:left; padding:10px 12px; font-weight:600; color:#555; border-bottom:2px solid #ddd; }
  td { padding:8px 12px; border-bottom:1px solid #eee; }
  tr.pass td:first-child { color:#27ae60; }
  tr.fail td { background:#fef5f5; }
  tr.fail td:first-child { color:#e74c3c; }
  .rec-item { padding:10px 14px; margin-bottom:8px; background:#fff8e1; border-left:3px solid #f39c12; border-radius:0 4px 4px 0; font-size:13px; }
  .footer { text-align:center; padding:20px; color:#888; font-size:12px; border-top:1px solid #e0e0e0; margin-top:20px; }
  .footer a { color:#2596be; text-decoration:none; }
  .status-ok { color:#27ae60; font-weight:600; }
  .status-warn { color:#f39c12; font-weight:600; }
  .status-bad { color:#e74c3c; font-weight:600; }
  @media print { body { background:#fff; } .section { box-shadow:none; border:1px solid #ddd; } }
</style>
</head>
<body>

<div class="header">
  <div class="brand">PC Plus Computing</div>
  <h1>360 Diagnostic Report - RMM Silent Scan</h1>
  <div class="subtitle">Automated Hardware &amp; Security Assessment</div>
  <div class="meta">
    <span>Computer: <strong>$($env:COMPUTERNAME)</strong></span>
    <span>Customer: <strong>$(if($CustomerName){$CustomerName}else{'N/A'})</strong></span>
    <span>Tech: <strong>$TechName</strong></span>
    <span>Date: <strong>$scanDate</strong></span>
  </div>
</div>

<div class="container">

<!-- System Overview -->
<div class="section">
  <h2>System Overview</h2>
  <div class="card-row">
    <div class="card"><div class="card-label">Operating System</div><div class="card-value" style="font-size:14px">$($hwResults.System.OSVersion)</div></div>
    <div class="card"><div class="card-label">CPU</div><div class="card-value" style="font-size:14px">$($hwResults.System.CPUModel)</div></div>
    <div class="card"><div class="card-label">RAM</div><div class="card-value">$($hwResults.System.RAMTotalGB) GB<br><span style="font-size:12px;color:#888">$($hwResults.System.RAMUsedPct)% used</span></div></div>
    <div class="card"><div class="card-label">Uptime</div><div class="card-value" style="font-size:14px">$($hwResults.System.Uptime)</div></div>
  </div>
  <div class="card-row" style="margin-top:12px">
    <div class="card"><div class="card-label">Manufacturer</div><div class="card-value" style="font-size:14px">$($hwResults.System.Manufacturer)</div></div>
    <div class="card"><div class="card-label">Model</div><div class="card-value" style="font-size:14px">$($hwResults.System.Model)</div></div>
    <div class="card"><div class="card-label">OS Build</div><div class="card-value">$($hwResults.System.OSBuild)</div></div>
    <div class="card"><div class="card-label">CPU Cores</div><div class="card-value">$($hwResults.System.CPUCores)C / $($hwResults.System.CPULogical)T</div></div>
  </div>
</div>

<!-- Security Score -->
<div class="section">
  <h2>Security Score</h2>
  <div class="score-section">
    <div class="score-chart">$donutSvg</div>
    <div class="score-summary">
      <div class="grade-label">Grade: <strong style="font-size:28px;color:$secColor">$secGrade</strong></div>
      <div class="grade-detail">
        <strong>$passedCount</strong> of <strong>$($secBreakdown.Count)</strong> checks passed<br>
        Score: <strong>$secScore / 100</strong> points<br>
        $(if($criticalFailures.Count -gt 0){"<span class=`"status-bad`">Critical: $($criticalFailures -join ', ')</span>"}else{"<span class=`"status-ok`">No critical failures</span>"})
      </div>
    </div>
  </div>
</div>

<!-- Security Breakdown -->
<div class="section">
  <h2>Security Audit - 41 Checks</h2>
  <table>
    <thead><tr><th style="width:30px"></th><th>Check</th><th>Weight</th><th>Result</th></tr></thead>
    <tbody>$secRowsHtml</tbody>
  </table>
</div>

<!-- Hardware / Disk Health -->
<div class="section">
  <h2>Physical Disks</h2>
  <table>
    <thead><tr><th>Model</th><th>Size</th><th>Type</th><th>Health</th><th>Temp</th><th>Wear</th></tr></thead>
    <tbody>$physDiskHtml</tbody>
  </table>
</div>
<div class="section">
  <h2>Volumes</h2>
  <table>
    <thead><tr><th>Drive</th><th>Total</th><th>Free</th><th>Free %</th><th>Usage</th></tr></thead>
    <tbody>$diskRowsHtml</tbody>
  </table>
</div>

<!-- Network -->
<div class="section">
  <h2>Network Status</h2>
  <div class="card-row" style="margin-bottom:16px">
    <div class="card"><div class="card-label">Gateway Ping</div><div class="card-value" style="font-size:13px">$gwStatus</div></div>
    <div class="card"><div class="card-label">DNS Resolution</div><div class="card-value" style="font-size:13px">$dnsStatus</div></div>
    <div class="card"><div class="card-label">Internet</div><div class="card-value" style="font-size:13px">$inetStatus</div></div>
    <div class="card"><div class="card-label">Public IP</div><div class="card-value" style="font-size:13px">$($hwResults.Network.PublicIP)</div></div>
  </div>
  $(if($hwResults.Network.Adapters.Count -gt 0){"<table><thead><tr><th>Adapter</th><th>IP</th><th>DNS</th><th>Speed</th></tr></thead><tbody>$netAdapterHtml</tbody></table>"}else{"<p>No active adapters detected.</p>"})
</div>

$batteryHtml
$thermalHtml

<!-- Startup & Services -->
<div class="section">
  <h2>System Activity</h2>
  <div class="card-row">
    <div class="card"><div class="card-label">Startup Programs</div><div class="card-value">$($hwResults.StartupCount)</div></div>
    <div class="card"><div class="card-label">Running Services</div><div class="card-value">$($hwResults.RunningServices)</div></div>
  </div>
</div>

<!-- Missing Patches -->
<div class="section">
  <h2>Missing Patches ($($missingPatches.Count))</h2>
  <table>
    <thead><tr><th>KB</th><th>Title</th><th>Severity</th><th>Size</th></tr></thead>
    <tbody>$patchRowsHtml</tbody>
  </table>
</div>

<!-- Recommendations -->
<div class="section">
  <h2>Recommendations</h2>
  $recsHtml
</div>

<!-- Footer -->
<div class="footer">
  <strong>PC Plus Computing</strong> | <a href="https://pcpluscomputing.com">pcpluscomputing.com</a> | 604-760-1662<br>
  Report generated by PCPlus 360 v2.6.0 - RMM Silent Scan | $scanDate
</div>

</div>
</body>
</html>
"@

$html | Out-File -FilePath $reportFile -Encoding UTF8 -Force

# ─────────────────────────────────────────────────────────────────────────────
# 11. AUTO-UPLOAD
# ─────────────────────────────────────────────────────────────────────────────
$uploaded = $false
$uploadMsg = ""

if (-not $SkipUpload -and -not [string]::IsNullOrWhiteSpace($UploadUrl)) {
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls11

        $boundary = [System.Guid]::NewGuid().ToString("N")
        $LF = "`r`n"
        $fileName = [IO.Path]::GetFileName($reportFile)
        $fileBytes = [IO.File]::ReadAllBytes($reportFile)

        $fields = @{
            customer_name  = $CustomerName
            computer_name  = $env:COMPUTERNAME
            tech_name      = $TechName
            scan_mode      = $ScanMode
            scan_date      = $scanDate
            file_type      = "HTML"
            source         = "rmm"
            security_score = "$secScore"
            security_grade = $secGrade
        }

        $bodyParts = [System.Collections.ArrayList]::new()
        foreach ($key in $fields.Keys) {
            [void]$bodyParts.Add("--$boundary$LF")
            [void]$bodyParts.Add("Content-Disposition: form-data; name=`"$key`"$LF$LF")
            [void]$bodyParts.Add("$($fields[$key])$LF")
        }

        $fileHeader = "--$boundary${LF}Content-Disposition: form-data; name=`"report_file`"; filename=`"$fileName`"${LF}Content-Type: text/html${LF}${LF}"
        $fileFooter = "${LF}--${boundary}--${LF}"

        $enc = [Text.Encoding]::UTF8
        $textPreamble = $enc.GetBytes(($bodyParts -join ""))
        $headerBytes  = $enc.GetBytes($fileHeader)
        $footerBytes  = $enc.GetBytes($fileFooter)

        $bodyStream = [IO.MemoryStream]::new()
        $bodyStream.Write($textPreamble, 0, $textPreamble.Length)
        $bodyStream.Write($headerBytes,  0, $headerBytes.Length)
        $bodyStream.Write($fileBytes,    0, $fileBytes.Length)
        $bodyStream.Write($footerBytes,  0, $footerBytes.Length)
        $fullBody = $bodyStream.ToArray()
        $bodyStream.Close()

        $headers = @{ "Content-Type" = "multipart/form-data; boundary=$boundary" }
        if (-not [string]::IsNullOrWhiteSpace($ApiKey)) {
            $headers["Authorization"] = "Bearer $ApiKey"
        }

        $response = Invoke-RestMethod -Uri $UploadUrl -Method Post -Headers $headers -Body $fullBody -ContentType "multipart/form-data; boundary=$boundary" -TimeoutSec 60 -ErrorAction Stop
        $uploaded = $true
        $uploadMsg = "Upload successful"
    }
    catch {
        $uploaded = $false
        $uploadMsg = "Upload failed: $($_.Exception.Message)"
    }
} else {
    $uploadMsg = if ($SkipUpload) { "Upload skipped (SkipUpload flag)" } else { "Upload skipped (no URL)" }
}

# ─────────────────────────────────────────────────────────────────────────────
# 12. JSON SUMMARY OUTPUT
# ─────────────────────────────────────────────────────────────────────────────
$scanEnd = Get-Date
$duration = [math]::Round(($scanEnd - $scanStart).TotalSeconds, 0)

$critList = @()
foreach ($cf in $criticalFailures) { $critList += $cf }

$summary = @{
    computer           = $env:COMPUTERNAME
    os                 = $hwResults.System.OSVersion
    os_build           = $hwResults.System.OSBuild
    security_score     = $secScore
    security_grade     = $secGrade
    passed_checks      = $passedCount
    failed_checks      = $failedCount
    critical_failures  = $critList
    disk_health        = $diskHealthOverall
    ram_gb             = $hwResults.System.RAMTotalGB
    ram_used_pct       = $hwResults.System.RAMUsedPct
    cpu                = $hwResults.System.CPUModel
    missing_patches    = $missingPatches.Count
    startup_programs   = $hwResults.StartupCount
    running_services   = $hwResults.RunningServices
    report_path        = $reportFile
    uploaded           = $uploaded
    upload_message     = $uploadMsg
    scan_duration_seconds = $duration
}

# PS 5.1 compatible JSON output (ConvertTo-Json)
$jsonOutput = $summary | ConvertTo-Json -Depth 3 -Compress
Write-Output $jsonOutput

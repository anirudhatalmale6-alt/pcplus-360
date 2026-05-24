#Requires -Version 5.1
<#
.SYNOPSIS
    PC Plus Computing - RDP Exposure & Brute-Force Risk Analysis
.DESCRIPTION
    Comprehensive audit of Remote Desktop Protocol configuration, exposure,
    and brute-force attack indicators. Checks NLA, firewall rules, security
    layers, login history, certificate status, and port exposure. Generates
    a branded HTML report with risk classification and overall score (0-100).
.NOTES
    Company : PC Plus Computing
    Website : pcpluscomputing.com
    Phone   : 604-760-1662 | 236-500-2700
    Version : 1.0.0
    Requires: PowerShell 5.1+, Windows 10/11, Administrator privileges
#>

Set-StrictMode -Version Latest
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
    Write-Host ""
    Write-Host "  [!] This script requires Administrator privileges." -ForegroundColor Red
    Write-Host "      Please right-click and select 'Run as Administrator'." -ForegroundColor Yellow
    Write-Host ""
    try {
        $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$($MyInvocation.MyCommand.Definition)`""
        Start-Process powershell.exe -ArgumentList $arguments -Verb RunAs
    } catch {
        Write-Host "  Failed to relaunch as admin: $_" -ForegroundColor Red
    }
    exit
}

# ─────────────────────────────────────────────────────────────────────────────
# BRANDING & PATHS
# ─────────────────────────────────────────────────────────────────────────────
$COMPANY_NAME    = "PC Plus Computing"
$COMPANY_PHONE   = "604-760-1662 | 236-500-2700"
$COMPANY_WEBSITE = "pcpluscomputing.com"
$SCRIPT_VERSION  = "1.0.0"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
if ([string]::IsNullOrEmpty($ScriptDir)) { $ScriptDir = Get-Location }
$ReportDir = Join-Path $ScriptDir "reports"
if (-not (Test-Path $ReportDir)) { New-Item -ItemType Directory -Path $ReportDir -Force | Out-Null }

$dateStamp  = (Get-Date).ToString("yyyyMMdd-HHmmss")
$scanDate   = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
$reportFile = Join-Path $ReportDir "PCPlus360-RDPExposure-$($env:COMPUTERNAME)-$dateStamp.html"

function Invoke-Safe { param([scriptblock]$Block, $Default = $null); try { return (& $Block) } catch { return $Default } }

# ─────────────────────────────────────────────────────────────────────────────
# CONSOLE BANNER
# ─────────────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "  ============================================================" -ForegroundColor Cyan
Write-Host "   $COMPANY_NAME - RDP Exposure & Brute-Force Audit" -ForegroundColor White
Write-Host "   $COMPANY_PHONE | $COMPANY_WEBSITE" -ForegroundColor DarkGray
Write-Host "  ============================================================" -ForegroundColor Cyan
Write-Host ""

$riskPoints   = 0
$maxRisk      = 0
$findings     = [System.Collections.ArrayList]::new()
$failedLogins = [System.Collections.ArrayList]::new()

function Add-Finding {
    param([string]$Check, [string]$Status, [int]$Points, [int]$MaxPoints, [string]$Detail = "", [string]$Severity = "INFO")
    $script:riskPoints += $Points
    $script:maxRisk    += $MaxPoints
    [void]$findings.Add(@{
        Check     = $Check
        Status    = $Status
        Points    = $Points
        MaxPoints = $MaxPoints
        Detail    = $Detail
        Severity  = $Severity
        Passed    = ($Points -eq $MaxPoints)
    })
}

# ═════════════════════════════════════════════════════════════════════════════
# CHECK 1: RDP Enabled/Disabled Status
# ═════════════════════════════════════════════════════════════════════════════
Write-Host "  [1/14] Checking RDP enabled status..." -ForegroundColor Yellow
$rdpEnabled = Invoke-Safe {
    $regVal = Get-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server" -Name "fDenyTSConnections" -ErrorAction Stop
    $regVal.fDenyTSConnections -eq 0
} $false

$rdpServiceRunning = Invoke-Safe {
    $svc = Get-Service -Name "TermService" -ErrorAction Stop
    $svc.Status -eq "Running"
} $false

if (-not $rdpEnabled) {
    Add-Finding "RDP Status" "SAFE" 15 15 "RDP is disabled - no remote desktop exposure" "LOW"
    Write-Host "         RDP is DISABLED" -ForegroundColor Green
} else {
    Add-Finding "RDP Status" "ALERT" 0 15 "RDP is ENABLED - service running: $(if($rdpServiceRunning){'Yes'}else{'No'})" "HIGH"
    Write-Host "         RDP is ENABLED (service running: $rdpServiceRunning)" -ForegroundColor Red
}

# ═════════════════════════════════════════════════════════════════════════════
# CHECK 2: RDP Port Configuration
# ═════════════════════════════════════════════════════════════════════════════
Write-Host "  [2/14] Checking RDP port..." -ForegroundColor Yellow
$rdpPort = Invoke-Safe {
    $regVal = Get-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" -Name "PortNumber" -ErrorAction Stop
    $regVal.PortNumber
} 3389

if ($rdpPort -ne 3389) {
    Add-Finding "RDP Port" "GOOD" 8 8 "Custom RDP port: $rdpPort (not default 3389)" "LOW"
    Write-Host "         Custom port: $rdpPort" -ForegroundColor Green
} else {
    Add-Finding "RDP Port" "WARN" 2 8 "Default port 3389 - easily discovered by scanners" "MEDIUM"
    Write-Host "         Default port 3389 (easily scannable)" -ForegroundColor Yellow
}

# ═════════════════════════════════════════════════════════════════════════════
# CHECK 3: Network Level Authentication (NLA)
# ═════════════════════════════════════════════════════════════════════════════
Write-Host "  [3/14] Checking Network Level Authentication..." -ForegroundColor Yellow
$nlaEnabled = Invoke-Safe {
    $regVal = Get-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" -Name "UserAuthentication" -ErrorAction Stop
    $regVal.UserAuthentication -eq 1
} $false

$nlaGP = Invoke-Safe {
    $regVal = Get-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services" -Name "UserAuthentication" -ErrorAction Stop
    $regVal.UserAuthentication -eq 1
} $null

if ($nlaEnabled) {
    Add-Finding "Network Level Auth (NLA)" "PASS" 15 15 "NLA is enforced$(if($nlaGP){' (via Group Policy)'})" "LOW"
    Write-Host "         NLA is ENABLED" -ForegroundColor Green
} else {
    $sev = if ($rdpEnabled) { "CRITICAL" } else { "MEDIUM" }
    Add-Finding "Network Level Auth (NLA)" "FAIL" 0 15 "NLA is DISABLED - pre-authentication not required" $sev
    Write-Host "         NLA is DISABLED" -ForegroundColor Red
}

# ═════════════════════════════════════════════════════════════════════════════
# CHECK 4: RDP Firewall Rules
# ═════════════════════════════════════════════════════════════════════════════
Write-Host "  [4/14] Analyzing RDP firewall rules..." -ForegroundColor Yellow
$fwRules = Invoke-Safe {
    Get-NetFirewallRule -ErrorAction Stop |
        Where-Object { $_.DisplayName -match "Remote Desktop|RDP" -or $_.Name -match "RemoteDesktop" } |
        ForEach-Object {
            $portFilter = Get-NetFirewallPortFilter -AssociatedNetFirewallRule $_ -ErrorAction SilentlyContinue
            $addrFilter = Get-NetFirewallAddressFilter -AssociatedNetFirewallRule $_ -ErrorAction SilentlyContinue
            @{
                Name       = $_.DisplayName
                Direction  = $_.Direction.ToString()
                Action     = $_.Action.ToString()
                Enabled    = $_.Enabled.ToString()
                Profile    = $_.Profile.ToString()
                LocalPort  = if ($portFilter) { $portFilter.LocalPort } else { "Any" }
                RemoteAddr = if ($addrFilter) { $addrFilter.RemoteAddress } else { "Any" }
            }
        }
} @()

$enabledInbound = @($fwRules | Where-Object { $_.Direction -eq "Inbound" -and $_.Enabled -eq "True" -and $_.Action -eq "Allow" })
$restrictedRules = @($enabledInbound | Where-Object { $_.RemoteAddr -and $_.RemoteAddr -ne "Any" -and $_.RemoteAddr -ne "*" })

if ($enabledInbound.Count -eq 0) {
    Add-Finding "RDP Firewall Rules" "PASS" 10 10 "No enabled inbound RDP allow rules" "LOW"
    Write-Host "         No inbound RDP allow rules" -ForegroundColor Green
} elseif ($restrictedRules.Count -eq $enabledInbound.Count -and $enabledInbound.Count -gt 0) {
    Add-Finding "RDP Firewall Rules" "GOOD" 8 10 "$($enabledInbound.Count) rules found, all IP-restricted" "LOW"
    Write-Host "         $($enabledInbound.Count) rules, all IP-restricted" -ForegroundColor Green
} else {
    $unrestricted = $enabledInbound.Count - $restrictedRules.Count
    Add-Finding "RDP Firewall Rules" "WARN" 3 10 "$unrestricted unrestricted inbound RDP rules (open to any IP)" "HIGH"
    Write-Host "         $unrestricted unrestricted RDP rules (open to any IP)" -ForegroundColor Red
}

# ═════════════════════════════════════════════════════════════════════════════
# CHECK 5: RDP Security Layer
# ═════════════════════════════════════════════════════════════════════════════
Write-Host "  [5/14] Checking RDP security layer..." -ForegroundColor Yellow
$secLayer = Invoke-Safe {
    $regVal = Get-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" -Name "SecurityLayer" -ErrorAction Stop
    $regVal.SecurityLayer
} $null

$secLayerName = switch ($secLayer) { 0 { "RDP Security (Legacy - WEAK)" }; 1 { "Negotiate" }; 2 { "TLS/SSL" }; default { "Unknown/Default" } }

$minEncLevel = Invoke-Safe {
    $regVal = Get-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" -Name "MinEncryptionLevel" -ErrorAction Stop
    $regVal.MinEncryptionLevel
} $null
$encLevelName = switch ($minEncLevel) { 1 { "Low" }; 2 { "Client Compatible" }; 3 { "High" }; 4 { "FIPS Compliant" }; default { "Default" } }

if ($secLayer -eq 2) {
    Add-Finding "RDP Security Layer" "PASS" 8 8 "Using TLS/SSL (strongest), encryption: $encLevelName" "LOW"
    Write-Host "         TLS/SSL security layer" -ForegroundColor Green
} elseif ($secLayer -eq 1) {
    Add-Finding "RDP Security Layer" "GOOD" 5 8 "Negotiate mode, encryption: $encLevelName" "MEDIUM"
    Write-Host "         Negotiate mode" -ForegroundColor Yellow
} else {
    Add-Finding "RDP Security Layer" "FAIL" 0 8 "Legacy RDP Security layer - vulnerable to MITM" "HIGH"
    Write-Host "         Legacy RDP Security layer (vulnerable)" -ForegroundColor Red
}

# ═════════════════════════════════════════════════════════════════════════════
# CHECK 6: Failed RDP Login Attempts (Event 4625, LogonType 10)
# ═════════════════════════════════════════════════════════════════════════════
Write-Host "  [6/14] Analyzing failed RDP logins (last 1000 events)..." -ForegroundColor Yellow
$failedRdpEvents = Invoke-Safe {
    $filterXml = @"
<QueryList>
  <Query Id="0" Path="Security">
    <Select Path="Security">
      *[System[(EventID=4625)]]
      and
      *[EventData[Data[@Name='LogonType']='10']]
    </Select>
  </Query>
</QueryList>
"@
    $events = Get-WinEvent -FilterXml $filterXml -MaxEvents 1000 -ErrorAction Stop
    $results = [System.Collections.ArrayList]::new()
    foreach ($evt in $events) {
        $xml = [xml]$evt.ToXml()
        $ns = New-Object Xml.XmlNamespaceManager($xml.NameTable)
        $ns.AddNamespace("e", "http://schemas.microsoft.com/win/2004/08/events/event")
        $sourceIP   = $xml.SelectSingleNode("//e:Data[@Name='IpAddress']", $ns).'#text'
        $targetUser = $xml.SelectSingleNode("//e:Data[@Name='TargetUserName']", $ns).'#text'
        $failReason = $xml.SelectSingleNode("//e:Data[@Name='FailureReason']", $ns).'#text'
        $subStatus  = $xml.SelectSingleNode("//e:Data[@Name='SubStatus']", $ns).'#text'
        [void]$results.Add(@{
            Time       = $evt.TimeCreated
            SourceIP   = if ($sourceIP) { $sourceIP } else { "Local" }
            User       = if ($targetUser) { $targetUser } else { "Unknown" }
            Reason     = if ($failReason) { $failReason } else { "" }
            SubStatus  = if ($subStatus) { $subStatus } else { "" }
        })
    }
    $results
} ([System.Collections.ArrayList]::new())

$failedCount = $failedRdpEvents.Count
Write-Host "         Found $failedCount failed RDP login events" -ForegroundColor $(if ($failedCount -gt 50) { "Red" } elseif ($failedCount -gt 10) { "Yellow" } else { "Green" })

if ($failedCount -eq 0) {
    Add-Finding "Failed RDP Logins" "PASS" 10 10 "No failed RDP login attempts found" "LOW"
} elseif ($failedCount -le 10) {
    Add-Finding "Failed RDP Logins" "INFO" 8 10 "$failedCount failed RDP attempts in event log" "LOW"
} elseif ($failedCount -le 50) {
    Add-Finding "Failed RDP Logins" "WARN" 4 10 "$failedCount failed RDP attempts - monitor closely" "MEDIUM"
} else {
    Add-Finding "Failed RDP Logins" "ALERT" 0 10 "$failedCount failed RDP attempts - possible brute force" "HIGH"
}

# Build Top 10 source IPs
$ipGroups = @{}
foreach ($evt in $failedRdpEvents) {
    $ip = $evt.SourceIP
    if (-not $ipGroups.ContainsKey($ip)) { $ipGroups[$ip] = 0 }
    $ipGroups[$ip]++
}
$topIPs = $ipGroups.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 10

# Build timeline (last 7 days by hour)
$timelineBuckets = @{}
$now = Get-Date
foreach ($evt in $failedRdpEvents) {
    $dayKey = $evt.Time.ToString("yyyy-MM-dd")
    if (-not $timelineBuckets.ContainsKey($dayKey)) { $timelineBuckets[$dayKey] = 0 }
    $timelineBuckets[$dayKey]++
}

# ═════════════════════════════════════════════════════════════════════════════
# CHECK 7: Successful RDP Logins (Event 4624, LogonType 10)
# ═════════════════════════════════════════════════════════════════════════════
Write-Host "  [7/14] Analyzing successful RDP logins..." -ForegroundColor Yellow
$successRdpEvents = Invoke-Safe {
    $filterXml = @"
<QueryList>
  <Query Id="0" Path="Security">
    <Select Path="Security">
      *[System[(EventID=4624)]]
      and
      *[EventData[Data[@Name='LogonType']='10']]
    </Select>
  </Query>
</QueryList>
"@
    $events = Get-WinEvent -FilterXml $filterXml -MaxEvents 100 -ErrorAction Stop
    $results = [System.Collections.ArrayList]::new()
    foreach ($evt in $events) {
        $xml = [xml]$evt.ToXml()
        $ns = New-Object Xml.XmlNamespaceManager($xml.NameTable)
        $ns.AddNamespace("e", "http://schemas.microsoft.com/win/2004/08/events/event")
        $sourceIP   = $xml.SelectSingleNode("//e:Data[@Name='IpAddress']", $ns).'#text'
        $targetUser = $xml.SelectSingleNode("//e:Data[@Name='TargetUserName']", $ns).'#text'
        [void]$results.Add(@{
            Time     = $evt.TimeCreated
            SourceIP = if ($sourceIP) { $sourceIP } else { "Local" }
            User     = if ($targetUser) { $targetUser } else { "Unknown" }
        })
    }
    $results
} ([System.Collections.ArrayList]::new())

$successCount = $successRdpEvents.Count
Write-Host "         Found $successCount successful RDP sessions" -ForegroundColor $(if ($successCount -gt 0) { "Yellow" } else { "DarkGray" })

# ═════════════════════════════════════════════════════════════════════════════
# CHECK 8: RDP Certificate Status
# ═════════════════════════════════════════════════════════════════════════════
Write-Host "  [8/14] Checking RDP certificate..." -ForegroundColor Yellow
$rdpCert = Invoke-Safe {
    $thumbprint = (Get-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" -Name "SSLCertificateSHA1Hash" -ErrorAction Stop).SSLCertificateSHA1Hash
    if ($thumbprint) {
        $hexStr = ($thumbprint | ForEach-Object { "{0:X2}" -f $_ }) -join ""
        $cert = Get-ChildItem Cert:\LocalMachine\My -ErrorAction SilentlyContinue | Where-Object { $_.Thumbprint -eq $hexStr } | Select-Object -First 1
        if ($cert) {
            @{
                Subject   = $cert.Subject
                Issuer    = $cert.Issuer
                NotAfter  = $cert.NotAfter
                NotBefore = $cert.NotBefore
                SelfSigned = ($cert.Subject -eq $cert.Issuer)
                Expired    = ($cert.NotAfter -lt (Get-Date))
                DaysLeft   = [math]::Round(($cert.NotAfter - (Get-Date)).TotalDays)
            }
        } else { $null }
    } else { $null }
} $null

if ($rdpCert) {
    if ($rdpCert.Expired) {
        Add-Finding "RDP Certificate" "FAIL" 0 5 "Certificate EXPIRED ($($rdpCert.DaysLeft) days ago)" "HIGH"
        Write-Host "         Certificate EXPIRED" -ForegroundColor Red
    } elseif ($rdpCert.SelfSigned) {
        Add-Finding "RDP Certificate" "WARN" 2 5 "Self-signed certificate (expires in $($rdpCert.DaysLeft) days)" "MEDIUM"
        Write-Host "         Self-signed certificate" -ForegroundColor Yellow
    } else {
        Add-Finding "RDP Certificate" "PASS" 5 5 "Valid CA-signed certificate (expires in $($rdpCert.DaysLeft) days)" "LOW"
        Write-Host "         Valid certificate ($($rdpCert.DaysLeft) days remaining)" -ForegroundColor Green
    }
} else {
    Add-Finding "RDP Certificate" "INFO" 3 5 "Using default Windows-generated certificate" "LOW"
    Write-Host "         Default Windows certificate" -ForegroundColor DarkGray
}

# ═════════════════════════════════════════════════════════════════════════════
# CHECK 9: CredSSP / NLA Settings
# ═════════════════════════════════════════════════════════════════════════════
Write-Host "  [9/14] Checking CredSSP configuration..." -ForegroundColor Yellow
$credSSP = @{}
$credSSP.AllowEncOracle = Invoke-Safe {
    $val = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\CredSSP\Parameters" -Name "AllowEncryptionOracle" -ErrorAction Stop
    $val.AllowEncryptionOracle
} $null

$credSSP.DelegateDefault = Invoke-Safe {
    $val = Get-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CredentialsDelegation" -Name "AllowDefaultCredentials" -ErrorAction Stop
    $val.AllowDefaultCredentials -eq 1
} $false

$oracleName = switch ($credSSP.AllowEncOracle) { 0 { "Force Updated Clients (Secure)" }; 1 { "Mitigated" }; 2 { "Vulnerable (Allow fallback)" }; default { "Default (Secure)" } }

if ($credSSP.AllowEncOracle -eq 2) {
    Add-Finding "CredSSP Policy" "FAIL" 0 5 "AllowEncryptionOracle set to Vulnerable" "HIGH"
    Write-Host "         CredSSP set to VULNERABLE" -ForegroundColor Red
} elseif ($credSSP.AllowEncOracle -eq 1) {
    Add-Finding "CredSSP Policy" "WARN" 3 5 "AllowEncryptionOracle set to Mitigated" "MEDIUM"
    Write-Host "         CredSSP mitigated" -ForegroundColor Yellow
} else {
    Add-Finding "CredSSP Policy" "PASS" 5 5 "CredSSP policy: $oracleName" "LOW"
    Write-Host "         CredSSP secure" -ForegroundColor Green
}

# ═════════════════════════════════════════════════════════════════════════════
# CHECK 10: RDP Session Limits and Timeouts
# ═════════════════════════════════════════════════════════════════════════════
Write-Host "  [10/14] Checking session limits and timeouts..." -ForegroundColor Yellow
$tsRegPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services"
$sessionLimits = @{}
$sessionLimits.MaxIdleTime         = Invoke-Safe { (Get-ItemProperty -Path $tsRegPath -Name "MaxIdleTime" -ErrorAction Stop).MaxIdleTime } $null
$sessionLimits.MaxDisconnectionTime = Invoke-Safe { (Get-ItemProperty -Path $tsRegPath -Name "MaxDisconnectionTime" -ErrorAction Stop).MaxDisconnectionTime } $null
$sessionLimits.MaxConnectionTime   = Invoke-Safe { (Get-ItemProperty -Path $tsRegPath -Name "MaxConnectionTime" -ErrorAction Stop).MaxConnectionTime } $null
$sessionLimits.LimitSessions       = Invoke-Safe { (Get-ItemProperty -Path $tsRegPath -Name "fSingleSessionPerUser" -ErrorAction Stop).fSingleSessionPerUser } $null

$hasTimeouts = ($sessionLimits.MaxIdleTime -ne $null -or $sessionLimits.MaxDisconnectionTime -ne $null)
if ($hasTimeouts) {
    $idleMins = if ($sessionLimits.MaxIdleTime) { [math]::Round($sessionLimits.MaxIdleTime / 60000) } else { "N/A" }
    $discMins = if ($sessionLimits.MaxDisconnectionTime) { [math]::Round($sessionLimits.MaxDisconnectionTime / 60000) } else { "N/A" }
    Add-Finding "Session Timeouts" "PASS" 5 5 "Idle: ${idleMins}min, Disconnect: ${discMins}min" "LOW"
    Write-Host "         Timeouts configured (idle: ${idleMins}min)" -ForegroundColor Green
} else {
    Add-Finding "Session Timeouts" "WARN" 1 5 "No session timeouts configured - sessions may persist indefinitely" "MEDIUM"
    Write-Host "         No session timeouts configured" -ForegroundColor Yellow
}

# ═════════════════════════════════════════════════════════════════════════════
# CHECK 11: Remote Desktop Users Group
# ═════════════════════════════════════════════════════════════════════════════
Write-Host "  [11/14] Checking Remote Desktop Users group..." -ForegroundColor Yellow
$rdpUsers = Invoke-Safe {
    $group = [ADSI]"WinNT://./$('Remote Desktop Users'),group"
    $members = @()
    $group.Invoke("Members") | ForEach-Object {
        $memberPath = ([ADSI]$_).Path
        $memberName = $memberPath.Split("/")[-1]
        $members += $memberName
    }
    $members
} @()

$adminInRDP = Invoke-Safe {
    $rdpUsers | Where-Object { $_ -match "admin|Administrator" }
} @()

if ($rdpUsers.Count -eq 0) {
    Add-Finding "RDP Users Group" "PASS" 5 5 "Remote Desktop Users group is empty" "LOW"
    Write-Host "         No users in Remote Desktop Users group" -ForegroundColor Green
} elseif ($rdpUsers.Count -le 3) {
    Add-Finding "RDP Users Group" "INFO" 4 5 "$($rdpUsers.Count) users: $($rdpUsers -join ', ')" "LOW"
    Write-Host "         $($rdpUsers.Count) users in group" -ForegroundColor Yellow
} else {
    Add-Finding "RDP Users Group" "WARN" 2 5 "$($rdpUsers.Count) users - consider reducing membership" "MEDIUM"
    Write-Host "         $($rdpUsers.Count) users in group (review recommended)" -ForegroundColor Yellow
}

# ═════════════════════════════════════════════════════════════════════════════
# CHECK 12: RDP Gateway Configuration
# ═════════════════════════════════════════════════════════════════════════════
Write-Host "  [12/14] Checking RDP Gateway settings..." -ForegroundColor Yellow
$rdGateway = @{}
$rdGateway.Server = Invoke-Safe {
    (Get-ItemProperty -Path "HKCU:\Software\Microsoft\Terminal Server Client\Default" -Name "GatewayHostname" -ErrorAction Stop).GatewayHostname
} $null

$rdGateway.ServiceInstalled = Invoke-Safe {
    $svc = Get-Service -Name "TSGateway" -ErrorAction Stop
    $true
} $false

$rdGateway.PolicyConfigured = Invoke-Safe {
    $regPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services"
    $val = Get-ItemProperty -Path $regPath -Name "GatewayServer" -ErrorAction Stop
    $val.GatewayServer -ne $null
} $false

if ($rdGateway.ServiceInstalled -or $rdGateway.PolicyConfigured) {
    Add-Finding "RDP Gateway" "PASS" 5 5 "RD Gateway configured$(if($rdGateway.Server){": $($rdGateway.Server)"})" "LOW"
    Write-Host "         RD Gateway configured" -ForegroundColor Green
} else {
    Add-Finding "RDP Gateway" "INFO" 2 5 "No RD Gateway - direct RDP connections only" "MEDIUM"
    Write-Host "         No RD Gateway configured" -ForegroundColor DarkGray
}

# ═════════════════════════════════════════════════════════════════════════════
# CHECK 13: Port Forwarding / UPnP Check for 3389
# ═════════════════════════════════════════════════════════════════════════════
Write-Host "  [13/14] Checking for port exposure / UPnP..." -ForegroundColor Yellow
$portExposure = @{ ListeningOnPort = $false; UPnPEnabled = $false }

$portExposure.ListeningOnPort = Invoke-Safe {
    $listeners = netstat -an 2>$null | Select-String "LISTENING"
    $rdpListening = $listeners | Select-String ":$rdpPort\s"
    ($rdpListening -ne $null)
} $false

$portExposure.UPnPEnabled = Invoke-Safe {
    $svc = Get-Service -Name "SSDPSRV" -ErrorAction Stop
    $svc.Status -eq "Running"
} $false

$portExposure.UPnPDeviceHost = Invoke-Safe {
    $svc = Get-Service -Name "upnphost" -ErrorAction Stop
    $svc.Status -eq "Running"
} $false

if ($portExposure.ListeningOnPort -and $rdpEnabled) {
    if ($portExposure.UPnPEnabled) {
        Add-Finding "Port Exposure" "ALERT" 0 7 "RDP port $rdpPort is listening AND UPnP is active (may auto-forward)" "CRITICAL"
        Write-Host "         Port $rdpPort listening + UPnP active (HIGH RISK)" -ForegroundColor Red
    } else {
        Add-Finding "Port Exposure" "WARN" 3 7 "RDP port $rdpPort is actively listening" "MEDIUM"
        Write-Host "         Port $rdpPort is listening" -ForegroundColor Yellow
    }
} elseif ($portExposure.UPnPEnabled) {
    Add-Finding "Port Exposure" "INFO" 5 7 "UPnP service running but RDP port not listening" "LOW"
    Write-Host "         UPnP active but RDP port not listening" -ForegroundColor Yellow
} else {
    Add-Finding "Port Exposure" "PASS" 7 7 "RDP port not listening, UPnP not active" "LOW"
    Write-Host "         No port exposure detected" -ForegroundColor Green
}

# ═════════════════════════════════════════════════════════════════════════════
# CHECK 14: Brute Force Indicators
# ═════════════════════════════════════════════════════════════════════════════
Write-Host "  [14/14] Analyzing brute force indicators..." -ForegroundColor Yellow

# Check for lockout events (4740)
$lockoutEvents = Invoke-Safe {
    Get-WinEvent -FilterHashtable @{ LogName = "Security"; Id = 4740 } -MaxEvents 50 -ErrorAction Stop |
        ForEach-Object {
            $xml = [xml]$_.ToXml()
            $ns = New-Object Xml.XmlNamespaceManager($xml.NameTable)
            $ns.AddNamespace("e", "http://schemas.microsoft.com/win/2004/08/events/event")
            @{
                Time    = $_.TimeCreated
                User    = $xml.SelectSingleNode("//e:Data[@Name='TargetUserName']", $ns).'#text'
                Source  = $xml.SelectSingleNode("//e:Data[@Name='TargetDomainName']", $ns).'#text'
            }
        }
} @()

# Brute force detection: any single IP with > 20 failed attempts
$bruteForceIPs = @($ipGroups.GetEnumerator() | Where-Object { $_.Value -ge 20 })
$isBruteForce  = ($bruteForceIPs.Count -gt 0)

# Rapid-fire detection: > 10 failures in 5 minutes
$rapidFire = $false
if ($failedRdpEvents.Count -ge 10) {
    $sortedEvents = $failedRdpEvents | Sort-Object { $_.Time }
    for ($i = 0; $i -le ($sortedEvents.Count - 10); $i++) {
        $window = ($sortedEvents[$i + 9].Time - $sortedEvents[$i].Time).TotalMinutes
        if ($window -le 5) { $rapidFire = $true; break }
    }
}

if ($isBruteForce -or $rapidFire) {
    $bfDetail = ""
    if ($isBruteForce) { $bfDetail += "$($bruteForceIPs.Count) IPs with 20+ failed attempts. " }
    if ($rapidFire)    { $bfDetail += "Rapid-fire pattern detected (10+ in 5min). " }
    Add-Finding "Brute Force Detection" "ALERT" 0 10 $bfDetail.Trim() "CRITICAL"
    Write-Host "         BRUTE FORCE INDICATORS DETECTED" -ForegroundColor Red
} elseif ($failedCount -gt 20) {
    Add-Finding "Brute Force Detection" "WARN" 4 10 "Elevated failed logins ($failedCount) but no clear brute force pattern" "MEDIUM"
    Write-Host "         Elevated failures but no clear brute force pattern" -ForegroundColor Yellow
} else {
    Add-Finding "Brute Force Detection" "PASS" 10 10 "No brute force indicators detected" "LOW"
    Write-Host "         No brute force indicators" -ForegroundColor Green
}

# ═════════════════════════════════════════════════════════════════════════════
# RISK CLASSIFICATION
# ═════════════════════════════════════════════════════════════════════════════
$riskScore = if ($maxRisk -gt 0) { [math]::Round(($riskPoints / $maxRisk) * 100) } else { 0 }
$riskScore = [math]::Min($riskScore, 100)

# Determine classification
$riskClass = "SAFE"
if ($rdpEnabled -and -not $nlaEnabled -and $rdpPort -eq 3389 -and ($portExposure.ListeningOnPort -or $portExposure.UPnPEnabled)) {
    $riskClass = "CRITICAL"
} elseif ($rdpEnabled -and -not $nlaEnabled) {
    $riskClass = "HIGH"
} elseif ($rdpEnabled -and $nlaEnabled -and $rdpPort -eq 3389) {
    $riskClass = "MEDIUM"
} elseif ($rdpEnabled -and $nlaEnabled -and $rdpPort -ne 3389) {
    $riskClass = "LOW"
} elseif (-not $rdpEnabled) {
    $riskClass = "SAFE"
}

# Override to CRITICAL if brute force detected
if ($isBruteForce -or $rapidFire) {
    if ($riskClass -ne "CRITICAL") { $riskClass = "CRITICAL" }
}

$riskColor = switch ($riskClass) {
    "CRITICAL" { "#e74c3c" }
    "HIGH"     { "#e67e22" }
    "MEDIUM"   { "#f39c12" }
    "LOW"      { "#3498db" }
    "SAFE"     { "#27ae60" }
}

$riskEmoji = switch ($riskClass) {
    "CRITICAL" { "&#9888;" }
    "HIGH"     { "&#9888;" }
    "MEDIUM"   { "&#128276;" }
    "LOW"      { "&#128505;" }
    "SAFE"     { "&#9989;" }
}

Write-Host ""
Write-Host "  ──────────────────────────────────────────────────────────" -ForegroundColor Cyan
$riskConsoleColor = switch ($riskClass) { "CRITICAL" { "Red" }; "HIGH" { "Red" }; "MEDIUM" { "Yellow" }; "LOW" { "Cyan" }; default { "Green" } }
Write-Host "   RDP RISK: $riskClass | SECURITY SCORE: $riskScore / 100" -ForegroundColor $riskConsoleColor
Write-Host "  ──────────────────────────────────────────────────────────" -ForegroundColor Cyan

# ═════════════════════════════════════════════════════════════════════════════
# HTML REPORT GENERATION
# ═════════════════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "  Generating HTML report..." -ForegroundColor Yellow

# Build findings table
$findingRowsHtml = ""
foreach ($f in $findings) {
    $icon = if ($f.Passed) { "&#9989;" } elseif ($f.Status -eq "INFO") { "&#8505;" } elseif ($f.Status -eq "WARN") { "&#9888;" } else { "&#10060;" }
    $cls  = if ($f.Passed) { "pass" } elseif ($f.Status -eq "ALERT" -or $f.Status -eq "FAIL") { "fail" } else { "" }
    $sevColor = switch ($f.Severity) { "CRITICAL" { "#e74c3c" }; "HIGH" { "#e67e22" }; "MEDIUM" { "#f39c12" }; default { "#27ae60" } }
    $findingRowsHtml += "<tr class=`"$cls`"><td>$icon</td><td>$($f.Check)</td><td>$($f.Points)/$($f.MaxPoints)</td><td style=`"color:$sevColor;font-weight:600`">$($f.Severity)</td><td style=`"font-size:11px;color:#666`">$($f.Detail)</td></tr>`n"
}

# Build top IPs table
$topIPRowsHtml = ""
$ipRank = 0
foreach ($ip in $topIPs) {
    $ipRank++
    $ipColor = if ($ip.Value -ge 50) { "#e74c3c" } elseif ($ip.Value -ge 20) { "#e67e22" } elseif ($ip.Value -ge 5) { "#f39c12" } else { "#333" }
    $barWidth = if ($topIPs[0].Value -gt 0) { [math]::Round(($ip.Value / $topIPs[0].Value) * 100) } else { 0 }
    $topIPRowsHtml += @"
<tr>
  <td style="font-weight:700">$ipRank</td>
  <td style="font-family:monospace">$($ip.Key)</td>
  <td style="color:$ipColor;font-weight:700">$($ip.Value)</td>
  <td><div style="background:#eee;border-radius:3px;height:16px;width:100%"><div style="background:$ipColor;border-radius:3px;height:16px;width:${barWidth}%"></div></div></td>
</tr>
"@
}
if (-not $topIPRowsHtml) {
    $topIPRowsHtml = "<tr><td colspan=`"4`" style=`"text-align:center;color:#27ae60;font-weight:600`">No failed RDP attempts recorded</td></tr>"
}

# Build timeline table
$timelineRowsHtml = ""
$sortedTimeline = $timelineBuckets.GetEnumerator() | Sort-Object Key -Descending | Select-Object -First 14
$maxDayCount = ($sortedTimeline | Sort-Object Value -Descending | Select-Object -First 1).Value
if (-not $maxDayCount) { $maxDayCount = 1 }
foreach ($day in $sortedTimeline) {
    $dayBarWidth = [math]::Round(($day.Value / $maxDayCount) * 100)
    $dayColor = if ($day.Value -ge 50) { "#e74c3c" } elseif ($day.Value -ge 20) { "#e67e22" } elseif ($day.Value -ge 5) { "#f39c12" } else { "#3498db" }
    $timelineRowsHtml += @"
<tr>
  <td style="font-family:monospace;white-space:nowrap">$($day.Key)</td>
  <td style="font-weight:700;color:$dayColor">$($day.Value)</td>
  <td style="width:60%"><div style="background:#eee;border-radius:3px;height:16px"><div style="background:$dayColor;border-radius:3px;height:16px;width:${dayBarWidth}%"></div></div></td>
</tr>
"@
}
if (-not $timelineRowsHtml) {
    $timelineRowsHtml = "<tr><td colspan=`"3`" style=`"text-align:center;color:#27ae60`">No events to display</td></tr>"
}

# Build successful logins table
$successRowsHtml = ""
foreach ($s in ($successRdpEvents | Select-Object -First 20)) {
    $successRowsHtml += "<tr><td>$($s.Time.ToString('yyyy-MM-dd HH:mm:ss'))</td><td style=`"font-family:monospace`">$($s.SourceIP)</td><td>$($s.User)</td></tr>`n"
}
if (-not $successRowsHtml) {
    $successRowsHtml = "<tr><td colspan=`"3`" style=`"text-align:center;color:#888`">No successful RDP logins recorded</td></tr>"
}

# Build lockout table
$lockoutRowsHtml = ""
foreach ($l in ($lockoutEvents | Select-Object -First 15)) {
    $lockoutRowsHtml += "<tr><td>$($l.Time.ToString('yyyy-MM-dd HH:mm:ss'))</td><td>$($l.User)</td><td>$($l.Source)</td></tr>`n"
}
if (-not $lockoutRowsHtml) {
    $lockoutRowsHtml = "<tr><td colspan=`"3`" style=`"text-align:center;color:#27ae60`">No lockout events</td></tr>"
}

# Build firewall rules table
$fwRowsHtml = ""
foreach ($fw in $fwRules) {
    $fwColor = if ($fw.Enabled -eq "True" -and $fw.Action -eq "Allow") { "#e67e22" } elseif ($fw.Action -eq "Block") { "#27ae60" } else { "#999" }
    $remoteAddrs = if ($fw.RemoteAddr -is [array]) { $fw.RemoteAddr -join ", " } else { $fw.RemoteAddr }
    $fwRowsHtml += "<tr><td>$($fw.Name)</td><td>$($fw.Direction)</td><td style=`"color:$fwColor;font-weight:600`">$($fw.Action)</td><td>$($fw.Enabled)</td><td>$($fw.Profile)</td><td style=`"font-family:monospace;font-size:11px`">$($fw.LocalPort)</td><td style=`"font-family:monospace;font-size:11px`">$remoteAddrs</td></tr>`n"
}
if (-not $fwRowsHtml) {
    $fwRowsHtml = "<tr><td colspan=`"7`" style=`"text-align:center;color:#888`">No RDP firewall rules found</td></tr>"
}

# Build RDP users list
$rdpUsersHtml = ""
foreach ($u in $rdpUsers) {
    $rdpUsersHtml += "<span style=`"display:inline-block;background:#f0f2f5;border:1px solid #ddd;border-radius:4px;padding:4px 10px;margin:3px;font-size:12px`">$u</span>"
}
if (-not $rdpUsersHtml) { $rdpUsersHtml = "<span style=`"color:#888;font-size:12px`">No members in Remote Desktop Users group</span>" }

# Score arc for SVG
$pctAngle = [math]::Round($riskScore * 3.6, 1)
$largeArc = if ($pctAngle -gt 180) { 1 } else { 0 }
$radians  = $pctAngle * [math]::PI / 180
$endX     = [math]::Round(50 + 40 * [math]::Sin($radians), 2)
$endY     = [math]::Round(50 - 40 * [math]::Cos($radians), 2)
$arcPath  = if ($riskScore -ge 100) { "M 50 10 A 40 40 0 1 1 49.99 10" } else { "M 50 10 A 40 40 0 $largeArc 1 $endX $endY" }
$scoreColor = if ($riskScore -ge 80) { "#27ae60" } elseif ($riskScore -ge 60) { "#f39c12" } else { "#e74c3c" }

$passedCount = ($findings | Where-Object { $_.Passed }).Count
$totalChecks = $findings.Count

$html = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>PC Plus 360 - RDP Exposure Audit - $($env:COMPUTERNAME)</title>
<style>
  * { margin:0; padding:0; box-sizing:border-box; }
  body { font-family:'Segoe UI',Tahoma,sans-serif; background:#f4f6f9; color:#333; line-height:1.5; }
  .header { background:linear-gradient(135deg,#0a3d5c 0%,#0d4b71 50%,#1a2d4a 100%); color:#fff; padding:24px 40px; }
  .header .brand { font-size:18px; font-weight:700; color:#2596be; }
  .header .tagline { font-size:10px; text-transform:uppercase; letter-spacing:2px; opacity:0.6; }
  .header h1 { font-size:22px; margin:8px 0 4px; }
  .header .meta { display:flex; gap:24px; font-size:13px; color:#bbb; flex-wrap:wrap; }
  .risk-banner { padding:16px 40px; font-size:16px; font-weight:700; color:white; display:flex; align-items:center; gap:12px; background:$riskColor; }
  .container { max-width:1100px; margin:0 auto; padding:20px; }
  .section { background:#fff; border-radius:8px; box-shadow:0 1px 3px rgba(0,0,0,0.08); padding:24px; margin-bottom:16px; }
  .section h2 { font-size:16px; color:#0d4b71; margin-bottom:14px; border-bottom:2px solid #2596be; padding-bottom:6px; }
  .card-row { display:flex; gap:12px; flex-wrap:wrap; }
  .card { flex:1; min-width:110px; background:#f8f9fc; border-radius:6px; padding:14px; text-align:center; border:1px solid #e8ecf1; }
  .card-label { font-size:10px; text-transform:uppercase; color:#888; letter-spacing:0.5px; }
  .card-value { font-size:18px; font-weight:700; color:#0d4b71; }
  .score-section { display:flex; align-items:center; gap:30px; flex-wrap:wrap; }
  table { width:100%; border-collapse:collapse; font-size:13px; }
  th { background:#f0f2f5; text-align:left; padding:8px 12px; font-weight:600; color:#555; border-bottom:2px solid #ddd; font-size:11px; text-transform:uppercase; }
  td { padding:7px 12px; border-bottom:1px solid #eee; }
  tr.pass td:first-child { color:#27ae60; }
  tr.fail td { background:#fef5f5; }
  tr.fail td:first-child { color:#e74c3c; }
  .footer { text-align:center; padding:16px; color:#888; font-size:11px; border-top:1px solid #e0e0e0; margin-top:16px; }
  @media print { body { background:#fff; } .section { box-shadow:none; border:1px solid #ddd; } }
</style>
</head>
<body>

<div class="header">
  <div class="brand">PC Plus Computing</div>
  <div class="tagline">Your Security, Our Priority</div>
  <h1>&#128374; RDP Exposure &amp; Brute-Force Audit</h1>
  <div class="meta">
    <span>Computer: <strong>$($env:COMPUTERNAME)</strong></span>
    <span>User: <strong>$($env:USERNAME)</strong></span>
    <span>Scan: <strong>$scanDate</strong></span>
    <span>RDP Port: <strong>$rdpPort</strong></span>
  </div>
</div>

<div class="risk-banner">
  $riskEmoji RDP RISK LEVEL: $riskClass $(switch($riskClass){
    "CRITICAL" { "- Immediate action required: RDP is critically exposed" };
    "HIGH"     { "- RDP enabled without NLA - high brute-force risk" };
    "MEDIUM"   { "- RDP enabled with NLA on default port - change port recommended" };
    "LOW"      { "- RDP configured with good security controls" };
    "SAFE"     { "- RDP is disabled - no remote desktop exposure" }
  })
</div>

<div class="container">

<!-- Risk Overview Cards -->
<div class="section">
  <h2>&#128202; Risk Overview</h2>
  <div class="score-section">
    <svg viewBox="0 0 100 100" width="150" height="150">
      <circle cx="50" cy="50" r="40" fill="none" stroke="#e0e0e0" stroke-width="8"/>
      <path d="$arcPath" fill="none" stroke="$scoreColor" stroke-width="8" stroke-linecap="round"/>
      <text x="50" y="44" text-anchor="middle" font-size="22" font-weight="bold" fill="$scoreColor">$riskScore</text>
      <text x="50" y="58" text-anchor="middle" font-size="10" fill="#666">/ 100</text>
      <text x="50" y="72" text-anchor="middle" font-size="14" font-weight="bold" fill="$riskColor">$riskClass</text>
    </svg>
    <div>
      <p><strong>$passedCount</strong> of <strong>$totalChecks</strong> checks passed</p>
      <p>Security Points: <strong>$riskPoints</strong> / <strong>$maxRisk</strong></p>
    </div>
  </div>
</div>

<!-- Status Cards -->
<div class="section">
  <h2>&#128374; RDP Configuration Summary</h2>
  <div class="card-row" style="margin-bottom:14px">
    <div class="card"><div class="card-label">RDP Status</div><div class="card-value" style="color:$(if($rdpEnabled){'#e74c3c'}else{'#27ae60'})">$(if($rdpEnabled){'ENABLED'}else{'DISABLED'})</div></div>
    <div class="card"><div class="card-label">NLA Required</div><div class="card-value" style="color:$(if($nlaEnabled){'#27ae60'}else{'#e74c3c'})">$(if($nlaEnabled){'YES'}else{'NO'})</div></div>
    <div class="card"><div class="card-label">Port</div><div class="card-value" style="color:$(if($rdpPort -eq 3389){'#f39c12'}else{'#27ae60'})">$rdpPort</div></div>
    <div class="card"><div class="card-label">Security Layer</div><div class="card-value" style="font-size:12px">$secLayerName</div></div>
    <div class="card"><div class="card-label">Risk Level</div><div class="card-value" style="color:$riskColor">$riskClass</div></div>
  </div>
  <div class="card-row">
    <div class="card"><div class="card-label">Failed Logins</div><div class="card-value" style="color:$(if($failedCount -ge 50){'#e74c3c'}elseif($failedCount -ge 10){'#f39c12'}else{'#27ae60'})">$failedCount</div></div>
    <div class="card"><div class="card-label">Successful Logins</div><div class="card-value">$successCount</div></div>
    <div class="card"><div class="card-label">Lockout Events</div><div class="card-value" style="color:$(if($lockoutEvents.Count -gt 0){'#e74c3c'}else{'#27ae60'})">$($lockoutEvents.Count)</div></div>
    <div class="card"><div class="card-label">Brute Force</div><div class="card-value" style="color:$(if($isBruteForce -or $rapidFire){'#e74c3c'}else{'#27ae60'})">$(if($isBruteForce -or $rapidFire){'DETECTED'}else{'None'})</div></div>
    <div class="card"><div class="card-label">RDP Users</div><div class="card-value">$($rdpUsers.Count)</div></div>
  </div>
</div>

<!-- Top 10 Failed IPs -->
<div class="section">
  <h2>&#128680; Top 10 Source IPs - Failed RDP Attempts</h2>
  <table>
    <thead><tr><th style="width:40px">#</th><th>IP Address</th><th>Attempts</th><th>Volume</th></tr></thead>
    <tbody>$topIPRowsHtml</tbody>
  </table>
</div>

<!-- Failed Login Timeline -->
<div class="section">
  <h2>&#128197; Failed Login Timeline (by Day)</h2>
  <table>
    <thead><tr><th>Date</th><th>Count</th><th>Volume</th></tr></thead>
    <tbody>$timelineRowsHtml</tbody>
  </table>
</div>

<!-- Successful RDP Sessions -->
<div class="section">
  <h2>&#128100; Recent Successful RDP Logins (Last 20)</h2>
  <table>
    <thead><tr><th>Time</th><th>Source IP</th><th>User</th></tr></thead>
    <tbody>$successRowsHtml</tbody>
  </table>
</div>

<!-- Lockout Events -->
<div class="section">
  <h2>&#128274; Account Lockout Events</h2>
  <table>
    <thead><tr><th>Time</th><th>User</th><th>Source</th></tr></thead>
    <tbody>$lockoutRowsHtml</tbody>
  </table>
</div>

<!-- Firewall Rules -->
<div class="section">
  <h2>&#128737; RDP Firewall Rules</h2>
  <div style="overflow-x:auto">
  <table>
    <thead><tr><th>Rule Name</th><th>Direction</th><th>Action</th><th>Enabled</th><th>Profile</th><th>Local Port</th><th>Remote Address</th></tr></thead>
    <tbody>$fwRowsHtml</tbody>
  </table>
  </div>
</div>

<!-- RDP Users Group -->
<div class="section">
  <h2>&#128101; Remote Desktop Users Group</h2>
  <div style="padding:8px 0">$rdpUsersHtml</div>
</div>

<!-- RDP Certificate & CredSSP -->
<div class="section">
  <h2>&#128272; Certificate &amp; CredSSP</h2>
  <div class="card-row">
    <div class="card"><div class="card-label">Certificate</div><div class="card-value" style="font-size:12px;color:$(if($rdpCert -and $rdpCert.Expired){'#e74c3c'}elseif($rdpCert -and $rdpCert.SelfSigned){'#f39c12'}elseif($rdpCert){'#27ae60'}else{'#888'})">$(if($rdpCert -and $rdpCert.Expired){'Expired'}elseif($rdpCert -and $rdpCert.SelfSigned){'Self-Signed'}elseif($rdpCert){'CA-Signed'}else{'Default'})</div></div>
    <div class="card"><div class="card-label">Cert Expires</div><div class="card-value" style="font-size:12px">$(if($rdpCert){"$($rdpCert.DaysLeft) days"}else{'N/A'})</div></div>
    <div class="card"><div class="card-label">CredSSP Oracle</div><div class="card-value" style="font-size:11px;color:$(if($credSSP.AllowEncOracle -eq 2){'#e74c3c'}else{'#27ae60'})">$oracleName</div></div>
    <div class="card"><div class="card-label">Encryption Level</div><div class="card-value" style="font-size:12px">$encLevelName</div></div>
    <div class="card"><div class="card-label">RD Gateway</div><div class="card-value" style="font-size:12px;color:$(if($rdGateway.ServiceInstalled -or $rdGateway.PolicyConfigured){'#27ae60'}else{'#888'})">$(if($rdGateway.ServiceInstalled -or $rdGateway.PolicyConfigured){'Configured'}else{'None'})</div></div>
  </div>
</div>

<!-- Session Limits -->
<div class="section">
  <h2>&#9202; Session Limits &amp; Timeouts</h2>
  <div class="card-row">
    <div class="card"><div class="card-label">Idle Timeout</div><div class="card-value" style="font-size:14px">$(if($sessionLimits.MaxIdleTime){"$([math]::Round($sessionLimits.MaxIdleTime / 60000)) min"}else{'Not Set'})</div></div>
    <div class="card"><div class="card-label">Disconnect Timeout</div><div class="card-value" style="font-size:14px">$(if($sessionLimits.MaxDisconnectionTime){"$([math]::Round($sessionLimits.MaxDisconnectionTime / 60000)) min"}else{'Not Set'})</div></div>
    <div class="card"><div class="card-label">Max Connection Time</div><div class="card-value" style="font-size:14px">$(if($sessionLimits.MaxConnectionTime){"$([math]::Round($sessionLimits.MaxConnectionTime / 60000)) min"}else{'Not Set'})</div></div>
    <div class="card"><div class="card-label">Single Session</div><div class="card-value" style="font-size:14px">$(if($sessionLimits.LimitSessions -eq 1){'Enforced'}else{'Not Set'})</div></div>
  </div>
</div>

<!-- Full Audit Breakdown -->
<div class="section">
  <h2>&#128203; Full Audit Breakdown - All Checks</h2>
  <table>
    <thead><tr><th style="width:30px"></th><th>Check</th><th>Score</th><th>Severity</th><th>Detail</th></tr></thead>
    <tbody>$findingRowsHtml</tbody>
  </table>
</div>

<div class="footer">
  <strong>$COMPANY_NAME</strong> | $COMPANY_WEBSITE | $COMPANY_PHONE<br>
  PC Plus 360 RDP Exposure Audit v$SCRIPT_VERSION | $scanDate
</div>

</div>
</body>
</html>
"@

$html | Out-File -FilePath $reportFile -Encoding UTF8 -Force

Write-Host "  Report saved: $reportFile" -ForegroundColor Green
Write-Host ""
Write-Host "  ============================================================" -ForegroundColor Cyan
Write-Host "   Audit complete. Opening report..." -ForegroundColor White
Write-Host "  ============================================================" -ForegroundColor Cyan
Write-Host ""

# Open the report
try { Start-Process $reportFile } catch { Write-Host "  Could not auto-open report. Please open manually: $reportFile" -ForegroundColor Yellow }

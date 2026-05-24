<#
.SYNOPSIS
    PC Plus Computing - Network Visibility & Troubleshooting Snapshot
.DESCRIPTION
    Portable PowerShell script that performs a comprehensive network audit including
    adapter inventory, WiFi diagnostics, DNS analysis, active connections, firewall
    status, VPN detection, proxy settings, and suspicious activity scanning.
    Generates a branded HTML report.
.NOTES
    Company:  PC Plus Computing
    Website:  pcpluscomputing.com
    Phone:    604-760-1662 | 236-500-2700
    Version:  1.0.0
    Requires: PowerShell 5.1+, Windows 10/11, Administrator privileges
#>

#Requires -Version 5.1
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
    try {
        $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$($MyInvocation.MyCommand.Definition)`""
        Start-Process powershell.exe -ArgumentList $arguments -Verb RunAs
    } catch {
        Write-Host ""
        Write-Host "  ERROR: This tool requires Administrator privileges." -ForegroundColor Red
        Write-Host "  Please right-click and select 'Run as Administrator'." -ForegroundColor Yellow
        Write-Host ""
        Read-Host "Press Enter to exit"
    }
    exit
}

# ─────────────────────────────────────────────────────────────────────────────
# BRANDING & SETUP
# ─────────────────────────────────────────────────────────────────────────────
$COMPANY_NAME    = "PC Plus Computing"
$COMPANY_PHONE1  = "604-760-1662"
$COMPANY_PHONE2  = "236-500-2700"
$COMPANY_WEBSITE = "pcpluscomputing.com"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
if ([string]::IsNullOrEmpty($ScriptDir)) { $ScriptDir = Get-Location }
$ReportDir = Join-Path $ScriptDir "reports"
if (-not (Test-Path $ReportDir)) { New-Item -ItemType Directory -Path $ReportDir -Force | Out-Null }

$scanStart = Get-Date
$scanDate  = $scanStart.ToString("yyyy-MM-dd HH:mm:ss")
$hostName  = $env:COMPUTERNAME

function Invoke-Safe {
    param([scriptblock]$Block, $Default = $null)
    try { return (& $Block) } catch { return $Default }
}

function Write-Section {
    param([string]$Title)
    Write-Host ""
    Write-Host "  [$((Get-Date).ToString('HH:mm:ss'))] $Title" -ForegroundColor Cyan
    Write-Host "  $('-' * 60)" -ForegroundColor DarkGray
}

function Write-Status {
    param([string]$Label, [string]$Value, [string]$Color = "White")
    Write-Host "    $Label : " -NoNewline -ForegroundColor Gray
    Write-Host $Value -ForegroundColor $Color
}

# ─────────────────────────────────────────────────────────────────────────────
# BANNER
# ─────────────────────────────────────────────────────────────────────────────
Clear-Host
Write-Host ""
Write-Host "  ╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "  ║          PC PLUS COMPUTING - NETWORK SNAPSHOT               ║" -ForegroundColor Cyan
Write-Host "  ║   $COMPANY_PHONE1 | $COMPANY_PHONE2 | $COMPANY_WEBSITE    ║" -ForegroundColor Cyan
Write-Host "  ╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host "    Computer: $hostName  |  Date: $scanDate" -ForegroundColor DarkGray
Write-Host ""

$findings = New-Object System.Collections.ArrayList

# ═════════════════════════════════════════════════════════════════════════════
# 1. NETWORK ADAPTERS
# ═════════════════════════════════════════════════════════════════════════════
Write-Section "Network Adapters"
$adapterData = Invoke-Safe {
    $results = New-Object System.Collections.ArrayList
    $adapters = Get-NetAdapter -ErrorAction SilentlyContinue | Sort-Object Status
    foreach ($a in $adapters) {
        $ipConfig = Get-NetIPConfiguration -InterfaceIndex $a.ifIndex -ErrorAction SilentlyContinue
        $ipv4     = ($ipConfig.IPv4Address | Select-Object -First 1).IPAddress
        $gateway  = ($ipConfig.IPv4DefaultGateway | Select-Object -First 1).NextHop
        $dns      = ($ipConfig.DnsServer | Where-Object { $_.AddressFamily -eq 2 }).ServerAddresses -join ", "
        $obj = @{
            Name     = $a.Name
            Desc     = $a.InterfaceDescription
            Status   = "$($a.Status)"
            Speed    = if ($a.LinkSpeed) { "$($a.LinkSpeed)" } else { "N/A" }
            MAC      = $a.MacAddress
            IPv4     = if ($ipv4) { $ipv4 } else { "N/A" }
            Gateway  = if ($gateway) { $gateway } else { "N/A" }
            DNS      = if ($dns) { $dns } else { "N/A" }
        }
        [void]$results.Add($obj)
        $statusColor = if ($a.Status -eq "Up") { "Green" } else { "Yellow" }
        Write-Status $a.Name "$($a.Status) | $($obj.Speed) | $($obj.IPv4)" $statusColor
    }
    return $results
} @()

# ═════════════════════════════════════════════════════════════════════════════
# 2. WIFI INFORMATION
# ═════════════════════════════════════════════════════════════════════════════
Write-Section "WiFi Information"
$wifiData = Invoke-Safe {
    $wifiRaw = netsh wlan show interfaces 2>$null
    if (-not $wifiRaw -or $wifiRaw -match "no wireless") {
        Write-Status "WiFi" "No wireless adapter detected" "Yellow"
        return @{ Available = $false }
    }
    $ssid     = ($wifiRaw | Select-String '^\s+SSID\s+:\s(.+)$' | Select-Object -First 1).Matches.Groups[1].Value.Trim()
    $signal   = ($wifiRaw | Select-String 'Signal\s+:\s(.+)$' | Select-Object -First 1).Matches.Groups[1].Value.Trim()
    $auth     = ($wifiRaw | Select-String 'Authentication\s+:\s(.+)$' | Select-Object -First 1).Matches.Groups[1].Value.Trim()
    $channel  = ($wifiRaw | Select-String 'Channel\s+:\s(.+)$' | Select-Object -First 1).Matches.Groups[1].Value.Trim()
    $rxRate   = ($wifiRaw | Select-String 'Receive rate\s+:\s(.+)$' | Select-Object -First 1).Matches.Groups[1].Value.Trim()
    $txRate   = ($wifiRaw | Select-String 'Transmit rate\s+:\s(.+)$' | Select-Object -First 1).Matches.Groups[1].Value.Trim()
    $bssid    = ($wifiRaw | Select-String 'BSSID\s+:\s(.+)$' | Select-Object -First 1).Matches.Groups[1].Value.Trim()
    $radioType = ($wifiRaw | Select-String 'Radio type\s+:\s(.+)$' | Select-Object -First 1).Matches.Groups[1].Value.Trim()

    $channelNum = 0
    if ($channel) { [int]::TryParse($channel, [ref]$channelNum) | Out-Null }
    $band = if ($channelNum -ge 1 -and $channelNum -le 14) { "2.4 GHz" }
            elseif ($channelNum -ge 36) { "5 GHz" }
            else { "Unknown" }

    Write-Status "SSID" $ssid "Green"
    Write-Status "Signal" $signal "$(if($signal -and [int]($signal -replace '%','') -ge 60){'Green'}else{'Yellow'})"
    Write-Status "Security" $auth "White"
    Write-Status "Channel" "$channel ($band)" "White"
    Write-Status "Radio" $radioType "White"

    return @{
        Available = $true
        SSID      = $ssid
        Signal    = $signal
        Auth      = $auth
        Channel   = $channel
        Band      = $band
        BSSID     = $bssid
        RxRate    = $rxRate
        TxRate    = $txRate
        RadioType = $radioType
    }
} @{ Available = $false }

# ═════════════════════════════════════════════════════════════════════════════
# 3. DNS CONFIGURATION
# ═════════════════════════════════════════════════════════════════════════════
Write-Section "DNS Configuration"
$dnsData = Invoke-Safe {
    $dnsServers = Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.ServerAddresses.Count -gt 0 } |
        Select-Object InterfaceAlias, @{N='Servers';E={$_.ServerAddresses -join ', '}}

    $cacheStats = Invoke-Safe {
        $stats = Get-DnsClientCache -ErrorAction SilentlyContinue
        @{ Count = ($stats | Measure-Object).Count }
    } @{ Count = 0 }

    $resolveTest = Invoke-Safe {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $result = Resolve-DnsName "www.google.com" -Type A -ErrorAction Stop | Select-Object -First 1
        $sw.Stop()
        @{ Success = $true; IP = $result.IPAddress; TimeMs = $sw.ElapsedMilliseconds }
    } @{ Success = $false; IP = "FAILED"; TimeMs = 0 }

    foreach ($d in $dnsServers) {
        Write-Status $d.InterfaceAlias $d.Servers "White"
    }
    Write-Status "Cache Entries" "$($cacheStats.Count)" "White"
    $resColor = if ($resolveTest.Success) { "Green" } else { "Red" }
    Write-Status "DNS Resolution" "$($resolveTest.IP) ($($resolveTest.TimeMs)ms)" $resColor

    return @{ Servers = $dnsServers; CacheCount = $cacheStats.Count; ResolveTest = $resolveTest }
} @{ Servers = @(); CacheCount = 0; ResolveTest = @{ Success = $false; IP = "N/A"; TimeMs = 0 } }

# ═════════════════════════════════════════════════════════════════════════════
# 4. ACTIVE CONNECTIONS
# ═════════════════════════════════════════════════════════════════════════════
Write-Section "Active Connections"
$connectionsData = Invoke-Safe {
    $conns = Get-NetTCPConnection -State Established -ErrorAction SilentlyContinue |
        ForEach-Object {
            $proc = Invoke-Safe { (Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue).ProcessName } "Unknown"
            @{
                LocalAddr  = "$($_.LocalAddress):$($_.LocalPort)"
                RemoteAddr = "$($_.RemoteAddress):$($_.RemotePort)"
                State      = "$($_.State)"
                PID        = $_.OwningProcess
                Process    = $proc
            }
        }
    Write-Status "Active TCP" "$($conns.Count) established connections" "White"
    return $conns
} @()

# ═════════════════════════════════════════════════════════════════════════════
# 5. LISTENING PORTS
# ═════════════════════════════════════════════════════════════════════════════
Write-Section "Listening Ports"
$listeningData = Invoke-Safe {
    $listeners = Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
        ForEach-Object {
            $proc = Invoke-Safe { (Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue).ProcessName } "Unknown"
            @{
                LocalAddr = "$($_.LocalAddress):$($_.LocalPort)"
                Port      = $_.LocalPort
                PID       = $_.OwningProcess
                Process   = $proc
            }
        } | Sort-Object { $_.Port }
    Write-Status "Listening" "$($listeners.Count) ports" "White"
    return $listeners
} @()

# ═════════════════════════════════════════════════════════════════════════════
# 6. ROUTING TABLE
# ═════════════════════════════════════════════════════════════════════════════
Write-Section "Routing Table"
$routeData = Invoke-Safe {
    $routes = Get-NetRoute -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Select-Object DestinationPrefix, NextHop, RouteMetric, InterfaceAlias |
        Sort-Object RouteMetric
    Write-Status "Routes" "$($routes.Count) IPv4 routes" "White"
    return $routes
} @()

# ═════════════════════════════════════════════════════════════════════════════
# 7. ARP TABLE
# ═════════════════════════════════════════════════════════════════════════════
Write-Section "ARP Table"
$arpData = Invoke-Safe {
    $arp = Get-NetNeighbor -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.State -ne "Unreachable" } |
        Select-Object IPAddress, LinkLayerAddress, State, InterfaceAlias
    Write-Status "ARP Entries" "$($arp.Count) reachable entries" "White"

    # Detect duplicate MACs (rogue device indicator)
    $macGroups = $arp | Where-Object { $_.LinkLayerAddress -and $_.LinkLayerAddress -ne "00-00-00-00-00-00" -and $_.LinkLayerAddress -ne "FF-FF-FF-FF-FF-FF" } | Group-Object LinkLayerAddress
    $dupes = $macGroups | Where-Object { $_.Count -gt 1 }
    if ($dupes) {
        Write-Status "WARNING" "$($dupes.Count) duplicate MAC(s) found - possible ARP spoofing" "Red"
        [void]$findings.Add(@{ Level = "HIGH"; Category = "ARP"; Message = "Duplicate MAC addresses detected - possible ARP spoofing"; Detail = ($dupes | ForEach-Object { "$($_.Name): $($_.Group.IPAddress -join ', ')" }) -join '; ' })
    }
    return $arp
} @()

# ═════════════════════════════════════════════════════════════════════════════
# 8. FIREWALL STATUS
# ═════════════════════════════════════════════════════════════════════════════
Write-Section "Firewall Status"
$firewallData = Invoke-Safe {
    $profiles = Get-NetFirewallProfile -ErrorAction SilentlyContinue
    $result = New-Object System.Collections.ArrayList
    foreach ($p in $profiles) {
        $rulesCount = Invoke-Safe {
            (Get-NetFirewallRule -PolicyStore ActiveStore -ErrorAction SilentlyContinue |
             Where-Object { $_.Profile -match $p.Name -or $_.Profile -eq "Any" } |
             Measure-Object).Count
        } 0
        $obj = @{
            Profile      = $p.Name
            Enabled      = $p.Enabled
            DefaultIn    = "$($p.DefaultInboundAction)"
            DefaultOut   = "$($p.DefaultOutboundAction)"
            RulesCount   = $rulesCount
        }
        [void]$result.Add($obj)
        $statusColor = if ($p.Enabled) { "Green" } else { "Red" }
        Write-Status "$($p.Name)" "$(if($p.Enabled){'ENABLED'}else{'DISABLED'}) | In:$($p.DefaultInboundAction) Out:$($p.DefaultOutboundAction)" $statusColor
        if (-not $p.Enabled) {
            [void]$findings.Add(@{ Level = "HIGH"; Category = "Firewall"; Message = "$($p.Name) firewall profile is DISABLED"; Detail = "" })
        }
    }
    return $result
} @()

# ═════════════════════════════════════════════════════════════════════════════
# 9. NETWORK SHARES
# ═════════════════════════════════════════════════════════════════════════════
Write-Section "Network Shares (SMB)"
$sharesData = Invoke-Safe {
    $shares = Get-SmbShare -ErrorAction SilentlyContinue | Where-Object { $_.Name -notmatch '^\$' -or $true }
    $result = New-Object System.Collections.ArrayList
    foreach ($s in $shares) {
        $perms = Invoke-Safe {
            (Get-SmbShareAccess -Name $s.Name -ErrorAction SilentlyContinue |
             ForEach-Object { "$($_.AccountName):$($_.AccessRight)" }) -join ", "
        } "N/A"
        $obj = @{
            Name        = $s.Name
            Path        = $s.Path
            Description = $s.Description
            Permissions = $perms
        }
        [void]$result.Add($obj)
        $shareColor = if ($s.Name -match '^\$') { "DarkGray" } else { "White" }
        Write-Status $s.Name "$($s.Path) [$perms]" $shareColor
    }
    return $result
} @()

# ═════════════════════════════════════════════════════════════════════════════
# 10. VPN STATUS
# ═════════════════════════════════════════════════════════════════════════════
Write-Section "VPN Status"
$vpnData = Invoke-Safe {
    $result = @{ ActiveVPNs = New-Object System.Collections.ArrayList; VPNSoftware = New-Object System.Collections.ArrayList }

    # Check built-in VPN connections
    $vpnConns = Get-VpnConnection -ErrorAction SilentlyContinue
    foreach ($v in $vpnConns) {
        [void]$result.ActiveVPNs.Add(@{
            Name   = $v.Name
            Type   = $v.TunnelType
            Status = "$($v.ConnectionStatus)"
        })
        Write-Status $v.Name "$($v.ConnectionStatus) ($($v.TunnelType))" "$(if($v.ConnectionStatus -eq 'Connected'){'Green'}else{'Gray'})"
    }

    # Check for VPN adapter names
    $vpnAdapters = Get-NetAdapter -ErrorAction SilentlyContinue |
        Where-Object { $_.InterfaceDescription -match "TAP-|tun|WireGuard|Fortinet|Cisco|Palo Alto|Juniper|OpenVPN|NordVPN|ExpressVPN|Surfshark|Private Internet Access|ProtonVPN|Mullvad" }
    foreach ($va in $vpnAdapters) {
        Write-Status "VPN Adapter" "$($va.InterfaceDescription) ($($va.Status))" "Cyan"
    }

    # Check for common VPN software processes
    $vpnProcesses = @("openvpn","wireguard","nordvpn","expressvpn","surfshark","protonvpn","mullvad",
                      "cisco","anyconnect","vpnagent","forticlient","fortisslvpn","pulsesecure",
                      "globalprotect","pangps","f5vpn","softether")
    $runningVPN = Get-Process -ErrorAction SilentlyContinue |
        Where-Object { $vpnProcesses -contains $_.ProcessName.ToLower() }
    foreach ($rv in $runningVPN) {
        [void]$result.VPNSoftware.Add($rv.ProcessName)
        Write-Status "VPN Process" "$($rv.ProcessName) (PID: $($rv.Id))" "Cyan"
    }

    if ($result.ActiveVPNs.Count -eq 0 -and $vpnAdapters.Count -eq 0 -and $runningVPN.Count -eq 0) {
        Write-Status "VPN" "No active VPN connections detected" "Gray"
    }
    return $result
} @{ ActiveVPNs = @(); VPNSoftware = @() }

# ═════════════════════════════════════════════════════════════════════════════
# 11. PROXY SETTINGS
# ═════════════════════════════════════════════════════════════════════════════
Write-Section "Proxy Settings"
$proxyData = Invoke-Safe {
    $result = @{}

    # System proxy (IE/WinINET)
    $regProxy = Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings" -ErrorAction SilentlyContinue
    $result.ProxyEnabled   = [bool]$regProxy.ProxyEnable
    $result.ProxyServer    = if ($regProxy.ProxyServer) { $regProxy.ProxyServer } else { "None" }
    $result.ProxyBypass    = if ($regProxy.ProxyOverride) { $regProxy.ProxyOverride } else { "None" }
    $result.AutoConfigURL  = if ($regProxy.AutoConfigURL) { $regProxy.AutoConfigURL } else { "None" }

    # WinHTTP proxy
    $winhttp = Invoke-Safe { netsh winhttp show proxy 2>$null } ""
    $result.WinHTTP = if ($winhttp) { ($winhttp | Out-String).Trim() } else { "N/A" }

    $proxyColor = if ($result.ProxyEnabled) { "Yellow" } else { "Green" }
    Write-Status "System Proxy" "$(if($result.ProxyEnabled){'ENABLED - ' + $result.ProxyServer}else{'Disabled'})" $proxyColor
    Write-Status "PAC File" $result.AutoConfigURL "White"
    Write-Status "WinHTTP" $(if($winhttp -match 'Direct access'){'Direct (no proxy)'}else{'Configured'}) "White"

    if ($result.ProxyEnabled) {
        [void]$findings.Add(@{ Level = "MEDIUM"; Category = "Proxy"; Message = "System proxy is enabled: $($result.ProxyServer)"; Detail = "Verify this proxy is legitimate" })
    }
    return $result
} @{ ProxyEnabled = $false; ProxyServer = "N/A"; WinHTTP = "N/A" }

# ═════════════════════════════════════════════════════════════════════════════
# 12. INTERNET CONNECTIVITY
# ═════════════════════════════════════════════════════════════════════════════
Write-Section "Internet Connectivity"
$connectivityData = Invoke-Safe {
    $targets = @(
        @{ Host = "8.8.8.8"; Label = "Google DNS" },
        @{ Host = "1.1.1.1"; Label = "Cloudflare DNS" },
        @{ Host = "microsoft.com"; Label = "Microsoft" }
    )
    $results = New-Object System.Collections.ArrayList
    foreach ($t in $targets) {
        $ping = Invoke-Safe {
            $p = Test-Connection -ComputerName $t.Host -Count 2 -ErrorAction Stop
            $avgMs = ($p | Measure-Object -Property ResponseTime -Average).Average
            @{ Success = $true; AvgMs = [math]::Round($avgMs, 1) }
        } @{ Success = $false; AvgMs = 0 }
        $obj = @{ Host = $t.Host; Label = $t.Label; Success = $ping.Success; AvgMs = $ping.AvgMs }
        [void]$results.Add($obj)
        $color = if ($ping.Success) { "Green" } else { "Red" }
        Write-Status "$($t.Label) ($($t.Host))" "$(if($ping.Success){"OK - $($ping.AvgMs)ms"}else{'FAILED'})" $color
    }
    return $results
} @()

# ═════════════════════════════════════════════════════════════════════════════
# 13. BANDWIDTH ESTIMATE
# ═════════════════════════════════════════════════════════════════════════════
Write-Section "Bandwidth Estimate"
$bandwidthData = Invoke-Safe {
    $url = "http://speedtest.tele2.net/1MB.zip"
    $tempFile = Join-Path $env:TEMP "pcplus_bw_test.tmp"
    try {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $wc = New-Object System.Net.WebClient
        $wc.DownloadFile($url, $tempFile)
        $sw.Stop()
        $fileSize = (Get-Item $tempFile -ErrorAction SilentlyContinue).Length
        $mbps = if ($sw.ElapsedMilliseconds -gt 0 -and $fileSize -gt 0) {
            [math]::Round(($fileSize * 8) / ($sw.ElapsedMilliseconds / 1000) / 1000000, 2)
        } else { 0 }
        Write-Status "Download" "$mbps Mbps (1MB test file, $($sw.ElapsedMilliseconds)ms)" "$(if($mbps -gt 5){'Green'}elseif($mbps -gt 1){'Yellow'}else{'Red'})"
        return @{ Success = $true; Mbps = $mbps; TimeMs = $sw.ElapsedMilliseconds; FileSize = $fileSize }
    } catch {
        Write-Status "Download" "Test failed: $($_.Exception.Message)" "Red"
        return @{ Success = $false; Mbps = 0; TimeMs = 0; FileSize = 0 }
    } finally {
        if (Test-Path $tempFile) { Remove-Item $tempFile -Force -ErrorAction SilentlyContinue }
        if ($wc) { $wc.Dispose() }
    }
} @{ Success = $false; Mbps = 0 }

# ═════════════════════════════════════════════════════════════════════════════
# 14. SUSPICIOUS NETWORK ACTIVITY
# ═════════════════════════════════════════════════════════════════════════════
Write-Section "Suspicious Network Activity Scan"
$suspiciousData = Invoke-Safe {
    $result = @{
        BadPorts          = New-Object System.Collections.ArrayList
        HighConnProcs     = New-Object System.Collections.ArrayList
        NonStdDNS         = New-Object System.Collections.ArrayList
        SuspiciousProxy   = $false
    }

    # Known suspicious ports
    $badPorts = @(4444, 5555, 1337, 31337, 6666, 6667, 6668, 6669, 1234, 12345,
                  54321, 3127, 3128, 8888, 9999, 7777, 2222, 4443, 8443, 1080,
                  9050, 9051, 9150, 4145, 1081, 3389, 5900, 5800, 65535, 31338,
                  27374, 12346, 20034, 16660, 65000, 33270, 33567, 33568)

    $allConns = Get-NetTCPConnection -ErrorAction SilentlyContinue
    foreach ($conn in $allConns) {
        if ($badPorts -contains $conn.RemotePort -and $conn.RemoteAddress -ne "127.0.0.1" -and $conn.RemoteAddress -ne "::1") {
            $proc = Invoke-Safe { (Get-Process -Id $conn.OwningProcess -ErrorAction SilentlyContinue).ProcessName } "Unknown"
            $entry = @{ RemoteAddr = "$($conn.RemoteAddress):$($conn.RemotePort)"; Port = $conn.RemotePort; Process = $proc; State = "$($conn.State)" }
            [void]$result.BadPorts.Add($entry)
            Write-Status "ALERT" "Connection to suspicious port $($conn.RemotePort) by $proc" "Red"
            [void]$findings.Add(@{ Level = "HIGH"; Category = "Suspicious Port"; Message = "Connection to port $($conn.RemotePort) by process $proc"; Detail = "$($conn.RemoteAddress):$($conn.RemotePort)" })
        }
    }

    # Processes with many outbound connections
    $procGroups = $allConns | Where-Object { $_.State -eq "Established" -and $_.RemoteAddress -ne "127.0.0.1" -and $_.RemoteAddress -ne "::1" } |
        Group-Object OwningProcess | Where-Object { $_.Count -ge 20 }
    foreach ($pg in $procGroups) {
        $proc = Invoke-Safe { (Get-Process -Id $pg.Name -ErrorAction SilentlyContinue).ProcessName } "PID:$($pg.Name)"
        [void]$result.HighConnProcs.Add(@{ Process = $proc; Count = $pg.Count })
        Write-Status "INFO" "$proc has $($pg.Count) outbound connections" "Yellow"
    }

    # Non-standard DNS servers (not well-known)
    $knownDNS = @("8.8.8.8","8.8.4.4","1.1.1.1","1.0.0.1","9.9.9.9","149.112.112.112",
                   "208.67.222.222","208.67.220.220","76.76.2.0","76.76.10.0",
                   "64.6.64.6","64.6.65.6","185.228.168.9","185.228.169.9")
    $configuredDNS = Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.ServerAddresses.Count -gt 0 }
    foreach ($iface in $configuredDNS) {
        foreach ($srv in $iface.ServerAddresses) {
            if ($srv -notmatch "^(10\.|172\.(1[6-9]|2\d|3[01])\.|192\.168\.|127\.)") {
                if ($knownDNS -notcontains $srv) {
                    [void]$result.NonStdDNS.Add(@{ Interface = $iface.InterfaceAlias; Server = $srv })
                    Write-Status "INFO" "Non-standard DNS $srv on $($iface.InterfaceAlias)" "Yellow"
                    [void]$findings.Add(@{ Level = "LOW"; Category = "DNS"; Message = "Non-standard DNS server: $srv"; Detail = "Interface: $($iface.InterfaceAlias)" })
                }
            }
        }
    }

    # SOCKS proxy detection
    $socksReg = Invoke-Safe {
        $ie = Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings" -ErrorAction SilentlyContinue
        if ($ie.ProxyServer -and $ie.ProxyServer -match "socks") {
            $result.SuspiciousProxy = $true
            Write-Status "ALERT" "SOCKS proxy configured: $($ie.ProxyServer)" "Red"
            [void]$findings.Add(@{ Level = "MEDIUM"; Category = "Proxy"; Message = "SOCKS proxy detected"; Detail = $ie.ProxyServer })
        }
    }

    if ($result.BadPorts.Count -eq 0 -and $result.HighConnProcs.Count -eq 0 -and $result.NonStdDNS.Count -eq 0 -and -not $result.SuspiciousProxy) {
        Write-Status "Status" "No suspicious network activity detected" "Green"
    }
    return $result
} @{ BadPorts = @(); HighConnProcs = @(); NonStdDNS = @(); SuspiciousProxy = $false }

# ═════════════════════════════════════════════════════════════════════════════
# GENERATE HTML REPORT
# ═════════════════════════════════════════════════════════════════════════════
Write-Section "Generating HTML Report"

$scanEnd  = Get-Date
$duration = ($scanEnd - $scanStart).TotalSeconds

# Build adapter rows
$adapterRows = ""
foreach ($a in $adapterData) {
    $statusClass = if ($a.Status -eq "Up") { "status-ok" } else { "status-warn" }
    $adapterRows += "<tr><td>$($a.Name)</td><td>$($a.Desc)</td><td class=`"$statusClass`">$($a.Status)</td><td>$($a.Speed)</td><td>$($a.MAC)</td><td>$($a.IPv4)</td><td>$($a.Gateway)</td><td>$($a.DNS)</td></tr>`n"
}

# Build connection rows (limit to 100)
$connRows = ""
$connCount = 0
foreach ($c in $connectionsData) {
    if ($connCount -ge 100) { $connRows += "<tr><td colspan='5' style='text-align:center;color:#888;'>... and $($connectionsData.Count - 100) more connections</td></tr>"; break }
    $connRows += "<tr><td>$($c.LocalAddr)</td><td>$($c.RemoteAddr)</td><td>$($c.State)</td><td>$($c.Process)</td><td>$($c.PID)</td></tr>`n"
    $connCount++
}

# Build listening rows
$listenRows = ""
foreach ($l in $listeningData) {
    $listenRows += "<tr><td>$($l.Port)</td><td>$($l.LocalAddr)</td><td>$($l.Process)</td><td>$($l.PID)</td></tr>`n"
}

# Build route rows
$routeRows = ""
foreach ($r in $routeData) {
    $routeRows += "<tr><td>$($r.DestinationPrefix)</td><td>$($r.NextHop)</td><td>$($r.RouteMetric)</td><td>$($r.InterfaceAlias)</td></tr>`n"
}

# Build ARP rows
$arpRows = ""
foreach ($a in $arpData) {
    $arpRows += "<tr><td>$($a.IPAddress)</td><td>$($a.LinkLayerAddress)</td><td>$($a.State)</td><td>$($a.InterfaceAlias)</td></tr>`n"
}

# Build firewall rows
$fwRows = ""
foreach ($f in $firewallData) {
    $statusClass = if ($f.Enabled) { "status-ok" } else { "status-bad" }
    $fwRows += "<tr><td>$($f.Profile)</td><td class=`"$statusClass`">$(if($f.Enabled){'Enabled'}else{'DISABLED'})</td><td>$($f.DefaultIn)</td><td>$($f.DefaultOut)</td><td>$($f.RulesCount)</td></tr>`n"
}

# Build shares rows
$shareRows = ""
foreach ($s in $sharesData) {
    $shareRows += "<tr><td>$($s.Name)</td><td>$($s.Path)</td><td>$($s.Description)</td><td>$($s.Permissions)</td></tr>`n"
}

# Build findings rows
$findingsRows = ""
foreach ($f in $findings) {
    $levelClass = switch ($f.Level) { "HIGH" { "status-bad" } "MEDIUM" { "status-warn" } "LOW" { "status-info" } default { "" } }
    $findingsRows += "<tr><td class=`"$levelClass`">$($f.Level)</td><td>$($f.Category)</td><td>$($f.Message)</td><td>$($f.Detail)</td></tr>`n"
}

# Build connectivity rows
$pingRows = ""
foreach ($c in $connectivityData) {
    $statusClass = if ($c.Success) { "status-ok" } else { "status-bad" }
    $pingRows += "<tr><td>$($c.Label)</td><td>$($c.Host)</td><td class=`"$statusClass`">$(if($c.Success){'OK'}else{'FAILED'})</td><td>$(if($c.Success){"$($c.AvgMs) ms"}else{'N/A'})</td></tr>`n"
}

# VPN section
$vpnHtml = ""
if ($vpnData.ActiveVPNs -and $vpnData.ActiveVPNs.Count -gt 0) {
    $vpnHtml += "<table><thead><tr><th>Name</th><th>Type</th><th>Status</th></tr></thead><tbody>"
    foreach ($v in $vpnData.ActiveVPNs) {
        $vpnHtml += "<tr><td>$($v.Name)</td><td>$($v.Type)</td><td>$($v.Status)</td></tr>"
    }
    $vpnHtml += "</tbody></table>"
} else {
    $vpnHtml = "<p style='color:#888;'>No VPN connections configured or active.</p>"
}
if ($vpnData.VPNSoftware -and $vpnData.VPNSoftware.Count -gt 0) {
    $vpnHtml += "<p style='margin-top:10px;'>Running VPN software: <strong>$($vpnData.VPNSoftware -join ', ')</strong></p>"
}

# WiFi section
$wifiHtml = ""
if ($wifiData.Available) {
    $wifiHtml = @"
<div class="card-row">
  <div class="card"><div class="card-label">SSID</div><div class="card-value" style="font-size:16px">$($wifiData.SSID)</div></div>
  <div class="card"><div class="card-label">Signal</div><div class="card-value">$($wifiData.Signal)</div></div>
  <div class="card"><div class="card-label">Security</div><div class="card-value" style="font-size:14px">$($wifiData.Auth)</div></div>
  <div class="card"><div class="card-label">Channel</div><div class="card-value">$($wifiData.Channel)</div></div>
</div>
<div class="card-row" style="margin-top:12px">
  <div class="card"><div class="card-label">Band</div><div class="card-value" style="font-size:16px">$($wifiData.Band)</div></div>
  <div class="card"><div class="card-label">Radio Type</div><div class="card-value" style="font-size:14px">$($wifiData.RadioType)</div></div>
  <div class="card"><div class="card-label">Rx Rate</div><div class="card-value" style="font-size:14px">$($wifiData.RxRate)</div></div>
  <div class="card"><div class="card-label">Tx Rate</div><div class="card-value" style="font-size:14px">$($wifiData.TxRate)</div></div>
</div>
"@
} else {
    $wifiHtml = "<p style='color:#888;'>No wireless adapter detected or WiFi is disconnected.</p>"
}

# Bandwidth section
$bwHtml = ""
if ($bandwidthData.Success) {
    $bwColor = if ($bandwidthData.Mbps -gt 20) { "#27ae60" } elseif ($bandwidthData.Mbps -gt 5) { "#f39c12" } else { "#e74c3c" }
    $bwHtml = "<div class='card-row'><div class='card'><div class='card-label'>Download Speed</div><div class='card-value' style='color:$bwColor'>$($bandwidthData.Mbps) Mbps</div></div><div class='card'><div class='card-label'>Time</div><div class='card-value' style='font-size:16px'>$($bandwidthData.TimeMs) ms</div></div><div class='card'><div class='card-label'>Test Size</div><div class='card-value' style='font-size:16px'>1 MB</div></div></div>"
} else {
    $bwHtml = "<p style='color:#e74c3c;'>Bandwidth test failed. The test server may be unreachable.</p>"
}

# Proxy section
$proxyHtml = @"
<table>
<thead><tr><th>Setting</th><th>Value</th></tr></thead>
<tbody>
<tr><td>System Proxy</td><td class="$(if($proxyData.ProxyEnabled){'status-warn'}else{'status-ok'})">$(if($proxyData.ProxyEnabled){"Enabled - $($proxyData.ProxyServer)"}else{'Disabled'})</td></tr>
<tr><td>Proxy Bypass</td><td>$($proxyData.ProxyBypass)</td></tr>
<tr><td>PAC/AutoConfig URL</td><td>$($proxyData.AutoConfigURL)</td></tr>
<tr><td>WinHTTP Proxy</td><td><pre style="margin:0;font-size:12px;white-space:pre-wrap;">$($proxyData.WinHTTP)</pre></td></tr>
</tbody>
</table>
"@

# Suspicious activity section
$suspHtml = ""
if ($suspiciousData.BadPorts -and $suspiciousData.BadPorts.Count -gt 0) {
    $suspHtml += "<h3 style='color:#e74c3c;margin-bottom:8px;'>Connections to Suspicious Ports</h3><table><thead><tr><th>Remote Address</th><th>Port</th><th>Process</th><th>State</th></tr></thead><tbody>"
    foreach ($bp in $suspiciousData.BadPorts) {
        $suspHtml += "<tr class='fail'><td>$($bp.RemoteAddr)</td><td>$($bp.Port)</td><td>$($bp.Process)</td><td>$($bp.State)</td></tr>"
    }
    $suspHtml += "</tbody></table>"
}
if ($suspiciousData.HighConnProcs -and $suspiciousData.HighConnProcs.Count -gt 0) {
    $suspHtml += "<h3 style='color:#f39c12;margin-top:16px;margin-bottom:8px;'>Processes with High Connection Counts</h3><table><thead><tr><th>Process</th><th>Connections</th></tr></thead><tbody>"
    foreach ($hp in $suspiciousData.HighConnProcs) {
        $suspHtml += "<tr><td>$($hp.Process)</td><td>$($hp.Count)</td></tr>"
    }
    $suspHtml += "</tbody></table>"
}
if ($suspiciousData.NonStdDNS -and $suspiciousData.NonStdDNS.Count -gt 0) {
    $suspHtml += "<h3 style='color:#f39c12;margin-top:16px;margin-bottom:8px;'>Non-Standard DNS Servers</h3><table><thead><tr><th>Interface</th><th>DNS Server</th></tr></thead><tbody>"
    foreach ($nd in $suspiciousData.NonStdDNS) {
        $suspHtml += "<tr><td>$($nd.Interface)</td><td>$($nd.Server)</td></tr>"
    }
    $suspHtml += "</tbody></table>"
}
if ([string]::IsNullOrEmpty($suspHtml)) {
    $suspHtml = "<p class='status-ok' style='font-size:15px;'>No suspicious network activity detected.</p>"
}

# DNS section
$dnsRows = ""
if ($dnsData.Servers) {
    foreach ($d in $dnsData.Servers) {
        $dnsRows += "<tr><td>$($d.InterfaceAlias)</td><td>$($d.Servers)</td></tr>`n"
    }
}

$overallStatus = if ($findings.Count -eq 0) { "CLEAN" }
    elseif ($findings | Where-Object { $_.Level -eq "HIGH" }) { "ISSUES DETECTED" }
    else { "REVIEW RECOMMENDED" }
$statusColor = switch ($overallStatus) { "CLEAN" { "#27ae60" } "ISSUES DETECTED" { "#e74c3c" } default { "#f39c12" } }

$html = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>PC Plus Computing - Network Snapshot - $hostName</title>
<style>
  * { margin:0; padding:0; box-sizing:border-box; }
  body { font-family:'Segoe UI',Tahoma,Geneva,Verdana,sans-serif; background:#f4f6f9; color:#333; line-height:1.5; }
  .header { background:linear-gradient(135deg,#0a1628 0%,#1a2d4a 100%); color:#fff; padding:30px 40px; }
  .header h1 { font-size:24px; margin-bottom:4px; }
  .header .subtitle { color:#8899aa; font-size:13px; }
  .header .meta { display:flex; gap:30px; margin-top:12px; font-size:13px; color:#bbb; flex-wrap:wrap; }
  .header .brand { color:#2596be; font-weight:600; font-size:18px; margin-bottom:8px; }
  .container { max-width:1200px; margin:0 auto; padding:20px; }
  .section { background:#fff; border-radius:8px; box-shadow:0 1px 3px rgba(0,0,0,0.08); padding:24px; margin-bottom:20px; }
  .section h2 { font-size:18px; color:#0a1628; margin-bottom:16px; border-bottom:2px solid #2596be; padding-bottom:8px; }
  .card-row { display:flex; gap:16px; flex-wrap:wrap; }
  .card { flex:1; min-width:140px; background:#f8f9fc; border-radius:6px; padding:16px; text-align:center; border:1px solid #e8ecf1; }
  .card-label { font-size:11px; text-transform:uppercase; color:#888; letter-spacing:0.5px; margin-bottom:4px; }
  .card-value { font-size:20px; font-weight:700; color:#0a1628; }
  table { width:100%; border-collapse:collapse; font-size:13px; }
  th { background:#f0f2f5; text-align:left; padding:10px 12px; font-weight:600; color:#555; border-bottom:2px solid #ddd; }
  td { padding:8px 12px; border-bottom:1px solid #eee; }
  tr:hover { background:#f8f9fc; }
  tr.fail td { background:#fef5f5; }
  .status-ok { color:#27ae60; font-weight:600; }
  .status-warn { color:#f39c12; font-weight:600; }
  .status-bad { color:#e74c3c; font-weight:600; }
  .status-info { color:#2596be; font-weight:600; }
  .overall-badge { display:inline-block; padding:8px 20px; border-radius:20px; font-weight:700; font-size:16px; color:#fff; }
  .footer { text-align:center; padding:20px; color:#888; font-size:12px; border-top:1px solid #e0e0e0; margin-top:20px; }
  .footer a { color:#2596be; text-decoration:none; }
  @media print { body { background:#fff; } .section { box-shadow:none; border:1px solid #ddd; } }
</style>
</head>
<body>

<div class="header">
  <div class="brand">$COMPANY_NAME</div>
  <h1>Network Snapshot Report</h1>
  <div class="subtitle">Comprehensive Network Visibility &amp; Troubleshooting Assessment</div>
  <div class="meta">
    <span>Computer: <strong>$hostName</strong></span>
    <span>Date: <strong>$scanDate</strong></span>
    <span>Duration: <strong>$([math]::Round($duration, 1))s</strong></span>
    <span>Status: <span class="overall-badge" style="background:$statusColor;font-size:12px;padding:4px 12px;">$overallStatus</span></span>
  </div>
</div>

<div class="container">

<!-- Findings Summary -->
$(if($findings.Count -gt 0){@"
<div class="section">
  <h2>Findings Summary ($($findings.Count) issue$(if($findings.Count -ne 1){'s'}))</h2>
  <table>
    <thead><tr><th style="width:80px">Level</th><th style="width:120px">Category</th><th>Description</th><th>Detail</th></tr></thead>
    <tbody>$findingsRows</tbody>
  </table>
</div>
"@})

<!-- 1. Network Adapters -->
<div class="section">
  <h2>1. Network Adapters</h2>
  <table>
    <thead><tr><th>Name</th><th>Description</th><th>Status</th><th>Speed</th><th>MAC</th><th>IPv4</th><th>Gateway</th><th>DNS</th></tr></thead>
    <tbody>$adapterRows</tbody>
  </table>
</div>

<!-- 2. WiFi Information -->
<div class="section">
  <h2>2. WiFi Information</h2>
  $wifiHtml
</div>

<!-- 3. DNS Configuration -->
<div class="section">
  <h2>3. DNS Configuration</h2>
  <div class="card-row" style="margin-bottom:16px">
    <div class="card"><div class="card-label">Cache Entries</div><div class="card-value">$($dnsData.CacheCount)</div></div>
    <div class="card"><div class="card-label">Resolution Test</div><div class="card-value" style="font-size:14px;color:$(if($dnsData.ResolveTest.Success){'#27ae60'}else{'#e74c3c'})">$(if($dnsData.ResolveTest.Success){"$($dnsData.ResolveTest.IP)"}else{'FAILED'})</div></div>
    <div class="card"><div class="card-label">Lookup Time</div><div class="card-value" style="font-size:16px">$($dnsData.ResolveTest.TimeMs) ms</div></div>
  </div>
  <table>
    <thead><tr><th>Interface</th><th>DNS Servers</th></tr></thead>
    <tbody>$dnsRows</tbody>
  </table>
</div>

<!-- 4. Active Connections -->
<div class="section">
  <h2>4. Active TCP Connections ($($connectionsData.Count) established)</h2>
  <table>
    <thead><tr><th>Local Address</th><th>Remote Address</th><th>State</th><th>Process</th><th>PID</th></tr></thead>
    <tbody>$connRows</tbody>
  </table>
</div>

<!-- 5. Listening Ports -->
<div class="section">
  <h2>5. Listening Ports ($($listeningData.Count) ports)</h2>
  <table>
    <thead><tr><th>Port</th><th>Local Address</th><th>Process</th><th>PID</th></tr></thead>
    <tbody>$listenRows</tbody>
  </table>
</div>

<!-- 6. Routing Table -->
<div class="section">
  <h2>6. Routing Table ($($routeData.Count) routes)</h2>
  <table>
    <thead><tr><th>Destination</th><th>Next Hop</th><th>Metric</th><th>Interface</th></tr></thead>
    <tbody>$routeRows</tbody>
  </table>
</div>

<!-- 7. ARP Table -->
<div class="section">
  <h2>7. ARP Table ($($arpData.Count) entries)</h2>
  <table>
    <thead><tr><th>IP Address</th><th>MAC Address</th><th>State</th><th>Interface</th></tr></thead>
    <tbody>$arpRows</tbody>
  </table>
</div>

<!-- 8. Firewall Status -->
<div class="section">
  <h2>8. Firewall Status</h2>
  <table>
    <thead><tr><th>Profile</th><th>Status</th><th>Inbound Default</th><th>Outbound Default</th><th>Rules</th></tr></thead>
    <tbody>$fwRows</tbody>
  </table>
</div>

<!-- 9. Network Shares -->
<div class="section">
  <h2>9. Network Shares (SMB)</h2>
  $(if($sharesData.Count -gt 0){"<table><thead><tr><th>Share Name</th><th>Path</th><th>Description</th><th>Permissions</th></tr></thead><tbody>$shareRows</tbody></table>"}else{"<p style='color:#888;'>No SMB shares found.</p>"})
</div>

<!-- 10. VPN Status -->
<div class="section">
  <h2>10. VPN Status</h2>
  $vpnHtml
</div>

<!-- 11. Proxy Settings -->
<div class="section">
  <h2>11. Proxy Settings</h2>
  $proxyHtml
</div>

<!-- 12. Internet Connectivity -->
<div class="section">
  <h2>12. Internet Connectivity</h2>
  <table>
    <thead><tr><th>Target</th><th>Address</th><th>Result</th><th>Latency</th></tr></thead>
    <tbody>$pingRows</tbody>
  </table>
</div>

<!-- 13. Bandwidth Estimate -->
<div class="section">
  <h2>13. Bandwidth Estimate</h2>
  $bwHtml
</div>

<!-- 14. Suspicious Network Activity -->
<div class="section">
  <h2>14. Suspicious Network Activity</h2>
  $suspHtml
</div>

</div>

<div class="footer">
  <strong>$COMPANY_NAME</strong> &mdash; $COMPANY_PHONE1 | $COMPANY_PHONE2 | <a href="https://$COMPANY_WEBSITE">$COMPANY_WEBSITE</a><br>
  Report generated: $scanDate | Duration: $([math]::Round($duration, 1))s | PowerShell $($PSVersionTable.PSVersion)
</div>

</body>
</html>
"@

$reportFile = Join-Path $ReportDir "NetworkSnapshot_${hostName}_$($scanStart.ToString('yyyyMMdd_HHmmss')).html"
try {
    $html | Out-File -FilePath $reportFile -Encoding UTF8 -Force
    Write-Host ""
    Write-Host "  Report saved: $reportFile" -ForegroundColor Green
} catch {
    Write-Host "  ERROR saving report: $($_.Exception.Message)" -ForegroundColor Red
}

# ─────────────────────────────────────────────────────────────────────────────
# SUMMARY
# ─────────────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "  ╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "  ║                    SCAN COMPLETE                            ║" -ForegroundColor Cyan
Write-Host "  ╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host "    Adapters: $($adapterData.Count) | Connections: $($connectionsData.Count) | Listening: $($listeningData.Count)" -ForegroundColor White
Write-Host "    Findings: $($findings.Count) | Duration: $([math]::Round($duration, 1))s" -ForegroundColor White
Write-Host ""

# Open report
try { Start-Process $reportFile } catch { }

Write-Host "  Press Enter to exit..." -ForegroundColor DarkGray
Read-Host

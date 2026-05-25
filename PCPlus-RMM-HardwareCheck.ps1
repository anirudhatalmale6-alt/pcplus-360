#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    PC Plus 360 - RMM Daily Hardware Check
.DESCRIPTION
    Lightweight hardware-only diagnostic for daily scheduled RMM deployment.
    Checks disk health, SMART, battery, thermal, network connectivity,
    and system resources. No CPU stress test or heavy benchmarks.
    Generates HTML report and JSON summary for RMM console.
.NOTES
    Company : PC Plus Computing
    Version : 1.0.0
    Website : pcpluscomputing.com
    Phone   : 604-760-1662
#>
param(
    [string]$UploadUrl    = "https://reports.pcpluscomputing.com/api/upload",
    [string]$ApiKey       = "",
    [string]$CustomerName = "",
    [string]$TechName     = "PC Plus RMM",
    [switch]$SkipUpload,
    [string]$OutputDir    = "C:\PCPlus360-Reports"
)

$ErrorActionPreference = "SilentlyContinue"
$ProgressPreference    = "SilentlyContinue"
$scanStart = Get-Date

function Invoke-Safe { param([scriptblock]$Block, $Default = $null); try { return (& $Block) } catch { return $Default } }

if (-not (Test-Path $OutputDir)) { New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null }

# ─────────────────────────────────────────────────────────────────────────────
# 1. SYSTEM INFO
# ─────────────────────────────────────────────────────────────────────────────
$os  = Get-CimInstance Win32_OperatingSystem
$cs  = Get-CimInstance Win32_ComputerSystem
$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
$uptime = (Get-Date) - $os.LastBootUpTime

$hw = @{}
$hw.System = @{
    ComputerName = $env:COMPUTERNAME
    OSVersion    = $os.Caption
    OSBuild      = $os.BuildNumber
    Architecture = $os.OSArchitecture
    CPUModel     = $cpu.Name.Trim()
    CPUCores     = $cpu.NumberOfCores
    CPULogical   = $cpu.NumberOfLogicalProcessors
    RAMTotalGB   = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
    RAMFreeGB    = [math]::Round(($os.FreePhysicalMemory * 1KB) / 1GB, 1)
    RAMUsedPct   = [math]::Round((1 - ($os.FreePhysicalMemory * 1KB / $cs.TotalPhysicalMemory)) * 100, 0)
    Uptime       = "{0}d {1}h {2}m" -f $uptime.Days, $uptime.Hours, $uptime.Minutes
    Manufacturer = $cs.Manufacturer
    Model        = $cs.Model
}

# ─────────────────────────────────────────────────────────────────────────────
# 2. CPU LOAD (current, not stress test)
# ─────────────────────────────────────────────────────────────────────────────
$hw.CPULoad = Invoke-Safe {
    $samples = @()
    for ($i = 0; $i -lt 3; $i++) {
        $samples += (Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average
        Start-Sleep -Milliseconds 500
    }
    @{
        CurrentPct  = [math]::Round(($samples | Measure-Object -Average).Average, 0)
        PeakPct     = [math]::Round(($samples | Measure-Object -Maximum).Maximum, 0)
        Status      = if (($samples | Measure-Object -Average).Average -gt 90) { "High" } elseif (($samples | Measure-Object -Average).Average -gt 60) { "Moderate" } else { "Normal" }
    }
} @{ CurrentPct = 0; PeakPct = 0; Status = "Unknown" }

# ─────────────────────────────────────────────────────────────────────────────
# 3. DISK HEALTH & SMART
# ─────────────────────────────────────────────────────────────────────────────
$hw.PhysicalDisks = Invoke-Safe {
    $pd = @()
    Get-PhysicalDisk | ForEach-Object {
        $bt = "$($_.BusType)"
        $rel = $null
        if ($bt -notin @("USB","SD","Unknown","Unspecified")) {
            $rel = Get-StorageReliabilityCounter -PhysicalDisk $_ -ErrorAction SilentlyContinue
        }
        $pd += @{
            Model     = $_.FriendlyName
            SizeGB    = [math]::Round($_.Size / 1GB, 0)
            MediaType = "$($_.MediaType)"
            BusType   = $bt
            Health    = "$($_.HealthStatus)"
            Temp      = if ($rel -and $rel.Temperature) { "$($rel.Temperature)C" } else { "N/A" }
            PowerOn   = if ($rel) { $rel.PowerOnHours } else { "N/A" }
            Wear      = if ($rel -and $rel.Wear) { "$($rel.Wear)%" } else { "N/A" }
            ReadErrors  = if ($rel) { $rel.ReadErrorsTotal } else { "N/A" }
            WriteErrors = if ($rel) { $rel.WriteErrorsTotal } else { "N/A" }
        }
    }
    $pd
} @()

$hw.Volumes = Invoke-Safe {
    $v = @()
    Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" | ForEach-Object {
        $v += @{
            Drive   = $_.DeviceID
            Label   = $_.VolumeName
            SizeGB  = [math]::Round($_.Size / 1GB, 1)
            FreeGB  = [math]::Round($_.FreeSpace / 1GB, 1)
            FreePct = if ($_.Size -gt 0) { [math]::Round(($_.FreeSpace / $_.Size) * 100, 1) } else { 0 }
            FileSystem = $_.FileSystem
        }
    }
    $v
} @()

$diskHealthOverall = "Healthy"
$diskAlerts = @()
foreach ($d in $hw.PhysicalDisks) {
    if ($d.Health -and $d.Health -notin @("Healthy","Unknown","")) {
        $diskHealthOverall = $d.Health
        $diskAlerts += "$($d.Model): $($d.Health)"
    }
    if ($d.Wear -ne "N/A" -and $d.Wear -ne "") {
        $wearNum = [int]($d.Wear -replace '%','')
        if ($wearNum -gt 80) { $diskAlerts += "$($d.Model): SSD wear at $($d.Wear)" }
    }
}
foreach ($v in $hw.Volumes) {
    if ($v.FreePct -lt 10) { $diskAlerts += "$($v.Drive) LOW SPACE: $($v.FreeGB) GB free ($($v.FreePct)%)" }
}

# ── Predictive Failure Analysis (SMART-based) ──
$hw.PredictiveFailure = Invoke-Safe {
    $predictions = @()
    Get-PhysicalDisk | ForEach-Object {
        $disk = $_
        $bt = "$($disk.BusType)"
        if ($bt -in @("USB","SD","Unknown","Unspecified")) { return }

        $rel = Get-StorageReliabilityCounter -PhysicalDisk $disk -ErrorAction SilentlyContinue
        if (-not $rel) { return }

        $riskLevel = "OK"
        $riskFactors = @()

        # Reallocated sector count (high = pending failure)
        if ($rel.ReadErrorsTotal -and $rel.ReadErrorsTotal -gt 0) {
            if ($rel.ReadErrorsTotal -gt 100) {
                $riskLevel = "CRITICAL"
                $riskFactors += "Read errors: $($rel.ReadErrorsTotal)"
            } elseif ($rel.ReadErrorsTotal -gt 10) {
                if ($riskLevel -ne "CRITICAL") { $riskLevel = "WARNING" }
                $riskFactors += "Read errors: $($rel.ReadErrorsTotal)"
            }
        }
        if ($rel.WriteErrorsTotal -and $rel.WriteErrorsTotal -gt 0) {
            if ($rel.WriteErrorsTotal -gt 100) {
                $riskLevel = "CRITICAL"
                $riskFactors += "Write errors: $($rel.WriteErrorsTotal)"
            } elseif ($rel.WriteErrorsTotal -gt 10) {
                if ($riskLevel -ne "CRITICAL") { $riskLevel = "WARNING" }
                $riskFactors += "Write errors: $($rel.WriteErrorsTotal)"
            }
        }

        # SSD Wear Level
        if ($rel.Wear) {
            if ($rel.Wear -gt 90) {
                $riskLevel = "CRITICAL"
                $riskFactors += "SSD wear at $($rel.Wear)% - imminent failure"
            } elseif ($rel.Wear -gt 70) {
                if ($riskLevel -ne "CRITICAL") { $riskLevel = "WARNING" }
                $riskFactors += "SSD wear at $($rel.Wear)%"
            }
        }

        # Temperature check for SSD
        if ($rel.Temperature) {
            $diskType = "$($disk.MediaType)"
            if ($diskType -eq "SSD" -and $rel.Temperature -gt 60) {
                if ($riskLevel -eq "OK") { $riskLevel = "WARNING" }
                $riskFactors += "SSD temp $($rel.Temperature)C (>60C threshold)"
            } elseif ($diskType -eq "SSD" -and $rel.Temperature -gt 70) {
                $riskLevel = "CRITICAL"
                $riskFactors += "SSD temp CRITICAL: $($rel.Temperature)C"
            }
            if ($diskType -eq "HDD" -and $rel.Temperature -gt 50) {
                if ($riskLevel -eq "OK") { $riskLevel = "WARNING" }
                $riskFactors += "HDD temp $($rel.Temperature)C (>50C threshold)"
            }
        }

        # Power-on hours (>40,000 for HDD = aging)
        if ($rel.PowerOnHours -and "$($disk.MediaType)" -eq "HDD") {
            if ($rel.PowerOnHours -gt 50000) {
                if ($riskLevel -eq "OK") { $riskLevel = "WARNING" }
                $riskFactors += "HDD power-on hours: $($rel.PowerOnHours) (>50,000)"
            }
        }

        # Windows reported health status
        if ("$($disk.HealthStatus)" -eq "Warning") {
            if ($riskLevel -eq "OK") { $riskLevel = "WARNING" }
            $riskFactors += "Windows reports Warning health status"
        } elseif ("$($disk.HealthStatus)" -notin @("Healthy","Unknown","")) {
            $riskLevel = "CRITICAL"
            $riskFactors += "Windows reports $($disk.HealthStatus) health status"
        }

        if ($riskFactors.Count -gt 0) {
            $predictions += @{
                Disk        = $disk.FriendlyName
                RiskLevel   = $riskLevel
                Factors     = $riskFactors
                Recommendation = switch ($riskLevel) {
                    "CRITICAL" { "REPLACE IMMEDIATELY - Back up all data NOW" }
                    "WARNING"  { "Schedule replacement - Monitor closely" }
                    default    { "Continue monitoring" }
                }
            }
            $diskAlerts += "$($disk.FriendlyName): PREDICTIVE $riskLevel - $($riskFactors -join '; ')"
        }
    }
    $predictions
} @()

# ── Temperature Trending & Threshold Alerts ──
$hw.ThermalAnalysis = @()
foreach ($tz in $hw.Thermal) {
    $status = "Normal"
    $threshold = ""
    if ($tz.TempC -gt 95) {
        $status = "CRITICAL"
        $threshold = "CPU >95C - Thermal throttling/shutdown risk"
        $thermalAlerts += "$($tz.Zone): $($tz.TempC)C - CRITICAL (>95C)"
    } elseif ($tz.TempC -gt 85) {
        $status = "WARNING"
        $threshold = "CPU >85C - Performance degradation likely"
    } elseif ($tz.TempC -gt 75) {
        $status = "ELEVATED"
        $threshold = "CPU >75C - Above optimal range"
    }
    $hw.ThermalAnalysis += @{
        Zone      = $tz.Zone
        TempC     = $tz.TempC
        TempF     = $tz.TempF
        Status    = $status
        Threshold = $threshold
    }
}

# ── Battery Degradation Alert ──
$hw.BatteryAnalysis = @{ Status = "N/A"; WearLevel = 0; Alert = "" }
if ($hw.Battery.Present -and $hw.Battery.HealthPct -gt 0) {
    $wearLevel = 100 - $hw.Battery.HealthPct
    $batStatus = "Healthy"
    $batAlert = ""
    if ($wearLevel -gt 40) {
        $batStatus = "CRITICAL"
        $batAlert = "Battery degradation >40% ($([math]::Round($wearLevel,1))%) - Replacement strongly recommended"
        $diskAlerts += "Battery: CRITICAL wear $([math]::Round($wearLevel,1))%"
    } elseif ($wearLevel -gt 20) {
        $batStatus = "WARNING"
        $batAlert = "Battery degradation >20% ($([math]::Round($wearLevel,1))%) - Monitor closely"
        $diskAlerts += "Battery: WARNING wear $([math]::Round($wearLevel,1))%"
    }
    $hw.BatteryAnalysis = @{
        Status    = $batStatus
        WearLevel = [math]::Round($wearLevel, 1)
        HealthPct = $hw.Battery.HealthPct
        Alert     = $batAlert
    }
}

# ── Memory Error Detection (Windows Memory Diagnostic) ──
$hw.MemoryDiagnostics = Invoke-Safe {
    $memResults = @{ Status = "No recent test"; Errors = 0; LastTest = "N/A"; Details = "" }

    # Check MemoryDiagnostics-Results event log
    $memEvents = Get-WinEvent -FilterHashtable @{
        LogName      = 'System'
        ProviderName = 'Microsoft-Windows-MemoryDiagnostics-Results'
    } -MaxEvents 5 -ErrorAction SilentlyContinue

    if ($memEvents -and $memEvents.Count -gt 0) {
        $latest = $memEvents[0]
        $memResults.LastTest = $latest.TimeCreated.ToString("yyyy-MM-dd HH:mm")

        if ($latest.Message -match "no errors") {
            $memResults.Status = "PASS"
            $memResults.Details = "Windows Memory Diagnostic found no errors"
        } else {
            $memResults.Status = "FAIL"
            $memResults.Errors = 1
            $memResults.Details = $latest.Message.Substring(0, [math]::Min($latest.Message.Length, 200))
            $diskAlerts += "MEMORY ERROR: Windows Memory Diagnostic detected issues"
        }
    }

    # Also check for WHEA (hardware error) memory events
    $wheaEvents = Get-WinEvent -FilterHashtable @{
        LogName = 'System'
        Id      = 18,19,20,47
        ProviderName = 'Microsoft-Windows-WHEA-Logger'
        StartTime = (Get-Date).AddDays(-30)
    } -MaxEvents 10 -ErrorAction SilentlyContinue

    $memWheaErrors = @($wheaEvents | Where-Object { $_.Message -match "memory|DIMM|RAM" })
    if ($memWheaErrors.Count -gt 0) {
        $memResults.Status = "FAIL"
        $memResults.Errors += $memWheaErrors.Count
        $memResults.Details += " | WHEA memory errors: $($memWheaErrors.Count) in last 30 days"
        $diskAlerts += "MEMORY WHEA ERRORS: $($memWheaErrors.Count) hardware memory errors in 30 days"
    }

    $memResults
} @{ Status = "Unable to check"; Errors = 0; LastTest = "N/A"; Details = "" }

# ─────────────────────────────────────────────────────────────────────────────
# 4. NETWORK CONNECTIVITY
# ─────────────────────────────────────────────────────────────────────────────
$hw.Network = @{}

$hw.Network.Adapters = Invoke-Safe {
    $a = @()
    Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq "Up" } | ForEach-Object {
        $ip  = (Get-NetIPAddress -InterfaceIndex $_.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | Select-Object -First 1).IPAddress
        $dns = (Get-DnsClientServerAddress -InterfaceIndex $_.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).ServerAddresses -join ", "
        $a += @{ Name = $_.Name; IP = $ip; DNS = $dns; Speed = $_.LinkSpeed; MAC = $_.MacAddress }
    }
    $a
} @()

$hw.Network.GatewayPing = Invoke-Safe {
    $gw = (Get-NetRoute -DestinationPrefix "0.0.0.0/0" -ErrorAction Stop | Select-Object -First 1).NextHop
    if ($gw) {
        $p = Test-Connection -ComputerName $gw -Count 4 -ErrorAction Stop
        $prop = if ($p[0].PSObject.Properties['Latency']) { 'Latency' } else { 'ResponseTime' }
        $avg = ($p | Measure-Object -Property $prop -Average).Average
        $max = ($p | Measure-Object -Property $prop -Maximum).Maximum
        @{ Gateway = $gw; AvgMs = [math]::Round($avg, 1); MaxMs = [math]::Round($max, 1); Success = $true }
    } else { @{ Gateway = "N/A"; AvgMs = 0; MaxMs = 0; Success = $false } }
} @{ Gateway = "N/A"; AvgMs = 0; MaxMs = 0; Success = $false }

$hw.Network.DNSTest = Invoke-Safe {
    $start = Get-Date
    $r = Resolve-DnsName "google.com" -Type A -ErrorAction Stop
    $ms = ((Get-Date) - $start).TotalMilliseconds
    @{ Success = $true; ResponseMs = [math]::Round($ms, 0); Resolved = $r[0].IP4Address }
} @{ Success = $false; ResponseMs = 0; Resolved = "Failed" }

$hw.Network.InternetTest = Invoke-Safe {
    $start = Get-Date
    Invoke-WebRequest -Uri "https://www.google.com" -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop | Out-Null
    @{ Success = $true; ResponseMs = [math]::Round(((Get-Date) - $start).TotalMilliseconds, 0) }
} @{ Success = $false; ResponseMs = 0 }

$hw.Network.PublicIP = Invoke-Safe {
    (Invoke-RestMethod -Uri "https://api.ipify.org?format=json" -TimeoutSec 5).ip
} "Unable to determine"

# ─────────────────────────────────────────────────────────────────────────────
# 5. BATTERY (laptops)
# ─────────────────────────────────────────────────────────────────────────────
$hw.Battery = Invoke-Safe {
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
# 6. THERMAL
# ─────────────────────────────────────────────────────────────────────────────
$hw.Thermal = Invoke-Safe {
    $t = @()
    Get-CimInstance MSAcpi_ThermalZoneTemperature -Namespace root/wmi -ErrorAction Stop | ForEach-Object {
        $c = [math]::Round(($_.CurrentTemperature / 10) - 273.15, 1)
        $t += @{ Zone = $_.InstanceName; TempC = $c; TempF = [math]::Round(($c * 9/5) + 32, 1) }
    }
    $t
} @()

$thermalAlerts = @()
foreach ($tz in $hw.Thermal) {
    if ($tz.TempC -gt 85) { $thermalAlerts += "$($tz.Zone): $($tz.TempC)C - CRITICAL" }
    elseif ($tz.TempC -gt 75) { $thermalAlerts += "$($tz.Zone): $($tz.TempC)C - Warning" }
}

# ─────────────────────────────────────────────────────────────────────────────
# 7. MEMORY DETAILS
# ─────────────────────────────────────────────────────────────────────────────
$hw.MemorySlots = Invoke-Safe {
    $slots = @()
    Get-CimInstance Win32_PhysicalMemory | ForEach-Object {
        $slots += @{
            Bank     = $_.BankLabel
            Capacity = "$([math]::Round($_.Capacity / 1GB, 0)) GB"
            Speed    = "$($_.Speed) MHz"
            Type     = "$($_.MemoryType)"
            Mfg      = $_.Manufacturer
        }
    }
    $slots
} @()

# ─────────────────────────────────────────────────────────────────────────────
# 8. EVENT LOG ERRORS (last 24h)
# ─────────────────────────────────────────────────────────────────────────────
$hw.RecentErrors = Invoke-Safe {
    $cutoff = (Get-Date).AddHours(-24)
    $sysErrors = Get-WinEvent -FilterHashtable @{LogName='System'; Level=2; StartTime=$cutoff} -MaxEvents 10 -ErrorAction SilentlyContinue
    $appErrors = Get-WinEvent -FilterHashtable @{LogName='Application'; Level=2; StartTime=$cutoff} -MaxEvents 10 -ErrorAction SilentlyContinue
    $errors = @()
    foreach ($e in ($sysErrors + $appErrors)) {
        $errors += @{
            Time    = $e.TimeCreated.ToString("HH:mm:ss")
            Source  = $e.ProviderName
            ID      = $e.Id
            Message = ($e.Message -split "`n")[0].Substring(0, [math]::Min(($e.Message -split "`n")[0].Length, 120))
            Log     = $e.LogName
        }
    }
    $errors | Sort-Object Time -Descending | Select-Object -First 15
} @()

# ─────────────────────────────────────────────────────────────────────────────
# 9. STARTUP & SERVICES
# ─────────────────────────────────────────────────────────────────────────────
$hw.StartupCount = Invoke-Safe {
    $count = 0
    $runKeys = @("HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run","HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run","HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run")
    foreach ($key in $runKeys) {
        if (Test-Path $key) { $count += @((Get-ItemProperty $key -ErrorAction SilentlyContinue).PSObject.Properties | Where-Object { $_.Name -notin @("PSPath","PSParentPath","PSChildName","PSDrive","PSProvider") }).Count }
    }
    $startupFolder = [Environment]::GetFolderPath("Startup")
    if (Test-Path $startupFolder) { $count += @(Get-ChildItem $startupFolder -File -ErrorAction SilentlyContinue).Count }
    $count
} 0

$hw.RunningServices = Invoke-Safe { (Get-Service | Where-Object { $_.Status -eq "Running" } | Measure-Object).Count } 0

# ─────────────────────────────────────────────────────────────────────────────
# 10. HEALTH SCORING
# ─────────────────────────────────────────────────────────────────────────────
$healthChecks = @(
    @{ Name="Disk Health";         Pts=20; Test={ $diskHealthOverall -eq "Healthy" } }
    @{ Name="Disk Space (>10%)";   Pts=15; Test={ ($hw.Volumes | Where-Object { $_.FreePct -lt 10 }).Count -eq 0 } }
    @{ Name="CPU Load Normal";     Pts=10; Test={ $hw.CPULoad.CurrentPct -lt 90 } }
    @{ Name="RAM Available";       Pts=10; Test={ $hw.System.RAMUsedPct -lt 90 } }
    @{ Name="Gateway Reachable";   Pts=10; Test={ $hw.Network.GatewayPing.Success } }
    @{ Name="DNS Working";         Pts=5;  Test={ $hw.Network.DNSTest.Success } }
    @{ Name="Internet Connected";  Pts=10; Test={ $hw.Network.InternetTest.Success } }
    @{ Name="Low Latency (<50ms)"; Pts=5;  Test={ $hw.Network.GatewayPing.AvgMs -lt 50 } }
    @{ Name="No Thermal Alerts";   Pts=10; Test={ $thermalAlerts.Count -eq 0 } }
    @{ Name="Battery OK";          Pts=5;  Test={ -not $hw.Battery.Present -or $hw.Battery.HealthPct -gt 40 } }
)

$hwScore = 0; $hwBreakdown = @(); $hwAlerts = @()
foreach ($c in $healthChecks) {
    $passed = try { & $c.Test } catch { $false }
    if ($passed) { $hwScore += $c.Pts } else { $hwAlerts += $c.Name }
    $hwBreakdown += @{ Check = $c.Name; Points = $c.Pts; Passed = $passed }
}
$hwGrade = if ($hwScore -ge 90) {"A"} elseif ($hwScore -ge 80) {"B"} elseif ($hwScore -ge 70) {"C"} elseif ($hwScore -ge 60) {"D"} else {"F"}
$hwColor = if ($hwGrade -in @("A","B")) {"#27ae60"} elseif ($hwGrade -in @("C","D")) {"#f39c12"} else {"#e74c3c"}

$passedCount = ($hwBreakdown | Where-Object { $_.Passed }).Count
$failedCount = ($hwBreakdown | Where-Object { -not $_.Passed }).Count

# ─────────────────────────────────────────────────────────────────────────────
# 11. HTML REPORT
# ─────────────────────────────────────────────────────────────────────────────
$scanDate  = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
$dateStamp = (Get-Date).ToString("yyyyMMdd-HHmmss")
$reportFile = Join-Path $OutputDir "PCPlus360-HW-$($env:COMPUTERNAME)-$dateStamp.html"

$checkRowsHtml = ""
foreach ($item in $hwBreakdown) {
    $icon = if ($item.Passed) { "&#9989;" } else { "&#10060;" }
    $cls  = if ($item.Passed) { "pass" } else { "fail" }
    $checkRowsHtml += "<tr class=`"$cls`"><td>$icon</td><td>$($item.Check)</td><td>$($item.Points) pts</td><td>$(if($item.Passed){'PASS'}else{'FAIL'})</td></tr>`n"
}

$diskRowsHtml = ""
foreach ($vol in $hw.Volumes) {
    $usedPct = if ($vol.SizeGB -gt 0) { [math]::Round((1 - $vol.FreeGB / $vol.SizeGB) * 100, 1) } else { 0 }
    $barColor = if ($usedPct -gt 90) { "#e74c3c" } elseif ($usedPct -gt 75) { "#f39c12" } else { "#27ae60" }
    $diskRowsHtml += "<tr><td><strong>$($vol.Drive)</strong></td><td>$($vol.Label)</td><td>$($vol.SizeGB) GB</td><td>$($vol.FreeGB) GB</td><td>$($vol.FreePct)%</td><td><div style=`"background:#e0e0e0;border-radius:4px;overflow:hidden;height:18px;width:120px`"><div style=`"background:${barColor};height:100%;width:${usedPct}%`"></div></div></td></tr>`n"
}

$physDiskHtml = ""
foreach ($pd in $hw.PhysicalDisks) {
    $hColor = if ($pd.Health -eq "Healthy") { "#27ae60" } else { "#e74c3c" }
    $physDiskHtml += "<tr><td>$($pd.Model)</td><td>$($pd.SizeGB) GB</td><td>$($pd.MediaType)</td><td>$($pd.BusType)</td><td style=`"color:${hColor};font-weight:bold`">$($pd.Health)</td><td>$($pd.Temp)</td><td>$($pd.PowerOn)</td><td>$($pd.Wear)</td></tr>`n"
}

$netAdapterHtml = ""
foreach ($a in $hw.Network.Adapters) {
    $netAdapterHtml += "<tr><td>$($a.Name)</td><td>$($a.IP)</td><td>$($a.DNS)</td><td>$($a.Speed)</td></tr>`n"
}

$memSlotHtml = ""
foreach ($m in $hw.MemorySlots) {
    $memSlotHtml += "<tr><td>$($m.Bank)</td><td>$($m.Capacity)</td><td>$($m.Speed)</td><td>$($m.Mfg)</td></tr>`n"
}

$errorLogHtml = ""
if ($hw.RecentErrors.Count -gt 0) {
    foreach ($e in $hw.RecentErrors) {
        $errorLogHtml += "<tr><td>$($e.Time)</td><td>$($e.Log)</td><td>$($e.Source)</td><td>$($e.ID)</td><td style=`"font-size:11px`">$($e.Message)</td></tr>`n"
    }
} else {
    $errorLogHtml = "<tr><td colspan=`"5`" style=`"text-align:center;color:#27ae60`">No errors in the last 24 hours</td></tr>"
}

$gwStatus = if ($hw.Network.GatewayPing.Success) { "<span style=`"color:#27ae60`">OK ($($hw.Network.GatewayPing.AvgMs) ms avg / $($hw.Network.GatewayPing.MaxMs) ms max)</span>" } else { "<span style=`"color:#e74c3c`">FAIL</span>" }
$dnsStatus = if ($hw.Network.DNSTest.Success) { "<span style=`"color:#27ae60`">OK ($($hw.Network.DNSTest.ResponseMs) ms)</span>" } else { "<span style=`"color:#e74c3c`">FAIL</span>" }
$inetStatus = if ($hw.Network.InternetTest.Success) { "<span style=`"color:#27ae60`">Connected ($($hw.Network.InternetTest.ResponseMs) ms)</span>" } else { "<span style=`"color:#e74c3c`">Offline</span>" }

$batteryHtml = ""
if ($hw.Battery.Present) {
    $batColor = if ($hw.Battery.HealthPct -gt 70) { "#27ae60" } elseif ($hw.Battery.HealthPct -gt 40) { "#f39c12" } else { "#e74c3c" }
    $batteryHtml = @"
<div class="section">
  <h2>&#128267; Battery</h2>
  <div class="card-row">
    <div class="card"><div class="card-label">Charge</div><div class="card-value">$($hw.Battery.Charge)%</div></div>
    <div class="card"><div class="card-label">Health</div><div class="card-value" style="color:$batColor">$($hw.Battery.HealthPct)%</div></div>
    <div class="card"><div class="card-label">Cycles</div><div class="card-value">$($hw.Battery.CycleCount)</div></div>
    <div class="card"><div class="card-label">Status</div><div class="card-value" style="font-size:14px">$($hw.Battery.Status)</div></div>
  </div>
</div>
"@
}

$thermalHtml = ""
if ($hw.Thermal.Count -gt 0) {
    $thermalRows = ""
    foreach ($tz in $hw.Thermal) {
        $tColor = if ($tz.TempC -gt 85) { "#e74c3c" } elseif ($tz.TempC -gt 75) { "#f39c12" } else { "#27ae60" }
        $thermalRows += "<tr><td>$($tz.Zone)</td><td style=`"color:${tColor};font-weight:bold`">$($tz.TempC)C / $($tz.TempF)F</td></tr>`n"
    }
    $thermalHtml = @"
<div class="section">
  <h2>&#127777; Thermal</h2>
  <table><thead><tr><th>Zone</th><th>Temperature</th></tr></thead><tbody>$thermalRows</tbody></table>
</div>
"@
}

$pctAngle = [math]::Round($hwScore * 3.6, 1)
$largeArc = if ($pctAngle -gt 180) { 1 } else { 0 }
$radians  = $pctAngle * [math]::PI / 180
$endX     = [math]::Round(50 + 40 * [math]::Sin($radians), 2)
$endY     = [math]::Round(50 - 40 * [math]::Cos($radians), 2)
$arcPath  = if ($hwScore -ge 100) { "M 50 10 A 40 40 0 1 1 49.99 10" } else { "M 50 10 A 40 40 0 $largeArc 1 $endX $endY" }

$html = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>PC Plus 360 - Daily Hardware Check - $($env:COMPUTERNAME)</title>
<style>
  * { margin:0; padding:0; box-sizing:border-box; }
  body { font-family:'Segoe UI',Tahoma,sans-serif; background:#f4f6f9; color:#333; line-height:1.5; }
  .header { background:linear-gradient(135deg,#0a3d5c 0%,#0d4b71 50%,#2596be 100%); color:#fff; padding:24px 40px; }
  .header .brand { font-size:18px; font-weight:700; margin-bottom:4px; }
  .header .tagline { font-size:11px; text-transform:uppercase; letter-spacing:2px; opacity:0.7; }
  .header h1 { font-size:22px; margin:8px 0 4px; }
  .header .meta { display:flex; gap:24px; font-size:13px; color:#ccc; flex-wrap:wrap; }
  .container { max-width:1100px; margin:0 auto; padding:20px; }
  .section { background:#fff; border-radius:8px; box-shadow:0 1px 3px rgba(0,0,0,0.08); padding:24px; margin-bottom:16px; }
  .section h2 { font-size:16px; color:#0d4b71; margin-bottom:14px; border-bottom:2px solid #2596be; padding-bottom:6px; }
  .card-row { display:flex; gap:12px; flex-wrap:wrap; }
  .card { flex:1; min-width:130px; background:#f8f9fc; border-radius:6px; padding:14px; text-align:center; border:1px solid #e8ecf1; }
  .card-label { font-size:10px; text-transform:uppercase; color:#888; letter-spacing:0.5px; margin-bottom:2px; }
  .card-value { font-size:18px; font-weight:700; color:#0d4b71; }
  .score-section { display:flex; align-items:center; gap:30px; flex-wrap:wrap; }
  .score-chart { flex-shrink:0; }
  .score-summary { flex:1; }
  .score-summary .grade-detail { font-size:13px; color:#555; margin-top:6px; }
  table { width:100%; border-collapse:collapse; font-size:13px; }
  th { background:#f0f2f5; text-align:left; padding:8px 12px; font-weight:600; color:#555; border-bottom:2px solid #ddd; font-size:11px; text-transform:uppercase; }
  td { padding:7px 12px; border-bottom:1px solid #eee; }
  tr.pass td:first-child { color:#27ae60; }
  tr.fail td { background:#fef5f5; }
  tr.fail td:first-child { color:#e74c3c; }
  .alert-box { background:#fff3cd; border:1px solid #ffc107; border-radius:6px; padding:12px 16px; margin-bottom:16px; font-size:13px; }
  .alert-box.critical { background:#f8d7da; border-color:#e74c3c; }
  .footer { text-align:center; padding:16px; color:#888; font-size:11px; border-top:1px solid #e0e0e0; margin-top:16px; }
  @media print { body { background:#fff; } .section { box-shadow:none; border:1px solid #ddd; } }
</style>
</head>
<body>

<div class="header">
  <div class="brand">PC Plus Computing</div>
  <div class="tagline">Your Security, Our Priority</div>
  <h1>Daily Hardware Health Check</h1>
  <div class="meta">
    <span>Computer: <strong>$($env:COMPUTERNAME)</strong></span>
    <span>Customer: <strong>$(if($CustomerName){$CustomerName}else{'N/A'})</strong></span>
    <span>Tech: <strong>$TechName</strong></span>
    <span>Date: <strong>$scanDate</strong></span>
  </div>
</div>

<div class="container">

$(if($diskAlerts.Count -gt 0 -or $thermalAlerts.Count -gt 0){"<div class=`"alert-box critical`"><strong>Alerts:</strong><br>$(($diskAlerts + $thermalAlerts) -join '<br>')</div>"})

<!-- Hardware Health Score -->
<div class="section">
  <h2>Hardware Health Score</h2>
  <div class="score-section">
    <div class="score-chart">
      <svg viewBox="0 0 100 100" width="160" height="160">
        <circle cx="50" cy="50" r="40" fill="none" stroke="#e0e0e0" stroke-width="8"/>
        <path d="$arcPath" fill="none" stroke="$hwColor" stroke-width="8" stroke-linecap="round"/>
        <text x="50" y="44" text-anchor="middle" font-size="22" font-weight="bold" fill="$hwColor">$hwScore</text>
        <text x="50" y="58" text-anchor="middle" font-size="10" fill="#666">/ 100</text>
        <text x="50" y="72" text-anchor="middle" font-size="16" font-weight="bold" fill="$hwColor">$hwGrade</text>
      </svg>
    </div>
    <div class="score-summary">
      <div class="grade-detail">
        <strong>$passedCount</strong> of <strong>$($hwBreakdown.Count)</strong> checks passed<br>
        $(if($hwAlerts.Count -gt 0){"<span style=`"color:#e74c3c`">Failed: $($hwAlerts -join ', ')</span>"}else{"<span style=`"color:#27ae60`">All hardware checks passed</span>"})
      </div>
    </div>
  </div>
  <table style="margin-top:14px">
    <thead><tr><th style="width:30px"></th><th>Check</th><th>Weight</th><th>Result</th></tr></thead>
    <tbody>$checkRowsHtml</tbody>
  </table>
</div>

<!-- System Overview -->
<div class="section">
  <h2>&#128187; System Overview</h2>
  <div class="card-row">
    <div class="card"><div class="card-label">OS</div><div class="card-value" style="font-size:12px">$($hw.System.OSVersion)</div></div>
    <div class="card"><div class="card-label">CPU</div><div class="card-value" style="font-size:12px">$($hw.System.CPUModel)</div></div>
    <div class="card"><div class="card-label">RAM</div><div class="card-value">$($hw.System.RAMTotalGB) GB<br><span style="font-size:11px;color:#888">$($hw.System.RAMUsedPct)% used</span></div></div>
    <div class="card"><div class="card-label">CPU Load</div><div class="card-value">$($hw.CPULoad.CurrentPct)%<br><span style="font-size:11px;color:#888">$($hw.CPULoad.Status)</span></div></div>
  </div>
  <div class="card-row" style="margin-top:8px">
    <div class="card"><div class="card-label">Make</div><div class="card-value" style="font-size:12px">$($hw.System.Manufacturer)</div></div>
    <div class="card"><div class="card-label">Model</div><div class="card-value" style="font-size:12px">$($hw.System.Model)</div></div>
    <div class="card"><div class="card-label">Uptime</div><div class="card-value" style="font-size:14px">$($hw.System.Uptime)</div></div>
    <div class="card"><div class="card-label">Cores</div><div class="card-value">$($hw.System.CPUCores)C / $($hw.System.CPULogical)T</div></div>
  </div>
</div>

<!-- Disks -->
<div class="section">
  <h2>&#128430; Physical Disks &amp; SMART</h2>
  <table>
    <thead><tr><th>Model</th><th>Size</th><th>Type</th><th>Bus</th><th>Health</th><th>Temp</th><th>Power-On Hrs</th><th>Wear</th></tr></thead>
    <tbody>$physDiskHtml</tbody>
  </table>
</div>
<div class="section">
  <h2>&#128190; Volumes</h2>
  <table>
    <thead><tr><th>Drive</th><th>Label</th><th>Total</th><th>Free</th><th>Free %</th><th>Usage</th></tr></thead>
    <tbody>$diskRowsHtml</tbody>
  </table>
</div>

<!-- RAM Slots -->
$(if($hw.MemorySlots.Count -gt 0){"<div class=`"section`"><h2>&#128204; Memory Slots</h2><table><thead><tr><th>Bank</th><th>Capacity</th><th>Speed</th><th>Manufacturer</th></tr></thead><tbody>$memSlotHtml</tbody></table></div>"})

<!-- Network -->
<div class="section">
  <h2>&#127760; Network</h2>
  <div class="card-row" style="margin-bottom:12px">
    <div class="card"><div class="card-label">Gateway</div><div class="card-value" style="font-size:12px">$gwStatus</div></div>
    <div class="card"><div class="card-label">DNS</div><div class="card-value" style="font-size:12px">$dnsStatus</div></div>
    <div class="card"><div class="card-label">Internet</div><div class="card-value" style="font-size:12px">$inetStatus</div></div>
    <div class="card"><div class="card-label">Public IP</div><div class="card-value" style="font-size:12px">$($hw.Network.PublicIP)</div></div>
  </div>
  $(if($hw.Network.Adapters.Count -gt 0){"<table><thead><tr><th>Adapter</th><th>IP</th><th>DNS</th><th>Speed</th></tr></thead><tbody>$netAdapterHtml</tbody></table>"})
</div>

$batteryHtml
$thermalHtml

<!-- Event Log Errors -->
<div class="section">
  <h2>&#9888; Event Log Errors (Last 24h)</h2>
  <table>
    <thead><tr><th>Time</th><th>Log</th><th>Source</th><th>ID</th><th>Message</th></tr></thead>
    <tbody>$errorLogHtml</tbody>
  </table>
</div>

<!-- System Activity -->
<div class="section">
  <h2>&#9881; System Activity</h2>
  <div class="card-row">
    <div class="card"><div class="card-label">Startup Programs</div><div class="card-value">$($hw.StartupCount)</div></div>
    <div class="card"><div class="card-label">Running Services</div><div class="card-value">$($hw.RunningServices)</div></div>
    <div class="card"><div class="card-label">RAM Free</div><div class="card-value">$($hw.System.RAMFreeGB) GB</div></div>
  </div>
</div>

<div class="footer">
  <strong>PC Plus Computing</strong> | pcpluscomputing.com | 604-760-1662 | 236-500-2700<br>
  PC Plus 360 Hardware Check v1.0.0 | $scanDate
</div>

</div>
</body>
</html>
"@

$html | Out-File -FilePath $reportFile -Encoding UTF8 -Force

# ─────────────────────────────────────────────────────────────────────────────
# 12. AUTO-UPLOAD
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
            scan_mode      = "Daily Hardware Check"
            scan_date      = $scanDate
            file_type      = "HTML"
            source         = "rmm-hardware"
            hardware_score = "$hwScore"
            hardware_grade = $hwGrade
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
        if (-not [string]::IsNullOrWhiteSpace($ApiKey)) { $headers["Authorization"] = "Bearer $ApiKey" }

        Invoke-RestMethod -Uri $UploadUrl -Method Post -Headers $headers -Body $fullBody -ContentType "multipart/form-data; boundary=$boundary" -TimeoutSec 60 -ErrorAction Stop | Out-Null
        $uploaded = $true
        $uploadMsg = "Upload successful"
    } catch {
        $uploaded = $false
        $uploadMsg = "Upload failed: $($_.Exception.Message)"
    }
} else {
    $uploadMsg = if ($SkipUpload) { "Upload skipped (SkipUpload flag)" } else { "Upload skipped (no URL)" }
}

# ─────────────────────────────────────────────────────────────────────────────
# 13. JSON SUMMARY
# ─────────────────────────────────────────────────────────────────────────────
$scanEnd  = Get-Date
$duration = [math]::Round(($scanEnd - $scanStart).TotalSeconds, 0)

# Build predictive failure details for JSON
$predictiveDetails = @()
foreach ($pf in $hw.PredictiveFailure) {
    $predictiveDetails += @{
        disk           = $pf.Disk
        risk_level     = $pf.RiskLevel
        factors        = $pf.Factors
        recommendation = $pf.Recommendation
    }
}

# Build thermal analysis for JSON
$thermalDetails = @()
foreach ($ta in $hw.ThermalAnalysis) {
    $thermalDetails += @{
        zone      = $ta.Zone
        temp_c    = $ta.TempC
        status    = $ta.Status
        threshold = $ta.Threshold
    }
}

# Build disk details for JSON
$diskDetails = @()
foreach ($pd in $hw.PhysicalDisks) {
    $diskDetails += @{
        model      = $pd.Model
        size_gb    = $pd.SizeGB
        media_type = $pd.MediaType
        bus_type   = $pd.BusType
        health     = $pd.Health
        temp       = $pd.Temp
        power_on   = $pd.PowerOn
        wear       = $pd.Wear
    }
}

# Build volume details for JSON
$volumeDetails = @()
foreach ($vl in $hw.Volumes) {
    $volumeDetails += @{
        drive    = $vl.Drive
        label    = $vl.Label
        size_gb  = $vl.SizeGB
        free_gb  = $vl.FreeGB
        free_pct = $vl.FreePct
    }
}

$summary = @{
    computer              = $env:COMPUTERNAME
    os                    = $hw.System.OSVersion
    hardware_score        = $hwScore
    hardware_grade        = $hwGrade
    passed_checks         = $passedCount
    failed_checks         = $failedCount
    alerts                = $hwAlerts + $diskAlerts + $thermalAlerts
    disk_health           = $diskHealthOverall
    disks                 = $diskDetails
    volumes               = $volumeDetails
    predictive_failures   = $predictiveDetails
    thermal_analysis      = $thermalDetails
    cpu_load_pct          = $hw.CPULoad.CurrentPct
    cpu_status            = $hw.CPULoad.Status
    ram_total_gb          = $hw.System.RAMTotalGB
    ram_free_gb           = $hw.System.RAMFreeGB
    ram_used_pct          = $hw.System.RAMUsedPct
    gateway_ms            = $hw.Network.GatewayPing.AvgMs
    internet              = $hw.Network.InternetTest.Success
    public_ip             = $hw.Network.PublicIP
    event_errors_24h      = $hw.RecentErrors.Count
    battery_present       = $hw.Battery.Present
    battery_health        = if ($hw.Battery.Present) { $hw.Battery.HealthPct } else { "N/A" }
    battery_wear_level    = $hw.BatteryAnalysis.WearLevel
    battery_status        = $hw.BatteryAnalysis.Status
    battery_alert         = $hw.BatteryAnalysis.Alert
    memory_diagnostic     = @{
        status    = $hw.MemoryDiagnostics.Status
        errors    = $hw.MemoryDiagnostics.Errors
        last_test = $hw.MemoryDiagnostics.LastTest
        details   = $hw.MemoryDiagnostics.Details
    }
    startup_programs      = $hw.StartupCount
    running_services      = $hw.RunningServices
    uptime                = $hw.System.Uptime
    manufacturer          = $hw.System.Manufacturer
    model                 = $hw.System.Model
    report_path           = $reportFile
    uploaded              = $uploaded
    upload_message        = $uploadMsg
    scan_seconds          = $duration
}

$summary | ConvertTo-Json -Depth 5 -Compress | Write-Output

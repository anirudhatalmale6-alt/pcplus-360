<#
.SYNOPSIS
    PC Plus Computing - Quick Risk Score (60-Second Health & Security Scanner)
.DESCRIPTION
    Instant health, security, performance, and risk scoring engine for Windows 10/11.
    Runs all checks in under 60 seconds - no stress tests, no reboots.
    Displays a branded WinForms dashboard with overall grade and category breakdowns.
    Generates an HTML report on demand.
.NOTES
    Company:  PC Plus Computing
    Website:  pcpluscomputing.com
    Phone:    604-760-1662 | 236-500-2700
    Version:  1.0.0
    Requires: PowerShell 5.1+, Windows 10/11, Administrator privileges
    Part of:  PC Plus 360 USB Diagnostic Toolkit
#>

#Requires -Version 5.1

$ErrorActionPreference = 'Continue'

# ─────────────────────────────────────────────────────────────────────────────
# ASSEMBLIES & VISUAL STYLES
# ─────────────────────────────────────────────────────────────────────────────
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

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
        $arguments = "-STA -NoProfile -ExecutionPolicy Bypass -File `"$($MyInvocation.MyCommand.Definition)`""
        Start-Process powershell.exe -ArgumentList $arguments -Verb RunAs
    } catch {
        [System.Windows.Forms.MessageBox]::Show(
            "This tool requires Administrator privileges.`nPlease right-click and 'Run as Administrator'.",
            "PC Plus Quick Risk Score - Elevation Required",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
    }
    exit
}

# ─────────────────────────────────────────────────────────────────────────────
# BRANDING CONSTANTS
# ─────────────────────────────────────────────────────────────────────────────
$COMPANY_NAME    = "PC Plus Computing"
$COMPANY_WEBSITE = "pcpluscomputing.com"
$COMPANY_PHONE1  = "604-760-1662"
$COMPANY_PHONE2  = "236-500-2700"
$COLOR_NAVY      = "#0a1628"
$COLOR_ACCENT    = "#2596be"
$COLOR_GREEN     = "#27ae60"
$COLOR_RED       = "#e74c3c"
$COLOR_ORANGE    = "#f39c12"
$COLOR_LIGHT_BG  = "#f8f9fa"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
if ([string]::IsNullOrEmpty($ScriptDir)) { $ScriptDir = Get-Location }
$ReportsDir = Join-Path $ScriptDir "reports"
if (-not (Test-Path $ReportsDir)) { New-Item -Path $ReportsDir -ItemType Directory -Force | Out-Null }

# ─────────────────────────────────────────────────────────────────────────────
# HELPER: Safe WMI/CIM call wrapper
# ─────────────────────────────────────────────────────────────────────────────
function Get-SafeCim {
    param([string]$ClassName, [string]$Namespace = "root/cimv2", [string]$Filter)
    try {
        $params = @{ ClassName = $ClassName; Namespace = $Namespace; ErrorAction = 'Stop' }
        if ($Filter) { $params['Filter'] = $Filter }
        return (Get-CimInstance @params)
    } catch { return $null }
}

# ─────────────────────────────────────────────────────────────────────────────
# CATEGORY 1: SECURITY SCORE (weight 30%)
# ─────────────────────────────────────────────────────────────────────────────
function Get-SecurityScore {
    $score = 100
    $findings = [System.Collections.ArrayList]::new()

    # --- Windows Defender real-time protection ---
    try {
        $defender = Get-MpComputerStatus -ErrorAction Stop
        if (-not $defender.RealTimeProtectionEnabled) {
            $score -= 20
            [void]$findings.Add("Windows Defender real-time protection is OFF")
        }
        if (-not $defender.AntivirusEnabled) {
            $score -= 10
            [void]$findings.Add("Antivirus engine is disabled")
        }
    } catch {
        $score -= 15
        [void]$findings.Add("Cannot query Windows Defender status")
    }

    # --- Firewall (all 3 profiles) ---
    try {
        $fwProfiles = Get-NetFirewallProfile -ErrorAction Stop
        foreach ($p in $fwProfiles) {
            if (-not $p.Enabled) {
                $score -= 5
                [void]$findings.Add("Firewall profile '$($p.Name)' is disabled")
            }
        }
    } catch {
        $score -= 10
        [void]$findings.Add("Cannot query firewall status")
    }

    # --- Windows Update last check ---
    try {
        $autoUpdate = Get-SafeCim -ClassName "Win32_QuickFixEngineering"
        if ($autoUpdate) {
            $dates = $autoUpdate | Where-Object { $_.InstalledOn } | ForEach-Object { $_.InstalledOn } | Sort-Object -Descending
            if ($dates.Count -gt 0) {
                $lastUpdate = $dates[0]
                $daysSince = (New-TimeSpan -Start $lastUpdate -End (Get-Date)).Days
                if ($daysSince -gt 90) {
                    $score -= 15
                    [void]$findings.Add("Last Windows update was $daysSince days ago (>90 days)")
                } elseif ($daysSince -gt 30) {
                    $score -= 5
                    [void]$findings.Add("Last Windows update was $daysSince days ago (>30 days)")
                }
            }
        }
    } catch {
        $score -= 5
        [void]$findings.Add("Cannot determine Windows Update history")
    }

    # --- BitLocker ---
    try {
        $bl = Get-BitLockerVolume -MountPoint "C:" -ErrorAction Stop
        if ($bl.ProtectionStatus -ne "On") {
            $score -= 10
            [void]$findings.Add("BitLocker is not enabled on C: drive")
        }
    } catch {
        $score -= 10
        [void]$findings.Add("BitLocker not available or not enabled on C:")
    }

    # --- UAC level ---
    try {
        $uacKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
        $enableLUA = (Get-ItemProperty -Path $uacKey -Name EnableLUA -ErrorAction Stop).EnableLUA
        $consentPrompt = (Get-ItemProperty -Path $uacKey -Name ConsentPromptBehaviorAdmin -ErrorAction Stop).ConsentPromptBehaviorAdmin
        if ($enableLUA -eq 0) {
            $score -= 10
            [void]$findings.Add("UAC is completely disabled")
        } elseif ($consentPrompt -eq 0) {
            $score -= 5
            [void]$findings.Add("UAC is set to never notify")
        }
    } catch {}

    # --- Guest account ---
    try {
        $guest = Get-LocalUser -Name "Guest" -ErrorAction Stop
        if ($guest.Enabled) {
            $score -= 5
            [void]$findings.Add("Guest account is enabled")
        }
    } catch {}

    # --- Password policy (max age) ---
    try {
        $netAccounts = net accounts 2>&1
        $maxAge = ($netAccounts | Select-String "Maximum password age" | ForEach-Object { ($_ -split ":\s*")[1].Trim() })
        if ($maxAge -eq "Unlimited") {
            $score -= 5
            [void]$findings.Add("Password expiration policy is set to Unlimited")
        }
    } catch {}

    # --- SMBv1 ---
    try {
        $smb1 = Get-SmbServerConfiguration -ErrorAction Stop
        if ($smb1.EnableSMB1Protocol) {
            $score -= 10
            [void]$findings.Add("SMBv1 protocol is enabled (security risk)")
        }
    } catch {}

    # --- RDP exposure ---
    try {
        $rdpKey = "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server"
        $rdpDisabled = (Get-ItemProperty -Path $rdpKey -Name fDenyTSConnections -ErrorAction Stop).fDenyTSConnections
        if ($rdpDisabled -eq 0) {
            $nla = (Get-ItemProperty -Path "$rdpKey\WinStations\RDP-Tcp" -Name UserAuthentication -ErrorAction SilentlyContinue).UserAuthentication
            if ($nla -ne 1) {
                $score -= 10
                [void]$findings.Add("RDP is enabled without Network Level Authentication")
            } else {
                $score -= 3
                [void]$findings.Add("RDP is enabled (NLA is on, but still an attack surface)")
            }
        }
    } catch {}

    if ($score -lt 0) { $score = 0 }
    return @{ Score = $score; Findings = $findings }
}

# ─────────────────────────────────────────────────────────────────────────────
# CATEGORY 2: HEALTH SCORE (weight 25%)
# ─────────────────────────────────────────────────────────────────────────────
function Get-HealthScore {
    $score = 100
    $findings = [System.Collections.ArrayList]::new()

    # --- Disk space C: ---
    try {
        $disk = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='C:'" -ErrorAction Stop
        $freePercent = [math]::Round(($disk.FreeSpace / $disk.Size) * 100, 1)
        if ($freePercent -lt 5) {
            $score -= 25
            [void]$findings.Add("C: drive critically low: $freePercent% free")
        } elseif ($freePercent -lt 10) {
            $score -= 15
            [void]$findings.Add("C: drive low: $freePercent% free")
        } elseif ($freePercent -lt 20) {
            $score -= 5
            [void]$findings.Add("C: drive space moderate: $freePercent% free")
        }
    } catch {
        $score -= 10
        [void]$findings.Add("Cannot determine C: drive space")
    }

    # --- SMART disk health (skip USB/SD to prevent hang) ---
    try {
        $physicalDisks = Get-PhysicalDisk -ErrorAction Stop
        foreach ($pd in $physicalDisks) {
            $busType = "$($pd.BusType)"
            if ($busType -notin @("USB", "SD", "Unknown", "Unspecified")) {
                try {
                    $rel = Get-StorageReliabilityCounter -PhysicalDisk $pd -ErrorAction SilentlyContinue
                    if ($rel) {
                        if ($rel.Wear -and $rel.Wear -gt 90) {
                            $score -= 15
                            [void]$findings.Add("Disk '$($pd.FriendlyName)' SSD wear at $($rel.Wear)%")
                        } elseif ($rel.Wear -and $rel.Wear -gt 70) {
                            $score -= 5
                            [void]$findings.Add("Disk '$($pd.FriendlyName)' SSD wear at $($rel.Wear)%")
                        }
                        if ($rel.ReadErrorsTotal -and $rel.ReadErrorsTotal -gt 0) {
                            $score -= 10
                            [void]$findings.Add("Disk '$($pd.FriendlyName)' has $($rel.ReadErrorsTotal) read errors")
                        }
                    }
                } catch {}
                $status = "$($pd.HealthStatus)"
                if ($status -ne "Healthy") {
                    $score -= 20
                    [void]$findings.Add("Disk '$($pd.FriendlyName)' health status: $status")
                }
            }
        }
    } catch {}

    # --- RAM usage ---
    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        $totalMB = [math]::Round($os.TotalVisibleMemorySize / 1024)
        $freeMB  = [math]::Round($os.FreePhysicalMemory / 1024)
        $usedPct = [math]::Round((($totalMB - $freeMB) / $totalMB) * 100, 1)
        if ($usedPct -gt 95) {
            $score -= 20
            [void]$findings.Add("RAM usage critical: $usedPct% ($freeMB MB free of $totalMB MB)")
        } elseif ($usedPct -gt 85) {
            $score -= 10
            [void]$findings.Add("RAM usage high: $usedPct% ($freeMB MB free of $totalMB MB)")
        }
    } catch {
        $score -= 5
        [void]$findings.Add("Cannot query RAM usage")
    }

    # --- CPU temperature (best effort via WMI thermal zone) ---
    try {
        $temp = Get-SafeCim -ClassName "MSAcpi_ThermalZoneTemperature" -Namespace "root/WMI"
        if ($temp) {
            foreach ($t in $temp) {
                $celsius = [math]::Round(($t.CurrentTemperature - 2732) / 10, 1)
                if ($celsius -gt 90) {
                    $score -= 15
                    [void]$findings.Add("CPU temperature very high: ${celsius}C")
                } elseif ($celsius -gt 75) {
                    $score -= 5
                    [void]$findings.Add("CPU temperature elevated: ${celsius}C")
                }
            }
        }
    } catch {}

    # --- Pending reboot ---
    try {
        $pendingReboot = $false
        $cbsKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending"
        $wuKey  = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired"
        if (Test-Path $cbsKey) { $pendingReboot = $true }
        if (Test-Path $wuKey)  { $pendingReboot = $true }
        if ($pendingReboot) {
            $score -= 10
            [void]$findings.Add("System has a pending reboot")
        }
    } catch {}

    # --- Windows activation ---
    try {
        $slmgr = Get-SafeCim -ClassName "SoftwareLicensingProduct" -Filter "ApplicationId='55c92734-d682-4d71-983e-d6ec3f16059f' AND LicenseStatus=1"
        if (-not $slmgr) {
            $score -= 10
            [void]$findings.Add("Windows may not be properly activated")
        }
    } catch {}

    # --- System uptime ---
    try {
        $bootTime = (Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop).LastBootUpTime
        $uptimeDays = (New-TimeSpan -Start $bootTime -End (Get-Date)).Days
        if ($uptimeDays -gt 30) {
            $score -= 10
            [void]$findings.Add("System uptime: $uptimeDays days (reboot recommended)")
        } elseif ($uptimeDays -gt 14) {
            $score -= 3
            [void]$findings.Add("System uptime: $uptimeDays days")
        }
    } catch {}

    if ($score -lt 0) { $score = 0 }
    return @{ Score = $score; Findings = $findings }
}

# ─────────────────────────────────────────────────────────────────────────────
# CATEGORY 3: PERFORMANCE SCORE (weight 20%)
# ─────────────────────────────────────────────────────────────────────────────
function Get-PerformanceScore {
    $score = 100
    $findings = [System.Collections.ArrayList]::new()

    # --- Startup programs count ---
    try {
        $startupItems = @()
        $startupItems += Get-CimInstance -ClassName Win32_StartupCommand -ErrorAction SilentlyContinue
        $regPaths = @(
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run",
            "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run",
            "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run"
        )
        foreach ($rp in $regPaths) {
            if (Test-Path $rp) {
                $props = Get-ItemProperty -Path $rp -ErrorAction SilentlyContinue
                if ($props) {
                    $propNames = $props.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' } | ForEach-Object { $_.Name }
                    $startupItems += $propNames
                }
            }
        }
        $startupCount = ($startupItems | Select-Object -Unique).Count
        if ($startupCount -gt 25) {
            $score -= 20
            [void]$findings.Add("Excessive startup programs: $startupCount items")
        } elseif ($startupCount -gt 15) {
            $score -= 10
            [void]$findings.Add("Many startup programs: $startupCount items")
        } elseif ($startupCount -gt 10) {
            $score -= 5
            [void]$findings.Add("$startupCount startup programs configured")
        }
    } catch {}

    # --- Running services count ---
    try {
        $runningServices = (Get-Service | Where-Object { $_.Status -eq 'Running' }).Count
        if ($runningServices -gt 200) {
            $score -= 10
            [void]$findings.Add("High number of running services: $runningServices")
        } elseif ($runningServices -gt 150) {
            $score -= 5
            [void]$findings.Add("$runningServices services running")
        }
    } catch {}

    # --- Memory pressure (commit charge vs physical) ---
    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        $commitPct = [math]::Round(($os.TotalVirtualMemorySize - $os.FreeVirtualMemory) / $os.TotalVirtualMemorySize * 100, 1)
        if ($commitPct -gt 90) {
            $score -= 15
            [void]$findings.Add("Memory commit charge critical: $commitPct%")
        } elseif ($commitPct -gt 75) {
            $score -= 5
            [void]$findings.Add("Memory commit charge elevated: $commitPct%")
        }
    } catch {}

    # --- Disk queue length (quick snapshot) ---
    try {
        $counter = Get-Counter '\PhysicalDisk(_Total)\Current Disk Queue Length' -SampleInterval 1 -MaxSamples 1 -ErrorAction Stop
        $queueLen = $counter.CounterSamples[0].CookedValue
        if ($queueLen -gt 5) {
            $score -= 15
            [void]$findings.Add("Disk queue length very high: $([math]::Round($queueLen,1))")
        } elseif ($queueLen -gt 2) {
            $score -= 5
            [void]$findings.Add("Disk queue length elevated: $([math]::Round($queueLen,1))")
        }
    } catch {}

    # --- Page file usage ---
    try {
        $pageFiles = Get-CimInstance -ClassName Win32_PageFileUsage -ErrorAction Stop
        foreach ($pf in $pageFiles) {
            if ($pf.AllocatedBaseSize -gt 0) {
                $pfUsePct = [math]::Round(($pf.CurrentUsage / $pf.AllocatedBaseSize) * 100, 1)
                if ($pfUsePct -gt 80) {
                    $score -= 15
                    [void]$findings.Add("Page file usage high: $pfUsePct%")
                } elseif ($pfUsePct -gt 50) {
                    $score -= 5
                    [void]$findings.Add("Page file usage moderate: $pfUsePct%")
                }
            }
        }
    } catch {}

    if ($score -lt 0) { $score = 0 }
    return @{ Score = $score; Findings = $findings }
}

# ─────────────────────────────────────────────────────────────────────────────
# CATEGORY 4: RISK SCORE (weight 25%)
# ─────────────────────────────────────────────────────────────────────────────
function Get-RiskScore {
    $score = 100
    $findings = [System.Collections.ArrayList]::new()

    # --- Browser extensions count (Chrome + Edge) ---
    try {
        $extCount = 0
        $chromePath = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Extensions"
        $edgePath   = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Extensions"
        if (Test-Path $chromePath) {
            $chromeExts = (Get-ChildItem -Path $chromePath -Directory -ErrorAction SilentlyContinue).Count
            $extCount += $chromeExts
        }
        if (Test-Path $edgePath) {
            $edgeExts = (Get-ChildItem -Path $edgePath -Directory -ErrorAction SilentlyContinue).Count
            $extCount += $edgeExts
        }
        if ($extCount -gt 20) {
            $score -= 15
            [void]$findings.Add("Excessive browser extensions installed: $extCount")
        } elseif ($extCount -gt 10) {
            $score -= 5
            [void]$findings.Add("$extCount browser extensions installed")
        }
    } catch {}

    # --- Suspicious startup entries (scripts, temp paths, appdata) ---
    try {
        $suspCount = 0
        $suspNames = [System.Collections.ArrayList]::new()
        $regPaths = @(
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run",
            "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
        )
        foreach ($rp in $regPaths) {
            if (Test-Path $rp) {
                $props = Get-ItemProperty -Path $rp -ErrorAction SilentlyContinue
                if ($props) {
                    $props.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' } | ForEach-Object {
                        $val = "$($_.Value)"
                        if ($val -match '(?i)(\\temp\\|\\tmp\\|\.vbs|\.bat|\.cmd|powershell.*-enc|mshta|wscript|cscript)') {
                            $suspCount++
                            [void]$suspNames.Add($_.Name)
                        }
                    }
                }
            }
        }
        if ($suspCount -gt 0) {
            $score -= ($suspCount * 10)
            [void]$findings.Add("$suspCount suspicious startup entries: $($suspNames -join ', ')")
        }
    } catch {}

    # --- Remote access tools ---
    try {
        $ratNames = @("TeamViewer", "AnyDesk", "SupRemo", "RustDesk", "UltraVNC",
                       "TightVNC", "RealVNC", "LogMeIn", "Splashtop", "ConnectWise",
                       "BeyondTrust", "GoToAssist", "GoToMyPC", "Ammyy Admin")
        $ratFound = [System.Collections.ArrayList]::new()
        $installedApps = Get-SafeCim -ClassName "Win32_Product"
        $regUninstall = @(
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
            "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
        )
        $regApps = foreach ($ru in $regUninstall) {
            try { Get-ItemProperty -Path $ru -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName } } catch {}
        }
        $allNames = @()
        if ($installedApps) { $allNames += $installedApps | ForEach-Object { $_.Name } }
        if ($regApps)       { $allNames += $regApps | ForEach-Object { $_.DisplayName } }
        foreach ($rat in $ratNames) {
            if ($allNames | Where-Object { $_ -match [regex]::Escape($rat) }) {
                [void]$ratFound.Add($rat)
            }
        }
        if ($ratFound.Count -gt 1) {
            $score -= 15
            [void]$findings.Add("Multiple remote access tools found: $($ratFound -join ', ')")
        } elseif ($ratFound.Count -eq 1) {
            $score -= 5
            [void]$findings.Add("Remote access tool installed: $($ratFound[0])")
        }
    } catch {}

    # --- Open ports (listening) ---
    try {
        $listeners = Get-NetTCPConnection -State Listen -ErrorAction Stop
        $riskyPorts = @(21, 23, 25, 445, 3389, 5900, 5985, 5986, 8080, 8443)
        $openRisky = [System.Collections.ArrayList]::new()
        foreach ($l in $listeners) {
            if ($l.LocalPort -in $riskyPorts -and $l.LocalAddress -notmatch '^127\.') {
                [void]$openRisky.Add($l.LocalPort)
            }
        }
        $openRisky = $openRisky | Select-Object -Unique
        if ($openRisky.Count -gt 3) {
            $score -= 15
            [void]$findings.Add("$($openRisky.Count) risky ports open: $($openRisky -join ', ')")
        } elseif ($openRisky.Count -gt 0) {
            $score -= 5
            [void]$findings.Add("Risky ports listening: $($openRisky -join ', ')")
        }
    } catch {}

    # --- Outdated / EOL software ---
    try {
        $eolPatterns = @(
            @{ Name = "Java [678]\b"; Label = "Java 6/7/8 (End of public updates)" },
            @{ Name = "Adobe Flash"; Label = "Adobe Flash Player (EOL)" },
            @{ Name = "Internet Explorer"; Label = "Internet Explorer (EOL)" },
            @{ Name = "Windows 7"; Label = "Windows 7 components (EOL)" },
            @{ Name = "Silverlight"; Label = "Microsoft Silverlight (EOL)" },
            @{ Name = "Python 2\."; Label = "Python 2.x (EOL)" },
            @{ Name = "\.NET Framework [1-3]\."; Label = ".NET Framework 1-3 (legacy)" }
        )
        $eolFound = [System.Collections.ArrayList]::new()
        $allAppNames = @()
        foreach ($ru in @("HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
                          "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*")) {
            try {
                $items = Get-ItemProperty -Path $ru -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName }
                if ($items) { $allAppNames += $items | ForEach-Object { $_.DisplayName } }
            } catch {}
        }
        foreach ($eol in $eolPatterns) {
            if ($allAppNames | Where-Object { $_ -match $eol.Name }) {
                [void]$eolFound.Add($eol.Label)
            }
        }
        if ($eolFound.Count -gt 0) {
            $score -= ($eolFound.Count * 5)
            [void]$findings.Add("Outdated/EOL software: $($eolFound -join '; ')")
        }
    } catch {}

    # --- Admin accounts count ---
    try {
        $admins = Get-LocalGroupMember -Group "Administrators" -ErrorAction Stop
        $adminCount = $admins.Count
        if ($adminCount -gt 3) {
            $score -= 10
            [void]$findings.Add("$adminCount administrator accounts (recommend reducing)")
        } elseif ($adminCount -gt 2) {
            $score -= 3
            [void]$findings.Add("$adminCount administrator accounts")
        }
    } catch {}

    # --- Shared folders exposed ---
    try {
        $shares = Get-SmbShare -ErrorAction Stop | Where-Object {
            $_.Name -notmatch '^\w\$' -and $_.Name -notin @('IPC$', 'ADMIN$', 'C$', 'print$')
        }
        $shareCount = ($shares | Measure-Object).Count
        if ($shareCount -gt 3) {
            $score -= 10
            [void]$findings.Add("$shareCount user-created network shares exposed")
        } elseif ($shareCount -gt 0) {
            $score -= 3
            [void]$findings.Add("$shareCount user-created network share(s): $($shares.Name -join ', ')")
        }
    } catch {}

    if ($score -lt 0) { $score = 0 }
    return @{ Score = $score; Findings = $findings }
}

# ─────────────────────────────────────────────────────────────────────────────
# GRADE CALCULATION
# ─────────────────────────────────────────────────────────────────────────────
function Get-LetterGrade {
    param([int]$Score)
    if ($Score -ge 90) { return "A" }
    if ($Score -ge 80) { return "B" }
    if ($Score -ge 70) { return "C" }
    if ($Score -ge 60) { return "D" }
    return "F"
}

function Get-GradeColor {
    param([string]$Grade)
    switch ($Grade) {
        "A" { return $COLOR_GREEN }
        "B" { return "#2ecc71" }
        "C" { return $COLOR_ORANGE }
        "D" { return "#e67e22" }
        "F" { return $COLOR_RED }
        default { return $COLOR_ACCENT }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# HTML REPORT GENERATION
# ─────────────────────────────────────────────────────────────────────────────
function Save-HtmlReport {
    param(
        [int]$Overall, [string]$Grade, [string]$GradeColor,
        [hashtable]$Security, [hashtable]$Health,
        [hashtable]$Performance, [hashtable]$Risk,
        [string]$OutputPath
    )

    $computerName = $env:COMPUTERNAME
    $userName     = $env:USERNAME
    $scanDate     = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $osInfo       = try { (Get-CimInstance Win32_OperatingSystem).Caption } catch { "Unknown" }

    # Load logo
    $logoDataUri = ""
    $logoPath = Join-Path $ScriptDir "logo-base64.txt"
    if (Test-Path $logoPath) {
        try {
            $logoB64 = (Get-Content $logoPath -Raw).Trim()
            $logoDataUri = "data:image/png;base64,$logoB64"
        } catch {}
    }
    $logoHTML = if ($logoDataUri) {
        "<img src='$logoDataUri' alt='PC Plus Computing' style='width:280px;max-width:90%;'/>"
    } else {
        "<div style='background:$COLOR_NAVY;color:#fff;padding:15px 40px;font-size:18pt;font-weight:bold;letter-spacing:3px;border-radius:6px;display:inline-block;'>PC PLUS COMPUTING</div>"
    }

    # Load QR codes
    $qrAppointmentUri = ""; $qrServiceUri = ""
    $qrAppPath = Join-Path $ScriptDir "qr-appointments.txt"
    $qrSvcPath = Join-Path $ScriptDir "qr-service-requests.txt"
    if (Test-Path $qrAppPath) { try { $qrAppointmentUri = "data:image/png;base64,$((Get-Content $qrAppPath -Raw).Trim())" } catch {} }
    if (Test-Path $qrSvcPath) { try { $qrServiceUri = "data:image/png;base64,$((Get-Content $qrSvcPath -Raw).Trim())" } catch {} }

    # Build findings rows
    $allFindings = [System.Collections.ArrayList]::new()
    foreach ($f in $Security.Findings)    { [void]$allFindings.Add(@{ Category = "Security"; Text = $f }) }
    foreach ($f in $Health.Findings)      { [void]$allFindings.Add(@{ Category = "Health"; Text = $f }) }
    foreach ($f in $Performance.Findings) { [void]$allFindings.Add(@{ Category = "Performance"; Text = $f }) }
    foreach ($f in $Risk.Findings)        { [void]$allFindings.Add(@{ Category = "Risk"; Text = $f }) }

    $findingsRows = ""
    $idx = 0
    foreach ($f in $allFindings) {
        $idx++
        $catColor = switch ($f.Category) {
            "Security"    { $COLOR_RED }
            "Health"      { $COLOR_ACCENT }
            "Performance" { $COLOR_ORANGE }
            "Risk"        { "#9b59b6" }
            default       { "#333" }
        }
        $bgColor = if ($idx % 2 -eq 0) { "#f9f9f9" } else { "#fff" }
        $findingsRows += @"
        <tr style="background:$bgColor;">
            <td style="padding:10px 15px;border-bottom:1px solid #eee;"><span style="background:$catColor;color:#fff;padding:3px 10px;border-radius:12px;font-size:11px;font-weight:600;">$($f.Category)</span></td>
            <td style="padding:10px 15px;border-bottom:1px solid #eee;color:#333;">$($f.Text)</td>
        </tr>
"@
    }
    if ($allFindings.Count -eq 0) {
        $findingsRows = "<tr><td colspan='2' style='padding:20px;text-align:center;color:#27ae60;font-weight:600;'>No issues found - system looks great!</td></tr>"
    }

    # Category bar helper
    function Get-BarHtml { param($Label, $Score, $Weight)
        $barColor = if ($Score -ge 80) { $COLOR_GREEN } elseif ($Score -ge 60) { $COLOR_ORANGE } else { $COLOR_RED }
        return @"
        <div style="margin-bottom:18px;">
            <div style="display:flex;justify-content:space-between;margin-bottom:4px;">
                <span style="font-weight:600;color:#333;">$Label</span>
                <span style="color:#666;font-size:13px;">$Score / 100 (weight: $Weight%)</span>
            </div>
            <div style="background:#e9ecef;border-radius:8px;height:22px;overflow:hidden;">
                <div style="width:${Score}%;height:100%;background:$barColor;border-radius:8px;transition:width 0.5s;"></div>
            </div>
        </div>
"@
    }

    $barsHtml  = Get-BarHtml -Label "Security" -Score $Security.Score -Weight 30
    $barsHtml += Get-BarHtml -Label "Health" -Score $Health.Score -Weight 25
    $barsHtml += Get-BarHtml -Label "Performance" -Score $Performance.Score -Weight 20
    $barsHtml += Get-BarHtml -Label "Risk" -Score $Risk.Score -Weight 25

    # Dash offset for SVG circle
    $dashOffset = [math]::Round(283 - (283 * $Overall / 100))

    # QR section
    $qrSection = ""
    if ($qrAppointmentUri -or $qrServiceUri) {
        $qrCols = ""
        if ($qrAppointmentUri) {
            $qrCols += "<div style='text-align:center;'><img src='$qrAppointmentUri' style='width:120px;height:120px;'/><br/><span style='font-size:11px;color:#666;'>Book Appointment</span></div>"
        }
        if ($qrServiceUri) {
            $qrCols += "<div style='text-align:center;'><img src='$qrServiceUri' style='width:120px;height:120px;'/><br/><span style='font-size:11px;color:#666;'>Service Request</span></div>"
        }
        $qrSection = @"
        <div style="text-align:center;margin-top:30px;padding:20px;background:#f8f9fa;border-radius:8px;">
            <div style="font-weight:600;margin-bottom:10px;color:#333;">Need Help? Scan to Get Started</div>
            <div style="display:flex;justify-content:center;gap:40px;">$qrCols</div>
        </div>
"@
    }

    $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1.0"/>
<title>PC Plus Quick Risk Score - $computerName</title>
<style>
    * { margin:0; padding:0; box-sizing:border-box; }
    body { font-family:'Segoe UI',Tahoma,Geneva,Verdana,sans-serif; background:#f0f2f5; color:#333; }
    .container { max-width:850px; margin:0 auto; padding:20px; }
    .header { background:$COLOR_NAVY; color:#fff; padding:30px; text-align:center; border-radius:12px 12px 0 0; }
    .header h1 { font-size:22pt; letter-spacing:1px; margin-top:15px; }
    .header .subtitle { font-size:11pt; color:$COLOR_ACCENT; margin-top:5px; }
    .meta { background:#fff; padding:15px 30px; display:flex; justify-content:space-between; flex-wrap:wrap; border-bottom:2px solid $COLOR_ACCENT; font-size:13px; color:#555; }
    .meta span { margin:3px 0; }
    .score-section { background:#fff; padding:40px 30px; text-align:center; }
    .grade-circle { display:inline-block; position:relative; width:160px; height:160px; }
    .grade-circle svg { transform:rotate(-90deg); }
    .grade-circle .grade-text { position:absolute; top:50%; left:50%; transform:translate(-50%,-50%); }
    .grade-circle .grade-letter { font-size:48px; font-weight:800; color:$GradeColor; }
    .grade-circle .grade-number { font-size:16px; color:#666; }
    .bars-section { background:#fff; padding:20px 30px 30px; }
    .findings-section { background:#fff; padding:20px 30px 30px; border-top:1px solid #eee; }
    .findings-section h2 { font-size:16pt; color:$COLOR_NAVY; margin-bottom:15px; }
    .footer { background:$COLOR_NAVY; color:#fff; padding:20px 30px; border-radius:0 0 12px 12px; text-align:center; font-size:12px; }
    .footer a { color:$COLOR_ACCENT; text-decoration:none; }
    @media print { body { background:#fff; } .container { max-width:100%; } }
</style>
</head>
<body>
<div class="container">
    <div class="header">
        $logoHTML
        <h1>Quick Risk Score Report</h1>
        <div class="subtitle">60-Second Health & Security Assessment</div>
    </div>
    <div class="meta">
        <span><strong>Computer:</strong> $computerName</span>
        <span><strong>User:</strong> $userName</span>
        <span><strong>OS:</strong> $osInfo</span>
        <span><strong>Scanned:</strong> $scanDate</span>
    </div>
    <div class="score-section">
        <div class="grade-circle">
            <svg width="160" height="160" viewBox="0 0 100 100">
                <circle cx="50" cy="50" r="45" fill="none" stroke="#e9ecef" stroke-width="8"/>
                <circle cx="50" cy="50" r="45" fill="none" stroke="$GradeColor" stroke-width="8"
                    stroke-dasharray="283" stroke-dashoffset="$dashOffset" stroke-linecap="round"/>
            </svg>
            <div class="grade-text">
                <div class="grade-letter">$Grade</div>
                <div class="grade-number">$Overall / 100</div>
            </div>
        </div>
        <div style="margin-top:15px;font-size:14pt;color:#555;">Overall System Score</div>
    </div>
    <div class="bars-section">
        <h2 style="font-size:16pt;color:$COLOR_NAVY;margin-bottom:15px;">Category Breakdown</h2>
        $barsHtml
    </div>
    <div class="findings-section">
        <h2>Findings & Recommendations ($($allFindings.Count) items)</h2>
        <table style="width:100%;border-collapse:collapse;">
            <thead><tr style="background:$COLOR_NAVY;color:#fff;">
                <th style="padding:10px 15px;text-align:left;width:120px;border-radius:6px 0 0 0;">Category</th>
                <th style="padding:10px 15px;text-align:left;border-radius:0 6px 0 0;">Finding</th>
            </tr></thead>
            <tbody>$findingsRows</tbody>
        </table>
    </div>
    $qrSection
    <div class="footer">
        <div style="margin-bottom:8px;font-size:14px;font-weight:600;">$COMPANY_NAME</div>
        <div>$COMPANY_PHONE1 | $COMPANY_PHONE2 | <a href="https://$COMPANY_WEBSITE">$COMPANY_WEBSITE</a></div>
        <div style="margin-top:8px;font-size:11px;color:#8899aa;">Report generated by PC Plus 360 Quick Risk Score v1.0.0</div>
    </div>
</div>
</body>
</html>
"@

    $html | Out-File -FilePath $OutputPath -Encoding UTF8 -Force
    return $OutputPath
}

# ─────────────────────────────────────────────────────────────────────────────
# WINFORMS UI
# ─────────────────────────────────────────────────────────────────────────────
function Show-ResultsWindow {
    param(
        [int]$Overall, [string]$Grade, [string]$GradeColor,
        [hashtable]$Security, [hashtable]$Health,
        [hashtable]$Performance, [hashtable]$Risk,
        [double]$ElapsedSeconds
    )

    $cNavy   = [System.Drawing.ColorTranslator]::FromHtml($COLOR_NAVY)
    $cAccent = [System.Drawing.ColorTranslator]::FromHtml($COLOR_ACCENT)
    $cGrade  = [System.Drawing.ColorTranslator]::FromHtml($GradeColor)
    $cGreen  = [System.Drawing.ColorTranslator]::FromHtml($COLOR_GREEN)
    $cRed    = [System.Drawing.ColorTranslator]::FromHtml($COLOR_RED)
    $cOrange = [System.Drawing.ColorTranslator]::FromHtml($COLOR_ORANGE)

    # --- Main Form ---
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "PC Plus Computing - Quick Risk Score"
    $form.Size = New-Object System.Drawing.Size(680, 720)
    $form.StartPosition = "CenterScreen"
    $form.FormBorderStyle = "FixedSingle"
    $form.MaximizeBox = $false
    $form.BackColor = [System.Drawing.Color]::White
    $form.Font = New-Object System.Drawing.Font("Segoe UI", 9)

    # --- Header Panel ---
    $header = New-Object System.Windows.Forms.Panel
    $header.Dock = "Top"
    $header.Height = 55
    $header.BackColor = $cNavy
    $form.Controls.Add($header)

    $headerLabel = New-Object System.Windows.Forms.Label
    $headerLabel.Text = "PC PLUS COMPUTING  -  QUICK RISK SCORE"
    $headerLabel.ForeColor = [System.Drawing.Color]::White
    $headerLabel.Font = New-Object System.Drawing.Font("Segoe UI", 13, [System.Drawing.FontStyle]::Bold)
    $headerLabel.AutoSize = $false
    $headerLabel.Size = New-Object System.Drawing.Size(660, 55)
    $headerLabel.TextAlign = "MiddleCenter"
    $header.Controls.Add($headerLabel)

    # --- Score circle (painted) ---
    $scorePanel = New-Object System.Windows.Forms.Panel
    $scorePanel.Location = New-Object System.Drawing.Point(230, 70)
    $scorePanel.Size = New-Object System.Drawing.Size(200, 200)
    $scorePanel.BackColor = [System.Drawing.Color]::White
    $form.Controls.Add($scorePanel)

    $scorePanel.Add_Paint({
        param($sender, $e)
        $g = $e.Graphics
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias

        # Background circle
        $bgPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(233, 236, 239), 10)
        $g.DrawEllipse($bgPen, 15, 15, 170, 170)
        $bgPen.Dispose()

        # Score arc
        $arcPen = New-Object System.Drawing.Pen($cGrade, 10)
        $arcPen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
        $arcPen.EndCap   = [System.Drawing.Drawing2D.LineCap]::Round
        $sweepAngle = [int]([math]::Round(360 * $Overall / 100))
        if ($sweepAngle -gt 0) {
            $g.DrawArc($arcPen, 15, 15, 170, 170, -90, $sweepAngle)
        }
        $arcPen.Dispose()

        # Grade letter
        $gradeFont = New-Object System.Drawing.Font("Segoe UI", 42, [System.Drawing.FontStyle]::Bold)
        $gradeBrush = New-Object System.Drawing.SolidBrush($cGrade)
        $sf = New-Object System.Drawing.StringFormat
        $sf.Alignment = "Center"
        $sf.LineAlignment = "Center"
        $gradeRect = New-Object System.Drawing.RectangleF(15, 25, 170, 140)
        $g.DrawString($Grade, $gradeFont, $gradeBrush, $gradeRect, $sf)
        $gradeFont.Dispose()
        $gradeBrush.Dispose()

        # Score number
        $numFont = New-Object System.Drawing.Font("Segoe UI", 13)
        $numBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::Gray)
        $numRect = New-Object System.Drawing.RectangleF(15, 115, 170, 50)
        $g.DrawString("$Overall / 100", $numFont, $numBrush, $numRect, $sf)
        $numFont.Dispose()
        $numBrush.Dispose()
        $sf.Dispose()
    })

    # --- "Overall System Score" label ---
    $lblOverall = New-Object System.Windows.Forms.Label
    $lblOverall.Text = "Overall System Score"
    $lblOverall.Font = New-Object System.Drawing.Font("Segoe UI", 11)
    $lblOverall.ForeColor = [System.Drawing.Color]::Gray
    $lblOverall.AutoSize = $false
    $lblOverall.Size = New-Object System.Drawing.Size(660, 25)
    $lblOverall.TextAlign = "MiddleCenter"
    $lblOverall.Location = New-Object System.Drawing.Point(0, 275)
    $form.Controls.Add($lblOverall)

    # --- Elapsed time ---
    $lblTime = New-Object System.Windows.Forms.Label
    $lblTime.Text = "Scan completed in $([math]::Round($ElapsedSeconds, 1)) seconds"
    $lblTime.Font = New-Object System.Drawing.Font("Segoe UI", 8)
    $lblTime.ForeColor = [System.Drawing.Color]::DarkGray
    $lblTime.AutoSize = $false
    $lblTime.Size = New-Object System.Drawing.Size(660, 18)
    $lblTime.TextAlign = "MiddleCenter"
    $lblTime.Location = New-Object System.Drawing.Point(0, 298)
    $form.Controls.Add($lblTime)

    # --- Category Bars ---
    $barY = 325
    $categories = @(
        @{ Label = "Security";    Score = $Security.Score;    Weight = "30%"; Color = $cRed },
        @{ Label = "Health";      Score = $Health.Score;      Weight = "25%"; Color = $cAccent },
        @{ Label = "Performance"; Score = $Performance.Score; Weight = "20%"; Color = $cOrange },
        @{ Label = "Risk";        Score = $Risk.Score;        Weight = "25%"; Color = [System.Drawing.ColorTranslator]::FromHtml("#9b59b6") }
    )

    foreach ($cat in $categories) {
        $barColor = if ($cat.Score -ge 80) { $cGreen } elseif ($cat.Score -ge 60) { $cOrange } else { $cRed }

        $lblCat = New-Object System.Windows.Forms.Label
        $lblCat.Text = "$($cat.Label)  ($($cat.Score)/100, weight $($cat.Weight))"
        $lblCat.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
        $lblCat.ForeColor = $cNavy
        $lblCat.Location = New-Object System.Drawing.Point(30, $barY)
        $lblCat.Size = New-Object System.Drawing.Size(600, 18)
        $form.Controls.Add($lblCat)
        $barY += 20

        # Bar background
        $barBg = New-Object System.Windows.Forms.Panel
        $barBg.Location = New-Object System.Drawing.Point(30, $barY)
        $barBg.Size = New-Object System.Drawing.Size(600, 16)
        $barBg.BackColor = [System.Drawing.Color]::FromArgb(233, 236, 239)
        $form.Controls.Add($barBg)

        # Bar fill
        $barFill = New-Object System.Windows.Forms.Panel
        $barFill.Location = New-Object System.Drawing.Point(0, 0)
        $fillWidth = [math]::Max(1, [int]([math]::Round(600 * $cat.Score / 100)))
        $barFill.Size = New-Object System.Drawing.Size($fillWidth, 16)
        $barFill.BackColor = $barColor
        $barBg.Controls.Add($barFill)

        $barY += 28
    }

    # --- Top Findings ---
    $lblFindings = New-Object System.Windows.Forms.Label
    $lblFindings.Text = "Top Findings"
    $lblFindings.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
    $lblFindings.ForeColor = $cNavy
    $lblFindings.Location = New-Object System.Drawing.Point(30, $barY + 5)
    $lblFindings.Size = New-Object System.Drawing.Size(600, 25)
    $form.Controls.Add($lblFindings)
    $barY += 30

    $allFindings = [System.Collections.ArrayList]::new()
    foreach ($f in $Security.Findings)    { [void]$allFindings.Add("[Security] $f") }
    foreach ($f in $Health.Findings)      { [void]$allFindings.Add("[Health] $f") }
    foreach ($f in $Performance.Findings) { [void]$allFindings.Add("[Performance] $f") }
    foreach ($f in $Risk.Findings)        { [void]$allFindings.Add("[Risk] $f") }

    $findingsText = if ($allFindings.Count -eq 0) {
        "No issues found - system looks great!"
    } else {
        $topItems = $allFindings | Select-Object -First 5
        ($topItems | ForEach-Object { "  * $_" }) -join "`r`n"
    }
    if ($allFindings.Count -gt 5) {
        $findingsText += "`r`n  ... and $($allFindings.Count - 5) more (see full report)"
    }

    $txtFindings = New-Object System.Windows.Forms.TextBox
    $txtFindings.Multiline = $true
    $txtFindings.ReadOnly = $true
    $txtFindings.ScrollBars = "Vertical"
    $txtFindings.Location = New-Object System.Drawing.Point(30, $barY)
    $txtFindings.Size = New-Object System.Drawing.Size(600, 100)
    $txtFindings.Font = New-Object System.Drawing.Font("Consolas", 9)
    $txtFindings.BackColor = [System.Drawing.ColorTranslator]::FromHtml($COLOR_LIGHT_BG)
    $txtFindings.Text = $findingsText
    $form.Controls.Add($txtFindings)
    $barY += 110

    # --- Buttons ---
    $btnReport = New-Object System.Windows.Forms.Button
    $btnReport.Text = "Generate Report"
    $btnReport.Location = New-Object System.Drawing.Point(190, $barY)
    $btnReport.Size = New-Object System.Drawing.Size(140, 36)
    $btnReport.BackColor = $cAccent
    $btnReport.ForeColor = [System.Drawing.Color]::White
    $btnReport.FlatStyle = "Flat"
    $btnReport.FlatAppearance.BorderSize = 0
    $btnReport.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $btnReport.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btnReport.Add_Click({
        try {
            $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
            $fileName  = "QuickRiskScore-$env:COMPUTERNAME-$timestamp.html"
            $outPath   = Join-Path $ReportsDir $fileName
            Save-HtmlReport -Overall $Overall -Grade $Grade -GradeColor $GradeColor `
                -Security $Security -Health $Health -Performance $Performance -Risk $Risk `
                -OutputPath $outPath
            [System.Windows.Forms.MessageBox]::Show(
                "Report saved to:`n$outPath",
                "Report Generated",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            )
            Start-Process $outPath
        } catch {
            [System.Windows.Forms.MessageBox]::Show(
                "Error generating report: $($_.Exception.Message)",
                "Error",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            )
        }
    })
    $form.Controls.Add($btnReport)

    $btnClose = New-Object System.Windows.Forms.Button
    $btnClose.Text = "Close"
    $btnClose.Location = New-Object System.Drawing.Point(345, $barY)
    $btnClose.Size = New-Object System.Drawing.Size(100, 36)
    $btnClose.FlatStyle = "Flat"
    $btnClose.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $btnClose.Add_Click({ $form.Close() })
    $form.Controls.Add($btnClose)

    # --- Footer ---
    $lblFooter = New-Object System.Windows.Forms.Label
    $lblFooter.Text = "$COMPANY_NAME  |  $COMPANY_PHONE1  |  $COMPANY_WEBSITE"
    $lblFooter.Font = New-Object System.Drawing.Font("Segoe UI", 8)
    $lblFooter.ForeColor = [System.Drawing.Color]::DarkGray
    $lblFooter.AutoSize = $false
    $lblFooter.Size = New-Object System.Drawing.Size(660, 20)
    $lblFooter.TextAlign = "MiddleCenter"
    $lblFooter.Location = New-Object System.Drawing.Point(0, $barY + 45)
    $form.Controls.Add($lblFooter)

    [void]$form.ShowDialog()
}

# ─────────────────────────────────────────────────────────────────────────────
# PROGRESS DIALOG (shows during scan)
# ─────────────────────────────────────────────────────────────────────────────
function Show-ProgressForm {
    $pf = New-Object System.Windows.Forms.Form
    $pf.Text = "PC Plus Quick Risk Score"
    $pf.Size = New-Object System.Drawing.Size(420, 200)
    $pf.StartPosition = "CenterScreen"
    $pf.FormBorderStyle = "FixedDialog"
    $pf.MaximizeBox = $false
    $pf.MinimizeBox = $false
    $pf.ControlBox = $false
    $pf.BackColor = [System.Drawing.Color]::White
    $pf.TopMost = $true

    $hdr = New-Object System.Windows.Forms.Panel
    $hdr.Dock = "Top"
    $hdr.Height = 40
    $hdr.BackColor = [System.Drawing.ColorTranslator]::FromHtml($COLOR_NAVY)
    $pf.Controls.Add($hdr)

    $hdrLbl = New-Object System.Windows.Forms.Label
    $hdrLbl.Text = "SCANNING SYSTEM..."
    $hdrLbl.ForeColor = [System.Drawing.Color]::White
    $hdrLbl.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
    $hdrLbl.AutoSize = $false
    $hdrLbl.Size = New-Object System.Drawing.Size(400, 40)
    $hdrLbl.TextAlign = "MiddleCenter"
    $hdr.Controls.Add($hdrLbl)

    $statusLabel = New-Object System.Windows.Forms.Label
    $statusLabel.Name = "StatusLabel"
    $statusLabel.Text = "Initializing..."
    $statusLabel.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $statusLabel.ForeColor = [System.Drawing.Color]::DimGray
    $statusLabel.Location = New-Object System.Drawing.Point(20, 60)
    $statusLabel.Size = New-Object System.Drawing.Size(370, 25)
    $statusLabel.TextAlign = "MiddleCenter"
    $pf.Controls.Add($statusLabel)

    $progressBar = New-Object System.Windows.Forms.ProgressBar
    $progressBar.Name = "ProgressBar"
    $progressBar.Location = New-Object System.Drawing.Point(20, 95)
    $progressBar.Size = New-Object System.Drawing.Size(370, 28)
    $progressBar.Style = "Continuous"
    $progressBar.Minimum = 0
    $progressBar.Maximum = 100
    $pf.Controls.Add($progressBar)

    $pctLabel = New-Object System.Windows.Forms.Label
    $pctLabel.Name = "PctLabel"
    $pctLabel.Text = "0%"
    $pctLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $pctLabel.ForeColor = [System.Drawing.Color]::Gray
    $pctLabel.Location = New-Object System.Drawing.Point(20, 128)
    $pctLabel.Size = New-Object System.Drawing.Size(370, 20)
    $pctLabel.TextAlign = "MiddleCenter"
    $pf.Controls.Add($pctLabel)

    return $pf
}

function Update-Progress {
    param($Form, [string]$Status, [int]$Percent)
    $sl = $Form.Controls.Find("StatusLabel", $false)
    $pb = $Form.Controls.Find("ProgressBar", $false)
    $pl = $Form.Controls.Find("PctLabel", $false)
    if ($sl.Count -gt 0) { $sl[0].Text = $Status }
    if ($pb.Count -gt 0) { $pb[0].Value = [math]::Min($Percent, 100) }
    if ($pl.Count -gt 0) { $pl[0].Text = "$Percent%" }
    $Form.Refresh()
    [System.Windows.Forms.Application]::DoEvents()
}

# ─────────────────────────────────────────────────────────────────────────────
# MAIN EXECUTION
# ─────────────────────────────────────────────────────────────────────────────
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

$progressForm = Show-ProgressForm
$progressForm.Show()
[System.Windows.Forms.Application]::DoEvents()

# Run each category scan
Update-Progress -Form $progressForm -Status "Checking security settings..." -Percent 5
$secResult = Get-SecurityScore
Update-Progress -Form $progressForm -Status "Security scan complete" -Percent 30

Update-Progress -Form $progressForm -Status "Checking system health..." -Percent 35
$healthResult = Get-HealthScore
Update-Progress -Form $progressForm -Status "Health check complete" -Percent 55

Update-Progress -Form $progressForm -Status "Checking performance..." -Percent 60
$perfResult = Get-PerformanceScore
Update-Progress -Form $progressForm -Status "Performance check complete" -Percent 75

Update-Progress -Form $progressForm -Status "Assessing risk factors..." -Percent 80
$riskResult = Get-RiskScore
Update-Progress -Form $progressForm -Status "Risk assessment complete" -Percent 95

# Calculate weighted overall score
$overallScore = [math]::Round(
    ($secResult.Score  * 0.30) +
    ($healthResult.Score * 0.25) +
    ($perfResult.Score * 0.20) +
    ($riskResult.Score * 0.25)
)
$overallGrade = Get-LetterGrade -Score $overallScore
$overallColor = Get-GradeColor -Grade $overallGrade

Update-Progress -Form $progressForm -Status "Done!" -Percent 100
$stopwatch.Stop()
$elapsed = $stopwatch.Elapsed.TotalSeconds

Start-Sleep -Milliseconds 400
$progressForm.Close()
$progressForm.Dispose()

# Show results
Show-ResultsWindow -Overall $overallScore -Grade $overallGrade -GradeColor $overallColor `
    -Security $secResult -Health $healthResult -Performance $perfResult -Risk $riskResult `
    -ElapsedSeconds $elapsed

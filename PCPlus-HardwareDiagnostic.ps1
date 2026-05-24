<#
.SYNOPSIS
    PC Plus Computing 360 - Comprehensive Hardware Diagnostic
.DESCRIPTION
    All-in-one hardware diagnostic tool covering CPU, Memory, Storage, GPU,
    Battery, Network, and Peripherals. Each test can run individually or all
    at once. Generates a branded HTML report with color-coded pass/warn/fail
    results and an overall hardware health score.
.NOTES
    Company:  PC Plus Computing
    Phone:    604-760-1662 | 236-500-2700
    Website:  pcpluscomputing.com
    Version:  1.0.0
    Requires: PowerShell 5.1+, Windows 10/11, Administrator privileges
    Part of:  PC Plus 360 USB Diagnostic Toolkit
.EXAMPLE
    PowerShell.exe -ExecutionPolicy Bypass -File .\PCPlus-HardwareDiagnostic.ps1
#>

#Requires -Version 5.1

$ErrorActionPreference = 'Continue'

# ─────────────────────────────────────────────────────────────────────────────
# ASSEMBLIES & VISUAL STYLES
# ─────────────────────────────────────────────────────────────────────────────
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Web
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
        $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$($MyInvocation.MyCommand.Definition)`""
        Start-Process powershell.exe -ArgumentList $arguments -Verb RunAs
    } catch {
        [System.Windows.Forms.MessageBox]::Show(
            "This tool requires Administrator privileges.`nPlease right-click and 'Run as Administrator'.",
            "$COMPANY_FULL - Elevation Required",
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
$COMPANY_FULL    = "PC Plus Computing 360"
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
# HELPER: Safe CIM wrapper with disposal
# ─────────────────────────────────────────────────────────────────────────────
function Get-SafeCim {
    param([string]$ClassName, [string]$Namespace = "root/cimv2", [string]$Filter)
    try {
        $params = @{ ClassName = $ClassName; Namespace = $Namespace; ErrorAction = 'Stop' }
        if ($Filter) { $params['Filter'] = $Filter }
        return (Get-CimInstance @params)
    } catch { return $null }
}

function Get-SafeWmi {
    param([string]$Class, [string]$Namespace = "root\cimv2", [string]$Filter)
    $results = $null
    try {
        $params = @{ Class = $Class; Namespace = $Namespace; ErrorAction = 'Stop' }
        if ($Filter) { $params['Filter'] = $Filter }
        $results = Get-WmiObject @params
    } catch {}
    return $results
}

function Dispose-WmiResults {
    param($Results)
    if ($null -eq $Results) { return }
    foreach ($item in $Results) {
        try {
            if ($item -is [System.Management.ManagementObject]) {
                $item.Dispose()
            }
        } catch {}
    }
}

# Status helpers
function New-TestResult {
    param(
        [string]$Name,
        [string]$Status,  # PASS, WARN, FAIL, INFO
        [string]$Value,
        [string]$Details = ""
    )
    return @{
        Name    = $Name
        Status  = $Status
        Value   = $Value
        Details = $Details
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# TEST 1: CPU DIAGNOSTIC
# ─────────────────────────────────────────────────────────────────────────────
function Test-CPU {
    param([System.Windows.Forms.Label]$StatusLabel)
    $results = [System.Collections.ArrayList]::new()

    if ($StatusLabel) { $StatusLabel.Text = "Testing CPU..." }
    [System.Windows.Forms.Application]::DoEvents()

    # Basic CPU info
    $cpu = Get-SafeCim -ClassName "Win32_Processor"
    if ($cpu) {
        $cpuObj = $cpu | Select-Object -First 1
        [void]$results.Add((New-TestResult "CPU Model" "INFO" $cpuObj.Name))
        [void]$results.Add((New-TestResult "Architecture" "INFO" $(
            switch ($cpuObj.Architecture) {
                0 { "x86 (32-bit)" }
                5 { "ARM" }
                9 { "x64 (64-bit)" }
                12 { "ARM64" }
                default { "Unknown ($($cpuObj.Architecture))" }
            }
        )))
        [void]$results.Add((New-TestResult "Cores / Logical Processors" "INFO" "$($cpuObj.NumberOfCores) cores / $($cpuObj.NumberOfLogicalProcessors) threads"))
        [void]$results.Add((New-TestResult "Base Clock Speed" "INFO" "$($cpuObj.MaxClockSpeed) MHz"))
        [void]$results.Add((New-TestResult "Current Clock Speed" "INFO" "$($cpuObj.CurrentClockSpeed) MHz"))
        [void]$results.Add((New-TestResult "Socket" "INFO" $cpuObj.SocketDesignation))
        [void]$results.Add((New-TestResult "L2 Cache" "INFO" "$([math]::Round($cpuObj.L2CacheSize / 1024, 1)) MB"))
        [void]$results.Add((New-TestResult "L3 Cache" "INFO" "$([math]::Round($cpuObj.L3CacheSize / 1024, 1)) MB"))

        # Voltage
        if ($cpuObj.CurrentVoltage -gt 0) {
            [void]$results.Add((New-TestResult "Voltage" "INFO" "$($cpuObj.CurrentVoltage / 10.0)V"))
        }

        # Load
        $loadPct = $cpuObj.LoadPercentage
        if ($null -ne $loadPct) {
            $loadStatus = if ($loadPct -gt 90) { "WARN" } else { "PASS" }
            [void]$results.Add((New-TestResult "Current Load" $loadStatus "$loadPct%" $(if ($loadPct -gt 90) { "CPU under heavy load" } else { "Normal" })))
        }
    }

    # Temperature (MSAcpi_ThermalZoneTemperature)
    if ($StatusLabel) { $StatusLabel.Text = "Testing CPU temperature..." }
    [System.Windows.Forms.Application]::DoEvents()
    try {
        $thermal = Get-SafeCim -ClassName "MSAcpi_ThermalZoneTemperature" -Namespace "root/wmi"
        if ($thermal) {
            $tempK = ($thermal | Select-Object -First 1).CurrentTemperature
            $tempC = [math]::Round(($tempK / 10.0) - 273.15, 1)
            $tempStatus = if ($tempC -gt 85) { "FAIL" } elseif ($tempC -gt 70) { "WARN" } else { "PASS" }
            $tempDetails = if ($tempC -gt 85) { "Critically high! Check cooling" } elseif ($tempC -gt 70) { "Elevated - monitor cooling" } else { "Normal range" }
            [void]$results.Add((New-TestResult "CPU Temperature" $tempStatus "${tempC}C" $tempDetails))
        } else {
            [void]$results.Add((New-TestResult "CPU Temperature" "INFO" "Unavailable" "Thermal sensor not accessible via WMI"))
        }
    } catch {
        [void]$results.Add((New-TestResult "CPU Temperature" "INFO" "Unavailable" "Thermal sensor not accessible"))
    }

    # Simple stress test (prime calculation for 30 seconds)
    if ($StatusLabel) { $StatusLabel.Text = "Running CPU stress test (30 seconds)..." }
    [System.Windows.Forms.Application]::DoEvents()
    try {
        $startTime = Get-Date
        $primeCount = 0
        $endTime = $startTime.AddSeconds(30)
        $checkpoints = [System.Collections.ArrayList]::new()
        $nextCheckpoint = $startTime.AddSeconds(5)

        while ((Get-Date) -lt $endTime) {
            # Count primes up to increasing numbers
            $candidate = $primeCount * 7 + 3
            $isPrime = $true
            if ($candidate -lt 2) { $isPrime = $false }
            else {
                $sqrtN = [math]::Sqrt($candidate)
                for ($i = 2; $i -le $sqrtN; $i++) {
                    if ($candidate % $i -eq 0) { $isPrime = $false; break }
                }
            }
            $primeCount++

            if ((Get-Date) -ge $nextCheckpoint) {
                [void]$checkpoints.Add($primeCount)
                $nextCheckpoint = $nextCheckpoint.AddSeconds(5)
                [System.Windows.Forms.Application]::DoEvents()
            }
        }

        $elapsed = ((Get-Date) - $startTime).TotalSeconds
        $opsPerSec = [math]::Round($primeCount / $elapsed)

        # Check for throttling (compare first and last 5-second intervals)
        $throttled = $false
        if ($checkpoints.Count -ge 2) {
            $firstInterval = $checkpoints[0]
            $lastInterval = $primeCount - $checkpoints[$checkpoints.Count - 1]
            if ($lastInterval -gt 0 -and $firstInterval -gt 0) {
                $ratio = $lastInterval / $firstInterval
                $throttled = ($ratio -lt 0.7)
            }
        }

        $stressStatus = if ($throttled) { "WARN" } else { "PASS" }
        $stressDetails = if ($throttled) { "Performance dropped during test - possible thermal throttling" } else { "Consistent performance throughout test" }
        [void]$results.Add((New-TestResult "Stress Test (30s)" $stressStatus "$opsPerSec ops/sec" $stressDetails))
        [void]$results.Add((New-TestResult "Throttling Detected" $stressStatus $(if ($throttled) { "Yes" } else { "No" }) $stressDetails))

        # Simple benchmark comparison
        $benchStatus = if ($opsPerSec -gt 500000) { "PASS" } elseif ($opsPerSec -gt 200000) { "INFO" } else { "WARN" }
        [void]$results.Add((New-TestResult "Benchmark Score" $benchStatus "$opsPerSec" "Higher is better"))
    } catch {
        [void]$results.Add((New-TestResult "Stress Test" "FAIL" "Error" $_.Exception.Message))
    }

    return $results
}

# ─────────────────────────────────────────────────────────────────────────────
# TEST 2: MEMORY DIAGNOSTIC
# ─────────────────────────────────────────────────────────────────────────────
function Test-Memory {
    param([System.Windows.Forms.Label]$StatusLabel)
    $results = [System.Collections.ArrayList]::new()

    if ($StatusLabel) { $StatusLabel.Text = "Testing Memory..." }
    [System.Windows.Forms.Application]::DoEvents()

    # Overall memory
    $os = Get-SafeCim -ClassName "Win32_OperatingSystem"
    if ($os) {
        $totalMB = [math]::Round($os.TotalVisibleMemorySize / 1024)
        $freeMB  = [math]::Round($os.FreePhysicalMemory / 1024)
        $usedMB  = $totalMB - $freeMB
        $usedPct = [math]::Round(($usedMB / $totalMB) * 100, 1)
        $totalGB = [math]::Round($totalMB / 1024, 1)

        [void]$results.Add((New-TestResult "Total RAM" "INFO" "${totalGB} GB"))
        [void]$results.Add((New-TestResult "Used / Available" "INFO" "${usedMB} MB / ${freeMB} MB"))

        $memStatus = if ($usedPct -gt 90) { "FAIL" } elseif ($usedPct -gt 75) { "WARN" } else { "PASS" }
        $memDetails = if ($usedPct -gt 90) { "Critical: Very low available memory" } elseif ($usedPct -gt 75) { "Memory usage is high" } else { "Memory usage normal" }
        [void]$results.Add((New-TestResult "Memory Usage" $memStatus "${usedPct}%" $memDetails))
    }

    # DIMM slots
    if ($StatusLabel) { $StatusLabel.Text = "Checking memory modules..." }
    [System.Windows.Forms.Application]::DoEvents()

    $memModules = Get-SafeCim -ClassName "Win32_PhysicalMemory"
    $slotIndex = 0
    if ($memModules) {
        foreach ($mod in $memModules) {
            $slotIndex++
            $capGB = [math]::Round($mod.Capacity / 1GB, 1)
            $speed = $mod.Speed
            $formFactor = switch ($mod.FormFactor) {
                8  { "DIMM" }
                12 { "SO-DIMM (Laptop)" }
                default { "Type $($mod.FormFactor)" }
            }
            $memType = switch ($mod.SMBIOSMemoryType) {
                20 { "DDR" }
                21 { "DDR2" }
                24 { "DDR3" }
                26 { "DDR4" }
                34 { "DDR5" }
                default {
                    switch ($mod.MemoryType) {
                        20 { "DDR" }
                        21 { "DDR2" }
                        24 { "DDR3" }
                        26 { "DDR4" }
                        default { "Unknown" }
                    }
                }
            }
            $locator = if ($mod.DeviceLocator) { $mod.DeviceLocator } else { "Slot $slotIndex" }
            [void]$results.Add((New-TestResult "DIMM: $locator" "INFO" "${capGB} GB ${memType} @ ${speed} MHz" "Form Factor: $formFactor"))
        }

        # Total slots (check for empty slots)
        $totalSlots = @(Get-SafeCim -ClassName "Win32_PhysicalMemoryArray" | Select-Object -ExpandProperty MemoryDevices -ErrorAction SilentlyContinue)
        if ($totalSlots.Count -gt 0 -and $totalSlots[0]) {
            $emptySlots = $totalSlots[0] - $slotIndex
            if ($emptySlots -gt 0) {
                [void]$results.Add((New-TestResult "Empty DIMM Slots" "INFO" "$emptySlots available" "Upgrade possible"))
            }
        }
    }

    # ECC support
    $memArray = Get-SafeCim -ClassName "Win32_PhysicalMemoryArray"
    if ($memArray) {
        $eccType = ($memArray | Select-Object -First 1).MemoryErrorCorrection
        $eccStr = switch ($eccType) {
            3 { "None" }
            4 { "Parity" }
            5 { "Single-bit ECC" }
            6 { "Multi-bit ECC" }
            default { "Unknown ($eccType)" }
        }
        $eccStatus = if ($eccType -ge 5) { "PASS" } else { "INFO" }
        [void]$results.Add((New-TestResult "ECC Support" $eccStatus $eccStr))
    }

    # Simple memory allocation test
    if ($StatusLabel) { $StatusLabel.Text = "Running memory allocation test..." }
    [System.Windows.Forms.Application]::DoEvents()

    try {
        $testSizeMB = 100
        $blockCount = 0
        $maxBlocks = 5
        $allPassed = $true
        $allocatedBlocks = [System.Collections.ArrayList]::new()

        for ($b = 0; $b -lt $maxBlocks; $b++) {
            try {
                $block = New-Object byte[] ($testSizeMB * 1MB)
                # Fill with pattern
                for ($i = 0; $i -lt $block.Length; $i += 4096) {
                    $block[$i] = [byte]0xAA
                }
                # Verify pattern
                for ($i = 0; $i -lt $block.Length; $i += 4096) {
                    if ($block[$i] -ne [byte]0xAA) {
                        $allPassed = $false
                        break
                    }
                }
                [void]$allocatedBlocks.Add($block)
                $blockCount++
                [System.Windows.Forms.Application]::DoEvents()
            } catch {
                break
            }
        }

        # Release
        $allocatedBlocks.Clear()
        [System.GC]::Collect()

        $allocStatus = if ($allPassed -and $blockCount -eq $maxBlocks) { "PASS" } elseif ($blockCount -gt 0) { "WARN" } else { "FAIL" }
        $allocDetails = if ($allPassed -and $blockCount -eq $maxBlocks) { "All ${maxBlocks} x ${testSizeMB}MB blocks passed" } elseif ($blockCount -gt 0) { "Only $blockCount of $maxBlocks blocks allocated/verified" } else { "Memory allocation failed" }
        [void]$results.Add((New-TestResult "Memory Allocation Test" $allocStatus "$($blockCount * $testSizeMB) MB tested" $allocDetails))
    } catch {
        [void]$results.Add((New-TestResult "Memory Allocation Test" "FAIL" "Error" $_.Exception.Message))
    }

    return $results
}

# ─────────────────────────────────────────────────────────────────────────────
# TEST 3: STORAGE DIAGNOSTIC
# ─────────────────────────────────────────────────────────────────────────────
function Test-Storage {
    param([System.Windows.Forms.Label]$StatusLabel)
    $results = [System.Collections.ArrayList]::new()

    if ($StatusLabel) { $StatusLabel.Text = "Testing Storage..." }
    [System.Windows.Forms.Application]::DoEvents()

    # Get physical disks (SKIP USB and SD to prevent hangs)
    $physDisks = $null
    try {
        $physDisks = Get-PhysicalDisk | Where-Object { $_.BusType -notin @('USB','SD') }
    } catch {
        [void]$results.Add((New-TestResult "Physical Disk Enumeration" "WARN" "Limited" "Get-PhysicalDisk not available, falling back to WMI"))
    }

    if ($physDisks) {
        foreach ($disk in $physDisks) {
            $sizeGB = [math]::Round($disk.Size / 1GB, 1)
            $mediaType = if ($disk.MediaType) { $disk.MediaType.ToString() } else { "Unknown" }
            $busType = if ($disk.BusType) { $disk.BusType.ToString() } else { "Unknown" }
            $isSSD = ($mediaType -eq "SSD" -or $mediaType -eq "4" -or $busType -eq "NVMe")

            $diskLabel = if ($disk.FriendlyName) { $disk.FriendlyName } else { "Disk $($disk.DeviceId)" }
            [void]$results.Add((New-TestResult "Drive: $diskLabel" "INFO" "${sizeGB} GB ($mediaType)" "Bus: $busType"))

            # Health status
            $healthStatus = if ($disk.HealthStatus) { $disk.HealthStatus.ToString() } else { "Unknown" }
            $healthResult = switch ($healthStatus) {
                "Healthy" { "PASS" }
                "Warning" { "WARN" }
                default   { "FAIL" }
            }
            [void]$results.Add((New-TestResult "  Health Status" $healthResult $healthStatus))

            # Operational status
            if ($disk.OperationalStatus) {
                [void]$results.Add((New-TestResult "  Operational Status" "INFO" $disk.OperationalStatus.ToString()))
            }

            # SMART data via CIM
            if ($StatusLabel) { $StatusLabel.Text = "Reading SMART data for $diskLabel..." }
            [System.Windows.Forms.Application]::DoEvents()

            try {
                $smartData = Get-SafeCim -ClassName "MSFT_PhysicalDisk" -Namespace "root/Microsoft/Windows/Storage" -Filter "DeviceId='$($disk.DeviceId)'"
                if ($smartData) {
                    # Reliability counters
                    $reliability = Get-SafeCim -ClassName "MSFT_StorageReliabilityCounter" -Namespace "root/Microsoft/Windows/Storage"
                    if ($reliability) {
                        foreach ($rel in $reliability) {
                            if ($null -ne $rel.Temperature) {
                                $tempC = $rel.Temperature
                                $tempStatus = if ($tempC -gt 55) { "FAIL" } elseif ($tempC -gt 45) { "WARN" } else { "PASS" }
                                [void]$results.Add((New-TestResult "  Temperature" $tempStatus "${tempC}C" $(if ($tempC -gt 55) { "Critically hot!" } elseif ($tempC -gt 45) { "Elevated" } else { "Normal" })))
                            }
                            if ($null -ne $rel.ReadErrorsTotal -and $rel.ReadErrorsTotal -gt 0) {
                                [void]$results.Add((New-TestResult "  Read Errors" "WARN" "$($rel.ReadErrorsTotal)" "Read errors detected"))
                            }
                            if ($null -ne $rel.Wear -and $rel.Wear -gt 0) {
                                $wearPct = $rel.Wear
                                $wearStatus = if ($wearPct -gt 80) { "FAIL" } elseif ($wearPct -gt 50) { "WARN" } else { "PASS" }
                                [void]$results.Add((New-TestResult "  Wear Level" $wearStatus "${wearPct}%" $(if ($wearPct -gt 80) { "Drive nearing end of life" } elseif ($wearPct -gt 50) { "Moderate wear" } else { "Good condition" })))
                            }
                            if ($null -ne $rel.PowerOnHours) {
                                $pohDays = [math]::Round($rel.PowerOnHours / 24)
                                $pohYears = [math]::Round($pohDays / 365, 1)
                                [void]$results.Add((New-TestResult "  Power-On Time" "INFO" "$($rel.PowerOnHours) hrs (~${pohYears} years)"))
                            }
                            break  # Only process first counter per disk
                        }
                    }
                }
            } catch {}

            # SSD vs HDD indicator
            $typeStr = if ($isSSD) { "Solid State Drive (SSD)" } else { "Hard Disk Drive (HDD)" }
            [void]$results.Add((New-TestResult "  Drive Type" "INFO" $typeStr))
        }
    }

    # Partition layout and free space
    if ($StatusLabel) { $StatusLabel.Text = "Checking partition layout..." }
    [System.Windows.Forms.Application]::DoEvents()

    $logicalDisks = Get-SafeCim -ClassName "Win32_LogicalDisk" -Filter "DriveType=3"
    if ($logicalDisks) {
        foreach ($ld in $logicalDisks) {
            $totalGB = [math]::Round($ld.Size / 1GB, 1)
            $freeGB  = [math]::Round($ld.FreeSpace / 1GB, 1)
            $usedPct = if ($ld.Size -gt 0) { [math]::Round((($ld.Size - $ld.FreeSpace) / $ld.Size) * 100, 1) } else { 0 }
            $volName  = if ($ld.VolumeName) { $ld.VolumeName } else { "Local Disk" }

            $spaceStatus = if ($freeGB -lt 5) { "FAIL" } elseif ($freeGB -lt 20 -or $usedPct -gt 90) { "WARN" } else { "PASS" }
            $spaceDetails = if ($freeGB -lt 5) { "Critically low disk space!" } elseif ($freeGB -lt 20) { "Low disk space" } else { "Adequate free space" }
            [void]$results.Add((New-TestResult "Partition $($ld.DeviceID) ($volName)" $spaceStatus "${freeGB} GB free of ${totalGB} GB ($usedPct% used)" $spaceDetails))
        }
    }

    # Sequential read speed test
    if ($StatusLabel) { $StatusLabel.Text = "Running disk read speed test..." }
    [System.Windows.Forms.Application]::DoEvents()

    try {
        $tempDir = Join-Path $env:TEMP "pcplus360-disktest"
        if (-not (Test-Path $tempDir)) { New-Item -Path $tempDir -ItemType Directory -Force | Out-Null }
        $testFile = Join-Path $tempDir "readtest.dat"

        # Write 50MB test file
        $testSizeMB = 50
        $buffer = New-Object byte[] (1MB)
        $random = New-Object System.Random
        $random.NextBytes($buffer)

        $fs = [System.IO.File]::Create($testFile)
        for ($i = 0; $i -lt $testSizeMB; $i++) { $fs.Write($buffer, 0, $buffer.Length) }
        $fs.Flush()
        $fs.Close()
        $fs.Dispose()

        # Read test
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $fsRead = [System.IO.File]::OpenRead($testFile)
        $readBuf = New-Object byte[] (1MB)
        $totalRead = 0
        while ($true) {
            $bytesRead = $fsRead.Read($readBuf, 0, $readBuf.Length)
            if ($bytesRead -le 0) { break }
            $totalRead += $bytesRead
        }
        $fsRead.Close()
        $fsRead.Dispose()
        $sw.Stop()

        $readMBps = [math]::Round(($totalRead / 1MB) / ($sw.ElapsedMilliseconds / 1000), 1)
        $speedStatus = if ($readMBps -gt 100) { "PASS" } elseif ($readMBps -gt 30) { "INFO" } else { "WARN" }
        [void]$results.Add((New-TestResult "Sequential Read Speed" $speedStatus "${readMBps} MB/s" "50MB test file on system drive"))

        # Cleanup
        Remove-Item -Path $testFile -Force -ErrorAction SilentlyContinue
        Remove-Item -Path $tempDir -Force -Recurse -ErrorAction SilentlyContinue
    } catch {
        [void]$results.Add((New-TestResult "Disk Read Speed Test" "WARN" "Error" $_.Exception.Message))
    }

    return $results
}

# ─────────────────────────────────────────────────────────────────────────────
# TEST 4: GPU DIAGNOSTIC
# ─────────────────────────────────────────────────────────────────────────────
function Test-GPU {
    param([System.Windows.Forms.Label]$StatusLabel)
    $results = [System.Collections.ArrayList]::new()

    if ($StatusLabel) { $StatusLabel.Text = "Testing GPU..." }
    [System.Windows.Forms.Application]::DoEvents()

    $gpus = Get-SafeCim -ClassName "Win32_VideoController"
    if ($gpus) {
        $gpuIndex = 0
        foreach ($gpu in $gpus) {
            $gpuIndex++
            $gpuName = if ($gpu.Name) { $gpu.Name } else { "GPU $gpuIndex" }
            [void]$results.Add((New-TestResult "GPU: $gpuName" "INFO" ""))

            # VRAM
            if ($gpu.AdapterRAM -and $gpu.AdapterRAM -gt 0) {
                $vramGB = [math]::Round($gpu.AdapterRAM / 1GB, 1)
                [void]$results.Add((New-TestResult "  VRAM" "INFO" "${vramGB} GB"))
            }

            # Driver version
            if ($gpu.DriverVersion) {
                [void]$results.Add((New-TestResult "  Driver Version" "INFO" $gpu.DriverVersion))
            }

            # Driver date
            if ($gpu.DriverDate) {
                try {
                    $driverDate = [Management.ManagementDateTimeConverter]::ToDateTime($gpu.DriverDate)
                    $driverAge = (New-TimeSpan -Start $driverDate -End (Get-Date)).Days
                    $ageMonths = [math]::Round($driverAge / 30)
                    $driverStatus = if ($driverAge -gt 365) { "WARN" } elseif ($driverAge -gt 180) { "INFO" } else { "PASS" }
                    $driverDetails = if ($driverAge -gt 365) { "Driver is over a year old - update recommended" } elseif ($driverAge -gt 180) { "Driver is over 6 months old" } else { "Driver is recent" }
                    [void]$results.Add((New-TestResult "  Driver Age" $driverStatus "$ageMonths months ($($driverDate.ToString('yyyy-MM-dd')))" $driverDetails))
                } catch {}
            }

            # Resolution
            if ($gpu.CurrentHorizontalResolution -and $gpu.CurrentVerticalResolution) {
                [void]$results.Add((New-TestResult "  Resolution" "INFO" "$($gpu.CurrentHorizontalResolution) x $($gpu.CurrentVerticalResolution) @ $($gpu.CurrentRefreshRate)Hz"))
            }

            # Status
            $gpuStatus = if ($gpu.Status -eq "OK") { "PASS" } else { "WARN" }
            [void]$results.Add((New-TestResult "  Status" $gpuStatus $gpu.Status))
        }

        # Multiple display detection
        $activeGPUs = @($gpus | Where-Object { $_.CurrentHorizontalResolution -gt 0 })
        [void]$results.Add((New-TestResult "Active Displays" "INFO" "$($activeGPUs.Count) detected"))
    }

    # DirectX version
    try {
        $dxVer = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\DirectX" -ErrorAction Stop).Version
        if ($dxVer) {
            [void]$results.Add((New-TestResult "DirectX Version" "INFO" $dxVer))
        }
    } catch {
        try {
            # Fallback: check feature level via dxdiag output
            $dxKey = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\DirectX" -ErrorAction SilentlyContinue
            if ($dxKey) {
                [void]$results.Add((New-TestResult "DirectX" "INFO" "Installed"))
            }
        } catch {}
    }

    return $results
}

# ─────────────────────────────────────────────────────────────────────────────
# TEST 5: BATTERY DIAGNOSTIC
# ─────────────────────────────────────────────────────────────────────────────
function Test-Battery {
    param([System.Windows.Forms.Label]$StatusLabel)
    $results = [System.Collections.ArrayList]::new()

    if ($StatusLabel) { $StatusLabel.Text = "Testing Battery..." }
    [System.Windows.Forms.Application]::DoEvents()

    $battery = Get-SafeCim -ClassName "Win32_Battery"
    if (-not $battery) {
        [void]$results.Add((New-TestResult "Battery" "INFO" "Not Present" "Desktop or battery not detected"))
        return $results
    }

    $bat = $battery | Select-Object -First 1
    [void]$results.Add((New-TestResult "Battery Name" "INFO" $(if ($bat.Name) { $bat.Name } else { "System Battery" })))

    # Battery status
    $statusStr = switch ($bat.BatteryStatus) {
        1 { "Discharging" }
        2 { "Plugged In (AC)" }
        3 { "Fully Charged" }
        4 { "Low" }
        5 { "Critical" }
        6 { "Charging" }
        7 { "Charging - High" }
        8 { "Charging - Low" }
        9 { "Charging - Critical" }
        10 { "Undefined" }
        11 { "Partially Charged" }
        default { "Unknown ($($bat.BatteryStatus))" }
    }
    [void]$results.Add((New-TestResult "Status" "INFO" $statusStr))

    # Charge level
    if ($null -ne $bat.EstimatedChargeRemaining) {
        $chargeStatus = if ($bat.EstimatedChargeRemaining -lt 20) { "WARN" } else { "PASS" }
        [void]$results.Add((New-TestResult "Charge Level" $chargeStatus "$($bat.EstimatedChargeRemaining)%"))
    }

    # Estimated runtime
    if ($null -ne $bat.EstimatedRunTime -and $bat.EstimatedRunTime -gt 0 -and $bat.EstimatedRunTime -lt 71582788) {
        $hours = [math]::Floor($bat.EstimatedRunTime / 60)
        $mins  = $bat.EstimatedRunTime % 60
        [void]$results.Add((New-TestResult "Estimated Runtime" "INFO" "${hours}h ${mins}m"))
    }

    # Design vs Full Charge Capacity (WMI BatteryStaticData / BatteryFullChargedCapacity)
    if ($StatusLabel) { $StatusLabel.Text = "Checking battery wear level..." }
    [System.Windows.Forms.Application]::DoEvents()

    try {
        $batStatic = Get-SafeCim -ClassName "BatteryStaticData" -Namespace "root/wmi"
        $batFull   = Get-SafeCim -ClassName "BatteryFullChargedCapacity" -Namespace "root/wmi"

        if ($batStatic -and $batFull) {
            $designCap = ($batStatic | Select-Object -First 1).DesignedCapacity
            $fullCap   = ($batFull | Select-Object -First 1).FullChargedCapacity

            if ($designCap -gt 0 -and $fullCap -gt 0) {
                $designWh = [math]::Round($designCap / 1000, 1)
                $fullWh   = [math]::Round($fullCap / 1000, 1)
                $wearPct  = [math]::Round((1 - ($fullCap / $designCap)) * 100, 1)

                [void]$results.Add((New-TestResult "Design Capacity" "INFO" "${designWh} Wh"))
                [void]$results.Add((New-TestResult "Current Full Capacity" "INFO" "${fullWh} Wh"))

                $wearStatus = if ($wearPct -gt 40) { "FAIL" } elseif ($wearPct -gt 20) { "WARN" } else { "PASS" }
                $wearDetails = if ($wearPct -gt 40) { "Battery significantly degraded - replacement recommended" } elseif ($wearPct -gt 20) { "Moderate battery wear" } else { "Battery in good condition" }
                [void]$results.Add((New-TestResult "Battery Wear" $wearStatus "${wearPct}%" $wearDetails))

                # Estimated remaining life
                if ($wearPct -lt 80) {
                    $remainPct = 100 - $wearPct
                    $estLife = if ($wearPct -gt 0) { [math]::Round($remainPct / ($wearPct / 2), 1) } else { "5+" }
                    [void]$results.Add((New-TestResult "Est. Remaining Life" "INFO" "~${estLife} years" "Rough estimate based on current wear rate"))
                }
            }
        }
    } catch {}

    # Charge cycles (via BatteryCycleCount if available)
    try {
        $cycleCount = Get-SafeCim -ClassName "BatteryCycleCount" -Namespace "root/wmi"
        if ($cycleCount) {
            $cycles = ($cycleCount | Select-Object -First 1).CycleCount
            if ($null -ne $cycles -and $cycles -gt 0) {
                $cycleStatus = if ($cycles -gt 800) { "WARN" } elseif ($cycles -gt 500) { "INFO" } else { "PASS" }
                [void]$results.Add((New-TestResult "Charge Cycles" $cycleStatus "$cycles" $(if ($cycles -gt 800) { "High cycle count" } else { "Normal" })))
            }
        }
    } catch {}

    # Power plan
    try {
        $activePlan = powercfg /getactivescheme 2>$null
        if ($activePlan) {
            $planName = if ($activePlan -match ':\s*(.+)$') { $Matches[1].Trim() } else { "Unknown" }
            # Trim GUID
            $planName = $planName -replace '\([0-9a-f\-]+\)', '' | ForEach-Object { $_.Trim() }
            [void]$results.Add((New-TestResult "Power Plan" "INFO" $planName))
        }
    } catch {}

    return $results
}

# ─────────────────────────────────────────────────────────────────────────────
# TEST 6: NETWORK ADAPTER DIAGNOSTIC
# ─────────────────────────────────────────────────────────────────────────────
function Test-Network {
    param([System.Windows.Forms.Label]$StatusLabel)
    $results = [System.Collections.ArrayList]::new()

    if ($StatusLabel) { $StatusLabel.Text = "Testing Network Adapters..." }
    [System.Windows.Forms.Application]::DoEvents()

    # All physical adapters
    $adapters = Get-SafeCim -ClassName "Win32_NetworkAdapterConfiguration" -Filter "IPEnabled=TRUE"
    if ($adapters) {
        foreach ($adapter in $adapters) {
            $desc = if ($adapter.Description) { $adapter.Description } else { "Network Adapter" }
            [void]$results.Add((New-TestResult "Adapter: $desc" "INFO" ""))

            if ($adapter.MACAddress) {
                [void]$results.Add((New-TestResult "  MAC Address" "INFO" $adapter.MACAddress))
            }
            if ($adapter.IPAddress) {
                $ipv4 = $adapter.IPAddress | Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' } | Select-Object -First 1
                if ($ipv4) {
                    [void]$results.Add((New-TestResult "  IPv4 Address" "INFO" $ipv4))
                }
            }
            if ($adapter.DefaultIPGateway) {
                [void]$results.Add((New-TestResult "  Gateway" "INFO" ($adapter.DefaultIPGateway -join ", ")))
            }
            if ($adapter.DNSServerSearchOrder) {
                [void]$results.Add((New-TestResult "  DNS Servers" "INFO" ($adapter.DNSServerSearchOrder -join ", ")))
            }
            if ($adapter.DHCPEnabled) {
                [void]$results.Add((New-TestResult "  DHCP" "INFO" "Enabled"))
            }
        }
    }

    # Adapter speed (via NetAdapter cmdlet)
    if ($StatusLabel) { $StatusLabel.Text = "Checking link speeds..." }
    [System.Windows.Forms.Application]::DoEvents()
    try {
        $netAdapters = Get-NetAdapter -ErrorAction Stop | Where-Object { $_.Status -eq 'Up' }
        foreach ($na in $netAdapters) {
            $speedMbps = [math]::Round($na.LinkSpeed -replace '[^0-9.]', '')
            if ($speedMbps -gt 0) {
                $speedStatus = if ($speedMbps -ge 1000) { "PASS" } elseif ($speedMbps -ge 100) { "INFO" } else { "WARN" }
                [void]$results.Add((New-TestResult "Link Speed: $($na.Name)" $speedStatus "$($na.LinkSpeed)" $(if ($speedMbps -lt 100) { "Slow connection" } else { "" })))
            }
        }
    } catch {}

    # WiFi signal strength
    if ($StatusLabel) { $StatusLabel.Text = "Checking WiFi signal..." }
    [System.Windows.Forms.Application]::DoEvents()
    try {
        $wifiOutput = netsh wlan show interfaces 2>$null
        if ($wifiOutput) {
            $ssid = ($wifiOutput | Select-String "^\s*SSID\s*:" | Select-Object -First 1) -replace '^\s*SSID\s*:\s*', ''
            $signal = ($wifiOutput | Select-String "^\s*Signal\s*:" | Select-Object -First 1) -replace '^\s*Signal\s*:\s*', ''

            if ($ssid) {
                [void]$results.Add((New-TestResult "WiFi Network" "INFO" $ssid.Trim()))
            }
            if ($signal) {
                $sigPct = [int]($signal.Trim() -replace '%', '')
                $sigStatus = if ($sigPct -lt 30) { "FAIL" } elseif ($sigPct -lt 60) { "WARN" } else { "PASS" }
                $sigDetails = if ($sigPct -lt 30) { "Very weak signal" } elseif ($sigPct -lt 60) { "Moderate signal" } else { "Strong signal" }
                [void]$results.Add((New-TestResult "WiFi Signal Strength" $sigStatus "${sigPct}%" $sigDetails))
            }
        }
    } catch {}

    # DNS response time
    if ($StatusLabel) { $StatusLabel.Text = "Testing DNS response time..." }
    [System.Windows.Forms.Application]::DoEvents()
    try {
        $dnsServers = @("8.8.8.8", "1.1.1.1")
        foreach ($dns in $dnsServers) {
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            $dnsResult = Resolve-DnsName -Name "google.com" -Server $dns -Type A -DnsOnly -ErrorAction Stop | Select-Object -First 1
            $sw.Stop()
            $dnsMs = $sw.ElapsedMilliseconds
            $dnsStatus = if ($dnsMs -gt 200) { "WARN" } elseif ($dnsMs -gt 50) { "INFO" } else { "PASS" }
            [void]$results.Add((New-TestResult "DNS Response ($dns)" $dnsStatus "${dnsMs} ms" $(if ($dnsMs -gt 200) { "Slow DNS response" } else { "" })))
            break  # Test only first reachable
        }
    } catch {
        [void]$results.Add((New-TestResult "DNS Response Test" "WARN" "Failed" "DNS resolution test failed"))
    }

    # Internet speed estimate (download small file)
    if ($StatusLabel) { $StatusLabel.Text = "Estimating internet speed..." }
    [System.Windows.Forms.Application]::DoEvents()
    try {
        $testUrl = "http://speedtest.tele2.net/1MB.zip"
        $tempFile = Join-Path $env:TEMP "pcplus360-speedtest.dat"

        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $wc = New-Object System.Net.WebClient
        $wc.DownloadFile($testUrl, $tempFile)
        $sw.Stop()
        $wc.Dispose()

        $fileSizeBytes = (Get-Item $tempFile).Length
        $fileSizeMB = $fileSizeBytes / 1MB
        $elapsedSec = $sw.ElapsedMilliseconds / 1000
        $speedMbps = [math]::Round(($fileSizeMB * 8) / $elapsedSec, 1)

        $speedStatus = if ($speedMbps -gt 25) { "PASS" } elseif ($speedMbps -gt 5) { "INFO" } else { "WARN" }
        [void]$results.Add((New-TestResult "Download Speed (est.)" $speedStatus "${speedMbps} Mbps" "1MB test file"))

        Remove-Item -Path $tempFile -Force -ErrorAction SilentlyContinue
    } catch {
        [void]$results.Add((New-TestResult "Download Speed Test" "INFO" "Unavailable" "Could not reach speed test server"))
    }

    return $results
}

# ─────────────────────────────────────────────────────────────────────────────
# TEST 7: PERIPHERAL DIAGNOSTIC
# ─────────────────────────────────────────────────────────────────────────────
function Test-Peripherals {
    param([System.Windows.Forms.Label]$StatusLabel)
    $results = [System.Collections.ArrayList]::new()

    if ($StatusLabel) { $StatusLabel.Text = "Testing Peripherals..." }
    [System.Windows.Forms.Application]::DoEvents()

    # USB Devices
    $usbDevices = Get-SafeCim -ClassName "Win32_USBHub"
    $usbCount = if ($usbDevices) { @($usbDevices).Count } else { 0 }
    [void]$results.Add((New-TestResult "USB Hubs/Devices" "INFO" "$usbCount detected"))

    $usbControllers = Get-SafeCim -ClassName "Win32_USBControllerDevice"
    if ($usbControllers) {
        $pnpDevices = Get-SafeCim -ClassName "Win32_PnPEntity" -Filter "PNPClass='USB'"
        if ($pnpDevices) {
            $shown = 0
            foreach ($dev in $pnpDevices) {
                if ($shown -ge 10) { break }
                $devName = if ($dev.Name) { $dev.Name } else { "USB Device" }
                if ($devName -notmatch "Root Hub|Host Controller|Generic Hub") {
                    [void]$results.Add((New-TestResult "  USB: $devName" "INFO" $(if ($dev.Status -eq "OK") { "OK" } else { $dev.Status })))
                    $shown++
                }
            }
        }
    }

    # Audio devices
    if ($StatusLabel) { $StatusLabel.Text = "Checking audio devices..." }
    [System.Windows.Forms.Application]::DoEvents()

    $audioDevices = Get-SafeCim -ClassName "Win32_SoundDevice"
    if ($audioDevices) {
        foreach ($audio in $audioDevices) {
            $audioName = if ($audio.Name) { $audio.Name } else { "Audio Device" }
            $audioStatus = if ($audio.Status -eq "OK") { "PASS" } else { "WARN" }
            [void]$results.Add((New-TestResult "Audio: $audioName" $audioStatus $audio.Status))
        }
    } else {
        [void]$results.Add((New-TestResult "Audio Devices" "WARN" "None detected"))
    }

    # Printers
    if ($StatusLabel) { $StatusLabel.Text = "Checking printers..." }
    [System.Windows.Forms.Application]::DoEvents()

    $printers = Get-SafeCim -ClassName "Win32_Printer"
    if ($printers) {
        foreach ($printer in $printers) {
            $printerName = if ($printer.Name) { $printer.Name } else { "Printer" }
            $printerStatus = if ($printer.PrinterStatus -eq 3) { "PASS" } else { "INFO" }
            $statusStr = switch ($printer.PrinterStatus) {
                1 { "Other" }
                2 { "Unknown" }
                3 { "Idle" }
                4 { "Printing" }
                5 { "Warming Up" }
                6 { "Stopped" }
                7 { "Offline" }
                default { "Status $($printer.PrinterStatus)" }
            }
            $defaultStr = if ($printer.Default) { " (Default)" } else { "" }
            [void]$results.Add((New-TestResult "Printer: ${printerName}${defaultStr}" $printerStatus $statusStr))
        }
    } else {
        [void]$results.Add((New-TestResult "Printers" "INFO" "None installed"))
    }

    # Bluetooth
    if ($StatusLabel) { $StatusLabel.Text = "Checking Bluetooth..." }
    [System.Windows.Forms.Application]::DoEvents()

    $bluetooth = Get-SafeCim -ClassName "Win32_PnPEntity" -Filter "PNPClass='Bluetooth'"
    if ($bluetooth) {
        $btCount = @($bluetooth).Count
        [void]$results.Add((New-TestResult "Bluetooth" "PASS" "Available ($btCount devices)"))
        $btShown = 0
        foreach ($bt in $bluetooth) {
            if ($btShown -ge 5) { break }
            $btName = if ($bt.Name) { $bt.Name } else { "Bluetooth Device" }
            $btStatus = if ($bt.Status -eq "OK") { "PASS" } else { "WARN" }
            [void]$results.Add((New-TestResult "  BT: $btName" $btStatus $bt.Status))
            $btShown++
        }
    } else {
        [void]$results.Add((New-TestResult "Bluetooth" "INFO" "Not detected or disabled"))
    }

    # Camera / webcam
    $cameras = Get-SafeCim -ClassName "Win32_PnPEntity" -Filter "PNPClass='Camera' OR PNPClass='Image'"
    if ($cameras) {
        foreach ($cam in $cameras) {
            $camName = if ($cam.Name) { $cam.Name } else { "Camera" }
            $camStatus = if ($cam.Status -eq "OK") { "PASS" } else { "WARN" }
            [void]$results.Add((New-TestResult "Camera: $camName" $camStatus $cam.Status))
        }
    }

    return $results
}

# ─────────────────────────────────────────────────────────────────────────────
# OVERALL HEALTH SCORE CALCULATOR
# ─────────────────────────────────────────────────────────────────────────────
function Get-OverallHealthScore {
    param([System.Collections.ArrayList]$AllResults)

    $totalTests = 0
    $passCount  = 0
    $warnCount  = 0
    $failCount  = 0

    foreach ($r in $AllResults) {
        if ($r.Status -eq "INFO") { continue }
        $totalTests++
        switch ($r.Status) {
            "PASS" { $passCount++ }
            "WARN" { $warnCount++ }
            "FAIL" { $failCount++ }
        }
    }

    if ($totalTests -eq 0) { return 50 }

    # Score: PASS=100, WARN=50, FAIL=0
    $score = [math]::Round(($passCount * 100 + $warnCount * 50) / $totalTests)
    return [math]::Min(100, [math]::Max(0, $score))
}

# ─────────────────────────────────────────────────────────────────────────────
# HTML REPORT GENERATION
# ─────────────────────────────────────────────────────────────────────────────
function New-HardwareDiagHtml {
    param(
        [hashtable]$TestResults,
        [int]$OverallScore,
        [string]$OverallGrade,
        [string[]]$TestsRun
    )

    $dateStr = Get-Date -Format "MMMM dd, yyyy 'at' hh:mm tt"
    $gradeColor = switch -Wildcard ($OverallGrade) {
        "A*" { $COLOR_GREEN }
        "B*" { $COLOR_ACCENT }
        "C*" { $COLOR_ORANGE }
        default { $COLOR_RED }
    }

    $testSections = ""
    $categoryNames = [ordered]@{
        "CPU"         = "CPU Diagnostics"
        "Memory"      = "Memory Diagnostics"
        "Storage"     = "Storage Diagnostics"
        "GPU"         = "GPU Diagnostics"
        "Battery"     = "Battery Diagnostics"
        "Network"     = "Network Diagnostics"
        "Peripherals" = "Peripheral Diagnostics"
    }

    foreach ($key in $categoryNames.Keys) {
        if ($TestResults.ContainsKey($key)) {
            $catResults = $TestResults[$key]
            $rowsHtml = ""
            foreach ($r in $catResults) {
                $statusColor = switch ($r.Status) {
                    "PASS" { $COLOR_GREEN }
                    "WARN" { $COLOR_ORANGE }
                    "FAIL" { $COLOR_RED }
                    "INFO" { $COLOR_ACCENT }
                    default { "#888" }
                }
                $statusBadge = "<span style='background: $statusColor; color: white; padding: 2px 10px; border-radius: 10px; font-size: 11px; font-weight: bold;'>$($r.Status)</span>"
                $detailsStr = if ($r.Details) { "<br><span style='color: #8899aa; font-size: 12px;'>$([System.Web.HttpUtility]::HtmlEncode($r.Details))</span>" } else { "" }

                $rowsHtml += @"
                <tr>
                    <td style="padding: 10px 15px; border-bottom: 1px solid #1e2d45; color: #e0e0e0;">$([System.Web.HttpUtility]::HtmlEncode($r.Name))</td>
                    <td style="padding: 10px 15px; border-bottom: 1px solid #1e2d45; color: white; font-weight: 500;">$([System.Web.HttpUtility]::HtmlEncode($r.Value))$detailsStr</td>
                    <td style="padding: 10px 15px; border-bottom: 1px solid #1e2d45; text-align: center;">$statusBadge</td>
                </tr>
"@
            }

            # Category pass/warn/fail counts
            $catPass = @($catResults | Where-Object { $_.Status -eq "PASS" }).Count
            $catWarn = @($catResults | Where-Object { $_.Status -eq "WARN" }).Count
            $catFail = @($catResults | Where-Object { $_.Status -eq "FAIL" }).Count

            $testSections += @"
            <div class="test-section">
                <div class="test-header">
                    <span class="test-title">$($categoryNames[$key])</span>
                    <span class="test-counts">
                        <span style="color: ${COLOR_GREEN};">$catPass Pass</span> &nbsp;
                        <span style="color: ${COLOR_ORANGE};">$catWarn Warn</span> &nbsp;
                        <span style="color: ${COLOR_RED};">$catFail Fail</span>
                    </span>
                </div>
                <table class="results-table">
                    <thead>
                        <tr>
                            <th style="width: 35%;">Test</th>
                            <th style="width: 45%;">Result</th>
                            <th style="width: 20%; text-align: center;">Status</th>
                        </tr>
                    </thead>
                    <tbody>
                        $rowsHtml
                    </tbody>
                </table>
            </div>
"@
        }
    }

    $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>$COMPANY_FULL - Hardware Diagnostic Report</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: ${COLOR_NAVY};
            color: #e0e0e0;
            line-height: 1.6;
        }
        .container { max-width: 950px; margin: 0 auto; padding: 20px; }
        .header {
            background: linear-gradient(135deg, ${COLOR_NAVY} 0%, #142238 100%);
            border: 2px solid ${COLOR_ACCENT};
            border-radius: 12px;
            padding: 30px;
            text-align: center;
            margin-bottom: 25px;
        }
        .header h1 { color: ${COLOR_ACCENT}; font-size: 28px; margin-bottom: 5px; }
        .header h2 { color: #8899aa; font-size: 16px; font-weight: 400; }
        .overall-score {
            text-align: center;
            margin-bottom: 25px;
            padding: 30px;
            background: #0f1f35;
            border-radius: 12px;
            border: 1px solid #1e2d45;
        }
        .grade-badge {
            display: inline-block;
            width: 100px; height: 100px;
            border-radius: 50%;
            line-height: 100px;
            font-size: 42px; font-weight: 800;
            color: white; text-align: center;
            margin-bottom: 10px;
            box-shadow: 0 4px 15px rgba(0,0,0,0.3);
        }
        .score-text { font-size: 20px; color: #ccc; margin-top: 5px; }
        .score-subtitle { font-size: 13px; color: #8899aa; margin-top: 5px; }
        .test-section {
            background: #0f1f35;
            border: 1px solid #1e2d45;
            border-radius: 10px;
            margin-bottom: 20px;
            overflow: hidden;
        }
        .test-header {
            display: flex; justify-content: space-between; align-items: center;
            padding: 15px 20px;
            background: #0c1a2e;
            border-bottom: 1px solid #1e2d45;
        }
        .test-title { font-size: 16px; font-weight: 600; color: ${COLOR_ACCENT}; }
        .test-counts { font-size: 12px; }
        .results-table { width: 100%; border-collapse: collapse; }
        .results-table th {
            background: #0c1a2e;
            color: #8899aa;
            padding: 10px 15px;
            text-align: left;
            font-size: 12px;
            text-transform: uppercase;
            letter-spacing: 0.5px;
        }
        .meta-info {
            display: flex; justify-content: space-between;
            background: #0f1f35;
            border: 1px solid #1e2d45;
            border-radius: 10px;
            padding: 12px 20px;
            margin-bottom: 20px;
            font-size: 13px;
        }
        .meta-info span { color: #8899aa; }
        .meta-info strong { color: white; }
        .footer {
            text-align: center; padding: 20px;
            color: #5a6a7a; font-size: 12px;
            border-top: 1px solid #1e2d45;
            margin-top: 30px;
        }
        @media print {
            body { background: white; color: #333; }
            .header { background: white; border-color: #2596be; }
            .header h1 { color: #0a1628; }
            .overall-score, .test-section, .meta-info { background: #f8f9fa; border-color: #ddd; }
            .test-header { background: #eee; border-color: #ddd; }
            .test-title { color: #0a1628; }
            .results-table th { background: #eee; color: #555; }
            .results-table td { color: #333; }
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>$COMPANY_FULL</h1>
            <h2>Comprehensive Hardware Diagnostic Report</h2>
        </div>

        <div class="meta-info">
            <span>Computer: <strong>$env:COMPUTERNAME</strong></span>
            <span>Tests Run: <strong>$($TestsRun -join ', ')</strong></span>
            <span>Date: <strong>$dateStr</strong></span>
        </div>

        <div class="overall-score">
            <div class="grade-badge" style="background: $gradeColor;">$OverallGrade</div>
            <div class="score-text">Hardware Health Score: $OverallScore / 100</div>
            <div class="score-subtitle">Based on $($TestsRun.Count) diagnostic categories</div>
        </div>

        $testSections

        <div class="footer">
            <p>$COMPANY_NAME &nbsp;|&nbsp; $COMPANY_PHONE1 &nbsp;|&nbsp; $COMPANY_PHONE2 &nbsp;|&nbsp; $COMPANY_WEBSITE</p>
            <p style="margin-top: 5px;">Report generated on $dateStr &nbsp;|&nbsp; $COMPANY_FULL Diagnostic Toolkit</p>
        </div>
    </div>
</body>
</html>
"@
    return $html
}

# ─────────────────────────────────────────────────────────────────────────────
# JSON EXPORT
# ─────────────────────────────────────────────────────────────────────────────
function Save-HardwareDiagJson {
    param(
        [hashtable]$TestResults,
        [int]$OverallScore,
        [string]$OverallGrade,
        [string[]]$TestsRun,
        [string]$OutputPath
    )

    $catData = [ordered]@{}
    foreach ($key in $TestResults.Keys) {
        $items = [System.Collections.ArrayList]::new()
        foreach ($r in $TestResults[$key]) {
            [void]$items.Add([ordered]@{
                Name    = $r.Name
                Status  = $r.Status
                Value   = $r.Value
                Details = $r.Details
            })
        }
        $catData[$key] = @($items)
    }

    $jsonObj = [ordered]@{
        ToolName      = "HardwareDiagnostic"
        Version       = "1.0.0"
        ComputerName  = $env:COMPUTERNAME
        DateTime      = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        TimestampUTC  = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        OverallScore  = $OverallScore
        OverallGrade  = $OverallGrade
        TestsRun      = $TestsRun
        Results       = $catData
    }
    $jsonObj | ConvertTo-Json -Depth 10 | Set-Content -Path $OutputPath -Encoding UTF8 -Force
}

# ─────────────────────────────────────────────────────────────────────────────
# GRADE HELPER
# ─────────────────────────────────────────────────────────────────────────────
function Get-LetterGrade {
    param([int]$Score)
    if ($Score -ge 97) { return "A+" }
    if ($Score -ge 93) { return "A"  }
    if ($Score -ge 90) { return "A-" }
    if ($Score -ge 87) { return "B+" }
    if ($Score -ge 83) { return "B"  }
    if ($Score -ge 80) { return "B-" }
    if ($Score -ge 77) { return "C+" }
    if ($Score -ge 73) { return "C"  }
    if ($Score -ge 70) { return "C-" }
    if ($Score -ge 67) { return "D+" }
    if ($Score -ge 63) { return "D"  }
    if ($Score -ge 60) { return "D-" }
    return "F"
}

# ─────────────────────────────────────────────────────────────────────────────
# WINFORMS UI - MAIN DIAGNOSTIC WINDOW
# ─────────────────────────────────────────────────────────────────────────────
function Show-DiagnosticUI {
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "$COMPANY_FULL - Hardware Diagnostic"
    $form.Size = New-Object System.Drawing.Size(780, 700)
    $form.StartPosition = "CenterScreen"
    $form.BackColor = [System.Drawing.ColorTranslator]::FromHtml($COLOR_NAVY)
    $form.ForeColor = [System.Drawing.Color]::White
    $form.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $form.FormBorderStyle = "FixedSingle"
    $form.MaximizeBox = $false

    $yPos = 15

    # Header
    $lblTitle = New-Object System.Windows.Forms.Label
    $lblTitle.Text = "$COMPANY_FULL"
    $lblTitle.Font = New-Object System.Drawing.Font("Segoe UI", 18, [System.Drawing.FontStyle]::Bold)
    $lblTitle.ForeColor = [System.Drawing.ColorTranslator]::FromHtml($COLOR_ACCENT)
    $lblTitle.AutoSize = $false
    $lblTitle.Size = New-Object System.Drawing.Size(740, 35)
    $lblTitle.Location = New-Object System.Drawing.Point(15, $yPos)
    $lblTitle.TextAlign = "MiddleCenter"
    $form.Controls.Add($lblTitle)
    $yPos += 35

    $lblSub = New-Object System.Windows.Forms.Label
    $lblSub.Text = "Comprehensive Hardware Diagnostic"
    $lblSub.Font = New-Object System.Drawing.Font("Segoe UI", 11)
    $lblSub.ForeColor = [System.Drawing.Color]::FromArgb(136, 153, 170)
    $lblSub.AutoSize = $false
    $lblSub.Size = New-Object System.Drawing.Size(740, 22)
    $lblSub.Location = New-Object System.Drawing.Point(15, $yPos)
    $lblSub.TextAlign = "MiddleCenter"
    $form.Controls.Add($lblSub)
    $yPos += 35

    # Test selection checkboxes
    $lblSelect = New-Object System.Windows.Forms.Label
    $lblSelect.Text = "SELECT TESTS TO RUN:"
    $lblSelect.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $lblSelect.ForeColor = [System.Drawing.ColorTranslator]::FromHtml($COLOR_ACCENT)
    $lblSelect.AutoSize = $true
    $lblSelect.Location = New-Object System.Drawing.Point(25, $yPos)
    $form.Controls.Add($lblSelect)
    $yPos += 25

    $checkboxes = @{}
    $testNames = @(
        @{ Key = "CPU";         Label = "CPU Test (stress test, temperature, benchmark)" }
        @{ Key = "Memory";      Label = "Memory Test (DIMM mapping, allocation test)" }
        @{ Key = "Storage";     Label = "Storage Test (SMART, health, read speed)" }
        @{ Key = "GPU";         Label = "GPU Test (driver, VRAM, displays)" }
        @{ Key = "Battery";     Label = "Battery Test (wear, cycles, capacity)" }
        @{ Key = "Network";     Label = "Network Test (adapters, WiFi, DNS, speed)" }
        @{ Key = "Peripherals"; Label = "Peripheral Test (USB, audio, printers, Bluetooth)" }
    )

    # Two columns of checkboxes
    $colWidth = 350
    $col = 0
    $rowY = $yPos
    foreach ($test in $testNames) {
        $cb = New-Object System.Windows.Forms.CheckBox
        $cb.Text = $test.Label
        $cb.Font = New-Object System.Drawing.Font("Segoe UI", 9)
        $cb.ForeColor = [System.Drawing.Color]::White
        $cb.AutoSize = $false
        $cb.Size = New-Object System.Drawing.Size($colWidth, 22)
        $cb.Checked = $true
        $xPos = if ($col -eq 0) { 30 } else { 390 }
        $cb.Location = New-Object System.Drawing.Point($xPos, $rowY)
        $cb.FlatStyle = "Flat"
        $form.Controls.Add($cb)
        $checkboxes[$test.Key] = $cb
        if ($col -eq 1) { $rowY += 26; $col = 0 } else { $col++ }
    }
    if ($col -eq 1) { $rowY += 26 }
    $yPos = $rowY + 5

    # Select All / Deselect All
    $btnSelectAll = New-Object System.Windows.Forms.Button
    $btnSelectAll.Text = "Select All"
    $btnSelectAll.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $btnSelectAll.Size = New-Object System.Drawing.Size(90, 26)
    $btnSelectAll.Location = New-Object System.Drawing.Point(30, $yPos)
    $btnSelectAll.FlatStyle = "Flat"
    $btnSelectAll.BackColor = [System.Drawing.ColorTranslator]::FromHtml($COLOR_GREEN)
    $btnSelectAll.ForeColor = [System.Drawing.Color]::White
    $btnSelectAll.Add_Click({ foreach ($cb in $checkboxes.Values) { $cb.Checked = $true } })
    $form.Controls.Add($btnSelectAll)

    $btnDeselectAll = New-Object System.Windows.Forms.Button
    $btnDeselectAll.Text = "Deselect All"
    $btnDeselectAll.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $btnDeselectAll.Size = New-Object System.Drawing.Size(90, 26)
    $btnDeselectAll.Location = New-Object System.Drawing.Point(130, $yPos)
    $btnDeselectAll.FlatStyle = "Flat"
    $btnDeselectAll.BackColor = [System.Drawing.Color]::FromArgb(60, 70, 85)
    $btnDeselectAll.ForeColor = [System.Drawing.Color]::White
    $btnDeselectAll.Add_Click({ foreach ($cb in $checkboxes.Values) { $cb.Checked = $false } })
    $form.Controls.Add($btnDeselectAll)
    $yPos += 38

    # Separator
    $sep = New-Object System.Windows.Forms.Label
    $sep.Text = ""
    $sep.BorderStyle = "Fixed3D"
    $sep.AutoSize = $false
    $sep.Size = New-Object System.Drawing.Size(720, 2)
    $sep.Location = New-Object System.Drawing.Point(25, $yPos)
    $form.Controls.Add($sep)
    $yPos += 12

    # Progress / Status
    $lblStatus = New-Object System.Windows.Forms.Label
    $lblStatus.Text = "Ready to run diagnostics"
    $lblStatus.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(200, 200, 200)
    $lblStatus.AutoSize = $false
    $lblStatus.Size = New-Object System.Drawing.Size(720, 22)
    $lblStatus.Location = New-Object System.Drawing.Point(25, $yPos)
    $form.Controls.Add($lblStatus)
    $yPos += 25

    $progressBar = New-Object System.Windows.Forms.ProgressBar
    $progressBar.Location = New-Object System.Drawing.Point(25, $yPos)
    $progressBar.Size = New-Object System.Drawing.Size(720, 22)
    $progressBar.Style = "Continuous"
    $progressBar.Minimum = 0
    $progressBar.Maximum = 100
    $progressBar.Value = 0
    $form.Controls.Add($progressBar)
    $yPos += 35

    # Results ListView
    $listView = New-Object System.Windows.Forms.ListView
    $listView.View = "Details"
    $listView.Location = New-Object System.Drawing.Point(25, $yPos)
    $listView.Size = New-Object System.Drawing.Size(720, 250)
    $listView.BackColor = [System.Drawing.Color]::FromArgb(15, 31, 53)
    $listView.ForeColor = [System.Drawing.Color]::White
    $listView.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $listView.FullRowSelect = $true
    $listView.GridLines = $true
    $listView.HeaderStyle = "Nonclickable"

    [void]$listView.Columns.Add("Category", 110)
    [void]$listView.Columns.Add("Test", 200)
    [void]$listView.Columns.Add("Result", 240)
    [void]$listView.Columns.Add("Status", 70)
    [void]$listView.Columns.Add("Details", 90)

    $form.Controls.Add($listView)
    $yPos += 260

    # Score display
    $lblScore = New-Object System.Windows.Forms.Label
    $lblScore.Text = ""
    $lblScore.Font = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
    $lblScore.ForeColor = [System.Drawing.ColorTranslator]::FromHtml($COLOR_ACCENT)
    $lblScore.AutoSize = $false
    $lblScore.Size = New-Object System.Drawing.Size(720, 30)
    $lblScore.Location = New-Object System.Drawing.Point(25, $yPos)
    $lblScore.TextAlign = "MiddleCenter"
    $form.Controls.Add($lblScore)
    $yPos += 35

    # Action buttons
    $btnRun = New-Object System.Windows.Forms.Button
    $btnRun.Text = "Run Diagnostics"
    $btnRun.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
    $btnRun.Size = New-Object System.Drawing.Size(160, 40)
    $btnRun.Location = New-Object System.Drawing.Point(100, $yPos)
    $btnRun.FlatStyle = "Flat"
    $btnRun.BackColor = [System.Drawing.ColorTranslator]::FromHtml($COLOR_GREEN)
    $btnRun.ForeColor = [System.Drawing.Color]::White
    $btnRun.Cursor = [System.Windows.Forms.Cursors]::Hand
    $form.Controls.Add($btnRun)

    $btnReport = New-Object System.Windows.Forms.Button
    $btnReport.Text = "Open Report"
    $btnReport.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $btnReport.Size = New-Object System.Drawing.Size(120, 40)
    $btnReport.Location = New-Object System.Drawing.Point(280, $yPos)
    $btnReport.FlatStyle = "Flat"
    $btnReport.BackColor = [System.Drawing.ColorTranslator]::FromHtml($COLOR_ACCENT)
    $btnReport.ForeColor = [System.Drawing.Color]::White
    $btnReport.Enabled = $false
    $btnReport.Cursor = [System.Windows.Forms.Cursors]::Hand
    $form.Controls.Add($btnReport)

    $btnExport = New-Object System.Windows.Forms.Button
    $btnExport.Text = "Save Report As..."
    $btnExport.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $btnExport.Size = New-Object System.Drawing.Size(130, 40)
    $btnExport.Location = New-Object System.Drawing.Point(415, $yPos)
    $btnExport.FlatStyle = "Flat"
    $btnExport.BackColor = [System.Drawing.Color]::FromArgb(60, 70, 85)
    $btnExport.ForeColor = [System.Drawing.Color]::White
    $btnExport.Enabled = $false
    $btnExport.Cursor = [System.Windows.Forms.Cursors]::Hand
    $form.Controls.Add($btnExport)

    $btnClose = New-Object System.Windows.Forms.Button
    $btnClose.Text = "Close"
    $btnClose.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $btnClose.Size = New-Object System.Drawing.Size(90, 40)
    $btnClose.Location = New-Object System.Drawing.Point(560, $yPos)
    $btnClose.FlatStyle = "Flat"
    $btnClose.BackColor = [System.Drawing.ColorTranslator]::FromHtml($COLOR_RED)
    $btnClose.ForeColor = [System.Drawing.Color]::White
    $btnClose.Add_Click({ $form.Close() })
    $form.Controls.Add($btnClose)

    # Track report path
    $script:reportHtmlPath = $null

    # Button handlers
    $btnReport.Add_Click({
        if ($script:reportHtmlPath -and (Test-Path $script:reportHtmlPath)) {
            Start-Process $script:reportHtmlPath
        }
    })

    $btnExport.Add_Click({
        if ($script:reportHtmlPath -and (Test-Path $script:reportHtmlPath)) {
            $sfd = New-Object System.Windows.Forms.SaveFileDialog
            $sfd.Filter = "HTML Files (*.html)|*.html"
            $sfd.FileName = [System.IO.Path]::GetFileName($script:reportHtmlPath)
            $sfd.Title = "Save Hardware Diagnostic Report"
            if ($sfd.ShowDialog() -eq "OK") {
                Copy-Item -Path $script:reportHtmlPath -Destination $sfd.FileName -Force
                [System.Windows.Forms.MessageBox]::Show("Report saved to:`n$($sfd.FileName)", "Saved", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
            }
        }
    })

    $btnRun.Add_Click({
        # Determine which tests to run
        $selectedTests = [System.Collections.ArrayList]::new()
        foreach ($key in $checkboxes.Keys) {
            if ($checkboxes[$key].Checked) {
                [void]$selectedTests.Add($key)
            }
        }

        if ($selectedTests.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show("Please select at least one test to run.", "No Tests Selected", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
            return
        }

        # Disable controls during test
        $btnRun.Enabled = $false
        $btnRun.Text = "Running..."
        $btnReport.Enabled = $false
        $btnExport.Enabled = $false
        foreach ($cb in $checkboxes.Values) { $cb.Enabled = $false }
        $listView.Items.Clear()
        $progressBar.Value = 0

        $allResults = [System.Collections.ArrayList]::new()
        $testResults = @{}
        $step = 0
        $totalSteps = $selectedTests.Count

        # Test dispatch
        $testFunctions = @{
            "CPU"         = { Test-CPU -StatusLabel $lblStatus }
            "Memory"      = { Test-Memory -StatusLabel $lblStatus }
            "Storage"     = { Test-Storage -StatusLabel $lblStatus }
            "GPU"         = { Test-GPU -StatusLabel $lblStatus }
            "Battery"     = { Test-Battery -StatusLabel $lblStatus }
            "Network"     = { Test-Network -StatusLabel $lblStatus }
            "Peripherals" = { Test-Peripherals -StatusLabel $lblStatus }
        }

        foreach ($testName in $selectedTests) {
            $step++
            $progressBar.Value = [math]::Round(($step / $totalSteps) * 100)
            [System.Windows.Forms.Application]::DoEvents()

            $catResults = & $testFunctions[$testName]
            $testResults[$testName] = $catResults

            # Add to ListView and allResults
            foreach ($r in $catResults) {
                [void]$allResults.Add($r)
                $item = New-Object System.Windows.Forms.ListViewItem($testName)
                [void]$item.SubItems.Add($r.Name)
                [void]$item.SubItems.Add($r.Value)
                [void]$item.SubItems.Add($r.Status)
                [void]$item.SubItems.Add($r.Details)

                switch ($r.Status) {
                    "PASS" { $item.ForeColor = [System.Drawing.ColorTranslator]::FromHtml($COLOR_GREEN) }
                    "WARN" { $item.ForeColor = [System.Drawing.ColorTranslator]::FromHtml($COLOR_ORANGE) }
                    "FAIL" { $item.ForeColor = [System.Drawing.ColorTranslator]::FromHtml($COLOR_RED) }
                    "INFO" { $item.ForeColor = [System.Drawing.Color]::White }
                }

                [void]$listView.Items.Add($item)
                $listView.EnsureVisible($listView.Items.Count - 1)
                [System.Windows.Forms.Application]::DoEvents()
            }
        }

        $progressBar.Value = 100

        # Calculate score
        $overallScore = Get-OverallHealthScore -AllResults $allResults
        $overallGrade = Get-LetterGrade -Score $overallScore
        $gradeColor = switch -Wildcard ($overallGrade) {
            "A*" { $COLOR_GREEN }
            "B*" { $COLOR_ACCENT }
            "C*" { $COLOR_ORANGE }
            default { $COLOR_RED }
        }

        $lblScore.Text = "Hardware Health: $overallGrade ($overallScore/100)"
        $lblScore.ForeColor = [System.Drawing.ColorTranslator]::FromHtml($gradeColor)
        $lblStatus.Text = "Diagnostics complete - $($allResults.Count) tests performed"

        # Generate reports
        try {
            $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"

            $htmlFileName = "HardwareDiag-$env:COMPUTERNAME-$timestamp.html"
            $htmlPath = Join-Path $ReportsDir $htmlFileName
            $html = New-HardwareDiagHtml -TestResults $testResults -OverallScore $overallScore -OverallGrade $overallGrade -TestsRun @($selectedTests)
            $html | Set-Content -Path $htmlPath -Encoding UTF8 -Force
            $script:reportHtmlPath = $htmlPath

            $jsonFileName = "HardwareDiag-$env:COMPUTERNAME-$timestamp.json"
            $jsonPath = Join-Path $ReportsDir $jsonFileName
            Save-HardwareDiagJson -TestResults $testResults -OverallScore $overallScore -OverallGrade $overallGrade -TestsRun @($selectedTests) -OutputPath $jsonPath

            $btnReport.Enabled = $true
            $btnExport.Enabled = $true
        } catch {
            [System.Windows.Forms.MessageBox]::Show("Error saving report: $($_.Exception.Message)", "Report Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        }

        # Re-enable controls
        $btnRun.Enabled = $true
        $btnRun.Text = "Run Again"
        foreach ($cb in $checkboxes.Values) { $cb.Enabled = $true }
    })

    [void]$form.ShowDialog()
}

# ─────────────────────────────────────────────────────────────────────────────
# MAIN ENTRY POINT
# ─────────────────────────────────────────────────────────────────────────────
Show-DiagnosticUI

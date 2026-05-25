<# 
PC Plus 360 - Advanced Physical RAM Isolation Test
Author: PC Plus Computing
Purpose:
  Guided technician workflow to isolate faulty RAM sticks or motherboard DIMM slots.

Important:
  A true physical isolation test requires testing ONE RAM stick at a time and/or one slot at a time.
  This script does NOT physically isolate RAM by itself. It guides the technician, records results,
  runs safe Windows-based memory stress checks, and creates a professional log/report.

Safety:
  - Close customer applications before running.
  - Save all work.
  - Do not run deep tests on unstable systems with unsaved data.
  - For final confirmation, use MemTest86 bootable USB if instability is detected.

Recommended workflow:
  Round 1: Test each RAM stick in known-good Slot A1.
  Round 2: Test known-good RAM stick in each motherboard slot.
#>

param(
    [ValidateSet("Quick","Standard","Deep")]
    [string]$Mode = "Standard",

    [string]$CustomerName = "Customer",
    [string]$TechnicianName = "PC Plus Technician",

    [int]$QuickMinutes = 3,
    [int]$StandardMinutes = 10,
    [int]$DeepMinutes = 30,

    [int]$MemoryUsePercent = 75,

    [switch]$JsonOutput
)

$ErrorActionPreference = "Continue"

trap {
    Write-Host ""
    Write-Host "  UNEXPECTED ERROR: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "  Line: $($_.InvocationInfo.ScriptLineNumber)" -ForegroundColor DarkGray
    Write-Host ""
    Read-Host "  Press Enter to exit"
    break
}

# ------------------------------
# Global Paths
# ------------------------------
$BaseDir = "C:\PCPlus360\RAM-Isolation"
$TimeStamp = Get-Date -Format "yyyyMMdd-HHmmss"
$ComputerNameSafe = $env:COMPUTERNAME -replace '[^\w\-]', '_'
$SessionDir = Join-Path $BaseDir "$ComputerNameSafe-$TimeStamp"
$LogFile = Join-Path $SessionDir "PCPlus360-RAM-Isolation-Log.txt"
$CsvFile = Join-Path $SessionDir "PCPlus360-RAM-Isolation-Results.csv"
$HtmlFile = Join-Path $SessionDir "PCPlus360-RAM-Isolation-Report.html"
$JsonFile = Join-Path $SessionDir "PCPlus360-RAM-Isolation-RawData.json"

New-Item -ItemType Directory -Path $SessionDir -Force | Out-Null

# ------------------------------
# Helper Functions
# ------------------------------
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $line = "[{0}] [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Level, $Message
    Write-Host $line
    Add-Content -Path $LogFile -Value $line
}

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-TestDurationMinutes {
    switch ($Mode) {
        "Quick" { return $QuickMinutes }
        "Standard" { return $StandardMinutes }
        "Deep" { return $DeepMinutes }
    }
}

function Get-SystemSummary {
    $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
    $bios = Get-CimInstance Win32_BIOS -ErrorAction SilentlyContinue
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    $cpu = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1

    [PSCustomObject]@{
        ComputerName = $env:COMPUTERNAME
        Manufacturer = $cs.Manufacturer
        Model = $cs.Model
        SerialNumber = $bios.SerialNumber
        BIOSVersion = ($bios.SMBIOSBIOSVersion -join " ")
        OS = $os.Caption
        OSBuild = $os.BuildNumber
        CPU = $cpu.Name
        TotalRAMGB = [math]::Round($cs.TotalPhysicalMemory / 1GB, 2)
        ReportDate = Get-Date
    }
}

function Get-RamInventory {
    $memory = Get-CimInstance Win32_PhysicalMemory -ErrorAction SilentlyContinue
    $slots = Get-CimInstance Win32_PhysicalMemoryArray -ErrorAction SilentlyContinue

    $memory | ForEach-Object {
        [PSCustomObject]@{
            Slot = $_.DeviceLocator
            Bank = $_.BankLabel
            CapacityGB = [math]::Round($_.Capacity / 1GB, 2)
            SpeedMHz = $_.Speed
            ConfiguredClockSpeedMHz = $_.ConfiguredClockSpeed
            Manufacturer = $_.Manufacturer
            PartNumber = ($_.PartNumber -as [string]).Trim()
            SerialNumber = ($_.SerialNumber -as [string]).Trim()
            SMBIOSMemoryType = $_.SMBIOSMemoryType
            FormFactor = $_.FormFactor
        }
    }
}

function Get-RecentMemoryRelatedEvents {
    param([int]$HoursBack = 24)

    $start = (Get-Date).AddHours(-$HoursBack)
    $events = @()

    $filters = @(
        @{LogName='System'; Id=41; StartTime=$start},     # Kernel-Power
        @{LogName='System'; Id=1001; StartTime=$start},   # BugCheck
        @{LogName='System'; Id=6008; StartTime=$start},   # Unexpected shutdown
        @{LogName='System'; ProviderName='Microsoft-Windows-WHEA-Logger'; StartTime=$start}
    )

    foreach ($filter in $filters) {
        try {
            $events += Get-WinEvent -FilterHashtable $filter -ErrorAction SilentlyContinue | Select-Object TimeCreated, ProviderName, Id, LevelDisplayName, Message
        } catch {}
    }

    try {
        $events += Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Microsoft-Windows-MemoryDiagnostics-Results'; StartTime=$start} -ErrorAction SilentlyContinue |
            Select-Object TimeCreated, ProviderName, Id, LevelDisplayName, Message
    } catch {}

    return $events | Sort-Object TimeCreated -Descending
}

function Invoke-MemoryStressTest {
    param(
        [int]$DurationMinutes = 10,
        [int]$UsePercent = 75
    )

    Write-Log "Starting memory stress test. Duration: $DurationMinutes minutes. Target RAM usage: $UsePercent%."

    $os = Get-CimInstance Win32_OperatingSystem
    $totalBytes = [double]$os.TotalVisibleMemorySize * 1KB
    $targetBytes = [int64]($totalBytes * ($UsePercent / 100))
    $blockSizeMB = 128
    $blockBytes = $blockSizeMB * 1MB
    $blocksToAllocate = [math]::Max(1, [math]::Floor($targetBytes / $blockBytes))

    $allocated = New-Object System.Collections.Generic.List[byte[]]
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $end = (Get-Date).AddMinutes($DurationMinutes)

    $result = [ordered]@{
        TestStart = Get-Date
        DurationMinutes = $DurationMinutes
        TargetUsePercent = $UsePercent
        BlocksAllocated = 0
        TargetBytes = $targetBytes
        AllocationFailures = 0
        PatternErrors = 0
        RandomErrors = 0
        CompressionErrors = 0
        PeakWorkingSetMB = 0
        AverageAvailableMemoryMB = 0
        Samples = @()
        Passed = $true
        Notes = @()
    }

    try {
        for ($i = 0; $i -lt $blocksToAllocate; $i++) {
            try {
                $block = New-Object byte[] $blockBytes
                $allocated.Add($block)
                $result.BlocksAllocated++
            } catch {
                $result.AllocationFailures++
                $result.Notes += "Allocation failed at block $i: $($_.Exception.Message)"
                break
            }
        }

        if ($allocated.Count -eq 0) {
            throw "No memory blocks could be allocated."
        }

        $patterns = @(0x00, 0xFF, 0xAA, 0x55)

        while ((Get-Date) -lt $end) {
            foreach ($pattern in $patterns) {
                foreach ($block in $allocated) {
                    try {
                        $fillByte = [byte]$pattern
                        $chunk = New-Object byte[] 4096
                        for ($i = 0; $i -lt 4096; $i++) { $chunk[$i] = $fillByte }
                        for ($i = 0; $i -lt $block.Length; $i += 4096) {
                            $len = [math]::Min(4096, $block.Length - $i)
                            [Buffer]::BlockCopy($chunk, 0, $block, $i, $len)
                        }

                        # Sample check every 4KB instead of reading every byte to keep test practical in PowerShell.
                        for ($offset = 0; $offset -lt $block.Length; $offset += 4096) {
                            if ($block[$offset] -ne [byte]$pattern) {
                                $result.PatternErrors++
                                $result.Passed = $false
                                break
                            }
                        }
                    } catch {
                        $result.PatternErrors++
                        $result.Passed = $false
                    }
                }
            }

            # Random write/read test.
            $rng = [Random]::new()
            foreach ($block in $allocated) {
                try {
                    for ($j = 0; $j -lt 256; $j++) {
                        $idx = $rng.Next(0, $block.Length)
                        $val = [byte]$rng.Next(0, 256)
                        $block[$idx] = $val
                        if ($block[$idx] -ne $val) {
                            $result.RandomErrors++
                            $result.Passed = $false
                        }
                    }
                } catch {
                    $result.RandomErrors++
                    $result.Passed = $false
                }
            }

            $counter = Get-Counter '\Memory\Available MBytes' -ErrorAction SilentlyContinue
            $availableMB = if ($counter) { [math]::Round($counter.CounterSamples[0].CookedValue, 2) } else { $null }
            $workingSetMB = [math]::Round((Get-Process -Id $PID).WorkingSet64 / 1MB, 2)
            if ($workingSetMB -gt $result.PeakWorkingSetMB) { $result.PeakWorkingSetMB = $workingSetMB }

            $result.Samples += [PSCustomObject]@{
                Time = Get-Date
                AvailableMemoryMB = $availableMB
                ProcessWorkingSetMB = $workingSetMB
                PatternErrors = $result.PatternErrors
                RandomErrors = $result.RandomErrors
            }

            Start-Sleep -Seconds 5
        }
    } catch {
        $result.Passed = $false
        $result.Notes += "Fatal test error: $($_.Exception.Message)"
        Write-Log "Memory stress test error: $($_.Exception.Message)" "ERROR"
    } finally {
        $allocated.Clear()
        [GC]::Collect()
        [GC]::WaitForPendingFinalizers()
    }

    $result.TestEnd = Get-Date

    $validSamples = $result.Samples | Where-Object { $null -ne $_.AvailableMemoryMB }
    if ($validSamples.Count -gt 0) {
        $result.AverageAvailableMemoryMB = [math]::Round(($validSamples | Measure-Object AvailableMemoryMB -Average).Average, 2)
    }

    if ($result.AllocationFailures -gt 0 -or $result.PatternErrors -gt 0 -or $result.RandomErrors -gt 0) {
        $result.Passed = $false
    }

    Write-Log "Memory stress test completed. Passed: $($result.Passed). PatternErrors: $($result.PatternErrors). RandomErrors: $($result.RandomErrors). AllocationFailures: $($result.AllocationFailures)."

    return [PSCustomObject]$result
}

function Get-RamConfigurationWarnings {
    param($RamInventory)

    $warnings = @()

    if (-not $RamInventory -or $RamInventory.Count -eq 0) {
        return @("No RAM inventory detected through WMI/CIM.")
    }

    $speeds = $RamInventory | Where-Object {$_.SpeedMHz} | Select-Object -ExpandProperty SpeedMHz -Unique
    if ($speeds.Count -gt 1) {
        $warnings += "Mixed RAM speeds detected: $($speeds -join ', ') MHz."
    }

    $sizes = $RamInventory | Select-Object -ExpandProperty CapacityGB -Unique
    if ($sizes.Count -gt 1) {
        $warnings += "Mixed RAM capacities detected: $($sizes -join ', ') GB."
    }

    $manufacturers = $RamInventory | Where-Object {$_.Manufacturer} | Select-Object -ExpandProperty Manufacturer -Unique
    if ($manufacturers.Count -gt 1) {
        $warnings += "Mixed RAM manufacturers detected: $($manufacturers -join ', ')."
    }

    $configuredSpeeds = $RamInventory | Where-Object {$_.ConfiguredClockSpeedMHz} | Select-Object -ExpandProperty ConfiguredClockSpeedMHz -Unique
    if ($configuredSpeeds.Count -gt 1) {
        $warnings += "Mixed configured RAM clock speeds detected: $($configuredSpeeds -join ', ') MHz."
    }

    return $warnings
}

function Get-MemoryThermalInfo {
    Write-Log "Checking memory controller thermal information."
    $thermalData = [PSCustomObject]@{
        Source            = "None"
        TemperatureCelsius = $null
        Status            = "Unknown"
        Notes             = @()
    }

    # Try LibreHardwareMonitor WMI namespace first (most accurate)
    try {
        $lhwSensors = Get-CimInstance -Namespace "root/LibreHardwareMonitor" -ClassName Sensor -ErrorAction Stop |
            Where-Object { $_.SensorType -eq "Temperature" -and $_.Name -match "Memory|RAM|DIMM" } |
            Select-Object -First 1
        if ($lhwSensors) {
            $thermalData.Source = "LibreHardwareMonitor"
            $thermalData.TemperatureCelsius = [math]::Round($lhwSensors.Value, 1)
            $thermalData.Notes += "Reading from LibreHardwareMonitor sensor: $($lhwSensors.Name)"
        }
    } catch {
        $thermalData.Notes += "LibreHardwareMonitor WMI not available."
    }

    # Fallback: try OpenHardwareMonitor namespace
    if ($null -eq $thermalData.TemperatureCelsius) {
        try {
            $ohmSensors = Get-CimInstance -Namespace "root/OpenHardwareMonitor" -ClassName Sensor -ErrorAction Stop |
                Where-Object { $_.SensorType -eq "Temperature" -and $_.Name -match "Memory|RAM|DIMM" } |
                Select-Object -First 1
            if ($ohmSensors) {
                $thermalData.Source = "OpenHardwareMonitor"
                $thermalData.TemperatureCelsius = [math]::Round($ohmSensors.Value, 1)
                $thermalData.Notes += "Reading from OpenHardwareMonitor sensor: $($ohmSensors.Name)"
            }
        } catch {
            $thermalData.Notes += "OpenHardwareMonitor WMI not available."
        }
    }

    # Fallback: MSAcpi_ThermalZoneTemperature (system-wide, not memory-specific)
    if ($null -eq $thermalData.TemperatureCelsius) {
        try {
            $acpiThermal = Get-CimInstance -Namespace "root/WMI" -ClassName MSAcpi_ThermalZoneTemperature -ErrorAction Stop |
                Select-Object -First 1
            if ($acpiThermal -and $acpiThermal.CurrentTemperature) {
                # MSAcpi returns temperature in tenths of Kelvin
                $celsius = [math]::Round(($acpiThermal.CurrentTemperature / 10) - 273.15, 1)
                if ($celsius -gt -40 -and $celsius -lt 150) {
                    $thermalData.Source = "MSAcpi_ThermalZoneTemperature (system-wide, not memory-specific)"
                    $thermalData.TemperatureCelsius = $celsius
                    $thermalData.Notes += "ACPI thermal zone reading (may represent CPU/chipset, not memory directly)."
                }
            }
        } catch {
            $thermalData.Notes += "MSAcpi_ThermalZoneTemperature not accessible (requires admin)."
        }
    }

    # Determine status based on temperature
    if ($null -ne $thermalData.TemperatureCelsius) {
        $temp = $thermalData.TemperatureCelsius
        if ($temp -lt 45) { $thermalData.Status = "Normal" }
        elseif ($temp -lt 60) { $thermalData.Status = "Warm" }
        elseif ($temp -lt 75) { $thermalData.Status = "Hot - check airflow" }
        else { $thermalData.Status = "Critical - potential thermal damage" }
    } else {
        $thermalData.Status = "Not available"
        $thermalData.Notes += "Install LibreHardwareMonitor for memory-specific thermal readings."
    }

    return $thermalData
}

function Get-PredictiveFailureAssessment {
    param(
        $RoundResults,
        $Events,
        $ConfigWarnings
    )

    Write-Log "Computing predictive failure assessment."

    $riskScore = 0
    $factors = @()

    # Factor 1: Test round failures
    $failCount = @($RoundResults | Where-Object { $_.Result -eq "FAIL" }).Count
    $warnCount = @($RoundResults | Where-Object { $_.Result -eq "WARNING" }).Count
    if ($failCount -gt 0) {
        $riskScore += [math]::Min(40, $failCount * 20)
        $factors += "FAIL results in $failCount test round(s)."
    }
    if ($warnCount -gt 0) {
        $riskScore += [math]::Min(15, $warnCount * 5)
        $factors += "WARNING results in $warnCount test round(s)."
    }

    # Factor 2: Pattern errors across rounds
    $totalPatternErrors = ($RoundResults | Measure-Object PatternErrors -Sum -ErrorAction SilentlyContinue).Sum
    $totalRandomErrors  = ($RoundResults | Measure-Object RandomErrors -Sum -ErrorAction SilentlyContinue).Sum
    if ($totalPatternErrors -gt 0) {
        $riskScore += [math]::Min(25, $totalPatternErrors * 5)
        $factors += "Total pattern errors: $totalPatternErrors."
    }
    if ($totalRandomErrors -gt 0) {
        $riskScore += [math]::Min(20, $totalRandomErrors * 5)
        $factors += "Total random errors: $totalRandomErrors."
    }

    # Factor 3: WHEA / hardware error events
    $wheaEvents = @($Events | Where-Object { $_.ProviderName -match "WHEA" })
    if ($wheaEvents.Count -gt 0) {
        $riskScore += [math]::Min(20, $wheaEvents.Count * 5)
        $factors += "WHEA hardware errors in event log: $($wheaEvents.Count)."
    }

    # Factor 4: BugCheck / BSOD events
    $bsodEvents = @($Events | Where-Object { $_.Id -eq 1001 })
    if ($bsodEvents.Count -gt 0) {
        $riskScore += [math]::Min(15, $bsodEvents.Count * 5)
        $factors += "BugCheck/BSOD events: $($bsodEvents.Count)."
    }

    # Factor 5: Unexpected shutdowns
    $unexpectedShutdowns = @($Events | Where-Object { $_.Id -in @(41, 6008) })
    if ($unexpectedShutdowns.Count -gt 0) {
        $riskScore += [math]::Min(10, $unexpectedShutdowns.Count * 3)
        $factors += "Unexpected shutdown events: $($unexpectedShutdowns.Count)."
    }

    # Factor 6: Configuration warnings (mixed RAM)
    if ($ConfigWarnings.Count -gt 0) {
        $riskScore += [math]::Min(10, $ConfigWarnings.Count * 3)
        $factors += "RAM configuration warnings: $($ConfigWarnings.Count)."
    }

    # Cap at 100
    if ($riskScore -gt 100) { $riskScore = 100 }

    # Determine probability level
    $probability = if ($riskScore -ge 60) { "High" }
        elseif ($riskScore -ge 30) { "Medium" }
        else { "Low" }

    $recommendation = switch ($probability) {
        "High"   { "Imminent DIMM failure likely. Replace suspect module(s) immediately. Confirm with MemTest86." }
        "Medium" { "Elevated risk of DIMM failure. Monitor closely, run MemTest86, consider proactive replacement." }
        "Low"    { "No strong indicators of imminent DIMM failure. Continue monitoring." }
    }

    [PSCustomObject]@{
        RiskScore       = $riskScore
        Probability     = $probability
        Factors         = $factors
        Recommendation  = $recommendation
    }
}

function Get-DIMMSlotMap {
    Write-Log "Mapping DIMM slot population."

    $memArrays = @(Get-CimInstance Win32_PhysicalMemoryArray -ErrorAction SilentlyContinue)
    $memModules = @(Get-CimInstance Win32_PhysicalMemory -ErrorAction SilentlyContinue)

    $totalSlots = 0
    $maxCapacityGB = 0
    foreach ($arr in $memArrays) {
        if ($arr.MemoryDevices) { $totalSlots += $arr.MemoryDevices }
        if ($arr.MaxCapacity) {
            # MaxCapacity is in KB
            $maxCapacityGB += [math]::Round($arr.MaxCapacity / 1MB, 2)
        } elseif ($arr.MaxCapacityEx) {
            # MaxCapacityEx is in KB (large memory support)
            $maxCapacityGB += [math]::Round($arr.MaxCapacityEx / 1MB, 2)
        }
    }

    $populatedSlots = $memModules.Count
    $emptySlots = [math]::Max(0, $totalSlots - $populatedSlots)
    $currentCapacityGB = 0
    foreach ($m in $memModules) {
        if ($m.Capacity) { $currentCapacityGB += [math]::Round($m.Capacity / 1GB, 2) }
    }

    # Build slot detail list
    $slotDetails = @()
    foreach ($m in $memModules) {
        $slotDetails += [PSCustomObject]@{
            SlotName     = $m.DeviceLocator
            Bank         = $m.BankLabel
            Status       = "Populated"
            CapacityGB   = [math]::Round($m.Capacity / 1GB, 2)
            SpeedMHz     = $m.Speed
            Manufacturer = $m.Manufacturer
            PartNumber   = ($m.PartNumber -as [string]).Trim()
            SerialNumber = ($m.SerialNumber -as [string]).Trim()
        }
    }

    # Upgrade recommendation
    $upgradeNotes = @()
    if ($emptySlots -gt 0) {
        $upgradeNotes += "$emptySlots empty slot(s) available for expansion."
    }
    if ($currentCapacityGB -lt $maxCapacityGB) {
        $remainingGB = [math]::Round($maxCapacityGB - $currentCapacityGB, 2)
        $upgradeNotes += "Can add up to $remainingGB GB more RAM (max supported: $maxCapacityGB GB)."
    }
    if ($emptySlots -eq 0 -and $currentCapacityGB -ge $maxCapacityGB) {
        $upgradeNotes += "All slots populated at maximum capacity. No further RAM upgrade possible without replacing existing modules."
    }
    if ($currentCapacityGB -lt 8) {
        $upgradeNotes += "Recommended: Upgrade to at least 8 GB for modern Windows usage."
    } elseif ($currentCapacityGB -lt 16) {
        $upgradeNotes += "Consider upgrading to 16 GB for multitasking and productivity."
    }

    [PSCustomObject]@{
        TotalSlots       = $totalSlots
        PopulatedSlots   = $populatedSlots
        EmptySlots       = $emptySlots
        MaxCapacityGB    = $maxCapacityGB
        CurrentCapacityGB = $currentCapacityGB
        SlotDetails      = $slotDetails
        UpgradeNotes     = $upgradeNotes
    }
}

function New-HtmlReport {
    param(
        $SystemSummary,
        $RamInventory,
        $RoundResults,
        $ConfigWarnings,
        $Events,
        $ThermalInfo,
        $PredictiveFailure,
        $DIMMSlotMap
    )

    $rows = foreach ($r in $RoundResults) {
        $statusClass = if ($r.Result -eq "PASS") { "pass" } elseif ($r.Result -eq "WARNING") { "warn" } else { "fail" }
        "<tr><td>$($r.Round)</td><td>$($r.TestType)</td><td>$($r.StickLabel)</td><td>$($r.SlotLabel)</td><td class='$statusClass'>$($r.Result)</td><td>$($r.DurationMinutes)</td><td>$($r.PatternErrors)</td><td>$($r.RandomErrors)</td><td>$($r.Notes)</td></tr>"
    }

    $ramRows = foreach ($m in $RamInventory) {
        "<tr><td>$($m.Slot)</td><td>$($m.Bank)</td><td>$($m.CapacityGB) GB</td><td>$($m.SpeedMHz)</td><td>$($m.ConfiguredClockSpeedMHz)</td><td>$($m.Manufacturer)</td><td>$($m.PartNumber)</td><td>$($m.SerialNumber)</td></tr>"
    }

    $warnItems = if ($ConfigWarnings.Count -gt 0) {
        ($ConfigWarnings | ForEach-Object { "<li>$_</li>" }) -join "`n"
    } else {
        "<li>No major RAM configuration warnings detected.</li>"
    }

    $eventRows = foreach ($e in ($Events | Select-Object -First 15)) {
        $msg = ($e.Message -replace '<','&lt;' -replace '>','&gt;')
        if ($msg.Length -gt 300) { $msg = $msg.Substring(0,300) + "..." }
        "<tr><td>$($e.TimeCreated)</td><td>$($e.ProviderName)</td><td>$($e.Id)</td><td>$($e.LevelDisplayName)</td><td>$msg</td></tr>"
    }

    $html = @"
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<title>PC Plus 360 RAM Isolation Report</title>
<style>
body { font-family: Segoe UI, Arial, sans-serif; background:#f3f8fb; margin:0; color:#163247; }
.header { background:linear-gradient(135deg,#0d4b71,#2596be); color:white; padding:30px; }
.header h1 { margin:0; font-size:34px; }
.header p { margin:8px 0 0 0; font-size:16px; }
.container { padding:25px; }
.card { background:white; border-radius:16px; padding:22px; margin-bottom:18px; box-shadow:0 8px 22px rgba(13,75,113,.12); }
.grid { display:grid; grid-template-columns:repeat(4,1fr); gap:14px; }
.metric { background:#eaf7fc; border-left:6px solid #2596be; border-radius:12px; padding:14px; }
.metric b { display:block; color:#0d4b71; font-size:13px; text-transform:uppercase; }
.metric span { font-size:18px; font-weight:700; }
table { width:100%; border-collapse:collapse; font-size:13px; }
th { background:#0d4b71; color:white; padding:10px; text-align:left; }
td { border-bottom:1px solid #dbe8ef; padding:9px; vertical-align:top; }
.pass { color:#16a34a; font-weight:700; }
.warn { color:#f59e0b; font-weight:700; }
.fail { color:#dc2626; font-weight:700; }
.footer { text-align:center; padding:20px; color:#64748b; font-size:12px; }
.badge { display:inline-block; padding:6px 10px; border-radius:999px; background:#eaf7fc; color:#0d4b71; font-weight:700; }
</style>
</head>
<body>
<div class="header">
  <h1>PC Plus 360 RAM Isolation Report</h1>
  <p>Advanced Physical RAM Isolation Workflow | PC Plus Computing | 604-760-1662 | pcpluscomputing.com</p>
</div>

<div class="container">
  <div class="card">
    <h2>Executive Summary</h2>
    <div class="grid">
      <div class="metric"><b>Customer</b><span>$CustomerName</span></div>
      <div class="metric"><b>Technician</b><span>$TechnicianName</span></div>
      <div class="metric"><b>Computer</b><span>$($SystemSummary.ComputerName)</span></div>
      <div class="metric"><b>Total RAM</b><span>$($SystemSummary.TotalRAMGB) GB</span></div>
    </div>
    <p><span class="badge">Mode: $Mode</span></p>
    <p>This report is designed to help isolate faulty RAM modules or motherboard DIMM slots using a guided technician workflow.</p>
  </div>

  <div class="card">
    <h2>RAM Configuration Warnings</h2>
    <ul>
      $warnItems
    </ul>
  </div>

  <div class="card">
    <h2>Detected RAM Modules</h2>
    <table>
      <tr><th>Slot</th><th>Bank</th><th>Capacity</th><th>Speed</th><th>Configured Speed</th><th>Manufacturer</th><th>Part Number</th><th>Serial</th></tr>
      $($ramRows -join "`n")
    </table>
  </div>

  <div class="card">
    <h2>Isolation Test Rounds</h2>
    <table>
      <tr><th>Round</th><th>Test Type</th><th>RAM Stick</th><th>Slot</th><th>Result</th><th>Minutes</th><th>Pattern Errors</th><th>Random Errors</th><th>Notes</th></tr>
      $($rows -join "`n")
    </table>
  </div>

  <div class="card">
    <h2>Recent Memory / Hardware Events</h2>
    <table>
      <tr><th>Time</th><th>Source</th><th>ID</th><th>Level</th><th>Message</th></tr>
      $($eventRows -join "`n")
    </table>
  </div>

  <div class="card">
    <h2>Memory Configuration Summary</h2>
    <div class="grid">
      <div class="metric"><b>Total Slots</b><span>$($DIMMSlotMap.TotalSlots)</span></div>
      <div class="metric"><b>Populated</b><span>$($DIMMSlotMap.PopulatedSlots)</span></div>
      <div class="metric"><b>Empty</b><span>$($DIMMSlotMap.EmptySlots)</span></div>
      <div class="metric"><b>Max Capacity</b><span>$($DIMMSlotMap.MaxCapacityGB) GB</span></div>
    </div>
    <p><b>Current Capacity:</b> $($DIMMSlotMap.CurrentCapacityGB) GB</p>
    <ul>
      $(($DIMMSlotMap.UpgradeNotes | ForEach-Object { "<li>$_</li>" }) -join "`n")
    </ul>
  </div>

  <div class="card">
    <h2>Thermal Monitoring</h2>
    <p><b>Source:</b> $($ThermalInfo.Source)</p>
    <p><b>Temperature:</b> $(if ($null -ne $ThermalInfo.TemperatureCelsius) { "$($ThermalInfo.TemperatureCelsius) C" } else { "N/A" })</p>
    <p><b>Status:</b> <span class="$(if ($ThermalInfo.Status -match 'Critical') {'fail'} elseif ($ThermalInfo.Status -match 'Hot|Warm') {'warn'} else {'pass'})">$($ThermalInfo.Status)</span></p>
    <ul>
      $(($ThermalInfo.Notes | ForEach-Object { "<li>$_</li>" }) -join "`n")
    </ul>
  </div>

  <div class="card">
    <h2>Predictive Failure Assessment</h2>
    <p><b>Risk Score:</b> $($PredictiveFailure.RiskScore)/100</p>
    <p><b>Failure Probability:</b> <span class="$(if ($PredictiveFailure.Probability -eq 'High') {'fail'} elseif ($PredictiveFailure.Probability -eq 'Medium') {'warn'} else {'pass'})">$($PredictiveFailure.Probability)</span></p>
    <p><b>Recommendation:</b> $($PredictiveFailure.Recommendation)</p>
    <h3>Risk Factors</h3>
    <ul>
      $(if ($PredictiveFailure.Factors.Count -gt 0) { ($PredictiveFailure.Factors | ForEach-Object { "<li>$_</li>" }) -join "`n" } else { "<li>No risk factors identified.</li>" })
    </ul>
  </div>

  <div class="card">
    <h2>Technician Recommendation</h2>
    <p>If one RAM stick fails in a known-good slot, suspect the RAM stick. If one known-good RAM stick fails in only one slot, suspect the motherboard slot or memory channel.</p>
    <p>For final confirmation, run MemTest86 bootable USB for 4 full passes.</p>
  </div>
</div>

<div class="footer">
  PC Plus Computing | Your Security, Our Priority | 30+ Years in Service | 4.9 Google Rating
</div>
</body>
</html>
"@

    Set-Content -Path $HtmlFile -Value $html -Encoding UTF8
}

# ------------------------------
# Main
# ------------------------------
Write-Log "PC Plus 360 Advanced Physical RAM Isolation Test started."
Write-Log "Mode: $Mode"
Write-Log "Session folder: $SessionDir"

if (-not (Test-IsAdmin)) {
    Write-Log "Script is not running as Administrator. Some event log or hardware details may be limited." "WARN"
}

$SystemSummary = Get-SystemSummary
$RamInventory = @(Get-RamInventory)
$ConfigWarnings = @(Get-RamConfigurationWarnings -RamInventory $RamInventory)

Write-Log "Detected system: $($SystemSummary.Manufacturer) $($SystemSummary.Model), Serial: $($SystemSummary.SerialNumber)"
Write-Log "Detected RAM modules: $($RamInventory.Count)"

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "PC PLUS 360 - ADVANCED PHYSICAL RAM ISOLATION TEST" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "IMPORTANT:" -ForegroundColor Yellow
Write-Host "This is a guided physical isolation workflow."
Write-Host "For exact stick/slot diagnosis, test ONE RAM stick at a time."
Write-Host ""
Write-Host "Recommended Workflow:" -ForegroundColor Yellow
Write-Host "1. RAM Stick Test: Test each stick in the same known-good slot."
Write-Host "2. Slot Test: Test one known-good stick in each motherboard slot."
Write-Host ""
Write-Host "Reports will be saved to: $SessionDir"
Write-Host ""

Write-Host "Detected RAM:" -ForegroundColor Green
$RamInventory | Format-Table Slot, Bank, CapacityGB, SpeedMHz, ConfiguredClockSpeedMHz, Manufacturer, PartNumber, SerialNumber -AutoSize

if ($ConfigWarnings.Count -gt 0) {
    Write-Host ""
    Write-Host "Configuration Warnings:" -ForegroundColor Yellow
    $ConfigWarnings | ForEach-Object { Write-Host "- $_" -ForegroundColor Yellow }
}

$RoundResults = @()
$round = 1
$duration = Get-TestDurationMinutes

do {
    Write-Host ""
    Write-Host "------------------------------" -ForegroundColor Cyan
    Write-Host "New Isolation Test Round #$round" -ForegroundColor Cyan
    Write-Host "------------------------------" -ForegroundColor Cyan

    $testType = Read-Host "Test type? Enter StickTest, SlotTest, or General"
    if ([string]::IsNullOrWhiteSpace($testType)) { $testType = "General" }

    $stickLabel = Read-Host "Enter RAM stick label/serial/description being tested"
    if ([string]::IsNullOrWhiteSpace($stickLabel)) { $stickLabel = "Not specified" }

    $slotLabel = Read-Host "Enter motherboard slot being tested, example DIMM_A1"
    if ([string]::IsNullOrWhiteSpace($slotLabel)) { $slotLabel = "Not specified" }

    Write-Host ""
    Write-Host "Before continuing, confirm the hardware setup is correct:" -ForegroundColor Yellow
    Write-Host "Test Type: $testType"
    Write-Host "RAM Stick: $stickLabel"
    Write-Host "Slot: $slotLabel"
    $confirm = Read-Host "Type YES to start the memory stress test"
    if ($confirm -ne "YES") {
        Write-Log "Round $round skipped by technician."
        continue
    }

    $eventsBefore = @(Get-RecentMemoryRelatedEvents -HoursBack 24)
    $stress = Invoke-MemoryStressTest -DurationMinutes $duration -UsePercent $MemoryUsePercent
    Start-Sleep -Seconds 3
    $eventsAfter = @(Get-RecentMemoryRelatedEvents -HoursBack 24)

    $newEventCount = [math]::Max(0, $eventsAfter.Count - $eventsBefore.Count)
    $resultStatus = if ($stress.Passed -and $newEventCount -eq 0) { "PASS" } elseif ($stress.Passed -and $newEventCount -gt 0) { "WARNING" } else { "FAIL" }

    $notes = @()
    if ($stress.AllocationFailures -gt 0) { $notes += "Allocation failures: $($stress.AllocationFailures)" }
    if ($stress.PatternErrors -gt 0) { $notes += "Pattern errors: $($stress.PatternErrors)" }
    if ($stress.RandomErrors -gt 0) { $notes += "Random errors: $($stress.RandomErrors)" }
    if ($newEventCount -gt 0) { $notes += "New/recent memory or hardware-related event count changed during/after test." }
    if ($stress.Notes.Count -gt 0) { $notes += ($stress.Notes -join "; ") }
    if ($notes.Count -eq 0) { $notes += "No memory errors detected during this Windows-based stress round." }

    $roundObject = [PSCustomObject]@{
        Round = $round
        TestType = $testType
        StickLabel = $stickLabel
        SlotLabel = $slotLabel
        Result = $resultStatus
        DurationMinutes = $duration
        TargetMemoryUsePercent = $MemoryUsePercent
        BlocksAllocated = $stress.BlocksAllocated
        AllocationFailures = $stress.AllocationFailures
        PatternErrors = $stress.PatternErrors
        RandomErrors = $stress.RandomErrors
        PeakWorkingSetMB = $stress.PeakWorkingSetMB
        AverageAvailableMemoryMB = $stress.AverageAvailableMemoryMB
        Notes = ($notes -join " | ")
        StartTime = $stress.TestStart
        EndTime = $stress.TestEnd
    }

    $RoundResults += $roundObject
    $roundObject | Export-Csv -Path $CsvFile -NoTypeInformation -Append

    Write-Host ""
    if ($resultStatus -eq "PASS") {
        Write-Host "Round Result: PASS" -ForegroundColor Green
    } elseif ($resultStatus -eq "WARNING") {
        Write-Host "Round Result: WARNING" -ForegroundColor Yellow
    } else {
        Write-Host "Round Result: FAIL" -ForegroundColor Red
    }
    Write-Host "Notes: $($roundObject.Notes)"

    $round++
    $again = Read-Host "Run another isolation round? Y/N"

} while ($again -match '^(Y|y)')

$Events = @(Get-RecentMemoryRelatedEvents -HoursBack 72)

# New diagnostics
$ThermalInfo = Get-MemoryThermalInfo
$DIMMSlotMap = Get-DIMMSlotMap
$PredictiveFailure = Get-PredictiveFailureAssessment -RoundResults $RoundResults -Events $Events -ConfigWarnings $ConfigWarnings

# Display memory configuration summary
Write-Host ""
Write-Host "Memory Configuration Summary:" -ForegroundColor Green
Write-Host "  Total Slots:      $($DIMMSlotMap.TotalSlots)"
Write-Host "  Populated Slots:  $($DIMMSlotMap.PopulatedSlots)"
Write-Host "  Empty Slots:      $($DIMMSlotMap.EmptySlots)"
Write-Host "  Max Capacity:     $($DIMMSlotMap.MaxCapacityGB) GB"
Write-Host "  Current Capacity: $($DIMMSlotMap.CurrentCapacityGB) GB"
if ($DIMMSlotMap.UpgradeNotes.Count -gt 0) {
    $DIMMSlotMap.UpgradeNotes | ForEach-Object { Write-Host "  - $_" -ForegroundColor Cyan }
}

# Display thermal info
Write-Host ""
Write-Host "Thermal Monitoring:" -ForegroundColor Green
Write-Host "  Source: $($ThermalInfo.Source)"
if ($null -ne $ThermalInfo.TemperatureCelsius) {
    Write-Host "  Temperature: $($ThermalInfo.TemperatureCelsius) C"
}
$thermalColor = if ($ThermalInfo.Status -match "Critical") { "Red" } elseif ($ThermalInfo.Status -match "Hot|Warm") { "Yellow" } else { "Green" }
Write-Host "  Status: $($ThermalInfo.Status)" -ForegroundColor $thermalColor

# Display predictive failure
Write-Host ""
Write-Host "Predictive Failure Assessment:" -ForegroundColor Green
$failColor = if ($PredictiveFailure.Probability -eq "High") { "Red" } elseif ($PredictiveFailure.Probability -eq "Medium") { "Yellow" } else { "Green" }
Write-Host "  Risk Score: $($PredictiveFailure.RiskScore)/100"
Write-Host "  Probability: $($PredictiveFailure.Probability)" -ForegroundColor $failColor
Write-Host "  $($PredictiveFailure.Recommendation)"

$raw = [PSCustomObject]@{
    CustomerName = $CustomerName
    TechnicianName = $TechnicianName
    Mode = $Mode
    SessionDir = $SessionDir
    SystemSummary = $SystemSummary
    RamInventory = $RamInventory
    ConfigurationWarnings = $ConfigWarnings
    RoundResults = $RoundResults
    RecentEvents = $Events | Select-Object -First 50
    ThermalInfo = $ThermalInfo
    DIMMSlotMap = $DIMMSlotMap
    PredictiveFailure = $PredictiveFailure
}

$raw | ConvertTo-Json -Depth 8 | Set-Content -Path $JsonFile -Encoding UTF8
New-HtmlReport -SystemSummary $SystemSummary -RamInventory $RamInventory -RoundResults $RoundResults -ConfigWarnings $ConfigWarnings -Events $Events -ThermalInfo $ThermalInfo -PredictiveFailure $PredictiveFailure -DIMMSlotMap $DIMMSlotMap

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "RAM Isolation Testing Completed" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "HTML Report: $HtmlFile"
Write-Host "CSV Results: $CsvFile"
Write-Host "Raw JSON: $JsonFile"
Write-Host "Log File: $LogFile"
Write-Host ""
Write-Host "Final Recommendation:" -ForegroundColor Yellow
Write-Host "- If one stick fails in a known-good slot, suspect the RAM stick."
Write-Host "- If a known-good stick fails only in one motherboard slot, suspect the slot/motherboard channel."
Write-Host "- For final confirmation, run MemTest86 bootable USB for 4 passes."
Write-Host ""

Write-Log "PC Plus 360 Advanced Physical RAM Isolation Test completed."

# -JsonOutput: Emit structured JSON to stdout for ReportCard integration
if ($JsonOutput) {
    $reportCardData = [PSCustomObject]@{
        ScriptName         = "PCPlus-RAMIsolation"
        Version            = "2.0"
        Timestamp          = (Get-Date -Format "o")
        ComputerName       = $env:COMPUTERNAME
        CustomerName       = $CustomerName
        TechnicianName     = $TechnicianName
        Mode               = $Mode
        TotalRAMGB         = $SystemSummary.TotalRAMGB
        ModulesDetected    = $RamInventory.Count
        TotalSlots         = $DIMMSlotMap.TotalSlots
        PopulatedSlots     = $DIMMSlotMap.PopulatedSlots
        EmptySlots         = $DIMMSlotMap.EmptySlots
        MaxCapacityGB      = $DIMMSlotMap.MaxCapacityGB
        CurrentCapacityGB  = $DIMMSlotMap.CurrentCapacityGB
        ThermalStatus      = $ThermalInfo.Status
        ThermalCelsius     = $ThermalInfo.TemperatureCelsius
        FailureProbability = $PredictiveFailure.Probability
        FailureRiskScore   = $PredictiveFailure.RiskScore
        RoundsRun          = $RoundResults.Count
        RoundsPassed       = @($RoundResults | Where-Object { $_.Result -eq "PASS" }).Count
        RoundsFailed       = @($RoundResults | Where-Object { $_.Result -eq "FAIL" }).Count
        RoundsWarning      = @($RoundResults | Where-Object { $_.Result -eq "WARNING" }).Count
        ConfigWarnings     = $ConfigWarnings
        UpgradeNotes       = $DIMMSlotMap.UpgradeNotes
        ReportPath         = $HtmlFile
        SessionDir         = $SessionDir
    }
    $reportCardData | ConvertTo-Json -Depth 4
}

Read-Host "  Press Enter to exit"

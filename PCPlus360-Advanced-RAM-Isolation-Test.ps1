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
                        $chunk = [byte[]]::new(4096)
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

# ------------------------------
# Trend Tracking & Baseline
# ------------------------------
$TrendDir = "C:\PCPlus360\Reports"
$TrendFile = Join-Path $TrendDir "RAM-Isolation-History.json"

function Get-TrendHistory {
    if (Test-Path $TrendFile) {
        try {
            $content = Get-Content -Path $TrendFile -Raw -ErrorAction Stop
            $history = $content | ConvertFrom-Json -ErrorAction Stop
            if ($history -is [array]) { return $history }
            return @($history)
        } catch {
            Write-Log "Could not parse trend history file. Starting fresh." "WARN"
            return @()
        }
    }
    return @()
}

function Save-TrendEntry {
    param($Entry)
    New-Item -ItemType Directory -Path $TrendDir -Force | Out-Null
    $history = @(Get-TrendHistory)
    $history += $Entry
    # Keep last 100 entries
    if ($history.Count -gt 100) { $history = $history[($history.Count - 100)..($history.Count - 1)] }
    $history | ConvertTo-Json -Depth 8 | Set-Content -Path $TrendFile -Encoding UTF8
}

function Get-BaselineComparison {
    param($CurrentEntry)
    $history = @(Get-TrendHistory)
    if ($history.Count -eq 0) {
        return [PSCustomObject]@{
            HasBaseline      = $false
            BaselineDate     = $null
            Note             = "This is the first run. It will become the baseline for future comparisons."
            Deltas           = @()
        }
    }

    $baseline = $history[0]
    $deltas = @()

    # Compare total pattern errors
    $basePatErr = if ($null -ne $baseline.TotalPatternErrors) { $baseline.TotalPatternErrors } else { 0 }
    $curPatErr  = if ($null -ne $CurrentEntry.TotalPatternErrors) { $CurrentEntry.TotalPatternErrors } else { 0 }
    $deltaPatErr = $curPatErr - $basePatErr
    $deltas += [PSCustomObject]@{
        Metric   = "Total Pattern Errors"
        Baseline = $basePatErr
        Current  = $curPatErr
        Delta    = $deltaPatErr
        Status   = if ($deltaPatErr -gt 0) { "Worse" } elseif ($deltaPatErr -lt 0) { "Better" } else { "Same" }
    }

    # Compare total random errors
    $baseRndErr = if ($null -ne $baseline.TotalRandomErrors) { $baseline.TotalRandomErrors } else { 0 }
    $curRndErr  = if ($null -ne $CurrentEntry.TotalRandomErrors) { $CurrentEntry.TotalRandomErrors } else { 0 }
    $deltaRndErr = $curRndErr - $baseRndErr
    $deltas += [PSCustomObject]@{
        Metric   = "Total Random Errors"
        Baseline = $baseRndErr
        Current  = $curRndErr
        Delta    = $deltaRndErr
        Status   = if ($deltaRndErr -gt 0) { "Worse" } elseif ($deltaRndErr -lt 0) { "Better" } else { "Same" }
    }

    # Compare pass rate
    $basePassRate = if ($null -ne $baseline.PassRate) { $baseline.PassRate } else { 100 }
    $curPassRate  = if ($null -ne $CurrentEntry.PassRate) { $CurrentEntry.PassRate } else { 100 }
    $deltaPass = $curPassRate - $basePassRate
    $deltas += [PSCustomObject]@{
        Metric   = "Pass Rate (%)"
        Baseline = $basePassRate
        Current  = $curPassRate
        Delta    = $deltaPass
        Status   = if ($deltaPass -lt 0) { "Worse" } elseif ($deltaPass -gt 0) { "Better" } else { "Same" }
    }

    [PSCustomObject]@{
        HasBaseline      = $true
        BaselineDate     = $baseline.Timestamp
        Note             = "Comparing against baseline from $($baseline.Timestamp)."
        Deltas           = $deltas
    }
}

function New-HtmlReport {
    param(
        $SystemSummary,
        $RamInventory,
        $RoundResults,
        $ConfigWarnings,
        $Events,
        $TrendComparison
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
  <div class="card" style="background:#fff3cd;border-left:6px solid #f59e0b;">
    <p style="margin:0;font-size:14px;"><b>ADVANCED VERSION</b> - This is the Advanced RAM Isolation Test with trend tracking and baseline comparison. A basic/quick version (<code>PCPlus-RAMIsolation.ps1</code>) is also available for rapid single-round checks.</p>
  </div>

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
    <h2>Trend Tracking & Baseline Comparison</h2>
    <p><b>$($TrendComparison.Note)</b></p>
    $(if ($TrendComparison.HasBaseline) {
        $trendRows = foreach ($d in $TrendComparison.Deltas) {
            $dClass = if ($d.Status -eq "Worse") { "fail" } elseif ($d.Status -eq "Better") { "pass" } else { "warn" }
            "<tr><td>$($d.Metric)</td><td>$($d.Baseline)</td><td>$($d.Current)</td><td class='$dClass'>$($d.Delta) ($($d.Status))</td></tr>"
        }
        "<table><tr><th>Metric</th><th>Baseline</th><th>Current</th><th>Delta</th></tr>$($trendRows -join "`n")</table>"
    } else {
        "<p>No previous runs to compare. This session establishes the baseline.</p>"
    })
    <p>Trend history stored at: <code>$TrendFile</code></p>
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
Write-Host "[ADVANCED VERSION] This is the full Advanced test with trend" -ForegroundColor Yellow
Write-Host "tracking and baseline comparison. For quick single-round" -ForegroundColor Yellow
Write-Host "checks, use PCPlus-RAMIsolation.ps1 instead." -ForegroundColor Yellow
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

# Build trend entry for this session
$totalPatternErrors = ($RoundResults | Measure-Object PatternErrors -Sum -ErrorAction SilentlyContinue).Sum
if ($null -eq $totalPatternErrors) { $totalPatternErrors = 0 }
$totalRandomErrors = ($RoundResults | Measure-Object RandomErrors -Sum -ErrorAction SilentlyContinue).Sum
if ($null -eq $totalRandomErrors) { $totalRandomErrors = 0 }
$passedCount = @($RoundResults | Where-Object { $_.Result -eq "PASS" }).Count
$passRate = if ($RoundResults.Count -gt 0) { [math]::Round(($passedCount / $RoundResults.Count) * 100, 1) } else { 100 }

$trendEntry = [PSCustomObject]@{
    Timestamp          = (Get-Date -Format "o")
    ComputerName       = $env:COMPUTERNAME
    Mode               = $Mode
    RoundsRun          = $RoundResults.Count
    RoundsPassed       = $passedCount
    RoundsFailed       = @($RoundResults | Where-Object { $_.Result -eq "FAIL" }).Count
    RoundsWarning      = @($RoundResults | Where-Object { $_.Result -eq "WARNING" }).Count
    PassRate           = $passRate
    TotalPatternErrors = $totalPatternErrors
    TotalRandomErrors  = $totalRandomErrors
    TotalRAMGB         = $SystemSummary.TotalRAMGB
    ModulesDetected    = $RamInventory.Count
}

$TrendComparison = Get-BaselineComparison -CurrentEntry $trendEntry
Save-TrendEntry -Entry $trendEntry
Write-Log "Trend entry saved to $TrendFile."

# Display trend comparison
Write-Host ""
Write-Host "Trend Tracking:" -ForegroundColor Green
Write-Host "  $($TrendComparison.Note)"
if ($TrendComparison.HasBaseline) {
    foreach ($d in $TrendComparison.Deltas) {
        $color = if ($d.Status -eq "Worse") { "Red" } elseif ($d.Status -eq "Better") { "Green" } else { "Gray" }
        Write-Host "  $($d.Metric): Baseline=$($d.Baseline), Current=$($d.Current), Delta=$($d.Delta) ($($d.Status))" -ForegroundColor $color
    }
}

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
    TrendEntry = $trendEntry
    TrendComparison = $TrendComparison
}

$raw | ConvertTo-Json -Depth 8 | Set-Content -Path $JsonFile -Encoding UTF8
New-HtmlReport -SystemSummary $SystemSummary -RamInventory $RamInventory -RoundResults $RoundResults -ConfigWarnings $ConfigWarnings -Events $Events -TrendComparison $TrendComparison

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "RAM Isolation Testing Completed" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "HTML Report: $HtmlFile"
Write-Host "CSV Results: $CsvFile"
Write-Host "Raw JSON: $JsonFile"
Write-Host "Log File: $LogFile"
Write-Host "Trend File: $TrendFile"
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
        ScriptName         = "PCPlus360-Advanced-RAM-Isolation-Test"
        Version            = "2.0"
        Timestamp          = (Get-Date -Format "o")
        ComputerName       = $env:COMPUTERNAME
        CustomerName       = $CustomerName
        TechnicianName     = $TechnicianName
        Mode               = $Mode
        TotalRAMGB         = $SystemSummary.TotalRAMGB
        ModulesDetected    = $RamInventory.Count
        RoundsRun          = $RoundResults.Count
        RoundsPassed       = $passedCount
        RoundsFailed       = @($RoundResults | Where-Object { $_.Result -eq "FAIL" }).Count
        RoundsWarning      = @($RoundResults | Where-Object { $_.Result -eq "WARNING" }).Count
        PassRate           = $passRate
        TotalPatternErrors = $totalPatternErrors
        TotalRandomErrors  = $totalRandomErrors
        TrendBaseline      = $TrendComparison.HasBaseline
        TrendBaselineDate  = $TrendComparison.BaselineDate
        ConfigWarnings     = $ConfigWarnings
        ReportPath         = $HtmlFile
        SessionDir         = $SessionDir
    }
    $reportCardData | ConvertTo-Json -Depth 4
}

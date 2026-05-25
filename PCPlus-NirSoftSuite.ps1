param(
    [string]$CustomerName = "Customer",
    [string]$TechnicianName = "PC Plus Technician",
    [string]$NirSoftDir = "",
    [switch]$IncludeBrowserHistory,
    [switch]$IncludeLastActivity,
    [switch]$OpenReport,
    [switch]$NoGUI
)

<#
PC Plus 360 - NirSoft Portable Tools Suite
Company: PC Plus Computing
Website: pcpluscomputing.com
Phone: 604-760-1662

Purpose:
Run NirSoft portable diagnostic tools, export results, analyze findings,
and generate a branded HTML/TXT/JSON/CSV report.

IMPORTANT:
This script DOES NOT download NirSoft tools automatically.
Place NirSoft EXE files in EITHER location:
  1. C:\PCPlus360\Tools\NirSoft (preferred for fixed installations)
  2. tools\nirsoft\ next to this script (for USB portable use)

Run as Administrator:
PowerShell.exe -STA -ExecutionPolicy Bypass -File .\PCPlus-NirSoftSuite.ps1

Console-only mode:
PowerShell.exe -STA -ExecutionPolicy Bypass -File .\PCPlus-NirSoftSuite.ps1 -NoGUI

Optional:
PowerShell.exe -STA -ExecutionPolicy Bypass -File .\PCPlus-NirSoftSuite.ps1 -CustomerName "John" -TechnicianName "Paul"
#>

$ErrorActionPreference = "Continue"

# ============================================================
# Self-Elevation (with -STA flag)
# ============================================================

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-IsAdmin)) {
    $scriptPath = $MyInvocation.MyCommand.Definition
    $argList = "-STA -ExecutionPolicy Bypass -File `"$scriptPath`""
    if ($CustomerName -ne "Customer") { $argList += " -CustomerName `"$CustomerName`"" }
    if ($TechnicianName -ne "PC Plus Technician") { $argList += " -TechnicianName `"$TechnicianName`"" }
    if ($NirSoftDir) { $argList += " -NirSoftDir `"$NirSoftDir`"" }
    if ($IncludeBrowserHistory) { $argList += " -IncludeBrowserHistory" }
    if ($IncludeLastActivity) { $argList += " -IncludeLastActivity" }
    if ($OpenReport) { $argList += " -OpenReport" }
    if ($NoGUI) { $argList += " -NoGUI" }
    try {
        Start-Process PowerShell.exe -ArgumentList $argList -Verb RunAs
    } catch {
        Write-Host "Failed to elevate. Please run as Administrator." -ForegroundColor Red
    }
    exit
}

# ============================================================
# Paths - check both fixed and USB-relative locations
# ============================================================

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
if ([string]::IsNullOrEmpty($ScriptDir)) { $ScriptDir = Get-Location }

if ([string]::IsNullOrEmpty($NirSoftDir)) {
    $fixedDir = "C:\PCPlus360\Tools\NirSoft"
    $usbNirDir = Join-Path $ScriptDir "tools\nirsoft"
    $usbToolsDir = Join-Path $ScriptDir "Tools"
    if (Test-Path $fixedDir) { $NirSoftDir = $fixedDir }
    elseif (Test-Path $usbNirDir) { $NirSoftDir = $usbNirDir }
    elseif (Test-Path $usbToolsDir) { $NirSoftDir = $usbToolsDir }
    else { $NirSoftDir = $fixedDir }
}

$BaseDir = "C:\PCPlus360\NirSoftReports"
$TimeStamp = Get-Date -Format "yyyyMMdd-HHmmss"
$ComputerSafe = $env:COMPUTERNAME -replace '[^\w\-]', '_'
$ReportDir = Join-Path $BaseDir "$ComputerSafe-$TimeStamp"
$ExportDir = Join-Path $ReportDir "Exports"

New-Item -ItemType Directory -Path $ReportDir -Force | Out-Null
New-Item -ItemType Directory -Path $ExportDir -Force | Out-Null

$LogFile  = Join-Path $ReportDir "PCPlus360-NirSoft-Log.txt"
$JsonFile = Join-Path $ReportDir "PCPlus360-NirSoft-RawData.json"
$HtmlFile = Join-Path $ReportDir "PCPlus360-NirSoft-Report.html"
$TxtFile  = Join-Path $ReportDir "PCPlus360-NirSoft-Summary.txt"
$CsvFile  = Join-Path $ReportDir "PCPlus360-NirSoft-Summary.csv"

# ============================================================
# Helpers
# ============================================================

function Write-PCLog {
    param([string]$Message, [string]$Level = "INFO")
    $line = "[{0}] [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Level, $Message
    if (-not $script:SuppressConsole) { Write-Host $line }
    Add-Content -Path $LogFile -Value $line -ErrorAction SilentlyContinue
}

function Get-ToolPath {
    param([string]$ExeName)
    $path = Join-Path $NirSoftDir $ExeName
    if (Test-Path $path) { return $path }
    $found = Get-ChildItem -Path $NirSoftDir -Filter $ExeName -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($found) { return $found.FullName }
    return $null
}

function Invoke-NirSoftExport {
    param(
        [string]$ToolName,
        [string]$ExeName,
        [string]$ExportBaseName,
        [string]$ExportSwitch = "/scomma",
        [string]$ExtraArgs = "",
        [int]$TimeoutSec = 30
    )

    $exe = Get-ToolPath $ExeName
    $csv = Join-Path $ExportDir "$ExportBaseName.csv"
    $txt = Join-Path $ExportDir "$ExportBaseName.txt"

    if (-not $exe) {
        Write-PCLog "$ToolName not found: $ExeName" "WARN"
        return [PSCustomObject]@{
            ToolName = $ToolName; ExeName = $ExeName; Found = $false; Ran = $false
            ExitCode = $null; CsvPath = $null; TxtPath = $null; RowCount = 0
            Notes = "Tool not found in $NirSoftDir"
        }
    }

    try {
        Write-PCLog "Running $ToolName export."

        $procArgs = "$ExtraArgs $ExportSwitch `"$csv`""
        $p = Start-Process -FilePath $exe -ArgumentList $procArgs -Wait -PassThru -WindowStyle Hidden

        $txtArgs = "$ExtraArgs /stext `"$txt`""
        Start-Process -FilePath $exe -ArgumentList $txtArgs -Wait -WindowStyle Hidden | Out-Null

        Start-Sleep -Milliseconds 300

        $rows = 0
        if (Test-Path $csv) {
            try {
                $import = Import-Csv $csv -ErrorAction SilentlyContinue
                $rows = @($import).Count
            } catch { $rows = 0 }
        }

        [PSCustomObject]@{
            ToolName = $ToolName; ExeName = $ExeName; Found = $true; Ran = $true
            ExitCode = $p.ExitCode; CsvPath = $csv; TxtPath = if (Test-Path $txt) { $txt } else { $null }
            RowCount = $rows; Notes = "Export completed"
        }
    } catch {
        Write-PCLog "$ToolName failed: $($_.Exception.Message)" "ERROR"
        [PSCustomObject]@{
            ToolName = $ToolName; ExeName = $ExeName; Found = $true; Ran = $false
            ExitCode = $null; CsvPath = $null; TxtPath = $null; RowCount = 0
            Notes = $_.Exception.Message
        }
    }
}

function Import-CsvSafe {
    param([string]$Path)
    if (-not $Path -or -not (Test-Path $Path)) { return @() }
    try { return @(Import-Csv $Path -ErrorAction SilentlyContinue) } catch { return @() }
}

function Get-SystemInfo {
    $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
    $bios = Get-CimInstance Win32_BIOS -ErrorAction SilentlyContinue
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    $cpu = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1

    [PSCustomObject]@{
        CustomerName = $CustomerName
        TechnicianName = $TechnicianName
        ComputerName = $env:COMPUTERNAME
        Manufacturer = $cs.Manufacturer
        Model = $cs.Model
        SerialNumber = $bios.SerialNumber
        OS = $os.Caption
        Build = $os.BuildNumber
        CPU = $cpu.Name
        TotalRAMGB = if ($cs.TotalPhysicalMemory) { [math]::Round($cs.TotalPhysicalMemory / 1GB, 2) } else { $null }
        ReportDate = Get-Date
        IsAdmin = Test-IsAdmin
    }
}

# ============================================================
# Analysis Functions
# ============================================================

function Analyze-BlueScreenView {
    param([string]$CsvPath)
    $rows = Import-CsvSafe $CsvPath
    $recent = @($rows | Select-Object -First 10)
    $drivers = @()
    foreach ($r in $rows) {
        $possible = @($r.'Caused By Driver', $r.'Caused By Address', $r.'File Description', $r.'Product Name') | Where-Object { $_ }
        foreach ($p in $possible) { $drivers += $p }
    }
    [PSCustomObject]@{
        CrashCount = $rows.Count
        RecentCrashes = $recent
        AllRows = @($rows)
        CommonDrivers = @($drivers | Group-Object | Sort-Object Count -Descending | Select-Object -First 5 Name, Count)
        Summary = if ($rows.Count -gt 0) { "$($rows.Count) blue screen dump(s) found." } else { "No BSOD dump records exported." }
    }
}

function Analyze-CurrPorts {
    param([string]$CsvPath)
    $rows = Import-CsvSafe $CsvPath
    $listening = @($rows | Where-Object { $_.State -match "Listen" -or $_.'Local Port' })
    $external = @($rows | Where-Object { $_.'Remote Address' -and $_.'Remote Address' -notmatch "^(127\.|0\.0\.0\.0|::|localhost)" })
    $suspectPorts = @($rows | Where-Object {
        $p = $_.'Local Port'
        $p -and ($p -match '^\d+$') -and ([int]$p -in @(4444,5555,6666,7777,8888,9999,1337,31337))
    })
    [PSCustomObject]@{
        TotalConnections = $rows.Count
        ListeningOrLocalPortCount = $listening.Count
        ExternalConnectionCount = $external.Count
        SuspiciousPortCount = $suspectPorts.Count
        AllRows = @($rows)
        TopProcesses = @($rows | Where-Object { $_.'Process Name' } | Group-Object 'Process Name' | Sort-Object Count -Descending | Select-Object -First 10 Name, Count)
        Summary = "$($rows.Count) network entries exported; $($external.Count) external connection(s) found."
    }
}

function Analyze-WhatInStartup {
    param([string]$CsvPath)
    $rows = Import-CsvSafe $CsvPath
    $enabled = @($rows | Where-Object { $_.Disabled -notmatch "Yes" })
    $disabled = @($rows | Where-Object { $_.Disabled -match "Yes" })
    [PSCustomObject]@{
        StartupTotal = $rows.Count
        StartupEnabled = $enabled.Count
        StartupDisabled = $disabled.Count
        AllRows = @($rows)
        StartupItems = @($rows | Select-Object -First 50)
        Summary = "$($enabled.Count) enabled startup item(s), $($disabled.Count) disabled startup item(s)."
    }
}

function Analyze-USBDeview {
    param([string]$CsvPath)
    $rows = Import-CsvSafe $CsvPath
    $connected = @($rows | Where-Object { $_.Connected -match "Yes" })
    $disconnected = @($rows | Where-Object { $_.Connected -notmatch "Yes" })
    [PSCustomObject]@{
        TotalUsbHistory = $rows.Count
        CurrentlyConnected = $connected.Count
        HistoricalDisconnected = $disconnected.Count
        AllRows = @($rows)
        RecentDevices = @($rows | Select-Object -First 30)
        Summary = "$($rows.Count) USB device history record(s); $($connected.Count) currently connected."
    }
}

function Analyze-BatteryInfoView {
    param([string]$CsvPath)
    $rows = Import-CsvSafe $CsvPath
    $health = $null
    $wearLevel = $null
    foreach ($r in $rows) {
        foreach ($prop in $r.PSObject.Properties.Name) {
            if ($prop -match "Battery Health|Health") { $health = $r.$prop }
            if ($prop -match "Wear Level|Wear") {
                $wearLevel = $r.$prop
            }
        }
    }
    [PSCustomObject]@{
        BatteryRows = $rows.Count
        BatteryHealth = $health
        WearLevel = $wearLevel
        AllRows = @($rows)
        BatteryData = @($rows | Select-Object -First 5)
        Summary = if ($rows.Count -gt 0) { "Battery data exported. Wear: $wearLevel" } else { "No battery data exported or desktop detected." }
    }
}

function Analyze-DriverView {
    param([string]$CsvPath)
    $rows = Import-CsvSafe $CsvPath
    $nonMicrosoft = @($rows | Where-Object { $_.Company -and $_.Company -notmatch "Microsoft" })
    $loaded = @($rows | Where-Object { $_.Loaded -match "Yes" })
    [PSCustomObject]@{
        TotalDrivers = $rows.Count
        LoadedDrivers = $loaded.Count
        NonMicrosoftDrivers = $nonMicrosoft.Count
        AllRows = @($rows)
        TopNonMicrosoft = @($nonMicrosoft | Select-Object -First 30)
        Summary = "$($rows.Count) drivers exported; $($nonMicrosoft.Count) non-Microsoft driver(s)."
    }
}

function Analyze-InstalledDriversList {
    param([string]$CsvPath)
    $rows = Import-CsvSafe $CsvPath
    $problem = @($rows | Where-Object { $_.Status -and $_.Status -notmatch "OK|Running" })
    $unsigned = @($rows | Where-Object { $_.'Signed' -eq 'No' -or $_.'Digital Signature' -eq 'Not Signed' })
    [PSCustomObject]@{
        TotalInstalledDrivers = $rows.Count
        ProblemDriverCount = $problem.Count
        UnsignedDriverCount = $unsigned.Count
        AllRows = @($rows)
        ProblemDrivers = @($problem | Select-Object -First 25)
        UnsignedDrivers = @($unsigned | Select-Object -First 25)
        Summary = "$($rows.Count) installed driver record(s); $($problem.Count) problem, $($unsigned.Count) unsigned."
    }
}

function Analyze-WinCrashReport {
    param([string]$CsvPath)
    $rows = Import-CsvSafe $CsvPath
    [PSCustomObject]@{
        AppCrashCount = $rows.Count
        AllRows = @($rows)
        RecentAppCrashes = @($rows | Select-Object -First 30)
        Summary = "$($rows.Count) application crash report(s) exported."
    }
}

function Analyze-WifiInfoView {
    param([string]$CsvPath)
    $rows = Import-CsvSafe $CsvPath
    [PSCustomObject]@{
        WifiNetworksSeen = $rows.Count
        AllRows = @($rows)
        Networks = @($rows | Select-Object -First 30)
        Summary = "$($rows.Count) Wi-Fi network record(s) exported."
    }
}

function Analyze-WirelessNetView {
    param([string]$CsvPath)
    $rows = Import-CsvSafe $CsvPath
    [PSCustomObject]@{
        NetworkCount = $rows.Count
        AllRows = @($rows)
        Networks = @($rows | Select-Object -First 30)
        Summary = "$($rows.Count) nearby wireless network(s) detected."
    }
}

function Analyze-FullEventLogView {
    param([string]$CsvPath)
    $rows = Import-CsvSafe $CsvPath
    $errors = @($rows | Where-Object { $_.Level -match "Error|Critical" -or $_.'Event Type' -match "Error|Critical" })
    [PSCustomObject]@{
        EventRows = $rows.Count
        ErrorOrCriticalCount = $errors.Count
        AllRows = @($rows)
        RecentErrors = @($errors | Select-Object -First 50)
        Summary = "$($rows.Count) event log records; $($errors.Count) error/critical."
    }
}

function Analyze-OpenedFilesView {
    param([string]$CsvPath)
    $rows = Import-CsvSafe $CsvPath
    [PSCustomObject]@{
        OpenedFileCount = $rows.Count
        AllRows = @($rows)
        Samples = @($rows | Select-Object -First 30)
        Summary = "$($rows.Count) opened/locked file record(s)."
    }
}

function Analyze-ProduKey {
    param([string]$CsvPath)
    $rows = Import-CsvSafe $CsvPath
    [PSCustomObject]@{
        KeyCount = $rows.Count
        AllRows = @($rows)
        Summary = "$($rows.Count) product key(s) recovered."
    }
}

function Analyze-DNSDataView {
    param([string]$CsvPath)
    $rows = Import-CsvSafe $CsvPath
    [PSCustomObject]@{
        RecordCount = $rows.Count
        AllRows = @($rows)
        Summary = "$($rows.Count) DNS cache record(s)."
    }
}

function Analyze-ProcessActivityView {
    param([string]$CsvPath)
    $rows = Import-CsvSafe $CsvPath
    [PSCustomObject]@{
        ProcessCount = $rows.Count
        AllRows = @($rows)
        Summary = "$($rows.Count) process activity record(s)."
    }
}

function Analyze-FolderChangesView {
    param([string]$CsvPath)
    $rows = Import-CsvSafe $CsvPath
    [PSCustomObject]@{
        ChangeCount = $rows.Count
        AllRows = @($rows)
        Summary = "$($rows.Count) file system change(s) detected."
    }
}

function Analyze-LastActivityView {
    param([string]$CsvPath)
    $rows = Import-CsvSafe $CsvPath
    [PSCustomObject]@{
        ActivityCount = $rows.Count
        AllRows = @($rows)
        Summary = "$($rows.Count) recent activity record(s)."
    }
}

function Analyze-BrowserDownloadsView {
    param([string]$CsvPath)
    $rows = Import-CsvSafe $CsvPath
    [PSCustomObject]@{
        DownloadCount = $rows.Count
        AllRows = @($rows)
        Summary = "$($rows.Count) browser download record(s)."
    }
}

# Generic analyzer for new tools without dedicated functions
function Analyze-Generic {
    param([string]$CsvPath, [string]$ToolName)
    $rows = Import-CsvSafe $CsvPath
    [PSCustomObject]@{
        RowCount = $rows.Count
        AllRows = @($rows)
        Summary = "$($rows.Count) $ToolName record(s) exported."
    }
}

# ============================================================
# Scoring
# ============================================================

function Get-PCPlusNirSoftScore {
    param($Analysis)

    $score = 100
    $issues = @()

    if ($Analysis.BlueScreenView.CrashCount -gt 0) {
        $score -= [math]::Min(25, $Analysis.BlueScreenView.CrashCount * 8)
        $issues += "$($Analysis.BlueScreenView.CrashCount) blue screen dump(s) found."
        if ($Analysis.BlueScreenView.CommonDrivers.Count -gt 0) {
            $topDriver = $Analysis.BlueScreenView.CommonDrivers[0].Name
            $issues += "Most common BSOD driver: $topDriver"
        }
    }

    if ($Analysis.WinCrashReport.AppCrashCount -gt 5) {
        $score -= 10
        $issues += "$($Analysis.WinCrashReport.AppCrashCount) application crash report(s) found."
    }

    if ($Analysis.WhatInStartup.StartupEnabled -gt 20) {
        $score -= 8
        $issues += "High number of startup items: $($Analysis.WhatInStartup.StartupEnabled)."
    } elseif ($Analysis.WhatInStartup.StartupEnabled -gt 15) {
        $score -= 4
        $issues += "Elevated startup items: $($Analysis.WhatInStartup.StartupEnabled)."
    }

    if ($Analysis.InstalledDriversList.ProblemDriverCount -gt 0) {
        $score -= [math]::Min(15, $Analysis.InstalledDriversList.ProblemDriverCount * 5)
        $issues += "$($Analysis.InstalledDriversList.ProblemDriverCount) possible problem driver(s)."
    }

    if ($Analysis.InstalledDriversList.UnsignedDriverCount -gt 0) {
        $score -= [math]::Min(10, $Analysis.InstalledDriversList.UnsignedDriverCount * 2)
        $issues += "$($Analysis.InstalledDriversList.UnsignedDriverCount) unsigned driver(s) found."
    }

    if ($Analysis.FullEventLogView.ErrorOrCriticalCount -gt 50) {
        $score -= 10
        $issues += "High event log error count: $($Analysis.FullEventLogView.ErrorOrCriticalCount)."
    } elseif ($Analysis.FullEventLogView.ErrorOrCriticalCount -gt 20) {
        $score -= 5
        $issues += "Elevated event log errors: $($Analysis.FullEventLogView.ErrorOrCriticalCount)."
    }

    if ($Analysis.CurrPorts.ExternalConnectionCount -gt 50) {
        $score -= 5
        $issues += "High external connections: $($Analysis.CurrPorts.ExternalConnectionCount)."
    }

    if ($Analysis.CurrPorts.SuspiciousPortCount -gt 0) {
        $score -= 10
        $issues += "$($Analysis.CurrPorts.SuspiciousPortCount) connection(s) on suspicious ports."
    }

    if ($Analysis.BatteryInfoView.WearLevel) {
        if ($Analysis.BatteryInfoView.WearLevel -match '(\d+)') {
            $wear = [int]$matches[1]
            if ($wear -gt 40) {
                $score -= 10
                $issues += "Battery wear level $wear% - replacement recommended."
            } elseif ($wear -gt 20) {
                $score -= 3
                $issues += "Battery wear level $wear% - monitor for decline."
            }
        }
    }

    if ($score -lt 0) { $score = 0 }

    $grade = if ($score -ge 90) { "A - Excellent" }
        elseif ($score -ge 80) { "B - Good" }
        elseif ($score -ge 70) { "C - Fair" }
        elseif ($score -ge 60) { "D - Needs Attention" }
        else { "F - Critical" }

    [PSCustomObject]@{
        Score = $score
        Grade = $grade
        Issues = @($issues | Select-Object -Unique)
    }
}

# ============================================================
# HTML Report Builder
# ============================================================

function Build-DataTableHtml {
    param($DataArray, [int]$MaxRows = 50, [string[]]$Columns = @())
    if (-not $DataArray -or @($DataArray).Count -eq 0) { return "<p class='empty'>No data collected or tool not available.</p>" }

    $rows = @($DataArray) | Select-Object -First $MaxRows
    if ($Columns.Count -eq 0) {
        $Columns = @($rows[0].PSObject.Properties.Name | Select-Object -First 10)
    }

    $sb = [System.Text.StringBuilder]::new()
    $null = $sb.Append("<div class='tbl-wrap'><table><tr>")
    foreach ($c in $Columns) { $null = $sb.Append("<th>$c</th>") }
    $null = $sb.Append("</tr>")

    foreach ($row in $rows) {
        $null = $sb.Append("<tr>")
        foreach ($c in $Columns) {
            $val = "$($row.$c)"
            if ($val.Length -gt 120) { $val = $val.Substring(0,117) + "..." }
            $val = $val.Replace("&","&amp;").Replace("<","&lt;").Replace(">","&gt;")
            $null = $sb.Append("<td>$val</td>")
        }
        $null = $sb.Append("</tr>")
    }
    $null = $sb.Append("</table></div>")
    if (@($DataArray).Count -gt $MaxRows) {
        $null = $sb.Append("<p class='note'>Showing $MaxRows of $(@($DataArray).Count) records. See CSV export for full data.</p>")
    }
    return $sb.ToString()
}

function Convert-ToHtmlList {
    param($Items)
    if (-not $Items -or $Items.Count -eq 0) { return "<li>No major findings.</li>" }
    return (($Items | ForEach-Object { "<li>$_</li>" }) -join "`n")
}

function New-PCPlusHtmlReport {
    param($Data)

    $scoreColor = if ($Data.Score.Score -ge 80) { "#16a34a" } elseif ($Data.Score.Score -ge 60) { "#f59e0b" } else { "#dc2626" }
    $issueHtml = Convert-ToHtmlList $Data.Score.Issues

    $toolRows = foreach ($t in $Data.ToolRuns) {
        $status = if ($t.Ran) { "RAN" } elseif ($t.Found) { "ERROR" } else { "MISSING" }
        $class = if ($t.Ran) { "pass" } elseif ($t.Found) { "warn" } else { "missing" }
        "<tr><td>$($t.ToolName)</td><td>$($t.ExeName)</td><td class='$class'>$status</td><td>$($t.RowCount)</td><td>$($t.Notes)</td></tr>"
    }

    # Build detail sections for each tool that has data
    $detailSections = ""

    # BlueScreenView
    if ($Data.Analysis.BlueScreenView.CrashCount -gt 0) {
        $bsodBadge = if ($Data.Analysis.BlueScreenView.CrashCount -lt 3) { "<span class='badge warn'>$($Data.Analysis.BlueScreenView.CrashCount) Crash(es)</span>" } else { "<span class='badge fail'>$($Data.Analysis.BlueScreenView.CrashCount) Crashes</span>" }
        $bsodTable = Build-DataTableHtml $Data.Analysis.BlueScreenView.AllRows -Columns @("Dump File","Bug Check String","Bug Check Code","Caused By Driver","Crash Time")
        $commonHtml = ""
        if ($Data.Analysis.BlueScreenView.CommonDrivers.Count -gt 0) {
            $commonHtml = "<h3>Most Common Crash Drivers</h3><table><tr><th>Driver</th><th>Count</th></tr>"
            foreach ($d in $Data.Analysis.BlueScreenView.CommonDrivers) {
                $commonHtml += "<tr><td>$($d.Name)</td><td>$($d.Count)</td></tr>"
            }
            $commonHtml += "</table>"
        }
        $detailSections += "<div class='card'><h2>Blue Screen (BSOD) Analysis $bsodBadge</h2>$bsodTable $commonHtml</div>`n"
    } else {
        $detailSections += "<div class='card'><h2>Blue Screen (BSOD) Analysis <span class='badge pass'>No Crashes</span></h2><p>No BSOD dump files found. System has not experienced blue screen crashes.</p></div>`n"
    }

    # CurrPorts
    if ($Data.Analysis.CurrPorts.TotalConnections -gt 0) {
        $portsBadge = if ($Data.Analysis.CurrPorts.SuspiciousPortCount -gt 0) { "<span class='badge fail'>$($Data.Analysis.CurrPorts.SuspiciousPortCount) Suspicious</span>" } else { "<span class='badge pass'>Clean</span>" }
        $portsTable = Build-DataTableHtml $Data.Analysis.CurrPorts.AllRows -MaxRows 60 -Columns @("Process Name","Process ID","Protocol","Local Port","Local Address","Remote Address","Remote Port","State")
        $topProc = ""
        if ($Data.Analysis.CurrPorts.TopProcesses.Count -gt 0) {
            $topProc = "<h3>Top Processes by Connection Count</h3><table><tr><th>Process</th><th>Connections</th></tr>"
            foreach ($tp in $Data.Analysis.CurrPorts.TopProcesses) {
                $topProc += "<tr><td>$($tp.Name)</td><td>$($tp.Count)</td></tr>"
            }
            $topProc += "</table>"
        }
        $detailSections += "<div class='card'><h2>Active Network Connections $portsBadge</h2><p>$($Data.Analysis.CurrPorts.Summary)</p>$portsTable $topProc</div>`n"
    }

    # WhatInStartup
    if ($Data.Analysis.WhatInStartup.StartupTotal -gt 0) {
        $startBadge = if ($Data.Analysis.WhatInStartup.StartupEnabled -gt 20) { "<span class='badge warn'>$($Data.Analysis.WhatInStartup.StartupEnabled) Active</span>" } elseif ($Data.Analysis.WhatInStartup.StartupEnabled -gt 15) { "<span class='badge warn'>$($Data.Analysis.WhatInStartup.StartupEnabled) Active</span>" } else { "<span class='badge pass'>$($Data.Analysis.WhatInStartup.StartupEnabled) Active</span>" }
        $startTable = Build-DataTableHtml $Data.Analysis.WhatInStartup.AllRows -MaxRows 60 -Columns @("Startup Name","Command","Location","Disabled","Company","Product Name")
        $detailSections += "<div class='card'><h2>Startup Items $startBadge</h2><p>$($Data.Analysis.WhatInStartup.Summary)</p>$startTable</div>`n"
    }

    # USBDeview
    if ($Data.Analysis.USBDeview.TotalUsbHistory -gt 0) {
        $usbTable = Build-DataTableHtml $Data.Analysis.USBDeview.AllRows -MaxRows 50 -Columns @("Device Name","Description","Device Type","Connected","Safe To Unplug","Serial Number","Last Plug/Unplug Date","Vendor ID","Product ID")
        $detailSections += "<div class='card'><h2>USB Device History ($($Data.Analysis.USBDeview.CurrentlyConnected) connected, $($Data.Analysis.USBDeview.TotalUsbHistory) total)</h2>$usbTable</div>`n"
    }

    # BatteryInfoView
    if ($Data.Analysis.BatteryInfoView.BatteryRows -gt 0) {
        $battTable = Build-DataTableHtml $Data.Analysis.BatteryInfoView.AllRows -Columns @("Battery Name","Manufacture Name","Serial Number","Designed Capacity","Full Charged Capacity","Current Capacity","Voltage","Charge/Discharge Rate","Wear Level","Power State","Chemistry")
        $detailSections += "<div class='card'><h2>Battery Health</h2><p>$($Data.Analysis.BatteryInfoView.Summary)</p>$battTable</div>`n"
    }

    # InstalledDriversList
    if ($Data.Analysis.InstalledDriversList.TotalInstalledDrivers -gt 0) {
        $drvBadge = if ($Data.Analysis.InstalledDriversList.ProblemDriverCount -gt 0 -or $Data.Analysis.InstalledDriversList.UnsignedDriverCount -gt 0) { "<span class='badge warn'>$($Data.Analysis.InstalledDriversList.ProblemDriverCount) Problem, $($Data.Analysis.InstalledDriversList.UnsignedDriverCount) Unsigned</span>" } else { "<span class='badge pass'>All OK</span>" }
        $drvTable = Build-DataTableHtml $Data.Analysis.InstalledDriversList.AllRows -MaxRows 80 -Columns @("Driver Name","Display Name","Description","Driver Type","Start Type","Driver Filename","Company","File Version","Signed")
        $detailSections += "<div class='card'><h2>Installed Drivers Audit $drvBadge</h2><p>$($Data.Analysis.InstalledDriversList.Summary)</p>$drvTable</div>`n"
    }

    # DriverView
    if ($Data.Analysis.DriverView.TotalDrivers -gt 0) {
        $dvTable = Build-DataTableHtml $Data.Analysis.DriverView.AllRows -MaxRows 80 -Columns @("Driver Name","Address","Size","Company","Product Name","File Version","Creation Time")
        $detailSections += "<div class='card'><h2>Loaded Kernel Drivers ($($Data.Analysis.DriverView.NonMicrosoftDrivers) non-Microsoft)</h2><p>$($Data.Analysis.DriverView.Summary)</p>$dvTable</div>`n"
    }

    # WinCrashReport
    if ($Data.Analysis.WinCrashReport.AppCrashCount -gt 0) {
        $crashBadge = if ($Data.Analysis.WinCrashReport.AppCrashCount -gt 5) { "<span class='badge warn'>$($Data.Analysis.WinCrashReport.AppCrashCount) Crashes</span>" } else { "<span class='badge pass'>$($Data.Analysis.WinCrashReport.AppCrashCount)</span>" }
        $crashTable = Build-DataTableHtml $Data.Analysis.WinCrashReport.AllRows -MaxRows 30 -Columns @("Application Name","Version","Module Name","Exception Code","Exception Description","Time Stamp")
        $detailSections += "<div class='card'><h2>Application Crash Reports $crashBadge</h2>$crashTable</div>`n"
    }

    # WifiInfoView
    if ($Data.Analysis.WifiInfoView.WifiNetworksSeen -gt 0) {
        $wifiTable = Build-DataTableHtml $Data.Analysis.WifiInfoView.AllRows -MaxRows 30 -Columns @("SSID","MAC Address","PHY Type","RSSI","Signal Quality","Frequency","Channel","Security","Authentication","Company")
        $detailSections += "<div class='card'><h2>Wi-Fi Network Analysis</h2><p>$($Data.Analysis.WifiInfoView.Summary)</p>$wifiTable</div>`n"
    }

    # WirelessNetView
    if ($Data.Analysis.WirelessNetView -and $Data.Analysis.WirelessNetView.NetworkCount -gt 0) {
        $wnetTable = Build-DataTableHtml $Data.Analysis.WirelessNetView.AllRows -MaxRows 30 -Columns @("SSID","Last Signal Quality","Security","Cipher","MAC Address","RSSI","Channel Frequency","First Detected On","Last Detected On")
        $detailSections += "<div class='card'><h2>Nearby Wireless Networks</h2><p>$($Data.Analysis.WirelessNetView.Summary)</p>$wnetTable</div>`n"
    }

    # FullEventLogView
    if ($Data.Analysis.FullEventLogView.EventRows -gt 0) {
        $evtBadge = if ($Data.Analysis.FullEventLogView.ErrorOrCriticalCount -gt 50) { "<span class='badge fail'>$($Data.Analysis.FullEventLogView.ErrorOrCriticalCount) Errors</span>" } elseif ($Data.Analysis.FullEventLogView.ErrorOrCriticalCount -gt 20) { "<span class='badge warn'>$($Data.Analysis.FullEventLogView.ErrorOrCriticalCount) Errors</span>" } else { "<span class='badge pass'>$($Data.Analysis.FullEventLogView.ErrorOrCriticalCount) Errors</span>" }
        $evtTable = Build-DataTableHtml $Data.Analysis.FullEventLogView.RecentErrors -MaxRows 50 -Columns @("Event ID","Time Created","Source","Level","Event Type","Description","Log Name")
        $detailSections += "<div class='card'><h2>Event Log Errors $evtBadge</h2><p>$($Data.Analysis.FullEventLogView.Summary)</p>$evtTable</div>`n"
    }

    # OpenedFilesView
    if ($Data.Analysis.OpenedFilesView.OpenedFileCount -gt 0) {
        $openTable = Build-DataTableHtml $Data.Analysis.OpenedFilesView.AllRows -MaxRows 30 -Columns @("Filename","Process Name","Process ID","Handle","Read Access","Write Access","File Size")
        $detailSections += "<div class='card'><h2>Opened/Locked Files</h2><p>$($Data.Analysis.OpenedFilesView.Summary)</p>$openTable</div>`n"
    }

    # ProduKey
    if ($Data.Analysis.ProduKey -and $Data.Analysis.ProduKey.KeyCount -gt 0) {
        $keyTable = Build-DataTableHtml $Data.Analysis.ProduKey.AllRows -Columns @("Product Name","Product ID","Product Key","Install Folder")
        $detailSections += "<div class='card'><h2>License Keys</h2>$keyTable</div>`n"
    }

    # DNSDataView
    if ($Data.Analysis.DNSDataView -and $Data.Analysis.DNSDataView.RecordCount -gt 0) {
        $dnsTable = Build-DataTableHtml $Data.Analysis.DNSDataView.AllRows -MaxRows 50 -Columns @("Host Name","IP Address","Record Type","Data Length","TTL")
        $detailSections += "<div class='card'><h2>DNS Cache</h2><p>$($Data.Analysis.DNSDataView.Summary)</p>$dnsTable</div>`n"
    }

    # ProcessActivityView
    if ($Data.Analysis.ProcessActivityView -and $Data.Analysis.ProcessActivityView.ProcessCount -gt 0) {
        $procTable = Build-DataTableHtml $Data.Analysis.ProcessActivityView.AllRows -MaxRows 30
        $detailSections += "<div class='card'><h2>Process Activity</h2><p>$($Data.Analysis.ProcessActivityView.Summary)</p>$procTable</div>`n"
    }

    # Privacy-sensitive sections
    if ($Data.Analysis.LastActivityView -and $Data.Analysis.LastActivityView.ActivityCount -gt 0) {
        $lastTable = Build-DataTableHtml $Data.Analysis.LastActivityView.AllRows -MaxRows 50 -Columns @("Action Time","Description","Filename","Full Path","More Information","Data Source")
        $detailSections += "<div class='card'><h2>Recent System Activity (Customer Consent)</h2>$lastTable</div>`n"
    }

    if ($Data.Analysis.BrowserDownloadsView -and $Data.Analysis.BrowserDownloadsView.DownloadCount -gt 0) {
        $dlTable = Build-DataTableHtml $Data.Analysis.BrowserDownloadsView.AllRows -MaxRows 30 -Columns @("Filename","URL","Web Browser","Download Time","File Size","MIME Type")
        $detailSections += "<div class='card'><h2>Browser Downloads (Customer Consent)</h2>$dlTable</div>`n"
    }

$html = @"
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<title>PC Plus 360 NirSoft Diagnostic Report</title>
<style>
body{font-family:'Segoe UI',Arial,sans-serif;background:#f3f8fb;margin:0;color:#163247}
.header{background:linear-gradient(135deg,#0d4b71,#2596be);color:white;padding:30px 34px}
.header h1{margin:0;font-size:28px}
.header p{margin:8px 0 0 0;font-size:14px;opacity:0.9}
.container{padding:24px;max-width:1300px;margin:0 auto}
.card{background:white;border-radius:14px;padding:22px;margin-bottom:18px;box-shadow:0 6px 18px rgba(13,75,113,.1)}
.card h2{margin:0 0 12px 0;color:#0d4b71;font-size:18px;border-bottom:2px solid #e2e8f0;padding-bottom:8px}
.card h3{margin:14px 0 8px 0;color:#0d4b71;font-size:15px}
.grid{display:grid;grid-template-columns:repeat(4,1fr);gap:14px}
.metric{background:#eaf7fc;border-left:5px solid #2596be;border-radius:10px;padding:14px}
.metric b{display:block;color:#0d4b71;font-size:11px;text-transform:uppercase;margin-bottom:4px}
.metric span{font-size:18px;font-weight:700}
.score-big{font-size:56px;font-weight:800;color:$scoreColor;margin:10px 0}
.tbl-wrap{overflow-x:auto}
table{width:100%;border-collapse:collapse;font-size:12px}
th{background:#0d4b71;color:white;padding:8px 10px;text-align:left;font-size:11px;white-space:nowrap}
td{border-bottom:1px solid #e2e8f0;padding:7px 10px;vertical-align:top;max-width:300px;overflow:hidden;text-overflow:ellipsis}
tr:nth-child(even){background:#f8fafc}
tr:hover{background:#eaf7fc}
.badge{display:inline-block;padding:4px 10px;border-radius:999px;font-weight:700;font-size:12px;margin-left:8px}
.pass{background:#dcfce7;color:#16a34a}
.warn{background:#fef3c7;color:#d97706}
.fail{background:#fee2e2;color:#dc2626}
.missing{color:#94a3b8;font-weight:400}
.empty{color:#94a3b8;font-style:italic}
.note{font-size:12px;color:#64748b;margin-top:4px}
.footer{text-align:center;padding:20px;color:#64748b;font-size:12px;border-top:1px solid #e2e8f0;margin-top:20px}
.privacy{background:#fffbeb;border-left:5px solid #f59e0b;border-radius:10px;padding:14px;margin-top:14px;font-size:13px}
@media print{.card{break-inside:avoid;box-shadow:none;border:1px solid #e2e8f0} .header{print-color-adjust:exact;-webkit-print-color-adjust:exact}}
</style>
</head>
<body>
<div class="header">
    <h1>PC Plus 360 - NirSoft Advanced Diagnostic Report</h1>
    <p>PC Plus Computing | 604-760-1662 | 236-500-2700 | pcpluscomputing.com | Your Security, Our Priority</p>
</div>

<div class="container">
    <div class="card">
        <h2>Executive Summary</h2>
        <div class="grid">
            <div class="metric"><b>Customer</b><span>$($Data.System.CustomerName)</span></div>
            <div class="metric"><b>Technician</b><span>$($Data.System.TechnicianName)</span></div>
            <div class="metric"><b>Computer</b><span>$($Data.System.ComputerName)</span></div>
            <div class="metric"><b>Model</b><span>$($Data.System.Model)</span></div>
        </div>
        <div class="score-big">$($Data.Score.Score)/100</div>
        <p><span class="badge $(if($Data.Score.Score -ge 80){'pass'}elseif($Data.Score.Score -ge 60){'warn'}else{'fail'})">$($Data.Score.Grade)</span></p>
        <h3>Top Findings</h3>
        <ul>$issueHtml</ul>
    </div>

    <div class="card">
        <h2>System Details</h2>
        <div class="grid">
            <div class="metric"><b>Manufacturer</b><span>$($Data.System.Manufacturer)</span></div>
            <div class="metric"><b>Serial</b><span>$($Data.System.SerialNumber)</span></div>
            <div class="metric"><b>Windows</b><span>$($Data.System.OS)</span></div>
            <div class="metric"><b>Build</b><span>$($Data.System.Build)</span></div>
            <div class="metric"><b>CPU</b><span>$($Data.System.CPU)</span></div>
            <div class="metric"><b>RAM</b><span>$($Data.System.TotalRAMGB) GB</span></div>
            <div class="metric"><b>Admin</b><span>$($Data.System.IsAdmin)</span></div>
            <div class="metric"><b>NirSoft Dir</b><span>$($Data.NirSoftDir)</span></div>
        </div>
    </div>

    <div class="card">
        <h2>NirSoft Tool Status</h2>
        <table>
            <tr><th>Tool</th><th>EXE</th><th>Status</th><th>Records</th><th>Notes</th></tr>
            $($toolRows -join "`n")
        </table>
    </div>

    $detailSections

    <div class="card">
        <h2>Export Folder</h2>
        <p>$($Data.ExportDir)</p>
        <p class="note">All raw CSV/TXT exports saved for technician review.</p>
        <div class="privacy">
            <b>Customer Privacy Notice:</b> This diagnostic focuses on crashes, drivers, startup items, USB hardware history, network connections, battery status, Wi-Fi diagnostics, and event logs. It does not collect passwords, browser passwords, documents, photos, emails, or private files unless explicitly enabled with customer consent.
        </div>
    </div>
</div>

<div class="footer">
    <p>PC Plus Computing | 30+ Years in Service | 4.9 Google Rating | #1 Best Rated in Surrey</p>
    <p style="font-size:11px;color:#94a3b8;">Generated by PC Plus 360 NirSoft Suite | $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")</p>
</div>
</body>
</html>
"@

    Set-Content -Path $HtmlFile -Value $html -Encoding UTF8
}

# ============================================================
# Full Diagnostic Run (used by both GUI and console modes)
# ============================================================

function Invoke-FullDiagnostic {
    param(
        [scriptblock]$ProgressCallback = $null
    )

    $script:SuppressConsole = $true

    if (-not (Test-Path $NirSoftDir)) {
        New-Item -ItemType Directory -Path $NirSoftDir -Force | Out-Null
    }

    if ($ProgressCallback) { & $ProgressCallback "Gathering system information..." }
    $System = Get-SystemInfo

    # Build full tool definitions (safe tools)
    $allTools = @(
        @{ToolName="BlueScreenView";       ExeName="BlueScreenView.exe";       Base="BlueScreenView"},
        @{ToolName="CurrPorts";            ExeName="CurrPorts.exe";            Base="CurrPorts"},
        @{ToolName="WhatInStartup";        ExeName="WhatInStartup.exe";        Base="WhatInStartup"},
        @{ToolName="USBDeview";            ExeName="USBDeview.exe";            Base="USBDeview"},
        @{ToolName="BatteryInfoView";      ExeName="BatteryInfoView.exe";      Base="BatteryInfoView"},
        @{ToolName="DriverView";           ExeName="DriverView.exe";           Base="DriverView"},
        @{ToolName="InstalledDriversList"; ExeName="InstalledDriversList.exe"; Base="InstalledDriversList"},
        @{ToolName="WinCrashReport";       ExeName="WinCrashReport.exe";       Base="WinCrashReport"},
        @{ToolName="WifiInfoView";         ExeName="WifiInfoView.exe";         Base="WifiInfoView"},
        @{ToolName="WirelessNetView";      ExeName="WirelessNetView.exe";      Base="WirelessNetView"},
        @{ToolName="FullEventLogView";     ExeName="FullEventLogView.exe";     Base="FullEventLogView"},
        @{ToolName="OpenedFilesView";      ExeName="OpenedFilesView.exe";      Base="OpenedFilesView"},
        @{ToolName="ProduKey";             ExeName="ProduKey.exe";             Base="ProduKey"},
        @{ToolName="DNSDataView";          ExeName="DNSDataView.exe";          Base="DNSDataView"},
        @{ToolName="ProcessActivityView";  ExeName="ProcessActivityView.exe";  Base="ProcessActivityView"},
        @{ToolName="FolderChangesView";    ExeName="FolderChangesView.exe";    Base="FolderChangesView"},
        @{ToolName="AppCrashView";         ExeName="AppCrashView.exe";         Base="AppCrashView"},
        @{ToolName="NetworkInterfacesView";ExeName="NetworkInterfacesView.exe";Base="NetworkInterfacesView"},
        @{ToolName="NetworkTrafficView";   ExeName="NetworkTrafficView.exe";   Base="NetworkTrafficView"},
        @{ToolName="DevManView";           ExeName="DevManView.exe";           Base="DevManView"},
        @{ToolName="USBLogView";           ExeName="USBLogView.exe";           Base="USBLogView"},
        @{ToolName="JumpListsView";        ExeName="JumpListsView.exe";        Base="JumpListsView"},
        @{ToolName="RecentFilesView";      ExeName="RecentFilesView.exe";      Base="RecentFilesView"},
        @{ToolName="ExecutedProgramsList";  ExeName="ExecutedProgramsList.exe"; Base="ExecutedProgramsList"},
        @{ToolName="UserAssistView";       ExeName="UserAssistView.exe";       Base="UserAssistView"},
        @{ToolName="MUICacheView";         ExeName="MUICacheView.exe";         Base="MUICacheView"},
        @{ToolName="ShellBagsView";        ExeName="ShellBagsView.exe";        Base="ShellBagsView"},
        @{ToolName="SearchMyFiles";        ExeName="SearchMyFiles.exe";        Base="SearchMyFiles"},
        @{ToolName="VideoCacheView";       ExeName="VideoCacheView.exe";       Base="VideoCacheView"}
    )

    # Privacy-sensitive tools (require opt-in)
    if ($IncludeLastActivity) {
        $allTools += @{ToolName="LastActivityView"; ExeName="LastActivityView.exe"; Base="LastActivityView"}
    }
    if ($IncludeBrowserHistory) {
        $allTools += @{ToolName="BrowserDownloadsView"; ExeName="BrowserDownloadsView.exe"; Base="BrowserDownloadsView"}
        $allTools += @{ToolName="BrowsingHistoryView"; ExeName="BrowsingHistoryView.exe"; Base="BrowsingHistoryView"}
        $allTools += @{ToolName="ChromeCacheView"; ExeName="ChromeCacheView.exe"; Base="ChromeCacheView"}
        $allTools += @{ToolName="EdgeCookiesView"; ExeName="EdgeCookiesView.exe"; Base="EdgeCookiesView"}
    }

    $ToolRuns = @()
    $total = $allTools.Count
    $idx = 0
    foreach ($tool in $allTools) {
        $idx++
        if ($ProgressCallback) { & $ProgressCallback "[$idx/$total] Exporting $($tool.ToolName)..." }
        $ToolRuns += Invoke-NirSoftExport -ToolName $tool.ToolName -ExeName $tool.ExeName -ExportBaseName $tool.Base
    }

    if ($ProgressCallback) { & $ProgressCallback "Analyzing results..." }

    # Build path map for analysis
    $PathMap = @{}
    foreach ($r in $ToolRuns) { $PathMap[$r.ToolName] = $r.CsvPath }

    # Run analysis on each tool's output
    $Analysis = [PSCustomObject]@{
        BlueScreenView       = Analyze-BlueScreenView      -CsvPath $PathMap["BlueScreenView"]
        CurrPorts            = Analyze-CurrPorts            -CsvPath $PathMap["CurrPorts"]
        WhatInStartup        = Analyze-WhatInStartup        -CsvPath $PathMap["WhatInStartup"]
        USBDeview            = Analyze-USBDeview            -CsvPath $PathMap["USBDeview"]
        BatteryInfoView      = Analyze-BatteryInfoView      -CsvPath $PathMap["BatteryInfoView"]
        DriverView           = Analyze-DriverView           -CsvPath $PathMap["DriverView"]
        InstalledDriversList = Analyze-InstalledDriversList  -CsvPath $PathMap["InstalledDriversList"]
        WinCrashReport       = Analyze-WinCrashReport       -CsvPath $PathMap["WinCrashReport"]
        WifiInfoView         = Analyze-WifiInfoView         -CsvPath $PathMap["WifiInfoView"]
        WirelessNetView      = Analyze-WirelessNetView      -CsvPath $PathMap["WirelessNetView"]
        FullEventLogView     = Analyze-FullEventLogView     -CsvPath $PathMap["FullEventLogView"]
        OpenedFilesView      = Analyze-OpenedFilesView      -CsvPath $PathMap["OpenedFilesView"]
        ProduKey             = Analyze-ProduKey              -CsvPath $PathMap["ProduKey"]
        DNSDataView          = Analyze-DNSDataView           -CsvPath $PathMap["DNSDataView"]
        ProcessActivityView  = Analyze-ProcessActivityView   -CsvPath $PathMap["ProcessActivityView"]
        FolderChangesView    = Analyze-FolderChangesView     -CsvPath $PathMap["FolderChangesView"]
    }

    if ($IncludeLastActivity -and $PathMap["LastActivityView"]) {
        $Analysis | Add-Member -MemberType NoteProperty -Name "LastActivityView" -Value (Analyze-LastActivityView -CsvPath $PathMap["LastActivityView"])
    }
    if ($IncludeBrowserHistory -and $PathMap["BrowserDownloadsView"]) {
        $Analysis | Add-Member -MemberType NoteProperty -Name "BrowserDownloadsView" -Value (Analyze-BrowserDownloadsView -CsvPath $PathMap["BrowserDownloadsView"])
    }

    if ($ProgressCallback) { & $ProgressCallback "Calculating health score..." }
    $Score = Get-PCPlusNirSoftScore -Analysis $Analysis

    $Data = [PSCustomObject]@{
        System = $System
        NirSoftDir = $NirSoftDir
        ReportDir = $ReportDir
        ExportDir = $ExportDir
        ToolRuns = $ToolRuns
        Analysis = $Analysis
        Score = $Score
    }

    # JSON export
    if ($ProgressCallback) { & $ProgressCallback "Generating reports..." }
    $Data | ConvertTo-Json -Depth 12 | Set-Content -Path $JsonFile -Encoding UTF8

    # TXT summary
    $summary = @"
PC Plus 360 NirSoft Diagnostic Summary

Customer: $CustomerName
Technician: $TechnicianName
Computer: $($System.ComputerName)
Model: $($System.Manufacturer) $($System.Model)
Serial: $($System.SerialNumber)
Windows: $($System.OS) Build $($System.Build)

Score: $($Score.Score)/100
Grade: $($Score.Grade)

Top Findings:
$($Score.Issues -join "`r`n")

Tool Results:
$($Analysis.PSObject.Properties | ForEach-Object { "- $($_.Name): $($_.Value.Summary)" } | Out-String)

Reports:
HTML: $HtmlFile
JSON: $JsonFile
Exports: $ExportDir
"@
    Set-Content -Path $TxtFile -Value $summary -Encoding UTF8

    # CSV summary
    [PSCustomObject]@{
        ComputerName = $System.ComputerName
        CustomerName = $CustomerName
        Score = $Score.Score
        Grade = $Score.Grade
        BlueScreens = $Analysis.BlueScreenView.CrashCount
        AppCrashes = $Analysis.WinCrashReport.AppCrashCount
        StartupEnabled = $Analysis.WhatInStartup.StartupEnabled
        ExternalConnections = $Analysis.CurrPorts.ExternalConnectionCount
        UnsignedDrivers = $Analysis.InstalledDriversList.UnsignedDriverCount
        ProblemDrivers = $Analysis.InstalledDriversList.ProblemDriverCount
        EventLogErrors = $Analysis.FullEventLogView.ErrorOrCriticalCount
        USBHistory = $Analysis.USBDeview.TotalUsbHistory
        ReportDate = Get-Date
    } | Export-Csv -Path $CsvFile -NoTypeInformation

    # HTML report
    New-PCPlusHtmlReport -Data $Data

    if ($ProgressCallback) { & $ProgressCallback "Diagnostic complete! Score: $($Score.Score)/100 ($($Score.Grade))" }

    $script:SuppressConsole = $false
    return $Data
}

# ============================================================
# Tool Definitions with Categories & Descriptions (for GUI)
# ============================================================

function Get-AllToolDefinitions {
    return @(
        # System & Crash Analysis
        [PSCustomObject]@{ Category="System & Crash Analysis"; ToolName="BlueScreenView"; ExeName="BlueScreenView.exe"; Description="Analyze BSOD minidump crash files"; Privacy=$false }
        [PSCustomObject]@{ Category="System & Crash Analysis"; ToolName="WinCrashReport"; ExeName="WinCrashReport.exe"; Description="Windows Error Reporting crash logs"; Privacy=$false }
        [PSCustomObject]@{ Category="System & Crash Analysis"; ToolName="AppCrashView"; ExeName="AppCrashView.exe"; Description="Application crash event viewer"; Privacy=$false }

        # Network & Connectivity
        [PSCustomObject]@{ Category="Network & Connectivity"; ToolName="CurrPorts"; ExeName="CurrPorts.exe"; Description="Active TCP/UDP network connections"; Privacy=$false }
        [PSCustomObject]@{ Category="Network & Connectivity"; ToolName="WifiInfoView"; ExeName="WifiInfoView.exe"; Description="Connected Wi-Fi adapter details"; Privacy=$false }
        [PSCustomObject]@{ Category="Network & Connectivity"; ToolName="WirelessNetView"; ExeName="WirelessNetView.exe"; Description="Scan nearby wireless networks"; Privacy=$false }
        [PSCustomObject]@{ Category="Network & Connectivity"; ToolName="DNSDataView"; ExeName="DNSDataView.exe"; Description="DNS resolver cache entries"; Privacy=$false }
        [PSCustomObject]@{ Category="Network & Connectivity"; ToolName="NetworkInterfacesView"; ExeName="NetworkInterfacesView.exe"; Description="All network adapters and statistics"; Privacy=$false }
        [PSCustomObject]@{ Category="Network & Connectivity"; ToolName="NetworkTrafficView"; ExeName="NetworkTrafficView.exe"; Description="Network traffic per-process breakdown"; Privacy=$false }

        # Hardware & Drivers
        [PSCustomObject]@{ Category="Hardware & Drivers"; ToolName="DriverView"; ExeName="DriverView.exe"; Description="Currently loaded kernel-mode drivers"; Privacy=$false }
        [PSCustomObject]@{ Category="Hardware & Drivers"; ToolName="InstalledDriversList"; ExeName="InstalledDriversList.exe"; Description="All installed driver packages audit"; Privacy=$false }
        [PSCustomObject]@{ Category="Hardware & Drivers"; ToolName="BatteryInfoView"; ExeName="BatteryInfoView.exe"; Description="Battery health, wear level, capacity"; Privacy=$false }
        [PSCustomObject]@{ Category="Hardware & Drivers"; ToolName="DevManView"; ExeName="DevManView.exe"; Description="Device Manager alternative with details"; Privacy=$false }

        # Startup & Security
        [PSCustomObject]@{ Category="Startup & Security"; ToolName="WhatInStartup"; ExeName="WhatInStartup.exe"; Description="All auto-start programs and services"; Privacy=$false }
        [PSCustomObject]@{ Category="Startup & Security"; ToolName="ProduKey"; ExeName="ProduKey.exe"; Description="Recover Windows/Office product keys"; Privacy=$false }

        # USB & Storage
        [PSCustomObject]@{ Category="USB & Storage"; ToolName="USBDeview"; ExeName="USBDeview.exe"; Description="Complete USB device connection history"; Privacy=$false }
        [PSCustomObject]@{ Category="USB & Storage"; ToolName="USBLogView"; ExeName="USBLogView.exe"; Description="USB connect/disconnect event log"; Privacy=$false }

        # Browser & History (privacy-sensitive)
        [PSCustomObject]@{ Category="Browser & History"; ToolName="BrowsingHistoryView"; ExeName="BrowsingHistoryView.exe"; Description="Multi-browser URL history [PRIVACY]"; Privacy=$true }
        [PSCustomObject]@{ Category="Browser & History"; ToolName="ChromeCacheView"; ExeName="ChromeCacheView.exe"; Description="Chrome browser cache contents [PRIVACY]"; Privacy=$true }
        [PSCustomObject]@{ Category="Browser & History"; ToolName="EdgeCookiesView"; ExeName="EdgeCookiesView.exe"; Description="Microsoft Edge cookies viewer [PRIVACY]"; Privacy=$true }
        [PSCustomObject]@{ Category="Browser & History"; ToolName="BrowserDownloadsView"; ExeName="BrowserDownloadsView.exe"; Description="All browser download records [PRIVACY]"; Privacy=$true }

        # System Activity
        [PSCustomObject]@{ Category="System Activity"; ToolName="LastActivityView"; ExeName="LastActivityView.exe"; Description="Recent user activity timeline [PRIVACY]"; Privacy=$true }
        [PSCustomObject]@{ Category="System Activity"; ToolName="ExecutedProgramsList"; ExeName="ExecutedProgramsList.exe"; Description="Programs executed on this PC"; Privacy=$false }
        [PSCustomObject]@{ Category="System Activity"; ToolName="OpenedFilesView"; ExeName="OpenedFilesView.exe"; Description="Currently locked/opened file handles"; Privacy=$false }
        [PSCustomObject]@{ Category="System Activity"; ToolName="FolderChangesView"; ExeName="FolderChangesView.exe"; Description="Real-time file system change monitor"; Privacy=$false }
        [PSCustomObject]@{ Category="System Activity"; ToolName="FullEventLogView"; ExeName="FullEventLogView.exe"; Description="Enhanced Windows Event Log viewer"; Privacy=$false }
        [PSCustomObject]@{ Category="System Activity"; ToolName="JumpListsView"; ExeName="JumpListsView.exe"; Description="Taskbar jump list recent items"; Privacy=$false }
        [PSCustomObject]@{ Category="System Activity"; ToolName="RecentFilesView"; ExeName="RecentFilesView.exe"; Description="Recently opened files list"; Privacy=$false }
        [PSCustomObject]@{ Category="System Activity"; ToolName="UserAssistView"; ExeName="UserAssistView.exe"; Description="UserAssist registry run count data"; Privacy=$false }
        [PSCustomObject]@{ Category="System Activity"; ToolName="MUICacheView"; ExeName="MUICacheView.exe"; Description="MUI cache application name entries"; Privacy=$false }
        [PSCustomObject]@{ Category="System Activity"; ToolName="ShellBagsView"; ExeName="ShellBagsView.exe"; Description="Explorer folder access history"; Privacy=$false }

        # Forensics & Search
        [PSCustomObject]@{ Category="Forensics & Search"; ToolName="ProcessActivityView"; ExeName="ProcessActivityView.exe"; Description="Process creation/termination log"; Privacy=$false }
        [PSCustomObject]@{ Category="Forensics & Search"; ToolName="SearchMyFiles"; ExeName="SearchMyFiles.exe"; Description="Advanced file search by attributes"; Privacy=$false }
        [PSCustomObject]@{ Category="Forensics & Search"; ToolName="VideoCacheView"; ExeName="VideoCacheView.exe"; Description="Browser video cache extractor"; Privacy=$true }
    )
}

# ============================================================
# WinForms GUI
# ============================================================

function Show-NirSoftGUI {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    # Colors
    $colNavy       = [System.Drawing.Color]::FromArgb(10, 22, 40)       # #0a1628
    $colNavyLight  = [System.Drawing.Color]::FromArgb(16, 32, 56)       # slightly lighter for panels
    $colAccent     = [System.Drawing.Color]::FromArgb(37, 150, 190)     # #2596be
    $colGreen      = [System.Drawing.Color]::FromArgb(39, 174, 96)      # #27ae60
    $colRed        = [System.Drawing.Color]::FromArgb(231, 76, 60)      # #e74c3c
    $colText       = [System.Drawing.Color]::FromArgb(220, 230, 240)
    $colTextDim    = [System.Drawing.Color]::FromArgb(140, 160, 180)
    $colRowAlt     = [System.Drawing.Color]::FromArgb(14, 28, 48)
    $colHeaderBg   = [System.Drawing.Color]::FromArgb(20, 40, 65)

    # Fonts
    $fontTitle     = New-Object System.Drawing.Font("Segoe UI", 16, [System.Drawing.FontStyle]::Bold)
    $fontSubtitle  = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Regular)
    $fontCategory  = New-Object System.Drawing.Font("Segoe UI Semibold", 10, [System.Drawing.FontStyle]::Bold)
    $fontNormal    = New-Object System.Drawing.Font("Segoe UI", 9)
    $fontSmall     = New-Object System.Drawing.Font("Segoe UI", 8)
    $fontLog       = New-Object System.Drawing.Font("Consolas", 8.5)
    $fontBtn       = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)

    # Main Form
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "PC Plus 360 - NirSoft Portable Tools Suite"
    $form.Size = New-Object System.Drawing.Size(920, 720)
    $form.StartPosition = "CenterScreen"
    $form.BackColor = $colNavy
    $form.ForeColor = $colText
    $form.Font = $fontNormal
    $form.MinimumSize = New-Object System.Drawing.Size(800, 600)
    $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::Sizable

    # ---- Header Panel ----
    $panelHeader = New-Object System.Windows.Forms.Panel
    $panelHeader.Dock = [System.Windows.Forms.DockStyle]::Top
    $panelHeader.Height = 70
    $panelHeader.BackColor = $colNavyLight
    $panelHeader.Padding = New-Object System.Windows.Forms.Padding(16, 8, 16, 8)
    $form.Controls.Add($panelHeader)

    $lblTitle = New-Object System.Windows.Forms.Label
    $lblTitle.Text = "PC Plus 360 - NirSoft Portable Tools Suite"
    $lblTitle.Font = $fontTitle
    $lblTitle.ForeColor = $colAccent
    $lblTitle.AutoSize = $true
    $lblTitle.Location = New-Object System.Drawing.Point(16, 10)
    $panelHeader.Controls.Add($lblTitle)

    $lblContact = New-Object System.Windows.Forms.Label
    $lblContact.Text = "PC Plus Computing  |  604-760-1662  |  236-500-2700  |  pcpluscomputing.com"
    $lblContact.Font = $fontSubtitle
    $lblContact.ForeColor = $colTextDim
    $lblContact.AutoSize = $true
    $lblContact.Location = New-Object System.Drawing.Point(16, 42)
    $panelHeader.Controls.Add($lblContact)

    # ---- Bottom Panel ----
    $panelBottom = New-Object System.Windows.Forms.Panel
    $panelBottom.Dock = [System.Windows.Forms.DockStyle]::Bottom
    $panelBottom.Height = 170
    $panelBottom.BackColor = $colNavyLight
    $panelBottom.Padding = New-Object System.Windows.Forms.Padding(16, 8, 16, 8)
    $form.Controls.Add($panelBottom)

    # Buttons in bottom panel
    $btnRunAll = New-Object System.Windows.Forms.Button
    $btnRunAll.Text = "Run Full Diagnostic"
    $btnRunAll.Font = $fontBtn
    $btnRunAll.Size = New-Object System.Drawing.Size(180, 36)
    $btnRunAll.Location = New-Object System.Drawing.Point(16, 10)
    $btnRunAll.BackColor = $colGreen
    $btnRunAll.ForeColor = [System.Drawing.Color]::White
    $btnRunAll.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnRunAll.FlatAppearance.BorderSize = 0
    $btnRunAll.Cursor = [System.Windows.Forms.Cursors]::Hand
    $panelBottom.Controls.Add($btnRunAll)

    $btnOpenReports = New-Object System.Windows.Forms.Button
    $btnOpenReports.Text = "Open Reports Folder"
    $btnOpenReports.Font = $fontBtn
    $btnOpenReports.Size = New-Object System.Drawing.Size(180, 36)
    $btnOpenReports.Location = New-Object System.Drawing.Point(210, 10)
    $btnOpenReports.BackColor = $colAccent
    $btnOpenReports.ForeColor = [System.Drawing.Color]::White
    $btnOpenReports.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnOpenReports.FlatAppearance.BorderSize = 0
    $btnOpenReports.Cursor = [System.Windows.Forms.Cursors]::Hand
    $panelBottom.Controls.Add($btnOpenReports)

    $lblNirDir = New-Object System.Windows.Forms.Label
    $lblNirDir.Text = "Tools: $NirSoftDir"
    $lblNirDir.Font = $fontSmall
    $lblNirDir.ForeColor = $colTextDim
    $lblNirDir.AutoSize = $true
    $lblNirDir.Location = New-Object System.Drawing.Point(410, 18)
    $panelBottom.Controls.Add($lblNirDir)

    # Log text box
    $txtLog = New-Object System.Windows.Forms.TextBox
    $txtLog.Multiline = $true
    $txtLog.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
    $txtLog.ReadOnly = $true
    $txtLog.Font = $fontLog
    $txtLog.BackColor = [System.Drawing.Color]::FromArgb(6, 14, 28)
    $txtLog.ForeColor = $colTextDim
    $txtLog.BorderStyle = [System.Windows.Forms.BorderStyle]::None
    $txtLog.Location = New-Object System.Drawing.Point(16, 54)
    $txtLog.Size = New-Object System.Drawing.Size(870, 105)
    $txtLog.Anchor = [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right -bor [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Bottom
    $panelBottom.Controls.Add($txtLog)

    # ---- Main Scrollable Panel (tool list) ----
    $panelMain = New-Object System.Windows.Forms.Panel
    $panelMain.Dock = [System.Windows.Forms.DockStyle]::Fill
    $panelMain.AutoScroll = $true
    $panelMain.Padding = New-Object System.Windows.Forms.Padding(16, 8, 16, 8)
    $form.Controls.Add($panelMain)

    # Helper to log messages
    $script:LogToGUI = {
        param([string]$msg)
        $txtLog.AppendText("[$(Get-Date -Format 'HH:mm:ss')] $msg`r`n")
        $txtLog.SelectionStart = $txtLog.TextLength
        $txtLog.ScrollToCaret()
        [System.Windows.Forms.Application]::DoEvents()
    }

    # Build tool entries in the panel
    $allDefs = Get-AllToolDefinitions
    $categories = @($allDefs | Select-Object -ExpandProperty Category -Unique)

    $yPos = 8
    $panelWidth = 860

    foreach ($cat in $categories) {
        # Category header
        $lblCat = New-Object System.Windows.Forms.Label
        $lblCat.Text = $cat.ToUpper()
        $lblCat.Font = $fontCategory
        $lblCat.ForeColor = $colAccent
        $lblCat.AutoSize = $false
        $lblCat.Size = New-Object System.Drawing.Size($panelWidth, 24)
        $lblCat.Location = New-Object System.Drawing.Point(0, $yPos)
        $lblCat.BackColor = $colHeaderBg
        $lblCat.Padding = New-Object System.Windows.Forms.Padding(8, 3, 0, 0)
        $panelMain.Controls.Add($lblCat)
        $yPos += 28

        $toolsInCat = @($allDefs | Where-Object { $_.Category -eq $cat })
        foreach ($toolDef in $toolsInCat) {
            $toolPath = Get-ToolPath $toolDef.ExeName
            $isFound = ($null -ne $toolPath)

            # Row panel
            $rowPanel = New-Object System.Windows.Forms.Panel
            $rowPanel.Size = New-Object System.Drawing.Size($panelWidth, 32)
            $rowPanel.Location = New-Object System.Drawing.Point(0, $yPos)
            $rowPanel.BackColor = if (($yPos / 32) % 2 -eq 0) { $colNavy } else { $colRowAlt }
            $panelMain.Controls.Add($rowPanel)

            # Status dot
            $lblDot = New-Object System.Windows.Forms.Label
            $lblDot.Text = [char]0x25CF  # filled circle
            $lblDot.Font = New-Object System.Drawing.Font("Segoe UI", 11)
            $lblDot.ForeColor = if ($isFound) { $colGreen } else { $colRed }
            $lblDot.AutoSize = $true
            $lblDot.Location = New-Object System.Drawing.Point(10, 5)
            $rowPanel.Controls.Add($lblDot)

            # Tool name
            $lblName = New-Object System.Windows.Forms.Label
            $lblName.Text = $toolDef.ToolName
            $lblName.Font = $fontNormal
            $lblName.ForeColor = $colText
            $lblName.AutoSize = $false
            $lblName.Size = New-Object System.Drawing.Size(180, 20)
            $lblName.Location = New-Object System.Drawing.Point(30, 6)
            $rowPanel.Controls.Add($lblName)

            # Description
            $lblDesc = New-Object System.Windows.Forms.Label
            $lblDesc.Text = $toolDef.Description
            $lblDesc.Font = $fontSmall
            $lblDesc.ForeColor = $colTextDim
            $lblDesc.AutoSize = $false
            $lblDesc.Size = New-Object System.Drawing.Size(360, 20)
            $lblDesc.Location = New-Object System.Drawing.Point(215, 7)
            $rowPanel.Controls.Add($lblDesc)

            # Launch button
            $btnLaunch = New-Object System.Windows.Forms.Button
            $btnLaunch.Text = "Launch"
            $btnLaunch.Font = $fontSmall
            $btnLaunch.Size = New-Object System.Drawing.Size(65, 24)
            $btnLaunch.Location = New-Object System.Drawing.Point(600, 4)
            $btnLaunch.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
            $btnLaunch.FlatAppearance.BorderColor = $colAccent
            $btnLaunch.FlatAppearance.BorderSize = 1
            $btnLaunch.BackColor = $colNavy
            $btnLaunch.ForeColor = $colAccent
            $btnLaunch.Enabled = $isFound
            $btnLaunch.Cursor = [System.Windows.Forms.Cursors]::Hand
            $btnLaunch.Tag = $toolPath
            $btnLaunch.Add_Click({
                $path = $this.Tag
                if ($path -and (Test-Path $path)) {
                    try {
                        Start-Process -FilePath $path
                        & $script:LogToGUI "Launched: $path"
                    } catch {
                        & $script:LogToGUI "ERROR launching: $($_.Exception.Message)"
                    }
                }
            })
            $rowPanel.Controls.Add($btnLaunch)

            # Export button
            $btnExport = New-Object System.Windows.Forms.Button
            $btnExport.Text = "Export"
            $btnExport.Font = $fontSmall
            $btnExport.Size = New-Object System.Drawing.Size(65, 24)
            $btnExport.Location = New-Object System.Drawing.Point(675, 4)
            $btnExport.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
            $btnExport.FlatAppearance.BorderColor = $colGreen
            $btnExport.FlatAppearance.BorderSize = 1
            $btnExport.BackColor = $colNavy
            $btnExport.ForeColor = $colGreen
            $btnExport.Enabled = $isFound
            $btnExport.Cursor = [System.Windows.Forms.Cursors]::Hand
            $btnExport.Tag = @{ ToolName = $toolDef.ToolName; ExeName = $toolDef.ExeName; Base = $toolDef.ToolName }
            $btnExport.Add_Click({
                $info = $this.Tag
                & $script:LogToGUI "Exporting $($info.ToolName)..."
                $this.Enabled = $false
                [System.Windows.Forms.Application]::DoEvents()
                try {
                    $result = Invoke-NirSoftExport -ToolName $info.ToolName -ExeName $info.ExeName -ExportBaseName $info.Base
                    if ($result.Ran) {
                        & $script:LogToGUI "  -> $($info.ToolName): $($result.RowCount) record(s) exported to CSV"
                    } else {
                        & $script:LogToGUI "  -> $($info.ToolName): Export failed - $($result.Notes)"
                    }
                } catch {
                    & $script:LogToGUI "  -> ERROR: $($_.Exception.Message)"
                }
                $this.Enabled = $true
            })
            $rowPanel.Controls.Add($btnExport)

            # Privacy badge
            if ($toolDef.Privacy) {
                $lblPriv = New-Object System.Windows.Forms.Label
                $lblPriv.Text = "PRIVACY"
                $lblPriv.Font = New-Object System.Drawing.Font("Segoe UI", 7, [System.Drawing.FontStyle]::Bold)
                $lblPriv.ForeColor = [System.Drawing.Color]::FromArgb(245, 158, 11)
                $lblPriv.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 10)
                $lblPriv.AutoSize = $true
                $lblPriv.Location = New-Object System.Drawing.Point(752, 9)
                $rowPanel.Controls.Add($lblPriv)
            }

            $yPos += 34
        }

        $yPos += 6  # space between categories
    }

    # Summary label at bottom of tool list
    $foundCount = @($allDefs | Where-Object { Get-ToolPath $_.ExeName }).Count
    $totalCount = $allDefs.Count
    $lblSummary = New-Object System.Windows.Forms.Label
    $lblSummary.Text = "$foundCount of $totalCount tools found in: $NirSoftDir"
    $lblSummary.Font = $fontSmall
    $lblSummary.ForeColor = if ($foundCount -eq $totalCount) { $colGreen } elseif ($foundCount -gt 0) { $colAccent } else { $colRed }
    $lblSummary.AutoSize = $true
    $lblSummary.Location = New-Object System.Drawing.Point(10, $yPos)
    $panelMain.Controls.Add($lblSummary)

    # ---- Event Handlers ----
    $btnRunAll.Add_Click({
        $btnRunAll.Enabled = $false
        $btnRunAll.Text = "Running..."
        $btnRunAll.BackColor = $colAccent
        [System.Windows.Forms.Application]::DoEvents()

        & $script:LogToGUI "=== FULL DIAGNOSTIC STARTED ==="
        & $script:LogToGUI "NirSoft Dir: $NirSoftDir"
        & $script:LogToGUI "Report Dir: $ReportDir"

        try {
            $progressCb = {
                param([string]$msg)
                & $script:LogToGUI $msg
            }
            $result = Invoke-FullDiagnostic -ProgressCallback $progressCb

            & $script:LogToGUI "=== DIAGNOSTIC COMPLETE ==="
            & $script:LogToGUI "HTML Report: $HtmlFile"
            & $script:LogToGUI "Score: $($result.Score.Score)/100 ($($result.Score.Grade))"

            if ($result.Score.Issues.Count -gt 0) {
                & $script:LogToGUI "Issues:"
                foreach ($issue in $result.Score.Issues) {
                    & $script:LogToGUI "  - $issue"
                }
            }

            # Open the HTML report automatically
            if (Test-Path $HtmlFile) {
                Start-Process $HtmlFile
            }
        } catch {
            & $script:LogToGUI "ERROR: $($_.Exception.Message)"
        }

        $btnRunAll.Enabled = $true
        $btnRunAll.Text = "Run Full Diagnostic"
        $btnRunAll.BackColor = $colGreen
    })

    $btnOpenReports.Add_Click({
        $reportsBase = "C:\PCPlus360\NirSoftReports"
        if (-not (Test-Path $reportsBase)) {
            New-Item -ItemType Directory -Path $reportsBase -Force | Out-Null
        }
        Start-Process "explorer.exe" -ArgumentList $reportsBase
    })

    # Initial log message
    & $script:LogToGUI "PC Plus 360 NirSoft Suite ready. $foundCount/$totalCount tools available."
    if (-not (Test-Path $NirSoftDir)) {
        & $script:LogToGUI "WARNING: NirSoft directory not found: $NirSoftDir"
        & $script:LogToGUI "Place NirSoft EXE files there and restart."
    }

    # Show the form
    [void]$form.ShowDialog()

    # Cleanup
    $form.Dispose()
}

# ============================================================
# Main Entry Point
# ============================================================

if ($NoGUI) {
    # Console-only mode (original behavior)
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "  PC PLUS 360 - NIRSOFT PORTABLE TOOLS SUITE" -ForegroundColor Cyan
    Write-Host "  PC Plus Computing | pcpluscomputing.com" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""

    Write-PCLog "PC Plus 360 NirSoft Diagnostic started."
    Write-PCLog "NirSoft directory: $NirSoftDir"

    if (-not (Test-Path $NirSoftDir)) {
        New-Item -ItemType Directory -Path $NirSoftDir -Force | Out-Null
        Write-PCLog "NirSoft directory created: $NirSoftDir" "WARN"
        Write-Host "NirSoft directory created at: $NirSoftDir" -ForegroundColor Yellow
        Write-Host "Place NirSoft EXE files there and run again." -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Recommended tools to download from nirsoft.net:" -ForegroundColor Cyan
        Write-Host "  BlueScreenView.exe, CurrPorts.exe, USBDeview.exe," -ForegroundColor White
        Write-Host "  BatteryInfoView.exe, WhatInStartup.exe, InstalledDriversList.exe," -ForegroundColor White
        Write-Host "  DriverView.exe, WinCrashReport.exe, WifiInfoView.exe," -ForegroundColor White
        Write-Host "  WirelessNetView.exe, FullEventLogView.exe, OpenedFilesView.exe," -ForegroundColor White
        Write-Host "  ProduKey.exe, DNSDataView.exe" -ForegroundColor White
        Read-Host "Press Enter to exit"
        exit
    }

    if (-not (Test-IsAdmin)) {
        Write-PCLog "Not running as Administrator. Some outputs may be limited." "WARN"
    }

    $System = Get-SystemInfo

    # Safe tools (auto-run, no privacy concern)
    $ToolDefinitions = @(
        @{ToolName="BlueScreenView";       ExeName="BlueScreenView.exe";       Base="BlueScreenView"},
        @{ToolName="CurrPorts";            ExeName="CurrPorts.exe";            Base="CurrPorts"},
        @{ToolName="WhatInStartup";        ExeName="WhatInStartup.exe";        Base="WhatInStartup"},
        @{ToolName="USBDeview";            ExeName="USBDeview.exe";            Base="USBDeview"},
        @{ToolName="BatteryInfoView";      ExeName="BatteryInfoView.exe";      Base="BatteryInfoView"},
        @{ToolName="DriverView";           ExeName="DriverView.exe";           Base="DriverView"},
        @{ToolName="InstalledDriversList"; ExeName="InstalledDriversList.exe"; Base="InstalledDriversList"},
        @{ToolName="WinCrashReport";       ExeName="WinCrashReport.exe";       Base="WinCrashReport"},
        @{ToolName="WifiInfoView";         ExeName="WifiInfoView.exe";         Base="WifiInfoView"},
        @{ToolName="WirelessNetView";      ExeName="WirelessNetView.exe";      Base="WirelessNetView"},
        @{ToolName="FullEventLogView";     ExeName="FullEventLogView.exe";     Base="FullEventLogView"},
        @{ToolName="OpenedFilesView";      ExeName="OpenedFilesView.exe";      Base="OpenedFilesView"},
        @{ToolName="ProduKey";             ExeName="ProduKey.exe";             Base="ProduKey"},
        @{ToolName="DNSDataView";          ExeName="DNSDataView.exe";          Base="DNSDataView"},
        @{ToolName="ProcessActivityView";  ExeName="ProcessActivityView.exe";  Base="ProcessActivityView"},
        @{ToolName="FolderChangesView";    ExeName="FolderChangesView.exe";    Base="FolderChangesView"},
        @{ToolName="AppCrashView";         ExeName="AppCrashView.exe";         Base="AppCrashView"},
        @{ToolName="NetworkInterfacesView";ExeName="NetworkInterfacesView.exe";Base="NetworkInterfacesView"},
        @{ToolName="NetworkTrafficView";   ExeName="NetworkTrafficView.exe";   Base="NetworkTrafficView"},
        @{ToolName="DevManView";           ExeName="DevManView.exe";           Base="DevManView"},
        @{ToolName="USBLogView";           ExeName="USBLogView.exe";           Base="USBLogView"},
        @{ToolName="JumpListsView";        ExeName="JumpListsView.exe";        Base="JumpListsView"},
        @{ToolName="RecentFilesView";      ExeName="RecentFilesView.exe";      Base="RecentFilesView"},
        @{ToolName="ExecutedProgramsList";  ExeName="ExecutedProgramsList.exe"; Base="ExecutedProgramsList"},
        @{ToolName="UserAssistView";       ExeName="UserAssistView.exe";       Base="UserAssistView"},
        @{ToolName="MUICacheView";         ExeName="MUICacheView.exe";         Base="MUICacheView"},
        @{ToolName="ShellBagsView";        ExeName="ShellBagsView.exe";        Base="ShellBagsView"},
        @{ToolName="SearchMyFiles";        ExeName="SearchMyFiles.exe";        Base="SearchMyFiles"},
        @{ToolName="VideoCacheView";       ExeName="VideoCacheView.exe";       Base="VideoCacheView"}
    )

    # Privacy-sensitive tools (require opt-in)
    if ($IncludeLastActivity) {
        $ToolDefinitions += @{ToolName="LastActivityView"; ExeName="LastActivityView.exe"; Base="LastActivityView"}
    }
    if ($IncludeBrowserHistory) {
        $ToolDefinitions += @{ToolName="BrowserDownloadsView"; ExeName="BrowserDownloadsView.exe"; Base="BrowserDownloadsView"}
        $ToolDefinitions += @{ToolName="BrowsingHistoryView"; ExeName="BrowsingHistoryView.exe"; Base="BrowsingHistoryView"}
        $ToolDefinitions += @{ToolName="ChromeCacheView"; ExeName="ChromeCacheView.exe"; Base="ChromeCacheView"}
        $ToolDefinitions += @{ToolName="EdgeCookiesView"; ExeName="EdgeCookiesView.exe"; Base="EdgeCookiesView"}
    }

    $available = @($ToolDefinitions | Where-Object { Get-ToolPath $_.ExeName })
    $missingTools = @($ToolDefinitions | Where-Object { -not (Get-ToolPath $_.ExeName) })

    Write-Host "Available: $($available.Count) / $($ToolDefinitions.Count) tools" -ForegroundColor Green
    if ($missingTools.Count -gt 0) {
        Write-Host "Missing: $($missingTools.Count) tool(s)" -ForegroundColor Yellow
        foreach ($m in $missingTools) { Write-Host "  - $($m.ExeName)" -ForegroundColor DarkYellow }
    }
    Write-Host ""

    $ToolRuns = @()
    foreach ($tool in $ToolDefinitions) {
        $ToolRuns += Invoke-NirSoftExport -ToolName $tool.ToolName -ExeName $tool.ExeName -ExportBaseName $tool.Base
    }

    # Build path map for analysis
    $PathMap = @{}
    foreach ($r in $ToolRuns) { $PathMap[$r.ToolName] = $r.CsvPath }

    # Run analysis on each tool's output
    $Analysis = [PSCustomObject]@{
        BlueScreenView       = Analyze-BlueScreenView      -CsvPath $PathMap["BlueScreenView"]
        CurrPorts            = Analyze-CurrPorts            -CsvPath $PathMap["CurrPorts"]
        WhatInStartup        = Analyze-WhatInStartup        -CsvPath $PathMap["WhatInStartup"]
        USBDeview            = Analyze-USBDeview            -CsvPath $PathMap["USBDeview"]
        BatteryInfoView      = Analyze-BatteryInfoView      -CsvPath $PathMap["BatteryInfoView"]
        DriverView           = Analyze-DriverView           -CsvPath $PathMap["DriverView"]
        InstalledDriversList = Analyze-InstalledDriversList  -CsvPath $PathMap["InstalledDriversList"]
        WinCrashReport       = Analyze-WinCrashReport       -CsvPath $PathMap["WinCrashReport"]
        WifiInfoView         = Analyze-WifiInfoView         -CsvPath $PathMap["WifiInfoView"]
        WirelessNetView      = Analyze-WirelessNetView      -CsvPath $PathMap["WirelessNetView"]
        FullEventLogView     = Analyze-FullEventLogView     -CsvPath $PathMap["FullEventLogView"]
        OpenedFilesView      = Analyze-OpenedFilesView      -CsvPath $PathMap["OpenedFilesView"]
        ProduKey             = Analyze-ProduKey              -CsvPath $PathMap["ProduKey"]
        DNSDataView          = Analyze-DNSDataView           -CsvPath $PathMap["DNSDataView"]
        ProcessActivityView  = Analyze-ProcessActivityView   -CsvPath $PathMap["ProcessActivityView"]
        FolderChangesView    = Analyze-FolderChangesView     -CsvPath $PathMap["FolderChangesView"]
    }

    if ($IncludeLastActivity -and $PathMap["LastActivityView"]) {
        $Analysis | Add-Member -MemberType NoteProperty -Name "LastActivityView" -Value (Analyze-LastActivityView -CsvPath $PathMap["LastActivityView"])
    }
    if ($IncludeBrowserHistory -and $PathMap["BrowserDownloadsView"]) {
        $Analysis | Add-Member -MemberType NoteProperty -Name "BrowserDownloadsView" -Value (Analyze-BrowserDownloadsView -CsvPath $PathMap["BrowserDownloadsView"])
    }

    $Score = Get-PCPlusNirSoftScore -Analysis $Analysis

    $Data = [PSCustomObject]@{
        System = $System
        NirSoftDir = $NirSoftDir
        ReportDir = $ReportDir
        ExportDir = $ExportDir
        ToolRuns = $ToolRuns
        Analysis = $Analysis
        Score = $Score
    }

    # JSON export
    $Data | ConvertTo-Json -Depth 12 | Set-Content -Path $JsonFile -Encoding UTF8

    # TXT summary
    $summary = @"
PC Plus 360 NirSoft Diagnostic Summary

Customer: $CustomerName
Technician: $TechnicianName
Computer: $($System.ComputerName)
Model: $($System.Manufacturer) $($System.Model)
Serial: $($System.SerialNumber)
Windows: $($System.OS) Build $($System.Build)

Score: $($Score.Score)/100
Grade: $($Score.Grade)

Top Findings:
$($Score.Issues -join "`r`n")

Tool Results:
$($Analysis.PSObject.Properties | ForEach-Object { "- $($_.Name): $($_.Value.Summary)" } | Out-String)

Reports:
HTML: $HtmlFile
JSON: $JsonFile
Exports: $ExportDir
"@
    Set-Content -Path $TxtFile -Value $summary -Encoding UTF8

    # CSV summary
    [PSCustomObject]@{
        ComputerName = $System.ComputerName
        CustomerName = $CustomerName
        Score = $Score.Score
        Grade = $Score.Grade
        BlueScreens = $Analysis.BlueScreenView.CrashCount
        AppCrashes = $Analysis.WinCrashReport.AppCrashCount
        StartupEnabled = $Analysis.WhatInStartup.StartupEnabled
        ExternalConnections = $Analysis.CurrPorts.ExternalConnectionCount
        UnsignedDrivers = $Analysis.InstalledDriversList.UnsignedDriverCount
        ProblemDrivers = $Analysis.InstalledDriversList.ProblemDriverCount
        EventLogErrors = $Analysis.FullEventLogView.ErrorOrCriticalCount
        USBHistory = $Analysis.USBDeview.TotalUsbHistory
        ReportDate = Get-Date
    } | Export-Csv -Path $CsvFile -NoTypeInformation

    # HTML report
    New-PCPlusHtmlReport -Data $Data

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "  PC Plus 360 NirSoft Diagnostic Completed" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "Score: $($Score.Score)/100 (Grade: $($Score.Grade))" -ForegroundColor $(if ($Score.Score -ge 80) { "Green" } elseif ($Score.Score -ge 60) { "Yellow" } else { "Red" })
    Write-Host ""
    Write-Host "Report Folder: $ReportDir" -ForegroundColor White
    Write-Host "HTML Report:   $HtmlFile" -ForegroundColor White
    Write-Host "JSON Raw Data: $JsonFile" -ForegroundColor White
    Write-Host "TXT Summary:   $TxtFile" -ForegroundColor White
    Write-Host "CSV Summary:   $CsvFile" -ForegroundColor White
    Write-Host "Exports:       $ExportDir" -ForegroundColor White
    Write-Host "Log File:      $LogFile" -ForegroundColor White

    if ($Score.Issues.Count -gt 0) {
        Write-Host ""
        Write-Host "Issues Found:" -ForegroundColor Yellow
        foreach ($i in $Score.Issues) { Write-Host "  - $i" -ForegroundColor Yellow }
    }

    $missing = @($ToolRuns | Where-Object { -not $_.Found })
    if ($missing.Count -gt 0) {
        Write-Host ""
        Write-Host "Missing NirSoft tools:" -ForegroundColor Yellow
        $missing | ForEach-Object { Write-Host "  - $($_.ExeName)" -ForegroundColor Yellow }
        Write-Host "Place EXE files in: $NirSoftDir" -ForegroundColor Yellow
    }

    Write-Host ""

    if ($OpenReport -and (Test-Path $HtmlFile)) {
        Start-Process $HtmlFile
    }

    Write-PCLog "PC Plus 360 NirSoft Diagnostic completed."
} else {
    # GUI mode (default)
    Show-NirSoftGUI
}

<#
PC Plus 360 - NirSoft Diagnostic Integration Script
Company: PC Plus Computing
Website: pcpluscomputing.com
Phone: 604-760-1662

Purpose:
Run helpful NirSoft portable diagnostic tools, export their results, and generate a branded
HTML/TXT/JSON summary report for PC Plus 360 diagnostics.

IMPORTANT:
This script DOES NOT download NirSoft tools automatically.
Place the NirSoft EXE files in:
C:\PCPlus360\Tools\NirSoft

Recommended tools:
- BlueScreenView.exe
- FullEventLogView.exe
- WhatInStartup.exe
- CurrPorts.exe
- USBDeview.exe
- BatteryInfoView.exe
- DriverView.exe
- InstalledDriversList.exe
- WinCrashReport.exe
- WifiInfoView.exe
- WirelessNetView.exe
- OpenedFilesView.exe

Privacy:
By default this script avoids browser history, password recovery, email/account extraction,
and private user data tools. Add those only with written customer consent.

Run:
PowerShell.exe -ExecutionPolicy Bypass -File .\PCPlus360-NirSoft-Diagnostic.ps1

Optional:
PowerShell.exe -ExecutionPolicy Bypass -File .\PCPlus360-NirSoft-Diagnostic.ps1 -CustomerName "John Smith" -TechnicianName "Paul"
#>

param(
    [string]$CustomerName = "Customer",
    [string]$TechnicianName = "PC Plus Technician",
    [string]$NirSoftDir = "C:\PCPlus360\Tools\NirSoft",
    [switch]$OpenReport
)

$ErrorActionPreference = "Continue"

# ============================================================
# Paths
# ============================================================

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
    Write-Host $line
    Add-Content -Path $LogFile -Value $line
}

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-ToolPath {
    param([string]$ExeName)
    $path = Join-Path $NirSoftDir $ExeName
    if (Test-Path $path) { return $path }
    return $null
}

function Invoke-NirSoftExport {
    param(
        [string]$ToolName,
        [string]$ExeName,
        [string]$ExportBaseName,
        [string]$ExportSwitch = "/scomma",
        [string]$ExtraArgs = ""
    )

    $exe = Get-ToolPath $ExeName
    $csv = Join-Path $ExportDir "$ExportBaseName.csv"
    $txt = Join-Path $ExportDir "$ExportBaseName.txt"

    if (-not $exe) {
        Write-PCLog "$ToolName not found: $ExeName" "WARN"
        return [PSCustomObject]@{
            ToolName = $ToolName
            ExeName = $ExeName
            Found = $false
            Ran = $false
            ExitCode = $null
            CsvPath = $null
            TxtPath = $null
            RowCount = 0
            Notes = "Tool not found in $NirSoftDir"
        }
    }

    try {
        Write-PCLog "Running $ToolName export."

        # CSV export
        $args = "$ExtraArgs $ExportSwitch `"$csv`""
        $p = Start-Process -FilePath $exe -ArgumentList $args -Wait -PassThru -WindowStyle Hidden

        # TXT export fallback/additional
        $txtArgs = "$ExtraArgs /stext `"$txt`""
        Start-Process -FilePath $exe -ArgumentList $txtArgs -Wait -WindowStyle Hidden | Out-Null

        Start-Sleep -Milliseconds 300

        $rows = 0
        if (Test-Path $csv) {
            try {
                $import = Import-Csv $csv -ErrorAction SilentlyContinue
                $rows = @($import).Count
            } catch {
                $rows = 0
            }
        }

        [PSCustomObject]@{
            ToolName = $ToolName
            ExeName = $ExeName
            Found = $true
            Ran = $true
            ExitCode = $p.ExitCode
            CsvPath = $csv
            TxtPath = if (Test-Path $txt) { $txt } else { $null }
            RowCount = $rows
            Notes = "Export completed"
        }
    } catch {
        Write-PCLog "$ToolName failed: $($_.Exception.Message)" "ERROR"
        [PSCustomObject]@{
            ToolName = $ToolName
            ExeName = $ExeName
            Found = $true
            Ran = $false
            ExitCode = $null
            CsvPath = $null
            TxtPath = $null
            RowCount = 0
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
        $possible = @(
            $r.'Caused By Driver',
            $r.'Caused By Address',
            $r.'File Description',
            $r.'Product Name'
        ) | Where-Object { $_ }
        foreach ($p in $possible) { $drivers += $p }
    }

    [PSCustomObject]@{
        CrashCount = $rows.Count
        RecentCrashes = $recent
        CommonDrivers = @($drivers | Group-Object | Sort-Object Count -Descending | Select-Object -First 5 Name,Count)
        Summary = if ($rows.Count -gt 0) { "$($rows.Count) blue screen dump(s) found." } else { "No BSOD dump records exported." }
    }
}

function Analyze-CurrPorts {
    param([string]$CsvPath)

    $rows = Import-CsvSafe $CsvPath
    $listening = @($rows | Where-Object { $_.State -match "Listen" -or $_.'Local Port' })
    $external = @($rows | Where-Object { $_.'Remote Address' -and $_.'Remote Address' -notmatch "^(127\.|0\.0\.0\.0|::|localhost)" })

    [PSCustomObject]@{
        TotalConnections = $rows.Count
        ListeningOrLocalPortCount = $listening.Count
        ExternalConnectionCount = $external.Count
        TopProcesses = @($rows | Where-Object { $_.'Process Name' } | Group-Object 'Process Name' | Sort-Object Count -Descending | Select-Object -First 10 Name,Count)
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
        StartupItems = @($rows | Select-Object -First 25)
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
        RecentDevices = @($rows | Select-Object -First 25)
        Summary = "$($rows.Count) USB device history record(s); $($connected.Count) currently connected."
    }
}

function Analyze-BatteryInfoView {
    param([string]$CsvPath)

    $rows = Import-CsvSafe $CsvPath
    $health = $null

    foreach ($r in $rows) {
        foreach ($prop in $r.PSObject.Properties.Name) {
            if ($prop -match "Battery Health|Health") {
                $health = $r.$prop
            }
        }
    }

    [PSCustomObject]@{
        BatteryRows = $rows.Count
        BatteryHealth = $health
        BatteryData = @($rows | Select-Object -First 5)
        Summary = if ($rows.Count -gt 0) { "Battery data exported." } else { "No battery data exported or desktop detected." }
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
        TopNonMicrosoft = @($nonMicrosoft | Select-Object -First 25)
        Summary = "$($rows.Count) drivers exported; $($nonMicrosoft.Count) non-Microsoft driver(s)."
    }
}

function Analyze-InstalledDriversList {
    param([string]$CsvPath)

    $rows = Import-CsvSafe $CsvPath
    $problem = @($rows | Where-Object { $_.Status -and $_.Status -notmatch "OK|Running" })

    [PSCustomObject]@{
        TotalInstalledDrivers = $rows.Count
        ProblemDriverCount = $problem.Count
        ProblemDrivers = @($problem | Select-Object -First 25)
        Summary = "$($rows.Count) installed driver record(s); $($problem.Count) potential problem driver(s)."
    }
}

function Analyze-WinCrashReport {
    param([string]$CsvPath)

    $rows = Import-CsvSafe $CsvPath
    [PSCustomObject]@{
        AppCrashCount = $rows.Count
        RecentAppCrashes = @($rows | Select-Object -First 25)
        Summary = "$($rows.Count) application crash report(s) exported."
    }
}

function Analyze-WifiInfoView {
    param([string]$CsvPath)

    $rows = Import-CsvSafe $CsvPath
    [PSCustomObject]@{
        WifiNetworksSeen = $rows.Count
        Networks = @($rows | Select-Object -First 25)
        Summary = "$($rows.Count) Wi-Fi network record(s) exported."
    }
}

function Analyze-FullEventLogView {
    param([string]$CsvPath)

    $rows = Import-CsvSafe $CsvPath
    $errors = @($rows | Where-Object { $_.Level -match "Error|Critical" -or $_.'Event Type' -match "Error|Critical" })

    [PSCustomObject]@{
        EventRows = $rows.Count
        ErrorOrCriticalCount = $errors.Count
        RecentErrors = @($errors | Select-Object -First 50)
        Summary = "$($rows.Count) event log records exported; $($errors.Count) error/critical records detected."
    }
}

function Analyze-OpenedFilesView {
    param([string]$CsvPath)

    $rows = Import-CsvSafe $CsvPath
    [PSCustomObject]@{
        OpenedFileCount = $rows.Count
        Samples = @($rows | Select-Object -First 25)
        Summary = "$($rows.Count) opened/locked file record(s) exported."
    }
}

function Get-PCPlusNirSoftScore {
    param($Analysis)

    $score = 100
    $issues = @()

    if ($Analysis.BlueScreenView.CrashCount -gt 0) {
        $score -= [math]::Min(25, $Analysis.BlueScreenView.CrashCount * 8)
        $issues += "$($Analysis.BlueScreenView.CrashCount) blue screen dump(s) found."
    }

    if ($Analysis.WinCrashReport.AppCrashCount -gt 5) {
        $score -= 10
        $issues += "$($Analysis.WinCrashReport.AppCrashCount) application crash report(s) found."
    }

    if ($Analysis.WhatInStartup.StartupEnabled -gt 20) {
        $score -= 8
        $issues += "High number of startup items: $($Analysis.WhatInStartup.StartupEnabled)."
    }

    if ($Analysis.InstalledDriversList.ProblemDriverCount -gt 0) {
        $score -= [math]::Min(15, $Analysis.InstalledDriversList.ProblemDriverCount * 5)
        $issues += "$($Analysis.InstalledDriversList.ProblemDriverCount) possible problem driver(s)."
    }

    if ($Analysis.FullEventLogView.ErrorOrCriticalCount -gt 50) {
        $score -= 10
        $issues += "High event log error count: $($Analysis.FullEventLogView.ErrorOrCriticalCount)."
    }

    if ($Analysis.CurrPorts.ExternalConnectionCount -gt 50) {
        $score -= 5
        $issues += "High number of external network connections: $($Analysis.CurrPorts.ExternalConnectionCount)."
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
# HTML Report
# ============================================================

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
        $status = if ($t.Ran) { "PASS" } elseif ($t.Found) { "WARNING" } else { "MISSING" }
        $class = if ($t.Ran) { "pass" } elseif ($t.Found) { "warn" } else { "fail" }
        "<tr><td>$($t.ToolName)</td><td>$($t.ExeName)</td><td class='$class'>$status</td><td>$($t.RowCount)</td><td>$($t.Notes)</td></tr>"
    }

    $summaryRows = foreach ($p in $Data.Analysis.PSObject.Properties) {
        $name = $p.Name
        $summary = $p.Value.Summary
        "<tr><td>$name</td><td>$summary</td></tr>"
    }

$html = @"
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<title>PC Plus 360 NirSoft Diagnostic Report</title>
<style>
body{font-family:Segoe UI,Arial,sans-serif;background:#f3f8fb;margin:0;color:#163247}
.header{background:linear-gradient(135deg,#0d4b71,#2596be);color:white;padding:34px}
.header h1{margin:0;font-size:32px}
.header p{margin:8px 0 0 0;font-size:15px}
.container{padding:24px}
.card{background:white;border-radius:16px;padding:22px;margin-bottom:18px;box-shadow:0 8px 22px rgba(13,75,113,.12)}
.grid{display:grid;grid-template-columns:repeat(4,1fr);gap:14px}
.metric{background:#eaf7fc;border-left:6px solid #2596be;border-radius:12px;padding:14px}
.metric b{display:block;color:#0d4b71;font-size:12px;text-transform:uppercase}
.metric span{font-size:18px;font-weight:700}
.score{font-size:58px;font-weight:800;color:$scoreColor;margin:8px 0}
table{width:100%;border-collapse:collapse;font-size:13px}
th{background:#0d4b71;color:white;padding:10px;text-align:left}
td{border-bottom:1px solid #dbe8ef;padding:9px;vertical-align:top}
.pass{color:#16a34a;font-weight:700}
.warn{color:#f59e0b;font-weight:700}
.fail{color:#dc2626;font-weight:700}
.badge{display:inline-block;padding:6px 10px;border-radius:999px;background:#eaf7fc;color:#0d4b71;font-weight:700}
.footer{text-align:center;padding:20px;color:#64748b;font-size:12px}
.small{font-size:12px;color:#64748b}
</style>
</head>
<body>
<div class="header">
  <h1>PC Plus 360 NirSoft Diagnostic Report</h1>
  <p>PC Plus Computing | 604-760-1662 | pcpluscomputing.com | Your Security, Our Priority</p>
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
    <div class="score">$($Data.Score.Score)/100</div>
    <p><span class="badge">$($Data.Score.Grade)</span></p>
    <h3>Top Findings</h3>
    <ul>$issueHtml</ul>
  </div>

  <div class="card">
    <h2>System Details</h2>
    <table>
      <tr><th>Manufacturer</th><td>$($Data.System.Manufacturer)</td></tr>
      <tr><th>Model</th><td>$($Data.System.Model)</td></tr>
      <tr><th>Serial</th><td>$($Data.System.SerialNumber)</td></tr>
      <tr><th>Windows</th><td>$($Data.System.OS) Build $($Data.System.Build)</td></tr>
      <tr><th>CPU</th><td>$($Data.System.CPU)</td></tr>
      <tr><th>RAM</th><td>$($Data.System.TotalRAMGB) GB</td></tr>
      <tr><th>Admin</th><td>$($Data.System.IsAdmin)</td></tr>
    </table>
  </div>

  <div class="card">
    <h2>NirSoft Tool Run Status</h2>
    <table>
      <tr><th>Tool</th><th>EXE</th><th>Status</th><th>Rows</th><th>Notes</th></tr>
      $($toolRows -join "`n")
    </table>
  </div>

  <div class="card">
    <h2>Analysis Summary</h2>
    <table>
      <tr><th>Module</th><th>Summary</th></tr>
      $($summaryRows -join "`n")
    </table>
  </div>

  <div class="card">
    <h2>Export Folder</h2>
    <p>$ExportDir</p>
    <p class="small">All raw CSV/TXT exports are saved in this folder for technician review.</p>
  </div>

  <div class="card">
    <h2>Customer Privacy Notice</h2>
    <p>This diagnostic focuses on crashes, drivers, startup items, USB hardware history, network connections, battery status, Wi-Fi diagnostics, and event logs. It does not collect passwords, browser passwords, documents, photos, emails, or private files.</p>
  </div>
</div>

<div class="footer">
PC Plus Computing | 30+ Years in Service | 4.9 Google Rating | #1 Best Rated in Surrey
</div>
</body>
</html>
"@

    Set-Content -Path $HtmlFile -Value $html -Encoding UTF8
}

# ============================================================
# Main
# ============================================================

Write-PCLog "PC Plus 360 NirSoft Diagnostic started."
Write-PCLog "NirSoft directory: $NirSoftDir"

if (-not (Test-Path $NirSoftDir)) {
    New-Item -ItemType Directory -Path $NirSoftDir -Force | Out-Null
    Write-PCLog "NirSoft directory was missing and has been created: $NirSoftDir" "WARN"
    Write-PCLog "Place NirSoft EXE files in this folder and run the script again." "WARN"
}

if (-not (Test-IsAdmin)) {
    Write-PCLog "Not running as Administrator. Some outputs may be limited." "WARN"
}

$System = Get-SystemInfo

# Tool list. Only safe/non-password/non-browser-history tools are included by default.
$ToolDefinitions = @(
    @{ToolName="BlueScreenView";        ExeName="BlueScreenView.exe";        Base="BlueScreenView"},
    @{ToolName="CurrPorts";             ExeName="CurrPorts.exe";             Base="CurrPorts"},
    @{ToolName="WhatInStartup";         ExeName="WhatInStartup.exe";         Base="WhatInStartup"},
    @{ToolName="USBDeview";             ExeName="USBDeview.exe";             Base="USBDeview"},
    @{ToolName="BatteryInfoView";       ExeName="BatteryInfoView.exe";       Base="BatteryInfoView"},
    @{ToolName="DriverView";            ExeName="DriverView.exe";            Base="DriverView"},
    @{ToolName="InstalledDriversList";  ExeName="InstalledDriversList.exe";  Base="InstalledDriversList"},
    @{ToolName="WinCrashReport";        ExeName="WinCrashReport.exe";        Base="WinCrashReport"},
    @{ToolName="WifiInfoView";          ExeName="WifiInfoView.exe";          Base="WifiInfoView"},
    @{ToolName="WirelessNetView";       ExeName="WirelessNetView.exe";       Base="WirelessNetView"},
    @{ToolName="FullEventLogView";      ExeName="FullEventLogView.exe";      Base="FullEventLogView"},
    @{ToolName="OpenedFilesView";       ExeName="OpenedFilesView.exe";       Base="OpenedFilesView"}
)

$ToolRuns = @()

foreach ($tool in $ToolDefinitions) {
    $ToolRuns += Invoke-NirSoftExport -ToolName $tool.ToolName -ExeName $tool.ExeName -ExportBaseName $tool.Base
}

# Build path map
$PathMap = @{}
foreach ($r in $ToolRuns) {
    $PathMap[$r.ToolName] = $r.CsvPath
}

$Analysis = [PSCustomObject]@{
    BlueScreenView       = Analyze-BlueScreenView      -CsvPath $PathMap["BlueScreenView"]
    CurrPorts            = Analyze-CurrPorts           -CsvPath $PathMap["CurrPorts"]
    WhatInStartup        = Analyze-WhatInStartup       -CsvPath $PathMap["WhatInStartup"]
    USBDeview            = Analyze-USBDeview           -CsvPath $PathMap["USBDeview"]
    BatteryInfoView      = Analyze-BatteryInfoView     -CsvPath $PathMap["BatteryInfoView"]
    DriverView           = Analyze-DriverView          -CsvPath $PathMap["DriverView"]
    InstalledDriversList = Analyze-InstalledDriversList -CsvPath $PathMap["InstalledDriversList"]
    WinCrashReport       = Analyze-WinCrashReport      -CsvPath $PathMap["WinCrashReport"]
    WifiInfoView         = Analyze-WifiInfoView        -CsvPath $PathMap["WifiInfoView"]
    FullEventLogView     = Analyze-FullEventLogView    -CsvPath $PathMap["FullEventLogView"]
    OpenedFilesView      = Analyze-OpenedFilesView     -CsvPath $PathMap["OpenedFilesView"]
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

$Data | ConvertTo-Json -Depth 12 | Set-Content -Path $JsonFile -Encoding UTF8

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

Reports:
HTML: $HtmlFile
JSON: $JsonFile
Exports: $ExportDir
"@

Set-Content -Path $TxtFile -Value $summary -Encoding UTF8

[PSCustomObject]@{
    ComputerName = $System.ComputerName
    CustomerName = $CustomerName
    Score = $Score.Score
    Grade = $Score.Grade
    BlueScreens = $Analysis.BlueScreenView.CrashCount
    AppCrashes = $Analysis.WinCrashReport.AppCrashCount
    StartupEnabled = $Analysis.WhatInStartup.StartupEnabled
    ExternalConnections = $Analysis.CurrPorts.ExternalConnectionCount
    USBHistory = $Analysis.USBDeview.TotalUsbHistory
    ReportDate = Get-Date
} | Export-Csv -Path $CsvFile -NoTypeInformation

New-PCPlusHtmlReport -Data $Data

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "PC Plus 360 NirSoft Diagnostic Completed" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "Report Folder: $ReportDir"
Write-Host "HTML Report:   $HtmlFile"
Write-Host "JSON Raw Data: $JsonFile"
Write-Host "TXT Summary:   $TxtFile"
Write-Host "CSV Summary:   $CsvFile"
Write-Host "Exports:       $ExportDir"
Write-Host "Log File:      $LogFile"
Write-Host ""

$missing = @($ToolRuns | Where-Object { -not $_.Found })
if ($missing.Count -gt 0) {
    Write-Host "Missing NirSoft tools:" -ForegroundColor Yellow
    $missing | ForEach-Object { Write-Host "- $($_.ExeName)" -ForegroundColor Yellow }
    Write-Host ""
    Write-Host "Place the EXE files in: $NirSoftDir" -ForegroundColor Yellow
}

if ($OpenReport -and (Test-Path $HtmlFile)) {
    Start-Process $HtmlFile
}

Write-PCLog "PC Plus 360 NirSoft Diagnostic completed."

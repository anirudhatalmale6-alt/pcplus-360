<#
PC Plus 360 - NirSoft Portable Tools Suite
Company: PC Plus Computing
Website: pcpluscomputing.com
Phone: 604-760-1662

Integrates NirSoft portable tools for advanced diagnostics:
- BlueScreenView: BSOD crash analysis
- CurrPorts: Active TCP/UDP connections (security)
- USBDeview: USB device history and diagnostics
- BatteryInfoView: Laptop battery health
- WhatInStartup: Startup items analysis
- InstalledDriversList: Driver audit
- DriverView: Loaded kernel drivers
- WinCrashReport: Application crash reports
- WifiInfoView: Wi-Fi network analysis
- ProduKey: Windows/Office license keys
- WirelessNetView: Nearby Wi-Fi networks
- DNSDataView: DNS cache analysis
- LastActivityView: Recent system activity
- OpenedFilesView: Currently locked files
- ProcessActivityView: Process execution history
- FolderChangesView: File system changes
- FullEventLogView: Enhanced event log viewer

Place NirSoft .exe files in: tools\nirsoft\
Each tool runs silently with /scomma export, results merged into branded HTML report.

Run as Administrator for best results.
PowerShell.exe -ExecutionPolicy Bypass -File .\PCPlus-NirSoftSuite.ps1
#>

param(
    [string]$CustomerName = "Customer",
    [string]$TechnicianName = "PC Plus Technician",
    [switch]$IncludeBrowserHistory,
    [switch]$IncludeLastActivity,
    [switch]$AutoRunAll
)

$ErrorActionPreference = "Continue"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
if ([string]::IsNullOrEmpty($ScriptDir)) { $ScriptDir = Get-Location }
$NirSoftDir = Join-Path $ScriptDir "tools\nirsoft"
$TimeStamp = Get-Date -Format "yyyyMMdd-HHmmss"
$ComputerSafe = $env:COMPUTERNAME -replace '[^\w\-]', '_'
$ReportDir = "C:\PCPlus360\NirSoft-Reports\$ComputerSafe-$TimeStamp"
New-Item -ItemType Directory -Path $ReportDir -Force | Out-Null

$LogFile = Join-Path $ReportDir "nirsoft-scan.log"
$JsonFile = Join-Path $ReportDir "nirsoft-data.json"
$HtmlFile = Join-Path $ReportDir "PCPlus360-NirSoft-Report.html"

function Write-NirLog {
    param([string]$Message, [string]$Level = "INFO")
    $line = "[{0}] [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Level, $Message
    Write-Host $line
    Add-Content -Path $LogFile -Value $line
}

function Test-NirTool {
    param([string]$Name)
    $exe = Join-Path $NirSoftDir "$Name.exe"
    return (Test-Path $exe)
}

function Invoke-NirTool {
    param(
        [string]$Name,
        [string]$ExtraArgs = "",
        [int]$TimeoutSec = 30
    )
    $exe = Join-Path $NirSoftDir "$Name.exe"
    if (-not (Test-Path $exe)) { return $null }

    $csvFile = Join-Path $ReportDir "$Name.csv"
    $args = "/scomma `"$csvFile`" $ExtraArgs"

    Write-NirLog "Running $Name..."
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $exe
        $psi.Arguments = $args
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true

        $p = New-Object System.Diagnostics.Process
        $p.StartInfo = $psi
        $null = $p.Start()

        if (-not $p.WaitForExit($TimeoutSec * 1000)) {
            $p.Kill()
            Write-NirLog "$Name timed out after ${TimeoutSec}s" "WARN"
            return $null
        }

        if (Test-Path $csvFile) {
            $data = Import-Csv $csvFile -ErrorAction SilentlyContinue
            Write-NirLog "$Name completed: $(@($data).Count) records"
            return $data
        } else {
            Write-NirLog "$Name produced no output" "WARN"
            return $null
        }
    } catch {
        Write-NirLog "$Name failed: $($_.Exception.Message)" "ERROR"
        return $null
    }
}

function Get-AvailableTools {
    $tools = @(
        @{Name="BlueScreenView"; Desc="BSOD Crash Analysis"; Category="Stability"; Priority="MUST HAVE"; SafeAuto=$true}
        @{Name="CurrPorts"; Desc="Active Network Connections"; Category="Security"; Priority="MUST HAVE"; SafeAuto=$true}
        @{Name="USBDeview"; Desc="USB Device History"; Category="Hardware"; Priority="MUST HAVE"; SafeAuto=$true}
        @{Name="BatteryInfoView"; Desc="Battery Health Details"; Category="Hardware"; Priority="MUST HAVE"; SafeAuto=$true}
        @{Name="WhatInStartup"; Desc="Startup Items Analysis"; Category="Performance"; Priority="MUST HAVE"; SafeAuto=$true}
        @{Name="InstalledDriversList"; Desc="Installed Driver Audit"; Category="Drivers"; Priority="MUST HAVE"; SafeAuto=$true}
        @{Name="DriverView"; Desc="Loaded Kernel Drivers"; Category="Drivers"; Priority="HIGH"; SafeAuto=$true}
        @{Name="WinCrashReport"; Desc="Application Crash Reports"; Category="Stability"; Priority="HIGH"; SafeAuto=$true}
        @{Name="WifiInfoView"; Desc="Wi-Fi Network Analysis"; Category="Network"; Priority="HIGH"; SafeAuto=$true}
        @{Name="ProduKey"; Desc="License Key Recovery"; Category="System"; Priority="HIGH"; SafeAuto=$true}
        @{Name="WirelessNetView"; Desc="Nearby Wi-Fi Networks"; Category="Network"; Priority="MEDIUM"; SafeAuto=$true}
        @{Name="DNSDataView"; Desc="DNS Cache Analysis"; Category="Network"; Priority="MEDIUM"; SafeAuto=$true}
        @{Name="FullEventLogView"; Desc="Enhanced Event Log Viewer"; Category="Stability"; Priority="HIGH"; SafeAuto=$true}
        @{Name="OpenedFilesView"; Desc="Currently Locked Files"; Category="System"; Priority="MEDIUM"; SafeAuto=$true}
        @{Name="ProcessActivityView"; Desc="Process Execution History"; Category="Security"; Priority="MEDIUM"; SafeAuto=$true}
        @{Name="FolderChangesView"; Desc="File System Changes"; Category="Security"; Priority="MEDIUM"; SafeAuto=$true}
        @{Name="LastActivityView"; Desc="Recent System Activity"; Category="Forensics"; Priority="HIGH"; SafeAuto=$false}
        @{Name="BrowserDownloadsView"; Desc="Browser Downloads History"; Category="Security"; Priority="MEDIUM"; SafeAuto=$false}
        @{Name="BrowserHistoryView"; Desc="Browser Browsing History"; Category="Privacy"; Priority="LOW"; SafeAuto=$false}
        @{Name="SmartSniff"; Desc="Network Traffic Monitor"; Category="Network"; Priority="MEDIUM"; SafeAuto=$false}
    )

    foreach ($t in $tools) {
        $t.Available = Test-NirTool $t.Name
    }
    return $tools
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  PC PLUS 360 - NIRSOFT PORTABLE TOOLS SUITE" -ForegroundColor Cyan
Write-Host "  PC Plus Computing | pcpluscomputing.com" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

Write-NirLog "NirSoft Suite scan started."
Write-NirLog "Customer: $CustomerName | Tech: $TechnicianName"
Write-NirLog "NirSoft folder: $NirSoftDir"

$allTools = Get-AvailableTools
$available = @($allTools | Where-Object { $_.Available })
$missing = @($allTools | Where-Object { -not $_.Available })

Write-Host "Available tools: $($available.Count) / $($allTools.Count)" -ForegroundColor Green
if ($missing.Count -gt 0) {
    Write-Host "Missing tools: $($missing.Count) (place .exe files in tools\nirsoft\)" -ForegroundColor Yellow
    foreach ($m in $missing) {
        Write-Host "  - $($m.Name) ($($m.Desc))" -ForegroundColor DarkYellow
    }
}
Write-Host ""

if ($available.Count -eq 0) {
    Write-Host "No NirSoft tools found in $NirSoftDir" -ForegroundColor Red
    Write-Host "Download portable versions from nirsoft.net and place .exe files in:" -ForegroundColor Yellow
    Write-Host "  $NirSoftDir" -ForegroundColor White
    Write-Host ""
    Write-Host "Recommended tools to download:" -ForegroundColor Cyan
    foreach ($t in ($allTools | Where-Object { $_.Priority -in @("MUST HAVE","HIGH") })) {
        Write-Host "  - $($t.Name).exe  ($($t.Desc))" -ForegroundColor White
    }
    pause
    exit
}

$Data = [ordered]@{
    ScanDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    CustomerName = $CustomerName
    TechnicianName = $TechnicianName
    ComputerName = $env:COMPUTERNAME
    AvailableTools = $available.Count
    TotalTools = $allTools.Count
}

$score = 100
$issues = @()
$recommendations = @()

# ── BLUESCREEN VIEW ──
if (Test-NirTool "BlueScreenView") {
    Write-Host "Scanning BSOD crash history..." -ForegroundColor Cyan
    $bsod = Invoke-NirTool "BlueScreenView"
    $Data.BlueScreenView = @($bsod)
    if ($bsod -and @($bsod).Count -gt 0) {
        $count = @($bsod).Count
        $recent = @($bsod)[0]
        $issues += "Found $count Blue Screen crash(es). Most recent caused by: $($recent.'Caused By Driver')"
        if ($count -ge 5) { $score -= 20 }
        elseif ($count -ge 2) { $score -= 10 }
        else { $score -= 5 }
        $recommendations += "Investigate BSOD crashes - check '$($recent.'Caused By Driver')' driver for updates or corruption."
    }
}

# ── CURRPORTS ──
if (Test-NirTool "CurrPorts") {
    Write-Host "Scanning active network connections..." -ForegroundColor Cyan
    $ports = Invoke-NirTool "CurrPorts"
    $Data.CurrPorts = @($ports)
    if ($ports) {
        $listening = @($ports | Where-Object { $_.'State' -eq 'Listening' })
        $established = @($ports | Where-Object { $_.'State' -eq 'Established' })
        $suspectPorts = @($ports | Where-Object {
            $p = $_.'Local Port'
            $p -and ($p -match '^\d+$') -and ([int]$p -gt 49152 -or [int]$p -in @(4444,5555,6666,7777,8888,9999,1337,31337))
        })
        if ($suspectPorts.Count -gt 0) {
            $issues += "$($suspectPorts.Count) connection(s) on unusual/suspicious ports detected."
            $score -= 5
            $recommendations += "Review connections on unusual ports for potential unauthorized access."
        }
    }
}

# ── USB DEVIEW ──
if (Test-NirTool "USBDeview") {
    Write-Host "Scanning USB device history..." -ForegroundColor Cyan
    $usb = Invoke-NirTool "USBDeview"
    $Data.USBDeview = @($usb)
    if ($usb) {
        $connected = @($usb | Where-Object { $_.'Connected' -eq 'Yes' })
        $disconnected = @($usb | Where-Object { $_.'Connected' -eq 'No' })
        $safeRemove = @($usb | Where-Object { $_.'Safe To Unplug' -eq 'No' -and $_.'Connected' -eq 'Yes' })
    }
}

# ── BATTERY INFO VIEW ──
if (Test-NirTool "BatteryInfoView") {
    Write-Host "Scanning battery health..." -ForegroundColor Cyan
    $battery = Invoke-NirTool "BatteryInfoView"
    $Data.BatteryInfoView = @($battery)
    if ($battery -and @($battery).Count -gt 0) {
        $b = @($battery)[0]
        $wearStr = $b.'Wear Level'
        if ($wearStr -and $wearStr -match '(\d+)') {
            $wear = [int]$matches[1]
            if ($wear -gt 40) {
                $issues += "Battery wear level is $wear% - battery replacement recommended."
                $score -= 10
                $recommendations += "Replace battery - wear level exceeds 40%."
            } elseif ($wear -gt 20) {
                $score -= 3
            }
        }
    }
}

# ── WHATINSTARTUP ──
if (Test-NirTool "WhatInStartup") {
    Write-Host "Scanning startup items..." -ForegroundColor Cyan
    $startup = Invoke-NirTool "WhatInStartup"
    $Data.WhatInStartup = @($startup)
    if ($startup) {
        $enabled = @($startup | Where-Object { $_.'Disabled' -ne 'Yes' })
        if ($enabled.Count -gt 15) {
            $issues += "$($enabled.Count) startup items enabled - may cause slow boot."
            $score -= 5
            $recommendations += "Disable unnecessary startup items to improve boot time."
        }
    }
}

# ── INSTALLED DRIVERS LIST ──
if (Test-NirTool "InstalledDriversList") {
    Write-Host "Auditing installed drivers..." -ForegroundColor Cyan
    $drivers = Invoke-NirTool "InstalledDriversList"
    $Data.InstalledDriversList = @($drivers)
    if ($drivers) {
        $unsigned = @($drivers | Where-Object { $_.'Signed' -eq 'No' -or $_.'Digital Signature' -eq 'Not Signed' })
        if ($unsigned.Count -gt 0) {
            $issues += "$($unsigned.Count) unsigned driver(s) found."
            $score -= 3
            $recommendations += "Review unsigned drivers for potential security or stability risks."
        }
    }
}

# ── DRIVER VIEW ──
if (Test-NirTool "DriverView") {
    Write-Host "Scanning loaded kernel drivers..." -ForegroundColor Cyan
    $drvView = Invoke-NirTool "DriverView"
    $Data.DriverView = @($drvView)
}

# ── WIN CRASH REPORT ──
if (Test-NirTool "WinCrashReport") {
    Write-Host "Scanning application crash reports..." -ForegroundColor Cyan
    $crashes = Invoke-NirTool "WinCrashReport"
    $Data.WinCrashReport = @($crashes)
    if ($crashes -and @($crashes).Count -gt 0) {
        $count = @($crashes).Count
        if ($count -ge 10) {
            $issues += "$count application crash report(s) found - system stability may be affected."
            $score -= 8
        } elseif ($count -ge 3) {
            $score -= 3
        }
    }
}

# ── WIFI INFO VIEW ──
if (Test-NirTool "WifiInfoView") {
    Write-Host "Scanning Wi-Fi networks..." -ForegroundColor Cyan
    $wifi = Invoke-NirTool "WifiInfoView"
    $Data.WifiInfoView = @($wifi)
}

# ── PRODUKEY ──
if (Test-NirTool "ProduKey") {
    Write-Host "Recovering license keys..." -ForegroundColor Cyan
    $keys = Invoke-NirTool "ProduKey"
    $Data.ProduKey = @($keys)
}

# ── WIRELESS NET VIEW ──
if (Test-NirTool "WirelessNetView") {
    Write-Host "Scanning nearby wireless networks..." -ForegroundColor Cyan
    $wnet = Invoke-NirTool "WirelessNetView"
    $Data.WirelessNetView = @($wnet)
}

# ── DNS DATA VIEW ──
if (Test-NirTool "DNSDataView") {
    Write-Host "Analyzing DNS cache..." -ForegroundColor Cyan
    $dns = Invoke-NirTool "DNSDataView"
    $Data.DNSDataView = @($dns)
}

# ── FULL EVENT LOG VIEW ──
if (Test-NirTool "FullEventLogView") {
    Write-Host "Scanning event logs (errors only)..." -ForegroundColor Cyan
    $evtArgs = '/filter "Include,Error"'
    $evt = Invoke-NirTool "FullEventLogView" -ExtraArgs $evtArgs -TimeoutSec 60
    $Data.FullEventLogView = @($evt)
}

# ── OPENED FILES VIEW ──
if (Test-NirTool "OpenedFilesView") {
    Write-Host "Scanning locked files..." -ForegroundColor Cyan
    $openFiles = Invoke-NirTool "OpenedFilesView"
    $Data.OpenedFilesView = @($openFiles)
}

# ── PROCESS ACTIVITY VIEW ──
if (Test-NirTool "ProcessActivityView") {
    Write-Host "Scanning process execution history..." -ForegroundColor Cyan
    $procAct = Invoke-NirTool "ProcessActivityView" -TimeoutSec 45
    $Data.ProcessActivityView = @($procAct)
}

# ── PRIVACY-SENSITIVE TOOLS (require explicit opt-in) ──
if ($IncludeLastActivity -or $AutoRunAll) {
    if (Test-NirTool "LastActivityView") {
        Write-Host "Scanning recent system activity (opted in)..." -ForegroundColor Yellow
        $lastAct = Invoke-NirTool "LastActivityView" -TimeoutSec 45
        $Data.LastActivityView = @($lastAct)
    }
}

if ($IncludeBrowserHistory -or $AutoRunAll) {
    if (Test-NirTool "BrowserDownloadsView") {
        Write-Host "Scanning browser downloads (opted in)..." -ForegroundColor Yellow
        $bDl = Invoke-NirTool "BrowserDownloadsView"
        $Data.BrowserDownloadsView = @($bDl)
    }
    if (Test-NirTool "BrowserHistoryView") {
        Write-Host "Scanning browser history (opted in)..." -ForegroundColor Yellow
        $bHist = Invoke-NirTool "BrowserHistoryView"
        $Data.BrowserHistoryView = @($bHist)
    }
}

# ── SCORING ──
if ($score -lt 0) { $score = 0 }
$grade = if ($score -ge 90) { "A" }
    elseif ($score -ge 80) { "B" }
    elseif ($score -ge 70) { "C" }
    elseif ($score -ge 60) { "D" }
    else { "F" }

$Data.Score = $score
$Data.Grade = $grade
$Data.Issues = @($issues)
$Data.Recommendations = @($recommendations)

# ── JSON EXPORT ──
$Data | ConvertTo-Json -Depth 8 | Set-Content -Path $JsonFile -Encoding UTF8

# ── HTML REPORT ──
Write-Host ""
Write-Host "Generating branded HTML report..." -ForegroundColor Cyan

function Build-TableHtml {
    param($DataArray, [int]$MaxRows = 100, [string[]]$Columns = @())
    if (-not $DataArray -or @($DataArray).Count -eq 0) { return "<p style='color:#64748b;font-style:italic;'>No data collected or tool not available.</p>" }

    $rows = @($DataArray) | Select-Object -First $MaxRows
    if ($Columns.Count -eq 0) {
        $Columns = @($rows[0].PSObject.Properties.Name | Select-Object -First 10)
    }

    $sb = [System.Text.StringBuilder]::new()
    $null = $sb.Append("<div style='overflow-x:auto;'><table><tr>")
    foreach ($c in $Columns) { $null = $sb.Append("<th>$c</th>") }
    $null = $sb.Append("</tr>")

    foreach ($row in $rows) {
        $null = $sb.Append("<tr>")
        foreach ($c in $Columns) {
            $val = $row.$c
            if ($null -eq $val) { $val = "" }
            $val = [System.Web.HttpUtility]::HtmlEncode("$val")
            if ($val.Length -gt 120) { $val = $val.Substring(0,117) + "..." }
            $null = $sb.Append("<td>$val</td>")
        }
        $null = $sb.Append("</tr>")
    }
    $null = $sb.Append("</table></div>")
    if (@($DataArray).Count -gt $MaxRows) {
        $null = $sb.Append("<p style='color:#64748b;font-size:12px;'>Showing $MaxRows of $(@($DataArray).Count) records. See CSV for full data.</p>")
    }
    return $sb.ToString()
}

$scoreColor = if ($score -ge 80) { "#16a34a" } elseif ($score -ge 60) { "#f59e0b" } else { "#dc2626" }

$issueListHtml = if ($issues.Count -gt 0) {
    ($issues | ForEach-Object { "<li style='margin-bottom:6px;'>$_</li>" }) -join "`n"
} else {
    "<li style='color:#16a34a;'>No significant issues detected from NirSoft analysis.</li>"
}

$recListHtml = if ($recommendations.Count -gt 0) {
    ($recommendations | ForEach-Object { "<li style='margin-bottom:6px;'>$_</li>" }) -join "`n"
} else {
    "<li style='color:#16a34a;'>System looks healthy. Continue regular maintenance.</li>"
}

$toolStatusHtml = ""
foreach ($t in $allTools) {
    $status = if ($t.Available) { "<span style='color:#16a34a;font-weight:700;'>AVAILABLE</span>" } else { "<span style='color:#94a3b8;'>Not installed</span>" }
    $toolStatusHtml += "<tr><td>$($t.Name)</td><td>$($t.Desc)</td><td>$($t.Category)</td><td>$($t.Priority)</td><td>$status</td></tr>`n"
}

# Build sections
$sections = ""

if ($Data.BlueScreenView -and @($Data.BlueScreenView).Count -gt 0) {
    $bsodTable = Build-TableHtml $Data.BlueScreenView -Columns @("Dump File","Bug Check String","Bug Check Code","Caused By Driver","Caused By Address","Crash Time")
    $bsodCount = @($Data.BlueScreenView).Count
    $bsodBadge = if ($bsodCount -eq 0) { "<span class='badge pass'>No Crashes</span>" } elseif ($bsodCount -lt 3) { "<span class='badge warn'>$bsodCount Crash(es)</span>" } else { "<span class='badge fail'>$bsodCount Crashes</span>" }
    $sections += @"
<div class="card">
    <h2>Blue Screen (BSOD) Analysis $bsodBadge</h2>
    <p>Analyzed Windows minidump files for Blue Screen of Death crash events.</p>
    $bsodTable
</div>
"@
}

if ($Data.CurrPorts -and @($Data.CurrPorts).Count -gt 0) {
    $portsTable = Build-TableHtml $Data.CurrPorts -MaxRows 50 -Columns @("Process Name","Process ID","Protocol","Local Port","Local Address","Remote Address","Remote Port","State","Remote Host Name")
    $sections += @"
<div class="card">
    <h2>Active Network Connections (Security)</h2>
    <p>All active TCP/UDP connections with owning process. Review for unauthorized or suspicious connections.</p>
    $portsTable
</div>
"@
}

if ($Data.USBDeview -and @($Data.USBDeview).Count -gt 0) {
    $usbTable = Build-TableHtml $Data.USBDeview -MaxRows 50 -Columns @("Device Name","Description","Device Type","Connected","Safe To Unplug","Serial Number","Last Plug/Unplug Date","Vendor ID","Product ID")
    $sections += @"
<div class="card">
    <h2>USB Device History</h2>
    <p>Complete history of all USB devices ever connected to this computer.</p>
    $usbTable
</div>
"@
}

if ($Data.BatteryInfoView -and @($Data.BatteryInfoView).Count -gt 0) {
    $battTable = Build-TableHtml $Data.BatteryInfoView -Columns @("Battery Name","Manufacture Name","Serial Number","Designed Capacity","Full Charged Capacity","Current Capacity","Voltage","Charge/Discharge Rate","Wear Level","Power State","Chemistry")
    $sections += @"
<div class="card">
    <h2>Battery Health (NirSoft)</h2>
    <p>Detailed battery health from BatteryInfoView sensor data.</p>
    $battTable
</div>
"@
}

if ($Data.WhatInStartup -and @($Data.WhatInStartup).Count -gt 0) {
    $startTable = Build-TableHtml $Data.WhatInStartup -MaxRows 60 -Columns @("Startup Name","Command","Location","Disabled","Company","Product Name","File Version")
    $enabledCount = @($Data.WhatInStartup | Where-Object { $_.'Disabled' -ne 'Yes' }).Count
    $sections += @"
<div class="card">
    <h2>Startup Items ($enabledCount active)</h2>
    <p>Programs that run at Windows startup. Excessive startup items cause slow boot times.</p>
    $startTable
</div>
"@
}

if ($Data.InstalledDriversList -and @($Data.InstalledDriversList).Count -gt 0) {
    $drvTable = Build-TableHtml $Data.InstalledDriversList -MaxRows 80 -Columns @("Driver Name","Display Name","Description","Driver Type","Start Type","Driver Filename","Company","File Version","Signed")
    $sections += @"
<div class="card">
    <h2>Installed Drivers Audit</h2>
    <p>All installed drivers with signature and version information. Unsigned drivers may indicate security risks.</p>
    $drvTable
</div>
"@
}

if ($Data.DriverView -and @($Data.DriverView).Count -gt 0) {
    $drvViewTable = Build-TableHtml $Data.DriverView -MaxRows 80 -Columns @("Driver Name","Address","Size","Company","Product Name","File Version","Creation Time","Load Order")
    $sections += @"
<div class="card">
    <h2>Loaded Kernel Drivers</h2>
    <p>Currently loaded kernel-mode drivers. Unusual drivers may indicate malware or instability.</p>
    $drvViewTable
</div>
"@
}

if ($Data.WinCrashReport -and @($Data.WinCrashReport).Count -gt 0) {
    $crashTable = Build-TableHtml $Data.WinCrashReport -MaxRows 30 -Columns @("Application Name","Version","Module Name","Exception Code","Exception Description","Time Stamp","Crash File")
    $sections += @"
<div class="card">
    <h2>Application Crash Reports</h2>
    <p>Recent application crashes and error reports from Windows Error Reporting.</p>
    $crashTable
</div>
"@
}

if ($Data.WifiInfoView -and @($Data.WifiInfoView).Count -gt 0) {
    $wifiTable = Build-TableHtml $Data.WifiInfoView -MaxRows 30 -Columns @("SSID","MAC Address","PHY Type","RSSI","Signal Quality","Frequency","Channel","Security","Cipher","Authentication","Company")
    $sections += @"
<div class="card">
    <h2>Wi-Fi Network Analysis</h2>
    <p>Detailed Wi-Fi network information including signal quality and channel usage.</p>
    $wifiTable
</div>
"@
}

if ($Data.ProduKey -and @($Data.ProduKey).Count -gt 0) {
    $keyTable = Build-TableHtml $Data.ProduKey -Columns @("Product Name","Product ID","Product Key","Install Folder")
    $sections += @"
<div class="card">
    <h2>License Keys</h2>
    <p>Windows and Office product keys recovered for documentation.</p>
    $keyTable
</div>
"@
}

if ($Data.WirelessNetView -and @($Data.WirelessNetView).Count -gt 0) {
    $wnetTable = Build-TableHtml $Data.WirelessNetView -MaxRows 30 -Columns @("SSID","Last Signal Quality","Security","Cipher","MAC Address","RSSI","Channel Frequency","Router Vendor","First Detected On","Last Detected On")
    $sections += @"
<div class="card">
    <h2>Nearby Wireless Networks</h2>
    <p>All Wi-Fi networks detected in range. Useful for channel optimization.</p>
    $wnetTable
</div>
"@
}

if ($Data.DNSDataView -and @($Data.DNSDataView).Count -gt 0) {
    $dnsTable = Build-TableHtml $Data.DNSDataView -MaxRows 50 -Columns @("Host Name","IP Address","Record Type","Data Length","TTL","Flags")
    $sections += @"
<div class="card">
    <h2>DNS Cache Analysis</h2>
    <p>Current DNS resolver cache. Suspicious domains may indicate malware C2 communication.</p>
    $dnsTable
</div>
"@
}

if ($Data.OpenedFilesView -and @($Data.OpenedFilesView).Count -gt 0) {
    $openTable = Build-TableHtml $Data.OpenedFilesView -MaxRows 50 -Columns @("Filename","Process Name","Process ID","Handle","Read Access","Write Access","File Position","File Size")
    $sections += @"
<div class="card">
    <h2>Currently Locked Files</h2>
    <p>Files currently held open by processes. Useful for troubleshooting backup and QuickBooks issues.</p>
    $openTable
</div>
"@
}

if ($Data.LastActivityView -and @($Data.LastActivityView).Count -gt 0) {
    $lastActTable = Build-TableHtml $Data.LastActivityView -MaxRows 50 -Columns @("Action Time","Description","Filename","Full Path","More Information","File Extension","Data Source")
    $sections += @"
<div class="card">
    <h2>Recent System Activity (Customer Consent Required)</h2>
    <p>Timeline of recent system activity including file access and logins.</p>
    $lastActTable
</div>
"@
}

if ($Data.BrowserDownloadsView -and @($Data.BrowserDownloadsView).Count -gt 0) {
    $dlTable = Build-TableHtml $Data.BrowserDownloadsView -MaxRows 30 -Columns @("Filename","URL","Web Browser","Download Time","File Size","MIME Type")
    $sections += @"
<div class="card">
    <h2>Browser Downloads (Customer Consent Required)</h2>
    <p>Recent browser downloads. May help identify malware sources.</p>
    $dlTable
</div>
"@
}

$html = @"
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<title>PC Plus 360 NirSoft Advanced Diagnostics Report</title>
<style>
body{font-family:'Segoe UI',Arial,sans-serif;background:#f3f8fb;margin:0;color:#163247}
.header{background:linear-gradient(135deg,#0d4b71,#2596be);color:white;padding:30px 34px}
.header h1{margin:0;font-size:28px}
.header p{margin:8px 0 0 0;font-size:14px;opacity:0.9}
.container{padding:24px;max-width:1200px;margin:0 auto}
.card{background:white;border-radius:14px;padding:22px;margin-bottom:18px;box-shadow:0 6px 18px rgba(13,75,113,.1)}
.card h2{margin:0 0 12px 0;color:#0d4b71;font-size:18px;border-bottom:2px solid #e2e8f0;padding-bottom:8px}
.grid{display:grid;grid-template-columns:repeat(4,1fr);gap:14px}
.metric{background:#eaf7fc;border-left:5px solid #2596be;border-radius:10px;padding:14px}
.metric b{display:block;color:#0d4b71;font-size:11px;text-transform:uppercase;margin-bottom:4px}
.metric span{font-size:20px;font-weight:700}
.score-circle{width:100px;height:100px;border-radius:50%;display:flex;align-items:center;justify-content:center;font-size:36px;font-weight:800;color:white;background:$scoreColor;margin:10px 0}
table{width:100%;border-collapse:collapse;font-size:12px}
th{background:#0d4b71;color:white;padding:8px 10px;text-align:left;font-size:11px;white-space:nowrap}
td{border-bottom:1px solid #e2e8f0;padding:7px 10px;vertical-align:top;max-width:300px;overflow:hidden;text-overflow:ellipsis}
tr:nth-child(even){background:#f8fafc}
tr:hover{background:#eaf7fc}
.badge{display:inline-block;padding:4px 10px;border-radius:999px;font-weight:700;font-size:12px;margin-left:8px}
.pass{background:#dcfce7;color:#16a34a}
.warn{background:#fef3c7;color:#d97706}
.fail{background:#fee2e2;color:#dc2626}
.footer{text-align:center;padding:20px;color:#64748b;font-size:12px;border-top:1px solid #e2e8f0;margin-top:20px}
@media print{.card{break-inside:avoid;box-shadow:none;border:1px solid #e2e8f0} .header{print-color-adjust:exact;-webkit-print-color-adjust:exact}}
</style>
</head>
<body>
<div class="header">
    <h1>PC Plus 360 - NirSoft Advanced Diagnostics Report</h1>
    <p>PC Plus Computing | 604-760-1662 | 236-500-2700 | pcpluscomputing.com | Your Security, Our Priority</p>
</div>

<div class="container">
    <div class="card">
        <h2>Executive Summary</h2>
        <div style="display:flex;align-items:center;gap:30px;">
            <div class="score-circle">$score</div>
            <div>
                <div style="font-size:24px;font-weight:700;color:$scoreColor;">Grade: $grade</div>
                <div style="color:#64748b;margin-top:4px;">$($available.Count) of $($allTools.Count) NirSoft tools scanned</div>
            </div>
        </div>
        <div class="grid" style="margin-top:16px;">
            <div class="metric"><b>Customer</b><span>$CustomerName</span></div>
            <div class="metric"><b>Technician</b><span>$TechnicianName</span></div>
            <div class="metric"><b>Computer</b><span>$($env:COMPUTERNAME)</span></div>
            <div class="metric"><b>Scan Date</b><span>$(Get-Date -Format "MMM dd, yyyy")</span></div>
        </div>
    </div>

    <div class="card">
        <h2>Key Findings</h2>
        <ul style="padding-left:20px;">$issueListHtml</ul>
        <h3 style="margin-top:16px;color:#0d4b71;">Recommendations</h3>
        <ul style="padding-left:20px;">$recListHtml</ul>
    </div>

    <div class="card">
        <h2>Tool Availability</h2>
        <table>
            <tr><th>Tool</th><th>Description</th><th>Category</th><th>Priority</th><th>Status</th></tr>
            $toolStatusHtml
        </table>
    </div>

    $sections

</div>

<div class="footer">
    <p>PC Plus Computing | 30+ Years in Service | 4.9 Google Rating | #1 Best Rated in Surrey</p>
    <p style="font-size:11px;color:#94a3b8;">Generated by PC Plus 360 NirSoft Suite | $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")</p>
</div>
</body>
</html>
"@

Add-Type -AssemblyName System.Web -ErrorAction SilentlyContinue
Set-Content -Path $HtmlFile -Value $html -Encoding UTF8

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  PC Plus 360 NirSoft Scan Complete" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "Score: $score/100 (Grade: $grade)" -ForegroundColor $(if ($score -ge 80) { "Green" } elseif ($score -ge 60) { "Yellow" } else { "Red" })
Write-Host ""
Write-Host "Report Folder: $ReportDir" -ForegroundColor White
Write-Host "HTML Report:   $HtmlFile" -ForegroundColor White
Write-Host "JSON Data:     $JsonFile" -ForegroundColor White
Write-Host "Log File:      $LogFile" -ForegroundColor White

if ($issues.Count -gt 0) {
    Write-Host ""
    Write-Host "Issues Found:" -ForegroundColor Yellow
    foreach ($i in $issues) { Write-Host "  - $i" -ForegroundColor Yellow }
}

Write-Host ""

try {
    Start-Process $HtmlFile
} catch {}

Write-NirLog "NirSoft Suite scan completed. Score: $score/100"
pause

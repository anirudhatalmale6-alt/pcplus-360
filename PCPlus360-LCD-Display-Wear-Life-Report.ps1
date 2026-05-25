<#
PC Plus 360 - LCD / Display Wear & Approximate Life Report
Company: PC Plus Computing
Website: pcpluscomputing.com
Phone: 604-760-1662

Purpose:
Creates a display/LCD wear and approximate life report for laptops/desktops.

What it checks:
- Monitor/panel EDID model and serial where Windows exposes it
- Current resolution and refresh rate
- Brightness support and current brightness where available
- HDR / display adapter details where available
- Display/GPU driver age
- Display driver reset/crash history
- Display disconnect/reconnect style events
- Thermal correlation risk
- Dead pixel / burn-in / color test page generator
- Interactive burn-in detection test (WinForms fullscreen color screens with technician rating)
- Webcam detection and status (device name, driver version, enabled/disabled)
- Touchscreen detection (digitizer status, max touch points, Windows touch features)
- Manual technician checklist for LCD condition
- Enhanced display health scoring (0-100 with color depth, HDR, webcam, touch, burn-in factors)
- Optional JSON export for ReportCard integration (-JsonOutput switch)

Important:
Windows cannot directly read exact LCD backlight hours or true panel remaining life.
This report estimates LCD health using available system age, display events, GPU/display stability,
brightness support, thermal indicators, and technician/manual visual test results.

Run:
PowerShell.exe -ExecutionPolicy Bypass -File .\PCPlus360-LCD-Display-Wear-Life-Report.ps1 -OpenReport

Optional:
PowerShell.exe -ExecutionPolicy Bypass -File .\PCPlus360-LCD-Display-Wear-Life-Report.ps1 -CustomerName "Customer Name" -TechnicianName "Paul" -OpenReport
PowerShell.exe -ExecutionPolicy Bypass -File .\PCPlus360-LCD-Display-Wear-Life-Report.ps1 -CustomerName "Customer Name" -TechnicianName "Paul" -OpenReport -JsonOutput
#>

param(
    [string]$CustomerName = "Customer",
    [string]$TechnicianName = "PC Plus Technician",
    [switch]$OpenReport,
    [switch]$CreateVisualTestOnly,
    [switch]$JsonOutput
)

$ErrorActionPreference = "Continue"

$BaseDir = "C:\PCPlus360\DisplayWearReports"
$TimeStamp = Get-Date -Format "yyyyMMdd-HHmmss"
$ComputerSafe = $env:COMPUTERNAME -replace '[^\w\-]', '_'
$ReportDir = Join-Path $BaseDir "$ComputerSafe-$TimeStamp"
New-Item -ItemType Directory -Path $ReportDir -Force | Out-Null

$LogFile  = Join-Path $ReportDir "PCPlus360-DisplayWear-Log.txt"
$JsonFile = Join-Path $ReportDir "PCPlus360-DisplayWear-RawData.json"
$HtmlFile = Join-Path $ReportDir "PCPlus360-DisplayWear-Report.html"
$TxtFile  = Join-Path $ReportDir "PCPlus360-DisplayWear-Summary.txt"
$CsvFile  = Join-Path $ReportDir "PCPlus360-DisplayWear-Summary.csv"
$VisualTestFile = Join-Path $ReportDir "PCPlus360-LCD-Visual-Test.html"

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

function Convert-BytesToGB {
    param([double]$Bytes)
    if ($null -eq $Bytes) { return $null }
    return [math]::Round($Bytes / 1GB, 2)
}

function Get-GradeFromScore {
    param([int]$Score)
    if ($Score -ge 90) { "A - Excellent" }
    elseif ($Score -ge 80) { "B - Good" }
    elseif ($Score -ge 70) { "C - Fair" }
    elseif ($Score -ge 60) { "D - Needs Attention" }
    else { "F - Critical" }
}

function Get-RiskFromScore {
    param([int]$Score)
    if ($Score -ge 85) { "Low" }
    elseif ($Score -ge 70) { "Moderate" }
    elseif ($Score -ge 55) { "High" }
    else { "Critical" }
}

function Get-LifeTextFromScore {
    param([int]$Score)
    if ($Score -ge 90) { "3-5+ years estimated comfortable display use" }
    elseif ($Score -ge 80) { "2-4 years estimated comfortable display use" }
    elseif ($Score -ge 70) { "1-3 years estimated comfortable display use; monitor condition should be reviewed" }
    elseif ($Score -ge 60) { "6-18 months estimated comfortable use if symptoms are present; service/replacement planning recommended" }
    else { "Immediate display inspection or replacement recommended" }
}

function New-Finding {
    param([string]$Category,[string]$Severity,[string]$Finding,[string]$Recommendation)
    [PSCustomObject]@{Category=$Category;Severity=$Severity;Finding=$Finding;Recommendation=$Recommendation}
}

function Convert-EdidString {
    param($CharArray)
    try {
        if (-not $CharArray) { return $null }
        $s = -join ($CharArray | ForEach-Object { if ($_ -gt 0) { [char]$_ } })
        return $s.Trim()
    } catch {
        return $null
    }
}

function Get-PCPlusSystemInfo {
    Write-PCLog "Collecting system information."
    $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
    $bios = Get-CimInstance Win32_BIOS -ErrorAction SilentlyContinue
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    $cpu = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1

    $biosDate = $null
    try { $biosDate = [Management.ManagementDateTimeConverter]::ToDateTime($bios.ReleaseDate) } catch {}
    $biosAgeYears = if ($biosDate) { [math]::Round(((Get-Date) - $biosDate).TotalDays / 365.25, 1) } else { $null }

    [PSCustomObject]@{
        CustomerName=$CustomerName
        TechnicianName=$TechnicianName
        ComputerName=$env:COMPUTERNAME
        Manufacturer=$cs.Manufacturer
        Model=$cs.Model
        SerialNumber=$bios.SerialNumber
        BIOSVersion=$bios.SMBIOSBIOSVersion
        BIOSDate=$biosDate
        BIOSAgeYears=$biosAgeYears
        OS=$os.Caption
        OSBuild=$os.BuildNumber
        LastBoot=$os.LastBootUpTime
        UptimeHours=[math]::Round(((Get-Date)-$os.LastBootUpTime).TotalHours,2)
        CPU=$cpu.Name
        RAMGB=Convert-BytesToGB $cs.TotalPhysicalMemory
        IsLaptop=($cs.PCSystemType -eq 2 -or $cs.PCSystemTypeEx -eq 2)
        ReportDate=Get-Date
    }
}

function Get-PCPlusMonitorInfo {
    Write-PCLog "Collecting monitor / LCD EDID information."

    $monitors = @()
    try {
        $ids = @(Get-CimInstance WmiMonitorID -Namespace root\wmi -ErrorAction SilentlyContinue)
        foreach ($m in $ids) {
            $monitors += [PSCustomObject]@{
                InstanceName=$m.InstanceName
                ManufacturerName=Convert-EdidString $m.ManufacturerName
                ProductCodeID=Convert-EdidString $m.ProductCodeID
                SerialNumberID=Convert-EdidString $m.SerialNumberID
                UserFriendlyName=Convert-EdidString $m.UserFriendlyName
                WeekOfManufacture=$m.WeekOfManufacture
                YearOfManufacture=$m.YearOfManufacture
                Active=$m.Active
            }
        }
    } catch {}

    $desktopMonitors = @()
    try {
        $desktopMonitors = @(Get-CimInstance Win32_DesktopMonitor -ErrorAction SilentlyContinue |
            Select-Object Name, ScreenHeight, ScreenWidth, MonitorManufacturer, MonitorType, Status, PNPDeviceID)
    } catch {}

    [PSCustomObject]@{
        WmiMonitorID=$monitors
        DesktopMonitor=$desktopMonitors
        MonitorCount=[math]::Max($monitors.Count,$desktopMonitors.Count)
    }
}

function Get-PCPlusDisplayAdapterInfo {
    Write-PCLog "Collecting display adapter / resolution information."

    $gpus = @(Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | ForEach-Object {
        $driverDate = $null
        try { $driverDate = [Management.ManagementDateTimeConverter]::ToDateTime($_.DriverDate) } catch {}
        $driverAgeYears = if ($driverDate) { [math]::Round(((Get-Date)-$driverDate).TotalDays/365.25,1) } else { $null }

        [PSCustomObject]@{
            Name=$_.Name
            VideoProcessor=$_.VideoProcessor
            AdapterRAMGB=Convert-BytesToGB $_.AdapterRAM
            DriverVersion=$_.DriverVersion
            DriverDate=$driverDate
            DriverAgeYears=$driverAgeYears
            CurrentHorizontalResolution=$_.CurrentHorizontalResolution
            CurrentVerticalResolution=$_.CurrentVerticalResolution
            CurrentRefreshRate=$_.CurrentRefreshRate
            MaxRefreshRate=$_.MaxRefreshRate
            MinRefreshRate=$_.MinRefreshRate
            VideoModeDescription=$_.VideoModeDescription
            Status=$_.Status
        }
    })

    [PSCustomObject]@{
        GPUs=$gpus
        PrimaryResolution=($gpus | Select-Object -First 1).VideoModeDescription
    }
}

function Get-PCPlusBrightnessInfo {
    Write-PCLog "Collecting brightness information."

    $brightness = @()
    $methods = @()
    try {
        $brightness = @(Get-CimInstance WmiMonitorBrightness -Namespace root\wmi -ErrorAction SilentlyContinue |
            Select-Object InstanceName, Active, CurrentBrightness, Level)
    } catch {}

    try {
        $methods = @(Get-CimInstance WmiMonitorBrightnessMethods -Namespace root\wmi -ErrorAction SilentlyContinue |
            Select-Object InstanceName, Active)
    } catch {}

    [PSCustomObject]@{
        BrightnessSupported=($brightness.Count -gt 0)
        CurrentBrightness=if($brightness.Count -gt 0){($brightness|Select-Object -First 1).CurrentBrightness}else{$null}
        BrightnessRecords=$brightness
        BrightnessMethods=$methods
        Notes="Windows usually reports brightness percentage, not actual panel nits. A colorimeter/light meter is required for true brightness wear measurement."
    }
}

function Get-PCPlusDisplayEvents {
    Write-PCLog "Collecting display/GPU/cable stability event history."

    $start = (Get-Date).AddDays(-180)
    $events = @()

    try {
        $events = @(Get-WinEvent -FilterHashtable @{LogName='System'; StartTime=$start} -MaxEvents 2000 -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Message -match "display driver|nvlddmkm|amdkmdag|igfx|video hardware|LiveKernelEvent|monitor|display|graphics|TDR|stopped responding|recovered"
            } |
            Select-Object TimeCreated, ProviderName, Id, LevelDisplayName, Message -First 80)
    } catch {}

    $summary = [PSCustomObject]@{
        DaysChecked=180
        EventCount=$events.Count
        RecentEvents=@($events | Sort-Object TimeCreated -Descending | Select-Object -First 20)
        DriverResetCount=@($events | Where-Object {$_.Message -match "stopped responding|recovered|TDR|display driver"}).Count
        PossibleCableReconnectCount=@($events | Where-Object {$_.Message -match "monitor|display.*disconnect|display.*connect|graphics"}).Count
    }

    return $summary
}

function Get-PCPlusThermalCorrelation {
    Write-PCLog "Collecting thermal correlation risk."

    $thermalEvents=@()
    try {
        $thermalEvents = @(Get-WinEvent -FilterHashtable @{LogName='System'; StartTime=(Get-Date).AddDays(-180)} -MaxEvents 2000 -ErrorAction SilentlyContinue |
            Where-Object { $_.Message -match "thermal|overheat|temperature|throttl" } |
            Select-Object TimeCreated, ProviderName, Id, LevelDisplayName, Message -First 40)
    } catch {}

    $thermalZones=@()
    try {
        $thermalZones = @(Get-CimInstance MSAcpi_ThermalZoneTemperature -Namespace root\wmi -ErrorAction SilentlyContinue | ForEach-Object {
            [PSCustomObject]@{InstanceName=$_.InstanceName;TemperatureC=[math]::Round(($_.CurrentTemperature/10)-273.15,1)}
        })
    } catch {}

    [PSCustomObject]@{
        ThermalEventCount=$thermalEvents.Count
        ThermalEvents=$thermalEvents
        ThermalZones=$thermalZones
        MaxReportedTemperatureC=if($thermalZones.Count -gt 0){($thermalZones|Measure-Object TemperatureC -Maximum).Maximum}else{$null}
        Notes="High internal heat can age LCD backlight, eDP/LVDS cable, adhesives, and display electronics faster."
    }
}

function Get-PCPlusWebcamInfo {
    Write-PCLog "Detecting webcam devices."

    $webcams = @()
    try {
        # Check PnP devices for camera/webcam/imaging devices
        $pnpDevices = @(Get-CimInstance Win32_PnPEntity -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Caption -match 'camera|webcam|imaging|video capture|IR camera|integrated camera' -or
                $_.PNPClass -eq 'Camera' -or $_.PNPClass -eq 'Image'
            })
        foreach ($dev in $pnpDevices) {
            $driverVer = $null
            try {
                $driverInfo = Get-CimInstance Win32_PnPSignedDriver -Filter "DeviceID='$($dev.DeviceID -replace "\\","\\\\")'" -ErrorAction SilentlyContinue
                if ($driverInfo) { $driverVer = $driverInfo.DriverVersion }
            } catch {}

            $webcams += [PSCustomObject]@{
                DeviceName    = $dev.Caption
                Status        = $dev.Status
                DeviceID      = $dev.DeviceID
                PNPClass      = $dev.PNPClass
                Manufacturer  = $dev.Manufacturer
                DriverVersion = $driverVer
                IsEnabled     = ($dev.Status -eq 'OK')
            }
        }
    } catch {
        Write-PCLog "Webcam detection error: $_" "WARN"
    }

    [PSCustomObject]@{
        WebcamDetected = ($webcams.Count -gt 0)
        WebcamCount    = $webcams.Count
        Webcams        = $webcams
    }
}

function Get-PCPlusTouchscreenInfo {
    Write-PCLog "Detecting touchscreen capability."

    $touchDevices = @()
    try {
        $pnpDevices = @(Get-CimInstance Win32_PnPEntity -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Caption -match 'touch screen|touch digitizer|touch controller|HID-compliant touch' -or
                $_.Caption -match 'touch pad' -eq $false -and $_.Caption -match 'touch'
            })
        foreach ($dev in $pnpDevices) {
            # Skip touchpads - we only want touchscreens
            if ($dev.Caption -match 'touchpad|track ?pad|synaptics.*pad|elan.*pad') { continue }
            $touchDevices += [PSCustomObject]@{
                DeviceName = $dev.Caption
                Status     = $dev.Status
                DeviceID   = $dev.DeviceID
                PNPClass   = $dev.PNPClass
                IsEnabled  = ($dev.Status -eq 'OK')
            }
        }
    } catch {
        Write-PCLog "Touchscreen detection error: $_" "WARN"
    }

    # Check max touch points via SM_MAXIMUMTOUCHES (SM index 95)
    $maxTouchPoints = $null
    try {
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class TouchInfo {
    [DllImport("user32.dll")]
    public static extern int GetSystemMetrics(int nIndex);
    public static int GetMaxTouchPoints() { return GetSystemMetrics(95); }
}
"@ -ErrorAction SilentlyContinue
        $maxTouchPoints = [TouchInfo]::GetMaxTouchPoints()
    } catch {
        Write-PCLog "Could not query touch points: $_" "WARN"
    }

    # Check if Windows touch/tablet features are enabled
    $touchEnabled = $false
    try {
        # SM_DIGITIZER = 94
        $digitizerFlags = [TouchInfo]::GetSystemMetrics(94)
        # Bit 0x01 = integrated touch, 0x02 = external touch, 0x40 = touch ready
        $touchEnabled = ($digitizerFlags -band 0x41) -ne 0
    } catch {}

    [PSCustomObject]@{
        TouchscreenDetected = ($touchDevices.Count -gt 0)
        TouchDeviceCount    = $touchDevices.Count
        TouchDevices        = $touchDevices
        MaxTouchPoints      = $maxTouchPoints
        TouchEnabled        = $touchEnabled
        Notes               = if ($touchDevices.Count -eq 0) { "No touchscreen digitizer detected." } else { "Touchscreen hardware found. Max touch points: $maxTouchPoints" }
    }
}

function Invoke-PCPlusBurnInTest {
    Write-PCLog "Starting interactive burn-in detection test (WinForms)."

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $colors = @(
        @{ Name = "RED";   Color = [System.Drawing.Color]::Red;       FG = [System.Drawing.Color]::White },
        @{ Name = "GREEN"; Color = [System.Drawing.Color]::Lime;      FG = [System.Drawing.Color]::Black },
        @{ Name = "BLUE";  Color = [System.Drawing.Color]::Blue;      FG = [System.Drawing.Color]::White },
        @{ Name = "WHITE"; Color = [System.Drawing.Color]::White;     FG = [System.Drawing.Color]::Black },
        @{ Name = "BLACK"; Color = [System.Drawing.Color]::Black;     FG = [System.Drawing.Color]::White },
        @{ Name = "GRAY";  Color = [System.Drawing.Color]::Gray;      FG = [System.Drawing.Color]::White }
    )

    $totalColors = $colors.Count
    $displaySeconds = 3

    # Show each color fullscreen for $displaySeconds seconds
    foreach ($colorDef in $colors) {
        $form = New-Object System.Windows.Forms.Form
        $form.Text = "PC Plus Computing 360 - Burn-In Test"
        $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
        $form.WindowState = [System.Windows.Forms.FormWindowState]::Maximized
        $form.TopMost = $true
        $form.BackColor = $colorDef.Color
        $form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen

        $label = New-Object System.Windows.Forms.Label
        $label.Text = "$($colorDef.Name) SCREEN`r`n`r`nLook for uneven brightness, dark spots, or color bleeding"
        $label.ForeColor = $colorDef.FG
        $label.BackColor = [System.Drawing.Color]::FromArgb(120, 0, 0, 0)
        if ($colorDef.Name -eq "BLACK") {
            $label.BackColor = [System.Drawing.Color]::FromArgb(80, 255, 255, 255)
        }
        $label.Font = New-Object System.Drawing.Font("Segoe UI", 22, [System.Drawing.FontStyle]::Bold)
        $label.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
        $label.AutoSize = $false
        $label.Size = New-Object System.Drawing.Size(800, 200)

        $form.Add_Shown({
            # Center the label on the form
            $label.Location = New-Object System.Drawing.Point(
                [int](($form.ClientSize.Width - $label.Width) / 2),
                [int](($form.ClientSize.Height - $label.Height) / 2)
            )
        })

        $form.Controls.Add($label)

        # Timer to close after display period
        $timer = New-Object System.Windows.Forms.Timer
        $timer.Interval = $displaySeconds * 1000
        $timer.Add_Tick({ $form.Close() })

        # Allow ESC to close early
        $form.Add_KeyDown({
            if ($_.KeyCode -eq 'Escape') { $form.Close() }
        })

        $form.Add_Shown({ $timer.Start() })
        $form.ShowDialog() | Out-Null
        $timer.Dispose()
        $form.Dispose()
    }

    # Now show the rating dialog
    $ratingForm = New-Object System.Windows.Forms.Form
    $ratingForm.Text = "PC Plus Computing 360 - Burn-In Assessment"
    $ratingForm.Size = New-Object System.Drawing.Size(620, 320)
    $ratingForm.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $ratingForm.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $ratingForm.MaximizeBox = $false
    $ratingForm.MinimizeBox = $false
    $ratingForm.TopMost = $true
    $ratingForm.BackColor = [System.Drawing.ColorTranslator]::FromHtml("#0a1628")
    $ratingForm.ForeColor = [System.Drawing.Color]::White

    $titleLabel = New-Object System.Windows.Forms.Label
    $titleLabel.Text = "PC Plus Computing 360"
    $titleLabel.Font = New-Object System.Drawing.Font("Segoe UI", 16, [System.Drawing.FontStyle]::Bold)
    $titleLabel.ForeColor = [System.Drawing.ColorTranslator]::FromHtml("#2596be")
    $titleLabel.Location = New-Object System.Drawing.Point(30, 20)
    $titleLabel.AutoSize = $true
    $ratingForm.Controls.Add($titleLabel)

    $questionLabel = New-Object System.Windows.Forms.Label
    $questionLabel.Text = "Did you notice any burn-in, dead pixels, or uneven areas?"
    $questionLabel.Font = New-Object System.Drawing.Font("Segoe UI", 13)
    $questionLabel.ForeColor = [System.Drawing.Color]::White
    $questionLabel.Location = New-Object System.Drawing.Point(30, 70)
    $questionLabel.Size = New-Object System.Drawing.Size(540, 40)
    $ratingForm.Controls.Add($questionLabel)

    $subLabel = New-Object System.Windows.Forms.Label
    $subLabel.Text = "Select the result of your visual inspection:"
    $subLabel.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $subLabel.ForeColor = [System.Drawing.ColorTranslator]::FromHtml("#a0b0c0")
    $subLabel.Location = New-Object System.Drawing.Point(30, 115)
    $subLabel.AutoSize = $true
    $ratingForm.Controls.Add($subLabel)

    $burnInResult = "Unsure"

    $btnYes = New-Object System.Windows.Forms.Button
    $btnYes.Text = "Yes - Issues Found"
    $btnYes.Size = New-Object System.Drawing.Size(160, 50)
    $btnYes.Location = New-Object System.Drawing.Point(30, 160)
    $btnYes.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnYes.BackColor = [System.Drawing.ColorTranslator]::FromHtml("#e74c3c")
    $btnYes.ForeColor = [System.Drawing.Color]::White
    $btnYes.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
    $btnYes.Add_Click({ $script:burnInResult = "Yes"; $ratingForm.Close() })
    $ratingForm.Controls.Add($btnYes)

    $btnNo = New-Object System.Windows.Forms.Button
    $btnNo.Text = "No - Display Clean"
    $btnNo.Size = New-Object System.Drawing.Size(160, 50)
    $btnNo.Location = New-Object System.Drawing.Point(220, 160)
    $btnNo.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnNo.BackColor = [System.Drawing.ColorTranslator]::FromHtml("#27ae60")
    $btnNo.ForeColor = [System.Drawing.Color]::White
    $btnNo.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
    $btnNo.Add_Click({ $script:burnInResult = "No"; $ratingForm.Close() })
    $ratingForm.Controls.Add($btnNo)

    $btnUnsure = New-Object System.Windows.Forms.Button
    $btnUnsure.Text = "Unsure"
    $btnUnsure.Size = New-Object System.Drawing.Size(160, 50)
    $btnUnsure.Location = New-Object System.Drawing.Point(410, 160)
    $btnUnsure.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnUnsure.BackColor = [System.Drawing.ColorTranslator]::FromHtml("#f39c12")
    $btnUnsure.ForeColor = [System.Drawing.Color]::White
    $btnUnsure.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
    $btnUnsure.Add_Click({ $script:burnInResult = "Unsure"; $ratingForm.Close() })
    $ratingForm.Controls.Add($btnUnsure)

    $ratingForm.ShowDialog() | Out-Null
    $ratingForm.Dispose()

    $result = $script:burnInResult
    Write-PCLog "Burn-in test result: $result"

    [PSCustomObject]@{
        TestPerformed    = $true
        BurnInDetected   = $result
        ColorsShown      = ($colors | ForEach-Object { $_.Name })
        DisplaySeconds   = $displaySeconds
        TechnicianRating = $result
        Notes            = switch ($result) {
            "Yes"    { "Technician observed burn-in, dead pixels, or uneven areas during visual test." }
            "No"     { "Display passed visual burn-in and uniformity check. No issues observed." }
            "Unsure" { "Technician was unsure about display condition. Further inspection recommended." }
        }
    }
}

function New-PCPlusVisualDisplayTest {
    Write-PCLog "Creating fullscreen LCD visual test page."

$html = @"
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<title>PC Plus 360 LCD Visual Test</title>
<style>
html,body{margin:0;height:100%;font-family:Segoe UI,Arial,sans-serif;background:#111;color:white;overflow:hidden}
#screen{height:100vh;width:100vw;display:flex;align-items:center;justify-content:center;text-align:center}
.panel{background:rgba(0,0,0,.55);padding:30px;border-radius:18px;max-width:900px}
button{padding:12px 18px;margin:6px;border:0;border-radius:10px;font-weight:700;cursor:pointer}
.small{font-size:14px;opacity:.85}
</style>
</head>
<body>
<div id="screen">
  <div class="panel" id="panel">
    <h1>PC Plus 360 LCD Visual Test</h1>
    <p>Use this test to check dead pixels, stuck pixels, burn-in, backlight bleed, color tint, flicker, and brightness uniformity.</p>
    <p>Press F11 for fullscreen. Use arrow keys or buttons to change test screens.</p>
    <div>
      <button onclick="setTest(0)">White</button>
      <button onclick="setTest(1)">Black</button>
      <button onclick="setTest(2)">Red</button>
      <button onclick="setTest(3)">Green</button>
      <button onclick="setTest(4)">Blue</button>
      <button onclick="setTest(5)">Gray</button>
      <button onclick="setTest(6)">Gradient</button>
      <button onclick="setTest(7)">Grid</button>
      <button onclick="setTest(8)">Text Ghosting</button>
    </div>
    <p class="small">Technician checks: dead/stuck pixels, yellow tint, uneven brightness, edge bleed, ghost image/taskbar burn-in, flicker, hinge angle flicker.</p>
  </div>
</div>
<script>
let idx=0;
const tests=[
 {name:'White',bg:'#fff',fg:'#111',html:'WHITE SCREEN<br><small>Check dark/dead pixels, dirt, pressure marks, uneven brightness.</small>'},
 {name:'Black',bg:'#000',fg:'#fff',html:'BLACK SCREEN<br><small>Check backlight bleed, edge glow, stuck bright pixels.</small>'},
 {name:'Red',bg:'#f00',fg:'#fff',html:'RED SCREEN<br><small>Check stuck/dead subpixels.</small>'},
 {name:'Green',bg:'#0f0',fg:'#111',html:'GREEN SCREEN<br><small>Check stuck/dead subpixels.</small>'},
 {name:'Blue',bg:'#00f',fg:'#fff',html:'BLUE SCREEN<br><small>Check stuck/dead subpixels.</small>'},
 {name:'Gray',bg:'#777',fg:'#fff',html:'GRAY SCREEN<br><small>Check burn-in, image retention, yellow tint, uniformity.</small>'},
 {name:'Gradient',bg:'linear-gradient(90deg,#000,#fff)',fg:'#fff',html:'BRIGHTNESS GRADIENT<br><small>Check banding and uneven brightness.</small>'},
 {name:'Grid',bg:'repeating-linear-gradient(0deg,#fff 0,#fff 1px,#111 1px,#111 40px),repeating-linear-gradient(90deg,transparent 0,transparent 39px,#fff 39px,#fff 40px)',fg:'#0ff',html:'GRID TEST<br><small>Check lines, panel damage, scaling, and geometry.</small>'},
 {name:'Text Ghosting',bg:'#333',fg:'#fff',html:'GHOSTING / BURN-IN TEST<br><br>PC PLUS COMPUTING DISPLAY TEST<br><br><small>Look for old taskbar/icons/window shadows on gray background.</small>'}
];
function setTest(i){
 idx=i; const t=tests[idx]; const s=document.getElementById('screen'); const p=document.getElementById('panel');
 s.style.background=t.bg; s.style.color=t.fg; p.innerHTML='<h1>'+t.html+'</h1><p class="small">Screen '+(idx+1)+' of '+tests.length+' | Use Left/Right arrows | Press F11 fullscreen</p>';
 if(idx>0){p.style.background='rgba(0,0,0,.35)'} else {p.style.background='rgba(255,255,255,.65)'}
}
document.addEventListener('keydown',e=>{if(e.key==='ArrowRight')setTest((idx+1)%tests.length); if(e.key==='ArrowLeft')setTest((idx-1+tests.length)%tests.length);});
</script>
</body>
</html>
"@
    Set-Content -Path $VisualTestFile -Value $html -Encoding UTF8
    return $VisualTestFile
}

function Get-PCPlusDisplayWearScore {
    param($System,$Monitor,$Adapter,$Brightness,$Events,$Thermal,$Webcam,$Touchscreen,$BurnIn)

    $score=100
    $findings=@()

    if ($System.BIOSAgeYears -ne $null) {
        if ($System.BIOSAgeYears -ge 8) {
            $score -= 18
            $findings += New-Finding "Display Age Estimate" "High" "System age is approximately $($System.BIOSAgeYears) years based on BIOS date." "LCD/backlight/cable wear risk is higher on older laptops."
        } elseif ($System.BIOSAgeYears -ge 5) {
            $score -= 10
            $findings += New-Finding "Display Age Estimate" "Moderate" "System age is approximately $($System.BIOSAgeYears) years." "Inspect brightness, uniformity, hinge cable, and panel condition."
        } elseif ($System.BIOSAgeYears -ge 3) {
            $score -= 4
            $findings += New-Finding "Display Age Estimate" "Low" "System age is approximately $($System.BIOSAgeYears) years." "Normal display aging possible."
        }
    }

    foreach ($gpu in $Adapter.GPUs) {
        if ($gpu.DriverAgeYears -ne $null -and $gpu.DriverAgeYears -ge 4) {
            $score -= 5
            $findings += New-Finding "Display Driver Age" "Low" "Graphics driver appears about $($gpu.DriverAgeYears) years old." "Update display driver if flicker, crashes, or monitor issues occur."
        }
        if ($gpu.Status -and $gpu.Status -notmatch "OK") {
            $score -= 15
            $findings += New-Finding "Display Adapter Status" "High" "$($gpu.Name) status is $($gpu.Status)." "Review Device Manager and display driver."
        }
        if ($gpu.CurrentRefreshRate -and $gpu.CurrentRefreshRate -lt 59) {
            $score -= 5
            $findings += New-Finding "Refresh Rate" "Low" "Current refresh rate is $($gpu.CurrentRefreshRate) Hz." "Confirm correct display mode and driver."
        }
    }

    if ($Brightness.BrightnessSupported -eq $false) {
        $findings += New-Finding "Brightness Reading" "Low" "Windows did not expose brightness controls/readings." "This is common on desktops/external monitors. Use visual/light meter testing for backlight wear."
    } elseif ($Brightness.CurrentBrightness -ne $null -and $Brightness.CurrentBrightness -lt 40) {
        $score -= 4
        $findings += New-Finding "Brightness Setting" "Low" "Current brightness is $($Brightness.CurrentBrightness)%." "Low brightness setting is not wear by itself; test maximum brightness visually."
    }

    if ($Events.DriverResetCount -gt 0) {
        $score -= [math]::Min(25, $Events.DriverResetCount * 8)
        $findings += New-Finding "Display Driver Resets" "High" "$($Events.DriverResetCount) display driver reset/recovery event(s) found." "Check GPU driver, GPU health, thermal condition, and display cable symptoms."
    }

    if ($Events.EventCount -gt 10) {
        $score -= 10
        $findings += New-Finding "Display/GPU Events" "Moderate" "$($Events.EventCount) display/GPU-related event(s) found in 180 days." "Review event details and test for flicker, black screen, or driver instability."
    }

    if ($Thermal.ThermalEventCount -gt 0) {
        $score -= 8
        $findings += New-Finding "Thermal Exposure" "Moderate" "$($Thermal.ThermalEventCount) thermal-related event(s) found." "Heat may accelerate LCD backlight, cable, and display electronics wear."
    }

    if ($Thermal.MaxReportedTemperatureC -ne $null -and $Thermal.MaxReportedTemperatureC -ge 85) {
        $score -= 8
        $findings += New-Finding "Heat Risk" "Moderate" "Reported thermal zone reached $($Thermal.MaxReportedTemperatureC) C." "Cooling service recommended if repeated."
    }

    if ($Monitor.MonitorCount -eq 0) {
        $score -= 5
        $findings += New-Finding "Monitor Detection" "Low" "Monitor EDID information was not detected." "Check display driver/monitor detection if display issues exist."
    }

    # Color depth check
    foreach ($gpu in $Adapter.GPUs) {
        if ($gpu.VideoModeDescription -match '(\d+)\s*(?:bit|bpp|colors)') {
            $colorBits = [int]$Matches[1]
            if ($colorBits -lt 32) {
                $score -= 3
                $findings += New-Finding "Color Depth" "Low" "Display running at $colorBits-bit color." "32-bit (True Color) recommended for accurate display testing."
            }
        }
    }

    # HDR support check
    $hdrSupported = $false
    try {
        $hdrKey = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers\MonitorData\*" -ErrorAction SilentlyContinue
        if ($hdrKey) {
            foreach ($prop in $hdrKey.PSObject.Properties) {
                if ($prop.Name -match 'HDR' -and $prop.Value) { $hdrSupported = $true }
            }
        }
    } catch {}
    if (-not $hdrSupported) {
        # Not a penalty, just informational
        $findings += New-Finding "HDR Support" "Info" "HDR display capability not detected or not enabled." "HDR is optional. Modern displays with HDR tend to have better panel quality."
    }

    # Webcam scoring
    if ($null -ne $Webcam) {
        if ($Webcam.WebcamDetected) {
            $allOK = $true
            foreach ($cam in $Webcam.Webcams) {
                if ($cam.Status -ne 'OK') {
                    $allOK = $false
                    $score -= 3
                    $findings += New-Finding "Webcam Status" "Low" "Webcam '$($cam.DeviceName)' status is $($cam.Status)." "Check Device Manager for webcam driver issues."
                }
            }
            if ($allOK) {
                $findings += New-Finding "Webcam" "Info" "$($Webcam.WebcamCount) webcam(s) detected and functional." "Webcam hardware is operational."
            }
        } else {
            if ($System.IsLaptop) {
                $score -= 2
                $findings += New-Finding "Webcam Missing" "Low" "No webcam detected on laptop." "Most laptops should have a built-in webcam. Check if disabled in BIOS/Device Manager."
            }
        }
    }

    # Touchscreen scoring (relevant for laptops / 2-in-1s)
    if ($null -ne $Touchscreen) {
        if ($Touchscreen.TouchscreenDetected) {
            $allTouchOK = $true
            foreach ($td in $Touchscreen.TouchDevices) {
                if ($td.Status -ne 'OK') {
                    $allTouchOK = $false
                    $score -= 3
                    $findings += New-Finding "Touchscreen Status" "Low" "Touch device '$($td.DeviceName)' status is $($td.Status)." "Check touch digitizer in Device Manager."
                }
            }
            if ($allTouchOK) {
                $findings += New-Finding "Touchscreen" "Info" "Touchscreen detected with $($Touchscreen.MaxTouchPoints) touch points." "Touch digitizer is operational."
            }
        }
    }

    # Burn-in test scoring
    if ($null -ne $BurnIn -and $BurnIn.TestPerformed) {
        switch ($BurnIn.BurnInDetected) {
            "Yes" {
                $score -= 15
                $findings += New-Finding "Burn-In Test" "High" "Technician observed burn-in, dead pixels, or uneven areas." "Display panel may need replacement or further professional assessment."
            }
            "Unsure" {
                $score -= 5
                $findings += New-Finding "Burn-In Test" "Moderate" "Technician was unsure about display condition." "Recommend retest in a darker environment or use a dedicated pixel test tool."
            }
            "No" {
                $findings += New-Finding "Burn-In Test" "Info" "Display passed visual burn-in and uniformity check." "No action needed."
            }
        }
    }

    if ($score -lt 0) { $score=0 }

    [PSCustomObject]@{
        Score=$score
        Grade=Get-GradeFromScore $score
        Risk=Get-RiskFromScore $score
        ApproxLife=Get-LifeTextFromScore $score
        Findings=$findings
        ManualVisualTestsRequired=@(
            "Dead/stuck pixel test",
            "Backlight bleed test",
            "Brightness uniformity check",
            "Gray-screen burn-in/image-retention check",
            "Color tint/yellowing check",
            "Hinge angle flicker test",
            "External monitor comparison test",
            "Camera/photo evidence optional"
        )
        Notes="LCD life is an approximation. Exact panel/backlight remaining hours usually cannot be read from Windows."
    }
}

function HtmlEncode {
    param([string]$Text)
    if ($null -eq $Text) { return "" }
    return $Text.Replace("&","&amp;").Replace("<","&lt;").Replace(">","&gt;").Replace('"',"&quot;")
}

function New-PCPlusDisplayHtmlReport {
    param($Data)

    $scoreColor=if($Data.Score.Score -ge 80){"#16a34a"}elseif($Data.Score.Score -ge 60){"#f59e0b"}else{"#dc2626"}

    $monitorRows=foreach($m in $Data.Monitor.WmiMonitorID){
        "<tr><td>$(HtmlEncode $m.UserFriendlyName)</td><td>$(HtmlEncode $m.ManufacturerName)</td><td>$(HtmlEncode $m.SerialNumberID)</td><td>$($m.YearOfManufacture)</td><td>$($m.Active)</td></tr>"
    }
    if(-not $monitorRows){$monitorRows="<tr><td colspan='5'>No WmiMonitorID EDID records found.</td></tr>"}

    $gpuRows=foreach($g in $Data.Adapter.GPUs){
        "<tr><td>$(HtmlEncode $g.Name)</td><td>$($g.AdapterRAMGB) GB</td><td>$($g.DriverVersion)</td><td>$($g.DriverDate)</td><td>$($g.CurrentHorizontalResolution)x$($g.CurrentVerticalResolution)</td><td>$($g.CurrentRefreshRate) Hz</td><td>$($g.Status)</td></tr>"
    }

    $findingRows=foreach($f in $Data.Score.Findings){
        $class=switch($f.Severity){"Critical"{"fail"}"High"{"fail"}"Moderate"{"warn"}default{"pass"}}
        "<tr><td>$($f.Category)</td><td class='$class'>$($f.Severity)</td><td>$(HtmlEncode $f.Finding)</td><td>$(HtmlEncode $f.Recommendation)</td></tr>"
    }
    if(-not $findingRows){$findingRows="<tr><td colspan='4'>No major display wear indicators detected from Windows data.</td></tr>"}

    $manualRows=foreach($t in $Data.Score.ManualVisualTestsRequired){
        "<tr><td>$t</td><td>Technician visual check required</td></tr>"
    }

    $eventRows=foreach($e in $Data.Events.RecentEvents){
        $msg=HtmlEncode $e.Message
        if($msg.Length -gt 260){$msg=$msg.Substring(0,260)+"..."}
        "<tr><td>$($e.TimeCreated)</td><td>$($e.ProviderName)</td><td>$($e.Id)</td><td>$($e.LevelDisplayName)</td><td>$msg</td></tr>"
    }
    if(-not $eventRows){$eventRows="<tr><td colspan='5'>No recent display/GPU-related events found.</td></tr>"}

$html=@"
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<title>PC Plus 360 LCD / Display Wear Report</title>
<style>
body{font-family:Segoe UI,Arial,sans-serif;background:#f3f8fb;margin:0;color:#163247}
.header{background:linear-gradient(135deg,#0d4b71,#2596be);color:white;padding:34px}
.header h1{margin:0;font-size:34px}.header p{margin:8px 0 0 0;font-size:15px}
.container{padding:24px}.card{background:white;border-radius:16px;padding:22px;margin-bottom:18px;box-shadow:0 8px 22px rgba(13,75,113,.12)}
.grid{display:grid;grid-template-columns:repeat(4,1fr);gap:14px}
.metric{background:#eaf7fc;border-left:6px solid #2596be;border-radius:12px;padding:14px}
.metric b{display:block;color:#0d4b71;font-size:12px;text-transform:uppercase}.metric span{font-size:18px;font-weight:700}
.score{font-size:60px;font-weight:800;color:$scoreColor;margin:8px 0}
table{width:100%;border-collapse:collapse;font-size:13px}
th{background:#0d4b71;color:white;padding:10px;text-align:left}
td{border-bottom:1px solid #dbe8ef;padding:9px;vertical-align:top}
.pass{color:#16a34a;font-weight:700}.warn{color:#f59e0b;font-weight:700}.fail{color:#dc2626;font-weight:700}
.badge{display:inline-block;padding:6px 10px;border-radius:999px;background:#eaf7fc;color:#0d4b71;font-weight:700}
.notice{background:#fff7ed;border-left:6px solid #f59e0b;padding:14px;border-radius:12px}
.footer{text-align:center;padding:20px;color:#64748b;font-size:12px}
a.btn{display:inline-block;background:#2596be;color:white;text-decoration:none;padding:12px 18px;border-radius:12px;font-weight:700}
</style>
</head>
<body>
<div class="header">
  <h1>PC Plus 360 LCD / Display Wear Report</h1>
  <p>Approximate panel life, backlight wear indicators, display stability and visual test workflow | PC Plus Computing | 604-760-1662</p>
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
    <p><span class="badge">$($Data.Score.Grade)</span> <span class="badge">Risk: $($Data.Score.Risk)</span></p>
    <h3>Approximate LCD / Display Life</h3>
    <p><b>$($Data.Score.ApproxLife)</b></p>
    <div class="notice">$($Data.Score.Notes)</div>
    <p><a class="btn" href="$VisualTestFile">Open LCD Visual Test</a></p>
  </div>

  <div class="card">
    <h2>System / Age Information</h2>
    <table>
      <tr><th>Manufacturer</th><td>$($Data.System.Manufacturer)</td></tr>
      <tr><th>Model</th><td>$($Data.System.Model)</td></tr>
      <tr><th>Serial</th><td>$($Data.System.SerialNumber)</td></tr>
      <tr><th>BIOS Age Estimate</th><td>$($Data.System.BIOSAgeYears) years</td></tr>
      <tr><th>Windows</th><td>$($Data.System.OS) Build $($Data.System.OSBuild)</td></tr>
      <tr><th>Laptop Detected</th><td>$($Data.System.IsLaptop)</td></tr>
    </table>
  </div>

  <div class="card">
    <h2>Findings & Recommendations</h2>
    <table><tr><th>Category</th><th>Severity</th><th>Finding</th><th>Recommendation</th></tr>$($findingRows -join "`n")</table>
  </div>

  <div class="card">
    <h2>Detected Monitor / Panel Information</h2>
    <table><tr><th>Name</th><th>Manufacturer</th><th>Serial</th><th>Year</th><th>Active</th></tr>$($monitorRows -join "`n")</table>
  </div>

  <div class="card">
    <h2>Display Adapter / Resolution</h2>
    <table><tr><th>GPU</th><th>VRAM</th><th>Driver</th><th>Driver Date</th><th>Resolution</th><th>Refresh</th><th>Status</th></tr>$($gpuRows -join "`n")</table>
  </div>

  <div class="card">
    <h2>Brightness Information</h2>
    <table>
      <tr><th>Brightness Supported</th><td>$($Data.Brightness.BrightnessSupported)</td></tr>
      <tr><th>Current Brightness</th><td>$($Data.Brightness.CurrentBrightness)%</td></tr>
      <tr><th>Note</th><td>$($Data.Brightness.Notes)</td></tr>
    </table>
  </div>

  <div class="card">
    <h2>Display / GPU Stability Events</h2>
    <p>Events found in 180 days: $($Data.Events.EventCount) | Driver reset/recovery events: $($Data.Events.DriverResetCount)</p>
    <table><tr><th>Time</th><th>Source</th><th>ID</th><th>Level</th><th>Message</th></tr>$($eventRows -join "`n")</table>
  </div>

  <div class="card">
    <h2>Manual Visual Inspection Checklist</h2>
    <table><tr><th>Test</th><th>Status</th></tr>$($manualRows -join "`n")</table>
  </div>

  <div class="card">
    <h2>Burn-In Detection Test</h2>
    <table>
      <tr><th>Test Performed</th><td>$($Data.BurnIn.TestPerformed)</td></tr>
      <tr><th>Technician Rating</th><td class='$(if($Data.BurnIn.BurnInDetected -eq "Yes"){"fail"}elseif($Data.BurnIn.BurnInDetected -eq "Unsure"){"warn"}else{"pass"})'>$($Data.BurnIn.BurnInDetected)</td></tr>
      <tr><th>Colors Tested</th><td>$($Data.BurnIn.ColorsShown -join ", ")</td></tr>
      <tr><th>Notes</th><td>$($Data.BurnIn.Notes)</td></tr>
    </table>
  </div>

  <div class="card">
    <h2>Webcam Detection</h2>
    <table>
      <tr><th>Webcam Detected</th><td>$($Data.Webcam.WebcamDetected)</td></tr>
      <tr><th>Webcam Count</th><td>$($Data.Webcam.WebcamCount)</td></tr>
    </table>
    $(if($Data.Webcam.WebcamDetected){
      $wcRows = foreach($wc in $Data.Webcam.Webcams){
        "<tr><td>$(HtmlEncode $wc.DeviceName)</td><td class='$(if($wc.Status -eq 'OK'){"pass"}else{"fail"})'>$($wc.Status)</td><td>$(HtmlEncode $wc.Manufacturer)</td><td>$($wc.DriverVersion)</td></tr>"
      }
      "<table><tr><th>Device</th><th>Status</th><th>Manufacturer</th><th>Driver Version</th></tr>$($wcRows -join '')</table>"
    } else {
      "<p>No webcam devices detected.</p>"
    })
  </div>

  <div class="card">
    <h2>Touchscreen Detection</h2>
    <table>
      <tr><th>Touchscreen Detected</th><td>$($Data.Touchscreen.TouchscreenDetected)</td></tr>
      <tr><th>Max Touch Points</th><td>$($Data.Touchscreen.MaxTouchPoints)</td></tr>
      <tr><th>Touch Enabled</th><td>$($Data.Touchscreen.TouchEnabled)</td></tr>
      <tr><th>Notes</th><td>$($Data.Touchscreen.Notes)</td></tr>
    </table>
    $(if($Data.Touchscreen.TouchscreenDetected){
      $tsRows = foreach($ts in $Data.Touchscreen.TouchDevices){
        "<tr><td>$(HtmlEncode $ts.DeviceName)</td><td class='$(if($ts.Status -eq 'OK'){"pass"}else{"fail"})'>$($ts.Status)</td><td>$($ts.PNPClass)</td></tr>"
      }
      "<table><tr><th>Device</th><th>Status</th><th>Class</th></tr>$($tsRows -join '')</table>"
    })
  </div>

  <div class="card">
    <h2>Technician Notes</h2>
    <p>For best LCD life estimate, add technician visual results: max brightness comparison, dead/stuck pixel count, backlight bleed level, burn-in/image retention, yellow tint, hinge-angle flicker, and external monitor comparison.</p>
  </div>
</div>
<div class="footer">PC Plus Computing | pcpluscomputing.com | 604-760-1662 | 30+ Years in Service | 4.9 Google Rating | #1 Best Rated in Surrey</div>
</body>
</html>
"@
    Set-Content -Path $HtmlFile -Value $html -Encoding UTF8
}

# MAIN
Write-PCLog "PC Plus 360 LCD / Display Wear Life Report started."
if (-not (Test-IsAdmin)) { Write-PCLog "Not running as Administrator. Some results may be limited." "WARN" }

$visualPath = New-PCPlusVisualDisplayTest

if ($CreateVisualTestOnly) {
    Write-Host "LCD Visual Test created: $visualPath"
    if ($OpenReport) { Start-Process $visualPath }
    return
}

$System = Get-PCPlusSystemInfo
$Monitor = Get-PCPlusMonitorInfo
$Adapter = Get-PCPlusDisplayAdapterInfo
$Brightness = Get-PCPlusBrightnessInfo
$Events = Get-PCPlusDisplayEvents
$Thermal = Get-PCPlusThermalCorrelation
$Webcam = Get-PCPlusWebcamInfo
$Touchscreen = Get-PCPlusTouchscreenInfo
$BurnIn = Invoke-PCPlusBurnInTest
$Score = Get-PCPlusDisplayWearScore -System $System -Monitor $Monitor -Adapter $Adapter -Brightness $Brightness -Events $Events -Thermal $Thermal -Webcam $Webcam -Touchscreen $Touchscreen -BurnIn $BurnIn

$Data = [PSCustomObject]@{
    System=$System
    Monitor=$Monitor
    Adapter=$Adapter
    Brightness=$Brightness
    Events=$Events
    Thermal=$Thermal
    Webcam=$Webcam
    Touchscreen=$Touchscreen
    BurnIn=$BurnIn
    Score=$Score
    VisualTestFile=$VisualTestFile
    ReportDir=$ReportDir
}

$Data | ConvertTo-Json -Depth 12 | Set-Content -Path $JsonFile -Encoding UTF8

$topFindings = $Score.Findings | ForEach-Object {
    "- [$($_.Severity)] $($_.Category): $($_.Finding) Recommendation: $($_.Recommendation)"
}

$webcamSummary = if ($Webcam.WebcamDetected) {
    $camNames = ($Webcam.Webcams | ForEach-Object { "$($_.DeviceName) [$($_.Status)]" }) -join ", "
    "Webcam: $($Webcam.WebcamCount) detected - $camNames"
} else { "Webcam: Not detected" }

$touchSummary = if ($Touchscreen.TouchscreenDetected) {
    "Touchscreen: Detected ($($Touchscreen.MaxTouchPoints) touch points)"
} else { "Touchscreen: Not detected" }

$burnInSummary = "Burn-In Test: $($BurnIn.BurnInDetected) - $($BurnIn.Notes)"

$summary=@"
PC Plus 360 LCD / Display Wear & Approximate Life Report

Customer: $CustomerName
Technician: $TechnicianName
Computer: $($System.ComputerName)
Model: $($System.Manufacturer) $($System.Model)
Serial: $($System.SerialNumber)
BIOS Age Estimate: $($System.BIOSAgeYears) years
Laptop Detected: $($System.IsLaptop)

Display Health Score: $($Score.Score)/100
Grade: $($Score.Grade)
Risk Level: $($Score.Risk)
Approximate LCD / Display Life:
$($Score.ApproxLife)

$webcamSummary
$touchSummary
$burnInSummary

Top Findings:
$($topFindings -join "`r`n")

Visual LCD Test:
$VisualTestFile

Reports:
HTML: $HtmlFile
JSON: $JsonFile
CSV: $CsvFile
Log: $LogFile

Important:
Windows cannot directly provide exact LCD/backlight remaining life. This report estimates LCD/display health using system age, EDID data, brightness capability, GPU/display events, driver status, thermal risk, and manual visual inspection workflow.
"@
Set-Content -Path $TxtFile -Value $summary -Encoding UTF8

[PSCustomObject]@{
    ComputerName=$System.ComputerName
    CustomerName=$CustomerName
    DisplayScore=$Score.Score
    Grade=$Score.Grade
    Risk=$Score.Risk
    ApproxLife=$Score.ApproxLife
    BIOSAgeYears=$System.BIOSAgeYears
    MonitorCount=$Monitor.MonitorCount
    BrightnessSupported=$Brightness.BrightnessSupported
    CurrentBrightness=$Brightness.CurrentBrightness
    DisplayEvents=$Events.EventCount
    DriverResetEvents=$Events.DriverResetCount
    WebcamDetected=$Webcam.WebcamDetected
    WebcamCount=$Webcam.WebcamCount
    TouchscreenDetected=$Touchscreen.TouchscreenDetected
    MaxTouchPoints=$Touchscreen.MaxTouchPoints
    BurnInResult=$BurnIn.BurnInDetected
    ReportDate=Get-Date
} | Export-Csv -Path $CsvFile -NoTypeInformation

New-PCPlusDisplayHtmlReport -Data $Data

# -JsonOutput: Export structured JSON for ReportCard integration
if ($JsonOutput) {
    $rcJsonFile = Join-Path $ReportDir "PCPlus360-DisplayWear-ReportCard.json"
    $reportCardData = [PSCustomObject]@{
        ReportType        = "LCD Display Wear & Life"
        ReportVersion     = "2.0"
        Brand             = "PC Plus Computing 360"
        GeneratedAt       = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
        ComputerName      = $System.ComputerName
        CustomerName      = $CustomerName
        TechnicianName    = $TechnicianName
        System            = [PSCustomObject]@{
            Manufacturer  = $System.Manufacturer
            Model         = $System.Model
            SerialNumber  = $System.SerialNumber
            BIOSAgeYears  = $System.BIOSAgeYears
            IsLaptop      = $System.IsLaptop
            OS            = $System.OS
            OSBuild       = $System.OSBuild
        }
        DisplayHealth     = [PSCustomObject]@{
            Score         = $Score.Score
            Grade         = $Score.Grade
            Risk          = $Score.Risk
            ApproxLife    = $Score.ApproxLife
        }
        Monitors          = $Monitor.WmiMonitorID
        MonitorCount      = $Monitor.MonitorCount
        DisplayAdapters   = @($Adapter.GPUs | ForEach-Object {
            [PSCustomObject]@{
                Name                     = $_.Name
                VRAMGB                   = $_.AdapterRAMGB
                DriverVersion            = $_.DriverVersion
                DriverDate               = if ($_.DriverDate) { $_.DriverDate.ToString("yyyy-MM-dd") } else { $null }
                DriverAgeYears           = $_.DriverAgeYears
                Resolution               = "$($_.CurrentHorizontalResolution)x$($_.CurrentVerticalResolution)"
                RefreshRate              = $_.CurrentRefreshRate
                Status                   = $_.Status
            }
        })
        Brightness        = [PSCustomObject]@{
            Supported     = $Brightness.BrightnessSupported
            Current       = $Brightness.CurrentBrightness
        }
        Webcam            = [PSCustomObject]@{
            Detected      = $Webcam.WebcamDetected
            Count         = $Webcam.WebcamCount
            Devices       = @($Webcam.Webcams | ForEach-Object {
                [PSCustomObject]@{
                    Name          = $_.DeviceName
                    Status        = $_.Status
                    Manufacturer  = $_.Manufacturer
                    DriverVersion = $_.DriverVersion
                }
            })
        }
        Touchscreen       = [PSCustomObject]@{
            Detected      = $Touchscreen.TouchscreenDetected
            DeviceCount   = $Touchscreen.TouchDeviceCount
            MaxTouchPoints = $Touchscreen.MaxTouchPoints
            TouchEnabled  = $Touchscreen.TouchEnabled
        }
        BurnInTest        = [PSCustomObject]@{
            Performed     = $BurnIn.TestPerformed
            Result        = $BurnIn.BurnInDetected
            Notes         = $BurnIn.Notes
        }
        StabilityEvents   = [PSCustomObject]@{
            TotalEvents       = $Events.EventCount
            DriverResets      = $Events.DriverResetCount
            CableReconnects   = $Events.PossibleCableReconnectCount
            DaysChecked       = $Events.DaysChecked
        }
        ThermalRisk       = [PSCustomObject]@{
            EventCount    = $Thermal.ThermalEventCount
            MaxTempC      = $Thermal.MaxReportedTemperatureC
        }
        Findings          = @($Score.Findings | ForEach-Object {
            [PSCustomObject]@{
                Category       = $_.Category
                Severity       = $_.Severity
                Finding        = $_.Finding
                Recommendation = $_.Recommendation
            }
        })
        ReportFiles       = [PSCustomObject]@{
            HTML          = $HtmlFile
            JSON          = $JsonFile
            CSV           = $CsvFile
            TXT           = $TxtFile
            Log           = $LogFile
            VisualTest    = $VisualTestFile
            ReportCard    = $rcJsonFile
        }
    }
    $reportCardData | ConvertTo-Json -Depth 10 | Set-Content -Path $rcJsonFile -Encoding UTF8
    Write-PCLog "ReportCard JSON exported to $rcJsonFile"
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "PC Plus 360 LCD / Display Wear Report Completed" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "Display Score: $($Score.Score)/100"
Write-Host "Grade: $($Score.Grade)"
Write-Host "Risk: $($Score.Risk)"
Write-Host "Approx Life: $($Score.ApproxLife)"
Write-Host ""
Write-Host "Webcam: $(if($Webcam.WebcamDetected){"$($Webcam.WebcamCount) detected"}else{"Not detected"})"
Write-Host "Touchscreen: $(if($Touchscreen.TouchscreenDetected){"Detected ($($Touchscreen.MaxTouchPoints) touch points)"}else{"Not detected"})"
Write-Host "Burn-In Test: $($BurnIn.BurnInDetected)"
Write-Host ""
Write-Host "Report Folder: $ReportDir"
Write-Host "HTML Report:   $HtmlFile"
Write-Host "Visual Test:   $VisualTestFile"
Write-Host "TXT Summary:   $TxtFile"
Write-Host "JSON Raw Data: $JsonFile"
Write-Host "CSV Summary:   $CsvFile"
Write-Host "Log File:      $LogFile"
if ($JsonOutput) { Write-Host "ReportCard:    $(Join-Path $ReportDir 'PCPlus360-DisplayWear-ReportCard.json')" }
Write-Host ""

if ($OpenReport -and (Test-Path $HtmlFile)) { Start-Process $HtmlFile }
Write-PCLog "PC Plus 360 LCD / Display Wear Life Report completed."

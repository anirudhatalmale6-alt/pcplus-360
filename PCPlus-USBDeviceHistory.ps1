<#
.SYNOPSIS
    PC Plus Computing - USB Device History & Forensic Analysis
.DESCRIPTION
    Enumerates all USB devices ever connected to the system via registry,
    setupapi logs, and event logs. Classifies devices, detects suspicious
    indicators (Rubber Ducky, BadUSB, rogue adapters), and generates a
    branded HTML report with full device table and forensic timeline.
.NOTES
    Company:  PC Plus Computing
    Phone:    604-760-1662 | 236-500-2700
    Website:  pcpluscomputing.com
    Version:  1.0.0
    Requires: PowerShell 5.1+, Windows 10/11, Administrator privileges
.EXAMPLE
    PowerShell.exe -ExecutionPolicy Bypass -File .\PCPlus-USBDeviceHistory.ps1
#>

#Requires -Version 5.1
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
        Write-Host "ERROR: This tool requires Administrator privileges." -ForegroundColor Red
        Write-Host "Please right-click and select 'Run as Administrator'." -ForegroundColor Yellow
    }
    exit
}

trap {
    Write-Host ""
    Write-Host "  UNEXPECTED ERROR: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "  Line: $($_.InvocationInfo.ScriptLineNumber)" -ForegroundColor DarkGray
    Write-Host ""
    Read-Host "  Press Enter to exit"
    break
}

# ─────────────────────────────────────────────────────────────────────────────
# BRANDING
# ─────────────────────────────────────────────────────────────────────────────
$COMPANY_NAME    = "PC Plus Computing"
$COMPANY_PHONE   = "604-760-1662 | 236-500-2700"
$COMPANY_WEBSITE = "pcpluscomputing.com"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
if ([string]::IsNullOrEmpty($ScriptDir)) { $ScriptDir = Get-Location }
$ReportDir = Join-Path $ScriptDir "reports"
if (-not (Test-Path $ReportDir)) { New-Item -ItemType Directory -Path $ReportDir -Force | Out-Null }

$Timestamp    = Get-Date -Format "yyyyMMdd-HHmmss"
$ComputerSafe = $env:COMPUTERNAME -replace '[^\w\-]', '_'
$HtmlFile     = Join-Path $ReportDir "PCPlus-USBDeviceHistory-$ComputerSafe-$Timestamp.html"

# ─────────────────────────────────────────────────────────────────────────────
# HELPERS
# ─────────────────────────────────────────────────────────────────────────────
function Write-Section {
    param([string]$Title)
    Write-Host ""
    Write-Host ("=" * 70) -ForegroundColor Cyan
    Write-Host "  $Title" -ForegroundColor Cyan
    Write-Host ("=" * 70) -ForegroundColor Cyan
}

function Write-Check {
    param([string]$Label, [string]$Value, [string]$Status = "INFO")
    $color = switch ($Status) {
        "PASS" { "Green" }
        "WARN" { "Yellow" }
        "FAIL" { "Red" }
        "ALERT"{ "Magenta" }
        default { "White" }
    }
    Write-Host "  [$(($Status).PadRight(5))] " -ForegroundColor $color -NoNewline
    Write-Host "$Label : " -ForegroundColor Gray -NoNewline
    Write-Host "$Value" -ForegroundColor $color
}

function HtmlEncode {
    param([string]$Text)
    if ($null -eq $Text) { return "" }
    $Text.Replace("&","&amp;").Replace("<","&lt;").Replace(">","&gt;").Replace('"',"&quot;")
}

function Classify-USBDevice {
    param([string]$CompatId, [string]$Service, [string]$Class, [string]$FriendlyName, [string]$DeviceId)
    # Classify device based on class, compatible IDs, service, and name
    if ($Class -match "DiskDrive|USB Mass Storage|USBSTOR" -or $Service -match "USBSTOR|disk" -or
        $CompatId -match "USBSTOR|Mass" -or $FriendlyName -match "Flash|Thumb|External|HDD|SSD|Storage|Disk") {
        return "Storage"
    }
    if ($Class -match "WPD|Portable" -or $CompatId -match "MTP|PTP" -or $Service -match "WUDFWpdMtp" -or
        $FriendlyName -match "Phone|iPhone|Android|Galaxy|Pixel|MTP") {
        return "Mobile Phone"
    }
    if ($Class -match "Printer|Print" -or $Service -match "usbprint" -or
        $FriendlyName -match "Printer|LaserJet|DeskJet|OfficeJet|Epson|Canon|Brother") {
        return "Printer"
    }
    if ($Class -match "Net" -or $Service -match "rndis|usb8023|ASIX|ax88|r8152" -or
        $FriendlyName -match "Ethernet|Network|LAN|Wi-?Fi|Wireless.*Adapter") {
        return "Network Adapter"
    }
    if ($Class -match "Keyboard|HIDClass" -and ($FriendlyName -match "Keyboard" -or $CompatId -match "Keyboard")) {
        return "Keyboard"
    }
    if ($Class -match "Mouse|HIDClass" -and ($FriendlyName -match "Mouse|Trackball|Trackpad" -or $CompatId -match "Mouse")) {
        return "Mouse"
    }
    if ($Class -match "HIDClass|HID" -or $CompatId -match "HID") {
        return "HID (Input)"
    }
    if ($Class -match "Media|Audio|Sound" -or $FriendlyName -match "Audio|Headset|Microphone|Speaker|Webcam|Camera") {
        return "Audio/Video"
    }
    if ($Class -match "Bluetooth" -or $FriendlyName -match "Bluetooth") {
        return "Bluetooth"
    }
    if ($Class -match "Image|Camera" -or $FriendlyName -match "Scanner|Camera") {
        return "Imaging"
    }
    if ($Class -match "SmartCard" -or $FriendlyName -match "Smart.*Card|YubiKey|Token") {
        return "Security Token"
    }
    if ($FriendlyName -match "Hub") {
        return "USB Hub"
    }
    return "Other/Unknown"
}

function Test-SuspiciousDevice {
    param($Device)
    $flags = New-Object System.Collections.ArrayList

    # Rubber Ducky / BadUSB: HID device that also appears as storage or has very fast keystroke injection
    if ($Device.Category -eq "HID (Input)" -or $Device.Category -eq "Keyboard") {
        # Check if same VID/PID appears as storage
        if ($Device.VID -and $Device.PID) {
            # Hak5 Rubber Ducky VID/PID
            $knownBadUSB = @(
                "VID_05AC&PID_021E",  # Common Rubber Ducky spoof (Apple keyboard)
                "VID_F000&PID_FF00",  # Generic BadUSB
                "VID_2341",           # Arduino (common for DIY BadUSB)
                "VID_1B4F",           # SparkFun (DIY HID attacks)
                "VID_16C0",           # Teensy (HID attack tool)
                "VID_239A",           # Adafruit (Circuit Playground)
                "VID_2E8A"            # Raspberry Pi Pico (BadUSB)
            )
            foreach ($bad in $knownBadUSB) {
                if ($Device.DeviceId -match [regex]::Escape($bad)) {
                    [void]$flags.Add("ALERT: Known BadUSB/HID-attack VID/PID match ($bad)")
                }
            }
        }
    }

    # USB network adapter could be rogue
    if ($Device.Category -eq "Network Adapter") {
        [void]$flags.Add("WARNING: USB network adapter - verify this is authorized")
    }

    # Device connected outside business hours (before 6am or after 10pm)
    if ($Device.FirstConnected -and $Device.FirstConnected -ne "Unknown") {
        try {
            $dt = [datetime]::Parse($Device.FirstConnected)
            $hour = $dt.Hour
            if ($hour -lt 6 -or $hour -ge 22) {
                [void]$flags.Add("INFO: First connected outside business hours ($($dt.ToString('HH:mm')))")
            }
        } catch { }
    }

    return $flags
}

# ─────────────────────────────────────────────────────────────────────────────
# DATA COLLECTION
# ─────────────────────────────────────────────────────────────────────────────
$allDevices = New-Object System.Collections.ArrayList
$suspiciousDevices = New-Object System.Collections.ArrayList
$stats = @{
    TotalUnique       = 0
    ByType            = @{}
    CurrentlyConnected = 0
    Last24h           = 0
    Last7d            = 0
    Last30d           = 0
    SuspiciousCount   = 0
}

# ─────────────────────────────────────────────────────────────────────────────
# 1. USBSTOR REGISTRY (Storage devices)
# ─────────────────────────────────────────────────────────────────────────────
Write-Section "USB Storage Device History (USBSTOR)"

$usbStorPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\USBSTOR"
try {
    if (Test-Path $usbStorPath) {
        $deviceClasses = Get-ChildItem $usbStorPath -ErrorAction SilentlyContinue
        foreach ($devClass in $deviceClasses) {
            $instances = Get-ChildItem $devClass.PSPath -ErrorAction SilentlyContinue
            foreach ($inst in $instances) {
                try {
                    $props = Get-ItemProperty -Path $inst.PSPath -ErrorAction SilentlyContinue
                    $friendlyName = if ($props.FriendlyName) { $props.FriendlyName } else { $devClass.PSChildName }
                    $serial = $inst.PSChildName
                    $compatId = if ($props.CompatibleIDs) { ($props.CompatibleIDs -join ";") } else { "" }
                    $svc = if ($props.Service) { $props.Service } else { "" }
                    $cls = "USBSTOR"

                    # Parse VID/PID from parent
                    $vid = ""; $pid = ""
                    $parentName = $devClass.PSChildName
                    if ($parentName -match "Ven_([^&]+)") { $vid = $Matches[1].Trim() }
                    if ($parentName -match "Prod_([^&]+)") { $pid = $Matches[1].Trim() }

                    $device = @{
                        DeviceId      = $inst.PSChildName
                        FriendlyName  = $friendlyName
                        SerialNumber  = $serial
                        VID           = $vid
                        PID           = $pid
                        Category      = "Storage"
                        Class         = $cls
                        Service       = $svc
                        CompatibleIDs = $compatId
                        Source        = "USBSTOR Registry"
                        Connected     = $false
                        FirstConnected = "Unknown"
                        LastConnected  = "Unknown"
                        Suspicious    = New-Object System.Collections.ArrayList
                    }

                    [void]$allDevices.Add($device)
                    Write-Check $friendlyName "Serial: $serial" "INFO"
                } catch {
                    Write-Check "Error" $_.Exception.Message "WARN"
                }
            }
        }
    } else {
        Write-Check "USBSTOR" "Registry key not found" "INFO"
    }
} catch {
    Write-Check "USBSTOR" "Error reading registry: $($_.Exception.Message)" "FAIL"
}

# ─────────────────────────────────────────────────────────────────────────────
# 2. USB REGISTRY (All USB devices)
# ─────────────────────────────────────────────────────────────────────────────
Write-Section "USB Device History (USB Enum)"

$usbPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\USB"
try {
    if (Test-Path $usbPath) {
        $vidPidKeys = Get-ChildItem $usbPath -ErrorAction SilentlyContinue
        foreach ($vpKey in $vidPidKeys) {
            $vpName = $vpKey.PSChildName
            $vid = ""; $pid = ""
            if ($vpName -match "VID_([0-9A-Fa-f]{4})") { $vid = $Matches[1] }
            if ($vpName -match "PID_([0-9A-Fa-f]{4})") { $pid = $Matches[1] }

            $serials = Get-ChildItem $vpKey.PSPath -ErrorAction SilentlyContinue
            foreach ($sKey in $serials) {
                try {
                    $props = Get-ItemProperty -Path $sKey.PSPath -ErrorAction SilentlyContinue
                    $friendlyName = if ($props.FriendlyName) { $props.FriendlyName }
                                    elseif ($props.DeviceDesc) {
                                        $desc = $props.DeviceDesc
                                        if ($desc -match ";(.+)$") { $Matches[1] } else { $desc }
                                    } else { $vpName }
                    $serial = $sKey.PSChildName
                    $compatId = if ($props.CompatibleIDs) { ($props.CompatibleIDs -join ";") } else { "" }
                    $svc = if ($props.Service) { $props.Service } else { "" }
                    $cls = if ($props.Class) { $props.Class } else { "" }

                    # Skip if we already captured this as USBSTOR
                    $isDuplicate = $false
                    foreach ($existing in $allDevices) {
                        if ($existing.SerialNumber -eq $serial -and $existing.Source -eq "USBSTOR Registry") {
                            $isDuplicate = $true
                            break
                        }
                    }
                    if ($isDuplicate) { continue }

                    $category = Classify-USBDevice -CompatId $compatId -Service $svc -Class $cls -FriendlyName $friendlyName -DeviceId "$vpName\$serial"

                    $device = @{
                        DeviceId       = "$vpName\$serial"
                        FriendlyName   = $friendlyName
                        SerialNumber   = $serial
                        VID            = $vid
                        PID            = $pid
                        Category       = $category
                        Class          = $cls
                        Service        = $svc
                        CompatibleIDs  = $compatId
                        Source         = "USB Registry"
                        Connected      = $false
                        FirstConnected = "Unknown"
                        LastConnected  = "Unknown"
                        Suspicious     = New-Object System.Collections.ArrayList
                    }

                    [void]$allDevices.Add($device)
                } catch { }
            }
        }
        Write-Check "USB Devices" "$($allDevices.Count) total devices found in registry" "INFO"
    }
} catch {
    Write-Check "USB Registry" "Error: $($_.Exception.Message)" "FAIL"
}

# ─────────────────────────────────────────────────────────────────────────────
# 3. PARSE SETUPAPI.DEV.LOG FOR TIMESTAMPS
# ─────────────────────────────────────────────────────────────────────────────
Write-Section "Setup API Device Log Analysis"

$setupLogPaths = @(
    "$env:SystemRoot\INF\setupapi.dev.log",
    "$env:SystemRoot\setupapi.dev.log"
)

$setupEntries = @{}  # keyed by serial/device fragment

foreach ($logPath in $setupLogPaths) {
    if (-not (Test-Path $logPath)) { continue }

    Write-Check "Parsing" $logPath "INFO"
    try {
        $reader = [System.IO.StreamReader]::new($logPath)
        $currentSection = ""
        $currentTimestamp = ""

        while ($null -ne ($line = $reader.ReadLine())) {
            # Match section headers like >>>  [Device Install ...]
            if ($line -match '>>>\s+\[Device Install.*\]') {
                $currentSection = $line
            }
            # Match timestamps like >>>  Section start YYYY/MM/DD HH:MM:SS
            if ($line -match '>>>\s+Section start\s+(\d{4}/\d{2}/\d{2}\s+\d{2}:\d{2}:\d{2})') {
                $currentTimestamp = $Matches[1]
            }

            # Look for USB device references
            if ($line -match 'USB\\VID_[0-9A-Fa-f]{4}&PID_[0-9A-Fa-f]{4}\\(.+)' -or
                $line -match 'USBSTOR\\.*\\(.+)') {
                $fragment = $Matches[1] -replace '\s+$', '' -replace '["\]]', ''
                if ($fragment.Length -gt 2 -and $currentTimestamp) {
                    try {
                        $parsedTime = [datetime]::ParseExact($currentTimestamp, "yyyy/MM/dd HH:mm:ss", $null)
                        if (-not $setupEntries.ContainsKey($fragment)) {
                            $setupEntries[$fragment] = @{ First = $parsedTime; Last = $parsedTime }
                        } else {
                            if ($parsedTime -lt $setupEntries[$fragment].First) {
                                $setupEntries[$fragment].First = $parsedTime
                            }
                            if ($parsedTime -gt $setupEntries[$fragment].Last) {
                                $setupEntries[$fragment].Last = $parsedTime
                            }
                        }
                    } catch { }
                }
            }
        }
        $reader.Close()
        $reader.Dispose()

        Write-Check "Parsed Entries" "$($setupEntries.Count) device install timestamps found" "INFO"
    } catch {
        Write-Check "SetupAPI" "Error parsing: $($_.Exception.Message)" "WARN"
    }
}

# Merge timestamps into device list
foreach ($device in $allDevices) {
    $serial = $device.SerialNumber
    if ($serial -and $setupEntries.ContainsKey($serial)) {
        $device.FirstConnected = $setupEntries[$serial].First.ToString("yyyy-MM-dd HH:mm:ss")
        $device.LastConnected  = $setupEntries[$serial].Last.ToString("yyyy-MM-dd HH:mm:ss")
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# 4. CURRENTLY CONNECTED DEVICES
# ─────────────────────────────────────────────────────────────────────────────
Write-Section "Currently Connected USB Devices"

try {
    $pnpDevices = Get-WmiObject -Class Win32_PnPEntity -ErrorAction SilentlyContinue |
        Where-Object { $_.DeviceID -match "^USB\\" -or $_.DeviceID -match "^USBSTOR\\" }

    $connectedIds = New-Object System.Collections.ArrayList
    if ($pnpDevices) {
        foreach ($pnp in $pnpDevices) {
            [void]$connectedIds.Add($pnp.DeviceID)
            # Try to match with our device list
            foreach ($device in $allDevices) {
                if ($pnp.DeviceID -match [regex]::Escape($device.SerialNumber) -and
                    $device.SerialNumber.Length -gt 3) {
                    $device.Connected = $true
                }
            }
        }
        $connectedCount = @($pnpDevices).Count
        Write-Check "Connected USB Devices" "$connectedCount currently plugged in" "INFO"

        foreach ($pnp in $pnpDevices) {
            $name = if ($pnp.Name) { $pnp.Name } else { $pnp.DeviceID }
            $status = if ($pnp.Status -eq "OK") { "PASS" } else { "WARN" }
            Write-Check "  $name" $pnp.Status $status
        }
    }
} catch {
    Write-Check "PnP Devices" "Error enumerating: $($_.Exception.Message)" "FAIL"
}

# ─────────────────────────────────────────────────────────────────────────────
# 5. PORTABLE DEVICE VOLUME SERIAL NUMBERS
# ─────────────────────────────────────────────────────────────────────────────
Write-Section "Portable Device Volumes & Mount Points"

$volumeInfo = New-Object System.Collections.ArrayList
$portDevPath = "HKLM:\SOFTWARE\Microsoft\Windows Portable Devices\Devices"
try {
    if (Test-Path $portDevPath) {
        $portDevices = Get-ChildItem $portDevPath -ErrorAction SilentlyContinue
        foreach ($pd in $portDevices) {
            try {
                $props = Get-ItemProperty -Path $pd.PSPath -ErrorAction SilentlyContinue
                $friendlyName = $props.FriendlyName
                $devicePath = $pd.PSChildName

                if ($friendlyName) {
                    $volEntry = @{
                        DevicePath   = $devicePath
                        FriendlyName = $friendlyName
                    }
                    [void]$volumeInfo.Add($volEntry)
                    Write-Check $friendlyName $devicePath "INFO"
                }
            } catch { }
        }
    }

    # Also check MountedDevices for drive letter mappings
    $mountPath = "HKLM:\SYSTEM\MountedDevices"
    if (Test-Path $mountPath) {
        $mountProps = Get-ItemProperty -Path $mountPath -ErrorAction SilentlyContinue
        $mountCount = 0
        if ($mountProps) {
            $propNames = $mountProps.PSObject.Properties | Where-Object { $_.Name -match '^\\\\\?\\Volume' -or $_.Name -match '^\\DosDevices\\' }
            $mountCount = @($propNames).Count
        }
        Write-Check "Mounted Device Entries" "$mountCount entries in registry" "INFO"
    }
} catch {
    Write-Check "Portable Devices" "Error: $($_.Exception.Message)" "WARN"
}

# ─────────────────────────────────────────────────────────────────────────────
# 6. DEVICE INSTALLATION EVENTS (System Event Log)
# ─────────────────────────────────────────────────────────────────────────────
Write-Section "Device Installation Events (Event Log)"

$installEvents = New-Object System.Collections.ArrayList
try {
    # Event ID 20001 = Device install, 20003 = Service install for device
    # DriverFrameworks-UserMode: 2003/2004 = Device connected/disconnected
    $eventFilter = @{
        LogName      = 'System'
        ProviderName = 'Microsoft-Windows-Kernel-PnP'
        Id           = @(400, 410, 420, 430)
    }

    $events = $null
    try {
        $events = Get-WinEvent -FilterHashtable $eventFilter -MaxEvents 200 -ErrorAction SilentlyContinue
    } catch { }

    # Also try DriverFrameworks
    $dfEvents = $null
    try {
        $dfFilter = @{
            LogName = 'Microsoft-Windows-DriverFrameworks-UserMode/Operational'
            Id      = @(2003, 2004, 2100, 2101, 2102, 2105)
        }
        $dfEvents = Get-WinEvent -FilterHashtable $dfFilter -MaxEvents 200 -ErrorAction SilentlyContinue
    } catch { }

    # Fallback: generic USB events from System log
    if (-not $events -and -not $dfEvents) {
        try {
            $genericFilter = @{
                LogName   = 'System'
                Id        = @(10000, 10100, 20001, 20003, 24576, 24577)
            }
            $events = Get-WinEvent -FilterHashtable $genericFilter -MaxEvents 200 -ErrorAction SilentlyContinue
        } catch { }
    }

    $combinedEvents = @()
    if ($events) { $combinedEvents += $events }
    if ($dfEvents) { $combinedEvents += $dfEvents }

    foreach ($evt in $combinedEvents) {
        $evtEntry = @{
            TimeCreated = $evt.TimeCreated.ToString("yyyy-MM-dd HH:mm:ss")
            Id          = $evt.Id
            Provider    = $evt.ProviderName
            Message     = if ($evt.Message.Length -gt 200) { $evt.Message.Substring(0, 200) + "..." } else { $evt.Message }
        }
        [void]$installEvents.Add($evtEntry)
    }

    Write-Check "Install Events" "$($installEvents.Count) USB-related events found" "INFO"
} catch {
    Write-Check "Event Log" "Error querying: $($_.Exception.Message)" "WARN"
}

# ─────────────────────────────────────────────────────────────────────────────
# 7. SUSPICIOUS DEVICE ANALYSIS
# ─────────────────────────────────────────────────────────────────────────────
Write-Section "Suspicious Device Analysis"

# Check for duplicate VID/PID with different serials (mass deployment or cloning)
$vidPidGroups = @{}
foreach ($device in $allDevices) {
    if ($device.VID -and $device.PID) {
        $key = "VID_$($device.VID)_PID_$($device.PID)"
        if (-not $vidPidGroups.ContainsKey($key)) {
            $vidPidGroups[$key] = New-Object System.Collections.ArrayList
        }
        [void]$vidPidGroups[$key].Add($device)
    }
}

foreach ($key in $vidPidGroups.Keys) {
    $group = $vidPidGroups[$key]
    if ($group.Count -gt 3) {
        foreach ($device in $group) {
            [void]$device.Suspicious.Add("INFO: $($group.Count) devices share $key (mass deployment?)")
        }
    }
}

# Run suspicious checks on each device
foreach ($device in $allDevices) {
    $flags = Test-SuspiciousDevice -Device $device
    foreach ($f in $flags) {
        [void]$device.Suspicious.Add($f)
    }
    if ($device.Suspicious.Count -gt 0) {
        [void]$suspiciousDevices.Add($device)
        foreach ($flag in $device.Suspicious) {
            $st = if ($flag -match "^ALERT") { "ALERT" } elseif ($flag -match "^WARNING") { "WARN" } else { "INFO" }
            Write-Check $device.FriendlyName $flag $st
        }
    }
}

if ($suspiciousDevices.Count -eq 0) {
    Write-Check "Suspicious Devices" "None detected" "PASS"
}

# ─────────────────────────────────────────────────────────────────────────────
# 8. SUMMARY STATISTICS
# ─────────────────────────────────────────────────────────────────────────────
Write-Section "Summary Statistics"

$stats.TotalUnique = $allDevices.Count
$stats.SuspiciousCount = $suspiciousDevices.Count
$stats.CurrentlyConnected = @($allDevices | Where-Object { $_.Connected }).Count

# Count by type
foreach ($device in $allDevices) {
    $cat = $device.Category
    if ($stats.ByType.ContainsKey($cat)) {
        $stats.ByType[$cat]++
    } else {
        $stats.ByType[$cat] = 1
    }
}

# Count by recency
$now = Get-Date
foreach ($device in $allDevices) {
    if ($device.LastConnected -ne "Unknown") {
        try {
            $lastDt = [datetime]::Parse($device.LastConnected)
            $daysAgo = ($now - $lastDt).TotalDays
            if ($daysAgo -le 1)  { $stats.Last24h++ }
            if ($daysAgo -le 7)  { $stats.Last7d++ }
            if ($daysAgo -le 30) { $stats.Last30d++ }
        } catch { }
    }
}

Write-Check "Total Unique Devices" "$($stats.TotalUnique)" "INFO"
Write-Check "Currently Connected" "$($stats.CurrentlyConnected)" "INFO"
Write-Check "Connected Last 24h" "$($stats.Last24h)" "INFO"
Write-Check "Connected Last 7 days" "$($stats.Last7d)" "INFO"
Write-Check "Connected Last 30 days" "$($stats.Last30d)" "INFO"
Write-Check "Suspicious Devices" "$($stats.SuspiciousCount)" $(if ($stats.SuspiciousCount -gt 0) { "WARN" } else { "PASS" })

foreach ($cat in ($stats.ByType.Keys | Sort-Object)) {
    Write-Check "  $cat" "$($stats.ByType[$cat]) device(s)" "INFO"
}

# ─────────────────────────────────────────────────────────────────────────────
# HTML REPORT GENERATION
# ─────────────────────────────────────────────────────────────────────────────
Write-Section "Generating HTML Report"

# Build device table rows
$deviceRows = ""
$sortedDevices = $allDevices | Sort-Object {
    if ($_.LastConnected -ne "Unknown") {
        try { [datetime]::Parse($_.LastConnected) } catch { [datetime]::MinValue }
    } else { [datetime]::MinValue }
} -Descending

foreach ($device in $sortedDevices) {
    $cls = ""
    $suspCol = ""
    if ($device.Suspicious.Count -gt 0) {
        $cls = " style='background:#fef2f2'"
        $suspCol = "<span class='fail'>" + (HtmlEncode ($device.Suspicious -join "; ")) + "</span>"
    } else {
        $suspCol = "<span class='pass'>Clean</span>"
    }

    $connStatus = if ($device.Connected) { "<span class='pass'>YES</span>" } else { "No" }
    $catClass = switch ($device.Category) {
        "Storage"         { "badge-blue" }
        "Mobile Phone"    { "badge-purple" }
        "Network Adapter" { "badge-orange" }
        "Keyboard"        { "badge-gray" }
        "Mouse"           { "badge-gray" }
        default           { "badge-default" }
    }

    $deviceRows += @"
<tr$cls>
<td>$(HtmlEncode $device.FriendlyName)</td>
<td><span class="cat-badge $catClass">$(HtmlEncode $device.Category)</span></td>
<td style="font-family:monospace;font-size:11px">$(HtmlEncode $device.VID)</td>
<td style="font-family:monospace;font-size:11px">$(HtmlEncode $device.PID)</td>
<td style="font-family:monospace;font-size:11px" title="$(HtmlEncode $device.SerialNumber)">$(if($device.SerialNumber.Length -gt 20){(HtmlEncode $device.SerialNumber.Substring(0,20))+"..."}else{HtmlEncode $device.SerialNumber})</td>
<td>$(HtmlEncode $device.FirstConnected)</td>
<td>$(HtmlEncode $device.LastConnected)</td>
<td>$connStatus</td>
<td>$suspCol</td>
</tr>

"@
}

if ($allDevices.Count -eq 0) {
    $deviceRows = "<tr><td colspan='9'>No USB devices found in registry</td></tr>"
}

# Build type summary rows
$typeRows = ""
foreach ($cat in ($stats.ByType.Keys | Sort-Object)) {
    $typeRows += "<tr><td>$(HtmlEncode $cat)</td><td>$($stats.ByType[$cat])</td></tr>`n"
}

# Build suspicious device rows
$suspRows = ""
if ($suspiciousDevices.Count -gt 0) {
    foreach ($sd in $suspiciousDevices) {
        $suspRows += "<tr><td>$(HtmlEncode $sd.FriendlyName)</td><td>$(HtmlEncode $sd.Category)</td><td style='font-family:monospace'>$(HtmlEncode $sd.DeviceId)</td><td class='fail'>$(HtmlEncode ($sd.Suspicious -join '; '))</td></tr>`n"
    }
} else {
    $suspRows = "<tr><td colspan='4' class='pass'>No suspicious devices detected</td></tr>"
}

# Build event log rows (most recent 50)
$eventRows = ""
$recentEvents = $installEvents | Select-Object -First 50
foreach ($evt in $recentEvents) {
    $msgShort = $evt.Message
    if ($msgShort.Length -gt 120) { $msgShort = $msgShort.Substring(0, 120) + "..." }
    $eventRows += "<tr><td>$(HtmlEncode $evt.TimeCreated)</td><td>$($evt.Id)</td><td>$(HtmlEncode $evt.Provider)</td><td>$(HtmlEncode $msgShort)</td></tr>`n"
}
if ($installEvents.Count -eq 0) {
    $eventRows = "<tr><td colspan='4'>No USB installation events found in event log</td></tr>"
}

# Build volume info rows
$volRows = ""
foreach ($vol in $volumeInfo) {
    $volRows += "<tr><td>$(HtmlEncode $vol.FriendlyName)</td><td style='font-family:monospace;font-size:11px'>$(HtmlEncode $vol.DevicePath)</td></tr>`n"
}
if ($volumeInfo.Count -eq 0) {
    $volRows = "<tr><td colspan='2'>No portable device volumes found</td></tr>"
}

$suspColor = if ($stats.SuspiciousCount -gt 0) { "#dc2626" } else { "#16a34a" }

$html = @"
<!DOCTYPE html><html><head><meta charset="utf-8"><title>PC Plus - USB Device History</title>
<style>
body{font-family:'Segoe UI',Arial,sans-serif;background:#f3f8fb;margin:0;color:#163247}
.header{background:linear-gradient(135deg,#0d4b71,#2596be);color:white;padding:34px 34px 28px 34px}
.header h1{margin:0;font-size:32px;letter-spacing:-0.5px}.header p{margin:8px 0 0 0;font-size:14px;opacity:.85}
.container{padding:24px;max-width:1200px;margin:0 auto}
.card{background:white;border-radius:16px;padding:22px;margin-bottom:18px;box-shadow:0 8px 22px rgba(13,75,113,.12)}
.card h2{margin-top:0;color:#0d4b71;font-size:20px;border-bottom:2px solid #e3edf3;padding-bottom:10px}
.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(180px,1fr));gap:14px}
.metric{background:#eaf7fc;border-left:6px solid #2596be;border-radius:12px;padding:14px}
.metric b{display:block;color:#0d4b71;font-size:11px;text-transform:uppercase;margin-bottom:4px}
.metric span{font-size:17px;font-weight:700}
table{width:100%;border-collapse:collapse;font-size:12px;margin-top:10px}
th{background:#0d4b71;color:white;padding:9px;text-align:left;font-size:11px;white-space:nowrap}
td{border-bottom:1px solid #dbe8ef;padding:8px;vertical-align:top}
tr:hover{background:#f0f7fc}
.pass{color:#16a34a;font-weight:700}.warn{color:#f59e0b;font-weight:700}.fail{color:#dc2626;font-weight:700}
.cat-badge{display:inline-block;padding:3px 8px;border-radius:999px;font-size:11px;font-weight:600;white-space:nowrap}
.badge-blue{background:#dbeafe;color:#1e40af}.badge-purple{background:#ede9fe;color:#6d28d9}
.badge-orange{background:#ffedd5;color:#9a3412}.badge-gray{background:#f1f5f9;color:#475569}
.badge-default{background:#f1f5f9;color:#475569}
.notice{background:#fff7ed;border-left:6px solid #f59e0b;padding:14px;border-radius:12px;margin:12px 0}
.notice-danger{background:#fef2f2;border-left:6px solid #dc2626;padding:14px;border-radius:12px;margin:12px 0}
.notice-success{background:#f0fdf4;border-left:6px solid #16a34a;padding:14px;border-radius:12px;margin:12px 0}
.footer{text-align:center;padding:20px;color:#64748b;font-size:12px;border-top:1px solid #e3edf3;margin-top:20px}
.table-scroll{overflow-x:auto;-webkit-overflow-scrolling:touch}
@media print{.header{-webkit-print-color-adjust:exact;print-color-adjust:exact}}
@media(max-width:900px){.grid{grid-template-columns:1fr 1fr}}
</style></head><body>
<div class="header">
<h1>USB Device History &amp; Forensic Analysis</h1>
<p>$COMPANY_NAME | $COMPANY_PHONE | $COMPANY_WEBSITE</p>
</div>
<div class="container">

<div class="card">
<h2>Overview</h2>
<div class="grid">
<div class="metric"><b>Computer</b><span>$($env:COMPUTERNAME)</span></div>
<div class="metric"><b>Scan Date</b><span>$(Get-Date -Format 'yyyy-MM-dd HH:mm')</span></div>
<div class="metric"><b>Total Unique Devices</b><span>$($stats.TotalUnique)</span></div>
<div class="metric"><b>Currently Connected</b><span>$($stats.CurrentlyConnected)</span></div>
<div class="metric"><b>Last 24 Hours</b><span>$($stats.Last24h)</span></div>
<div class="metric"><b>Last 7 Days</b><span>$($stats.Last7d)</span></div>
<div class="metric"><b>Last 30 Days</b><span>$($stats.Last30d)</span></div>
<div class="metric"><b>Suspicious</b><span style="color:$suspColor">$($stats.SuspiciousCount)</span></div>
</div>
</div>

<div class="card">
<h2>Devices by Type</h2>
<table><tr><th>Category</th><th>Count</th></tr>
$typeRows
</table>
</div>

<div class="card">
<h2>Complete Device History</h2>
<p style="font-size:12px;color:#64748b">All USB devices ever connected to this system, sorted by most recently connected first.</p>
<div class="table-scroll">
<table>
<tr><th>Device Name</th><th>Type</th><th>VID</th><th>PID</th><th>Serial Number</th><th>First Connected</th><th>Last Connected</th><th>Now</th><th>Flags</th></tr>
$deviceRows
</table>
</div>
</div>

<div class="card">
<h2>Suspicious Device Analysis</h2>
$(if($suspiciousDevices.Count -gt 0){'<div class="notice-danger"><strong>Suspicious devices detected - review recommended</strong></div>'}else{'<div class="notice-success"><strong>No suspicious devices detected</strong></div>'})
<table><tr><th>Device</th><th>Type</th><th>Device ID</th><th>Flags</th></tr>
$suspRows
</table>
<div class="notice">
<strong>What we look for:</strong>
<ul style="margin:6px 0;padding-left:20px;font-size:12px">
<li><b>Rubber Ducky / BadUSB:</b> HID devices with known attack-tool VID/PIDs (Hak5, Arduino, Teensy, Raspberry Pi Pico)</li>
<li><b>Rogue Network Adapters:</b> USB network adapters that could intercept traffic</li>
<li><b>Mass VID/PID Duplicates:</b> Many devices sharing the same VID/PID with different serials (cloning indicator)</li>
<li><b>Off-hours Connections:</b> Devices first connected outside business hours (before 6 AM or after 10 PM)</li>
</ul>
</div>
</div>

<div class="card">
<h2>Portable Device Volumes</h2>
<table><tr><th>Friendly Name</th><th>Device Path</th></tr>
$volRows
</table>
</div>

<div class="card">
<h2>Device Installation Events (Recent)</h2>
<p style="font-size:12px;color:#64748b">From Windows Event Log (up to 50 most recent USB-related events)</p>
<div class="table-scroll">
<table><tr><th>Time</th><th>Event ID</th><th>Provider</th><th>Message</th></tr>
$eventRows
</table>
</div>
</div>

</div>
<div class="footer">$COMPANY_NAME | $COMPANY_PHONE | $COMPANY_WEBSITE | 30+ Years in Service | 4.9 Google Rating | #1 Best Rated in Surrey</div>
</body></html>
"@

Set-Content -Path $HtmlFile -Value $html -Encoding UTF8
Write-Check "HTML Report" $HtmlFile "PASS"

# ─────────────────────────────────────────────────────────────────────────────
# FINAL SUMMARY
# ─────────────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host ("=" * 70) -ForegroundColor Cyan
Write-Host "  SCAN COMPLETE" -ForegroundColor Cyan
Write-Host ("=" * 70) -ForegroundColor Cyan
Write-Host ""
Write-Host "  Total Devices:  $($stats.TotalUnique)" -ForegroundColor White
Write-Host "  Connected Now:  $($stats.CurrentlyConnected)" -ForegroundColor White
$suspColor2 = if ($stats.SuspiciousCount -gt 0) { "Red" } else { "Green" }
Write-Host "  Suspicious:     $($stats.SuspiciousCount)" -ForegroundColor $suspColor2
Write-Host "  Report:         $HtmlFile" -ForegroundColor White
Write-Host ""
Write-Host "  $COMPANY_NAME | $COMPANY_PHONE | $COMPANY_WEBSITE" -ForegroundColor Gray
Write-Host ""

# Open report
try {
    Start-Process $HtmlFile
} catch { }

Write-Host "Press any key to exit..." -ForegroundColor Gray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

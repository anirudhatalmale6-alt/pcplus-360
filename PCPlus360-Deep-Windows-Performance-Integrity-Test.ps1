<#
PC Plus 360 - Deep Windows Performance & Integrity Test
Company: PC Plus Computing
Website: pcpluscomputing.com
Phone: 604-760-1662

Purpose:
Hardware may be healthy, but Windows can still be slow, corrupt, unstable, or damaged.
This script performs a deep Windows health check including:
- Windows file integrity
- DISM image health
- disk/file system integrity
- boot/shutdown performance
- startup apps
- service health
- WMI/CIM health
- driver/device health
- event log crash history
- Windows Update health
- responsiveness/app launch timing
- network response
- power/sleep health reports
- branded HTML/TXT/JSON/CSV output

Safe by default:
- Does not collect passwords
- Does not collect browser passwords
- Does not copy personal files
- Does not read emails/documents/photos
- RestoreHealth is optional and off by default unless -RunRepair is used

Run as Administrator:
PowerShell.exe -ExecutionPolicy Bypass -File .\PCPlus360-Deep-Windows-Test.ps1 -Mode Standard

Optional repair:
PowerShell.exe -ExecutionPolicy Bypass -File .\PCPlus360-Deep-Windows-Test.ps1 -Mode Deep -RunRepair
#>

param(
    [ValidateSet("Quick","Standard","Deep")]
    [string]$Mode = "Standard",

    [string]$CustomerName = "Customer",
    [string]$TechnicianName = "PC Plus Technician",

    [switch]$RunRepair,
    [switch]$SkipSFC,
    [switch]$SkipDISM,
    [switch]$SkipPowerReports,

    [switch]$JsonOutput
)

$ErrorActionPreference = "Continue"

# ============================================================
# Paths
# ============================================================

$BaseDir = "C:\PCPlus360\WindowsDeepTest"
$TimeStamp = Get-Date -Format "yyyyMMdd-HHmmss"
$ComputerSafe = $env:COMPUTERNAME -replace '[^\w\-]', '_'
$ReportDir = Join-Path $BaseDir "$ComputerSafe-$TimeStamp"

New-Item -ItemType Directory -Path $ReportDir -Force | Out-Null

$LogFile = Join-Path $ReportDir "PCPlus360-WindowsDeepTest-Log.txt"
$JsonFile = Join-Path $ReportDir "PCPlus360-WindowsDeepTest-RawData.json"
$HtmlFile = Join-Path $ReportDir "PCPlus360-WindowsDeepTest-Report.html"
$TxtFile = Join-Path $ReportDir "PCPlus360-WindowsDeepTest-Summary.txt"
$CsvFile = Join-Path $ReportDir "PCPlus360-WindowsDeepTest-Summary.csv"

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

function Invoke-TimedCommand {
    param(
        [string]$Name,
        [scriptblock]$ScriptBlock
    )

    Write-PCLog "Starting: $Name"
    $sw = [Diagnostics.Stopwatch]::StartNew()
    try {
        $result = & $ScriptBlock
        $sw.Stop()
        Write-PCLog "Completed: $Name in $([math]::Round($sw.Elapsed.TotalSeconds,2)) seconds"
        return [PSCustomObject]@{
            Name = $Name
            Success = $true
            Seconds = [math]::Round($sw.Elapsed.TotalSeconds,2)
            Result = $result
            Error = $null
        }
    } catch {
        $sw.Stop()
        Write-PCLog "Failed: $Name - $($_.Exception.Message)" "ERROR"
        return [PSCustomObject]@{
            Name = $Name
            Success = $false
            Seconds = [math]::Round($sw.Elapsed.TotalSeconds,2)
            Result = $null
            Error = $_.Exception.Message
        }
    }
}

function Convert-BytesToGB {
    param([double]$Bytes)
    if ($null -eq $Bytes) { return $null }
    return [math]::Round($Bytes / 1GB, 2)
}

function Get-ProcessSafe {
    param([string]$Path, [string]$Arguments = "")
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $Path
    $psi.Arguments = $Arguments
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true

    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $psi
    $null = $p.Start()
    $stdout = $p.StandardOutput.ReadToEnd()
    $stderr = $p.StandardError.ReadToEnd()
    $p.WaitForExit()

    [PSCustomObject]@{
        ExitCode = $p.ExitCode
        StdOut = $stdout
        StdErr = $stderr
    }
}

# ============================================================
# System Info
# ============================================================

function Get-PCPlusSystemInfo {
    Write-PCLog "Collecting system information."

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
        Version = $os.Version
        Build = $os.BuildNumber
        Architecture = $os.OSArchitecture
        InstallDate = $os.InstallDate
        LastBoot = $os.LastBootUpTime
        UptimeHours = [math]::Round(((Get-Date) - $os.LastBootUpTime).TotalHours, 2)
        TotalRAMGB = Convert-BytesToGB $cs.TotalPhysicalMemory
        CPU = $cpu.Name
        Mode = $Mode
        RunRepair = [bool]$RunRepair
        ReportDate = Get-Date
    }
}

# ============================================================
# Windows Integrity: SFC / DISM
# ============================================================

function Invoke-PCPlusSFC {
    if ($SkipSFC) {
        return [PSCustomObject]@{ Skipped=$true; ExitCode=$null; Summary="SFC skipped."; RawLogPath=$null }
    }

    $outFile = Join-Path $ReportDir "sfc-output.txt"

    $result = Invoke-TimedCommand -Name "SFC ScanNow" -ScriptBlock {
        Get-ProcessSafe -Path "sfc.exe" -Arguments "/scannow"
    }

    $raw = ""
    if ($result.Result) {
        $raw = $result.Result.StdOut + "`r`n" + $result.Result.StdErr
        Set-Content -Path $outFile -Value $raw -Encoding UTF8
    }

    $summary = "Unknown"
    if ($raw -match "did not find any integrity violations") {
        $summary = "PASS - Windows Resource Protection found no integrity violations."
    } elseif ($raw -match "found corrupt files and successfully repaired") {
        $summary = "REPAIRED - Corrupt files found and repaired."
    } elseif ($raw -match "found corrupt files but was unable to fix") {
        $summary = "FAIL - Corrupt files found but not all could be repaired."
    } elseif ($raw -match "could not perform the requested operation") {
        $summary = "WARNING - SFC could not complete the operation."
    }

    [PSCustomObject]@{
        Skipped = $false
        ExitCode = $result.Result.ExitCode
        Seconds = $result.Seconds
        Summary = $summary
        RawLogPath = $outFile
    }
}

function Invoke-PCPlusDISM {
    if ($SkipDISM) {
        return [PSCustomObject]@{ Skipped=$true; CheckHealth="DISM skipped."; ScanHealth="DISM skipped."; RestoreHealth="DISM skipped." }
    }

    $checkFile = Join-Path $ReportDir "dism-checkhealth.txt"
    $scanFile = Join-Path $ReportDir "dism-scanhealth.txt"
    $restoreFile = Join-Path $ReportDir "dism-restorehealth.txt"

    $check = Invoke-TimedCommand -Name "DISM CheckHealth" -ScriptBlock {
        Get-ProcessSafe -Path "dism.exe" -Arguments "/Online /Cleanup-Image /CheckHealth"
    }
    Set-Content -Path $checkFile -Value (($check.Result.StdOut) + "`r`n" + ($check.Result.StdErr)) -Encoding UTF8

    $scan = $null
    $restore = $null

    if ($Mode -in @("Standard","Deep")) {
        $scan = Invoke-TimedCommand -Name "DISM ScanHealth" -ScriptBlock {
            Get-ProcessSafe -Path "dism.exe" -Arguments "/Online /Cleanup-Image /ScanHealth"
        }
        Set-Content -Path $scanFile -Value (($scan.Result.StdOut) + "`r`n" + ($scan.Result.StdErr)) -Encoding UTF8
    }

    if ($RunRepair) {
        $restore = Invoke-TimedCommand -Name "DISM RestoreHealth" -ScriptBlock {
            Get-ProcessSafe -Path "dism.exe" -Arguments "/Online /Cleanup-Image /RestoreHealth"
        }
        Set-Content -Path $restoreFile -Value (($restore.Result.StdOut) + "`r`n" + ($restore.Result.StdErr)) -Encoding UTF8
    }

    function Get-DismSummary($text) {
        if ($null -eq $text) { return "Not run" }
        if ($text -match "No component store corruption detected") { return "PASS - No component store corruption detected." }
        if ($text -match "The component store is repairable") { return "WARNING - Component store is repairable." }
        if ($text -match "The restore operation completed successfully") { return "REPAIRED - RestoreHealth completed successfully." }
        if ($text -match "The operation completed successfully") { return "PASS - Operation completed successfully." }
        return "Review required."
    }

    [PSCustomObject]@{
        CheckHealth = Get-DismSummary ($check.Result.StdOut + $check.Result.StdErr)
        CheckHealthSeconds = $check.Seconds
        CheckHealthLog = $checkFile
        ScanHealth = if ($scan) { Get-DismSummary ($scan.Result.StdOut + $scan.Result.StdErr) } else { "Not run in Quick mode." }
        ScanHealthSeconds = if ($scan) { $scan.Seconds } else { $null }
        ScanHealthLog = if ($scan) { $scanFile } else { $null }
        RestoreHealth = if ($restore) { Get-DismSummary ($restore.Result.StdOut + $restore.Result.StdErr) } else { "Not run. Use -RunRepair to enable." }
        RestoreHealthSeconds = if ($restore) { $restore.Seconds } else { $null }
        RestoreHealthLog = if ($restore) { $restoreFile } else { $null }
    }
}

# ============================================================
# Disk/File System Integrity
# ============================================================

function Get-PCPlusFileSystemHealth {
    Write-PCLog "Checking disk and file system integrity."

    $volumes = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" -ErrorAction SilentlyContinue
    $results = @()

    foreach ($v in $volumes) {
        $letter = $v.DeviceID
        $dirty = $null
        $chkdskSummary = "Not run"

        try {
            $dirtyOutput = cmd.exe /c "fsutil dirty query $letter" 2>&1
            $dirty = ($dirtyOutput -join " ")
        } catch {
            $dirty = "Unable to query dirty bit."
        }

        if ($Mode -in @("Standard","Deep")) {
            try {
                $safeLetter = $letter.Replace(":","")
                $scan = Get-ProcessSafe -Path "chkdsk.exe" -Arguments "$letter /scan"
                $scanFile = Join-Path $ReportDir "chkdsk-$safeLetter.txt"
                Set-Content -Path $scanFile -Value ($scan.StdOut + "`r`n" + $scan.StdErr) -Encoding UTF8

                if ($scan.StdOut -match "Windows has scanned the file system and found no problems") {
                    $chkdskSummary = "PASS - No file system problems found."
                } elseif ($scan.StdOut -match "found problems") {
                    $chkdskSummary = "WARNING - File system problems found. Review CHKDSK output."
                } else {
                    $chkdskSummary = "Review required. See CHKDSK output."
                }
            } catch {
                $chkdskSummary = "CHKDSK scan failed: $($_.Exception.Message)"
            }
        }

        $results += [PSCustomObject]@{
            Drive = $letter
            FileSystem = $v.FileSystem
            SizeGB = Convert-BytesToGB $v.Size
            FreeGB = Convert-BytesToGB $v.FreeSpace
            FreePercent = if ($v.Size -gt 0) { [math]::Round(($v.FreeSpace / $v.Size) * 100, 2) } else { $null }
            DirtyBit = $dirty
            ChkdskSummary = $chkdskSummary
        }
    }

    $results
}

# ============================================================
# Boot and Responsiveness
# ============================================================

function Get-PCPlusBootPerformance {
    Write-PCLog "Collecting boot/shutdown performance."

    $events = @()
    try {
        $events = Get-WinEvent -LogName "Microsoft-Windows-Diagnostics-Performance/Operational" -MaxEvents 120 -ErrorAction SilentlyContinue |
            Where-Object { $_.Id -in @(100,101,102,103,200,201,202,203) } |
            Select-Object TimeCreated, Id, ProviderName, Message
    } catch {}

    $latestBoot = $events | Where-Object {$_.Id -eq 100} | Sort-Object TimeCreated -Descending | Select-Object -First 1
    $latestShutdown = $events | Where-Object {$_.Id -eq 200} | Sort-Object TimeCreated -Descending | Select-Object -First 1

    function Extract-DurationMs($msg) {
        if ($msg -match "Boot Duration\s*:\s*(\d+)ms") { return [int]$matches[1] }
        if ($msg -match "Shutdown Duration\s*:\s*(\d+)ms") { return [int]$matches[1] }
        if ($msg -match "Duration\s*:\s*(\d+)ms") { return [int]$matches[1] }
        return $null
    }

    [PSCustomObject]@{
        LatestBootTime = $latestBoot.TimeCreated
        LatestBootDurationMS = if ($latestBoot) { Extract-DurationMs $latestBoot.Message } else { $null }
        LatestShutdownTime = $latestShutdown.TimeCreated
        LatestShutdownDurationMS = if ($latestShutdown) { Extract-DurationMs $latestShutdown.Message } else { $null }
        SlowBootRelatedEvents = @($events | Where-Object {$_.Id -in @(101,102,103)} | Select-Object -First 20)
        SlowShutdownRelatedEvents = @($events | Where-Object {$_.Id -in @(201,202,203)} | Select-Object -First 20)
    }
}

function Test-PCPlusResponsiveness {
    Write-PCLog "Running Windows responsiveness tests."

    $tests = @()

    $apps = @(
        @{Name="Notepad"; Path="notepad.exe"; Args=""},
        @{Name="Explorer"; Path="explorer.exe"; Args=""},
        @{Name="Control Panel"; Path="control.exe"; Args=""}
    )

    foreach ($app in $apps) {
        try {
            $sw = [Diagnostics.Stopwatch]::StartNew()
            $p = Start-Process -FilePath $app.Path -ArgumentList $app.Args -PassThru -ErrorAction Stop
            Start-Sleep -Milliseconds 900
            $sw.Stop()

            # Do not force close Explorer shell. Only close test windows where safe.
            if ($app.Name -ne "Explorer") {
                try { $p.CloseMainWindow() | Out-Null; Start-Sleep -Milliseconds 300; if (-not $p.HasExited) { $p.Kill() } } catch {}
            }

            $tests += [PSCustomObject]@{
                Test = "Launch $($app.Name)"
                Success = $true
                ResponseMS = $sw.ElapsedMilliseconds
                Notes = "Process launched successfully."
            }
        } catch {
            $tests += [PSCustomObject]@{
                Test = "Launch $($app.Name)"
                Success = $false
                ResponseMS = $null
                Notes = $_.Exception.Message
            }
        }
    }

    # File create/copy/delete test
    try {
        $testRoot = Join-Path $ReportDir "ResponsivenessFileTest"
        New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
        $source = Join-Path $testRoot "source.bin"
        $copy = Join-Path $testRoot "copy.bin"

        $buffer = New-Object byte[] (32MB)
        (New-Object Random).NextBytes($buffer)

        $sw = [Diagnostics.Stopwatch]::StartNew()
        [System.IO.File]::WriteAllBytes($source, $buffer)
        Copy-Item $source $copy -Force
        Remove-Item $source, $copy -Force
        $sw.Stop()

        $tests += [PSCustomObject]@{
            Test = "Create/Copy/Delete 32MB file"
            Success = $true
            ResponseMS = $sw.ElapsedMilliseconds
            Notes = "Basic file system response test."
        }
    } catch {
        $tests += [PSCustomObject]@{
            Test = "Create/Copy/Delete 32MB file"
            Success = $false
            ResponseMS = $null
            Notes = $_.Exception.Message
        }
    }

    $tests
}

# ============================================================
# Startup, Services, WMI, Drivers
# ============================================================

function Get-PCPlusStartupHealth {
    Write-PCLog "Collecting startup app health."

    $startupWmi = Get-CimInstance Win32_StartupCommand -ErrorAction SilentlyContinue |
        Select-Object Name, Command, Location, User

    $runKeys = @()
    $paths = @(
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run",
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run",
        "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run"
    )

    foreach ($p in $paths) {
        try {
            $props = Get-ItemProperty -Path $p -ErrorAction SilentlyContinue
            if ($props) {
                $props.PSObject.Properties | Where-Object {$_.Name -notmatch "^PS"} | ForEach-Object {
                    $runKeys += [PSCustomObject]@{ Location=$p; Name=$_.Name; Value=$_.Value }
                }
            }
        } catch {}
    }

    $scheduled = @()
    try {
        $scheduled = Get-ScheduledTask -ErrorAction SilentlyContinue |
            Where-Object {$_.State -ne "Disabled" -and ($_.TaskPath -notlike "\Microsoft*")} |
            Select-Object TaskName, TaskPath, State
    } catch {}

    [PSCustomObject]@{
        StartupCommandCount = @($startupWmi).Count
        StartupCommands = @($startupWmi)
        RunKeyCount = @($runKeys).Count
        RunKeys = @($runKeys)
        ThirdPartyScheduledTaskCount = @($scheduled).Count
        ThirdPartyScheduledTasks = @($scheduled | Select-Object -First 50)
    }
}

function Test-PCPlusServiceHealth {
    Write-PCLog "Checking critical Windows services."

    $criticalServices = @(
        "EventLog",
        "Winmgmt",
        "wuauserv",
        "BITS",
        "CryptSvc",
        "Schedule",
        "VSS",
        "Spooler",
        "Dhcp",
        "Dnscache",
        "LanmanWorkstation",
        "LanmanServer",
        "ProfSvc",
        "Themes"
    )

    $results = foreach ($svc in $criticalServices) {
        $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
        if ($s) {
            [PSCustomObject]@{
                Name = $svc
                DisplayName = $s.DisplayName
                Status = $s.Status.ToString()
                StartType = (Get-CimInstance Win32_Service -Filter "Name='$svc'" -ErrorAction SilentlyContinue).StartMode
                Healthy = ($s.Status -eq "Running" -or $svc -in @("wuauserv","VSS","Spooler"))
            }
        } else {
            [PSCustomObject]@{
                Name = $svc
                DisplayName = "Not found"
                Status = "Missing"
                StartType = "Unknown"
                Healthy = $false
            }
        }
    }

    $results
}

function Test-PCPlusWmiHealth {
    Write-PCLog "Checking WMI/CIM health."

    $tests = @()

    $queries = @(
        @{Name="Win32_OperatingSystem"; Query={Get-CimInstance Win32_OperatingSystem -ErrorAction Stop}},
        @{Name="Win32_ComputerSystem"; Query={Get-CimInstance Win32_ComputerSystem -ErrorAction Stop}},
        @{Name="Win32_Processor"; Query={Get-CimInstance Win32_Processor -ErrorAction Stop}},
        @{Name="Win32_LogicalDisk"; Query={Get-CimInstance Win32_LogicalDisk -ErrorAction Stop}}
    )

    foreach ($q in $queries) {
        $r = Invoke-TimedCommand -Name "CIM Query $($q.Name)" -ScriptBlock $q.Query
        $tests += [PSCustomObject]@{
            Test = $q.Name
            Success = $r.Success
            Seconds = $r.Seconds
            Error = $r.Error
        }
    }

    $repo = $null
    try {
        $repo = winmgmt /verifyrepository 2>&1
    } catch {
        $repo = "Unable to verify WMI repository: $($_.Exception.Message)"
    }

    [PSCustomObject]@{
        CimQueryTests = $tests
        RepositoryStatus = ($repo -join " ")
    }
}

function Get-PCPlusDriverDeviceHealth {
    Write-PCLog "Collecting driver and device health."

    $problemDevices = Get-PnpDevice -ErrorAction SilentlyContinue | Where-Object {$_.Status -ne "OK"}
    $drivers = Get-CimInstance Win32_PnPSignedDriver -ErrorAction SilentlyContinue

    $oldDrivers = @()
    try {
        $cutoff = (Get-Date).AddYears(-5)
        $oldDrivers = $drivers | Where-Object {
            $_.DriverDate -and ([Management.ManagementDateTimeConverter]::ToDateTime($_.DriverDate) -lt $cutoff)
        } | Select-Object DeviceName, Manufacturer, DriverVersion, DriverDate -First 50
    } catch {}

    [PSCustomObject]@{
        ProblemDeviceCount = @($problemDevices).Count
        ProblemDevices = @($problemDevices | Select-Object Class, FriendlyName, InstanceId, Status, Problem)
        OldDriverSample = @($oldDrivers)
        TotalSignedDrivers = @($drivers).Count
    }
}

# ============================================================
# Event Logs, Updates, Apps
# ============================================================

function Get-PCPlusDeepEventLogScan {
    Write-PCLog "Running deep event log scan."

    $days = if ($Mode -eq "Deep") { 90 } elseif ($Mode -eq "Standard") { 30 } else { 7 }
    $start = (Get-Date).AddDays(-$days)

    $queries = @(
        @{Category="Kernel Power Unexpected Shutdown"; Filter=@{LogName='System'; Id=41; StartTime=$start}},
        @{Category="Blue Screen BugCheck"; Filter=@{LogName='System'; Id=1001; StartTime=$start}},
        @{Category="Unexpected Shutdown"; Filter=@{LogName='System'; Id=6008; StartTime=$start}},
        @{Category="Disk Bad Block"; Filter=@{LogName='System'; Id=7; StartTime=$start}},
        @{Category="Disk Warning"; Filter=@{LogName='System'; Id=51; StartTime=$start}},
        @{Category="NTFS Corruption"; Filter=@{LogName='System'; Id=55; StartTime=$start}},
        @{Category="Storage Reset"; Filter=@{LogName='System'; Id=129; StartTime=$start}},
        @{Category="Disk IO Retry"; Filter=@{LogName='System'; Id=153; StartTime=$start}},
        @{Category="WHEA Hardware Error"; Filter=@{LogName='System'; ProviderName='Microsoft-Windows-WHEA-Logger'; StartTime=$start}},
        @{Category="Application Error"; Filter=@{LogName='Application'; ProviderName='Application Error'; StartTime=$start}},
        @{Category="Application Hang"; Filter=@{LogName='Application'; ProviderName='Application Hang'; StartTime=$start}},
        @{Category="Windows Error Reporting"; Filter=@{LogName='Application'; ProviderName='Windows Error Reporting'; StartTime=$start}},
        @{Category="Windows Update Client"; Filter=@{LogName='System'; ProviderName='Microsoft-Windows-WindowsUpdateClient'; StartTime=$start}}
    )

    $summary = @()
    foreach ($q in $queries) {
        try {
            $events = @(Get-WinEvent -FilterHashtable $q.Filter -ErrorAction SilentlyContinue)
            $summary += [PSCustomObject]@{
                Category = $q.Category
                DaysChecked = $days
                Count = $events.Count
                MostRecent = ($events | Sort-Object TimeCreated -Descending | Select-Object -First 1).TimeCreated
                RecentSamples = @($events | Sort-Object TimeCreated -Descending | Select-Object TimeCreated, ProviderName, Id, LevelDisplayName, Message -First 5)
            }
        } catch {
            $summary += [PSCustomObject]@{
                Category = $q.Category
                DaysChecked = $days
                Count = 0
                MostRecent = $null
                RecentSamples = @()
            }
        }
    }

    $summary
}

function Get-PCPlusWindowsUpdateHealth {
    Write-PCLog "Collecting Windows Update health."

    $services = "wuauserv","BITS","CryptSvc" | ForEach-Object {
        $s = Get-Service $_ -ErrorAction SilentlyContinue
        [PSCustomObject]@{Name=$_.ToString(); Status=if($s){$s.Status.ToString()}else{"Missing"}}
    }

    $rebootKeys = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired",
        "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager"
    )

    $rebootPending = $false
    foreach ($key in $rebootKeys[0..1]) {
        if (Test-Path $key) { $rebootPending = $true }
    }

    $hotfixes = @()
    try {
        $hotfixes = Get-HotFix | Sort-Object InstalledOn -Descending | Select-Object -First 15
    } catch {}

    $wuEvents = @()
    try {
        $wuEvents = Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Microsoft-Windows-WindowsUpdateClient'; StartTime=(Get-Date).AddDays(-30)} -ErrorAction SilentlyContinue |
            Sort-Object TimeCreated -Descending |
            Select-Object TimeCreated, Id, LevelDisplayName, Message -First 20
    } catch {}

    [PSCustomObject]@{
        Services = $services
        RebootPending = $rebootPending
        RecentHotfixes = @($hotfixes)
        RecentWindowsUpdateEvents = @($wuEvents)
    }
}

# ============================================================
# Power/Sleep
# ============================================================

function Invoke-PCPlusPowerReports {
    if ($SkipPowerReports) {
        return [PSCustomObject]@{Skipped=$true; EnergyReport=$null; SleepStudy=$null; LastWake=$null; AvailableSleepStates=$null}
    }

    Write-PCLog "Generating power and sleep reports."

    $energy = Join-Path $ReportDir "power-energy-report.html"
    $sleep = Join-Path $ReportDir "power-sleepstudy-report.html"
    $battery = Join-Path $ReportDir "battery-report.html"

    try { powercfg /energy /output $energy /duration 30 | Out-Null } catch { Write-PCLog "powercfg energy failed: $($_.Exception.Message)" "WARN" }
    try { powercfg /sleepstudy /output $sleep | Out-Null } catch { Write-PCLog "powercfg sleepstudy failed: $($_.Exception.Message)" "WARN" }
    try { powercfg /batteryreport /output $battery | Out-Null } catch { Write-PCLog "powercfg batteryreport failed: $($_.Exception.Message)" "WARN" }

    $lastWake = $null
    $wakeTimers = $null
    $sleepStates = $null
    try { $lastWake = (powercfg /lastwake) -join "`r`n" } catch {}
    try { $wakeTimers = (powercfg /waketimers) -join "`r`n" } catch {}
    try { $sleepStates = (powercfg /a) -join "`r`n" } catch {}

    [PSCustomObject]@{
        Skipped = $false
        EnergyReport = $energy
        SleepStudy = $sleep
        BatteryReport = $battery
        LastWake = $lastWake
        WakeTimers = $wakeTimers
        AvailableSleepStates = $sleepStates
    }
}

# ============================================================
# Network Response
# ============================================================

function Test-PCPlusNetworkResponse {
    Write-PCLog "Testing basic network response."

    $targets = @("127.0.0.1","1.1.1.1","8.8.8.8","google.com")
    $results = @()

    foreach ($t in $targets) {
        try {
            $p = @(Test-Connection $t -Count 5 -ErrorAction SilentlyContinue)
            $results += [PSCustomObject]@{
                Target = $t
                Sent = 5
                Received = $p.Count
                PacketLossPercent = [math]::Round(((5 - $p.Count) / 5) * 100, 2)
                AverageMS = if ($p.Count -gt 0) { [math]::Round(($p | Measure-Object ResponseTime -Average).Average,2) } else { $null }
                MaxMS = if ($p.Count -gt 0) { ($p | Measure-Object ResponseTime -Maximum).Maximum } else { $null }
            }
        } catch {
            $results += [PSCustomObject]@{
                Target = $t
                Sent = 5
                Received = 0
                PacketLossPercent = 100
                AverageMS = $null
                MaxMS = $null
            }
        }
    }

    $dnsTime = $null
    try {
        $sw = [Diagnostics.Stopwatch]::StartNew()
        Resolve-DnsName google.com -ErrorAction Stop | Out-Null
        $sw.Stop()
        $dnsTime = $sw.ElapsedMilliseconds
    } catch {}

    [PSCustomObject]@{
        PingResults = $results
        DnsLookupGoogleMS = $dnsTime
        Notes = "Use Speedtest CLI for download/upload speed and iPerf3 for LAN speed."
    }
}

# ============================================================
# Disk I/O Benchmark
# ============================================================

function Invoke-PCPlusDiskBenchmark {
    Write-PCLog "Running disk I/O benchmark."

    $results = @()
    $benchDir = Join-Path $ReportDir "DiskBenchmark"
    New-Item -ItemType Directory -Path $benchDir -Force | Out-Null

    $testSizeMB = 256
    $testBytes = $testSizeMB * 1MB
    $testFile = Join-Path $benchDir "pcplus-diskbench.tmp"

    try {
        # Sequential Write
        $buffer = New-Object byte[] $testBytes
        $rng = New-Object Random
        $rng.NextBytes($buffer)

        $sw = [Diagnostics.Stopwatch]::StartNew()
        [System.IO.File]::WriteAllBytes($testFile, $buffer)
        # Flush to disk
        $fs = [System.IO.File]::Open($testFile, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Write)
        $fs.Flush($true)
        $fs.Close()
        $fs.Dispose()
        $sw.Stop()

        $writeSeconds = $sw.Elapsed.TotalSeconds
        $writeMBps = if ($writeSeconds -gt 0) { [math]::Round($testSizeMB / $writeSeconds, 2) } else { 0 }

        $results += [PSCustomObject]@{
            Test          = "Sequential Write ${testSizeMB}MB"
            SizeMB        = $testSizeMB
            Seconds       = [math]::Round($writeSeconds, 3)
            ThroughputMBps = $writeMBps
            Success       = $true
            Notes         = ""
        }

        # Sequential Read
        $sw = [Diagnostics.Stopwatch]::StartNew()
        $readBuffer = [System.IO.File]::ReadAllBytes($testFile)
        $sw.Stop()

        $readSeconds = $sw.Elapsed.TotalSeconds
        $readMBps = if ($readSeconds -gt 0) { [math]::Round($testSizeMB / $readSeconds, 2) } else { 0 }

        $results += [PSCustomObject]@{
            Test          = "Sequential Read ${testSizeMB}MB"
            SizeMB        = $testSizeMB
            Seconds       = [math]::Round($readSeconds, 3)
            ThroughputMBps = $readMBps
            Success       = $true
            Notes         = ""
        }

        $readBuffer = $null
        $buffer = $null
    } catch {
        $results += [PSCustomObject]@{
            Test          = "Disk Benchmark"
            SizeMB        = $testSizeMB
            Seconds       = $null
            ThroughputMBps = $null
            Success       = $false
            Notes         = $_.Exception.Message
        }
    } finally {
        if (Test-Path $testFile) { Remove-Item $testFile -Force -ErrorAction SilentlyContinue }
        [GC]::Collect()
    }

    $results
}

# ============================================================
# Network Performance Benchmark
# ============================================================

function Invoke-PCPlusNetworkBenchmark {
    Write-PCLog "Running network performance benchmark."

    $results = [ordered]@{
        DNSLookups = @()
        PingLatency = @()
    }

    # DNS lookup benchmarks
    $dnsTargets = @("google.com", "microsoft.com", "cloudflare.com")
    foreach ($target in $dnsTargets) {
        try {
            $sw = [Diagnostics.Stopwatch]::StartNew()
            $resolved = Resolve-DnsName $target -Type A -ErrorAction Stop | Select-Object -First 1
            $sw.Stop()
            $results.DNSLookups += [PSCustomObject]@{
                Target     = $target
                ResolvedIP = $resolved.IPAddress
                LookupMS   = $sw.ElapsedMilliseconds
                Success    = $true
            }
        } catch {
            $results.DNSLookups += [PSCustomObject]@{
                Target     = $target
                ResolvedIP = $null
                LookupMS   = $null
                Success    = $false
            }
        }
    }

    # Ping latency to common servers
    $pingTargets = @(
        @{Name="Google DNS"; IP="8.8.8.8"},
        @{Name="Cloudflare DNS"; IP="1.1.1.1"},
        @{Name="Google DNS Secondary"; IP="8.8.4.4"},
        @{Name="Quad9 DNS"; IP="9.9.9.9"}
    )

    foreach ($pt in $pingTargets) {
        try {
            $pings = @(Test-Connection $pt.IP -Count 10 -ErrorAction SilentlyContinue)
            $avgMs = if ($pings.Count -gt 0) { [math]::Round(($pings | Measure-Object ResponseTime -Average).Average, 2) } else { $null }
            $minMs = if ($pings.Count -gt 0) { ($pings | Measure-Object ResponseTime -Minimum).Minimum } else { $null }
            $maxMs = if ($pings.Count -gt 0) { ($pings | Measure-Object ResponseTime -Maximum).Maximum } else { $null }
            $jitter = if ($pings.Count -gt 1) {
                $times = $pings | ForEach-Object { $_.ResponseTime }
                $diffs = @()
                for ($i = 1; $i -lt $times.Count; $i++) { $diffs += [math]::Abs($times[$i] - $times[$i-1]) }
                if ($diffs.Count -gt 0) { [math]::Round(($diffs | Measure-Object -Average).Average, 2) } else { 0 }
            } else { $null }
            $loss = [math]::Round(((10 - $pings.Count) / 10) * 100, 1)

            $results.PingLatency += [PSCustomObject]@{
                Name         = $pt.Name
                IP           = $pt.IP
                Sent         = 10
                Received     = $pings.Count
                PacketLoss   = $loss
                AvgMS        = $avgMs
                MinMS        = $minMs
                MaxMS        = $maxMs
                JitterMS     = $jitter
            }
        } catch {
            $results.PingLatency += [PSCustomObject]@{
                Name         = $pt.Name
                IP           = $pt.IP
                Sent         = 10
                Received     = 0
                PacketLoss   = 100
                AvgMS        = $null
                MinMS        = $null
                MaxMS        = $null
                JitterMS     = $null
            }
        }
    }

    [PSCustomObject]$results
}

# ============================================================
# Trend Tracking & System Comparison
# ============================================================

$PerfTrendDir = "C:\PCPlus360\Reports"
$PerfTrendFile = Join-Path $PerfTrendDir "WindowsPerformance-History.json"

function Get-PerfTrendHistory {
    if (Test-Path $PerfTrendFile) {
        try {
            $content = Get-Content -Path $PerfTrendFile -Raw -ErrorAction Stop
            $history = $content | ConvertFrom-Json -ErrorAction Stop
            if ($history -is [array]) { return $history }
            return @($history)
        } catch {
            Write-PCLog "Could not parse performance trend file. Starting fresh." "WARN"
            return @()
        }
    }
    return @()
}

function Save-PerfTrendEntry {
    param($Entry)
    New-Item -ItemType Directory -Path $PerfTrendDir -Force | Out-Null
    $history = @(Get-PerfTrendHistory)
    $history += $Entry
    if ($history.Count -gt 100) { $history = $history[($history.Count - 100)..($history.Count - 1)] }
    $history | ConvertTo-Json -Depth 8 | Set-Content -Path $PerfTrendFile -Encoding UTF8
}

function Get-PerfTrendComparison {
    param($CurrentEntry)
    $history = @(Get-PerfTrendHistory)
    if ($history.Count -eq 0) {
        return [PSCustomObject]@{
            HasPrevious   = $false
            PreviousDate  = $null
            Note          = "First run. This session becomes the baseline."
            Deltas        = @()
        }
    }

    $prev = $history[$history.Count - 1]
    $deltas = @()

    # Score comparison
    $prevScore = if ($null -ne $prev.Score) { $prev.Score } else { 0 }
    $curScore  = if ($null -ne $CurrentEntry.Score) { $CurrentEntry.Score } else { 0 }
    $deltas += [PSCustomObject]@{
        Metric   = "Health Score"
        Previous = $prevScore
        Current  = $curScore
        Delta    = $curScore - $prevScore
        Status   = if (($curScore - $prevScore) -gt 0) { "Improved" } elseif (($curScore - $prevScore) -lt 0) { "Degraded" } else { "Unchanged" }
    }

    # Disk write throughput
    $prevWrite = if ($null -ne $prev.DiskWriteMBps) { $prev.DiskWriteMBps } else { 0 }
    $curWrite  = if ($null -ne $CurrentEntry.DiskWriteMBps) { $CurrentEntry.DiskWriteMBps } else { 0 }
    $deltas += [PSCustomObject]@{
        Metric   = "Disk Write MB/s"
        Previous = $prevWrite
        Current  = $curWrite
        Delta    = [math]::Round($curWrite - $prevWrite, 2)
        Status   = if (($curWrite - $prevWrite) -gt 5) { "Improved" } elseif (($curWrite - $prevWrite) -lt -5) { "Degraded" } else { "Unchanged" }
    }

    # Disk read throughput
    $prevRead = if ($null -ne $prev.DiskReadMBps) { $prev.DiskReadMBps } else { 0 }
    $curRead  = if ($null -ne $CurrentEntry.DiskReadMBps) { $CurrentEntry.DiskReadMBps } else { 0 }
    $deltas += [PSCustomObject]@{
        Metric   = "Disk Read MB/s"
        Previous = $prevRead
        Current  = $curRead
        Delta    = [math]::Round($curRead - $prevRead, 2)
        Status   = if (($curRead - $prevRead) -gt 5) { "Improved" } elseif (($curRead - $prevRead) -lt -5) { "Degraded" } else { "Unchanged" }
    }

    # Network latency (average ping to 8.8.8.8)
    $prevPing = if ($null -ne $prev.AvgPingMS) { $prev.AvgPingMS } else { 0 }
    $curPing  = if ($null -ne $CurrentEntry.AvgPingMS) { $CurrentEntry.AvgPingMS } else { 0 }
    $deltas += [PSCustomObject]@{
        Metric   = "Avg Ping (8.8.8.8) ms"
        Previous = $prevPing
        Current  = $curPing
        Delta    = [math]::Round($curPing - $prevPing, 2)
        Status   = if (($curPing - $prevPing) -gt 5) { "Degraded" } elseif (($curPing - $prevPing) -lt -5) { "Improved" } else { "Unchanged" }
    }

    [PSCustomObject]@{
        HasPrevious   = $true
        PreviousDate  = $prev.Timestamp
        Note          = "Comparing against previous run from $($prev.Timestamp)."
        Deltas        = $deltas
    }
}

function Get-SystemCategory {
    param($Score, $DiskWriteMBps, $TotalRAMGB, $CPUName)

    # Classify the system based on score and hardware
    $category = "Low-end PC"
    $notes = @()

    # RAM-based classification
    if ($TotalRAMGB -ge 64) { $ramTier = 4; $notes += "RAM: Workstation-class ($TotalRAMGB GB)" }
    elseif ($TotalRAMGB -ge 32) { $ramTier = 3; $notes += "RAM: High-end ($TotalRAMGB GB)" }
    elseif ($TotalRAMGB -ge 16) { $ramTier = 2; $notes += "RAM: Mid-range ($TotalRAMGB GB)" }
    elseif ($TotalRAMGB -ge 8) { $ramTier = 1; $notes += "RAM: Entry-level ($TotalRAMGB GB)" }
    else { $ramTier = 0; $notes += "RAM: Below minimum ($TotalRAMGB GB)" }

    # Disk-based classification
    if ($null -eq $DiskWriteMBps -or $DiskWriteMBps -le 0) { $diskTier = 1 }
    elseif ($DiskWriteMBps -ge 1500) { $diskTier = 4; $notes += "Disk: NVMe-class ($DiskWriteMBps MB/s write)" }
    elseif ($DiskWriteMBps -ge 400) { $diskTier = 3; $notes += "Disk: SSD-class ($DiskWriteMBps MB/s write)" }
    elseif ($DiskWriteMBps -ge 100) { $diskTier = 2; $notes += "Disk: Fast HDD/slow SSD ($DiskWriteMBps MB/s write)" }
    else { $diskTier = 1; $notes += "Disk: HDD-class ($DiskWriteMBps MB/s write)" }

    # Score-based classification
    if ($Score -ge 90) { $scoreTier = 4 }
    elseif ($Score -ge 75) { $scoreTier = 3 }
    elseif ($Score -ge 55) { $scoreTier = 2 }
    else { $scoreTier = 1 }

    $avgTier = [math]::Round(($ramTier + $diskTier + $scoreTier) / 3, 1)

    if ($avgTier -ge 3.5) { $category = "Workstation / High-Performance" }
    elseif ($avgTier -ge 2.5) { $category = "High-end PC" }
    elseif ($avgTier -ge 1.5) { $category = "Mid-range PC" }
    else { $category = "Low-end PC" }

    [PSCustomObject]@{
        Category   = $category
        AvgTier    = $avgTier
        ScoreTier  = $scoreTier
        RAMTier    = $ramTier
        DiskTier   = $diskTier
        Notes      = $notes
        Comparison = @(
            [PSCustomObject]@{ Tier="Low-end PC"; ScoreRange="0-54"; RAM="< 8 GB"; DiskWrite="< 100 MB/s" }
            [PSCustomObject]@{ Tier="Mid-range PC"; ScoreRange="55-74"; RAM="8-15 GB"; DiskWrite="100-399 MB/s" }
            [PSCustomObject]@{ Tier="High-end PC"; ScoreRange="75-89"; RAM="16-31 GB"; DiskWrite="400-1499 MB/s" }
            [PSCustomObject]@{ Tier="Workstation"; ScoreRange="90-100"; RAM="32+ GB"; DiskWrite="1500+ MB/s" }
        )
    }
}

# ============================================================
# Score
# ============================================================

function Get-PCPlusWindowsHealthScore {
    param($Data)

    $score = 100
    $issues = @()

    # SFC/DISM
    if ($Data.SFC.Summary -match "FAIL") { $score -= 20; $issues += $Data.SFC.Summary }
    elseif ($Data.SFC.Summary -match "REPAIRED|WARNING") { $score -= 8; $issues += $Data.SFC.Summary }

    if ($Data.DISM.CheckHealth -match "WARNING") { $score -= 8; $issues += $Data.DISM.CheckHealth }
    if ($Data.DISM.ScanHealth -match "WARNING") { $score -= 10; $issues += $Data.DISM.ScanHealth }

    # File system
    foreach ($fs in $Data.FileSystemHealth) {
        if ($fs.DirtyBit -match "dirty") { $score -= 10; $issues += "$($fs.Drive) dirty bit set." }
        if ($fs.ChkdskSummary -match "WARNING|problems") { $score -= 10; $issues += "$($fs.Drive): $($fs.ChkdskSummary)" }
        if ($fs.FreePercent -lt 10) { $score -= 10; $issues += "$($fs.Drive) low free space: $($fs.FreePercent)%" }
    }

    # Devices
    if ($Data.DriverDeviceHealth.ProblemDeviceCount -gt 0) {
        $score -= [math]::Min(15, $Data.DriverDeviceHealth.ProblemDeviceCount * 3)
        $issues += "$($Data.DriverDeviceHealth.ProblemDeviceCount) device/driver issue(s) detected."
    }

    # Services
    $badServices = @($Data.ServiceHealth | Where-Object {$_.Healthy -eq $false})
    if ($badServices.Count -gt 0) {
        $score -= [math]::Min(15, $badServices.Count * 3)
        $issues += "$($badServices.Count) important service(s) not healthy."
    }

    # WMI
    if ($Data.WmiHealth.RepositoryStatus -notmatch "consistent") {
        $score -= 10
        $issues += "WMI repository may need review: $($Data.WmiHealth.RepositoryStatus)"
    }

    # Event counts
    foreach ($e in $Data.EventLogScan) {
        if ($e.Count -gt 0 -and $e.Category -match "Blue Screen|WHEA|Disk Bad|NTFS|Storage Reset") {
            $score -= 10
            $issues += "$($e.Category): $($e.Count) event(s)."
        } elseif ($e.Count -gt 0 -and $e.Category -match "Unexpected Shutdown|Application Error|Application Hang") {
            $score -= 5
            $issues += "$($e.Category): $($e.Count) event(s)."
        }
    }

    # Responsiveness
    foreach ($r in $Data.Responsiveness) {
        if ($r.Success -eq $false) {
            $score -= 5
            $issues += "Responsiveness failed: $($r.Test)"
        } elseif ($r.ResponseMS -gt 5000) {
            $score -= 4
            $issues += "Slow response: $($r.Test) took $($r.ResponseMS) ms."
        }
    }

    # Windows Update
    if ($Data.WindowsUpdateHealth.RebootPending) {
        $score -= 5
        $issues += "Windows reboot pending."
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

function New-PCPlusWindowsHtmlReport {
    param($Data)

    $scoreColor = if ($Data.Score.Score -ge 80) { "#16a34a" } elseif ($Data.Score.Score -ge 60) { "#f59e0b" } else { "#dc2626" }

    $issueHtml = if ($Data.Score.Issues.Count -gt 0) {
        ($Data.Score.Issues | ForEach-Object { "<li>$_</li>" }) -join "`n"
    } else {
        "<li>No major Windows performance or integrity issues detected.</li>"
    }

    $fsRows = foreach ($f in $Data.FileSystemHealth) {
        "<tr><td>$($f.Drive)</td><td>$($f.FileSystem)</td><td>$($f.SizeGB) GB</td><td>$($f.FreePercent)%</td><td>$($f.DirtyBit)</td><td>$($f.ChkdskSummary)</td></tr>"
    }

    $respRows = foreach ($r in $Data.Responsiveness) {
        "<tr><td>$($r.Test)</td><td>$($r.Success)</td><td>$($r.ResponseMS)</td><td>$($r.Notes)</td></tr>"
    }

    $eventRows = foreach ($e in $Data.EventLogScan) {
        "<tr><td>$($e.Category)</td><td>$($e.DaysChecked)</td><td>$($e.Count)</td><td>$($e.MostRecent)</td></tr>"
    }

    $serviceRows = foreach ($s in $Data.ServiceHealth) {
        $class = if ($s.Healthy) { "pass" } else { "fail" }
        "<tr><td>$($s.Name)</td><td>$($s.DisplayName)</td><td class='$class'>$($s.Status)</td><td>$($s.StartType)</td></tr>"
    }

    $netRows = foreach ($n in $Data.NetworkResponse.PingResults) {
        "<tr><td>$($n.Target)</td><td>$($n.Received)/$($n.Sent)</td><td>$($n.PacketLossPercent)%</td><td>$($n.AverageMS)</td><td>$($n.MaxMS)</td></tr>"
    }

$html = @"
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<title>PC Plus 360 Deep Windows Performance & Integrity Report</title>
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
</style>
</head>
<body>
<div class="header">
  <h1>PC Plus 360 Deep Windows Performance & Integrity Report</h1>
  <p>PC Plus Computing | 604-760-1662 | pcpluscomputing.com | Your Security, Our Priority</p>
</div>

<div class="container">
  <div class="card">
    <h2>Executive Summary</h2>
    <div class="grid">
      <div class="metric"><b>Customer</b><span>$($Data.System.CustomerName)</span></div>
      <div class="metric"><b>Technician</b><span>$($Data.System.TechnicianName)</span></div>
      <div class="metric"><b>Computer</b><span>$($Data.System.ComputerName)</span></div>
      <div class="metric"><b>Mode</b><span>$($Data.System.Mode)</span></div>
    </div>
    <div class="score">$($Data.Score.Score)/100</div>
    <p><span class="badge">$($Data.Score.Grade)</span></p>
    <h3>Top Findings</h3>
    <ul>$issueHtml</ul>
  </div>

  <div class="card">
    <h2>Windows Integrity</h2>
    <table>
      <tr><th>Test</th><th>Result</th><th>Seconds</th></tr>
      <tr><td>SFC</td><td>$($Data.SFC.Summary)</td><td>$($Data.SFC.Seconds)</td></tr>
      <tr><td>DISM CheckHealth</td><td>$($Data.DISM.CheckHealth)</td><td>$($Data.DISM.CheckHealthSeconds)</td></tr>
      <tr><td>DISM ScanHealth</td><td>$($Data.DISM.ScanHealth)</td><td>$($Data.DISM.ScanHealthSeconds)</td></tr>
      <tr><td>DISM RestoreHealth</td><td>$($Data.DISM.RestoreHealth)</td><td>$($Data.DISM.RestoreHealthSeconds)</td></tr>
    </table>
  </div>

  <div class="card">
    <h2>File System Integrity</h2>
    <table>
      <tr><th>Drive</th><th>File System</th><th>Size</th><th>Free</th><th>Dirty Bit</th><th>CHKDSK Summary</th></tr>
      $($fsRows -join "`n")
    </table>
  </div>

  <div class="card">
    <h2>Responsiveness Test</h2>
    <table>
      <tr><th>Test</th><th>Success</th><th>Response MS</th><th>Notes</th></tr>
      $($respRows -join "`n")
    </table>
  </div>

  <div class="card">
    <h2>Critical Service Health</h2>
    <table>
      <tr><th>Service</th><th>Display Name</th><th>Status</th><th>Start Type</th></tr>
      $($serviceRows -join "`n")
    </table>
  </div>

  <div class="card">
    <h2>Deep Event Log Scan</h2>
    <table>
      <tr><th>Category</th><th>Days Checked</th><th>Count</th><th>Most Recent</th></tr>
      $($eventRows -join "`n")
    </table>
  </div>

  <div class="card">
    <h2>Network Response</h2>
    <table>
      <tr><th>Target</th><th>Received</th><th>Packet Loss</th><th>Average MS</th><th>Max MS</th></tr>
      $($netRows -join "`n")
    </table>
    <p>DNS lookup for google.com: $($Data.NetworkResponse.DnsLookupGoogleMS) ms</p>
  </div>

  <div class="card">
    <h2>Power / Sleep Reports</h2>
    <p>Energy Report: $($Data.PowerReports.EnergyReport)</p>
    <p>Sleep Study: $($Data.PowerReports.SleepStudy)</p>
    <p>Battery Report: $($Data.PowerReports.BatteryReport)</p>
  </div>

  <div class="card">
    <h2>Disk I/O Benchmark</h2>
    <table>
      <tr><th>Test</th><th>Size MB</th><th>Seconds</th><th>Throughput MB/s</th><th>Notes</th></tr>
      $(foreach ($db in $Data.DiskBenchmark) {
        "<tr><td>$($db.Test)</td><td>$($db.SizeMB)</td><td>$($db.Seconds)</td><td>$($db.ThroughputMBps)</td><td>$($db.Notes)</td></tr>"
      })
    </table>
  </div>

  <div class="card">
    <h2>Network Performance Benchmark</h2>
    <h3>DNS Lookup Times</h3>
    <table>
      <tr><th>Target</th><th>Resolved IP</th><th>Lookup MS</th><th>Success</th></tr>
      $(foreach ($dns in $Data.NetworkBenchmark.DNSLookups) {
        "<tr><td>$($dns.Target)</td><td>$($dns.ResolvedIP)</td><td>$($dns.LookupMS)</td><td>$($dns.Success)</td></tr>"
      })
    </table>
    <h3>Ping Latency</h3>
    <table>
      <tr><th>Name</th><th>IP</th><th>Recv/Sent</th><th>Loss %</th><th>Avg MS</th><th>Min MS</th><th>Max MS</th><th>Jitter MS</th></tr>
      $(foreach ($pl in $Data.NetworkBenchmark.PingLatency) {
        "<tr><td>$($pl.Name)</td><td>$($pl.IP)</td><td>$($pl.Received)/$($pl.Sent)</td><td>$($pl.PacketLoss)%</td><td>$($pl.AvgMS)</td><td>$($pl.MinMS)</td><td>$($pl.MaxMS)</td><td>$($pl.JitterMS)</td></tr>"
      })
    </table>
  </div>

  <div class="card">
    <h2>System Classification</h2>
    <p><b>This System:</b> <span class="badge" style="font-size:16px;">$($Data.SystemCategory.Category)</span></p>
    <ul>
      $(($Data.SystemCategory.Notes | ForEach-Object { "<li>$_</li>" }) -join "`n")
    </ul>
    <h3>Typical System Categories</h3>
    <table>
      <tr><th>Category</th><th>Score Range</th><th>RAM</th><th>Disk Write</th></tr>
      $(foreach ($c in $Data.SystemCategory.Comparison) {
        $highlight = if ($c.Tier -eq $Data.SystemCategory.Category -or ($c.Tier -eq "Workstation" -and $Data.SystemCategory.Category -match "Workstation")) { " style='background:#eaf7fc;font-weight:700;'" } else { "" }
        "<tr$highlight><td>$($c.Tier)</td><td>$($c.ScoreRange)</td><td>$($c.RAM)</td><td>$($c.DiskWrite)</td></tr>"
      })
    </table>
  </div>

  <div class="card">
    <h2>Performance Trend</h2>
    <p><b>$($Data.PerfTrend.Note)</b></p>
    $(if ($Data.PerfTrend.HasPrevious) {
        $tRows = foreach ($d in $Data.PerfTrend.Deltas) {
            $tClass = if ($d.Status -eq "Degraded") { "fail" } elseif ($d.Status -eq "Improved") { "pass" } else { "warn" }
            "<tr><td>$($d.Metric)</td><td>$($d.Previous)</td><td>$($d.Current)</td><td class='$tClass'>$($d.Delta) ($($d.Status))</td></tr>"
        }
        "<table><tr><th>Metric</th><th>Previous</th><th>Current</th><th>Delta</th></tr>$($tRows -join "`n")</table>"
    } else {
        "<p>No previous runs to compare. This session establishes the baseline.</p>"
    })
    <p>Trend history: <code>$PerfTrendFile</code></p>
  </div>

  <div class="card">
    <h2>Technician Recommendation</h2>
    <p>If hardware tests pass but Windows score is low, focus on Windows corruption, startup apps, service problems, disk/file system issues, driver crashes, update failures, or application instability.</p>
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
# MAIN
# ============================================================

Write-PCLog "PC Plus 360 Deep Windows Performance & Integrity Test started."
Write-PCLog "Mode: $Mode | RunRepair: $RunRepair"

if (-not (Test-IsAdmin)) {
    Write-PCLog "Not running as Administrator. Some tests may be limited. Please run as Administrator for best results." "WARN"
}

$Data = [ordered]@{}

$Data.System = Get-PCPlusSystemInfo
$Data.SFC = Invoke-PCPlusSFC
$Data.DISM = Invoke-PCPlusDISM
$Data.FileSystemHealth = @(Get-PCPlusFileSystemHealth)
$Data.BootPerformance = Get-PCPlusBootPerformance
$Data.Responsiveness = @(Test-PCPlusResponsiveness)
$Data.StartupHealth = Get-PCPlusStartupHealth
$Data.ServiceHealth = @(Test-PCPlusServiceHealth)
$Data.WmiHealth = Test-PCPlusWmiHealth
$Data.DriverDeviceHealth = Get-PCPlusDriverDeviceHealth
$Data.EventLogScan = @(Get-PCPlusDeepEventLogScan)
$Data.WindowsUpdateHealth = Get-PCPlusWindowsUpdateHealth
$Data.PowerReports = Invoke-PCPlusPowerReports
$Data.NetworkResponse = Test-PCPlusNetworkResponse
$Data.DiskBenchmark = @(Invoke-PCPlusDiskBenchmark)
$Data.NetworkBenchmark = Invoke-PCPlusNetworkBenchmark

$Data.Score = Get-PCPlusWindowsHealthScore -Data $Data

# Extract key metrics for trend entry and system classification
$diskWriteResult = $Data.DiskBenchmark | Where-Object { $_.Test -match "Write" -and $_.Success } | Select-Object -First 1
$diskReadResult  = $Data.DiskBenchmark | Where-Object { $_.Test -match "Read" -and $_.Success } | Select-Object -First 1
$diskWriteMBps = if ($diskWriteResult) { $diskWriteResult.ThroughputMBps } else { $null }
$diskReadMBps  = if ($diskReadResult) { $diskReadResult.ThroughputMBps } else { $null }
$avgPingResult = $Data.NetworkBenchmark.PingLatency | Where-Object { $_.IP -eq "8.8.8.8" } | Select-Object -First 1
$avgPingMS = if ($avgPingResult) { $avgPingResult.AvgMS } else { $null }

# System classification
$Data.SystemCategory = Get-SystemCategory -Score $Data.Score.Score -DiskWriteMBps $diskWriteMBps -TotalRAMGB $Data.System.TotalRAMGB -CPUName $Data.System.CPU

# Build and save trend entry
$perfTrendEntry = [PSCustomObject]@{
    Timestamp     = (Get-Date -Format "o")
    ComputerName  = $env:COMPUTERNAME
    Mode          = $Mode
    Score         = $Data.Score.Score
    Grade         = $Data.Score.Grade
    DiskWriteMBps = $diskWriteMBps
    DiskReadMBps  = $diskReadMBps
    AvgPingMS     = $avgPingMS
    TotalRAMGB    = $Data.System.TotalRAMGB
    Category      = $Data.SystemCategory.Category
}

$Data.PerfTrend = Get-PerfTrendComparison -CurrentEntry $perfTrendEntry
Save-PerfTrendEntry -Entry $perfTrendEntry
Write-PCLog "Performance trend entry saved to $PerfTrendFile."

$Data | ConvertTo-Json -Depth 12 | Set-Content -Path $JsonFile -Encoding UTF8

$summary = @"
PC Plus 360 Deep Windows Performance & Integrity Test

Customer: $CustomerName
Technician: $TechnicianName
Computer: $($Data.System.ComputerName)
Model: $($Data.System.Manufacturer) $($Data.System.Model)
Serial: $($Data.System.SerialNumber)
Windows: $($Data.System.OS) Build $($Data.System.Build)
Mode: $Mode
Repair Mode: $RunRepair

Windows Health Score: $($Data.Score.Score)/100
Grade: $($Data.Score.Grade)

Top Findings:
$($Data.Score.Issues -join "`r`n")

SFC:
$($Data.SFC.Summary)

DISM:
CheckHealth: $($Data.DISM.CheckHealth)
ScanHealth: $($Data.DISM.ScanHealth)
RestoreHealth: $($Data.DISM.RestoreHealth)

Disk I/O Benchmark:
Write: $diskWriteMBps MB/s
Read: $diskReadMBps MB/s

System Classification: $($Data.SystemCategory.Category)

Network Benchmark:
Avg Ping (8.8.8.8): $avgPingMS ms

Report Folder:
$ReportDir
"@

Set-Content -Path $TxtFile -Value $summary -Encoding UTF8

[PSCustomObject]@{
    ComputerName = $Data.System.ComputerName
    CustomerName = $CustomerName
    Score = $Data.Score.Score
    Grade = $Data.Score.Grade
    SFC = $Data.SFC.Summary
    DISMCheck = $Data.DISM.CheckHealth
    ProblemDevices = $Data.DriverDeviceHealth.ProblemDeviceCount
    RebootPending = $Data.WindowsUpdateHealth.RebootPending
    DiskWriteMBps = $diskWriteMBps
    DiskReadMBps = $diskReadMBps
    AvgPingMS = $avgPingMS
    SystemCategory = $Data.SystemCategory.Category
    ReportDate = Get-Date
} | Export-Csv -Path $CsvFile -NoTypeInformation

New-PCPlusWindowsHtmlReport -Data $Data

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "PC Plus 360 Deep Windows Test Completed" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "Report Folder: $ReportDir"
Write-Host "HTML Report:   $HtmlFile"
Write-Host "JSON Raw Data: $JsonFile"
Write-Host "TXT Summary:   $TxtFile"
Write-Host "CSV Summary:   $CsvFile"
Write-Host "Log File:      $LogFile"
# Display additional benchmark results
Write-Host ""
Write-Host "Disk I/O Benchmark:" -ForegroundColor Green
if ($diskWriteMBps) { Write-Host "  Sequential Write: $diskWriteMBps MB/s" }
if ($diskReadMBps)  { Write-Host "  Sequential Read:  $diskReadMBps MB/s" }

Write-Host ""
Write-Host "System Classification: $($Data.SystemCategory.Category)" -ForegroundColor Green
$Data.SystemCategory.Notes | ForEach-Object { Write-Host "  - $_" }

Write-Host ""
Write-Host "Performance Trend:" -ForegroundColor Green
Write-Host "  $($Data.PerfTrend.Note)"
if ($Data.PerfTrend.HasPrevious) {
    foreach ($d in $Data.PerfTrend.Deltas) {
        $color = if ($d.Status -eq "Degraded") { "Red" } elseif ($d.Status -eq "Improved") { "Green" } else { "Gray" }
        Write-Host "  $($d.Metric): Prev=$($d.Previous), Now=$($d.Current), Delta=$($d.Delta) ($($d.Status))" -ForegroundColor $color
    }
}
Write-Host "Trend File: $PerfTrendFile"

Write-Host ""
Write-PCLog "PC Plus 360 Deep Windows Performance & Integrity Test completed."

# -JsonOutput: Emit structured JSON to stdout for ReportCard integration
if ($JsonOutput) {
    $reportCardData = [PSCustomObject]@{
        ScriptName      = "PCPlus360-Deep-Windows-Performance-Integrity-Test"
        Version         = "2.0"
        Timestamp       = (Get-Date -Format "o")
        ComputerName    = $env:COMPUTERNAME
        CustomerName    = $CustomerName
        TechnicianName  = $TechnicianName
        Mode            = $Mode
        Score           = $Data.Score.Score
        Grade           = $Data.Score.Grade
        Issues          = $Data.Score.Issues
        SFC             = $Data.SFC.Summary
        DISMCheck       = $Data.DISM.CheckHealth
        ProblemDevices  = $Data.DriverDeviceHealth.ProblemDeviceCount
        RebootPending   = $Data.WindowsUpdateHealth.RebootPending
        DiskWriteMBps   = $diskWriteMBps
        DiskReadMBps    = $diskReadMBps
        AvgPingMS       = $avgPingMS
        SystemCategory  = $Data.SystemCategory.Category
        TotalRAMGB      = $Data.System.TotalRAMGB
        CPU             = $Data.System.CPU
        TrendPrevious   = $Data.PerfTrend.HasPrevious
        TrendPrevDate   = $Data.PerfTrend.PreviousDate
        ReportPath      = $HtmlFile
        ReportDir       = $ReportDir
    }
    $reportCardData | ConvertTo-Json -Depth 4
}

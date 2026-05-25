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
# AUTOMATED REPAIR SUGGESTIONS
# Maps each failed test to actionable fix suggestions
# ============================================================

function Get-PCPlusRepairSuggestions {
    param($Data)
    $suggestions = @()

    # SFC failures
    if ($Data.SFC.Summary -match "FAIL") {
        $suggestions += [PSCustomObject]@{
            Category = "Windows Integrity"; Issue = "SFC found unfixable corrupt files"
            Severity = "Critical"; AutoFixable = $true
            RepairCommand = "DISM /Online /Cleanup-Image /RestoreHealth && sfc /scannow"
            ManualSteps = "1. Run DISM RestoreHealth first. 2. Re-run SFC. 3. If still failing, consider in-place Windows upgrade."
        }
    }
    elseif ($Data.SFC.Summary -match "REPAIRED|WARNING") {
        $suggestions += [PSCustomObject]@{
            Category = "Windows Integrity"; Issue = "SFC found and repaired corrupt files"
            Severity = "Moderate"; AutoFixable = $false
            RepairCommand = ""; ManualSteps = "Re-run SFC to verify all repairs hold. Monitor for recurrence."
        }
    }

    # DISM failures
    if ($Data.DISM.CheckHealth -match "WARNING" -or $Data.DISM.ScanHealth -match "WARNING") {
        $suggestions += [PSCustomObject]@{
            Category = "Component Store"; Issue = "DISM reports repairable component store corruption"
            Severity = "High"; AutoFixable = $true
            RepairCommand = "DISM /Online /Cleanup-Image /RestoreHealth"
            ManualSteps = "Run DISM RestoreHealth with internet connection for Windows Update source files."
        }
    }

    # File system issues
    foreach ($fs in $Data.FileSystemHealth) {
        if ($fs.DirtyBit -match "dirty") {
            $suggestions += [PSCustomObject]@{
                Category = "File System"; Issue = "$($fs.Drive) dirty bit is set"
                Severity = "High"; AutoFixable = $true
                RepairCommand = "chkdsk $($fs.Drive) /f /r"
                ManualSteps = "Schedule CHKDSK for next reboot. The dirty bit indicates an improper shutdown or file system error."
            }
        }
        if ($fs.ChkdskSummary -match "WARNING|problems") {
            $suggestions += [PSCustomObject]@{
                Category = "File System"; Issue = "$($fs.Drive) CHKDSK found problems"
                Severity = "High"; AutoFixable = $true
                RepairCommand = "chkdsk $($fs.Drive) /f /r"
                ManualSteps = "Back up important data, then schedule CHKDSK with /f /r flags for repair on next reboot."
            }
        }
        if ($fs.FreePercent -lt 10) {
            $suggestions += [PSCustomObject]@{
                Category = "Storage Space"; Issue = "$($fs.Drive) has only $($fs.FreePercent)% free space"
                Severity = "High"; AutoFixable = $true
                RepairCommand = "cleanmgr /d $($fs.Drive.Replace(':',''))"
                ManualSteps = "Run Disk Cleanup, empty recycle bin, remove temp files, uninstall unused programs."
            }
        }
    }

    # Device issues
    if ($Data.DriverDeviceHealth.ProblemDeviceCount -gt 0) {
        $suggestions += [PSCustomObject]@{
            Category = "Device Drivers"; Issue = "$($Data.DriverDeviceHealth.ProblemDeviceCount) device(s) reporting errors"
            Severity = "Moderate"; AutoFixable = $false
            RepairCommand = ""
            ManualSteps = "Open Device Manager, right-click problem devices, update or reinstall drivers. Check manufacturer website."
        }
    }

    # Service issues
    $badServices = @($Data.ServiceHealth | Where-Object { $_.Healthy -eq $false })
    if ($badServices.Count -gt 0) {
        foreach ($svc in $badServices) {
            $suggestions += [PSCustomObject]@{
                Category = "Windows Services"; Issue = "Service '$($svc.DisplayName)' is $($svc.Status)"
                Severity = "Moderate"; AutoFixable = $true
                RepairCommand = "net start $($svc.Name)"
                ManualSteps = "Try starting the service manually. If it fails, check dependencies and event logs."
            }
        }
    }

    # WMI issues
    if ($Data.WmiHealth.RepositoryStatus -notmatch "consistent") {
        $suggestions += [PSCustomObject]@{
            Category = "WMI Repository"; Issue = "WMI repository may be inconsistent"
            Severity = "Moderate"; AutoFixable = $true
            RepairCommand = "winmgmt /salvagerepository"
            ManualSteps = "Try salvage first. If it fails, use winmgmt /resetrepository (resets all WMI data)."
        }
    }

    # Windows Update issues
    if ($Data.WindowsUpdateHealth.RebootPending) {
        $suggestions += [PSCustomObject]@{
            Category = "Windows Update"; Issue = "Windows reboot pending for updates"
            Severity = "Low"; AutoFixable = $false
            RepairCommand = ""
            ManualSteps = "Restart the computer to complete pending Windows updates."
        }
    }

    return $suggestions
}

# ============================================================
# CORRUPTION SCORING (0-100 System Integrity Score)
# Provides a focused score on Windows file/component integrity
# ============================================================

function Get-PCPlusCorruptionScore {
    param($Data)

    $score = 100
    $details = @()

    # SFC weight: 25 points
    if ($Data.SFC.Summary -match "FAIL") { $score -= 25; $details += "SFC found unfixable corruption (-25)" }
    elseif ($Data.SFC.Summary -match "REPAIRED") { $score -= 10; $details += "SFC repaired files (-10)" }
    elseif ($Data.SFC.Summary -match "WARNING") { $score -= 8; $details += "SFC warning (-8)" }

    # DISM weight: 20 points
    if ($Data.DISM.CheckHealth -match "WARNING") { $score -= 10; $details += "DISM CheckHealth warning (-10)" }
    if ($Data.DISM.ScanHealth -match "WARNING") { $score -= 10; $details += "DISM ScanHealth warning (-10)" }

    # File system weight: 20 points
    foreach ($fs in $Data.FileSystemHealth) {
        if ($fs.DirtyBit -match "dirty") { $score -= 10; $details += "$($fs.Drive) dirty bit (-10)" }
        if ($fs.ChkdskSummary -match "WARNING|problems") { $score -= 10; $details += "$($fs.Drive) CHKDSK issues (-10)" }
    }

    # WMI weight: 10 points
    if ($Data.WmiHealth.RepositoryStatus -notmatch "consistent") { $score -= 10; $details += "WMI repository inconsistent (-10)" }

    # Event log corruption indicators: 15 points
    foreach ($e in $Data.EventLogScan) {
        if ($e.Count -gt 0 -and $e.Category -match "NTFS Corruption") {
            $score -= 15; $details += "NTFS corruption events: $($e.Count) (-15)"
            break
        }
    }

    # Services: 10 points
    $badServices = @($Data.ServiceHealth | Where-Object { $_.Healthy -eq $false })
    if ($badServices.Count -gt 0) {
        $deduct = [math]::Min(10, $badServices.Count * 2)
        $score -= $deduct
        $details += "$($badServices.Count) unhealthy services (-$deduct)"
    }

    $score = [math]::Max(0, $score)
    $integrityGrade = if ($score -ge 90) { "Excellent" }
                      elseif ($score -ge 80) { "Good" }
                      elseif ($score -ge 70) { "Fair" }
                      elseif ($score -ge 50) { "Degraded" }
                      else { "Critical" }

    return [PSCustomObject]@{
        IntegrityScore = $score
        IntegrityGrade = $integrityGrade
        Details = $details
    }
}

# ============================================================
# ROLLBACK SUPPORT & SAFE REPAIR
# Creates restore point, attempts fixes, logs all changes
# ============================================================

function Invoke-PCPlusSafeRepair {
    param($Data, $Suggestions, [string]$LogDir)

    $changeLog = @()
    $rollbackInfo = @{
        RestorePointCreated = $false
        RestorePointName = $null
        ChangesAttempted = @()
        ChangesSucceeded = @()
        ChangesFailed = @()
        StartTime = Get-Date
        EndTime = $null
    }

    # Step 1: Create restore point
    Write-PCLog "Safe Repair: Creating system restore point..."
    try {
        $rpName = "PCPlus360 Safe Repair - $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
        Checkpoint-Computer -Description $rpName -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
        $rollbackInfo.RestorePointCreated = $true
        $rollbackInfo.RestorePointName = $rpName
        Write-PCLog "Restore point created: $rpName"
        $changeLog += "[$(Get-Date -Format 'HH:mm:ss')] Created restore point: $rpName"
    } catch {
        Write-PCLog "Failed to create restore point: $($_.Exception.Message)" "WARN"
        $changeLog += "[$(Get-Date -Format 'HH:mm:ss')] FAILED to create restore point: $($_.Exception.Message)"
    }

    # Step 2: Attempt auto-fixable repairs
    $autoFixes = @($Suggestions | Where-Object { $_.AutoFixable -eq $true -and $_.RepairCommand })
    foreach ($fix in $autoFixes) {
        Write-PCLog "Safe Repair: Attempting fix for '$($fix.Issue)'..."
        $changeLog += "[$(Get-Date -Format 'HH:mm:ss')] Attempting: $($fix.Category) - $($fix.Issue)"
        $rollbackInfo.ChangesAttempted += $fix.Issue

        try {
            # Only run safe commands
            $cmd = $fix.RepairCommand
            if ($cmd -match "^(net start|cleanmgr|winmgmt)") {
                $result = cmd.exe /c "$cmd" 2>&1
                $rollbackInfo.ChangesSucceeded += $fix.Issue
                $changeLog += "[$(Get-Date -Format 'HH:mm:ss')] SUCCESS: $($fix.Issue)"
                Write-PCLog "Safe Repair: Fixed '$($fix.Issue)'"
            } else {
                # Skip potentially dangerous commands in automated mode
                $changeLog += "[$(Get-Date -Format 'HH:mm:ss')] SKIPPED (requires manual): $($fix.Issue) - Command: $cmd"
                Write-PCLog "Safe Repair: Skipped '$($fix.Issue)' (requires manual execution)" "WARN"
            }
        } catch {
            $rollbackInfo.ChangesFailed += $fix.Issue
            $changeLog += "[$(Get-Date -Format 'HH:mm:ss')] FAILED: $($fix.Issue) - $($_.Exception.Message)"
            Write-PCLog "Safe Repair: Failed '$($fix.Issue)': $($_.Exception.Message)" "ERROR"
        }
    }

    $rollbackInfo.EndTime = Get-Date

    # Save change log
    if ($LogDir) {
        $logPath = Join-Path $LogDir "PCPlus360-SafeRepair-ChangeLog.txt"
        $changeLog | Set-Content -Path $logPath -Encoding UTF8
        Write-PCLog "Safe Repair change log saved: $logPath"
    }

    return [PSCustomObject]@{
        RestorePointCreated = $rollbackInfo.RestorePointCreated
        RestorePointName = $rollbackInfo.RestorePointName
        TotalAttempted = $rollbackInfo.ChangesAttempted.Count
        TotalSucceeded = $rollbackInfo.ChangesSucceeded.Count
        TotalFailed = $rollbackInfo.ChangesFailed.Count
        ChangesAttempted = $rollbackInfo.ChangesAttempted
        ChangesSucceeded = $rollbackInfo.ChangesSucceeded
        ChangesFailed = $rollbackInfo.ChangesFailed
        ChangeLog = $changeLog
        UndoInstructions = if ($rollbackInfo.RestorePointCreated) { "To undo all changes, use System Restore and select restore point: $($rollbackInfo.RestorePointName)" } else { "No restore point was created. Manual reversal may be needed." }
    }
}

# ============================================================
# JSON OUTPUT FOR REPORTCARD INTEGRATION
# ============================================================

function Export-WindowsDeepTestJson {
    param($Data, [string]$OutputFolder)
    if (-not $OutputFolder) { $OutputFolder = "C:\PCPlus360\Reports" }
    if (-not (Test-Path $OutputFolder)) { New-Item -Path $OutputFolder -ItemType Directory -Force | Out-Null }

    $ds = Get-Date -Format "yyyyMMdd-HHmmss"
    $computerSafe = $env:COMPUTERNAME -replace '[^\w\-]', '_'
    $jsonPath = Join-Path $OutputFolder "PCPlus-WindowsDeepTest-$computerSafe-$ds.json"

    $export = @{
        ReportType = "PCPlus-WindowsDeepTest"
        GeneratedAt = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        ComputerName = $env:COMPUTERNAME
        CustomerName = $Data.System.CustomerName
        Mode = $Data.System.Mode
        HealthScore = $Data.Score.Score
        HealthGrade = $Data.Score.Grade
        IntegrityScore = if ($Data.CorruptionScore) { $Data.CorruptionScore.IntegrityScore } else { $null }
        IntegrityGrade = if ($Data.CorruptionScore) { $Data.CorruptionScore.IntegrityGrade } else { $null }
        SFC = $Data.SFC.Summary
        DISM = @{ CheckHealth = $Data.DISM.CheckHealth; ScanHealth = $Data.DISM.ScanHealth; RestoreHealth = $Data.DISM.RestoreHealth }
        ProblemDevices = $Data.DriverDeviceHealth.ProblemDeviceCount
        RebootPending = $Data.WindowsUpdateHealth.RebootPending
        RepairSuggestionCount = if ($Data.RepairSuggestions) { $Data.RepairSuggestions.Count } else { 0 }
        Issues = $Data.Score.Issues
    }

    $export | ConvertTo-Json -Depth 8 | Set-Content -Path $jsonPath -Encoding UTF8
    return $jsonPath
}

# ============================================================
# HTML Report
# ============================================================

function New-PCPlusWindowsHtmlReport {
    param($Data)

    $scoreColor = if ($Data.Score.Score -ge 80) { "#16a34a" } elseif ($Data.Score.Score -ge 60) { "#f59e0b" } else { "#dc2626" }

    # Corruption/Integrity score colors
    $intScore = if ($Data.CorruptionScore) { $Data.CorruptionScore.IntegrityScore } else { $Data.Score.Score }
    $intGrade = if ($Data.CorruptionScore) { $Data.CorruptionScore.IntegrityGrade } else { "N/A" }
    $intColor = if ($intScore -ge 80) { "#16a34a" } elseif ($intScore -ge 60) { "#f59e0b" } else { "#dc2626" }

    $issueHtml = if ($Data.Score.Issues.Count -gt 0) {
        ($Data.Score.Issues | ForEach-Object { "<li>$_</li>" }) -join "`n"
    } else {
        "<li>No major Windows performance or integrity issues detected.</li>"
    }

    # Build repair suggestions HTML
    $repairHtml = ""
    if ($Data.RepairSuggestions -and $Data.RepairSuggestions.Count -gt 0) {
        $repairRows = foreach ($r in $Data.RepairSuggestions) {
            $sevClass = switch ($r.Severity) { "Critical" { "fail" } "High" { "fail" } "Moderate" { "warn" } default { "pass" } }
            $autoIcon = if ($r.AutoFixable) { "&#9889;" } else { "&#128736;" }
            "<tr><td>$($r.Category)</td><td class='$sevClass'>$($r.Severity)</td><td>$($r.Issue)</td><td>$autoIcon $($r.ManualSteps)</td></tr>"
        }
        $repairHtml = @"
  <div class="card">
    <h2>Repair Suggestions</h2>
    <p>$($Data.RepairSuggestions.Count) repair suggestion(s) based on test results:</p>
    <table>
      <tr><th>Category</th><th>Severity</th><th>Issue</th><th>Recommended Fix</th></tr>
      $($repairRows -join "`n")
    </table>
  </div>
"@
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
    <div style="display:flex;gap:20px;margin:14px 0;">
      <div style="text-align:center;flex:1;">
        <div style="font-size:11px;color:#64748b;text-transform:uppercase;font-weight:600;">Health Score</div>
        <div class="score">$($Data.Score.Score)/100</div>
        <p><span class="badge">$($Data.Score.Grade)</span></p>
      </div>
      <div style="text-align:center;flex:1;">
        <div style="font-size:11px;color:#64748b;text-transform:uppercase;font-weight:600;">System Integrity</div>
        <div style="font-size:48px;font-weight:800;color:$intColor;margin:8px 0;">$intScore/100</div>
        <p><span class="badge" style="background:$(if($intScore -ge 80){'#eafaf1'}elseif($intScore -ge 60){'#fffbeb'}else{'#fef5f5'});color:$intColor;">$intGrade</span></p>
      </div>
    </div>
    <h3>Top Findings</h3>
    <ul>$issueHtml</ul>
  </div>

  $repairHtml

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

$Data.Score = Get-PCPlusWindowsHealthScore -Data $Data
$Data.RepairSuggestions = @(Get-PCPlusRepairSuggestions -Data $Data)
$Data.CorruptionScore = Get-PCPlusCorruptionScore -Data $Data

Write-PCLog "Corruption/Integrity Score: $($Data.CorruptionScore.IntegrityScore)/100 ($($Data.CorruptionScore.IntegrityGrade))"
Write-PCLog "Repair Suggestions: $($Data.RepairSuggestions.Count) item(s)"

$Data | ConvertTo-Json -Depth 12 | Set-Content -Path $JsonFile -Encoding UTF8

# JSON output for ReportCard integration
if ($JsonOutput) {
    $jsonExportPath = Export-WindowsDeepTestJson -Data $Data
    Write-PCLog "JSON export for ReportCard: $jsonExportPath"
}

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
Write-Host ""
Write-PCLog "PC Plus 360 Deep Windows Performance & Integrity Test completed."

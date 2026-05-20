<#
PC Plus 360 - Wear & Tear + Approximate Hardware Life Report
Company: PC Plus Computing | pcpluscomputing.com | 604-760-1662

Purpose:
Detailed wear-and-tear report for laptops/desktops:
- approximate remaining hardware life
- SSD/HDD/NVMe wear
- battery wear
- thermal/cooling indicators
- RAM configuration/stability indicators
- GPU/display stability
- Windows reliability/crash history
- device/USB/network wear indicators
- branded HTML, TXT, CSV, JSON outputs

Run:
PowerShell.exe -ExecutionPolicy Bypass -File .\PCPlus360-Wear-And-Tear-Life-Report.ps1 -OpenReport
#>

param(
    [string]$CustomerName = "Customer",
    [string]$TechnicianName = "PC Plus Technician",
    [string]$ToolsDir = "C:\PCPlus360\Tools",
    [switch]$OpenReport
)

$ErrorActionPreference = "Continue"

$BaseDir = "C:\PCPlus360\WearAndTearReports"
$TimeStamp = Get-Date -Format "yyyyMMdd-HHmmss"
$ComputerSafe = $env:COMPUTERNAME -replace '[^\w\-]', '_'
$ReportDir = Join-Path $BaseDir "$ComputerSafe-$TimeStamp"
New-Item -ItemType Directory -Path $ReportDir -Force | Out-Null

$LogFile  = Join-Path $ReportDir "PCPlus360-WearAndTear-Log.txt"
$JsonFile = Join-Path $ReportDir "PCPlus360-WearAndTear-RawData.json"
$HtmlFile = Join-Path $ReportDir "PCPlus360-WearAndTear-Report.html"
$TxtFile  = Join-Path $ReportDir "PCPlus360-WearAndTear-Summary.txt"
$CsvFile  = Join-Path $ReportDir "PCPlus360-WearAndTear-Summary.csv"

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

function Convert-BytesToGB { param([double]$Bytes) if ($null -eq $Bytes) { return $null }; [math]::Round($Bytes / 1GB, 2) }
function Convert-KBToGB { param([double]$KB) if ($null -eq $KB) { return $null }; [math]::Round(($KB * 1KB) / 1GB, 2) }

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
    if ($Score -ge 90) { "3-5+ years estimated remaining life if maintained properly" }
    elseif ($Score -ge 80) { "2-4 years estimated remaining life" }
    elseif ($Score -ge 70) { "1-3 years estimated remaining life; maintenance or upgrade recommended" }
    elseif ($Score -ge 60) { "6-18 months estimated useful life; plan repairs/upgrades soon" }
    else { "Immediate attention recommended; failure/replacement risk is high" }
}

function New-Finding {
    param([string]$Category,[string]$Severity,[string]$Finding,[string]$Recommendation)
    [PSCustomObject]@{Category=$Category;Severity=$Severity;Finding=$Finding;Recommendation=$Recommendation}
}

function Get-PCPlusSystemAge {
    Write-PCLog "Collecting system age and inventory."
    $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
    $bios = Get-CimInstance Win32_BIOS -ErrorAction SilentlyContinue
    $bb = Get-CimInstance Win32_BaseBoard -ErrorAction SilentlyContinue
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    $cpu = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1

    $biosDate = $null
    try { $biosDate = [Management.ManagementDateTimeConverter]::ToDateTime($bios.ReleaseDate) } catch {}
    $installDate = $null
    try { $installDate = $os.InstallDate } catch {}

    $biosAgeYears = if ($biosDate) { [math]::Round(((Get-Date) - $biosDate).TotalDays / 365.25, 1) } else { $null }
    $osAgeYears = if ($installDate) { [math]::Round(((Get-Date) - $installDate).TotalDays / 365.25, 1) } else { $null }

    $score = 100
    $findings = @()

    if ($biosAgeYears -ne $null) {
        if ($biosAgeYears -ge 8) {
            $score -= 25
            $findings += New-Finding "System Age" "High" "BIOS age is approximately $biosAgeYears years." "Plan replacement or major hardware refresh."
        } elseif ($biosAgeYears -ge 5) {
            $score -= 15
            $findings += New-Finding "System Age" "Moderate" "BIOS age is approximately $biosAgeYears years." "System is aging; plan upgrades or replacement timeline."
        } elseif ($biosAgeYears -ge 3) {
            $score -= 5
            $findings += New-Finding "System Age" "Low" "BIOS age is approximately $biosAgeYears years." "Continue monitoring."
        }
    }

    [PSCustomObject]@{
        ComputerName=$env:COMPUTERNAME;CustomerName=$CustomerName;TechnicianName=$TechnicianName
        Manufacturer=$cs.Manufacturer;Model=$cs.Model;SerialNumber=$bios.SerialNumber
        MotherboardManufacturer=$bb.Manufacturer;MotherboardModel=$bb.Product
        BIOSVersion=$bios.SMBIOSBIOSVersion;BIOSDate=$biosDate;BIOSAgeYears=$biosAgeYears
        OS=$os.Caption;OSBuild=$os.BuildNumber;OSInstallDate=$installDate;OSAgeYears=$osAgeYears
        LastBoot=$os.LastBootUpTime;UptimeHours=[math]::Round(((Get-Date)-$os.LastBootUpTime).TotalHours,2)
        CPU=$cpu.Name;TotalRAMGB=Convert-BytesToGB $cs.TotalPhysicalMemory
        Score=[math]::Max(0,$score);Grade=Get-GradeFromScore ([math]::Max(0,$score));Findings=$findings;ReportDate=Get-Date
    }
}

function Get-SmartCtlPath {
    $possible = @(
        (Join-Path $ToolsDir "smartctl.exe"),
        (Join-Path $ToolsDir "smartmontools\bin\smartctl.exe"),
        "C:\Program Files\smartmontools\bin\smartctl.exe",
        "C:\Program Files (x86)\smartmontools\bin\smartctl.exe"
    )
    foreach ($p in $possible) { if (Test-Path $p) { return $p } }
    return $null
}

function Invoke-SmartCtl {
    param([string]$SmartCtlPath,[string]$DeviceId)
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $SmartCtlPath
        $psi.Arguments = "-a `"$DeviceId`""
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
        return $stdout + "`r`n" + $stderr
    } catch { return $null }
}

function Parse-SmartText {
    param([string]$Text)
    $o = [ordered]@{
        Health=$null; PowerOnHours=$null; TemperatureC=$null; PercentageUsed=$null; UnsafeShutdowns=$null
        ReallocatedSectors=$null; PendingSectors=$null; UncorrectableErrors=$null; TotalHostWritesTB=$null
    }
    if (-not $Text) { return [PSCustomObject]$o }

    if ($Text -match "SMART overall-health self-assessment test result:\s*(\w+)") { $o.Health=$matches[1] }
    elseif ($Text -match "SMART Health Status:\s*(\w+)") { $o.Health=$matches[1] }

    if ($Text -match "Power_On_Hours.*?\s(\d+)\s*$") { $o.PowerOnHours=[int64]$matches[1] }
    elseif ($Text -match "Power On Hours:\s*([0-9,]+)") { $o.PowerOnHours=[int64](($matches[1])-replace ",","") }

    if ($Text -match "Temperature_Celsius.*?\s(\d+)\s*$") { $o.TemperatureC=[int]$matches[1] }
    elseif ($Text -match "Temperature:\s*([0-9]+)\s*Celsius") { $o.TemperatureC=[int]$matches[1] }

    if ($Text -match "Percentage Used:\s*([0-9]+)%") { $o.PercentageUsed=[int]$matches[1] }
    if ($Text -match "Unsafe Shutdowns:\s*([0-9,]+)") { $o.UnsafeShutdowns=[int64](($matches[1])-replace ",","") }
    if ($Text -match "Reallocated_Sector_Ct.*?\s(\d+)\s*$") { $o.ReallocatedSectors=[int64]$matches[1] }
    if ($Text -match "Current_Pending_Sector.*?\s(\d+)\s*$") { $o.PendingSectors=[int64]$matches[1] }
    if ($Text -match "Offline_Uncorrectable.*?\s(\d+)\s*$") { $o.UncorrectableErrors=[int64]$matches[1] }

    if ($Text -match "Data Units Written:\s*([0-9,]+)") {
        $units=[double](($matches[1])-replace ",","")
        $o.TotalHostWritesTB=[math]::Round(($units*512000)/1TB,2)
    }
    [PSCustomObject]$o
}

function Get-PCPlusStorageWear {
    Write-PCLog "Collecting storage wear information."
    $smartctl = Get-SmartCtlPath
    $diskDrives = @(Get-CimInstance Win32_DiskDrive -ErrorAction SilentlyContinue)
    $physicalDisks = @(Get-PhysicalDisk -ErrorAction SilentlyContinue)
    $logicalDisks = @(Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" -ErrorAction SilentlyContinue)
    $driveResults=@(); $findings=@()

    foreach ($d in $diskDrives) {
        $matched = $physicalDisks | Where-Object { $_.FriendlyName -like "*$($d.Model)*" } | Select-Object -First 1
        $rel = $null
        try { if ($matched) { $rel = Get-StorageReliabilityCounter -PhysicalDisk $matched -ErrorAction SilentlyContinue } } catch {}

        $smartParsed = Parse-SmartText $null
        if ($smartctl) {
            $smartText = Invoke-SmartCtl -SmartCtlPath $smartctl -DeviceId $d.DeviceID
            if ($smartText) {
                $safe = ($d.Model -replace '[^\w\-]','_')
                if ($safe.Length -gt 35) { $safe = $safe.Substring(0,35) }
                Set-Content -Path (Join-Path $ReportDir "smart-$safe.txt") -Value $smartText -Encoding UTF8
                $smartParsed = Parse-SmartText $smartText
            }
        }

        $score=100; $driveFindings=@()
        $health = if ($matched) { $matched.HealthStatus } else { $d.Status }
        if ($health -and $health -notmatch "Healthy|OK") {
            $score -= 35
            $driveFindings += New-Finding "Storage" "Critical" "$($d.Model) health status is $health." "Back up data immediately and plan drive replacement."
        }

        $temp=$smartParsed.TemperatureC
        if ($null -eq $temp -and $rel) { $temp=$rel.Temperature }
        if ($temp -ne $null) {
            if ($temp -ge 75) { $score-=20; $driveFindings += New-Finding "Storage Temperature" "High" "$($d.Model) temperature is $temp C." "Improve cooling or replace drive if overheating continues." }
            elseif ($temp -ge 65) { $score-=10; $driveFindings += New-Finding "Storage Temperature" "Moderate" "$($d.Model) temperature is $temp C." "Monitor drive temperature and airflow." }
        }

        $wear=$smartParsed.PercentageUsed
        if ($null -eq $wear -and $rel) { $wear=$rel.Wear }
        if ($wear -ne $null) {
            if ($wear -ge 90) { $score-=35; $driveFindings += New-Finding "SSD Wear" "Critical" "$($d.Model) reports approximately $wear% lifetime used." "Replace SSD immediately." }
            elseif ($wear -ge 70) { $score-=20; $driveFindings += New-Finding "SSD Wear" "High" "$($d.Model) reports approximately $wear% lifetime used." "Plan SSD replacement soon." }
            elseif ($wear -ge 50) { $score-=10; $driveFindings += New-Finding "SSD Wear" "Moderate" "$($d.Model) reports approximately $wear% lifetime used." "Monitor SSD wear trend." }
        }

        $hours=$smartParsed.PowerOnHours
        if ($null -eq $hours -and $rel) { $hours=$rel.PowerOnHours }
        if ($hours -ne $null) {
            if ($hours -ge 40000) { $score-=20; $driveFindings += New-Finding "Drive Age" "High" "$($d.Model) has $hours power-on hours." "Drive is heavily used. Replacement planning recommended." }
            elseif ($hours -ge 25000) { $score-=10; $driveFindings += New-Finding "Drive Age" "Moderate" "$($d.Model) has $hours power-on hours." "Drive aging detected. Monitor and ensure backups." }
        }

        if ($smartParsed.ReallocatedSectors -gt 0) { $score-=20; $driveFindings += New-Finding "Bad Sectors" "High" "$($d.Model) has $($smartParsed.ReallocatedSectors) reallocated sector(s)." "Back up data and consider drive replacement." }
        if ($smartParsed.PendingSectors -gt 0) { $score-=30; $driveFindings += New-Finding "Pending Sectors" "Critical" "$($d.Model) has $($smartParsed.PendingSectors) pending sector(s)." "Back up data immediately. Drive may be failing." }
        if ($smartParsed.UncorrectableErrors -gt 0) { $score-=30; $driveFindings += New-Finding "Uncorrectable Errors" "Critical" "$($d.Model) has $($smartParsed.UncorrectableErrors) uncorrectable error(s)." "Replace drive and verify data integrity." }
        if ($smartParsed.UnsafeShutdowns -gt 50) { $score-=5; $driveFindings += New-Finding "Unsafe Shutdowns" "Moderate" "$($d.Model) reports $($smartParsed.UnsafeShutdowns) unsafe shutdown(s)." "Check power stability, battery, PSU, and shutdown behavior." }

        if ($score -lt 0) { $score=0 }
        $driveResults += [PSCustomObject]@{
            Model=$d.Model;SerialNumber=($d.SerialNumber -as [string]).Trim();InterfaceType=$d.InterfaceType;MediaType=$d.MediaType
            BusType=$matched.BusType;SizeGB=Convert-BytesToGB $d.Size;HealthStatus=$health;TemperatureC=$temp
            WearPercentUsed=$wear;EstimatedRemainingPercent=if($wear -ne $null){[math]::Max(0,100-$wear)}else{$null}
            PowerOnHours=$hours;PowerOnYearsApprox=if($hours -ne $null){[math]::Round($hours/8760,1)}else{$null}
            TotalHostWritesTB=$smartParsed.TotalHostWritesTB;UnsafeShutdowns=$smartParsed.UnsafeShutdowns
            ReallocatedSectors=$smartParsed.ReallocatedSectors;PendingSectors=$smartParsed.PendingSectors;UncorrectableErrors=$smartParsed.UncorrectableErrors
            Score=[math]::Max(0,$score);Grade=Get-GradeFromScore ([math]::Max(0,$score));ApproxLife=Get-LifeTextFromScore ([math]::Max(0,$score));Findings=$driveFindings
        }
        $findings += $driveFindings
    }

    $volumeResults=@()
    foreach ($v in $logicalDisks) {
        $freePct = if ($v.Size -gt 0) { [math]::Round(($v.FreeSpace/$v.Size)*100,2) } else { $null }
        $volumeResults += [PSCustomObject]@{Drive=$v.DeviceID;FileSystem=$v.FileSystem;SizeGB=Convert-BytesToGB $v.Size;FreeGB=Convert-BytesToGB $v.FreeSpace;FreePercent=$freePct}
        if ($freePct -ne $null -and $freePct -lt 10) { $findings += New-Finding "Storage Space" "High" "$($v.DeviceID) has only $freePct% free space." "Free space or upgrade storage." }
        elseif ($freePct -ne $null -and $freePct -lt 15) { $findings += New-Finding "Storage Space" "Moderate" "$($v.DeviceID) has $freePct% free space." "Consider cleanup or larger SSD." }
    }

    $avg = if ($driveResults.Count -gt 0) { [int](($driveResults | Measure-Object Score -Average).Average) } else { 100 }
    [PSCustomObject]@{SmartCtlFound=[bool]$smartctl;Drives=$driveResults;Volumes=$volumeResults;Score=$avg;Grade=Get-GradeFromScore $avg;Risk=Get-RiskFromScore $avg;ApproxLife=Get-LifeTextFromScore $avg;Findings=$findings}
}

function Get-PCPlusBatteryWear {
    Write-PCLog "Collecting battery wear information."
    $batteryReport = Join-Path $ReportDir "battery-report.html"
    try { powercfg /batteryreport /output $batteryReport | Out-Null } catch {}
    $batt = @(Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue)
    $findings=@(); $score=100; $health=$null; $design=$null; $full=$null; $cycles=$null

    if (Test-Path $batteryReport) {
        try {
            $html = Get-Content $batteryReport -Raw
            if ($html -match "DESIGN CAPACITY.*?([0-9,]+)\s*mWh") { $design=[int64](($matches[1])-replace ",","") }
            if ($html -match "FULL CHARGE CAPACITY.*?([0-9,]+)\s*mWh") { $full=[int64](($matches[1])-replace ",","") }
            if ($html -match "CYCLE COUNT.*?([0-9,]+)") { $cycles=[int64](($matches[1])-replace ",","") }
            if ($design -and $full -and $design -gt 0) { $health=[math]::Round(($full/$design)*100,1) }
        } catch {}
    }

    if ($batt.Count -eq 0) {
        return [PSCustomObject]@{BatteryDetected=$false;Score=100;Grade="N/A - Desktop or no battery detected";Risk="N/A";ApproxLife="No battery detected";BatteryHealthPercent=$null;DesignCapacityMWh=$null;FullChargeCapacityMWh=$null;CycleCount=$null;CurrentChargePercent=$null;BatteryReport=$batteryReport;Findings=@()}
    }

    if ($health -ne $null) {
        if ($health -lt 40) { $score-=45; $findings += New-Finding "Battery Wear" "Critical" "Battery health is approximately $health%." "Replace battery immediately." }
        elseif ($health -lt 60) { $score-=30; $findings += New-Finding "Battery Wear" "High" "Battery health is approximately $health%." "Battery replacement recommended." }
        elseif ($health -lt 80) { $score-=15; $findings += New-Finding "Battery Wear" "Moderate" "Battery health is approximately $health%." "Monitor runtime and plan replacement." }
    } else {
        $score-=5; $findings += New-Finding "Battery Wear" "Low" "Battery health percentage could not be calculated." "Review battery report manually."
    }

    if ($cycles -ne $null) {
        if ($cycles -gt 800) { $score-=20; $findings += New-Finding "Battery Cycles" "High" "Battery cycle count is $cycles." "Battery is heavily used. Replacement recommended." }
        elseif ($cycles -gt 500) { $score-=10; $findings += New-Finding "Battery Cycles" "Moderate" "Battery cycle count is $cycles." "Battery aging detected." }
    }

    if ($score -lt 0) { $score=0 }
    [PSCustomObject]@{BatteryDetected=$true;WmiBattery=$batt;Score=$score;Grade=Get-GradeFromScore $score;Risk=Get-RiskFromScore $score;ApproxLife=Get-LifeTextFromScore $score;BatteryHealthPercent=$health;DesignCapacityMWh=$design;FullChargeCapacityMWh=$full;CycleCount=$cycles;CurrentChargePercent=($batt|Select-Object -First 1).EstimatedChargeRemaining;BatteryReport=$batteryReport;Findings=$findings}
}

function Get-PCPlusThermalWear {
    Write-PCLog "Collecting thermal/cooling indicators."
    $findings=@(); $score=100
    $thermalZones=@()
    try {
        $thermalZones = @(Get-CimInstance MSAcpi_ThermalZoneTemperature -Namespace "root/wmi" -ErrorAction SilentlyContinue | ForEach-Object {
            [PSCustomObject]@{InstanceName=$_.InstanceName;TemperatureC=[math]::Round(($_.CurrentTemperature/10)-273.15,1)}
        })
    } catch {}
    $maxTemp = if ($thermalZones.Count -gt 0) { ($thermalZones | Measure-Object TemperatureC -Maximum).Maximum } else { $null }
    if ($maxTemp -ne $null) {
        if ($maxTemp -ge 90) { $score-=30; $findings += New-Finding "Thermal Wear" "Critical" "Reported thermal zone temperature is $maxTemp C." "Inspect cooling, clean dust, verify fan, replace thermal paste." }
        elseif ($maxTemp -ge 80) { $score-=20; $findings += New-Finding "Thermal Wear" "High" "Reported thermal zone temperature is $maxTemp C." "Cooling service recommended." }
        elseif ($maxTemp -ge 70) { $score-=10; $findings += New-Finding "Thermal Wear" "Moderate" "Reported thermal zone temperature is $maxTemp C." "Monitor temperatures and airflow." }
    } else {
        $findings += New-Finding "Thermal Sensors" "Low" "Windows did not expose reliable temperature sensors." "Use HWiNFO, LibreHardwareMonitor, or OCCT for accurate sensors."
    }

    $thermalEvents=@()
    try {
        $thermalEvents = @(Get-WinEvent -FilterHashtable @{LogName='System'; StartTime=(Get-Date).AddDays(-90)} -ErrorAction SilentlyContinue |
            Where-Object { $_.Message -match "thermal|overheat|temperature|throttl" } |
            Select-Object TimeCreated,ProviderName,Id,LevelDisplayName,Message -First 20)
    } catch {}
    if ($thermalEvents.Count -gt 0) { $score-=15; $findings += New-Finding "Thermal Events" "High" "$($thermalEvents.Count) thermal/throttling-related event(s) found." "Review cooling performance and sensor logs." }
    if ($score -lt 0) { $score=0 }
    [PSCustomObject]@{Score=$score;Grade=Get-GradeFromScore $score;Risk=Get-RiskFromScore $score;ApproxLife=Get-LifeTextFromScore $score;ThermalZones=$thermalZones;MaxReportedTemperatureC=$maxTemp;ThermalEvents=$thermalEvents;Findings=$findings;Notes="Windows WMI temperature data is limited. Integrate LibreHardwareMonitor/HWiNFO for accurate fan RPM, CPU/GPU/NVMe temperatures, and throttling."}
}

function Get-PCPlusRamWear {
    Write-PCLog "Collecting RAM configuration/stability indicators."
    $modules = @(Get-CimInstance Win32_PhysicalMemory -ErrorAction SilentlyContinue)
    $array = Get-CimInstance Win32_PhysicalMemoryArray -ErrorAction SilentlyContinue
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    $moduleList = @($modules | ForEach-Object {
        [PSCustomObject]@{Slot=$_.DeviceLocator;Bank=$_.BankLabel;CapacityGB=Convert-BytesToGB $_.Capacity;SpeedMHz=$_.Speed;ConfiguredClockSpeedMHz=$_.ConfiguredClockSpeed;Manufacturer=($_.Manufacturer -as [string]).Trim();PartNumber=($_.PartNumber -as [string]).Trim();SerialNumber=($_.SerialNumber -as [string]).Trim();SMBIOSMemoryType=$_.SMBIOSMemoryType;FormFactor=$_.FormFactor}
    })
    $score=100; $findings=@()
    $speeds=@($moduleList|Where-Object{$_.SpeedMHz}|Select-Object -ExpandProperty SpeedMHz -Unique)
    if ($speeds.Count -gt 1) { $score-=10; $findings += New-Finding "RAM Configuration" "Moderate" "Mixed RAM speeds detected: $($speeds -join ', ') MHz." "Use matched RAM modules for best stability/performance." }
    $sizes=@($moduleList|Select-Object -ExpandProperty CapacityGB -Unique)
    if ($sizes.Count -gt 1) { $score-=5; $findings += New-Finding "RAM Configuration" "Low" "Mixed RAM capacities detected: $($sizes -join ', ') GB." "Matched RAM modules are recommended." }

    $totalRamGB=Convert-KBToGB $os.TotalVisibleMemorySize
    if ($totalRamGB -lt 8) { $score-=25; $findings += New-Finding "RAM Capacity" "High" "System has less than 8GB RAM." "Upgrade to at least 8GB; 16GB recommended." }
    elseif ($totalRamGB -lt 16) { $score-=10; $findings += New-Finding "RAM Capacity" "Moderate" "System has $totalRamGB GB RAM." "16GB is recommended for smoother performance." }

    $memEvents=@(); $whea=@()
    try { $memEvents=@(Get-WinEvent -FilterHashtable @{LogName='System';ProviderName='Microsoft-Windows-MemoryDiagnostics-Results';StartTime=(Get-Date).AddDays(-180)} -ErrorAction SilentlyContinue | Select-Object TimeCreated,ProviderName,Id,LevelDisplayName,Message -First 10) } catch {}
    try { $whea=@(Get-WinEvent -FilterHashtable @{LogName='System';ProviderName='Microsoft-Windows-WHEA-Logger';StartTime=(Get-Date).AddDays(-90)} -ErrorAction SilentlyContinue | Select-Object TimeCreated,ProviderName,Id,LevelDisplayName,Message -First 20) } catch {}
    if ($whea.Count -gt 0) { $score-=20; $findings += New-Finding "Hardware Errors" "High" "$($whea.Count) WHEA hardware error(s) detected." "Run advanced RAM/CPU/motherboard stability tests." }
    if ($score -lt 0) { $score=0 }

    [PSCustomObject]@{TotalRAMGB=$totalRamGB;FreeRAMGB=Convert-KBToGB $os.FreePhysicalMemory;SlotsSupported=$array.MemoryDevices;ModulesInstalled=$moduleList.Count;Modules=$moduleList;MemoryDiagnosticEvents=$memEvents;WHEAEvents=$whea;Score=$score;Grade=Get-GradeFromScore $score;Risk=Get-RiskFromScore $score;ApproxLife=Get-LifeTextFromScore $score;Findings=$findings;Notes="RAM life is estimated from configuration, capacity, WHEA errors, and memory diagnostic results."}
}

function Get-PCPlusGpuWear {
    Write-PCLog "Collecting GPU/display wear indicators."
    $gpus=@(Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue)
    $score=100; $findings=@()
    $gpuEvents=@()
    try {
        $gpuEvents=@(Get-WinEvent -FilterHashtable @{LogName='System';StartTime=(Get-Date).AddDays(-90)} -ErrorAction SilentlyContinue |
            Where-Object { $_.Message -match "display driver|nvlddmkm|amdkmdag|igfx|video hardware|LiveKernelEvent" } |
            Select-Object TimeCreated,ProviderName,Id,LevelDisplayName,Message -First 30)
    } catch {}
    if ($gpuEvents.Count -gt 0) { $score-=20; $findings += New-Finding "GPU/Display Stability" "High" "$($gpuEvents.Count) GPU/display-related event(s) found." "Update graphics driver and run GPU stress/thermal test." }
    foreach ($gpu in $gpus) {
        if ($gpu.Status -and $gpu.Status -notmatch "OK") { $score-=15; $findings += New-Finding "GPU Status" "High" "$($gpu.Name) status is $($gpu.Status)." "Review device manager and graphics driver." }
    }
    if ($score -lt 0) { $score=0 }
    [PSCustomObject]@{GPUs=@($gpus|ForEach-Object{[PSCustomObject]@{Name=$_.Name;VideoProcessor=$_.VideoProcessor;AdapterRAMGB=Convert-BytesToGB $_.AdapterRAM;DriverVersion=$_.DriverVersion;DriverDate=$_.DriverDate;CurrentResolution="$($_.CurrentHorizontalResolution)x$($_.CurrentVerticalResolution)";RefreshRate=$_.CurrentRefreshRate;Status=$_.Status}});GPUEvents=$gpuEvents;Score=$score;Grade=Get-GradeFromScore $score;Risk=Get-RiskFromScore $score;ApproxLife=Get-LifeTextFromScore $score;Findings=$findings;Notes="GPU thermal wear/fan health require HWiNFO/LibreHardwareMonitor/OCCT/FurMark integration."}
}

function Get-PCPlusWindowsReliabilityWear {
    Write-PCLog "Collecting Windows reliability/wear indicators."
    $days=90; $start=(Get-Date).AddDays(-$days); $score=100; $findings=@()
    $defs=@(
        @{Category="Unexpected Shutdown";Filter=@{LogName='System';Id=41;StartTime=$start}},
        @{Category="Blue Screen BugCheck";Filter=@{LogName='System';Id=1001;StartTime=$start}},
        @{Category="Unexpected Shutdown Log";Filter=@{LogName='System';Id=6008;StartTime=$start}},
        @{Category="Disk Bad Block";Filter=@{LogName='System';Id=7;StartTime=$start}},
        @{Category="Disk Warning";Filter=@{LogName='System';Id=51;StartTime=$start}},
        @{Category="NTFS Corruption";Filter=@{LogName='System';Id=55;StartTime=$start}},
        @{Category="Storage Reset";Filter=@{LogName='System';Id=129;StartTime=$start}},
        @{Category="Disk IO Retry";Filter=@{LogName='System';Id=153;StartTime=$start}},
        @{Category="WHEA Hardware Error";Filter=@{LogName='System';ProviderName='Microsoft-Windows-WHEA-Logger';StartTime=$start}},
        @{Category="Application Error";Filter=@{LogName='Application';ProviderName='Application Error';StartTime=$start}},
        @{Category="Application Hang";Filter=@{LogName='Application';ProviderName='Application Hang';StartTime=$start}}
    )
    $summary=@()
    foreach($def in $defs){
        $events=@()
        try{$events=@(Get-WinEvent -FilterHashtable $def.Filter -ErrorAction SilentlyContinue)}catch{}
        $count=$events.Count; $recent=($events|Sort-Object TimeCreated -Descending|Select-Object -First 1).TimeCreated
        $summary += [PSCustomObject]@{Category=$def.Category;Count=$count;DaysChecked=$days;MostRecent=$recent}
        if($count -gt 0){
            if($def.Category -match "Blue Screen|WHEA|Disk Bad|NTFS|Storage Reset"){
                $score -= [math]::Min(25,$count*8); $findings += New-Finding "Reliability" "High" "$($def.Category): $count event(s) in last $days days." "Investigate hardware/driver/storage stability."
            } elseif($def.Category -match "Unexpected Shutdown"){
                $score -= [math]::Min(20,$count*5); $findings += New-Finding "Reliability" "Moderate" "$($def.Category): $count event(s) in last $days days." "Check power, battery, PSU, overheating, and crash history."
            } elseif($def.Category -match "Application" -and $count -gt 10){
                $score -= 10; $findings += New-Finding "Application Stability" "Moderate" "$($def.Category): $count event(s) in last $days days." "Review failing applications and drivers."
            }
        }
    }
    if($score -lt 0){$score=0}
    [PSCustomObject]@{DaysChecked=$days;EventSummary=$summary;Score=$score;Grade=Get-GradeFromScore $score;Risk=Get-RiskFromScore $score;ApproxLife=Get-LifeTextFromScore $score;Findings=$findings}
}

function Get-PCPlusDeviceWear {
    Write-PCLog "Collecting device/USB/network wear indicators."
    $score=100; $findings=@()
    $problem=@(Get-PnpDevice -ErrorAction SilentlyContinue | Where-Object{$_.Status -ne "OK"})
    if($problem.Count -gt 0){$score -= [math]::Min(25,$problem.Count*5); $findings += New-Finding "Device Health" "High" "$($problem.Count) device(s) have non-OK status." "Review Device Manager, drivers, and hardware connections."}
    $net=@(Get-NetAdapter -ErrorAction SilentlyContinue)
    $netStats=@(Get-NetAdapterStatistics -ErrorAction SilentlyContinue)
    $netWarn=@()
    foreach($n in $net){
        if($n.Status -ne "Up" -and $n.HardwareInterface){$netWarn += "$($n.Name) status is $($n.Status)"}
        if($n.LinkSpeed -match "100 Mbps" -and $n.InterfaceDescription -match "Gigabit|GbE|1000"){$netWarn += "$($n.Name) may be limited to 100Mbps on a gigabit adapter."}
    }
    if($netWarn.Count -gt 0){$score-=10; $findings += New-Finding "Network Hardware" "Moderate" ($netWarn -join "; ") "Check cable, switch port, Wi-Fi signal, or adapter driver."}
    $usbEvents=@()
    try{$usbEvents=@(Get-WinEvent -FilterHashtable @{LogName='System';StartTime=(Get-Date).AddDays(-90)} -ErrorAction SilentlyContinue | Where-Object{$_.Message -match "USB|device not recognized|device descriptor|reset.*port"} | Select-Object TimeCreated,ProviderName,Id,LevelDisplayName,Message -First 20)}catch{}
    if($usbEvents.Count -gt 0){$score-=10; $findings += New-Finding "USB/Port Wear" "Moderate" "$($usbEvents.Count) USB/port-related event(s) found." "Check USB ports, hubs, cables, external drives, and power delivery."}
    if($score -lt 0){$score=0}
    [PSCustomObject]@{ProblemDeviceCount=$problem.Count;ProblemDevices=@($problem|Select-Object Class,FriendlyName,InstanceId,Status,Problem);NetworkAdapters=@($net|Select-Object Name,InterfaceDescription,Status,LinkSpeed,MacAddress);NetworkStats=$netStats;USBEvents=$usbEvents;Score=$score;Grade=Get-GradeFromScore $score;Risk=Get-RiskFromScore $score;ApproxLife=Get-LifeTextFromScore $score;Findings=$findings}
}

function Get-PCPlusOverallWearScore {
    param($Data)
    $scores=@(
        @{Name="System Age";Score=$Data.System.Score;Weight=10},
        @{Name="Storage";Score=$Data.Storage.Score;Weight=25},
        @{Name="Battery";Score=$Data.Battery.Score;Weight=10},
        @{Name="Thermal";Score=$Data.Thermal.Score;Weight=15},
        @{Name="RAM";Score=$Data.RAM.Score;Weight=15},
        @{Name="GPU";Score=$Data.GPU.Score;Weight=5},
        @{Name="Reliability";Score=$Data.Reliability.Score;Weight=15},
        @{Name="Devices";Score=$Data.DeviceWear.Score;Weight=5}
    )
    if($Data.Battery.BatteryDetected -eq $false){ foreach($s in $scores){ if($s.Name -eq "Battery"){$s.Score=100} } }
    $weighted=0; $weight=0
    foreach($s in $scores){$weighted+=($s.Score*$s.Weight);$weight+=$s.Weight}
    $overall=[int]([math]::Round($weighted/$weight,0))
    $all=@()
    $all += $Data.System.Findings; $all += $Data.Storage.Findings; $all += $Data.Battery.Findings; $all += $Data.Thermal.Findings
    $all += $Data.RAM.Findings; $all += $Data.GPU.Findings; $all += $Data.Reliability.Findings; $all += $Data.DeviceWear.Findings
    $critical=@($all|Where-Object{$_.Severity -eq "Critical"}); $high=@($all|Where-Object{$_.Severity -eq "High"}); $moderate=@($all|Where-Object{$_.Severity -eq "Moderate"})
    $replacement="Keep and maintain"
    if($critical.Count -gt 0 -or $overall -lt 55){$replacement="Repair immediately or replace"}
    elseif($high.Count -ge 2 -or $overall -lt 70){$replacement="Plan major repair/upgrade or replacement within 6-12 months"}
    elseif($moderate.Count -ge 2 -or $overall -lt 80){$replacement="Maintenance/upgrade recommended within 12-24 months"}
    [PSCustomObject]@{Score=$overall;Grade=Get-GradeFromScore $overall;Risk=Get-RiskFromScore $overall;ApproxLife=Get-LifeTextFromScore $overall;ReplacementRecommendation=$replacement;CriticalCount=$critical.Count;HighCount=$high.Count;ModerateCount=$moderate.Count;ComponentScores=$scores;Findings=@($all|Sort-Object Severity,Category)}
}

function HtmlEncode { param([string]$Text) if($null -eq $Text){return ""}; $Text.Replace("&","&amp;").Replace("<","&lt;").Replace(">","&gt;").Replace('"',"&quot;") }

function New-PCPlusWearHtmlReport {
    param($Data)
    $scoreColor=if($Data.Overall.Score -ge 80){"#16a34a"}elseif($Data.Overall.Score -ge 60){"#f59e0b"}else{"#dc2626"}
    $findingRows=foreach($f in ($Data.Overall.Findings|Select-Object -First 60)){
        $class=switch($f.Severity){"Critical"{"fail"}"High"{"fail"}"Moderate"{"warn"}default{"pass"}}
        "<tr><td>$($f.Category)</td><td class='$class'>$($f.Severity)</td><td>$(HtmlEncode $f.Finding)</td><td>$(HtmlEncode $f.Recommendation)</td></tr>"
    }
    $componentRows=foreach($c in $Data.Overall.ComponentScores){
        $class=if($c.Score -ge 80){"pass"}elseif($c.Score -ge 60){"warn"}else{"fail"}
        "<tr><td>$($c.Name)</td><td class='$class'>$($c.Score)/100</td><td>$(Get-GradeFromScore $c.Score)</td></tr>"
    }
    $driveRows=foreach($d in $Data.Storage.Drives){
        $class=if($d.Score -ge 80){"pass"}elseif($d.Score -ge 60){"warn"}else{"fail"}
        "<tr><td>$(HtmlEncode $d.Model)</td><td>$($d.MediaType)</td><td>$($d.SizeGB) GB</td><td>$($d.PowerOnHours)</td><td>$($d.WearPercentUsed)</td><td>$($d.TemperatureC)</td><td>$($d.PendingSectors)</td><td class='$class'>$($d.Score)/100</td><td>$($d.ApproxLife)</td></tr>"
    }
    $volumeRows=foreach($v in $Data.Storage.Volumes){"<tr><td>$($v.Drive)</td><td>$($v.FileSystem)</td><td>$($v.SizeGB) GB</td><td>$($v.FreeGB) GB</td><td>$($v.FreePercent)%</td></tr>"}
    $ramRows=foreach($m in $Data.RAM.Modules){"<tr><td>$($m.Slot)</td><td>$($m.CapacityGB) GB</td><td>$($m.SpeedMHz)</td><td>$($m.ConfiguredClockSpeedMHz)</td><td>$(HtmlEncode $m.Manufacturer)</td><td>$(HtmlEncode $m.PartNumber)</td></tr>"}
    $gpuRows=foreach($g in $Data.GPU.GPUs){"<tr><td>$(HtmlEncode $g.Name)</td><td>$($g.AdapterRAMGB) GB</td><td>$($g.DriverVersion)</td><td>$($g.CurrentResolution)</td><td>$($g.Status)</td></tr>"}
    $relRows=foreach($e in $Data.Reliability.EventSummary){"<tr><td>$($e.Category)</td><td>$($e.Count)</td><td>$($e.MostRecent)</td></tr>"}

$html=@"
<!DOCTYPE html><html><head><meta charset="utf-8"><title>PC Plus 360 Wear & Tear Report</title>
<style>
body{font-family:Segoe UI,Arial,sans-serif;background:#f3f8fb;margin:0;color:#163247}
.header{background:linear-gradient(135deg,#0d4b71,#2596be);color:white;padding:34px}
.header h1{margin:0;font-size:34px}.header p{margin:8px 0 0 0;font-size:15px}
.container{padding:24px}.card{background:white;border-radius:16px;padding:22px;margin-bottom:18px;box-shadow:0 8px 22px rgba(13,75,113,.12)}
.grid{display:grid;grid-template-columns:repeat(4,1fr);gap:14px}.metric{background:#eaf7fc;border-left:6px solid #2596be;border-radius:12px;padding:14px}
.metric b{display:block;color:#0d4b71;font-size:12px;text-transform:uppercase}.metric span{font-size:18px;font-weight:700}
.score{font-size:60px;font-weight:800;color:$scoreColor;margin:8px 0}table{width:100%;border-collapse:collapse;font-size:13px}
th{background:#0d4b71;color:white;padding:10px;text-align:left}td{border-bottom:1px solid #dbe8ef;padding:9px;vertical-align:top}
.pass{color:#16a34a;font-weight:700}.warn{color:#f59e0b;font-weight:700}.fail{color:#dc2626;font-weight:700}
.badge{display:inline-block;padding:6px 10px;border-radius:999px;background:#eaf7fc;color:#0d4b71;font-weight:700}
.footer{text-align:center;padding:20px;color:#64748b;font-size:12px}.notice{background:#fff7ed;border-left:6px solid #f59e0b;padding:14px;border-radius:12px}
</style></head><body>
<div class="header"><h1>PC Plus 360 Wear & Tear Report</h1><p>Approximate Hardware Life, Reliability, Aging & Replacement Planning | PC Plus Computing | 604-760-1662</p></div>
<div class="container">
<div class="card"><h2>Executive Summary</h2><div class="grid">
<div class="metric"><b>Customer</b><span>$($Data.System.CustomerName)</span></div>
<div class="metric"><b>Technician</b><span>$($Data.System.TechnicianName)</span></div>
<div class="metric"><b>Computer</b><span>$($Data.System.ComputerName)</span></div>
<div class="metric"><b>Model</b><span>$($Data.System.Model)</span></div>
</div><div class="score">$($Data.Overall.Score)/100</div>
<p><span class="badge">$($Data.Overall.Grade)</span> <span class="badge">Risk: $($Data.Overall.Risk)</span></p>
<h3>Approximate Remaining Life</h3><p><b>$($Data.Overall.ApproxLife)</b></p>
<h3>Replacement / Upgrade Recommendation</h3><p><b>$($Data.Overall.ReplacementRecommendation)</b></p>
<p>Critical: $($Data.Overall.CriticalCount) | High: $($Data.Overall.HighCount) | Moderate: $($Data.Overall.ModerateCount)</p></div>

<div class="card"><h2>System Details</h2><table>
<tr><th>Manufacturer</th><td>$($Data.System.Manufacturer)</td></tr><tr><th>Model</th><td>$($Data.System.Model)</td></tr>
<tr><th>Serial</th><td>$($Data.System.SerialNumber)</td></tr><tr><th>BIOS</th><td>$($Data.System.BIOSVersion) | Date: $($Data.System.BIOSDate) | Approx Age: $($Data.System.BIOSAgeYears) years</td></tr>
<tr><th>Windows</th><td>$($Data.System.OS) Build $($Data.System.OSBuild)</td></tr><tr><th>CPU</th><td>$($Data.System.CPU)</td></tr>
<tr><th>RAM</th><td>$($Data.System.TotalRAMGB) GB</td></tr><tr><th>Uptime</th><td>$($Data.System.UptimeHours) hours</td></tr></table></div>

<div class="card"><h2>Component Wear Scores</h2><table><tr><th>Component</th><th>Score</th><th>Grade</th></tr>$($componentRows -join "`n")</table></div>
<div class="card"><h2>Findings & Recommendations</h2><table><tr><th>Category</th><th>Severity</th><th>Finding</th><th>Recommendation</th></tr>$($findingRows -join "`n")</table></div>
<div class="card"><h2>Storage Wear</h2><p>SMART deep details require smartctl/CrystalDiskInfo. Smartctl found: $($Data.Storage.SmartCtlFound)</p><table>
<tr><th>Drive</th><th>Type</th><th>Size</th><th>Power Hours</th><th>Wear Used %</th><th>Temp C</th><th>Pending Sectors</th><th>Score</th><th>Approx Life</th></tr>
$($driveRows -join "`n")</table><h3>Volumes</h3><table><tr><th>Drive</th><th>File System</th><th>Size</th><th>Free</th><th>Free %</th></tr>$($volumeRows -join "`n")</table></div>
<div class="card"><h2>Battery Wear</h2><table><tr><th>Battery Detected</th><td>$($Data.Battery.BatteryDetected)</td></tr>
<tr><th>Battery Health</th><td>$($Data.Battery.BatteryHealthPercent)%</td></tr><tr><th>Design Capacity</th><td>$($Data.Battery.DesignCapacityMWh) mWh</td></tr>
<tr><th>Full Charge Capacity</th><td>$($Data.Battery.FullChargeCapacityMWh) mWh</td></tr><tr><th>Cycle Count</th><td>$($Data.Battery.CycleCount)</td></tr>
<tr><th>Score</th><td>$($Data.Battery.Score)/100 - $($Data.Battery.Grade)</td></tr><tr><th>Battery Report</th><td>$($Data.Battery.BatteryReport)</td></tr></table></div>
<div class="card"><h2>Thermal / Cooling Wear</h2><p>Score: <b>$($Data.Thermal.Score)/100 - $($Data.Thermal.Grade)</b></p><p>Max reported Windows thermal zone temperature: $($Data.Thermal.MaxReportedTemperatureC) C</p><div class="notice">$($Data.Thermal.Notes)</div></div>
<div class="card"><h2>RAM Wear / Stability Indicators</h2><p>Score: <b>$($Data.RAM.Score)/100 - $($Data.RAM.Grade)</b></p><table><tr><th>Slot</th><th>Capacity</th><th>Speed</th><th>Configured</th><th>Manufacturer</th><th>Part</th></tr>$($ramRows -join "`n")</table></div>
<div class="card"><h2>GPU / Display Stability</h2><p>Score: <b>$($Data.GPU.Score)/100 - $($Data.GPU.Grade)</b></p><table><tr><th>GPU</th><th>VRAM</th><th>Driver</th><th>Resolution</th><th>Status</th></tr>$($gpuRows -join "`n")</table></div>
<div class="card"><h2>Windows Reliability History</h2><p>Score: <b>$($Data.Reliability.Score)/100 - $($Data.Reliability.Grade)</b></p><table><tr><th>Category</th><th>Count</th><th>Most Recent</th></tr>$($relRows -join "`n")</table></div>
<div class="card"><h2>Device / USB / Network Wear</h2><p>Score: <b>$($Data.DeviceWear.Score)/100 - $($Data.DeviceWear.Grade)</b></p><p>Problem devices: $($Data.DeviceWear.ProblemDeviceCount)</p><p>USB/port-related events found: $($Data.DeviceWear.USBEvents.Count)</p></div>
<div class="card"><h2>Important Note</h2><p>This report estimates wear and remaining useful life based on available Windows data, SMART data, battery reports, event logs, and configuration indicators. It is an approximation, not a manufacturer warranty prediction.</p></div>
</div><div class="footer">PC Plus Computing | pcpluscomputing.com | 604-760-1662 | 30+ Years in Service | 4.9 Google Rating | #1 Best Rated in Surrey</div>
</body></html>
"@
    Set-Content -Path $HtmlFile -Value $html -Encoding UTF8
}

# MAIN
Write-PCLog "PC Plus 360 Wear & Tear Life Report started."
if (-not (Test-IsAdmin)) { Write-PCLog "Not running as Administrator. Some results may be limited." "WARN" }

$Data=[ordered]@{}
$Data.System=Get-PCPlusSystemAge
$Data.Storage=Get-PCPlusStorageWear
$Data.Battery=Get-PCPlusBatteryWear
$Data.Thermal=Get-PCPlusThermalWear
$Data.RAM=Get-PCPlusRamWear
$Data.GPU=Get-PCPlusGpuWear
$Data.Reliability=Get-PCPlusWindowsReliabilityWear
$Data.DeviceWear=Get-PCPlusDeviceWear
$Data.Overall=Get-PCPlusOverallWearScore -Data $Data

$Data | ConvertTo-Json -Depth 12 | Set-Content -Path $JsonFile -Encoding UTF8

$topFindings = $Data.Overall.Findings | Select-Object -First 12 | ForEach-Object {
    "- [$($_.Severity)] $($_.Category): $($_.Finding) Recommendation: $($_.Recommendation)"
}

$componentText = $Data.Overall.ComponentScores | ForEach-Object { "$($_.Name): $($_.Score)/100 - $(Get-GradeFromScore $_.Score)" }

$summary=@"
PC Plus 360 Wear & Tear + Approximate Hardware Life Report

Customer: $CustomerName
Technician: $TechnicianName
Computer: $($Data.System.ComputerName)
Manufacturer/Model: $($Data.System.Manufacturer) $($Data.System.Model)
Serial: $($Data.System.SerialNumber)
Windows: $($Data.System.OS) Build $($Data.System.OSBuild)
BIOS Age Approx: $($Data.System.BIOSAgeYears) years

Overall Wear Score: $($Data.Overall.Score)/100
Grade: $($Data.Overall.Grade)
Risk Level: $($Data.Overall.Risk)
Approximate Remaining Life: $($Data.Overall.ApproxLife)
Replacement / Upgrade Recommendation:
$($Data.Overall.ReplacementRecommendation)

Component Scores:
$($componentText -join "`r`n")

Top Findings:
$($topFindings -join "`r`n")

Reports:
HTML: $HtmlFile
JSON: $JsonFile
CSV: $CsvFile
Log: $LogFile

Important:
This is an approximate wear and remaining-life estimate based on available Windows hardware data, SMART information, battery data, event logs, and reliability indicators. It is not a manufacturer warranty prediction.
"@

Set-Content -Path $TxtFile -Value $summary -Encoding UTF8

[PSCustomObject]@{
    ComputerName=$Data.System.ComputerName
    CustomerName=$CustomerName
    Score=$Data.Overall.Score
    Grade=$Data.Overall.Grade
    Risk=$Data.Overall.Risk
    ApproxLife=$Data.Overall.ApproxLife
    Recommendation=$Data.Overall.ReplacementRecommendation
    StorageScore=$Data.Storage.Score
    BatteryScore=$Data.Battery.Score
    ThermalScore=$Data.Thermal.Score
    RamScore=$Data.RAM.Score
    ReliabilityScore=$Data.Reliability.Score
    ReportDate=Get-Date
} | Export-Csv -Path $CsvFile -NoTypeInformation

New-PCPlusWearHtmlReport -Data $Data

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "PC Plus 360 Wear & Tear Report Completed" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "Overall Score: $($Data.Overall.Score)/100"
Write-Host "Grade: $($Data.Overall.Grade)"
Write-Host "Risk: $($Data.Overall.Risk)"
Write-Host "Approx Life: $($Data.Overall.ApproxLife)"
Write-Host "Recommendation: $($Data.Overall.ReplacementRecommendation)"
Write-Host ""
Write-Host "Report Folder: $ReportDir"
Write-Host "HTML Report:   $HtmlFile"
Write-Host "TXT Summary:   $TxtFile"
Write-Host "JSON Raw Data: $JsonFile"
Write-Host "CSV Summary:   $CsvFile"
Write-Host "Log File:      $LogFile"
Write-Host ""

if ($OpenReport -and (Test-Path $HtmlFile)) { Start-Process $HtmlFile }
Write-PCLog "PC Plus 360 Wear & Tear Life Report completed."

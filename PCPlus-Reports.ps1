# PCPlus-Reports.ps1 - Report generation, scan history, and data export
# This file is dot-sourced by PCPlus-360.ps1
# Edit this file to change report formats without affecting tests or UI
# ─────────────────────────────────────────────────────────────────────────────

# ─────────────────────────────────────────────────────────────────────────────
# HISTORICAL TRACKING
# ─────────────────────────────────────────────────────────────────────────────

$Global:HistoryDir = "C:\PCPlus360\History"

function Save-ScanHistory {
    param($ScanData)
    Write-DiagLog "Saving scan to history..."
    Invoke-Safe {
        $compName = $ScanData.SystemInfo.ComputerName
        $serial = $ScanData.SystemInfo.Serial
        $deviceDir = Join-Path $Global:HistoryDir ($compName -replace '[\\/:*?"<>|]','_')
        if (-not (Test-Path $deviceDir)) { New-Item -Path $deviceDir -ItemType Directory -Force | Out-Null }

        $summary = @{
            ScanDate = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            ComputerName = $compName; Serial = $serial
            HardwareScore = $ScanData.HardwareScore; SecurityScore = $ScanData.SecurityScore
            CPUModel = $ScanData.SystemInfo.CPUModel; RAMTotal = $ScanData.SystemInfo.RAMTotal
            CPUPeakTemp = if ($ScanData.StressResults.CPU) { $ScanData.StressResults.CPU.MaxTemp } else { "N/A" }
            GPUPeakTemp = if ($ScanData.StressResults.GPU) { $ScanData.StressResults.GPU.MaxTemp } else { "N/A" }
            CPUStressPassed = if ($ScanData.StressResults.CPU) { $ScanData.StressResults.CPU.Passed } else { $null }
            RAMStressPassed = if ($ScanData.StressResults.RAM) { $ScanData.StressResults.RAM.Passed } else { $null }
            GPUStressPassed = if ($ScanData.StressResults.GPU) { $ScanData.StressResults.GPU.Passed } else { $null }
            DiskWriteMBps = if ($ScanData.StressResults.Disk) { $ScanData.StressResults.Disk.SeqWriteMBps } else { "N/A" }
            DiskReadMBps = if ($ScanData.StressResults.Disk) { $ScanData.StressResults.Disk.SeqReadMBps } else { "N/A" }
            SSDHealth = ($ScanData.SystemInfo.SMART | ForEach-Object { "$($_.Model):$($_.Health)" }) -join "; "
            SSDWear = ($ScanData.SystemInfo.SMART | ForEach-Object { "$($_.Model):$($_.Wear)" }) -join "; "
            SSDTemp = ($ScanData.SystemInfo.SMART | ForEach-Object { "$($_.Model):$($_.Temperature)" }) -join "; "
            BatteryHealth = if ($ScanData.Battery -and $ScanData.Battery.Present) { $ScanData.Battery.HealthPct } else { "N/A" }
            BatteryCycles = if ($ScanData.Battery -and $ScanData.Battery.Present) { $ScanData.Battery.CycleCount } else { "N/A" }
            CrashCount = if ($ScanData.Stability) { $ScanData.Stability.TotalBSODs + $ScanData.Stability.TotalUnexpected } else { 0 }
            StabilityRating = if ($ScanData.Stability) { $ScanData.Stability.StabilityRating } else { "N/A" }
            BootTime = $ScanData.SystemInfo.Uptime
            NetworkDownload = if ($ScanData.SpeedTest) { $ScanData.SpeedTest.DownloadMbps } else { "N/A" }
            GamingScore = if ($ScanData.Gaming) { $ScanData.Gaming.Score } else { "N/A" }
            GamingTier = if ($ScanData.Gaming) { $ScanData.Gaming.Tier } else { "N/A" }
            ScanMode = $ScanData.ScanMode
        }

        $fileName = "scan_$(Get-Date -Format 'yyyyMMdd_HHmmss').json"
        $filePath = Join-Path $deviceDir $fileName
        $summary | ConvertTo-Json -Depth 5 | Set-Content $filePath -Encoding UTF8
        Write-DiagLog "History saved: $filePath"
        $filePath
    } $null
}

function Get-ScanHistory {
    param([string]$ComputerName)
    Write-DiagLog "Loading scan history for $ComputerName..."
    Invoke-Safe {
        $deviceDir = Join-Path $Global:HistoryDir ($ComputerName -replace '[\\/:*?"<>|]','_')
        if (-not (Test-Path $deviceDir)) { return @() }
        $scans = @()
        Get-ChildItem $deviceDir -Filter "scan_*.json" | Sort-Object Name -Descending | Select-Object -First 20 | ForEach-Object {
            $data = Get-Content $_.FullName -Raw | ConvertFrom-Json
            $scans += $data
        }
        $scans
    } @()
}

function Compare-ScanHistory {
    param($Current, $Previous)
    if (-not $Previous -or $Previous.Count -eq 0) { return $null }
    $last = $Previous[0]
    $comparison = @{
        PreviousDate = $last.ScanDate; HasPrevious = $true
        ScoreDelta = if ($Current.HardwareScore -ne "N/A" -and $last.HardwareScore -ne "N/A") { $Current.HardwareScore - $last.HardwareScore } else { 0 }
        Trends = @()
    }
    # SSD health trend
    if ($last.SSDHealth -and $Current.SSDHealth) {
        $comparison.Trends += @{ Category = "SSD Health"; Previous = $last.SSDHealth; Current = $Current.SSDHealth }
    }
    # Battery trend
    if ($last.BatteryHealth -ne "N/A" -and $Current.BatteryHealth -ne "N/A") {
        $delta = $Current.BatteryHealth - $last.BatteryHealth
        $dir = if ($delta -gt 0) { "Improved" } elseif ($delta -lt 0) { "Declined" } else { "Stable" }
        $comparison.Trends += @{ Category = "Battery Health"; Previous = "$($last.BatteryHealth)%"; Current = "$($Current.BatteryHealth)%"; Direction = $dir; Delta = $delta }
    }
    # Temperature trend
    if ($last.CPUPeakTemp -ne "N/A" -and $Current.CPUPeakTemp -ne "N/A") {
        $comparison.Trends += @{ Category = "CPU Peak Temp"; Previous = "$($last.CPUPeakTemp)C"; Current = "$($Current.CPUPeakTemp)C" }
    }
    # Crash trend
    if ($last.CrashCount -ne $null -and $Current.CrashCount -ne $null) {
        $comparison.Trends += @{ Category = "Crash Events"; Previous = $last.CrashCount; Current = $Current.CrashCount }
    }
    # Disk performance trend
    if ($last.DiskWriteMBps -ne "N/A" -and $Current.DiskWriteMBps -ne "N/A") {
        $comparison.Trends += @{ Category = "Disk Write Speed"; Previous = "$($last.DiskWriteMBps) MB/s"; Current = "$($Current.DiskWriteMBps) MB/s" }
    }
    return $comparison
}

# ─────────────────────────────────────────────────────────────────────────────
# EXPORT FUNCTIONS
# ─────────────────────────────────────────────────────────────────────────────

function Export-ScanJSON {
    param($ScanData, [string]$OutputFolder)
    $safeName = $ScanData.CustomerName -replace '[\\/:*?"<>|]','_'
    $safeDev = $ScanData.SystemInfo.ComputerName -replace '[\\/:*?"<>|]','_'
    $ds = Get-Date -Format "yyyy-MM-dd"
    $path = Join-Path $OutputFolder "$safeName - $safeDev - Full Data $ds.json"
    $ScanData | ConvertTo-Json -Depth 10 | Set-Content $path -Encoding UTF8
    Write-DiagLog "JSON exported: $path"
    return $path
}

function Export-ScanCSV {
    param($ScanData, [string]$OutputFolder)
    $safeName = $ScanData.CustomerName -replace '[\\/:*?"<>|]','_'
    $safeDev = $ScanData.SystemInfo.ComputerName -replace '[\\/:*?"<>|]','_'
    $ds = Get-Date -Format "yyyy-MM-dd"
    $path = Join-Path $OutputFolder "$safeName - $safeDev - Summary $ds.csv"
    $rows = @()
    $rows += [PSCustomObject]@{ Category="System"; Item="Computer Name"; Value=$ScanData.SystemInfo.ComputerName }
    $rows += [PSCustomObject]@{ Category="System"; Item="Manufacturer"; Value=$ScanData.SystemInfo.Manufacturer }
    $rows += [PSCustomObject]@{ Category="System"; Item="Model"; Value=$ScanData.SystemInfo.Model }
    $rows += [PSCustomObject]@{ Category="System"; Item="Serial"; Value=$ScanData.SystemInfo.Serial }
    $rows += [PSCustomObject]@{ Category="System"; Item="OS"; Value=$ScanData.SystemInfo.OSVersion }
    $rows += [PSCustomObject]@{ Category="System"; Item="CPU"; Value=$ScanData.SystemInfo.CPUModel }
    $rows += [PSCustomObject]@{ Category="System"; Item="RAM"; Value="$($ScanData.SystemInfo.RAMTotal) GB" }
    $rows += [PSCustomObject]@{ Category="Score"; Item="Hardware Score"; Value=$ScanData.HardwareScore }
    $rows += [PSCustomObject]@{ Category="Score"; Item="Security Score"; Value=$ScanData.SecurityScore }
    if ($ScanData.StressResults.CPU) {
        $rows += [PSCustomObject]@{ Category="Stress"; Item="CPU Test"; Value=if($ScanData.StressResults.CPU.Passed){"PASS"}else{"FAIL"} }
        $rows += [PSCustomObject]@{ Category="Stress"; Item="CPU Peak Temp"; Value="$($ScanData.StressResults.CPU.MaxTemp)C" }
    }
    if ($ScanData.StressResults.RAM) { $rows += [PSCustomObject]@{ Category="Stress"; Item="RAM Test"; Value=if($ScanData.StressResults.RAM.Passed){"PASS"}else{"FAIL"} } }
    if ($ScanData.StressResults.GPU) { $rows += [PSCustomObject]@{ Category="Stress"; Item="GPU Test"; Value=if($ScanData.StressResults.GPU.Passed){"PASS"}else{"FAIL"} } }
    if ($ScanData.StressResults.Disk) {
        $rows += [PSCustomObject]@{ Category="Stress"; Item="Disk Write"; Value="$($ScanData.StressResults.Disk.SeqWriteMBps) MB/s" }
        $rows += [PSCustomObject]@{ Category="Stress"; Item="Disk Read"; Value="$($ScanData.StressResults.Disk.SeqReadMBps) MB/s" }
    }
    foreach ($d in $ScanData.SystemInfo.SMART) {
        $rows += [PSCustomObject]@{ Category="Storage"; Item=$d.Model; Value="$($d.Health), Wear:$($d.Wear), Temp:$($d.Temperature)" }
    }
    if ($ScanData.Battery -and $ScanData.Battery.Present) {
        $rows += [PSCustomObject]@{ Category="Battery"; Item="Health"; Value="$($ScanData.Battery.HealthPct)%" }
        $rows += [PSCustomObject]@{ Category="Battery"; Item="Cycles"; Value=$ScanData.Battery.CycleCount }
    }
    if ($ScanData.Stability) {
        $rows += [PSCustomObject]@{ Category="Stability"; Item="Rating"; Value=$ScanData.Stability.StabilityRating }
        $rows += [PSCustomObject]@{ Category="Stability"; Item="BSODs (90 days)"; Value=$ScanData.Stability.TotalBSODs }
    }
    if ($ScanData.SpeedTest) {
        $rows += [PSCustomObject]@{ Category="Network"; Item="Download"; Value=$ScanData.SpeedTest.DownloadMbps }
        $rows += [PSCustomObject]@{ Category="Network"; Item="Ping"; Value=$ScanData.SpeedTest.PingMs }
    }
    if ($ScanData.Gaming) {
        $rows += [PSCustomObject]@{ Category="Gaming"; Item="Score"; Value=$ScanData.Gaming.Score }
        $rows += [PSCustomObject]@{ Category="Gaming"; Item="Tier"; Value=$ScanData.Gaming.Tier }
    }
    $rows | Export-Csv -Path $path -NoTypeInformation -Encoding UTF8
    Write-DiagLog "CSV exported: $path"
    return $path
}

# ─────────────────────────────────────────────────────────────────────────────
# JSON OUTPUT FOR REPORTCARD INTEGRATION
# ─────────────────────────────────────────────────────────────────────────────

function Export-ReportCardJson {
    param($ScanData, $PerformanceScore, [string]$OutputFolder)
    if (-not $OutputFolder) { $OutputFolder = "C:\PCPlus360\Reports" }
    if (-not (Test-Path $OutputFolder)) { New-Item -Path $OutputFolder -ItemType Directory -Force | Out-Null }

    $ds = Get-Date -Format "yyyyMMdd-HHmmss"
    $computerSafe = $ScanData.SystemInfo.ComputerName -replace '[^\w\-]', '_'
    $jsonPath = Join-Path $OutputFolder "PCPlus-ReportCard-$computerSafe-$ds.json"

    $export = @{
        ReportType = "PCPlus-360-ReportCard"
        GeneratedAt = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        ComputerName = $ScanData.SystemInfo.ComputerName
        CustomerName = $ScanData.CustomerName
        HardwareScore = $ScanData.HardwareScore
        SecurityScore = $ScanData.SecurityScore
        PerformanceScore = if ($PerformanceScore) { $PerformanceScore.Score } else { $null }
        PerformanceGrade = if ($PerformanceScore) { $PerformanceScore.LetterGrade } else { $null }
        SystemInfo = @{
            Manufacturer = $ScanData.SystemInfo.Manufacturer
            Model = $ScanData.SystemInfo.Model
            Serial = $ScanData.SystemInfo.Serial
            OS = $ScanData.SystemInfo.OSVersion
            CPU = $ScanData.SystemInfo.CPUModel
            RAMTotal = $ScanData.SystemInfo.RAMTotal
        }
        ScanMode = $ScanData.ScanMode
    }

    $export | ConvertTo-Json -Depth 8 | Set-Content -Path $jsonPath -Encoding UTF8
    Write-DiagLog "ReportCard JSON exported: $jsonPath"
    return $jsonPath
}

# ─────────────────────────────────────────────────────────────────────────────
# EXECUTIVE SUMMARY HELPERS
# Letter grade, SVG risk gauge, business risk assessment, remediation table
# ─────────────────────────────────────────────────────────────────────────────

function Get-OverallLetterGrade {
    param([int]$HwScore, [int]$SecScore)
    $avg = [math]::Round(($HwScore + $SecScore) / 2)
    $grade = if ($avg -ge 95) { "A+" } elseif ($avg -ge 90) { "A" } elseif ($avg -ge 85) { "A-" }
             elseif ($avg -ge 80) { "B+" } elseif ($avg -ge 75) { "B" } elseif ($avg -ge 70) { "B-" }
             elseif ($avg -ge 65) { "C+" } elseif ($avg -ge 60) { "C" } elseif ($avg -ge 55) { "C-" }
             elseif ($avg -ge 50) { "D" } else { "F" }
    $color = if ($avg -ge 80) { "#27ae60" } elseif ($avg -ge 60) { "#f39c12" } else { "#e74c3c" }
    return @{ Score = $avg; Grade = $grade; Color = $color }
}

function Build-SVGRiskGauge {
    param([int]$Score)
    $color = if ($Score -ge 80) { "#27ae60" } elseif ($Score -ge 60) { "#f39c12" } else { "#e74c3c" }
    $riskLabel = if ($Score -ge 85) { "LOW RISK" } elseif ($Score -ge 70) { "MODERATE" } elseif ($Score -ge 55) { "ELEVATED" } else { "HIGH RISK" }
    # SVG semi-circle gauge
    $angle = [math]::Round(180 * $Score / 100)
    $rad = [math]::Round($angle * [math]::PI / 180, 4)
    $x = [math]::Round(50 + 40 * [math]::Cos([math]::PI - $rad), 2)
    $y = [math]::Round(55 - 40 * [math]::Sin([math]::PI - $rad), 2)
    $largeArc = if ($angle -gt 180) { 1 } else { 0 }

    return @"
<svg viewBox="0 0 100 65" width="200" height="130" style="display:block;margin:0 auto;">
  <path d="M 10 55 A 40 40 0 0 1 90 55" fill="none" stroke="#e5e7eb" stroke-width="8" stroke-linecap="round"/>
  <path d="M 10 55 A 40 40 0 $largeArc 1 $x $y" fill="none" stroke="$color" stroke-width="8" stroke-linecap="round"/>
  <text x="50" y="45" text-anchor="middle" font-size="18" font-weight="bold" fill="$color">$Score</text>
  <text x="50" y="58" text-anchor="middle" font-size="7" fill="#64748b" font-weight="600">$riskLabel</text>
</svg>
"@
}

function Build-BusinessRiskAssessment {
    param([int]$HwScore, [int]$SecScore, $SystemInfo, $Stability, $StressResults)
    $avg = [math]::Round(($HwScore + $SecScore) / 2)
    $lines = @()

    if ($avg -ge 85) {
        $lines += "This system is operating in excellent condition with minimal risk to business operations."
        $lines += "Regular maintenance and monitoring should continue to maintain this status."
    } elseif ($avg -ge 70) {
        $lines += "This system shows moderate wear but remains functional for daily business use."
        $lines += "Addressing the identified issues within 30-60 days will help prevent service disruptions."
    } elseif ($avg -ge 55) {
        $lines += "This system presents elevated risk to business continuity with multiple areas requiring attention."
        $lines += "We recommend prioritizing critical repairs within 14 days to avoid potential data loss or extended downtime."
    } else {
        $lines += "This system is at high risk of failure and poses an immediate threat to business operations."
        $lines += "Critical action is required within 7 days. Consider temporary backup solutions while repairs are underway."
    }

    # Add specific risk factors
    if ($Stability -and $Stability.TotalBSODs -ge 3) {
        $lines += "Frequent Blue Screen events ($($Stability.TotalBSODs) in 90 days) indicate potential hardware instability that could result in unexpected data loss."
    }
    if ($SystemInfo -and $SystemInfo.Battery -and $SystemInfo.Battery.Present -and $SystemInfo.Battery.HealthPct -lt 50) {
        $lines += "Battery health is critically low ($($SystemInfo.Battery.HealthPct)%), which limits mobile use and increases risk of abrupt shutdowns."
    }
    if ($StressResults -and $StressResults.CPU -and -not $StressResults.CPU.Passed) {
        $lines += "CPU stress test failure suggests potential thermal or hardware degradation that may lead to system instability under heavy workloads."
    }
    if ($SecScore -lt 50) {
        $lines += "The low security score exposes the system to malware, ransomware, and unauthorized access. Immediate hardening is strongly recommended."
    }

    return ($lines -join " ")
}

function Build-RemediationTable {
    param($HwIssues, $SecurityFailures)
    $items = @()

    foreach ($issue in $HwIssues) {
        $priority = if ($issue -match "FAIL|critical|failing") { "Critical" }
                    elseif ($issue -match "error|nearly full|throttl") { "High" }
                    else { "Medium" }
        $time = switch ($priority) { "Critical" { "1-2 hours" } "High" { "2-4 hours" } default { "1 hour" } }
        $items += @{ Issue = $issue; Priority = $priority; Status = "Open"; EstTime = $time }
    }

    foreach ($sec in $SecurityFailures) {
        $priority = if ($sec.Points -ge 7) { "Critical" } elseif ($sec.Points -ge 3) { "High" } else { "Medium" }
        $time = switch ($priority) { "Critical" { "30-60 min" } "High" { "15-30 min" } default { "10-15 min" } }
        $items += @{ Issue = $sec.Check; Priority = $priority; Status = "Open"; EstTime = $time }
    }

    return $items | Select-Object -First 15
}

function Build-RecommendedServices {
    param($HwIssues, $SecurityFailures, $SystemInfo, $StressResults)
    $services = @()

    # Map findings to PC Plus service offerings
    $hasStorageIssue = $HwIssues | Where-Object { $_ -match "Disk|SSD|drive|storage" }
    $hasThermalIssue = $HwIssues | Where-Object { $_ -match "temp|thermal|throttl|overheat" }
    $hasRamIssue = $HwIssues | Where-Object { $_ -match "RAM|memory" }
    $hasBatteryIssue = $HwIssues | Where-Object { $_ -match "Battery" }
    $hasSecurityIssue = $SecurityFailures.Count -gt 3

    if ($hasStorageIssue) {
        $services += @{ Service = "SSD Upgrade & Data Migration"; Description = "Replace aging/failing drive with fast NVMe SSD and migrate all data."; PriceRange = "$120 - $250" }
    }
    if ($hasThermalIssue) {
        $services += @{ Service = "Thermal Paste & Cooling Service"; Description = "Clean internal fans, replace thermal paste, optimize airflow."; PriceRange = "$60 - $90" }
    }
    if ($hasRamIssue) {
        $services += @{ Service = "RAM Upgrade"; Description = "Install additional or replacement RAM modules for better performance."; PriceRange = "$50 - $120" }
    }
    if ($hasBatteryIssue) {
        $services += @{ Service = "Battery Replacement"; Description = "Replace worn battery to restore portable runtime."; PriceRange = "$60 - $140" }
    }
    if ($hasSecurityIssue) {
        $services += @{ Service = "Security Hardening Package"; Description = "Full security audit remediation, patch management, and protection setup."; PriceRange = "$80 - $150" }
    }
    if ($StressResults -and $StressResults.CPU -and -not $StressResults.CPU.Passed) {
        $services += @{ Service = "Hardware Diagnostics & Repair"; Description = "In-depth hardware testing to isolate and fix failing components."; PriceRange = "$80 - $200" }
    }

    # Always recommend maintenance
    $services += @{ Service = "Annual Maintenance Plan"; Description = "Quarterly checkups, priority support, and preventive maintenance."; PriceRange = "$199/year" }

    return $services
}

# ─────────────────────────────────────────────────────────────────────────────
# REPORT GENERATION
# ─────────────────────────────────────────────────────────────────────────────

function Build-HardwareReport {
    param($Params, $SystemInfo, $Network, $Software, $Performance, $StressResults, $LicenseKeys, $Stability, $BatteryDetail, $PowerInfo, $SpeedTest, $Gaming, $HistoryComparison, $ScanMode, $BootPerf, $Win11Ready)
    $date = Get-Date -Format "MMMM dd, yyyy 'at' h:mm tt"
    $iconPass = "&#10004;"; $iconFail = "&#10008;"; $iconWarn = "&#9888;"

    # ── WEIGHTED SCORING (Storage 25%, CPU/RAM 20%, Thermal 15%, Stability 15%, Battery 10%, Devices 10%, Network 5%) ──
    $hwIssues = @()
    # Storage (25%)
    $storageScore = 100
    foreach ($d in $SystemInfo.SMART) { if ($d.Health -ne "Healthy") { $storageScore -= 25; $hwIssues += "Disk $($d.Model): $($d.Health)" } }
    foreach ($d in $SystemInfo.Disks) { if ($d.UsedPct -gt 90) { $storageScore -= 20; $hwIssues += "Drive $($d.Drive) nearly full ($($d.UsedPct)%)" } elseif ($d.UsedPct -gt 75) { $storageScore -= 10 } }
    if ($StressResults.Disk -and -not $StressResults.Disk.Passed) { $storageScore -= 20; $hwIssues += "Disk benchmark FAILED" }
    $storageScore = [math]::Max($storageScore, 0)
    # CPU/RAM (20%)
    $cpuMemScore = 100
    if ($StressResults.CPU -and -not $StressResults.CPU.Passed) { $cpuMemScore -= 35; $hwIssues += "CPU stress test FAILED" }
    if ($StressResults.RAM -and -not $StressResults.RAM.Passed) { $cpuMemScore -= 40; $hwIssues += "RAM stress test FAILED" }
    if ($StressResults.GPU -and -not $StressResults.GPU.Passed) { $cpuMemScore -= 15; $hwIssues += "GPU stress test FAILED" }
    if ($Performance.CPUPercent -gt 90) { $cpuMemScore -= 10 }
    if ($Performance.RAMPercent -gt 90) { $cpuMemScore -= 10 }
    $cpuMemScore = [math]::Max($cpuMemScore, 0)
    # Thermal (15%)
    $thermalScore = 100
    foreach ($t in $SystemInfo.Temperatures) { if ($t.TempC -gt 80) { $thermalScore -= 25; $hwIssues += "High temperature: $($t.TempC)C" } elseif ($t.TempC -gt 60) { $thermalScore -= 10 } }
    if ($StressResults.CPU -and $StressResults.CPU.ThrottleDetected) { $thermalScore -= 30; $hwIssues += "CPU thermal throttling detected" }
    $thermalScore = [math]::Max($thermalScore, 0)
    # Stability (15%)
    $stabilityScore = 100
    if ($Stability) {
        if ($Stability.TotalBSODs -ge 5) { $stabilityScore -= 40; $hwIssues += "$($Stability.TotalBSODs) BSODs in last 90 days" }
        elseif ($Stability.TotalBSODs -ge 1) { $stabilityScore -= ($Stability.TotalBSODs * 10) }
        if ($Stability.TotalUnexpected -ge 5) { $stabilityScore -= 25; $hwIssues += "$($Stability.TotalUnexpected) unexpected shutdowns" }
        elseif ($Stability.TotalUnexpected -ge 1) { $stabilityScore -= ($Stability.TotalUnexpected * 8) }
        if ($Stability.TotalWHEA -ge 3) { $stabilityScore -= 20 }
        if ($Stability.TotalDiskErrors -ge 5) { $stabilityScore -= 15 }
    }
    $stabilityScore = [math]::Max($stabilityScore, 0)
    # Battery/Power (10%)
    $batteryPowerScore = 100
    if ($SystemInfo.Battery.Present -and $SystemInfo.Battery.HealthPct -gt 0) {
        if ($SystemInfo.Battery.HealthPct -lt 40) { $batteryPowerScore = 30; $hwIssues += "Battery health critical: $($SystemInfo.Battery.HealthPct)%" }
        elseif ($SystemInfo.Battery.HealthPct -lt 60) { $batteryPowerScore = 55 }
        elseif ($SystemInfo.Battery.HealthPct -lt 80) { $batteryPowerScore = 75 }
    }
    if ($PowerInfo -and $PowerInfo.UnexpectedShutdowns -ge 3) { $batteryPowerScore -= 20 }
    $batteryPowerScore = [math]::Max($batteryPowerScore, 0)
    # Devices (10%)
    $deviceScore = 100
    if ($SystemInfo.DeviceErrors.Count -gt 0) { $deviceScore -= ($SystemInfo.DeviceErrors.Count * 10); $hwIssues += "$($SystemInfo.DeviceErrors.Count) Device Manager errors" }
    $deviceScore = [math]::Max($deviceScore, 0)
    # Network (5%)
    $networkScore = 100
    if ($SpeedTest -and $SpeedTest.PacketLoss -and $SpeedTest.PacketLoss -ne "N/A" -and $SpeedTest.PacketLoss -ne "0%") {
        $lossVal = [int]($SpeedTest.PacketLoss -replace '%','')
        if ($lossVal -ge 10) { $networkScore -= 40 } elseif ($lossVal -ge 5) { $networkScore -= 20 }
    }
    $networkScore = [math]::Max($networkScore, 0)

    # Weighted total
    $hwScore = [math]::Round(($storageScore * 0.25) + ($cpuMemScore * 0.20) + ($thermalScore * 0.15) + ($stabilityScore * 0.15) + ($batteryPowerScore * 0.10) + ($deviceScore * 0.10) + ($networkScore * 0.05))
    $hwScore = [math]::Max([math]::Min($hwScore, 100), 0)
    $hwGrade = if ($hwScore -ge 90){"A"} elseif ($hwScore -ge 80){"B"} elseif ($hwScore -ge 70){"C"} elseif ($hwScore -ge 60){"D"} else {"F"}
    $hwColor = if ($hwGrade -eq "A" -or $hwGrade -eq "B"){"#27ae60"} elseif ($hwGrade -eq "C" -or $hwGrade -eq "D"){"#f39c12"} else {"#e74c3c"}
    $dashOffset = 283 - (283 * $hwScore / 100)

    # Load logo as base64 data URI
    $logoDataUri = ""
    $logoPath = Join-Path $Global:ScriptDir "logo-base64.txt"
    if (Test-Path $logoPath) {
        try {
            $logoB64 = (Get-Content $logoPath -Raw).Trim()
            $logoDataUri = "data:image/png;base64,$logoB64"
        } catch { $logoDataUri = "" }
    }
    $logoHTML = if ($logoDataUri) {
        "<img src='$logoDataUri' alt='PC Plus Computing' style='width:350px;max-width:90%;margin-bottom:30px;'/>"
    } else {
        "<div style='background:#0a1628;color:#fff;padding:20px 50px;font-size:22pt;font-weight:bold;letter-spacing:3px;border-radius:6px;margin-bottom:30px;'>PC PLUS COMPUTING</div>"
    }

    # Load QR codes as base64 data URIs
    $qrAppointmentUri = ""; $qrServiceUri = ""
    $qrAppPath = Join-Path $Global:ScriptDir "qr-appointments.txt"
    $qrSvcPath = Join-Path $Global:ScriptDir "qr-service-requests.txt"
    if (Test-Path $qrAppPath) { try { $qrAppointmentUri = "data:image/png;base64,$((Get-Content $qrAppPath -Raw).Trim())" } catch {} }
    if (Test-Path $qrSvcPath) { try { $qrServiceUri = "data:image/png;base64,$((Get-Content $qrSvcPath -Raw).Trim())" } catch {} }

    # Load cross-promotion banners
    $bannerSecTopUri = ""; $bannerSecBottomUri = ""
    $bstPath = Join-Path $Global:ScriptDir "banner-security-top.txt"
    $bsbPath = Join-Path $Global:ScriptDir "banner-security-bottom.txt"
    if (Test-Path $bstPath) { try { $bannerSecTopUri = "data:image/jpeg;base64,$((Get-Content $bstPath -Raw).Trim())" } catch {} }
    if (Test-Path $bsbPath) { try { $bannerSecBottomUri = "data:image/jpeg;base64,$((Get-Content $bsbPath -Raw).Trim())" } catch {} }

    # Load hardware report's own banner
    $bannerHwOwnUri = ""
    $bhoPath = Join-Path $Global:ScriptDir "banner-hardware-top.txt"
    if (Test-Path $bhoPath) { try { $bannerHwOwnUri = "data:image/jpeg;base64,$((Get-Content $bhoPath -Raw).Trim())" } catch {} }

    # Battery score for display
    $batteryScore = if ($SystemInfo.Battery.Present -and $SystemInfo.Battery.HealthPct -gt 0) { $SystemInfo.Battery.HealthPct } else { -1 }

    # Helper: color for a sub-score
    function Get-ScoreColor($s) { if ($s -ge 80) { "#16a34a" } elseif ($s -ge 60) { "#f59e0b" } else { "#dc2626" } }
    function Get-ScoreGrade($s) { if ($s -ge 90){"A"} elseif($s -ge 80){"B"} elseif($s -ge 70){"C"} elseif($s -ge 60){"D"} else{"F"} }

    # Build key findings
    $keyFindings = @()
    if ($hwIssues.Count -eq 0) { $keyFindings += "All hardware components are functioning within normal parameters." }
    foreach ($d in $SystemInfo.SMART) { if ($d.Health -ne "Healthy") { $keyFindings += "Storage drive '$($d.Model)' is reporting $($d.Health) status and may need replacement." } }
    foreach ($d in $SystemInfo.Disks) { if ($d.UsedPct -gt 90) { $keyFindings += "Drive $($d.Drive) is nearly full at $($d.UsedPct)% used, which can degrade performance." } }
    if ($SystemInfo.DeviceErrors.Count -gt 0) { $keyFindings += "$($SystemInfo.DeviceErrors.Count) device(s) in Device Manager are reporting errors and may need driver updates." }
    if ($SystemInfo.Battery.Present -and $SystemInfo.Battery.HealthPct -gt 0 -and $SystemInfo.Battery.HealthPct -lt 50) { $keyFindings += "Battery health is at $($SystemInfo.Battery.HealthPct)% - replacement recommended for reliable portable use." }
    if ($StressResults.CPU -and -not $StressResults.CPU.Passed) { $keyFindings += "The CPU failed its stress test, which may indicate overheating or hardware instability." }
    if ($StressResults.RAM -and -not $StressResults.RAM.Passed) { $keyFindings += "RAM stress test detected errors - one or more memory modules may be faulty." }
    if ($StressResults.CPU -and $StressResults.CPU.Passed -and $StressResults.RAM -and $StressResults.RAM.Passed) { $keyFindings += "CPU and RAM both passed stress testing with no errors detected." }
    if ($SystemInfo.Temperatures.Count -gt 0) {
        $maxTemp = ($SystemInfo.Temperatures | Measure-Object -Property TempC -Maximum).Maximum
        if ($maxTemp -gt 80) { $keyFindings += "Maximum temperature reading is ${maxTemp}C, which is in the critical range." }
        elseif ($maxTemp -gt 60) { $keyFindings += "Temperatures are slightly elevated (peak ${maxTemp}C) - ensure proper airflow and clean dust filters." }
        else { $keyFindings += "All temperature readings are within safe operating ranges." }
    }
    if ($Stability -and $Stability.TotalBSODs -gt 0) { $keyFindings += "$($Stability.TotalBSODs) Blue Screen of Death events recorded in the last 90 days." }
    if ($Stability -and $Stability.TotalUnexpected -gt 0) { $keyFindings += "$($Stability.TotalUnexpected) unexpected shutdowns detected - may indicate power or hardware issues." }
    if ($SpeedTest -and $SpeedTest.DownloadMbps -ne "N/A") { $keyFindings += "Network download speed: $($SpeedTest.DownloadMbps), Ping: $($SpeedTest.PingMs)" }
    if ($Gaming -and $Gaming.Score -gt 0) { $keyFindings += "Gaming readiness: $($Gaming.Tier) (Score: $($Gaming.Score)/100)" }
    $keyFindings = $keyFindings | Select-Object -First 8

    # Build recommendations
    $recommendations = @()
    foreach ($d in $SystemInfo.SMART) { if ($d.Health -ne "Healthy") { $recommendations += "Replace the failing '$($d.Model)' drive and restore data from backup." } }
    foreach ($d in $SystemInfo.Disks) { if ($d.UsedPct -gt 90) { $recommendations += "Free up space on drive $($d.Drive) or upgrade to a larger drive." } }
    if ($SystemInfo.DeviceErrors.Count -gt 0) { $recommendations += "Update or reinstall drivers for the $($SystemInfo.DeviceErrors.Count) device(s) showing errors." }
    if ($SystemInfo.Battery.Present -and $SystemInfo.Battery.HealthPct -gt 0 -and $SystemInfo.Battery.HealthPct -lt 50) { $recommendations += "Replace the battery to restore reliable portable operation." }
    if ($StressResults.CPU -and -not $StressResults.CPU.Passed) { $recommendations += "Clean CPU heatsink and reapply thermal paste; test again to rule out hardware failure." }
    if ($StressResults.RAM -and -not $StressResults.RAM.Passed) { $recommendations += "Run individual stick testing to isolate the faulty RAM module and replace it." }
    if ($recommendations.Count -eq 0) { $recommendations += "Continue regular maintenance: keep Windows updated, run periodic diagnostics, and maintain clean airflow." }

    # Build RAM rows
    $ramRows = ($SystemInfo.RAMSticks | ForEach-Object { "<tr><td>$($_.Slot)</td><td>$($_.CapacityGB) GB</td><td>$($_.Speed)</td><td>$($_.Type)</td><td>$($_.Manufacturer)</td><td>$($_.PartNumber)</td></tr>" }) -join "`n"
    # GPU rows
    $gpuRows = ($SystemInfo.GPUs | ForEach-Object { "<tr><td>$($_.Name)</td><td>$(if($_.VRAM_MB -gt 0){"$($_.VRAM_MB) MB"}else{"Shared"})</td><td>$($_.DriverVer)</td><td>$($_.DriverDate)</td><td>$($_.Resolution)</td></tr>" }) -join "`n"
    # SMART rows
    $smartRows = ($SystemInfo.SMART | ForEach-Object { $c=if($_.Health -eq 'Healthy'){'pass'}else{'fail'}; "<tr><td>$($_.Model)</td><td>$($_.MediaType)</td><td>$($_.BusType)</td><td>$($_.SizeGB) GB</td><td class='$c'>$($_.Health)</td><td>$($_.PowerOnHours)</td><td>$($_.Temperature)</td><td>$($_.ReadErrors)</td><td>$($_.Wear)</td></tr>" }) -join "`n"
    # Disk rows with progress bars
    $diskRowsDetailed = ($SystemInfo.Disks | ForEach-Object {
        $c = if($_.UsedPct -gt 90){'#dc2626'}elseif($_.UsedPct -gt 75){'#f59e0b'}else{'#16a34a'}
        "<tr><td>$($_.Drive)</td><td>$($_.Size) GB</td><td>$($_.Free) GB</td><td style='width:35%;'><div style='display:flex;align-items:center;gap:8px;'><div class='progress-track'><div class='progress-fill' style='width:$($_.UsedPct)%;background:$c;'></div></div><span style='color:$c;font-weight:600;white-space:nowrap;'>$($_.UsedPct)%</span></div></td></tr>"
    }) -join "`n"
    # Monitor rows
    $monitorRows = ($SystemInfo.Monitors | ForEach-Object { "<tr><td>$($_.Model)</td><td>$($_.Manufacturer)</td><td>$($_.Serial)</td><td>$($_.Year)</td></tr>" }) -join "`n"
    # Printer rows
    $printerRows = ($SystemInfo.Printers | ForEach-Object { "<tr><td>$($_.Name)</td><td>$($_.Port)</td><td>$($_.Driver)</td><td>$(if($_.Default){'Yes'}else{'No'})</td></tr>" }) -join "`n"
    # Network rows
    $netRows = ($Network.Adapters | ForEach-Object { "<tr><td>$($_.Name)</td><td>$($_.IP)</td><td>$($_.MAC)</td><td>$($_.DNS)</td><td>$($_.Speed)</td></tr>" }) -join "`n"
    # Stress test results
    $stressHTML = ""
    if ($StressResults.CPU) {
        $cpuClass = if($StressResults.CPU.Passed){"pass"}else{"fail"}
        $throttleWarn = if($StressResults.CPU.ThrottleDetected){"<br/><span class='fail'>$iconWarn THROTTLING DETECTED</span>"}else{""}
        $stressHTML += "<tr><td>CPU Stress Test</td><td class='$cpuClass'>$(if($StressResults.CPU.Passed){"$iconPass PASSED"}else{"$iconFail FAILED"})$throttleWarn</td><td>$($StressResults.CPU.Threads) threads, $($StressResults.CPU.Duration)s, $($StressResults.CPU.Iterations) iterations</td><td>Start: $($StressResults.CPU.StartTemp)C / Peak: $($StressResults.CPU.MaxTemp)C / End: $($StressResults.CPU.EndTemp)C<br/>Recovery: $($StressResults.CPU.RecoveryTemp)C (15s cooldown)</td></tr>`n"
    }
    if ($StressResults.RAM) {
        $ramClass = if($StressResults.RAM.Passed){"pass"}else{"fail"}
        $stressHTML += "<tr><td>RAM Stress Test</td><td class='$ramClass'>$(if($StressResults.RAM.Passed){"$iconPass PASSED"}else{"$iconFail FAILED"})</td><td>$($StressResults.RAM.BlocksTested) blocks ($($StressResults.RAM.TotalMBTested) MB tested)</td><td>$($StressResults.RAM.Errors) errors</td></tr>`n"
    }
    if ($StressResults.Disk) {
        $dkClass = if($StressResults.Disk.Passed){"pass"}else{"fail"}
        $stressHTML += "<tr><td>Disk Benchmark</td><td class='$dkClass'>$(if($StressResults.Disk.Passed){"$iconPass PASSED"}else{"$iconFail FAILED"})</td><td>Write: $($StressResults.Disk.SeqWriteMBps) MB/s | Read: $($StressResults.Disk.SeqReadMBps) MB/s</td><td>$($StressResults.Disk.FileSizeMB) MB test file</td></tr>`n"
    }
    if ($StressResults.GPU) {
        $gpuClass = if($StressResults.GPU.Passed){"pass"}else{"fail"}
        $stressHTML += "<tr><td>GPU Stress Test</td><td class='$gpuClass'>$(if($StressResults.GPU.Passed){"$iconPass PASSED"}else{"$iconFail FAILED"})</td><td>$($StressResults.GPU.GPUName), $($StressResults.GPU.Iterations) render cycles</td><td>Max Temp: $($StressResults.GPU.MaxTemp)C</td></tr>`n"
    }
    # Hardware issues
    $issuesHTML = if ($hwIssues.Count -gt 0) {
        ($hwIssues | ForEach-Object { "<div style='padding:8px 12px;margin:4px 0;background:#fef5f5;border-left:4px solid #dc2626;border-radius:4px;'><span class='fail'>$iconFail</span> $_</div>" }) -join "`n"
    } else { "<div style='padding:12px;background:#eafaf1;border-left:4px solid #16a34a;border-radius:4px;'><span class='pass'>$iconPass</span> <strong>No hardware issues detected.</strong></div>" }
    # Device errors
    $devErrHTML = if ($SystemInfo.DeviceErrors.Count -gt 0) {
        "<div class='sub-header' style='color:#dc2626;'>Device Manager Errors ($($SystemInfo.DeviceErrors.Count))</div><table><tr><th>Device</th><th>Class</th><th>Error</th></tr>" +
        (($SystemInfo.DeviceErrors | ForEach-Object { "<tr><td class='fail'>$($_.Device)</td><td>$($_.Class)</td><td class='fail'>$($_.Error)</td></tr>" }) -join "`n") + "</table>"
    } else { "<div class='sub-header' style='color:#16a34a;'>Device Manager - All Clear</div><p style='padding:8px;background:#eafaf1;border-radius:4px;'><span class='pass'>$iconPass</span> All devices functioning properly.</p>" }
    # Battery
    $batteryHTML = ""
    if ($SystemInfo.Battery.Present) {
        $bhClass = if($SystemInfo.Battery.HealthPct -ge 80){"pass"}elseif($SystemInfo.Battery.HealthPct -ge 50){"warn"}else{"fail"}
        $bhColor = if($SystemInfo.Battery.HealthPct -ge 80){"#16a34a"}elseif($SystemInfo.Battery.HealthPct -ge 50){"#f59e0b"}else{"#dc2626"}
        $bhPct = $SystemInfo.Battery.HealthPct
        $batteryHTML = @"
<div class="sub-header">Battery Health</div>
<div style="display:flex;align-items:center;gap:20px;margin-bottom:12px;">
<div style="text-align:center;">
<svg viewBox="0 0 100 100" width="80" height="80">
<circle cx="50" cy="50" r="40" fill="none" stroke="#e5e7eb" stroke-width="8"/>
<circle cx="50" cy="50" r="40" fill="none" stroke="$bhColor" stroke-width="8" stroke-dasharray="251" stroke-dashoffset="$([math]::Round(251 - (251 * $bhPct / 100)))" transform="rotate(-90 50 50)" stroke-linecap="round"/>
<text x="50" y="55" text-anchor="middle" font-size="18" font-weight="bold" fill="$bhColor">$bhPct%</text>
</svg>
</div>
<div style="flex:1;">
<table><tr><th style="width:35%;">Property</th><th>Value</th></tr>
<tr><td>Status</td><td>$($SystemInfo.Battery.Status)</td></tr>
<tr><td>Current Charge</td><td>$($SystemInfo.Battery.Charge)%</td></tr>
<tr><td>Battery Health</td><td class='$bhClass' style="font-size:11pt;">$($SystemInfo.Battery.HealthPct)%</td></tr>
<tr><td>Design Capacity</td><td>$($SystemInfo.Battery.DesignCap) mWh</td></tr>
<tr><td>Full Charge Capacity</td><td>$($SystemInfo.Battery.FullCap) mWh</td></tr>
<tr><td>Cycle Count</td><td>$($SystemInfo.Battery.CycleCount)</td></tr>
<tr><td>Estimated Runtime</td><td>$($SystemInfo.Battery.Runtime)</td></tr>
</table>
</div>
</div>
"@
    }
    # License keys
    $winKeyRows = if ($LicenseKeys.WindowsKeys.Count -gt 0) {
        ($LicenseKeys.WindowsKeys | ForEach-Object { "<tr><td>$($_.Source)</td><td><strong style='font-family:Consolas,monospace;letter-spacing:1px;'>$($_.Key)</strong></td></tr>" }) -join "`n"
    } else { "<tr><td colspan='2' class='warn'>$iconWarn No Windows product key found</td></tr>" }
    $officeKeyRows = if ($LicenseKeys.OfficeKeys.Count -gt 0) {
        ($LicenseKeys.OfficeKeys | ForEach-Object { "<tr><td>$($_.Product) ($($_.Version))</td><td><strong style='font-family:Consolas,monospace;'>$($_.Key)</strong></td></tr>" }) -join "`n"
    } else { "<tr><td colspan='2'>No Office keys found (may use 365 account)</td></tr>" }
    $adobeKeyRows = if ($LicenseKeys.AdobeKeys.Count -gt 0) {
        ($LicenseKeys.AdobeKeys | ForEach-Object { "<tr><td>$($_.Product)</td><td><strong style='font-family:Consolas,monospace;'>$($_.Key)</strong></td></tr>" }) -join "`n"
    } else { "" }
    $wifiRows = if ($LicenseKeys.WiFiPasswords.Count -gt 0) {
        ($LicenseKeys.WiFiPasswords | ForEach-Object { "<tr><td><strong>$($_.SSID)</strong></td><td style='font-family:Consolas,monospace;'>$($_.Password)</td><td>$($_.Auth)</td></tr>" }) -join "`n"
    } else { "<tr><td colspan='3'>No saved WiFi profiles</td></tr>" }
    # Top processes
    $topProcRows = ($Software.TopRAM | ForEach-Object { "<tr><td>$($_.Name)</td><td>$($_.RAM_MB) MB</td></tr>" }) -join "`n"
    # Installed software
    $swRows = ($Software.Installed | ForEach-Object { "<tr><td>$($_.Name)</td><td>$($_.Version)</td><td>$($_.Publisher)</td></tr>" }) -join "`n"
    # Temperature rows with color coding
    $tempRows = if ($SystemInfo.Temperatures.Count -gt 0) {
        ($SystemInfo.Temperatures | ForEach-Object {
            $tc = if($_.TempC -gt 80){"fail"}elseif($_.TempC -gt 60){"warn"}else{"pass"}
            $tColor = if($_.TempC -gt 80){"#dc2626"}elseif($_.TempC -gt 60){"#f59e0b"}else{"#16a34a"}
            $tPct = [math]::Min([math]::Round($_.TempC / 100 * 100), 100)
            "<tr><td>$($_.Zone)</td><td class='$tc'>$($_.TempC)&deg;C</td><td class='$tc'>$($_.TempF)&deg;F</td><td style='width:30%;'><div class='progress-track'><div class='progress-fill' style='width:$tPct%;background:$tColor;'></div></div></td></tr>"
        }) -join "`n"
    } else { "" }
    # Technician notes field
    $techNotes = if ($Params.TechNotes) { "<div class='section-header'>Technician Notes</div><div style='padding:16px 20px;background:#f8fafc;border:1px solid #d1d5db;border-radius:8px;min-height:60px;white-space:pre-wrap;font-size:10pt;line-height:1.7;margin-bottom:16px;'>$([System.Web.HttpUtility]::HtmlEncode($Params.TechNotes))</div>" } else { "" }

    # Build key findings HTML
    $findingsHTML = ($keyFindings | ForEach-Object { "<li style='margin-bottom:6px;'>$_</li>" }) -join "`n"
    # Build recommendations HTML
    $recsHTML = ""
    for ($i = 0; $i -lt $recommendations.Count; $i++) {
        $recsHTML += "<li style='margin-bottom:6px;'>$($recommendations[$i])</li>`n"
    }

    # ── NEW: Generate executive summary enhancements ──
    $securityFailures = @()  # Security failures come from security report; pass empty for HW-only context
    $riskGaugeSVG = Build-SVGRiskGauge -Score $hwScore
    $businessRiskText = Build-BusinessRiskAssessment -HwScore $hwScore -SecScore 0 -SystemInfo $SystemInfo -Stability $Stability -StressResults $StressResults
    $remediationItems = Build-RemediationTable -HwIssues $hwIssues -SecurityFailures $securityFailures
    $recommendedServices = Build-RecommendedServices -HwIssues $hwIssues -SecurityFailures $securityFailures -SystemInfo $SystemInfo -StressResults $StressResults

    # Build remediation HTML rows
    $remediationHTML = ""
    if ($remediationItems.Count -gt 0) {
        $remediationRows = ($remediationItems | ForEach-Object {
            $prColor = switch ($_.Priority) { "Critical" { "#dc2626" } "High" { "#f59e0b" } default { "#2596be" } }
            $prBg = switch ($_.Priority) { "Critical" { "#fef2f2" } "High" { "#fffbeb" } default { "#f0f7fb" } }
            "<tr><td style='color:$prColor;font-weight:700;'>$($_.Priority)</td><td>$($_.Issue)</td><td style='text-align:center;'><span style='padding:3px 10px;border-radius:12px;background:#fff3cd;color:#856404;font-size:8pt;font-weight:600;'>$($_.Status)</span></td><td style='text-align:center;'>$($_.EstTime)</td></tr>"
        }) -join "`n"
        $remediationHTML = @"
<div class='sub-header' style='margin-top:18px;'>Remediation Tracking</div>
<table><tr><th>Priority</th><th>Issue</th><th style='text-align:center;'>Status</th><th style='text-align:center;'>Est. Time</th></tr>
$remediationRows
</table>
"@
    }

    # Build recommended services HTML
    $servicesHTML = ""
    if ($recommendedServices.Count -gt 0) {
        $serviceRows = ($recommendedServices | ForEach-Object {
            "<tr><td style='font-weight:600;color:#0a1628;'>$($_.Service)</td><td>$($_.Description)</td><td style='text-align:center;font-weight:700;color:#0d4b71;white-space:nowrap;'>$($_.PriceRange)</td></tr>"
        }) -join "`n"
        $servicesHTML = @"
<div class='sub-header' style='margin-top:18px;'>&#128736; Recommended Services</div>
<div style='padding:10px;background:#f0f7fb;border-left:4px solid #2596be;border-radius:4px;margin-bottom:10px;font-size:9pt;color:#0d4b71;'>
Based on the diagnostic findings, the following services are recommended to address identified issues and optimize system performance.
</div>
<table><tr><th>Service</th><th>Description</th><th style='text-align:center;'>Price Range</th></tr>
$serviceRows
</table>
"@
    }

    # Build category score cards for executive summary
    function Build-MiniDonut($score, $label) {
        $color = if ($score -ge 80) { "#16a34a" } elseif ($score -ge 60) { "#f59e0b" } else { "#dc2626" }
        $offset = [math]::Round(251 - (251 * $score / 100))
        $grade = if ($score -ge 90){"A"} elseif($score -ge 80){"B"} elseif($score -ge 70){"C"} elseif($score -ge 60){"D"} else{"F"}
        return @"
<div class="score-card">
<svg viewBox="0 0 100 100" width="72" height="72">
<circle cx="50" cy="50" r="40" fill="none" stroke="#e5e7eb" stroke-width="7"/>
<circle cx="50" cy="50" r="40" fill="none" stroke="$color" stroke-width="7" stroke-dasharray="251" stroke-dashoffset="$offset" transform="rotate(-90 50 50)" stroke-linecap="round"/>
<text x="50" y="56" text-anchor="middle" font-size="22" font-weight="bold" fill="$color">$grade</text>
</svg>
<div class="score-card-label">$label</div>
<div class="score-card-value" style="color:$color;">$score / 100</div>
</div>
"@
    }

    $storageCard = Build-MiniDonut $storageScore "Storage Health"
    $cpuMemCard = Build-MiniDonut $cpuMemScore "CPU &amp; Memory"
    $thermalCard = Build-MiniDonut $thermalScore "Thermal"
    $deviceCard = Build-MiniDonut $deviceScore "Devices"
    $batteryCard = if ($batteryScore -ge 0) { Build-MiniDonut $batteryScore "Battery" } else { "" }

    # Performance bars
    $cpuBarColor = if($Performance.CPUPercent -gt 90){"#dc2626"}elseif($Performance.CPUPercent -gt 70){"#f59e0b"}else{"#16a34a"}
    $ramBarColor = if($Performance.RAMPercent -gt 90){"#dc2626"}elseif($Performance.RAMPercent -gt 70){"#f59e0b"}else{"#16a34a"}

    # RAM slots progress bar
    $ramSlotPct = if ($SystemInfo.RAMSlots.Total -gt 0) { [math]::Round($SystemInfo.RAMSlots.Used / $SystemInfo.RAMSlots.Total * 100) } else { 0 }

$html = @"
<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8"/><title>Hardware Diagnostic Report - $($Params.CustomerName)</title>
<style>
@page { size: letter; margin: 0.5in 0.6in 0.9in 0.6in; }
* { margin:0; padding:0; box-sizing:border-box; }
body { font-family: 'Segoe UI', -apple-system, Tahoma, sans-serif; font-size: 9.5pt; color: #1e293b; line-height: 1.6; background: #fff; }
h1,h2,h3,h4 { margin:0; }

/* Print handling */
@media print {
    body { -webkit-print-color-adjust: exact; print-color-adjust: exact; font-size: 9pt; }
    .page-break { page-break-before: always; }
    .no-break { page-break-inside: avoid; }
    table { page-break-inside: avoid; }
    .section-header { page-break-after: avoid; }
    .sub-header { page-break-after: avoid; }
    .score-cards { page-break-inside: avoid; }
    .findings-box, .recs-box { page-break-inside: avoid; }
    .summary-strip { page-break-inside: avoid; }
    .promo-banner { page-break-inside: avoid; }
    a { text-decoration: none; color: inherit; }
    tr { page-break-inside: avoid; }
}
.page-break { page-break-before: always; }

/* Fixed print footer - repeats on every page */
.print-footer {
    position: fixed; bottom: 0; left: 0; right: 0;
    padding: 6px 0; border-top: 1.5px solid #0d4b71;
    text-align: center; font-size: 7.5pt; color: #94a3b8;
    background: #fff;
}
.print-footer strong { color: #0d4b71; font-size: 7.5pt; }
.print-footer .report-name { color: #475569; }
.no-break { page-break-inside: avoid; }

/* ── Section headers ── */
.section-header {
    background: linear-gradient(135deg, #0a1628 0%, #0d4b71 100%);
    color: #fff; padding: 10px 20px; font-size: 12pt; font-weight: 600;
    margin: 24px 0 14px 0; border-radius: 6px; letter-spacing: 0.5px;
    display: flex; align-items: center; gap: 10px;
}
.section-header .section-icon { font-size: 14pt; opacity: 0.85; }
.sub-header {
    color: #0d4b71; font-size: 10.5pt; font-weight: 700; margin: 18px 0 8px 0;
    padding-bottom: 5px; border-bottom: 2px solid #2596be; letter-spacing: 0.3px;
}

/* ── Tables ── */
table { width: 100%; border-collapse: collapse; margin-bottom: 14px; font-size: 9pt; }
th {
    background: #0d4b71; color: #fff; padding: 7px 10px; text-align: left;
    font-weight: 600; font-size: 8.5pt; text-transform: uppercase; letter-spacing: 0.5px;
}
td { padding: 6px 10px; border-bottom: 1px solid #e2e8f0; vertical-align: middle; }
tr:nth-child(even) td { background: #f8fafc; }
tr:hover td { background: #eaf7fc; }
.pass { color: #16a34a; font-weight: 600; }
.fail { color: #dc2626; font-weight: 600; }
.warn { color: #f59e0b; font-weight: 600; }

/* ── Progress bars ── */
.progress-track {
    background: #e5e7eb; border-radius: 6px; height: 10px; flex: 1; overflow: hidden;
}
.progress-fill {
    height: 100%; border-radius: 6px; transition: width 0.3s;
}
.progress-lg .progress-track { height: 14px; border-radius: 7px; }
.progress-lg .progress-fill { border-radius: 7px; }

/* ── Score cards (executive summary) ── */
.score-cards {
    display: flex; gap: 12px; margin: 14px 0; flex-wrap: wrap; justify-content: center;
}
.score-card {
    flex: 1; min-width: 100px; max-width: 140px; text-align: center; padding: 12px 8px;
    background: #fff; border: 1px solid #e2e8f0; border-radius: 10px;
    box-shadow: 0 1px 3px rgba(0,0,0,0.05);
}
.score-card-label { font-size: 8pt; color: #64748b; text-transform: uppercase; font-weight: 600; margin-top: 4px; letter-spacing: 0.3px; }
.score-card-value { font-size: 9pt; font-weight: 700; margin-top: 2px; }

/* ── Findings & recommendations ── */
.findings-box {
    background: #f8fafc; border: 1px solid #e2e8f0; border-radius: 10px;
    padding: 16px 20px; margin: 12px 0;
}
.findings-box h3 { font-size: 10.5pt; color: #0d4b71; margin-bottom: 8px; font-weight: 700; }
.findings-box ul { margin: 0; padding-left: 18px; }
.findings-box li { font-size: 9.5pt; color: #334155; line-height: 1.6; }
.recs-box {
    background: #fffbeb; border: 1px solid #fde68a; border-radius: 10px;
    padding: 16px 20px; margin: 12px 0;
}
.recs-box h3 { font-size: 10.5pt; color: #92400e; margin-bottom: 8px; font-weight: 700; }
.recs-box ol { margin: 0; padding-left: 18px; }
.recs-box li { font-size: 9.5pt; color: #451a03; line-height: 1.6; }

/* ── Summary strip ── */
.summary-strip {
    display: flex; gap: 10px; margin: 14px 0;
}
.summary-chip {
    flex: 1; text-align: center; padding: 12px 8px; background: #f8fafc;
    border: 1px solid #e2e8f0; border-radius: 8px;
}
.summary-chip .chip-val { font-size: 18pt; font-weight: 700; color: #0a1628; display: block; }
.summary-chip .chip-lbl { font-size: 7.5pt; color: #64748b; text-transform: uppercase; font-weight: 600; letter-spacing: 0.3px; }

/* ── QR placeholder boxes ── */
.qr-row { display: flex; justify-content: center; gap: 60px; margin: 20px 0; }
.qr-item { text-align: center; }
.qr-item img { width: 160px; height: 160px; border-radius: 8px; }
.qr-item .qr-fallback { width: 160px; height: 160px; border: 2px dashed #94a3b8; border-radius: 8px; display: flex; align-items: center; justify-content: center; font-size: 7.5pt; color: #94a3b8; line-height: 1.3; }
.qr-label { font-size: 9pt; font-weight: 600; color: #0d4b71; margin-top: 8px; }
.qr-sublabel { font-size: 7.5pt; color: #64748b; margin-top: 2px; }
.promo-banner { text-align: center; margin: 20px 0; page-break-inside: avoid; }
.promo-banner img { width: 100%; max-width: 100%; border-radius: 8px; box-shadow: 0 2px 8px rgba(0,0,0,0.1); }

/* ── Repeated page footer ── */
.page-footer-bar {
    margin-top: 30px; padding: 10px 0; border-top: 2px solid #0d4b71;
    text-align: center; font-size: 8pt; color: #94a3b8;
}
.page-footer-bar strong { color: #0d4b71; }

/* ── Confidential banner ── */
.confidential-banner {
    background: #fef2f2; border: 1px solid #fca5a5; border-radius: 6px;
    padding: 8px 14px; font-size: 8.5pt; color: #991b1b; margin-bottom: 14px;
    display: flex; align-items: center; gap: 8px;
}
.confidential-banner .lock-icon { font-size: 12pt; }

/* ── Info pair rows ── */
.info-grid { display: flex; flex-wrap: wrap; gap: 0; }
.info-pair { width: 50%; display: flex; padding: 6px 10px; border-bottom: 1px solid #e2e8f0; font-size: 9pt; }
.info-pair:nth-child(4n+3), .info-pair:nth-child(4n+4) { background: #f8fafc; }
.info-pair .lbl { color: #64748b; font-weight: 600; min-width: 130px; }
.info-pair .val { color: #1e293b; }
</style></head><body>

<div class="print-footer">
<span class="report-name">Hardware Diagnostic Report</span> &nbsp;|&nbsp; <strong>$COMPANY</strong> &nbsp;|&nbsp; $WEBSITE &nbsp;|&nbsp; $PHONE
</div>

<!-- ══════════════════════════ COVER PAGE ══════════════════════════ -->
<div style="page-break-after:always;">
$(if($bannerHwOwnUri){"<div style='text-align:center;margin-bottom:15px;'><img src='$bannerHwOwnUri' alt='PC Plus Hardware Test' style='width:100%;border-radius:8px;'/></div>"})

<div style="display:flex;gap:20px;align-items:center;margin:15px 0;">
<div style="flex:1;">
<div style="background:#f8fafc;border:1px solid #e2e8f0;border-radius:10px;padding:16px;">
<table style="width:100%;font-size:10pt;border:none;margin:0;">
<tr><td style="border:none;padding:4px 8px;color:#64748b;font-weight:600;width:110px;">Customer:</td><td style="border:none;padding:4px 8px;color:#0a1628;font-weight:700;">$($Params.CustomerName)</td></tr>
$(if($Params.CustomerPhone){"<tr><td style='border:none;padding:4px 8px;color:#64748b;font-weight:600;'>Phone:</td><td style='border:none;padding:4px 8px;color:#0a1628;'>$($Params.CustomerPhone)</td></tr>"})
$(if($Params.CustomerEmail){"<tr><td style='border:none;padding:4px 8px;color:#64748b;font-weight:600;'>Email:</td><td style='border:none;padding:4px 8px;color:#0a1628;'>$($Params.CustomerEmail)</td></tr>"})
$(if($Params.ContactName){"<tr><td style='border:none;padding:4px 8px;color:#64748b;font-weight:600;'>Contact:</td><td style='border:none;padding:4px 8px;color:#0a1628;'>$($Params.ContactName)</td></tr>"})
<tr><td style="border:none;padding:4px 8px;color:#64748b;font-weight:600;">Device:</td><td style="border:none;padding:4px 8px;color:#0a1628;">$($SystemInfo.ComputerName)</td></tr>
<tr><td style="border:none;padding:4px 8px;color:#64748b;font-weight:600;">Date:</td><td style="border:none;padding:4px 8px;color:#0a1628;">$date</td></tr>
<tr><td style="border:none;padding:4px 8px;color:#64748b;font-weight:600;">Technician:</td><td style="border:none;padding:4px 8px;color:#0a1628;">$($Params.TechName)</td></tr>
</table>
</div>
</div>
<div style="text-align:center;">
<svg viewBox="0 0 100 100" width="130" height="130">
<circle cx="50" cy="50" r="45" fill="none" stroke="#e5e7eb" stroke-width="8"/>
<circle cx="50" cy="50" r="45" fill="none" stroke="$hwColor" stroke-width="8" stroke-dasharray="283" stroke-dashoffset="$dashOffset" transform="rotate(-90 50 50)" stroke-linecap="round"/>
<text x="50" y="46" text-anchor="middle" font-size="20" font-weight="bold" fill="$hwColor">$hwGrade</text>
<text x="50" y="62" text-anchor="middle" font-size="10" fill="#64748b">$hwScore / 100</text>
</svg>
<div style="font-size:9pt;color:$hwColor;font-weight:700;margin-top:4px;">Overall Health</div>
</div>
</div>

$(if($bannerSecTopUri){"<div style='text-align:center;margin-top:15px;'><img src='$bannerSecTopUri' alt='PC Plus Security Audit' style='width:100%;border-radius:8px;'/></div>"})
</div>

<!-- ══════════════════════════ EXECUTIVE SUMMARY ══════════════════════════ -->
<div class="page-break"></div>

<div class="section-header"><span class="section-icon">&#128202;</span> Executive Summary</div>

<div style="display:flex;align-items:center;gap:24px;margin:14px 0;">
<div style="text-align:center;">
<svg viewBox="0 0 100 100" width="100" height="100">
<circle cx="50" cy="50" r="40" fill="none" stroke="#e5e7eb" stroke-width="8"/>
<circle cx="50" cy="50" r="40" fill="none" stroke="$hwColor" stroke-width="8" stroke-dasharray="251" stroke-dashoffset="$([math]::Round(251 - (251 * $hwScore / 100)))" transform="rotate(-90 50 50)" stroke-linecap="round"/>
<text x="50" y="46" text-anchor="middle" font-size="20" font-weight="bold" fill="$hwColor">$hwGrade</text>
<text x="50" y="62" text-anchor="middle" font-size="11" fill="#64748b">$hwScore / 100</text>
</svg>
<div style="font-size:8pt;color:#64748b;font-weight:600;margin-top:4px;">OVERALL HEALTH</div>
</div>
<div style="flex:1;">
<div class="score-cards">
$storageCard
$cpuMemCard
$thermalCard
$deviceCard
$batteryCard
</div>
</div>
</div>

<div class="findings-box no-break">
<h3>&#128270; Key Findings</h3>
<ul>$findingsHTML</ul>
</div>

<div class="recs-box no-break">
<h3>&#9881; Top Recommendations</h3>
<ol>$recsHTML</ol>
</div>

<!-- Risk Gauge & Business Assessment -->
<div class="no-break" style="display:flex;align-items:flex-start;gap:24px;margin:18px 0;">
<div style="text-align:center;min-width:200px;">
<div style="font-size:9pt;font-weight:700;color:#0d4b71;margin-bottom:6px;text-transform:uppercase;letter-spacing:0.5px;">Risk Assessment</div>
$riskGaugeSVG
</div>
<div style="flex:1;background:#f8fafc;border:1px solid #e2e8f0;border-radius:10px;padding:16px 20px;">
<div style="font-size:10.5pt;font-weight:700;color:#0d4b71;margin-bottom:8px;">&#128202; Business Risk Assessment</div>
<div style="font-size:9.5pt;color:#334155;line-height:1.7;">$businessRiskText</div>
</div>
</div>

$remediationHTML

$servicesHTML

$issuesHTML

$(if($stressHTML){"
<div class='sub-header'>Stress Test Results</div>
<table><tr><th>Test</th><th>Result</th><th>Details</th><th>Temps</th></tr>$stressHTML</table>
"})

$(if($StressResults.CPU -and $StressResults.CPU.TempLog.Count -gt 0){
$thermalPoints = ($StressResults.CPU.TempLog | ForEach-Object { "$($_.Time)s:$($_.TempC)C" }) -join " -> "
@"
<div class='sub-header'>Thermal Timeline (CPU Stress)</div>
<div style='padding:10px;background:#f8fafc;border-radius:8px;border:1px solid #e2e8f0;margin-bottom:14px;'>
<div style='display:flex;gap:20px;margin-bottom:10px;'>
<div><strong>Start:</strong> $($StressResults.CPU.StartTemp)C</div>
<div><strong>Peak:</strong> <span style='color:$(if([double]$StressResults.CPU.MaxTemp -gt 80){"#dc2626"}elseif([double]$StressResults.CPU.MaxTemp -gt 60){"#f59e0b"}else{"#16a34a"})'>$($StressResults.CPU.MaxTemp)C</span></div>
<div><strong>End:</strong> $($StressResults.CPU.EndTemp)C</div>
<div><strong>Recovery (15s):</strong> $($StressResults.CPU.RecoveryTemp)C</div>
<div><strong>Average:</strong> $($StressResults.CPU.AvgTemp)C</div>
</div>
<div style='font-size:8pt;color:#64748b;'>$thermalPoints</div>
$(if($StressResults.CPU.ThrottleDetected){"<div style='margin-top:8px;padding:8px;background:#fef5f5;border-left:4px solid #dc2626;border-radius:4px;'><span class='fail'>$iconWarn</span> <strong>Thermal Throttling Detected</strong> - CPU clock dropped below 80% of base frequency during stress. Check cooling system.</div>"})
$(if($StressResults.CPU.BaseClock -ne 'N/A'){"<div style='margin-top:6px;font-size:8.5pt;'><strong>Clock Speed:</strong> Base: $($StressResults.CPU.BaseClock) MHz | Min during stress: $($StressResults.CPU.MinClock) MHz | Max: $($StressResults.CPU.MaxClock) MHz</div>"})
$(if($StressResults.CPU.FanSpeedStart -ne 'N/A'){"<div style='margin-top:4px;font-size:8.5pt;'><strong>Fan Speed:</strong> Start: $($StressResults.CPU.FanSpeedStart) RPM | Peak: $($StressResults.CPU.FanSpeedPeak) RPM</div>"})
</div>
"@
})

<!-- ══════════════════════════ STABILITY HISTORY ══════════════════════════ -->
$(if($Stability){
$bsodRows = if ($Stability.BSODs.Count -gt 0) { ($Stability.BSODs | Select-Object -First 10 | ForEach-Object { "<tr><td class='fail'>$($_.Time)</td><td>$($_.BugCheck)</td></tr>" }) -join "`n" } else { "" }
$kpRows = if ($Stability.KernelPower.Count -gt 0) { ($Stability.KernelPower | Select-Object -First 10 | ForEach-Object { "<tr><td class='warn'>$($_.Time)</td><td>$($_.Message)</td></tr>" }) -join "`n" } else { "" }
$diskErrRows = if ($Stability.DiskErrors.Count -gt 0) { ($Stability.DiskErrors | Select-Object -First 10 | ForEach-Object { "<tr><td>$($_.Time)</td><td>Event $($_.Id)</td><td>$($_.Message)</td></tr>" }) -join "`n" } else { "" }
$wheaRows = if ($Stability.WHEAErrors.Count -gt 0) { ($Stability.WHEAErrors | Select-Object -First 10 | ForEach-Object { "<tr><td class='fail'>$($_.Time)</td><td>$($_.Message)</td></tr>" }) -join "`n" } else { "" }
$stabColor = if($Stability.StabilityRating -eq 'Excellent'){"#16a34a"}elseif($Stability.StabilityRating -eq 'Good'){"#22c55e"}elseif($Stability.StabilityRating -eq 'Fair'){"#f59e0b"}else{"#dc2626"}
@"
<div class='page-break'></div>
<div class='section-header'><span class='section-icon'>&#128200;</span> Stability History (Last 90 Days)</div>
<div style='display:flex;gap:15px;margin-bottom:14px;flex-wrap:wrap;'>
<div class='score-card'><div style='font-size:24pt;font-weight:bold;color:$stabColor;'>$($Stability.StabilityRating)</div><div class='score-card-label'>Overall Stability</div></div>
<div class='score-card'><div style='font-size:24pt;font-weight:bold;color:$(if($Stability.TotalBSODs -eq 0){"#16a34a"}else{"#dc2626"})'>$($Stability.TotalBSODs)</div><div class='score-card-label'>Blue Screens</div></div>
<div class='score-card'><div style='font-size:24pt;font-weight:bold;color:$(if($Stability.TotalUnexpected -eq 0){"#16a34a"}else{"#f59e0b"})'>$($Stability.TotalUnexpected)</div><div class='score-card-label'>Unexpected Shutdowns</div></div>
<div class='score-card'><div style='font-size:24pt;font-weight:bold;'>$($Stability.TotalDiskErrors)</div><div class='score-card-label'>Disk Errors</div></div>
<div class='score-card'><div style='font-size:24pt;font-weight:bold;color:$(if($Stability.TotalWHEA -eq 0){"#16a34a"}else{"#dc2626"})'>$($Stability.TotalWHEA)</div><div class='score-card-label'>Hardware Errors (WHEA)</div></div>
<div class='score-card'><div style='font-size:24pt;font-weight:bold;'>$($Stability.MinidumpCount)</div><div class='score-card-label'>Minidump Files</div></div>
</div>
<div style='padding:10px;background:#f8fafc;border-radius:8px;border:1px solid #e2e8f0;margin-bottom:14px;'>
<strong>Risk Level:</strong> <span style='color:$stabColor;font-weight:bold;'>$($Stability.RiskLevel)</span>
$(if($Stability.TotalBSODs -ge 3){" | <span class='fail'>$iconFail Frequent crashes indicate potential hardware failure. Thorough testing recommended.</span>"})
$(if($Stability.TotalDiskErrors -ge 5){" | <span class='warn'>$iconWarn Elevated disk errors may indicate drive degradation.</span>"})
</div>
$(if($bsodRows){"<div class='sub-header' style='color:#dc2626;'>Blue Screen Events (BugCheck)</div><table><tr><th style='width:25%;'>Date/Time</th><th>Details</th></tr>$bsodRows</table>"})
$(if($kpRows){"<div class='sub-header' style='color:#f59e0b;'>Kernel-Power Events (Unexpected Shutdowns)</div><table><tr><th style='width:25%;'>Date/Time</th><th>Details</th></tr>$kpRows</table>"})
$(if($diskErrRows){"<div class='sub-header'>Disk Errors</div><table><tr><th style='width:20%;'>Date/Time</th><th style='width:15%;'>Event ID</th><th>Message</th></tr>$diskErrRows</table>"})
$(if($wheaRows){"<div class='sub-header' style='color:#dc2626;'>Hardware Errors (WHEA)</div><table><tr><th style='width:25%;'>Date/Time</th><th>Details</th></tr>$wheaRows</table>"})
"@
})

<!-- ══════════════════════════ NETWORK SPEED TEST ══════════════════════════ -->
$(if($SpeedTest -and $SpeedTest.DownloadMbps -ne $null){
@"
<div class='sub-header'><span class='section-icon'>&#127760;</span> Network Speed Test</div>
<div style='display:flex;gap:15px;margin-bottom:14px;flex-wrap:wrap;'>
<div class='score-card'><div style='font-size:16pt;font-weight:bold;color:#2563eb;'>$($SpeedTest.DownloadMbps)</div><div class='score-card-label'>Download Speed</div></div>
<div class='score-card'><div style='font-size:16pt;font-weight:bold;color:#16a34a;'>$($SpeedTest.PingMs)</div><div class='score-card-label'>Ping Latency</div></div>
<div class='score-card'><div style='font-size:16pt;font-weight:bold;'>$($SpeedTest.Jitter)</div><div class='score-card-label'>Jitter</div></div>
<div class='score-card'><div style='font-size:16pt;font-weight:bold;color:$(if($SpeedTest.PacketLoss -eq '0%'){"#16a34a"}else{"#dc2626"})'>$($SpeedTest.PacketLoss)</div><div class='score-card-label'>Packet Loss</div></div>
</div>
<table><tr><th style='width:35%;'>Test</th><th>Result</th></tr>
<tr><td>Gateway</td><td>$($SpeedTest.Gateway) (Ping: $($SpeedTest.GatewayPing))</td></tr>
<tr><td>DNS Response</td><td>$($SpeedTest.DNSResponseMs)</td></tr>
<tr><td>WiFi Signal</td><td>$($SpeedTest.WiFiSignal)</td></tr>
<tr><td>WiFi Channel</td><td>$($SpeedTest.WiFiChannel)</td></tr>
<tr><td>WiFi Radio</td><td>$($SpeedTest.WiFiRadioType)</td></tr>
<tr><td>WiFi Receive Rate</td><td>$(if($SpeedTest.WiFiRxRate){$SpeedTest.WiFiRxRate}else{"N/A"})</td></tr>
<tr><td>WiFi Transmit Rate</td><td>$(if($SpeedTest.WiFiTxRate){$SpeedTest.WiFiTxRate}else{"N/A"})</td></tr>
</table>
"@
})

<!-- ══════════════════════════ DETAILED BATTERY ══════════════════════════ -->
$(if($BatteryDetail -and $BatteryDetail.Present){
$bdColor = if($BatteryDetail.HealthPct -ge 80){"#16a34a"}elseif($BatteryDetail.HealthPct -ge 50){"#f59e0b"}else{"#dc2626"}
$bdOffset = [math]::Round(251 - (251 * $BatteryDetail.HealthPct / 100))
@"
<div class='sub-header'><span class='section-icon'>&#128267;</span> Detailed Battery Report</div>
<div style='display:flex;align-items:center;gap:25px;margin-bottom:14px;'>
<div style='text-align:center;'>
<svg viewBox='0 0 100 100' width='90' height='90'>
<circle cx='50' cy='50' r='40' fill='none' stroke='#e5e7eb' stroke-width='8'/>
<circle cx='50' cy='50' r='40' fill='none' stroke='$bdColor' stroke-width='8' stroke-dasharray='251' stroke-dashoffset='$bdOffset' transform='rotate(-90 50 50)' stroke-linecap='round'/>
<text x='50' y='48' text-anchor='middle' font-size='16' font-weight='bold' fill='$bdColor'>$($BatteryDetail.HealthPct)%</text>
<text x='50' y='64' text-anchor='middle' font-size='9' fill='#64748b'>Health</text>
</svg>
</div>
<div style='flex:1;'>
<table><tr><th style='width:35%;'>Property</th><th>Value</th></tr>
<tr><td>Battery Name</td><td>$($BatteryDetail.Name)</td></tr>
<tr><td>Status</td><td>$($BatteryDetail.Status) $(if($BatteryDetail.Charging){"(Charging)"}else{"(On Battery)"})</td></tr>
<tr><td>Current Charge</td><td><strong>$($BatteryDetail.Charge)%</strong></td></tr>
<tr><td>Health Status</td><td style='color:$bdColor;font-weight:bold;'>$($BatteryDetail.HealthStatus)</td></tr>
<tr><td>Design Capacity</td><td>$($BatteryDetail.DesignCapacity) mWh</td></tr>
<tr><td>Full Charge Capacity</td><td>$($BatteryDetail.FullChargeCapacity) mWh</td></tr>
<tr><td>Battery Health</td><td style='color:$bdColor;font-weight:bold;'>$($BatteryDetail.HealthPct)%</td></tr>
<tr><td>Cycle Count</td><td>$($BatteryDetail.CycleCount)</td></tr>
<tr><td>Drain Rate</td><td>$($BatteryDetail.DrainRate)</td></tr>
<tr><td>Estimated Runtime</td><td>$($BatteryDetail.Runtime)</td></tr>
</table>
</div>
</div>
$(if($BatteryDetail.HealthPct -lt 50){"<div style='padding:10px;background:#fef5f5;border-left:4px solid #dc2626;border-radius:4px;margin-bottom:12px;'><span class='fail'>$iconFail</span> <strong>Battery replacement recommended.</strong> Current capacity is below 50% of original design capacity.</div>"})
$(if($BatteryDetail.BatteryReportPath){"<div style='font-size:8.5pt;color:#64748b;margin-bottom:12px;'>Full Windows battery report saved to: $($BatteryDetail.BatteryReportPath)</div>"})
"@
})

<!-- ══════════════════════════ GAMING READINESS ══════════════════════════ -->
$(if($Gaming -and $Gaming.Score -gt 0){
$gmColor = if($Gaming.Score -ge 80){"#16a34a"}elseif($Gaming.Score -ge 60){"#2563eb"}elseif($Gaming.Score -ge 40){"#f59e0b"}else{"#dc2626"}
$gmOffset = [math]::Round(251 - (251 * $Gaming.Score / 100))
@"
<div class='sub-header'><span class='section-icon'>&#127918;</span> Gaming Readiness Assessment</div>
<div style='display:flex;align-items:center;gap:25px;margin-bottom:14px;'>
<div style='text-align:center;'>
<svg viewBox='0 0 100 100' width='90' height='90'>
<circle cx='50' cy='50' r='40' fill='none' stroke='#e5e7eb' stroke-width='8'/>
<circle cx='50' cy='50' r='40' fill='none' stroke='$gmColor' stroke-width='8' stroke-dasharray='251' stroke-dashoffset='$gmOffset' transform='rotate(-90 50 50)' stroke-linecap='round'/>
<text x='50' y='48' text-anchor='middle' font-size='16' font-weight='bold' fill='$gmColor'>$($Gaming.Score)</text>
<text x='50' y='64' text-anchor='middle' font-size='9' fill='#64748b'>Score</text>
</svg>
</div>
<div style='flex:1;'>
<div style='font-size:14pt;font-weight:bold;color:$gmColor;margin-bottom:8px;'>$($Gaming.Tier)</div>
<table><tr><th style='width:35%;'>Component</th><th>Details</th><th>Score</th></tr>
<tr><td>GPU</td><td>$($Gaming.GPUName) ($($Gaming.VRAM_MB) MB VRAM)</td><td style='color:$gmColor;font-weight:bold;'>$($Gaming.GPUScoreDetail)/40</td></tr>
<tr><td>CPU</td><td>$(if($Gaming.CPUCores){"$($Gaming.CPUCores) cores / $($Gaming.CPUThreads) threads @ $($Gaming.CPUBaseClock) MHz"}else{"N/A"})</td><td style='color:$gmColor;font-weight:bold;'>$($Gaming.CPUScoreDetail)/35</td></tr>
<tr><td>RAM</td><td>$($Gaming.TotalRAM) GB</td><td style='color:$gmColor;font-weight:bold;'>$($Gaming.RAMScoreDetail)/25</td></tr>
</table>
<table style='margin-top:8px;'><tr><th style='width:35%;'>Info</th><th>Value</th></tr>
<tr><td>DirectX</td><td>$($Gaming.DirectXVersion)</td></tr>
<tr><td>Resolution</td><td>$(if($Gaming.Resolution){$Gaming.Resolution}else{"N/A"})</td></tr>
<tr><td>Refresh Rate</td><td>$($Gaming.RefreshRate)</td></tr>
<tr><td>GPU Driver</td><td>$(if($Gaming.DriverVersion){$Gaming.DriverVersion}else{"N/A"})</td></tr>
</table>
</div>
</div>
"@
})

<!-- ══════════════════════════ BOOT PERFORMANCE ══════════════════════════ -->
$(if($BootPerf){
@"
<div class='sub-header'><span class='section-icon'>&#9889;</span> Boot Performance</div>
<div style='display:flex;gap:15px;margin-bottom:14px;flex-wrap:wrap;'>
<div class='score-card'><div style='font-size:16pt;font-weight:bold;color:#2563eb;'>$($BootPerf.BootTimeMs)</div><div class='score-card-label'>Last Boot Time</div></div>
<div class='score-card'><div style='font-size:16pt;font-weight:bold;'>$($BootPerf.ShutdownTimeMs)</div><div class='score-card-label'>Last Shutdown Time</div></div>
<div class='score-card'><div style='font-size:16pt;font-weight:bold;'>$($BootPerf.SlowStartupApps.Count)</div><div class='score-card-label'>Slow Startup Apps</div></div>
</div>
$(if($BootPerf.SlowStartupApps.Count -gt 0){
$slowRows = ($BootPerf.SlowStartupApps | ForEach-Object { "<tr><td>$($_.Name)</td><td>$($_.DelayMs)</td><td>$($_.Date)</td></tr>" }) -join "`n"
"<div class='sub-header'>Slow Startup Applications</div><table><tr><th>Application</th><th>Delay</th><th>Date</th></tr>$slowRows</table>"
})
"@
})

<!-- ══════════════════════════ WINDOWS 11 READINESS ══════════════════════════ -->
$(if($Win11Ready){
$w11Color = if($Win11Ready.Ready){"#16a34a"}else{"#dc2626"}
$w11Rows = ($Win11Ready.Checks | ForEach-Object {
    $cls = if($_.Passed){"pass"}else{"fail"}
    $icon = if($_.Passed){"$iconPass"}else{"$iconFail"}
    "<tr><td>$($_.Name)</td><td class='$cls'>$icon $(if($_.Passed){'PASS'}else{'FAIL'})</td><td>$($_.Value)</td></tr>"
}) -join "`n"
@"
<div class='sub-header'><span class='section-icon'>&#128187;</span> Windows 11 Readiness</div>
<div style='display:flex;align-items:center;gap:20px;margin-bottom:14px;'>
<div style='text-align:center;padding:15px 25px;background:$(if($Win11Ready.Ready){"#eafaf1"}else{"#fef5f5"});border:2px solid $w11Color;border-radius:12px;'>
<div style='font-size:18pt;font-weight:bold;color:$w11Color;'>$(if($Win11Ready.Ready){"READY"}else{"NOT READY"})</div>
<div style='font-size:9pt;color:#64748b;'>Windows 11 Compatibility</div>
</div>
<div style='font-size:16pt;font-weight:bold;color:$w11Color;'>$($Win11Ready.Score) / $($Win11Ready.MaxScore)</div>
</div>
<table><tr><th>Requirement</th><th>Status</th><th>Details</th></tr>$w11Rows</table>
<div style='font-size:8.5pt;color:#64748b;margin-top:8px;'>$($Win11Ready.Verdict)</div>
"@
})

<!-- ══════════════════════════ POWER STABILITY ══════════════════════════ -->
$(if($PowerInfo){
$pwColor = if($PowerInfo.StabilityScore -ge 80){"#16a34a"}elseif($PowerInfo.StabilityScore -ge 60){"#f59e0b"}else{"#dc2626"}
@"
<div class='sub-header'><span class='section-icon'>&#9889;</span> Power Stability</div>
<div style='display:flex;gap:15px;margin-bottom:14px;flex-wrap:wrap;'>
<div class='score-card'><div style='font-size:16pt;font-weight:bold;color:$pwColor;'>$($PowerInfo.Rating)</div><div class='score-card-label'>Power Stability</div></div>
<div class='score-card'><div style='font-size:16pt;font-weight:bold;'>$($PowerInfo.ACAdapter)</div><div class='score-card-label'>Power Source</div></div>
<div class='score-card'><div style='font-size:16pt;font-weight:bold;color:$(if($PowerInfo.UnexpectedShutdowns -eq 0){"#16a34a"}else{"#dc2626"})'>$($PowerInfo.UnexpectedShutdowns)</div><div class='score-card-label'>Unexpected Shutdowns</div></div>
</div>
<div style='font-size:8.5pt;color:#64748b;margin-bottom:8px;'>$($PowerInfo.LastBootType)</div>
$(if($PowerInfo.PowerEvents.Count -gt 0){
$pwEvtRows = ($PowerInfo.PowerEvents | Select-Object -First 10 | ForEach-Object { "<tr><td>$($_.Time)</td><td>$($_.Type)</td></tr>" }) -join "`n"
"<div class='sub-header'>Recent Power Events</div><table><tr><th style='width:25%;'>Date/Time</th><th>Event</th></tr>$pwEvtRows</table>"
})
"@
})

<!-- ══════════════════════════ HISTORICAL COMPARISON ══════════════════════════ -->
$(if($HistoryComparison -and $HistoryComparison.HasPrevious){
$trendRows = ($HistoryComparison.Trends | ForEach-Object {
    $dirIcon = if($_.Direction -eq 'Improved'){"<span class='pass'>&#8593;</span>"}elseif($_.Direction -eq 'Declined'){"<span class='fail'>&#8595;</span>"}else{"<span>&#8596;</span>"}
    "<tr><td>$($_.Category)</td><td>$($_.Previous)</td><td>$($_.Current)</td><td>$dirIcon $(if($_.Direction){$_.Direction}else{'--'})</td></tr>"
}) -join "`n"
@"
<div class='page-break'></div>
<div class='section-header'><span class='section-icon'>&#128202;</span> Historical Comparison</div>
<div style='padding:12px;background:#eff6ff;border-left:4px solid #2563eb;border-radius:4px;margin-bottom:14px;'>
<strong>Previous Scan:</strong> $($HistoryComparison.PreviousDate) | <strong>Score Change:</strong> <span style='color:$(if($HistoryComparison.ScoreDelta -ge 0){"#16a34a"}else{"#dc2626"});font-weight:bold;'>$(if($HistoryComparison.ScoreDelta -ge 0){"+$($HistoryComparison.ScoreDelta)"}else{$HistoryComparison.ScoreDelta})</span> points
</div>
$(if($trendRows){"<table><tr><th>Category</th><th>Previous</th><th>Current</th><th>Trend</th></tr>$trendRows</table>"})
"@
})

<!-- ══════════════════════════ SYSTEM INFORMATION ══════════════════════════ -->
<div class="page-break"></div>

<div class="section-header"><span class="section-icon">&#128187;</span> System Information</div>
<table><tr><th style="width:35%;">Property</th><th>Value</th></tr>
<tr><td>Computer Name</td><td><strong>$($SystemInfo.ComputerName)</strong></td></tr>
<tr><td>Manufacturer / Model</td><td>$($SystemInfo.Manufacturer) $($SystemInfo.Model)</td></tr>
<tr><td>Serial Number</td><td style="font-family:Consolas,monospace;letter-spacing:0.5px;">$($SystemInfo.Serial)</td></tr>
<tr><td>Operating System</td><td>$($SystemInfo.OSVersion) (Build $($SystemInfo.OSBuild))</td></tr>
<tr><td>Architecture</td><td>$($SystemInfo.Architecture)</td></tr>
<tr><td>CPU</td><td>$($SystemInfo.CPUModel)</td></tr>
<tr><td>Cores / Threads</td><td>$($SystemInfo.CPUCores) / $($SystemInfo.CPUThreads)</td></tr>
<tr><td>RAM</td><td>$($SystemInfo.RAMTotal) GB total / $($SystemInfo.RAMFree) GB free</td></tr>
<tr><td>Uptime</td><td>$($SystemInfo.Uptime)</td></tr>
<tr><td>Domain / Workgroup</td><td>$($SystemInfo.Domain)</td></tr>
</table>

<div class="sub-header">Motherboard &amp; BIOS</div>
<table><tr><th style="width:35%;">Property</th><th>Value</th></tr>
<tr><td>Motherboard</td><td>$($SystemInfo.Board.Manufacturer) $($SystemInfo.Board.Product)</td></tr>
<tr><td>Board Serial</td><td style="font-family:Consolas,monospace;">$($SystemInfo.Board.Serial)</td></tr>
<tr><td>BIOS Vendor</td><td>$($SystemInfo.BIOS.Vendor)</td></tr>
<tr><td>BIOS Version</td><td>$($SystemInfo.BIOS.Version)</td></tr>
<tr><td>BIOS Date</td><td>$($SystemInfo.BIOS.Date)</td></tr>
</table>

<div class="sub-header">Memory (RAM) &mdash; $($SystemInfo.RAMSlots.Used) of $($SystemInfo.RAMSlots.Total) slots used$(if($SystemInfo.RAMSlots.Empty -gt 0){" ($($SystemInfo.RAMSlots.Empty) available)"})</div>
<div style="display:flex;align-items:center;gap:10px;margin-bottom:10px;">
<div class="progress-track progress-lg" style="flex:1;height:14px;"><div class="progress-fill" style="width:$ramSlotPct%;background:#2596be;height:14px;"></div></div>
<span style="font-size:9pt;color:#0d4b71;font-weight:600;">$($SystemInfo.RAMSlots.Used) / $($SystemInfo.RAMSlots.Total)</span>
</div>
<table><tr><th>Slot</th><th>Size</th><th>Speed</th><th>Type</th><th>Manufacturer</th><th>Part Number</th></tr>$ramRows</table>

<div class="sub-header">Graphics</div>
<table><tr><th>GPU</th><th>VRAM</th><th>Driver</th><th>Driver Date</th><th>Resolution</th></tr>$gpuRows</table>

$(if($monitorRows){"<div class='sub-header'>Monitors</div><table><tr><th>Model</th><th>Manufacturer</th><th>Serial</th><th>Year</th></tr>$monitorRows</table>"})


<!-- ══════════════════════════ STORAGE HEALTH ══════════════════════════ -->
<div class="page-break"></div>

<div class="section-header"><span class="section-icon">&#128190;</span> Storage Health</div>

<div class="sub-header">S.M.A.R.T. Status</div>
<table><tr><th>Model</th><th>Type</th><th>Bus</th><th>Size</th><th>Health</th><th>Power-On Hrs</th><th>Temp</th><th>Read Errors</th><th>Wear</th></tr>$smartRows</table>

<div class="sub-header">Drive Space Usage</div>
<table><tr><th>Drive</th><th>Capacity</th><th>Free</th><th>Used</th></tr>$diskRowsDetailed</table>

$(if($tempRows){"
<div class='sub-header'>Temperature Readings</div>
<table><tr><th>Sensor</th><th>Celsius</th><th>Fahrenheit</th><th>Level</th></tr>$tempRows</table>
"})

$batteryHTML


<!-- ══════════════════════════ DEVICE MANAGER ══════════════════════════ -->
<div class="page-break"></div>

<div class="section-header"><span class="section-icon">&#128268;</span> Device Manager</div>
$devErrHTML

$(if($printerRows){"<div class='sub-header'>Printers</div><table><tr><th>Name</th><th>Port</th><th>Driver</th><th>Default</th></tr>$printerRows</table>"})

<!-- ══════════════════════════ NETWORK ══════════════════════════ -->
<div class="section-header"><span class="section-icon">&#127760;</span> Network</div>
<table><tr><th>Adapter</th><th>IP Address</th><th>MAC Address</th><th>DNS</th><th>Speed</th></tr>$netRows</table>
<table><tr><th style="width:30%;">Property</th><th>Value</th></tr>
<tr><td>WiFi SSID</td><td>$($Network.WiFi.SSID)</td></tr>
<tr><td>Public IP</td><td>$($Network.PublicIP)</td></tr>
<tr><td>DNS Response</td><td>$(if($Network.DNSTest.Success){"$($Network.DNSTest.ResponseMs) ms"}else{"<span class='fail'>Failed</span>"})</td></tr>
<tr><td>Internet Connectivity</td><td>$(if($Network.InternetTest.Success){"<span class='pass'>Connected ($($Network.InternetTest.ResponseMs) ms)</span>"}else{"<span class='fail'>No Connection</span>"})</td></tr>
</table>
$(if($Network.OpenPorts.Count -gt 0){"<div class='sub-header'>Listening Ports</div><table><tr><th>Port</th><th>Address</th><th>Process</th></tr>$(($Network.OpenPorts | ForEach-Object {"<tr><td>$($_.Port)</td><td>$($_.Address)</td><td>$($_.Process)</td></tr>"}) -join "`n")</table>"})


<!-- ══════════════════════════ PERFORMANCE ══════════════════════════ -->
<div class="page-break"></div>

<div class="section-header"><span class="section-icon">&#9889;</span> Performance</div>

<div class="summary-strip">
<div class="summary-chip"><span class="chip-val">$($Performance.CPUPercent)%</span><span class="chip-lbl">CPU Usage</span></div>
<div class="summary-chip"><span class="chip-val">$($Performance.RAMPercent)%</span><span class="chip-lbl">RAM Usage</span></div>
<div class="summary-chip"><span class="chip-val">$($Software.ProcessCount)</span><span class="chip-lbl">Processes</span></div>
<div class="summary-chip"><span class="chip-val">$($Software.RunningServices)</span><span class="chip-lbl">Services</span></div>
</div>

<div style="margin:12px 0;">
<div style="display:flex;align-items:center;gap:10px;margin-bottom:8px;">
<span style="min-width:90px;font-size:9pt;font-weight:600;color:#334155;">CPU Usage</span>
<div class="progress-track progress-lg" style="flex:1;"><div class="progress-fill" style="width:$($Performance.CPUPercent)%;background:$cpuBarColor;"></div></div>
<span style="min-width:40px;font-size:9pt;font-weight:600;color:$cpuBarColor;">$($Performance.CPUPercent)%</span>
</div>
<div style="display:flex;align-items:center;gap:10px;margin-bottom:8px;">
<span style="min-width:90px;font-size:9pt;font-weight:600;color:#334155;">RAM Usage</span>
<div class="progress-track progress-lg" style="flex:1;"><div class="progress-fill" style="width:$($Performance.RAMPercent)%;background:$ramBarColor;"></div></div>
<span style="min-width:40px;font-size:9pt;font-weight:600;color:$ramBarColor;">$($Performance.RAMPercent)%</span>
</div>
</div>

<div class="sub-header">Top Memory Consumers</div>
<table><tr><th>Process</th><th>RAM Usage</th></tr>$topProcRows</table>


<!-- ══════════════════════════ STRESS TEST RESULTS ══════════════════════════ -->
$(if($stressHTML){"
<div class='page-break'></div>
<div class='section-header'><span class='section-icon'>&#128293;</span> Stress Test Results</div>
<table><tr><th>Test</th><th>Result</th><th>Details</th><th>Temps / Info</th></tr>$stressHTML</table>
"})

<!-- ══════════════════════════ LICENSE KEYS & CREDENTIALS ══════════════════════════ -->
<div class="page-break"></div>

<div class="section-header"><span class="section-icon">&#128272;</span> License Keys &amp; Credentials</div>
<div class="confidential-banner">
<span class="lock-icon">&#128274;</span>
<span><strong>CONFIDENTIAL</strong> &mdash; This section contains sensitive information. Store securely and do not share publicly.</span>
</div>

<div class="sub-header">Windows Product Key</div>
<table><tr><th>Source</th><th>Key</th></tr>$winKeyRows</table>

<div class="sub-header">Microsoft Office</div>
<table><tr><th>Product</th><th>Key</th></tr>$officeKeyRows</table>

$(if($adobeKeyRows){"<div class='sub-header'>Adobe Products</div><table><tr><th>Product</th><th>Key</th></tr>$adobeKeyRows</table>"})

<div class="sub-header">Saved WiFi Networks</div>
<table><tr><th>Network (SSID)</th><th>Password</th><th>Security</th></tr>$wifiRows</table>


<!-- ══════════════════════════ TECHNICIAN NOTES ══════════════════════════ -->
$techNotes

<!-- ══════════════════════════ INSTALLED SOFTWARE ══════════════════════════ -->
<div class="page-break"></div>

<div class="section-header"><span class="section-icon">&#128230;</span> Installed Software ($($Software.Installed.Count))</div>
<table><tr><th>Name</th><th>Version</th><th>Publisher</th></tr>$swRows</table>

<div class="sub-header">Startup Programs ($($Software.StartupPrograms.Count))</div>
<table><tr><th>Name</th><th>Location</th></tr>$(($Software.StartupPrograms | ForEach-Object {"<tr><td>$($_.Name)</td><td style='font-size:8pt;word-break:break-all;'>$($_.Location)</td></tr>"}) -join "`n")</table>

$(if($bannerSecBottomUri){"<div class='page-break'></div><div class='promo-banner' style='padding-top:30px;'><img src='$bannerSecBottomUri' alt='175-Point Security Inspection'/></div>"})

<!-- ══════════════════════════ BACK PAGE ══════════════════════════ -->
<div class="page-break"></div>

<div style="text-align:center;padding-top:60px;">
$(if($logoDataUri){"<img src='$logoDataUri' alt='PC Plus Computing' style='width:250px;margin-bottom:30px;'/>"}else{"<div style='background:#0a1628;color:#fff;padding:16px 40px;font-size:18pt;font-weight:bold;letter-spacing:3px;border-radius:6px;margin-bottom:30px;display:inline-block;'>PC PLUS COMPUTING</div>"})
<div style="font-size:12pt;color:#0d4b71;font-weight:600;margin-bottom:6px;">Thank you for choosing PC Plus Computing</div>
<div style="font-size:10pt;color:#64748b;margin-bottom:30px;">Your Security, Our Priority &nbsp;|&nbsp; 30+ Years in Service &nbsp;|&nbsp; 4.9&#9733; Google Rating</div>

<div class="qr-row">
<div class="qr-item">
$(if($qrAppointmentUri){"<img src='$qrAppointmentUri' alt='Book Appointment'/>"}else{"<div class='qr-fallback'>Book<br/>Appointment</div>"})
<div class="qr-label">Book an Appointment</div>
<div class="qr-sublabel">pcpluscomputing.com/appointments</div>
</div>
<div class="qr-item">
$(if($qrServiceUri){"<img src='$qrServiceUri' alt='Send Info'/>"}else{"<div class='qr-fallback'>Send Us<br/>Info</div>"})
<div class="qr-label">Send Us Your Info</div>
<div class="qr-sublabel">Service Request Portal</div>
</div>
</div>

<div style="margin-top:40px;padding:20px;background:#f8fafc;border-radius:10px;border:1px solid #e2e8f0;display:inline-block;">
<div style="font-size:11pt;font-weight:700;color:#0a1628;margin-bottom:8px;">Get In Touch</div>
<div style="font-size:10pt;color:#475569;">
&#127760; $WEBSITE &nbsp;&nbsp;|&nbsp;&nbsp; &#128222; $PHONE
</div>
</div>

<div style="margin-top:40px;font-size:8pt;color:#94a3b8;">
Hardware Diagnostic Report generated $date<br/>
Technician: $($Params.TechName) &nbsp;|&nbsp; Device: $($SystemInfo.ComputerName)
</div>
</div>

</body></html>
"@
    return $html
}

function Build-SecurityReport {
    param($Params, $SystemInfo, $Security, $MissingPatches, $Scoring)
    $date = Get-Date -Format "MMMM dd, yyyy 'at' h:mm tt"
    $iconPass = "&#10004;"; $iconFail = "&#10008;"; $iconWarn = "&#9888;"
    $passCount = ($Scoring.Breakdown | Where-Object { $_.Passed }).Count
    $failCount = ($Scoring.Breakdown | Where-Object { -not $_.Passed }).Count
    $dashOffset = 283 - (283 * $Scoring.Score / 100)

    # Load logo as base64 data URI
    $logoDataUri = ""
    $logoPath = Join-Path $Global:ScriptDir "logo-base64.txt"
    if (Test-Path $logoPath) {
        try {
            $logoB64 = (Get-Content $logoPath -Raw).Trim()
            $logoDataUri = "data:image/png;base64,$logoB64"
        } catch { $logoDataUri = "" }
    }
    $logoHTML = if ($logoDataUri) {
        "<img src='$logoDataUri' alt='PC Plus Computing' style='width:350px;max-width:90%;margin-bottom:30px;'/>"
    } else {
        "<div style='background:#0a1628;color:#fff;padding:20px 50px;font-size:22pt;font-weight:bold;letter-spacing:3px;border-radius:6px;margin-bottom:30px;'>PC PLUS COMPUTING</div>"
    }

    # Load QR codes as base64 data URIs
    $qrAppointmentUri = ""; $qrServiceUri = ""
    $qrAppPath = Join-Path $Global:ScriptDir "qr-appointments.txt"
    $qrSvcPath = Join-Path $Global:ScriptDir "qr-service-requests.txt"
    if (Test-Path $qrAppPath) { try { $qrAppointmentUri = "data:image/png;base64,$((Get-Content $qrAppPath -Raw).Trim())" } catch {} }
    if (Test-Path $qrSvcPath) { try { $qrServiceUri = "data:image/png;base64,$((Get-Content $qrSvcPath -Raw).Trim())" } catch {} }

    # Load cross-promotion banners
    $bannerHwTopUri = ""; $bannerHwBottomUri = ""
    $bhtPath = Join-Path $Global:ScriptDir "banner-hardware-top.txt"
    $bhbPath = Join-Path $Global:ScriptDir "banner-hardware-bottom.txt"
    if (Test-Path $bhtPath) { try { $bannerHwTopUri = "data:image/jpeg;base64,$((Get-Content $bhtPath -Raw).Trim())" } catch {} }
    if (Test-Path $bhbPath) { try { $bannerHwBottomUri = "data:image/jpeg;base64,$((Get-Content $bhbPath -Raw).Trim())" } catch {} }

    # Load security report's own banner
    $bannerSecOwnUri = ""
    $bsoPath = Join-Path $Global:ScriptDir "banner-security-top.txt"
    if (Test-Path $bsoPath) { try { $bannerSecOwnUri = "data:image/jpeg;base64,$((Get-Content $bsoPath -Raw).Trim())" } catch {} }

    # Breakdown rows
    $breakdownRows = ($Scoring.Breakdown | ForEach-Object {
        $ic = if($_.Passed){"<span class='pass'>$iconPass</span>"}else{"<span class='fail'>$iconFail</span>"}
        $statusBadge = if($_.Passed){"<span class='status-badge status-pass'>PASS</span>"}else{"<span class='status-badge status-fail'>FAIL</span>"}
        "<tr><td style='width:30px;text-align:center;'>$ic</td><td>$($_.Check)</td><td>$statusBadge</td><td style='text-align:center;font-weight:600;'>$($_.Points) pts</td></tr>"
    }) -join "`n"
    # Recommendations
    $recs = @()
    foreach ($item in $Scoring.Breakdown) {
        if (-not $item.Passed) {
            $rec = switch ($item.Check) {
                "Antivirus Active" { "Install and activate antivirus immediately." }
                "Firewall All Profiles" { "Enable Windows Firewall on all profiles." }
                "BitLocker on C:" { "Enable BitLocker drive encryption." }
                "No Critical Patches Missing" { "Install all pending critical updates." }
                "UAC Enabled" { "Re-enable User Account Control." }
                "Secure Boot" { "Enable Secure Boot in BIOS/UEFI." }
                "TPM Present" { "Hardware upgrade needed for TPM 2.0." }
                "Password Policy" { "Set minimum 8 character password with complexity." }
                "Guest Disabled" { "Disable the Guest account." }
                "No Auto-Login" { "Disable automatic login." }
                "RDP Secure" { "Disable RDP or enable NLA." }
                "SMBv1 Disabled" { "Disable SMBv1 (ransomware vulnerability)." }
                "Admin Accounts <=2" { "Reduce admin accounts, use standard for daily use." }
                "Real-Time Protection" { "Enable Windows Defender real-time protection." }
                "AV Definitions Current" { "Update antivirus definitions." }
                "Telemetry Minimal" { "Set Windows telemetry to Security/Basic level in Settings > Privacy." }
                "Advertising ID Disabled" { "Disable advertising ID in Settings > Privacy > General." }
                "Location Tracking Off" { "Disable location tracking in Settings > Privacy > Location." }
                "Activity History Off" { "Disable activity history in Settings > Privacy > Activity History." }
                "Cortana/Copilot Disabled" { "Disable Cortana/Copilot data collection via Group Policy or Settings." }
                "Find My Device On" { "Enable Find My Device in Settings > Update & Security > Find My Device." }
                "Chrome No Saved Passwords" { "Remove saved passwords from Chrome, use a dedicated password manager." }
                "Edge No Saved Passwords" { "Remove saved passwords from Edge, use a dedicated password manager." }
                "SmartScreen Enabled" { "Enable SmartScreen in Windows Security > App & Browser Control." }
                "Browser Extensions <15" { "Remove unnecessary browser extensions to reduce attack surface." }
                "No Open Shares" { "Remove unnecessary network shares or restrict permissions." }
                "UPnP Disabled" { "Disable UPnP (SSDP Discovery service) to prevent port-mapping exploits." }
                "LLMNR Disabled" { "Disable LLMNR via Group Policy to prevent name resolution poisoning." }
                "DNS-over-HTTPS" { "Enable DNS-over-HTTPS in Settings > Network > DNS for encrypted lookups." }
                "Remote Assistance Off" { "Disable Remote Assistance in System Properties > Remote." }
                "Driver Sig Enforced" { "Disable test signing mode: bcdedit /set testsigning off" }
                "PS Script Logging" { "Enable PowerShell script block logging via Group Policy." }
                "Logon Audit Enabled" { "Enable logon auditing: auditpol /set /subcategory:Logon /success:enable" }
                "Credential Guard" { "Enable Credential Guard via Group Policy (requires UEFI + Secure Boot)." }
                "LSASS Protected" { "Enable LSASS protection: set RunAsPPL=1 in registry." }
                "No Stale Accounts" { "Remove or disable local accounts not used in 90+ days." }
                "No Empty Passwords" { "Set passwords on all local accounts or disable them." }
                "Password Age Policy" { "Set a maximum password age policy (e.g. 90 days)." }
                "Controlled Folder Access" { "Enable Controlled Folder Access in Windows Security > Ransomware Protection." }
                "Recent Restore Point" { "Create a System Restore point and enable automatic restore points." }
                "No Suspicious Tasks" { "Review scheduled tasks running from temp/AppData directories." }
                default { "Review and fix this configuration." }
            }
            $sev = if($item.Points -ge 7){"Critical"}elseif($item.Points -ge 3){"Warning"}else{"Advisory"}
            $recs += @{ Check = $item.Check; Rec = $rec; Severity = $sev }
        }
    }
    $recsHTML = ($recs | ForEach-Object {
        $borderColor = switch($_.Severity){"Critical"{"#dc2626"}"Warning"{"#f59e0b"}default{"#2596be"}}
        $bgColor = switch($_.Severity){"Critical"{"#fef5f5"}"Warning"{"#fffbeb"}default{"#f0f7fb"}}
        $sevColor = switch($_.Severity){"Critical"{"#dc2626"}"Warning"{"#92400e"}default{"#0d4b71"}}
        "<div class='rec-card' style='border-left:4px solid $borderColor;background:$bgColor;'><div class='rec-severity' style='color:$sevColor;'>$($_.Severity)</div><div class='rec-check'>$($_.Check)</div><div class='rec-action'>$($_.Rec)</div></div>"
    }) -join "`n"
    # Security details - card-style panels
    $secDetails = @()
    # Defender
    $defSt = if($Security.Defender.RealTimeProtection -eq $true){"<span class='status-badge status-pass'>$iconPass Active</span>"}elseif($Security.Defender.RealTimeProtection -eq $false){"<span class='status-badge status-fail'>$iconFail Disabled</span>"}else{"<span class='status-badge status-warn'>$iconWarn Unknown</span>"}
    $secDetails += @{ Name="Windows Defender"; Status=$defSt }
    if($Security.Defender.DefinitionAge -ne $null){$da=if($Security.Defender.DefinitionsUpToDate){"status-pass"}else{"status-fail"};$secDetails+=@{Name="AV Definitions";Status="<span class='status-badge $da'>$($Security.Defender.DefinitionAge) days old</span>"}}
    if($Security.ThirdPartyAV.Count -gt 0){$secDetails+=@{Name="Third-Party AV";Status="<span class='status-badge status-pass'>$($Security.ThirdPartyAV -join ', ')</span>"}}
    foreach($p in @("Domain","Private","Public")){$v=$Security.Firewall.$p;$s=if($v -eq $true){"<span class='status-badge status-pass'>$iconPass Enabled</span>"}elseif($v -eq $false){"<span class='status-badge status-fail'>$iconFail Disabled</span>"}else{"<span class='status-badge status-warn'>$iconWarn Unknown</span>"};$secDetails+=@{Name="Firewall - $p";Status=$s}}
    $uacSt = if($Security.UAC.Enabled){"<span class='status-badge status-pass'>$iconPass Enabled</span>"}else{"<span class='status-badge status-fail'>$iconFail Disabled</span>"}
    $secDetails += @{ Name="UAC"; Status=$uacSt }
    if($Security.BitLocker.Count -gt 0){foreach($d in $Security.BitLocker.Keys){$bi=$Security.BitLocker[$d];$bs=if($bi.Status -eq "On"){"<span class='status-badge status-pass'>$iconPass Encrypted</span>"}else{"<span class='status-badge status-fail'>$iconFail Not Encrypted</span>"};$secDetails+=@{Name="BitLocker $d";Status=$bs}}}else{$secDetails+=@{Name="BitLocker";Status="<span class='status-badge status-fail'>$iconFail Not Detected</span>"}}
    $sbSt = if($Security.SecureBoot -eq $true){"<span class='status-badge status-pass'>$iconPass Enabled</span>"}elseif($Security.SecureBoot -eq $false){"<span class='status-badge status-fail'>$iconFail Disabled</span>"}else{"<span class='status-badge status-warn'>$iconWarn Unknown</span>"}
    $secDetails += @{ Name="Secure Boot"; Status=$sbSt }
    $tpmSt = if($Security.TPM.Present){"<span class='status-badge status-pass'>$iconPass Present (v$($Security.TPM.Version))</span>"}else{"<span class='status-badge status-fail'>$iconFail Not Present</span>"}
    $secDetails += @{ Name="TPM"; Status=$tpmSt }
    $secDetails += @{ Name="Password Policy"; Status="Min Length: $($Security.PasswordPolicy.MinLength), Complexity: $(if($Security.PasswordPolicy.Complexity){'Yes'}else{'No'}), Lockout: $(if($Security.PasswordPolicy.LockoutThreshold -gt 0){$Security.PasswordPolicy.LockoutThreshold}else{'None'})" }
    $gSt = if($Security.GuestDisabled -eq $true){"<span class='status-badge status-pass'>$iconPass Disabled</span>"}else{"<span class='status-badge status-fail'>$iconFail Enabled</span>"}
    $secDetails += @{ Name="Guest Account"; Status=$gSt }
    $alSt = if($Security.AutoLoginDisabled -eq $true){"<span class='status-badge status-pass'>$iconPass Off</span>"}else{"<span class='status-badge status-fail'>$iconFail On</span>"}
    $secDetails += @{ Name="Auto-Login"; Status=$alSt }
    $rdpSt = if($Security.RDP.Enabled -eq $false){"<span class='status-badge status-pass'>$iconPass Disabled</span>"}elseif($Security.RDP.NLA){"<span class='status-badge status-warn'>$iconWarn Enabled (NLA)</span>"}else{"<span class='status-badge status-fail'>$iconFail Enabled (No NLA)</span>"}
    $secDetails += @{ Name="Remote Desktop"; Status=$rdpSt }
    $smbSt = if($Security.SMBv1Disabled -eq $true){"<span class='status-badge status-pass'>$iconPass Disabled</span>"}else{"<span class='status-badge status-fail'>$iconFail Enabled</span>"}
    $secDetails += @{ Name="SMBv1"; Status=$smbSt }
    $secDetails += @{ Name="Local Admins"; Status="$($Security.LocalAdmins.Count): $($Security.LocalAdmins.Names)" }

    # Privacy & Data Protection
    $privacyDetails = @()
    if ($Security.Privacy) {
        $privacyDetails += @{ Name="Telemetry Level"; Status=if($Security.Privacy.TelemetryMinimal){"<span class='status-badge status-pass'>$iconPass Minimal</span>"}else{"<span class='status-badge status-fail'>$iconFail Not Restricted</span>"} }
        $privacyDetails += @{ Name="Advertising ID"; Status=if($Security.Privacy.AdvertisingIdDisabled){"<span class='status-badge status-pass'>$iconPass Disabled</span>"}else{"<span class='status-badge status-fail'>$iconFail Active</span>"} }
        $privacyDetails += @{ Name="Location Tracking"; Status=if($Security.Privacy.LocationDisabled){"<span class='status-badge status-pass'>$iconPass Off</span>"}else{"<span class='status-badge status-fail'>$iconFail Active</span>"} }
        $privacyDetails += @{ Name="Activity History"; Status=if($Security.Privacy.ActivityHistoryDisabled){"<span class='status-badge status-pass'>$iconPass Disabled</span>"}else{"<span class='status-badge status-fail'>$iconFail Active</span>"} }
        $privacyDetails += @{ Name="Cortana/Copilot"; Status=if($Security.Privacy.CortanaDisabled){"<span class='status-badge status-pass'>$iconPass Disabled</span>"}else{"<span class='status-badge status-warn'>$iconWarn Active</span>"} }
        $privacyDetails += @{ Name="Find My Device"; Status=if($Security.Privacy.FindMyDeviceEnabled){"<span class='status-badge status-pass'>$iconPass Enabled</span>"}else{"<span class='status-badge status-fail'>$iconFail Off</span>"} }
    }

    # Browser Security
    $browserDetails = @()
    if ($Security.BrowserSecurity) {
        $browserDetails += @{ Name="Chrome Passwords"; Status=if($Security.BrowserSecurity.ChromeNoSavedPasswords){"<span class='status-badge status-pass'>$iconPass None Saved</span>"}else{"<span class='status-badge status-warn'>$iconWarn Passwords Stored</span>"} }
        $browserDetails += @{ Name="Edge Passwords"; Status=if($Security.BrowserSecurity.EdgeNoSavedPasswords){"<span class='status-badge status-pass'>$iconPass None Saved</span>"}else{"<span class='status-badge status-warn'>$iconWarn Passwords Stored</span>"} }
        $browserDetails += @{ Name="SmartScreen"; Status=if($Security.BrowserSecurity.SmartScreenEnabled){"<span class='status-badge status-pass'>$iconPass Enabled</span>"}else{"<span class='status-badge status-fail'>$iconFail Disabled</span>"} }
        $browserDetails += @{ Name="Extensions"; Status=if($Security.BrowserSecurity.ExtensionCountOk){"<span class='status-badge status-pass'>$iconPass Reasonable</span>"}else{"<span class='status-badge status-warn'>$iconWarn 15+ Installed</span>"} }
    }

    # Network Hardening
    $networkDetails = @()
    if ($Security.NetworkHardening) {
        $networkDetails += @{ Name="Open Shares"; Status=if($Security.NetworkHardening.NoOpenShares){"<span class='status-badge status-pass'>$iconPass None</span>"}else{"<span class='status-badge status-warn'>$iconWarn Shares Found</span>"} }
        $networkDetails += @{ Name="UPnP (SSDP)"; Status=if($Security.NetworkHardening.UPnPDisabled){"<span class='status-badge status-pass'>$iconPass Disabled</span>"}else{"<span class='status-badge status-fail'>$iconFail Running</span>"} }
        $networkDetails += @{ Name="LLMNR"; Status=if($Security.NetworkHardening.LLMNRDisabled){"<span class='status-badge status-pass'>$iconPass Disabled</span>"}else{"<span class='status-badge status-warn'>$iconWarn Active</span>"} }
        $networkDetails += @{ Name="DNS-over-HTTPS"; Status=if($Security.NetworkHardening.DoHEnabled){"<span class='status-badge status-pass'>$iconPass Enabled</span>"}else{"<span class='status-badge status-warn'>$iconWarn Off</span>"} }
        $networkDetails += @{ Name="Remote Assistance"; Status=if($Security.NetworkHardening.RemoteAssistanceDisabled){"<span class='status-badge status-pass'>$iconPass Disabled</span>"}else{"<span class='status-badge status-warn'>$iconWarn Enabled</span>"} }
    }

    # System Integrity
    $integrityDetails = @()
    if ($Security.SystemIntegrity) {
        $integrityDetails += @{ Name="Driver Signing"; Status=if($Security.SystemIntegrity.DriverSigEnforced){"<span class='status-badge status-pass'>$iconPass Enforced</span>"}else{"<span class='status-badge status-fail'>$iconFail Test Mode</span>"} }
        $integrityDetails += @{ Name="PS Script Logging"; Status=if($Security.SystemIntegrity.PSScriptLogging){"<span class='status-badge status-pass'>$iconPass On</span>"}else{"<span class='status-badge status-warn'>$iconWarn Off</span>"} }
        $integrityDetails += @{ Name="Logon Auditing"; Status=if($Security.SystemIntegrity.LogonAuditEnabled){"<span class='status-badge status-pass'>$iconPass Enabled</span>"}else{"<span class='status-badge status-warn'>$iconWarn Off</span>"} }
        $integrityDetails += @{ Name="Credential Guard"; Status=if($Security.SystemIntegrity.CredentialGuard){"<span class='status-badge status-pass'>$iconPass Running</span>"}else{"<span class='status-badge status-warn'>$iconWarn Off</span>"} }
        $integrityDetails += @{ Name="LSASS Protection"; Status=if($Security.SystemIntegrity.LSASSProtected){"<span class='status-badge status-pass'>$iconPass PPL</span>"}else{"<span class='status-badge status-warn'>$iconWarn Unprotected</span>"} }
    }

    # Account Hygiene
    $accountDetails = @()
    if ($Security.AccountHygiene) {
        $accountDetails += @{ Name="Stale Accounts"; Status=if($Security.AccountHygiene.NoStaleAccounts){"<span class='status-badge status-pass'>$iconPass None</span>"}else{"<span class='status-badge status-warn'>$iconWarn Found</span>"} }
        $accountDetails += @{ Name="Empty Passwords"; Status=if($Security.AccountHygiene.NoEmptyPasswords){"<span class='status-badge status-pass'>$iconPass None</span>"}else{"<span class='status-badge status-fail'>$iconFail Found</span>"} }
        $accountDetails += @{ Name="Password Expiry"; Status=if($Security.AccountHygiene.PasswordAgePolicy){"<span class='status-badge status-pass'>$iconPass Set</span>"}else{"<span class='status-badge status-warn'>$iconWarn Unlimited</span>"} }
    }

    # Ransomware Protection
    $ransomDetails = @()
    if ($Security.RansomwareProtection) {
        $ransomDetails += @{ Name="Controlled Folders"; Status=if($Security.RansomwareProtection.ControlledFolderAccess){"<span class='status-badge status-pass'>$iconPass On</span>"}else{"<span class='status-badge status-fail'>$iconFail Off</span>"} }
        $ransomDetails += @{ Name="Restore Points"; Status=if($Security.RansomwareProtection.RecentRestorePoint){"<span class='status-badge status-pass'>$iconPass Recent</span>"}else{"<span class='status-badge status-fail'>$iconFail None Recent</span>"} }
        $ransomDetails += @{ Name="Suspicious Tasks"; Status=if($Security.RansomwareProtection.NoSuspiciousScheduledTasks){"<span class='status-badge status-pass'>$iconPass Clean</span>"}else{"<span class='status-badge status-fail'>$iconFail Found</span>"} }
    }

    # Build all detail sections
    $buildDetailCards = { param($items) ($items | ForEach-Object { "<div class='sec-detail-row'><div class='sec-detail-label'>$($_.Name)</div><div class='sec-detail-value'>$($_.Status)</div></div>" }) -join "`n" }
    $secDetailCards = & $buildDetailCards $secDetails
    $privacyDetailCards = if($privacyDetails.Count -gt 0){ & $buildDetailCards $privacyDetails } else { "" }
    $browserDetailCards = if($browserDetails.Count -gt 0){ & $buildDetailCards $browserDetails } else { "" }
    $networkDetailCards = if($networkDetails.Count -gt 0){ & $buildDetailCards $networkDetails } else { "" }
    $integrityDetailCards = if($integrityDetails.Count -gt 0){ & $buildDetailCards $integrityDetails } else { "" }
    $accountDetailCards = if($accountDetails.Count -gt 0){ & $buildDetailCards $accountDetails } else { "" }
    $ransomDetailCards = if($ransomDetails.Count -gt 0){ & $buildDetailCards $ransomDetails } else { "" }

    # Patch rows
    $patchRows = if($MissingPatches.Count -gt 0){
        ($MissingPatches | ForEach-Object {
            $sevBadge = switch($_.Severity){"Critical"{"<span class='status-badge status-fail'>Critical</span>"}"Important"{"<span class='status-badge status-warn'>Important</span>"}default{"<span class='status-badge status-info'>$($_.Severity)</span>"}}
            "<tr><td style='font-family:Consolas,monospace;font-weight:600;'>$($_.KB)</td><td>$($_.Title)</td><td>$sevBadge</td><td style='text-align:right;'>$($_.SizeMB) MB</td></tr>"
        }) -join "`n"
    } else { "<tr><td colspan='4' class='pass' style='text-align:center;padding:16px;'>$iconPass All patches up to date</td></tr>" }

    # Mini donut helper for exec summary cards
    $criticalPatches = ($MissingPatches | Where-Object { $_.Severity -eq "Critical" }).Count
    $importantPatches = ($MissingPatches | Where-Object { $_.Severity -eq "Important" }).Count

    # ── NEW: Generate executive summary enhancements for security report ──
    $secSecurityFailures = @()
    foreach ($item in $Scoring.Breakdown) {
        if (-not $item.Passed) {
            $secSecurityFailures += @{ Check = $item.Check; Points = $item.Points }
        }
    }
    $secRiskGaugeSVG = Build-SVGRiskGauge -Score $Scoring.Score
    $secBusinessRiskText = Build-BusinessRiskAssessment -HwScore 0 -SecScore $Scoring.Score -SystemInfo $SystemInfo -Stability $null -StressResults $null
    $secRemediationItems = Build-RemediationTable -HwIssues @() -SecurityFailures $secSecurityFailures
    $secRecommendedSvcs = Build-RecommendedServices -HwIssues @() -SecurityFailures $secSecurityFailures -SystemInfo $SystemInfo -StressResults $null

    # Build security remediation HTML rows
    $secRemediationHTML = ""
    if ($secRemediationItems.Count -gt 0) {
        $secRemRows = ($secRemediationItems | ForEach-Object {
            $prColor = switch ($_.Priority) { "Critical" { "#dc2626" } "High" { "#f59e0b" } default { "#2596be" } }
            "<tr><td style='color:$prColor;font-weight:700;'>$($_.Priority)</td><td>$($_.Issue)</td><td style='text-align:center;'><span style='padding:3px 10px;border-radius:12px;background:#fff3cd;color:#856404;font-size:8pt;font-weight:600;'>$($_.Status)</span></td><td style='text-align:center;'>$($_.EstTime)</td></tr>"
        }) -join "`n"
        $secRemediationHTML = @"
<div class='sub-header' style='margin-top:18px;'>Remediation Tracking</div>
<table><tr><th>Priority</th><th>Issue</th><th style='text-align:center;'>Status</th><th style='text-align:center;'>Est. Time</th></tr>
$secRemRows
</table>
"@
    }

    # Build security recommended services HTML
    $secServicesHTML = ""
    if ($secRecommendedSvcs.Count -gt 0) {
        $secSvcRows = ($secRecommendedSvcs | ForEach-Object {
            "<tr><td style='font-weight:600;color:#0a1628;'>$($_.Service)</td><td>$($_.Description)</td><td style='text-align:center;font-weight:700;color:#0d4b71;white-space:nowrap;'>$($_.PriceRange)</td></tr>"
        }) -join "`n"
        $secServicesHTML = @"
<div class='sub-header' style='margin-top:18px;'>&#128736; Recommended Services</div>
<div style='padding:10px;background:#f0f7fb;border-left:4px solid #2596be;border-radius:4px;margin-bottom:10px;font-size:9pt;color:#0d4b71;'>
Based on the security audit findings, the following services are recommended to harden this system and reduce risk.
</div>
<table><tr><th>Service</th><th>Description</th><th style='text-align:center;'>Price Range</th></tr>
$secSvcRows
</table>
"@
    }

$html = @"
<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8"/><title>Security Audit Report - $($Params.CustomerName)</title>
<style>
@page { size: letter; margin: 0.5in 0.6in 0.9in 0.6in; }
* { margin:0; padding:0; box-sizing:border-box; }
body { font-family: 'Segoe UI', -apple-system, Tahoma, sans-serif; font-size: 9.5pt; color: #1e293b; line-height: 1.6; background: #fff; }
h1,h2,h3,h4 { margin:0; }

/* Print handling */
@media print {
    body { -webkit-print-color-adjust: exact; print-color-adjust: exact; font-size: 9pt; }
    .page-break { page-break-before: always; }
    .no-break { page-break-inside: avoid; }
    table { page-break-inside: avoid; }
    .section-header { page-break-after: avoid; }
    .sub-header { page-break-after: avoid; }
    .score-cards { page-break-inside: avoid; }
    .sec-detail-panel { page-break-inside: avoid; }
    .rec-card { page-break-inside: avoid; }
    .promo-banner { page-break-inside: avoid; }
    a { text-decoration: none; color: inherit; }
    tr { page-break-inside: avoid; }
}
.page-break { page-break-before: always; }

/* Fixed print footer - repeats on every page */
.print-footer {
    position: fixed; bottom: 0; left: 0; right: 0;
    padding: 6px 0; border-top: 1.5px solid #0d4b71;
    text-align: center; font-size: 7.5pt; color: #94a3b8;
    background: #fff;
}
.print-footer strong { color: #0d4b71; font-size: 7.5pt; }
.print-footer .report-name { color: #475569; }
.no-break { page-break-inside: avoid; }

/* Section headers */
.section-header {
    background: linear-gradient(135deg, #0a1628 0%, #0d4b71 100%);
    color: #fff; padding: 10px 20px; font-size: 12pt; font-weight: 600;
    margin: 24px 0 14px 0; border-radius: 6px; letter-spacing: 0.5px;
    display: flex; align-items: center; gap: 10px;
}
.section-header .section-icon { font-size: 14pt; opacity: 0.85; }
.sub-header {
    color: #0d4b71; font-size: 10.5pt; font-weight: 700; margin: 18px 0 8px 0;
    padding-bottom: 5px; border-bottom: 2px solid #2596be; letter-spacing: 0.3px;
}

/* Tables */
table { width: 100%; border-collapse: collapse; margin-bottom: 14px; font-size: 9pt; }
th {
    background: #0d4b71; color: #fff; padding: 7px 10px; text-align: left;
    font-weight: 600; font-size: 8.5pt; text-transform: uppercase; letter-spacing: 0.5px;
}
td { padding: 6px 10px; border-bottom: 1px solid #e2e8f0; vertical-align: middle; }
tr:nth-child(even) td { background: #f8fafc; }
tr:hover td { background: #eaf7fc; }
.pass { color: #16a34a; font-weight: 600; }
.fail { color: #dc2626; font-weight: 600; }
.warn { color: #f59e0b; font-weight: 600; }

/* Status badges */
.status-badge {
    display: inline-block; padding: 3px 10px; border-radius: 12px; font-size: 8.5pt;
    font-weight: 600; letter-spacing: 0.3px;
}
.status-pass { background: #dcfce7; color: #166534; }
.status-fail { background: #fef2f2; color: #991b1b; }
.status-warn { background: #fffbeb; color: #92400e; }
.status-info { background: #f0f7fb; color: #0d4b71; }

/* Score cards (executive summary) */
.score-cards {
    display: flex; gap: 12px; margin: 14px 0; flex-wrap: wrap; justify-content: center;
}
.score-card {
    flex: 1; min-width: 110px; max-width: 150px; text-align: center; padding: 14px 10px;
    background: #fff; border: 1px solid #e2e8f0; border-radius: 10px;
    box-shadow: 0 1px 3px rgba(0,0,0,0.05);
}
.score-card-label { font-size: 8pt; color: #64748b; text-transform: uppercase; font-weight: 600; margin-top: 4px; letter-spacing: 0.3px; }
.score-card-value { font-size: 16pt; font-weight: 700; margin-top: 2px; }

/* Recommendation cards */
.rec-card {
    padding: 12px 16px; margin: 8px 0; border-radius: 6px;
}
.rec-severity { font-size: 8pt; font-weight: 700; text-transform: uppercase; letter-spacing: 0.5px; margin-bottom: 2px; }
.rec-check { font-size: 10pt; font-weight: 600; color: #0a1628; margin-bottom: 3px; }
.rec-action { font-size: 9pt; color: #475569; }

/* Security detail rows */
.sec-detail-panel {
    background: #fff; border: 1px solid #e2e8f0; border-radius: 10px;
    overflow: hidden; margin-bottom: 14px;
}
.sec-detail-row {
    display: flex; padding: 9px 16px; border-bottom: 1px solid #f1f5f9;
    align-items: center;
}
.sec-detail-row:nth-child(even) { background: #f8fafc; }
.sec-detail-row:last-child { border-bottom: none; }
.sec-detail-label { min-width: 180px; font-weight: 600; color: #334155; font-size: 9.5pt; }
.sec-detail-value { flex: 1; font-size: 9.5pt; }

/* QR codes */
.qr-row { display: flex; justify-content: center; gap: 60px; margin: 20px 0; }
.qr-item { text-align: center; }
.qr-item img { width: 160px; height: 160px; border-radius: 8px; }
.qr-item .qr-fallback { width: 160px; height: 160px; border: 2px dashed #94a3b8; border-radius: 8px; display: flex; align-items: center; justify-content: center; font-size: 7.5pt; color: #94a3b8; line-height: 1.3; }
.qr-label { font-size: 9pt; font-weight: 600; color: #0d4b71; margin-top: 8px; }
.qr-sublabel { font-size: 7.5pt; color: #64748b; margin-top: 2px; }
.promo-banner { text-align: center; margin: 20px 0; page-break-inside: avoid; }
.promo-banner img { width: 100%; max-width: 100%; border-radius: 8px; box-shadow: 0 2px 8px rgba(0,0,0,0.1); }

/* Repeated page footer */
.page-footer-bar {
    margin-top: 30px; padding: 10px 0; border-top: 2px solid #0d4b71;
    text-align: center; font-size: 8pt; color: #94a3b8;
}
.page-footer-bar strong { color: #0d4b71; }
</style></head><body>

<div class="print-footer">
<span class="report-name">Security Audit Report</span> &nbsp;|&nbsp; <strong>$COMPANY</strong> &nbsp;|&nbsp; $WEBSITE &nbsp;|&nbsp; $PHONE
</div>

<!-- COVER PAGE -->
<div style="page-break-after:always;">
$(if($bannerSecOwnUri){"<div style='text-align:center;margin-bottom:15px;'><img src='$bannerSecOwnUri' alt='PC Plus Security Audit' style='width:100%;border-radius:8px;'/></div>"})

<div style="display:flex;gap:20px;align-items:center;margin:15px 0;">
<div style="flex:1;">
<div style="background:#f8fafc;border:1px solid #e2e8f0;border-radius:10px;padding:16px;">
<table style="width:100%;font-size:10pt;border:none;margin:0;">
<tr><td style="border:none;padding:4px 8px;color:#64748b;font-weight:600;width:110px;">Customer:</td><td style="border:none;padding:4px 8px;color:#0a1628;font-weight:700;">$($Params.CustomerName)</td></tr>
$(if($Params.CustomerPhone){"<tr><td style='border:none;padding:4px 8px;color:#64748b;font-weight:600;'>Phone:</td><td style='border:none;padding:4px 8px;color:#0a1628;'>$($Params.CustomerPhone)</td></tr>"})
$(if($Params.CustomerEmail){"<tr><td style='border:none;padding:4px 8px;color:#64748b;font-weight:600;'>Email:</td><td style='border:none;padding:4px 8px;color:#0a1628;'>$($Params.CustomerEmail)</td></tr>"})
$(if($Params.ContactName){"<tr><td style='border:none;padding:4px 8px;color:#64748b;font-weight:600;'>Contact:</td><td style='border:none;padding:4px 8px;color:#0a1628;'>$($Params.ContactName)</td></tr>"})
<tr><td style="border:none;padding:4px 8px;color:#64748b;font-weight:600;">Device:</td><td style="border:none;padding:4px 8px;color:#0a1628;">$($SystemInfo.ComputerName)</td></tr>
<tr><td style="border:none;padding:4px 8px;color:#64748b;font-weight:600;">Date:</td><td style="border:none;padding:4px 8px;color:#0a1628;">$date</td></tr>
<tr><td style="border:none;padding:4px 8px;color:#64748b;font-weight:600;">Technician:</td><td style="border:none;padding:4px 8px;color:#0a1628;">$($Params.TechName)</td></tr>
</table>
</div>
</div>
<div style="text-align:center;">
<svg viewBox="0 0 100 100" width="130" height="130">
<circle cx="50" cy="50" r="45" fill="none" stroke="#e5e7eb" stroke-width="8"/>
<circle cx="50" cy="50" r="45" fill="none" stroke="$($Scoring.Color)" stroke-width="8" stroke-dasharray="283" stroke-dashoffset="$dashOffset" transform="rotate(-90 50 50)" stroke-linecap="round"/>
<text x="50" y="46" text-anchor="middle" font-size="20" font-weight="bold" fill="$($Scoring.Color)">$($Scoring.Grade)</text>
<text x="50" y="62" text-anchor="middle" font-size="10" fill="#64748b">$($Scoring.Score) / 100</text>
</svg>
<div style="font-size:9pt;color:$($Scoring.Color);font-weight:700;margin-top:4px;">Security Score</div>
</div>
</div>

$(if($bannerHwTopUri){"<div style='text-align:center;margin-top:15px;'><img src='$bannerHwTopUri' alt='PC Plus Hardware Test' style='width:100%;border-radius:8px;'/></div>"})
</div>

<!-- EXECUTIVE SUMMARY -->
<div class="page-break"></div>

<div class="section-header"><span class="section-icon">&#128737;</span> Executive Summary</div>

<div style="display:flex;align-items:center;gap:24px;margin:14px 0;">
<div style="text-align:center;">
<svg viewBox="0 0 100 100" width="100" height="100">
<circle cx="50" cy="50" r="40" fill="none" stroke="#e5e7eb" stroke-width="8"/>
<circle cx="50" cy="50" r="40" fill="none" stroke="$($Scoring.Color)" stroke-width="8" stroke-dasharray="251" stroke-dashoffset="$([math]::Round(251 - (251 * $Scoring.Score / 100)))" transform="rotate(-90 50 50)" stroke-linecap="round"/>
<text x="50" y="46" text-anchor="middle" font-size="20" font-weight="bold" fill="$($Scoring.Color)">$($Scoring.Grade)</text>
<text x="50" y="62" text-anchor="middle" font-size="11" fill="#64748b">$($Scoring.Score) / 100</text>
</svg>
<div style="font-size:8pt;color:#64748b;font-weight:600;margin-top:4px;">SECURITY SCORE</div>
</div>
<div style="flex:1;">
<div class="score-cards">
<div class="score-card">
<div class="score-card-value" style="color:#16a34a;">$passCount</div>
<svg viewBox="0 0 80 6" width="80" height="6" style="margin-top:6px;"><rect width="80" height="6" rx="3" fill="#e5e7eb"/><rect width="$([math]::Round(80 * $passCount / $Scoring.Breakdown.Count))" height="6" rx="3" fill="#16a34a"/></svg>
<div class="score-card-label">Passed</div>
</div>
<div class="score-card">
<div class="score-card-value" style="color:#dc2626;">$failCount</div>
<svg viewBox="0 0 80 6" width="80" height="6" style="margin-top:6px;"><rect width="80" height="6" rx="3" fill="#e5e7eb"/><rect width="$([math]::Round(80 * $failCount / $Scoring.Breakdown.Count))" height="6" rx="3" fill="#dc2626"/></svg>
<div class="score-card-label">Failed</div>
</div>
<div class="score-card">
<div class="score-card-value" style="color:$($Scoring.Color);">$($Scoring.Score)</div>
<svg viewBox="0 0 80 6" width="80" height="6" style="margin-top:6px;"><rect width="80" height="6" rx="3" fill="#e5e7eb"/><rect width="$([math]::Round(80 * $Scoring.Score / 100))" height="6" rx="3" fill="$($Scoring.Color)"/></svg>
<div class="score-card-label">Score</div>
</div>
<div class="score-card">
<div class="score-card-value" style="color:$(if($MissingPatches.Count -eq 0){'#16a34a'}elseif($criticalPatches -gt 0){'#dc2626'}else{'#f59e0b'});">$($MissingPatches.Count)</div>
<svg viewBox="0 0 80 6" width="80" height="6" style="margin-top:6px;"><rect width="80" height="6" rx="3" fill="#e5e7eb"/><rect width="$(if($MissingPatches.Count -gt 0){[math]::Min(80, $MissingPatches.Count * 4)}else{0})" height="6" rx="3" fill="$(if($criticalPatches -gt 0){'#dc2626'}elseif($MissingPatches.Count -gt 0){'#f59e0b'}else{'#16a34a'})"/></svg>
<div class="score-card-label">Missing Patches</div>
</div>
</div>
</div>
</div>

$(if($recs.Count -gt 0){
"<div style='background:#fef5f5;border:1px solid #fca5a5;border-radius:10px;padding:14px 18px;margin:12px 0;'>
<div style='font-size:10.5pt;font-weight:700;color:#991b1b;margin-bottom:8px;'>&#9888; Action Required ($($recs.Count) item$(if($recs.Count -ne 1){'s'}))</div>
$recsHTML
</div>"
} else {
"<div style='background:#eafaf1;border:1px solid #86efac;border-radius:10px;padding:16px 20px;margin:12px 0;'>
<div style='font-size:10.5pt;font-weight:700;color:#166534;'>$iconPass All Security Checks Passed</div>
<div style='font-size:9.5pt;color:#334155;margin-top:4px;'>This system meets all security baseline requirements.</div>
</div>"
})

<!-- Risk Gauge & Business Assessment -->
<div class="no-break" style="display:flex;align-items:flex-start;gap:24px;margin:18px 0;">
<div style="text-align:center;min-width:200px;">
<div style="font-size:9pt;font-weight:700;color:#0d4b71;margin-bottom:6px;text-transform:uppercase;letter-spacing:0.5px;">Risk Assessment</div>
$secRiskGaugeSVG
</div>
<div style="flex:1;background:#f8fafc;border:1px solid #e2e8f0;border-radius:10px;padding:16px 20px;">
<div style="font-size:10.5pt;font-weight:700;color:#0d4b71;margin-bottom:8px;">&#128202; Business Risk Assessment</div>
<div style="font-size:9.5pt;color:#334155;line-height:1.7;">$secBusinessRiskText</div>
</div>
</div>

$secRemediationHTML

$secServicesHTML

<!-- SCORE BREAKDOWN -->
<div class="page-break"></div>

<div class="section-header"><span class="section-icon">&#128202;</span> Security Score Breakdown</div>

<table><tr><th style="width:30px;"></th><th>Security Check</th><th>Status</th><th style="width:70px;text-align:center;">Weight</th></tr>$breakdownRows</table>


<!-- DETAILED SECURITY STATUS -->
<div class="page-break"></div>

<div class="section-header"><span class="section-icon">&#128274;</span> Core Security Status</div>
<div class="sec-detail-panel">
$secDetailCards
</div>

$(if($privacyDetailCards){"<div class='section-header' style='margin-top:16px;'><span class='section-icon'>&#128065;</span> Privacy &amp; Data Protection</div><div class='sec-detail-panel'>$privacyDetailCards</div>"})

$(if($browserDetailCards){"<div class='section-header' style='margin-top:16px;'><span class='section-icon'>&#127760;</span> Browser Security</div><div class='sec-detail-panel'>$browserDetailCards</div>"})

<div class="page-break"></div>

$(if($networkDetailCards){"<div class='section-header'><span class='section-icon'>&#128225;</span> Network Hardening</div><div class='sec-detail-panel'>$networkDetailCards</div>"})

$(if($integrityDetailCards){"<div class='section-header' style='margin-top:16px;'><span class='section-icon'>&#128737;</span> System Integrity</div><div class='sec-detail-panel'>$integrityDetailCards</div>"})

$(if($accountDetailCards){"<div class='section-header' style='margin-top:16px;'><span class='section-icon'>&#128100;</span> Account Hygiene</div><div class='sec-detail-panel'>$accountDetailCards</div>"})

$(if($ransomDetailCards){"<div class='section-header' style='margin-top:16px;'><span class='section-icon'>&#128721;</span> Ransomware Protection</div><div class='sec-detail-panel'>$ransomDetailCards</div>"})


<!-- MISSING PATCHES -->
<div class="page-break"></div>

<div class="section-header"><span class="section-icon">&#128259;</span> Missing Windows Updates ($($MissingPatches.Count))</div>

$(if($criticalPatches -gt 0){"<div style='background:#fef5f5;border-left:4px solid #dc2626;border-radius:4px;padding:10px 14px;margin-bottom:12px;font-size:9.5pt;'><strong class='fail'>$iconFail $criticalPatches Critical</strong> and <strong class='warn'>$importantPatches Important</strong> updates are missing. Install immediately.</div>"})

<table><tr><th>KB Article</th><th>Update Title</th><th>Severity</th><th style="text-align:right;">Size</th></tr>$patchRows</table>

$(if($bannerHwBottomUri){"<div class='page-break'></div><div class='promo-banner' style='padding-top:30px;'><img src='$bannerHwBottomUri' alt='PC Plus Hardware Test'/></div>"})

<!-- BACK PAGE -->
<div class="page-break"></div>

<div style="text-align:center;padding-top:60px;">
$(if($logoDataUri){"<img src='$logoDataUri' alt='PC Plus Computing' style='width:250px;margin-bottom:30px;'/>"}else{"<div style='background:#0a1628;color:#fff;padding:16px 40px;font-size:18pt;font-weight:bold;letter-spacing:3px;border-radius:6px;margin-bottom:30px;display:inline-block;'>PC PLUS COMPUTING</div>"})
<div style="font-size:12pt;color:#0d4b71;font-weight:600;margin-bottom:6px;">Thank you for choosing PC Plus Computing</div>
<div style="font-size:10pt;color:#64748b;margin-bottom:30px;">Your Security, Our Priority &nbsp;|&nbsp; 30+ Years in Service &nbsp;|&nbsp; 4.9&#9733; Google Rating</div>

<div class="qr-row">
<div class="qr-item">
$(if($qrAppointmentUri){"<img src='$qrAppointmentUri' alt='Book Appointment'/>"}else{"<div class='qr-fallback'>Book<br/>Appointment</div>"})
<div class="qr-label">Book an Appointment</div>
<div class="qr-sublabel">pcpluscomputing.com/appointments</div>
</div>
<div class="qr-item">
$(if($qrServiceUri){"<img src='$qrServiceUri' alt='Send Info'/>"}else{"<div class='qr-fallback'>Send Us<br/>Info</div>"})
<div class="qr-label">Send Us Your Info</div>
<div class="qr-sublabel">Service Request Portal</div>
</div>
</div>

<div style="margin-top:40px;padding:20px;background:#f8fafc;border-radius:10px;border:1px solid #e2e8f0;display:inline-block;">
<div style="font-size:11pt;font-weight:700;color:#0a1628;margin-bottom:8px;">Get In Touch</div>
<div style="font-size:10pt;color:#475569;">
&#127760; $WEBSITE &nbsp;&nbsp;|&nbsp;&nbsp; &#128222; $PHONE
</div>
</div>

<div style="margin-top:40px;font-size:8pt;color:#94a3b8;">
Security Audit Report generated $date<br/>
Technician: $($Params.TechName) &nbsp;|&nbsp; Device: $($SystemInfo.ComputerName)
</div>
</div>

</body></html>
"@
    return $html
}

function Convert-ToPDF {
    param([string]$HTMLPath, [string]$PDFPath)
    $browsers = @()
    foreach ($p in @("${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe","$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe","$env:LOCALAPPDATA\Microsoft\Edge\Application\msedge.exe")) { if (Test-Path $p) { $browsers += $p; break } }
    foreach ($p in @("${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe","$env:ProgramFiles\Google\Chrome\Application\chrome.exe","$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe")) { if (Test-Path $p) { $browsers += $p; break } }
    foreach ($b in $browsers) {
        try {
            $args = "--headless --disable-gpu --no-sandbox --print-to-pdf=`"$PDFPath`" --print-to-pdf-no-header --no-pdf-header-footer --run-all-compositor-stages-before-draw --disable-extensions `"file:///$($HTMLPath.Replace('\','/'))`""
            Start-Process -FilePath $b -ArgumentList $args -PassThru -WindowStyle Hidden -Wait | Out-Null
            if (Test-Path $PDFPath) { return $true }
        } catch { continue }
    }
    return $false
}

# ─────────────────────────────────────────────────────────────────────────────
# CUSTOMER-FRIENDLY SUMMARY REPORT (1-2 pages, donut charts, plain English)
# ─────────────────────────────────────────────────────────────────────────────

function Build-CustomerSummary {
    param($Params, $SystemInfo, $Security, $Patches, $Scoring, $StressResults, $Stability, $BatteryDetail, $Network, $SpeedTest, $ScanMode)

    $logoDataUri = ""
    $logoPath = Join-Path $Global:ScriptDir "logo-base64.txt"
    if (Test-Path $logoPath) { try { $logoDataUri = "data:image/png;base64,$((Get-Content $logoPath -Raw).Trim())" } catch {} }
    $logoHTML = if ($logoDataUri) {
        "<img src='$logoDataUri' alt='PC Plus Computing' style='width:280px;max-width:80%;'/>"
    } else {
        "<div style='font-size:20pt;font-weight:700;color:#0a3a56;letter-spacing:2px;'>PC PLUS COMPUTING</div>"
    }

    $qrAppUri = ""; $qrSvcUri = ""
    $qrAppPath = Join-Path $Global:ScriptDir "qr-appointments.txt"
    $qrSvcPath = Join-Path $Global:ScriptDir "qr-service-requests.txt"
    if (Test-Path $qrAppPath) { try { $qrAppUri = "data:image/png;base64,$((Get-Content $qrAppPath -Raw).Trim())" } catch {} }
    if (Test-Path $qrSvcPath) { try { $qrSvcUri = "data:image/png;base64,$((Get-Content $qrSvcPath -Raw).Trim())" } catch {} }

    # Calculate category scores
    $secScore = if ($Scoring) { $Scoring.Score } else { 0 }

    # Hardware score from stress tests
    $hwParts = @()
    if ($StressResults.CPU) { $hwParts += if ($StressResults.CPU.Passed) { 100 } else { 30 } }
    if ($StressResults.RAM) { $hwParts += if ($StressResults.RAM.Passed) { 100 } else { 20 } }
    if ($StressResults.GPU) { $hwParts += if ($StressResults.GPU.Passed) { 100 } else { 40 } }
    if ($Stability) {
        $crashes = $Stability.TotalBSODs + $Stability.TotalUnexpected
        $hwParts += if ($crashes -eq 0) { 100 } elseif ($crashes -le 3) { 70 } else { 40 }
    }
    if ($SystemInfo.DeviceErrors.Count -gt 0) { $hwParts += [math]::Max(30, 100 - ($SystemInfo.DeviceErrors.Count * 15)) }
    else { $hwParts += 100 }
    $hwScore = if ($hwParts.Count -gt 0) { [math]::Round(($hwParts | Measure-Object -Average).Average) } else { 85 }

    # Storage score
    $storageParts = @()
    foreach ($d in $SystemInfo.SMART) {
        $storageParts += if ($d.Health -eq "Healthy") { 100 } else { 30 }
    }
    foreach ($d in $SystemInfo.Disks) {
        $storageParts += if ($d.UsedPct -le 75) { 100 } elseif ($d.UsedPct -le 90) { 65 } else { 30 }
    }
    $storageScore = if ($storageParts.Count -gt 0) { [math]::Round(($storageParts | Measure-Object -Average).Average) } else { 85 }

    # Network score
    $netParts = @()
    if ($Network) {
        $netParts += if ($Network.InternetTest.Success) { 100 } else { 20 }
        $netParts += if ($Network.DNSTest.Success) { 100 } else { 30 }
        if ($Network.InternetTest.ResponseMs) {
            $netParts += if ($Network.InternetTest.ResponseMs -lt 100) { 100 } elseif ($Network.InternetTest.ResponseMs -lt 300) { 75 } else { 50 }
        }
    }
    $netScore = if ($netParts.Count -gt 0) { [math]::Round(($netParts | Measure-Object -Average).Average) } else { 85 }

    # Overall score (weighted average)
    $overallScore = [math]::Round(($hwScore * 0.30) + ($secScore * 0.30) + ($storageScore * 0.25) + ($netScore * 0.15))

    # Helper functions
    function Get-DonutSVG($score, $size, $label) {
        $color = if ($score -ge 80) { "#22c55e" } elseif ($score -ge 60) { "#f59e0b" } else { "#dc2626" }
        $bg = if ($score -ge 80) { "#dcfce7" } elseif ($score -ge 60) { "#fef3c7" } else { "#fee2e2" }
        $grade = if ($score -ge 90){"A"} elseif($score -ge 80){"B"} elseif($score -ge 70){"C"} elseif($score -ge 60){"D"} else{"F"}
        $r = 42
        $circ = [math]::Round(2 * [math]::PI * $r, 1)
        $offset = [math]::Round($circ - ($circ * $score / 100), 1)
        return @"
<div style="text-align:center;">
<svg viewBox="0 0 100 100" width="$size" height="$size">
<circle cx="50" cy="50" r="$r" fill="none" stroke="#e5e7eb" stroke-width="8"/>
<circle cx="50" cy="50" r="$r" fill="none" stroke="$color" stroke-width="8"
  stroke-dasharray="$circ" stroke-dashoffset="$offset"
  transform="rotate(-90 50 50)" stroke-linecap="round"/>
<text x="50" y="46" text-anchor="middle" font-size="22" font-weight="bold" fill="$color" font-family="Segoe UI,sans-serif">$grade</text>
<text x="50" y="62" text-anchor="middle" font-size="10" fill="#64748b" font-family="Segoe UI,sans-serif">$score/100</text>
</svg>
<div style="font-size:10pt;color:#1a2b3c;font-weight:600;margin-top:4px;">$label</div>
</div>
"@
    }

    # Plain English findings
    $findings = @()

    # Storage findings
    foreach ($d in $SystemInfo.SMART) {
        if ($d.Health -eq "Healthy") { $findings += @{T="Your hard drive ($($d.Model)) is healthy and working well.";S="pass"} }
        else { $findings += @{T="Your hard drive ($($d.Model)) is showing signs of wear and may need replacing soon.";S="fail"} }
    }
    foreach ($d in $SystemInfo.Disks) {
        if ($d.UsedPct -gt 90) { $findings += @{T="Your $($d.Drive) drive is almost full ($($d.UsedPct)% used). This slows down your computer.";S="fail"} }
        elseif ($d.UsedPct -gt 75) { $findings += @{T="Your $($d.Drive) drive is getting full ($($d.UsedPct)% used). Consider cleaning up some files.";S="warn"} }
        else { $findings += @{T="Your $($d.Drive) drive has plenty of free space ($($d.Free) GB available).";S="pass"} }
    }

    # Security findings
    if ($Security) {
        if ($Security.Defender.RealTimeProtection -or ($Security.ThirdPartyAV -and $Security.ThirdPartyAV.Count -gt 0)) {
            $findings += @{T="Your antivirus protection is active and running.";S="pass"}
        } else { $findings += @{T="Your antivirus protection appears to be off. We recommend turning it on for safety.";S="fail"} }

        if ($Security.Firewall.Domain -and $Security.Firewall.Private -and $Security.Firewall.Public) {
            $findings += @{T="Your firewall is properly enabled on all network types.";S="pass"}
        } else { $findings += @{T="Your firewall is not fully enabled. Some network profiles are unprotected.";S="fail"} }
    }

    if ($Patches) {
        $critPatches = @($Patches | Where-Object { $_.Severity -eq "Critical" })
        if ($critPatches.Count -gt 0) { $findings += @{T="Your computer is missing $($critPatches.Count) important Windows security update(s) that should be installed.";S="fail"} }
        elseif ($Patches.Count -gt 0) { $findings += @{T="There are $($Patches.Count) optional Windows update(s) available for your computer.";S="warn"} }
        else { $findings += @{T="Your Windows is up to date with all important updates installed.";S="pass"} }
    }

    # Stress test findings
    if ($StressResults.CPU -and $StressResults.RAM) {
        if ($StressResults.CPU.Passed -and $StressResults.RAM.Passed) {
            $findings += @{T="Your processor and memory both passed stress testing with no errors detected.";S="pass"}
        } else {
            if (-not $StressResults.CPU.Passed) { $findings += @{T="Your processor showed issues during stress testing. This may cause freezing or crashes.";S="fail"} }
            if (-not $StressResults.RAM.Passed) { $findings += @{T="Your memory (RAM) had errors during testing. This can cause crashes and data issues.";S="fail"} }
        }
    }

    # Battery
    if ($BatteryDetail -and $BatteryDetail.Present -and $BatteryDetail.HealthPct -gt 0) {
        $bh = $BatteryDetail.HealthPct
        if ($bh -ge 80) { $findings += @{T="Your battery is in good condition ($bh% of original capacity remaining).";S="pass"} }
        elseif ($bh -ge 50) { $findings += @{T="Your battery shows some wear ($bh% of original capacity). It still works but won't last as long.";S="warn"} }
        else { $findings += @{T="Your battery is worn out ($bh% of original). We recommend replacing it for reliable use away from the charger.";S="fail"} }
    }

    # Stability
    if ($Stability) {
        $crashes = $Stability.TotalBSODs + $Stability.TotalUnexpected
        if ($crashes -eq 0) { $findings += @{T="Your computer has been running stably with no crashes or unexpected shutdowns.";S="pass"} }
        elseif ($crashes -le 3) { $findings += @{T="Your computer has had $crashes unexpected shutdown(s) recently. Worth monitoring.";S="warn"} }
        else { $findings += @{T="Your computer has crashed $crashes times recently, which may indicate a hardware or software problem.";S="fail"} }
    }

    # Network
    if ($Network) {
        if ($Network.InternetTest.Success) { $findings += @{T="Your internet connection is working normally.";S="pass"} }
        else { $findings += @{T="Your computer could not connect to the internet during testing.";S="fail"} }
    }

    # Build findings HTML
    $findingsHTML = ""
    $findCount = 0
    foreach ($f in $findings) {
        if ($findCount -ge 8) { break }
        $icon = switch ($f.S) { "pass" { "&#10004;" } "warn" { "&#9888;" } "fail" { "&#10008;" } }
        $iconColor = switch ($f.S) { "pass" { "#22c55e" } "warn" { "#f59e0b" } "fail" { "#dc2626" } }
        $bgColor = switch ($f.S) { "pass" { "#f0fdf4" } "warn" { "#fffbeb" } "fail" { "#fef2f2" } }
        $findingsHTML += "<div style='display:flex;align-items:flex-start;gap:10px;padding:8px 12px;margin:4px 0;border-radius:6px;background:$bgColor;'>"
        $findingsHTML += "<span style='font-size:14pt;color:$iconColor;flex-shrink:0;'>$icon</span>"
        $findingsHTML += "<span style='font-size:10.5pt;color:#1a2b3c;line-height:1.4;'>$($f.T)</span>"
        $findingsHTML += "</div>"
        $findCount++
    }

    # Build pass/fail checklist
    $checklist = @()
    $checklist += @{L="Processor (CPU)"; P=$(if($StressResults.CPU){$StressResults.CPU.Passed}else{$true}); D=$(if($StressResults.CPU -and -not $StressResults.CPU.Passed){"Failed stress test"}else{"Working normally"})}
    $checklist += @{L="Memory (RAM)"; P=$(if($StressResults.RAM){$StressResults.RAM.Passed}else{$true}); D=$(if($StressResults.RAM -and $StressResults.RAM.Errors -gt 0){"$($StressResults.RAM.Errors) error(s) found"}else{"Working normally"})}
    $checklist += @{L="Hard Drive Health"; P=$(($SystemInfo.SMART | Where-Object { $_.Health -ne "Healthy" }).Count -eq 0); D=$(if(($SystemInfo.SMART | Where-Object { $_.Health -ne "Healthy" }).Count -gt 0){"Needs attention"}else{"All drives healthy"})}
    $storageWarn = @($SystemInfo.Disks | Where-Object { $_.UsedPct -gt 90 })
    $checklist += @{L="Hard Drive Space"; P=$($storageWarn.Count -eq 0); D=$(if($storageWarn.Count -gt 0){"Drive nearly full"}else{"Plenty of space"})}
    if ($BatteryDetail -and $BatteryDetail.Present) {
        $checklist += @{L="Battery Health"; P=$($BatteryDetail.HealthPct -ge 50); D="$($BatteryDetail.HealthPct)% of original capacity"}
    }
    $checklist += @{L="System Stability"; P=$(if($Stability){($Stability.TotalBSODs + $Stability.TotalUnexpected) -eq 0}else{$true}); D=$(if($Stability -and ($Stability.TotalBSODs + $Stability.TotalUnexpected) -gt 0){"$($Stability.TotalBSODs + $Stability.TotalUnexpected) crash(es) detected"}else{"No crashes detected"})}
    if ($Security) {
        $checklist += @{L="Antivirus Protection"; P=$($Security.Defender.RealTimeProtection -or ($Security.ThirdPartyAV -and $Security.ThirdPartyAV.Count -gt 0)); D=$(if($Security.Defender.RealTimeProtection){"Windows Defender active"}elseif($Security.ThirdPartyAV -and $Security.ThirdPartyAV.Count -gt 0){$Security.ThirdPartyAV[0]}else{"Not detected"})}
        $checklist += @{L="Firewall"; P=$($Security.Firewall.Domain -and $Security.Firewall.Private -and $Security.Firewall.Public); D=$(if($Security.Firewall.Domain -and $Security.Firewall.Private -and $Security.Firewall.Public){"All profiles enabled"}else{"Some profiles disabled"})}
    }
    if ($Patches) {
        $critP = @($Patches | Where-Object { $_.Severity -eq "Critical" }).Count
        $checklist += @{L="Windows Updates"; P=$($critP -eq 0); D=$(if($critP -gt 0){"$critP critical update(s) missing"}else{"Up to date"})}
    }
    if ($Network) {
        $checklist += @{L="Internet Connection"; P=$Network.InternetTest.Success; D=$(if($Network.InternetTest.Success){"Connected ($($Network.InternetTest.ResponseMs)ms)"}else{"Not connected"})}
    }

    $checklistHTML = ""
    foreach ($c in $checklist) {
        $icon = if ($c.P) { "&#10004;" } else { "&#10008;" }
        $color = if ($c.P) { "#22c55e" } else { "#dc2626" }
        $statusText = if ($c.P) { "PASS" } else { "NEEDS ATTENTION" }
        $statusBg = if ($c.P) { "#f0fdf4" } else { "#fef2f2" }
        $checklistHTML += @"
<tr>
<td style='padding:8px 12px;border-bottom:1px solid #f1f5f9;font-size:10.5pt;color:#1a2b3c;'>$($c.L)</td>
<td style='padding:8px 12px;border-bottom:1px solid #f1f5f9;text-align:center;'>
<span style='display:inline-block;padding:3px 12px;border-radius:12px;font-size:9pt;font-weight:600;color:$color;background:$statusBg;'>
<span style='font-size:11pt;'>$icon</span> $statusText</span></td>
<td style='padding:8px 12px;border-bottom:1px solid #f1f5f9;font-size:9.5pt;color:#64748b;'>$($c.D)</td>
</tr>
"@
    }

    # Recommendations
    $recs = @()
    $failFindings = @($findings | Where-Object { $_.S -eq "fail" })
    $warnFindings = @($findings | Where-Object { $_.S -eq "warn" })
    if ($failFindings.Count -eq 0 -and $warnFindings.Count -eq 0) {
        $recs += "Your computer is in great shape! Keep up with regular Windows updates."
        $recs += "Schedule regular checkups to catch issues early and keep things running smoothly."
    } else {
        foreach ($f in $failFindings) {
            if ($f.T -match "hard drive.*wear") { $recs += "Consider replacing your hard drive soon to prevent data loss." }
            if ($f.T -match "almost full") { $recs += "Free up disk space by removing unused programs and files, or upgrade to a larger drive." }
            if ($f.T -match "antivirus.*off") { $recs += "Turn on your antivirus protection right away for better security." }
            if ($f.T -match "security update") { $recs += "Install the missing Windows updates as soon as possible for better security." }
            if ($f.T -match "battery.*worn") { $recs += "Replace the laptop battery for reliable use without the charger." }
            if ($f.T -match "processor.*issues") { $recs += "The CPU issue may indicate overheating. Have it checked for thermal paste and cooling." }
            if ($f.T -match "memory.*errors") { $recs += "Memory errors can cause crashes. Consider testing or replacing your RAM sticks." }
            if ($f.T -match "crashed.*times") { $recs += "Frequent crashes may indicate a hardware problem. A deeper diagnostic is recommended." }
        }
        foreach ($f in $warnFindings) {
            if ($f.T -match "getting full") { $recs += "Start clearing out old files before your drive fills up completely." }
            if ($f.T -match "battery.*wear") { $recs += "Your battery still works but consider replacing it if you use the laptop unplugged often." }
        }
        if ($recs.Count -eq 0) { $recs += "Address the items marked 'Needs Attention' above for the best experience." }
        $recs += "Schedule regular checkups to catch issues early and keep things running smoothly."
    }
    $recsHTML = ""
    $recCount = 0
    foreach ($r in $recs) {
        if ($recCount -ge 4) { break }
        $recsHTML += "<div style='padding:6px 0;font-size:10.5pt;color:#1a2b3c;'><span style='color:#2596be;font-weight:bold;margin-right:6px;'>&#10148;</span>$r</div>"
        $recCount++
    }

    # QR code section
    $qrHTML = ""
    if ($qrAppUri -or $qrSvcUri) {
        $qrHTML = "<div style='display:flex;justify-content:center;gap:40px;margin-top:16px;'>"
        if ($qrAppUri) { $qrHTML += "<div style='text-align:center;'><img src='$qrAppUri' style='width:90px;height:90px;border-radius:6px;'/><div style='font-size:8.5pt;color:#64748b;margin-top:4px;'>Book Appointment</div></div>" }
        if ($qrSvcUri) { $qrHTML += "<div style='text-align:center;'><img src='$qrSvcUri' style='width:90px;height:90px;border-radius:6px;'/><div style='font-size:8.5pt;color:#64748b;margin-top:4px;'>Service Request</div></div>" }
        $qrHTML += "</div>"
    }

    # Overall condition text
    $condText = if ($overallScore -ge 90) { "Excellent" } elseif ($overallScore -ge 80) { "Good" } elseif ($overallScore -ge 60) { "Fair" } else { "Needs Attention" }
    $condColor = if ($overallScore -ge 80) { "#22c55e" } elseif ($overallScore -ge 60) { "#f59e0b" } else { "#dc2626" }

    $html = @"
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8"/>
<title>Computer Health Summary - $($Params.CustomerName)</title>
<style>
@page { size: letter; margin: 0.6in 0.7in; }
body { font-family: 'Segoe UI', Tahoma, sans-serif; margin: 0; padding: 0; color: #1a2b3c; background: #fff; line-height: 1.5; }
.page { max-width: 720px; margin: 0 auto; padding: 20px 0; }
.header { text-align: center; padding-bottom: 16px; border-bottom: 2px solid #0a3a56; margin-bottom: 20px; }
.meta { display: flex; justify-content: space-between; font-size: 9.5pt; color: #64748b; margin-bottom: 20px; }
.donuts-row { display: flex; justify-content: center; gap: 30px; margin: 20px 0; }
.section-title { font-size: 13pt; font-weight: 700; color: #0a3a56; margin: 20px 0 10px; padding-bottom: 4px; border-bottom: 2px solid #2596be; display: inline-block; }
table { width: 100%; border-collapse: collapse; }
th { background: #f1f5f9; padding: 8px 12px; text-align: left; font-size: 9.5pt; color: #64748b; font-weight: 600; text-transform: uppercase; }
.footer { text-align: center; margin-top: 24px; padding-top: 16px; border-top: 2px solid #0a3a56; }
.footer-brand { font-size: 10pt; color: #0a3a56; font-weight: 600; }
.footer-contact { font-size: 9pt; color: #64748b; margin-top: 4px; }
.footer-tagline { font-size: 9pt; color: #2596be; font-style: italic; margin-top: 6px; }
</style>
</head>
<body>
<div class="page">
    <div class="header">
        $logoHTML
        <div style="font-size:16pt;font-weight:700;color:#0a3a56;margin-top:8px;">Computer Health Report</div>
    </div>

    <div class="meta">
        <div><strong>Prepared for:</strong> $($Params.CustomerName)$(if($Params.CustomerPhone){" | $($Params.CustomerPhone)"})$(if($Params.CustomerEmail){" | $($Params.CustomerEmail)"})</div>
        <div><strong>Computer:</strong> $($SystemInfo.ComputerName)</div>
        <div><strong>Date:</strong> $(Get-Date -Format 'MMMM dd, yyyy')</div>
    </div>

    <!-- Main Health Score -->
    <div style="text-align:center;margin:10px 0 6px;">
        $(Get-DonutSVG $overallScore 180 "")
        <div style="font-size:14pt;font-weight:700;color:$condColor;margin-top:2px;">Your computer is in $condText condition</div>
    </div>

    <!-- Category Scores -->
    <div class="donuts-row">
        $(Get-DonutSVG $hwScore 100 "Hardware")
        $(Get-DonutSVG $secScore 100 "Security")
        $(Get-DonutSVG $storageScore 100 "Storage")
        $(Get-DonutSVG $netScore 100 "Network")
    </div>

    <!-- Key Findings -->
    <div class="section-title">What We Found</div>
    <div style="margin-bottom:16px;">
        $findingsHTML
    </div>

    <!-- Pass/Fail Checklist -->
    <div class="section-title">Detailed Results</div>
    <table>
        <tr><th>Component</th><th style="text-align:center;">Status</th><th>Details</th></tr>
        $checklistHTML
    </table>

    <!-- Recommendations -->
    <div class="section-title">Our Recommendations</div>
    <div style="background:#f0f9ff;border-radius:8px;padding:12px 16px;border-left:4px solid #2596be;">
        $recsHTML
    </div>

    <!-- Footer -->
    <div class="footer">
        $qrHTML
        <div class="footer-brand" style="margin-top:12px;">PC Plus Computing</div>
        <div class="footer-contact">604-760-1662 | 236-500-2700 | pcpluscomputing.com</div>
        <div class="footer-tagline">Your Security, Our Priority</div>
        <div style="font-size:8pt;color:#94a3b8;margin-top:8px;">
            Scan mode: $ScanMode | Technician: $($Params.TechName) | Report generated $(Get-Date -Format 'yyyy-MM-dd HH:mm')
        </div>
    </div>
</div>
</body>
</html>
"@

    return $html
}

# ─────────────────────────────────────────────────────────────────────────────
# WEAR & TEAR LIFECYCLE REPORT (branded HTML with component breakdown)
# ─────────────────────────────────────────────────────────────────────────────

function Build-WearAndTearHTMLReport {
    param($Params, $SystemInfo, $WearTear)
    $date = Get-Date -Format "MMMM dd, yyyy 'at' h:mm tt"
    $iconPass = "&#10004;"; $iconFail = "&#10008;"; $iconWarn = "&#9888;"

    function Get-WTDonut([int]$score, [int]$max, [string]$label) {
        $pct = if ($max -gt 0) { [math]::Round(($score / $max) * 100) } else { 0 }
        $r = 36; $c = 226.2; $dash = [math]::Round($c * $pct / 100, 1); $gap = [math]::Round($c - $dash, 1)
        $color = if ($pct -ge 80) { "#22c55e" } elseif ($pct -ge 60) { "#f59e0b" } else { "#ef4444" }
        return @"
<div style="display:inline-block;text-align:center;margin:6px 10px;width:90px;">
<svg width="80" height="80" viewBox="0 0 80 80">
<circle cx="40" cy="40" r="$r" fill="none" stroke="#e5e7eb" stroke-width="7"/>
<circle cx="40" cy="40" r="$r" fill="none" stroke="$color" stroke-width="7" stroke-dasharray="$dash $gap" stroke-dashoffset="56.55" stroke-linecap="round" transform="rotate(-90 40 40)"/>
<text x="40" y="37" text-anchor="middle" font-size="16" font-weight="bold" fill="$color">$score</text>
<text x="40" y="50" text-anchor="middle" font-size="8" fill="#64748b">/ $max</text>
</svg>
<div style="font-size:8pt;font-weight:600;color:#334155;margin-top:2px;">$label</div>
</div>
"@
    }

    $c = $WearTear.Components
    $donuts = ""
    $donuts += Get-WTDonut $c.SystemAge.Score 100 "System Age"
    $donuts += Get-WTDonut $c.Storage.Score 100 "Storage"
    $donuts += Get-WTDonut $c.Battery.Score 100 "Battery"
    $donuts += Get-WTDonut $c.Thermal.Score 100 "Thermal"
    $donuts += Get-WTDonut $c.RAM.Score 100 "RAM"
    $donuts += Get-WTDonut $c.GPU.Score 100 "GPU"
    $donuts += Get-WTDonut $c.WindowsReliability.Score 100 "Windows"
    $donuts += Get-WTDonut $c.DeviceHealth.Score 100 "Devices"

    $riskColor = switch ($WearTear.RiskLevel) { "Low" { "#22c55e" }; "Moderate" { "#f59e0b" }; "High" { "#f97316" }; "Critical" { "#ef4444" }; default { "#64748b" } }

    $componentRows = ""
    foreach ($w in $WearTear.ComponentScores) {
        $barColor = if ($w.Score -ge 80) { "#22c55e" } elseif ($w.Score -ge 60) { "#f59e0b" } else { "#ef4444" }
        $statusIcon = if ($w.Score -ge 80) { "<span style='color:#22c55e;'>$iconPass</span>" } elseif ($w.Score -ge 60) { "<span style='color:#f59e0b;'>$iconWarn</span>" } else { "<span style='color:#ef4444;'>$iconFail</span>" }
        $componentRows += "<tr><td>$($w.Name)</td><td style='text-align:center;'>$statusIcon $($w.Score)/100</td><td><div style='background:#e5e7eb;border-radius:4px;height:12px;width:100%;'><div style='background:$barColor;border-radius:4px;height:12px;width:$($w.Score)%;'></div></div></td><td style='text-align:center;font-size:9pt;color:#64748b;'>$($w.Weight)%</td></tr>"
    }

    $detailHTML = ""
    if ($c.SystemAge.AgeYears) { $detailHTML += "<div class='detail-card'><div class='detail-title'>System Age</div><div class='detail-body'>Hardware: ~$($c.SystemAge.AgeYears) years | BIOS: $($c.SystemAge.BIOSDate) | OS Install: $($c.SystemAge.InstallDate)<br/>Make: $($c.SystemAge.Manufacturer) $($c.SystemAge.Model) | S/N: $($c.SystemAge.Serial)</div></div>" }
    if ($c.Storage.Details -and $c.Storage.Details.Count -gt 0) {
        $storageLines = ""
        foreach ($d in $c.Storage.Details) {
            $lifeBar = if ($null -ne $d.LifeRemainingPct) { "$($d.LifeRemainingPct)% life remaining" } else { "Life data N/A" }
            $storageLines += "$($d.Model) | $($d.Type) $($d.SizeGB) GB | $lifeBar | POH: $($d.PowerOnHours)h<br/>"
        }
        $detailHTML += "<div class='detail-card'><div class='detail-title'>Storage Health</div><div class='detail-body'>$storageLines</div></div>"
    }
    if ($c.Battery.BatteryDetected) { $detailHTML += "<div class='detail-card'><div class='detail-title'>Battery</div><div class='detail-body'>Health: $($c.Battery.HealthPct)% | Cycles: $($c.Battery.CycleCount) | Charge: $($c.Battery.ChargePercent)%<br/>Design: $($c.Battery.DesignCapMWh) mWh | Current Max: $($c.Battery.FullChargeCapMWh) mWh</div></div>" }
    else { $detailHTML += "<div class='detail-card'><div class='detail-title'>Battery</div><div class='detail-body'>No battery detected (desktop)</div></div>" }
    $detailHTML += "<div class='detail-card'><div class='detail-title'>Thermal</div><div class='detail-body'>Avg Temp: $($c.Thermal.AvgTemp)C | Max: $($c.Thermal.MaxTemp)C | Thermal Events (90d): $($c.Thermal.ThermalEventCount)</div></div>"
    $detailHTML += "<div class='detail-card'><div class='detail-title'>RAM</div><div class='detail-body'>Total: $($c.RAM.TotalGB) GB | Modules: $($c.RAM.ModuleCount) | Mixed Speeds: $(if($c.RAM.MixedSpeeds){'Yes'}else{'No'}) | WHEA Errors: $($c.RAM.WHEAErrors)</div></div>"
    if ($c.GPU.GPUs -and $c.GPU.GPUs.Count -gt 0) {
        $gpuLines = ($c.GPU.GPUs | ForEach-Object { "$($_.Name) ($($_.DriverVersion))" }) -join "<br/>"
        $detailHTML += "<div class='detail-card'><div class='detail-title'>GPU</div><div class='detail-body'>$gpuLines<br/>Driver Crashes (90d): $($c.GPU.GPUEvents) | Driver Age: $($c.GPU.DriverAge)</div></div>"
    }
    $detailHTML += "<div class='detail-card'><div class='detail-title'>Windows Reliability</div><div class='detail-body'>BSODs: $($c.WindowsReliability.BSODs) | App Crashes: $($c.WindowsReliability.AppCrashes) | App Hangs: $($c.WindowsReliability.AppHangs) | Period: $($c.WindowsReliability.DaysChecked) days</div></div>"
    $detailHTML += "<div class='detail-card'><div class='detail-title'>Device Health</div><div class='detail-body'>Problem Devices: $($c.DeviceHealth.ProblemDevices) | Network Warnings: $($c.DeviceHealth.NetworkWarnings) | USB Events: $($c.DeviceHealth.USBEventCount)</div></div>"

    $recsHTML = ""
    if ($WearTear.Recommendations -and $WearTear.Recommendations.Count -gt 0) {
        foreach ($r in $WearTear.Recommendations) { $recsHTML += "<li>$r</li>" }
    } else { $recsHTML = "<li>No immediate action required - system is in good condition</li>" }

    $logoDataUri = ""
    $logoPath = Join-Path $Global:ScriptDir "logo-base64.txt"
    if (Test-Path $logoPath) { try { $logoDataUri = "data:image/png;base64,$((Get-Content $logoPath -Raw).Trim())" } catch {} }
    $logoHTML = if ($logoDataUri) { "<img src='$logoDataUri' alt='PC Plus Computing' style='width:240px;'/>" } else { "<div style='font-size:18pt;font-weight:700;color:#0a3a56;letter-spacing:2px;'>PC PLUS COMPUTING</div>" }

    $html = @"
<!DOCTYPE html>
<html><head><meta charset="utf-8"/><title>Wear &amp; Tear Life Report - $($Params.CustomerName)</title>
<style>
@page { size:A4; margin:12mm; }
body { font-family:'Segoe UI',Tahoma,sans-serif; margin:0; padding:0; background:#f8fafc; color:#1e293b; font-size:10pt; }
.page { max-width:800px; margin:0 auto; background:white; padding:32px; }
.header { text-align:center; border-bottom:3px solid #0d4b71; padding-bottom:16px; margin-bottom:20px; }
.header-sub { font-size:9pt; color:#64748b; margin-top:6px; }
.title-bar { background:linear-gradient(135deg,#0d4b71,#2596be); color:white; border-radius:8px; padding:16px 20px; margin-bottom:20px; display:flex; justify-content:space-between; align-items:center; }
.title-bar .score { font-size:32pt; font-weight:800; }
.title-bar .meta { text-align:right; }
.donut-row { display:flex; flex-wrap:wrap; justify-content:center; background:#f8fafc; border-radius:8px; padding:12px; margin-bottom:16px; border:1px solid #e2e8f0; }
.section-title { font-size:12pt; font-weight:700; color:#0d4b71; border-bottom:2px solid #2596be; padding-bottom:4px; margin:16px 0 10px; }
table { width:100%; border-collapse:collapse; margin-bottom:12px; }
th { background:#0d4b71; color:white; padding:6px 8px; text-align:left; font-size:9pt; }
td { padding:5px 8px; border-bottom:1px solid #e2e8f0; font-size:9pt; }
tr:nth-child(even) { background:#f8fafc; }
.detail-card { background:#f8fafc; border:1px solid #e2e8f0; border-radius:6px; padding:10px 14px; margin-bottom:8px; }
.detail-title { font-weight:700; color:#0d4b71; font-size:9.5pt; margin-bottom:3px; }
.detail-body { font-size:9pt; color:#475569; line-height:1.5; }
.risk-badge { display:inline-block; padding:4px 14px; border-radius:20px; font-weight:700; font-size:11pt; }
.recs { background:#f0f9ff; border-left:4px solid #2596be; border-radius:0 6px 6px 0; padding:10px 16px; }
.recs li { margin-bottom:4px; }
.footer { text-align:center; border-top:2px solid #0d4b71; padding-top:12px; margin-top:20px; font-size:8pt; color:#64748b; }
@media print { body { background:white; } .page { padding:0; box-shadow:none; } }
</style></head><body>
<div class="page">
    <div class="header">
        $logoHTML
        <div style="font-size:8pt;color:#2596be;font-weight:600;letter-spacing:3px;margin-top:4px;">YOUR SECURITY, OUR PRIORITY</div>
        <div class="header-sub">604-760-1662 | 236-500-2700 | pcpluscomputing.com</div>
    </div>

    <div style="text-align:center;font-size:14pt;font-weight:700;color:#0d4b71;margin-bottom:4px;">WEAR &amp; TEAR LIFECYCLE REPORT</div>
    <div style="text-align:center;font-size:9pt;color:#64748b;margin-bottom:16px;">
        Customer: $($Params.CustomerName)$(if($Params.CustomerPhone){" | Ph: $($Params.CustomerPhone)"})$(if($Params.CustomerEmail){" | $($Params.CustomerEmail)"}) | Computer: $($SystemInfo.ComputerName) | Date: $date
    </div>

    <div class="title-bar">
        <div>
            <div style="font-size:10pt;opacity:0.8;">Overall Health Score</div>
            <div class="score">$($WearTear.Score)<span style="font-size:14pt;opacity:0.6;">/100</span></div>
            <div style="font-size:10pt;">$($WearTear.GradeFull)</div>
        </div>
        <div class="meta">
            <div class="risk-badge" style="background:$riskColor;color:white;">$($WearTear.RiskLevel) Risk</div>
            <div style="margin-top:8px;font-size:10pt;color:rgba(255,255,255,0.9);">Est. Life: $($WearTear.EstimatedLifeYears) years</div>
            <div style="font-size:9pt;color:rgba(255,255,255,0.7);margin-top:2px;">$($WearTear.LifeText)</div>
        </div>
    </div>

    <div class="section-title">Component Health Overview</div>
    <div class="donut-row">$donuts</div>

    <div class="section-title">Component Breakdown</div>
    <table>
        <tr><th>Component</th><th style="text-align:center;">Score</th><th>Health Bar</th><th style="text-align:center;">Weight</th></tr>
        $componentRows
    </table>

    <div class="section-title">Detailed Analysis</div>
    $detailHTML

    <div class="section-title">Recommendations</div>
    <div class="recs"><ul style="margin:0;padding-left:18px;">$recsHTML</ul></div>

    <div class="footer">
        <div style="font-weight:700;color:#0d4b71;">PC Plus Computing</div>
        <div>604-760-1662 | 236-500-2700 | pcpluscomputing.com</div>
        <div style="color:#2596be;">Your Security, Our Priority</div>
        <div style="margin-top:6px;">Technician: $($Params.TechName) | Report generated $(Get-Date -Format 'yyyy-MM-dd HH:mm')</div>
    </div>
</div>
</body></html>
"@

    return $html
}

# ─────────────────────────────────────────────────────────────────────────────
# PAPERLESS DELIVERY - Server upload, email, config, and UI dialog
# ─────────────────────────────────────────────────────────────────────────────

function Initialize-PaperlessConfig {
    <#
    .SYNOPSIS
        Creates or reads the PCPlus360-Config.json paperless delivery config.
    .DESCRIPTION
        If the config file does not exist, creates one with sensible defaults
        (all delivery methods disabled). Returns the parsed config object.
    #>
    param(
        [string]$ConfigPath = ""
    )

    if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
        $ConfigPath = Join-Path $Global:ScriptDir "PCPlus360-Config.json"
    }

    $defaultConfig = @{
        ServerUpload = @{
            Enabled    = $false
            Url        = "https://reports.pcpluscomputing.com/api/upload"
            ApiKey     = ""
            AutoUpload = $false
        }
        Email = @{
            Enabled          = $false
            SmtpServer       = ""
            SmtpPort         = 587
            UseSSL           = $true
            FromAddress      = ""
            FromName         = "PC Plus Computing"
            Username         = ""
            Password         = ""
            DefaultRecipient = ""
        }
        AutoUploadEnabled = $true
    }

    if (Test-Path $ConfigPath) {
        try {
            $raw = Get-Content $ConfigPath -Raw -Encoding UTF8
            $config = $raw | ConvertFrom-Json

            # Ensure all expected keys exist (merge with defaults for forward compat)
            if (-not $config.ServerUpload) {
                $config | Add-Member -NotePropertyName "ServerUpload" -NotePropertyValue ($defaultConfig.ServerUpload | ConvertTo-Json -Depth 3 | ConvertFrom-Json) -Force
            }
            if (-not $config.Email) {
                $config | Add-Member -NotePropertyName "Email" -NotePropertyValue ($defaultConfig.Email | ConvertTo-Json -Depth 3 | ConvertFrom-Json) -Force
            }
            if ($null -eq $config.AutoUploadEnabled) {
                $config | Add-Member -NotePropertyName "AutoUploadEnabled" -NotePropertyValue $true -Force
            }

            Write-DiagLog "Paperless config loaded from $ConfigPath"
            return $config
        }
        catch {
            Write-DiagLog "Failed to parse config at $ConfigPath : $($_.Exception.Message)" "WARN"
            # Fall through to create new default
        }
    }

    # Create default config
    try {
        $json = $defaultConfig | ConvertTo-Json -Depth 5
        [IO.File]::WriteAllText($ConfigPath, $json, [Text.Encoding]::UTF8)
        Write-DiagLog "Created default paperless config at $ConfigPath"
    }
    catch {
        Write-DiagLog "Could not write config file: $($_.Exception.Message)" "WARN"
    }

    return ($defaultConfig | ConvertTo-Json -Depth 5 | ConvertFrom-Json)
}


function Send-ReportToServer {
    <#
    .SYNOPSIS
        Uploads a diagnostic report (HTML or PDF) to the PC Plus reporting server.
    .DESCRIPTION
        Reads the server URL and API key from PCPlus360-Config.json, then performs
        a multipart/form-data POST with file + metadata. Returns a hashtable with
        Success, Message, and ViewUrl keys. Fails gracefully on network errors.
    #>
    param(
        [Parameter(Mandatory)][string]$ReportPath,
        [string]$CustomerName  = "",
        [string]$ComputerName  = "",
        [string]$TechName      = "",
        [string]$ScanMode      = "",
        [string]$ServerUrl     = ""
    )

    $result = @{ Success = $false; Message = ""; ViewUrl = "" }

    # Validate file exists
    if (-not (Test-Path $ReportPath)) {
        $result.Message = "Report file not found: $ReportPath"
        Write-DiagLog $result.Message "WARN"
        return $result
    }

    # Load config
    $config = Initialize-PaperlessConfig
    if (-not $config.ServerUpload.Enabled -and [string]::IsNullOrWhiteSpace($ServerUrl)) {
        $result.Message = "Server upload is disabled in config and no override URL provided."
        Write-DiagLog $result.Message "WARN"
        return $result
    }

    $uploadUrl = if (-not [string]::IsNullOrWhiteSpace($ServerUrl)) { $ServerUrl } else { $config.ServerUpload.Url }
    $apiKey    = $config.ServerUpload.ApiKey

    if ([string]::IsNullOrWhiteSpace($uploadUrl)) {
        $result.Message = "No server URL configured."
        Write-DiagLog $result.Message "WARN"
        return $result
    }

    # Determine file type
    $ext = [IO.Path]::GetExtension($ReportPath).ToLower()
    $fileType = switch ($ext) {
        ".pdf"  { "application/pdf" }
        ".html" { "text/html" }
        ".htm"  { "text/html" }
        default { "application/octet-stream" }
    }
    $friendlyType = if ($ext -eq ".pdf") { "PDF" } else { "HTML" }

    try {
        Write-DiagLog "Uploading report to $uploadUrl ..."

        # Build multipart form body
        $boundary = [System.Guid]::NewGuid().ToString("N")
        $LF = "`r`n"
        $fileName = [IO.Path]::GetFileName($ReportPath)
        $fileBytes = [IO.File]::ReadAllBytes($ReportPath)

        # Metadata fields
        $fields = @{
            customer_name = $CustomerName
            computer_name = $ComputerName
            tech_name     = $TechName
            scan_mode     = $ScanMode
            scan_date     = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            file_type     = $friendlyType
        }

        $bodyParts = [System.Collections.ArrayList]::new()
        foreach ($key in $fields.Keys) {
            [void]$bodyParts.Add("--$boundary$LF")
            [void]$bodyParts.Add("Content-Disposition: form-data; name=`"$key`"$LF$LF")
            [void]$bodyParts.Add("$($fields[$key])$LF")
        }

        # File part header
        $fileHeader = "--$boundary${LF}Content-Disposition: form-data; name=`"report_file`"; filename=`"$fileName`"${LF}Content-Type: $fileType${LF}${LF}"
        $fileFooter = "${LF}--${boundary}--${LF}"

        # Assemble as bytes
        $enc = [Text.Encoding]::UTF8
        $textPreamble = $enc.GetBytes(($bodyParts -join ""))
        $headerBytes  = $enc.GetBytes($fileHeader)
        $footerBytes  = $enc.GetBytes($fileFooter)

        $bodyStream = [IO.MemoryStream]::new()
        $bodyStream.Write($textPreamble, 0, $textPreamble.Length)
        $bodyStream.Write($headerBytes,  0, $headerBytes.Length)
        $bodyStream.Write($fileBytes,    0, $fileBytes.Length)
        $bodyStream.Write($footerBytes,  0, $footerBytes.Length)
        $fullBody = $bodyStream.ToArray()
        $bodyStream.Close()

        # Build headers
        $headers = @{
            "Content-Type" = "multipart/form-data; boundary=$boundary"
        }
        if (-not [string]::IsNullOrWhiteSpace($apiKey)) {
            $headers["Authorization"] = "Bearer $apiKey"
        }

        # Allow TLS 1.2
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls11

        $response = Invoke-RestMethod -Uri $uploadUrl -Method Post -Headers $headers -Body $fullBody -ContentType "multipart/form-data; boundary=$boundary" -TimeoutSec 60 -ErrorAction Stop

        $result.Success = $true
        $result.Message = "Report uploaded successfully."
        if ($response.url)      { $result.ViewUrl = $response.url }
        elseif ($response.link) { $result.ViewUrl = $response.link }
        elseif ($response.id)   { $result.ViewUrl = "$($uploadUrl -replace '/api/upload.*$','')/view/$($response.id)" }
        Write-DiagLog "Upload complete. View URL: $($result.ViewUrl)"
    }
    catch [System.Net.WebException] {
        $statusCode = ""
        if ($_.Exception.Response) {
            $statusCode = [int]$_.Exception.Response.StatusCode
        }
        $result.Message = "Server unreachable or returned error$(if($statusCode){" (HTTP $statusCode)"}): $($_.Exception.Message)"
        Write-DiagLog $result.Message "WARN"
    }
    catch {
        $result.Message = "Upload failed: $($_.Exception.Message)"
        Write-DiagLog $result.Message "WARN"
    }

    return $result
}


function Send-ReportByEmail {
    <#
    .SYNOPSIS
        Emails a diagnostic report to a recipient via SMTP or falls back to mailto:.
    .DESCRIPTION
        Reads SMTP config from PCPlus360-Config.json. Sends the report as an
        attachment with a branded plaintext body. If SMTP fails, opens the default
        email client via mailto: so the tech can send manually.
    #>
    param(
        [Parameter(Mandatory)][string]$ReportPath,
        [string]$RecipientEmail = "",
        [string]$CustomerName   = "",
        [string]$TechName       = "",
        [string]$ScanMode       = ""
    )

    $result = @{ Success = $false; Message = ""; FallbackUsed = $false }

    # Validate file
    if (-not (Test-Path $ReportPath)) {
        $result.Message = "Report file not found: $ReportPath"
        Write-DiagLog $result.Message "WARN"
        return $result
    }

    # Load config
    $config = Initialize-PaperlessConfig
    $smtp = $config.Email

    if ([string]::IsNullOrWhiteSpace($RecipientEmail)) {
        $RecipientEmail = $smtp.DefaultRecipient
    }
    if ([string]::IsNullOrWhiteSpace($RecipientEmail)) {
        $result.Message = "No recipient email provided and no default configured."
        Write-DiagLog $result.Message "WARN"
        return $result
    }

    # Build email content
    $fileName  = [IO.Path]::GetFileName($ReportPath)
    $dateStr   = Get-Date -Format "MMMM dd, yyyy"
    $techLabel = if (-not [string]::IsNullOrWhiteSpace($TechName)) { $TechName } else { "PC Plus Computing" }

    $subject = "PC Plus Computing - Diagnostic Report for $CustomerName"

    $body = @"
Hello,

Please find attached the diagnostic report for $CustomerName.

Report:      $fileName
Scan Mode:   $ScanMode
Date:        $dateStr
Technician:  $techLabel

If you have any questions about this report, please don't hesitate to contact us.

Best regards,
$techLabel
PC Plus Computing
604-760-1662 | 236-500-2700
pcpluscomputing.com
Your Security, Our Priority
"@

    # Attempt SMTP send
    $smtpAttempted = $false
    if ($smtp.Enabled -and -not [string]::IsNullOrWhiteSpace($smtp.SmtpServer)) {
        $smtpAttempted = $true
        try {
            Write-DiagLog "Sending email via SMTP ($($smtp.SmtpServer):$($smtp.SmtpPort))..."

            $fromAddr = if (-not [string]::IsNullOrWhiteSpace($smtp.FromAddress)) { $smtp.FromAddress } else { $smtp.Username }
            if ([string]::IsNullOrWhiteSpace($fromAddr)) {
                throw "No From address or Username configured for SMTP."
            }

            $mailParams = @{
                From        = if (-not [string]::IsNullOrWhiteSpace($smtp.FromName)) { "$($smtp.FromName) <$fromAddr>" } else { $fromAddr }
                To          = $RecipientEmail
                Subject     = $subject
                Body        = $body
                SmtpServer  = $smtp.SmtpServer
                Port        = $smtp.SmtpPort
                Attachments = $ReportPath
                Encoding    = [Text.Encoding]::UTF8
            }

            if ($smtp.UseSSL) {
                $mailParams["UseSsl"] = $true
            }

            if (-not [string]::IsNullOrWhiteSpace($smtp.Username) -and -not [string]::IsNullOrWhiteSpace($smtp.Password)) {
                $secPass = ConvertTo-SecureString $smtp.Password -AsPlainText -Force
                $cred = New-Object System.Management.Automation.PSCredential($smtp.Username, $secPass)
                $mailParams["Credential"] = $cred
            }

            Send-MailMessage @mailParams -ErrorAction Stop

            $result.Success = $true
            $result.Message = "Email sent to $RecipientEmail via SMTP."
            Write-DiagLog $result.Message
            return $result
        }
        catch {
            Write-DiagLog "SMTP send failed: $($_.Exception.Message)" "WARN"
            # Fall through to mailto: fallback
        }
    }

    # Fallback: open default mail client
    Write-DiagLog "Using mailto: fallback..."
    $result.FallbackUsed = $true

    try {
        # Copy report path to clipboard so tech can attach it
        try { [System.Windows.Clipboard]::SetText($ReportPath) } catch {}

        $encodedSubject = [Uri]::EscapeDataString($subject)
        $encodedBody    = [Uri]::EscapeDataString($body)
        $mailto = "mailto:${RecipientEmail}?subject=$encodedSubject&body=$encodedBody"
        Start-Process $mailto

        $reason = if ($smtpAttempted) { "SMTP failed - opened default email client" } else { "SMTP not configured - opened default email client" }
        $result.Success = $true
        $result.Message = "$reason. Report path copied to clipboard - please attach manually."
        Write-DiagLog $result.Message
    }
    catch {
        $result.Success = $false
        $result.Message = "Could not open email client: $($_.Exception.Message)"
        Write-DiagLog $result.Message "WARN"
    }

    return $result
}


function Show-PaperlessDialog {
    <#
    .SYNOPSIS
        WPF dialog for paperless report delivery (upload to server + email).
    .DESCRIPTION
        Shows a branded dark-themed dialog where the tech can toggle server upload
        and email delivery, enter a recipient, and see real-time status. Returns
        a hashtable summarizing what was sent and any errors.
    .PARAMETER ReportPath
        Path to the report file (HTML or PDF) to deliver.
    .PARAMETER CustomerName
        Customer name for metadata.
    .PARAMETER ComputerName
        Computer name for metadata.
    .PARAMETER TechName
        Technician name for metadata.
    .PARAMETER ScanMode
        Scan mode label (Quick, Full, etc.).
    #>
    param(
        [Parameter(Mandatory)][string]$ReportPath,
        [string]$CustomerName = "",
        [string]$ComputerName = "",
        [string]$TechName     = "",
        [string]$ScanMode     = ""
    )

    $dialogResult = @{
        Cancelled    = $true
        ServerResult = $null
        EmailResult  = $null
    }

    # Load config for defaults
    $config = Initialize-PaperlessConfig
    $defaultEmail = $config.Email.DefaultRecipient

    $xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="PC Plus 360 - Paperless Delivery" Height="520" Width="540"
        WindowStartupLocation="CenterScreen" ResizeMode="NoResize"
        Background="#eef4f8" FontFamily="Segoe UI">
    <Window.Resources>
        <Style x:Key="FlatBtn" TargetType="Button">
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="bd" Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="6" Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="{TemplateBinding HorizontalContentAlignment}"
                                              VerticalAlignment="{TemplateBinding VerticalContentAlignment}"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="bd" Property="Opacity" Value="0.85"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="bd" Property="Opacity" Value="0.7"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter Property="Opacity" Value="0.4"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>
    <Grid>
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <!-- Header -->
        <Border Grid.Row="0" Background="#0a3a56" Padding="16,14">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="*"/>
                </Grid.ColumnDefinitions>
                <Border Width="36" Height="36" CornerRadius="8" Margin="0,0,12,0">
                    <Border.Background>
                        <LinearGradientBrush StartPoint="0,0" EndPoint="1,1">
                            <GradientStop Color="#2596be" Offset="0"/>
                            <GradientStop Color="#3bbde0" Offset="1"/>
                        </LinearGradientBrush>
                    </Border.Background>
                    <TextBlock Text="&#xE122;" FontFamily="Segoe MDL2 Assets" FontSize="16" Foreground="White" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                </Border>
                <StackPanel Grid.Column="1" VerticalAlignment="Center">
                    <TextBlock Text="Paperless Report Delivery" FontSize="15" FontWeight="SemiBold" Foreground="White"/>
                    <TextBlock Text="Upload to server or email directly to customer" FontSize="10.5" Foreground="#3bbde0"/>
                </StackPanel>
            </Grid>
        </Border>

        <!-- Content -->
        <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto" Margin="0">
            <StackPanel Margin="18,14,18,10">

                <!-- Report Info -->
                <Border Background="White" CornerRadius="7" Padding="12" Margin="0,0,0,12" BorderBrush="#d8e8f0" BorderThickness="1">
                    <StackPanel>
                        <TextBlock Text="REPORT FILE" FontSize="8.5" FontWeight="SemiBold" Foreground="#8a9baa" Margin="0,0,0,3"/>
                        <TextBlock x:Name="lblReportFile" Text="" FontSize="11" Foreground="#1a2b3c" FontFamily="Consolas" TextWrapping="Wrap"/>
                        <StackPanel Orientation="Horizontal" Margin="0,4,0,0">
                            <TextBlock Text="Customer:" FontSize="10" Foreground="#5a7080" Margin="0,0,6,0"/>
                            <TextBlock x:Name="lblCustomer" Text="" FontSize="10" FontWeight="SemiBold" Foreground="#1a2b3c"/>
                            <TextBlock Text="  |  Computer:" FontSize="10" Foreground="#5a7080" Margin="8,0,6,0"/>
                            <TextBlock x:Name="lblComputer" Text="" FontSize="10" FontWeight="SemiBold" Foreground="#1a2b3c"/>
                        </StackPanel>
                    </StackPanel>
                </Border>

                <!-- Server Upload Section -->
                <Border Background="White" CornerRadius="7" Padding="12" Margin="0,0,0,10" BorderBrush="#d8e8f0" BorderThickness="1">
                    <StackPanel>
                        <Grid>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="Auto"/>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="Auto"/>
                            </Grid.ColumnDefinitions>
                            <Border Width="28" Height="28" CornerRadius="6" Background="#eef8ff" Margin="0,0,10,0">
                                <TextBlock Text="&#xE128;" FontFamily="Segoe MDL2 Assets" FontSize="13" Foreground="#2596be" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                            </Border>
                            <StackPanel Grid.Column="1" VerticalAlignment="Center">
                                <TextBlock Text="Upload to Server" FontSize="12.5" FontWeight="SemiBold" Foreground="#1a2b3c"/>
                                <TextBlock Text="Send to PC Plus reporting dashboard" FontSize="9.5" Foreground="#5a7080"/>
                            </StackPanel>
                            <CheckBox x:Name="chkUpload" Grid.Column="2" VerticalAlignment="Center" IsChecked="False"/>
                        </Grid>
                        <TextBlock x:Name="lblUploadStatus" Text="" FontSize="9.5" Foreground="#5a7080" Margin="38,6,0,0" TextWrapping="Wrap"/>
                    </StackPanel>
                </Border>

                <!-- Email Section -->
                <Border Background="White" CornerRadius="7" Padding="12" Margin="0,0,0,10" BorderBrush="#d8e8f0" BorderThickness="1">
                    <StackPanel>
                        <Grid>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="Auto"/>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="Auto"/>
                            </Grid.ColumnDefinitions>
                            <Border Width="28" Height="28" CornerRadius="6" Background="#f0fdf4" Margin="0,0,10,0">
                                <TextBlock Text="&#xE119;" FontFamily="Segoe MDL2 Assets" FontSize="13" Foreground="#16a34a" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                            </Border>
                            <StackPanel Grid.Column="1" VerticalAlignment="Center">
                                <TextBlock Text="Send by Email" FontSize="12.5" FontWeight="SemiBold" Foreground="#1a2b3c"/>
                                <TextBlock Text="Email report directly to customer" FontSize="9.5" Foreground="#5a7080"/>
                            </StackPanel>
                            <CheckBox x:Name="chkEmail" Grid.Column="2" VerticalAlignment="Center" IsChecked="False"/>
                        </Grid>
                        <StackPanel Margin="38,8,0,0">
                            <TextBlock Text="RECIPIENT EMAIL" FontSize="8.5" FontWeight="SemiBold" Foreground="#8a9baa" Margin="0,0,0,2"/>
                            <TextBox x:Name="txtEmail" FontSize="12" Padding="6,4" Background="#f6f9fb" Foreground="#1a2b3c" BorderBrush="#d8e8f0"/>
                        </StackPanel>
                        <TextBlock x:Name="lblEmailStatus" Text="" FontSize="9.5" Foreground="#5a7080" Margin="38,6,0,0" TextWrapping="Wrap"/>
                    </StackPanel>
                </Border>

                <!-- Status Section -->
                <Border x:Name="borderStatus" Background="#f8fafc" CornerRadius="7" Padding="12" Margin="0,0,0,4" BorderBrush="#d8e8f0" BorderThickness="1" Visibility="Collapsed">
                    <StackPanel>
                        <TextBlock Text="DELIVERY STATUS" FontSize="8.5" FontWeight="SemiBold" Foreground="#8a9baa" Margin="0,0,0,6"/>
                        <TextBlock x:Name="lblStatus" Text="" FontSize="11" Foreground="#1a2b3c" TextWrapping="Wrap"/>
                    </StackPanel>
                </Border>
            </StackPanel>
        </ScrollViewer>

        <!-- Footer Buttons -->
        <Border Grid.Row="2" Background="#f0f5f9" Padding="18,10" BorderBrush="#d8e8f0" BorderThickness="0,1,0,0">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <TextBlock Grid.Column="0" VerticalAlignment="Center" FontSize="9.5" Foreground="#5a7080">
                    <Run Text="PC Plus Computing"/>
                    <Run Text=" | "/>
                    <Run Text="pcpluscomputing.com"/>
                </TextBlock>
                <Button x:Name="btnCancel" Grid.Column="1" Style="{StaticResource FlatBtn}" Background="#e2e8f0" Padding="18,8" Margin="0,0,8,0">
                    <TextBlock Text="Cancel" FontSize="11.5" FontWeight="SemiBold" Foreground="#475569"/>
                </Button>
                <Button x:Name="btnSend" Grid.Column="2" Style="{StaticResource FlatBtn}" Background="#2596be" Padding="22,8">
                    <TextBlock Text="Send" FontSize="11.5" FontWeight="SemiBold" Foreground="White"/>
                </Button>
            </Grid>
        </Border>
    </Grid>
</Window>
"@

    try {
        $reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($xaml))
        $dlg = [System.Windows.Markup.XamlReader]::Load($reader)
    }
    catch {
        Write-DiagLog "Failed to load Paperless dialog XAML: $($_.Exception.Message)" "ERROR"
        return $dialogResult
    }

    # Grab controls
    $lblReportFile  = $dlg.FindName("lblReportFile")
    $lblCustomer    = $dlg.FindName("lblCustomer")
    $lblComputer    = $dlg.FindName("lblComputer")
    $chkUpload      = $dlg.FindName("chkUpload")
    $chkEmail       = $dlg.FindName("chkEmail")
    $txtEmail       = $dlg.FindName("txtEmail")
    $lblUploadStatus = $dlg.FindName("lblUploadStatus")
    $lblEmailStatus  = $dlg.FindName("lblEmailStatus")
    $borderStatus   = $dlg.FindName("borderStatus")
    $lblStatus      = $dlg.FindName("lblStatus")
    $btnSend        = $dlg.FindName("btnSend")
    $btnCancel      = $dlg.FindName("btnCancel")

    # Populate initial values
    $lblReportFile.Text = [IO.Path]::GetFileName($ReportPath)
    $lblCustomer.Text   = $CustomerName
    $lblComputer.Text   = $ComputerName
    $txtEmail.Text      = $defaultEmail

    # Pre-check boxes if config has them enabled
    $chkUpload.IsChecked = $config.ServerUpload.Enabled
    $chkEmail.IsChecked  = $config.Email.Enabled

    # Upload status hint
    if (-not $config.ServerUpload.Enabled) {
        $lblUploadStatus.Text = "Server upload is disabled in config. Check the box to upload anyway."
    }
    elseif ([string]::IsNullOrWhiteSpace($config.ServerUpload.ApiKey)) {
        $lblUploadStatus.Text = "Warning: No API key configured. Upload may fail."
        $lblUploadStatus.Foreground = [System.Windows.Media.Brushes]::DarkOrange
    }

    # Email status hint
    if (-not $config.Email.Enabled -or [string]::IsNullOrWhiteSpace($config.Email.SmtpServer)) {
        $lblEmailStatus.Text = "SMTP not configured. Will open default email client as fallback."
    }

    # Helper to update status panel
    $showStatus = {
        param([string]$Text, [string]$Color)
        $borderStatus.Visibility = "Visible"
        $lblStatus.Text = $Text
        $lblStatus.Foreground = if ($Color) {
            [System.Windows.Media.BrushConverter]::new().ConvertFrom($Color)
        } else {
            [System.Windows.Media.Brushes]::SlateGray
        }
        $dlg.Dispatcher.Invoke([Action]{}, [System.Windows.Threading.DispatcherPriority]::Background)
    }

    # Cancel button
    $btnCancel.Add_Click({
        $dlg.Close()
    })

    # Send button
    $btnSend.Add_Click({
        $doUpload = $chkUpload.IsChecked
        $doEmail  = $chkEmail.IsChecked

        if (-not $doUpload -and -not $doEmail) {
            & $showStatus "Please select at least one delivery method." "#dc2626"
            return
        }

        $btnSend.IsEnabled   = $false
        $btnCancel.IsEnabled = $false
        $statusLines = @()

        # Server Upload
        if ($doUpload) {
            & $showStatus "Uploading report to server..." "#2596be"
            $uploadRes = Send-ReportToServer -ReportPath $ReportPath -CustomerName $CustomerName -ComputerName $ComputerName -TechName $TechName -ScanMode $ScanMode
            $dialogResult.ServerResult = $uploadRes
            if ($uploadRes.Success) {
                $statusLines += "Server: Uploaded successfully."
                if ($uploadRes.ViewUrl) { $statusLines += "  View: $($uploadRes.ViewUrl)" }
                $lblUploadStatus.Text = "Uploaded"
                $lblUploadStatus.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#16a34a")
            }
            else {
                $statusLines += "Server: $($uploadRes.Message)"
                $lblUploadStatus.Text = "Failed: $($uploadRes.Message)"
                $lblUploadStatus.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#dc2626")
            }
        }

        # Email
        if ($doEmail) {
            $recipient = $txtEmail.Text.Trim()
            if ([string]::IsNullOrWhiteSpace($recipient)) {
                $statusLines += "Email: No recipient address entered."
                $lblEmailStatus.Text = "No recipient"
                $lblEmailStatus.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#dc2626")
            }
            else {
                & $showStatus (($statusLines + "Sending email...") -join "`n") "#2596be"
                $emailRes = Send-ReportByEmail -ReportPath $ReportPath -RecipientEmail $recipient -CustomerName $CustomerName -TechName $TechName -ScanMode $ScanMode
                $dialogResult.EmailResult = $emailRes
                if ($emailRes.Success -and -not $emailRes.FallbackUsed) {
                    $statusLines += "Email: Sent to $recipient via SMTP."
                    $lblEmailStatus.Text = "Sent"
                    $lblEmailStatus.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#16a34a")
                }
                elseif ($emailRes.Success -and $emailRes.FallbackUsed) {
                    $statusLines += "Email: Opened mail client for $recipient (report path on clipboard)."
                    $lblEmailStatus.Text = "Mail client opened"
                    $lblEmailStatus.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#f59e0b")
                }
                else {
                    $statusLines += "Email: $($emailRes.Message)"
                    $lblEmailStatus.Text = "Failed"
                    $lblEmailStatus.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#dc2626")
                }
            }
        }

        $dialogResult.Cancelled = $false
        $anySuccess = ($dialogResult.ServerResult -and $dialogResult.ServerResult.Success) -or ($dialogResult.EmailResult -and $dialogResult.EmailResult.Success)
        $finalColor = if ($anySuccess) { "#16a34a" } else { "#dc2626" }
        & $showStatus ($statusLines -join "`n") $finalColor

        $btnCancel.IsEnabled = $true
        # Change cancel to "Close" now that we're done
        ($btnCancel.Content).Text = "Close"
        $btnSend.IsEnabled = $true
    })

    $dlg.ShowDialog() | Out-Null
    return $dialogResult
}


# ─────────────────────────────────────────────────────────────────────────────
# GAMING PC / LAPTOP DIAGNOSTIC REPORT (SVG visual graphs, print-ready A4)
# ─────────────────────────────────────────────────────────────────────────────

function Build-GamingPCReport {
    param(
        $Params,          # CustomerName, TechName, ContactName, TechNotes
        $SystemInfo,      # CPU, RAM, GPU, disks, SMART, Temperatures, etc.
        $StressResults,   # CPU, RAM, GPU, Disk stress test results
        $Network,         # Network diagnostics
        $SpeedTest,       # Download/Upload speeds
        $SSDLife,         # Drive health/wear  (.Drives[] with .Model, .LifeRemainingPct, .PowerOnHours, .Grade)
        $Thermal,         # Temperature data   (.CPUTemp, .GPUTemp, .OverheatDetected)
        $Gaming,          # Gaming readiness    (.Score, .Tier, .GPUTier, .CPUTier)
        $BatteryDetail,   # Battery info        (.Present, .HealthPct, .CycleCount)
        $Performance,     # Perf snapshot       (.CPUUsage, .MemUsedGB, .MemTotalGB)
        $FanInfo,         # Fan speeds          (.Fans[] with .Name, .RPM, .MaxRPM)
        $ScanMode         # Which scan was run
    )

    $date = Get-Date -Format "MMMM dd, yyyy 'at' h:mm tt"
    $iconPass = "&#10004;"; $iconFail = "&#10008;"; $iconWarn = "&#9888;"

    # ── Safe accessors ──────────────────────────────────────────────────────
    $customerName   = if ($Params.CustomerName)    { $Params.CustomerName }   else { "Customer" }
    $customerPhone  = if ($Params.CustomerPhone)   { $Params.CustomerPhone }  else { "" }
    $customerEmail  = if ($Params.CustomerEmail)   { $Params.CustomerEmail }  else { "" }
    $techName       = if ($Params.TechName)        { $Params.TechName }       else { "Technician" }
    $contactName    = if ($Params.ContactName)     { $Params.ContactName }    else { "" }

    $cpuModel       = if ($SystemInfo.CPUModel)    { $SystemInfo.CPUModel }   else { "Unknown CPU" }
    $ramTotalGB     = if ($SystemInfo.RAMTotal)     { $SystemInfo.RAMTotal }   else { 0 }
    $gpuName        = if ($SystemInfo.GPUs -and $SystemInfo.GPUs.Count -gt 0) { $SystemInfo.GPUs[0].Name } else { "Unknown GPU" }
    $compName       = if ($SystemInfo.ComputerName) { $SystemInfo.ComputerName } else { "PC" }

    # Stress results (safe)
    $cpuStress  = $StressResults.CPU
    $ramStress  = $StressResults.RAM
    $gpuStress  = $StressResults.GPU
    $diskStress = $StressResults.Disk

    # Thermal (safe)
    $cpuTemp    = if ($Thermal -and $Thermal.CPUTemp)  { [double]$Thermal.CPUTemp }  else { 0 }
    $gpuTemp    = if ($Thermal -and $Thermal.GPUTemp)  { [double]$Thermal.GPUTemp }  else { 0 }
    $overheat   = if ($Thermal) { $Thermal.OverheatDetected } else { $false }

    # SpeedTest (safe)
    $dlMbps     = if ($SpeedTest -and $SpeedTest.DownloadMbps) { [double]($SpeedTest.DownloadMbps -replace '[^\d.]','') } else { 0 }
    $ulMbps     = if ($SpeedTest -and $SpeedTest.UploadMbps)   { [double]($SpeedTest.UploadMbps -replace '[^\d.]','') }  else { 0 }
    $pingMs     = if ($SpeedTest -and $SpeedTest.Ping)         { $SpeedTest.Ping } elseif ($SpeedTest -and $SpeedTest.PingMs) { $SpeedTest.PingMs } else { "N/A" }

    # Gaming (safe)
    $gamingScore = if ($Gaming -and $Gaming.Score) { [int]$Gaming.Score } else { 0 }
    $gamingTier  = if ($Gaming -and $Gaming.Tier)  { $Gaming.Tier }       else { "N/A" }
    $gpuTier     = if ($Gaming -and $Gaming.GPUTier) { $Gaming.GPUTier }  else { "N/A" }
    $cpuTier     = if ($Gaming -and $Gaming.CPUTier) { $Gaming.CPUTier }  else { "N/A" }

    # Performance (safe)
    $cpuUsage    = if ($Performance -and $Performance.CPUUsage -ne $null)  { [double]$Performance.CPUUsage }  else { 0 }
    $memUsedGB   = if ($Performance -and $Performance.MemUsedGB -ne $null) { [double]$Performance.MemUsedGB } else { 0 }
    $memTotalGB  = if ($Performance -and $Performance.MemTotalGB -ne $null){ [double]$Performance.MemTotalGB} else { if ($ramTotalGB -gt 0) { $ramTotalGB } else { 1 } }

    # Battery (safe)
    $battPresent = if ($BatteryDetail -and $BatteryDetail.Present) { $true } else { $false }
    $battHealth  = if ($battPresent -and $BatteryDetail.HealthPct) { [int]$BatteryDetail.HealthPct } else { 0 }
    $battCycles  = if ($battPresent -and $BatteryDetail.CycleCount) { $BatteryDetail.CycleCount } else { "N/A" }

    # SSD Life (safe)
    $ssdDrives   = if ($SSDLife -and $SSDLife.Drives) { @($SSDLife.Drives) } else { @() }

    # FanInfo (safe)
    $fans        = if ($FanInfo -and $FanInfo.Fans) { @($FanInfo.Fans) } else { @() }

    # ── Compute component health scores ─────────────────────────────────────
    $cpuHealth = 100
    if ($cpuStress -and -not $cpuStress.Passed) { $cpuHealth -= 40 }
    if ($cpuTemp -gt 85) { $cpuHealth -= 30 } elseif ($cpuTemp -gt 70) { $cpuHealth -= 15 }
    if ($cpuStress -and $cpuStress.ThrottleDetected) { $cpuHealth -= 20 }
    $cpuHealth = [math]::Max($cpuHealth, 0)

    $ramHealth = 100
    if ($ramStress -and -not $ramStress.Passed) { $ramHealth -= 50 }
    if ($ramStress -and $ramStress.Errors -gt 0) { $ramHealth -= 20 }
    if ($memTotalGB -gt 0 -and ($memUsedGB / $memTotalGB) -gt 0.95) { $ramHealth -= 15 }
    $ramHealth = [math]::Max($ramHealth, 0)

    $gpuHealth = 100
    if ($gpuStress -and -not $gpuStress.Passed) { $gpuHealth -= 40 }
    if ($gpuTemp -gt 85) { $gpuHealth -= 30 } elseif ($gpuTemp -gt 70) { $gpuHealth -= 15 }
    $gpuHealth = [math]::Max($gpuHealth, 0)

    $storageHealth = 100
    if ($ssdDrives.Count -gt 0) {
        $avgLife = ($ssdDrives | ForEach-Object { if ($_.LifeRemainingPct) { [int]$_.LifeRemainingPct } else { 100 } } | Measure-Object -Average).Average
        $storageHealth = [math]::Round($avgLife)
    }
    if ($diskStress -and -not $diskStress.Passed) { $storageHealth -= 20 }
    foreach ($d in $SystemInfo.SMART) { if ($d.Health -ne "Healthy") { $storageHealth -= 25 } }
    $storageHealth = [math]::Max([math]::Min($storageHealth, 100), 0)

    $networkHealth = 100
    if ($Network -and -not $Network.InternetTest.Success) { $networkHealth -= 40 }
    if ($dlMbps -gt 0 -and $dlMbps -lt 10) { $networkHealth -= 20 } elseif ($dlMbps -gt 0 -and $dlMbps -lt 25) { $networkHealth -= 10 }
    if ($SpeedTest -and $SpeedTest.PacketLoss -and $SpeedTest.PacketLoss -ne "0%" -and $SpeedTest.PacketLoss -ne "N/A") {
        $lv = [int]($SpeedTest.PacketLoss -replace '%','')
        if ($lv -ge 5) { $networkHealth -= 20 }
    }
    $networkHealth = [math]::Max($networkHealth, 0)

    $batteryHealth = if ($battPresent) { $battHealth } else { 100 }

    # Overall score (weighted)
    $overallScore = [math]::Round(
        ($cpuHealth * 0.20) + ($ramHealth * 0.15) + ($gpuHealth * 0.20) +
        ($storageHealth * 0.20) + ($networkHealth * 0.10) +
        ($(if ($battPresent) { $batteryHealth * 0.15 } else { 100 * 0.15 }))
    )
    $overallScore = [math]::Max([math]::Min($overallScore, 100), 0)
    $overallGrade = if ($overallScore -ge 90){"A"} elseif ($overallScore -ge 80){"B"} elseif ($overallScore -ge 70){"C"} elseif ($overallScore -ge 60){"D"} else {"F"}
    $overallColor = if ($overallScore -ge 80){"#22c55e"} elseif ($overallScore -ge 60){"#f59e0b"} else {"#dc2626"}

    # ── Helper: badge ───────────────────────────────────────────────────────
    function Get-GamingBadge($score) {
        if ($score -ge 80) { return @{ Text="PASS"; Color="#16a34a"; Bg="#dcfce7" } }
        elseif ($score -ge 60) { return @{ Text="WARNING"; Color="#92400e"; Bg="#fef3c7" } }
        else { return @{ Text="FAIL"; Color="#991b1b"; Bg="#fee2e2" } }
    }

    # ── Load logo ───────────────────────────────────────────────────────────
    $logoDataUri = ""
    $logoPath = Join-Path $Global:ScriptDir "logo-base64.txt"
    if (Test-Path $logoPath) {
        try { $logoDataUri = "data:image/png;base64,$((Get-Content $logoPath -Raw).Trim())" } catch {}
    }
    $logoHTML = if ($logoDataUri) {
        "<img src='$logoDataUri' alt='PC Plus Computing' style='width:320px;max-width:85%;'/>"
    } else {
        "<div style='background:linear-gradient(135deg,#0a1628,#0d4b71);color:#fff;padding:16px 40px;font-size:20pt;font-weight:bold;letter-spacing:3px;border-radius:8px;display:inline-block;'>PC PLUS COMPUTING</div>"
    }

    # ── Load QR codes ───────────────────────────────────────────────────────
    $qrAppUri = ""; $qrSvcUri = ""
    $qrAppPath = Join-Path $Global:ScriptDir "qr-appointments.txt"
    $qrSvcPath = Join-Path $Global:ScriptDir "qr-service-requests.txt"
    if (Test-Path $qrAppPath) { try { $qrAppUri = "data:image/png;base64,$((Get-Content $qrAppPath -Raw).Trim())" } catch {} }
    if (Test-Path $qrSvcPath) { try { $qrSvcUri = "data:image/png;base64,$((Get-Content $qrSvcPath -Raw).Trim())" } catch {} }

    # ── Load gaming banner ──────────────────────────────────────────────────
    $bannerGamingUri = ""
    $bgPath = Join-Path $Global:ScriptDir "banner-gaming-top.txt"
    if (Test-Path $bgPath) { try { $bannerGamingUri = "data:image/jpeg;base64,$((Get-Content $bgPath -Raw).Trim())" } catch {} }

    # ══════════════════════════════════════════════════════════════════════════
    # SVG CHART BUILDERS
    # ══════════════════════════════════════════════════════════════════════════

    # ── 1. System Health Donut ──────────────────────────────────────────────
    $donutR = 45; $donutCirc = [math]::Round(2 * [math]::PI * $donutR, 1)
    $donutOffset = [math]::Round($donutCirc - ($donutCirc * $overallScore / 100), 1)
    $svgHealthDonut = @"
<svg viewBox="0 0 200 200" width="180" height="180" xmlns="http://www.w3.org/2000/svg">
  <circle cx="100" cy="100" r="$donutR" fill="none" stroke="#1a1a2e" stroke-width="3" opacity="0.1"/>
  <circle cx="100" cy="100" r="$donutR" fill="none" stroke="#e5e7eb" stroke-width="12"/>
  <circle cx="100" cy="100" r="$donutR" fill="none" stroke="$overallColor" stroke-width="12"
    stroke-dasharray="$donutCirc" stroke-dashoffset="$donutOffset"
    transform="rotate(-90 100 100)" stroke-linecap="round"/>
  <text x="100" y="90" text-anchor="middle" font-size="36" font-weight="bold" fill="$overallColor" font-family="Segoe UI,sans-serif">$overallGrade</text>
  <text x="100" y="112" text-anchor="middle" font-size="14" fill="#64748b" font-family="Segoe UI,sans-serif">$overallScore / 100</text>
  <text x="100" y="132" text-anchor="middle" font-size="11" fill="#94a3b8" font-family="Segoe UI,sans-serif">System Health</text>
</svg>
"@

    # ── 2. Temperature Bar Chart ────────────────────────────────────────────
    $tempBars = @()
    if ($cpuTemp -gt 0) { $tempBars += @{ Label="CPU"; Temp=$cpuTemp } }
    if ($gpuTemp -gt 0) { $tempBars += @{ Label="GPU"; Temp=$gpuTemp } }
    if ($SystemInfo.Temperatures) {
        foreach ($t in $SystemInfo.Temperatures) {
            if ($t.Zone -notmatch "CPU|GPU" -and $t.TempC -gt 0) {
                $tempBars += @{ Label=$t.Zone; Temp=[double]$t.TempC }
            }
        }
    }
    $tempBarCount = $tempBars.Count
    if ($tempBarCount -eq 0) { $tempBarCount = 1; $tempBars += @{ Label="N/A"; Temp=0 } }
    $tempSvgH = 40 + ($tempBarCount * 45)
    $tempBarSVG = "<svg viewBox='0 0 500 $tempSvgH' width='100%' height='${tempSvgH}px' xmlns='http://www.w3.org/2000/svg'>`n"
    $tempBarSVG += "  <rect x='300' y='5' width='12' height='12' rx='2' fill='#22c55e'/><text x='316' y='15' font-size='10' fill='#64748b' font-family='Segoe UI,sans-serif'>&lt;70C Safe</text>`n"
    $tempBarSVG += "  <rect x='370' y='5' width='12' height='12' rx='2' fill='#f59e0b'/><text x='386' y='15' font-size='10' fill='#64748b' font-family='Segoe UI,sans-serif'>70-85C Warm</text>`n"
    $tempBarSVG += "  <rect x='448' y='5' width='12' height='12' rx='2' fill='#dc2626'/><text x='464' y='15' font-size='10' fill='#64748b' font-family='Segoe UI,sans-serif'>&gt;85C Hot</text>`n"
    $yOff = 35
    foreach ($tb in $tempBars) {
        $tColor = if ($tb.Temp -lt 70) { "#22c55e" } elseif ($tb.Temp -le 85) { "#f59e0b" } else { "#dc2626" }
        $barW = [math]::Min([math]::Round($tb.Temp / 110 * 380), 380)
        $tempBarSVG += "  <text x='0' y='$($yOff + 16)' font-size='12' font-weight='600' fill='#334155' font-family='Segoe UI,sans-serif'>$($tb.Label)</text>`n"
        $tempBarSVG += "  <rect x='60' y='$($yOff + 2)' width='380' height='22' rx='4' fill='#e5e7eb'/>`n"
        if ($barW -gt 0) {
            $tempBarSVG += "  <rect x='60' y='$($yOff + 2)' width='$barW' height='22' rx='4' fill='$tColor'/>`n"
        }
        $line70 = [math]::Round(70 / 110 * 380) + 60
        $line85 = [math]::Round(85 / 110 * 380) + 60
        $tempBarSVG += "  <line x1='$line70' y1='$($yOff)' x2='$line70' y2='$($yOff + 26)' stroke='#f59e0b' stroke-width='1.5' stroke-dasharray='3,2'/>`n"
        $tempBarSVG += "  <line x1='$line85' y1='$($yOff)' x2='$line85' y2='$($yOff + 26)' stroke='#dc2626' stroke-width='1.5' stroke-dasharray='3,2'/>`n"
        $tempBarSVG += "  <text x='$($barW + 65)' y='$($yOff + 17)' font-size='11' font-weight='700' fill='$tColor' font-family='Segoe UI,sans-serif'>$($tb.Temp)&#176;C</text>`n"
        $yOff += 45
    }
    $tempBarSVG += "</svg>"

    # ── 3. Storage Read/Write Speed Bar Chart ───────────────────────────────
    $seqRead  = if ($diskStress -and $diskStress.SeqReadMBps)  { [double]$diskStress.SeqReadMBps }  else { 0 }
    $seqWrite = if ($diskStress -and $diskStress.SeqWriteMBps) { [double]$diskStress.SeqWriteMBps } else { 0 }
    $maxSpeed = [math]::Max([math]::Max($seqRead, $seqWrite), 600)
    $speedScale = 420 / $maxSpeed
    $readBarW  = [math]::Round($seqRead * $speedScale)
    $writeBarW = [math]::Round($seqWrite * $speedScale)
    $hddLine   = [math]::Round(100 * $speedScale) + 60
    $ssdLine   = [math]::Min([math]::Round(500 * $speedScale) + 60, 475)

    $storageSVG = @"
<svg viewBox='0 0 500 160' width='100%' height='160px' xmlns='http://www.w3.org/2000/svg'>
  <rect x='300' y='5' width='12' height='12' rx='2' fill='#2596be'/><text x='316' y='15' font-size='10' fill='#64748b' font-family='Segoe UI,sans-serif'>Sequential Read</text>
  <rect x='410' y='5' width='12' height='12' rx='2' fill='#3bbde0'/><text x='426' y='15' font-size='10' fill='#64748b' font-family='Segoe UI,sans-serif'>Sequential Write</text>
  <text x='0' y='50' font-size='12' font-weight='600' fill='#334155' font-family='Segoe UI,sans-serif'>Read</text>
  <rect x='60' y='36' width='420' height='22' rx='4' fill='#e5e7eb'/>
  <rect x='60' y='36' width='$readBarW' height='22' rx='4' fill='#2596be'/>
  <text x='$($readBarW + 65)' y='52' font-size='11' font-weight='700' fill='#2596be' font-family='Segoe UI,sans-serif'>$seqRead MB/s</text>
  <text x='0' y='95' font-size='12' font-weight='600' fill='#334155' font-family='Segoe UI,sans-serif'>Write</text>
  <rect x='60' y='81' width='420' height='22' rx='4' fill='#e5e7eb'/>
  <rect x='60' y='81' width='$writeBarW' height='22' rx='4' fill='#3bbde0'/>
  <text x='$($writeBarW + 65)' y='97' font-size='11' font-weight='700' fill='#3bbde0' font-family='Segoe UI,sans-serif'>$seqWrite MB/s</text>
  <line x1='$hddLine' y1='30' x2='$hddLine' y2='108' stroke='#94a3b8' stroke-width='1' stroke-dasharray='4,3'/>
  <text x='$($hddLine + 2)' y='120' font-size='8' fill='#94a3b8' font-family='Segoe UI,sans-serif'>Good HDD</text>
  <text x='$($hddLine + 2)' y='130' font-size='8' fill='#94a3b8' font-family='Segoe UI,sans-serif'>100 MB/s</text>
  <line x1='$ssdLine' y1='30' x2='$ssdLine' y2='108' stroke='#2596be' stroke-width='1' stroke-dasharray='4,3'/>
  <text x='$([math]::Min($ssdLine + 2, 455))' y='120' font-size='8' fill='#2596be' font-family='Segoe UI,sans-serif'>Good SSD</text>
  <text x='$([math]::Min($ssdLine + 2, 455))' y='130' font-size='8' fill='#2596be' font-family='Segoe UI,sans-serif'>500 MB/s</text>
  <text x='60' y='150' font-size='8' fill='#94a3b8' font-family='Segoe UI,sans-serif'>0</text>
  <text x='$([math]::Round($maxSpeed/2 * $speedScale) + 55)' y='150' font-size='8' fill='#94a3b8' font-family='Segoe UI,sans-serif' text-anchor='middle'>$([math]::Round($maxSpeed/2)) MB/s</text>
  <text x='475' y='150' font-size='8' fill='#94a3b8' font-family='Segoe UI,sans-serif' text-anchor='end'>$([math]::Round($maxSpeed)) MB/s</text>
</svg>
"@

    # ── 4. Network Speed Gauge (semi-circle) ────────────────────────────────
    $maxDl = [math]::Max($dlMbps, 100)
    if ($dlMbps -gt 100) { $maxDl = [math]::Ceiling($dlMbps / 50) * 50 }
    $gaugeR = 70
    $gaugeCirc = [math]::Round([math]::PI * $gaugeR, 1)
    $dlDash = [math]::Round($gaugeCirc * [math]::Min($dlMbps / $maxDl, 1), 1)
    $ulDash = [math]::Round($gaugeCirc * [math]::Min($ulMbps / $maxDl, 1), 1)
    $dlColor = if ($dlMbps -ge 100) { "#22c55e" } elseif ($dlMbps -ge 25) { "#2596be" } elseif ($dlMbps -gt 0) { "#f59e0b" } else { "#94a3b8" }
    $ulColor = if ($ulMbps -ge 50) { "#22c55e" } elseif ($ulMbps -ge 10) { "#3bbde0" } elseif ($ulMbps -gt 0) { "#f59e0b" } else { "#94a3b8" }

    $networkGaugeSVG = @"
<svg viewBox='0 0 440 180' width='100%' height='180px' xmlns='http://www.w3.org/2000/svg'>
  <text x='110' y='16' text-anchor='middle' font-size='11' font-weight='600' fill='#334155' font-family='Segoe UI,sans-serif'>Download</text>
  <path d='M 30,150 A $gaugeR,$gaugeR 0 0 1 190,150' fill='none' stroke='#e5e7eb' stroke-width='14' stroke-linecap='round'/>
  <path d='M 30,150 A $gaugeR,$gaugeR 0 0 1 190,150' fill='none' stroke='$dlColor' stroke-width='14' stroke-linecap='round'
    stroke-dasharray='$dlDash $gaugeCirc'/>
  <text x='110' y='130' text-anchor='middle' font-size='28' font-weight='bold' fill='$dlColor' font-family='Segoe UI,sans-serif'>$([math]::Round($dlMbps,1))</text>
  <text x='110' y='148' text-anchor='middle' font-size='11' fill='#64748b' font-family='Segoe UI,sans-serif'>Mbps</text>
  <text x='25' y='168' font-size='8' fill='#94a3b8' font-family='Segoe UI,sans-serif'>0</text>
  <text x='190' y='168' font-size='8' fill='#94a3b8' font-family='Segoe UI,sans-serif' text-anchor='end'>$maxDl</text>
  <text x='330' y='16' text-anchor='middle' font-size='11' font-weight='600' fill='#334155' font-family='Segoe UI,sans-serif'>Upload</text>
  <path d='M 250,150 A $gaugeR,$gaugeR 0 0 1 410,150' fill='none' stroke='#e5e7eb' stroke-width='14' stroke-linecap='round'/>
  <path d='M 250,150 A $gaugeR,$gaugeR 0 0 1 410,150' fill='none' stroke='$ulColor' stroke-width='14' stroke-linecap='round'
    stroke-dasharray='$ulDash $gaugeCirc'/>
  <text x='330' y='130' text-anchor='middle' font-size='28' font-weight='bold' fill='$ulColor' font-family='Segoe UI,sans-serif'>$([math]::Round($ulMbps,1))</text>
  <text x='330' y='148' text-anchor='middle' font-size='11' fill='#64748b' font-family='Segoe UI,sans-serif'>Mbps</text>
  <text x='245' y='168' font-size='8' fill='#94a3b8' font-family='Segoe UI,sans-serif'>0</text>
  <text x='410' y='168' font-size='8' fill='#94a3b8' font-family='Segoe UI,sans-serif' text-anchor='end'>$maxDl</text>
</svg>
"@

    # ── 5. Component Health Grid (3x2 mini donuts) ──────────────────────────
    function Build-GamingMiniDonut($score, $label, $cx, $cy) {
        $r = 30; $c = [math]::Round(2 * [math]::PI * $r, 1)
        $off = [math]::Round($c - ($c * $score / 100), 1)
        $col = if ($score -ge 80) { "#22c55e" } elseif ($score -ge 60) { "#f59e0b" } else { "#dc2626" }
        $grade = if ($score -ge 90){"A"} elseif($score -ge 80){"B"} elseif($score -ge 70){"C"} elseif($score -ge 60){"D"} else{"F"}
        $bd = Get-GamingBadge $score
        return @"
  <circle cx='$cx' cy='$cy' r='$r' fill='none' stroke='#e5e7eb' stroke-width='6'/>
  <circle cx='$cx' cy='$cy' r='$r' fill='none' stroke='$col' stroke-width='6'
    stroke-dasharray='$c' stroke-dashoffset='$off'
    transform='rotate(-90 $cx $cy)' stroke-linecap='round'/>
  <text x='$cx' y='$($cy - 2)' text-anchor='middle' font-size='16' font-weight='bold' fill='$col' font-family='Segoe UI,sans-serif'>$grade</text>
  <text x='$cx' y='$($cy + 12)' text-anchor='middle' font-size='8' fill='#64748b' font-family='Segoe UI,sans-serif'>$score%</text>
  <text x='$cx' y='$($cy + 48)' text-anchor='middle' font-size='10' font-weight='600' fill='#334155' font-family='Segoe UI,sans-serif'>$label</text>
  <rect x='$($cx - 24)' y='$($cy + 53)' width='48' height='16' rx='8' fill='$($bd.Bg)'/>
  <text x='$cx' y='$($cy + 64)' text-anchor='middle' font-size='7' font-weight='700' fill='$($bd.Color)' font-family='Segoe UI,sans-serif'>$($bd.Text)</text>
"@
    }

    $healthGridSVG = "<svg viewBox='0 0 500 260' width='100%' height='260px' xmlns='http://www.w3.org/2000/svg'>`n"
    $healthGridSVG += Build-GamingMiniDonut $cpuHealth "CPU Health" 85 55
    $healthGridSVG += Build-GamingMiniDonut $ramHealth "RAM Health" 250 55
    $healthGridSVG += Build-GamingMiniDonut $gpuHealth "GPU Health" 415 55
    $healthGridSVG += Build-GamingMiniDonut $storageHealth "Storage" 85 185
    $healthGridSVG += Build-GamingMiniDonut $networkHealth "Network" 250 185
    $battLabel = if ($battPresent) { "Battery" } else { "Battery (N/A)" }
    $healthGridSVG += Build-GamingMiniDonut $batteryHealth $battLabel 415 185
    $healthGridSVG += "</svg>"

    # ── 6. RAM Usage Stacked Bar ────────────────────────────────────────────
    $ramUsedPct = if ($memTotalGB -gt 0) { [math]::Round($memUsedGB / $memTotalGB * 100) } else { 0 }
    $ramFreeGB  = [math]::Round($memTotalGB - $memUsedGB, 1)
    $ramBarClr  = if ($ramUsedPct -gt 90) { "#dc2626" } elseif ($ramUsedPct -gt 70) { "#f59e0b" } else { "#2596be" }
    $ramUsedW   = [math]::Round($ramUsedPct / 100 * 400)

    $ramBarSVG = @"
<svg viewBox='0 0 500 70' width='100%' height='70px' xmlns='http://www.w3.org/2000/svg'>
  <rect x='50' y='12' width='400' height='28' rx='6' fill='#e5e7eb'/>
  <rect x='50' y='12' width='$ramUsedW' height='28' rx='6' fill='$ramBarClr'/>
  <text x='$([math]::Round($ramUsedW / 2) + 50)' y='31' text-anchor='middle' font-size='11' font-weight='bold' fill='#fff' font-family='Segoe UI,sans-serif'>Used: $memUsedGB GB ($ramUsedPct%)</text>
  $(if ((100 - $ramUsedPct) -gt 15) { "<text x='$([math]::Round($ramUsedW + (400 - $ramUsedW) / 2) + 50)' y='31' text-anchor='middle' font-size='10' fill='#64748b' font-family='Segoe UI,sans-serif'>Free: $ramFreeGB GB</text>" })
  <text x='50' y='58' font-size='9' fill='#64748b' font-family='Segoe UI,sans-serif'>0 GB</text>
  <text x='450' y='58' font-size='9' fill='#64748b' font-family='Segoe UI,sans-serif' text-anchor='end'>$memTotalGB GB</text>
  <text x='0' y='31' font-size='11' font-weight='600' fill='#334155' font-family='Segoe UI,sans-serif'>RAM</text>
  <rect x='300' y='50' width='10' height='10' rx='2' fill='$ramBarClr'/><text x='314' y='59' font-size='8' fill='#64748b' font-family='Segoe UI,sans-serif'>Used</text>
  <rect x='350' y='50' width='10' height='10' rx='2' fill='#e5e7eb'/><text x='364' y='59' font-size='8' fill='#64748b' font-family='Segoe UI,sans-serif'>Free</text>
</svg>
"@

    # ── 7. Fan Speed Indicators ─────────────────────────────────────────────
    $fanSVG = ""
    if ($fans.Count -gt 0) {
        $fanW = [math]::Min(160, [math]::Floor(480 / [math]::Max($fans.Count, 1)))
        $totalW = $fanW * $fans.Count
        $fanSVG = "<svg viewBox='0 0 $totalW 110' width='100%' height='110px' xmlns='http://www.w3.org/2000/svg'>`n"
        $fx = 0
        foreach ($fan in $fans) {
            $fRPM    = if ($fan.RPM)    { [int]$fan.RPM }    else { 0 }
            $fMaxRPM = if ($fan.MaxRPM) { [int]$fan.MaxRPM } else { [math]::Max($fRPM, 3000) }
            $fName   = if ($fan.Name)   { $fan.Name }        else { "Fan" }
            $fPct    = if ($fMaxRPM -gt 0) { [math]::Round($fRPM / $fMaxRPM * 100) } else { 0 }
            $fColor  = if ($fPct -gt 90) { "#dc2626" } elseif ($fPct -gt 60) { "#f59e0b" } else { "#22c55e" }
            $fR = 32; $fCirc = [math]::Round(2 * [math]::PI * $fR, 1)
            $fOff = [math]::Round($fCirc - ($fCirc * $fPct / 100), 1)
            $cx = $fx + [math]::Round($fanW / 2)
            $fanSVG += "  <circle cx='$cx' cy='42' r='$fR' fill='none' stroke='#e5e7eb' stroke-width='6'/>`n"
            $fanSVG += "  <circle cx='$cx' cy='42' r='$fR' fill='none' stroke='$fColor' stroke-width='6' stroke-dasharray='$fCirc' stroke-dashoffset='$fOff' transform='rotate(-90 $cx 42)' stroke-linecap='round'/>`n"
            $fanSVG += "  <text x='$cx' y='40' text-anchor='middle' font-size='11' font-weight='bold' fill='$fColor' font-family='Segoe UI,sans-serif'>$fRPM</text>`n"
            $fanSVG += "  <text x='$cx' y='52' text-anchor='middle' font-size='8' fill='#64748b' font-family='Segoe UI,sans-serif'>RPM</text>`n"
            $fanSVG += "  <text x='$cx' y='95' text-anchor='middle' font-size='9' font-weight='600' fill='#334155' font-family='Segoe UI,sans-serif'>$fName</text>`n"
            $fanSVG += "  <text x='$cx' y='107' text-anchor='middle' font-size='7' fill='#94a3b8' font-family='Segoe UI,sans-serif'>max $fMaxRPM</text>`n"
            $fx += $fanW
        }
        $fanSVG += "</svg>"
    }

    # ══════════════════════════════════════════════════════════════════════════
    # BUILD DETAIL SECTIONS
    # ══════════════════════════════════════════════════════════════════════════

    # Stress test summary rows
    $stressRows = ""
    if ($cpuStress) {
        $badge = if ($cpuStress.Passed) { "<span style='display:inline-block;padding:2px 10px;border-radius:10px;font-size:8pt;font-weight:700;background:#dcfce7;color:#166534;'>$iconPass PASS</span>" } else { "<span style='display:inline-block;padding:2px 10px;border-radius:10px;font-size:8pt;font-weight:700;background:#fee2e2;color:#991b1b;'>$iconFail FAIL</span>" }
        $throttle = if ($cpuStress.ThrottleDetected) { "<br/><span class='fail'>$iconWarn THROTTLING</span>" } else { "" }
        $stressRows += "<tr><td>CPU Stress</td><td>$badge$throttle</td><td>Peak: $($cpuStress.MaxTemp)C | $($cpuStress.Iterations) iterations | $($cpuStress.Duration)s</td></tr>`n"
    }
    if ($ramStress) {
        $badge = if ($ramStress.Passed) { "<span style='display:inline-block;padding:2px 10px;border-radius:10px;font-size:8pt;font-weight:700;background:#dcfce7;color:#166534;'>$iconPass PASS</span>" } else { "<span style='display:inline-block;padding:2px 10px;border-radius:10px;font-size:8pt;font-weight:700;background:#fee2e2;color:#991b1b;'>$iconFail FAIL</span>" }
        $stressRows += "<tr><td>RAM Stress</td><td>$badge</td><td>$($ramStress.TotalMBTested) MB tested | $($ramStress.Errors) errors</td></tr>`n"
    }
    if ($gpuStress) {
        $badge = if ($gpuStress.Passed) { "<span style='display:inline-block;padding:2px 10px;border-radius:10px;font-size:8pt;font-weight:700;background:#dcfce7;color:#166534;'>$iconPass PASS</span>" } else { "<span style='display:inline-block;padding:2px 10px;border-radius:10px;font-size:8pt;font-weight:700;background:#fee2e2;color:#991b1b;'>$iconFail FAIL</span>" }
        $stressRows += "<tr><td>GPU Stress</td><td>$badge</td><td>$($gpuStress.GPUName) | Peak: $($gpuStress.MaxTemp)C | $($gpuStress.Iterations) cycles</td></tr>`n"
    }
    if ($diskStress) {
        $badge = if ($diskStress.Passed) { "<span style='display:inline-block;padding:2px 10px;border-radius:10px;font-size:8pt;font-weight:700;background:#dcfce7;color:#166534;'>$iconPass PASS</span>" } else { "<span style='display:inline-block;padding:2px 10px;border-radius:10px;font-size:8pt;font-weight:700;background:#fee2e2;color:#991b1b;'>$iconFail FAIL</span>" }
        $stressRows += "<tr><td>Disk Benchmark</td><td>$badge</td><td>Read: $seqRead MB/s | Write: $seqWrite MB/s</td></tr>`n"
    }

    # SSD life table rows
    $ssdRows = ""
    foreach ($drv in $ssdDrives) {
        $dModel = if ($drv.Model) { $drv.Model } else { "Unknown" }
        $dLife  = if ($drv.LifeRemainingPct -ne $null) { [int]$drv.LifeRemainingPct } else { 100 }
        $dHours = if ($drv.PowerOnHours) { $drv.PowerOnHours } else { "N/A" }
        $dGrade = if ($drv.Grade) { $drv.Grade } else { if ($dLife -ge 80){"Good"} elseif($dLife -ge 50){"Fair"} else{"Poor"} }
        $dColor = if ($dLife -ge 80) { "#22c55e" } elseif ($dLife -ge 50) { "#f59e0b" } else { "#dc2626" }
        $dBadge = if ($dLife -ge 80) { "<span style='display:inline-block;padding:2px 10px;border-radius:10px;font-size:8pt;font-weight:700;background:#dcfce7;color:#166534;'>$dGrade</span>" } elseif ($dLife -ge 50) { "<span style='display:inline-block;padding:2px 10px;border-radius:10px;font-size:8pt;font-weight:700;background:#fef3c7;color:#92400e;'>$dGrade</span>" } else { "<span style='display:inline-block;padding:2px 10px;border-radius:10px;font-size:8pt;font-weight:700;background:#fee2e2;color:#991b1b;'>$dGrade</span>" }
        $ssdRows += "<tr><td>$dModel</td><td style='width:180px;'><div style='display:flex;align-items:center;gap:6px;'><div style='flex:1;background:#e5e7eb;border-radius:4px;height:10px;overflow:hidden;'><div style='width:${dLife}%;height:100%;background:$dColor;border-radius:4px;'></div></div><span style='font-weight:700;color:$dColor;font-size:9pt;min-width:32px;'>$dLife%</span></div></td><td>$dHours hrs</td><td>$dBadge</td></tr>`n"
    }

    # Gaming readiness section
    $gamingHTML = ""
    if ($gamingScore -gt 0) {
        $gmColor = if ($gamingScore -ge 80){"#22c55e"} elseif ($gamingScore -ge 60){"#2596be"} elseif ($gamingScore -ge 40){"#f59e0b"} else {"#dc2626"}
        $gmR = 40; $gmCirc = [math]::Round(2 * [math]::PI * $gmR, 1)
        $gmOff = [math]::Round($gmCirc - ($gmCirc * $gamingScore / 100), 1)
        $gamingHTML = @"
<div class='section-header'><span class='section-icon'>&#127918;</span> Gaming Readiness</div>
<div style='display:flex;align-items:center;gap:24px;margin-bottom:14px;'>
<div style='text-align:center;'>
<svg viewBox='0 0 100 100' width='110' height='110' xmlns='http://www.w3.org/2000/svg'>
<circle cx='50' cy='50' r='$gmR' fill='none' stroke='#e5e7eb' stroke-width='7'/>
<circle cx='50' cy='50' r='$gmR' fill='none' stroke='$gmColor' stroke-width='7'
  stroke-dasharray='$gmCirc' stroke-dashoffset='$gmOff'
  transform='rotate(-90 50 50)' stroke-linecap='round'/>
<text x='50' y='46' text-anchor='middle' font-size='18' font-weight='bold' fill='$gmColor' font-family='Segoe UI,sans-serif'>$gamingScore</text>
<text x='50' y='60' text-anchor='middle' font-size='9' fill='#64748b' font-family='Segoe UI,sans-serif'>/ 100</text>
</svg>
<div style='font-size:12pt;font-weight:700;color:$gmColor;margin-top:4px;'>$gamingTier</div>
</div>
<div style='flex:1;'>
<table><tr><th>Component</th><th>Tier</th></tr>
<tr><td>GPU Gaming Tier</td><td style='font-weight:700;color:$gmColor;'>$gpuTier</td></tr>
<tr><td>CPU Gaming Tier</td><td style='font-weight:700;color:$gmColor;'>$cpuTier</td></tr>
$(if($Gaming.GPUName){"<tr><td>GPU</td><td>$($Gaming.GPUName)</td></tr>"})
$(if($Gaming.VRAM_MB){"<tr><td>VRAM</td><td>$($Gaming.VRAM_MB) MB</td></tr>"})
$(if($Gaming.TotalRAM){"<tr><td>System RAM</td><td>$($Gaming.TotalRAM) GB</td></tr>"})
$(if($Gaming.DirectXVersion){"<tr><td>DirectX</td><td>$($Gaming.DirectXVersion)</td></tr>"})
$(if($Gaming.RefreshRate){"<tr><td>Refresh Rate</td><td>$($Gaming.RefreshRate)</td></tr>"})
</table>
</div>
</div>
"@
    }

    # Battery section
    $batteryHTML = ""
    if ($battPresent) {
        $btColor = if ($battHealth -ge 80) { "#22c55e" } elseif ($battHealth -ge 50) { "#f59e0b" } else { "#dc2626" }
        $btR = 35; $btCirc = [math]::Round(2 * [math]::PI * $btR, 1)
        $btOff = [math]::Round($btCirc - ($btCirc * $battHealth / 100), 1)
        $btBdg = Get-GamingBadge $battHealth
        $batteryHTML = @"
<div class='sub-header'>Battery Health</div>
<div style='display:flex;align-items:center;gap:20px;margin-bottom:14px;'>
<div style='text-align:center;'>
<svg viewBox='0 0 100 100' width='90' height='90' xmlns='http://www.w3.org/2000/svg'>
<circle cx='50' cy='50' r='$btR' fill='none' stroke='#e5e7eb' stroke-width='7'/>
<circle cx='50' cy='50' r='$btR' fill='none' stroke='$btColor' stroke-width='7'
  stroke-dasharray='$btCirc' stroke-dashoffset='$btOff'
  transform='rotate(-90 50 50)' stroke-linecap='round'/>
<text x='50' y='48' text-anchor='middle' font-size='16' font-weight='bold' fill='$btColor' font-family='Segoe UI,sans-serif'>$battHealth%</text>
<text x='50' y='62' text-anchor='middle' font-size='8' fill='#64748b' font-family='Segoe UI,sans-serif'>Health</text>
</svg>
</div>
<div style='flex:1;'>
<table><tr><th style='width:40%;'>Property</th><th>Value</th></tr>
<tr><td>Battery Health</td><td style='color:$btColor;font-weight:700;'>$battHealth%
  <span style='display:inline-block;padding:2px 8px;border-radius:10px;font-size:7.5pt;font-weight:700;background:$($btBdg.Bg);color:$($btBdg.Color);margin-left:6px;'>$($btBdg.Text)</span></td></tr>
<tr><td>Cycle Count</td><td>$battCycles</td></tr>
$(if($BatteryDetail.Charge){"<tr><td>Current Charge</td><td>$($BatteryDetail.Charge)%</td></tr>"})
$(if($BatteryDetail.DesignCapacity){"<tr><td>Design Capacity</td><td>$($BatteryDetail.DesignCapacity) mWh</td></tr>"})
$(if($BatteryDetail.FullChargeCapacity){"<tr><td>Full Charge Capacity</td><td>$($BatteryDetail.FullChargeCapacity) mWh</td></tr>"})
$(if($BatteryDetail.Runtime){"<tr><td>Estimated Runtime</td><td>$($BatteryDetail.Runtime)</td></tr>"})
</table>
</div>
</div>
$(if($battHealth -lt 50){"<div style='padding:10px;background:#fef2f2;border-left:4px solid #dc2626;border-radius:4px;margin-bottom:12px;'><span class='fail'>$iconFail</span> <strong>Battery replacement recommended.</strong> Capacity is below 50% of original design.</div>"})
"@
    }

    # Technician notes
    $techNotesHTML = if ($Params.TechNotes) { "<div class='section-header'><span class='section-icon'>&#128221;</span> Technician Notes</div><div style='padding:14px 18px;background:#f8fafc;border:1px solid #d1d5db;border-radius:8px;min-height:50px;white-space:pre-wrap;font-size:9.5pt;line-height:1.7;margin-bottom:16px;'>$([System.Web.HttpUtility]::HtmlEncode($Params.TechNotes))</div>" } else { "" }

    # Key findings
    $keyFindings = @()
    if ($cpuStress -and $cpuStress.Passed) { $keyFindings += @{T="CPU passed stress testing.";S="pass"} }
    elseif ($cpuStress) { $keyFindings += @{T="CPU FAILED stress testing - possible instability.";S="fail"} }
    if ($ramStress -and $ramStress.Passed) { $keyFindings += @{T="RAM passed stress testing with no errors.";S="pass"} }
    elseif ($ramStress) { $keyFindings += @{T="RAM FAILED stress testing - memory errors detected.";S="fail"} }
    if ($gpuStress -and $gpuStress.Passed) { $keyFindings += @{T="GPU passed stress testing.";S="pass"} }
    elseif ($gpuStress) { $keyFindings += @{T="GPU FAILED stress testing - possible hardware issue.";S="fail"} }
    if ($overheat) { $keyFindings += @{T="OVERHEATING DETECTED - thermal management needs attention.";S="fail"} }
    elseif ($cpuTemp -gt 0 -or $gpuTemp -gt 0) {
        $maxT = [math]::Max($cpuTemp, $gpuTemp)
        if ($maxT -gt 85) { $keyFindings += @{T="Peak temperature ${maxT}C is in the critical range.";S="fail"} }
        elseif ($maxT -gt 70) { $keyFindings += @{T="Temperatures slightly elevated (peak ${maxT}C). Check airflow.";S="warn"} }
        else { $keyFindings += @{T="All temperatures within safe operating ranges.";S="pass"} }
    }
    if ($diskStress -and $diskStress.Passed) { $keyFindings += @{T="Disk benchmark passed: Read $seqRead MB/s, Write $seqWrite MB/s.";S="pass"} }
    elseif ($diskStress) { $keyFindings += @{T="Disk benchmark FAILED - storage may be degraded.";S="fail"} }
    if ($gamingScore -ge 80) { $keyFindings += @{T="Gaming readiness: $gamingTier ($gamingScore/100) - excellent for gaming.";S="pass"} }
    elseif ($gamingScore -ge 60) { $keyFindings += @{T="Gaming readiness: $gamingTier ($gamingScore/100) - decent for gaming.";S="warn"} }
    elseif ($gamingScore -gt 0) { $keyFindings += @{T="Gaming readiness: $gamingTier ($gamingScore/100) - upgrades recommended.";S="fail"} }
    if ($dlMbps -ge 100) { $keyFindings += @{T="Network speed: ${dlMbps} Mbps download - great for online gaming.";S="pass"} }
    elseif ($dlMbps -ge 25) { $keyFindings += @{T="Network speed: ${dlMbps} Mbps download - adequate for gaming.";S="pass"} }
    elseif ($dlMbps -gt 0) { $keyFindings += @{T="Network speed: ${dlMbps} Mbps download - may experience lag in online games.";S="warn"} }
    if ($battPresent -and $battHealth -lt 50) { $keyFindings += @{T="Battery at $battHealth% health - replacement recommended.";S="fail"} }
    elseif ($battPresent -and $battHealth -lt 80) { $keyFindings += @{T="Battery at $battHealth% health - still serviceable but degrading.";S="warn"} }
    $keyFindings = @($keyFindings | Select-Object -First 8)

    $findingsHTML = ""
    foreach ($f in $keyFindings) {
        $fIcon = switch ($f.S) { "pass" { "&#10004;" } "warn" { "&#9888;" } "fail" { "&#10008;" } }
        $fIconColor = switch ($f.S) { "pass" { "#22c55e" } "warn" { "#f59e0b" } "fail" { "#dc2626" } }
        $fBg = switch ($f.S) { "pass" { "#f0fdf4" } "warn" { "#fffbeb" } "fail" { "#fef2f2" } }
        $findingsHTML += "<div style='display:flex;align-items:flex-start;gap:10px;padding:7px 12px;margin:3px 0;border-radius:6px;background:$fBg;'><span style='font-size:13pt;color:$fIconColor;flex-shrink:0;'>$fIcon</span><span style='font-size:9.5pt;color:#1e293b;line-height:1.4;'>$($f.T)</span></div>`n"
    }

    # ══════════════════════════════════════════════════════════════════════════
    # ASSEMBLE THE FULL HTML
    # ══════════════════════════════════════════════════════════════════════════

$html = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8"/>
<title>Gaming PC Diagnostic Report - $customerName</title>
<style>
@page { size: A4; margin: 0.5in 0.6in 0.9in 0.6in; }
* { margin:0; padding:0; box-sizing:border-box; }
body { font-family: 'Segoe UI', -apple-system, Tahoma, sans-serif; font-size: 9.5pt; color: #1e293b; line-height: 1.6; background: #fff; }
h1,h2,h3,h4 { margin:0; }
@media print {
    body { -webkit-print-color-adjust: exact; print-color-adjust: exact; }
    .page-break { page-break-before: always; }
    .no-break { page-break-inside: avoid; }
}
.page-break { page-break-before: always; }
.print-footer {
    position: fixed; bottom: 0; left: 0; right: 0;
    padding: 6px 0; border-top: 1.5px solid #0d4b71;
    text-align: center; font-size: 7.5pt; color: #94a3b8; background: #fff;
}
.print-footer strong { color: #0d4b71; font-size: 7.5pt; }
.print-footer .report-name { color: #475569; }
.no-break { page-break-inside: avoid; }
.section-header {
    background: linear-gradient(135deg, #1a1a2e 0%, #0d4b71 100%);
    color: #fff; padding: 10px 20px; font-size: 12pt; font-weight: 600;
    margin: 24px 0 14px 0; border-radius: 6px; letter-spacing: 0.5px;
    display: flex; align-items: center; gap: 10px;
}
.section-header .section-icon { font-size: 14pt; opacity: 0.85; }
.sub-header {
    color: #0d4b71; font-size: 10.5pt; font-weight: 700; margin: 18px 0 8px 0;
    padding-bottom: 5px; border-bottom: 2px solid #2596be; letter-spacing: 0.3px;
}
table { width: 100%; border-collapse: collapse; margin-bottom: 14px; font-size: 9pt; }
th {
    background: #0d4b71; color: #fff; padding: 7px 10px; text-align: left;
    font-weight: 600; font-size: 8.5pt; text-transform: uppercase; letter-spacing: 0.5px;
}
td { padding: 6px 10px; border-bottom: 1px solid #e2e8f0; vertical-align: middle; }
tr:nth-child(even) td { background: #f8fafc; }
tr:hover td { background: #eaf7fc; }
.pass { color: #16a34a; font-weight: 600; }
.fail { color: #dc2626; font-weight: 600; }
.warn { color: #f59e0b; font-weight: 600; }
.chart-box {
    background: #fff; border: 1px solid #e2e8f0; border-radius: 10px;
    padding: 16px; margin: 12px 0; box-shadow: 0 1px 3px rgba(0,0,0,0.04);
}
.chart-box .chart-title {
    font-size: 10.5pt; font-weight: 700; color: #0d4b71; margin-bottom: 10px;
    padding-bottom: 4px; border-bottom: 1px solid #e2e8f0;
}
.summary-strip { display: flex; gap: 10px; margin: 14px 0; }
.summary-chip {
    flex: 1; text-align: center; padding: 10px 8px; background: #f8fafc;
    border: 1px solid #e2e8f0; border-radius: 8px;
}
.summary-chip .chip-val { font-size: 15pt; font-weight: 700; color: #0a1628; display: block; }
.summary-chip .chip-lbl { font-size: 7.5pt; color: #64748b; text-transform: uppercase; font-weight: 600; letter-spacing: 0.3px; }
.qr-row { display: flex; justify-content: center; gap: 60px; margin: 20px 0; }
.qr-item { text-align: center; }
.qr-item img { width: 140px; height: 140px; border-radius: 8px; }
.qr-item .qr-fallback { width: 140px; height: 140px; border: 2px dashed #94a3b8; border-radius: 8px; display: flex; align-items: center; justify-content: center; font-size: 7.5pt; color: #94a3b8; }
.qr-label { font-size: 9pt; font-weight: 600; color: #0d4b71; margin-top: 8px; }
.qr-sublabel { font-size: 7.5pt; color: #64748b; margin-top: 2px; }
</style>
</head>
<body>

<div class="print-footer">
<span class="report-name">Gaming PC Diagnostic Report</span> &nbsp;|&nbsp; <strong>$COMPANY</strong> &nbsp;|&nbsp; $WEBSITE &nbsp;|&nbsp; $PHONE
</div>

<!-- ══════════════════════════ COVER PAGE ══════════════════════════ -->
<div style="page-break-after:always;">
$(if($bannerGamingUri){"<div style='text-align:center;margin-bottom:12px;'><img src='$bannerGamingUri' alt='PC Plus Gaming Diagnostic' style='width:100%;border-radius:8px;'/></div>"})
<div style="text-align:center;padding:20px 0 10px;">
$logoHTML
<div style="font-size:17pt;font-weight:700;color:#0d4b71;margin-top:12px;letter-spacing:0.5px;">Gaming PC Diagnostic Report</div>
<div style="font-size:10pt;color:#3bbde0;margin-top:4px;">Complete Hardware &amp; Performance Analysis</div>
</div>
<div style="display:flex;gap:20px;align-items:center;margin:16px 0;">
<div style="flex:1;">
<div style="background:#f8fafc;border:1px solid #e2e8f0;border-radius:10px;padding:14px;">
<table style="width:100%;font-size:10pt;border:none;margin:0;">
<tr><td style="border:none;padding:4px 8px;color:#64748b;font-weight:600;width:110px;">Customer:</td><td style="border:none;padding:4px 8px;color:#0a1628;font-weight:700;">$customerName</td></tr>
$(if($customerPhone){"<tr><td style='border:none;padding:4px 8px;color:#64748b;font-weight:600;'>Phone:</td><td style='border:none;padding:4px 8px;color:#0a1628;'>$customerPhone</td></tr>"})
$(if($customerEmail){"<tr><td style='border:none;padding:4px 8px;color:#64748b;font-weight:600;'>Email:</td><td style='border:none;padding:4px 8px;color:#0a1628;'>$customerEmail</td></tr>"})
$(if($contactName){"<tr><td style='border:none;padding:4px 8px;color:#64748b;font-weight:600;'>Contact:</td><td style='border:none;padding:4px 8px;color:#0a1628;'>$contactName</td></tr>"})
<tr><td style="border:none;padding:4px 8px;color:#64748b;font-weight:600;">Device:</td><td style="border:none;padding:4px 8px;color:#0a1628;">$compName</td></tr>
<tr><td style="border:none;padding:4px 8px;color:#64748b;font-weight:600;">Date:</td><td style="border:none;padding:4px 8px;color:#0a1628;">$date</td></tr>
<tr><td style="border:none;padding:4px 8px;color:#64748b;font-weight:600;">Technician:</td><td style="border:none;padding:4px 8px;color:#0a1628;">$techName</td></tr>
$(if($ScanMode){"<tr><td style='border:none;padding:4px 8px;color:#64748b;font-weight:600;'>Scan Mode:</td><td style='border:none;padding:4px 8px;color:#0a1628;'>$ScanMode</td></tr>"})
</table>
</div>
</div>
<div style="text-align:center;">
$svgHealthDonut
</div>
</div>
<div class="summary-strip">
<div class="summary-chip"><span class="chip-val" style="font-size:11pt;">$cpuModel</span><span class="chip-lbl">Processor</span></div>
</div>
<div class="summary-strip">
<div class="summary-chip"><span class="chip-val" style="font-size:11pt;">$gpuName</span><span class="chip-lbl">Graphics Card</span></div>
<div class="summary-chip"><span class="chip-val">$ramTotalGB GB</span><span class="chip-lbl">RAM</span></div>
$(if($gamingScore -gt 0){"<div class='summary-chip'><span class='chip-val' style='color:$(if($gamingScore -ge 80){""#22c55e""}elseif($gamingScore -ge 60){""#2596be""}else{""#f59e0b""})'>$gamingTier</span><span class='chip-lbl'>Gaming Tier</span></div>"})
</div>
</div>

<!-- ══════════════════════════ EXECUTIVE SUMMARY ══════════════════════════ -->
<div class="page-break"></div>
<div class="section-header"><span class="section-icon">&#128202;</span> Executive Summary</div>
<div style="display:flex;align-items:flex-start;gap:20px;margin:14px 0;">
<div style="text-align:center;min-width:180px;">
$svgHealthDonut
</div>
<div style="flex:1;">
<div class="chart-box">
<div class="chart-title">Component Health Overview</div>
$healthGridSVG
</div>
</div>
</div>
<div style="background:#f8fafc;border:1px solid #e2e8f0;border-radius:10px;padding:14px 18px;margin:12px 0;" class="no-break">
<div style="font-size:10.5pt;font-weight:700;color:#0d4b71;margin-bottom:8px;">&#128270; Key Findings</div>
$findingsHTML
</div>

<!-- ══════════════════════════ THERMAL & STORAGE ══════════════════════════ -->
<div class="page-break"></div>
<div class="section-header"><span class="section-icon">&#127777;</span> Thermal Analysis</div>
<div class="chart-box no-break">
<div class="chart-title">Temperature Overview</div>
$tempBarSVG
$(if($overheat){"<div style='margin-top:10px;padding:8px 12px;background:#fef2f2;border-left:4px solid #dc2626;border-radius:4px;'><span class='fail'>$iconFail</span> <strong>Overheating detected!</strong> Clean dust filters, check thermal paste, and ensure proper ventilation.</div>"})
</div>
$(if($fans.Count -gt 0){@"
<div class='chart-box no-break'>
<div class='chart-title'>Fan Speed Monitoring</div>
$fanSVG
</div>
"@})
<div class="section-header"><span class="section-icon">&#128190;</span> Storage Performance</div>
<div class="chart-box no-break">
<div class="chart-title">Sequential Read / Write Speed</div>
$storageSVG
</div>
$(if($ssdRows){@"
<div class='sub-header'>Drive Health &amp; Lifespan</div>
<table><tr><th>Drive Model</th><th>Life Remaining</th><th>Power-On Hours</th><th>Grade</th></tr>
$ssdRows
</table>
"@})

<!-- ══════════════════════════ PERFORMANCE & NETWORK ══════════════════════════ -->
<div class="page-break"></div>
<div class="section-header"><span class="section-icon">&#9889;</span> Performance Snapshot</div>
<div class="chart-box no-break">
<div class="chart-title">RAM Usage</div>
$ramBarSVG
</div>
<div style="display:flex;gap:12px;margin:14px 0;" class="no-break">
<div class="summary-chip" style="flex:1;"><span class="chip-val" style="color:$(if($cpuUsage -gt 90){"#dc2626"}elseif($cpuUsage -gt 70){"#f59e0b"}else{"#22c55e"})">$cpuUsage%</span><span class="chip-lbl">CPU Usage</span></div>
<div class="summary-chip" style="flex:1;"><span class="chip-val" style="color:$(if($ramUsedPct -gt 90){"#dc2626"}elseif($ramUsedPct -gt 70){"#f59e0b"}else{"#2596be"})">$ramUsedPct%</span><span class="chip-lbl">RAM Usage</span></div>
<div class="summary-chip" style="flex:1;"><span class="chip-val">$memUsedGB / $memTotalGB GB</span><span class="chip-lbl">Memory</span></div>
</div>
<div class="section-header"><span class="section-icon">&#127760;</span> Network Speed</div>
<div class="chart-box no-break">
<div class="chart-title">Download &amp; Upload Speed</div>
$networkGaugeSVG
<div style="text-align:center;margin-top:6px;">
<span style="font-size:9pt;color:#64748b;">Ping: <strong>$pingMs</strong></span>
$(if($SpeedTest -and $SpeedTest.PacketLoss){"&nbsp;&nbsp;|&nbsp;&nbsp;<span style='font-size:9pt;color:#64748b;'>Packet Loss: <strong>$($SpeedTest.PacketLoss)</strong></span>"})
$(if($SpeedTest -and $SpeedTest.Jitter){"&nbsp;&nbsp;|&nbsp;&nbsp;<span style='font-size:9pt;color:#64748b;'>Jitter: <strong>$($SpeedTest.Jitter)</strong></span>"})
</div>
</div>
$(if($SpeedTest -and $SpeedTest.WiFiSignal){@"
<table><tr><th style='width:35%;'>Network Detail</th><th>Value</th></tr>
$(if($SpeedTest.Gateway){"<tr><td>Gateway</td><td>$($SpeedTest.Gateway)</td></tr>"})
$(if($SpeedTest.WiFiSignal){"<tr><td>WiFi Signal</td><td>$($SpeedTest.WiFiSignal)</td></tr>"})
$(if($SpeedTest.WiFiChannel){"<tr><td>WiFi Channel</td><td>$($SpeedTest.WiFiChannel)</td></tr>"})
$(if($SpeedTest.WiFiRadioType){"<tr><td>WiFi Radio</td><td>$($SpeedTest.WiFiRadioType)</td></tr>"})
$(if($SpeedTest.DNSResponseMs){"<tr><td>DNS Response</td><td>$($SpeedTest.DNSResponseMs)</td></tr>"})
</table>
"@})

<!-- ══════════════════════════ STRESS TESTS & GAMING ══════════════════════════ -->
$(if($stressRows -or $gamingHTML){"<div class='page-break'></div>"})
$(if($stressRows){@"
<div class='section-header'><span class='section-icon'>&#128293;</span> Stress Test Results</div>
<table><tr><th>Test</th><th>Result</th><th>Details</th></tr>
$stressRows
</table>
"@})
$gamingHTML
$(if($batteryHTML){@"
<div class='section-header'><span class='section-icon'>&#128267;</span> Battery &amp; Power</div>
$batteryHTML
"@})

<!-- ══════════════════════════ SYSTEM INFO ══════════════════════════ -->
<div class="page-break"></div>
<div class="section-header"><span class="section-icon">&#128187;</span> System Information</div>
<table><tr><th style="width:35%;">Property</th><th>Value</th></tr>
<tr><td>Computer Name</td><td><strong>$compName</strong></td></tr>
$(if($SystemInfo.Manufacturer){"<tr><td>Manufacturer / Model</td><td>$($SystemInfo.Manufacturer) $($SystemInfo.Model)</td></tr>"})
$(if($SystemInfo.Serial){"<tr><td>Serial Number</td><td style='font-family:Consolas,monospace;letter-spacing:0.5px;'>$($SystemInfo.Serial)</td></tr>"})
$(if($SystemInfo.OSVersion){"<tr><td>Operating System</td><td>$($SystemInfo.OSVersion)$(if($SystemInfo.OSBuild){" (Build $($SystemInfo.OSBuild))"})</td></tr>"})
<tr><td>CPU</td><td>$cpuModel</td></tr>
$(if($SystemInfo.CPUCores){"<tr><td>Cores / Threads</td><td>$($SystemInfo.CPUCores) / $($SystemInfo.CPUThreads)</td></tr>"})
<tr><td>RAM</td><td>$ramTotalGB GB$(if($SystemInfo.RAMFree){" ($($SystemInfo.RAMFree) GB free)"})</td></tr>
$(if($SystemInfo.GPUs){($SystemInfo.GPUs | ForEach-Object {"<tr><td>GPU</td><td>$($_.Name)$(if($_.VRAM_MB -gt 0){" ($($_.VRAM_MB) MB VRAM)"})</td></tr>"}) -join "`n"})
$(if($SystemInfo.Uptime){"<tr><td>Uptime</td><td>$($SystemInfo.Uptime)</td></tr>"})
</table>
$techNotesHTML

<!-- ══════════════════════════ BACK PAGE ══════════════════════════ -->
<div class="page-break"></div>
<div style="text-align:center;padding-top:60px;">
$(if($logoDataUri){"<img src='$logoDataUri' alt='PC Plus Computing' style='width:250px;margin-bottom:30px;'/>"}else{"<div style='background:linear-gradient(135deg,#0a1628,#0d4b71);color:#fff;padding:16px 40px;font-size:18pt;font-weight:bold;letter-spacing:3px;border-radius:6px;margin-bottom:30px;display:inline-block;'>PC PLUS COMPUTING</div>"})
<div style="font-size:12pt;color:#0d4b71;font-weight:600;margin-bottom:6px;">Thank you for choosing PC Plus Computing</div>
<div style="font-size:10pt;color:#64748b;margin-bottom:30px;">Your Security, Our Priority &nbsp;|&nbsp; 30+ Years in Service &nbsp;|&nbsp; 4.9&#9733; Google Rating</div>
<div class="qr-row">
<div class="qr-item">
$(if($qrAppUri){"<img src='$qrAppUri' alt='Book Appointment'/>"}else{"<div class='qr-fallback'>Book<br/>Appointment</div>"})
<div class="qr-label">Book an Appointment</div>
<div class="qr-sublabel">pcpluscomputing.com/appointments</div>
</div>
<div class="qr-item">
$(if($qrSvcUri){"<img src='$qrSvcUri' alt='Send Info'/>"}else{"<div class='qr-fallback'>Send Us<br/>Info</div>"})
<div class="qr-label">Send Us Your Info</div>
<div class="qr-sublabel">Service Request Portal</div>
</div>
</div>
<div style="margin-top:40px;padding:20px;background:#f8fafc;border-radius:10px;border:1px solid #e2e8f0;display:inline-block;">
<div style="font-size:11pt;font-weight:700;color:#0a1628;margin-bottom:8px;">Get In Touch</div>
<div style="font-size:10pt;color:#475569;">
&#127760; $WEBSITE &nbsp;&nbsp;|&nbsp;&nbsp; &#128222; $PHONE
</div>
</div>
<div style="margin-top:40px;font-size:8pt;color:#94a3b8;">
Gaming PC Diagnostic Report generated $date<br/>
Technician: $techName &nbsp;|&nbsp; Device: $compName
</div>
</div>

</body>
</html>
"@

    return $html
}

# ─────────────────────────────────────────────────────────────────────────────
# GAMING PERFORMANCE & STABILITY REPORT  (Time-Series SVG Charts)
# ─────────────────────────────────────────────────────────────────────────────

function Build-GamingPerformanceReport {
    param(
        $Params,          # CustomerName, TechName, ContactName, TechNotes
        $SystemInfo,      # CPU, RAM, GPU, disks
        $TimeSeries,      # Time-sampled stress data with .Samples array
        $Storage,         # DiskSpd benchmark results
        $NetworkDeep,     # Deep network test results
        $FPS,             # PresentMon capture results
        $PowerStability,  # Power stability data
        $PreStress,       # Pre-stress thermal snapshot
        $PostStress,      # Post-stress thermal snapshot
        $Recovery,        # Recovery thermal data
        $Scores,          # Overall scores
        $Recommendations,
        $ScanMode
    )

    $date = Get-Date -Format "MMMM dd, yyyy 'at' h:mm tt"
    $iconPass = "&#10004;"; $iconFail = "&#10008;"; $iconWarn = "&#9888;"

    # ── Safe accessors ──────────────────────────────────────────────────────
    $customerName  = if ($Params.CustomerName)  { $Params.CustomerName }  else { "Customer" }
    $customerPhone = if ($Params.CustomerPhone) { $Params.CustomerPhone } else { "" }
    $customerEmail = if ($Params.CustomerEmail) { $Params.CustomerEmail } else { "" }
    $techName      = if ($Params.TechName)      { $Params.TechName }      else { "Technician" }
    $contactName   = if ($Params.ContactName)   { $Params.ContactName }   else { "" }
    $techNotes     = if ($Params.TechNotes)     { $Params.TechNotes }     else { "" }

    $cpuModel  = if ($SystemInfo.CPUModel)    { $SystemInfo.CPUModel }   else { "Unknown CPU" }
    $ramTotal  = if ($SystemInfo.RAMTotal)     { $SystemInfo.RAMTotal }   else { 0 }
    $gpuName   = if ($SystemInfo.GPUs -and $SystemInfo.GPUs.Count -gt 0) { $SystemInfo.GPUs[0].Name } else { "Unknown GPU" }
    $compName  = if ($SystemInfo.ComputerName) { $SystemInfo.ComputerName } else { "PC" }

    # TimeSeries safe
    $samples       = if ($TimeSeries -and $TimeSeries.Samples) { @($TimeSeries.Samples) } else { @() }
    $peakCPUTemp   = if ($TimeSeries.PeakCPUTemp)  { [double]$TimeSeries.PeakCPUTemp }  else { 0 }
    $peakGPUTemp   = if ($TimeSeries.PeakGPUTemp)  { [double]$TimeSeries.PeakGPUTemp }  else { 0 }
    $avgCPUTemp    = if ($TimeSeries.AvgCPUTemp)    { [double]$TimeSeries.AvgCPUTemp }   else { 0 }
    $avgGPUTemp    = if ($TimeSeries.AvgGPUTemp)    { [double]$TimeSeries.AvgGPUTemp }   else { 0 }
    $throttle      = if ($TimeSeries.ThrottleDetected) { $true } else { $false }
    $coolRecoverySec = if ($TimeSeries.CoolingRecoveryTimeSec) { [int]$TimeSeries.CoolingRecoveryTimeSec } else { 0 }

    # Storage safe
    $seqRead     = if ($Storage.SeqReadMBps)        { [double]$Storage.SeqReadMBps }        else { 0 }
    $seqWrite    = if ($Storage.SeqWriteMBps)        { [double]$Storage.SeqWriteMBps }       else { 0 }
    $rand4KR     = if ($Storage.Random4KReadIOPS)    { [double]$Storage.Random4KReadIOPS }   else { 0 }
    $rand4KW     = if ($Storage.Random4KWriteIOPS)   { [double]$Storage.Random4KWriteIOPS }  else { 0 }
    $avgLatency  = if ($Storage.AvgLatencyMs)        { [double]$Storage.AvgLatencyMs }       else { 0 }
    $storTool    = if ($Storage.ToolUsed)             { $Storage.ToolUsed }                   else { "N/A" }

    # Network safe
    $netDL       = if ($NetworkDeep.Download)       { [double]($NetworkDeep.Download -replace '[^\d.]','') } else { 0 }
    $netUL       = if ($NetworkDeep.Upload)          { [double]($NetworkDeep.Upload -replace '[^\d.]','') }  else { 0 }
    $netPing     = if ($NetworkDeep.PingAvg)          { $NetworkDeep.PingAvg }         else { "N/A" }
    $netJitter   = if ($NetworkDeep.PingJitter)       { $NetworkDeep.PingJitter }      else { "N/A" }
    $netPktLoss  = if ($NetworkDeep.PacketLossPct -ne $null) { $NetworkDeep.PacketLossPct } else { "N/A" }
    $netDNS      = if ($NetworkDeep.DNSResponseMs)    { $NetworkDeep.DNSResponseMs }   else { "N/A" }
    $netWiFi     = if ($NetworkDeep.WiFiSignalPct)    { $NetworkDeep.WiFiSignalPct }   else { $null }
    $netEthSpeed = if ($NetworkDeep.EthernetSpeedMbps){ $NetworkDeep.EthernetSpeedMbps } else { $null }

    # FPS safe
    $fpsAvail    = if ($FPS -and $FPS.Available) { $true } else { $false }
    $fpsAvg      = if ($FPS.AvgFPS)              { [double]$FPS.AvgFPS }          else { 0 }
    $fps1Low     = if ($FPS.OnePercentLowFPS)    { [double]$FPS.OnePercentLowFPS } else { 0 }
    $fpsAvgFT    = if ($FPS.AvgFrameTimeMs)      { [double]$FPS.AvgFrameTimeMs }  else { 0 }
    $fpsP99FT    = if ($FPS.P99FrameTimeMs)      { [double]$FPS.P99FrameTimeMs }  else { 0 }

    # Power safe
    $pwrKernel   = if ($PowerStability.KernelPowerEvents) { [int]$PowerStability.KernelPowerEvents } else { 0 }
    $pwrShutdown = if ($PowerStability.UnexpectedShutdowns) { [int]$PowerStability.UnexpectedShutdowns } else { 0 }
    $pwrScore    = if ($PowerStability.Score -ne $null) { [int]$PowerStability.Score } else { 100 }

    # Scores safe
    $scoreOverall  = if ($Scores.Overall)        { [int]$Scores.Overall }        else { 0 }
    $scoreThermal  = if ($Scores.Thermal)        { [int]$Scores.Thermal }        else { 0 }
    $scoreFPS      = if ($Scores.FPSStability)   { $Scores.FPSStability }        else { "N/A" }
    $scoreStorage  = if ($Scores.StorageSpeed)   { $Scores.StorageSpeed }        else { "N/A" }
    $scorePower    = if ($Scores.PowerStability)  { $Scores.PowerStability }      else { "N/A" }
    $scoreGrade    = if ($Scores.Grade)           { $Scores.Grade }              else { if ($scoreOverall -ge 90){"A"} elseif($scoreOverall -ge 80){"B"} elseif($scoreOverall -ge 70){"C"} elseif($scoreOverall -ge 60){"D"} else {"F"} }
    $overallColor  = if ($scoreOverall -ge 80){"#22c55e"} elseif ($scoreOverall -ge 60){"#f59e0b"} else {"#dc2626"}

    # Recommendations safe
    $recs = if ($Recommendations) { @($Recommendations) } else { @() }

    # ── Load logo ───────────────────────────────────────────────────────────
    $logoDataUri = ""
    $logoPath = Join-Path $Global:ScriptDir "logo-base64.txt"
    if (Test-Path $logoPath) {
        try { $logoDataUri = "data:image/png;base64,$((Get-Content $logoPath -Raw).Trim())" } catch {}
    }
    $logoHTML = if ($logoDataUri) {
        "<img src='$logoDataUri' alt='PC Plus Computing' style='width:320px;max-width:85%;'/>"
    } else {
        "<div style='background:linear-gradient(135deg,#0a1628,#0d4b71);color:#fff;padding:16px 40px;font-size:20pt;font-weight:bold;letter-spacing:3px;border-radius:8px;display:inline-block;'>PC PLUS COMPUTING</div>"
    }

    # ── Load QR codes ───────────────────────────────────────────────────────
    $qrAppUri = ""; $qrSvcUri = ""
    $qrAppPath = Join-Path $Global:ScriptDir "qr-appointments.txt"
    $qrSvcPath = Join-Path $Global:ScriptDir "qr-service-requests.txt"
    if (Test-Path $qrAppPath) { try { $qrAppUri = "data:image/png;base64,$((Get-Content $qrAppPath -Raw).Trim())" } catch {} }
    if (Test-Path $qrSvcPath) { try { $qrSvcUri = "data:image/png;base64,$((Get-Content $qrSvcPath -Raw).Trim())" } catch {} }

    # ── Load gaming performance banner ──────────────────────────────────────
    $bannerUri = ""
    $bgPath = Join-Path $Global:ScriptDir "banner-gaming-top.txt"
    if (Test-Path $bgPath) { try { $bannerUri = "data:image/jpeg;base64,$((Get-Content $bgPath -Raw).Trim())" } catch {} }

    # ══════════════════════════════════════════════════════════════════════════
    # SVG CHART BUILDER HELPERS
    # ══════════════════════════════════════════════════════════════════════════

    # Chart constants
    $chartW = 600; $chartH = 200
    $plotL = 55; $plotR = 580; $plotT = 20; $plotB = 175
    $plotW = $plotR - $plotL; $plotH = $plotB - $plotT

    # Helper: map data value to Y coordinate (inverted because SVG y goes down)
    function Map-Y([double]$val, [double]$minVal, [double]$maxVal) {
        if ($maxVal -le $minVal) { return $plotB }
        $pct = ($val - $minVal) / ($maxVal - $minVal)
        return [math]::Round($plotB - ($pct * $plotH), 1)
    }

    # Helper: build grid lines and Y-axis labels for a chart
    function Build-GridSVG([double]$minVal, [double]$maxVal, [string]$unit, [int]$steps) {
        $grid = ""
        for ($i = 0; $i -le $steps; $i++) {
            $v = $minVal + ($maxVal - $minVal) * $i / $steps
            $y = Map-Y $v $minVal $maxVal
            $grid += "  <line x1='$plotL' y1='$y' x2='$plotR' y2='$y' stroke='#334155' stroke-width='0.5' stroke-dasharray='4,3' opacity='0.4'/>`n"
            $grid += "  <text x='$($plotL - 4)' y='$($y + 3)' text-anchor='end' font-size='8' fill='#94a3b8' font-family='Segoe UI,sans-serif'>$([math]::Round($v,0))$unit</text>`n"
        }
        return $grid
    }

    # Helper: build X-axis time labels
    function Build-XAxisSVG([double]$maxTimeSec) {
        $xaxis = ""
        if ($maxTimeSec -le 0) { return $xaxis }
        $tickCount = [math]::Min(6, [math]::Max(2, [math]::Floor($maxTimeSec / 30)))
        for ($i = 0; $i -le $tickCount; $i++) {
            $t = [math]::Round($maxTimeSec * $i / $tickCount)
            $x = [math]::Round($plotL + ($plotW * $i / $tickCount), 1)
            $xaxis += "  <line x1='$x' y1='$plotB' x2='$x' y2='$($plotB + 4)' stroke='#64748b' stroke-width='0.5'/>`n"
            $label = if ($t -ge 60) { "$([math]::Floor($t/60))m$($t % 60)s" } else { "${t}s" }
            $xaxis += "  <text x='$x' y='$($plotB + 14)' text-anchor='middle' font-size='7.5' fill='#94a3b8' font-family='Segoe UI,sans-serif'>$label</text>`n"
        }
        # X-axis label
        $xaxis += "  <text x='$([math]::Round(($plotL + $plotR) / 2))' y='$($plotB + 26)' text-anchor='middle' font-size='8' fill='#64748b' font-family='Segoe UI,sans-serif'>Time</text>`n"
        return $xaxis
    }

    # Helper: build polyline from samples
    function Build-PolylineSVG([array]$points, [string]$color, [double]$minVal, [double]$maxVal, [double]$maxTimeSec) {
        if ($points.Count -lt 2 -or $maxTimeSec -le 0) { return "" }
        $coords = @()
        foreach ($p in $points) {
            $x = [math]::Round($plotL + ($p.T / $maxTimeSec * $plotW), 1)
            $y = Map-Y $p.V $minVal $maxVal
            $coords += "$x,$y"
        }
        $ptStr = $coords -join " "
        return "  <polyline points='$ptStr' fill='none' stroke='$color' stroke-width='2' stroke-linejoin='round' stroke-linecap='round'/>`n"
    }

    # Helper: stress/recovery divider line
    function Build-PhaseDividerSVG([double]$stressEndSec, [double]$maxTimeSec) {
        if ($stressEndSec -le 0 -or $maxTimeSec -le 0) { return "" }
        $x = [math]::Round($plotL + ($stressEndSec / $maxTimeSec * $plotW), 1)
        $svg = "  <line x1='$x' y1='$plotT' x2='$x' y2='$plotB' stroke='#f59e0b' stroke-width='1.5' stroke-dasharray='6,3'/>`n"
        $svg += "  <text x='$($x - 4)' y='$($plotT - 4)' text-anchor='end' font-size='7' fill='#f59e0b' font-family='Segoe UI,sans-serif'>Stress</text>`n"
        $svg += "  <text x='$($x + 4)' y='$($plotT - 4)' text-anchor='start' font-size='7' fill='#3bbde0' font-family='Segoe UI,sans-serif'>Recovery</text>`n"
        return $svg
    }

    # Determine max time and stress end time from samples
    $maxTimeSec = 0
    $stressEndSec = 0
    if ($samples.Count -gt 0) {
        $maxTimeSec = ($samples | ForEach-Object { if ($_.TimeSec) { [double]$_.TimeSec } else { 0 } } | Measure-Object -Maximum).Maximum
        # Estimate stress end: last sample where CPU usage > 80% (heuristic)
        $stressSamples = @($samples | Where-Object { $_.CPUUsagePct -and [double]$_.CPUUsagePct -gt 80 })
        if ($stressSamples.Count -gt 0) {
            $stressEndSec = ($stressSamples | ForEach-Object { [double]$_.TimeSec } | Measure-Object -Maximum).Maximum
        } else {
            $stressEndSec = $maxTimeSec * 0.7  # fallback: 70% mark
        }
    }

    # ══════════════════════════════════════════════════════════════════════════
    # CHART 1: CPU Temperature Over Time
    # ══════════════════════════════════════════════════════════════════════════

    $svgCPUTemp = ""
    if ($samples.Count -ge 2) {
        $cpuTemps = @($samples | Where-Object { $_.CPUTempC -ne $null } | ForEach-Object { @{ T=[double]$_.TimeSec; V=[double]$_.CPUTempC } })
        if ($cpuTemps.Count -ge 2) {
            $minT = 20; $maxT = [math]::Max(100, [math]::Ceiling(($cpuTemps | ForEach-Object { $_.V } | Measure-Object -Maximum).Maximum / 10) * 10)

            # Temperature zone backgrounds
            $yGreenTop = Map-Y 70 $minT $maxT
            $yYellowTop = Map-Y 85 $minT $maxT
            $yRedTop = Map-Y $maxT $minT $maxT

            $svgCPUTemp = @"
<svg viewBox="0 0 $chartW $chartH" width="100%" height="200px" xmlns="http://www.w3.org/2000/svg" style="background:#1a1a2e;border-radius:8px;">
  <!-- Temperature zone backgrounds -->
  <rect x="$plotL" y="$plotT" width="$plotW" height="$($yYellowTop - $plotT)" fill="#dc2626" opacity="0.12"/>
  <rect x="$plotL" y="$yYellowTop" width="$plotW" height="$($yGreenTop - $yYellowTop)" fill="#f59e0b" opacity="0.10"/>
  <rect x="$plotL" y="$yGreenTop" width="$plotW" height="$($plotB - $yGreenTop)" fill="#22c55e" opacity="0.08"/>
  <!-- Zone labels -->
  <text x="$($plotR + 2)" y="$($yRedTop + 12)" font-size="6.5" fill="#dc2626" font-family="Segoe UI,sans-serif" opacity="0.8">&gt;85C</text>
  <text x="$($plotR + 2)" y="$([math]::Round(($yYellowTop + $yGreenTop)/2 + 3))" font-size="6.5" fill="#f59e0b" font-family="Segoe UI,sans-serif" opacity="0.8">70-85C</text>
  <text x="$($plotR + 2)" y="$([math]::Round(($yGreenTop + $plotB)/2 + 3))" font-size="6.5" fill="#22c55e" font-family="Segoe UI,sans-serif" opacity="0.8">&lt;70C</text>
  <!-- Plot border -->
  <rect x="$plotL" y="$plotT" width="$plotW" height="$plotH" fill="none" stroke="#334155" stroke-width="0.5"/>
$(Build-GridSVG $minT $maxT "C" 5)
$(Build-XAxisSVG $maxTimeSec)
$(Build-PhaseDividerSVG $stressEndSec $maxTimeSec)
$(Build-PolylineSVG $cpuTemps "#ff6b6b" $minT $maxT $maxTimeSec)
  <!-- Peak marker -->
  <text x="$($plotL + 6)" y="$($plotT + 12)" font-size="8" fill="#ff6b6b" font-family="Segoe UI,sans-serif" font-weight="600">Peak: $($peakCPUTemp)C | Avg: $($avgCPUTemp)C$(if($throttle){" | THROTTLE DETECTED"})</text>
  <!-- Legend -->
  <line x1="$($plotR - 80)" y1="$($plotT + 8)" x2="$($plotR - 60)" y2="$($plotT + 8)" stroke="#ff6b6b" stroke-width="2"/>
  <text x="$($plotR - 56)" y="$($plotT + 11)" font-size="7.5" fill="#e2e8f0" font-family="Segoe UI,sans-serif">CPU Temp</text>
</svg>
"@
        }
    }

    # ══════════════════════════════════════════════════════════════════════════
    # CHART 2: GPU Temperature Over Time
    # ══════════════════════════════════════════════════════════════════════════

    $svgGPUTemp = ""
    if ($samples.Count -ge 2) {
        $gpuTemps = @($samples | Where-Object { $_.GPUTempC -ne $null } | ForEach-Object { @{ T=[double]$_.TimeSec; V=[double]$_.GPUTempC } })
        if ($gpuTemps.Count -ge 2) {
            $minT2 = 20; $maxT2 = [math]::Max(100, [math]::Ceiling(($gpuTemps | ForEach-Object { $_.V } | Measure-Object -Maximum).Maximum / 10) * 10)
            $yGreenTop2 = Map-Y 70 $minT2 $maxT2
            $yYellowTop2 = Map-Y 85 $minT2 $maxT2
            $yRedTop2 = Map-Y $maxT2 $minT2 $maxT2

            $svgGPUTemp = @"
<svg viewBox="0 0 $chartW $chartH" width="100%" height="200px" xmlns="http://www.w3.org/2000/svg" style="background:#1a1a2e;border-radius:8px;">
  <rect x="$plotL" y="$plotT" width="$plotW" height="$($yYellowTop2 - $plotT)" fill="#dc2626" opacity="0.12"/>
  <rect x="$plotL" y="$yYellowTop2" width="$plotW" height="$($yGreenTop2 - $yYellowTop2)" fill="#f59e0b" opacity="0.10"/>
  <rect x="$plotL" y="$yGreenTop2" width="$plotW" height="$($plotB - $yGreenTop2)" fill="#22c55e" opacity="0.08"/>
  <text x="$($plotR + 2)" y="$($yRedTop2 + 12)" font-size="6.5" fill="#dc2626" font-family="Segoe UI,sans-serif" opacity="0.8">&gt;85C</text>
  <text x="$($plotR + 2)" y="$([math]::Round(($yYellowTop2 + $yGreenTop2)/2 + 3))" font-size="6.5" fill="#f59e0b" font-family="Segoe UI,sans-serif" opacity="0.8">70-85C</text>
  <text x="$($plotR + 2)" y="$([math]::Round(($yGreenTop2 + $plotB)/2 + 3))" font-size="6.5" fill="#22c55e" font-family="Segoe UI,sans-serif" opacity="0.8">&lt;70C</text>
  <rect x="$plotL" y="$plotT" width="$plotW" height="$plotH" fill="none" stroke="#334155" stroke-width="0.5"/>
$(Build-GridSVG $minT2 $maxT2 "C" 5)
$(Build-XAxisSVG $maxTimeSec)
$(Build-PhaseDividerSVG $stressEndSec $maxTimeSec)
$(Build-PolylineSVG $gpuTemps "#3bbde0" $minT2 $maxT2 $maxTimeSec)
  <text x="$($plotL + 6)" y="$($plotT + 12)" font-size="8" fill="#3bbde0" font-family="Segoe UI,sans-serif" font-weight="600">Peak: $($peakGPUTemp)C | Avg: $($avgGPUTemp)C</text>
  <line x1="$($plotR - 80)" y1="$($plotT + 8)" x2="$($plotR - 60)" y2="$($plotT + 8)" stroke="#3bbde0" stroke-width="2"/>
  <text x="$($plotR - 56)" y="$($plotT + 11)" font-size="7.5" fill="#e2e8f0" font-family="Segoe UI,sans-serif">GPU Temp</text>
</svg>
"@
        }
    }

    # ══════════════════════════════════════════════════════════════════════════
    # CHART 3: CPU/GPU Usage Over Time (Dual Line)
    # ══════════════════════════════════════════════════════════════════════════

    $svgUsage = ""
    if ($samples.Count -ge 2) {
        $cpuUsageData = @($samples | Where-Object { $_.CPUUsagePct -ne $null } | ForEach-Object { @{ T=[double]$_.TimeSec; V=[double]$_.CPUUsagePct } })
        $ramUsageData = @($samples | Where-Object { $_.RAMUsagePct -ne $null } | ForEach-Object { @{ T=[double]$_.TimeSec; V=[double]$_.RAMUsagePct } })

        $svgUsage = @"
<svg viewBox="0 0 $chartW $chartH" width="100%" height="200px" xmlns="http://www.w3.org/2000/svg" style="background:#1a1a2e;border-radius:8px;">
  <rect x="$plotL" y="$plotT" width="$plotW" height="$plotH" fill="none" stroke="#334155" stroke-width="0.5"/>
$(Build-GridSVG 0 100 "%" 5)
$(Build-XAxisSVG $maxTimeSec)
$(Build-PhaseDividerSVG $stressEndSec $maxTimeSec)
$(Build-PolylineSVG $cpuUsageData "#4dabf7" 0 100 $maxTimeSec)
$(Build-PolylineSVG $ramUsageData "#51cf66" 0 100 $maxTimeSec)
  <!-- Legend -->
  <line x1="$($plotR - 160)" y1="$($plotT + 8)" x2="$($plotR - 140)" y2="$($plotT + 8)" stroke="#4dabf7" stroke-width="2"/>
  <text x="$($plotR - 136)" y="$($plotT + 11)" font-size="7.5" fill="#e2e8f0" font-family="Segoe UI,sans-serif">CPU Usage</text>
  <line x1="$($plotR - 80)" y1="$($plotT + 8)" x2="$($plotR - 60)" y2="$($plotT + 8)" stroke="#51cf66" stroke-width="2"/>
  <text x="$($plotR - 56)" y="$($plotT + 11)" font-size="7.5" fill="#e2e8f0" font-family="Segoe UI,sans-serif">RAM Usage</text>
</svg>
"@
    }

    # ══════════════════════════════════════════════════════════════════════════
    # CHART 4: CPU Clock Speed Over Time
    # ══════════════════════════════════════════════════════════════════════════

    $svgClock = ""
    if ($samples.Count -ge 2) {
        $clockData = @($samples | Where-Object { $_.CPUClockMHz -ne $null -and [double]$_.CPUClockMHz -gt 0 } | ForEach-Object { @{ T=[double]$_.TimeSec; V=[double]$_.CPUClockMHz } })
        if ($clockData.Count -ge 2) {
            $clockMin = 0
            $clockMax = [math]::Ceiling(($clockData | ForEach-Object { $_.V } | Measure-Object -Maximum).Maximum / 500) * 500
            if ($clockMax -le 0) { $clockMax = 5000 }
            $clockAvg = [math]::Round(($clockData | ForEach-Object { $_.V } | Measure-Object -Average).Average)

            # Detect throttle drops: points where clock drops below 70% of max
            $clockPeak = ($clockData | ForEach-Object { $_.V } | Measure-Object -Maximum).Maximum
            $throttleThreshold = $clockPeak * 0.7

            # Build throttle highlight rects for regions where clock dips
            $throttleHighlights = ""
            $inThrottle = $false; $tStart = 0
            foreach ($p in $clockData) {
                if ($p.V -lt $throttleThreshold -and -not $inThrottle) {
                    $inThrottle = $true; $tStart = $p.T
                } elseif ($p.V -ge $throttleThreshold -and $inThrottle) {
                    $inThrottle = $false
                    $x1 = [math]::Round($plotL + ($tStart / $maxTimeSec * $plotW), 1)
                    $x2 = [math]::Round($plotL + ($p.T / $maxTimeSec * $plotW), 1)
                    $throttleHighlights += "  <rect x='$x1' y='$plotT' width='$([math]::Round($x2 - $x1, 1))' height='$plotH' fill='#dc2626' opacity='0.15'/>`n"
                }
            }
            if ($inThrottle) {
                $x1 = [math]::Round($plotL + ($tStart / $maxTimeSec * $plotW), 1)
                $throttleHighlights += "  <rect x='$x1' y='$plotT' width='$([math]::Round($plotR - $x1, 1))' height='$plotH' fill='#dc2626' opacity='0.15'/>`n"
            }

            $svgClock = @"
<svg viewBox="0 0 $chartW $chartH" width="100%" height="200px" xmlns="http://www.w3.org/2000/svg" style="background:#1a1a2e;border-radius:8px;">
  <rect x="$plotL" y="$plotT" width="$plotW" height="$plotH" fill="none" stroke="#334155" stroke-width="0.5"/>
$throttleHighlights
$(Build-GridSVG $clockMin $clockMax " MHz" 5)
$(Build-XAxisSVG $maxTimeSec)
$(Build-PhaseDividerSVG $stressEndSec $maxTimeSec)
$(Build-PolylineSVG $clockData "#ffd43b" $clockMin $clockMax $maxTimeSec)
  <!-- Throttle threshold line -->
  <line x1="$plotL" y1="$(Map-Y $throttleThreshold $clockMin $clockMax)" x2="$plotR" y2="$(Map-Y $throttleThreshold $clockMin $clockMax)" stroke="#dc2626" stroke-width="1" stroke-dasharray="5,3" opacity="0.6"/>
  <text x="$($plotR - 2)" y="$([math]::Round((Map-Y $throttleThreshold $clockMin $clockMax) - 3))" text-anchor="end" font-size="6.5" fill="#dc2626" font-family="Segoe UI,sans-serif">Throttle Line</text>
  <text x="$($plotL + 6)" y="$($plotT + 12)" font-size="8" fill="#ffd43b" font-family="Segoe UI,sans-serif" font-weight="600">Peak: $([math]::Round($clockPeak)) MHz | Avg: $clockAvg MHz$(if($throttle){" | THROTTLING DETECTED"})</text>
  <line x1="$($plotR - 80)" y1="$($plotT + 8)" x2="$($plotR - 60)" y2="$($plotT + 8)" stroke="#ffd43b" stroke-width="2"/>
  <text x="$($plotR - 56)" y="$($plotT + 11)" font-size="7.5" fill="#e2e8f0" font-family="Segoe UI,sans-serif">Clock MHz</text>
</svg>
"@
        }
    }

    # ══════════════════════════════════════════════════════════════════════════
    # CHART 5: Fan RPM Over Time
    # ══════════════════════════════════════════════════════════════════════════

    $svgFan = ""
    if ($samples.Count -ge 2) {
        $fanData = @($samples | Where-Object { $_.FanRPM -ne $null -and [double]$_.FanRPM -gt 0 } | ForEach-Object { @{ T=[double]$_.TimeSec; V=[double]$_.FanRPM } })
        if ($fanData.Count -ge 2) {
            $fanMin = 0
            $fanMax = [math]::Ceiling(($fanData | ForEach-Object { $_.V } | Measure-Object -Maximum).Maximum / 500) * 500
            if ($fanMax -le 0) { $fanMax = 3000 }
            $fanAvg = [math]::Round(($fanData | ForEach-Object { $_.V } | Measure-Object -Average).Average)
            $fanPeak = [math]::Round(($fanData | ForEach-Object { $_.V } | Measure-Object -Maximum).Maximum)

            # Phase background shading: before stress, during stress, recovery
            $phaseShading = ""
            if ($stressEndSec -gt 0 -and $maxTimeSec -gt 0) {
                # Find first high-load sample as stress start (~first sample with CPU > 50%)
                $stressStartSec = 0
                $highLoadSamples = @($samples | Where-Object { $_.CPUUsagePct -and [double]$_.CPUUsagePct -gt 50 })
                if ($highLoadSamples.Count -gt 0) {
                    $stressStartSec = ($highLoadSamples | ForEach-Object { [double]$_.TimeSec } | Measure-Object -Minimum).Minimum
                }
                $xStart = [math]::Round($plotL + ($stressStartSec / $maxTimeSec * $plotW), 1)
                $xEnd   = [math]::Round($plotL + ($stressEndSec / $maxTimeSec * $plotW), 1)
                # Before stress (idle)
                if ($stressStartSec -gt 0) {
                    $phaseShading += "  <rect x='$plotL' y='$plotT' width='$([math]::Round($xStart - $plotL, 1))' height='$plotH' fill='#22c55e' opacity='0.05'/>`n"
                    $phaseShading += "  <text x='$([math]::Round(($plotL + $xStart)/2))' y='$($plotB - 4)' text-anchor='middle' font-size='7' fill='#22c55e' font-family='Segoe UI,sans-serif' opacity='0.7'>Idle</text>`n"
                }
                # During stress
                $phaseShading += "  <rect x='$xStart' y='$plotT' width='$([math]::Round($xEnd - $xStart, 1))' height='$plotH' fill='#f59e0b' opacity='0.06'/>`n"
                $phaseShading += "  <text x='$([math]::Round(($xStart + $xEnd)/2))' y='$($plotB - 4)' text-anchor='middle' font-size='7' fill='#f59e0b' font-family='Segoe UI,sans-serif' opacity='0.7'>Stress</text>`n"
                # Recovery
                $phaseShading += "  <rect x='$xEnd' y='$plotT' width='$([math]::Round($plotR - $xEnd, 1))' height='$plotH' fill='#3bbde0' opacity='0.05'/>`n"
                $phaseShading += "  <text x='$([math]::Round(($xEnd + $plotR)/2))' y='$($plotB - 4)' text-anchor='middle' font-size='7' fill='#3bbde0' font-family='Segoe UI,sans-serif' opacity='0.7'>Recovery</text>`n"
            }

            $svgFan = @"
<svg viewBox="0 0 $chartW $chartH" width="100%" height="200px" xmlns="http://www.w3.org/2000/svg" style="background:#1a1a2e;border-radius:8px;">
$phaseShading
  <rect x="$plotL" y="$plotT" width="$plotW" height="$plotH" fill="none" stroke="#334155" stroke-width="0.5"/>
$(Build-GridSVG $fanMin $fanMax " RPM" 5)
$(Build-XAxisSVG $maxTimeSec)
$(Build-PhaseDividerSVG $stressEndSec $maxTimeSec)
$(Build-PolylineSVG $fanData "#c084fc" $fanMin $fanMax $maxTimeSec)
  <text x="$($plotL + 6)" y="$($plotT + 12)" font-size="8" fill="#c084fc" font-family="Segoe UI,sans-serif" font-weight="600">Peak: $fanPeak RPM | Avg: $fanAvg RPM</text>
  <line x1="$($plotR - 80)" y1="$($plotT + 8)" x2="$($plotR - 60)" y2="$($plotT + 8)" stroke="#c084fc" stroke-width="2"/>
  <text x="$($plotR - 56)" y="$($plotT + 11)" font-size="7.5" fill="#e2e8f0" font-family="Segoe UI,sans-serif">Fan RPM</text>
</svg>
"@
        }
    }

    # ══════════════════════════════════════════════════════════════════════════
    # CHART 6: Storage Speed Horizontal Bar Chart
    # ══════════════════════════════════════════════════════════════════════════

    $svgStorage = ""
    if ($seqRead -gt 0 -or $seqWrite -gt 0 -or $rand4KR -gt 0 -or $rand4KW -gt 0) {
        # Reference thresholds for "Good SSD"
        $refSeqRead  = 3000; $refSeqWrite = 2000; $refRand4KR = 50000; $refRand4KW = 40000

        $storBars = @(
            @{ Label="Seq Read";  Value=$seqRead;  Max=[math]::Max($seqRead * 1.3, $refSeqRead * 1.2);  Ref=$refSeqRead;  Unit="MB/s"; Color="#4dabf7" }
            @{ Label="Seq Write"; Value=$seqWrite; Max=[math]::Max($seqWrite * 1.3, $refSeqWrite * 1.2); Ref=$refSeqWrite; Unit="MB/s"; Color="#3bbde0" }
            @{ Label="4K Read";   Value=$rand4KR;  Max=[math]::Max($rand4KR * 1.3, $refRand4KR * 1.2);  Ref=$refRand4KR;  Unit="IOPS"; Color="#51cf66" }
            @{ Label="4K Write";  Value=$rand4KW;  Max=[math]::Max($rand4KW * 1.3, $refRand4KW * 1.2);  Ref=$refRand4KW;  Unit="IOPS"; Color="#ffd43b" }
        )

        $storH = 40 + ($storBars.Count * 42)
        $svgStorage = "<svg viewBox='0 0 $chartW $storH' width='100%' height='${storH}px' xmlns='http://www.w3.org/2000/svg' style='background:#1a1a2e;border-radius:8px;'>`n"
        # Legend
        $svgStorage += "  <rect x='$($plotR - 120)' y='6' width='10' height='10' rx='2' fill='#64748b' opacity='0.6'/>`n"
        $svgStorage += "  <text x='$($plotR - 106)' y='15' font-size='7.5' fill='#94a3b8' font-family='Segoe UI,sans-serif'>Good SSD Reference</text>`n"
        $yOff = 30
        foreach ($sb in $storBars) {
            $barMaxW = $plotW - 10
            $barW = if ($sb.Max -gt 0) { [math]::Round($sb.Value / $sb.Max * $barMaxW) } else { 0 }
            $barW = [math]::Max($barW, 0)
            $refX = if ($sb.Max -gt 0) { [math]::Round($plotL + 5 + ($sb.Ref / $sb.Max * $barMaxW)) } else { 0 }

            $svgStorage += "  <text x='$($plotL - 4)' y='$($yOff + 17)' text-anchor='end' font-size='8.5' font-weight='600' fill='#e2e8f0' font-family='Segoe UI,sans-serif'>$($sb.Label)</text>`n"
            # Background bar
            $svgStorage += "  <rect x='$($plotL + 5)' y='$($yOff + 4)' width='$barMaxW' height='22' rx='4' fill='#334155' opacity='0.4'/>`n"
            # Value bar
            if ($barW -gt 0) {
                $svgStorage += "  <rect x='$($plotL + 5)' y='$($yOff + 4)' width='$barW' height='22' rx='4' fill='$($sb.Color)' opacity='0.85'/>`n"
            }
            # Reference line
            if ($refX -gt $plotL -and $refX -lt $plotR) {
                $svgStorage += "  <line x1='$refX' y1='$($yOff + 2)' x2='$refX' y2='$($yOff + 28)' stroke='#94a3b8' stroke-width='1.5' stroke-dasharray='3,2'/>`n"
            }
            # Value label
            $valLabel = if ($sb.Value -ge 1000 -and $sb.Unit -eq "MB/s") { "$([math]::Round($sb.Value)) $($sb.Unit)" } elseif ($sb.Value -ge 1000) { "$([math]::Round($sb.Value / 1000, 1))K $($sb.Unit)" } else { "$([math]::Round($sb.Value, 1)) $($sb.Unit)" }
            $svgStorage += "  <text x='$($plotL + $barW + 10)' y='$($yOff + 18)' font-size='8' font-weight='700' fill='$($sb.Color)' font-family='Segoe UI,sans-serif'>$valLabel</text>`n"
            $yOff += 42
        }
        if ($avgLatency -gt 0) {
            $svgStorage += "  <text x='$($plotL + 5)' y='$($yOff + 10)' font-size='8' fill='#94a3b8' font-family='Segoe UI,sans-serif'>Avg Latency: $($avgLatency)ms | Tool: $storTool</text>`n"
        }
        $svgStorage += "</svg>"
    }

    # ══════════════════════════════════════════════════════════════════════════
    # CHART 7: Network Performance Bars
    # ══════════════════════════════════════════════════════════════════════════

    $svgNetwork = ""
    if ($netDL -gt 0 -or $netUL -gt 0) {
        $netMax = [math]::Max($netDL, $netUL) * 1.3
        if ($netMax -le 0) { $netMax = 100 }
        $barMaxW = $plotW - 10

        $dlBarW = [math]::Round($netDL / $netMax * $barMaxW)
        $ulBarW = [math]::Round($netUL / $netMax * $barMaxW)
        $dlColor = if ($netDL -ge 100) {"#22c55e"} elseif ($netDL -ge 25) {"#3bbde0"} else {"#f59e0b"}
        $ulColor = if ($netUL -ge 50) {"#22c55e"} elseif ($netUL -ge 10) {"#3bbde0"} else {"#f59e0b"}

        # Safe numeric extraction for color logic
        $pingVal = 0; try { $pingVal = [double]($netPing -replace '[^\d.]','') } catch {}
        $jitterVal = 0; try { if ($netJitter -ne 'N/A') { $jitterVal = [double]($netJitter -replace '[^\d.]','') } } catch {}
        $dnsVal = 0; try { if ($netDNS -ne 'N/A') { $dnsVal = [double]($netDNS -replace '[^\d.]','') } } catch {}
        $pktVal = 0; try { if ($netPktLoss -ne 'N/A') { $pktVal = [double]($netPktLoss -replace '[^\d.]','') } } catch {}

        $pingColor = if ($pingVal -lt 20) {"#22c55e"} elseif ($pingVal -lt 50) {"#3bbde0"} else {"#f59e0b"}
        $jitterColor = if ($jitterVal -lt 5) {"#22c55e"} else {"#f59e0b"}
        $pktColor = if ($pktVal -eq 0) {"#22c55e"} else {"#dc2626"}
        $dnsColor = if ($dnsVal -lt 50) {"#22c55e"} else {"#f59e0b"}

        $svgNetwork = @"
<svg viewBox="0 0 $chartW 200" width="100%" height="200px" xmlns="http://www.w3.org/2000/svg" style="background:#1a1a2e;border-radius:8px;">
  <!-- Download bar -->
  <text x="$($plotL - 4)" y="42" text-anchor="end" font-size="9" font-weight="600" fill="#e2e8f0" font-family="Segoe UI,sans-serif">Download</text>
  <rect x="$($plotL + 5)" y="28" width="$barMaxW" height="24" rx="5" fill="#334155" opacity="0.4"/>
  <rect x="$($plotL + 5)" y="28" width="$dlBarW" height="24" rx="5" fill="$dlColor" opacity="0.85"/>
  <text x="$($plotL + $dlBarW + 10)" y="44" font-size="9" font-weight="700" fill="$dlColor" font-family="Segoe UI,sans-serif">$([math]::Round($netDL, 1)) Mbps</text>
  <!-- Upload bar -->
  <text x="$($plotL - 4)" y="82" text-anchor="end" font-size="9" font-weight="600" fill="#e2e8f0" font-family="Segoe UI,sans-serif">Upload</text>
  <rect x="$($plotL + 5)" y="68" width="$barMaxW" height="24" rx="5" fill="#334155" opacity="0.4"/>
  <rect x="$($plotL + 5)" y="68" width="$ulBarW" height="24" rx="5" fill="$ulColor" opacity="0.85"/>
  <text x="$($plotL + $ulBarW + 10)" y="84" font-size="9" font-weight="700" fill="$ulColor" font-family="Segoe UI,sans-serif">$([math]::Round($netUL, 1)) Mbps</text>
  <!-- Metrics row -->
  <line x1="$plotL" y1="110" x2="$plotR" y2="110" stroke="#334155" stroke-width="0.5"/>
  <text x="$($plotL + 20)" y="134" text-anchor="middle" font-size="18" font-weight="700" fill="$pingColor" font-family="Segoe UI,sans-serif">$netPing</text>
  <text x="$($plotL + 20)" y="148" text-anchor="middle" font-size="7.5" fill="#94a3b8" font-family="Segoe UI,sans-serif">Ping (ms)</text>
  <text x="$([math]::Round($plotL + $plotW * 0.25))" y="134" text-anchor="middle" font-size="18" font-weight="700" fill="$jitterColor" font-family="Segoe UI,sans-serif">$netJitter</text>
  <text x="$([math]::Round($plotL + $plotW * 0.25))" y="148" text-anchor="middle" font-size="7.5" fill="#94a3b8" font-family="Segoe UI,sans-serif">Jitter (ms)</text>
  <text x="$([math]::Round($plotL + $plotW * 0.50))" y="134" text-anchor="middle" font-size="18" font-weight="700" fill="$pktColor" font-family="Segoe UI,sans-serif">$(if($netPktLoss -eq 'N/A'){"0"}else{$netPktLoss})%</text>
  <text x="$([math]::Round($plotL + $plotW * 0.50))" y="148" text-anchor="middle" font-size="7.5" fill="#94a3b8" font-family="Segoe UI,sans-serif">Packet Loss</text>
  <text x="$([math]::Round($plotL + $plotW * 0.75))" y="134" text-anchor="middle" font-size="18" font-weight="700" fill="$dnsColor" font-family="Segoe UI,sans-serif">$netDNS</text>
  <text x="$([math]::Round($plotL + $plotW * 0.75))" y="148" text-anchor="middle" font-size="7.5" fill="#94a3b8" font-family="Segoe UI,sans-serif">DNS (ms)</text>
  <!-- Connection info -->
  $(if($netWiFi){"<text x='$($plotL + 5)' y='175' font-size='8' fill='#94a3b8' font-family='Segoe UI,sans-serif'>WiFi Signal: $netWiFi%</text>"})
  $(if($netEthSpeed){"<text x='$($plotR - 5)' y='175' text-anchor='end' font-size='8' fill='#94a3b8' font-family='Segoe UI,sans-serif'>Ethernet: $netEthSpeed Mbps</text>"})
</svg>
"@
    }

    # ══════════════════════════════════════════════════════════════════════════
    # CHART 8: FPS Performance Bar Chart
    # ══════════════════════════════════════════════════════════════════════════

    $svgFPS = ""
    if ($fpsAvail -and $fpsAvg -gt 0) {
        $fpsMax = [math]::Max($fpsAvg * 1.4, 120)
        $barMaxW = $plotW - 10
        $ref60X = [math]::Round($plotL + 5 + (60 / $fpsMax * $barMaxW))

        $avgBarW = [math]::Round($fpsAvg / $fpsMax * $barMaxW)
        $lowBarW = [math]::Round($fps1Low / $fpsMax * $barMaxW)

        $avgColor = if ($fpsAvg -ge 60) {"#22c55e"} elseif ($fpsAvg -ge 30) {"#f59e0b"} else {"#dc2626"}
        $lowColor = if ($fps1Low -ge 60) {"#22c55e"} elseif ($fps1Low -ge 30) {"#f59e0b"} else {"#dc2626"}

        $svgFPS = @"
<svg viewBox="0 0 $chartW 180" width="100%" height="180px" xmlns="http://www.w3.org/2000/svg" style="background:#1a1a2e;border-radius:8px;">
  <!-- Avg FPS bar -->
  <text x="$($plotL - 4)" y="38" text-anchor="end" font-size="8.5" font-weight="600" fill="#e2e8f0" font-family="Segoe UI,sans-serif">Avg FPS</text>
  <rect x="$($plotL + 5)" y="24" width="$barMaxW" height="24" rx="5" fill="#334155" opacity="0.4"/>
  <rect x="$($plotL + 5)" y="24" width="$avgBarW" height="24" rx="5" fill="$avgColor" opacity="0.85"/>
  <text x="$($plotL + $avgBarW + 10)" y="40" font-size="9" font-weight="700" fill="$avgColor" font-family="Segoe UI,sans-serif">$([math]::Round($fpsAvg, 1)) FPS</text>
  <!-- 1% Low FPS bar -->
  <text x="$($plotL - 4)" y="78" text-anchor="end" font-size="8.5" font-weight="600" fill="#e2e8f0" font-family="Segoe UI,sans-serif">1% Low</text>
  <rect x="$($plotL + 5)" y="64" width="$barMaxW" height="24" rx="5" fill="#334155" opacity="0.4"/>
  <rect x="$($plotL + 5)" y="64" width="$lowBarW" height="24" rx="5" fill="$lowColor" opacity="0.85"/>
  <text x="$($plotL + $lowBarW + 10)" y="80" font-size="9" font-weight="700" fill="$lowColor" font-family="Segoe UI,sans-serif">$([math]::Round($fps1Low, 1)) FPS</text>
  <!-- 60 FPS reference line -->
  <line x1="$ref60X" y1="18" x2="$ref60X" y2="95" stroke="#f59e0b" stroke-width="1.5" stroke-dasharray="5,3"/>
  <text x="$ref60X" y="14" text-anchor="middle" font-size="7" fill="#f59e0b" font-family="Segoe UI,sans-serif">60 FPS Target</text>
  <!-- Frame time metrics -->
  <line x1="$plotL" y1="110" x2="$plotR" y2="110" stroke="#334155" stroke-width="0.5"/>
  <text x="$([math]::Round($plotL + $plotW * 0.25))" y="138" text-anchor="middle" font-size="20" font-weight="700" fill="$(if($fpsAvgFT -lt 16.7){"#22c55e"}elseif($fpsAvgFT -lt 33){"#f59e0b"}else{"#dc2626"})" font-family="Segoe UI,sans-serif">$([math]::Round($fpsAvgFT, 1))</text>
  <text x="$([math]::Round($plotL + $plotW * 0.25))" y="154" text-anchor="middle" font-size="7.5" fill="#94a3b8" font-family="Segoe UI,sans-serif">Avg Frame Time (ms)</text>
  <text x="$([math]::Round($plotL + $plotW * 0.75))" y="138" text-anchor="middle" font-size="20" font-weight="700" fill="$(if($fpsP99FT -lt 33){"#22c55e"}elseif($fpsP99FT -lt 50){"#f59e0b"}else{"#dc2626"})" font-family="Segoe UI,sans-serif">$([math]::Round($fpsP99FT, 1))</text>
  <text x="$([math]::Round($plotL + $plotW * 0.75))" y="154" text-anchor="middle" font-size="7.5" fill="#94a3b8" font-family="Segoe UI,sans-serif">P99 Frame Time (ms)</text>
</svg>
"@
    }

    # ══════════════════════════════════════════════════════════════════════════
    # SCORECARD DONUT
    # ══════════════════════════════════════════════════════════════════════════

    $donutR = 45; $donutCirc = [math]::Round(2 * [math]::PI * $donutR, 1)
    $donutOffset = [math]::Round($donutCirc - ($donutCirc * $scoreOverall / 100), 1)

    $svgScoreDonut = @"
<svg viewBox="0 0 200 200" width="180" height="180" xmlns="http://www.w3.org/2000/svg">
  <circle cx="100" cy="100" r="$donutR" fill="none" stroke="#1a1a2e" stroke-width="3" opacity="0.1"/>
  <circle cx="100" cy="100" r="$donutR" fill="none" stroke="#e5e7eb" stroke-width="12"/>
  <circle cx="100" cy="100" r="$donutR" fill="none" stroke="$overallColor" stroke-width="12"
    stroke-dasharray="$donutCirc" stroke-dashoffset="$donutOffset"
    transform="rotate(-90 100 100)" stroke-linecap="round"/>
  <text x="100" y="90" text-anchor="middle" font-size="36" font-weight="bold" fill="$overallColor" font-family="Segoe UI,sans-serif">$scoreGrade</text>
  <text x="100" y="112" text-anchor="middle" font-size="14" fill="#64748b" font-family="Segoe UI,sans-serif">$scoreOverall / 100</text>
  <text x="100" y="132" text-anchor="middle" font-size="11" fill="#94a3b8" font-family="Segoe UI,sans-serif">Gaming Perf</text>
</svg>
"@

    # ══════════════════════════════════════════════════════════════════════════
    # SCORECARD CHIPS
    # ══════════════════════════════════════════════════════════════════════════

    function Get-PerfChipStyle([string]$val) {
        $lv = "$val".ToLower()
        if ($lv -match "^(excellent|a|pass)$" -or ($val -match '^\d+$' -and [int]$val -ge 80)) {
            return "background:#dcfce7;color:#166534;border:1px solid #bbf7d0;"
        } elseif ($lv -match "^(good|b|ok)$" -or ($val -match '^\d+$' -and [int]$val -ge 60)) {
            return "background:#dbeafe;color:#1e40af;border:1px solid #bfdbfe;"
        } elseif ($lv -match "^(warning|fair|c|d)$" -or ($val -match '^\d+$' -and [int]$val -ge 40)) {
            return "background:#fef3c7;color:#92400e;border:1px solid #fde68a;"
        } else {
            return "background:#fee2e2;color:#991b1b;border:1px solid #fecaca;"
        }
    }

    $thermalChipStyle  = Get-PerfChipStyle "$scoreThermal"
    $fpsChipStyle      = Get-PerfChipStyle "$scoreFPS"
    $storageChipStyle  = Get-PerfChipStyle "$scoreStorage"
    $powerChipStyle    = Get-PerfChipStyle "$scorePower"

    # ══════════════════════════════════════════════════════════════════════════
    # THERMAL SNAPSHOT TABLE
    # ══════════════════════════════════════════════════════════════════════════

    $thermalSnapshotHTML = ""
    if ($PreStress -or $PostStress -or $Recovery) {
        $thermalSnapshotHTML = "<div class='sub-header'>Thermal Snapshots</div><table><tr><th>Phase</th><th>CPU Temp</th><th>GPU Temp</th><th>Notes</th></tr>`n"
        if ($PreStress) {
            $thermalSnapshotHTML += "<tr><td>Pre-Stress (Idle)</td><td>$(if($PreStress.CPUTempC){"$($PreStress.CPUTempC)C"}else{"N/A"})</td><td>$(if($PreStress.GPUTempC){"$($PreStress.GPUTempC)C"}else{"N/A"})</td><td>Baseline temperatures before load</td></tr>`n"
        }
        if ($PostStress) {
            $psCPU = if ($PostStress.CPUTempC) { [double]$PostStress.CPUTempC } else { 0 }
            $psGPU = if ($PostStress.GPUTempC) { [double]$PostStress.GPUTempC } else { 0 }
            $psNote = if ($psCPU -gt 85 -or $psGPU -gt 85) { "<span class='fail'>Critical temperatures reached</span>" } elseif ($psCPU -gt 70 -or $psGPU -gt 70) { "<span class='warn'>Elevated but within tolerance</span>" } else { "<span class='pass'>Within safe limits</span>" }
            $thermalSnapshotHTML += "<tr><td>Post-Stress (Peak)</td><td>$(if($psCPU -gt 0){"${psCPU}C"}else{"N/A"})</td><td>$(if($psGPU -gt 0){"${psGPU}C"}else{"N/A"})</td><td>$psNote</td></tr>`n"
        }
        if ($Recovery) {
            $recNote = if ($coolRecoverySec -gt 0) { "Recovered in ${coolRecoverySec}s" } else { "" }
            $thermalSnapshotHTML += "<tr><td>Recovery (Cool-down)</td><td>$(if($Recovery.CPUTempC){"$($Recovery.CPUTempC)C"}else{"N/A"})</td><td>$(if($Recovery.GPUTempC){"$($Recovery.GPUTempC)C"}else{"N/A"})</td><td>$recNote</td></tr>`n"
        }
        $thermalSnapshotHTML += "</table>"
    }

    # ══════════════════════════════════════════════════════════════════════════
    # POWER STABILITY SECTION
    # ══════════════════════════════════════════════════════════════════════════

    $pwrColor = if ($pwrScore -ge 80) {"#22c55e"} elseif ($pwrScore -ge 60) {"#f59e0b"} else {"#dc2626"}
    $pwrDonutR = 35; $pwrCirc = [math]::Round(2 * [math]::PI * $pwrDonutR, 1)
    $pwrOff = [math]::Round($pwrCirc - ($pwrCirc * $pwrScore / 100), 1)

    $powerHTML = @"
<div style="display:flex;align-items:center;gap:24px;margin:14px 0;">
<div style="text-align:center;">
<svg viewBox="0 0 100 100" width="100" height="100" xmlns="http://www.w3.org/2000/svg">
  <circle cx="50" cy="50" r="$pwrDonutR" fill="none" stroke="#e5e7eb" stroke-width="7"/>
  <circle cx="50" cy="50" r="$pwrDonutR" fill="none" stroke="$pwrColor" stroke-width="7"
    stroke-dasharray="$pwrCirc" stroke-dashoffset="$pwrOff"
    transform="rotate(-90 50 50)" stroke-linecap="round"/>
  <text x="50" y="48" text-anchor="middle" font-size="16" font-weight="bold" fill="$pwrColor" font-family="Segoe UI,sans-serif">$pwrScore</text>
  <text x="50" y="62" text-anchor="middle" font-size="8" fill="#64748b" font-family="Segoe UI,sans-serif">/ 100</text>
</svg>
<div style="font-size:8pt;font-weight:600;color:$pwrColor;margin-top:4px;">Power Score</div>
</div>
<div style="flex:1;">
<table><tr><th>Metric</th><th>Value</th><th>Status</th></tr>
<tr><td>Kernel Power Events (30d)</td><td>$pwrKernel</td><td>$(if($pwrKernel -eq 0){"<span class='pass'>$iconPass Clean</span>"}elseif($pwrKernel -le 2){"<span class='warn'>$iconWarn Monitor</span>"}else{"<span class='fail'>$iconFail Concerning</span>"})</td></tr>
<tr><td>Unexpected Shutdowns (30d)</td><td>$pwrShutdown</td><td>$(if($pwrShutdown -eq 0){"<span class='pass'>$iconPass None</span>"}elseif($pwrShutdown -le 1){"<span class='warn'>$iconWarn Investigate</span>"}else{"<span class='fail'>$iconFail Replace PSU?</span>"})</td></tr>
</table>
$(if($pwrKernel -gt 2 -or $pwrShutdown -gt 1){"<div style='padding:8px 12px;background:#fef2f2;border-left:4px solid #dc2626;border-radius:4px;margin-top:8px;'><span class='fail'>$iconFail</span> <strong>Power instability detected.</strong> Check PSU, power cables, and wall outlet. A UPS is strongly recommended.</div>"})
</div>
</div>
"@

    # ══════════════════════════════════════════════════════════════════════════
    # RECOMMENDATIONS
    # ══════════════════════════════════════════════════════════════════════════

    $recsHTML = ""
    if ($recs.Count -gt 0) {
        foreach ($r in $recs) {
            $rText = if ($r -is [hashtable] -or $r -is [pscustomobject]) {
                $rt = if ($r.Text) { $r.Text } elseif ($r.Message) { $r.Message } else { "$r" }
                $rt
            } else { "$r" }
            $rIcon = $iconWarn
            $rBg = "#fffbeb"
            $rBorder = "#f59e0b"
            if ($rText -match "(?i)critical|fail|replace|urgent") { $rIcon = $iconFail; $rBg = "#fef2f2"; $rBorder = "#dc2626" }
            elseif ($rText -match "(?i)pass|good|excellent|optimal") { $rIcon = $iconPass; $rBg = "#f0fdf4"; $rBorder = "#22c55e" }
            $recsHTML += "<div style='display:flex;align-items:flex-start;gap:10px;padding:8px 14px;margin:4px 0;border-radius:6px;background:$rBg;border-left:4px solid $rBorder;'><span style='font-size:13pt;flex-shrink:0;'>$rIcon</span><span style='font-size:9.5pt;color:#1e293b;line-height:1.5;'>$([System.Web.HttpUtility]::HtmlEncode($rText))</span></div>`n"
        }
    }

    # ══════════════════════════════════════════════════════════════════════════
    # TECHNICIAN NOTES
    # ══════════════════════════════════════════════════════════════════════════

    $techNotesHTML = if ($techNotes) {
        "<div class='section-header'><span class='section-icon'>&#128221;</span> Technician Notes</div><div style='padding:14px 18px;background:#f8fafc;border:1px solid #d1d5db;border-radius:8px;min-height:50px;white-space:pre-wrap;font-size:9.5pt;line-height:1.7;margin-bottom:16px;'>$([System.Web.HttpUtility]::HtmlEncode($techNotes))</div>"
    } else { "" }

    # ══════════════════════════════════════════════════════════════════════════
    # ASSEMBLE THE FULL HTML
    # ══════════════════════════════════════════════════════════════════════════

$html = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8"/>
<title>Gaming Performance &amp; Stability Report - $customerName</title>
<style>
@page { size: A4; margin: 0.5in 0.6in 0.9in 0.6in; }
* { margin:0; padding:0; box-sizing:border-box; }
body { font-family: 'Segoe UI', -apple-system, Tahoma, sans-serif; font-size: 9.5pt; color: #1e293b; line-height: 1.6; background: #fff; }
h1,h2,h3,h4 { margin:0; }
@media print {
    body { -webkit-print-color-adjust: exact; print-color-adjust: exact; }
    .page-break { page-break-before: always; }
    .no-break { page-break-inside: avoid; }
}
.page-break { page-break-before: always; }
.print-footer {
    position: fixed; bottom: 0; left: 0; right: 0;
    padding: 6px 0; border-top: 1.5px solid #0d4b71;
    text-align: center; font-size: 7.5pt; color: #94a3b8; background: #fff;
}
.print-footer strong { color: #0d4b71; font-size: 7.5pt; }
.print-footer .report-name { color: #475569; }
.no-break { page-break-inside: avoid; }
.section-header {
    background: linear-gradient(135deg, #1a1a2e 0%, #0d4b71 100%);
    color: #fff; padding: 10px 20px; font-size: 12pt; font-weight: 600;
    margin: 24px 0 14px 0; border-radius: 6px; letter-spacing: 0.5px;
    display: flex; align-items: center; gap: 10px;
}
.section-header .section-icon { font-size: 14pt; opacity: 0.85; }
.sub-header {
    color: #0d4b71; font-size: 10.5pt; font-weight: 700; margin: 18px 0 8px 0;
    padding-bottom: 5px; border-bottom: 2px solid #2596be; letter-spacing: 0.3px;
}
table { width: 100%; border-collapse: collapse; margin-bottom: 14px; font-size: 9pt; }
th {
    background: #0d4b71; color: #fff; padding: 7px 10px; text-align: left;
    font-weight: 600; font-size: 8.5pt; text-transform: uppercase; letter-spacing: 0.5px;
}
td { padding: 6px 10px; border-bottom: 1px solid #e2e8f0; vertical-align: middle; }
tr:nth-child(even) td { background: #f8fafc; }
tr:hover td { background: #eaf7fc; }
.pass { color: #16a34a; font-weight: 600; }
.fail { color: #dc2626; font-weight: 600; }
.warn { color: #f59e0b; font-weight: 600; }
.chart-box {
    background: #fff; border: 1px solid #e2e8f0; border-radius: 10px;
    padding: 16px; margin: 12px 0; box-shadow: 0 1px 3px rgba(0,0,0,0.04);
}
.chart-box .chart-title {
    font-size: 10.5pt; font-weight: 700; color: #0d4b71; margin-bottom: 10px;
    padding-bottom: 4px; border-bottom: 1px solid #e2e8f0;
}
.summary-strip { display: flex; gap: 10px; margin: 14px 0; }
.summary-chip {
    flex: 1; text-align: center; padding: 10px 8px; background: #f8fafc;
    border: 1px solid #e2e8f0; border-radius: 8px;
}
.summary-chip .chip-val { font-size: 15pt; font-weight: 700; color: #0a1628; display: block; }
.summary-chip .chip-lbl { font-size: 7.5pt; color: #64748b; text-transform: uppercase; font-weight: 600; letter-spacing: 0.3px; }
.scorecard-grid {
    display: grid; grid-template-columns: 1fr 1fr; gap: 8px; margin: 14px 0;
}
.score-chip {
    display: flex; align-items: center; justify-content: space-between;
    padding: 8px 14px; border-radius: 8px; font-size: 9.5pt;
}
.score-chip .sc-label { font-weight: 600; color: #334155; }
.score-chip .sc-value { font-weight: 700; font-size: 10pt; padding: 2px 10px; border-radius: 12px; }
.qr-row { display: flex; justify-content: center; gap: 60px; margin: 20px 0; }
.qr-item { text-align: center; }
.qr-item img { width: 140px; height: 140px; border-radius: 8px; }
.qr-item .qr-fallback { width: 140px; height: 140px; border: 2px dashed #94a3b8; border-radius: 8px; display: flex; align-items: center; justify-content: center; font-size: 7.5pt; color: #94a3b8; }
.qr-label { font-size: 9pt; font-weight: 600; color: #0d4b71; margin-top: 8px; }
.qr-sublabel { font-size: 7.5pt; color: #64748b; margin-top: 2px; }
</style>
</head>
<body>

<div class="print-footer">
<span class="report-name">Gaming Performance &amp; Stability Report</span> &nbsp;|&nbsp; <strong>$COMPANY</strong> &nbsp;|&nbsp; $WEBSITE &nbsp;|&nbsp; $PHONE
</div>

<!-- =============================== PAGE 1: COVER =============================== -->
<div style="page-break-after:always;">
$(if($bannerUri){"<div style='text-align:center;margin-bottom:12px;'><img src='$bannerUri' alt='PC Plus Gaming Performance' style='width:100%;border-radius:8px;'/></div>"})
<div style="text-align:center;padding:20px 0 10px;">
$logoHTML
<div style="font-size:17pt;font-weight:700;color:#0d4b71;margin-top:12px;letter-spacing:0.5px;">PC Plus 360 Gaming Performance &amp; Stability Report</div>
<div style="font-size:10pt;color:#3bbde0;margin-top:4px;">Comprehensive Stress Testing &amp; Time-Series Analysis</div>
</div>

<!-- Customer info + Donut -->
<div style="display:flex;gap:20px;align-items:center;margin:16px 0;">
<div style="flex:1;">
<div style="background:#f8fafc;border:1px solid #e2e8f0;border-radius:10px;padding:14px;">
<table style="width:100%;font-size:10pt;border:none;margin:0;">
<tr><td style="border:none;padding:4px 8px;color:#64748b;font-weight:600;width:110px;">Customer:</td><td style="border:none;padding:4px 8px;color:#0a1628;font-weight:700;">$customerName</td></tr>
$(if($customerPhone){"<tr><td style='border:none;padding:4px 8px;color:#64748b;font-weight:600;'>Phone:</td><td style='border:none;padding:4px 8px;color:#0a1628;'>$customerPhone</td></tr>"})
$(if($customerEmail){"<tr><td style='border:none;padding:4px 8px;color:#64748b;font-weight:600;'>Email:</td><td style='border:none;padding:4px 8px;color:#0a1628;'>$customerEmail</td></tr>"})
$(if($contactName){"<tr><td style='border:none;padding:4px 8px;color:#64748b;font-weight:600;'>Contact:</td><td style='border:none;padding:4px 8px;color:#0a1628;'>$contactName</td></tr>"})
<tr><td style="border:none;padding:4px 8px;color:#64748b;font-weight:600;">Device:</td><td style="border:none;padding:4px 8px;color:#0a1628;">$compName</td></tr>
<tr><td style="border:none;padding:4px 8px;color:#64748b;font-weight:600;">Date:</td><td style="border:none;padding:4px 8px;color:#0a1628;">$date</td></tr>
<tr><td style="border:none;padding:4px 8px;color:#64748b;font-weight:600;">Technician:</td><td style="border:none;padding:4px 8px;color:#0a1628;">$techName</td></tr>
$(if($ScanMode){"<tr><td style='border:none;padding:4px 8px;color:#64748b;font-weight:600;'>Scan Mode:</td><td style='border:none;padding:4px 8px;color:#0a1628;'>$ScanMode</td></tr>"})
</table>
</div>
</div>
<div style="text-align:center;">
$svgScoreDonut
</div>
</div>

<!-- System specs strip -->
<div class="summary-strip">
<div class="summary-chip"><span class="chip-val" style="font-size:10pt;">$cpuModel</span><span class="chip-lbl">Processor</span></div>
</div>
<div class="summary-strip">
<div class="summary-chip"><span class="chip-val" style="font-size:10pt;">$gpuName</span><span class="chip-lbl">Graphics Card</span></div>
<div class="summary-chip"><span class="chip-val">$ramTotal GB</span><span class="chip-lbl">RAM</span></div>
</div>

<!-- Scorecard -->
<div class="section-header" style="margin-top:18px;"><span class="section-icon">&#127942;</span> Performance Scorecard</div>
<div style="display:flex;align-items:flex-start;gap:16px;margin:10px 0;">
<div style="flex:1;">
<div class="score-chip" style="margin-bottom:6px;background:#f8fafc;border:1px solid #e2e8f0;border-radius:8px;">
<span class="sc-label">Gaming Performance Score</span>
<span class="sc-value" style="$(Get-PerfChipStyle "$scoreOverall") font-size:12pt;">$scoreOverall / 100</span>
</div>
<div class="scorecard-grid">
<div class="score-chip" style="$thermalChipStyle">
<span class="sc-label">Thermal Score</span>
<span class="sc-value" style="$thermalChipStyle">$scoreThermal / 100</span>
</div>
<div class="score-chip" style="$fpsChipStyle">
<span class="sc-label">FPS Stability</span>
<span class="sc-value" style="$fpsChipStyle">$scoreFPS</span>
</div>
<div class="score-chip" style="$storageChipStyle">
<span class="sc-label">Storage Speed</span>
<span class="sc-value" style="$storageChipStyle">$scoreStorage</span>
</div>
<div class="score-chip" style="$powerChipStyle">
<span class="sc-label">Power Stability</span>
<span class="sc-value" style="$powerChipStyle">$scorePower</span>
</div>
</div>
</div>
</div>

<!-- System info table -->
<div class="sub-header">System Specifications</div>
<table><tr><th style="width:35%;">Component</th><th>Details</th></tr>
<tr><td>Computer Name</td><td><strong>$compName</strong></td></tr>
$(if($SystemInfo.Manufacturer){"<tr><td>Manufacturer / Model</td><td>$($SystemInfo.Manufacturer) $($SystemInfo.Model)</td></tr>"})
$(if($SystemInfo.Serial){"<tr><td>Serial Number</td><td style='font-family:Consolas,monospace;letter-spacing:0.5px;'>$($SystemInfo.Serial)</td></tr>"})
$(if($SystemInfo.OSVersion){"<tr><td>Operating System</td><td>$($SystemInfo.OSVersion)$(if($SystemInfo.OSBuild){" (Build $($SystemInfo.OSBuild))"})</td></tr>"})
<tr><td>CPU</td><td>$cpuModel$(if($SystemInfo.CPUCores){" ($($SystemInfo.CPUCores)C / $($SystemInfo.CPUThreads)T)"})</td></tr>
<tr><td>RAM</td><td>$ramTotal GB</td></tr>
$(if($SystemInfo.GPUs){($SystemInfo.GPUs | ForEach-Object {"<tr><td>GPU</td><td>$($_.Name)$(if($_.VRAM_MB -gt 0){" ($($_.VRAM_MB) MB VRAM)"})</td></tr>"}) -join "`n"})
$(if($SystemInfo.Disks){($SystemInfo.Disks | ForEach-Object {"<tr><td>Disk ($($_.Drive))</td><td>$($_.Model) - $($_.SizeGB) GB $(if($_.UsedPct){"($($_.UsedPct)% used)"})</td></tr>"}) -join "`n"})
</table>
</div>

<!-- =============================== PAGE 2: TEMPERATURE & USAGE CHARTS =============================== -->
<div class="page-break"></div>
<div class="section-header"><span class="section-icon">&#127777;</span> Thermal Analysis - Time Series</div>

$(if($svgCPUTemp){@"
<div class='chart-box no-break'>
<div class='chart-title'>CPU Temperature Over Time</div>
$svgCPUTemp
</div>
"@} else {"<div class='chart-box'><div class='chart-title'>CPU Temperature Over Time</div><div style='text-align:center;padding:30px;color:#94a3b8;'>No time-series data available</div></div>"})

$(if($svgGPUTemp){@"
<div class='chart-box no-break'>
<div class='chart-title'>GPU Temperature Over Time</div>
$svgGPUTemp
</div>
"@} else {"<div class='chart-box'><div class='chart-title'>GPU Temperature Over Time</div><div style='text-align:center;padding:30px;color:#94a3b8;'>No GPU temperature data available</div></div>"})

$(if($svgUsage){@"
<div class='chart-box no-break'>
<div class='chart-title'>CPU / RAM Usage Over Time</div>
$svgUsage
</div>
"@} else {"<div class='chart-box'><div class='chart-title'>CPU / RAM Usage Over Time</div><div style='text-align:center;padding:30px;color:#94a3b8;'>No usage data available</div></div>"})

$(if($svgClock){@"
<div class='chart-box no-break'>
<div class='chart-title'>CPU Clock Speed Over Time</div>
$svgClock
$(if($throttle){"<div style='margin-top:8px;padding:8px 12px;background:#fef2f2;border-left:4px solid #dc2626;border-radius:4px;'><span class='fail'>$iconFail</span> <strong>Thermal throttling detected!</strong> CPU clock speed dropped significantly under load. Check cooling solution.</div>"})
</div>
"@} else {"<div class='chart-box'><div class='chart-title'>CPU Clock Speed Over Time</div><div style='text-align:center;padding:30px;color:#94a3b8;'>No clock speed data available</div></div>"})

$thermalSnapshotHTML

<!-- =============================== PAGE 3: FAN, STORAGE, FPS =============================== -->
<div class="page-break"></div>

$(if($svgFan){@"
<div class='section-header'><span class='section-icon'>&#127744;</span> Fan Speed Over Time</div>
<div class='chart-box no-break'>
<div class='chart-title'>Fan RPM During Stress Test</div>
$svgFan
$(if($coolRecoverySec -gt 0){"<div style='margin-top:8px;font-size:9pt;color:#64748b;'>Cooling recovery time: <strong>${coolRecoverySec}s</strong> to return to idle temperatures</div>"})
</div>
"@} else {"<div class='section-header'><span class='section-icon'>&#127744;</span> Fan Speed Over Time</div><div class='chart-box'><div class='chart-title'>Fan RPM</div><div style='text-align:center;padding:30px;color:#94a3b8;'>No fan RPM data available</div></div>"})

<div class="section-header"><span class="section-icon">&#128190;</span> Storage Performance</div>
$(if($svgStorage){@"
<div class='chart-box no-break'>
<div class='chart-title'>Disk Benchmark Results$(if($storTool -ne 'N/A'){" ($storTool)"})</div>
$svgStorage
</div>
"@} else {"<div class='chart-box'><div class='chart-title'>Disk Benchmark Results</div><div style='text-align:center;padding:30px;color:#94a3b8;'>No storage benchmark data available</div></div>"})

$(if($fpsAvail){@"
<div class='section-header'><span class='section-icon'>&#127918;</span> FPS Performance (PresentMon)</div>
<div class='chart-box no-break'>
<div class='chart-title'>Frame Rate &amp; Frame Time Analysis</div>
$svgFPS
</div>
"@})

<!-- =============================== PAGE 4: NETWORK, POWER, RECOMMENDATIONS =============================== -->
<div class="page-break"></div>
<div class="section-header"><span class="section-icon">&#127760;</span> Network Performance</div>
$(if($svgNetwork){@"
<div class='chart-box no-break'>
<div class='chart-title'>Speed &amp; Latency Analysis</div>
$svgNetwork
</div>
"@} else {"<div class='chart-box'><div class='chart-title'>Network Performance</div><div style='text-align:center;padding:30px;color:#94a3b8;'>No network test data available</div></div>"})

<div class="section-header"><span class="section-icon">&#9889;</span> Power Stability Analysis</div>
<div class="chart-box no-break">
$powerHTML
</div>

$(if($recsHTML){@"
<div class='section-header'><span class='section-icon'>&#128161;</span> Recommendations</div>
<div style='margin:8px 0;'>
$recsHTML
</div>
"@})

$techNotesHTML

<!-- =============================== BACK PAGE =============================== -->
<div class="page-break"></div>
<div style="text-align:center;padding-top:60px;">
$(if($logoDataUri){"<img src='$logoDataUri' alt='PC Plus Computing' style='width:250px;margin-bottom:30px;'/>"}else{"<div style='background:linear-gradient(135deg,#0a1628,#0d4b71);color:#fff;padding:16px 40px;font-size:18pt;font-weight:bold;letter-spacing:3px;border-radius:6px;margin-bottom:30px;display:inline-block;'>PC PLUS COMPUTING</div>"})
<div style="font-size:12pt;color:#0d4b71;font-weight:600;margin-bottom:6px;">Thank you for choosing PC Plus Computing</div>
<div style="font-size:10pt;color:#64748b;margin-bottom:30px;">Your Security, Our Priority &nbsp;|&nbsp; 30+ Years in Service &nbsp;|&nbsp; 4.9&#9733; Google Rating</div>
<div class="qr-row">
<div class="qr-item">
$(if($qrAppUri){"<img src='$qrAppUri' alt='Book Appointment'/>"}else{"<div class='qr-fallback'>Book<br/>Appointment</div>"})
<div class="qr-label">Book an Appointment</div>
<div class="qr-sublabel">pcpluscomputing.com/appointments</div>
</div>
<div class="qr-item">
$(if($qrSvcUri){"<img src='$qrSvcUri' alt='Send Info'/>"}else{"<div class='qr-fallback'>Send Us<br/>Info</div>"})
<div class="qr-label">Send Us Your Info</div>
<div class="qr-sublabel">Service Request Portal</div>
</div>
</div>
<div style="margin-top:40px;padding:20px;background:#f8fafc;border-radius:10px;border:1px solid #e2e8f0;display:inline-block;">
<div style="font-size:11pt;font-weight:700;color:#0a1628;margin-bottom:8px;">Get In Touch</div>
<div style="font-size:10pt;color:#475569;">
&#127760; $WEBSITE &nbsp;&nbsp;|&nbsp;&nbsp; &#128222; $PHONE
</div>
</div>
<div style="margin-top:40px;font-size:8pt;color:#94a3b8;">
Gaming Performance &amp; Stability Report generated $date<br/>
Technician: $techName &nbsp;|&nbsp; Device: $compName
</div>
</div>

</body>
</html>
"@

    return $html
}

# ─────────────────────────────────────────────────────────────────────────────
# BENCHMARK COMPARISON HTML SNIPPET
# ─────────────────────────────────────────────────────────────────────────────

function Build-BenchmarkComparisonHTML {
    param(
        [hashtable]$CurrentScores,
        [hashtable]$PercentileOverall,
        [hashtable]$PercentileThermal,
        [hashtable]$PercentileStorage,
        [hashtable]$PercentileNetwork
    )
    Write-DiagLog "Building benchmark comparison HTML snippet..."

    # Safe value extraction
    $overallScore = if ($CurrentScores -and $CurrentScores.Overall) { $CurrentScores.Overall } else { 0 }
    $overallPct   = if ($PercentileOverall)  { $PercentileOverall.Percentile }  else { 0 }
    $overallAvg   = if ($PercentileOverall)  { $PercentileOverall.AvgScore }    else { 0 }
    $overallBest  = if ($PercentileOverall)  { $PercentileOverall.BestScore }   else { 0 }
    $overallWorst = if ($PercentileOverall)  { $PercentileOverall.WorstScore }  else { 0 }
    $totalSamples = if ($PercentileOverall)  { $PercentileOverall.TotalSamples } else { 0 }
    $similarCount = if ($PercentileOverall)  { $PercentileOverall.SimilarSystemCount } else { 0 }

    $thermalScore = if ($CurrentScores -and $CurrentScores.Thermal) { $CurrentScores.Thermal } else { 0 }
    $thermalPct   = if ($PercentileThermal) { $PercentileThermal.Percentile } else { 0 }
    $thermalAvg   = if ($PercentileThermal) { $PercentileThermal.AvgScore }   else { 0 }

    $storageScore = if ($CurrentScores -and $CurrentScores.Storage) { $CurrentScores.Storage } else { 0 }
    $storagePct   = if ($PercentileStorage) { $PercentileStorage.Percentile } else { 0 }
    $storageAvg   = if ($PercentileStorage) { $PercentileStorage.AvgScore }   else { 0 }

    $networkScore = if ($CurrentScores -and $CurrentScores.Network) { $CurrentScores.Network } else { 0 }
    $networkPct   = if ($PercentileNetwork) { $PercentileNetwork.Percentile } else { 0 }
    $networkAvg   = if ($PercentileNetwork) { $PercentileNetwork.AvgScore }   else { 0 }

    # Color for percentile
    function Get-PctColor($pct) {
        if ($pct -ge 75) { return "#22c55e" }
        elseif ($pct -ge 50) { return "#f59e0b" }
        elseif ($pct -ge 25) { return "#f97316" }
        else { return "#ef4444" }
    }

    $overallColor  = Get-PctColor $overallPct
    $thermalColor  = Get-PctColor $thermalPct
    $storageColor  = Get-PctColor $storagePct
    $networkColor  = Get-PctColor $networkPct

    # Build the HTML snippet
    $html = @"
<!-- Benchmark Comparison Section -->
<div style="margin:30px 0;padding:24px;background:#0f172a;border-radius:12px;border:1px solid #1e293b;font-family:'Segoe UI',sans-serif;">
    <div style="display:flex;align-items:center;margin-bottom:18px;">
        <div style="width:36px;height:36px;background:linear-gradient(135deg,#6366f1,#8b5cf6);border-radius:8px;display:flex;align-items:center;justify-content:center;margin-right:12px;">
            <span style="color:white;font-size:16px;font-weight:bold;">&#9733;</span>
        </div>
        <div>
            <div style="font-size:15px;font-weight:700;color:#f1f5f9;">Your System vs Others Tested</div>
            <div style="font-size:11px;color:#64748b;">Based on $totalSamples benchmarks across $similarCount similar systems</div>
        </div>
    </div>

    <!-- Overall Percentile Hero -->
    <div style="text-align:center;padding:20px;margin-bottom:20px;background:#1e293b;border-radius:10px;">
        <div style="font-size:42px;font-weight:800;color:$overallColor;">$($overallPct)%</div>
        <div style="font-size:13px;color:#94a3b8;margin-top:4px;">Your score of <span style="color:#f1f5f9;font-weight:600;">$overallScore</span> is better than <span style="color:$overallColor;font-weight:600;">$($overallPct)%</span> of tested systems</div>
        <!-- Gradient bar -->
        <div style="margin:16px auto 0;max-width:400px;position:relative;">
            <div style="height:10px;border-radius:5px;background:linear-gradient(90deg,#ef4444 0%,#f97316 25%,#f59e0b 50%,#22c55e 75%,#16a34a 100%);"></div>
            <div style="position:absolute;top:-4px;left:$($overallPct)%;transform:translateX(-50%);width:18px;height:18px;background:white;border-radius:50%;border:3px solid $overallColor;box-shadow:0 0 8px rgba(0,0,0,0.3);"></div>
        </div>
        <div style="display:flex;justify-content:space-between;max-width:400px;margin:8px auto 0;">
            <span style="font-size:9px;color:#64748b;">Worst: $overallWorst</span>
            <span style="font-size:9px;color:#64748b;">Avg: $overallAvg</span>
            <span style="font-size:9px;color:#64748b;">Best: $overallBest</span>
        </div>
    </div>

    <!-- Category Breakdown -->
    <div style="display:grid;grid-template-columns:1fr 1fr;gap:12px;">
        <!-- Thermal -->
        <div style="padding:14px;background:#1e293b;border-radius:8px;">
            <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:8px;">
                <span style="font-size:12px;font-weight:600;color:#f1f5f9;">Thermal</span>
                <span style="font-size:12px;font-weight:700;color:$thermalColor;">$($thermalPct)%ile</span>
            </div>
            <div style="height:6px;background:#334155;border-radius:3px;overflow:hidden;">
                <div style="height:100%;width:$($thermalPct)%;background:$thermalColor;border-radius:3px;"></div>
            </div>
            <div style="font-size:10px;color:#64748b;margin-top:6px;">Score: $thermalScore (avg: $thermalAvg)</div>
        </div>
        <!-- Storage -->
        <div style="padding:14px;background:#1e293b;border-radius:8px;">
            <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:8px;">
                <span style="font-size:12px;font-weight:600;color:#f1f5f9;">Storage</span>
                <span style="font-size:12px;font-weight:700;color:$storageColor;">$($storagePct)%ile</span>
            </div>
            <div style="height:6px;background:#334155;border-radius:3px;overflow:hidden;">
                <div style="height:100%;width:$($storagePct)%;background:$storageColor;border-radius:3px;"></div>
            </div>
            <div style="font-size:10px;color:#64748b;margin-top:6px;">Score: $storageScore (avg: $storageAvg)</div>
        </div>
        <!-- Network -->
        <div style="padding:14px;background:#1e293b;border-radius:8px;">
            <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:8px;">
                <span style="font-size:12px;font-weight:600;color:#f1f5f9;">Network</span>
                <span style="font-size:12px;font-weight:700;color:$networkColor;">$($networkPct)%ile</span>
            </div>
            <div style="height:6px;background:#334155;border-radius:3px;overflow:hidden;">
                <div style="height:100%;width:$($networkPct)%;background:$networkColor;border-radius:3px;"></div>
            </div>
            <div style="font-size:10px;color:#64748b;margin-top:6px;">Score: $networkScore (avg: $networkAvg)</div>
        </div>
        <!-- Database Info -->
        <div style="padding:14px;background:#1e293b;border-radius:8px;">
            <div style="font-size:12px;font-weight:600;color:#f1f5f9;margin-bottom:8px;">Database</div>
            <div style="font-size:10px;color:#94a3b8;line-height:1.6;">
                Total benchmarks: <span style="color:#f1f5f9;">$totalSamples</span><br/>
                Similar systems: <span style="color:#f1f5f9;">$similarCount</span><br/>
                Avg overall score: <span style="color:#f1f5f9;">$overallAvg</span>
            </div>
        </div>
    </div>
</div>
"@

    return $html
}

# ─────────────────────────────────────────────────────────────────────────────
# AUTO-UPLOAD - Silent background upload after every report generation
# ─────────────────────────────────────────────────────────────────────────────

function Invoke-AutoUploadReport {
    <#
    .SYNOPSIS
        Silently uploads a report file in the background if auto-upload is enabled.
    .DESCRIPTION
        Reads PCPlus360-Config.json and, if AutoUploadEnabled is true AND a server
        URL is configured, uploads the report using the same logic as Send-ReportToServer
        but without any UI dialogs. Logs success/failure via Write-DiagLog only.
    .PARAMETER ReportPath
        Path to the report file (HTML or PDF) to upload.
    .PARAMETER CustomerName
        Customer name for upload metadata.
    .PARAMETER ComputerName
        Computer name for upload metadata.
    .PARAMETER TechName
        Technician name for upload metadata.
    .PARAMETER ScanMode
        Scan mode label for upload metadata.
    #>
    param(
        [Parameter(Mandatory)][string]$ReportPath,
        [string]$CustomerName  = "",
        [string]$ComputerName  = "",
        [string]$TechName      = "",
        [string]$ScanMode      = ""
    )

    $result = @{ Uploaded = $false; Message = "" }

    # Check file exists
    if (-not (Test-Path $ReportPath)) {
        $result.Message = "Auto-upload skipped: file not found '$ReportPath'"
        Write-DiagLog $result.Message "WARN"
        return $result
    }

    # Load config
    $config = Invoke-Safe { Initialize-PaperlessConfig } $null
    if (-not $config) {
        $result.Message = "Auto-upload skipped: could not load config"
        Write-DiagLog $result.Message "WARN"
        return $result
    }

    # Check if auto-upload is enabled
    $autoEnabled = $true
    if ($null -ne $config.AutoUploadEnabled) {
        $autoEnabled = [bool]$config.AutoUploadEnabled
    }
    if (-not $autoEnabled) {
        $result.Message = "Auto-upload disabled in config"
        Write-DiagLog $result.Message
        return $result
    }

    # Check if server upload is configured with a URL
    if (-not $config.ServerUpload) {
        $result.Message = "Auto-upload skipped: no ServerUpload config section"
        Write-DiagLog $result.Message
        return $result
    }
    if ([string]::IsNullOrWhiteSpace($config.ServerUpload.Url)) {
        $result.Message = "Auto-upload skipped: no server URL configured"
        Write-DiagLog $result.Message
        return $result
    }

    # Perform the upload silently using Send-ReportToServer
    Write-DiagLog "Auto-upload: uploading '$([IO.Path]::GetFileName($ReportPath))' to $($config.ServerUpload.Url)..."
    $uploadResult = Invoke-Safe {
        Send-ReportToServer -ReportPath $ReportPath `
            -CustomerName $CustomerName `
            -ComputerName $ComputerName `
            -TechName $TechName `
            -ScanMode $ScanMode `
            -ServerUrl $config.ServerUpload.Url
    } $null

    if ($uploadResult -and $uploadResult.Success) {
        $result.Uploaded = $true
        $result.Message = "Auto-upload successful$(if($uploadResult.ViewUrl){" - $($uploadResult.ViewUrl)"})"
        Write-DiagLog "Auto-upload: $($result.Message)"
    }
    elseif ($uploadResult) {
        $result.Message = "Auto-upload failed: $($uploadResult.Message)"
        Write-DiagLog $result.Message "WARN"
    }
    else {
        $result.Message = "Auto-upload failed: Send-ReportToServer returned null"
        Write-DiagLog $result.Message "WARN"
    }

    return $result
}

# ─────────────────────────────────────────────────────────────────────────────
# LCD DISPLAY WEAR & LIFE REPORT
# ─────────────────────────────────────────────────────────────────────────────

function Build-LCDDisplayReport {
    <#
    .SYNOPSIS
        Generates a branded HTML report for the LCD Display Wear & Life test.
    .PARAMETER Params
        Hashtable with CustomerName, TechName, ContactName, TechNotes.
    .PARAMETER LCDData
        The hashtable returned by Invoke-LCDDisplayTest.
    #>
    param(
        $Params,
        $LCDData
    )

    $date = Get-Date -Format "MMMM dd, yyyy 'at' h:mm tt"
    $iconPass = "&#10004;"; $iconFail = "&#10008;"; $iconWarn = "&#9888;"

    # ── Safe accessors ──
    $customerName  = if ($Params.CustomerName)  { $Params.CustomerName }  else { "Customer" }
    $customerPhone = if ($Params.CustomerPhone) { $Params.CustomerPhone } else { "" }
    $customerEmail = if ($Params.CustomerEmail) { $Params.CustomerEmail } else { "" }
    $techName      = if ($Params.TechName)      { $Params.TechName }      else { "Technician" }
    $contactName   = if ($Params.ContactName)   { $Params.ContactName }   else { "" }
    $techNotes     = if ($Params.TechNotes)     { $Params.TechNotes }     else { "" }

    $sys   = $LCDData.System
    $mon   = $LCDData.Monitor
    $adp   = $LCDData.Adapter
    $brt   = $LCDData.Brightness
    $evt   = $LCDData.Events
    $thm   = $LCDData.Thermal
    $scr   = $LCDData.Score

    $compName = if ($sys.ComputerName) { $sys.ComputerName } else { "PC" }

    # Score colors
    $scoreVal   = if ($scr.Score -ne $null) { [int]$scr.Score } else { 0 }
    $scoreColor = if ($scoreVal -ge 80) {"#22c55e"} elseif ($scoreVal -ge 60) {"#f59e0b"} else {"#dc2626"}
    $riskColor  = if ($scr.Risk -eq "Low") {"#22c55e"} elseif ($scr.Risk -eq "Moderate") {"#f59e0b"} elseif ($scr.Risk -eq "High") {"#f97316"} else {"#dc2626"}

    # ── Load logo ──
    $logoDataUri = ""
    $logoPath = Join-Path $Global:ScriptDir "logo-base64.txt"
    if (Test-Path $logoPath) {
        try { $logoDataUri = "data:image/png;base64,$((Get-Content $logoPath -Raw).Trim())" } catch {}
    }
    $logoHTML = if ($logoDataUri) {
        "<img src='$logoDataUri' alt='PC Plus Computing' style='width:320px;max-width:85%;'/>"
    } else {
        "<div style='background:linear-gradient(135deg,#0a1628,#0d4b71);color:#fff;padding:16px 40px;font-size:20pt;font-weight:bold;letter-spacing:3px;border-radius:8px;display:inline-block;'>PC PLUS COMPUTING</div>"
    }

    # ── Load QR codes ──
    $qrAppUri = ""; $qrSvcUri = ""
    $qrAppPath = Join-Path $Global:ScriptDir "qr-appointments.txt"
    $qrSvcPath = Join-Path $Global:ScriptDir "qr-service-requests.txt"
    if (Test-Path $qrAppPath) { try { $qrAppUri = "data:image/png;base64,$((Get-Content $qrAppPath -Raw).Trim())" } catch {} }
    if (Test-Path $qrSvcPath) { try { $qrSvcUri = "data:image/png;base64,$((Get-Content $qrSvcPath -Raw).Trim())" } catch {} }

    # ── Donut SVG for wear score ──
    $donutR = 40; $donutCirc = [math]::Round(2 * [math]::PI * $donutR, 1)
    $donutOffset = [math]::Round($donutCirc - ($donutCirc * $scoreVal / 100), 1)

    $donutSVG = @"
<svg viewBox="0 0 120 120" width="140" height="140" xmlns="http://www.w3.org/2000/svg">
  <circle cx="60" cy="60" r="$donutR" fill="none" stroke="#334155" stroke-width="8"/>
  <circle cx="60" cy="60" r="$donutR" fill="none" stroke="$scoreColor" stroke-width="8"
    stroke-dasharray="$donutCirc" stroke-dashoffset="$donutOffset"
    transform="rotate(-90 60 60)" stroke-linecap="round"/>
  <text x="60" y="56" text-anchor="middle" font-size="22" font-weight="bold" fill="$scoreColor" font-family="Segoe UI,sans-serif">$scoreVal</text>
  <text x="60" y="72" text-anchor="middle" font-size="9" fill="#94a3b8" font-family="Segoe UI,sans-serif">/ 100</text>
</svg>
"@

    # ── Monitor info rows ──
    $monitorRows = ""
    if ($mon.WmiMonitorID -and $mon.WmiMonitorID.Count -gt 0) {
        foreach ($m in $mon.WmiMonitorID) {
            $mName = if ($m.UserFriendlyName) { [System.Web.HttpUtility]::HtmlEncode($m.UserFriendlyName) } else { "N/A" }
            $mMfr  = if ($m.ManufacturerName) { [System.Web.HttpUtility]::HtmlEncode($m.ManufacturerName) } else { "N/A" }
            $mSer  = if ($m.SerialNumberID) { [System.Web.HttpUtility]::HtmlEncode($m.SerialNumberID) } else { "N/A" }
            $mYear = if ($m.YearOfManufacture) { $m.YearOfManufacture } else { "N/A" }
            $mAct  = if ($m.Active) { "<span class='pass'>$iconPass Active</span>" } else { "Inactive" }
            $monitorRows += "<tr><td>$mName</td><td>$mMfr</td><td>$mSer</td><td>$mYear</td><td>$mAct</td></tr>`n"
        }
    } else {
        $monitorRows = "<tr><td colspan='5'>No WMI Monitor EDID records found. This is normal for some desktops/external monitors.</td></tr>"
    }

    # ── GPU adapter rows ──
    $gpuRows = ""
    if ($adp.GPUs -and $adp.GPUs.Count -gt 0) {
        foreach ($g in $adp.GPUs) {
            $gName   = if ($g.Name) { [System.Web.HttpUtility]::HtmlEncode($g.Name) } else { "N/A" }
            $gVRAM   = if ($g.AdapterRAMGB) { "$($g.AdapterRAMGB) GB" } else { "N/A" }
            $gDrv    = if ($g.DriverVersion) { $g.DriverVersion } else { "N/A" }
            $gDrvDt  = if ($g.DriverDate) { $g.DriverDate.ToString("yyyy-MM-dd") } else { "N/A" }
            $gRes    = "$($g.CurrentHorizontalResolution)x$($g.CurrentVerticalResolution)"
            $gRefr   = if ($g.CurrentRefreshRate) { "$($g.CurrentRefreshRate) Hz" } else { "N/A" }
            $gStat   = if ($g.Status -match "OK") { "<span class='pass'>$iconPass $($g.Status)</span>" } else { "<span class='fail'>$iconFail $($g.Status)</span>" }
            $gpuRows += "<tr><td>$gName</td><td>$gVRAM</td><td>$gDrv</td><td>$gDrvDt</td><td>$gRes</td><td>$gRefr</td><td>$gStat</td></tr>`n"
        }
    } else {
        $gpuRows = "<tr><td colspan='7'>No display adapters detected.</td></tr>"
    }

    # ── Findings rows ──
    $findingRows = ""
    if ($scr.Findings -and $scr.Findings.Count -gt 0) {
        foreach ($f in $scr.Findings) {
            $fClass = switch ($f.Severity) { "Critical" {"fail"} "High" {"fail"} "Moderate" {"warn"} default {"pass"} }
            $fIcon  = switch ($f.Severity) { "Critical" {$iconFail} "High" {$iconFail} "Moderate" {$iconWarn} default {$iconPass} }
            $findingRows += "<tr><td>$($f.Category)</td><td class='$fClass'>$fIcon $($f.Severity)</td><td>$([System.Web.HttpUtility]::HtmlEncode($f.Finding))</td><td>$([System.Web.HttpUtility]::HtmlEncode($f.Recommendation))</td></tr>`n"
        }
    } else {
        $findingRows = "<tr><td colspan='4'><span class='pass'>$iconPass No major display wear indicators detected from Windows data.</span></td></tr>"
    }

    # ── Event rows ──
    $eventRows = ""
    if ($evt.RecentEvents -and $evt.RecentEvents.Count -gt 0) {
        foreach ($e in $evt.RecentEvents) {
            $eMsg = [System.Web.HttpUtility]::HtmlEncode($e.Message)
            if ($eMsg.Length -gt 260) { $eMsg = $eMsg.Substring(0, 260) + "..." }
            $eLvl = if ($e.LevelDisplayName -match "Error|Critical") { "<span class='fail'>$($e.LevelDisplayName)</span>" } elseif ($e.LevelDisplayName -match "Warning") { "<span class='warn'>$($e.LevelDisplayName)</span>" } else { $e.LevelDisplayName }
            $eventRows += "<tr><td>$($e.TimeCreated)</td><td>$($e.ProviderName)</td><td>$($e.Id)</td><td>$eLvl</td><td>$eMsg</td></tr>`n"
        }
    } else {
        $eventRows = "<tr><td colspan='5'><span class='pass'>$iconPass No recent display/GPU-related events found in 180 days.</span></td></tr>"
    }

    # ── Manual visual test checklist rows ──
    $manualRows = ""
    foreach ($t in $scr.ManualVisualTestsRequired) {
        $manualRows += "<tr><td style='padding-left:18px;'>&#9744; $t</td><td style='color:#64748b;'>Technician visual check required</td></tr>`n"
    }

    # ── Thermal zone rows ──
    $thermalZoneRows = ""
    if ($thm.ThermalZones -and $thm.ThermalZones.Count -gt 0) {
        foreach ($tz in $thm.ThermalZones) {
            $tzName = if ($tz.InstanceName) { $tz.InstanceName -replace '\\\\','/' } else { "Zone" }
            $tzTemp = $tz.TemperatureC
            $tzClass = if ($tzTemp -ge 85) {"fail"} elseif ($tzTemp -ge 65) {"warn"} else {"pass"}
            $thermalZoneRows += "<tr><td>$tzName</td><td class='$tzClass'>$tzTemp C</td></tr>`n"
        }
    } else {
        $thermalZoneRows = "<tr><td colspan='2'>No ACPI thermal zone data available.</td></tr>"
    }

    # ── Tech notes HTML ──
    $techNotesHTML = if ($techNotes) {
        "<div class='section-header'><span class='section-icon'>&#128221;</span> Technician Notes</div><div style='padding:14px 18px;background:#f8fafc;border:1px solid #d1d5db;border-radius:8px;min-height:50px;white-space:pre-wrap;font-size:9.5pt;line-height:1.7;margin-bottom:16px;'>$([System.Web.HttpUtility]::HtmlEncode($techNotes))</div>"
    } else { "" }

    # ── Recommendations based on score ──
    $recsHTML = ""
    if ($scoreVal -lt 60) {
        $recsHTML += "<div style='display:flex;align-items:flex-start;gap:10px;padding:8px 14px;margin:4px 0;border-radius:6px;background:#fef2f2;border-left:4px solid #dc2626;'><span style='font-size:13pt;flex-shrink:0;'>$iconFail</span><span style='font-size:9.5pt;color:#1e293b;line-height:1.5;'>Display health is critical. Schedule a professional inspection and consider LCD panel replacement or external monitor use.</span></div>`n"
    }
    if ($evt.DriverResetCount -gt 0) {
        $recsHTML += "<div style='display:flex;align-items:flex-start;gap:10px;padding:8px 14px;margin:4px 0;border-radius:6px;background:#fffbeb;border-left:4px solid #f59e0b;'><span style='font-size:13pt;flex-shrink:0;'>$iconWarn</span><span style='font-size:9.5pt;color:#1e293b;line-height:1.5;'>Display driver resets detected. Update graphics drivers and check for GPU overheating. If flickering continues, test the display cable (eDP/LVDS).</span></div>`n"
    }
    if ($thm.ThermalEventCount -gt 0) {
        $recsHTML += "<div style='display:flex;align-items:flex-start;gap:10px;padding:8px 14px;margin:4px 0;border-radius:6px;background:#fffbeb;border-left:4px solid #f59e0b;'><span style='font-size:13pt;flex-shrink:0;'>$iconWarn</span><span style='font-size:9.5pt;color:#1e293b;line-height:1.5;'>Thermal events detected. Clean fans and heatsinks, reapply thermal paste if needed. High heat accelerates LCD backlight and cable wear.</span></div>`n"
    }
    if ($sys.BIOSAgeYears -ne $null -and $sys.BIOSAgeYears -ge 5) {
        $recsHTML += "<div style='display:flex;align-items:flex-start;gap:10px;padding:8px 14px;margin:4px 0;border-radius:6px;background:#f0fdf4;border-left:4px solid #22c55e;'><span style='font-size:13pt;flex-shrink:0;'>$iconWarn</span><span style='font-size:9.5pt;color:#1e293b;line-height:1.5;'>System is approximately $($sys.BIOSAgeYears) years old. Consider a full visual inspection of the LCD panel, backlight uniformity, and hinge cable during the next service.</span></div>`n"
    }
    if (-not $recsHTML) {
        $recsHTML = "<div style='display:flex;align-items:flex-start;gap:10px;padding:8px 14px;margin:4px 0;border-radius:6px;background:#f0fdf4;border-left:4px solid #22c55e;'><span style='font-size:13pt;flex-shrink:0;'>$iconPass</span><span style='font-size:9.5pt;color:#1e293b;line-height:1.5;'>No critical display issues detected. Continue regular use and schedule periodic visual inspections.</span></div>"
    }

    # ══════════════════════════════════════════════════════════════════════════
    # ASSEMBLE THE FULL HTML
    # ══════════════════════════════════════════════════════════════════════════

$html = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8"/>
<title>LCD Display Wear &amp; Life Report - $customerName</title>
<style>
@page { size: A4; margin: 0.5in 0.6in 0.9in 0.6in; }
* { margin:0; padding:0; box-sizing:border-box; }
body { font-family: 'Segoe UI', -apple-system, Tahoma, sans-serif; font-size: 9.5pt; color: #1e293b; line-height: 1.6; background: #fff; }
h1,h2,h3,h4 { margin:0; }
@media print {
    body { -webkit-print-color-adjust: exact; print-color-adjust: exact; }
    .page-break { page-break-before: always; }
    .no-break { page-break-inside: avoid; }
}
.page-break { page-break-before: always; }
.print-footer {
    position: fixed; bottom: 0; left: 0; right: 0;
    padding: 6px 0; border-top: 1.5px solid #0d4b71;
    text-align: center; font-size: 7.5pt; color: #94a3b8; background: #fff;
}
.print-footer strong { color: #0d4b71; font-size: 7.5pt; }
.print-footer .report-name { color: #475569; }
.no-break { page-break-inside: avoid; }
.section-header {
    background: linear-gradient(135deg, #1a1a2e 0%, #0d4b71 100%);
    color: #fff; padding: 10px 20px; font-size: 12pt; font-weight: 600;
    margin: 24px 0 14px 0; border-radius: 6px; letter-spacing: 0.5px;
    display: flex; align-items: center; gap: 10px;
}
.section-header .section-icon { font-size: 14pt; opacity: 0.85; }
.sub-header {
    color: #0d4b71; font-size: 10.5pt; font-weight: 700; margin: 18px 0 8px 0;
    padding-bottom: 5px; border-bottom: 2px solid #2596be; letter-spacing: 0.3px;
}
table { width: 100%; border-collapse: collapse; margin-bottom: 14px; font-size: 9pt; }
th {
    background: #0d4b71; color: #fff; padding: 7px 10px; text-align: left;
    font-weight: 600; font-size: 8.5pt; text-transform: uppercase; letter-spacing: 0.5px;
}
td { padding: 6px 10px; border-bottom: 1px solid #e2e8f0; vertical-align: middle; }
tr:nth-child(even) td { background: #f8fafc; }
tr:hover td { background: #eaf7fc; }
.pass { color: #16a34a; font-weight: 600; }
.fail { color: #dc2626; font-weight: 600; }
.warn { color: #f59e0b; font-weight: 600; }
.summary-strip { display: flex; gap: 10px; margin: 14px 0; flex-wrap: wrap; }
.summary-chip {
    flex: 1; min-width: 100px; text-align: center; padding: 10px 8px; background: #f8fafc;
    border: 1px solid #e2e8f0; border-radius: 8px;
}
.summary-chip .chip-val { font-size: 13pt; font-weight: 700; color: #0a1628; display: block; }
.summary-chip .chip-lbl { font-size: 7.5pt; color: #64748b; text-transform: uppercase; font-weight: 600; letter-spacing: 0.3px; }
.info-card {
    background: #f8fafc; border: 1px solid #e2e8f0; border-radius: 10px; padding: 14px; margin-bottom: 12px;
}
.notice {
    background: #fffbeb; border-left: 5px solid #f59e0b; padding: 12px 16px; border-radius: 6px;
    font-size: 9pt; color: #92400e; margin: 12px 0;
}
.qr-row { display: flex; justify-content: center; gap: 60px; margin: 20px 0; }
.qr-item { text-align: center; }
.qr-item img { width: 140px; height: 140px; border-radius: 8px; }
.qr-item .qr-fallback { width: 140px; height: 140px; border: 2px dashed #94a3b8; border-radius: 8px; display: flex; align-items: center; justify-content: center; font-size: 7.5pt; color: #94a3b8; }
.qr-label { font-size: 9pt; font-weight: 600; color: #0d4b71; margin-top: 8px; }
.qr-sublabel { font-size: 7.5pt; color: #64748b; margin-top: 2px; }
</style>
</head>
<body>

<div class="print-footer">
<span class="report-name">LCD Display Wear &amp; Life Report</span> &nbsp;|&nbsp; <strong>$COMPANY</strong> &nbsp;|&nbsp; $WEBSITE &nbsp;|&nbsp; $PHONE
</div>

<!-- =============================== PAGE 1: COVER =============================== -->
<div style="page-break-after:always;">
<div style="text-align:center;padding:20px 0 10px;">
$logoHTML
<div style="font-size:17pt;font-weight:700;color:#0d4b71;margin-top:12px;letter-spacing:0.5px;">PC Plus 360 LCD Display Wear &amp; Life Report</div>
<div style="font-size:10pt;color:#3bbde0;margin-top:4px;">Panel Health Estimation &amp; Visual Inspection Workflow</div>
</div>

<!-- Customer info + Donut -->
<div style="display:flex;gap:20px;align-items:center;margin:16px 0;">
<div style="flex:1;">
<div class="info-card">
<table style="width:100%;font-size:10pt;border:none;margin:0;">
<tr><td style="border:none;padding:4px 8px;color:#64748b;font-weight:600;width:110px;">Customer:</td><td style="border:none;padding:4px 8px;color:#0a1628;font-weight:700;">$customerName</td></tr>
$(if($customerPhone){"<tr><td style='border:none;padding:4px 8px;color:#64748b;font-weight:600;'>Phone:</td><td style='border:none;padding:4px 8px;color:#0a1628;'>$customerPhone</td></tr>"})
$(if($customerEmail){"<tr><td style='border:none;padding:4px 8px;color:#64748b;font-weight:600;'>Email:</td><td style='border:none;padding:4px 8px;color:#0a1628;'>$customerEmail</td></tr>"})
$(if($contactName){"<tr><td style='border:none;padding:4px 8px;color:#64748b;font-weight:600;'>Contact:</td><td style='border:none;padding:4px 8px;color:#0a1628;'>$contactName</td></tr>"})
<tr><td style="border:none;padding:4px 8px;color:#64748b;font-weight:600;">Device:</td><td style="border:none;padding:4px 8px;color:#0a1628;">$compName</td></tr>
<tr><td style="border:none;padding:4px 8px;color:#64748b;font-weight:600;">Model:</td><td style="border:none;padding:4px 8px;color:#0a1628;">$($sys.Manufacturer) $($sys.Model)</td></tr>
<tr><td style="border:none;padding:4px 8px;color:#64748b;font-weight:600;">Date:</td><td style="border:none;padding:4px 8px;color:#0a1628;">$date</td></tr>
<tr><td style="border:none;padding:4px 8px;color:#64748b;font-weight:600;">Technician:</td><td style="border:none;padding:4px 8px;color:#0a1628;">$techName</td></tr>
</table>
</div>
</div>
<div style="text-align:center;">
$donutSVG
<div style="font-size:10pt;font-weight:700;color:$scoreColor;margin-top:4px;">$($scr.Grade)</div>
<div style="font-size:8pt;color:#64748b;margin-top:2px;">Display Wear Score</div>
</div>
</div>

<!-- Summary strip -->
<div class="summary-strip">
<div class="summary-chip"><span class="chip-val" style="color:$scoreColor;">$scoreVal</span><span class="chip-lbl">Wear Score</span></div>
<div class="summary-chip"><span class="chip-val" style="color:$riskColor;">$($scr.Risk)</span><span class="chip-lbl">Risk Level</span></div>
<div class="summary-chip"><span class="chip-val">$($mon.MonitorCount)</span><span class="chip-lbl">Monitors</span></div>
<div class="summary-chip"><span class="chip-val">$(if($brt.CurrentBrightness -ne $null){"$($brt.CurrentBrightness)%"}else{"N/A"})</span><span class="chip-lbl">Brightness</span></div>
<div class="summary-chip"><span class="chip-val">$(if($sys.BIOSAgeYears){"~$($sys.BIOSAgeYears)y"}else{"N/A"})</span><span class="chip-lbl">System Age</span></div>
<div class="summary-chip"><span class="chip-val">$(if($sys.IsLaptop){"Yes"}else{"No"})</span><span class="chip-lbl">Laptop</span></div>
</div>

<!-- Approximate Life -->
<div class="info-card" style="border-left:5px solid $scoreColor;">
<div style="font-size:10pt;font-weight:700;color:#0d4b71;margin-bottom:4px;">Approximate LCD / Display Life</div>
<div style="font-size:10pt;color:#1e293b;">$($scr.ApproxLife)</div>
</div>

<div class="notice">
<strong>$iconWarn Important:</strong> $($scr.Notes)
</div>

<!-- System info -->
<div class="section-header"><span class="section-icon">&#128187;</span> System / Age Information</div>
<table class="no-break">
<tr><th>Property</th><th>Value</th></tr>
<tr><td>Manufacturer</td><td>$($sys.Manufacturer)</td></tr>
<tr><td>Model</td><td>$($sys.Model)</td></tr>
<tr><td>Serial Number</td><td>$($sys.SerialNumber)</td></tr>
<tr><td>BIOS Version</td><td>$($sys.BIOSVersion)</td></tr>
<tr><td>BIOS Age Estimate</td><td>$(if($sys.BIOSAgeYears){"$($sys.BIOSAgeYears) years"}else{"N/A"})</td></tr>
<tr><td>Operating System</td><td>$($sys.OS) Build $($sys.OSBuild)</td></tr>
<tr><td>CPU</td><td>$($sys.CPU)</td></tr>
<tr><td>RAM</td><td>$($sys.RAMGB) GB</td></tr>
<tr><td>Laptop Detected</td><td>$(if($sys.IsLaptop){"<span class='warn'>Yes - LCD wear monitoring recommended</span>"}else{"No (Desktop)"})</td></tr>
<tr><td>Uptime</td><td>$($sys.UptimeHours) hours</td></tr>
</table>
</div>

<!-- =============================== PAGE 2: FINDINGS & HARDWARE =============================== -->
<div class="page-break"></div>

<div class="section-header"><span class="section-icon">&#128270;</span> Findings &amp; Recommendations</div>
<table class="no-break">
<tr><th>Category</th><th>Severity</th><th>Finding</th><th>Recommendation</th></tr>
$findingRows
</table>

$(if($recsHTML){@"
<div class="section-header"><span class="section-icon">&#128161;</span> Recommendations</div>
<div style="margin:8px 0;">
$recsHTML
</div>
"@})

<div class="section-header"><span class="section-icon">&#128424;</span> Detected Monitor / Panel Information</div>
<table class="no-break">
<tr><th>Name</th><th>Manufacturer</th><th>Serial</th><th>Year</th><th>Active</th></tr>
$monitorRows
</table>

<div class="section-header"><span class="section-icon">&#127912;</span> Display Adapter / Resolution</div>
<table class="no-break">
<tr><th>GPU</th><th>VRAM</th><th>Driver</th><th>Driver Date</th><th>Resolution</th><th>Refresh</th><th>Status</th></tr>
$gpuRows
</table>

<div class="section-header"><span class="section-icon">&#9728;</span> Brightness Information</div>
<table class="no-break">
<tr><th>Property</th><th>Value</th></tr>
<tr><td>Brightness Supported</td><td>$(if($brt.BrightnessSupported){"<span class='pass'>$iconPass Yes</span>"}else{"No (common for desktops/external monitors)"})</td></tr>
<tr><td>Current Brightness</td><td>$(if($brt.CurrentBrightness -ne $null){"$($brt.CurrentBrightness)%"}else{"N/A"})</td></tr>
<tr><td>Note</td><td>$($brt.Notes)</td></tr>
</table>

<!-- =============================== PAGE 3: EVENTS & THERMAL =============================== -->
<div class="page-break"></div>

<div class="section-header"><span class="section-icon">&#128200;</span> Display / GPU Stability Events (Last $($evt.DaysChecked) Days)</div>
<div class="summary-strip" style="margin-bottom:10px;">
<div class="summary-chip"><span class="chip-val">$($evt.EventCount)</span><span class="chip-lbl">Total Events</span></div>
<div class="summary-chip"><span class="chip-val" style="color:$(if($evt.DriverResetCount -gt 0){'#dc2626'}else{'#22c55e'});">$($evt.DriverResetCount)</span><span class="chip-lbl">Driver Resets</span></div>
<div class="summary-chip"><span class="chip-val">$($evt.PossibleCableReconnectCount)</span><span class="chip-lbl">Cable/Reconnect</span></div>
</div>
<table>
<tr><th>Time</th><th>Source</th><th>ID</th><th>Level</th><th>Message</th></tr>
$eventRows
</table>

<div class="section-header"><span class="section-icon">&#127777;</span> Thermal Correlation Risk</div>
<div class="summary-strip" style="margin-bottom:10px;">
<div class="summary-chip"><span class="chip-val" style="color:$(if($thm.ThermalEventCount -gt 0){'#f59e0b'}else{'#22c55e'});">$($thm.ThermalEventCount)</span><span class="chip-lbl">Thermal Events</span></div>
<div class="summary-chip"><span class="chip-val">$(if($thm.MaxReportedTemperatureC){"$($thm.MaxReportedTemperatureC) C"}else{"N/A"})</span><span class="chip-lbl">Max Temp</span></div>
</div>
<div class="sub-header">Current Thermal Zones</div>
<table class="no-break">
<tr><th>Zone</th><th>Temperature</th></tr>
$thermalZoneRows
</table>
<div class="notice">
$($thm.Notes)
</div>

<!-- =============================== PAGE 4: VISUAL TEST & CHECKLIST =============================== -->
<div class="page-break"></div>

<div class="section-header"><span class="section-icon">&#128065;</span> Manual Visual Inspection Checklist</div>
<p style="margin:8px 0 12px;font-size:9.5pt;color:#64748b;">The following tests require a technician to visually inspect the display using the LCD Visual Test page (included as a separate HTML file). Check each item after inspection.</p>
<table class="no-break">
<tr><th>Test</th><th>Status</th></tr>
$manualRows
</table>

<div style="padding:14px 18px;background:#eaf7fc;border:1px solid #2596be;border-radius:8px;margin:16px 0;">
<div style="font-size:10pt;font-weight:700;color:#0d4b71;margin-bottom:6px;">&#128161; How to Use the LCD Visual Test</div>
<ol style="font-size:9pt;color:#1e293b;margin-left:18px;line-height:1.8;">
<li>Open the <strong>LCD-Visual-Test.html</strong> file (saved alongside this report)</li>
<li>Press <strong>F11</strong> to go fullscreen</li>
<li>Use <strong>arrow keys</strong> or buttons to cycle through: White, Black, Red, Green, Blue, Gray, Gradient, Grid, and Ghosting screens</li>
<li>On each screen, carefully inspect for: dead/stuck pixels, backlight bleed, color tint, burn-in, uniformity issues</li>
<li>Record findings in the technician notes section above</li>
</ol>
</div>

$techNotesHTML

<!-- =============================== BACK PAGE =============================== -->
<div class="page-break"></div>
<div style="text-align:center;padding-top:60px;">
$(if($logoDataUri){"<img src='$logoDataUri' alt='PC Plus Computing' style='width:250px;margin-bottom:30px;'/>"}else{"<div style='background:linear-gradient(135deg,#0a1628,#0d4b71);color:#fff;padding:16px 40px;font-size:18pt;font-weight:bold;letter-spacing:3px;border-radius:6px;margin-bottom:30px;display:inline-block;'>PC PLUS COMPUTING</div>"})
<div style="font-size:12pt;color:#0d4b71;font-weight:600;margin-bottom:6px;">Thank you for choosing PC Plus Computing</div>
<div style="font-size:10pt;color:#64748b;margin-bottom:30px;">Your Security, Our Priority &nbsp;|&nbsp; 30+ Years in Service &nbsp;|&nbsp; 4.9&#9733; Google Rating</div>
<div class="qr-row">
<div class="qr-item">
$(if($qrAppUri){"<img src='$qrAppUri' alt='Book Appointment'/>"}else{"<div class='qr-fallback'>Book<br/>Appointment</div>"})
<div class="qr-label">Book an Appointment</div>
<div class="qr-sublabel">pcpluscomputing.com/appointments</div>
</div>
<div class="qr-item">
$(if($qrSvcUri){"<img src='$qrSvcUri' alt='Send Info'/>"}else{"<div class='qr-fallback'>Send Us<br/>Info</div>"})
<div class="qr-label">Send Us Your Info</div>
<div class="qr-sublabel">Service Request Portal</div>
</div>
</div>
<div style="margin-top:40px;padding:20px;background:#f8fafc;border-radius:10px;border:1px solid #e2e8f0;display:inline-block;">
<div style="font-size:11pt;font-weight:700;color:#0a1628;margin-bottom:8px;">Get In Touch</div>
<div style="font-size:10pt;color:#475569;">
&#127760; $WEBSITE &nbsp;&nbsp;|&nbsp;&nbsp; &#128222; $PHONE
</div>
</div>
<div style="margin-top:40px;font-size:8pt;color:#94a3b8;">
LCD Display Wear &amp; Life Report generated $date<br/>
Technician: $techName &nbsp;|&nbsp; Device: $compName
</div>
</div>

</body>
</html>
"@

    return $html
}

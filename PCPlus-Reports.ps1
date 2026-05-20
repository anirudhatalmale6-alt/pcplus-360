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
    body { -webkit-print-color-adjust: exact; print-color-adjust: exact; }
    .page-break { page-break-before: always; }
    .no-break { page-break-inside: avoid; }
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
                default { "Review and fix this configuration." }
            }
            $sev = if($item.Points -ge 10){"Critical"}elseif($item.Points -ge 5){"Warning"}else{"Advisory"}
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

    # Build security detail cards
    $secDetailCards = ($secDetails | ForEach-Object {
        "<div class='sec-detail-row'><div class='sec-detail-label'>$($_.Name)</div><div class='sec-detail-value'>$($_.Status)</div></div>"
    }) -join "`n"

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

$html = @"
<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8"/><title>Security Audit Report - $($Params.CustomerName)</title>
<style>
@page { size: letter; margin: 0.5in 0.6in 0.9in 0.6in; }
* { margin:0; padding:0; box-sizing:border-box; }
body { font-family: 'Segoe UI', -apple-system, Tahoma, sans-serif; font-size: 9.5pt; color: #1e293b; line-height: 1.6; background: #fff; }
h1,h2,h3,h4 { margin:0; }

/* Print handling */
@media print {
    body { -webkit-print-color-adjust: exact; print-color-adjust: exact; }
    .page-break { page-break-before: always; }
    .no-break { page-break-inside: avoid; }
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

<!-- SCORE BREAKDOWN -->
<div class="page-break"></div>

<div class="section-header"><span class="section-icon">&#128202;</span> Security Score Breakdown</div>

<table><tr><th style="width:30px;"></th><th>Security Check</th><th>Status</th><th style="width:70px;text-align:center;">Weight</th></tr>$breakdownRows</table>


<!-- DETAILED SECURITY STATUS -->
<div class="page-break"></div>

<div class="section-header"><span class="section-icon">&#128274;</span> Detailed Security Status</div>

<div class="sec-detail-panel">
$secDetailCards
</div>


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
        <div><strong>Prepared for:</strong> $($Params.CustomerName)</div>
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

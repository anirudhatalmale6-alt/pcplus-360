<#
.SYNOPSIS
    PC Plus Computing 360 - Customer Report Card
.DESCRIPTION
    Executive summary "report card" that aggregates results from all other
    PC Plus 360 scans into a single customer-facing report with letter grades,
    plain-English findings, and recommended services.
.NOTES
    Company:  PC Plus Computing
    Phone:    604-760-1662 | 236-500-2700
    Website:  pcpluscomputing.com
    Version:  1.0.0
    Requires: PowerShell 5.1+, Windows 10/11
    Part of:  PC Plus 360 USB Diagnostic Toolkit
.EXAMPLE
    PowerShell.exe -ExecutionPolicy Bypass -File .\PCPlus-ReportCard.ps1
#>

#Requires -Version 5.1

$ErrorActionPreference = 'Continue'

# ─────────────────────────────────────────────────────────────────────────────
# ASSEMBLIES & VISUAL STYLES
# ─────────────────────────────────────────────────────────────────────────────
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Web
[System.Windows.Forms.Application]::EnableVisualStyles()

# ─────────────────────────────────────────────────────────────────────────────
# BRANDING CONSTANTS
# ─────────────────────────────────────────────────────────────────────────────
$COMPANY_NAME    = "PC Plus Computing"
$COMPANY_FULL    = "PC Plus Computing 360"
$COMPANY_WEBSITE = "pcpluscomputing.com"
$COMPANY_PHONE1  = "604-760-1662"
$COMPANY_PHONE2  = "236-500-2700"
$COLOR_NAVY      = "#0a1628"
$COLOR_ACCENT    = "#2596be"
$COLOR_GREEN     = "#27ae60"
$COLOR_RED       = "#e74c3c"
$COLOR_ORANGE    = "#f39c12"
$COLOR_LIGHT_BG  = "#f8f9fa"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
if ([string]::IsNullOrEmpty($ScriptDir)) { $ScriptDir = Get-Location }
$ReportsDir = Join-Path $ScriptDir "reports"
if (-not (Test-Path $ReportsDir)) { New-Item -Path $ReportsDir -ItemType Directory -Force | Out-Null }

# ─────────────────────────────────────────────────────────────────────────────
# GRADING SYSTEM
# ─────────────────────────────────────────────────────────────────────────────
function Get-LetterGrade {
    param([int]$Score)
    if ($Score -ge 97) { return "A+" }
    if ($Score -ge 93) { return "A"  }
    if ($Score -ge 90) { return "A-" }
    if ($Score -ge 87) { return "B+" }
    if ($Score -ge 83) { return "B"  }
    if ($Score -ge 80) { return "B-" }
    if ($Score -ge 77) { return "C+" }
    if ($Score -ge 73) { return "C"  }
    if ($Score -ge 70) { return "C-" }
    if ($Score -ge 67) { return "D+" }
    if ($Score -ge 63) { return "D"  }
    if ($Score -ge 60) { return "D-" }
    return "F"
}

function Get-GradeColor {
    param([string]$Grade)
    switch -Wildcard ($Grade) {
        "A*" { return $COLOR_GREEN }
        "B*" { return $COLOR_ACCENT }
        "C*" { return $COLOR_ORANGE }
        "D*" { return $COLOR_RED }
        "F"  { return $COLOR_RED }
        default { return "#888888" }
    }
}

function Get-ScoreColor {
    param([int]$Score)
    if ($Score -ge 80) { return $COLOR_GREEN }
    if ($Score -ge 60) { return $COLOR_ORANGE }
    return $COLOR_RED
}

# ─────────────────────────────────────────────────────────────────────────────
# SCAN RESULT LOADERS
# ─────────────────────────────────────────────────────────────────────────────

# Finds the most recent report file matching a pattern
function Find-LatestReport {
    param([string]$Pattern)
    try {
        $files = Get-ChildItem -Path $ReportsDir -Filter $Pattern -ErrorAction SilentlyContinue |
                 Sort-Object LastWriteTime -Descending
        if ($files.Count -gt 0) {
            return $files[0].FullName
        }
    } catch {}
    return $null
}

# Reads HTML report and extracts score from common patterns
function Get-ScoreFromHtml {
    param([string]$FilePath, [string]$ScorePattern)
    try {
        $content = Get-Content -Path $FilePath -Raw -ErrorAction Stop
        if ($content -match $ScorePattern) {
            $val = [int]$Matches[1]
            if ($val -ge 0 -and $val -le 100) { return $val }
        }
    } catch {}
    return -1
}

# Reads JSON report data
function Get-JsonReportData {
    param([string]$FilePath)
    try {
        return (Get-Content -Path $FilePath -Raw -ErrorAction Stop | ConvertFrom-Json)
    } catch {}
    return $null
}

# Extract findings from HTML (look for common list patterns)
function Get-FindingsFromHtml {
    param([string]$FilePath, [int]$MaxFindings = 3)
    $findings = [System.Collections.ArrayList]::new()
    try {
        $content = Get-Content -Path $FilePath -Raw -ErrorAction Stop
        # Look for list items with warning/fail indicators
        $pattern = '<(?:li|td)[^>]*>.*?(?:FAIL|WARN|WARNING|CRITICAL|HIGH|MEDIUM|Issue|Problem|Risk)[^<]*'
        $matches2 = [regex]::Matches($content, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        foreach ($m in $matches2) {
            if ($findings.Count -ge $MaxFindings) { break }
            $text = $m.Value -replace '<[^>]+>', '' -replace '&nbsp;', ' '
            $text = $text.Trim()
            if ($text.Length -gt 10 -and $text.Length -lt 200) {
                [void]$findings.Add($text)
            }
        }
    } catch {}
    return $findings
}

# ─────────────────────────────────────────────────────────────────────────────
# CATEGORY ASSESSMENT FUNCTIONS
# ─────────────────────────────────────────────────────────────────────────────

function Get-SecurityPosture {
    $result = @{
        Score      = -1
        Grade      = "N/A"
        Status     = "Not Scanned"
        Findings   = [System.Collections.ArrayList]::new()
        Actions    = [System.Collections.ArrayList]::new()
        Sources    = [System.Collections.ArrayList]::new()
    }

    $scores = [System.Collections.ArrayList]::new()

    # SecurityAudit
    $secAuditFile = Find-LatestReport "SecurityAudit-*.html"
    if ($secAuditFile) {
        [void]$result.Sources.Add("SecurityAudit")
        $score = Get-ScoreFromHtml -FilePath $secAuditFile -ScorePattern 'Overall[^0-9]*?(\d{1,3})\s*[/%]'
        if ($score -lt 0) { $score = Get-ScoreFromHtml -FilePath $secAuditFile -ScorePattern '(\d{1,3})\s*/\s*100' }
        if ($score -ge 0) { [void]$scores.Add($score) }
        $f = Get-FindingsFromHtml -FilePath $secAuditFile -MaxFindings 3
        foreach ($item in $f) { [void]$result.Findings.Add($item) }
    }

    # QuickRiskScore
    $qrsFile = Find-LatestReport "QuickRiskScore-*.html"
    if ($qrsFile) {
        [void]$result.Sources.Add("QuickRiskScore")
        $score = Get-ScoreFromHtml -FilePath $qrsFile -ScorePattern 'Security[^0-9]*?(\d{1,3})'
        if ($score -ge 0) { [void]$scores.Add($score) }
        $f = Get-FindingsFromHtml -FilePath $qrsFile -MaxFindings 2
        foreach ($item in $f) { [void]$result.Findings.Add($item) }
    }

    # ScamProtectionAudit
    $scamFile = Find-LatestReport "ScamProtection-*.html"
    if ($scamFile) {
        [void]$result.Sources.Add("ScamProtectionAudit")
        $score = Get-ScoreFromHtml -FilePath $scamFile -ScorePattern '(\d{1,3})\s*/\s*100'
        if ($score -ge 0) { [void]$scores.Add($score) }
    }

    if ($scores.Count -gt 0) {
        $total = 0
        foreach ($s in $scores) { $total += $s }
        $result.Score = [math]::Round($total / $scores.Count)
        $result.Grade = Get-LetterGrade -Score $result.Score
        $result.Status = "Scanned"

        if ($result.Score -lt 70) {
            [void]$result.Actions.Add("Security hardening and malware scan recommended")
            [void]$result.Actions.Add("Review and update antivirus/firewall settings")
        }
        if ($result.Score -lt 50) {
            [void]$result.Actions.Add("Urgent: Full security overhaul needed")
        }
    }

    # Trim findings to top 3
    while ($result.Findings.Count -gt 3) { $result.Findings.RemoveAt($result.Findings.Count - 1) }

    return $result
}

function Get-SystemHealth {
    $result = @{
        Score      = -1
        Grade      = "N/A"
        Status     = "Not Scanned"
        Findings   = [System.Collections.ArrayList]::new()
        Actions    = [System.Collections.ArrayList]::new()
        Sources    = [System.Collections.ArrayList]::new()
    }

    $scores = [System.Collections.ArrayList]::new()

    # WindowsDeepTest
    $deepFile = Find-LatestReport "WindowsDeepTest-*.html"
    if ($null -eq $deepFile) { $deepFile = Find-LatestReport "DeepWindows-*.html" }
    if ($deepFile) {
        [void]$result.Sources.Add("WindowsDeepTest")
        $score = Get-ScoreFromHtml -FilePath $deepFile -ScorePattern '(\d{1,3})\s*/\s*100'
        if ($score -ge 0) { [void]$scores.Add($score) }
        $f = Get-FindingsFromHtml -FilePath $deepFile -MaxFindings 3
        foreach ($item in $f) { [void]$result.Findings.Add($item) }
    }

    # QuickRiskScore - Health category
    $qrsFile = Find-LatestReport "QuickRiskScore-*.html"
    if ($qrsFile) {
        [void]$result.Sources.Add("QuickRiskScore")
        $score = Get-ScoreFromHtml -FilePath $qrsFile -ScorePattern 'Health[^0-9]*?(\d{1,3})'
        if ($score -ge 0) { [void]$scores.Add($score) }
    }

    # StartupThreatAudit
    $startupFile = Find-LatestReport "StartupThreat-*.html"
    if ($startupFile) {
        [void]$result.Sources.Add("StartupThreatAudit")
        $score = Get-ScoreFromHtml -FilePath $startupFile -ScorePattern '(\d{1,3})\s*/\s*100'
        if ($score -ge 0) { [void]$scores.Add($score) }
    }

    if ($scores.Count -gt 0) {
        $total = 0
        foreach ($s in $scores) { $total += $s }
        $result.Score = [math]::Round($total / $scores.Count)
        $result.Grade = Get-LetterGrade -Score $result.Score
        $result.Status = "Scanned"

        if ($result.Score -lt 70) {
            [void]$result.Actions.Add("System optimization and cleanup recommended")
            [void]$result.Actions.Add("Check for Windows Update issues")
        }
    }

    while ($result.Findings.Count -gt 3) { $result.Findings.RemoveAt($result.Findings.Count - 1) }

    return $result
}

function Get-PrivacyBrowserSafety {
    $result = @{
        Score      = -1
        Grade      = "N/A"
        Status     = "Not Scanned"
        Findings   = [System.Collections.ArrayList]::new()
        Actions    = [System.Collections.ArrayList]::new()
        Sources    = [System.Collections.ArrayList]::new()
    }

    $scores = [System.Collections.ArrayList]::new()

    # BrowserRiskAudit
    $browserFile = Find-LatestReport "BrowserRisk-*.html"
    if ($null -eq $browserFile) { $browserFile = Find-LatestReport "Browser*Audit-*.html" }
    if ($browserFile) {
        [void]$result.Sources.Add("BrowserRiskAudit")
        $score = Get-ScoreFromHtml -FilePath $browserFile -ScorePattern '(?:Overall|Total)[^0-9]*?(\d{1,3})'
        if ($score -lt 0) { $score = Get-ScoreFromHtml -FilePath $browserFile -ScorePattern '(\d{1,3})\s*/\s*100' }
        if ($score -ge 0) { [void]$scores.Add($score) }
        $f = Get-FindingsFromHtml -FilePath $browserFile -MaxFindings 3
        foreach ($item in $f) { [void]$result.Findings.Add($item) }
    }

    if ($scores.Count -gt 0) {
        $total = 0
        foreach ($s in $scores) { $total += $s }
        $result.Score = [math]::Round($total / $scores.Count)
        $result.Grade = Get-LetterGrade -Score $result.Score
        $result.Status = "Scanned"

        if ($result.Score -lt 70) {
            [void]$result.Actions.Add("Remove suspicious browser extensions")
            [void]$result.Actions.Add("Update browser to latest version")
            [void]$result.Actions.Add("Clear tracking cookies and cached data")
        }
    }

    while ($result.Findings.Count -gt 3) { $result.Findings.RemoveAt($result.Findings.Count - 1) }

    return $result
}

function Get-BackupReadiness {
    $result = @{
        Score      = -1
        Grade      = "N/A"
        Status     = "Not Scanned"
        Findings   = [System.Collections.ArrayList]::new()
        Actions    = [System.Collections.ArrayList]::new()
        Sources    = [System.Collections.ArrayList]::new()
    }

    $scores = [System.Collections.ArrayList]::new()

    # BackupRealityCheck
    $backupFile = Find-LatestReport "BackupReality-*.html"
    if ($null -eq $backupFile) { $backupFile = Find-LatestReport "Backup*Check-*.html" }
    if ($backupFile) {
        [void]$result.Sources.Add("BackupRealityCheck")
        $score = Get-ScoreFromHtml -FilePath $backupFile -ScorePattern '(\d{1,3})\s*/\s*100'
        if ($score -ge 0) { [void]$scores.Add($score) }
        $f = Get-FindingsFromHtml -FilePath $backupFile -MaxFindings 3
        foreach ($item in $f) { [void]$result.Findings.Add($item) }
    }

    # BitLockerAudit
    $blFile = Find-LatestReport "BitLocker-*.html"
    if ($blFile) {
        [void]$result.Sources.Add("BitLockerAudit")
        $score = Get-ScoreFromHtml -FilePath $blFile -ScorePattern '(\d{1,3})\s*/\s*100'
        if ($score -ge 0) { [void]$scores.Add($score) }
    }

    if ($scores.Count -gt 0) {
        $total = 0
        foreach ($s in $scores) { $total += $s }
        $result.Score = [math]::Round($total / $scores.Count)
        $result.Grade = Get-LetterGrade -Score $result.Score
        $result.Status = "Scanned"

        if ($result.Score -lt 70) {
            [void]$result.Actions.Add("Set up automated backup solution")
            [void]$result.Actions.Add("Verify backup recovery works")
        }
        if ($result.Score -lt 40) {
            [void]$result.Actions.Add("Critical: No reliable backup - data at risk")
        }
    }

    while ($result.Findings.Count -gt 3) { $result.Findings.RemoveAt($result.Findings.Count - 1) }

    return $result
}

function Get-NetworkSecurity {
    $result = @{
        Score      = -1
        Grade      = "N/A"
        Status     = "Not Scanned"
        Findings   = [System.Collections.ArrayList]::new()
        Actions    = [System.Collections.ArrayList]::new()
        Sources    = [System.Collections.ArrayList]::new()
    }

    $scores = [System.Collections.ArrayList]::new()

    # NetworkSnapshot
    $netFile = Find-LatestReport "NetworkSnapshot-*.html"
    if ($null -eq $netFile) { $netFile = Find-LatestReport "Network-*.html" }
    if ($netFile) {
        [void]$result.Sources.Add("NetworkSnapshot")
        $score = Get-ScoreFromHtml -FilePath $netFile -ScorePattern '(\d{1,3})\s*/\s*100'
        if ($score -ge 0) { [void]$scores.Add($score) }
        $f = Get-FindingsFromHtml -FilePath $netFile -MaxFindings 2
        foreach ($item in $f) { [void]$result.Findings.Add($item) }
    }

    # RDPExposureAudit
    $rdpFile = Find-LatestReport "RDPExposure-*.html"
    if ($null -eq $rdpFile) { $rdpFile = Find-LatestReport "RDP-*.html" }
    if ($rdpFile) {
        [void]$result.Sources.Add("RDPExposureAudit")
        $score = Get-ScoreFromHtml -FilePath $rdpFile -ScorePattern '(\d{1,3})\s*/\s*100'
        if ($score -ge 0) { [void]$scores.Add($score) }
        $f = Get-FindingsFromHtml -FilePath $rdpFile -MaxFindings 2
        foreach ($item in $f) { [void]$result.Findings.Add($item) }
    }

    if ($scores.Count -gt 0) {
        $total = 0
        foreach ($s in $scores) { $total += $s }
        $result.Score = [math]::Round($total / $scores.Count)
        $result.Grade = Get-LetterGrade -Score $result.Score
        $result.Status = "Scanned"

        if ($result.Score -lt 70) {
            [void]$result.Actions.Add("Review firewall rules and open ports")
            [void]$result.Actions.Add("Disable unnecessary remote access")
        }
    }

    while ($result.Findings.Count -gt 3) { $result.Findings.RemoveAt($result.Findings.Count - 1) }

    return $result
}

function Get-HardwareCondition {
    $result = @{
        Score      = -1
        Grade      = "N/A"
        Status     = "Not Scanned"
        Findings   = [System.Collections.ArrayList]::new()
        Actions    = [System.Collections.ArrayList]::new()
        Sources    = [System.Collections.ArrayList]::new()
    }

    $scores = [System.Collections.ArrayList]::new()

    # WearAndTear
    $wearFile = Find-LatestReport "WearAndTear-*.html"
    if ($null -eq $wearFile) { $wearFile = Find-LatestReport "Wear*Life-*.html" }
    if ($wearFile) {
        [void]$result.Sources.Add("WearAndTear")
        $score = Get-ScoreFromHtml -FilePath $wearFile -ScorePattern '(\d{1,3})\s*/\s*100'
        if ($score -ge 0) { [void]$scores.Add($score) }
        $f = Get-FindingsFromHtml -FilePath $wearFile -MaxFindings 2
        foreach ($item in $f) { [void]$result.Findings.Add($item) }
    }

    # RAMIsolation
    $ramFile = Find-LatestReport "RAMIsolation-*.html"
    if ($null -eq $ramFile) { $ramFile = Find-LatestReport "RAM-*.html" }
    if ($ramFile) {
        [void]$result.Sources.Add("RAMIsolation")
        $score = Get-ScoreFromHtml -FilePath $ramFile -ScorePattern '(\d{1,3})\s*/\s*100'
        if ($score -ge 0) { [void]$scores.Add($score) }
        $f = Get-FindingsFromHtml -FilePath $ramFile -MaxFindings 2
        foreach ($item in $f) { [void]$result.Findings.Add($item) }
    }

    # HardwareDiagnostic (from our new script)
    $hwFile = Find-LatestReport "HardwareDiag-*.html"
    if ($null -eq $hwFile) { $hwFile = Find-LatestReport "HardwareDiagnostic-*.html" }
    if ($hwFile) {
        [void]$result.Sources.Add("HardwareDiagnostic")
        $score = Get-ScoreFromHtml -FilePath $hwFile -ScorePattern '(?:Overall|Hardware)[^0-9]*?(\d{1,3})'
        if ($score -ge 0) { [void]$scores.Add($score) }
        $f = Get-FindingsFromHtml -FilePath $hwFile -MaxFindings 2
        foreach ($item in $f) { [void]$result.Findings.Add($item) }
    }

    # LCD Display
    $lcdFile = Find-LatestReport "LCD*-*.html"
    if ($lcdFile) {
        [void]$result.Sources.Add("LCDDisplayWear")
        $score = Get-ScoreFromHtml -FilePath $lcdFile -ScorePattern '(\d{1,3})\s*/\s*100'
        if ($score -ge 0) { [void]$scores.Add($score) }
    }

    if ($scores.Count -gt 0) {
        $total = 0
        foreach ($s in $scores) { $total += $s }
        $result.Score = [math]::Round($total / $scores.Count)
        $result.Grade = Get-LetterGrade -Score $result.Score
        $result.Status = "Scanned"

        if ($result.Score -lt 70) {
            [void]$result.Actions.Add("Hardware components showing wear - monitor closely")
            [void]$result.Actions.Add("Consider RAM or drive replacement if failing")
        }
        if ($result.Score -lt 40) {
            [void]$result.Actions.Add("Critical: Hardware replacement may be needed soon")
        }
    }

    while ($result.Findings.Count -gt 3) { $result.Findings.RemoveAt($result.Findings.Count - 1) }

    return $result
}

# ─────────────────────────────────────────────────────────────────────────────
# SERVICE RECOMMENDATIONS MAP
# ─────────────────────────────────────────────────────────────────────────────
function Get-ServiceRecommendations {
    param([hashtable]$Categories)

    $services = [System.Collections.ArrayList]::new()

    # Security
    $sec = $Categories["Security Posture"]
    if ($null -ne $sec -and $sec.Score -ge 0 -and $sec.Score -lt 80) {
        $priority = if ($sec.Score -lt 50) { "HIGH" } elseif ($sec.Score -lt 70) { "MEDIUM" } else { "LOW" }
        $time = if ($sec.Score -lt 50) { "2-3 hours" } else { "1-2 hours" }
        [void]$services.Add(@{
            Service   = "Security Hardening & Malware Removal"
            Priority  = $priority
            Time      = $time
            Reason    = "Security score is $($sec.Score)/100 - needs attention"
        })
    }

    # System Health
    $health = $Categories["System Health"]
    if ($null -ne $health -and $health.Score -ge 0 -and $health.Score -lt 80) {
        $priority = if ($health.Score -lt 50) { "HIGH" } elseif ($health.Score -lt 70) { "MEDIUM" } else { "LOW" }
        $time = if ($health.Score -lt 50) { "2-4 hours" } else { "1-2 hours" }
        [void]$services.Add(@{
            Service   = "System Optimization & Cleanup"
            Priority  = $priority
            Time      = $time
            Reason    = "System health score is $($health.Score)/100"
        })
    }

    # Browser
    $browser = $Categories["Privacy & Browser Safety"]
    if ($null -ne $browser -and $browser.Score -ge 0 -and $browser.Score -lt 80) {
        $priority = if ($browser.Score -lt 50) { "HIGH" } else { "MEDIUM" }
        $time = "30-60 minutes"
        [void]$services.Add(@{
            Service   = "Browser Security & Privacy Cleanup"
            Priority  = $priority
            Time      = $time
            Reason    = "Browser safety score is $($browser.Score)/100"
        })
    }

    # Backup
    $backup = $Categories["Backup Readiness"]
    if ($null -ne $backup -and $backup.Score -ge 0 -and $backup.Score -lt 80) {
        $priority = if ($backup.Score -lt 40) { "HIGH" } elseif ($backup.Score -lt 70) { "MEDIUM" } else { "LOW" }
        $time = "1-2 hours"
        [void]$services.Add(@{
            Service   = "Backup Setup & Data Protection"
            Priority  = $priority
            Time      = $time
            Reason    = "Backup readiness score is $($backup.Score)/100"
        })
    }

    # Network
    $net = $Categories["Network Security"]
    if ($null -ne $net -and $net.Score -ge 0 -and $net.Score -lt 80) {
        $priority = if ($net.Score -lt 50) { "HIGH" } else { "MEDIUM" }
        $time = "1-2 hours"
        [void]$services.Add(@{
            Service   = "Network Security & Firewall Configuration"
            Priority  = $priority
            Time      = $time
            Reason    = "Network security score is $($net.Score)/100"
        })
    }

    # Hardware
    $hw = $Categories["Hardware Condition"]
    if ($null -ne $hw -and $hw.Score -ge 0 -and $hw.Score -lt 70) {
        $priority = if ($hw.Score -lt 40) { "HIGH" } elseif ($hw.Score -lt 60) { "MEDIUM" } else { "LOW" }
        $time = if ($hw.Score -lt 40) { "Varies (parts may be needed)" } else { "1-2 hours" }
        [void]$services.Add(@{
            Service   = "Hardware Diagnosis & Component Replacement"
            Priority  = $priority
            Time      = $time
            Reason    = "Hardware condition score is $($hw.Score)/100"
        })
    }

    return $services
}

# ─────────────────────────────────────────────────────────────────────────────
# PLAIN ENGLISH SUMMARY GENERATOR
# ─────────────────────────────────────────────────────────────────────────────
function Get-PlainEnglishSummary {
    param(
        [int]$OverallScore,
        [hashtable]$Categories
    )

    $lines = [System.Collections.ArrayList]::new()

    if ($OverallScore -ge 90) {
        [void]$lines.Add("Great news! Your computer is in excellent shape overall. We found no major issues during our scan.")
    } elseif ($OverallScore -ge 80) {
        [void]$lines.Add("Your computer is in good condition with just a few minor areas that could use some attention.")
    } elseif ($OverallScore -ge 70) {
        [void]$lines.Add("Your computer is working okay, but we found some areas that need improvement to keep it running smoothly and safely.")
    } elseif ($OverallScore -ge 50) {
        [void]$lines.Add("We found several issues with your computer that should be addressed soon. Some of these could affect your security or performance.")
    } else {
        [void]$lines.Add("Your computer needs attention right away. We found significant issues that could put your data and security at risk.")
    }

    # Add category-specific plain English
    foreach ($catName in @("Security Posture", "System Health", "Privacy & Browser Safety", "Backup Readiness", "Network Security", "Hardware Condition")) {
        $cat = $Categories[$catName]
        if ($null -eq $cat -or $cat.Score -lt 0) { continue }

        switch ($catName) {
            "Security Posture" {
                if ($cat.Score -lt 60) {
                    [void]$lines.Add("Your computer's security defenses are weak. This means viruses, hackers, or malware could get in more easily. We strongly recommend a security tune-up.")
                } elseif ($cat.Score -lt 80) {
                    [void]$lines.Add("Your security is decent but has some gaps. A few updates and setting changes would make your computer much safer.")
                }
            }
            "System Health" {
                if ($cat.Score -lt 60) {
                    [void]$lines.Add("Your system is showing signs of strain - it may be running slowly, have errors, or be out of date. A cleanup and optimization would help a lot.")
                } elseif ($cat.Score -lt 80) {
                    [void]$lines.Add("Your system is running fairly well, but a tune-up could improve speed and reliability.")
                }
            }
            "Privacy & Browser Safety" {
                if ($cat.Score -lt 60) {
                    [void]$lines.Add("Your web browsers have some concerning extensions or settings that could track your activity or put your passwords at risk.")
                } elseif ($cat.Score -lt 80) {
                    [void]$lines.Add("Your browsers are mostly safe, but we found a few items worth cleaning up for better privacy.")
                }
            }
            "Backup Readiness" {
                if ($cat.Score -lt 50) {
                    [void]$lines.Add("Your important files are NOT being backed up properly. If something goes wrong (like a hard drive failure or ransomware), you could lose everything. Setting up a backup is the single most important thing we can do for you.")
                } elseif ($cat.Score -lt 80) {
                    [void]$lines.Add("You have some backup protection, but it's not complete. We can help make sure your important files are fully protected.")
                }
            }
            "Network Security" {
                if ($cat.Score -lt 60) {
                    [void]$lines.Add("Your network settings have some security holes. This could allow unauthorized access to your computer, especially if you use public WiFi.")
                } elseif ($cat.Score -lt 80) {
                    [void]$lines.Add("Your network settings are mostly good, with a few areas we can tighten up.")
                }
            }
            "Hardware Condition" {
                if ($cat.Score -lt 50) {
                    [void]$lines.Add("Some of your hardware components are showing significant wear. This could lead to failures or data loss if not addressed.")
                } elseif ($cat.Score -lt 70) {
                    [void]$lines.Add("Your hardware is showing some wear but is still functional. We recommend monitoring it closely.")
                }
            }
        }
    }

    return ($lines -join "`n`n")
}

# ─────────────────────────────────────────────────────────────────────────────
# CUSTOMER INFO FROM CONSENT LOCK
# ─────────────────────────────────────────────────────────────────────────────
function Get-CustomerInfo {
    $lockPath = Join-Path $ScriptDir ".consent-lock"
    if (Test-Path $lockPath) {
        try {
            $lock = Get-Content -Path $lockPath -Raw -ErrorAction Stop | ConvertFrom-Json
            return @{
                Name        = $lock.CustomerName
                WorkOrder   = $lock.WorkOrderNumber
                HasConsent  = $true
            }
        } catch {}
    }
    return @{
        Name        = $env:USERNAME
        WorkOrder   = "N/A"
        HasConsent  = $false
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# HTML REPORT GENERATION
# ─────────────────────────────────────────────────────────────────────────────
function New-ReportCardHtml {
    param(
        [int]$OverallScore,
        [string]$OverallGrade,
        [hashtable]$Categories,
        [System.Collections.ArrayList]$Services,
        [string]$Summary,
        [string]$CustomerName,
        [string]$TechnicianName,
        [string]$WorkOrder
    )

    $overallColor = Get-GradeColor -Grade $OverallGrade
    $dateStr = Get-Date -Format "MMMM dd, yyyy 'at' hh:mm tt"

    # Build category cards HTML
    $categoryHtml = ""
    $categoryOrder = @("Security Posture", "System Health", "Privacy & Browser Safety", "Backup Readiness", "Network Security", "Hardware Condition")
    $categoryIcons = @{
        "Security Posture"          = "&#128737;"
        "System Health"             = "&#9881;"
        "Privacy & Browser Safety"  = "&#128065;"
        "Backup Readiness"          = "&#128190;"
        "Network Security"          = "&#128279;"
        "Hardware Condition"        = "&#128187;"
    }

    foreach ($catName in $categoryOrder) {
        $cat = $Categories[$catName]
        $icon = $categoryIcons[$catName]
        if ($null -eq $icon) { $icon = "&#9733;" }

        if ($null -eq $cat -or $cat.Score -lt 0) {
            # Not scanned
            $categoryHtml += @"
            <div class="category-card not-scanned">
                <div class="cat-header">
                    <span class="cat-icon">$icon</span>
                    <span class="cat-name">$catName</span>
                    <span class="cat-badge" style="background: #555;">NOT SCANNED</span>
                </div>
                <div class="cat-body">
                    <p style="color: #777; font-style: italic;">This area has not been scanned yet. Run the corresponding PC Plus 360 tool to assess this category.</p>
                </div>
            </div>
"@
        } else {
            $catColor = Get-GradeColor -Grade $cat.Grade
            $findingsHtml = ""
            if ($cat.Findings.Count -gt 0) {
                $findingsHtml = "<ul class='findings-list'>"
                foreach ($f in $cat.Findings) {
                    $findingsHtml += "<li>$([System.Web.HttpUtility]::HtmlEncode($f))</li>"
                }
                $findingsHtml += "</ul>"
            } else {
                $findingsHtml = "<p style='color: ${COLOR_GREEN}; font-size: 13px;'>No significant issues found.</p>"
            }

            $actionsHtml = ""
            if ($cat.Actions.Count -gt 0) {
                $actionsHtml = "<div class='actions-box'><strong>Recommended:</strong><ul>"
                foreach ($a in $cat.Actions) {
                    $actionsHtml += "<li>$([System.Web.HttpUtility]::HtmlEncode($a))</li>"
                }
                $actionsHtml += "</ul></div>"
            }

            $sourcesStr = if ($cat.Sources.Count -gt 0) { ($cat.Sources -join ", ") } else { "N/A" }

            $categoryHtml += @"
            <div class="category-card">
                <div class="cat-header">
                    <span class="cat-icon">$icon</span>
                    <span class="cat-name">$catName</span>
                    <span class="cat-grade" style="background: $catColor;">$($cat.Grade)</span>
                    <span class="cat-score">$($cat.Score)/100</span>
                </div>
                <div class="cat-body">
                    <div class="score-bar-container">
                        <div class="score-bar" style="width: $($cat.Score)%; background: $catColor;"></div>
                    </div>
                    <div class="cat-findings">
                        $findingsHtml
                    </div>
                    $actionsHtml
                    <div class="cat-sources">Data from: $sourcesStr</div>
                </div>
            </div>
"@
        }
    }

    # Services section
    $servicesHtml = ""
    if ($Services.Count -gt 0) {
        foreach ($svc in $Services) {
            $priColor = switch ($svc.Priority) {
                "HIGH"   { $COLOR_RED }
                "MEDIUM" { $COLOR_ORANGE }
                "LOW"    { $COLOR_GREEN }
                default  { "#888" }
            }
            $servicesHtml += @"
            <tr>
                <td style="padding: 12px 15px; border-bottom: 1px solid #1e2d45;">$([System.Web.HttpUtility]::HtmlEncode($svc.Service))</td>
                <td style="padding: 12px 15px; border-bottom: 1px solid #1e2d45; text-align: center;">
                    <span style="background: $priColor; color: white; padding: 3px 10px; border-radius: 10px; font-size: 11px; font-weight: bold;">$($svc.Priority)</span>
                </td>
                <td style="padding: 12px 15px; border-bottom: 1px solid #1e2d45; text-align: center;">$($svc.Time)</td>
                <td style="padding: 12px 15px; border-bottom: 1px solid #1e2d45; font-size: 12px; color: #8899aa;">$([System.Web.HttpUtility]::HtmlEncode($svc.Reason))</td>
            </tr>
"@
        }
    } else {
        $servicesHtml = @"
        <tr>
            <td colspan="4" style="padding: 20px; text-align: center; color: ${COLOR_GREEN}; font-style: italic;">
                No service recommendations at this time - your computer is in great shape!
            </td>
        </tr>
"@
    }

    # Scanned count
    $scannedCount = 0
    $totalCategories = 6
    foreach ($catName in $categoryOrder) {
        $cat = $Categories[$catName]
        if ($null -ne $cat -and $cat.Score -ge 0) { $scannedCount++ }
    }

    $summaryHtmlEncoded = [System.Web.HttpUtility]::HtmlEncode($Summary) -replace "`n`n", "</p><p>" -replace "`n", "<br>"

    $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>PC Plus 360 Report Card - $([System.Web.HttpUtility]::HtmlEncode($CustomerName))</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: ${COLOR_NAVY};
            color: #e0e0e0;
            line-height: 1.6;
        }
        .container { max-width: 900px; margin: 0 auto; padding: 20px; }
        .header {
            background: linear-gradient(135deg, ${COLOR_NAVY} 0%, #142238 100%);
            border: 2px solid ${COLOR_ACCENT};
            border-radius: 12px;
            padding: 30px;
            text-align: center;
            margin-bottom: 25px;
        }
        .header h1 { color: ${COLOR_ACCENT}; font-size: 28px; margin-bottom: 5px; }
        .header h2 { color: #8899aa; font-size: 16px; font-weight: 400; }
        .header .logo-placeholder {
            width: 120px; height: 60px;
            margin: 0 auto 15px;
            border: 1px dashed ${COLOR_ACCENT};
            border-radius: 8px;
            display: flex; align-items: center; justify-content: center;
            color: ${COLOR_ACCENT}; font-size: 11px;
        }
        .overall-grade {
            text-align: center;
            margin-bottom: 25px;
            padding: 30px;
            background: #0f1f35;
            border-radius: 12px;
            border: 1px solid #1e2d45;
        }
        .grade-badge {
            display: inline-block;
            width: 120px; height: 120px;
            border-radius: 50%;
            line-height: 120px;
            font-size: 48px;
            font-weight: 800;
            color: white;
            text-align: center;
            margin-bottom: 15px;
            box-shadow: 0 4px 20px rgba(0,0,0,0.3);
        }
        .overall-score { font-size: 22px; color: #ccc; margin-top: 5px; }
        .scan-coverage { font-size: 13px; color: #8899aa; margin-top: 8px; }
        .customer-info {
            display: flex; justify-content: space-between;
            background: #0f1f35;
            border: 1px solid #1e2d45;
            border-radius: 10px;
            padding: 15px 25px;
            margin-bottom: 25px;
            font-size: 13px;
        }
        .customer-info .info-item { text-align: center; }
        .customer-info .info-label { color: #8899aa; font-size: 11px; text-transform: uppercase; }
        .customer-info .info-value { color: white; font-weight: 600; margin-top: 2px; }
        .section { margin-bottom: 25px; }
        .section-title {
            color: ${COLOR_ACCENT};
            font-size: 20px; font-weight: 600;
            margin-bottom: 15px;
            padding-bottom: 8px;
            border-bottom: 2px solid ${COLOR_ACCENT};
        }
        .category-card {
            background: #0f1f35;
            border: 1px solid #1e2d45;
            border-radius: 10px;
            margin-bottom: 15px;
            overflow: hidden;
        }
        .category-card.not-scanned { opacity: 0.6; }
        .cat-header {
            display: flex; align-items: center;
            padding: 15px 20px;
            background: #0c1a2e;
            border-bottom: 1px solid #1e2d45;
        }
        .cat-icon { font-size: 20px; margin-right: 12px; }
        .cat-name { flex: 1; font-size: 16px; font-weight: 600; color: white; }
        .cat-grade {
            display: inline-block;
            padding: 4px 14px;
            border-radius: 15px;
            font-size: 16px; font-weight: 800;
            color: white;
            margin-right: 10px;
        }
        .cat-badge {
            display: inline-block;
            padding: 4px 14px;
            border-radius: 15px;
            font-size: 12px; font-weight: 600;
            color: white;
        }
        .cat-score { color: #8899aa; font-size: 14px; }
        .cat-body { padding: 15px 20px; }
        .score-bar-container {
            height: 6px; background: #1a2a40;
            border-radius: 3px;
            margin-bottom: 12px;
            overflow: hidden;
        }
        .score-bar { height: 100%; border-radius: 3px; transition: width 0.5s; }
        .findings-list { list-style: none; padding: 0; }
        .findings-list li {
            padding: 5px 0 5px 20px;
            position: relative;
            font-size: 13px;
            color: #ccc;
        }
        .findings-list li::before {
            content: '\\25CF';
            position: absolute; left: 0;
            color: ${COLOR_ORANGE};
        }
        .actions-box {
            background: #1a2a40;
            border-left: 3px solid ${COLOR_ACCENT};
            padding: 10px 15px;
            margin-top: 10px;
            border-radius: 0 6px 6px 0;
            font-size: 13px;
        }
        .actions-box ul { list-style: disc; padding-left: 20px; margin-top: 5px; }
        .actions-box li { padding: 2px 0; color: #ccc; }
        .cat-sources { font-size: 11px; color: #5a6a7a; margin-top: 10px; font-style: italic; }
        .summary-box {
            background: #0f1f35;
            border: 1px solid #1e2d45;
            border-radius: 10px;
            padding: 25px;
            margin-bottom: 25px;
        }
        .summary-box p { margin-bottom: 12px; font-size: 15px; color: #ccc; line-height: 1.7; }
        .services-table { width: 100%; border-collapse: collapse; }
        .services-table th {
            background: #0c1a2e;
            color: ${COLOR_ACCENT};
            padding: 12px 15px;
            text-align: left;
            font-size: 13px;
            text-transform: uppercase;
            letter-spacing: 0.5px;
        }
        .services-table td { color: #e0e0e0; font-size: 14px; }
        .qr-section {
            text-align: center;
            margin: 25px 0;
        }
        .qr-placeholder {
            display: inline-block;
            width: 120px; height: 120px;
            border: 2px dashed ${COLOR_ACCENT};
            border-radius: 10px;
            line-height: 120px;
            color: ${COLOR_ACCENT};
            font-size: 11px;
        }
        .signature-line {
            display: flex; justify-content: space-between;
            margin-top: 40px; padding-top: 20px;
            border-top: 1px solid #1e2d45;
        }
        .sig-block { text-align: center; width: 45%; }
        .sig-line { border-top: 1px solid #5a6a7a; margin-top: 40px; padding-top: 8px; color: #8899aa; font-size: 12px; }
        .footer {
            text-align: center; padding: 20px;
            color: #5a6a7a; font-size: 12px;
            border-top: 1px solid #1e2d45;
            margin-top: 30px;
        }
        @media print {
            body { background: white; color: #333; }
            .header { background: white; border-color: #2596be; }
            .header h1 { color: #0a1628; }
            .overall-grade, .category-card, .summary-box, .customer-info { background: #f8f9fa; border-color: #ddd; }
            .cat-header { background: #eee; border-color: #ddd; }
            .cat-name, .customer-info .info-value { color: #333; }
            .cat-body, .findings-list li, .actions-box li, .summary-box p { color: #444; }
            .services-table th { background: #eee; color: #333; }
            .services-table td { color: #333; }
            .score-bar-container { background: #ddd; }
            .actions-box { background: #f0f0f0; }
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <div class="logo-placeholder">[PC Plus Logo]</div>
            <h1>$COMPANY_FULL</h1>
            <h2>Computer Health Report Card</h2>
        </div>

        <div class="customer-info">
            <div class="info-item">
                <div class="info-label">Customer</div>
                <div class="info-value">$([System.Web.HttpUtility]::HtmlEncode($CustomerName))</div>
            </div>
            <div class="info-item">
                <div class="info-label">Computer</div>
                <div class="info-value">$env:COMPUTERNAME</div>
            </div>
            <div class="info-item">
                <div class="info-label">Work Order</div>
                <div class="info-value">$([System.Web.HttpUtility]::HtmlEncode($WorkOrder))</div>
            </div>
            <div class="info-item">
                <div class="info-label">Date</div>
                <div class="info-value">$dateStr</div>
            </div>
        </div>

        <div class="overall-grade">
            <div class="grade-badge" style="background: $overallColor;">$OverallGrade</div>
            <div class="overall-score">Overall Score: $OverallScore / 100</div>
            <div class="scan-coverage">$scannedCount of $totalCategories categories scanned</div>
        </div>

        <div class="section">
            <div class="section-title">What We Found</div>
            <div class="summary-box">
                <p>$summaryHtmlEncoded</p>
            </div>
        </div>

        <div class="section">
            <div class="section-title">Category Breakdown</div>
            $categoryHtml
        </div>

        <div class="section">
            <div class="section-title">Recommended Services</div>
            <div style="background: #0f1f35; border: 1px solid #1e2d45; border-radius: 10px; overflow: hidden;">
                <table class="services-table">
                    <thead>
                        <tr>
                            <th>Service</th>
                            <th style="text-align: center;">Priority</th>
                            <th style="text-align: center;">Est. Time</th>
                            <th>Reason</th>
                        </tr>
                    </thead>
                    <tbody>
                        $servicesHtml
                    </tbody>
                </table>
            </div>
        </div>

        <div class="qr-section">
            <div class="qr-placeholder">[QR Code]</div>
            <p style="color: #8899aa; font-size: 12px; margin-top: 8px;">
                Scan to visit $COMPANY_WEBSITE<br>or book a service appointment
            </p>
        </div>

        <div class="signature-line">
            <div class="sig-block">
                <div class="sig-line">Customer Signature</div>
            </div>
            <div class="sig-block">
                <div class="sig-line">Technician: $([System.Web.HttpUtility]::HtmlEncode($TechnicianName))</div>
            </div>
        </div>

        <div class="footer">
            <p>$COMPANY_NAME &nbsp;|&nbsp; $COMPANY_PHONE1 &nbsp;|&nbsp; $COMPANY_PHONE2 &nbsp;|&nbsp; $COMPANY_WEBSITE</p>
            <p style="margin-top: 5px;">Report generated on $dateStr &nbsp;|&nbsp; $COMPANY_FULL Diagnostic Toolkit</p>
        </div>
    </div>
</body>
</html>
"@
    return $html
}

# ─────────────────────────────────────────────────────────────────────────────
# JSON EXPORT
# ─────────────────────────────────────────────────────────────────────────────
function Save-ReportCardJson {
    param(
        [int]$OverallScore,
        [string]$OverallGrade,
        [hashtable]$Categories,
        [System.Collections.ArrayList]$Services,
        [string]$CustomerName,
        [string]$WorkOrder,
        [string]$OutputPath
    )

    $catData = [ordered]@{}
    foreach ($catName in @("Security Posture", "System Health", "Privacy & Browser Safety", "Backup Readiness", "Network Security", "Hardware Condition")) {
        $cat = $Categories[$catName]
        if ($null -ne $cat) {
            $catData[$catName] = [ordered]@{
                Score    = $cat.Score
                Grade    = $cat.Grade
                Status   = $cat.Status
                Findings = @($cat.Findings)
                Actions  = @($cat.Actions)
                Sources  = @($cat.Sources)
            }
        } else {
            $catData[$catName] = [ordered]@{
                Score    = -1
                Grade    = "N/A"
                Status   = "Not Scanned"
                Findings = @()
                Actions  = @()
                Sources  = @()
            }
        }
    }

    $svcData = [System.Collections.ArrayList]::new()
    foreach ($svc in $Services) {
        [void]$svcData.Add([ordered]@{
            Service  = $svc.Service
            Priority = $svc.Priority
            Time     = $svc.Time
            Reason   = $svc.Reason
        })
    }

    $jsonObj = [ordered]@{
        ToolName      = "ReportCard"
        Version       = "1.0.0"
        ComputerName  = $env:COMPUTERNAME
        CustomerName  = $CustomerName
        WorkOrder     = $WorkOrder
        DateTime      = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        TimestampUTC  = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        OverallScore  = $OverallScore
        OverallGrade  = $OverallGrade
        Categories    = $catData
        Services      = @($svcData)
    }
    $jsonObj | ConvertTo-Json -Depth 10 | Set-Content -Path $OutputPath -Encoding UTF8 -Force
}

# ─────────────────────────────────────────────────────────────────────────────
# WINFORMS UI - PREVIEW & EXPORT
# ─────────────────────────────────────────────────────────────────────────────
function Show-ReportCardUI {
    $customerInfo = Get-CustomerInfo

    # ── Launch form for technician name ──
    $launchForm = New-Object System.Windows.Forms.Form
    $launchForm.Text = "$COMPANY_FULL - Report Card Generator"
    $launchForm.Size = New-Object System.Drawing.Size(500, 300)
    $launchForm.StartPosition = "CenterScreen"
    $launchForm.FormBorderStyle = "FixedDialog"
    $launchForm.MaximizeBox = $false
    $launchForm.BackColor = [System.Drawing.ColorTranslator]::FromHtml($COLOR_NAVY)
    $launchForm.ForeColor = [System.Drawing.Color]::White
    $launchForm.Font = New-Object System.Drawing.Font("Segoe UI", 9)

    $yPos = 20

    $lblTitle = New-Object System.Windows.Forms.Label
    $lblTitle.Text = "$COMPANY_FULL"
    $lblTitle.Font = New-Object System.Drawing.Font("Segoe UI", 16, [System.Drawing.FontStyle]::Bold)
    $lblTitle.ForeColor = [System.Drawing.ColorTranslator]::FromHtml($COLOR_ACCENT)
    $lblTitle.AutoSize = $false
    $lblTitle.Size = New-Object System.Drawing.Size(460, 30)
    $lblTitle.Location = New-Object System.Drawing.Point(15, $yPos)
    $lblTitle.TextAlign = "MiddleCenter"
    $launchForm.Controls.Add($lblTitle)
    $yPos += 35

    $lblSub = New-Object System.Windows.Forms.Label
    $lblSub.Text = "Customer Report Card Generator"
    $lblSub.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $lblSub.ForeColor = [System.Drawing.Color]::FromArgb(136, 153, 170)
    $lblSub.AutoSize = $false
    $lblSub.Size = New-Object System.Drawing.Size(460, 22)
    $lblSub.Location = New-Object System.Drawing.Point(15, $yPos)
    $lblSub.TextAlign = "MiddleCenter"
    $launchForm.Controls.Add($lblSub)
    $yPos += 35

    # Customer Name
    $lblCust = New-Object System.Windows.Forms.Label
    $lblCust.Text = "Customer Name:"
    $lblCust.ForeColor = [System.Drawing.ColorTranslator]::FromHtml($COLOR_ACCENT)
    $lblCust.AutoSize = $true
    $lblCust.Location = New-Object System.Drawing.Point(25, $yPos)
    $launchForm.Controls.Add($lblCust)
    $yPos += 20

    $txtCust = New-Object System.Windows.Forms.TextBox
    $txtCust.Font = New-Object System.Drawing.Font("Segoe UI", 11)
    $txtCust.Size = New-Object System.Drawing.Size(430, 28)
    $txtCust.Location = New-Object System.Drawing.Point(25, $yPos)
    $txtCust.BackColor = [System.Drawing.Color]::FromArgb(26, 42, 64)
    $txtCust.ForeColor = [System.Drawing.Color]::White
    $txtCust.BorderStyle = "FixedSingle"
    $txtCust.Text = $customerInfo.Name
    $launchForm.Controls.Add($txtCust)
    $yPos += 38

    # Technician Name
    $lblTech = New-Object System.Windows.Forms.Label
    $lblTech.Text = "Technician Name:"
    $lblTech.ForeColor = [System.Drawing.ColorTranslator]::FromHtml($COLOR_ACCENT)
    $lblTech.AutoSize = $true
    $lblTech.Location = New-Object System.Drawing.Point(25, $yPos)
    $launchForm.Controls.Add($lblTech)
    $yPos += 20

    $txtTech = New-Object System.Windows.Forms.TextBox
    $txtTech.Font = New-Object System.Drawing.Font("Segoe UI", 11)
    $txtTech.Size = New-Object System.Drawing.Size(430, 28)
    $txtTech.Location = New-Object System.Drawing.Point(25, $yPos)
    $txtTech.BackColor = [System.Drawing.Color]::FromArgb(26, 42, 64)
    $txtTech.ForeColor = [System.Drawing.Color]::White
    $txtTech.BorderStyle = "FixedSingle"
    $launchForm.Controls.Add($txtTech)
    $yPos += 42

    $btnGenerate = New-Object System.Windows.Forms.Button
    $btnGenerate.Text = "Generate Report Card"
    $btnGenerate.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
    $btnGenerate.Size = New-Object System.Drawing.Size(200, 38)
    $btnGenerate.Location = New-Object System.Drawing.Point(80, $yPos)
    $btnGenerate.FlatStyle = "Flat"
    $btnGenerate.BackColor = [System.Drawing.ColorTranslator]::FromHtml($COLOR_GREEN)
    $btnGenerate.ForeColor = [System.Drawing.Color]::White
    $btnGenerate.Cursor = [System.Windows.Forms.Cursors]::Hand
    $launchForm.Controls.Add($btnGenerate)

    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = "Cancel"
    $btnCancel.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $btnCancel.Size = New-Object System.Drawing.Size(100, 38)
    $btnCancel.Location = New-Object System.Drawing.Point(295, $yPos)
    $btnCancel.FlatStyle = "Flat"
    $btnCancel.BackColor = [System.Drawing.Color]::FromArgb(60, 70, 85)
    $btnCancel.ForeColor = [System.Drawing.Color]::White
    $btnCancel.Add_Click({ $launchForm.Close() })
    $launchForm.Controls.Add($btnCancel)

    $script:launchResult = $null

    $btnGenerate.Add_Click({
        if ([string]::IsNullOrWhiteSpace($txtCust.Text)) {
            [System.Windows.Forms.MessageBox]::Show("Please enter a customer name.", "Validation", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
            return
        }
        $script:launchResult = @{
            CustomerName  = $txtCust.Text.Trim()
            TechnicianName = $txtTech.Text.Trim()
            WorkOrder     = $customerInfo.WorkOrder
        }
        $launchForm.Close()
    })

    [void]$launchForm.ShowDialog()

    if ($null -eq $script:launchResult) { return }

    # ── Gather all category data ──
    $categories = @{}
    $categories["Security Posture"]         = Get-SecurityPosture
    $categories["System Health"]            = Get-SystemHealth
    $categories["Privacy & Browser Safety"] = Get-PrivacyBrowserSafety
    $categories["Backup Readiness"]         = Get-BackupReadiness
    $categories["Network Security"]         = Get-NetworkSecurity
    $categories["Hardware Condition"]       = Get-HardwareCondition

    # ── Calculate overall score (average of scanned categories) ──
    $scannedScores = [System.Collections.ArrayList]::new()
    foreach ($key in $categories.Keys) {
        $cat = $categories[$key]
        if ($null -ne $cat -and $cat.Score -ge 0) {
            [void]$scannedScores.Add($cat.Score)
        }
    }

    $overallScore = 0
    if ($scannedScores.Count -gt 0) {
        $total = 0
        foreach ($s in $scannedScores) { $total += $s }
        $overallScore = [math]::Round($total / $scannedScores.Count)
    }
    $overallGrade = Get-LetterGrade -Score $overallScore

    # ── Service Recommendations ──
    $services = Get-ServiceRecommendations -Categories $categories

    # ── Plain English Summary ──
    $summary = Get-PlainEnglishSummary -OverallScore $overallScore -Categories $categories

    # ── Generate HTML ──
    $html = New-ReportCardHtml -OverallScore $overallScore -OverallGrade $overallGrade `
        -Categories $categories -Services $services -Summary $summary `
        -CustomerName $script:launchResult.CustomerName `
        -TechnicianName $script:launchResult.TechnicianName `
        -WorkOrder $script:launchResult.WorkOrder

    # ── Save files ──
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $htmlFileName = "ReportCard-$env:COMPUTERNAME-$timestamp.html"
    $htmlPath = Join-Path $ReportsDir $htmlFileName
    $html | Set-Content -Path $htmlPath -Encoding UTF8 -Force

    $jsonFileName = "ReportCard-$env:COMPUTERNAME-$timestamp.json"
    $jsonPath = Join-Path $ReportsDir $jsonFileName
    Save-ReportCardJson -OverallScore $overallScore -OverallGrade $overallGrade `
        -Categories $categories -Services $services `
        -CustomerName $script:launchResult.CustomerName `
        -WorkOrder $script:launchResult.WorkOrder `
        -OutputPath $jsonPath

    # ── Results / Export Window ──
    $resultForm = New-Object System.Windows.Forms.Form
    $resultForm.Text = "$COMPANY_FULL - Report Card: $overallGrade ($overallScore/100)"
    $resultForm.Size = New-Object System.Drawing.Size(750, 550)
    $resultForm.StartPosition = "CenterScreen"
    $resultForm.BackColor = [System.Drawing.ColorTranslator]::FromHtml($COLOR_NAVY)
    $resultForm.ForeColor = [System.Drawing.Color]::White
    $resultForm.Font = New-Object System.Drawing.Font("Segoe UI", 9)

    $yPos = 15

    # Header
    $lblResTitle = New-Object System.Windows.Forms.Label
    $lblResTitle.Text = "Report Card Generated"
    $lblResTitle.Font = New-Object System.Drawing.Font("Segoe UI", 16, [System.Drawing.FontStyle]::Bold)
    $lblResTitle.ForeColor = [System.Drawing.ColorTranslator]::FromHtml($COLOR_ACCENT)
    $lblResTitle.AutoSize = $false
    $lblResTitle.Size = New-Object System.Drawing.Size(710, 30)
    $lblResTitle.Location = New-Object System.Drawing.Point(15, $yPos)
    $lblResTitle.TextAlign = "MiddleCenter"
    $resultForm.Controls.Add($lblResTitle)
    $yPos += 40

    # Grade display
    $gradeColor = Get-GradeColor -Grade $overallGrade
    $lblGrade = New-Object System.Windows.Forms.Label
    $lblGrade.Text = $overallGrade
    $lblGrade.Font = New-Object System.Drawing.Font("Segoe UI", 40, [System.Drawing.FontStyle]::Bold)
    $lblGrade.ForeColor = [System.Drawing.ColorTranslator]::FromHtml($gradeColor)
    $lblGrade.AutoSize = $false
    $lblGrade.Size = New-Object System.Drawing.Size(710, 70)
    $lblGrade.Location = New-Object System.Drawing.Point(15, $yPos)
    $lblGrade.TextAlign = "MiddleCenter"
    $resultForm.Controls.Add($lblGrade)
    $yPos += 70

    $lblScoreLine = New-Object System.Windows.Forms.Label
    $lblScoreLine.Text = "Overall Score: $overallScore / 100  |  $($scannedScores.Count) of 6 categories scanned"
    $lblScoreLine.Font = New-Object System.Drawing.Font("Segoe UI", 11)
    $lblScoreLine.ForeColor = [System.Drawing.Color]::FromArgb(200, 200, 200)
    $lblScoreLine.AutoSize = $false
    $lblScoreLine.Size = New-Object System.Drawing.Size(710, 25)
    $lblScoreLine.Location = New-Object System.Drawing.Point(15, $yPos)
    $lblScoreLine.TextAlign = "MiddleCenter"
    $resultForm.Controls.Add($lblScoreLine)
    $yPos += 35

    # Category summary list
    $listView = New-Object System.Windows.Forms.ListView
    $listView.View = "Details"
    $listView.Location = New-Object System.Drawing.Point(20, $yPos)
    $listView.Size = New-Object System.Drawing.Size(690, 200)
    $listView.BackColor = [System.Drawing.Color]::FromArgb(15, 31, 53)
    $listView.ForeColor = [System.Drawing.Color]::White
    $listView.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $listView.FullRowSelect = $true
    $listView.GridLines = $true
    $listView.HeaderStyle = "Nonclickable"

    [void]$listView.Columns.Add("Category", 220)
    [void]$listView.Columns.Add("Score", 80)
    [void]$listView.Columns.Add("Grade", 80)
    [void]$listView.Columns.Add("Status", 120)
    [void]$listView.Columns.Add("Sources", 180)

    foreach ($catName in @("Security Posture", "System Health", "Privacy & Browser Safety", "Backup Readiness", "Network Security", "Hardware Condition")) {
        $cat = $categories[$catName]
        $item = New-Object System.Windows.Forms.ListViewItem($catName)
        if ($null -ne $cat -and $cat.Score -ge 0) {
            [void]$item.SubItems.Add("$($cat.Score)/100")
            [void]$item.SubItems.Add($cat.Grade)
            [void]$item.SubItems.Add("Scanned")
            [void]$item.SubItems.Add(($cat.Sources -join ", "))
        } else {
            [void]$item.SubItems.Add("--")
            [void]$item.SubItems.Add("N/A")
            [void]$item.SubItems.Add("Not Scanned")
            [void]$item.SubItems.Add("--")
        }
        [void]$listView.Items.Add($item)
    }

    $resultForm.Controls.Add($listView)
    $yPos += 215

    # Buttons
    $btnOpenBrowser = New-Object System.Windows.Forms.Button
    $btnOpenBrowser.Text = "Open in Browser"
    $btnOpenBrowser.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $btnOpenBrowser.Size = New-Object System.Drawing.Size(160, 38)
    $btnOpenBrowser.Location = New-Object System.Drawing.Point(120, $yPos)
    $btnOpenBrowser.FlatStyle = "Flat"
    $btnOpenBrowser.BackColor = [System.Drawing.ColorTranslator]::FromHtml($COLOR_ACCENT)
    $btnOpenBrowser.ForeColor = [System.Drawing.Color]::White
    $btnOpenBrowser.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btnOpenBrowser.Add_Click({ Start-Process $htmlPath })
    $resultForm.Controls.Add($btnOpenBrowser)

    $btnSaveAs = New-Object System.Windows.Forms.Button
    $btnSaveAs.Text = "Save as HTML..."
    $btnSaveAs.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $btnSaveAs.Size = New-Object System.Drawing.Size(140, 38)
    $btnSaveAs.Location = New-Object System.Drawing.Point(295, $yPos)
    $btnSaveAs.FlatStyle = "Flat"
    $btnSaveAs.BackColor = [System.Drawing.ColorTranslator]::FromHtml($COLOR_GREEN)
    $btnSaveAs.ForeColor = [System.Drawing.Color]::White
    $btnSaveAs.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btnSaveAs.Add_Click({
        $sfd = New-Object System.Windows.Forms.SaveFileDialog
        $sfd.Filter = "HTML Files (*.html)|*.html"
        $sfd.FileName = $htmlFileName
        $sfd.Title = "Save Report Card"
        if ($sfd.ShowDialog() -eq "OK") {
            Copy-Item -Path $htmlPath -Destination $sfd.FileName -Force
            [System.Windows.Forms.MessageBox]::Show("Report saved to:`n$($sfd.FileName)", "Saved", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
        }
    })
    $resultForm.Controls.Add($btnSaveAs)

    $btnClose = New-Object System.Windows.Forms.Button
    $btnClose.Text = "Close"
    $btnClose.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $btnClose.Size = New-Object System.Drawing.Size(100, 38)
    $btnClose.Location = New-Object System.Drawing.Point(450, $yPos)
    $btnClose.FlatStyle = "Flat"
    $btnClose.BackColor = [System.Drawing.Color]::FromArgb(60, 70, 85)
    $btnClose.ForeColor = [System.Drawing.Color]::White
    $btnClose.Add_Click({ $resultForm.Close() })
    $resultForm.Controls.Add($btnClose)
    $yPos += 50

    # Footer
    $lblFoot = New-Object System.Windows.Forms.Label
    $lblFoot.Text = "Reports saved to: $ReportsDir"
    $lblFoot.Font = New-Object System.Drawing.Font("Segoe UI", 8)
    $lblFoot.ForeColor = [System.Drawing.Color]::FromArgb(90, 106, 122)
    $lblFoot.AutoSize = $false
    $lblFoot.Size = New-Object System.Drawing.Size(710, 18)
    $lblFoot.Location = New-Object System.Drawing.Point(15, $yPos)
    $lblFoot.TextAlign = "MiddleCenter"
    $resultForm.Controls.Add($lblFoot)

    [void]$resultForm.ShowDialog()
}

# ─────────────────────────────────────────────────────────────────────────────
# MAIN ENTRY POINT
# ─────────────────────────────────────────────────────────────────────────────
Show-ReportCardUI

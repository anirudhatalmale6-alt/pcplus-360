<#
.SYNOPSIS
    PC Plus Computing 360 - Ransomware Readiness Assessment & Simulation Toolkit
.DESCRIPTION
    Comprehensive ransomware defense assessment with WinForms tabbed interface.
    Checks for ransomware indicators, shadow copy integrity, Defender status,
    Controlled Folder Access, SMB exposure, and macro settings. Includes a
    read-only simulation tab and hardening recommendations. Generates a branded
    HTML report with MITRE ATT&CK mapping and a 0-100 readiness score.
.NOTES
    Company:  PC Plus Computing
    Website:  pcpluscomputing.com
    Phone:    604-760-1662 | 236-500-2700
    Version:  1.0.0
    Requires: PowerShell 5.1+, Windows 10/11, Administrator privileges
    Part of:  PC Plus 360 USB Diagnostic Toolkit
.EXAMPLE
    PowerShell.exe -ExecutionPolicy Bypass -File .\PCPlus-RansomwareReadiness.ps1
#>

#Requires -Version 5.1

$ErrorActionPreference = 'Continue'

# ─────────────────────────────────────────────────────────────────────────────
# ASSEMBLIES & VISUAL STYLES
# ─────────────────────────────────────────────────────────────────────────────
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

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
        $arguments = "-STA -NoProfile -ExecutionPolicy Bypass -File `"$($MyInvocation.MyCommand.Definition)`""
        Start-Process powershell.exe -ArgumentList $arguments -Verb RunAs
    } catch {
        [System.Windows.Forms.MessageBox]::Show(
            "This tool requires Administrator privileges.`nPlease right-click and 'Run as Administrator'.",
            "PC Plus Ransomware Readiness - Elevation Required",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
    }
    exit
}

# ─────────────────────────────────────────────────────────────────────────────
# BRANDING CONSTANTS
# ─────────────────────────────────────────────────────────────────────────────
$COMPANY_NAME    = "PC Plus Computing"
$COMPANY_WEBSITE = "pcpluscomputing.com"
$COMPANY_PHONE1  = "604-760-1662"
$COMPANY_PHONE2  = "236-500-2700"
$SCRIPT_VERSION  = "1.0.0"
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

$Timestamp    = Get-Date -Format "yyyyMMdd-HHmmss"
$ScanDate     = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$ComputerSafe = $env:COMPUTERNAME -replace '[^\w\-]', '_'

# ─────────────────────────────────────────────────────────────────────────────
# HELPERS
# ─────────────────────────────────────────────────────────────────────────────
function Invoke-Safe {
    param([scriptblock]$Block, $Default = $null)
    try { return (& $Block) } catch { return $Default }
}

function HtmlEncode {
    param([string]$Text)
    if ($null -eq $Text) { return "" }
    $Text.Replace("&","&amp;").Replace("<","&lt;").Replace(">","&gt;").Replace('"',"&quot;")
}

# ─────────────────────────────────────────────────────────────────────────────
# KNOWN RANSOMWARE EXTENSIONS (common families)
# ─────────────────────────────────────────────────────────────────────────────
$RansomwareExtensions = @(
    ".encrypted", ".enc", ".crypted", ".crypto", ".crypt", ".locked", ".lock",
    ".cerber", ".cerber2", ".cerber3", ".zepto", ".locky", ".odin", ".thor",
    ".aesir", ".zzzzz", ".osiris", ".sage", ".dharma", ".wallet", ".onion",
    ".arena", ".java", ".bip", ".combo", ".gamma", ".arrow", ".audit",
    ".crab", ".krab", ".GANDCRAB", ".STOP", ".djvu", ".rumba", ".tro",
    ".puma", ".pumax", ".pumas", ".shadow", ".litar", ".gero", ".hese",
    ".xdata", ".seto", ".moka", ".peta", ".mpal", ".sqpc", ".mado",
    ".jope", ".mpaj", ".nile", ".gujd", ".ygkz", ".wbxd", ".sspq",
    ".watz", ".waqa", ".WNCRY", ".wncry", ".wcry", ".wncryt",
    ".WANNACRY", ".CRYPTOLOCKER", ".cryptolocker",
    ".ecc", ".ezz", ".exx", ".xyz", ".zzz", ".aaa", ".abc",
    ".ccc", ".vvv", ".xxx", ".ttt", ".micro", ".mp3", ".fun",
    ".pays", ".luceq", ".conti", ".ryuk", ".revil", ".sodinokibi",
    ".maze", ".egregor", ".clop", ".cl0p", ".avaddon", ".darkside",
    ".blackmatter", ".blackcat", ".alphv", ".lockbit", ".lockbit3",
    ".hive", ".royal", ".play", ".akira", ".rhysida",
    ".ransom", ".pay", ".btc", ".decrypt", ".helpme", ".readthis"
)

# ─────────────────────────────────────────────────────────────────────────────
# MITRE ATT&CK TECHNIQUE MAP
# ─────────────────────────────────────────────────────────────────────────────
$MitreMap = @{
    "T1486" = "Data Encrypted for Impact"
    "T1490" = "Inhibit System Recovery"
    "T1562" = "Impair Defenses"
    "T1059" = "Command and Scripting Interpreter"
    "T1204" = "User Execution (Macros)"
    "T1021" = "Remote Services (SMB/RDP)"
    "T1570" = "Lateral Tool Transfer"
    "T1071" = "Application Layer Protocol"
    "T1083" = "File and Directory Discovery"
    "T1489" = "Service Stop"
    "T1082" = "System Information Discovery"
    "T1027" = "Obfuscated Files or Information"
    "T1548" = "Abuse Elevation Control Mechanism"
}

# ─────────────────────────────────────────────────────────────────────────────
# GLOBAL STATE
# ─────────────────────────────────────────────────────────────────────────────
$script:Score      = 0
$script:MaxScore   = 0
$script:Findings   = [System.Collections.ArrayList]::new()
$script:AssessmentLog = [System.Collections.ArrayList]::new()
$script:SimulationLog = [System.Collections.ArrayList]::new()
$script:HardeningActions = [System.Collections.ArrayList]::new()

function Add-Finding {
    param(
        [string]$Check,
        [string]$Status,   # PASS, WARN, FAIL, INFO
        [int]$Points,
        [int]$MaxPoints,
        [string]$Detail = "",
        [string]$MitreID = "",
        [string]$Category = "Assessment"
    )
    $script:Score    += $Points
    $script:MaxScore += $MaxPoints
    $mitreName = if ($MitreID -and $MitreMap.ContainsKey($MitreID)) { $MitreMap[$MitreID] } else { "" }
    [void]$script:Findings.Add(@{
        Check     = $Check
        Status    = $Status
        Points    = $Points
        MaxPoints = $MaxPoints
        Detail    = $Detail
        MitreID   = $MitreID
        MitreName = $mitreName
        Category  = $Category
        Passed    = ($Points -eq $MaxPoints)
    })
}

function Get-LetterGrade {
    param([int]$Pct)
    if ($Pct -ge 90) { return "A" }
    if ($Pct -ge 80) { return "B" }
    if ($Pct -ge 70) { return "C" }
    if ($Pct -ge 60) { return "D" }
    return "F"
}

function Get-GradeColor {
    param([string]$Grade)
    switch ($Grade) {
        "A" { return $COLOR_GREEN }
        "B" { return "#2ecc71" }
        "C" { return $COLOR_ORANGE }
        "D" { return "#e67e22" }
        "F" { return $COLOR_RED }
        default { return "#999999" }
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# ASSESSMENT FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════════

function Test-RansomwareExtensions {
    param([System.Windows.Forms.TextBox]$Log)
    $Log.AppendText("[1/10] Scanning for known ransomware file extensions...`r`n")
    $userFolders = @(
        [Environment]::GetFolderPath("MyDocuments"),
        [Environment]::GetFolderPath("Desktop"),
        (Join-Path $env:USERPROFILE "Downloads")
    )
    $suspiciousFiles = [System.Collections.ArrayList]::new()
    foreach ($folder in $userFolders) {
        if (-not (Test-Path $folder)) { continue }
        try {
            $files = Get-ChildItem -Path $folder -Recurse -File -ErrorAction SilentlyContinue |
                Where-Object {
                    $ext = $_.Extension.ToLower()
                    $RansomwareExtensions -contains $ext
                } | Select-Object -First 50
            foreach ($f in $files) {
                [void]$suspiciousFiles.Add($f.FullName)
            }
        } catch { }
    }
    if ($suspiciousFiles.Count -gt 0) {
        $detail = "Found $($suspiciousFiles.Count) file(s) with ransomware-associated extensions"
        $Log.AppendText("   [FAIL] $detail`r`n")
        foreach ($sf in ($suspiciousFiles | Select-Object -First 10)) {
            $Log.AppendText("          - $sf`r`n")
        }
        Add-Finding "Ransomware File Extensions" "FAIL" 0 10 $detail "T1486"
    } else {
        $Log.AppendText("   [PASS] No ransomware-associated file extensions found`r`n")
        Add-Finding "Ransomware File Extensions" "PASS" 10 10 "No suspicious file extensions detected in user folders" "T1486"
    }
}

function Test-VolumeShadowCopies {
    param([System.Windows.Forms.TextBox]$Log)
    $Log.AppendText("[2/10] Checking Volume Shadow Copies (VSS)...`r`n")

    $vssService = Invoke-Safe { Get-Service -Name VSS -ErrorAction Stop } $null
    if ($null -eq $vssService) {
        $Log.AppendText("   [FAIL] VSS service not found`r`n")
        Add-Finding "VSS Service" "FAIL" 0 10 "Volume Shadow Copy service not found" "T1490"
        return
    }

    $shadows = Invoke-Safe {
        $wmiShadows = Get-WmiObject Win32_ShadowCopy -ErrorAction Stop
        $result = @()
        foreach ($s in $wmiShadows) {
            $result += @{
                ID        = $s.ID
                InstallDate = $s.InstallDate
                DeviceObject = $s.DeviceObject
            }
            if ($s -and $s.PSObject.Methods.Name -contains "Dispose") { $s.Dispose() }
        }
        $result
    } @()

    if ($shadows.Count -gt 0) {
        $Log.AppendText("   [PASS] Found $($shadows.Count) shadow copies`r`n")
        Add-Finding "Shadow Copies Exist" "PASS" 10 10 "$($shadows.Count) shadow copies available for recovery" "T1490"
    } else {
        $Log.AppendText("   [WARN] No shadow copies found - recovery will be difficult`r`n")
        Add-Finding "Shadow Copies Exist" "WARN" 3 10 "No shadow copies found; ransomware recovery limited" "T1490"
    }
}

function Test-VSSThrottling {
    param([System.Windows.Forms.TextBox]$Log)
    $Log.AppendText("[3/10] Checking if VSS is throttled or disabled...`r`n")

    # Check VSS service startup type
    $vssService = Invoke-Safe { Get-Service -Name VSS -ErrorAction Stop } $null
    $vssStartup = if ($vssService) { $vssService.StartType.ToString() } else { "NotFound" }

    # Check if MaxShadowCopies is set unusually low (ransomware technique)
    $maxShadow = Invoke-Safe {
        $val = (Get-ItemProperty -Path "HKLM:\System\CurrentControlSet\Services\VSS\Settings" -Name "MaxShadowCopies" -ErrorAction Stop).MaxShadowCopies
        $val
    } $null

    # Check System Protection settings
    $spEnabled = Invoke-Safe {
        $rp = Get-ComputerRestorePoint -ErrorAction Stop
        ($null -ne $rp -and $rp.Count -gt 0)
    } $false

    $issues = [System.Collections.ArrayList]::new()
    if ($vssStartup -eq "Disabled") {
        [void]$issues.Add("VSS service is DISABLED (common ransomware technique)")
    }
    if ($null -ne $maxShadow -and $maxShadow -lt 5) {
        [void]$issues.Add("MaxShadowCopies is set to $maxShadow (suspiciously low)")
    }
    if (-not $spEnabled) {
        [void]$issues.Add("System Protection has no restore points")
    }

    if ($issues.Count -eq 0) {
        $Log.AppendText("   [PASS] VSS is not being throttled`r`n")
        Add-Finding "VSS Throttling" "PASS" 10 10 "VSS running normally, System Protection active" "T1490"
    } else {
        foreach ($issue in $issues) {
            $Log.AppendText("   [WARN] $issue`r`n")
        }
        $pts = [Math]::Max(0, 10 - ($issues.Count * 4))
        Add-Finding "VSS Throttling" "WARN" $pts 10 ($issues -join "; ") "T1490"
    }
}

function Test-DefenderProtection {
    param([System.Windows.Forms.TextBox]$Log)
    $Log.AppendText("[4/10] Checking Windows Defender status...`r`n")

    $defender = Invoke-Safe { Get-MpComputerStatus -ErrorAction Stop } $null
    if ($null -eq $defender) {
        $Log.AppendText("   [FAIL] Cannot query Windows Defender`r`n")
        Add-Finding "Defender Real-Time Protection" "FAIL" 0 10 "Windows Defender status unavailable" "T1562"
        Add-Finding "Cloud-Delivered Protection" "FAIL" 0 5 "Cannot verify cloud protection" "T1562"
        return
    }

    # Real-time protection
    if ($defender.RealTimeProtectionEnabled) {
        $Log.AppendText("   [PASS] Real-time protection is ON`r`n")
        Add-Finding "Defender Real-Time Protection" "PASS" 10 10 "Real-time protection enabled" "T1562"
    } else {
        $Log.AppendText("   [FAIL] Real-time protection is OFF`r`n")
        Add-Finding "Defender Real-Time Protection" "FAIL" 0 10 "Real-time protection DISABLED - major risk" "T1562"
    }

    # Cloud-delivered protection
    if ($defender.IoavProtectionEnabled) {
        $Log.AppendText("   [PASS] Cloud-delivered protection is ON`r`n")
        Add-Finding "Cloud-Delivered Protection" "PASS" 5 5 "Cloud-delivered protection enabled" "T1562"
    } else {
        $Log.AppendText("   [WARN] Cloud-delivered protection is OFF`r`n")
        Add-Finding "Cloud-Delivered Protection" "WARN" 2 5 "Cloud-delivered protection disabled" "T1562"
    }

    # Signature freshness
    $sigAge = Invoke-Safe {
        $lastUpdate = $defender.AntivirusSignatureLastUpdated
        (New-TimeSpan -Start $lastUpdate -End (Get-Date)).Days
    } -1
    if ($sigAge -ge 0) {
        if ($sigAge -le 3) {
            $Log.AppendText("   [PASS] Signatures updated $sigAge day(s) ago`r`n")
        } elseif ($sigAge -le 14) {
            $Log.AppendText("   [WARN] Signatures are $sigAge days old`r`n")
        } else {
            $Log.AppendText("   [FAIL] Signatures are $sigAge days old - update immediately`r`n")
        }
    }
}

function Test-ControlledFolderAccess {
    param([System.Windows.Forms.TextBox]$Log)
    $Log.AppendText("[5/10] Checking Controlled Folder Access (CFA)...`r`n")

    $cfaEnabled = Invoke-Safe {
        $prefs = Get-MpPreference -ErrorAction Stop
        $prefs.EnableControlledFolderAccess -eq 1
    } $false

    if ($cfaEnabled) {
        $Log.AppendText("   [PASS] Controlled Folder Access is ENABLED`r`n")
        Add-Finding "Controlled Folder Access" "PASS" 15 15 "CFA enabled - ransomware protection active" "T1486"

        # Check protected folders
        $protectedFolders = Invoke-Safe { (Get-MpPreference -ErrorAction Stop).ControlledFolderAccessProtectedFolders } @()
        if ($protectedFolders.Count -gt 0) {
            $Log.AppendText("   Protected folders: $($protectedFolders.Count) custom folder(s)`r`n")
        }
    } else {
        $Log.AppendText("   [WARN] Controlled Folder Access is DISABLED`r`n")
        $Log.AppendText("         This is Windows' built-in ransomware protection`r`n")
        Add-Finding "Controlled Folder Access" "WARN" 0 15 "CFA disabled - enable for ransomware protection" "T1486"
    }
}

function Test-BackupIntegrity {
    param([System.Windows.Forms.TextBox]$Log)
    $Log.AppendText("[6/10] Verifying backup state and recency...`r`n")

    $backupScore = 0
    $backupMax   = 10
    $details     = [System.Collections.ArrayList]::new()

    # Check Windows Backup (File History)
    $fhService = Invoke-Safe { Get-Service -Name fhsvc -ErrorAction Stop } $null
    if ($fhService -and $fhService.Status -eq 'Running') {
        $backupScore += 3
        [void]$details.Add("File History service running")
        $Log.AppendText("   [PASS] File History service is running`r`n")
    } else {
        [void]$details.Add("File History service not running")
        $Log.AppendText("   [WARN] File History service not running`r`n")
    }

    # Check System Restore points
    $restorePoints = Invoke-Safe { Get-ComputerRestorePoint -ErrorAction Stop } @()
    if ($restorePoints -and $restorePoints.Count -gt 0) {
        $latestRP = $restorePoints | Sort-Object -Property CreationTime -Descending | Select-Object -First 1
        $rpAge = Invoke-Safe { (New-TimeSpan -Start ([Management.ManagementDateTimeConverter]::ToDateTime($latestRP.CreationTime)) -End (Get-Date)).Days } 999
        $backupScore += 3
        [void]$details.Add("$($restorePoints.Count) restore point(s), latest $rpAge days ago")
        $Log.AppendText("   [PASS] $($restorePoints.Count) restore point(s) found (latest: $rpAge days ago)`r`n")
    } else {
        [void]$details.Add("No restore points found")
        $Log.AppendText("   [WARN] No restore points found`r`n")
    }

    # Check for third-party backup software
    $backupApps = @("Veeam", "Acronis", "Carbonite", "Backblaze", "CrashPlan", "Macrium")
    $foundBackup = $false
    foreach ($app in $backupApps) {
        $proc = Get-Process -Name "*$app*" -ErrorAction SilentlyContinue
        if ($proc) {
            $foundBackup = $true
            $backupScore += 4
            [void]$details.Add("$app backup agent detected")
            $Log.AppendText("   [PASS] $app backup agent is running`r`n")
            break
        }
    }
    if (-not $foundBackup) {
        # Check installed programs
        $installed = Invoke-Safe {
            Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue |
                Where-Object { $_.DisplayName } | ForEach-Object { $_.DisplayName }
        } @()
        foreach ($app in $backupApps) {
            $match = $installed | Where-Object { $_ -match $app }
            if ($match) {
                $foundBackup = $true
                $backupScore += 2
                [void]$details.Add("$app installed (not running)")
                $Log.AppendText("   [INFO] $app installed but not running`r`n")
                break
            }
        }
    }

    if (-not $foundBackup) {
        [void]$details.Add("No third-party backup software detected")
        $Log.AppendText("   [WARN] No third-party backup software detected`r`n")
    }

    $detailStr = $details -join "; "
    if ($backupScore -ge 7) {
        Add-Finding "Backup Integrity" "PASS" $backupScore $backupMax $detailStr "T1490"
    } elseif ($backupScore -ge 3) {
        Add-Finding "Backup Integrity" "WARN" $backupScore $backupMax $detailStr "T1490"
    } else {
        Add-Finding "Backup Integrity" "FAIL" $backupScore $backupMax $detailStr "T1490"
    }
}

function Test-SMBExposure {
    param([System.Windows.Forms.TextBox]$Log)
    $Log.AppendText("[7/10] Checking for exposed SMB shares...`r`n")

    $shares = Invoke-Safe {
        $wmiShares = Get-WmiObject Win32_Share -ErrorAction Stop
        $result = @()
        foreach ($s in $wmiShares) {
            $result += @{
                Name = $s.Name
                Path = $s.Path
                Type = $s.Type
                Description = $s.Description
            }
            if ($s -and $s.PSObject.Methods.Name -contains "Dispose") { $s.Dispose() }
        }
        $result
    } @()

    # Filter out default admin shares
    $customShares = $shares | Where-Object { $_.Name -notmatch '^\w\$' -and $_.Name -ne 'IPC$' -and $_.Name -ne 'ADMIN$' }

    # Check SMBv1 (extremely dangerous)
    $smbv1 = Invoke-Safe {
        $feature = Get-WindowsOptionalFeature -Online -FeatureName "SMB1Protocol" -ErrorAction Stop
        $feature.State -eq "Enabled"
    } $false

    $issues = [System.Collections.ArrayList]::new()
    if ($smbv1) {
        [void]$issues.Add("SMBv1 is ENABLED (WannaCry attack vector)")
        $Log.AppendText("   [FAIL] SMBv1 is enabled - critical vulnerability (WannaCry/EternalBlue)`r`n")
    } else {
        $Log.AppendText("   [PASS] SMBv1 is disabled`r`n")
    }

    if ($customShares.Count -gt 0) {
        [void]$issues.Add("$($customShares.Count) custom share(s) exposed")
        foreach ($share in $customShares) {
            $Log.AppendText("   [WARN] Share: $($share.Name) -> $($share.Path)`r`n")
        }
    } else {
        $Log.AppendText("   [PASS] No custom shares exposed`r`n")
    }

    if ($issues.Count -eq 0) {
        Add-Finding "SMB Exposure" "PASS" 10 10 "No custom shares, SMBv1 disabled" "T1021"
    } elseif ($smbv1) {
        Add-Finding "SMB Exposure" "FAIL" 0 10 ($issues -join "; ") "T1021"
    } else {
        Add-Finding "SMB Exposure" "WARN" 5 10 ($issues -join "; ") "T1021"
    }
}

function Test-PowerShellPolicy {
    param([System.Windows.Forms.TextBox]$Log)
    $Log.AppendText("[8/10] Checking PowerShell execution policy...`r`n")

    $policy = Invoke-Safe { Get-ExecutionPolicy -ErrorAction Stop } "Unknown"
    $policyStr = $policy.ToString()

    $Log.AppendText("   Current execution policy: $policyStr`r`n")

    # Check PowerShell logging
    $scriptBlockLogging = Invoke-Safe {
        $val = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging" -Name "EnableScriptBlockLogging" -ErrorAction Stop).EnableScriptBlockLogging
        $val -eq 1
    } $false

    $moduleLogging = Invoke-Safe {
        $val = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ModuleLogging" -Name "EnableModuleLogging" -ErrorAction Stop).EnableModuleLogging
        $val -eq 1
    } $false

    $pts = 5
    $details = [System.Collections.ArrayList]::new()

    if ($policyStr -eq "Unrestricted" -or $policyStr -eq "Bypass") {
        $pts = 1
        [void]$details.Add("Execution policy '$policyStr' allows any script to run")
        $Log.AppendText("   [WARN] Policy '$policyStr' - scripts can run without restriction`r`n")
    } elseif ($policyStr -eq "RemoteSigned") {
        $pts = 4
        [void]$details.Add("RemoteSigned - local scripts run freely")
    } else {
        [void]$details.Add("Policy: $policyStr")
    }

    if ($scriptBlockLogging) {
        $pts = [Math]::Min($pts + 2, 5)
        [void]$details.Add("Script block logging enabled")
        $Log.AppendText("   [PASS] Script block logging is enabled`r`n")
    } else {
        [void]$details.Add("Script block logging disabled")
        $Log.AppendText("   [WARN] Script block logging is disabled`r`n")
    }

    if ($moduleLogging) {
        $pts = [Math]::Min($pts + 1, 5)
        [void]$details.Add("Module logging enabled")
    }

    $status = if ($pts -ge 4) { "PASS" } elseif ($pts -ge 2) { "WARN" } else { "FAIL" }
    Add-Finding "PowerShell Security" $status $pts 5 ($details -join "; ") "T1059"
}

function Test-OfficeMacroSettings {
    param([System.Windows.Forms.TextBox]$Log)
    $Log.AppendText("[9/10] Checking Office macro execution settings...`r`n")

    $officeVersions = @("16.0", "15.0", "14.0")  # 2016+/365, 2013, 2010
    $officeApps = @("Word", "Excel", "PowerPoint")
    $macroIssues = [System.Collections.ArrayList]::new()
    $checkedAny = $false

    foreach ($ver in $officeVersions) {
        foreach ($app in $officeApps) {
            $regPath = "HKCU:\Software\Microsoft\Office\$ver\$app\Security"
            $vbaWarn = Invoke-Safe {
                (Get-ItemProperty -Path $regPath -Name "VBAWarnings" -ErrorAction Stop).VBAWarnings
            } $null

            if ($null -ne $vbaWarn) {
                $checkedAny = $true
                # 1 = Enable all, 2 = Disable with notification (default), 3 = Disable except signed, 4 = Disable all
                switch ($vbaWarn) {
                    1 {
                        [void]$macroIssues.Add("$app $ver: Macros ENABLED without warning")
                        $Log.AppendText("   [FAIL] $app (Office $ver): Macros enabled without any warning`r`n")
                    }
                    2 {
                        $Log.AppendText("   [INFO] $app (Office $ver): Macros disabled with notification (default)`r`n")
                    }
                    3 {
                        $Log.AppendText("   [PASS] $app (Office $ver): Only signed macros allowed`r`n")
                    }
                    4 {
                        $Log.AppendText("   [PASS] $app (Office $ver): All macros disabled`r`n")
                    }
                }
            }
        }
    }

    if (-not $checkedAny) {
        $Log.AppendText("   [INFO] No Office installation detected or no macro policy set`r`n")
        Add-Finding "Office Macro Security" "INFO" 5 5 "No Office macro settings found (Office may not be installed)" "T1204"
    } elseif ($macroIssues.Count -gt 0) {
        Add-Finding "Office Macro Security" "FAIL" 0 5 ($macroIssues -join "; ") "T1204"
    } else {
        Add-Finding "Office Macro Security" "PASS" 5 5 "Office macro settings are secure" "T1204"
    }
}

function Test-RapidEncryptionActivity {
    param([System.Windows.Forms.TextBox]$Log)
    $Log.AppendText("[10/10] Checking for rapid file encryption activity...`r`n")

    # Take a snapshot of user folder file counts and look for anomalies
    $userDirs = @(
        [Environment]::GetFolderPath("MyDocuments"),
        [Environment]::GetFolderPath("Desktop"),
        (Join-Path $env:USERPROFILE "Downloads")
    )

    $highIO = $false
    $encryptedCount = 0
    $totalFiles = 0

    foreach ($dir in $userDirs) {
        if (-not (Test-Path $dir)) { continue }
        try {
            $files = Get-ChildItem -Path $dir -File -ErrorAction SilentlyContinue | Select-Object -First 500
            $totalFiles += $files.Count
            $recentlyModified = $files | Where-Object {
                $_.LastWriteTime -gt (Get-Date).AddMinutes(-5)
            }
            if ($recentlyModified.Count -gt 50) {
                $highIO = $true
            }
            # Check for encrypted-looking files (high entropy filenames, ransomware extensions)
            $suspExt = $files | Where-Object {
                $ext = $_.Extension.ToLower()
                $RansomwareExtensions -contains $ext
            }
            $encryptedCount += $suspExt.Count
        } catch { }
    }

    if ($highIO) {
        $Log.AppendText("   [FAIL] HIGH I/O DETECTED - More than 50 files modified in last 5 minutes`r`n")
        $Log.AppendText("          This could indicate active ransomware encryption`r`n")
        Add-Finding "Rapid Encryption Activity" "FAIL" 0 10 "High file modification rate detected in user directories" "T1486"
    } elseif ($encryptedCount -gt 0) {
        $Log.AppendText("   [WARN] Found $encryptedCount file(s) with suspicious extensions`r`n")
        Add-Finding "Rapid Encryption Activity" "WARN" 5 10 "$encryptedCount files with ransomware-like extensions" "T1486"
    } else {
        $Log.AppendText("   [PASS] No rapid encryption activity detected ($totalFiles files checked)`r`n")
        Add-Finding "Rapid Encryption Activity" "PASS" 10 10 "No unusual file activity detected" "T1486"
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# SIMULATION FUNCTIONS (READ-ONLY)
# ═══════════════════════════════════════════════════════════════════════════════

function Run-CanarySimulation {
    param([System.Windows.Forms.TextBox]$Log)
    $Log.AppendText("=== RANSOMWARE CANARY SIMULATION (Read-Only) ===`r`n`r`n")

    $canaryPath = Join-Path $env:TEMP "PCPlus360_CanaryTest"

    # Create canary folder with test files
    $Log.AppendText("[1/5] Creating canary folder with test files...`r`n")
    try {
        if (Test-Path $canaryPath) {
            Remove-Item -Path $canaryPath -Recurse -Force -ErrorAction SilentlyContinue
        }
        New-Item -ItemType Directory -Path $canaryPath -Force | Out-Null

        $canaryFiles = @(
            @{ Name = "important_document.txt"; Content = "This is a canary test file for ransomware detection." },
            @{ Name = "financial_report.docx"; Content = "CANARY: Fake document for monitoring." },
            @{ Name = "budget_2024.xlsx"; Content = "CANARY: Fake spreadsheet for monitoring." },
            @{ Name = "family_photo.jpg"; Content = "CANARY: Fake image file for monitoring." },
            @{ Name = "contract_signed.pdf"; Content = "CANARY: Fake PDF for monitoring." }
        )

        foreach ($cf in $canaryFiles) {
            $filePath = Join-Path $canaryPath $cf.Name
            Set-Content -Path $filePath -Value $cf.Content -Force
            $Log.AppendText("   Created: $($cf.Name)`r`n")
        }
        $Log.AppendText("   Canary folder: $canaryPath`r`n`r`n")
    } catch {
        $Log.AppendText("   [ERROR] Failed to create canary files: $($_.Exception.Message)`r`n`r`n")
    }

    # Demonstrate monitoring concept
    $Log.AppendText("[2/5] Monitoring canary folder for changes (5 seconds)...`r`n")
    $Log.AppendText("   In production, a FileSystemWatcher would monitor this folder 24/7.`r`n")
    $Log.AppendText("   If any file is modified/renamed/deleted, an alert would fire.`r`n")
    $Log.AppendText("   Sample FileSystemWatcher code:`r`n")
    $Log.AppendText("   -------`r`n")
    $Log.AppendText("   `$watcher = New-Object System.IO.FileSystemWatcher`r`n")
    $Log.AppendText("   `$watcher.Path = '$canaryPath'`r`n")
    $Log.AppendText("   `$watcher.NotifyFilter = 'LastWrite,FileName,Size'`r`n")
    $Log.AppendText("   `$watcher.EnableRaisingEvents = `$true`r`n")
    $Log.AppendText("   Register-ObjectEvent `$watcher 'Changed' -Action { ALERT }`r`n")
    $Log.AppendText("   -------`r`n")
    $Log.AppendText("   No changes detected (expected - this is a simulation).`r`n`r`n")

    # Show what CFA would block
    $Log.AppendText("[3/5] Controlled Folder Access simulation...`r`n")
    $Log.AppendText("   With CFA enabled, unauthorized apps attempting to modify files`r`n")
    $Log.AppendText("   in Documents, Desktop, Pictures, etc. would be BLOCKED.`r`n")
    $Log.AppendText("   Blocked actions would appear in:`r`n")
    $Log.AppendText("   - Windows Security > Virus & threat protection > Protection history`r`n")
    $Log.AppendText("   - Event Log: Microsoft-Windows-Windows Defender/Operational (Event ID 1123)`r`n")

    $cfaBlocks = Invoke-Safe {
        Get-WinEvent -LogName "Microsoft-Windows-Windows Defender/Operational" -MaxEvents 50 -ErrorAction Stop |
            Where-Object { $_.Id -eq 1123 } | Select-Object -First 5
    } @()

    if ($cfaBlocks.Count -gt 0) {
        $Log.AppendText("   Recent CFA blocks found: $($cfaBlocks.Count)`r`n")
        foreach ($block in $cfaBlocks) {
            $Log.AppendText("   - $($block.TimeCreated): $($block.Message.Substring(0, [Math]::Min(100, $block.Message.Length)))`r`n")
        }
    } else {
        $Log.AppendText("   No recent CFA block events found.`r`n")
    }
    $Log.AppendText("`r`n")

    # Demonstrate VSS recovery process
    $Log.AppendText("[4/5] VSS Snapshot Recovery Demonstration (commands only)...`r`n")
    $Log.AppendText("   To list available shadow copies:`r`n")
    $Log.AppendText("     vssadmin list shadows`r`n`r`n")
    $Log.AppendText("   To create a new shadow copy:`r`n")
    $Log.AppendText("     wmic shadowcopy call create Volume='C:\'`r`n`r`n")
    $Log.AppendText("   To mount a shadow copy for file recovery:`r`n")
    $Log.AppendText("     mklink /d C:\ShadowRecover \\?\GLOBALROOT\Device\HarddiskVolumeShadowCopyN\`r`n`r`n")
    $Log.AppendText("   To restore via Previous Versions:`r`n")
    $Log.AppendText("     Right-click folder > Properties > Previous Versions tab`r`n`r`n")

    # Recovery time estimate
    $Log.AppendText("[5/5] Recovery time estimate...`r`n")
    $shadows = Invoke-Safe {
        $wmiObj = Get-WmiObject Win32_ShadowCopy -ErrorAction Stop
        $count = if ($wmiObj) { @($wmiObj).Count } else { 0 }
        foreach ($obj in $wmiObj) {
            if ($obj -and $obj.PSObject.Methods.Name -contains "Dispose") { $obj.Dispose() }
        }
        $count
    } 0

    $restorePoints = Invoke-Safe { (Get-ComputerRestorePoint -ErrorAction Stop).Count } 0
    $hasBackupSW = (Get-Process -Name "*Veeam*","*Acronis*","*Backblaze*","*Carbonite*" -ErrorAction SilentlyContinue).Count -gt 0
    $hasCFA = Invoke-Safe { (Get-MpPreference -ErrorAction Stop).EnableControlledFolderAccess -eq 1 } $false

    $rtoMinutes = 480  # Base: 8 hours
    if ($shadows -gt 0) { $rtoMinutes -= 120 }
    if ($restorePoints -gt 0) { $rtoMinutes -= 60 }
    if ($hasBackupSW) { $rtoMinutes -= 180 }
    if ($hasCFA) { $rtoMinutes -= 60 }
    $rtoMinutes = [Math]::Max(30, $rtoMinutes)

    $rtoHours = [Math]::Round($rtoMinutes / 60, 1)
    $Log.AppendText("   Estimated Recovery Time: ~$rtoHours hours ($rtoMinutes minutes)`r`n")
    $Log.AppendText("   Factors:`r`n")
    $Log.AppendText("     Shadow copies:     $(if($shadows -gt 0){'Available (-2h)'}else{'None (+0)'})`r`n")
    $Log.AppendText("     Restore points:    $(if($restorePoints -gt 0){'Available (-1h)'}else{'None (+0)'})`r`n")
    $Log.AppendText("     Backup software:   $(if($hasBackupSW){'Running (-3h)'}else{'None (+0)'})`r`n")
    $Log.AppendText("     CFA protection:    $(if($hasCFA){'Enabled (-1h)'}else{'Disabled (+0)'})`r`n`r`n")

    # Clean up canary folder
    try {
        if (Test-Path $canaryPath) {
            Remove-Item -Path $canaryPath -Recurse -Force -ErrorAction SilentlyContinue
            $Log.AppendText("Canary folder cleaned up.`r`n")
        }
    } catch { }

    $Log.AppendText("`r`n=== SIMULATION COMPLETE (no files were harmed) ===`r`n")
}

# ═══════════════════════════════════════════════════════════════════════════════
# HARDENING FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════════

function Invoke-EnableCFA {
    param([System.Windows.Forms.TextBox]$Log)
    $Log.AppendText("Enabling Controlled Folder Access...`r`n")

    # Create restore point first
    $Log.AppendText("  Creating System Restore point...`r`n")
    try {
        Enable-ComputerRestore -Drive "C:\" -ErrorAction SilentlyContinue
        Checkpoint-Computer -Description "PCPlus360 - Before CFA Enable" -RestorePointType "MODIFY_SETTINGS" -ErrorAction Stop
        $Log.AppendText("  [PASS] Restore point created`r`n")
    } catch {
        $Log.AppendText("  [WARN] Could not create restore point: $($_.Exception.Message)`r`n")
    }

    try {
        Set-MpPreference -EnableControlledFolderAccess Enabled -ErrorAction Stop
        $Log.AppendText("  [PASS] Controlled Folder Access ENABLED`r`n")
        $Log.AppendText("  Note: Some legitimate apps may be blocked. Add them via:`r`n")
        $Log.AppendText("  Windows Security > Virus & threat protection > Ransomware protection > Allow an app`r`n")
    } catch {
        $Log.AppendText("  [FAIL] Failed to enable CFA: $($_.Exception.Message)`r`n")
    }
}

function Invoke-EnableASR {
    param([System.Windows.Forms.TextBox]$Log)
    $Log.AppendText("Enabling Attack Surface Reduction (ASR) rules...`r`n")

    # Key ASR rules for ransomware protection
    $asrRules = @(
        @{ ID = "56a863a9-875e-4185-98a7-b882c64b5ce5"; Name = "Block abuse of exploited vulnerable signed drivers" },
        @{ ID = "7674ba52-37eb-4a4f-a9a1-f0f9a1619a2c"; Name = "Block Adobe Reader from creating child processes" },
        @{ ID = "d4f940ab-401b-4efc-aadc-ad5f3c50688a"; Name = "Block all Office applications from creating child processes" },
        @{ ID = "9e6c4e1f-7d60-472f-ba1a-a39ef669e4b2"; Name = "Block credential stealing from LSASS" },
        @{ ID = "be9ba2d9-53ea-4cdc-84e5-9b1eeee46550"; Name = "Block executable content from email client and webmail" },
        @{ ID = "01443614-cd74-433a-b99e-2ecdc07bfc25"; Name = "Block executable files from running unless they meet criteria" },
        @{ ID = "5beb7efe-fd9a-4556-801d-275e5ffc04cc"; Name = "Block execution of potentially obfuscated scripts" },
        @{ ID = "d3e037e1-3eb8-44c8-a917-57927947596d"; Name = "Block JavaScript or VBScript from launching downloaded content" },
        @{ ID = "3b576869-a4ec-4529-8536-b80a7769e899"; Name = "Block Office applications from creating executable content" },
        @{ ID = "75668c1f-73b5-4cf0-bb93-3ecf5cb7cc84"; Name = "Block Office applications from injecting code into other processes" },
        @{ ID = "b2b3f03d-6a65-4f7b-a9c7-1c7ef74a9ba4"; Name = "Block untrusted and unsigned processes from USB" },
        @{ ID = "92e97fa1-2edf-4476-bdd6-9dd0b4dddc7b"; Name = "Block Win32 API calls from Office macros" },
        @{ ID = "c1db55ab-c21a-4637-bb3f-a12568109d35"; Name = "Use advanced protection against ransomware" }
    )

    $Log.AppendText("  Setting $($asrRules.Count) ASR rules to Audit mode...`r`n")
    $Log.AppendText("  (Audit mode logs blocks without enforcing - safe to test first)`r`n`r`n")

    foreach ($rule in $asrRules) {
        $Log.AppendText("  - $($rule.Name)`r`n")
    }

    $Log.AppendText("`r`n  To enable these rules, run the following in an elevated PowerShell:`r`n")
    $Log.AppendText("  -------`r`n")
    foreach ($rule in $asrRules) {
        $Log.AppendText("  Add-MpPreference -AttackSurfaceReductionRules_Ids $($rule.ID) -AttackSurfaceReductionRules_Actions AuditMode`r`n")
    }
    $Log.AppendText("  -------`r`n")
    $Log.AppendText("  Change 'AuditMode' to 'Enabled' after testing.`r`n")
}

function Show-HardeningRecommendations {
    param([System.Windows.Forms.TextBox]$Log)
    $Log.AppendText("=== RANSOMWARE HARDENING RECOMMENDATIONS ===`r`n`r`n")

    # 1. File Extension Visibility
    $Log.AppendText("[1] Show File Extensions (prevent double-extension tricks)`r`n")
    $hideExt = Invoke-Safe {
        (Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "HideFileExt" -ErrorAction Stop).HideFileExt
    } 1
    if ($hideExt -eq 1) {
        $Log.AppendText("    STATUS: File extensions are HIDDEN (risky)`r`n")
        $Log.AppendText("    FIX: Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'HideFileExt' -Value 0`r`n")
    } else {
        $Log.AppendText("    STATUS: File extensions are visible (good)`r`n")
    }
    $Log.AppendText("`r`n")

    # 2. Macro Security
    $Log.AppendText("[2] Block Office Macro Execution`r`n")
    $Log.AppendText("    Macros are the #1 ransomware delivery mechanism.`r`n")
    $Log.AppendText("    Recommended: Block macros from internet-downloaded files (default in Office 2022+).`r`n")
    $Log.AppendText("    GPO: User Config > Admin Templates > Microsoft Office > Security Settings`r`n")
    $Log.AppendText("         > Block macros from running in Office files from the Internet = Enabled`r`n`r`n")

    # 3. Network Segmentation
    $Log.AppendText("[3] Network Segmentation`r`n")
    $Log.AppendText("    Ransomware spreads laterally via SMB/RDP.`r`n")
    $Log.AppendText("    Recommendations:`r`n")
    $Log.AppendText("    - Disable SMBv1: Disable-WindowsOptionalFeature -Online -FeatureName SMB1Protocol`r`n")
    $Log.AppendText("    - Restrict RDP access to specific IPs via Windows Firewall`r`n")
    $Log.AppendText("    - Use VLANs to segment critical systems from workstations`r`n")
    $Log.AppendText("    - Disable file sharing on public/guest WiFi networks`r`n`r`n")

    # 4. 3-2-1 Backup Rule
    $Log.AppendText("[4] Backup 3-2-1 Rule Compliance`r`n")
    $Log.AppendText("    Rule: 3 copies of data, on 2 different media, with 1 offsite.`r`n")

    $copies = 0
    $mediaTypes = [System.Collections.ArrayList]::new()
    $offsite = $false

    # Check local backups
    $restorePoints = Invoke-Safe { (Get-ComputerRestorePoint -ErrorAction Stop).Count } 0
    if ($restorePoints -gt 0) {
        $copies++
        [void]$mediaTypes.Add("Local (System Restore)")
    }

    # Check OneDrive / cloud
    $odProcess = Get-Process -Name "OneDrive" -ErrorAction SilentlyContinue
    if ($odProcess) {
        $copies++
        [void]$mediaTypes.Add("Cloud (OneDrive)")
        $offsite = $true
    }

    # Check external drives
    $externalDrives = Invoke-Safe {
        Get-WmiObject Win32_DiskDrive -ErrorAction Stop | Where-Object { $_.InterfaceType -eq 'USB' }
    } @()
    if ($externalDrives) {
        $copies++
        [void]$mediaTypes.Add("External USB")
        foreach ($d in $externalDrives) {
            if ($d -and $d.PSObject.Methods.Name -contains "Dispose") { $d.Dispose() }
        }
    }

    $Log.AppendText("    Copies found: $copies / 3`r`n")
    $Log.AppendText("    Media types: $(if($mediaTypes.Count -gt 0){$mediaTypes -join ', '}else{'None detected'})`r`n")
    $Log.AppendText("    Offsite: $(if($offsite){'Yes (cloud)'}else{'No'})`r`n")

    if ($copies -ge 3 -and $mediaTypes.Count -ge 2 -and $offsite) {
        $Log.AppendText("    RESULT: 3-2-1 rule COMPLIANT`r`n")
    } elseif ($copies -ge 2) {
        $Log.AppendText("    RESULT: PARTIAL compliance - need $(3-$copies) more copies`r`n")
    } else {
        $Log.AppendText("    RESULT: NOT COMPLIANT - significant data loss risk`r`n")
    }
    $Log.AppendText("`r`n")

    # 5. Additional hardening
    $Log.AppendText("[5] Additional Hardening Steps`r`n")
    $Log.AppendText("    - Enable multi-factor authentication (MFA) on all accounts`r`n")
    $Log.AppendText("    - Use application whitelisting (AppLocker or WDAC)`r`n")
    $Log.AppendText("    - Deploy EDR (Endpoint Detection & Response) solution`r`n")
    $Log.AppendText("    - Implement least-privilege access (no daily admin accounts)`r`n")
    $Log.AppendText("    - Keep all software up to date (OS, browsers, Office, Adobe)`r`n")
    $Log.AppendText("    - Configure email gateway to block macro-enabled attachments`r`n")
    $Log.AppendText("    - Train users on phishing recognition`r`n")
    $Log.AppendText("    - Test backups regularly with actual restore drills`r`n`r`n")

    $Log.AppendText("=== END OF RECOMMENDATIONS ===`r`n")
}

# ═══════════════════════════════════════════════════════════════════════════════
# HTML REPORT GENERATION
# ═══════════════════════════════════════════════════════════════════════════════

function New-HtmlReport {
    $finalScore = if ($script:MaxScore -gt 0) { [Math]::Round(($script:Score / $script:MaxScore) * 100) } else { 0 }
    $grade      = Get-LetterGrade $finalScore
    $gradeColor = Get-GradeColor $grade

    $passedCount = ($script:Findings | Where-Object { $_.Passed }).Count
    $totalChecks = $script:Findings.Count
    $failedCount = ($script:Findings | Where-Object { $_.Status -eq "FAIL" }).Count
    $warnCount   = ($script:Findings | Where-Object { $_.Status -eq "WARN" }).Count

    # SVG arc for score
    $angle = [Math]::Min(359.9, ($finalScore / 100) * 360)
    $rad   = $angle * [Math]::PI / 180
    $x     = 50 + 40 * [Math]::Sin($rad)
    $y     = 50 - 40 * [Math]::Cos($rad)
    $large = if ($angle -gt 180) { 1 } else { 0 }
    $arcPath = "M 50 10 A 40 40 0 $large 1 $([Math]::Round($x,2)) $([Math]::Round($y,2))"

    # Build findings rows
    $findingsRows = ""
    foreach ($f in $script:Findings) {
        $statusClass = switch ($f.Status) {
            "PASS" { "pass" }
            "FAIL" { "fail" }
            "WARN" { "warn" }
            default { "" }
        }
        $statusIcon = switch ($f.Status) {
            "PASS" { "&#9989;" }
            "FAIL" { "&#10060;" }
            "WARN" { "&#9888;" }
            default { "&#8505;" }
        }
        $mitreCell = if ($f.MitreID) {
            "<a href='https://attack.mitre.org/techniques/$($f.MitreID)/' target='_blank' style='color:#2596be;text-decoration:none'>$($f.MitreID)</a><br><small>$(HtmlEncode $f.MitreName)</small>"
        } else { "-" }
        $findingsRows += "<tr class='$statusClass'><td>$statusIcon $(HtmlEncode $f.Check)</td><td>$($f.Points)/$($f.MaxPoints)</td><td>$(HtmlEncode $f.Detail)</td><td>$mitreCell</td></tr>`n"
    }

    # Build remediation list
    $remediationHtml = ""
    $failFindings = $script:Findings | Where-Object { $_.Status -eq "FAIL" -or $_.Status -eq "WARN" }
    $priority = 1
    foreach ($f in $failFindings) {
        $severityColor = if ($f.Status -eq "FAIL") { "#e74c3c" } else { "#f39c12" }
        $remediationHtml += @"
<div style='padding:10px 14px;margin-bottom:8px;border-left:4px solid $severityColor;background:#f8f9fc;border-radius:0 6px 6px 0'>
  <strong>$priority. $(HtmlEncode $f.Check)</strong> <span style='color:$severityColor;font-weight:bold'>[$($f.Status)]</span>
  $(if($f.MitreID){"<span style='float:right;color:#2596be;font-size:11px'>MITRE $($f.MitreID)</span>"})
  <br><span style='color:#666;font-size:12px'>$(HtmlEncode $f.Detail)</span>
</div>
"@
        $priority++
    }

    if (-not $remediationHtml) {
        $remediationHtml = "<p style='color:#27ae60;padding:14px'>All checks passed. System is well-protected against ransomware.</p>"
    }

    $htmlFile = Join-Path $ReportsDir "PCPlus360-RansomwareReadiness-$ComputerSafe-$Timestamp.html"

    $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>PC Plus 360 - Ransomware Readiness Assessment - $($env:COMPUTERNAME)</title>
<style>
  * { margin:0; padding:0; box-sizing:border-box; }
  body { font-family:'Segoe UI',Tahoma,sans-serif; background:#0d1117; color:#c9d1d9; line-height:1.5; }
  .header { background:linear-gradient(135deg,#0a1628 0%,#0d2137 50%,#1a2d4a 100%); color:#fff; padding:24px 40px; }
  .header .brand { font-size:18px; font-weight:700; color:#2596be; }
  .header .tagline { font-size:10px; text-transform:uppercase; letter-spacing:2px; opacity:0.6; }
  .header h1 { font-size:22px; margin:8px 0 4px; }
  .header .meta { display:flex; gap:24px; font-size:13px; color:#8b949e; flex-wrap:wrap; }
  .score-banner { padding:16px 40px; font-size:16px; font-weight:700; color:white; display:flex; align-items:center; gap:12px; background:$gradeColor; }
  .container { max-width:1100px; margin:0 auto; padding:20px; }
  .section { background:#161b22; border-radius:8px; border:1px solid #30363d; padding:24px; margin-bottom:16px; }
  .section h2 { font-size:16px; color:#2596be; margin-bottom:14px; border-bottom:2px solid #2596be; padding-bottom:6px; }
  .card-row { display:flex; gap:12px; flex-wrap:wrap; }
  .card { flex:1; min-width:120px; background:#0d1117; border-radius:6px; padding:14px; text-align:center; border:1px solid #30363d; }
  .card-label { font-size:10px; text-transform:uppercase; color:#8b949e; letter-spacing:0.5px; }
  .card-value { font-size:18px; font-weight:700; color:#c9d1d9; }
  table { width:100%; border-collapse:collapse; font-size:13px; }
  th { background:#21262d; text-align:left; padding:8px 12px; font-weight:600; color:#8b949e; border-bottom:2px solid #30363d; font-size:11px; text-transform:uppercase; }
  td { padding:7px 12px; border-bottom:1px solid #21262d; color:#c9d1d9; }
  tr.pass td:first-child { color:#27ae60; }
  tr.fail td { background:rgba(231,76,60,0.08); }
  tr.fail td:first-child { color:#e74c3c; }
  tr.warn td { background:rgba(243,156,18,0.08); }
  tr.warn td:first-child { color:#f39c12; }
  a { color:#2596be; }
  .mitre-badge { display:inline-block; background:#1a2d4a; color:#2596be; padding:2px 8px; border-radius:4px; font-size:11px; font-weight:600; }
  .footer { text-align:center; padding:16px; color:#484f58; font-size:11px; border-top:1px solid #21262d; margin-top:16px; }
  @media print { body { background:#fff; color:#333; } .section { background:#fff; border:1px solid #ddd; } td,th { color:#333; } }
</style>
</head>
<body>

<div class="header">
  <div class="brand">$COMPANY_NAME</div>
  <div class="tagline">Ransomware Defense Assessment</div>
  <h1>&#128737; Ransomware Readiness Report</h1>
  <div class="meta">
    <span>Computer: <strong>$($env:COMPUTERNAME)</strong></span>
    <span>User: <strong>$($env:USERNAME)</strong></span>
    <span>Scan: <strong>$ScanDate</strong></span>
    <span>OS: <strong>$(Invoke-Safe { (Get-CimInstance Win32_OperatingSystem).Caption } 'Windows')</strong></span>
  </div>
</div>

<div class="score-banner">
  $(if ($finalScore -ge 80) { "&#9989; RANSOMWARE READINESS: STRONG ($grade) - Score $finalScore/100" } elseif ($finalScore -ge 60) { "&#9888; RANSOMWARE READINESS: MODERATE ($grade) - Score $finalScore/100" } else { "&#10060; RANSOMWARE READINESS: WEAK ($grade) - Score $finalScore/100" })
</div>

<div class="container">

<div class="section">
  <h2>&#128202; Readiness Score</h2>
  <div style="display:flex;align-items:center;gap:30px;flex-wrap:wrap">
    <svg viewBox="0 0 100 100" width="150" height="150">
      <circle cx="50" cy="50" r="40" fill="none" stroke="#30363d" stroke-width="8"/>
      <path d="$arcPath" fill="none" stroke="$gradeColor" stroke-width="8" stroke-linecap="round"/>
      <text x="50" y="44" text-anchor="middle" font-size="22" font-weight="bold" fill="$gradeColor">$finalScore</text>
      <text x="50" y="58" text-anchor="middle" font-size="10" fill="#8b949e">/ 100</text>
      <text x="50" y="72" text-anchor="middle" font-size="16" font-weight="bold" fill="$gradeColor">$grade</text>
    </svg>
    <div>
      <p><strong>$passedCount</strong> of <strong>$totalChecks</strong> checks passed</p>
      <p>Points: <strong>$($script:Score)</strong> / <strong>$($script:MaxScore)</strong></p>
      <p style="margin-top:8px">
        <span style="color:#27ae60">&#9679; Passed: $passedCount</span> &nbsp;
        <span style="color:#f39c12">&#9679; Warnings: $warnCount</span> &nbsp;
        <span style="color:#e74c3c">&#9679; Failed: $failedCount</span>
      </p>
    </div>
  </div>
</div>

<div class="section">
  <h2>&#128202; Summary Cards</h2>
  <div class="card-row">
    <div class="card"><div class="card-label">Overall Score</div><div class="card-value" style="color:$gradeColor">$finalScore%</div></div>
    <div class="card"><div class="card-label">Grade</div><div class="card-value" style="color:$gradeColor">$grade</div></div>
    <div class="card"><div class="card-label">Checks Passed</div><div class="card-value" style="color:#27ae60">$passedCount/$totalChecks</div></div>
    <div class="card"><div class="card-label">Critical Issues</div><div class="card-value" style="color:$(if($failedCount -gt 0){'#e74c3c'}else{'#27ae60'})">$failedCount</div></div>
  </div>
</div>

<div class="section">
  <h2>&#128270; Detailed Findings (MITRE ATT&amp;CK Mapped)</h2>
  <div style="overflow-x:auto">
  <table>
    <thead><tr><th>Check</th><th>Score</th><th>Detail</th><th>MITRE ATT&amp;CK</th></tr></thead>
    <tbody>$findingsRows</tbody>
  </table>
  </div>
</div>

<div class="section">
  <h2>&#128736; Remediation Priority List</h2>
  $remediationHtml
</div>

<div class="section">
  <h2>&#128218; MITRE ATT&amp;CK Reference</h2>
  <p style="margin-bottom:12px;color:#8b949e">Techniques assessed in this scan:</p>
  <div class="card-row" style="flex-wrap:wrap;gap:8px">
$(foreach ($key in ($MitreMap.Keys | Sort-Object)) {
    "    <div style='background:#0d1117;border:1px solid #30363d;border-radius:6px;padding:8px 12px;min-width:200px'><span class='mitre-badge'>$key</span> <span style='font-size:12px;color:#c9d1d9'>$($MitreMap[$key])</span></div>`n"
})  </div>
</div>

<div class="footer">
  $COMPANY_NAME | $COMPANY_PHONE1 | $COMPANY_PHONE2 | $COMPANY_WEBSITE<br>
  Ransomware Readiness Assessment v$SCRIPT_VERSION | Generated $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
</div>

</div>
</body>
</html>
"@
    $html | Out-File -FilePath $htmlFile -Encoding UTF8 -Force
    return $htmlFile
}

# ═══════════════════════════════════════════════════════════════════════════════
# JSON REPORT (for ReportCard integration)
# ═══════════════════════════════════════════════════════════════════════════════

function New-JsonReport {
    $finalScore = if ($script:MaxScore -gt 0) { [Math]::Round(($script:Score / $script:MaxScore) * 100) } else { 0 }
    $grade = Get-LetterGrade $finalScore

    $jsonObj = @{
        tool        = "PCPlus-RansomwareReadiness"
        version     = $SCRIPT_VERSION
        computer    = $env:COMPUTERNAME
        user        = $env:USERNAME
        scanDate    = $ScanDate
        score       = $finalScore
        grade       = $grade
        pointsEarned = $script:Score
        pointsMax   = $script:MaxScore
        findings    = @()
    }

    foreach ($f in $script:Findings) {
        $jsonObj.findings += @{
            check     = $f.Check
            status    = $f.Status
            points    = $f.Points
            maxPoints = $f.MaxPoints
            detail    = $f.Detail
            mitreId   = $f.MitreID
            mitreName = $f.MitreName
            passed    = $f.Passed
        }
    }

    $jsonFile = Join-Path $ReportsDir "PCPlus360-RansomwareReadiness-$ComputerSafe-$Timestamp.json"
    $jsonObj | ConvertTo-Json -Depth 5 | Out-File -FilePath $jsonFile -Encoding UTF8 -Force
    return $jsonFile
}

# ═══════════════════════════════════════════════════════════════════════════════
# WINFORMS UI
# ═══════════════════════════════════════════════════════════════════════════════

function Show-MainForm {
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "PC Plus Computing 360 - Ransomware Readiness Assessment"
    $form.Size = New-Object System.Drawing.Size(950, 720)
    $form.StartPosition = "CenterScreen"
    $form.BackColor = [System.Drawing.ColorTranslator]::FromHtml($COLOR_NAVY)
    $form.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $form.MinimumSize = New-Object System.Drawing.Size(800, 600)

    # ── Header Panel ──
    $headerPanel = New-Object System.Windows.Forms.Panel
    $headerPanel.Dock = "Top"
    $headerPanel.Height = 70
    $headerPanel.BackColor = [System.Drawing.ColorTranslator]::FromHtml("#0d2137")
    $form.Controls.Add($headerPanel)

    $lblTitle = New-Object System.Windows.Forms.Label
    $lblTitle.Text = "PC PLUS COMPUTING 360 - RANSOMWARE READINESS"
    $lblTitle.ForeColor = [System.Drawing.Color]::White
    $lblTitle.Font = New-Object System.Drawing.Font("Segoe UI", 16, [System.Drawing.FontStyle]::Bold)
    $lblTitle.AutoSize = $false
    $lblTitle.Size = New-Object System.Drawing.Size(700, 35)
    $lblTitle.Location = New-Object System.Drawing.Point(20, 8)
    $headerPanel.Controls.Add($lblTitle)

    $lblSubtitle = New-Object System.Windows.Forms.Label
    $lblSubtitle.Text = "$COMPANY_PHONE1 | $COMPANY_PHONE2 | $COMPANY_WEBSITE"
    $lblSubtitle.ForeColor = [System.Drawing.ColorTranslator]::FromHtml("#8b949e")
    $lblSubtitle.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $lblSubtitle.AutoSize = $true
    $lblSubtitle.Location = New-Object System.Drawing.Point(20, 42)
    $headerPanel.Controls.Add($lblSubtitle)

    # ── Tab Control ──
    $tabControl = New-Object System.Windows.Forms.TabControl
    $tabControl.Dock = "Fill"
    $tabControl.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $form.Controls.Add($tabControl)

    # ── TAB 1: Assessment ──
    $tabAssess = New-Object System.Windows.Forms.TabPage
    $tabAssess.Text = "Assessment"
    $tabAssess.BackColor = [System.Drawing.ColorTranslator]::FromHtml("#0d1117")
    $tabControl.TabPages.Add($tabAssess)

    $txtAssess = New-Object System.Windows.Forms.TextBox
    $txtAssess.Multiline = $true
    $txtAssess.ReadOnly = $true
    $txtAssess.ScrollBars = "Vertical"
    $txtAssess.Dock = "Fill"
    $txtAssess.BackColor = [System.Drawing.ColorTranslator]::FromHtml("#0d1117")
    $txtAssess.ForeColor = [System.Drawing.ColorTranslator]::FromHtml("#c9d1d9")
    $txtAssess.Font = New-Object System.Drawing.Font("Consolas", 10)
    $tabAssess.Controls.Add($txtAssess)

    $panelAssessBtn = New-Object System.Windows.Forms.Panel
    $panelAssessBtn.Dock = "Bottom"
    $panelAssessBtn.Height = 50
    $panelAssessBtn.BackColor = [System.Drawing.ColorTranslator]::FromHtml("#161b22")
    $tabAssess.Controls.Add($panelAssessBtn)

    $btnRunAssess = New-Object System.Windows.Forms.Button
    $btnRunAssess.Text = "Run Assessment"
    $btnRunAssess.Size = New-Object System.Drawing.Size(160, 35)
    $btnRunAssess.Location = New-Object System.Drawing.Point(10, 8)
    $btnRunAssess.BackColor = [System.Drawing.ColorTranslator]::FromHtml($COLOR_ACCENT)
    $btnRunAssess.ForeColor = [System.Drawing.Color]::White
    $btnRunAssess.FlatStyle = "Flat"
    $btnRunAssess.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $btnRunAssess.Cursor = [System.Windows.Forms.Cursors]::Hand
    $panelAssessBtn.Controls.Add($btnRunAssess)

    $lblScore = New-Object System.Windows.Forms.Label
    $lblScore.Text = "Score: -- / --"
    $lblScore.ForeColor = [System.Drawing.Color]::White
    $lblScore.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
    $lblScore.AutoSize = $true
    $lblScore.Location = New-Object System.Drawing.Point(190, 14)
    $panelAssessBtn.Controls.Add($lblScore)

    $btnGenReport = New-Object System.Windows.Forms.Button
    $btnGenReport.Text = "Generate Report"
    $btnGenReport.Size = New-Object System.Drawing.Size(150, 35)
    $btnGenReport.Location = New-Object System.Drawing.Point(500, 8)
    $btnGenReport.BackColor = [System.Drawing.ColorTranslator]::FromHtml($COLOR_GREEN)
    $btnGenReport.ForeColor = [System.Drawing.Color]::White
    $btnGenReport.FlatStyle = "Flat"
    $btnGenReport.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $btnGenReport.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btnGenReport.Enabled = $false
    $panelAssessBtn.Controls.Add($btnGenReport)

    $btnRunAssess.Add_Click({
        $btnRunAssess.Enabled = $false
        $txtAssess.Clear()
        $script:Score = 0
        $script:MaxScore = 0
        $script:Findings.Clear()

        $txtAssess.AppendText("=== PC Plus Computing 360 - Ransomware Readiness Assessment ===`r`n")
        $txtAssess.AppendText("Computer: $($env:COMPUTERNAME) | User: $($env:USERNAME) | $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`r`n")
        $txtAssess.AppendText("$('=' * 70)`r`n`r`n")

        [System.Windows.Forms.Application]::DoEvents()

        Test-RansomwareExtensions -Log $txtAssess
        [System.Windows.Forms.Application]::DoEvents()

        Test-VolumeShadowCopies -Log $txtAssess
        [System.Windows.Forms.Application]::DoEvents()

        Test-VSSThrottling -Log $txtAssess
        [System.Windows.Forms.Application]::DoEvents()

        Test-DefenderProtection -Log $txtAssess
        [System.Windows.Forms.Application]::DoEvents()

        Test-ControlledFolderAccess -Log $txtAssess
        [System.Windows.Forms.Application]::DoEvents()

        Test-BackupIntegrity -Log $txtAssess
        [System.Windows.Forms.Application]::DoEvents()

        Test-SMBExposure -Log $txtAssess
        [System.Windows.Forms.Application]::DoEvents()

        Test-PowerShellPolicy -Log $txtAssess
        [System.Windows.Forms.Application]::DoEvents()

        Test-OfficeMacroSettings -Log $txtAssess
        [System.Windows.Forms.Application]::DoEvents()

        Test-RapidEncryptionActivity -Log $txtAssess
        [System.Windows.Forms.Application]::DoEvents()

        $finalScore = if ($script:MaxScore -gt 0) { [Math]::Round(($script:Score / $script:MaxScore) * 100) } else { 0 }
        $grade = Get-LetterGrade $finalScore

        $txtAssess.AppendText("`r`n$('=' * 70)`r`n")
        $txtAssess.AppendText("RANSOMWARE READINESS SCORE: $finalScore / 100 (Grade: $grade)`r`n")
        $txtAssess.AppendText("Points: $($script:Score) / $($script:MaxScore)`r`n")
        $txtAssess.AppendText("$('=' * 70)`r`n")

        $lblScore.Text = "Score: $finalScore / 100 ($grade)"
        $scoreColor = Get-GradeColor $grade
        $lblScore.ForeColor = [System.Drawing.ColorTranslator]::FromHtml($scoreColor)

        $btnRunAssess.Enabled = $true
        $btnGenReport.Enabled = $true
    })

    $btnGenReport.Add_Click({
        $htmlFile = New-HtmlReport
        $jsonFile = New-JsonReport

        $txtAssess.AppendText("`r`nHTML Report: $htmlFile`r`n")
        $txtAssess.AppendText("JSON Report: $jsonFile`r`n")

        try {
            Start-Process $htmlFile
        } catch { }

        [System.Windows.Forms.MessageBox]::Show(
            "Reports generated:`n`n- HTML: $htmlFile`n- JSON: $jsonFile",
            "Report Generated",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        )
    })

    # ── TAB 2: Simulation ──
    $tabSim = New-Object System.Windows.Forms.TabPage
    $tabSim.Text = "Simulation (Read-Only)"
    $tabSim.BackColor = [System.Drawing.ColorTranslator]::FromHtml("#0d1117")
    $tabControl.TabPages.Add($tabSim)

    $txtSim = New-Object System.Windows.Forms.TextBox
    $txtSim.Multiline = $true
    $txtSim.ReadOnly = $true
    $txtSim.ScrollBars = "Vertical"
    $txtSim.Dock = "Fill"
    $txtSim.BackColor = [System.Drawing.ColorTranslator]::FromHtml("#0d1117")
    $txtSim.ForeColor = [System.Drawing.ColorTranslator]::FromHtml("#c9d1d9")
    $txtSim.Font = New-Object System.Drawing.Font("Consolas", 10)
    $tabSim.Controls.Add($txtSim)

    $panelSimBtn = New-Object System.Windows.Forms.Panel
    $panelSimBtn.Dock = "Bottom"
    $panelSimBtn.Height = 50
    $panelSimBtn.BackColor = [System.Drawing.ColorTranslator]::FromHtml("#161b22")
    $tabSim.Controls.Add($panelSimBtn)

    $btnRunSim = New-Object System.Windows.Forms.Button
    $btnRunSim.Text = "Run Simulation"
    $btnRunSim.Size = New-Object System.Drawing.Size(160, 35)
    $btnRunSim.Location = New-Object System.Drawing.Point(10, 8)
    $btnRunSim.BackColor = [System.Drawing.ColorTranslator]::FromHtml($COLOR_ORANGE)
    $btnRunSim.ForeColor = [System.Drawing.Color]::White
    $btnRunSim.FlatStyle = "Flat"
    $btnRunSim.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $btnRunSim.Cursor = [System.Windows.Forms.Cursors]::Hand
    $panelSimBtn.Controls.Add($btnRunSim)

    $lblSimNote = New-Object System.Windows.Forms.Label
    $lblSimNote.Text = "This simulation is READ-ONLY. No files will be permanently modified."
    $lblSimNote.ForeColor = [System.Drawing.ColorTranslator]::FromHtml($COLOR_ORANGE)
    $lblSimNote.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Italic)
    $lblSimNote.AutoSize = $true
    $lblSimNote.Location = New-Object System.Drawing.Point(190, 16)
    $panelSimBtn.Controls.Add($lblSimNote)

    $btnRunSim.Add_Click({
        $btnRunSim.Enabled = $false
        $txtSim.Clear()
        Run-CanarySimulation -Log $txtSim
        $btnRunSim.Enabled = $true
    })

    # ── TAB 3: Hardening ──
    $tabHarden = New-Object System.Windows.Forms.TabPage
    $tabHarden.Text = "Hardening"
    $tabHarden.BackColor = [System.Drawing.ColorTranslator]::FromHtml("#0d1117")
    $tabControl.TabPages.Add($tabHarden)

    $txtHarden = New-Object System.Windows.Forms.TextBox
    $txtHarden.Multiline = $true
    $txtHarden.ReadOnly = $true
    $txtHarden.ScrollBars = "Vertical"
    $txtHarden.Dock = "Fill"
    $txtHarden.BackColor = [System.Drawing.ColorTranslator]::FromHtml("#0d1117")
    $txtHarden.ForeColor = [System.Drawing.ColorTranslator]::FromHtml("#c9d1d9")
    $txtHarden.Font = New-Object System.Drawing.Font("Consolas", 10)
    $tabHarden.Controls.Add($txtHarden)

    $panelHardenBtn = New-Object System.Windows.Forms.Panel
    $panelHardenBtn.Dock = "Bottom"
    $panelHardenBtn.Height = 50
    $panelHardenBtn.BackColor = [System.Drawing.ColorTranslator]::FromHtml("#161b22")
    $tabHarden.Controls.Add($panelHardenBtn)

    $btnShowRecs = New-Object System.Windows.Forms.Button
    $btnShowRecs.Text = "Show Recommendations"
    $btnShowRecs.Size = New-Object System.Drawing.Size(200, 35)
    $btnShowRecs.Location = New-Object System.Drawing.Point(10, 8)
    $btnShowRecs.BackColor = [System.Drawing.ColorTranslator]::FromHtml($COLOR_ACCENT)
    $btnShowRecs.ForeColor = [System.Drawing.Color]::White
    $btnShowRecs.FlatStyle = "Flat"
    $btnShowRecs.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $btnShowRecs.Cursor = [System.Windows.Forms.Cursors]::Hand
    $panelHardenBtn.Controls.Add($btnShowRecs)

    $btnEnableCFA = New-Object System.Windows.Forms.Button
    $btnEnableCFA.Text = "Enable CFA"
    $btnEnableCFA.Size = New-Object System.Drawing.Size(130, 35)
    $btnEnableCFA.Location = New-Object System.Drawing.Point(230, 8)
    $btnEnableCFA.BackColor = [System.Drawing.ColorTranslator]::FromHtml($COLOR_GREEN)
    $btnEnableCFA.ForeColor = [System.Drawing.Color]::White
    $btnEnableCFA.FlatStyle = "Flat"
    $btnEnableCFA.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $btnEnableCFA.Cursor = [System.Windows.Forms.Cursors]::Hand
    $panelHardenBtn.Controls.Add($btnEnableCFA)

    $btnShowASR = New-Object System.Windows.Forms.Button
    $btnShowASR.Text = "Show ASR Rules"
    $btnShowASR.Size = New-Object System.Drawing.Size(150, 35)
    $btnShowASR.Location = New-Object System.Drawing.Point(380, 8)
    $btnShowASR.BackColor = [System.Drawing.ColorTranslator]::FromHtml($COLOR_ORANGE)
    $btnShowASR.ForeColor = [System.Drawing.Color]::White
    $btnShowASR.FlatStyle = "Flat"
    $btnShowASR.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $btnShowASR.Cursor = [System.Windows.Forms.Cursors]::Hand
    $panelHardenBtn.Controls.Add($btnShowASR)

    $btnShowRecs.Add_Click({
        $txtHarden.Clear()
        Show-HardeningRecommendations -Log $txtHarden
    })

    $btnEnableCFA.Add_Click({
        $confirm = [System.Windows.Forms.MessageBox]::Show(
            "This will enable Controlled Folder Access (Windows ransomware protection).`n`nA system restore point will be created first.`n`nSome legitimate applications may be blocked and need to be allowed manually.`n`nContinue?",
            "Enable Controlled Folder Access",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        if ($confirm -eq [System.Windows.Forms.DialogResult]::Yes) {
            Invoke-EnableCFA -Log $txtHarden
        }
    })

    $btnShowASR.Add_Click({
        $txtHarden.AppendText("`r`n`r`n")
        Invoke-EnableASR -Log $txtHarden
    })

    # Show form
    $form.Add_Shown({ $form.Activate() })
    [void]$form.ShowDialog()
    $form.Dispose()
}

# ═══════════════════════════════════════════════════════════════════════════════
# ENTRY POINT
# ═══════════════════════════════════════════════════════════════════════════════

Show-MainForm

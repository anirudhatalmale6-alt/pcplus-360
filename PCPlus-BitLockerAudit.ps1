#Requires -Version 5.1
<#
.SYNOPSIS
    PC Plus Computing - BitLocker & Encryption Audit Tool
.DESCRIPTION
    Comprehensive BitLocker status and encryption posture audit for all drives.
    Checks TPM, key protectors, encryption methods, EFS usage, WIP status,
    and Group Policy settings. Generates a branded HTML report with an overall
    encryption score (0-100).
.NOTES
    Company : PC Plus Computing
    Website : pcpluscomputing.com
    Phone   : 604-760-1662 | 236-500-2700
    Version : 1.0.0
    Requires: PowerShell 5.1+, Windows 10/11, Administrator privileges
#>

Set-StrictMode -Version Latest
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
    Write-Host ""
    Write-Host "  [!] This script requires Administrator privileges." -ForegroundColor Red
    Write-Host "      Please right-click and select 'Run as Administrator'." -ForegroundColor Yellow
    Write-Host ""
    try {
        $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$($MyInvocation.MyCommand.Definition)`""
        Start-Process powershell.exe -ArgumentList $arguments -Verb RunAs
    } catch {
        Write-Host "  Failed to relaunch as admin: $_" -ForegroundColor Red
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
# BRANDING & PATHS
# ─────────────────────────────────────────────────────────────────────────────
$COMPANY_NAME    = "PC Plus Computing"
$COMPANY_PHONE   = "604-760-1662 | 236-500-2700"
$COMPANY_WEBSITE = "pcpluscomputing.com"
$SCRIPT_VERSION  = "1.0.0"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
if ([string]::IsNullOrEmpty($ScriptDir)) { $ScriptDir = Get-Location }
$ReportDir = Join-Path $ScriptDir "reports"
if (-not (Test-Path $ReportDir)) { New-Item -ItemType Directory -Path $ReportDir -Force | Out-Null }

$dateStamp  = (Get-Date).ToString("yyyyMMdd-HHmmss")
$scanDate   = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
$reportFile = Join-Path $ReportDir "PCPlus360-BitLocker-$($env:COMPUTERNAME)-$dateStamp.html"

function Invoke-Safe { param([scriptblock]$Block, $Default = $null); try { return (& $Block) } catch { return $Default } }

# ─────────────────────────────────────────────────────────────────────────────
# CONSOLE BANNER
# ─────────────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "  ============================================================" -ForegroundColor Cyan
Write-Host "   $COMPANY_NAME - BitLocker & Encryption Audit" -ForegroundColor White
Write-Host "   $COMPANY_PHONE | $COMPANY_WEBSITE" -ForegroundColor DarkGray
Write-Host "  ============================================================" -ForegroundColor Cyan
Write-Host ""

$score       = 0
$maxScore    = 0
$findings    = [System.Collections.ArrayList]::new()
$driveData   = [System.Collections.ArrayList]::new()

function Add-Finding {
    param([string]$Check, [string]$Status, [int]$Points, [int]$MaxPoints, [string]$Detail = "")
    $script:score    += $Points
    $script:maxScore += $MaxPoints
    [void]$findings.Add(@{ Check = $Check; Status = $Status; Points = $Points; MaxPoints = $MaxPoints; Detail = $Detail; Passed = ($Points -eq $MaxPoints) })
}

# ═════════════════════════════════════════════════════════════════════════════
# CHECK 1: BitLocker Module Availability
# ═════════════════════════════════════════════════════════════════════════════
Write-Host "  [1/10] Checking BitLocker module availability..." -ForegroundColor Yellow
$blModuleAvailable = Invoke-Safe { Get-Module -ListAvailable -Name BitLocker; $true } $false
if ($blModuleAvailable) {
    Import-Module BitLocker -ErrorAction SilentlyContinue
    Write-Host "         BitLocker module loaded" -ForegroundColor Green
} else {
    Write-Host "         BitLocker module not available (Home edition?)" -ForegroundColor Red
}

# ═════════════════════════════════════════════════════════════════════════════
# CHECK 2: BitLocker Status for All Drives
# ═════════════════════════════════════════════════════════════════════════════
Write-Host "  [2/10] Enumerating BitLocker volumes..." -ForegroundColor Yellow
$blVolumes = Invoke-Safe { Get-BitLockerVolume -ErrorAction Stop } @()

if ($blVolumes -and $blVolumes.Count -gt 0) {
    $encryptedCount = 0
    foreach ($vol in $blVolumes) {
        $driveLabel = Invoke-Safe { (Get-Volume -DriveLetter $vol.MountPoint.TrimEnd(':', '\') -ErrorAction Stop).FileSystemLabel } "N/A"
        $driveSize  = Invoke-Safe {
            $letter = $vol.MountPoint.TrimEnd(':', '\')
            $diskObj = Get-WmiObject Win32_LogicalDisk -Filter "DeviceID='${letter}:'" -ErrorAction Stop
            [math]::Round($diskObj.Size / 1GB, 1)
        } 0

        $protStatus   = $vol.ProtectionStatus.ToString()
        $volStatus    = $vol.VolumeStatus.ToString()
        $encMethod    = $vol.EncryptionMethod.ToString()
        $encPct       = $vol.EncryptionPercentage
        $lockStatus   = $vol.LockStatus.ToString()
        $autoUnlock   = $vol.AutoUnlockEnabled
        $keyProtNames = @()
        foreach ($kp in $vol.KeyProtector) { $keyProtNames += $kp.KeyProtectorType.ToString() }
        $keyProtStr = if ($keyProtNames.Count -gt 0) { $keyProtNames -join ", " } else { "None" }

        # Determine hardware vs software encryption
        $encType = "Software"
        if ($encMethod -match "Hardware") { $encType = "Hardware" }

        # Recovery key backup check
        $recoveryBacked = $false
        foreach ($kp in $vol.KeyProtector) {
            if ($kp.KeyProtectorType -eq "RecoveryPassword") {
                $recoveryBacked = $true
            }
        }

        $isOsDrive = ($vol.MountPoint -eq "C:" -or $vol.MountPoint -eq "C:\")

        [void]$driveData.Add(@{
            DriveLetter    = $vol.MountPoint
            Label          = $driveLabel
            SizeGB         = $driveSize
            Protection     = $protStatus
            VolumeStatus   = $volStatus
            EncMethod      = $encMethod
            EncPercentage  = $encPct
            LockStatus     = $lockStatus
            AutoUnlock     = $autoUnlock
            KeyProtectors  = $keyProtStr
            EncType        = $encType
            HasRecoveryKey = $recoveryBacked
            IsOsDrive      = $isOsDrive
        })

        if ($protStatus -eq "On") { $encryptedCount++ }

        $statusColor = if ($protStatus -eq "On") { "Green" } else { "Red" }
        Write-Host "         $($vol.MountPoint) - Protection: $protStatus | Method: $encMethod | $encPct% encrypted" -ForegroundColor $statusColor
    }

    $osDrive = $driveData | Where-Object { $_.IsOsDrive }
    if ($osDrive -and $osDrive.Protection -eq "On") {
        Add-Finding "OS Drive Encrypted" "PASS" 20 20 "C: drive is BitLocker protected"
    } elseif ($osDrive) {
        Add-Finding "OS Drive Encrypted" "FAIL" 0 20 "C: drive is NOT BitLocker protected"
    } else {
        Add-Finding "OS Drive Encrypted" "WARN" 5 20 "Could not identify OS drive"
    }

    $allEncrypted = ($encryptedCount -eq $blVolumes.Count)
    if ($allEncrypted) {
        Add-Finding "All Drives Encrypted" "PASS" 10 10 "All $($blVolumes.Count) volumes protected"
    } else {
        Add-Finding "All Drives Encrypted" "FAIL" 0 10 "$encryptedCount of $($blVolumes.Count) volumes protected"
    }
} else {
    Write-Host "         No BitLocker volumes found or module unavailable" -ForegroundColor Red
    Add-Finding "OS Drive Encrypted" "FAIL" 0 20 "BitLocker not configured on any drive"
    Add-Finding "All Drives Encrypted" "FAIL" 0 10 "No BitLocker volumes detected"
}

# ═════════════════════════════════════════════════════════════════════════════
# CHECK 3: Encryption Method Strength
# ═════════════════════════════════════════════════════════════════════════════
Write-Host "  [3/10] Evaluating encryption methods..." -ForegroundColor Yellow
$strongMethods = @("XtsAes256", "XtsAes128", "Aes256")
$hasStrongEnc  = $false
foreach ($d in $driveData) {
    if ($d.Protection -eq "On" -and ($strongMethods -contains $d.EncMethod)) {
        $hasStrongEnc = $true
    }
}
if ($driveData.Count -gt 0 -and $hasStrongEnc) {
    Add-Finding "Strong Encryption Method" "PASS" 10 10 "Using AES-256 or XTS-AES"
    Write-Host "         Strong encryption detected" -ForegroundColor Green
} elseif ($driveData.Count -gt 0 -and ($driveData | Where-Object { $_.Protection -eq "On" })) {
    Add-Finding "Strong Encryption Method" "WARN" 5 10 "Using AES-128 (AES-256/XTS recommended)"
    Write-Host "         AES-128 detected - consider upgrading to AES-256" -ForegroundColor Yellow
} else {
    Add-Finding "Strong Encryption Method" "FAIL" 0 10 "No encryption active"
    Write-Host "         No encryption active" -ForegroundColor Red
}

# ═════════════════════════════════════════════════════════════════════════════
# CHECK 4: TPM Status and Version
# ═════════════════════════════════════════════════════════════════════════════
Write-Host "  [4/10] Checking TPM status..." -ForegroundColor Yellow
$tpmInfo = Invoke-Safe {
    $tpm = Get-Tpm -ErrorAction Stop
    $tpmVer = Invoke-Safe {
        $wmi = Get-WmiObject -Namespace "root\cimv2\Security\MicrosoftTpm" -Class Win32_Tpm -ErrorAction Stop
        $ver = $wmi.SpecVersion
        if ($wmi -and $wmi.PSObject.Methods.Name -contains "Dispose") { $wmi.Dispose() }
        $ver
    } "Unknown"
    @{
        Present      = $tpm.TpmPresent
        Ready        = $tpm.TpmReady
        Enabled      = $tpm.TpmEnabled
        Activated    = $tpm.TpmActivated
        Owned        = $tpm.TpmOwned
        Version      = $tpmVer
    }
} @{ Present = $false; Ready = $false; Enabled = $false; Activated = $false; Owned = $false; Version = "N/A" }

if ($tpmInfo.Present -and $tpmInfo.Ready) {
    Add-Finding "TPM Present & Ready" "PASS" 15 15 "TPM version: $($tpmInfo.Version)"
    Write-Host "         TPM present and ready (version: $($tpmInfo.Version))" -ForegroundColor Green
} elseif ($tpmInfo.Present) {
    Add-Finding "TPM Present & Ready" "WARN" 8 15 "TPM present but not ready"
    Write-Host "         TPM present but not ready" -ForegroundColor Yellow
} else {
    Add-Finding "TPM Present & Ready" "FAIL" 0 15 "No TPM detected"
    Write-Host "         No TPM detected" -ForegroundColor Red
}

# ═════════════════════════════════════════════════════════════════════════════
# CHECK 5: Recovery Key Backup Status
# ═════════════════════════════════════════════════════════════════════════════
Write-Host "  [5/10] Checking recovery key backup..." -ForegroundColor Yellow
$hasRecovery = ($driveData | Where-Object { $_.HasRecoveryKey }) -ne $null
$adBackedUp = Invoke-Safe {
    $adObj = Get-ADObject -Filter {objectClass -eq 'msFVE-RecoveryInformation'} -ErrorAction Stop
    ($adObj -ne $null)
} $false
$azureBackedUp = Invoke-Safe {
    $regPath = "HKLM:\SOFTWARE\Policies\Microsoft\FVE"
    $val = Get-ItemProperty -Path $regPath -Name "ActiveDirectoryBackup" -ErrorAction Stop
    $val.ActiveDirectoryBackup -eq 1
} $false

if ($hasRecovery -and ($adBackedUp -or $azureBackedUp)) {
    Add-Finding "Recovery Key Backed Up" "PASS" 10 10 "Recovery key backed up to AD/Azure"
    Write-Host "         Recovery key backed up" -ForegroundColor Green
} elseif ($hasRecovery) {
    Add-Finding "Recovery Key Backed Up" "WARN" 5 10 "Recovery key exists but backup to AD/Azure not confirmed"
    Write-Host "         Recovery key exists, AD/Azure backup unconfirmed" -ForegroundColor Yellow
} else {
    Add-Finding "Recovery Key Backed Up" "FAIL" 0 10 "No recovery key protector found"
    Write-Host "         No recovery key protector found" -ForegroundColor Red
}

# ═════════════════════════════════════════════════════════════════════════════
# CHECK 6: Encryption Completion
# ═════════════════════════════════════════════════════════════════════════════
Write-Host "  [6/10] Checking encryption completion..." -ForegroundColor Yellow
$allComplete = $true
foreach ($d in $driveData) {
    if ($d.Protection -eq "On" -and $d.EncPercentage -lt 100) {
        $allComplete = $false
    }
}
if (($driveData | Where-Object { $_.Protection -eq "On" }) -and $allComplete) {
    Add-Finding "Encryption Complete" "PASS" 5 5 "All protected volumes 100% encrypted"
    Write-Host "         All volumes fully encrypted" -ForegroundColor Green
} elseif ($driveData | Where-Object { $_.Protection -eq "On" }) {
    Add-Finding "Encryption Complete" "WARN" 2 5 "Encryption still in progress on one or more drives"
    Write-Host "         Encryption in progress" -ForegroundColor Yellow
} else {
    Add-Finding "Encryption Complete" "FAIL" 0 5 "No drives are being encrypted"
    Write-Host "         No drives encrypted" -ForegroundColor Red
}

# ═════════════════════════════════════════════════════════════════════════════
# CHECK 7: Auto-Unlock Status
# ═════════════════════════════════════════════════════════════════════════════
Write-Host "  [7/10] Checking auto-unlock configuration..." -ForegroundColor Yellow
$dataDrives = $driveData | Where-Object { -not $_.IsOsDrive }
$autoUnlockConfigured = $false
foreach ($d in $dataDrives) {
    if ($d.AutoUnlock -eq $true) { $autoUnlockConfigured = $true }
}
if ($dataDrives -and ($dataDrives | Where-Object { $_.Protection -eq "On" })) {
    if ($autoUnlockConfigured) {
        Add-Finding "Auto-Unlock (Data Drives)" "PASS" 5 5 "Auto-unlock enabled for data drives"
        Write-Host "         Auto-unlock enabled for data drives" -ForegroundColor Green
    } else {
        Add-Finding "Auto-Unlock (Data Drives)" "INFO" 3 5 "Auto-unlock not enabled (manual unlock required)"
        Write-Host "         Auto-unlock not enabled for data drives" -ForegroundColor Yellow
    }
} else {
    Add-Finding "Auto-Unlock (Data Drives)" "INFO" 5 5 "No encrypted data drives to check"
    Write-Host "         No encrypted data drives" -ForegroundColor DarkGray
}

# ═════════════════════════════════════════════════════════════════════════════
# CHECK 8: BitLocker Group Policy Settings
# ═════════════════════════════════════════════════════════════════════════════
Write-Host "  [8/10] Checking BitLocker Group Policy..." -ForegroundColor Yellow
$gpSettings = @{}
$fveRegPath = "HKLM:\SOFTWARE\Policies\Microsoft\FVE"
$gpSettings.EncMethodOS    = Invoke-Safe { (Get-ItemProperty -Path $fveRegPath -Name "EncryptionMethodWithXtsOs" -ErrorAction Stop).EncryptionMethodWithXtsOs } $null
$gpSettings.EncMethodFixed = Invoke-Safe { (Get-ItemProperty -Path $fveRegPath -Name "EncryptionMethodWithXtsFdv" -ErrorAction Stop).EncryptionMethodWithXtsFdv } $null
$gpSettings.RequireAuth    = Invoke-Safe { (Get-ItemProperty -Path $fveRegPath -Name "UseAdvancedStartup" -ErrorAction Stop).UseAdvancedStartup } $null
$gpSettings.MinPIN         = Invoke-Safe { (Get-ItemProperty -Path $fveRegPath -Name "MinimumPIN" -ErrorAction Stop).MinimumPIN } $null
$gpSettings.ADBackup       = Invoke-Safe { (Get-ItemProperty -Path $fveRegPath -Name "ActiveDirectoryBackup" -ErrorAction Stop).ActiveDirectoryBackup } $null
$gpSettings.RequireADBackup = Invoke-Safe { (Get-ItemProperty -Path $fveRegPath -Name "RequireActiveDirectoryBackup" -ErrorAction Stop).RequireActiveDirectoryBackup } $null

$gpConfigured = ($gpSettings.Values | Where-Object { $_ -ne $null }).Count -gt 0
if ($gpConfigured) {
    Add-Finding "Group Policy Configured" "PASS" 10 10 "BitLocker GPO settings detected"
    Write-Host "         BitLocker Group Policy settings found" -ForegroundColor Green
} else {
    Add-Finding "Group Policy Configured" "WARN" 3 10 "No BitLocker GPO - using defaults"
    Write-Host "         No BitLocker Group Policy configured" -ForegroundColor Yellow
}

# ═════════════════════════════════════════════════════════════════════════════
# CHECK 9: Windows Information Protection (WIP)
# ═════════════════════════════════════════════════════════════════════════════
Write-Host "  [9/10] Checking Windows Information Protection..." -ForegroundColor Yellow
$wipStatus = Invoke-Safe {
    $wipReg = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\EnterpriseDataProtection"
    $status = Get-ItemProperty -Path $wipReg -ErrorAction Stop
    @{ Enabled = $true; Level = $status.EnforcementLevel }
} @{ Enabled = $false; Level = $null }

$wipMdm = Invoke-Safe {
    $mdmReg = "HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\DataProtection"
    $val = Get-ItemProperty -Path $mdmReg -Name "EnterpriseDataProtection" -ErrorAction Stop
    $val.EnterpriseDataProtection -ne $null
} $false

if ($wipStatus.Enabled -or $wipMdm) {
    $wipLevel = switch ($wipStatus.Level) { 0 {"Off"}; 1 {"Silent"}; 2 {"Override"}; 3 {"Block"}; default {"Configured"} }
    Add-Finding "Windows Info Protection" "PASS" 5 5 "WIP enabled - level: $wipLevel"
    Write-Host "         WIP enabled ($wipLevel)" -ForegroundColor Green
} else {
    Add-Finding "Windows Info Protection" "INFO" 2 5 "WIP not configured (optional for consumer PCs)"
    Write-Host "         WIP not configured" -ForegroundColor DarkGray
}

# ═════════════════════════════════════════════════════════════════════════════
# CHECK 10: EFS Usage Check
# ═════════════════════════════════════════════════════════════════════════════
Write-Host "  [10/10] Checking EFS (Encrypting File System) usage..." -ForegroundColor Yellow
$efsInfo = @{ CertFound = $false; FilesFound = 0; Details = "" }

$efsInfo.CertFound = Invoke-Safe {
    $certs = Get-ChildItem Cert:\CurrentUser\My -ErrorAction Stop | Where-Object {
        $_.EnhancedKeyUsageList.ObjectId -contains "1.3.6.1.4.1.311.10.3.4"
    }
    ($certs -ne $null -and $certs.Count -gt 0)
} $false

$efsInfo.FilesFound = Invoke-Safe {
    $count = 0
    $commonPaths = @("$env:USERPROFILE\Documents", "$env:USERPROFILE\Desktop")
    foreach ($p in $commonPaths) {
        if (Test-Path $p) {
            $encrypted = Get-ChildItem -Path $p -Recurse -Force -ErrorAction SilentlyContinue |
                Where-Object { $_.Attributes -band [System.IO.FileAttributes]::Encrypted } |
                Select-Object -First 50
            if ($encrypted) { $count += $encrypted.Count }
        }
    }
    $count
} 0

$efsDisabledGP = Invoke-Safe {
    $val = Get-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\CurrentVersion\EFS" -Name "EfsConfiguration" -ErrorAction Stop
    $val.EfsConfiguration -eq 1
} $false

if ($efsInfo.CertFound) {
    Add-Finding "EFS Configuration" "PASS" 10 10 "EFS certificate found; $($efsInfo.FilesFound) encrypted files in profile"
    Write-Host "         EFS certificate present, $($efsInfo.FilesFound) encrypted files" -ForegroundColor Green
} elseif ($efsDisabledGP) {
    Add-Finding "EFS Configuration" "INFO" 5 10 "EFS disabled by Group Policy"
    Write-Host "         EFS disabled by Group Policy" -ForegroundColor DarkGray
} else {
    Add-Finding "EFS Configuration" "INFO" 5 10 "No EFS certificate - EFS not in use"
    Write-Host "         EFS not in use" -ForegroundColor DarkGray
}

# ═════════════════════════════════════════════════════════════════════════════
# CALCULATE FINAL SCORE
# ═════════════════════════════════════════════════════════════════════════════
$finalScore = if ($maxScore -gt 0) { [math]::Round(($score / $maxScore) * 100) } else { 0 }
$finalScore = [math]::Min($finalScore, 100)
$grade = switch ($true) {
    ($finalScore -ge 90) { "A+" }
    ($finalScore -ge 80) { "A"  }
    ($finalScore -ge 70) { "B"  }
    ($finalScore -ge 60) { "C"  }
    ($finalScore -ge 50) { "D"  }
    default              { "F"  }
}
$gradeColor = switch ($true) {
    ($finalScore -ge 80) { "#27ae60" }
    ($finalScore -ge 60) { "#f39c12" }
    default              { "#e74c3c" }
}

Write-Host ""
Write-Host "  ──────────────────────────────────────────────────────────" -ForegroundColor Cyan
Write-Host "   ENCRYPTION POSTURE SCORE: $finalScore / 100 ($grade)" -ForegroundColor $(if ($finalScore -ge 80) { "Green" } elseif ($finalScore -ge 60) { "Yellow" } else { "Red" })
Write-Host "  ──────────────────────────────────────────────────────────" -ForegroundColor Cyan

# ═════════════════════════════════════════════════════════════════════════════
# HTML REPORT GENERATION
# ═════════════════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "  Generating HTML report..." -ForegroundColor Yellow

# Build drive table rows
$driveRowsHtml = ""
foreach ($d in $driveData) {
    $protColor = switch ($d.Protection) { "On" { "#27ae60" }; "Off" { "#e74c3c" }; default { "#f39c12" } }
    $driveRowsHtml += @"
<tr>
  <td style="font-weight:700">$($d.DriveLetter)</td>
  <td>$($d.Label)</td>
  <td>$($d.SizeGB) GB</td>
  <td style="color:$protColor;font-weight:700">$($d.Protection)</td>
  <td>$($d.EncMethod)</td>
  <td>$($d.KeyProtectors)</td>
  <td>$($d.LockStatus)</td>
  <td>$($d.EncPercentage)%</td>
  <td>$($d.EncType)</td>
  <td>$(if($d.AutoUnlock){'Yes'}else{'No'})</td>
</tr>
"@
}
if (-not $driveRowsHtml) {
    $driveRowsHtml = "<tr><td colspan=`"10`" style=`"text-align:center;color:#e74c3c;font-weight:600`">No BitLocker volumes detected</td></tr>"
}

# Build findings table rows
$findingRowsHtml = ""
foreach ($f in $findings) {
    $icon = if ($f.Passed) { "&#9989;" } elseif ($f.Status -eq "INFO") { "&#8505;" } else { "&#10060;" }
    $cls  = if ($f.Passed) { "pass" } elseif ($f.Status -eq "WARN" -or $f.Status -eq "INFO") { "" } else { "fail" }
    $findingRowsHtml += "<tr class=`"$cls`"><td>$icon</td><td>$($f.Check)</td><td>$($f.Points)/$($f.MaxPoints)</td><td>$($f.Status)</td><td style=`"font-size:11px;color:#666`">$($f.Detail)</td></tr>`n"
}

# Build GP settings rows
$gpRowsHtml = ""
$encMethodNames = @{ 3 = "AES-CBC 128"; 4 = "AES-CBC 256"; 6 = "XTS-AES 128"; 7 = "XTS-AES 256" }
$gpItems = @(
    @{ Name = "OS Drive Encryption Method"; Value = if ($gpSettings.EncMethodOS) { $encMethodNames[[int]$gpSettings.EncMethodOS] } else { "Not configured" } },
    @{ Name = "Fixed Drive Encryption Method"; Value = if ($gpSettings.EncMethodFixed) { $encMethodNames[[int]$gpSettings.EncMethodFixed] } else { "Not configured" } },
    @{ Name = "Require Advanced Startup Auth"; Value = if ($gpSettings.RequireAuth -eq 1) { "Enabled" } elseif ($gpSettings.RequireAuth -eq 0) { "Disabled" } else { "Not configured" } },
    @{ Name = "Minimum PIN Length"; Value = if ($gpSettings.MinPIN) { "$($gpSettings.MinPIN) characters" } else { "Not configured" } },
    @{ Name = "AD Backup Required"; Value = if ($gpSettings.RequireADBackup -eq 1) { "Yes" } elseif ($gpSettings.ADBackup -eq 1) { "Enabled (not required)" } else { "Not configured" } }
)
foreach ($gp in $gpItems) {
    $valColor = if ($gp.Value -eq "Not configured") { "#999" } else { "#0d4b71" }
    $gpRowsHtml += "<tr><td>$($gp.Name)</td><td style=`"color:$valColor;font-weight:600`">$($gp.Value)</td></tr>`n"
}

# TPM info rows
$tpmColor = if ($tpmInfo.Present -and $tpmInfo.Ready) { "#27ae60" } elseif ($tpmInfo.Present) { "#f39c12" } else { "#e74c3c" }

# Score arc for SVG
$pctAngle = [math]::Round($finalScore * 3.6, 1)
$largeArc = if ($pctAngle -gt 180) { 1 } else { 0 }
$radians  = $pctAngle * [math]::PI / 180
$endX     = [math]::Round(50 + 40 * [math]::Sin($radians), 2)
$endY     = [math]::Round(50 - 40 * [math]::Cos($radians), 2)
$arcPath  = if ($finalScore -ge 100) { "M 50 10 A 40 40 0 1 1 49.99 10" } else { "M 50 10 A 40 40 0 $largeArc 1 $endX $endY" }

$passedCount = ($findings | Where-Object { $_.Passed }).Count
$totalChecks = $findings.Count

$html = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>PC Plus 360 - BitLocker Encryption Audit - $($env:COMPUTERNAME)</title>
<style>
  * { margin:0; padding:0; box-sizing:border-box; }
  body { font-family:'Segoe UI',Tahoma,sans-serif; background:#f4f6f9; color:#333; line-height:1.5; }
  .header { background:linear-gradient(135deg,#0a3d5c 0%,#0d4b71 50%,#1a2d4a 100%); color:#fff; padding:24px 40px; }
  .header .brand { font-size:18px; font-weight:700; color:#2596be; }
  .header .tagline { font-size:10px; text-transform:uppercase; letter-spacing:2px; opacity:0.6; }
  .header h1 { font-size:22px; margin:8px 0 4px; }
  .header .meta { display:flex; gap:24px; font-size:13px; color:#bbb; flex-wrap:wrap; }
  .score-banner { padding:16px 40px; font-size:16px; font-weight:700; color:white; display:flex; align-items:center; gap:12px; background:$gradeColor; }
  .container { max-width:1100px; margin:0 auto; padding:20px; }
  .section { background:#fff; border-radius:8px; box-shadow:0 1px 3px rgba(0,0,0,0.08); padding:24px; margin-bottom:16px; }
  .section h2 { font-size:16px; color:#0d4b71; margin-bottom:14px; border-bottom:2px solid #2596be; padding-bottom:6px; }
  .card-row { display:flex; gap:12px; flex-wrap:wrap; }
  .card { flex:1; min-width:120px; background:#f8f9fc; border-radius:6px; padding:14px; text-align:center; border:1px solid #e8ecf1; }
  .card-label { font-size:10px; text-transform:uppercase; color:#888; letter-spacing:0.5px; }
  .card-value { font-size:18px; font-weight:700; color:#0d4b71; }
  .score-section { display:flex; align-items:center; gap:30px; flex-wrap:wrap; }
  table { width:100%; border-collapse:collapse; font-size:13px; }
  th { background:#f0f2f5; text-align:left; padding:8px 12px; font-weight:600; color:#555; border-bottom:2px solid #ddd; font-size:11px; text-transform:uppercase; }
  td { padding:7px 12px; border-bottom:1px solid #eee; }
  tr.pass td:first-child { color:#27ae60; }
  tr.fail td { background:#fef5f5; }
  tr.fail td:first-child { color:#e74c3c; }
  .footer { text-align:center; padding:16px; color:#888; font-size:11px; border-top:1px solid #e0e0e0; margin-top:16px; }
  @media print { body { background:#fff; } .section { box-shadow:none; border:1px solid #ddd; } }
</style>
</head>
<body>

<div class="header">
  <div class="brand">PC Plus Computing</div>
  <div class="tagline">Your Data, Fully Encrypted</div>
  <h1>&#128274; BitLocker &amp; Encryption Audit</h1>
  <div class="meta">
    <span>Computer: <strong>$($env:COMPUTERNAME)</strong></span>
    <span>User: <strong>$($env:USERNAME)</strong></span>
    <span>Scan: <strong>$scanDate</strong></span>
    <span>OS: <strong>$(Invoke-Safe { (Get-CimInstance Win32_OperatingSystem).Caption } 'Windows')</strong></span>
  </div>
</div>

<div class="score-banner">
  $(if ($finalScore -ge 80) { "&#9989; ENCRYPTION POSTURE: STRONG ($grade) - Score $finalScore/100" } elseif ($finalScore -ge 60) { "&#9888; ENCRYPTION POSTURE: MODERATE ($grade) - Score $finalScore/100" } else { "&#10060; ENCRYPTION POSTURE: WEAK ($grade) - Score $finalScore/100" })
</div>

<div class="container">

<!-- Score Overview -->
<div class="section">
  <h2>&#128202; Encryption Score</h2>
  <div class="score-section">
    <svg viewBox="0 0 100 100" width="150" height="150">
      <circle cx="50" cy="50" r="40" fill="none" stroke="#e0e0e0" stroke-width="8"/>
      <path d="$arcPath" fill="none" stroke="$gradeColor" stroke-width="8" stroke-linecap="round"/>
      <text x="50" y="44" text-anchor="middle" font-size="22" font-weight="bold" fill="$gradeColor">$finalScore</text>
      <text x="50" y="58" text-anchor="middle" font-size="10" fill="#666">/ 100</text>
      <text x="50" y="72" text-anchor="middle" font-size="16" font-weight="bold" fill="$gradeColor">$grade</text>
    </svg>
    <div>
      <p><strong>$passedCount</strong> of <strong>$totalChecks</strong> checks passed</p>
      <p>Points: <strong>$score</strong> / <strong>$maxScore</strong></p>
    </div>
  </div>
</div>

<!-- Drive Summary Cards -->
<div class="section">
  <h2>&#128426; Drive Summary</h2>
  <div class="card-row" style="margin-bottom:14px">
    <div class="card"><div class="card-label">Total Volumes</div><div class="card-value">$($driveData.Count)</div></div>
    <div class="card"><div class="card-label">Protected</div><div class="card-value" style="color:#27ae60">$(($driveData | Where-Object { $_.Protection -eq 'On' }).Count)</div></div>
    <div class="card"><div class="card-label">Unprotected</div><div class="card-value" style="color:$(if(($driveData | Where-Object { $_.Protection -ne 'On' }).Count -gt 0){'#e74c3c'}else{'#27ae60'})">$(($driveData | Where-Object { $_.Protection -ne 'On' }).Count)</div></div>
    <div class="card"><div class="card-label">TPM Status</div><div class="card-value" style="color:$tpmColor">$(if($tpmInfo.Ready){'Ready'}elseif($tpmInfo.Present){'Not Ready'}else{'Missing'})</div></div>
  </div>
</div>

<!-- BitLocker Volume Details -->
<div class="section">
  <h2>&#128274; BitLocker Volume Details</h2>
  <div style="overflow-x:auto">
  <table>
    <thead><tr><th>Drive</th><th>Label</th><th>Size</th><th>Protection</th><th>Encryption</th><th>Key Protectors</th><th>Lock</th><th>Complete</th><th>Type</th><th>Auto-Unlock</th></tr></thead>
    <tbody>$driveRowsHtml</tbody>
  </table>
  </div>
</div>

<!-- TPM Details -->
<div class="section">
  <h2>&#128272; TPM (Trusted Platform Module)</h2>
  <div class="card-row">
    <div class="card"><div class="card-label">Present</div><div class="card-value" style="color:$(if($tpmInfo.Present){'#27ae60'}else{'#e74c3c'})">$(if($tpmInfo.Present){'Yes'}else{'No'})</div></div>
    <div class="card"><div class="card-label">Ready</div><div class="card-value" style="color:$(if($tpmInfo.Ready){'#27ae60'}else{'#e74c3c'})">$(if($tpmInfo.Ready){'Yes'}else{'No'})</div></div>
    <div class="card"><div class="card-label">Enabled</div><div class="card-value" style="color:$(if($tpmInfo.Enabled){'#27ae60'}else{'#e74c3c'})">$(if($tpmInfo.Enabled){'Yes'}else{'No'})</div></div>
    <div class="card"><div class="card-label">Owned</div><div class="card-value" style="color:$(if($tpmInfo.Owned){'#27ae60'}else{'#f39c12'})">$(if($tpmInfo.Owned){'Yes'}else{'No'})</div></div>
    <div class="card"><div class="card-label">Version</div><div class="card-value" style="font-size:12px">$($tpmInfo.Version)</div></div>
  </div>
</div>

<!-- Group Policy Settings -->
<div class="section">
  <h2>&#128220; BitLocker Group Policy</h2>
  <table>
    <thead><tr><th>Policy Setting</th><th>Value</th></tr></thead>
    <tbody>$gpRowsHtml</tbody>
  </table>
</div>

<!-- EFS & WIP -->
<div class="section">
  <h2>&#128737; Additional Encryption</h2>
  <div class="card-row">
    <div class="card"><div class="card-label">EFS Certificate</div><div class="card-value" style="color:$(if($efsInfo.CertFound){'#27ae60'}else{'#999'})">$(if($efsInfo.CertFound){'Found'}else{'None'})</div></div>
    <div class="card"><div class="card-label">EFS Files Found</div><div class="card-value">$($efsInfo.FilesFound)</div></div>
    <div class="card"><div class="card-label">WIP Status</div><div class="card-value" style="color:$(if($wipStatus.Enabled -or $wipMdm){'#27ae60'}else{'#999'})">$(if($wipStatus.Enabled -or $wipMdm){'Enabled'}else{'Not Configured'})</div></div>
    <div class="card"><div class="card-label">EFS Policy</div><div class="card-value" style="color:$(if($efsDisabledGP){'#e74c3c'}else{'#27ae60'})">$(if($efsDisabledGP){'Disabled by GP'}else{'Allowed'})</div></div>
  </div>
</div>

<!-- Full Audit Breakdown -->
<div class="section">
  <h2>&#128203; Audit Breakdown - All Checks</h2>
  <table>
    <thead><tr><th style="width:30px"></th><th>Check</th><th>Score</th><th>Status</th><th>Detail</th></tr></thead>
    <tbody>$findingRowsHtml</tbody>
  </table>
</div>

<div class="footer">
  <strong>$COMPANY_NAME</strong> | $COMPANY_WEBSITE | $COMPANY_PHONE<br>
  PC Plus 360 BitLocker Audit v$SCRIPT_VERSION | $scanDate
</div>

</div>
</body>
</html>
"@

$html | Out-File -FilePath $reportFile -Encoding UTF8 -Force

Write-Host "  Report saved: $reportFile" -ForegroundColor Green
Write-Host ""
Write-Host "  ============================================================" -ForegroundColor Cyan
Write-Host "   Audit complete. Opening report..." -ForegroundColor White
Write-Host "  ============================================================" -ForegroundColor Cyan
Write-Host ""

# Open the report
try { Start-Process $reportFile } catch { Write-Host "  Could not auto-open report. Please open manually: $reportFile" -ForegroundColor Yellow }

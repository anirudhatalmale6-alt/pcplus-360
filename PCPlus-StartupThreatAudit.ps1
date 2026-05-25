<#
.SYNOPSIS
    PC Plus 360 - Startup Persistence & Malware Auto-Start Auditing Tool
.DESCRIPTION
    Comprehensive audit of all Windows persistence mechanisms used by malware,
    PUPs, and legitimate software. Checks registry run keys, scheduled tasks,
    services, startup folders, WMI subscriptions, shell extensions, BHOs,
    DLL hijacking vectors, IFEO debuggers, AppInit_DLLs, Winlogon, and
    boot execute entries. Each entry is risk-classified based on signature,
    publisher, file location, and known threat patterns.
.NOTES
    Company : PC Plus Computing
    Website : pcpluscomputing.com
    Phone   : 604-760-1662 | 236-500-2700
    Version : 1.0.0
    Requires: PowerShell 5.1+, Windows 10/11, Administrator privileges
.EXAMPLE
    PowerShell.exe -ExecutionPolicy Bypass -File .\PCPlus-StartupThreatAudit.ps1
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
        Write-Host ""
        Write-Host "  ERROR: This tool requires Administrator privileges." -ForegroundColor Red
        Write-Host "  Please right-click and select 'Run as Administrator'." -ForegroundColor Yellow
        Write-Host ""
        Read-Host "  Press Enter to exit"
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

$ReportDir   = Join-Path $ScriptDir "reports"
$TimeStamp   = Get-Date -Format "yyyyMMdd-HHmmss"
$ComputerSafe = $env:COMPUTERNAME -replace '[^\w\-]', '_'

if (-not (Test-Path $ReportDir)) {
    New-Item -ItemType Directory -Path $ReportDir -Force | Out-Null
}

$HtmlReportPath = Join-Path $ReportDir "StartupThreatAudit-$ComputerSafe-$TimeStamp.html"

# ─────────────────────────────────────────────────────────────────────────────
# RISK LEVELS & COLORS
# ─────────────────────────────────────────────────────────────────────────────
$RISK_SAFE     = "SAFE"
$RISK_LOW      = "LOW RISK"
$RISK_MEDIUM   = "MEDIUM RISK"
$RISK_HIGH     = "HIGH RISK"
$RISK_CRITICAL = "CRITICAL"

$RiskColors = @{
    $RISK_SAFE     = "Green"
    $RISK_LOW      = "Cyan"
    $RISK_MEDIUM   = "Yellow"
    $RISK_HIGH     = "DarkYellow"
    $RISK_CRITICAL = "Red"
}

$RiskHtmlColors = @{
    $RISK_SAFE     = "#16a34a"
    $RISK_LOW      = "#2596be"
    $RISK_MEDIUM   = "#f59e0b"
    $RISK_HIGH     = "#ea580c"
    $RISK_CRITICAL = "#dc2626"
}

# ─────────────────────────────────────────────────────────────────────────────
# SUSPICIOUS PATTERNS & KNOWN THREAT INDICATORS
# ─────────────────────────────────────────────────────────────────────────────
$SuspiciousPaths = @(
    [regex]::Escape($env:TEMP),
    [regex]::Escape("$env:LOCALAPPDATA\Temp"),
    '\\AppData\\Local\\Temp\\',
    '\\Users\\Public\\',
    '\\ProgramData\\[^M]',
    '\\Downloads\\',
    '\\Desktop\\.*\.(exe|bat|cmd|vbs|js|ps1)',
    '\\Recycle'
)

$SuspiciousCommandPatterns = @(
    'powershell.*-enc',
    'powershell.*-e\s',
    'powershell.*encodedcommand',
    'powershell.*hidden',
    'powershell.*bypass.*-c\s',
    'cmd\.exe\s*/c.*&&',
    'cmd\.exe\s*/c.*\|',
    'mshta\s+',
    'wscript\s+',
    'cscript\s+',
    'regsvr32\s+/s\s+/n\s+/u\s+/i:',
    'rundll32.*javascript',
    'certutil.*-urlcache',
    'bitsadmin.*\/transfer'
)

$KnownRATServiceNames = @(
    'DarkComet', 'njRAT', 'Quasar', 'AsyncRAT', 'NanoCore',
    'Remcos', 'NetWire', 'Orcus', 'LimeRAT', 'Warzone',
    'Cobalt', 'Meterpreter', 'Mimikatz', 'TeamSpy',
    'XtremeRAT', 'Adwind', 'jRAT', 'Gh0st', 'PoisonIvy',
    'BlackShades', 'SpyNote', 'CyberGate', 'Imminent'
)

$TrustedPublishers = @(
    'Microsoft Corporation',
    'Microsoft Windows',
    'Google LLC',
    'Google Inc',
    'Adobe Inc.',
    'Adobe Systems Incorporated',
    'Apple Inc.',
    'Intel Corporation',
    'Intel(R) Corporation',
    'NVIDIA Corporation',
    'Realtek Semiconductor',
    'Advanced Micro Devices',
    'Logitech',
    'Dell Inc',
    'HP Inc.',
    'Lenovo',
    'Zoom Video Communications',
    'Slack Technologies',
    'Dropbox, Inc',
    'Mozilla Corporation',
    'Valve Corp.',
    'Steam',
    'Oracle Corporation',
    'Cisco Systems',
    'VMware, Inc.',
    'Symantec Corporation',
    'Norton',
    'McAfee',
    'Malwarebytes Inc',
    'Kaspersky',
    'ESET',
    'Bitdefender',
    'Avast Software',
    'CrowdStrike',
    'SentinelOne',
    'Sophos'
)

# ─────────────────────────────────────────────────────────────────────────────
# RESULTS COLLECTION
# ─────────────────────────────────────────────────────────────────────────────
$AllFindings = New-Object System.Collections.ArrayList

function Add-Finding {
    param(
        [string]$Category,
        [string]$Name,
        [string]$Value,
        [string]$FilePath,
        [string]$Risk,
        [string]$Details,
        [string]$Signer      = "",
        [bool]  $IsSigned     = $false
    )
    $obj = [PSCustomObject]@{
        Category = $Category
        Name     = $Name
        Value    = $Value
        FilePath = $FilePath
        Risk     = $Risk
        Details  = $Details
        Signer   = $Signer
        IsSigned = $IsSigned
    }
    [void]$AllFindings.Add($obj)
}

# ─────────────────────────────────────────────────────────────────────────────
# HELPER: WRITE COLORED RISK OUTPUT
# ─────────────────────────────────────────────────────────────────────────────
function Write-RiskLine {
    param(
        [string]$Risk,
        [string]$Name,
        [string]$Detail
    )
    $color = if ($RiskColors.ContainsKey($Risk)) { $RiskColors[$Risk] } else { "White" }
    $tag = "[$Risk]"
    Write-Host "  $($tag.PadRight(14))" -ForegroundColor $color -NoNewline
    Write-Host " $Name" -ForegroundColor White -NoNewline
    if ($Detail) {
        Write-Host " - $Detail" -ForegroundColor DarkGray
    } else {
        Write-Host ""
    }
}

function Write-SectionHeader {
    param([string]$Title, [int]$Number)
    Write-Host ""
    Write-Host ("=" * 78) -ForegroundColor DarkCyan
    Write-Host "  [$Number] $Title" -ForegroundColor Cyan
    Write-Host ("=" * 78) -ForegroundColor DarkCyan
}

# ─────────────────────────────────────────────────────────────────────────────
# HELPER: CHECK FILE SIGNATURE
# ─────────────────────────────────────────────────────────────────────────────
function Get-FileSignatureInfo {
    param([string]$Path)

    $result = @{ IsSigned = $false; Signer = ""; Status = "Unknown" }

    if ([string]::IsNullOrWhiteSpace($Path)) { return $result }

    # Extract actual file path from command lines
    $cleanPath = $Path.Trim('"', "'", ' ')

    # Handle paths with arguments
    if ($cleanPath -match '^"([^"]+)"') {
        $cleanPath = $Matches[1]
    } elseif ($cleanPath -match '^([a-zA-Z]:\\[^\s]+\.exe)') {
        $cleanPath = $Matches[1]
    } elseif ($cleanPath -match '^([a-zA-Z]:\\[^\s]+\.dll)') {
        $cleanPath = $Matches[1]
    }

    # Expand environment variables
    $cleanPath = [Environment]::ExpandEnvironmentVariables($cleanPath)

    if (-not (Test-Path $cleanPath -ErrorAction SilentlyContinue)) { return $result }

    try {
        $sig = Get-AuthenticodeSignature -FilePath $cleanPath -ErrorAction Stop
        if ($sig.Status -eq 'Valid') {
            $result.IsSigned = $true
            $result.Signer   = if ($sig.SignerCertificate) { $sig.SignerCertificate.Subject } else { "" }
            $result.Status   = "Valid"

            # Extract CN from subject
            if ($result.Signer -match 'CN=([^,]+)') {
                $result.Signer = $Matches[1].Trim('"')
            }
        } else {
            $result.Status = $sig.Status.ToString()
        }
    } catch {
        # Signature check failed
    }

    return $result
}

# ─────────────────────────────────────────────────────────────────────────────
# HELPER: CLASSIFY RISK
# ─────────────────────────────────────────────────────────────────────────────
function Get-RiskLevel {
    param(
        [string]$FilePath,
        [string]$Value,
        [bool]  $IsSigned,
        [string]$Signer,
        [string]$Category
    )

    $expandedPath = ""
    if (-not [string]::IsNullOrWhiteSpace($FilePath)) {
        $expandedPath = [Environment]::ExpandEnvironmentVariables($FilePath)
    }
    $combined = "$FilePath $Value".ToLower()

    # CRITICAL: Check for known RAT names
    foreach ($rat in $KnownRATServiceNames) {
        if ($combined -match [regex]::Escape($rat.ToLower())) {
            return @{ Risk = $RISK_CRITICAL; Reason = "Known RAT/backdoor indicator: $rat" }
        }
    }

    # CRITICAL: Suspicious command patterns
    foreach ($pattern in $SuspiciousCommandPatterns) {
        if ($combined -match $pattern) {
            return @{ Risk = $RISK_CRITICAL; Reason = "Suspicious command pattern detected" }
        }
    }

    # HIGH: Unsigned file in suspicious location
    $inSuspiciousPath = $false
    foreach ($sp in $SuspiciousPaths) {
        if ($combined -match $sp) {
            $inSuspiciousPath = $true
            break
        }
    }

    if ($inSuspiciousPath -and -not $IsSigned) {
        return @{ Risk = $RISK_HIGH; Reason = "Unsigned file in suspicious location" }
    }

    if ($inSuspiciousPath -and $IsSigned) {
        return @{ Risk = $RISK_MEDIUM; Reason = "Signed but in suspicious location" }
    }

    # Check for VBS/JS in startup
    if ($combined -match '\.(vbs|js|wsf|hta|bat|cmd)$') {
        if (-not $IsSigned) {
            return @{ Risk = $RISK_HIGH; Reason = "Script file in auto-start ($Category)" }
        }
        return @{ Risk = $RISK_MEDIUM; Reason = "Script file in auto-start" }
    }

    # SAFE: Known Microsoft or trusted, signed
    if ($IsSigned) {
        $isTrusted = $false
        foreach ($tp in $TrustedPublishers) {
            if ($Signer -match [regex]::Escape($tp)) {
                $isTrusted = $true
                break
            }
        }
        if ($Signer -match 'Microsoft') {
            return @{ Risk = $RISK_SAFE; Reason = "Microsoft signed" }
        }
        if ($isTrusted) {
            return @{ Risk = $RISK_LOW; Reason = "Trusted publisher: $Signer" }
        }
        return @{ Risk = $RISK_LOW; Reason = "Signed by: $Signer" }
    }

    # MEDIUM: Unsigned but in standard location
    if ($expandedPath -match '^C:\\Program Files' -or $expandedPath -match '^C:\\Windows\\System32') {
        return @{ Risk = $RISK_MEDIUM; Reason = "Unsigned but in standard system location" }
    }

    # HIGH: Unsigned, non-standard location
    return @{ Risk = $RISK_HIGH; Reason = "Unsigned executable in non-standard location" }
}

# ─────────────────────────────────────────────────────────────────────────────
# HELPER: READ REGISTRY SAFELY
# ─────────────────────────────────────────────────────────────────────────────
function Get-RegistryEntries {
    param([string]$Path)

    $entries = @()
    try {
        if (Test-Path "Registry::$Path" -ErrorAction SilentlyContinue) {
            $key = Get-Item "Registry::$Path" -ErrorAction Stop
            foreach ($valueName in $key.GetValueNames()) {
                if ([string]::IsNullOrEmpty($valueName)) { continue }
                $data = $key.GetValue($valueName)
                $entries += [PSCustomObject]@{
                    Name  = $valueName
                    Value = "$data"
                    Path  = $Path
                }
            }
        }
    } catch {
        # Registry key not accessible
    }
    return $entries
}

# ═════════════════════════════════════════════════════════════════════════════
# BANNER
# ═════════════════════════════════════════════════════════════════════════════
Clear-Host
Write-Host ""
Write-Host "  ╔══════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "  ║                                                                  ║" -ForegroundColor Cyan
Write-Host "  ║     PC Plus 360 - Startup & Persistence Threat Audit             ║" -ForegroundColor Cyan
Write-Host "  ║     $COMPANY_NAME                                          ║" -ForegroundColor Cyan
Write-Host "  ║     $COMPANY_PHONE | $COMPANY_WEBSITE              ║" -ForegroundColor Cyan
Write-Host "  ║     Version $SCRIPT_VERSION                                              ║" -ForegroundColor Cyan
Write-Host "  ║                                                                  ║" -ForegroundColor Cyan
Write-Host "  ╚══════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Computer: $env:COMPUTERNAME | User: $env:USERNAME | $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor DarkGray
Write-Host "  OS: $((Get-CimInstance Win32_OperatingSystem).Caption)" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  Scanning all Windows persistence mechanisms..." -ForegroundColor White
Write-Host ""

$scanStart = Get-Date

# ═════════════════════════════════════════════════════════════════════════════
# [1] REGISTRY RUN KEYS
# ═════════════════════════════════════════════════════════════════════════════
Write-SectionHeader "Registry Run Keys" 1

$RunKeyPaths = @(
    "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Run",
    "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce",
    "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Run",
    "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce",
    "HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run"
)

$runKeyCount = 0
foreach ($regPath in $RunKeyPaths) {
    $entries = Get-RegistryEntries -Path $regPath
    foreach ($entry in $entries) {
        $sigInfo  = Get-FileSignatureInfo -Path $entry.Value
        $riskInfo = Get-RiskLevel -FilePath $entry.Value -Value $entry.Value `
                                  -IsSigned $sigInfo.IsSigned -Signer $sigInfo.Signer `
                                  -Category "Registry Run Key"

        Add-Finding -Category "Registry Run Key" -Name $entry.Name `
                    -Value $entry.Value -FilePath $entry.Value `
                    -Risk $riskInfo.Risk -Details "$($riskInfo.Reason) | Key: $regPath" `
                    -Signer $sigInfo.Signer -IsSigned $sigInfo.IsSigned

        Write-RiskLine -Risk $riskInfo.Risk -Name $entry.Name -Detail $riskInfo.Reason
        $runKeyCount++
    }
}

if ($runKeyCount -eq 0) {
    Write-Host "  No registry run key entries found." -ForegroundColor DarkGray
}

# ═════════════════════════════════════════════════════════════════════════════
# [2] SCHEDULED TASKS
# ═════════════════════════════════════════════════════════════════════════════
Write-SectionHeader "Scheduled Tasks (Non-Microsoft)" 2

try {
    $tasks = Get-ScheduledTask -ErrorAction Stop | Where-Object {
        $_.TaskPath -notmatch '^\\Microsoft\\' -and
        $_.TaskName -notmatch '^User_Feed_Synchronization' -and
        $_.State -ne 'Disabled'
    }

    $taskCount = 0
    foreach ($task in $tasks) {
        try {
            $actions = $task.Actions
            $execPath = ""
            $arguments = ""
            foreach ($action in $actions) {
                if ($action.Execute) {
                    $execPath  = $action.Execute
                    $arguments = $action.Arguments
                    break
                }
            }

            $fullCmd  = "$execPath $arguments".Trim()
            $sigInfo  = Get-FileSignatureInfo -Path $execPath
            $riskInfo = Get-RiskLevel -FilePath $execPath -Value $fullCmd `
                                      -IsSigned $sigInfo.IsSigned -Signer $sigInfo.Signer `
                                      -Category "Scheduled Task"

            Add-Finding -Category "Scheduled Task" -Name $task.TaskName `
                        -Value $fullCmd -FilePath $execPath `
                        -Risk $riskInfo.Risk `
                        -Details "$($riskInfo.Reason) | Path: $($task.TaskPath)" `
                        -Signer $sigInfo.Signer -IsSigned $sigInfo.IsSigned

            Write-RiskLine -Risk $riskInfo.Risk -Name $task.TaskName -Detail $riskInfo.Reason
            $taskCount++
        } catch {
            continue
        }
    }

    if ($taskCount -eq 0) {
        Write-Host "  No non-Microsoft scheduled tasks found." -ForegroundColor DarkGray
    }
} catch {
    Write-Host "  ERROR: Could not enumerate scheduled tasks - $($_.Exception.Message)" -ForegroundColor Red
}

# ═════════════════════════════════════════════════════════════════════════════
# [3] SERVICES (Non-Microsoft)
# ═════════════════════════════════════════════════════════════════════════════
Write-SectionHeader "Services (Non-Microsoft)" 3

try {
    $services = Get-CimInstance Win32_Service -ErrorAction Stop | Where-Object {
        $_.PathName -and
        $_.PathName -notmatch '\\Windows\\System32\\svchost\.exe' -and
        $_.PathName -notmatch '^C:\\Windows\\servicing\\' -and
        $_.StartMode -ne 'Disabled'
    }

    $svcCount = 0
    foreach ($svc in $services) {
        $svcPath = $svc.PathName
        $sigInfo = Get-FileSignatureInfo -Path $svcPath

        # Skip confirmed Microsoft services
        if ($sigInfo.IsSigned -and $sigInfo.Signer -match 'Microsoft') {
            continue
        }

        $riskInfo = Get-RiskLevel -FilePath $svcPath -Value "$($svc.Name) $svcPath" `
                                  -IsSigned $sigInfo.IsSigned -Signer $sigInfo.Signer `
                                  -Category "Service"

        Add-Finding -Category "Service" -Name "$($svc.Name) ($($svc.DisplayName))" `
                    -Value $svcPath -FilePath $svcPath `
                    -Risk $riskInfo.Risk `
                    -Details "$($riskInfo.Reason) | Start: $($svc.StartMode) | State: $($svc.State)" `
                    -Signer $sigInfo.Signer -IsSigned $sigInfo.IsSigned

        Write-RiskLine -Risk $riskInfo.Risk -Name $svc.Name -Detail "$($riskInfo.Reason) [$($svc.State)]"
        $svcCount++
    }

    if ($svcCount -eq 0) {
        Write-Host "  No non-Microsoft services found." -ForegroundColor DarkGray
    }
} catch {
    Write-Host "  ERROR: Could not enumerate services - $($_.Exception.Message)" -ForegroundColor Red
}

# ═════════════════════════════════════════════════════════════════════════════
# [4] STARTUP FOLDERS
# ═════════════════════════════════════════════════════════════════════════════
Write-SectionHeader "Startup Folders" 4

$StartupFolders = @(
    [Environment]::GetFolderPath('Startup'),
    [Environment]::GetFolderPath('CommonStartup')
)

$startupCount = 0
foreach ($folder in $StartupFolders) {
    if (-not (Test-Path $folder -ErrorAction SilentlyContinue)) { continue }

    try {
        $files = Get-ChildItem -Path $folder -File -ErrorAction Stop
        foreach ($file in $files) {
            if ($file.Name -eq 'desktop.ini') { continue }

            $sigInfo  = Get-FileSignatureInfo -Path $file.FullName
            $riskInfo = Get-RiskLevel -FilePath $file.FullName -Value $file.Name `
                                      -IsSigned $sigInfo.IsSigned -Signer $sigInfo.Signer `
                                      -Category "Startup Folder"

            # Shortcuts - resolve target
            $target = $file.FullName
            if ($file.Extension -eq '.lnk') {
                try {
                    $shell = New-Object -ComObject WScript.Shell
                    $shortcut = $shell.CreateShortcut($file.FullName)
                    $target = $shortcut.TargetPath
                    [System.Runtime.InteropServices.Marshal]::ReleaseComObject($shell) | Out-Null
                    $sigInfo  = Get-FileSignatureInfo -Path $target
                    $riskInfo = Get-RiskLevel -FilePath $target -Value $target `
                                              -IsSigned $sigInfo.IsSigned -Signer $sigInfo.Signer `
                                              -Category "Startup Folder"
                } catch { }
            }

            Add-Finding -Category "Startup Folder" -Name $file.Name `
                        -Value $target -FilePath $target `
                        -Risk $riskInfo.Risk `
                        -Details "$($riskInfo.Reason) | Folder: $folder" `
                        -Signer $sigInfo.Signer -IsSigned $sigInfo.IsSigned

            Write-RiskLine -Risk $riskInfo.Risk -Name $file.Name -Detail $riskInfo.Reason
            $startupCount++
        }
    } catch {
        continue
    }
}

if ($startupCount -eq 0) {
    Write-Host "  No files found in startup folders." -ForegroundColor DarkGray
}

# ═════════════════════════════════════════════════════════════════════════════
# [5] WMI EVENT SUBSCRIPTIONS
# ═════════════════════════════════════════════════════════════════════════════
Write-SectionHeader "WMI Event Subscriptions" 5

$wmiCount = 0
try {
    $consumers = Get-CimInstance -Namespace root\subscription -ClassName __EventConsumer -ErrorAction Stop
    foreach ($consumer in $consumers) {
        $consumerName  = $consumer.Name
        $consumerClass = $consumer.CimClass.CimClassName
        $command = ""

        if ($consumer.PSObject.Properties['CommandLineTemplate']) {
            $command = $consumer.CommandLineTemplate
        } elseif ($consumer.PSObject.Properties['ScriptText']) {
            $command = "Script: $($consumer.ScriptText.Substring(0, [Math]::Min(200, $consumer.ScriptText.Length)))"
        }

        $sigInfo  = Get-FileSignatureInfo -Path $command
        $riskInfo = @{ Risk = $RISK_HIGH; Reason = "WMI persistence - $consumerClass" }

        if ($consumerName -match 'SCM Event') {
            $riskInfo = @{ Risk = $RISK_SAFE; Reason = "Built-in WMI consumer" }
        }

        Add-Finding -Category "WMI Subscription" -Name $consumerName `
                    -Value $command -FilePath $command `
                    -Risk $riskInfo.Risk `
                    -Details "$($riskInfo.Reason) | Class: $consumerClass" `
                    -Signer $sigInfo.Signer -IsSigned $sigInfo.IsSigned

        Write-RiskLine -Risk $riskInfo.Risk -Name $consumerName -Detail $riskInfo.Reason
        $wmiCount++
    }
} catch {
    Write-Host "  Could not query WMI subscriptions (may require elevated access)." -ForegroundColor DarkGray
}

if ($wmiCount -eq 0) {
    Write-Host "  No WMI event subscriptions found." -ForegroundColor DarkGray
}

# ═════════════════════════════════════════════════════════════════════════════
# [6] SHELL EXTENSIONS & BROWSER HELPER OBJECTS
# ═════════════════════════════════════════════════════════════════════════════
Write-SectionHeader "Shell Extensions & Browser Helper Objects" 6

$ShellExtPaths = @(
    "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\ShellIconOverlayIdentifiers",
    "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Shell Extensions\Approved",
    "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Browser Helper Objects",
    "HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Explorer\Browser Helper Objects"
)

$shellCount = 0
foreach ($regPath in $ShellExtPaths) {
    try {
        if (-not (Test-Path "Registry::$regPath" -ErrorAction SilentlyContinue)) { continue }

        $subkeys = Get-ChildItem "Registry::$regPath" -ErrorAction SilentlyContinue
        foreach ($subkey in $subkeys) {
            $clsid = $subkey.PSChildName
            $friendlyName = ""

            # Try to resolve CLSID to file path
            $clsidPath = "HKLM\SOFTWARE\Classes\CLSID\$clsid\InprocServer32"
            $dllPath = ""
            try {
                if (Test-Path "Registry::$clsidPath" -ErrorAction SilentlyContinue) {
                    $dllPath = (Get-ItemProperty "Registry::$clsidPath" -ErrorAction SilentlyContinue).'(default)'
                }
            } catch { }

            $sigInfo = Get-FileSignatureInfo -Path $dllPath
            $displayName = if ($friendlyName) { $friendlyName } else { $clsid }

            # Skip known Microsoft shell extensions
            if ($sigInfo.IsSigned -and $sigInfo.Signer -match 'Microsoft') { continue }

            $riskInfo = Get-RiskLevel -FilePath $dllPath -Value "$displayName $dllPath" `
                                      -IsSigned $sigInfo.IsSigned -Signer $sigInfo.Signer `
                                      -Category "Shell Extension"

            $categoryLabel = if ($regPath -match 'Browser Helper') { "Browser Helper Object" } else { "Shell Extension" }

            Add-Finding -Category $categoryLabel -Name $displayName `
                        -Value $dllPath -FilePath $dllPath `
                        -Risk $riskInfo.Risk `
                        -Details "$($riskInfo.Reason) | CLSID: $clsid" `
                        -Signer $sigInfo.Signer -IsSigned $sigInfo.IsSigned

            Write-RiskLine -Risk $riskInfo.Risk -Name $displayName -Detail $riskInfo.Reason
            $shellCount++
        }
    } catch {
        continue
    }
}

if ($shellCount -eq 0) {
    Write-Host "  No non-Microsoft shell extensions or BHOs found." -ForegroundColor DarkGray
}

# ═════════════════════════════════════════════════════════════════════════════
# [7] DLL SEARCH ORDER HIJACKING
# ═════════════════════════════════════════════════════════════════════════════
Write-SectionHeader "DLL Search Order Hijacking Check" 7

$HijackTargetDLLs = @(
    @{ DLL = "version.dll";    Dir = "$env:SystemRoot" },
    @{ DLL = "dwmapi.dll";     Dir = "$env:SystemRoot" },
    @{ DLL = "uxtheme.dll";    Dir = "$env:SystemRoot" },
    @{ DLL = "propsys.dll";    Dir = "$env:SystemRoot" },
    @{ DLL = "profapi.dll";    Dir = "$env:SystemRoot" },
    @{ DLL = "cryptbase.dll";  Dir = "$env:SystemRoot\System32" },
    @{ DLL = "IPHLPAPI.DLL";   Dir = "$env:SystemRoot\System32" },
    @{ DLL = "amsi.dll";       Dir = "$env:SystemRoot\System32" },
    @{ DLL = "winhttp.dll";    Dir = "$env:SystemRoot\System32" }
)

# Check for DLLs planted in directories they shouldn't be in
$CommonAppPaths = @(
    "$env:ProgramFiles",
    "${env:ProgramFiles(x86)}",
    "$env:LOCALAPPDATA"
)

$dllHijackCount = 0
foreach ($target in $HijackTargetDLLs) {
    foreach ($appBase in $CommonAppPaths) {
        if (-not (Test-Path $appBase -ErrorAction SilentlyContinue)) { continue }

        try {
            $found = Get-ChildItem -Path $appBase -Filter $target.DLL -Recurse `
                         -Depth 3 -ErrorAction SilentlyContinue | Select-Object -First 5

            foreach ($f in $found) {
                $sigInfo = Get-FileSignatureInfo -Path $f.FullName

                # If the DLL is signed by Microsoft and in a normal location, skip
                if ($sigInfo.IsSigned -and $sigInfo.Signer -match 'Microsoft') { continue }

                $riskInfo = @{
                    Risk   = $RISK_HIGH
                    Reason = "Possible DLL hijack: $($target.DLL) found outside System32"
                }

                if (-not $sigInfo.IsSigned) {
                    $riskInfo.Risk = $RISK_CRITICAL
                    $riskInfo.Reason = "UNSIGNED $($target.DLL) outside System32 - likely DLL hijack"
                }

                Add-Finding -Category "DLL Hijack" -Name $target.DLL `
                            -Value $f.FullName -FilePath $f.FullName `
                            -Risk $riskInfo.Risk `
                            -Details $riskInfo.Reason `
                            -Signer $sigInfo.Signer -IsSigned $sigInfo.IsSigned

                Write-RiskLine -Risk $riskInfo.Risk -Name $target.DLL -Detail $f.FullName
                $dllHijackCount++
            }
        } catch {
            continue
        }
    }
}

if ($dllHijackCount -eq 0) {
    Write-Host "  No DLL search order hijacking detected." -ForegroundColor Green
}

# ═════════════════════════════════════════════════════════════════════════════
# [8] IMAGE FILE EXECUTION OPTIONS (IFEO)
# ═════════════════════════════════════════════════════════════════════════════
Write-SectionHeader "Image File Execution Options (Debugger Hijacks)" 8

$IFEOPath = "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options"
$ifeoCount = 0

try {
    if (Test-Path "Registry::$IFEOPath" -ErrorAction SilentlyContinue) {
        $ifeoKeys = Get-ChildItem "Registry::$IFEOPath" -ErrorAction SilentlyContinue
        foreach ($key in $ifeoKeys) {
            try {
                $debugger = (Get-ItemProperty "Registry::$($key.PSPath)" -Name 'Debugger' -ErrorAction SilentlyContinue).Debugger
                if ($debugger) {
                    $sigInfo  = Get-FileSignatureInfo -Path $debugger
                    $riskInfo = @{ Risk = $RISK_CRITICAL; Reason = "IFEO debugger hijack detected" }

                    # Some legitimate debuggers
                    if ($sigInfo.IsSigned -and ($sigInfo.Signer -match 'Microsoft' -or $sigInfo.Signer -match 'JetBrains')) {
                        $riskInfo = @{ Risk = $RISK_LOW; Reason = "Known debugger tool" }
                    }

                    Add-Finding -Category "IFEO Debugger" -Name $key.PSChildName `
                                -Value $debugger -FilePath $debugger `
                                -Risk $riskInfo.Risk `
                                -Details "$($riskInfo.Reason) | Target: $($key.PSChildName)" `
                                -Signer $sigInfo.Signer -IsSigned $sigInfo.IsSigned

                    Write-RiskLine -Risk $riskInfo.Risk -Name $key.PSChildName -Detail "Debugger: $debugger"
                    $ifeoCount++
                }
            } catch {
                continue
            }
        }
    }
} catch {
    Write-Host "  ERROR: Could not read IFEO registry - $($_.Exception.Message)" -ForegroundColor Red
}

if ($ifeoCount -eq 0) {
    Write-Host "  No IFEO debugger hijacks found." -ForegroundColor Green
}

# ═════════════════════════════════════════════════════════════════════════════
# [9] AppInit_DLLs
# ═════════════════════════════════════════════════════════════════════════════
Write-SectionHeader "AppInit_DLLs" 9

$AppInitPaths = @(
    "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Windows",
    "HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows NT\CurrentVersion\Windows"
)

$appInitCount = 0
foreach ($aiPath in $AppInitPaths) {
    try {
        if (-not (Test-Path "Registry::$aiPath" -ErrorAction SilentlyContinue)) { continue }

        $props = Get-ItemProperty "Registry::$aiPath" -ErrorAction SilentlyContinue

        # Check LoadAppInit_DLLs
        $loadEnabled = $false
        if ($props.PSObject.Properties['LoadAppInit_DLLs']) {
            $loadEnabled = $props.LoadAppInit_DLLs -ne 0
        }

        $appInitDlls = ""
        if ($props.PSObject.Properties['AppInit_DLLs']) {
            $appInitDlls = $props.AppInit_DLLs
        }

        if (-not [string]::IsNullOrWhiteSpace($appInitDlls)) {
            $dlls = $appInitDlls -split '[,;\s]' | Where-Object { $_ }
            foreach ($dll in $dlls) {
                $sigInfo  = Get-FileSignatureInfo -Path $dll
                $riskInfo = @{
                    Risk   = if ($loadEnabled) { $RISK_CRITICAL } else { $RISK_HIGH }
                    Reason = if ($loadEnabled) { "AppInit_DLL ACTIVE - injected into all processes" }
                             else { "AppInit_DLL present but loading disabled" }
                }

                if ($sigInfo.IsSigned -and $sigInfo.Signer -match 'Microsoft') {
                    $riskInfo = @{ Risk = $RISK_SAFE; Reason = "Microsoft-signed AppInit_DLL" }
                }

                Add-Finding -Category "AppInit_DLLs" -Name "AppInit_DLL" `
                            -Value $dll -FilePath $dll `
                            -Risk $riskInfo.Risk `
                            -Details "$($riskInfo.Reason) | Key: $aiPath" `
                            -Signer $sigInfo.Signer -IsSigned $sigInfo.IsSigned

                Write-RiskLine -Risk $riskInfo.Risk -Name $dll -Detail $riskInfo.Reason
                $appInitCount++
            }
        }
    } catch {
        continue
    }
}

if ($appInitCount -eq 0) {
    Write-Host "  No AppInit_DLLs configured. (Good)" -ForegroundColor Green
}

# ═════════════════════════════════════════════════════════════════════════════
# [10] WINLOGON ENTRIES
# ═════════════════════════════════════════════════════════════════════════════
Write-SectionHeader "Winlogon Shell & Userinit" 10

$WinlogonPath = "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
$winlogonCount = 0

try {
    if (Test-Path "Registry::$WinlogonPath" -ErrorAction SilentlyContinue) {
        $wlProps = Get-ItemProperty "Registry::$WinlogonPath" -ErrorAction SilentlyContinue

        # Check Shell
        $shell = if ($wlProps.PSObject.Properties['Shell']) { $wlProps.Shell } else { "" }
        if (-not [string]::IsNullOrWhiteSpace($shell)) {
            $isDefault = ($shell.Trim().ToLower() -eq 'explorer.exe')
            $riskInfo = if ($isDefault) {
                @{ Risk = $RISK_SAFE; Reason = "Default Windows shell" }
            } else {
                @{ Risk = $RISK_CRITICAL; Reason = "Modified Winlogon Shell - possible rootkit" }
            }

            Add-Finding -Category "Winlogon" -Name "Shell" `
                        -Value $shell -FilePath $shell `
                        -Risk $riskInfo.Risk -Details $riskInfo.Reason `
                        -Signer "" -IsSigned $false

            Write-RiskLine -Risk $riskInfo.Risk -Name "Winlogon Shell" -Detail $shell
            $winlogonCount++
        }

        # Check Userinit
        $userinit = if ($wlProps.PSObject.Properties['Userinit']) { $wlProps.Userinit } else { "" }
        if (-not [string]::IsNullOrWhiteSpace($userinit)) {
            $defaultUserinit = 'C:\Windows\system32\userinit.exe'
            $cleanUserinit = $userinit.Trim().TrimEnd(',').ToLower()
            $isDefault = ($cleanUserinit -eq $defaultUserinit.ToLower())

            $riskInfo = if ($isDefault) {
                @{ Risk = $RISK_SAFE; Reason = "Default Userinit" }
            } else {
                @{ Risk = $RISK_CRITICAL; Reason = "Modified Userinit - possible malware persistence" }
            }

            Add-Finding -Category "Winlogon" -Name "Userinit" `
                        -Value $userinit -FilePath $userinit `
                        -Risk $riskInfo.Risk -Details $riskInfo.Reason `
                        -Signer "" -IsSigned $false

            Write-RiskLine -Risk $riskInfo.Risk -Name "Winlogon Userinit" -Detail $userinit
            $winlogonCount++
        }

        # Check Notify packages
        $notify = if ($wlProps.PSObject.Properties['Notify']) { $wlProps.Notify } else { "" }
        if (-not [string]::IsNullOrWhiteSpace($notify)) {
            Add-Finding -Category "Winlogon" -Name "Notify" `
                        -Value $notify -FilePath $notify `
                        -Risk $RISK_MEDIUM -Details "Winlogon Notify package present" `
                        -Signer "" -IsSigned $false

            Write-RiskLine -Risk $RISK_MEDIUM -Name "Winlogon Notify" -Detail $notify
            $winlogonCount++
        }
    }
} catch {
    Write-Host "  ERROR: Could not read Winlogon entries - $($_.Exception.Message)" -ForegroundColor Red
}

if ($winlogonCount -eq 0) {
    Write-Host "  No Winlogon entries found." -ForegroundColor DarkGray
}

# ═════════════════════════════════════════════════════════════════════════════
# [11] BOOT EXECUTE
# ═════════════════════════════════════════════════════════════════════════════
Write-SectionHeader "Boot Execute" 11

$BootExecPath = "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager"
$bootCount = 0

try {
    if (Test-Path "Registry::$BootExecPath" -ErrorAction SilentlyContinue) {
        $smProps = Get-ItemProperty "Registry::$BootExecPath" -ErrorAction SilentlyContinue

        if ($smProps.PSObject.Properties['BootExecute']) {
            $bootExecs = $smProps.BootExecute
            if ($bootExecs -is [string]) { $bootExecs = @($bootExecs) }

            foreach ($be in $bootExecs) {
                if ([string]::IsNullOrWhiteSpace($be)) { continue }

                $isDefault = ($be.Trim().ToLower() -eq 'autocheck autochk *')
                $riskInfo = if ($isDefault) {
                    @{ Risk = $RISK_SAFE; Reason = "Default BootExecute value" }
                } else {
                    @{ Risk = $RISK_HIGH; Reason = "Non-default BootExecute entry" }
                }

                Add-Finding -Category "Boot Execute" -Name "BootExecute" `
                            -Value $be -FilePath $be `
                            -Risk $riskInfo.Risk -Details $riskInfo.Reason `
                            -Signer "" -IsSigned $false

                Write-RiskLine -Risk $riskInfo.Risk -Name "BootExecute" -Detail $be
                $bootCount++
            }
        }
    }
} catch {
    Write-Host "  ERROR: Could not read Boot Execute - $($_.Exception.Message)" -ForegroundColor Red
}

if ($bootCount -eq 0) {
    Write-Host "  No Boot Execute entries found." -ForegroundColor DarkGray
}

# ═════════════════════════════════════════════════════════════════════════════
# SUMMARY
# ═════════════════════════════════════════════════════════════════════════════
$scanEnd  = Get-Date
$duration = ($scanEnd - $scanStart).TotalSeconds

Write-Host ""
Write-Host ("=" * 78) -ForegroundColor Cyan
Write-Host "  SCAN COMPLETE - SUMMARY" -ForegroundColor Cyan
Write-Host ("=" * 78) -ForegroundColor Cyan
Write-Host ""

$totalEntries = $AllFindings.Count
$countSafe     = @($AllFindings | Where-Object { $_.Risk -eq $RISK_SAFE     }).Count
$countLow      = @($AllFindings | Where-Object { $_.Risk -eq $RISK_LOW      }).Count
$countMedium   = @($AllFindings | Where-Object { $_.Risk -eq $RISK_MEDIUM   }).Count
$countHigh     = @($AllFindings | Where-Object { $_.Risk -eq $RISK_HIGH     }).Count
$countCritical = @($AllFindings | Where-Object { $_.Risk -eq $RISK_CRITICAL }).Count

Write-Host "  Total entries scanned:  $totalEntries" -ForegroundColor White
Write-Host "  Scan duration:          $([Math]::Round($duration, 1)) seconds" -ForegroundColor White
Write-Host ""
Write-Host "  SAFE:        $countSafe" -ForegroundColor Green
Write-Host "  LOW RISK:    $countLow" -ForegroundColor Cyan
Write-Host "  MEDIUM RISK: $countMedium" -ForegroundColor Yellow
Write-Host "  HIGH RISK:   $countHigh" -ForegroundColor DarkYellow
Write-Host "  CRITICAL:    $countCritical" -ForegroundColor Red
Write-Host ""

# ─────────────────────────────────────────────────────────────────────────────
# RECOMMENDATIONS
# ─────────────────────────────────────────────────────────────────────────────
$recommendations = New-Object System.Collections.ArrayList

if ($countCritical -gt 0) {
    [void]$recommendations.Add("URGENT: $countCritical CRITICAL findings require immediate investigation. These may indicate active malware.")
}
if ($countHigh -gt 0) {
    [void]$recommendations.Add("$countHigh HIGH RISK entries found. Review unsigned executables in non-standard locations.")
}
if ($countMedium -gt 0) {
    [void]$recommendations.Add("$countMedium MEDIUM RISK entries found. Consider verifying legitimacy of unsigned programs.")
}

$criticalFindings = @($AllFindings | Where-Object { $_.Risk -eq $RISK_CRITICAL })
if ($criticalFindings.Count -gt 0) {
    [void]$recommendations.Add("Run a full antivirus scan with an up-to-date scanner (Malwarebytes, Windows Defender).")
    [void]$recommendations.Add("Consider booting from a rescue disk for offline scanning if rootkit is suspected.")
}

if ($recommendations.Count -eq 0) {
    [void]$recommendations.Add("System startup configuration looks clean. No immediate threats detected.")
    [void]$recommendations.Add("Continue regular antivirus updates and periodic scans.")
}

Write-Host "  RECOMMENDATIONS:" -ForegroundColor Cyan
foreach ($rec in $recommendations) {
    Write-Host "    * $rec" -ForegroundColor White
}
Write-Host ""

# ═════════════════════════════════════════════════════════════════════════════
# HTML REPORT GENERATION
# ═════════════════════════════════════════════════════════════════════════════
Write-Host "  Generating HTML report..." -ForegroundColor DarkGray

# Build table rows
$tableRows = New-Object System.Text.StringBuilder

foreach ($f in $AllFindings) {
    $riskColor = if ($RiskHtmlColors.ContainsKey($f.Risk)) { $RiskHtmlColors[$f.Risk] } else { "#666" }
    $signedIcon = if ($f.IsSigned) { "&#9989;" } else { "&#10060;" }
    $escapedName    = [System.Net.WebUtility]::HtmlEncode($f.Name)
    $escapedValue   = [System.Net.WebUtility]::HtmlEncode($f.Value)
    $escapedDetails = [System.Net.WebUtility]::HtmlEncode($f.Details)
    $escapedSigner  = [System.Net.WebUtility]::HtmlEncode($f.Signer)

    [void]$tableRows.Append(@"
<tr>
  <td>$($f.Category)</td>
  <td class="name-col">$escapedName</td>
  <td class="path-col" title="$escapedValue">$escapedValue</td>
  <td style="color:$riskColor;font-weight:700">$($f.Risk)</td>
  <td>$signedIcon</td>
  <td>$escapedSigner</td>
  <td>$escapedDetails</td>
</tr>

"@)
}

$recHtml = New-Object System.Text.StringBuilder
foreach ($rec in $recommendations) {
    [void]$recHtml.Append("<li>$([System.Net.WebUtility]::HtmlEncode($rec))</li>`n")
}

$overallStatus = if ($countCritical -gt 0) { "CRITICAL THREATS DETECTED" }
                 elseif ($countHigh -gt 0) { "HIGH RISK ITEMS FOUND" }
                 elseif ($countMedium -gt 0) { "REVIEW RECOMMENDED" }
                 else { "SYSTEM CLEAN" }

$statusColor = if ($countCritical -gt 0) { "#dc2626" }
               elseif ($countHigh -gt 0) { "#ea580c" }
               elseif ($countMedium -gt 0) { "#f59e0b" }
               else { "#16a34a" }

$htmlContent = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>PC Plus 360 - Startup Threat Audit Report</title>
<style>
*{box-sizing:border-box;margin:0;padding:0}
body{font-family:'Segoe UI',Arial,Helvetica,sans-serif;background:#f0f4f8;color:#163247;line-height:1.5}
.header{background:linear-gradient(135deg,#0a1628 0%,#0d4b71 50%,#2596be 100%);color:white;padding:36px 40px}
.header h1{font-size:28px;margin-bottom:4px;letter-spacing:-0.5px}
.header p{font-size:13px;opacity:0.85}
.container{max-width:1400px;margin:0 auto;padding:24px}
.card{background:white;border-radius:14px;padding:24px;margin-bottom:20px;box-shadow:0 4px 16px rgba(13,75,113,0.1)}
.card h2{color:#0d4b71;font-size:20px;margin-bottom:14px;border-bottom:2px solid #e2eaf0;padding-bottom:8px}
.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(180px,1fr));gap:14px;margin-bottom:16px}
.metric{background:#eaf7fc;border-left:5px solid #2596be;border-radius:10px;padding:14px 16px}
.metric b{display:block;color:#0d4b71;font-size:11px;text-transform:uppercase;letter-spacing:0.5px}
.metric span{font-size:22px;font-weight:800}
.status-badge{display:inline-block;padding:8px 20px;border-radius:999px;font-weight:800;font-size:16px;color:white;background:$statusColor}
.risk-bar{display:flex;gap:8px;flex-wrap:wrap;margin:12px 0}
.risk-item{padding:6px 14px;border-radius:8px;font-weight:700;font-size:13px}
.risk-safe{background:#dcfce7;color:#16a34a}
.risk-low{background:#e0f7fa;color:#0d4b71}
.risk-medium{background:#fef3c7;color:#92400e}
.risk-high{background:#fed7aa;color:#9a3412}
.risk-critical{background:#fecaca;color:#991b1b}
table{width:100%;border-collapse:collapse;font-size:12px;table-layout:fixed}
th{background:#0d4b71;color:white;padding:10px 8px;text-align:left;position:sticky;top:0;cursor:pointer;user-select:none;white-space:nowrap}
th:hover{background:#2596be}
th::after{content:'';display:inline-block;width:0;height:0;margin-left:5px;vertical-align:middle}
th.sort-asc::after{border-left:4px solid transparent;border-right:4px solid transparent;border-bottom:6px solid white}
th.sort-desc::after{border-left:4px solid transparent;border-right:4px solid transparent;border-top:6px solid white}
td{border-bottom:1px solid #e2eaf0;padding:8px;vertical-align:top;overflow:hidden;text-overflow:ellipsis;word-break:break-all}
tr:hover{background:#f5faff}
.name-col{max-width:200px;font-weight:600}
.path-col{max-width:300px;font-size:11px;color:#475569}
.filter-bar{display:flex;gap:10px;margin-bottom:14px;flex-wrap:wrap;align-items:center}
.filter-bar input,.filter-bar select{padding:8px 12px;border:1px solid #cbd5e1;border-radius:8px;font-size:13px}
.filter-bar input{flex:1;min-width:200px}
.footer{text-align:center;padding:24px;color:#64748b;font-size:12px;border-top:1px solid #e2eaf0;margin-top:20px}
ul{margin:8px 0 8px 20px}
li{margin:4px 0}
@media(max-width:768px){.grid{grid-template-columns:1fr 1fr}.container{padding:12px}}
@media print{.filter-bar{display:none}th{background:#0d4b71 !important;-webkit-print-color-adjust:exact;print-color-adjust:exact}}
</style>
</head>
<body>

<div class="header">
  <h1>PC Plus 360 - Startup &amp; Persistence Threat Audit</h1>
  <p>$COMPANY_NAME | $COMPANY_PHONE | $COMPANY_WEBSITE | Your Security, Our Priority</p>
</div>

<div class="container">

  <div class="card">
    <h2>Executive Summary</h2>
    <div class="grid">
      <div class="metric"><b>Computer</b><span>$env:COMPUTERNAME</span></div>
      <div class="metric"><b>User</b><span>$env:USERNAME</span></div>
      <div class="metric"><b>Scan Date</b><span>$(Get-Date -Format 'yyyy-MM-dd HH:mm')</span></div>
      <div class="metric"><b>Total Entries</b><span>$totalEntries</span></div>
      <div class="metric"><b>Duration</b><span>$([Math]::Round($duration, 1))s</span></div>
      <div class="metric"><b>OS</b><span>$((Get-CimInstance Win32_OperatingSystem).Caption -replace 'Microsoft ','')</span></div>
    </div>
    <p style="margin:12px 0"><span class="status-badge">$overallStatus</span></p>
    <div class="risk-bar">
      <span class="risk-item risk-safe">SAFE: $countSafe</span>
      <span class="risk-item risk-low">LOW: $countLow</span>
      <span class="risk-item risk-medium">MEDIUM: $countMedium</span>
      <span class="risk-item risk-high">HIGH: $countHigh</span>
      <span class="risk-item risk-critical">CRITICAL: $countCritical</span>
    </div>
  </div>

  <div class="card">
    <h2>Recommendations</h2>
    <ul>
$($recHtml.ToString())
    </ul>
  </div>

  <div class="card">
    <h2>All Findings</h2>
    <div class="filter-bar">
      <input type="text" id="searchBox" placeholder="Search by name, path, or category..." onkeyup="filterTable()">
      <select id="riskFilter" onchange="filterTable()">
        <option value="">All Risk Levels</option>
        <option value="CRITICAL">Critical</option>
        <option value="HIGH RISK">High Risk</option>
        <option value="MEDIUM RISK">Medium Risk</option>
        <option value="LOW RISK">Low Risk</option>
        <option value="SAFE">Safe</option>
      </select>
      <select id="categoryFilter" onchange="filterTable()">
        <option value="">All Categories</option>
        <option value="Registry Run Key">Registry Run Key</option>
        <option value="Scheduled Task">Scheduled Task</option>
        <option value="Service">Service</option>
        <option value="Startup Folder">Startup Folder</option>
        <option value="WMI Subscription">WMI Subscription</option>
        <option value="Shell Extension">Shell Extension</option>
        <option value="Browser Helper Object">Browser Helper Object</option>
        <option value="DLL Hijack">DLL Hijack</option>
        <option value="IFEO Debugger">IFEO Debugger</option>
        <option value="AppInit_DLLs">AppInit_DLLs</option>
        <option value="Winlogon">Winlogon</option>
        <option value="Boot Execute">Boot Execute</option>
      </select>
    </div>
    <div style="overflow-x:auto">
      <table id="findingsTable">
        <thead>
          <tr>
            <th onclick="sortTable(0)" style="width:12%">Category</th>
            <th onclick="sortTable(1)" style="width:14%">Name</th>
            <th onclick="sortTable(2)" style="width:22%">Value / Path</th>
            <th onclick="sortTable(3)" style="width:10%">Risk</th>
            <th onclick="sortTable(4)" style="width:5%">Signed</th>
            <th onclick="sortTable(5)" style="width:12%">Publisher</th>
            <th onclick="sortTable(6)" style="width:25%">Details</th>
          </tr>
        </thead>
        <tbody>
$($tableRows.ToString())
        </tbody>
      </table>
    </div>
  </div>

</div>

<div class="footer">
  <p><strong>$COMPANY_NAME</strong> | $COMPANY_PHONE | $COMPANY_WEBSITE</p>
  <p>Report generated on $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | PC Plus 360 Startup Threat Audit v$SCRIPT_VERSION</p>
  <p>This report is for professional IT diagnostic use. Findings should be verified by a qualified technician.</p>
</div>

<script>
// Sortable table
var sortDir = {};
function sortTable(col) {
  var table = document.getElementById('findingsTable');
  var tbody = table.tBodies[0];
  var rows = Array.prototype.slice.call(tbody.rows);
  var headers = table.tHead.rows[0].cells;

  // Toggle direction
  sortDir[col] = sortDir[col] === 'asc' ? 'desc' : 'asc';
  var dir = sortDir[col];

  // Clear sort classes
  for (var i = 0; i < headers.length; i++) {
    headers[i].className = '';
  }
  headers[col].className = dir === 'asc' ? 'sort-asc' : 'sort-desc';

  // Risk ordering for sort
  var riskOrder = {'CRITICAL':0,'HIGH RISK':1,'MEDIUM RISK':2,'LOW RISK':3,'SAFE':4};

  rows.sort(function(a, b) {
    var aVal = a.cells[col].textContent.trim();
    var bVal = b.cells[col].textContent.trim();

    if (col === 3) {
      aVal = riskOrder[aVal] !== undefined ? riskOrder[aVal] : 5;
      bVal = riskOrder[bVal] !== undefined ? riskOrder[bVal] : 5;
      return dir === 'asc' ? aVal - bVal : bVal - aVal;
    }

    if (dir === 'asc') return aVal.localeCompare(bVal);
    return bVal.localeCompare(aVal);
  });

  for (var j = 0; j < rows.length; j++) {
    tbody.appendChild(rows[j]);
  }
}

// Filter table
function filterTable() {
  var search = document.getElementById('searchBox').value.toLowerCase();
  var risk = document.getElementById('riskFilter').value;
  var category = document.getElementById('categoryFilter').value;
  var table = document.getElementById('findingsTable');
  var rows = table.tBodies[0].rows;

  for (var i = 0; i < rows.length; i++) {
    var row = rows[i];
    var text = row.textContent.toLowerCase();
    var rowRisk = row.cells[3].textContent.trim();
    var rowCat = row.cells[0].textContent.trim();

    var matchSearch = !search || text.indexOf(search) > -1;
    var matchRisk = !risk || rowRisk === risk;
    var matchCat = !category || rowCat === category;

    row.style.display = (matchSearch && matchRisk && matchCat) ? '' : 'none';
  }
}
</script>

</body>
</html>
"@

try {
    $htmlContent | Out-File -FilePath $HtmlReportPath -Encoding UTF8 -Force
    Write-Host ""
    Write-Host "  HTML Report: $HtmlReportPath" -ForegroundColor Green
} catch {
    Write-Host "  ERROR: Could not write HTML report - $($_.Exception.Message)" -ForegroundColor Red
}

# ═════════════════════════════════════════════════════════════════════════════
# FINAL OUTPUT
# ═════════════════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host ("=" * 78) -ForegroundColor Cyan
Write-Host "  $COMPANY_NAME | $COMPANY_PHONE | $COMPANY_WEBSITE" -ForegroundColor Cyan
Write-Host "  Startup & Persistence Threat Audit Complete" -ForegroundColor Cyan
Write-Host ("=" * 78) -ForegroundColor Cyan
Write-Host ""

if ($countCritical -gt 0) {
    Write-Host "  *** CRITICAL FINDINGS DETECTED - IMMEDIATE ACTION REQUIRED ***" -ForegroundColor Red
    Write-Host ""
    foreach ($cf in ($AllFindings | Where-Object { $_.Risk -eq $RISK_CRITICAL })) {
        Write-Host "    [CRITICAL] $($cf.Category): $($cf.Name)" -ForegroundColor Red
        Write-Host "               $($cf.Value)" -ForegroundColor DarkRed
        Write-Host "               $($cf.Details)" -ForegroundColor DarkGray
        Write-Host ""
    }
}

Write-Host "  Press any key to exit..." -ForegroundColor DarkGray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

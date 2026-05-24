<#
.SYNOPSIS
    PC Plus Computing - Scam Software & Fake Support Tool Detection
.DESCRIPTION
    Detects known scam software, fake antivirus programs, PUPs, suspicious remote
    access tools, browser scam indicators, and other tech support fraud artifacts.
    Generates a branded HTML report with risk assessment.
.NOTES
    Company:  PC Plus Computing
    Website:  pcpluscomputing.com
    Phone:    604-760-1662 | 236-500-2700
    Version:  1.0.0
    Requires: PowerShell 5.1+, Windows 10/11, Administrator privileges
#>

#Requires -Version 5.1
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
    try {
        $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$($MyInvocation.MyCommand.Definition)`""
        Start-Process powershell.exe -ArgumentList $arguments -Verb RunAs
    } catch {
        Write-Host ""
        Write-Host "  ERROR: This tool requires Administrator privileges." -ForegroundColor Red
        Write-Host "  Please right-click and select 'Run as Administrator'." -ForegroundColor Yellow
        Write-Host ""
        Read-Host "Press Enter to exit"
    }
    exit
}

# ─────────────────────────────────────────────────────────────────────────────
# BRANDING & SETUP
# ─────────────────────────────────────────────────────────────────────────────
$COMPANY_NAME    = "PC Plus Computing"
$COMPANY_PHONE1  = "604-760-1662"
$COMPANY_PHONE2  = "236-500-2700"
$COMPANY_WEBSITE = "pcpluscomputing.com"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
if ([string]::IsNullOrEmpty($ScriptDir)) { $ScriptDir = Get-Location }
$ReportDir = Join-Path $ScriptDir "reports"
if (-not (Test-Path $ReportDir)) { New-Item -ItemType Directory -Path $ReportDir -Force | Out-Null }

$scanStart = Get-Date
$scanDate  = $scanStart.ToString("yyyy-MM-dd HH:mm:ss")
$hostName  = $env:COMPUTERNAME

function Invoke-Safe {
    param([scriptblock]$Block, $Default = $null)
    try { return (& $Block) } catch { return $Default }
}

function Write-Section {
    param([string]$Title)
    Write-Host ""
    Write-Host "  [$((Get-Date).ToString('HH:mm:ss'))] $Title" -ForegroundColor Cyan
    Write-Host "  $('-' * 60)" -ForegroundColor DarkGray
}

function Write-Status {
    param([string]$Label, [string]$Value, [string]$Color = "White")
    Write-Host "    $Label : " -NoNewline -ForegroundColor Gray
    Write-Host $Value -ForegroundColor $Color
}

# ─────────────────────────────────────────────────────────────────────────────
# FINDINGS COLLECTION
# ─────────────────────────────────────────────────────────────────────────────
$findings = New-Object System.Collections.ArrayList

function Add-Finding {
    param(
        [ValidateSet("CRITICAL","HIGH","MEDIUM","LOW")]
        [string]$Level,
        [string]$Category,
        [string]$Name,
        [string]$Detail = ""
    )
    [void]$findings.Add(@{ Level = $Level; Category = $Category; Name = $Name; Detail = $Detail })
    $color = switch ($Level) { "CRITICAL" { "Red" } "HIGH" { "Red" } "MEDIUM" { "Yellow" } "LOW" { "DarkYellow" } }
    Write-Host "    [$Level] " -NoNewline -ForegroundColor $color
    Write-Host "$Category - $Name" -ForegroundColor White
}

# ─────────────────────────────────────────────────────────────────────────────
# BANNER
# ─────────────────────────────────────────────────────────────────────────────
Clear-Host
Write-Host ""
Write-Host "  ╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Magenta
Write-Host "  ║        PC PLUS COMPUTING - SCAM PROTECTION AUDIT            ║" -ForegroundColor Magenta
Write-Host "  ║   $COMPANY_PHONE1 | $COMPANY_PHONE2 | $COMPANY_WEBSITE    ║" -ForegroundColor Magenta
Write-Host "  ╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Magenta
Write-Host "    Computer: $hostName  |  Date: $scanDate" -ForegroundColor DarkGray
Write-Host ""

# ─────────────────────────────────────────────────────────────────────────────
# LOAD ALL INSTALLED PROGRAMS (cached for multiple checks)
# ─────────────────────────────────────────────────────────────────────────────
Write-Section "Loading Installed Programs"
$installedPrograms = New-Object System.Collections.ArrayList
$regPaths = @(
    "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*"
)
foreach ($rp in $regPaths) {
    try {
        $items = Get-ItemProperty $rp -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName } |
            Select-Object DisplayName, Publisher, InstallDate, DisplayVersion, UninstallString, InstallLocation
        foreach ($item in $items) {
            [void]$installedPrograms.Add($item)
        }
    } catch { }
}
Write-Status "Programs Found" "$($installedPrograms.Count) installed programs" "White"

# ═════════════════════════════════════════════════════════════════════════════
# 1. KNOWN SCAM SOFTWARE DETECTION
# ═════════════════════════════════════════════════════════════════════════════
Write-Section "Known Scam Software Detection"

$scamPatterns = @(
    # Fake Antivirus / Security
    @{ Pattern = "PC Accelerate"; Category = "Fake Optimizer" },
    @{ Pattern = "PC Optimizer Pro"; Category = "Fake Optimizer" },
    @{ Pattern = "MyPC Backup"; Category = "Fake Backup" },
    @{ Pattern = "MyCleanPC"; Category = "Fake Cleaner" },
    @{ Pattern = "PC Cleaner Pro"; Category = "Fake Cleaner" },
    @{ Pattern = "PC SpeedUp"; Category = "Fake Optimizer" },
    @{ Pattern = "PC Booster"; Category = "Fake Optimizer" },
    @{ Pattern = "PC Speed Maximizer"; Category = "Fake Optimizer" },
    @{ Pattern = "PC Health Advisor"; Category = "Fake Optimizer" },
    @{ Pattern = "PC Mechanic"; Category = "Fake Optimizer" },
    @{ Pattern = "PC TuneUp"; Category = "Fake Optimizer" },
    @{ Pattern = "OneSafe PC Cleaner"; Category = "Fake Cleaner" },
    @{ Pattern = "SpeedUpMyPC"; Category = "Fake Optimizer" },
    @{ Pattern = "FixMyPC"; Category = "Fake Optimizer" },
    # Fake Cleaners / Registry
    @{ Pattern = "RegClean Pro"; Category = "Fake Registry Cleaner" },
    @{ Pattern = "WinZip Driver Updater"; Category = "Fake Driver Updater" },
    @{ Pattern = "SlimCleaner"; Category = "Fake Cleaner" },
    @{ Pattern = "WinZip System Utilities"; Category = "Fake System Utility" },
    @{ Pattern = "Registry Reviver"; Category = "Fake Registry Cleaner" },
    @{ Pattern = "RegCure"; Category = "Fake Registry Cleaner" },
    @{ Pattern = "Registry Mechanic"; Category = "Fake Registry Cleaner" },
    @{ Pattern = "Registry Winner"; Category = "Fake Registry Cleaner" },
    @{ Pattern = "Registry Easy"; Category = "Fake Registry Cleaner" },
    @{ Pattern = "Registry Booster"; Category = "Fake Registry Cleaner" },
    @{ Pattern = "Registry First Aid"; Category = "Fake Registry Cleaner" },
    @{ Pattern = "Uniblue Registry Booster"; Category = "Fake Registry Cleaner" },
    @{ Pattern = "Uniblue SpeedUpMyPC"; Category = "Fake Optimizer" },
    @{ Pattern = "Uniblue DriverScanner"; Category = "Fake Driver Updater" },
    @{ Pattern = "Uniblue PowerSuite"; Category = "Fake System Utility" },
    # Fake System Tools
    @{ Pattern = "Reimage Repair"; Category = "Fake Repair Tool" },
    @{ Pattern = "Reimage PC Repair"; Category = "Fake Repair Tool" },
    @{ Pattern = "Advanced SystemCare"; Category = "PUP System Tool" },
    @{ Pattern = "IObit Malware Fighter"; Category = "PUP Security" },
    @{ Pattern = "IObit Advanced SystemCare"; Category = "PUP System Tool" },
    @{ Pattern = "System Mechanic"; Category = "PUP System Tool" },
    @{ Pattern = "Segurazo"; Category = "Fake Antivirus" },
    @{ Pattern = "SAntivirus"; Category = "Fake Antivirus" },
    @{ Pattern = "Scanguard"; Category = "Fake Antivirus" },
    @{ Pattern = "TotalAV"; Category = "Questionable AV" },
    @{ Pattern = "PC Matic"; Category = "Questionable AV" },
    @{ Pattern = "MacKeeper"; Category = "Fake Cleaner" },
    @{ Pattern = "SpyHunter"; Category = "PUP Security" },
    @{ Pattern = "WinFixer"; Category = "Fake Repair Tool" },
    @{ Pattern = "ErrorSafe"; Category = "Fake Repair Tool" },
    @{ Pattern = "WinAntiVirus"; Category = "Fake Antivirus" },
    @{ Pattern = "XP Antivirus"; Category = "Fake Antivirus" },
    @{ Pattern = "Vista Antivirus"; Category = "Fake Antivirus" },
    @{ Pattern = "Win 7 Antivirus"; Category = "Fake Antivirus" },
    @{ Pattern = "Smart Fortress"; Category = "Fake Antivirus" },
    @{ Pattern = "Security Shield"; Category = "Fake Antivirus" },
    @{ Pattern = "Security Essentials 2010"; Category = "Fake Antivirus" },
    @{ Pattern = "Antivirus Pro 2017"; Category = "Fake Antivirus" },
    @{ Pattern = "ByteFence"; Category = "PUP Security" },
    @{ Pattern = "Total System Care"; Category = "Fake Optimizer" },
    # Fake Driver Updaters
    @{ Pattern = "Driver Booster"; Category = "PUP Driver Updater" },
    @{ Pattern = "Driver Reviver"; Category = "Fake Driver Updater" },
    @{ Pattern = "DriverFix"; Category = "Fake Driver Updater" },
    @{ Pattern = "Driver Easy"; Category = "PUP Driver Updater" },
    @{ Pattern = "Driver Updater"; Category = "Fake Driver Updater" },
    @{ Pattern = "Driver Support"; Category = "Fake Driver Updater" },
    @{ Pattern = "Driver Restore"; Category = "Fake Driver Updater" },
    @{ Pattern = "Smart Driver Updater"; Category = "Fake Driver Updater" },
    @{ Pattern = "DriverMax"; Category = "PUP Driver Updater" },
    @{ Pattern = "Driver Talent"; Category = "PUP Driver Updater" },
    # Adware / Browser Hijackers
    @{ Pattern = "Ask Toolbar"; Category = "Adware Toolbar" },
    @{ Pattern = "Conduit"; Category = "Browser Hijacker" },
    @{ Pattern = "Mindspark"; Category = "Browser Hijacker" },
    @{ Pattern = "MyWebSearch"; Category = "Browser Hijacker" },
    @{ Pattern = "Search Protect"; Category = "Browser Hijacker" },
    @{ Pattern = "Babylon Toolbar"; Category = "Browser Hijacker" },
    @{ Pattern = "Delta Toolbar"; Category = "Browser Hijacker" },
    @{ Pattern = "Wajam"; Category = "Adware" },
    @{ Pattern = "OpenCandy"; Category = "Adware Bundler" },
    @{ Pattern = "InstallCore"; Category = "Adware Bundler" },
    # Fake Subscription / Renewal Scams
    @{ Pattern = "iLivid"; Category = "Adware" },
    @{ Pattern = "YAC"; Category = "Fake Antivirus" },
    @{ Pattern = "Auslogics BoostSpeed"; Category = "PUP Optimizer" },
    @{ Pattern = "Auslogics Registry Cleaner"; Category = "PUP Registry Cleaner" },
    @{ Pattern = "Glary Utilities"; Category = "PUP System Tool" },
    @{ Pattern = "Wise Care 365"; Category = "PUP System Tool" },
    @{ Pattern = "CCleaner"; Category = "Caution - Often Bundled" }
)

$scamFound    = New-Object System.Collections.ArrayList
$scamRunning  = New-Object System.Collections.ArrayList
$runningProcs = Get-Process -ErrorAction SilentlyContinue | Select-Object ProcessName, Id, Path

foreach ($scam in $scamPatterns) {
    $matches = $installedPrograms | Where-Object { $_.DisplayName -match [regex]::Escape($scam.Pattern) }
    foreach ($m in $matches) {
        $isRunning = $false
        # Check if a related process is running
        $procMatch = $runningProcs | Where-Object {
            $_.ProcessName -match [regex]::Escape(($scam.Pattern -replace '\s','')) -or
            ($_.Path -and $_.Path -match [regex]::Escape($scam.Pattern))
        }
        if ($procMatch) {
            $isRunning = $true
            foreach ($pm in $procMatch) { [void]$scamRunning.Add(@{ Name = $m.DisplayName; PID = $pm.Id; Process = $pm.ProcessName }) }
        }

        $level = if ($isRunning) { "CRITICAL" } else { "HIGH" }
        [void]$scamFound.Add(@{
            Name      = $m.DisplayName
            Category  = $scam.Category
            Publisher = $m.Publisher
            Version   = $m.DisplayVersion
            Running   = $isRunning
        })
        Add-Finding -Level $level -Category $scam.Category -Name $m.DisplayName -Detail "Publisher: $($m.Publisher)"
    }
}

if ($scamFound.Count -eq 0) {
    Write-Status "Result" "No known scam software detected" "Green"
}

# ═════════════════════════════════════════════════════════════════════════════
# 2. REMOTE ACCESS TOOLS DETECTION
# ═════════════════════════════════════════════════════════════════════════════
Write-Section "Remote Access Tools Detection"

$ratPatterns = @(
    @{ Name = "TeamViewer";       Process = "TeamViewer" },
    @{ Name = "AnyDesk";          Process = "AnyDesk" },
    @{ Name = "ScreenConnect";    Process = "ScreenConnect" },
    @{ Name = "ConnectWise";      Process = "ScreenConnect" },
    @{ Name = "Splashtop";        Process = "SplashtopStreamer" },
    @{ Name = "UltraVNC";         Process = "winvnc" },
    @{ Name = "TightVNC";         Process = "tvnserver" },
    @{ Name = "RealVNC";          Process = "vncserver" },
    @{ Name = "LogMeIn";          Process = "LogMeIn" },
    @{ Name = "GoToMyPC";         Process = "g2mcomm" },
    @{ Name = "RemotePC";         Process = "RemotePC" },
    @{ Name = "Supremo";          Process = "Supremo" },
    @{ Name = "Ammyy Admin";      Process = "AA_v3" },
    @{ Name = "DameWare";         Process = "DWRCC" },
    @{ Name = "GoToAssist";       Process = "GoToAssist" },
    @{ Name = "BeyondTrust";      Process = "bomgar" },
    @{ Name = "Zoho Assist";      Process = "ZohoMeeting" },
    @{ Name = "Rustdesk";         Process = "rustdesk" },
    @{ Name = "SimpleHelp";       Process = "SimpleHelp" },
    @{ Name = "Remote Utilities"; Process = "rutserv" },
    @{ Name = "ISL Online";       Process = "ISLLight" },
    @{ Name = "Parallels Access";  Process = "prl_client_app" },
    @{ Name = "Chrome Remote Desktop"; Process = "remoting_host" }
)

$ratFound = New-Object System.Collections.ArrayList
$thirtyDaysAgo = (Get-Date).AddDays(-30)

foreach ($rat in $ratPatterns) {
    $installed = $installedPrograms | Where-Object { $_.DisplayName -match [regex]::Escape($rat.Name) }
    foreach ($inst in $installed) {
        $isRunning = $null -ne ($runningProcs | Where-Object { $_.ProcessName -match [regex]::Escape($rat.Process) } | Select-Object -First 1)

        $installDate = $null
        $isRecent = $false
        if ($inst.InstallDate) {
            try {
                $installDate = [datetime]::ParseExact($inst.InstallDate, "yyyyMMdd", $null)
                $isRecent = $installDate -gt $thirtyDaysAgo
            } catch { }
        }

        $level = if ($isRecent -and $isRunning) { "HIGH" } elseif ($isRecent) { "MEDIUM" } else { "MEDIUM" }
        [void]$ratFound.Add(@{
            Name        = $inst.DisplayName
            Publisher   = $inst.Publisher
            Version     = $inst.DisplayVersion
            Running     = $isRunning
            InstallDate = if ($installDate) { $installDate.ToString("yyyy-MM-dd") } else { "Unknown" }
            Recent      = $isRecent
        })
        $detail = "Running: $isRunning | Installed: $(if($installDate){$installDate.ToString('yyyy-MM-dd')}else{'Unknown'})"
        if ($isRecent) { $detail += " (RECENTLY INSTALLED)" }
        Add-Finding -Level $level -Category "Remote Access" -Name $inst.DisplayName -Detail $detail
    }
}

# Also check for running RAT processes without installed entries
foreach ($rat in $ratPatterns) {
    $alreadyFound = $ratFound | Where-Object { $_.Name -match [regex]::Escape($rat.Name) }
    if (-not $alreadyFound) {
        $running = $runningProcs | Where-Object { $_.ProcessName -match [regex]::Escape($rat.Process) }
        if ($running) {
            foreach ($r in $running) {
                [void]$ratFound.Add(@{
                    Name        = "$($rat.Name) (process only)"
                    Publisher   = "N/A"
                    Version     = "N/A"
                    Running     = $true
                    InstallDate = "N/A"
                    Recent      = $false
                })
                Add-Finding -Level "HIGH" -Category "Remote Access" -Name "$($rat.Name) running (not in Add/Remove Programs)" -Detail "PID: $($r.Id) Path: $($r.Path)"
            }
        }
    }
}

if ($ratFound.Count -eq 0) {
    Write-Status "Result" "No remote access tools detected" "Green"
}

# ═════════════════════════════════════════════════════════════════════════════
# 3. RECENT PROGRAM INSTALLATIONS (Last 30 Days)
# ═════════════════════════════════════════════════════════════════════════════
Write-Section "Recent Installations (Last 30 Days)"
$recentInstalls = New-Object System.Collections.ArrayList
foreach ($prog in $installedPrograms) {
    if ($prog.InstallDate) {
        try {
            $instDate = [datetime]::ParseExact($prog.InstallDate, "yyyyMMdd", $null)
            if ($instDate -gt $thirtyDaysAgo) {
                [void]$recentInstalls.Add(@{
                    Name      = $prog.DisplayName
                    Publisher = $prog.Publisher
                    Date      = $instDate.ToString("yyyy-MM-dd")
                    Version   = $prog.DisplayVersion
                })
            }
        } catch { }
    }
}
$recentInstalls = [System.Collections.ArrayList]@($recentInstalls | Sort-Object { $_.Date } -Descending)
Write-Status "Recent" "$($recentInstalls.Count) programs installed in last 30 days" "White"

# ═════════════════════════════════════════════════════════════════════════════
# 4. BROWSER SCAM INDICATORS
# ═════════════════════════════════════════════════════════════════════════════
Write-Section "Browser Scam Indicators"
$browserFindings = New-Object System.Collections.ArrayList

# Check common browser history databases for scam patterns
$scamUrlPatterns = @(
    "virus.*detected", "computer.*infected", "call.*support.*now",
    "microsoft.*alert", "windows.*defender.*alert", "apple.*security",
    "your.*computer.*blocked", "firewall.*alert", "trojan.*detected",
    "pornographic.*virus", "zeus.*virus", "spyware.*detected",
    "tech.*support.*\d{3}", "call.*1-8[0-9]{2}", "geek.*squad.*renewal",
    "norton.*renewal", "mcafee.*renewal", "subscription.*expired",
    "refund.*department", "billing.*department"
)

$scamNumberPatterns = @(
    "1-8\d{2}-\d{3}-\d{4}", "1-877-", "1-888-", "1-866-", "1-855-",
    "toll.free.*number", "call.*immediately", "do.*not.*close"
)

$browserPaths = @(
    @{ Browser = "Chrome"; Path = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\History" },
    @{ Browser = "Edge";   Path = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\History" },
    @{ Browser = "Firefox"; Path = "$env:APPDATA\Mozilla\Firefox\Profiles" }
)

foreach ($bp in $browserPaths) {
    if ($bp.Browser -eq "Firefox") {
        $ffProfiles = Invoke-Safe { Get-ChildItem $bp.Path -Directory -ErrorAction SilentlyContinue } @()
        foreach ($ffp in $ffProfiles) {
            $histFile = Join-Path $ffp.FullName "places.sqlite"
            if (Test-Path $histFile) {
                [void]$browserFindings.Add(@{ Browser = "Firefox"; Status = "History DB found"; Path = $histFile; Suspicious = $false })
            }
        }
    } else {
        if (Test-Path $bp.Path) {
            [void]$browserFindings.Add(@{ Browser = $bp.Browser; Status = "History DB found"; Path = $bp.Path; Suspicious = $false })
        }
    }
}

# Check Downloads folder for suspicious files
$downloadPaths = @(
    (Join-Path $env:USERPROFILE "Downloads"),
    (Join-Path $env:USERPROFILE "Desktop")
)

$suspFilePatterns = @(
    "*.bat", "*.vbs", "*.ps1", "*.hta", "*.wsf", "*.scr",
    "*support*", "*refund*", "*antivirus*", "*cleaner*",
    "*optimizer*", "*driver*update*", "*fix*computer*",
    "*microsoft*support*", "*apple*support*", "*geek*squad*",
    "*norton*renewal*", "*mcafee*renewal*"
)

$suspFiles = New-Object System.Collections.ArrayList
foreach ($dl in $downloadPaths) {
    if (Test-Path $dl) {
        foreach ($pat in $suspFilePatterns) {
            try {
                $matched = Get-ChildItem -Path $dl -Filter $pat -File -ErrorAction SilentlyContinue |
                    Where-Object { $_.CreationTime -gt $thirtyDaysAgo }
                foreach ($mf in $matched) {
                    [void]$suspFiles.Add(@{
                        Name     = $mf.Name
                        Path     = $mf.FullName
                        Size     = "$([math]::Round($mf.Length / 1KB, 1)) KB"
                        Created  = $mf.CreationTime.ToString("yyyy-MM-dd HH:mm")
                        Location = (Split-Path $dl -Leaf)
                    })
                }
            } catch { }
        }
    }
}

if ($suspFiles.Count -gt 0) {
    Write-Status "Suspicious Files" "$($suspFiles.Count) suspicious files found" "Yellow"
    foreach ($sf in $suspFiles) {
        Add-Finding -Level "LOW" -Category "Suspicious File" -Name $sf.Name -Detail "Location: $($sf.Location) | Created: $($sf.Created)"
    }
} else {
    Write-Status "Downloads/Desktop" "No suspicious files detected" "Green"
}

# ═════════════════════════════════════════════════════════════════════════════
# 5. SUSPICIOUS SCHEDULED TASKS
# ═════════════════════════════════════════════════════════════════════════════
Write-Section "Suspicious Scheduled Tasks"
$suspTasks = New-Object System.Collections.ArrayList
Invoke-Safe {
    $tasks = Get-ScheduledTask -ErrorAction SilentlyContinue |
        Where-Object { $_.State -ne "Disabled" -and $_.TaskPath -notmatch "\\Microsoft\\" }

    $suspTaskKeywords = @("update", "helper", "support", "clean", "optimize", "boost",
                          "scan", "protect", "driver", "registry", "speed",
                          "accelerate", "fix", "repair", "backup.*my")

    foreach ($task in $tasks) {
        $actions = $task | Get-ScheduledTaskInfo -ErrorAction SilentlyContinue
        $taskActions = Invoke-Safe {
            ($task.Actions | ForEach-Object { "$($_.Execute) $($_.Arguments)" }) -join "; "
        } "N/A"

        $isSuspicious = $false
        foreach ($kw in $suspTaskKeywords) {
            if ($task.TaskName -match $kw -or $taskActions -match $kw) {
                $isSuspicious = $true
                break
            }
        }

        # Check for executables in temp/appdata
        if ($taskActions -match "\\Temp\\" -or $taskActions -match "\\AppData\\") {
            $isSuspicious = $true
        }

        if ($isSuspicious) {
            [void]$suspTasks.Add(@{
                Name    = $task.TaskName
                Path    = $task.TaskPath
                State   = "$($task.State)"
                Actions = $taskActions
            })
            Add-Finding -Level "MEDIUM" -Category "Scheduled Task" -Name $task.TaskName -Detail "Action: $taskActions"
        }
    }
}

if ($suspTasks.Count -eq 0) {
    Write-Status "Result" "No suspicious scheduled tasks detected" "Green"
}

# ═════════════════════════════════════════════════════════════════════════════
# 6. DESKTOP / DOWNLOADS SUSPICIOUS FILES
# ═════════════════════════════════════════════════════════════════════════════
Write-Section "Desktop & Downloads Cleanup Check"
$cleanupItems = New-Object System.Collections.ArrayList
$scanPaths = @(
    @{ Path = (Join-Path $env:USERPROFILE "Desktop"); Label = "Desktop" },
    @{ Path = (Join-Path $env:USERPROFILE "Downloads"); Label = "Downloads" },
    @{ Path = $env:TEMP; Label = "Temp" }
)

foreach ($sp in $scanPaths) {
    if (Test-Path $sp.Path) {
        # Count executable files
        $exeFiles = Invoke-Safe {
            Get-ChildItem -Path $sp.Path -Include "*.exe","*.msi","*.bat","*.vbs","*.hta","*.scr","*.ps1","*.cmd","*.wsf" -Recurse -File -ErrorAction SilentlyContinue |
                Where-Object { $_.CreationTime -gt $thirtyDaysAgo }
        } @()
        if ($exeFiles.Count -gt 0) {
            Write-Status "$($sp.Label)" "$($exeFiles.Count) executable(s) found (last 30 days)" "Yellow"
            foreach ($ef in $exeFiles | Select-Object -First 20) {
                [void]$cleanupItems.Add(@{
                    Location = $sp.Label
                    Name     = $ef.Name
                    Size     = "$([math]::Round($ef.Length / 1KB, 1)) KB"
                    Created  = $ef.CreationTime.ToString("yyyy-MM-dd HH:mm")
                })
            }
        } else {
            Write-Status "$($sp.Label)" "Clean - no recent executables" "Green"
        }
    }
}

# ═════════════════════════════════════════════════════════════════════════════
# 7. EVENT LOG ANALYSIS
# ═════════════════════════════════════════════════════════════════════════════
Write-Section "Event Log - Recent Software Installations"
$eventInstalls = New-Object System.Collections.ArrayList
Invoke-Safe {
    # MsiInstaller events (Event ID 1033 = install complete, 11707 = success)
    $events = Get-WinEvent -FilterHashtable @{
        LogName   = "Application"
        ID        = @(1033, 11707, 11724)
        StartTime = $thirtyDaysAgo
    } -MaxEvents 50 -ErrorAction SilentlyContinue

    foreach ($evt in $events) {
        [void]$eventInstalls.Add(@{
            Time    = $evt.TimeCreated.ToString("yyyy-MM-dd HH:mm")
            EventID = $evt.Id
            Message = ($evt.Message -split "`n" | Select-Object -First 1).Trim()
        })
    }
    Write-Status "Install Events" "$($eventInstalls.Count) software installation events (30 days)" "White"
}

# Also check for AppLocker / audit events
$securityEvents = New-Object System.Collections.ArrayList
Invoke-Safe {
    $sevts = Get-WinEvent -FilterHashtable @{
        LogName   = "System"
        Level     = @(2, 3)
        StartTime = (Get-Date).AddDays(-7)
    } -MaxEvents 20 -ErrorAction SilentlyContinue

    foreach ($se in $sevts) {
        if ($se.Message -match "install|software|update|driver" -and $se.Message -notmatch "Windows Update") {
            [void]$securityEvents.Add(@{
                Time    = $se.TimeCreated.ToString("yyyy-MM-dd HH:mm")
                Source  = $se.ProviderName
                Message = ($se.Message -split "`n" | Select-Object -First 1).Trim()
            })
        }
    }
}

# ═════════════════════════════════════════════════════════════════════════════
# 8. PHONE HOME DETECTION
# ═════════════════════════════════════════════════════════════════════════════
Write-Section "Phone Home Detection"
$phoneHome = New-Object System.Collections.ArrayList
Invoke-Safe {
    $suspiciousDomainKeywords = @(
        "support", "helpdesk", "remote", "assist", "teamviewer",
        "anydesk", "logmein", "gotomypc", "splashtop",
        "ammyy", "supremo", "connectwise"
    )

    $connections = Get-NetTCPConnection -State Established -ErrorAction SilentlyContinue |
        Where-Object { $_.RemoteAddress -ne "127.0.0.1" -and $_.RemoteAddress -ne "::1" -and $_.RemoteAddress -ne "0.0.0.0" }

    $scamProcessNames = @()
    foreach ($sf in $scamFound) {
        $procName = $sf.Name -replace '\s',''
        $scamProcessNames += $procName
    }

    foreach ($conn in $connections) {
        $proc = Invoke-Safe { (Get-Process -Id $conn.OwningProcess -ErrorAction SilentlyContinue).ProcessName } "Unknown"
        $procPath = Invoke-Safe { (Get-Process -Id $conn.OwningProcess -ErrorAction SilentlyContinue).Path } ""

        $isScamProc = $false
        foreach ($sp in $scamPatterns) {
            if ($proc -match [regex]::Escape(($sp.Pattern -replace '\s','')) -or ($procPath -and $procPath -match [regex]::Escape($sp.Pattern))) {
                $isScamProc = $true
                break
            }
        }

        if ($isScamProc) {
            [void]$phoneHome.Add(@{
                Process    = $proc
                PID        = $conn.OwningProcess
                RemoteAddr = "$($conn.RemoteAddress):$($conn.RemotePort)"
            })
            Add-Finding -Level "CRITICAL" -Category "Phone Home" -Name "Scam software $proc connecting to $($conn.RemoteAddress)" -Detail "Port: $($conn.RemotePort)"
        }
    }

    if ($phoneHome.Count -eq 0) {
        Write-Status "Result" "No scam software phone-home connections detected" "Green"
    }
}

# ═════════════════════════════════════════════════════════════════════════════
# 9. LOCK SCREEN / WALLPAPER CHANGES
# ═════════════════════════════════════════════════════════════════════════════
Write-Section "Lock Screen & Wallpaper Check"
$wallpaperData = Invoke-Safe {
    $result = @{}

    # Current wallpaper
    $wpPath = (Get-ItemProperty "HKCU:\Control Panel\Desktop" -ErrorAction SilentlyContinue).WallPaper
    $result.Wallpaper = if ($wpPath) { $wpPath } else { "Default" }

    # Check if wallpaper was recently changed
    if ($wpPath -and (Test-Path $wpPath)) {
        $wpFile = Get-Item $wpPath -ErrorAction SilentlyContinue
        $result.WallpaperModified = $wpFile.LastWriteTime.ToString("yyyy-MM-dd HH:mm")
        $isRecent = $wpFile.LastWriteTime -gt (Get-Date).AddDays(-7)
        if ($isRecent) {
            Add-Finding -Level "LOW" -Category "Wallpaper" -Name "Wallpaper was changed recently" -Detail "File: $wpPath | Modified: $($result.WallpaperModified)"
        }
    } else {
        $result.WallpaperModified = "N/A"
    }

    # Lock screen image
    $lockScreenPath = Invoke-Safe {
        $lsReg = Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization" -ErrorAction SilentlyContinue
        if ($lsReg.LockScreenImage) { $lsReg.LockScreenImage } else { "Default (Windows Spotlight)" }
    } "Default"
    $result.LockScreen = $lockScreenPath

    Write-Status "Wallpaper" $result.Wallpaper "White"
    Write-Status "Lock Screen" $result.LockScreen "White"
    return $result
} @{ Wallpaper = "N/A"; LockScreen = "N/A"; WallpaperModified = "N/A" }

# ═════════════════════════════════════════════════════════════════════════════
# 10. FAKE SUBSCRIPTION ALERTS
# ═════════════════════════════════════════════════════════════════════════════
Write-Section "Fake Subscription / Renewal Alert Check"
$fakeSubFindings = New-Object System.Collections.ArrayList
Invoke-Safe {
    # Check for suspicious notification/popup scheduled tasks
    $subTasks = Get-ScheduledTask -ErrorAction SilentlyContinue |
        Where-Object {
            $_.TaskName -match "norton|mcafee|geek.*squad|renewal|subscription|billing|refund|antivirus.*alert" -and
            $_.State -ne "Disabled"
        }
    foreach ($st in $subTasks) {
        [void]$fakeSubFindings.Add(@{ Type = "Scheduled Task"; Name = $st.TaskName; Detail = "Task path: $($st.TaskPath)" })
        Add-Finding -Level "HIGH" -Category "Fake Subscription" -Name "Suspicious renewal task: $($st.TaskName)" -Detail $st.TaskPath
    }

    # Check for suspicious startup entries
    $startupPaths = @(
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run",
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run",
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce",
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce"
    )
    foreach ($sPath in $startupPaths) {
        try {
            $entries = Get-ItemProperty $sPath -ErrorAction SilentlyContinue
            if ($entries) {
                $props = $entries.PSObject.Properties | Where-Object { $_.Name -notmatch "^PS" }
                foreach ($prop in $props) {
                    $val = "$($prop.Value)"
                    if ($val -match "norton|mcafee|geek.*squad|renewal|subscription|billing|support.*alert|antivirus.*expired") {
                        [void]$fakeSubFindings.Add(@{ Type = "Startup Entry"; Name = $prop.Name; Detail = $val })
                        Add-Finding -Level "HIGH" -Category "Fake Subscription" -Name "Suspicious startup: $($prop.Name)" -Detail $val
                    }
                }
            }
        } catch { }
    }

    # Check browser notification permissions (Chrome)
    $chromePrefs = Join-Path $env:LOCALAPPDATA "Google\Chrome\User Data\Default\Preferences"
    if (Test-Path $chromePrefs) {
        try {
            $prefsJson = Get-Content $chromePrefs -Raw -ErrorAction SilentlyContinue
            if ($prefsJson -match "norton|mcafee|geek.*squad|antivirus.*alert|virus.*detected|computer.*infected") {
                [void]$fakeSubFindings.Add(@{ Type = "Browser Data"; Name = "Chrome preferences contain scam keywords"; Detail = "Check notification permissions" })
                Add-Finding -Level "MEDIUM" -Category "Fake Subscription" -Name "Chrome preferences contain scam-related keywords" -Detail "Manual review recommended"
            }
        } catch { }
    }

    if ($fakeSubFindings.Count -eq 0) {
        Write-Status "Result" "No fake subscription/renewal indicators found" "Green"
    }
}

# ═════════════════════════════════════════════════════════════════════════════
# RISK ASSESSMENT
# ═════════════════════════════════════════════════════════════════════════════
$critCount  = ($findings | Where-Object { $_.Level -eq "CRITICAL" }).Count
$highCount  = ($findings | Where-Object { $_.Level -eq "HIGH" }).Count
$medCount   = ($findings | Where-Object { $_.Level -eq "MEDIUM" }).Count
$lowCount   = ($findings | Where-Object { $_.Level -eq "LOW" }).Count

$overallRisk = if ($critCount -gt 0) { "CRITICAL" }
    elseif ($highCount -gt 0)  { "HIGH" }
    elseif ($medCount -gt 0)   { "MEDIUM" }
    elseif ($lowCount -gt 0)   { "LOW" }
    else { "CLEAN" }

$riskColor = switch ($overallRisk) {
    "CRITICAL" { "#e74c3c" }
    "HIGH"     { "#e74c3c" }
    "MEDIUM"   { "#f39c12" }
    "LOW"      { "#f0ad4e" }
    "CLEAN"    { "#27ae60" }
}

$riskDescription = switch ($overallRisk) {
    "CRITICAL" { "Known scam software is actively running on this computer. Immediate action required." }
    "HIGH"     { "Known scam software or suspicious programs are installed. Removal recommended." }
    "MEDIUM"   { "Suspicious remote access tools or minor threats found. Review recommended." }
    "LOW"      { "Minor PUPs or low-risk items detected. Cleanup optional." }
    "CLEAN"    { "No scam indicators found. This computer appears clean." }
}

# ═════════════════════════════════════════════════════════════════════════════
# GENERATE HTML REPORT
# ═════════════════════════════════════════════════════════════════════════════
Write-Section "Generating HTML Report"

$scanEnd  = Get-Date
$duration = ($scanEnd - $scanStart).TotalSeconds

# Build findings table rows
$findingsRows = ""
foreach ($f in ($findings | Sort-Object { switch ($_.Level) { "CRITICAL" { 0 } "HIGH" { 1 } "MEDIUM" { 2 } "LOW" { 3 } } })) {
    $levelClass = switch ($f.Level) { "CRITICAL" { "level-critical" } "HIGH" { "level-high" } "MEDIUM" { "level-medium" } "LOW" { "level-low" } }
    $findingsRows += "<tr><td><span class=`"$levelClass`">$($f.Level)</span></td><td>$($f.Category)</td><td>$($f.Name)</td><td>$($f.Detail)</td></tr>`n"
}

# Build scam software rows
$scamRows = ""
foreach ($s in $scamFound) {
    $runClass = if ($s.Running) { "status-bad" } else { "" }
    $scamRows += "<tr class=`"$(if($s.Running){'fail'})`"><td>$($s.Name)</td><td>$($s.Category)</td><td>$($s.Publisher)</td><td>$($s.Version)</td><td class=`"$runClass`">$(if($s.Running){'YES - RUNNING'}else{'No'})</td></tr>`n"
}

# Build RAT rows
$ratRows = ""
foreach ($r in $ratFound) {
    $runClass = if ($r.Running) { "status-warn" } else { "" }
    $recentTag = if ($r.Recent) { " <span class='status-bad'>(RECENT)</span>" } else { "" }
    $ratRows += "<tr><td>$($r.Name)</td><td>$($r.Publisher)</td><td>$($r.InstallDate)$recentTag</td><td>$($r.Version)</td><td class=`"$runClass`">$(if($r.Running){'YES'}else{'No'})</td></tr>`n"
}

# Build recent installs rows
$recentRows = ""
foreach ($ri in $recentInstalls) {
    $recentRows += "<tr><td>$($ri.Date)</td><td>$($ri.Name)</td><td>$($ri.Publisher)</td><td>$($ri.Version)</td></tr>`n"
}

# Build suspicious tasks rows
$taskRows = ""
foreach ($t in $suspTasks) {
    $taskRows += "<tr><td>$($t.Name)</td><td>$($t.Path)</td><td>$($t.State)</td><td style='font-size:11px;word-break:break-all;'>$($t.Actions)</td></tr>`n"
}

# Build cleanup items rows
$cleanupRows = ""
foreach ($ci in $cleanupItems) {
    $cleanupRows += "<tr><td>$($ci.Location)</td><td>$($ci.Name)</td><td>$($ci.Size)</td><td>$($ci.Created)</td></tr>`n"
}

# Build event log rows
$eventRows = ""
foreach ($ei in $eventInstalls) {
    $eventRows += "<tr><td>$($ei.Time)</td><td>$($ei.EventID)</td><td style='font-size:11px;'>$([System.Web.HttpUtility]::HtmlEncode($ei.Message))</td></tr>`n"
}

# Build phone home rows
$phoneRows = ""
foreach ($ph in $phoneHome) {
    $phoneRows += "<tr class='fail'><td>$($ph.Process)</td><td>$($ph.PID)</td><td>$($ph.RemoteAddr)</td></tr>`n"
}

# Build fake subscription rows
$fakeSubRows = ""
foreach ($fs in $fakeSubFindings) {
    $fakeSubRows += "<tr><td>$($fs.Type)</td><td>$($fs.Name)</td><td style='font-size:11px;'>$($fs.Detail)</td></tr>`n"
}

$html = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>PC Plus Computing - Scam Protection Audit - $hostName</title>
<style>
  * { margin:0; padding:0; box-sizing:border-box; }
  body { font-family:'Segoe UI',Tahoma,Geneva,Verdana,sans-serif; background:#f4f6f9; color:#333; line-height:1.5; }
  .header { background:linear-gradient(135deg,#0a1628 0%,#1a2d4a 100%); color:#fff; padding:30px 40px; }
  .header h1 { font-size:24px; margin-bottom:4px; }
  .header .subtitle { color:#8899aa; font-size:13px; }
  .header .meta { display:flex; gap:30px; margin-top:12px; font-size:13px; color:#bbb; flex-wrap:wrap; }
  .header .brand { color:#2596be; font-weight:600; font-size:18px; margin-bottom:8px; }
  .container { max-width:1200px; margin:0 auto; padding:20px; }
  .section { background:#fff; border-radius:8px; box-shadow:0 1px 3px rgba(0,0,0,0.08); padding:24px; margin-bottom:20px; }
  .section h2 { font-size:18px; color:#0a1628; margin-bottom:16px; border-bottom:2px solid #2596be; padding-bottom:8px; }
  .card-row { display:flex; gap:16px; flex-wrap:wrap; }
  .card { flex:1; min-width:140px; background:#f8f9fc; border-radius:6px; padding:16px; text-align:center; border:1px solid #e8ecf1; }
  .card-label { font-size:11px; text-transform:uppercase; color:#888; letter-spacing:0.5px; margin-bottom:4px; }
  .card-value { font-size:20px; font-weight:700; color:#0a1628; }
  table { width:100%; border-collapse:collapse; font-size:13px; }
  th { background:#f0f2f5; text-align:left; padding:10px 12px; font-weight:600; color:#555; border-bottom:2px solid #ddd; }
  td { padding:8px 12px; border-bottom:1px solid #eee; }
  tr:hover { background:#f8f9fc; }
  tr.fail td { background:#fef5f5; }
  .status-ok { color:#27ae60; font-weight:600; }
  .status-warn { color:#f39c12; font-weight:600; }
  .status-bad { color:#e74c3c; font-weight:600; }
  .level-critical { background:#e74c3c; color:#fff; padding:2px 8px; border-radius:3px; font-weight:700; font-size:11px; }
  .level-high { background:#e74c3c; color:#fff; padding:2px 8px; border-radius:3px; font-weight:600; font-size:11px; }
  .level-medium { background:#f39c12; color:#fff; padding:2px 8px; border-radius:3px; font-weight:600; font-size:11px; }
  .level-low { background:#f0ad4e; color:#fff; padding:2px 8px; border-radius:3px; font-weight:600; font-size:11px; }
  .risk-badge { display:inline-block; padding:12px 30px; border-radius:25px; font-weight:700; font-size:22px; color:#fff; letter-spacing:1px; }
  .risk-desc { font-size:14px; color:#555; margin-top:10px; }
  .clean-badge { background:#27ae60; }
  .footer { text-align:center; padding:20px; color:#888; font-size:12px; border-top:1px solid #e0e0e0; margin-top:20px; }
  .footer a { color:#2596be; text-decoration:none; }
  @media print { body { background:#fff; } .section { box-shadow:none; border:1px solid #ddd; } }
</style>
</head>
<body>

<div class="header">
  <div class="brand">$COMPANY_NAME</div>
  <h1>Scam Protection Audit Report</h1>
  <div class="subtitle">Scam Software, Fake Support Tools &amp; PUP Detection</div>
  <div class="meta">
    <span>Computer: <strong>$hostName</strong></span>
    <span>Date: <strong>$scanDate</strong></span>
    <span>Duration: <strong>$([math]::Round($duration, 1))s</strong></span>
    <span>Programs Scanned: <strong>$($installedPrograms.Count)</strong></span>
  </div>
</div>

<div class="container">

<!-- Risk Assessment -->
<div class="section" style="text-align:center;">
  <h2>Overall Risk Assessment</h2>
  <div class="risk-badge" style="background:$riskColor;">$overallRisk</div>
  <div class="risk-desc">$riskDescription</div>
  <div class="card-row" style="margin-top:20px;">
    <div class="card"><div class="card-label">Critical</div><div class="card-value" style="color:#e74c3c;">$critCount</div></div>
    <div class="card"><div class="card-label">High</div><div class="card-value" style="color:#e74c3c;">$highCount</div></div>
    <div class="card"><div class="card-label">Medium</div><div class="card-value" style="color:#f39c12;">$medCount</div></div>
    <div class="card"><div class="card-label">Low</div><div class="card-value" style="color:#f0ad4e;">$lowCount</div></div>
    <div class="card"><div class="card-label">Total Findings</div><div class="card-value">$($findings.Count)</div></div>
  </div>
</div>

<!-- All Findings -->
$(if($findings.Count -gt 0){@"
<div class="section">
  <h2>All Findings ($($findings.Count))</h2>
  <table>
    <thead><tr><th style="width:80px">Risk</th><th style="width:140px">Category</th><th>Name</th><th>Detail</th></tr></thead>
    <tbody>$findingsRows</tbody>
  </table>
</div>
"@}else{@"
<div class="section" style="text-align:center;">
  <h2>Scan Results</h2>
  <p class="clean-badge status-ok" style="display:inline-block;padding:12px 30px;font-size:18px;background:#e8f5e9;border-radius:8px;">No scam indicators found. This computer appears clean.</p>
</div>
"@})

<!-- 1. Known Scam Software -->
<div class="section">
  <h2>1. Known Scam Software ($($scamFound.Count) found)</h2>
  $(if($scamFound.Count -gt 0){"<table><thead><tr><th>Program</th><th>Category</th><th>Publisher</th><th>Version</th><th>Running?</th></tr></thead><tbody>$scamRows</tbody></table>"}else{"<p class='status-ok'>No known scam software detected out of $($scamPatterns.Count) checked patterns.</p>"})
</div>

<!-- 2. Remote Access Tools -->
<div class="section">
  <h2>2. Remote Access Tools ($($ratFound.Count) found)</h2>
  $(if($ratFound.Count -gt 0){"<table><thead><tr><th>Program</th><th>Publisher</th><th>Install Date</th><th>Version</th><th>Running?</th></tr></thead><tbody>$ratRows</tbody></table>"}else{"<p class='status-ok'>No remote access tools detected.</p>"})
</div>

<!-- 3. Recent Installations -->
<div class="section">
  <h2>3. Recent Installations - Last 30 Days ($($recentInstalls.Count) programs)</h2>
  $(if($recentInstalls.Count -gt 0){"<table><thead><tr><th>Date</th><th>Program</th><th>Publisher</th><th>Version</th></tr></thead><tbody>$recentRows</tbody></table>"}else{"<p style='color:#888;'>No programs installed in the last 30 days.</p>"})
</div>

<!-- 4. Browser Scam Indicators -->
<div class="section">
  <h2>4. Browser Scam Indicators</h2>
  $(if($suspFiles.Count -gt 0){
    $sfRows = ""
    foreach($sf in $suspFiles){ $sfRows += "<tr><td>$($sf.Location)</td><td>$($sf.Name)</td><td>$($sf.Size)</td><td>$($sf.Created)</td></tr>`n" }
    "<h3 style='margin-bottom:8px;'>Suspicious Files in Downloads/Desktop</h3><table><thead><tr><th>Location</th><th>Filename</th><th>Size</th><th>Created</th></tr></thead><tbody>$sfRows</tbody></table>"
  }else{
    "<p class='status-ok'>No suspicious browser-related files found.</p>"
  })
  <div style="margin-top:12px;">
    <h3 style="margin-bottom:8px;">Browser History Databases</h3>
    $(if($browserFindings.Count -gt 0){
      $bfRows = ""
      foreach($bf in $browserFindings){ $bfRows += "<tr><td>$($bf.Browser)</td><td>$($bf.Status)</td></tr>`n" }
      "<table><thead><tr><th>Browser</th><th>Status</th></tr></thead><tbody>$bfRows</tbody></table>"
    }else{
      "<p style='color:#888;'>No browser history databases found.</p>"
    })
  </div>
</div>

<!-- 5. Suspicious Scheduled Tasks -->
<div class="section">
  <h2>5. Suspicious Scheduled Tasks ($($suspTasks.Count) found)</h2>
  $(if($suspTasks.Count -gt 0){"<table><thead><tr><th>Task Name</th><th>Path</th><th>State</th><th>Actions</th></tr></thead><tbody>$taskRows</tbody></table>"}else{"<p class='status-ok'>No suspicious scheduled tasks detected.</p>"})
</div>

<!-- 6. Desktop/Downloads Cleanup -->
<div class="section">
  <h2>6. Desktop &amp; Downloads Cleanup Check ($($cleanupItems.Count) executables)</h2>
  $(if($cleanupItems.Count -gt 0){"<table><thead><tr><th>Location</th><th>Filename</th><th>Size</th><th>Created</th></tr></thead><tbody>$cleanupRows</tbody></table>"}else{"<p class='status-ok'>No suspicious executables found in common locations.</p>"})
</div>

<!-- 7. Event Log Analysis -->
<div class="section">
  <h2>7. Event Log - Software Installation History ($($eventInstalls.Count) events)</h2>
  $(if($eventInstalls.Count -gt 0){"<table><thead><tr><th style='width:140px'>Time</th><th style='width:70px'>Event ID</th><th>Message</th></tr></thead><tbody>$eventRows</tbody></table>"}else{"<p style='color:#888;'>No recent software installation events found.</p>"})
</div>

<!-- 8. Phone Home Detection -->
<div class="section">
  <h2>8. Phone Home Detection</h2>
  $(if($phoneHome.Count -gt 0){"<table><thead><tr><th>Process</th><th>PID</th><th>Remote Address</th></tr></thead><tbody>$phoneRows</tbody></table>"}else{"<p class='status-ok'>No scam software phone-home connections detected.</p>"})
</div>

<!-- 9. Lock Screen / Wallpaper -->
<div class="section">
  <h2>9. Lock Screen &amp; Wallpaper Check</h2>
  <table>
    <thead><tr><th>Setting</th><th>Value</th></tr></thead>
    <tbody>
      <tr><td>Current Wallpaper</td><td style="font-size:11px;word-break:break-all;">$($wallpaperData.Wallpaper)</td></tr>
      <tr><td>Wallpaper Last Modified</td><td>$($wallpaperData.WallpaperModified)</td></tr>
      <tr><td>Lock Screen</td><td>$($wallpaperData.LockScreen)</td></tr>
    </tbody>
  </table>
</div>

<!-- 10. Fake Subscription Alerts -->
<div class="section">
  <h2>10. Fake Subscription / Renewal Alerts ($($fakeSubFindings.Count) found)</h2>
  $(if($fakeSubFindings.Count -gt 0){"<table><thead><tr><th>Type</th><th>Name</th><th>Detail</th></tr></thead><tbody>$fakeSubRows</tbody></table>"}else{"<p class='status-ok'>No fake subscription or renewal alert indicators found.</p>"})
</div>

</div>

<div class="footer">
  <strong>$COMPANY_NAME</strong> &mdash; $COMPANY_PHONE1 | $COMPANY_PHONE2 | <a href="https://$COMPANY_WEBSITE">$COMPANY_WEBSITE</a><br>
  Report generated: $scanDate | Duration: $([math]::Round($duration, 1))s | Patterns checked: $($scamPatterns.Count) | Programs scanned: $($installedPrograms.Count)<br>
  <em>If scam software was found, please contact us immediately for professional removal.</em>
</div>

</body>
</html>
"@

$reportFile = Join-Path $ReportDir "ScamProtectionAudit_${hostName}_$($scanStart.ToString('yyyyMMdd_HHmmss')).html"
try {
    $html | Out-File -FilePath $reportFile -Encoding UTF8 -Force
    Write-Host ""
    Write-Host "  Report saved: $reportFile" -ForegroundColor Green
} catch {
    Write-Host "  ERROR saving report: $($_.Exception.Message)" -ForegroundColor Red
}

# ─────────────────────────────────────────────────────────────────────────────
# SUMMARY
# ─────────────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "  ╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Magenta
Write-Host "  ║                    SCAN COMPLETE                            ║" -ForegroundColor Magenta
Write-Host "  ╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Magenta
$riskConsoleColor = switch ($overallRisk) { "CRITICAL" { "Red" } "HIGH" { "Red" } "MEDIUM" { "Yellow" } "LOW" { "Yellow" } "CLEAN" { "Green" } }
Write-Host "    Risk Level: " -NoNewline -ForegroundColor White
Write-Host $overallRisk -ForegroundColor $riskConsoleColor
Write-Host "    $riskDescription" -ForegroundColor DarkGray
Write-Host "    Scam Software: $($scamFound.Count) | RATs: $($ratFound.Count) | Tasks: $($suspTasks.Count) | Total Findings: $($findings.Count)" -ForegroundColor White
Write-Host "    Duration: $([math]::Round($duration, 1))s" -ForegroundColor White
Write-Host ""

# Open report
try { Start-Process $reportFile } catch { }

Write-Host "  Press Enter to exit..." -ForegroundColor DarkGray
Read-Host

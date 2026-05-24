#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    PC Plus 360 - RMM Security Watchdog
.DESCRIPTION
    Configurable-frequency security monitoring with ransomware and intrusion
    detection. Runs the full 41-check security audit plus real-time threat
    detection. Designed for Tactical RMM scheduled deployment.
.NOTES
    Company : PC Plus Computing
    Version : 1.0.0
    Website : pcpluscomputing.com
    Phone   : 604-760-1662
#>
param(
    [string]$UploadUrl    = "https://reports.pcpluscomputing.com/api/upload",
    [string]$ApiKey       = "",
    [string]$CustomerName = "",
    [string]$TechName     = "PC Plus RMM",
    [switch]$SkipUpload,
    [string]$OutputDir    = "C:\PCPlus360-Reports",
    [string]$CanaryDir    = "C:\PCPlus360-Canary",
    [switch]$Monitor,
    [int]$MonitorInterval = 60,
    [string]$EncryptPassword = ""
)

$ErrorActionPreference = "SilentlyContinue"
$ProgressPreference    = "SilentlyContinue"
$scanStart = Get-Date

function Invoke-Safe { param([scriptblock]$Block, $Default = $null); try { return (& $Block) } catch { return $Default } }

if (-not (Test-Path $OutputDir)) { New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null }

$stateFile = Join-Path $OutputDir "SecurityWatch-State.json"
$prevState = if (Test-Path $stateFile) { Get-Content $stateFile -Raw | ConvertFrom-Json } else { $null }

$alerts = [System.Collections.ArrayList]::new()
function Add-Alert {
    param([string]$Severity, [string]$Category, [string]$Message, [string]$Detail = "")
    [void]$alerts.Add(@{ Severity = $Severity; Category = $Category; Message = $Message; Detail = $Detail; Time = (Get-Date).ToString("HH:mm:ss") })
}

# ── Encrypted ZIP Creation for secure upload of findings ──
function New-EncryptedFindings {
    param(
        [string]$SourcePath,
        [string]$Password,
        [string]$OutDir
    )
    $zipPath = Join-Path $OutDir ("PCPlus360-SecFindings-" + $env:COMPUTERNAME + "-" + (Get-Date).ToString("yyyyMMdd-HHmmss") + ".zip")

    # Try 7-Zip first (supports AES-256 encryption)
    $sevenZipPaths = @(
        "${env:ProgramFiles}\7-Zip\7z.exe",
        "${env:ProgramFiles(x86)}\7-Zip\7z.exe"
    )
    $sevenZip = $null
    foreach ($szp in $sevenZipPaths) {
        if (Test-Path $szp) { $sevenZip = $szp; break }
    }

    if ($sevenZip) {
        $zipPath = $zipPath -replace '\.zip$', '.7z'
        $args7z = @("a", "-t7z", "-mhe=on", "-p$Password", $zipPath, $SourcePath)
        $proc = Start-Process -FilePath $sevenZip -ArgumentList $args7z -NoNewWindow -Wait -PassThru -RedirectStandardOutput ([IO.Path]::GetTempFileName()) -RedirectStandardError ([IO.Path]::GetTempFileName())
        if ($proc.ExitCode -eq 0 -and (Test-Path $zipPath)) {
            return @{ Success = $true; Path = $zipPath; Method = "7-Zip AES-256" }
        }
    }

    # Fallback: .NET ZipArchive (no native AES in .NET Framework 4.x, but we create
    # a standard ZIP and XOR-obfuscate the content as a basic protection layer)
    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop
        Add-Type -AssemblyName System.IO.Compression -ErrorAction Stop

        $zipPath = $zipPath -replace '\.7z$', '.zip'
        $fileBytes = [IO.File]::ReadAllBytes($SourcePath)

        # XOR obfuscation with password-derived key (basic protection for transit)
        $keyBytes = [Text.Encoding]::UTF8.GetBytes($Password)
        for ($i = 0; $i -lt $fileBytes.Length; $i++) {
            $fileBytes[$i] = $fileBytes[$i] -bxor $keyBytes[$i % $keyBytes.Length]
        }

        $zipStream = [IO.File]::Create($zipPath)
        $archive = New-Object System.IO.Compression.ZipArchive($zipStream, [System.IO.Compression.ZipArchiveMode]::Create)
        $entryName = [IO.Path]::GetFileName($SourcePath) + ".enc"
        $entry = $archive.CreateEntry($entryName, [System.IO.Compression.CompressionLevel]::Optimal)
        $entryStream = $entry.Open()
        $entryStream.Write($fileBytes, 0, $fileBytes.Length)
        $entryStream.Close()
        $archive.Dispose()
        $zipStream.Close()

        return @{ Success = $true; Path = $zipPath; Method = "ZipArchive+XOR" }
    } catch {
        return @{ Success = $false; Path = ""; Method = "Failed: $($_.Exception.Message)" }
    }
}

# ── Defender Threat Event Log Detection (last 24h) ──
function Get-DefenderThreatEvents {
    $threatEvents = @()
    try {
        # Windows Defender Operational log - threat detections (Event IDs: 1006=malware detected, 1116=threat detected, 1117=action taken)
        $defenderEvents = Get-WinEvent -FilterHashtable @{
            LogName   = 'Microsoft-Windows-Windows Defender/Operational'
            Id        = 1006,1007,1008,1009,1116,1117,1118,1119
            StartTime = (Get-Date).AddHours(-24)
        } -MaxEvents 25 -ErrorAction SilentlyContinue

        foreach ($evt in $defenderEvents) {
            $severity = switch ($evt.Id) {
                { $_ -in @(1006,1116) } { "CRITICAL" }
                { $_ -in @(1117,1118) } { "HIGH" }
                default { "MEDIUM" }
            }
            $action = switch ($evt.Id) {
                1006 { "Malware detected" }
                1007 { "Action taken on malware" }
                1008 { "Action failed" }
                1009 { "Item restored from quarantine" }
                1116 { "Threat detected" }
                1117 { "Protection action taken" }
                1118 { "Protection action failed" }
                1119 { "Protection action - critical failure" }
                default { "Defender event" }
            }
            $threatName = ""
            if ($evt.Message -match "Name:\s*(.+?)[\r\n]") { $threatName = $Matches[1].Trim() }
            elseif ($evt.Message -match "Threat Name:\s*(.+?)[\r\n]") { $threatName = $Matches[1].Trim() }

            $threatEvents += @{
                Time        = $evt.TimeCreated.ToString("yyyy-MM-dd HH:mm:ss")
                EventId     = $evt.Id
                Action      = $action
                ThreatName  = $threatName
                Severity    = $severity
                Message     = $evt.Message.Substring(0, [math]::Min($evt.Message.Length, 300))
            }
        }
    } catch {}
    return $threatEvents
}

# ═════════════════════════════════════════════════════════════════════════════
# PART 1: RANSOMWARE DETECTION
# ═════════════════════════════════════════════════════════════════════════════

# 1A. Honeypot Canary Files
$canaryResults = @{ Status = "OK"; Modified = @() }
Invoke-Safe {
    if (-not (Test-Path $CanaryDir)) {
        New-Item -ItemType Directory -Path $CanaryDir -Force | Out-Null
        attrib +h +s $CanaryDir 2>$null
    }

    $canaryFiles = @(
        @{ Name = "~budget_2024.xlsx"; Content = "PCPLUS360-CANARY-DO-NOT-DELETE-{0}" -f [guid]::NewGuid().ToString() },
        @{ Name = "~invoice_backup.docx"; Content = "PCPLUS360-CANARY-DO-NOT-DELETE-{0}" -f [guid]::NewGuid().ToString() },
        @{ Name = "~client_data.pdf"; Content = "PCPLUS360-CANARY-DO-NOT-DELETE-{0}" -f [guid]::NewGuid().ToString() },
        @{ Name = "~photos_2024.zip"; Content = "PCPLUS360-CANARY-DO-NOT-DELETE-{0}" -f [guid]::NewGuid().ToString() }
    )

    foreach ($cf in $canaryFiles) {
        $path = Join-Path $CanaryDir $cf.Name
        if (-not (Test-Path $path)) {
            $cf.Content | Out-File -FilePath $path -Encoding UTF8 -Force
            attrib +h $path 2>$null
        } else {
            $content = Get-Content $path -Raw -ErrorAction SilentlyContinue
            if (-not $content -or $content -notmatch "PCPLUS360-CANARY") {
                $canaryResults.Status = "ALERT"
                $canaryResults.Modified += $cf.Name
                Add-Alert "CRITICAL" "Ransomware" "Canary file modified: $($cf.Name)" "Honeypot file was altered - possible encryption in progress"
            }
        }
    }

    $missingCanaries = $canaryFiles | Where-Object { -not (Test-Path (Join-Path $CanaryDir $_.Name)) }
    if ($missingCanaries) {
        foreach ($mc in $missingCanaries) {
            $canaryResults.Status = "ALERT"
            $canaryResults.Modified += $mc.Name
            Add-Alert "CRITICAL" "Ransomware" "Canary file deleted: $($mc.Name)" "Honeypot file was removed - possible ransomware activity"
        }
    }
}

# 1B. Suspicious File Extensions (ransomware indicators)
$ransomwareExtensions = Invoke-Safe {
    $suspiciousExts = @("*.locked","*.encrypted","*.crypt","*.crypto","*.locky","*.cerber","*.zepto","*.odin","*.thor","*.zzzzz","*.micro","*.cryptolocker","*.cryptowall","*.crypz","*.ransom","*.r5a","*.WNCRY","*.wcry","*.wncrypt")
    $found = @()
    $searchPaths = @("$env:USERPROFILE\Desktop","$env:USERPROFILE\Documents","$env:USERPROFILE\Downloads")
    foreach ($sp in $searchPaths) {
        if (Test-Path $sp) {
            foreach ($ext in $suspiciousExts) {
                $matches = Get-ChildItem -Path $sp -Filter $ext -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 5
                foreach ($m in $matches) {
                    $found += @{ File = $m.FullName; Extension = $m.Extension; Modified = $m.LastWriteTime.ToString("yyyy-MM-dd HH:mm") }
                }
            }
        }
    }
    if ($found.Count -gt 0) {
        foreach ($f in $found) {
            Add-Alert "CRITICAL" "Ransomware" "Suspicious encrypted file: $($f.File)" "Extension $($f.Extension) detected"
        }
    }
    $found
} @()

# 1C. Shadow Copy Deletion Detection
$vssStatus = Invoke-Safe {
    $recent = Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='VSS'; Level=2,3; StartTime=(Get-Date).AddHours(-24)} -MaxEvents 5 -ErrorAction SilentlyContinue
    $deletions = Get-WinEvent -FilterHashtable @{LogName='Security'; Id=4688; StartTime=(Get-Date).AddHours(-24)} -MaxEvents 100 -ErrorAction SilentlyContinue |
        Where-Object { $_.Message -match "vssadmin.*delete|wmic.*shadowcopy.*delete|bcdedit.*recoveryenabled.*no|wbadmin.*delete" }
    if ($deletions) {
        foreach ($d in $deletions) {
            Add-Alert "CRITICAL" "Ransomware" "Shadow copy deletion attempt detected" $d.Message.Substring(0, [math]::Min($d.Message.Length, 200))
        }
        @{ Status = "ALERT"; Count = $deletions.Count }
    } else { @{ Status = "OK"; Count = 0 } }
} @{ Status = "OK"; Count = 0 }

# 1D. Suspicious Processes from Temp/AppData
$suspiciousProcs = Invoke-Safe {
    $found = @()
    Get-Process -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            $path = $_.Path
            if ($path -and ($path -match "\\Temp\\" -or $path -match "\\AppData\\Local\\Temp\\" -or $path -match "\\Downloads\\.*\.exe")) {
                $found += @{ Name = $_.ProcessName; PID = $_.Id; Path = $path; CPU = [math]::Round($_.CPU, 1) }
            }
        } catch {}
    }
    if ($found.Count -gt 3) {
        Add-Alert "HIGH" "Ransomware" "$($found.Count) processes running from Temp/Downloads" ($found | ForEach-Object { $_.Name } | Select-Object -First 5) -join ", "
    }
    $found
} @()

# 1E. Controlled Folder Access Status
$controlledFolderAccess = Invoke-Safe {
    $v = (Get-MpPreference -ErrorAction Stop).EnableControlledFolderAccess
    if ($v -ne 1 -and $v -ne 2) {
        Add-Alert "MEDIUM" "Ransomware" "Controlled Folder Access is disabled" "Enable in Windows Security > Virus & Threat Protection > Ransomware Protection"
    }
    $v -eq 1 -or $v -eq 2
} $false

# ═════════════════════════════════════════════════════════════════════════════
# PART 2: INTRUSION DETECTION
# ═════════════════════════════════════════════════════════════════════════════

# 2A. Failed Login Attempts (brute force)
$failedLogins = Invoke-Safe {
    $cutoff = (Get-Date).AddHours(-1)
    $events = Get-WinEvent -FilterHashtable @{LogName='Security'; Id=4625; StartTime=$cutoff} -ErrorAction SilentlyContinue
    $count = ($events | Measure-Object).Count
    $sources = @{}
    foreach ($e in $events) {
        $ip = if ($e.Message -match "Source Network Address:\s+(\S+)") { $Matches[1] } else { "Local" }
        if ($sources.ContainsKey($ip)) { $sources[$ip]++ } else { $sources[$ip] = 1 }
    }
    if ($count -ge 10) {
        $topSources = ($sources.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 3 | ForEach-Object { "$($_.Key): $($_.Value)" }) -join ", "
        Add-Alert "CRITICAL" "Intrusion" "$count failed logins in last hour - possible brute force" "Top sources: $topSources"
    } elseif ($count -ge 5) {
        Add-Alert "HIGH" "Intrusion" "$count failed logins in last hour" ""
    }
    @{ Count = $count; Sources = $sources }
} @{ Count = 0; Sources = @{} }

# 2B. New Admin Accounts (since last scan)
$adminAccounts = Invoke-Safe {
    $admins = Get-LocalGroupMember -Group "Administrators" -ErrorAction Stop
    $currentAdmins = @()
    foreach ($a in $admins) { $currentAdmins += $a.Name }

    if ($prevState -and $prevState.AdminAccounts) {
        $prevAdmins = @($prevState.AdminAccounts)
        $newAdmins = $currentAdmins | Where-Object { $_ -notin $prevAdmins }
        if ($newAdmins) {
            foreach ($na in $newAdmins) {
                Add-Alert "CRITICAL" "Intrusion" "New admin account detected: $na" "Account was added since last security scan"
            }
        }
    }
    $currentAdmins
} @()

# 2C. New Services Installed (since last scan)
$currentServices = Invoke-Safe {
    $svcs = Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.StartType -ne "Disabled" } | ForEach-Object { $_.Name }
    if ($prevState -and $prevState.Services) {
        $prevSvcs = @($prevState.Services)
        $newSvcs = $svcs | Where-Object { $_ -notin $prevSvcs }
        if ($newSvcs.Count -gt 0 -and $newSvcs.Count -lt 20) {
            foreach ($ns in $newSvcs) {
                $svc = Get-Service $ns -ErrorAction SilentlyContinue
                $path = (Get-CimInstance Win32_Service -Filter "Name='$ns'" -ErrorAction SilentlyContinue).PathName
                Add-Alert "HIGH" "Intrusion" "New service installed: $ns" "Path: $path"
            }
        }
    }
    $svcs
} @()

# 2D. Registry Run Key Changes (persistence)
$runKeyEntries = Invoke-Safe {
    $entries = @()
    $runKeys = @("HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run","HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run","HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run","HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce","HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce")
    foreach ($key in $runKeys) {
        if (Test-Path $key) {
            $props = Get-ItemProperty $key -ErrorAction SilentlyContinue
            $props.PSObject.Properties | Where-Object { $_.Name -notin @("PSPath","PSParentPath","PSChildName","PSDrive","PSProvider") } | ForEach-Object {
                $entries += "$($_.Name)=$($_.Value)"
            }
        }
    }

    if ($prevState -and $prevState.RunKeys) {
        $prevKeys = @($prevState.RunKeys)
        $newKeys = $entries | Where-Object { $_ -notin $prevKeys }
        if ($newKeys) {
            foreach ($nk in $newKeys) {
                $name = ($nk -split "=")[0]
                Add-Alert "HIGH" "Intrusion" "New startup entry: $name" $nk
            }
        }
    }
    $entries
} @()

# 2E. Suspicious Scheduled Tasks
$suspiciousTasks = Invoke-Safe {
    $found = @()
    Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.State -ne "Disabled" } | ForEach-Object {
        $task = $_
        foreach ($action in $task.Actions) {
            $exec = "$($action.Execute) $($action.Arguments)"
            if ($exec -match "\\Temp\\|\\AppData\\Local\\Temp|encodedcommand|encodedCommand|-enc\s|-ec\s|powershell.*-w\s*hidden|cmd.*\/c.*del|bitsadmin|certutil.*-urlcache|mshta|regsvr32.*\/s.*\/u|rundll32.*javascript") {
                $found += @{ TaskName = $task.TaskName; Command = $exec.Substring(0, [math]::Min($exec.Length, 150)); State = "$($task.State)" }
                Add-Alert "HIGH" "Intrusion" "Suspicious scheduled task: $($task.TaskName)" $exec.Substring(0, [math]::Min($exec.Length, 200))
            }
        }
    }
    $found
} @()

# 2F. RDP Session Monitoring
$rdpSessions = Invoke-Safe {
    $cutoff = (Get-Date).AddHours(-24)
    $logons = Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-TerminalServices-LocalSessionManager/Operational'; Id=21,25; StartTime=$cutoff} -MaxEvents 20 -ErrorAction SilentlyContinue
    $sessions = @()
    foreach ($l in $logons) {
        $user = if ($l.Message -match "User:\s+(\S+)") { $Matches[1] } else { "Unknown" }
        $ip = if ($l.Message -match "Source Network Address:\s+(\S+)") { $Matches[1] } else { "Local" }
        $sessions += @{ User = $user; IP = $ip; Time = $l.TimeCreated.ToString("yyyy-MM-dd HH:mm"); EventId = $l.Id }
    }
    if ($sessions.Count -gt 0) {
        $externalRDP = $sessions | Where-Object { $_.IP -ne "Local" -and $_.IP -ne "127.0.0.1" -and $_.IP -notmatch "^192\.168\." -and $_.IP -notmatch "^10\." -and $_.IP -notmatch "^172\.(1[6-9]|2[0-9]|3[01])\." }
        if ($externalRDP) {
            foreach ($r in $externalRDP) {
                Add-Alert "HIGH" "Intrusion" "External RDP session: $($r.User) from $($r.IP)" "At $($r.Time)"
            }
        }
    }
    $sessions
} @()

# 2G. Firewall Changes
$firewallStatus = Invoke-Safe {
    $fw = Get-NetFirewallProfile -ErrorAction Stop
    $disabled = $fw | Where-Object { -not $_.Enabled }
    if ($disabled) {
        foreach ($d in $disabled) {
            Add-Alert "CRITICAL" "Intrusion" "Firewall DISABLED on $($d.Name) profile" "Windows Firewall must be enabled on all profiles"
        }
    }
    @{
        Domain  = ($fw | Where-Object { $_.Name -eq "Domain" }).Enabled
        Private = ($fw | Where-Object { $_.Name -eq "Private" }).Enabled
        Public  = ($fw | Where-Object { $_.Name -eq "Public" }).Enabled
    }
} @{}

# 2H. PowerShell Encoded Commands (last 24h)
$encodedCommands = Invoke-Safe {
    $cutoff = (Get-Date).AddHours(-24)
    $events = Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-PowerShell/Operational'; Id=4104; StartTime=$cutoff} -MaxEvents 50 -ErrorAction SilentlyContinue
    $suspicious = @()
    foreach ($e in $events) {
        if ($e.Message -match "encodedcommand|FromBase64String|Invoke-Expression.*\[Convert\]|IEX.*Download|Net\.WebClient|Invoke-WebRequest.*\|.*IEX|Start-BitsTransfer.*-Source.*http") {
            $suspicious += @{ Time = $e.TimeCreated.ToString("HH:mm:ss"); Snippet = $e.Message.Substring(0, [math]::Min($e.Message.Length, 200)) }
        }
    }
    if ($suspicious.Count -gt 0) {
        Add-Alert "HIGH" "Intrusion" "$($suspicious.Count) suspicious PowerShell executions in 24h" ($suspicious | Select-Object -First 1).Snippet
    }
    $suspicious
} @()

# 2I. Defender Status
$defenderStatus = Invoke-Safe {
    $mp = Get-MpComputerStatus -ErrorAction Stop
    if (-not $mp.RealTimeProtectionEnabled) {
        Add-Alert "CRITICAL" "Security" "Windows Defender Real-Time Protection is DISABLED" ""
    }
    if ($mp.AntivirusSignatureAge -gt 3) {
        Add-Alert "HIGH" "Security" "Antivirus definitions are $($mp.AntivirusSignatureAge) days old" "Update Windows Defender definitions"
    }
    $threats = Get-MpThreatDetection -ErrorAction SilentlyContinue | Where-Object { $_.InitialDetectionTime -gt (Get-Date).AddHours(-24) }
    if ($threats) {
        foreach ($t in $threats) {
            Add-Alert "CRITICAL" "Security" "Threat detected: $($t.ThreatName)" "Action: $($t.ActionSuccess)"
        }
    }
    @{
        RealTime      = $mp.RealTimeProtectionEnabled
        DefAge        = $mp.AntivirusSignatureAge
        LastScan      = if ($mp.QuickScanEndTime) { $mp.QuickScanEndTime.ToString("yyyy-MM-dd HH:mm") } else { "Never" }
        ThreatsFound  = ($threats | Measure-Object).Count
    }
} @{ RealTime = $null; DefAge = $null; LastScan = "Unknown"; ThreatsFound = 0 }

# 2J. Defender Threat Event Log (detailed threat history)
$defenderThreatEvents = Get-DefenderThreatEvents
if ($defenderThreatEvents.Count -gt 0) {
    foreach ($dte in $defenderThreatEvents) {
        if ($dte.Severity -eq "CRITICAL") {
            Add-Alert "CRITICAL" "Defender" "$($dte.Action): $($dte.ThreatName)" "Event $($dte.EventId) at $($dte.Time)"
        } elseif ($dte.Severity -eq "HIGH") {
            Add-Alert "HIGH" "Defender" "$($dte.Action): $($dte.ThreatName)" "Event $($dte.EventId) at $($dte.Time)"
        } else {
            Add-Alert "MEDIUM" "Defender" "$($dte.Action)" "Event $($dte.EventId) at $($dte.Time)"
        }
    }
}

# ═════════════════════════════════════════════════════════════════════════════
# PART 3: FULL 41-CHECK SECURITY AUDIT
# ═════════════════════════════════════════════════════════════════════════════
$sec = @{}

$sec.Firewall = $firewallStatus

$sec.UAC = Invoke-Safe {
    $k = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
    @{ Enabled = (Get-ItemProperty $k -Name "EnableLUA" -ErrorAction Stop).EnableLUA -eq 1
       Level = (Get-ItemProperty $k -Name "ConsentPromptBehaviorAdmin" -ErrorAction Stop).ConsentPromptBehaviorAdmin }
} @{ Enabled = $null; Level = $null }

$sec.BitLocker = Invoke-Safe {
    $bl = @{}; Get-BitLockerVolume -ErrorAction Stop | ForEach-Object {
        $bl[$_.MountPoint] = @{ Status = $_.ProtectionStatus.ToString(); Encryption = $_.EncryptionPercentage }
    }; $bl
} @{}

$sec.SecureBoot = Invoke-Safe { Confirm-SecureBootUEFI -ErrorAction Stop } $null
$sec.TPM = Invoke-Safe {
    $tpm = Get-Tpm -ErrorAction Stop
    @{ Present = $tpm.TpmPresent; Ready = $tpm.TpmReady }
} @{ Present = $false; Ready = $false }

$sec.PasswordPolicy = Invoke-Safe {
    $na = net accounts 2>&1; $minLen = 0; $complexity = $false; $lockout = 0
    foreach ($l in $na) {
        if ($l -match "Minimum password length:\s+(\d+)") { $minLen = [int]$Matches[1] }
        if ($l -match "Lockout threshold:\s+(\w+)") { $lockout = if ($Matches[1] -eq "Never") { 0 } else { [int]$Matches[1] } }
    }
    $tmp = [IO.Path]::GetTempFileName(); secedit /export /cfg $tmp /quiet 2>$null
    if (Test-Path $tmp) { $c = Get-Content $tmp -Raw; if ($c -match "PasswordComplexity\s*=\s*1") { $complexity = $true }; Remove-Item $tmp -Force }
    @{ MinLength = $minLen; Complexity = $complexity; LockoutThreshold = $lockout }
} @{ MinLength = 0; Complexity = $false; LockoutThreshold = 0 }

$sec.GuestDisabled = Invoke-Safe { -not (Get-LocalUser -Name "Guest" -ErrorAction Stop).Enabled } $null
$sec.AutoLoginDisabled = Invoke-Safe { (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" -Name "AutoAdminLogon" -ErrorAction SilentlyContinue).AutoAdminLogon -ne "1" } $null

$sec.RDP = Invoke-Safe {
    $en = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server" -Name "fDenyTSConnections" -ErrorAction Stop).fDenyTSConnections -eq 0
    $nla = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" -Name "UserAuthentication" -ErrorAction SilentlyContinue).UserAuthentication -eq 1
    @{ Enabled = $en; NLA = $nla }
} @{ Enabled = $null; NLA = $null }

$sec.SMBv1Disabled = Invoke-Safe { -not (Get-SmbServerConfiguration -ErrorAction Stop).EnableSMB1Protocol } $null
$sec.LocalAdmins = Invoke-Safe { @{ Count = (Get-LocalGroupMember -Group "Administrators" -ErrorAction Stop).Count } } @{ Count = 0 }
$sec.DefenderRTP = Invoke-Safe { (Get-MpComputerStatus -ErrorAction Stop).RealTimeProtectionEnabled } $null
$sec.DefenderDefs = Invoke-Safe { (Get-MpComputerStatus -ErrorAction Stop).AntivirusSignatureAge -le 7 } $null
$sec.ThirdPartyAV = Invoke-Safe { @(Get-CimInstance -Namespace "root\SecurityCenter2" -ClassName AntiVirusProduct -ErrorAction Stop | Where-Object { $_.displayName -ne "Windows Defender" }).Count -gt 0 } $false

$sec.Privacy = @{}
$sec.Privacy.TelemetryMinimal = Invoke-Safe { $v = (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Name "AllowTelemetry" -ErrorAction SilentlyContinue).AllowTelemetry; $null -ne $v -and $v -le 1 } $false
$sec.Privacy.AdvertisingIdDisabled = Invoke-Safe { $v = (Get-ItemProperty "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo" -Name "Enabled" -ErrorAction SilentlyContinue).Enabled; $null -eq $v -or $v -ne 1 } $true
$sec.Privacy.LocationDisabled = Invoke-Safe { $v = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location" -Name "Value" -ErrorAction SilentlyContinue).Value; $v -eq "Deny" } $false
$sec.Privacy.ActivityHistoryDisabled = Invoke-Safe { $v = (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Name "PublishUserActivities" -ErrorAction SilentlyContinue).PublishUserActivities; $null -ne $v -and $v -ne 1 } $false
$sec.Privacy.CortanaDisabled = Invoke-Safe { $v = (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" -Name "AllowCortana" -ErrorAction SilentlyContinue).AllowCortana; $null -ne $v -and $v -eq 0 } $false
$sec.Privacy.FindMyDeviceEnabled = Invoke-Safe { $v = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Settings\FindMyDevice\UserConsent" -Name "Value" -ErrorAction SilentlyContinue).Value; $null -ne $v -and $v -eq 1 } $false

$sec.Browser = @{}
$sec.Browser.ChromeNoPwd = Invoke-Safe { $f = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Login Data"; -not (Test-Path $f) -or (Get-Item $f).Length -le 40960 } $true
$sec.Browser.EdgeNoPwd = Invoke-Safe { $f = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Login Data"; -not (Test-Path $f) -or (Get-Item $f).Length -le 40960 } $true
$sec.Browser.SmartScreen = Invoke-Safe { $v = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer" -Name "SmartScreenEnabled" -ErrorAction SilentlyContinue).SmartScreenEnabled; $null -eq $v -or $v -ne "Off" } $true
$sec.Browser.ExtOk = Invoke-Safe { $c = 0; @("$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Extensions","$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Extensions") | ForEach-Object { if (Test-Path $_) { $c += @(Get-ChildItem $_ -Directory).Count } }; $c -lt 15 } $true

$sec.NetHarden = @{}
$sec.NetHarden.NoOpenShares = Invoke-Safe { (Get-SmbShare | Where-Object { $_.Name -notmatch '^\w\$|^ADMIN\$|^IPC\$|^print\$' } | Measure-Object).Count -eq 0 } $null
$sec.NetHarden.UPnPDisabled = Invoke-Safe { (Get-Service "SSDPSRV" -ErrorAction Stop).Status -ne "Running" } $null
$sec.NetHarden.LLMNRDisabled = Invoke-Safe { $v = (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient" -Name "EnableMulticast" -ErrorAction SilentlyContinue).EnableMulticast; $null -ne $v -and $v -eq 0 } $false
$sec.NetHarden.DoHEnabled = Invoke-Safe { $v = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters" -Name "EnableAutoDoh" -ErrorAction SilentlyContinue).EnableAutoDoh; $null -ne $v -and $v -ge 2 } $false
$sec.NetHarden.RemAssistOff = Invoke-Safe { $v = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Remote Assistance" -Name "fAllowToGetHelp" -ErrorAction SilentlyContinue).fAllowToGetHelp; $null -ne $v -and $v -eq 0 } $false

$sec.Integrity = @{}
$sec.Integrity.DriverSig = Invoke-Safe { $b = bcdedit /enum "{current}" 2>&1 | Out-String; $b -notmatch "testsigning\s+Yes" } $true
$sec.Integrity.PSLogging = Invoke-Safe { $v = (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging" -Name "EnableScriptBlockLogging" -ErrorAction SilentlyContinue).EnableScriptBlockLogging; $null -ne $v -and $v -eq 1 } $false
$sec.Integrity.LogonAudit = Invoke-Safe { $o = auditpol /get /subcategory:"Logon" 2>&1 | Out-String; $o -match "Success" -and $o -notmatch "No Auditing" } $false
$sec.Integrity.CredGuard = Invoke-Safe { $dg = Get-CimInstance -ClassName Win32_DeviceGuard -Namespace "root\Microsoft\Windows\DeviceGuard" -ErrorAction Stop; $dg.SecurityServicesRunning -contains 1 } $false
$sec.Integrity.LSASS = Invoke-Safe { $v = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name "RunAsPPL" -ErrorAction SilentlyContinue).RunAsPPL; $null -ne $v -and $v -eq 1 } $false

$sec.Account = @{}
$sec.Account.NoStale = Invoke-Safe { $c = (Get-Date).AddDays(-90); (Get-LocalUser | Where-Object { $_.Enabled -and -not $_.SID.Value.EndsWith("-500") -and -not $_.SID.Value.EndsWith("-501") -and $null -ne $_.LastLogon -and $_.LastLogon -lt $c } | Measure-Object).Count -eq 0 } $true
$sec.Account.NoPwdEmpty = Invoke-Safe { (Get-LocalUser | Where-Object { $_.Enabled -and -not $_.PasswordRequired } | Measure-Object).Count -eq 0 } $true
$sec.Account.PwdAge = Invoke-Safe { $n = net accounts 2>&1 | Out-String; $n -notmatch "Maximum password age \(days\):\s+Unlimited" } $false

$sec.Ransom = @{}
$sec.Ransom.CFA = $controlledFolderAccess
$sec.Ransom.RestorePoint = Invoke-Safe { $c = (Get-Date).AddDays(-30); (Get-ComputerRestorePoint -ErrorAction Stop | Where-Object { [Management.ManagementDateTimeConverter]::ToDateTime($_.CreationTime) -gt $c } | Measure-Object).Count -gt 0 } $false
$sec.Ransom.NoSuspTasks = ($suspiciousTasks.Count -eq 0)

$missingPatches = Invoke-Safe {
    $session = New-Object -ComObject Microsoft.Update.Session
    $result = $session.CreateUpdateSearcher().Search("IsInstalled=0 AND Type='Software'")
    $patches = @()
    foreach ($u in $result.Updates) {
        $sev = if ($u.MsrcSeverity) { $u.MsrcSeverity } else { "Unknown" }
        $kb = @(); foreach ($k in $u.KBArticleIDs) { $kb += "KB$k" }
        $patches += @{ Title = $u.Title; KB = ($kb -join ", "); Severity = $sev }
    }
    $patches
} @()

# Scoring
$scoreChecks = @(
    @{ Name="Antivirus Active";         Pts=10; Pass=($sec.DefenderRTP -eq $true -or $sec.ThirdPartyAV) }
    @{ Name="Firewall All Profiles";    Pts=10; Pass=($sec.Firewall.Domain -and $sec.Firewall.Private -and $sec.Firewall.Public) }
    @{ Name="BitLocker on C:";          Pts=7;  Pass=($sec.BitLocker["C:"] -and $sec.BitLocker["C:"].Status -eq "On") }
    @{ Name="No Critical Patches";      Pts=7;  Pass=(($missingPatches | Where-Object { $_.Severity -eq "Critical" }).Count -eq 0) }
    @{ Name="UAC Enabled";              Pts=4;  Pass=($sec.UAC.Enabled -eq $true) }
    @{ Name="Secure Boot";              Pts=4;  Pass=($sec.SecureBoot -eq $true) }
    @{ Name="TPM Present";              Pts=4;  Pass=($sec.TPM.Present -eq $true) }
    @{ Name="Password Policy";          Pts=3;  Pass=($sec.PasswordPolicy.MinLength -ge 8 -or $sec.PasswordPolicy.Complexity) }
    @{ Name="Guest Disabled";           Pts=2;  Pass=($sec.GuestDisabled -eq $true) }
    @{ Name="No Auto-Login";            Pts=2;  Pass=($sec.AutoLoginDisabled -eq $true) }
    @{ Name="RDP Secure";               Pts=4;  Pass=($sec.RDP.Enabled -eq $false -or $sec.RDP.NLA -eq $true) }
    @{ Name="SMBv1 Disabled";           Pts=4;  Pass=($sec.SMBv1Disabled -eq $true) }
    @{ Name="Admin Accounts <=2";       Pts=3;  Pass=($sec.LocalAdmins.Count -le 2) }
    @{ Name="Real-Time Protection";     Pts=4;  Pass=($sec.DefenderRTP -eq $true) }
    @{ Name="AV Definitions Current";   Pts=3;  Pass=($sec.DefenderDefs -eq $true) }
    @{ Name="Telemetry Minimal";        Pts=1;  Pass=($sec.Privacy.TelemetryMinimal) }
    @{ Name="Advertising ID Off";       Pts=1;  Pass=($sec.Privacy.AdvertisingIdDisabled) }
    @{ Name="Location Off";             Pts=1;  Pass=($sec.Privacy.LocationDisabled) }
    @{ Name="Activity History Off";     Pts=1;  Pass=($sec.Privacy.ActivityHistoryDisabled) }
    @{ Name="Cortana/Copilot Off";      Pts=1;  Pass=($sec.Privacy.CortanaDisabled) }
    @{ Name="Find My Device On";        Pts=1;  Pass=($sec.Privacy.FindMyDeviceEnabled) }
    @{ Name="Chrome No Saved Pwd";      Pts=1;  Pass=($sec.Browser.ChromeNoPwd) }
    @{ Name="Edge No Saved Pwd";        Pts=1;  Pass=($sec.Browser.EdgeNoPwd) }
    @{ Name="SmartScreen Enabled";      Pts=1;  Pass=($sec.Browser.SmartScreen) }
    @{ Name="Browser Extensions <15";   Pts=1;  Pass=($sec.Browser.ExtOk) }
    @{ Name="No Open Shares";           Pts=1;  Pass=($sec.NetHarden.NoOpenShares -eq $true) }
    @{ Name="UPnP Disabled";            Pts=1;  Pass=($sec.NetHarden.UPnPDisabled -eq $true) }
    @{ Name="LLMNR Disabled";           Pts=1;  Pass=($sec.NetHarden.LLMNRDisabled) }
    @{ Name="DNS-over-HTTPS";           Pts=1;  Pass=($sec.NetHarden.DoHEnabled) }
    @{ Name="Remote Assistance Off";    Pts=1;  Pass=($sec.NetHarden.RemAssistOff) }
    @{ Name="Driver Sig Enforced";      Pts=1;  Pass=($sec.Integrity.DriverSig) }
    @{ Name="PS Script Logging";        Pts=1;  Pass=($sec.Integrity.PSLogging) }
    @{ Name="Logon Audit Enabled";      Pts=1;  Pass=($sec.Integrity.LogonAudit) }
    @{ Name="Credential Guard";         Pts=1;  Pass=($sec.Integrity.CredGuard) }
    @{ Name="LSASS Protected";          Pts=1;  Pass=($sec.Integrity.LSASS) }
    @{ Name="No Stale Accounts";        Pts=1;  Pass=($sec.Account.NoStale) }
    @{ Name="No Empty Passwords";       Pts=1;  Pass=($sec.Account.NoPwdEmpty) }
    @{ Name="Password Age Policy";      Pts=1;  Pass=($sec.Account.PwdAge) }
    @{ Name="Controlled Folder Access"; Pts=2;  Pass=($sec.Ransom.CFA) }
    @{ Name="Recent Restore Point";     Pts=2;  Pass=($sec.Ransom.RestorePoint) }
    @{ Name="No Suspicious Tasks";      Pts=2;  Pass=($sec.Ransom.NoSuspTasks) }
)

$secScore = 0; $secBreakdown = @(); $critFails = @()
foreach ($c in $scoreChecks) {
    if ($c.Pass) { $secScore += $c.Pts } elseif ($c.Pts -ge 4) { $critFails += $c.Name }
    $secBreakdown += @{ Check = $c.Name; Points = $c.Pts; Passed = $c.Pass }
}
$secGrade = if ($secScore -ge 90) {"A"} elseif ($secScore -ge 80) {"B"} elseif ($secScore -ge 70) {"C"} elseif ($secScore -ge 60) {"D"} else {"F"}
$secColor = if ($secGrade -in @("A","B")) {"#27ae60"} elseif ($secGrade -in @("C","D")) {"#f39c12"} else {"#e74c3c"}

$passedCount = ($secBreakdown | Where-Object { $_.Passed }).Count
$failedCount = ($secBreakdown | Where-Object { -not $_.Passed }).Count

# ═════════════════════════════════════════════════════════════════════════════
# PART 4: SAVE STATE FOR NEXT RUN
# ═════════════════════════════════════════════════════════════════════════════
$newState = @{
    LastRun       = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    AdminAccounts = $adminAccounts
    Services      = $currentServices
    RunKeys       = $runKeyEntries
    SecurityScore = $secScore
}
$newState | ConvertTo-Json -Depth 3 | Out-File -FilePath $stateFile -Encoding UTF8 -Force

# ═════════════════════════════════════════════════════════════════════════════
# PART 5: HTML REPORT
# ═════════════════════════════════════════════════════════════════════════════
$scanDate  = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
$dateStamp = (Get-Date).ToString("yyyyMMdd-HHmmss")
$reportFile = Join-Path $OutputDir "PCPlus360-SecWatch-$($env:COMPUTERNAME)-$dateStamp.html"

$criticalAlerts = $alerts | Where-Object { $_.Severity -eq "CRITICAL" }
$highAlerts     = $alerts | Where-Object { $_.Severity -eq "HIGH" }
$mediumAlerts   = $alerts | Where-Object { $_.Severity -eq "MEDIUM" }
$totalAlerts    = $alerts.Count

$threatLevel = if ($criticalAlerts.Count -gt 0) { "CRITICAL" } elseif ($highAlerts.Count -gt 0) { "ELEVATED" } elseif ($mediumAlerts.Count -gt 0) { "ADVISORY" } else { "CLEAR" }
$threatColor = switch ($threatLevel) { "CRITICAL" { "#e74c3c" }; "ELEVATED" { "#e67e22" }; "ADVISORY" { "#f39c12" }; default { "#27ae60" } }

$alertRowsHtml = ""
foreach ($a in ($alerts | Sort-Object { switch($_.Severity){"CRITICAL"{0};"HIGH"{1};"MEDIUM"{2};default{3}} })) {
    $sevColor = switch ($a.Severity) { "CRITICAL" { "#e74c3c" }; "HIGH" { "#e67e22" }; "MEDIUM" { "#f39c12" }; default { "#666" } }
    $alertRowsHtml += "<tr><td style=`"color:${sevColor};font-weight:700`">$($a.Severity)</td><td>$($a.Category)</td><td>$($a.Message)</td><td style=`"font-size:11px;color:#666`">$($a.Detail)</td><td>$($a.Time)</td></tr>`n"
}
if (-not $alertRowsHtml) { $alertRowsHtml = "<tr><td colspan=`"5`" style=`"text-align:center;color:#27ae60;font-weight:600`">No threats detected - all clear</td></tr>" }

$secRowsHtml = ""
foreach ($item in $secBreakdown) {
    $icon = if ($item.Passed) { "&#9989;" } else { "&#10060;" }
    $cls  = if ($item.Passed) { "pass" } else { "fail" }
    $secRowsHtml += "<tr class=`"$cls`"><td>$icon</td><td>$($item.Check)</td><td>$($item.Points) pts</td><td>$(if($item.Passed){'PASS'}else{'FAIL'})</td></tr>`n"
}

$pctAngle = [math]::Round($secScore * 3.6, 1)
$largeArc = if ($pctAngle -gt 180) { 1 } else { 0 }
$radians  = $pctAngle * [math]::PI / 180
$endX     = [math]::Round(50 + 40 * [math]::Sin($radians), 2)
$endY     = [math]::Round(50 - 40 * [math]::Cos($radians), 2)
$arcPath  = if ($secScore -ge 100) { "M 50 10 A 40 40 0 1 1 49.99 10" } else { "M 50 10 A 40 40 0 $largeArc 1 $endX $endY" }

$html = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>PC Plus 360 - Security Watchdog - $($env:COMPUTERNAME)</title>
<style>
  * { margin:0; padding:0; box-sizing:border-box; }
  body { font-family:'Segoe UI',Tahoma,sans-serif; background:#f4f6f9; color:#333; line-height:1.5; }
  .header { background:linear-gradient(135deg,#0a3d5c 0%,#0d4b71 50%,#1a2d4a 100%); color:#fff; padding:24px 40px; }
  .header .brand { font-size:18px; font-weight:700; color:#2596be; }
  .header .tagline { font-size:10px; text-transform:uppercase; letter-spacing:2px; opacity:0.6; }
  .header h1 { font-size:22px; margin:8px 0 4px; }
  .header .meta { display:flex; gap:24px; font-size:13px; color:#bbb; flex-wrap:wrap; }
  .threat-banner { padding:16px 40px; font-size:16px; font-weight:700; color:white; display:flex; align-items:center; gap:12px; background:$threatColor; }
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
  <div class="tagline">Your Security, Our Priority</div>
  <h1>&#128737; Security Watchdog Report</h1>
  <div class="meta">
    <span>Computer: <strong>$($env:COMPUTERNAME)</strong></span>
    <span>Customer: <strong>$(if($CustomerName){$CustomerName}else{'N/A'})</strong></span>
    <span>Scan: <strong>$scanDate</strong></span>
  </div>
</div>

<div class="threat-banner">
  $(switch($threatLevel){ "CRITICAL"{"&#9888; THREAT LEVEL: CRITICAL - Immediate action required"}; "ELEVATED"{"&#9888; THREAT LEVEL: ELEVATED - Review recommended"}; "ADVISORY"{"&#128276; THREAT LEVEL: ADVISORY - Minor issues found"}; default{"&#9989; THREAT LEVEL: CLEAR - No threats detected"} })
</div>

<div class="container">

<!-- Alert Summary -->
<div class="section">
  <h2>&#128680; Threat Alerts ($totalAlerts)</h2>
  <div class="card-row" style="margin-bottom:14px">
    <div class="card"><div class="card-label">Critical</div><div class="card-value" style="color:#e74c3c">$($criticalAlerts.Count)</div></div>
    <div class="card"><div class="card-label">High</div><div class="card-value" style="color:#e67e22">$($highAlerts.Count)</div></div>
    <div class="card"><div class="card-label">Medium</div><div class="card-value" style="color:#f39c12">$($mediumAlerts.Count)</div></div>
    <div class="card"><div class="card-label">Threat Level</div><div class="card-value" style="color:$threatColor">$threatLevel</div></div>
  </div>
  <table>
    <thead><tr><th>Severity</th><th>Category</th><th>Alert</th><th>Detail</th><th>Time</th></tr></thead>
    <tbody>$alertRowsHtml</tbody>
  </table>
</div>

<!-- Ransomware Status -->
<div class="section">
  <h2>&#128274; Ransomware Protection</h2>
  <div class="card-row">
    <div class="card"><div class="card-label">Canary Files</div><div class="card-value" style="color:$(if($canaryResults.Status -eq 'OK'){'#27ae60'}else{'#e74c3c'})">$($canaryResults.Status)</div></div>
    <div class="card"><div class="card-label">Suspicious Files</div><div class="card-value">$($ransomwareExtensions.Count)</div></div>
    <div class="card"><div class="card-label">VSS Deletions</div><div class="card-value" style="color:$(if($vssStatus.Count -eq 0){'#27ae60'}else{'#e74c3c'})">$($vssStatus.Count)</div></div>
    <div class="card"><div class="card-label">Controlled Folders</div><div class="card-value" style="color:$(if($controlledFolderAccess){'#27ae60'}else{'#e74c3c'})">$(if($controlledFolderAccess){'ON'}else{'OFF'})</div></div>
    <div class="card"><div class="card-label">Suspicious Procs</div><div class="card-value">$($suspiciousProcs.Count)</div></div>
  </div>
</div>

<!-- Intrusion Detection -->
<div class="section">
  <h2>&#128373; Intrusion Detection</h2>
  <div class="card-row">
    <div class="card"><div class="card-label">Failed Logins (1h)</div><div class="card-value" style="color:$(if($failedLogins.Count -ge 10){'#e74c3c'}elseif($failedLogins.Count -ge 5){'#e67e22'}else{'#27ae60'})">$($failedLogins.Count)</div></div>
    <div class="card"><div class="card-label">RDP Sessions (24h)</div><div class="card-value">$($rdpSessions.Count)</div></div>
    <div class="card"><div class="card-label">Encoded PS (24h)</div><div class="card-value" style="color:$(if($encodedCommands.Count -gt 0){'#e74c3c'}else{'#27ae60'})">$($encodedCommands.Count)</div></div>
    <div class="card"><div class="card-label">Suspicious Tasks</div><div class="card-value" style="color:$(if($suspiciousTasks.Count -gt 0){'#e74c3c'}else{'#27ae60'})">$($suspiciousTasks.Count)</div></div>
    <div class="card"><div class="card-label">Threats (24h)</div><div class="card-value" style="color:$(if($defenderStatus.ThreatsFound -gt 0){'#e74c3c'}else{'#27ae60'})">$($defenderStatus.ThreatsFound)</div></div>
  </div>
</div>

<!-- Defender -->
<div class="section">
  <h2>&#128737; Defender Status</h2>
  <div class="card-row">
    <div class="card"><div class="card-label">Real-Time</div><div class="card-value" style="color:$(if($defenderStatus.RealTime){'#27ae60'}else{'#e74c3c'})">$(if($defenderStatus.RealTime){'ON'}else{'OFF'})</div></div>
    <div class="card"><div class="card-label">Definitions Age</div><div class="card-value" style="color:$(if($defenderStatus.DefAge -le 3){'#27ae60'}elseif($defenderStatus.DefAge -le 7){'#f39c12'}else{'#e74c3c'})">$($defenderStatus.DefAge) days</div></div>
    <div class="card"><div class="card-label">Last Scan</div><div class="card-value" style="font-size:12px">$($defenderStatus.LastScan)</div></div>
    <div class="card"><div class="card-label">Firewall</div><div class="card-value" style="color:$(if($sec.Firewall.Domain -and $sec.Firewall.Private -and $sec.Firewall.Public){'#27ae60'}else{'#e74c3c'})">$(if($sec.Firewall.Domain -and $sec.Firewall.Private -and $sec.Firewall.Public){'ALL ON'}else{'CHECK'})</div></div>
  </div>
</div>

<!-- Security Score -->
<div class="section">
  <h2>&#128202; Security Audit Score</h2>
  <div class="score-section">
    <svg viewBox="0 0 100 100" width="150" height="150">
      <circle cx="50" cy="50" r="40" fill="none" stroke="#e0e0e0" stroke-width="8"/>
      <path d="$arcPath" fill="none" stroke="$secColor" stroke-width="8" stroke-linecap="round"/>
      <text x="50" y="44" text-anchor="middle" font-size="22" font-weight="bold" fill="$secColor">$secScore</text>
      <text x="50" y="58" text-anchor="middle" font-size="10" fill="#666">/ 100</text>
      <text x="50" y="72" text-anchor="middle" font-size="16" font-weight="bold" fill="$secColor">$secGrade</text>
    </svg>
    <div><strong>$passedCount</strong> of <strong>$($secBreakdown.Count)</strong> checks passed | Missing patches: <strong>$($missingPatches.Count)</strong></div>
  </div>
</div>

<!-- Full Audit Breakdown -->
<div class="section">
  <h2>Security Audit - 41 Checks</h2>
  <table>
    <thead><tr><th style="width:30px"></th><th>Check</th><th>Weight</th><th>Result</th></tr></thead>
    <tbody>$secRowsHtml</tbody>
  </table>
</div>

<div class="footer">
  <strong>PC Plus Computing</strong> | pcpluscomputing.com | 604-760-1662 | 236-500-2700<br>
  PC Plus 360 Security Watchdog v1.0.0 | $scanDate
</div>

</div>
</body>
</html>
"@

$html | Out-File -FilePath $reportFile -Encoding UTF8 -Force

# ═════════════════════════════════════════════════════════════════════════════
# PART 6: AUTO-UPLOAD
# ═════════════════════════════════════════════════════════════════════════════
$uploaded = $false; $uploadMsg = ""
if (-not $SkipUpload -and -not [string]::IsNullOrWhiteSpace($UploadUrl)) {
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls11
        $boundary = [System.Guid]::NewGuid().ToString("N"); $LF = "`r`n"
        $fileName = [IO.Path]::GetFileName($reportFile)
        $fileBytes = [IO.File]::ReadAllBytes($reportFile)
        $fields = @{ customer_name = $CustomerName; computer_name = $env:COMPUTERNAME; tech_name = $TechName; scan_mode = "Security Watchdog"; scan_date = $scanDate; file_type = "HTML"; source = "rmm-security"; security_score = "$secScore"; security_grade = $secGrade; threat_level = $threatLevel; alert_count = "$totalAlerts" }
        $bodyParts = [System.Collections.ArrayList]::new()
        foreach ($key in $fields.Keys) { [void]$bodyParts.Add("--$boundary$LF"); [void]$bodyParts.Add("Content-Disposition: form-data; name=`"$key`"$LF$LF"); [void]$bodyParts.Add("$($fields[$key])$LF") }
        $fileHeader = "--$boundary${LF}Content-Disposition: form-data; name=`"report_file`"; filename=`"$fileName`"${LF}Content-Type: text/html${LF}${LF}"
        $fileFooter = "${LF}--${boundary}--${LF}"
        $enc = [Text.Encoding]::UTF8
        $bodyStream = [IO.MemoryStream]::new()
        $bytes = $enc.GetBytes(($bodyParts -join "")); $bodyStream.Write($bytes, 0, $bytes.Length)
        $bytes = $enc.GetBytes($fileHeader); $bodyStream.Write($bytes, 0, $bytes.Length)
        $bodyStream.Write($fileBytes, 0, $fileBytes.Length)
        $bytes = $enc.GetBytes($fileFooter); $bodyStream.Write($bytes, 0, $bytes.Length)
        $fullBody = $bodyStream.ToArray(); $bodyStream.Close()
        $headers = @{ "Content-Type" = "multipart/form-data; boundary=$boundary" }
        if (-not [string]::IsNullOrWhiteSpace($ApiKey)) { $headers["Authorization"] = "Bearer $ApiKey" }
        Invoke-RestMethod -Uri $UploadUrl -Method Post -Headers $headers -Body $fullBody -ContentType "multipart/form-data; boundary=$boundary" -TimeoutSec 60 -ErrorAction Stop | Out-Null
        $uploaded = $true; $uploadMsg = "Upload successful"
    } catch { $uploaded = $false; $uploadMsg = "Upload failed: $($_.Exception.Message)" }
} else { $uploadMsg = if ($SkipUpload) { "Skipped" } else { "No URL" } }

# ═════════════════════════════════════════════════════════════════════════════
# PART 7: JSON SUMMARY
# ═════════════════════════════════════════════════════════════════════════════
$scanEnd = Get-Date
$summary = @{
    computer        = $env:COMPUTERNAME
    threat_level    = $threatLevel
    alerts_critical = $criticalAlerts.Count
    alerts_high     = $highAlerts.Count
    alerts_medium   = $mediumAlerts.Count
    alerts_total    = $totalAlerts
    security_score  = $secScore
    security_grade  = $secGrade
    passed_checks   = $passedCount
    failed_checks   = $failedCount
    canary_status   = $canaryResults.Status
    failed_logins   = $failedLogins.Count
    threats_found   = $defenderStatus.ThreatsFound
    defender_rtp    = $defenderStatus.RealTime
    defender_age    = $defenderStatus.DefAge
    missing_patches = $missingPatches.Count
    report_path     = $reportFile
    uploaded        = $uploaded
    scan_seconds    = [math]::Round(($scanEnd - $scanStart).TotalSeconds, 0)
}

# Add Defender threat event details to summary
$summary["defender_threat_events"] = $defenderThreatEvents.Count

# Add severity breakdown per finding
$findingSeverities = @{
    CRITICAL = @($alerts | Where-Object { $_.Severity -eq "CRITICAL" }).Count
    HIGH     = @($alerts | Where-Object { $_.Severity -eq "HIGH" }).Count
    MEDIUM   = @($alerts | Where-Object { $_.Severity -eq "MEDIUM" }).Count
    INFO     = @($alerts | Where-Object { $_.Severity -eq "INFO" }).Count
}
$summary["severity_breakdown"] = $findingSeverities

# ── Encrypted Upload Preparation ──
$encryptedResult = @{ Success = $false; Path = ""; Method = "Skipped" }
if ($EncryptPassword -and $EncryptPassword.Length -gt 0 -and (Test-Path $reportFile)) {
    $encryptedResult = New-EncryptedFindings -SourcePath $reportFile -Password $EncryptPassword -OutDir $OutputDir
    $summary["encrypted_archive"] = $encryptedResult.Path
    $summary["encryption_method"] = $encryptedResult.Method
}

$summary | ConvertTo-Json -Depth 4 -Compress | Write-Output

# ═════════════════════════════════════════════════════════════════════════════
# PART 8: REAL-TIME MONITORING MODE (-Monitor switch)
# ═════════════════════════════════════════════════════════════════════════════
if ($Monitor) {
    # Output initial scan results, then enter monitoring loop
    $lastEventTime = Get-Date
    $monitorIteration = 0

    while ($true) {
        Start-Sleep -Seconds $MonitorInterval
        $monitorIteration++
        $newAlerts = [System.Collections.ArrayList]::new()

        # Check for new security events since last check
        $checkSince = $lastEventTime

        # New failed logins
        $newFailedLogins = Invoke-Safe {
            $events = Get-WinEvent -FilterHashtable @{LogName='Security'; Id=4625; StartTime=$checkSince} -MaxEvents 20 -ErrorAction SilentlyContinue
            ($events | Measure-Object).Count
        } 0
        if ($newFailedLogins -ge 5) {
            [void]$newAlerts.Add(@{ Severity = "CRITICAL"; Category = "Intrusion"; Message = "$newFailedLogins new failed logins"; Time = (Get-Date).ToString("HH:mm:ss") })
        }

        # Defender real-time status change
        $currentRTP = Invoke-Safe { (Get-MpComputerStatus -ErrorAction Stop).RealTimeProtectionEnabled } $null
        if ($currentRTP -eq $false) {
            [void]$newAlerts.Add(@{ Severity = "CRITICAL"; Category = "Security"; Message = "Defender Real-Time Protection OFF"; Time = (Get-Date).ToString("HH:mm:ss") })
        }

        # New Defender threat detections
        $newThreats = Invoke-Safe {
            Get-WinEvent -FilterHashtable @{
                LogName   = 'Microsoft-Windows-Windows Defender/Operational'
                Id        = 1006,1116,1117
                StartTime = $checkSince
            } -MaxEvents 10 -ErrorAction SilentlyContinue
        } @()
        foreach ($nt in $newThreats) {
            $tName = ""
            if ($nt.Message -match "Name:\s*(.+?)[\r\n]") { $tName = $Matches[1].Trim() }
            [void]$newAlerts.Add(@{ Severity = "CRITICAL"; Category = "Defender"; Message = "Threat detected: $tName"; Time = $nt.TimeCreated.ToString("HH:mm:ss") })
        }

        # Canary file integrity check
        $canaryCheck = Invoke-Safe {
            $canaryFiles = @("~budget_2024.xlsx","~invoice_backup.docx","~client_data.pdf","~photos_2024.zip")
            foreach ($cf in $canaryFiles) {
                $path = Join-Path $CanaryDir $cf
                if (Test-Path $path) {
                    $content = Get-Content $path -Raw -ErrorAction SilentlyContinue
                    if (-not $content -or $content -notmatch "PCPLUS360-CANARY") {
                        return "MODIFIED: $cf"
                    }
                } else {
                    return "MISSING: $cf"
                }
            }
            return "OK"
        } "OK"
        if ($canaryCheck -ne "OK") {
            [void]$newAlerts.Add(@{ Severity = "CRITICAL"; Category = "Ransomware"; Message = "Canary file $canaryCheck"; Time = (Get-Date).ToString("HH:mm:ss") })
        }

        # Firewall profile check
        $fwCheck = Invoke-Safe {
            $fw = Get-NetFirewallProfile -ErrorAction Stop
            $disabled = $fw | Where-Object { -not $_.Enabled }
            if ($disabled) { ($disabled | ForEach-Object { $_.Name }) -join ", " } else { "OK" }
        } "OK"
        if ($fwCheck -ne "OK") {
            [void]$newAlerts.Add(@{ Severity = "CRITICAL"; Category = "Security"; Message = "Firewall disabled on: $fwCheck"; Time = (Get-Date).ToString("HH:mm:ss") })
        }

        # Output new findings only (as JSON lines)
        if ($newAlerts.Count -gt 0) {
            $monitorOutput = @{
                monitor_iteration = $monitorIteration
                timestamp         = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
                new_alerts        = @($newAlerts)
                alert_count       = $newAlerts.Count
            }
            $monitorOutput | ConvertTo-Json -Depth 3 -Compress | Write-Output
        }

        $lastEventTime = Get-Date
    }
}

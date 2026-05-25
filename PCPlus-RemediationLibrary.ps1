param(
    [switch]$ReadOnly,
    [switch]$NoRestorePoint,
    [string]$LogPath
)

<#
.SYNOPSIS
    PC Plus Computing - Remediation Library (Fix Center)
.DESCRIPTION
    WPF-based remediation toolkit for common Windows issues. Categories include
    Windows Repair, Network Fixes, Security Fixes, Performance Fixes, Printer
    Fixes, and PC Plus internal tools. Each fix runs with optional restore point
    creation, real-time output logging, and PASS/FAIL result tracking.

    Commands are data-driven from remediation-commands.json. Techs can add/edit
    custom commands via the UI which are persisted to the JSON config.
.NOTES
    Company:  PC Plus Computing
    Website:  pcpluscomputing.com
    Phone:    604-760-1662 | 236-500-2700
    Version:  2.0.0
    Requires: PowerShell 5.1+, Windows 10/11, Administrator privileges
#>

#Requires -Version 5.1

$ErrorActionPreference = 'Continue'

# ─────────────────────────────────────────────────────────────────────────────
# GLOBALS
# ─────────────────────────────────────────────────────────────────────────────
$Global:ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
if ([string]::IsNullOrEmpty($Global:ScriptDir)) { $Global:ScriptDir = Get-Location }

$Global:DebugLogPath = Join-Path $Global:ScriptDir "PCPlus-RemediationLibrary-debug.log"
$Global:RemediationLogPath = if ($LogPath) { $LogPath } else { Join-Path $Global:ScriptDir "remediation-log.txt" }
$Global:ReportsDir = Join-Path $Global:ScriptDir "reports"
$Global:IsReadOnly = $ReadOnly.IsPresent
$Global:CreateRestorePoint = (-not $NoRestorePoint.IsPresent)
$Global:CommandsJsonPath = Join-Path $Global:ScriptDir "remediation-commands.json"

if (-not (Test-Path $Global:ReportsDir)) { New-Item -Path $Global:ReportsDir -ItemType Directory -Force | Out-Null }

# ─────────────────────────────────────────────────────────────────────────────
# DEBUG LOG
# ─────────────────────────────────────────────────────────────────────────────
function Write-DebugLog {
    param([string]$Msg)
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "[$ts] $Msg" | Out-File -FilePath $Global:DebugLogPath -Append -Encoding UTF8
}

Write-DebugLog "Script starting..."
Write-DebugLog "PowerShell version: $($PSVersionTable.PSVersion)"
Write-DebugLog "Script path: $($MyInvocation.MyCommand.Definition)"
Write-DebugLog "Current user: $env:USERNAME"
Write-DebugLog "ScriptDir: $Global:ScriptDir"

# ─────────────────────────────────────────────────────────────────────────────
# ASSEMBLIES
# ─────────────────────────────────────────────────────────────────────────────
Write-DebugLog "Loading assemblies..."
try {
    Add-Type -AssemblyName PresentationFramework
    Add-Type -AssemblyName PresentationCore
    Add-Type -AssemblyName WindowsBase
    Add-Type -AssemblyName System.Windows.Forms
    Write-DebugLog "Assemblies loaded OK"
} catch {
    Write-DebugLog "Assembly load FAILED: $($_.Exception.Message)"
    exit 1
}

# ─────────────────────────────────────────────────────────────────────────────
# ELEVATION CHECK
# ─────────────────────────────────────────────────────────────────────────────
function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

$Global:IsAdmin = Test-IsAdmin
Write-DebugLog "Is Admin: $Global:IsAdmin"

if (-not $Global:IsAdmin) {
    Write-DebugLog "Not admin - attempting elevation..."
    try {
        $scriptPath = $MyInvocation.MyCommand.Definition
        $argString = "-STA -NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""
        if ($ReadOnly) { $argString += " -ReadOnly" }
        if ($NoRestorePoint) { $argString += " -NoRestorePoint" }
        if ($LogPath) { $argString += " -LogPath `"$LogPath`"" }
        Start-Process powershell.exe -ArgumentList $argString -Verb RunAs
        Write-DebugLog "Elevation launched OK"
    } catch {
        Write-DebugLog "Elevation FAILED: $($_.Exception.Message)"
        [System.Windows.MessageBox]::Show(
            "This tool requires Administrator privileges.`n`n$($_.Exception.Message)",
            "PC Plus 360 - Remediation Library - Elevation Required",
            "OK", "Warning"
        )
    }
    exit
}

Write-DebugLog "Running as admin, continuing..."

# ─────────────────────────────────────────────────────────────────────────────
# BRANDING
# ─────────────────────────────────────────────────────────────────────────────
$COMPANY      = "PC Plus Computing"
$PHONE        = "604-760-1662 | 236-500-2700"
$WEBSITE      = "pcpluscomputing.com"
$VERSION      = "2.0.0"

# ─────────────────────────────────────────────────────────────────────────────
# REMEDIATION LOG
# ─────────────────────────────────────────────────────────────────────────────
function Write-RemediationLog {
    param([string]$Message, [string]$Level = "INFO")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts] [$Level] $Message"
    Add-Content -Path $Global:RemediationLogPath -Value $line -ErrorAction SilentlyContinue
    Write-DebugLog "$Level : $Message"
}

# ─────────────────────────────────────────────────────────────────────────────
# BUILT-IN SCRIPTBLOCKS (keyed by command id)
# These are the original 20 command implementations. When a command has
# builtin=true and a matching id, the engine uses these instead of evaluating
# the "command" field directly.
# ─────────────────────────────────────────────────────────────────────────────
$Global:BuiltinScriptBlocks = @{

    "sfc_scan" = {
        Write-Output "Starting System File Checker..."
        $output = & sfc /scannow 2>&1
        $output | ForEach-Object { Write-Output $_ }
        if ($LASTEXITCODE -eq 0 -or $null -eq $LASTEXITCODE) {
            Write-Output "`n[RESULT] SFC scan completed successfully."
            return $true
        } else {
            Write-Output "`n[RESULT] SFC scan reported issues. Review output above."
            return $false
        }
    }

    "dism_repair" = {
        Write-Output "Starting DISM online repair..."
        $output = & DISM /Online /Cleanup-Image /RestoreHealth 2>&1
        $output | ForEach-Object { Write-Output $_ }
        if ($LASTEXITCODE -eq 0) {
            Write-Output "`n[RESULT] DISM repair completed successfully."
            return $true
        } else {
            Write-Output "`n[RESULT] DISM repair encountered issues."
            return $false
        }
    }

    "wu_reset" = {
        Write-Output "Stopping Windows Update services..."
        $services = @('wuauserv', 'cryptSvc', 'bits', 'msiserver')
        foreach ($svc in $services) {
            try {
                Stop-Service -Name $svc -Force -ErrorAction Stop
                Write-Output "  Stopped: $svc"
            } catch {
                Write-Output "  Warning: Could not stop $svc - $($_.Exception.Message)"
            }
        }

        Write-Output "`nRenaming SoftwareDistribution folder..."
        $sdPath = "$env:SystemRoot\SoftwareDistribution"
        $sdBackup = "$env:SystemRoot\SoftwareDistribution.old_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        if (Test-Path $sdPath) {
            try {
                Rename-Item -Path $sdPath -NewName (Split-Path $sdBackup -Leaf) -Force -ErrorAction Stop
                Write-Output "  Renamed to: $(Split-Path $sdBackup -Leaf)"
            } catch {
                Write-Output "  Warning: Could not rename SoftwareDistribution - $($_.Exception.Message)"
            }
        }

        Write-Output "Renaming catroot2 folder..."
        $crPath = "$env:SystemRoot\System32\catroot2"
        $crBackup = "$env:SystemRoot\System32\catroot2.old_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        if (Test-Path $crPath) {
            try {
                Rename-Item -Path $crPath -NewName (Split-Path $crBackup -Leaf) -Force -ErrorAction Stop
                Write-Output "  Renamed to: $(Split-Path $crBackup -Leaf)"
            } catch {
                Write-Output "  Warning: Could not rename catroot2 - $($_.Exception.Message)"
            }
        }

        Write-Output "`nRestarting Windows Update services..."
        foreach ($svc in $services) {
            try {
                Start-Service -Name $svc -ErrorAction Stop
                Write-Output "  Started: $svc"
            } catch {
                Write-Output "  Warning: Could not start $svc - $($_.Exception.Message)"
            }
        }

        Write-Output "`n[RESULT] Windows Update reset completed."
        return $true
    }

    "store_repair" = {
        Write-Output "Re-registering all Windows Store apps..."
        try {
            $packages = Get-AppXPackage -ErrorAction Stop
            $total = $packages.Count
            $current = 0
            $errors = 0
            foreach ($pkg in $packages) {
                $current++
                $manifest = "$($pkg.InstallLocation)\AppXManifest.xml"
                if (Test-Path $manifest) {
                    try {
                        Add-AppxPackage -DisableDevelopmentMode -Register $manifest -ErrorAction Stop
                    } catch {
                        $errors++
                    }
                }
                if ($current % 20 -eq 0) {
                    Write-Output "  Progress: $current / $total packages processed..."
                }
            }
            Write-Output "`n[RESULT] Store App Repair completed. $total packages processed, $errors errors."
            return ($errors -lt ($total / 2))
        } catch {
            Write-Output "[RESULT] Store App Repair failed: $($_.Exception.Message)"
            return $false
        }
    }

    "flush_dns" = {
        Write-Output "Flushing DNS resolver cache..."
        $output = & ipconfig /flushdns 2>&1
        $output | ForEach-Object { Write-Output $_ }
        Write-Output "`n[RESULT] DNS cache flushed successfully."
        return $true
    }

    "reset_winsock" = {
        Write-Output "Resetting Winsock catalog..."
        $output = & netsh winsock reset 2>&1
        $output | ForEach-Object { Write-Output $_ }
        Write-Output "`nNOTE: A system reboot is required for changes to take effect."
        Write-Output "[RESULT] Winsock reset completed. Please reboot."
        return $true
    }

    "reset_tcpip" = {
        Write-Output "Resetting TCP/IP stack..."
        $output = & netsh int ip reset 2>&1
        $output | ForEach-Object { Write-Output $_ }
        Write-Output "`nNOTE: A system reboot is required for changes to take effect."
        Write-Output "[RESULT] TCP/IP reset completed. Please reboot."
        return $true
    }

    "renew_ip" = {
        Write-Output "Releasing IP address..."
        $output = & ipconfig /release 2>&1
        $output | ForEach-Object { Write-Output $_ }
        Write-Output "`nRenewing IP address..."
        $output2 = & ipconfig /renew 2>&1
        $output2 | ForEach-Object { Write-Output $_ }
        Write-Output "`n[RESULT] IP release/renew completed."
        return $true
    }

    "enable_defender" = {
        Write-Output "Checking Windows Defender status..."
        try {
            $mpPref = Get-MpPreference -ErrorAction Stop
            $currentState = -not $mpPref.DisableRealtimeMonitoring
            Write-Output "  Current Real-time Monitoring: $(if ($currentState) { 'ENABLED' } else { 'DISABLED' })"
            if (-not $currentState) {
                Write-Output "`nEnabling Real-time Monitoring..."
                Set-MpPreference -DisableRealtimeMonitoring $false -ErrorAction Stop
                Write-Output "[RESULT] Windows Defender Real-time Monitoring has been ENABLED."
            } else {
                Write-Output "`n[RESULT] Windows Defender Real-time Monitoring is already enabled."
            }
            return $true
        } catch {
            Write-Output "[RESULT] Failed to configure Defender: $($_.Exception.Message)"
            return $false
        }
    }

    "update_defender" = {
        Write-Output "Updating Windows Defender signatures..."
        try {
            Update-MpSignature -ErrorAction Stop
            $sig = Get-MpComputerStatus -ErrorAction SilentlyContinue
            if ($sig) {
                Write-Output "  Antivirus Signature Version: $($sig.AntivirusSignatureVersion)"
                Write-Output "  Last Updated: $($sig.AntivirusSignatureLastUpdated)"
            }
            Write-Output "`n[RESULT] Defender signatures updated successfully."
            return $true
        } catch {
            Write-Output "[RESULT] Failed to update signatures: $($_.Exception.Message)"
            return $false
        }
    }

    "enable_firewall" = {
        Write-Output "Checking firewall status..."
        try {
            $profiles = Get-NetFirewallProfile -ErrorAction Stop
            foreach ($p in $profiles) {
                Write-Output "  $($p.Name) profile: $(if ($p.Enabled) { 'ENABLED' } else { 'DISABLED' })"
            }
            Write-Output "`nEnabling firewall for all profiles..."
            Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled True -ErrorAction Stop
            Write-Output "[RESULT] Windows Firewall enabled for all profiles."
            return $true
        } catch {
            Write-Output "[RESULT] Failed to configure firewall: $($_.Exception.Message)"
            return $false
        }
    }

    "check_bitlocker" = {
        Write-Output "Checking BitLocker status for all volumes..."
        try {
            $volumes = Get-BitLockerVolume -ErrorAction Stop
            foreach ($vol in $volumes) {
                Write-Output "`n  Drive: $($vol.MountPoint)"
                Write-Output "    Protection Status: $($vol.ProtectionStatus)"
                Write-Output "    Encryption Method: $($vol.EncryptionMethod)"
                Write-Output "    Volume Status: $($vol.VolumeStatus)"
                Write-Output "    Lock Status: $($vol.LockStatus)"
                Write-Output "    Key Protectors: $(($vol.KeyProtector | ForEach-Object { $_.KeyProtectorType }) -join ', ')"
            }
            Write-Output "`n[RESULT] BitLocker status check completed."
            return $true
        } catch {
            Write-Output "[RESULT] BitLocker check failed: $($_.Exception.Message)"
            Write-Output "  Note: BitLocker may not be available on this Windows edition."
            return $false
        }
    }

    "clean_temp" = {
        $totalRemoved = 0

        Write-Output "Cleaning user temp folder ($env:TEMP)..."
        if (Test-Path $env:TEMP) {
            $items = Get-ChildItem -Path $env:TEMP -Recurse -Force -ErrorAction SilentlyContinue
            $count = 0
            foreach ($item in $items) {
                try {
                    Remove-Item -Path $item.FullName -Recurse -Force -ErrorAction Stop
                    $count++
                } catch { }
            }
            Write-Output "  Removed $count items from user temp."
            $totalRemoved += $count
        }

        Write-Output "Cleaning system temp folder (C:\Windows\Temp)..."
        $sysTemp = "C:\Windows\Temp"
        if (Test-Path $sysTemp) {
            $items = Get-ChildItem -Path $sysTemp -Recurse -Force -ErrorAction SilentlyContinue
            $count = 0
            foreach ($item in $items) {
                try {
                    Remove-Item -Path $item.FullName -Recurse -Force -ErrorAction Stop
                    $count++
                } catch { }
            }
            Write-Output "  Removed $count items from system temp."
            $totalRemoved += $count
        }

        Write-Output "`nRunning Disk Cleanup (cleanmgr) silently..."
        try {
            # Set all cleanup options via registry
            $cleanupKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches"
            if (Test-Path $cleanupKey) {
                $subkeys = Get-ChildItem -Path $cleanupKey -ErrorAction SilentlyContinue
                foreach ($sk in $subkeys) {
                    Set-ItemProperty -Path $sk.PSPath -Name "StateFlags0100" -Value 2 -ErrorAction SilentlyContinue
                }
            }
            Start-Process -FilePath "cleanmgr.exe" -ArgumentList "/sagerun:100" -Wait -NoNewWindow -ErrorAction Stop
            Write-Output "  Disk Cleanup completed."
        } catch {
            Write-Output "  Disk Cleanup could not run: $($_.Exception.Message)"
        }

        Write-Output "`n[RESULT] Temp cleanup completed. $totalRemoved items removed."
        return $true
    }

    "disable_startup" = {
        Write-Output "Scanning startup programs...`n"

        # Registry run keys
        $locations = @(
            @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"; Scope = "Machine" }
            @{ Path = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"; Scope = "User" }
            @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce"; Scope = "Machine (RunOnce)" }
        )

        $startupItems = @()
        foreach ($loc in $locations) {
            if (Test-Path $loc.Path) {
                $props = Get-ItemProperty -Path $loc.Path -ErrorAction SilentlyContinue
                if ($props) {
                    $names = $props.PSObject.Properties | Where-Object { $_.Name -notin @('PSPath','PSParentPath','PSChildName','PSDrive','PSProvider') }
                    foreach ($n in $names) {
                        $startupItems += [PSCustomObject]@{
                            Name    = $n.Name
                            Command = $n.Value
                            Scope   = $loc.Scope
                            Source  = "Registry"
                        }
                    }
                }
            }
        }

        # Startup folder
        $startupFolder = [System.IO.Path]::Combine($env:APPDATA, "Microsoft\Windows\Start Menu\Programs\Startup")
        if (Test-Path $startupFolder) {
            $files = Get-ChildItem -Path $startupFolder -ErrorAction SilentlyContinue
            foreach ($f in $files) {
                $startupItems += [PSCustomObject]@{
                    Name    = $f.BaseName
                    Command = $f.FullName
                    Scope   = "User"
                    Source  = "Startup Folder"
                }
            }
        }

        # Scheduled tasks at logon
        try {
            $tasks = Get-ScheduledTask -ErrorAction SilentlyContinue |
                Where-Object { $_.Triggers | Where-Object { $_.CimClass.CimClassName -eq 'MSFT_TaskLogonTrigger' } }
            foreach ($t in $tasks) {
                $startupItems += [PSCustomObject]@{
                    Name    = $t.TaskName
                    Command = ($t.Actions | ForEach-Object { $_.Execute }) -join "; "
                    Scope   = "System"
                    Source  = "Scheduled Task"
                }
            }
        } catch { }

        if ($startupItems.Count -eq 0) {
            Write-Output "No startup items found."
        } else {
            Write-Output "Found $($startupItems.Count) startup items:`n"
            Write-Output ("{0,-30} {1,-10} {2,-12} {3}" -f "NAME", "SCOPE", "SOURCE", "COMMAND")
            Write-Output ("{0,-30} {1,-10} {2,-12} {3}" -f "----", "-----", "------", "-------")
            foreach ($item in $startupItems) {
                $name = if ($item.Name.Length -gt 28) { $item.Name.Substring(0, 28) + ".." } else { $item.Name }
                $cmd  = if ($item.Command.Length -gt 60) { $item.Command.Substring(0, 60) + "..." } else { $item.Command }
                Write-Output ("{0,-30} {1,-10} {2,-12} {3}" -f $name, $item.Scope, $item.Source, $cmd)
            }
        }

        Write-Output "`n[RESULT] Startup scan completed. $($startupItems.Count) items found."
        return $true
    }

    "disk_health" = {
        Write-Output "Running disk health check on C: drive..."
        Write-Output "This may take several minutes.`n"
        $output = & chkdsk C: /scan 2>&1
        $output | ForEach-Object { Write-Output $_ }
        Write-Output "`n[RESULT] Disk health check completed."
        return $true
    }

    "restart_spooler" = {
        Write-Output "Restarting Print Spooler service..."
        try {
            Restart-Service -Name Spooler -Force -ErrorAction Stop
            $svc = Get-Service -Name Spooler
            Write-Output "  Spooler status: $($svc.Status)"
            Write-Output "`n[RESULT] Print Spooler restarted successfully."
            return $true
        } catch {
            Write-Output "[RESULT] Failed to restart Print Spooler: $($_.Exception.Message)"
            return $false
        }
    }

    "clear_print_queue" = {
        Write-Output "Stopping Print Spooler..."
        try {
            Stop-Service -Name Spooler -Force -ErrorAction Stop
            Write-Output "  Spooler stopped."
        } catch {
            Write-Output "  Warning: Could not stop Spooler - $($_.Exception.Message)"
        }

        Write-Output "Clearing print queue files..."
        $spoolPath = "C:\Windows\System32\spool\PRINTERS"
        if (Test-Path $spoolPath) {
            $files = Get-ChildItem -Path "$spoolPath\*" -Force -ErrorAction SilentlyContinue
            $count = 0
            foreach ($f in $files) {
                try {
                    Remove-Item -Path $f.FullName -Force -ErrorAction Stop
                    $count++
                } catch { }
            }
            Write-Output "  Removed $count files from print queue."
        } else {
            Write-Output "  Spool folder not found at expected path."
        }

        Write-Output "Starting Print Spooler..."
        try {
            Start-Service -Name Spooler -ErrorAction Stop
            Write-Output "  Spooler started."
            Write-Output "`n[RESULT] Print queue cleared and spooler restarted."
            return $true
        } catch {
            Write-Output "[RESULT] Spooler could not be restarted: $($_.Exception.Message)"
            return $false
        }
    }

    "run_audit" = {
        $auditScript = Join-Path $Global:ScriptDir "PCPlus-SecurityAudit.ps1"
        if (Test-Path $auditScript) {
            Write-Output "Launching PCPlus-SecurityAudit.ps1..."
            try {
                Start-Process powershell.exe -ArgumentList "-STA -NoProfile -ExecutionPolicy Bypass -File `"$auditScript`"" -Verb RunAs
                Write-Output "[RESULT] Security Audit launched in a new window."
                return $true
            } catch {
                Write-Output "[RESULT] Failed to launch audit: $($_.Exception.Message)"
                return $false
            }
        } else {
            Write-Output "[RESULT] PCPlus-SecurityAudit.ps1 not found at: $auditScript"
            Write-Output "  Make sure the audit script is in the same folder as this tool."
            return $false
        }
    }

    "install_badge" = {
        Write-Output "PC Plus Support Badge Deployment"
        Write-Output "================================"
        Write-Output ""
        Write-Output "This feature will deploy the PC Plus support badge"
        Write-Output "that provides quick access to:"
        Write-Output "  - Remote support session"
        Write-Output "  - Service request portal"
        Write-Output "  - Knowledge base"
        Write-Output "  - Contact information"
        Write-Output ""
        Write-Output "[RESULT] Support Badge deployment is a placeholder for future release."
        return $true
    }

    "security_bulletin" = {
        Write-Output "============================================="
        Write-Output "  PC PLUS COMPUTING - SECURITY BULLETIN"
        Write-Output "  $(Get-Date -Format 'MMMM yyyy')"
        Write-Output "============================================="
        Write-Output ""
        Write-Output "CURRENT ADVISORIES:"
        Write-Output ""
        Write-Output "1. WINDOWS UPDATES"
        Write-Output "   Ensure all Windows updates are installed."

        try {
            $hotfixes = Get-HotFix -ErrorAction SilentlyContinue | Sort-Object InstalledOn -Descending | Select-Object -First 3
            if ($hotfixes) {
                Write-Output "   Latest installed updates:"
                foreach ($hf in $hotfixes) {
                    Write-Output "     - $($hf.HotFixID) ($(if ($hf.InstalledOn) { $hf.InstalledOn.ToString('yyyy-MM-dd') } else { 'Unknown date' }))"
                }
            }
        } catch { }

        Write-Output ""
        Write-Output "2. ANTIVIRUS STATUS"
        try {
            $mpStatus = Get-MpComputerStatus -ErrorAction Stop
            Write-Output "   Real-time Protection: $(if ($mpStatus.RealTimeProtectionEnabled) { 'ENABLED' } else { 'DISABLED - ACTION REQUIRED' })"
            Write-Output "   Signature Version: $($mpStatus.AntivirusSignatureVersion)"
            Write-Output "   Last Updated: $($mpStatus.AntivirusSignatureLastUpdated)"
        } catch {
            Write-Output "   Could not retrieve Defender status."
        }

        Write-Output ""
        Write-Output "3. FIREWALL STATUS"
        try {
            $fwProfiles = Get-NetFirewallProfile -ErrorAction Stop
            foreach ($p in $fwProfiles) {
                $status = if ($p.Enabled) { "ENABLED" } else { "DISABLED - ACTION REQUIRED" }
                Write-Output "   $($p.Name) Profile: $status"
            }
        } catch {
            Write-Output "   Could not retrieve firewall status."
        }

        Write-Output ""
        Write-Output "4. RECOMMENDATIONS"
        Write-Output "   - Keep Windows and all drivers up to date"
        Write-Output "   - Use strong, unique passwords for all accounts"
        Write-Output "   - Enable BitLocker encryption on all drives"
        Write-Output "   - Schedule regular backups (local + cloud)"
        Write-Output "   - Be cautious of phishing emails and suspicious links"
        Write-Output ""
        Write-Output "CONTACT: $PHONE"
        Write-Output "WEB:     $WEBSITE"
        Write-Output ""
        Write-Output "[RESULT] Security bulletin displayed."
        return $true
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# DEFAULT JSON CONTENT (used when no JSON file exists)
# ─────────────────────────────────────────────────────────────────────────────
function Get-DefaultCommandsJson {
    return @'
[
  {
    "name": "SFC Scan",
    "id": "sfc_scan",
    "category": "Windows Repair",
    "description": "Runs System File Checker to scan and repair protected system files.",
    "command": "sfc /scannow",
    "type": "cmd",
    "requiresAdmin": true,
    "modifiesSystem": true,
    "estimatedTime": "5-15 min",
    "icon": "",
    "builtin": true
  },
  {
    "name": "DISM Repair",
    "id": "dism_repair",
    "category": "Windows Repair",
    "description": "Repairs the Windows component store using DISM online cleanup.",
    "command": "DISM /Online /Cleanup-Image /RestoreHealth",
    "type": "cmd",
    "requiresAdmin": true,
    "modifiesSystem": true,
    "estimatedTime": "10-30 min",
    "icon": "",
    "builtin": true
  },
  {
    "name": "Windows Update Reset",
    "id": "wu_reset",
    "category": "Windows Repair",
    "description": "Stops update services, renames cache folders, and restarts services.",
    "command": "",
    "type": "powershell",
    "requiresAdmin": true,
    "modifiesSystem": true,
    "estimatedTime": "2-5 min",
    "icon": "",
    "builtin": true
  },
  {
    "name": "Store App Repair",
    "id": "store_repair",
    "category": "Windows Repair",
    "description": "Re-registers all Windows Store apps to fix broken or missing apps.",
    "command": "",
    "type": "powershell",
    "requiresAdmin": true,
    "modifiesSystem": true,
    "estimatedTime": "5-15 min",
    "icon": "",
    "builtin": true
  },
  {
    "name": "Flush DNS",
    "id": "flush_dns",
    "category": "Network Fixes",
    "description": "Clears the DNS resolver cache to fix domain resolution issues.",
    "command": "ipconfig /flushdns",
    "type": "cmd",
    "requiresAdmin": true,
    "modifiesSystem": false,
    "estimatedTime": "< 1 min",
    "icon": "",
    "builtin": true
  },
  {
    "name": "Reset Winsock",
    "id": "reset_winsock",
    "category": "Network Fixes",
    "description": "Resets Winsock catalog to fix network connectivity issues. Requires reboot.",
    "command": "netsh winsock reset",
    "type": "cmd",
    "requiresAdmin": true,
    "modifiesSystem": true,
    "estimatedTime": "< 1 min",
    "icon": "",
    "builtin": true
  },
  {
    "name": "Reset TCP/IP",
    "id": "reset_tcpip",
    "category": "Network Fixes",
    "description": "Resets TCP/IP stack to fix IP connectivity issues. Requires reboot.",
    "command": "netsh int ip reset",
    "type": "cmd",
    "requiresAdmin": true,
    "modifiesSystem": true,
    "estimatedTime": "< 1 min",
    "icon": "",
    "builtin": true
  },
  {
    "name": "Renew IP",
    "id": "renew_ip",
    "category": "Network Fixes",
    "description": "Releases and renews IP address from DHCP server.",
    "command": "",
    "type": "powershell",
    "requiresAdmin": true,
    "modifiesSystem": false,
    "estimatedTime": "< 1 min",
    "icon": "",
    "builtin": true
  },
  {
    "name": "Enable Defender",
    "id": "enable_defender",
    "category": "Security Fixes",
    "description": "Enables Windows Defender real-time monitoring protection.",
    "command": "",
    "type": "toggle",
    "requiresAdmin": true,
    "modifiesSystem": false,
    "estimatedTime": "< 1 min",
    "icon": "",
    "builtin": true
  },
  {
    "name": "Update Defender",
    "id": "update_defender",
    "category": "Security Fixes",
    "description": "Downloads latest Windows Defender signature updates.",
    "command": "",
    "type": "powershell",
    "requiresAdmin": true,
    "modifiesSystem": false,
    "estimatedTime": "1-5 min",
    "icon": "",
    "builtin": true
  },
  {
    "name": "Enable Firewall",
    "id": "enable_firewall",
    "category": "Security Fixes",
    "description": "Enables Windows Firewall for all profiles (Domain, Public, Private).",
    "command": "",
    "type": "toggle",
    "requiresAdmin": true,
    "modifiesSystem": false,
    "estimatedTime": "< 1 min",
    "icon": "",
    "builtin": true
  },
  {
    "name": "Check BitLocker",
    "id": "check_bitlocker",
    "category": "Security Fixes",
    "description": "Reads BitLocker encryption status for all volumes (read-only).",
    "command": "",
    "type": "powershell",
    "requiresAdmin": true,
    "modifiesSystem": false,
    "estimatedTime": "< 1 min",
    "icon": "",
    "builtin": true
  },
  {
    "name": "Clean Temp Files",
    "id": "clean_temp",
    "category": "Performance",
    "description": "Removes temporary files from user and system temp folders, runs Disk Cleanup.",
    "command": "",
    "type": "powershell",
    "requiresAdmin": true,
    "modifiesSystem": true,
    "estimatedTime": "2-10 min",
    "icon": "",
    "builtin": true
  },
  {
    "name": "Disable Startup Apps",
    "id": "disable_startup",
    "category": "Performance",
    "description": "Lists startup programs with option to see which ones can be disabled.",
    "command": "",
    "type": "powershell",
    "requiresAdmin": false,
    "modifiesSystem": false,
    "estimatedTime": "< 1 min",
    "icon": "",
    "builtin": true
  },
  {
    "name": "Disk Health Check",
    "id": "disk_health",
    "category": "Performance",
    "description": "Runs chkdsk /scan on C: to check disk integrity without making changes.",
    "command": "chkdsk C: /scan",
    "type": "cmd",
    "requiresAdmin": true,
    "modifiesSystem": false,
    "estimatedTime": "5-20 min",
    "icon": "",
    "builtin": true
  },
  {
    "name": "Restart Print Spooler",
    "id": "restart_spooler",
    "category": "Printer Fixes",
    "description": "Restarts the Windows Print Spooler service to fix stuck print jobs.",
    "command": "",
    "type": "powershell",
    "requiresAdmin": true,
    "modifiesSystem": false,
    "estimatedTime": "< 1 min",
    "icon": "",
    "builtin": true
  },
  {
    "name": "Clear Print Queue",
    "id": "clear_print_queue",
    "category": "Printer Fixes",
    "description": "Stops spooler, clears all pending print jobs, then restarts spooler.",
    "command": "",
    "type": "powershell",
    "requiresAdmin": true,
    "modifiesSystem": true,
    "estimatedTime": "< 1 min",
    "icon": "",
    "builtin": true
  },
  {
    "name": "Run 175-Point Audit",
    "id": "run_audit",
    "category": "PC Plus Tools",
    "description": "Launches the PC Plus Security Audit (PCPlus-SecurityAudit.ps1).",
    "command": "",
    "type": "powershell",
    "requiresAdmin": true,
    "modifiesSystem": false,
    "estimatedTime": "2-10 min",
    "icon": "",
    "builtin": true
  },
  {
    "name": "Install Support Badge",
    "id": "install_badge",
    "category": "PC Plus Tools",
    "description": "Deploys the PC Plus support badge on this system (coming soon).",
    "command": "",
    "type": "powershell",
    "requiresAdmin": true,
    "modifiesSystem": false,
    "estimatedTime": "< 1 min",
    "icon": "",
    "builtin": true
  },
  {
    "name": "Show Security Bulletin",
    "id": "security_bulletin",
    "category": "PC Plus Tools",
    "description": "Displays current security advisories and recommendations.",
    "command": "",
    "type": "powershell",
    "requiresAdmin": false,
    "modifiesSystem": false,
    "estimatedTime": "< 1 min",
    "icon": "",
    "builtin": true
  }
]
'@
}

# ─────────────────────────────────────────────────────────────────────────────
# JSON CONFIG: LOAD / MERGE / SAVE
# ─────────────────────────────────────────────────────────────────────────────
function Load-CommandsFromJson {
    $defaultJson = Get-DefaultCommandsJson
    $defaults = $defaultJson | ConvertFrom-Json

    if (-not (Test-Path $Global:CommandsJsonPath)) {
        # No file exists - create with defaults
        Write-DebugLog "No remediation-commands.json found, creating default..."
        $defaultJson | Out-File -FilePath $Global:CommandsJsonPath -Encoding UTF8
        Write-DebugLog "Default commands JSON created at: $Global:CommandsJsonPath"
        return $defaults
    }

    # File exists - load and merge with defaults
    Write-DebugLog "Loading commands from: $Global:CommandsJsonPath"
    try {
        $fileContent = Get-Content -Path $Global:CommandsJsonPath -Raw -ErrorAction Stop
        $userCommands = $fileContent | ConvertFrom-Json

        # Build a lookup of existing command ids
        $existingIds = @{}
        foreach ($cmd in $userCommands) {
            $cmdId = $cmd.id
            if ($cmdId) {
                $existingIds[$cmdId] = $true
            }
        }

        # Add any new built-in defaults that are missing from the user file
        $merged = $false
        foreach ($def in $defaults) {
            if ($def.id -and -not $existingIds.ContainsKey($def.id)) {
                # New built-in command not in user file, append it
                $userCommands += $def
                $merged = $true
                Write-DebugLog "Merged new built-in command: $($def.name) ($($def.id))"
            }
        }

        if ($merged) {
            # Save the merged result back
            Save-CommandsToJson $userCommands
            Write-DebugLog "Merged file saved with new built-in commands."
        }

        Write-DebugLog "Loaded $($userCommands.Count) commands from JSON."
        return $userCommands
    } catch {
        Write-DebugLog "ERROR loading JSON: $($_.Exception.Message). Falling back to defaults."
        $defaultJson | Out-File -FilePath $Global:CommandsJsonPath -Encoding UTF8
        return $defaults
    }
}

function Save-CommandsToJson {
    param($Commands)
    try {
        $Commands | ConvertTo-Json -Depth 10 | Out-File -FilePath $Global:CommandsJsonPath -Encoding UTF8 -Force
        Write-DebugLog "Commands saved to JSON ($($Commands.Count) commands)."
    } catch {
        Write-DebugLog "ERROR saving JSON: $($_.Exception.Message)"
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# LOAD COMMANDS AND BUILD CATEGORY DATA
# ─────────────────────────────────────────────────────────────────────────────
$Global:CommandList = Load-CommandsFromJson

function Build-CategoriesFromCommandList {
    # Returns an ordered hashtable: category name -> array of command objects
    $cats = [ordered]@{}
    foreach ($cmd in $Global:CommandList) {
        $cat = $cmd.category
        if (-not $cat) { $cat = "Uncategorized" }
        if (-not $cats.Contains($cat)) {
            $cats[$cat] = @()
        }
        $cats[$cat] += $cmd
    }
    return $cats
}

$Global:Categories = Build-CategoriesFromCommandList

# Map category -> sidebar icon (Unicode char) and color
$Global:CategoryMeta = @{
    "Windows Repair" = @{ Icon = [char]0xE90F; Color = "#2596be" }
    "Network Fixes"  = @{ Icon = [char]0xE968; Color = "#3bbde0" }
    "Security Fixes" = @{ Icon = [char]0xE83D; Color = "#27ae60" }
    "Performance"    = @{ Icon = [char]0xE9D9; Color = "#f39c12" }
    "Printer Fixes"  = @{ Icon = [char]0xE749; Color = "#e879f9" }
    "PC Plus Tools"  = @{ Icon = [char]0xE9D5; Color = "#e74c3c" }
}

# Fallback colors for new/custom categories
$Global:FallbackColors = @("#00bcd4", "#8bc34a", "#ff9800", "#9c27b0", "#795548", "#607d8b", "#cddc39", "#e91e63")
$Global:FallbackIcons = @([char]0xE8F1, [char]0xE768, [char]0xE7B8, [char]0xE8D7, [char]0xE90F, [char]0xE8B7)

function Get-CategoryMeta {
    param([string]$CategoryName)
    if ($Global:CategoryMeta.ContainsKey($CategoryName)) {
        return $Global:CategoryMeta[$CategoryName]
    }
    # Generate deterministic color/icon for custom categories
    $hash = 0
    foreach ($c in $CategoryName.ToCharArray()) { $hash = ($hash * 31 + [int]$c) }
    if ($hash -lt 0) { $hash = -$hash }
    $colorIdx = $hash % $Global:FallbackColors.Count
    $iconIdx  = $hash % $Global:FallbackIcons.Count
    return @{
        Icon  = $Global:FallbackIcons[$iconIdx]
        Color = $Global:FallbackColors[$colorIdx]
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# RESTORE POINT HELPER
# ─────────────────────────────────────────────────────────────────────────────
function New-SafeRestorePoint {
    param([string]$Description = "PC Plus Remediation")
    try {
        Write-Output "Creating system restore point: $Description"
        # Enable System Restore on C: if not already enabled
        Enable-ComputerRestore -Drive "C:\" -ErrorAction SilentlyContinue
        Checkpoint-Computer -Description $Description -RestorePointType "MODIFY_SETTINGS" -ErrorAction Stop
        Write-Output "  Restore point created successfully."
        return $true
    } catch {
        Write-Output "  Warning: Could not create restore point - $($_.Exception.Message)"
        Write-Output "  Continuing without restore point..."
        return $false
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# BUILD SCRIPTBLOCK FOR A COMMAND
# ─────────────────────────────────────────────────────────────────────────────
function Get-CommandScriptBlock {
    param($CmdObj)

    # Built-in commands use the hardcoded scriptblocks
    $cmdId = $CmdObj.id
    $isBuiltin = $false
    if ($null -ne $CmdObj.builtin) {
        $isBuiltin = $CmdObj.builtin
    }

    if ($isBuiltin -and $cmdId -and $Global:BuiltinScriptBlocks.ContainsKey($cmdId)) {
        return $Global:BuiltinScriptBlocks[$cmdId]
    }

    # Custom commands: build scriptblock from type + command field
    $commandStr = $CmdObj.command
    $cmdType    = $CmdObj.type

    switch ($cmdType) {
        "cmd" {
            return [ScriptBlock]::Create(@"
Write-Output "Running: $commandStr"
`$output = & cmd.exe /c "$commandStr" 2>&1
`$output | ForEach-Object { Write-Output `$_ }
if (`$LASTEXITCODE -eq 0 -or `$null -eq `$LASTEXITCODE) {
    Write-Output "``n[RESULT] Command completed successfully."
    return `$true
} else {
    Write-Output "``n[RESULT] Command exited with code `$LASTEXITCODE."
    return `$false
}
"@)
        }
        "powershell" {
            return [ScriptBlock]::Create(@"
Write-Output "Running PowerShell command..."
try {
    $commandStr
    Write-Output "``n[RESULT] Command completed successfully."
    return `$true
} catch {
    Write-Output "``n[RESULT] Command failed: `$(`$_.Exception.Message)"
    return `$false
}
"@)
        }
        "script" {
            return [ScriptBlock]::Create(@"
`$scriptPath = "$commandStr"
if (-not [System.IO.Path]::IsPathRooted(`$scriptPath)) {
    `$scriptPath = Join-Path `$Global:ScriptDir `$scriptPath
}
if (Test-Path `$scriptPath) {
    Write-Output "Running script: `$scriptPath"
    try {
        & `$scriptPath
        Write-Output "``n[RESULT] Script completed successfully."
        return `$true
    } catch {
        Write-Output "``n[RESULT] Script failed: `$(`$_.Exception.Message)"
        return `$false
    }
} else {
    Write-Output "[RESULT] Script not found: `$scriptPath"
    return `$false
}
"@)
        }
        "toggle" {
            return [ScriptBlock]::Create(@"
Write-Output "Running toggle command..."
try {
    $commandStr
    Write-Output "``n[RESULT] Toggle completed successfully."
    return `$true
} catch {
    Write-Output "``n[RESULT] Toggle failed: `$(`$_.Exception.Message)"
    return `$false
}
"@)
        }
        default {
            return [ScriptBlock]::Create(@"
Write-Output "Running: $commandStr"
try {
    Invoke-Expression "$commandStr"
    Write-Output "``n[RESULT] Command completed."
    return `$true
} catch {
    Write-Output "``n[RESULT] Command failed: `$(`$_.Exception.Message)"
    return `$false
}
"@)
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# WPF XAML UI
# ─────────────────────────────────────────────────────────────────────────────
function Show-RemediationUI {

[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="PC Plus 360 - Remediation Library" Height="780" Width="1100"
        MinHeight="650" MinWidth="900"
        WindowStartupLocation="CenterScreen" ResizeMode="CanResizeWithGrip"
        Background="#0a1628" FontFamily="Segoe UI">
    <Window.Resources>
        <!-- Flat button style -->
        <Style x:Key="FlatBtn" TargetType="Button">
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="FontFamily" Value="Segoe UI"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="bd" Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="5" Padding="{TemplateBinding Padding}">
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

        <!-- Sidebar nav button -->
        <Style x:Key="SideNav" TargetType="Button">
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="HorizontalContentAlignment" Value="Stretch"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="bd" Background="Transparent" CornerRadius="6" Padding="12,10" Margin="4,2,4,2">
                            <ContentPresenter HorizontalAlignment="Left"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="bd" Property="Background" Value="#1a2d42"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter Property="Opacity" Value="0.4"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Active sidebar nav button -->
        <Style x:Key="SideNavActive" TargetType="Button">
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="HorizontalContentAlignment" Value="Stretch"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="bd" Background="#1a2d42" CornerRadius="6" Padding="12,10" Margin="4,2,4,2"
                                BorderBrush="#2596be" BorderThickness="2,0,0,0">
                            <ContentPresenter HorizontalAlignment="Left"/>
                        </Border>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Run button -->
        <Style x:Key="RunBtn" TargetType="Button">
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="FontFamily" Value="Segoe UI"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="bd" Background="{TemplateBinding Background}"
                                CornerRadius="5" Padding="14,7">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="bd" Property="Opacity" Value="0.88"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="bd" Property="Opacity" Value="0.7"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter Property="Opacity" Value="0.35"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Small icon button (edit pencil) -->
        <Style x:Key="IconBtn" TargetType="Button">
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="bd" Background="Transparent" CornerRadius="4" Padding="4,2">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="bd" Property="Background" Value="#1a2d42"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="bd" Property="Opacity" Value="0.7"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Checkbox style for dark theme -->
        <Style x:Key="DarkCheck" TargetType="CheckBox">
            <Setter Property="Foreground" Value="#b0c4d8"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="VerticalContentAlignment" Value="Center"/>
            <Setter Property="Cursor" Value="Hand"/>
        </Style>

        <!-- ScrollBar dark style -->
        <Style TargetType="ScrollViewer">
            <Setter Property="Background" Value="Transparent"/>
        </Style>
    </Window.Resources>

    <Grid>
        <Grid.ColumnDefinitions>
            <ColumnDefinition Width="230"/>
            <ColumnDefinition Width="*"/>
        </Grid.ColumnDefinitions>

        <!-- SIDEBAR -->
        <Border Grid.Column="0" Background="#0d1b2a" BorderBrush="#152238" BorderThickness="0,0,1,0">
            <DockPanel LastChildFill="True">
                <!-- Logo / branding top -->
                <Border DockPanel.Dock="Top" Padding="16,18,16,14" BorderBrush="#152238" BorderThickness="0,0,0,1">
                    <StackPanel>
                        <StackPanel Orientation="Horizontal">
                            <Border Width="40" Height="40" CornerRadius="10" Margin="0,0,12,0">
                                <Border.Background>
                                    <LinearGradientBrush StartPoint="0,0" EndPoint="1,1">
                                        <GradientStop Color="#2596be" Offset="0"/>
                                        <GradientStop Color="#27ae60" Offset="1"/>
                                    </LinearGradientBrush>
                                </Border.Background>
                                <TextBlock Text="FIX" FontSize="13" FontWeight="Bold" Foreground="White"
                                           HorizontalAlignment="Center" VerticalAlignment="Center" FontFamily="Consolas"/>
                            </Border>
                            <StackPanel VerticalAlignment="Center">
                                <TextBlock Text="PC Plus Computing" FontSize="13" FontWeight="SemiBold" Foreground="White"/>
                                <TextBlock Text="REMEDIATION LIBRARY" FontSize="8" Foreground="#2596be" FontWeight="Bold" Margin="0,2,0,0"/>
                            </StackPanel>
                        </StackPanel>
                    </StackPanel>
                </Border>

                <!-- Footer -->
                <Border DockPanel.Dock="Bottom" Padding="16,10" BorderBrush="#152238" BorderThickness="0,1,0,0">
                    <StackPanel>
                        <TextBlock x:Name="lblVersion" Text="v2.0.0" FontSize="10" Foreground="#2596be" FontFamily="Consolas"/>
                        <TextBlock Text="604-760-1662 | 236-500-2700" FontSize="8.5" Foreground="#4a6a7a" Margin="0,3,0,0"/>
                        <TextBlock Text="pcpluscomputing.com" FontSize="8.5" Foreground="#3a5a6a"/>
                    </StackPanel>
                </Border>

                <!-- Category nav (built dynamically) -->
                <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
                    <StackPanel x:Name="pnlSidebar" Margin="4,12,4,8">
                        <TextBlock Text="  CATEGORIES" FontSize="9" FontWeight="Bold" Foreground="#4a6a7a" Margin="8,0,0,8"/>
                        <!-- Dynamic category buttons inserted here -->
                        <StackPanel x:Name="pnlCategoryButtons"/>

                        <Border Height="1" Background="#152238" Margin="8,14,8,14"/>

                        <!-- Add Command button -->
                        <Button x:Name="btnAddCommand" Style="{StaticResource FlatBtn}" Background="#1a3a2a"
                                Padding="12,8" Margin="8,4,8,4" HorizontalContentAlignment="Center">
                            <StackPanel Orientation="Horizontal">
                                <TextBlock Text="&#xE710;" FontFamily="Segoe MDL2 Assets" FontSize="12" Foreground="#27ae60" VerticalAlignment="Center" Margin="0,0,6,0"/>
                                <TextBlock Text="Add Command" FontSize="11" Foreground="#27ae60" FontWeight="SemiBold"/>
                            </StackPanel>
                        </Button>

                        <Border Height="1" Background="#152238" Margin="8,10,8,10"/>

                        <TextBlock Text="  OPTIONS" FontSize="9" FontWeight="Bold" Foreground="#4a6a7a" Margin="8,0,0,8"/>

                        <StackPanel Margin="16,0,8,0">
                            <CheckBox x:Name="chkRestorePoint" Style="{StaticResource DarkCheck}"
                                      Content="Create restore point before fixes" IsChecked="True" Margin="0,0,0,6"/>
                            <CheckBox x:Name="chkReadOnly" Style="{StaticResource DarkCheck}"
                                      Content="Read-Only mode (diagnostics only)" Margin="0,0,0,6"/>
                        </StackPanel>

                        <Border Height="1" Background="#152238" Margin="8,10,8,10"/>

                        <Button x:Name="btnExportLog" Style="{StaticResource FlatBtn}" Background="#1a2d42"
                                Padding="12,8" Margin="8,4,8,4" HorizontalContentAlignment="Center">
                            <TextBlock Text="Export Log" FontSize="11" Foreground="#b0c4d8"/>
                        </Button>

                        <Button x:Name="btnClearLog" Style="{StaticResource FlatBtn}" Background="#1a2d42"
                                Padding="12,8" Margin="8,4,8,4" HorizontalContentAlignment="Center">
                            <TextBlock Text="Clear Output" FontSize="11" Foreground="#b0c4d8"/>
                        </Button>
                    </StackPanel>
                </ScrollViewer>
            </DockPanel>
        </Border>

        <!-- MAIN CONTENT -->
        <Grid Grid.Column="1">
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="*"/>
                <RowDefinition Height="5"/>
                <RowDefinition Height="220"/>
            </Grid.RowDefinitions>

            <!-- Header bar -->
            <Border Grid.Row="0" Background="#0d1b2a" Padding="20,14,20,14" BorderBrush="#152238" BorderThickness="0,0,0,1">
                <Grid>
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>
                    <StackPanel>
                        <TextBlock x:Name="lblCategoryTitle" Text="Windows Repair" FontSize="20" FontWeight="Bold" Foreground="White"/>
                        <TextBlock x:Name="lblCategoryDesc" Text="System file repair and Windows component fixes" FontSize="11.5" Foreground="#6a8a9a" Margin="0,3,0,0"/>
                    </StackPanel>
                    <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center">
                        <Border x:Name="badgeAdmin" CornerRadius="4" Padding="8,4" Margin="0,0,8,0">
                            <TextBlock x:Name="lblAdminStatus" Text="ADMIN" FontSize="9" FontWeight="Bold" Foreground="White"/>
                        </Border>
                        <Border x:Name="badgeMode" CornerRadius="4" Background="#1a2d42" Padding="8,4">
                            <TextBlock x:Name="lblModeStatus" Text="LIVE MODE" FontSize="9" FontWeight="Bold" Foreground="#f39c12"/>
                        </Border>
                    </StackPanel>
                </Grid>
            </Border>

            <!-- Cards area -->
            <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" Padding="0">
                <WrapPanel x:Name="pnlCards" Margin="16,16,16,8" Orientation="Horizontal"/>
            </ScrollViewer>

            <!-- Splitter -->
            <GridSplitter Grid.Row="2" Height="5" HorizontalAlignment="Stretch" Background="#152238" ResizeDirection="Rows"/>

            <!-- Output log pane -->
            <Border Grid.Row="3" Background="#080f1a" BorderBrush="#152238" BorderThickness="0,1,0,0">
                <DockPanel>
                    <Border DockPanel.Dock="Top" Background="#0d1b2a" Padding="16,8,16,8">
                        <Grid>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="Auto"/>
                            </Grid.ColumnDefinitions>
                            <StackPanel Orientation="Horizontal">
                                <TextBlock Text="OUTPUT LOG" FontSize="10" FontWeight="Bold" Foreground="#4a6a7a" VerticalAlignment="Center"/>
                                <TextBlock x:Name="lblRunStatus" Text="" FontSize="10" Foreground="#2596be" Margin="12,0,0,0" VerticalAlignment="Center"/>
                            </StackPanel>
                            <StackPanel Grid.Column="1" Orientation="Horizontal">
                                <TextBlock x:Name="lblResultIndicator" Text="" FontSize="12" FontWeight="Bold" Margin="0,0,8,0" VerticalAlignment="Center"/>
                            </StackPanel>
                        </Grid>
                    </Border>
                    <TextBox x:Name="txtOutput" Background="#080f1a" Foreground="#a0b8c8" FontFamily="Consolas"
                             FontSize="11" IsReadOnly="True" TextWrapping="Wrap" AcceptsReturn="True"
                             VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto"
                             Padding="16,8" BorderThickness="0"
                             VerticalAlignment="Stretch"/>
                </DockPanel>
            </Border>
        </Grid>
    </Grid>
</Window>
"@

    # ─────────────────────────────────────────────────────────────────────────
    # LOAD XAML
    # ─────────────────────────────────────────────────────────────────────────
    $reader = New-Object System.Xml.XmlNodeReader $xaml
    $window = [Windows.Markup.XamlReader]::Load($reader)

    # ─────────────────────────────────────────────────────────────────────────
    # FIND CONTROLS
    # ─────────────────────────────────────────────────────────────────────────
    $lblCategoryTitle   = $window.FindName("lblCategoryTitle")
    $lblCategoryDesc    = $window.FindName("lblCategoryDesc")
    $pnlCards           = $window.FindName("pnlCards")
    $pnlCategoryButtons = $window.FindName("pnlCategoryButtons")
    $txtOutput          = $window.FindName("txtOutput")
    $lblRunStatus       = $window.FindName("lblRunStatus")
    $lblResultIndicator = $window.FindName("lblResultIndicator")
    $chkRestorePoint    = $window.FindName("chkRestorePoint")
    $chkReadOnly        = $window.FindName("chkReadOnly")
    $badgeAdmin         = $window.FindName("badgeAdmin")
    $lblAdminStatus     = $window.FindName("lblAdminStatus")
    $badgeMode          = $window.FindName("badgeMode")
    $lblModeStatus      = $window.FindName("lblModeStatus")
    $btnAddCommand      = $window.FindName("btnAddCommand")
    $btnExportLog       = $window.FindName("btnExportLog")
    $btnClearLog        = $window.FindName("btnClearLog")

    # ─────────────────────────────────────────────────────────────────────────
    # SET INITIAL STATE
    # ─────────────────────────────────────────────────────────────────────────
    $chkRestorePoint.IsChecked = $Global:CreateRestorePoint
    $chkReadOnly.IsChecked = $Global:IsReadOnly

    if ($Global:IsAdmin) {
        $badgeAdmin.Background = [Windows.Media.BrushConverter]::new().ConvertFrom("#27ae60")
        $lblAdminStatus.Text = "ADMIN"
    } else {
        $badgeAdmin.Background = [Windows.Media.BrushConverter]::new().ConvertFrom("#e74c3c")
        $lblAdminStatus.Text = "NO ADMIN"
    }

    # Track running state
    $Global:IsRunning = $false
    $Global:CurrentCategory = ""
    $Global:RunResults = [System.Collections.ArrayList]::new()

    # Sidebar button references (built dynamically)
    $Global:SidebarButtons = @{}

    # Category descriptions (default ones + auto-generated for custom)
    $defaultCategoryDescriptions = @{
        "Windows Repair" = "System file repair and Windows component fixes"
        "Network Fixes"  = "DNS, Winsock, TCP/IP, and IP address fixes"
        "Security Fixes" = "Defender, Firewall, and BitLocker management"
        "Performance"    = "Temp cleanup, startup optimization, and disk checks"
        "Printer Fixes"  = "Print spooler and queue management"
        "PC Plus Tools"  = "PC Plus Computing internal tools and reports"
    }

    function Get-CategoryDescription {
        param([string]$Cat)
        if ($defaultCategoryDescriptions.ContainsKey($Cat)) {
            return $defaultCategoryDescriptions[$Cat]
        }
        return "Custom commands in category: $Cat"
    }

    # ─────────────────────────────────────────────────────────────────────────
    # HELPER: Append to output log (thread-safe via Dispatcher)
    # ─────────────────────────────────────────────────────────────────────────
    function Append-Output {
        param([string]$Text)
        $window.Dispatcher.Invoke([Action]{
            $txtOutput.AppendText("$Text`r`n")
            $txtOutput.ScrollToEnd()
        }, [System.Windows.Threading.DispatcherPriority]::Background)
    }

    function Set-RunStatus {
        param([string]$Text, [string]$Color = "#2596be")
        $window.Dispatcher.Invoke([Action]{
            $lblRunStatus.Text = $Text
            $lblRunStatus.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom($Color)
        }, [System.Windows.Threading.DispatcherPriority]::Background)
    }

    function Set-ResultIndicator {
        param([string]$Text, [string]$Color)
        $window.Dispatcher.Invoke([Action]{
            $lblResultIndicator.Text = $Text
            $lblResultIndicator.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom($Color)
        }, [System.Windows.Threading.DispatcherPriority]::Background)
    }

    # ─────────────────────────────────────────────────────────────────────────
    # HELPER: Update Read-Only mode badge
    # ─────────────────────────────────────────────────────────────────────────
    function Update-ModeBadge {
        if ($chkReadOnly.IsChecked) {
            $lblModeStatus.Text = "READ-ONLY"
            $lblModeStatus.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#2596be")
        } else {
            $lblModeStatus.Text = "LIVE MODE"
            $lblModeStatus.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#f39c12")
        }
    }

    $chkReadOnly.Add_Checked({ Update-ModeBadge })
    $chkReadOnly.Add_Unchecked({ Update-ModeBadge })
    Update-ModeBadge

    # ─────────────────────────────────────────────────────────────────────────
    # BUILD SIDEBAR CATEGORY BUTTONS (dynamic from JSON data)
    # ─────────────────────────────────────────────────────────────────────────
    function Build-SidebarButtons {
        $pnlCategoryButtons.Children.Clear()
        $Global:SidebarButtons = @{}

        foreach ($catName in $Global:Categories.Keys) {
            $meta = Get-CategoryMeta $catName

            $btn = New-Object Windows.Controls.Button
            $btn.Style = $window.FindResource("SideNav")
            $btn.Tag = $catName

            $sp = New-Object Windows.Controls.StackPanel
            $sp.Orientation = "Horizontal"

            $iconTb = New-Object Windows.Controls.TextBlock
            $iconTb.FontFamily = New-Object Windows.Media.FontFamily("Segoe MDL2 Assets")
            $iconTb.FontSize = 16
            $iconTb.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom($meta.Color)
            $iconTb.VerticalAlignment = "Center"
            $iconTb.Margin = [Windows.Thickness]::new(0, 0, 10, 0)
            $iconTb.Text = [string]$meta.Icon
            $sp.Children.Add($iconTb) | Out-Null

            $labelTb = New-Object Windows.Controls.TextBlock
            $labelTb.Text = $catName
            $labelTb.FontSize = 12.5
            $labelTb.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#c0d4e8")
            $labelTb.FontWeight = "SemiBold"
            $sp.Children.Add($labelTb) | Out-Null

            $btn.Content = $sp

            $btn.Add_Click({
                param($sender, $e)
                Show-Category $sender.Tag
            })

            $pnlCategoryButtons.Children.Add($btn) | Out-Null
            $Global:SidebarButtons[$catName] = $btn
        }
    }

    # ─────────────────────────────────────────────────────────────────────────
    # ADD/EDIT COMMAND DIALOG
    # ─────────────────────────────────────────────────────────────────────────
    function Show-CommandDialog {
        param(
            [string]$Mode = "Add",          # "Add" or "Edit"
            $ExistingCmd = $null             # PSObject from JSON when editing
        )

        # Build dialog XAML
        [xml]$dlgXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="$Mode Command" Height="520" Width="480"
        WindowStartupLocation="CenterOwner" ResizeMode="NoResize"
        Background="#0d1b2a" FontFamily="Segoe UI">
    <Grid Margin="24">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <!-- Name -->
        <TextBlock Grid.Row="0" Text="Name" Foreground="#b0c4d8" FontSize="11" Margin="0,0,0,4"/>
        <TextBox x:Name="txtName" Grid.Row="1" Background="#111d2e" Foreground="White" FontSize="12"
                 BorderBrush="#1a2d42" Padding="8,6" Margin="0,0,0,10"/>

        <!-- Category -->
        <TextBlock Grid.Row="2" Text="Category" Foreground="#b0c4d8" FontSize="11" Margin="0,0,0,4"/>
        <Grid Grid.Row="3" Margin="0,0,0,10">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <ComboBox x:Name="cmbCategory" Grid.Column="0" Background="#111d2e" Foreground="White" FontSize="12"
                      Padding="8,6" Margin="0,0,8,0"/>
            <TextBox x:Name="txtNewCategory" Grid.Column="1" Width="140" Background="#111d2e" Foreground="White"
                     FontSize="12" BorderBrush="#1a2d42" Padding="8,6" Visibility="Collapsed"/>
        </Grid>

        <!-- Description -->
        <TextBlock Grid.Row="4" Text="Description" Foreground="#b0c4d8" FontSize="11" Margin="0,0,0,4"/>
        <TextBox x:Name="txtDescription" Grid.Row="5" Background="#111d2e" Foreground="White" FontSize="12"
                 BorderBrush="#1a2d42" Padding="8,6" Margin="0,0,0,10" TextWrapping="Wrap"
                 AcceptsReturn="False" Height="50"/>

        <!-- Command / Script Path -->
        <TextBlock Grid.Row="6" Text="Command or Script Path" Foreground="#b0c4d8" FontSize="11" Margin="0,0,0,4"/>
        <TextBox x:Name="txtCommand" Grid.Row="7" Background="#111d2e" Foreground="White" FontSize="12"
                 BorderBrush="#1a2d42" Padding="8,6" Margin="0,0,0,10" FontFamily="Consolas"
                 TextWrapping="Wrap" AcceptsReturn="False" Height="50"/>

        <!-- Type + Options row -->
        <Grid Grid.Row="8" Margin="0,0,0,16">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
                <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>

            <TextBlock Grid.Row="0" Grid.Column="0" Text="Type" Foreground="#b0c4d8" FontSize="11" Margin="0,0,0,4"/>
            <ComboBox x:Name="cmbType" Grid.Row="1" Grid.Column="0" Background="#111d2e" Foreground="White"
                      FontSize="12" Padding="8,6" Margin="0,0,16,0">
                <ComboBoxItem Content="cmd" IsSelected="True"/>
                <ComboBoxItem Content="powershell"/>
                <ComboBoxItem Content="script"/>
                <ComboBoxItem Content="toggle"/>
            </ComboBox>

            <CheckBox x:Name="chkAdmin" Grid.Row="1" Grid.Column="1" Content="Requires Admin"
                      Foreground="#b0c4d8" FontSize="11" VerticalAlignment="Center" Margin="0,0,16,0"
                      IsChecked="True" Cursor="Hand"/>
            <CheckBox x:Name="chkModifies" Grid.Row="1" Grid.Column="2" Content="Modifies System"
                      Foreground="#b0c4d8" FontSize="11" VerticalAlignment="Center"
                      IsChecked="False" Cursor="Hand"/>
        </Grid>

        <!-- Save / Cancel -->
        <StackPanel Grid.Row="9" Orientation="Horizontal" HorizontalAlignment="Right">
            <Button x:Name="btnCancel" Content="Cancel" Width="80" Padding="0,8" Margin="0,0,10,0"
                    Background="#1a2d42" Foreground="#b0c4d8" FontSize="12" Cursor="Hand"
                    BorderThickness="0">
                <Button.Template>
                    <ControlTemplate TargetType="Button">
                        <Border Background="{TemplateBinding Background}" CornerRadius="5" Padding="14,8">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                    </ControlTemplate>
                </Button.Template>
            </Button>
            <Button x:Name="btnSave" Width="120" Padding="0,8"
                    Background="#2596be" Foreground="White" FontSize="12" FontWeight="SemiBold" Cursor="Hand"
                    BorderThickness="0">
                <Button.Template>
                    <ControlTemplate TargetType="Button">
                        <Border Background="{TemplateBinding Background}" CornerRadius="5" Padding="14,8">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                    </ControlTemplate>
                </Button.Template>
            </Button>
        </StackPanel>
    </Grid>
</Window>
"@

        $dlgReader = New-Object System.Xml.XmlNodeReader $dlgXaml
        $dlg = [Windows.Markup.XamlReader]::Load($dlgReader)
        $dlg.Owner = $window

        $txtName        = $dlg.FindName("txtName")
        $cmbCategory    = $dlg.FindName("cmbCategory")
        $txtNewCategory = $dlg.FindName("txtNewCategory")
        $txtDescription = $dlg.FindName("txtDescription")
        $txtCommand     = $dlg.FindName("txtCommand")
        $cmbType        = $dlg.FindName("cmbType")
        $chkAdmin       = $dlg.FindName("chkAdmin")
        $chkModifies    = $dlg.FindName("chkModifies")
        $btnSave        = $dlg.FindName("btnSave")
        $btnCancel      = $dlg.FindName("btnCancel")

        $btnSave.Content = if ($Mode -eq "Edit") { "Save Changes" } else { "Add Command" }

        # Capture function references so .GetNewClosure() can find them
        $fnSaveCommandsToJson = ${function:Save-CommandsToJson}
        $fnBuildCategoriesFromCommandList = ${function:Build-CategoriesFromCommandList}
        $fnBuildSidebarButtons = ${function:Build-SidebarButtons}
        $fnShowCategory = ${function:Show-Category}

        # Populate category dropdown
        $existingCats = @($Global:Categories.Keys)
        foreach ($cat in $existingCats) {
            $cmbCategory.Items.Add($cat) | Out-Null
        }
        $cmbCategory.Items.Add("-- New Category --") | Out-Null
        $cmbCategory.SelectedIndex = 0

        # Show/hide new category textbox
        $cmbCategory.Add_SelectionChanged({
            param($s, $e)
            $selectedItem = $cmbCategory.SelectedItem
            if ($selectedItem -and $selectedItem.ToString() -eq "-- New Category --") {
                $txtNewCategory.Visibility = "Visible"
            } else {
                $txtNewCategory.Visibility = "Collapsed"
            }
        }.GetNewClosure())

        # Pre-fill for edit mode
        if ($Mode -eq "Edit" -and $ExistingCmd) {
            $txtName.Text = $ExistingCmd.name
            $txtDescription.Text = $ExistingCmd.description
            $txtCommand.Text = $ExistingCmd.command

            # Select category
            for ($i = 0; $i -lt $cmbCategory.Items.Count; $i++) {
                if ($cmbCategory.Items[$i].ToString() -eq $ExistingCmd.category) {
                    $cmbCategory.SelectedIndex = $i
                    break
                }
            }

            # Select type
            $typeStr = $ExistingCmd.type
            for ($i = 0; $i -lt $cmbType.Items.Count; $i++) {
                $item = $cmbType.Items[$i]
                if ($item.Content -eq $typeStr) {
                    $cmbType.SelectedIndex = $i
                    break
                }
            }

            $chkAdmin.IsChecked = [bool]$ExistingCmd.requiresAdmin
            $chkModifies.IsChecked = [bool]$ExistingCmd.modifiesSystem
        }

        # Dialog result holder
        $dlgResult = @{ Saved = $false }

        $btnCancel.Add_Click({ $dlg.Close() }.GetNewClosure())

        $btnSave.Add_Click({
            # Validate
            $name = $txtName.Text.Trim()
            if ([string]::IsNullOrEmpty($name)) {
                [Windows.MessageBox]::Show("Please enter a command name.", "Validation", "OK", "Warning")
                return
            }

            # Determine category
            $selectedCat = $cmbCategory.SelectedItem
            $category = ""
            if ($selectedCat -and $selectedCat.ToString() -eq "-- New Category --") {
                $category = $txtNewCategory.Text.Trim()
                if ([string]::IsNullOrEmpty($category)) {
                    [Windows.MessageBox]::Show("Please enter a new category name.", "Validation", "OK", "Warning")
                    return
                }
            } else {
                $category = $selectedCat.ToString()
            }

            $desc = $txtDescription.Text.Trim()
            $cmdText = $txtCommand.Text.Trim()
            $typeItem = $cmbType.SelectedItem
            $typeVal = if ($typeItem -is [Windows.Controls.ComboBoxItem]) { $typeItem.Content.ToString() } else { $typeItem.ToString() }

            # Generate an id for new commands
            $newId = ($name -replace '[^a-zA-Z0-9]', '_').ToLower()

            if ($Mode -eq "Edit" -and $ExistingCmd) {
                # Update existing command in the global list
                foreach ($cmd in $Global:CommandList) {
                    if ($cmd.id -eq $ExistingCmd.id -and $cmd.name -eq $ExistingCmd.name) {
                        $cmd.name = $name
                        $cmd.category = $category
                        $cmd.description = $desc
                        $cmd.command = $cmdText
                        $cmd.type = $typeVal
                        $cmd.requiresAdmin = [bool]$chkAdmin.IsChecked
                        $cmd.modifiesSystem = [bool]$chkModifies.IsChecked
                        break
                    }
                }
            } else {
                # Add new command
                $newCmd = [PSCustomObject]@{
                    name          = $name
                    id            = $newId
                    category      = $category
                    description   = $desc
                    command       = $cmdText
                    type          = $typeVal
                    requiresAdmin = [bool]$chkAdmin.IsChecked
                    modifiesSystem = [bool]$chkModifies.IsChecked
                    estimatedTime = ""
                    icon          = ""
                    builtin       = $false
                }
                $Global:CommandList += $newCmd
            }

            # Save to JSON
            & $fnSaveCommandsToJson $Global:CommandList

            # Rebuild categories and UI
            $Global:Categories = & $fnBuildCategoriesFromCommandList
            & $fnBuildSidebarButtons
            & $fnShowCategory $category

            $dlgResult.Saved = $true
            $dlg.Close()
        }.GetNewClosure())

        $dlg.ShowDialog() | Out-Null
        return $dlgResult.Saved
    }

    # ─────────────────────────────────────────────────────────────────────────
    # BUILD CARDS FOR A CATEGORY
    # ─────────────────────────────────────────────────────────────────────────
    function Show-Category {
        param([string]$CategoryName)

        if ($Global:IsRunning) { return }

        $Global:CurrentCategory = $CategoryName
        $lblCategoryTitle.Text = $CategoryName
        $lblCategoryDesc.Text = (Get-CategoryDescription $CategoryName)

        # Update sidebar active states
        foreach ($key in @($Global:SidebarButtons.Keys)) {
            if ($key -eq $CategoryName) {
                $Global:SidebarButtons[$key].Style = $window.FindResource("SideNavActive")
            } else {
                $Global:SidebarButtons[$key].Style = $window.FindResource("SideNav")
            }
        }

        # Clear and rebuild cards
        $pnlCards.Children.Clear()

        if (-not $Global:Categories.Contains($CategoryName)) { return }
        $commands = $Global:Categories[$CategoryName]
        $meta = Get-CategoryMeta $CategoryName
        $accentColor = $meta.Color

        foreach ($cmdObj in $commands) {
            # Determine display properties from JSON object
            $cmdName = $cmdObj.name
            $cmdDesc = $cmdObj.description
            $cmdIcon = $cmdObj.icon
            $isDestructive = [bool]$cmdObj.modifiesSystem
            $isToggle = ($cmdObj.type -eq "toggle")
            $reqAdmin = [bool]$cmdObj.requiresAdmin
            $isBuiltin = $false
            if ($null -ne $cmdObj.builtin) { $isBuiltin = [bool]$cmdObj.builtin }

            # Use icon from JSON if available, otherwise use category default
            $displayIcon = $meta.Icon
            if ($cmdIcon -and $cmdIcon.Length -gt 0) {
                $displayIcon = $cmdIcon
            }

            # Card border
            $card = New-Object Windows.Controls.Border
            $card.Width = 260
            $card.Margin = [Windows.Thickness]::new(0, 0, 12, 12)
            $card.CornerRadius = [Windows.CornerRadius]::new(8)
            $card.Background = [Windows.Media.BrushConverter]::new().ConvertFrom("#111d2e")
            $card.BorderBrush = [Windows.Media.BrushConverter]::new().ConvertFrom("#1a2d42")
            $card.BorderThickness = [Windows.Thickness]::new(1)
            $card.Padding = [Windows.Thickness]::new(16)

            # Card content
            $stack = New-Object Windows.Controls.StackPanel

            # Top row: Icon + badges + edit button
            $topRow = New-Object Windows.Controls.Grid
            $col1 = New-Object Windows.Controls.ColumnDefinition
            $col1.Width = [Windows.GridLength]::new(1, [Windows.GridUnitType]::Star)
            $col2 = New-Object Windows.Controls.ColumnDefinition
            $col2.Width = [Windows.GridLength]::Auto
            $topRow.ColumnDefinitions.Add($col1)
            $topRow.ColumnDefinitions.Add($col2)
            $topRow.Margin = [Windows.Thickness]::new(0, 0, 0, 10)

            # Icon + badges
            $iconRow = New-Object Windows.Controls.StackPanel
            $iconRow.Orientation = "Horizontal"
            [Windows.Controls.Grid]::SetColumn($iconRow, 0)

            $iconBorder = New-Object Windows.Controls.Border
            $iconBorder.Width = 36
            $iconBorder.Height = 36
            $iconBorder.CornerRadius = [Windows.CornerRadius]::new(8)
            $iconBorder.Background = [Windows.Media.BrushConverter]::new().ConvertFrom("#1a2d42")

            $iconText = New-Object Windows.Controls.TextBlock
            $iconText.FontFamily = New-Object Windows.Media.FontFamily("Segoe MDL2 Assets")
            $iconText.FontSize = 16
            $iconText.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom($accentColor)
            $iconText.HorizontalAlignment = "Center"
            $iconText.VerticalAlignment = "Center"
            $iconText.Text = [string]$displayIcon
            $iconBorder.Child = $iconText

            $iconRow.Children.Add($iconBorder) | Out-Null

            # Destructive / toggle badge
            if ($isDestructive) {
                $badge = New-Object Windows.Controls.Border
                $badge.CornerRadius = [Windows.CornerRadius]::new(3)
                $badge.Background = [Windows.Media.BrushConverter]::new().ConvertFrom("#2a1520")
                $badge.Padding = [Windows.Thickness]::new(6, 2, 6, 2)
                $badge.Margin = [Windows.Thickness]::new(8, 0, 0, 0)
                $badge.VerticalAlignment = "Center"
                $badgeText = New-Object Windows.Controls.TextBlock
                $badgeText.Text = "MODIFIES"
                $badgeText.FontSize = 8
                $badgeText.FontWeight = "Bold"
                $badgeText.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#e74c3c")
                $badge.Child = $badgeText
                $iconRow.Children.Add($badge) | Out-Null
            } elseif ($isToggle) {
                $badge = New-Object Windows.Controls.Border
                $badge.CornerRadius = [Windows.CornerRadius]::new(3)
                $badge.Background = [Windows.Media.BrushConverter]::new().ConvertFrom("#1a2520")
                $badge.Padding = [Windows.Thickness]::new(6, 2, 6, 2)
                $badge.Margin = [Windows.Thickness]::new(8, 0, 0, 0)
                $badge.VerticalAlignment = "Center"
                $badgeText = New-Object Windows.Controls.TextBlock
                $badgeText.Text = "TOGGLE"
                $badgeText.FontSize = 8
                $badgeText.FontWeight = "Bold"
                $badgeText.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#27ae60")
                $badge.Child = $badgeText
                $iconRow.Children.Add($badge) | Out-Null
            }

            $topRow.Children.Add($iconRow) | Out-Null

            # Edit pencil button (top right)
            $btnEdit = New-Object Windows.Controls.Button
            $btnEdit.Style = $window.FindResource("IconBtn")
            $btnEdit.VerticalAlignment = "Top"
            $btnEdit.ToolTip = "Edit command"
            $btnEdit.Tag = $cmdObj
            [Windows.Controls.Grid]::SetColumn($btnEdit, 1)

            $editIcon = New-Object Windows.Controls.TextBlock
            $editIcon.Text = [string][char]0xE70F  # Edit/pencil icon
            $editIcon.FontFamily = New-Object Windows.Media.FontFamily("Segoe MDL2 Assets")
            $editIcon.FontSize = 13
            $editIcon.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#6a8a9a")
            $btnEdit.Content = $editIcon

            $btnEdit.Add_Click({
                param($sender, $e)
                $editCmd = $sender.Tag
                Show-CommandDialog -Mode "Edit" -ExistingCmd $editCmd
            })

            $topRow.Children.Add($btnEdit) | Out-Null

            $stack.Children.Add($topRow) | Out-Null

            # Title
            $title = New-Object Windows.Controls.TextBlock
            $title.Text = $cmdName
            $title.FontSize = 14
            $title.FontWeight = "SemiBold"
            $title.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("White")
            $title.Margin = [Windows.Thickness]::new(0, 0, 0, 4)
            $stack.Children.Add($title) | Out-Null

            # Description
            $desc = New-Object Windows.Controls.TextBlock
            $desc.Text = $cmdDesc
            $desc.FontSize = 11
            $desc.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#6a8a9a")
            $desc.TextWrapping = "Wrap"
            $desc.Margin = [Windows.Thickness]::new(0, 0, 0, 14)
            $stack.Children.Add($desc) | Out-Null

            # Run button
            $btnRun = New-Object Windows.Controls.Button
            $btnRun.Style = $window.FindResource("RunBtn")
            $btnRun.Background = [Windows.Media.BrushConverter]::new().ConvertFrom($accentColor)
            $btnRun.HorizontalAlignment = "Left"

            $btnContent = New-Object Windows.Controls.TextBlock
            $btnContent.Text = "Run"
            $btnContent.FontSize = 12
            $btnContent.FontWeight = "SemiBold"
            $btnContent.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("White")
            $btnRun.Content = $btnContent

            # Store command data on the button via Tag (as a hashtable for the run logic)
            $runData = @{
                Title         = $cmdName
                Description   = $cmdDesc
                RequiresAdmin = $reqAdmin
                IsDestructive = $isDestructive
                IsToggle      = $isToggle
                CmdObj        = $cmdObj
            }
            $btnRun.Tag = $runData

            $btnRun.Add_Click({
                param($sender, $e)
                $rd = $sender.Tag

                if ($Global:IsRunning) {
                    [Windows.MessageBox]::Show("A command is currently running. Please wait for it to complete.",
                        "PC Plus 360 - Remediation Library", "OK", "Information")
                    return
                }

                # Read-only mode check
                if ($chkReadOnly.IsChecked -and $rd.IsDestructive) {
                    $txtOutput.AppendText("`r`n[$(Get-Date -Format 'HH:mm:ss')] BLOCKED: '$($rd.Title)' is a destructive operation and Read-Only mode is enabled.`r`n")
                    $txtOutput.ScrollToEnd()
                    Set-ResultIndicator "BLOCKED (Read-Only)" "#f39c12"
                    Write-RemediationLog "BLOCKED by Read-Only mode: $($rd.Title)" "WARN"
                    return
                }

                # Admin check
                if ($rd.RequiresAdmin -and -not $Global:IsAdmin) {
                    $txtOutput.AppendText("`r`n[$(Get-Date -Format 'HH:mm:ss')] ERROR: '$($rd.Title)' requires Administrator privileges.`r`n")
                    $txtOutput.ScrollToEnd()
                    Set-ResultIndicator "FAILED (No Admin)" "#e74c3c"
                    Write-RemediationLog "BLOCKED - no admin: $($rd.Title)" "ERROR"
                    return
                }

                $Global:IsRunning = $true
                Set-RunStatus "Running: $($rd.Title)..." "#f39c12"
                Set-ResultIndicator "" "#ffffff"

                $txtOutput.AppendText("`r`n" + ("=" * 70) + "`r`n")
                $txtOutput.AppendText("[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] RUNNING: $($rd.Title)`r`n")
                $txtOutput.AppendText(("=" * 70) + "`r`n`r`n")
                $txtOutput.ScrollToEnd()

                Write-RemediationLog "START: $($rd.Title)" "INFO"

                # Create restore point if checked and command is destructive
                if ($chkRestorePoint.IsChecked -and $rd.IsDestructive) {
                    $txtOutput.AppendText("[$(Get-Date -Format 'HH:mm:ss')] Creating restore point...`r`n")
                    $txtOutput.ScrollToEnd()
                    try {
                        Enable-ComputerRestore -Drive "C:\" -ErrorAction SilentlyContinue
                        Checkpoint-Computer -Description "PC Plus Remediation - $($rd.Title)" -RestorePointType "MODIFY_SETTINGS" -ErrorAction Stop
                        $txtOutput.AppendText("[$(Get-Date -Format 'HH:mm:ss')] Restore point created successfully.`r`n`r`n")
                        Write-RemediationLog "Restore point created for: $($rd.Title)" "INFO"
                    } catch {
                        $txtOutput.AppendText("[$(Get-Date -Format 'HH:mm:ss')] Warning: Could not create restore point - $($_.Exception.Message)`r`n")
                        $txtOutput.AppendText("[$(Get-Date -Format 'HH:mm:ss')] Continuing without restore point...`r`n`r`n")
                        Write-RemediationLog "Restore point failed: $($_.Exception.Message)" "WARN"
                    }
                    $txtOutput.ScrollToEnd()
                }

                # Get the scriptblock to run
                $scriptToRun = Get-CommandScriptBlock $rd.CmdObj
                $cmdTitle = $rd.Title

                # Run command in background using runspace for UI responsiveness
                $runspace = [System.Management.Automation.PowerShell]::Create()
                $runspace.AddScript({
                    param($ScriptBlock, $ScriptDir, $Company, $Phone, $Website)
                    $Global:ScriptDir = $ScriptDir
                    $COMPANY = $Company
                    $PHONE = $Phone
                    $WEBSITE = $Website
                    $output = [System.Collections.ArrayList]::new()
                    # Redirect Write-Output by invoking the block
                    try {
                        $result = & $ScriptBlock *>&1
                        foreach ($line in $result) {
                            $output.Add([string]$line) | Out-Null
                        }
                        # Check if last output line has a result
                        $success = $true
                        foreach ($line in $output) {
                            if ($line -match '\[RESULT\].*fail') { $success = $false }
                        }
                        return @{ Output = $output; Success = $success }
                    } catch {
                        $output.Add("ERROR: $($_.Exception.Message)") | Out-Null
                        return @{ Output = $output; Success = $false }
                    }
                }).AddArgument($scriptToRun).AddArgument($Global:ScriptDir).AddArgument($COMPANY).AddArgument($PHONE).AddArgument($WEBSITE) | Out-Null

                $handle = $runspace.BeginInvoke()

                # Poll for completion using a DispatcherTimer
                $timer = New-Object System.Windows.Threading.DispatcherTimer
                $timer.Interval = [TimeSpan]::FromMilliseconds(250)

                # Store references needed in the timer callback
                $timerState = @{
                    Runspace  = $runspace
                    Handle    = $handle
                    Timer     = $timer
                    CmdTitle  = $cmdTitle
                    Window    = $window
                    TxtOutput = $txtOutput
                }

                $timer.Add_Tick({
                    $ts = $timerState
                    if ($ts.Handle.IsCompleted) {
                        $ts.Timer.Stop()

                        try {
                            $result = $ts.Runspace.EndInvoke($ts.Handle)
                            if ($result -and $result.Count -gt 0) {
                                $data = $result[0]
                                if ($data -is [hashtable] -or $data -is [PSCustomObject]) {
                                    $outputLines = if ($data -is [hashtable]) { $data.Output } else { $data.Output }
                                    $success = if ($data -is [hashtable]) { $data.Success } else { $data.Success }

                                    foreach ($line in $outputLines) {
                                        $ts.TxtOutput.AppendText("$line`r`n")
                                    }

                                    if ($success) {
                                        Set-RunStatus "Completed: $($ts.CmdTitle)" "#27ae60"
                                        Set-ResultIndicator "PASS" "#27ae60"
                                        Write-RemediationLog "PASS: $($ts.CmdTitle)" "INFO"
                                    } else {
                                        Set-RunStatus "Failed: $($ts.CmdTitle)" "#e74c3c"
                                        Set-ResultIndicator "FAIL" "#e74c3c"
                                        Write-RemediationLog "FAIL: $($ts.CmdTitle)" "ERROR"
                                    }

                                    # Save result
                                    $Global:RunResults.Add(@{
                                        Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                                        Command   = $ts.CmdTitle
                                        Category  = $Global:CurrentCategory
                                        Success   = $success
                                    }) | Out-Null
                                } else {
                                    # Unexpected result format
                                    $ts.TxtOutput.AppendText("[Result data in unexpected format]`r`n")
                                    Set-RunStatus "Completed: $($ts.CmdTitle)" "#f39c12"
                                    Set-ResultIndicator "DONE" "#f39c12"
                                }
                            } else {
                                $ts.TxtOutput.AppendText("[No output received]`r`n")
                                Set-RunStatus "Completed: $($ts.CmdTitle)" "#f39c12"
                                Set-ResultIndicator "DONE" "#f39c12"
                            }
                        } catch {
                            $ts.TxtOutput.AppendText("`r`nERROR: $($_.Exception.Message)`r`n")
                            Set-RunStatus "Error: $($ts.CmdTitle)" "#e74c3c"
                            Set-ResultIndicator "ERROR" "#e74c3c"
                            Write-RemediationLog "ERROR in $($ts.CmdTitle) : $($_.Exception.Message)" "ERROR"
                        }

                        $ts.TxtOutput.AppendText("`r`n" + ("-" * 70) + "`r`n")
                        $ts.TxtOutput.ScrollToEnd()
                        $ts.Runspace.Dispose()
                        $Global:IsRunning = $false
                    }
                })

                $timer.Start()
            })

            $stack.Children.Add($btnRun) | Out-Null
            $card.Child = $stack
            $pnlCards.Children.Add($card) | Out-Null
        }
    }

    # ─────────────────────────────────────────────────────────────────────────
    # ADD COMMAND BUTTON
    # ─────────────────────────────────────────────────────────────────────────
    $btnAddCommand.Add_Click({
        Show-CommandDialog -Mode "Add"
    })

    # ─────────────────────────────────────────────────────────────────────────
    # EXPORT LOG
    # ─────────────────────────────────────────────────────────────────────────
    $btnExportLog.Add_Click({
        $saveDialog = New-Object Microsoft.Win32.SaveFileDialog
        $saveDialog.Title = "Export Remediation Log"
        $saveDialog.Filter = "Text Files (*.txt)|*.txt|All Files (*.*)|*.*"
        $saveDialog.FileName = "PCPlus-Remediation-$(Get-Date -Format 'yyyy-MM-dd-HHmm').txt"
        $saveDialog.InitialDirectory = $Global:ReportsDir

        if ($saveDialog.ShowDialog()) {
            try {
                $reportContent = @()
                $reportContent += "PC PLUS COMPUTING - REMEDIATION REPORT"
                $reportContent += "======================================"
                $reportContent += "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
                $reportContent += "Computer:  $env:COMPUTERNAME"
                $reportContent += "User:      $env:USERNAME"
                $reportContent += ""

                if ($Global:RunResults.Count -gt 0) {
                    $reportContent += "RESULTS SUMMARY"
                    $reportContent += "---------------"
                    foreach ($r in $Global:RunResults) {
                        $status = if ($r.Success) { "PASS" } else { "FAIL" }
                        $reportContent += "[$($r.Timestamp)] [$status] $($r.Category) / $($r.Command)"
                    }
                    $reportContent += ""
                }

                $reportContent += "FULL OUTPUT LOG"
                $reportContent += "---------------"
                $reportContent += $txtOutput.Text
                $reportContent += ""
                $reportContent += "---"
                $reportContent += "$COMPANY | $PHONE | $WEBSITE"

                $reportContent | Out-File -FilePath $saveDialog.FileName -Encoding UTF8
                [Windows.MessageBox]::Show("Log exported to:`n$($saveDialog.FileName)",
                    "PC Plus 360 - Export Complete", "OK", "Information")
                Write-RemediationLog "Log exported to: $($saveDialog.FileName)" "INFO"
            } catch {
                [Windows.MessageBox]::Show("Failed to export log:`n$($_.Exception.Message)",
                    "PC Plus 360 - Export Error", "OK", "Error")
            }
        }
    })

    # ─────────────────────────────────────────────────────────────────────────
    # CLEAR LOG
    # ─────────────────────────────────────────────────────────────────────────
    $btnClearLog.Add_Click({
        $txtOutput.Clear()
        $lblRunStatus.Text = ""
        $lblResultIndicator.Text = ""
        $txtOutput.AppendText("[$(Get-Date -Format 'HH:mm:ss')] Output cleared.`r`n")
    })

    # ─────────────────────────────────────────────────────────────────────────
    # INITIAL LOAD
    # ─────────────────────────────────────────────────────────────────────────
    $txtOutput.AppendText("PC Plus Computing - Remediation Library v$VERSION`r`n")
    $txtOutput.AppendText("$PHONE | $WEBSITE`r`n")
    $txtOutput.AppendText("=" * 70 + "`r`n")
    $txtOutput.AppendText("[$(Get-Date -Format 'HH:mm:ss')] Ready. Select a category and click Run on any fix.`r`n")
    $txtOutput.AppendText("[$(Get-Date -Format 'HH:mm:ss')] Admin: $($Global:IsAdmin) | Computer: $env:COMPUTERNAME | User: $env:USERNAME`r`n")
    $txtOutput.AppendText("[$(Get-Date -Format 'HH:mm:ss')] Commands loaded: $($Global:CommandList.Count) from remediation-commands.json`r`n")
    if ($chkReadOnly.IsChecked) {
        $txtOutput.AppendText("[$(Get-Date -Format 'HH:mm:ss')] READ-ONLY mode active - destructive operations will be blocked.`r`n")
    }
    $txtOutput.AppendText("`r`n")

    # Build sidebar and show first category
    Build-SidebarButtons

    $firstCategory = @($Global:Categories.Keys)[0]
    if ($firstCategory) {
        Show-Category $firstCategory
    }

    Write-RemediationLog "Remediation Library UI opened. Admin=$($Global:IsAdmin), Commands=$($Global:CommandList.Count)" "INFO"

    # Show the window
    $window.ShowDialog() | Out-Null

    Write-DebugLog "UI closed."
    Write-RemediationLog "Remediation Library UI closed." "INFO"

    # Save results report on close if there were any runs
    if ($Global:RunResults.Count -gt 0) {
        $autoReport = Join-Path $Global:ReportsDir "PCPlus-Remediation-$(Get-Date -Format 'yyyy-MM-dd-HHmm').txt"
        try {
            $reportLines = @()
            $reportLines += "PC PLUS COMPUTING - REMEDIATION REPORT"
            $reportLines += "======================================"
            $reportLines += "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
            $reportLines += "Computer:  $env:COMPUTERNAME"
            $reportLines += "User:      $env:USERNAME"
            $reportLines += ""
            $reportLines += "RESULTS SUMMARY"
            $reportLines += "---------------"
            $passed = 0
            $failed = 0
            foreach ($r in $Global:RunResults) {
                $status = if ($r.Success) { "PASS"; $passed++ } else { "FAIL"; $failed++ }
                $reportLines += "[$($r.Timestamp)] [$status] $($r.Category) / $($r.Command)"
            }
            $reportLines += ""
            $reportLines += "Total: $($Global:RunResults.Count) | Passed: $passed | Failed: $failed"
            $reportLines += ""
            $reportLines += "---"
            $reportLines += "$COMPANY | $PHONE | $WEBSITE"
            $reportLines | Out-File -FilePath $autoReport -Encoding UTF8
            Write-DebugLog "Auto-saved report to: $autoReport"
        } catch {
            Write-DebugLog "Failed to auto-save report: $($_.Exception.Message)"
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# ENTRY POINT
# ─────────────────────────────────────────────────────────────────────────────
Write-DebugLog "Launching Remediation Library UI..."
Show-RemediationUI
Write-DebugLog "Script finished."

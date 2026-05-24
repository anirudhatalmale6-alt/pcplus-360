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
.NOTES
    Company:  PC Plus Computing
    Website:  pcpluscomputing.com
    Phone:    604-760-1662 | 236-500-2700
    Version:  1.0.0
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
$VERSION      = "1.0.0"

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
# REMEDIATION CATEGORIES & COMMANDS
# ─────────────────────────────────────────────────────────────────────────────
$Global:Categories = [ordered]@{
    "Windows Repair" = @(
        @{
            Id          = "sfc_scan"
            Title       = "SFC Scan"
            Description = "Runs System File Checker to scan and repair protected system files."
            Icon        = [char]0xE90F  # shield
            RequiresAdmin = $true
            IsDestructive = $true
            ScriptBlock = {
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
        },
        @{
            Id          = "dism_repair"
            Title       = "DISM Repair"
            Description = "Repairs the Windows component store using DISM online cleanup."
            Icon        = [char]0xE8E5  # repair
            RequiresAdmin = $true
            IsDestructive = $true
            ScriptBlock = {
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
        },
        @{
            Id          = "wu_reset"
            Title       = "Windows Update Reset"
            Description = "Stops update services, renames cache folders, and restarts services."
            Icon        = [char]0xE895  # sync
            RequiresAdmin = $true
            IsDestructive = $true
            ScriptBlock = {
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
        },
        @{
            Id          = "store_repair"
            Title       = "Store App Repair"
            Description = "Re-registers all Windows Store apps to fix broken or missing apps."
            Icon        = [char]0xE8F1  # apps
            RequiresAdmin = $true
            IsDestructive = $true
            ScriptBlock = {
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
        }
    )

    "Network Fixes" = @(
        @{
            Id          = "flush_dns"
            Title       = "Flush DNS"
            Description = "Clears the DNS resolver cache to fix domain resolution issues."
            Icon        = [char]0xE968  # globe
            RequiresAdmin = $true
            IsDestructive = $false
            ScriptBlock = {
                Write-Output "Flushing DNS resolver cache..."
                $output = & ipconfig /flushdns 2>&1
                $output | ForEach-Object { Write-Output $_ }
                Write-Output "`n[RESULT] DNS cache flushed successfully."
                return $true
            }
        },
        @{
            Id          = "reset_winsock"
            Title       = "Reset Winsock"
            Description = "Resets Winsock catalog to fix network connectivity issues. Requires reboot."
            Icon        = [char]0xE839  # network
            RequiresAdmin = $true
            IsDestructive = $true
            ScriptBlock = {
                Write-Output "Resetting Winsock catalog..."
                $output = & netsh winsock reset 2>&1
                $output | ForEach-Object { Write-Output $_ }
                Write-Output "`nNOTE: A system reboot is required for changes to take effect."
                Write-Output "[RESULT] Winsock reset completed. Please reboot."
                return $true
            }
        },
        @{
            Id          = "reset_tcpip"
            Title       = "Reset TCP/IP"
            Description = "Resets TCP/IP stack to fix IP connectivity issues. Requires reboot."
            Icon        = [char]0xE774  # ethernet
            RequiresAdmin = $true
            IsDestructive = $true
            ScriptBlock = {
                Write-Output "Resetting TCP/IP stack..."
                $output = & netsh int ip reset 2>&1
                $output | ForEach-Object { Write-Output $_ }
                Write-Output "`nNOTE: A system reboot is required for changes to take effect."
                Write-Output "[RESULT] TCP/IP reset completed. Please reboot."
                return $true
            }
        },
        @{
            Id          = "renew_ip"
            Title       = "Renew IP"
            Description = "Releases and renews IP address from DHCP server."
            Icon        = [char]0xE895  # refresh
            RequiresAdmin = $true
            IsDestructive = $false
            ScriptBlock = {
                Write-Output "Releasing IP address..."
                $output = & ipconfig /release 2>&1
                $output | ForEach-Object { Write-Output $_ }
                Write-Output "`nRenewing IP address..."
                $output2 = & ipconfig /renew 2>&1
                $output2 | ForEach-Object { Write-Output $_ }
                Write-Output "`n[RESULT] IP release/renew completed."
                return $true
            }
        }
    )

    "Security Fixes" = @(
        @{
            Id          = "enable_defender"
            Title       = "Enable Defender"
            Description = "Enables Windows Defender real-time monitoring protection."
            Icon        = [char]0xE83D  # shield check
            RequiresAdmin = $true
            IsDestructive = $false
            IsToggle    = $true
            ScriptBlock = {
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
        },
        @{
            Id          = "update_defender"
            Title       = "Update Defender"
            Description = "Downloads latest Windows Defender signature updates."
            Icon        = [char]0xE896  # download
            RequiresAdmin = $true
            IsDestructive = $false
            ScriptBlock = {
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
        },
        @{
            Id          = "enable_firewall"
            Title       = "Enable Firewall"
            Description = "Enables Windows Firewall for all profiles (Domain, Public, Private)."
            Icon        = [char]0xE946  # firewall
            RequiresAdmin = $true
            IsDestructive = $false
            IsToggle    = $true
            ScriptBlock = {
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
        },
        @{
            Id          = "check_bitlocker"
            Title       = "Check BitLocker"
            Description = "Reads BitLocker encryption status for all volumes (read-only)."
            Icon        = [char]0xE72E  # lock
            RequiresAdmin = $true
            IsDestructive = $false
            ScriptBlock = {
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
        }
    )

    "Performance" = @(
        @{
            Id          = "clean_temp"
            Title       = "Clean Temp Files"
            Description = "Removes temporary files from user and system temp folders, runs Disk Cleanup."
            Icon        = [char]0xE74D  # delete
            RequiresAdmin = $true
            IsDestructive = $true
            ScriptBlock = {
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
        },
        @{
            Id          = "disable_startup"
            Title       = "Disable Startup Apps"
            Description = "Lists startup programs with option to see which ones can be disabled."
            Icon        = [char]0xE768  # list
            RequiresAdmin = $false
            IsDestructive = $false
            ScriptBlock = {
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
        },
        @{
            Id          = "disk_health"
            Title       = "Disk Health Check"
            Description = "Runs chkdsk /scan on C: to check disk integrity without making changes."
            Icon        = [char]0xEDA2  # hard drive
            RequiresAdmin = $true
            IsDestructive = $false
            ScriptBlock = {
                Write-Output "Running disk health check on C: drive..."
                Write-Output "This may take several minutes.`n"
                $output = & chkdsk C: /scan 2>&1
                $output | ForEach-Object { Write-Output $_ }
                Write-Output "`n[RESULT] Disk health check completed."
                return $true
            }
        }
    )

    "Printer Fixes" = @(
        @{
            Id          = "restart_spooler"
            Title       = "Restart Print Spooler"
            Description = "Restarts the Windows Print Spooler service to fix stuck print jobs."
            Icon        = [char]0xE749  # printer
            RequiresAdmin = $true
            IsDestructive = $false
            ScriptBlock = {
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
        },
        @{
            Id          = "clear_print_queue"
            Title       = "Clear Print Queue"
            Description = "Stops spooler, clears all pending print jobs, then restarts spooler."
            Icon        = [char]0xE74D  # delete
            RequiresAdmin = $true
            IsDestructive = $true
            ScriptBlock = {
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
        }
    )

    "PC Plus Tools" = @(
        @{
            Id          = "run_audit"
            Title       = "Run 175-Point Audit"
            Description = "Launches the PC Plus Security Audit (PCPlus-SecurityAudit.ps1)."
            Icon        = [char]0xE9D5  # checklist
            RequiresAdmin = $true
            IsDestructive = $false
            ScriptBlock = {
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
        },
        @{
            Id          = "install_badge"
            Title       = "Install Support Badge"
            Description = "Deploys the PC Plus support badge on this system (coming soon)."
            Icon        = [char]0xEB51  # badge
            RequiresAdmin = $true
            IsDestructive = $false
            ScriptBlock = {
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
        },
        @{
            Id          = "security_bulletin"
            Title       = "Show Security Bulletin"
            Description = "Displays current security advisories and recommendations."
            Icon        = [char]0xE783  # info
            RequiresAdmin = $false
            IsDestructive = $false
            ScriptBlock = {
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
    )
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

        <!-- ═══════════════ SIDEBAR ═══════════════ -->
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
                        <TextBlock x:Name="lblVersion" Text="v1.0.0" FontSize="10" Foreground="#2596be" FontFamily="Consolas"/>
                        <TextBlock Text="604-760-1662 | 236-500-2700" FontSize="8.5" Foreground="#4a6a7a" Margin="0,3,0,0"/>
                        <TextBlock Text="pcpluscomputing.com" FontSize="8.5" Foreground="#3a5a6a"/>
                    </StackPanel>
                </Border>

                <!-- Category nav -->
                <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
                    <StackPanel Margin="4,12,4,8">
                        <TextBlock Text="  CATEGORIES" FontSize="9" FontWeight="Bold" Foreground="#4a6a7a" Margin="8,0,0,8"/>

                        <Button x:Name="btnCatWindowsRepair" Style="{StaticResource SideNav}">
                            <StackPanel Orientation="Horizontal">
                                <TextBlock Text="&#xE90F;" FontFamily="Segoe MDL2 Assets" FontSize="16" Foreground="#2596be" VerticalAlignment="Center" Margin="0,0,10,0"/>
                                <TextBlock Text="Windows Repair" FontSize="12.5" Foreground="#c0d4e8" FontWeight="SemiBold"/>
                            </StackPanel>
                        </Button>

                        <Button x:Name="btnCatNetwork" Style="{StaticResource SideNav}">
                            <StackPanel Orientation="Horizontal">
                                <TextBlock Text="&#xE968;" FontFamily="Segoe MDL2 Assets" FontSize="16" Foreground="#3bbde0" VerticalAlignment="Center" Margin="0,0,10,0"/>
                                <TextBlock Text="Network Fixes" FontSize="12.5" Foreground="#c0d4e8" FontWeight="SemiBold"/>
                            </StackPanel>
                        </Button>

                        <Button x:Name="btnCatSecurity" Style="{StaticResource SideNav}">
                            <StackPanel Orientation="Horizontal">
                                <TextBlock Text="&#xE83D;" FontFamily="Segoe MDL2 Assets" FontSize="16" Foreground="#27ae60" VerticalAlignment="Center" Margin="0,0,10,0"/>
                                <TextBlock Text="Security Fixes" FontSize="12.5" Foreground="#c0d4e8" FontWeight="SemiBold"/>
                            </StackPanel>
                        </Button>

                        <Button x:Name="btnCatPerformance" Style="{StaticResource SideNav}">
                            <StackPanel Orientation="Horizontal">
                                <TextBlock Text="&#xE9D9;" FontFamily="Segoe MDL2 Assets" FontSize="16" Foreground="#f39c12" VerticalAlignment="Center" Margin="0,0,10,0"/>
                                <TextBlock Text="Performance" FontSize="12.5" Foreground="#c0d4e8" FontWeight="SemiBold"/>
                            </StackPanel>
                        </Button>

                        <Button x:Name="btnCatPrinter" Style="{StaticResource SideNav}">
                            <StackPanel Orientation="Horizontal">
                                <TextBlock Text="&#xE749;" FontFamily="Segoe MDL2 Assets" FontSize="16" Foreground="#e879f9" VerticalAlignment="Center" Margin="0,0,10,0"/>
                                <TextBlock Text="Printer Fixes" FontSize="12.5" Foreground="#c0d4e8" FontWeight="SemiBold"/>
                            </StackPanel>
                        </Button>

                        <Button x:Name="btnCatPCPlus" Style="{StaticResource SideNav}">
                            <StackPanel Orientation="Horizontal">
                                <TextBlock Text="&#xE9D5;" FontFamily="Segoe MDL2 Assets" FontSize="16" Foreground="#e74c3c" VerticalAlignment="Center" Margin="0,0,10,0"/>
                                <TextBlock Text="PC Plus Tools" FontSize="12.5" Foreground="#c0d4e8" FontWeight="SemiBold"/>
                            </StackPanel>
                        </Button>

                        <Border Height="1" Background="#152238" Margin="8,14,8,14"/>

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

        <!-- ═══════════════ MAIN CONTENT ═══════════════ -->
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
    $txtOutput          = $window.FindName("txtOutput")
    $lblRunStatus       = $window.FindName("lblRunStatus")
    $lblResultIndicator = $window.FindName("lblResultIndicator")
    $chkRestorePoint    = $window.FindName("chkRestorePoint")
    $chkReadOnly        = $window.FindName("chkReadOnly")
    $badgeAdmin         = $window.FindName("badgeAdmin")
    $lblAdminStatus     = $window.FindName("lblAdminStatus")
    $badgeMode          = $window.FindName("badgeMode")
    $lblModeStatus      = $window.FindName("lblModeStatus")

    $btnCatWindowsRepair = $window.FindName("btnCatWindowsRepair")
    $btnCatNetwork       = $window.FindName("btnCatNetwork")
    $btnCatSecurity      = $window.FindName("btnCatSecurity")
    $btnCatPerformance   = $window.FindName("btnCatPerformance")
    $btnCatPrinter       = $window.FindName("btnCatPrinter")
    $btnCatPCPlus        = $window.FindName("btnCatPCPlus")
    $btnExportLog        = $window.FindName("btnExportLog")
    $btnClearLog         = $window.FindName("btnClearLog")

    # Sidebar button list for active-state management
    $sidebarButtons = @{
        "Windows Repair" = $btnCatWindowsRepair
        "Network Fixes"  = $btnCatNetwork
        "Security Fixes" = $btnCatSecurity
        "Performance"    = $btnCatPerformance
        "Printer Fixes"  = $btnCatPrinter
        "PC Plus Tools"  = $btnCatPCPlus
    }

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
    $Global:CurrentCategory = "Windows Repair"
    $Global:RunResults = [System.Collections.ArrayList]::new()

    # Category descriptions
    $categoryDescriptions = @{
        "Windows Repair" = "System file repair and Windows component fixes"
        "Network Fixes"  = "DNS, Winsock, TCP/IP, and IP address fixes"
        "Security Fixes" = "Defender, Firewall, and BitLocker management"
        "Performance"    = "Temp cleanup, startup optimization, and disk checks"
        "Printer Fixes"  = "Print spooler and queue management"
        "PC Plus Tools"  = "PC Plus Computing internal tools and reports"
    }

    # Category icons for cards
    $categoryCardColors = @{
        "Windows Repair" = "#2596be"
        "Network Fixes"  = "#3bbde0"
        "Security Fixes" = "#27ae60"
        "Performance"    = "#f39c12"
        "Printer Fixes"  = "#e879f9"
        "PC Plus Tools"  = "#e74c3c"
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
    # BUILD CARDS FOR A CATEGORY
    # ─────────────────────────────────────────────────────────────────────────
    function Show-Category {
        param([string]$CategoryName)

        if ($Global:IsRunning) { return }

        $Global:CurrentCategory = $CategoryName
        $lblCategoryTitle.Text = $CategoryName
        $lblCategoryDesc.Text = $categoryDescriptions[$CategoryName]

        # Update sidebar active states
        foreach ($key in $sidebarButtons.Keys) {
            if ($key -eq $CategoryName) {
                $sidebarButtons[$key].Style = $window.FindResource("SideNavActive")
            } else {
                $sidebarButtons[$key].Style = $window.FindResource("SideNav")
            }
        }

        # Clear and rebuild cards
        $pnlCards.Children.Clear()

        $commands = $Global:Categories[$CategoryName]
        $accentColor = $categoryCardColors[$CategoryName]

        foreach ($cmd in $commands) {
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

            # Icon row
            $iconRow = New-Object Windows.Controls.StackPanel
            $iconRow.Orientation = "Horizontal"
            $iconRow.Margin = [Windows.Thickness]::new(0, 0, 0, 10)

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
            $iconText.Text = [string]$cmd.Icon
            $iconBorder.Child = $iconText

            $iconRow.Children.Add($iconBorder) | Out-Null

            # Destructive / toggle badge
            if ($cmd.IsDestructive) {
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
            } elseif ($cmd.IsToggle) {
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

            $stack.Children.Add($iconRow) | Out-Null

            # Title
            $title = New-Object Windows.Controls.TextBlock
            $title.Text = $cmd.Title
            $title.FontSize = 14
            $title.FontWeight = "SemiBold"
            $title.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("White")
            $title.Margin = [Windows.Thickness]::new(0, 0, 0, 4)
            $stack.Children.Add($title) | Out-Null

            # Description
            $desc = New-Object Windows.Controls.TextBlock
            $desc.Text = $cmd.Description
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

            # Store command data on the button via Tag
            $btnRun.Tag = $cmd

            $btnRun.Add_Click({
                param($sender, $e)
                $command = $sender.Tag

                if ($Global:IsRunning) {
                    [Windows.MessageBox]::Show("A command is currently running. Please wait for it to complete.",
                        "PC Plus 360 - Remediation Library", "OK", "Information")
                    return
                }

                # Read-only mode check
                if ($chkReadOnly.IsChecked -and $command.IsDestructive) {
                    $txtOutput.AppendText("`r`n[$(Get-Date -Format 'HH:mm:ss')] BLOCKED: '$($command.Title)' is a destructive operation and Read-Only mode is enabled.`r`n")
                    $txtOutput.ScrollToEnd()
                    Set-ResultIndicator "BLOCKED (Read-Only)" "#f39c12"
                    Write-RemediationLog "BLOCKED by Read-Only mode: $($command.Title)" "WARN"
                    return
                }

                # Admin check
                if ($command.RequiresAdmin -and -not $Global:IsAdmin) {
                    $txtOutput.AppendText("`r`n[$(Get-Date -Format 'HH:mm:ss')] ERROR: '$($command.Title)' requires Administrator privileges.`r`n")
                    $txtOutput.ScrollToEnd()
                    Set-ResultIndicator "FAILED (No Admin)" "#e74c3c"
                    Write-RemediationLog "BLOCKED - no admin: $($command.Title)" "ERROR"
                    return
                }

                $Global:IsRunning = $true
                Set-RunStatus "Running: $($command.Title)..." "#f39c12"
                Set-ResultIndicator "" "#ffffff"

                $txtOutput.AppendText("`r`n" + ("=" * 70) + "`r`n")
                $txtOutput.AppendText("[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] RUNNING: $($command.Title)`r`n")
                $txtOutput.AppendText(("=" * 70) + "`r`n`r`n")
                $txtOutput.ScrollToEnd()

                Write-RemediationLog "START: $($command.Title)" "INFO"

                # Create restore point if checked and command is destructive
                if ($chkRestorePoint.IsChecked -and $command.IsDestructive) {
                    $txtOutput.AppendText("[$(Get-Date -Format 'HH:mm:ss')] Creating restore point...`r`n")
                    $txtOutput.ScrollToEnd()
                    try {
                        Enable-ComputerRestore -Drive "C:\" -ErrorAction SilentlyContinue
                        Checkpoint-Computer -Description "PC Plus Remediation - $($command.Title)" -RestorePointType "MODIFY_SETTINGS" -ErrorAction Stop
                        $txtOutput.AppendText("[$(Get-Date -Format 'HH:mm:ss')] Restore point created successfully.`r`n`r`n")
                        Write-RemediationLog "Restore point created for: $($command.Title)" "INFO"
                    } catch {
                        $txtOutput.AppendText("[$(Get-Date -Format 'HH:mm:ss')] Warning: Could not create restore point - $($_.Exception.Message)`r`n")
                        $txtOutput.AppendText("[$(Get-Date -Format 'HH:mm:ss')] Continuing without restore point...`r`n`r`n")
                        Write-RemediationLog "Restore point failed: $($_.Exception.Message)" "WARN"
                    }
                    $txtOutput.ScrollToEnd()
                }

                # Run command in background using runspace for UI responsiveness
                $scriptToRun = $command.ScriptBlock
                $cmdTitle = $command.Title

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
                }.GetNewClosure())

                $timer.Start()
            })

            $stack.Children.Add($btnRun) | Out-Null
            $card.Child = $stack
            $pnlCards.Children.Add($card) | Out-Null
        }
    }

    # ─────────────────────────────────────────────────────────────────────────
    # SIDEBAR CLICK HANDLERS
    # ─────────────────────────────────────────────────────────────────────────
    $btnCatWindowsRepair.Add_Click({ Show-Category "Windows Repair" })
    $btnCatNetwork.Add_Click({ Show-Category "Network Fixes" })
    $btnCatSecurity.Add_Click({ Show-Category "Security Fixes" })
    $btnCatPerformance.Add_Click({ Show-Category "Performance" })
    $btnCatPrinter.Add_Click({ Show-Category "Printer Fixes" })
    $btnCatPCPlus.Add_Click({ Show-Category "PC Plus Tools" })

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
    if ($chkReadOnly.IsChecked) {
        $txtOutput.AppendText("[$(Get-Date -Format 'HH:mm:ss')] READ-ONLY mode active - destructive operations will be blocked.`r`n")
    }
    $txtOutput.AppendText("`r`n")

    # Show Windows Repair by default
    Show-Category "Windows Repair"

    Write-RemediationLog "Remediation Library UI opened. Admin=$($Global:IsAdmin)" "INFO"

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

<#
.SYNOPSIS
    PC Plus Computing - Hardware & Security Audit Tool
.DESCRIPTION
    Standalone PowerShell script that performs a comprehensive hardware diagnostic
    and security audit on Windows 10/11 PCs, generating a branded PDF report.
    Runs from a USB drive with no installation required.
.NOTES
    Company:  PC Plus Computing
    Website:  pcpluscomputing.com
    Phone:    604-760-1662
    Version:  2.0.0
    Requires: PowerShell 5.1+, Windows 10/11, Administrator privileges
#>

#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

# ─────────────────────────────────────────────────────────────────────────────
# ELEVATION CHECK - Relaunch as admin if needed
# ─────────────────────────────────────────────────────────────────────────────
function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-IsAdmin)) {
    try {
        $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$($MyInvocation.MyCommand.Definition)`""
        Start-Process powershell.exe -ArgumentList $arguments -Verb RunAs
    } catch {
        [System.Windows.Forms.MessageBox]::Show(
            "This tool requires Administrator privileges.`nPlease right-click and 'Run as Administrator'.",
            "PC Plus Hardware & Security Audit - Elevation Required",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
    }
    exit
}

# ─────────────────────────────────────────────────────────────────────────────
# ASSEMBLIES
# ─────────────────────────────────────────────────────────────────────────────
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# ─────────────────────────────────────────────────────────────────────────────
# BRANDING CONSTANTS
# ─────────────────────────────────────────────────────────────────────────────
$COMPANY_NAME    = "PC Plus Computing"
$COMPANY_WEBSITE = "pcpluscomputing.com"
$COMPANY_PHONE   = "604-760-1662"
$COLOR_NAVY      = "#0a1628"
$COLOR_ACCENT    = "#2596be"
$COLOR_GREEN     = "#27ae60"
$COLOR_RED       = "#e74c3c"
$COLOR_ORANGE    = "#f39c12"
$COLOR_LIGHT_BG  = "#f8f9fa"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
if ([string]::IsNullOrEmpty($ScriptDir)) { $ScriptDir = Get-Location }

# ─────────────────────────────────────────────────────────────────────────────
# LAUNCH DIALOG
# ─────────────────────────────────────────────────────────────────────────────
function Show-LaunchDialog {
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "PC Plus Computing - Hardware & Security Audit"
    $form.Size = New-Object System.Drawing.Size(500, 380)
    $form.StartPosition = "CenterScreen"
    $form.FormBorderStyle = "FixedDialog"
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.BackColor = [System.Drawing.Color]::White
    $form.Font = New-Object System.Drawing.Font("Segoe UI", 9)

    # Header panel
    $header = New-Object System.Windows.Forms.Panel
    $header.Dock = "Top"
    $header.Height = 60
    $header.BackColor = [System.Drawing.ColorTranslator]::FromHtml($COLOR_NAVY)
    $form.Controls.Add($header)

    $headerLabel = New-Object System.Windows.Forms.Label
    $headerLabel.Text = "PC PLUS COMPUTING - SECURITY AUDIT"
    $headerLabel.ForeColor = [System.Drawing.Color]::White
    $headerLabel.Font = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
    $headerLabel.AutoSize = $false
    $headerLabel.Size = New-Object System.Drawing.Size(480, 60)
    $headerLabel.TextAlign = "MiddleCenter"
    $header.Controls.Add($headerLabel)

    $y = 80

    # Customer Name
    $lblCust = New-Object System.Windows.Forms.Label
    $lblCust.Text = "Customer Name *"
    $lblCust.Location = New-Object System.Drawing.Point(30, $y)
    $lblCust.Size = New-Object System.Drawing.Size(200, 20)
    $form.Controls.Add($lblCust)
    $y += 22

    $txtCust = New-Object System.Windows.Forms.TextBox
    $txtCust.Location = New-Object System.Drawing.Point(30, $y)
    $txtCust.Size = New-Object System.Drawing.Size(420, 24)
    $form.Controls.Add($txtCust)
    $y += 38

    # Contact Name
    $lblContact = New-Object System.Windows.Forms.Label
    $lblContact.Text = "Contact Name (optional)"
    $lblContact.Location = New-Object System.Drawing.Point(30, $y)
    $lblContact.Size = New-Object System.Drawing.Size(200, 20)
    $form.Controls.Add($lblContact)
    $y += 22

    $txtContact = New-Object System.Windows.Forms.TextBox
    $txtContact.Location = New-Object System.Drawing.Point(30, $y)
    $txtContact.Size = New-Object System.Drawing.Size(420, 24)
    $form.Controls.Add($txtContact)
    $y += 38

    # Technician Name
    $lblTech = New-Object System.Windows.Forms.Label
    $lblTech.Text = "Technician Name"
    $lblTech.Location = New-Object System.Drawing.Point(30, $y)
    $lblTech.Size = New-Object System.Drawing.Size(200, 20)
    $form.Controls.Add($lblTech)
    $y += 22

    $txtTech = New-Object System.Windows.Forms.TextBox
    $txtTech.Text = "PC Plus Computing"
    $txtTech.Location = New-Object System.Drawing.Point(30, $y)
    $txtTech.Size = New-Object System.Drawing.Size(420, 24)
    $form.Controls.Add($txtTech)
    $y += 38

    # Output Folder
    $lblOut = New-Object System.Windows.Forms.Label
    $lblOut.Text = "Output Folder"
    $lblOut.Location = New-Object System.Drawing.Point(30, $y)
    $lblOut.Size = New-Object System.Drawing.Size(200, 20)
    $form.Controls.Add($lblOut)
    $y += 22

    $txtOut = New-Object System.Windows.Forms.TextBox
    $txtOut.Text = Join-Path $ScriptDir "PCPlus-Audits"
    $txtOut.Location = New-Object System.Drawing.Point(30, $y)
    $txtOut.Size = New-Object System.Drawing.Size(350, 24)
    $form.Controls.Add($txtOut)

    $btnBrowse = New-Object System.Windows.Forms.Button
    $btnBrowse.Text = "..."
    $btnBrowse.Location = New-Object System.Drawing.Point(385, $y)
    $btnBrowse.Size = New-Object System.Drawing.Size(65, 24)
    $btnBrowse.Add_Click({
        $fbd = New-Object System.Windows.Forms.FolderBrowserDialog
        $fbd.SelectedPath = $txtOut.Text
        if ($fbd.ShowDialog() -eq "OK") { $txtOut.Text = $fbd.SelectedPath }
    })
    $form.Controls.Add($btnBrowse)
    $y += 45

    # Start button
    $btnStart = New-Object System.Windows.Forms.Button
    $btnStart.Text = "Start Audit"
    $btnStart.Location = New-Object System.Drawing.Point(170, $y)
    $btnStart.Size = New-Object System.Drawing.Size(140, 38)
    $btnStart.BackColor = [System.Drawing.ColorTranslator]::FromHtml($COLOR_ACCENT)
    $btnStart.ForeColor = [System.Drawing.Color]::White
    $btnStart.FlatStyle = "Flat"
    $btnStart.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
    $btnStart.FlatAppearance.BorderSize = 0
    $btnStart.Add_Click({
        if ([string]::IsNullOrWhiteSpace($txtCust.Text)) {
            [System.Windows.Forms.MessageBox]::Show("Customer Name is required.", "Validation", "OK", "Warning")
            return
        }
        $form.Tag = @{
            CustomerName  = $txtCust.Text.Trim()
            ContactName   = $txtContact.Text.Trim()
            TechName      = $txtTech.Text.Trim()
            OutputFolder  = $txtOut.Text.Trim()
        }
        $form.DialogResult = "OK"
        $form.Close()
    })
    $form.Controls.Add($btnStart)
    $form.AcceptButton = $btnStart

    if ($form.ShowDialog() -eq "OK") {
        return $form.Tag
    }
    return $null
}

# ─────────────────────────────────────────────────────────────────────────────
# PROGRESS WINDOW
# ─────────────────────────────────────────────────────────────────────────────
function New-ProgressWindow {
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "PC Plus Computing - Scanning..."
    $form.Size = New-Object System.Drawing.Size(520, 200)
    $form.StartPosition = "CenterScreen"
    $form.FormBorderStyle = "FixedDialog"
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.ControlBox = $false
    $form.BackColor = [System.Drawing.Color]::White
    $form.Font = New-Object System.Drawing.Font("Segoe UI", 9)

    $header = New-Object System.Windows.Forms.Panel
    $header.Dock = "Top"
    $header.Height = 40
    $header.BackColor = [System.Drawing.ColorTranslator]::FromHtml($COLOR_NAVY)
    $form.Controls.Add($header)

    $hl = New-Object System.Windows.Forms.Label
    $hl.Text = "HARDWARE & SECURITY AUDIT IN PROGRESS"
    $hl.ForeColor = [System.Drawing.Color]::White
    $hl.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
    $hl.AutoSize = $false
    $hl.Size = New-Object System.Drawing.Size(500, 40)
    $hl.TextAlign = "MiddleCenter"
    $header.Controls.Add($hl)

    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Name = "StatusLabel"
    $lbl.Text = "Initializing..."
    $lbl.Location = New-Object System.Drawing.Point(30, 60)
    $lbl.Size = New-Object System.Drawing.Size(450, 25)
    $form.Controls.Add($lbl)

    $pb = New-Object System.Windows.Forms.ProgressBar
    $pb.Name = "ProgressBar"
    $pb.Location = New-Object System.Drawing.Point(30, 95)
    $pb.Size = New-Object System.Drawing.Size(445, 28)
    $pb.Minimum = 0
    $pb.Maximum = 100
    $pb.Style = "Continuous"
    $form.Controls.Add($pb)

    $pctLbl = New-Object System.Windows.Forms.Label
    $pctLbl.Name = "PctLabel"
    $pctLbl.Text = "0%"
    $pctLbl.Location = New-Object System.Drawing.Point(30, 128)
    $pctLbl.Size = New-Object System.Drawing.Size(450, 20)
    $pctLbl.TextAlign = "MiddleCenter"
    $form.Controls.Add($pctLbl)

    $form.Show()
    $form.Refresh()
    return $form
}

function Update-Progress {
    param($Form, [string]$Status, [int]$Percent)
    $Form.Controls["StatusLabel"].Text = $Status
    $Form.Controls["ProgressBar"].Value = [Math]::Min($Percent, 100)
    $Form.Controls["PctLabel"].Text = "$Percent%"
    $Form.Refresh()
    [System.Windows.Forms.Application]::DoEvents()
}

# ─────────────────────────────────────────────────────────────────────────────
# SAFE WRAPPERS
# ─────────────────────────────────────────────────────────────────────────────
function Invoke-SafeCheck {
    param([scriptblock]$ScriptBlock, $Default = "Unable to determine")
    try { return (& $ScriptBlock) } catch { return $Default }
}

function Get-RegistryValue {
    param([string]$Path, [string]$Name, $Default = $null)
    try {
        $val = Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop
        return $val.$Name
    } catch { return $Default }
}

# ─────────────────────────────────────────────────────────────────────────────
# AUDIT FUNCTIONS
# ─────────────────────────────────────────────────────────────────────────────

function Get-SystemInfo {
    $os = Get-CimInstance Win32_OperatingSystem
    $cs = Get-CimInstance Win32_ComputerSystem
    $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
    $bios = Get-CimInstance Win32_BIOS

    $uptime = (Get-Date) - $os.LastBootUpTime
    $uptimeStr = "{0}d {1}h {2}m" -f $uptime.Days, $uptime.Hours, $uptime.Minutes

    $disks = @()
    Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" | ForEach-Object {
        $healthStatus = Invoke-SafeCheck {
            $phys = Get-PhysicalDisk -ErrorAction Stop
            if ($phys) { ($phys | Select-Object -First 1).HealthStatus } else { "Unknown" }
        } "Unknown"
        $disks += @{
            Drive    = $_.DeviceID
            Size     = [math]::Round($_.Size / 1GB, 1)
            Free     = [math]::Round($_.FreeSpace / 1GB, 1)
            UsedPct  = if ($_.Size -gt 0) { [math]::Round((($_.Size - $_.FreeSpace) / $_.Size) * 100, 1) } else { 0 }
            Health   = $healthStatus
        }
    }

    return @{
        ComputerName = $cs.Name
        OSVersion    = $os.Caption
        OSBuild      = $os.BuildNumber
        Architecture = $os.OSArchitecture
        CPUModel     = $cpu.Name.Trim()
        CPUCores     = $cpu.NumberOfCores
        CPUThreads   = $cpu.NumberOfLogicalProcessors
        RAMTotal     = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
        RAMFree      = [math]::Round(($os.FreePhysicalMemory * 1KB) / 1GB, 1)
        Uptime       = $uptimeStr
        Domain       = if ($cs.PartOfDomain) { "Domain: $($cs.Domain)" } else { "Workgroup: $($cs.Workgroup)" }
        Serial       = $bios.SerialNumber
        Manufacturer = $cs.Manufacturer
        Model        = $cs.Model
        Disks        = $disks
    }
}

function Get-SecurityStatus {
    $results = @{}

    # Windows Defender
    $defender = Invoke-SafeCheck {
        $mpStatus = Get-MpComputerStatus -ErrorAction Stop
        @{
            RealTimeProtection = $mpStatus.RealTimeProtectionEnabled
            DefinitionsUpToDate = $mpStatus.AntivirusSignatureAge -le 7
            DefinitionAge = $mpStatus.AntivirusSignatureAge
            LastScan = $mpStatus.QuickScanEndTime
            EngineVersion = $mpStatus.AMEngineVersion
        }
    } @{ RealTimeProtection = $null; DefinitionsUpToDate = $null; DefinitionAge = $null; LastScan = $null; EngineVersion = $null }
    $results.Defender = $defender

    # Third-party AV
    $results.ThirdPartyAV = Invoke-SafeCheck {
        $avProducts = Get-CimInstance -Namespace "root\SecurityCenter2" -ClassName AntiVirusProduct -ErrorAction Stop
        $avList = @()
        foreach ($av in $avProducts) {
            if ($av.displayName -ne "Windows Defender") {
                $avList += $av.displayName
            }
        }
        $avList
    } @()

    # Firewall
    $results.Firewall = Invoke-SafeCheck {
        $fw = Get-NetFirewallProfile -ErrorAction Stop
        @{
            Domain  = ($fw | Where-Object { $_.Name -eq "Domain" }).Enabled
            Private = ($fw | Where-Object { $_.Name -eq "Private" }).Enabled
            Public  = ($fw | Where-Object { $_.Name -eq "Public" }).Enabled
        }
    } @{ Domain = $null; Private = $null; Public = $null }

    # UAC
    $results.UAC = Invoke-SafeCheck {
        $uacKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
        @{
            Enabled = (Get-RegistryValue $uacKey "EnableLUA" 0) -eq 1
            Level   = Get-RegistryValue $uacKey "ConsentPromptBehaviorAdmin" -1
        }
    } @{ Enabled = $null; Level = $null }

    # BitLocker
    $results.BitLocker = Invoke-SafeCheck {
        $blVolumes = Get-BitLockerVolume -ErrorAction Stop
        $blStatus = @{}
        foreach ($vol in $blVolumes) {
            $blStatus[$vol.MountPoint] = @{
                Status     = $vol.ProtectionStatus.ToString()
                Encryption = $vol.EncryptionPercentage
                Method     = $vol.EncryptionMethod.ToString()
            }
        }
        $blStatus
    } @{}

    # Windows Update
    $results.WindowsUpdate = Invoke-SafeCheck {
        $autoUpdate = (New-Object -ComObject Microsoft.Update.AutoUpdate -ErrorAction Stop)
        $lastCheck = $autoUpdate.Results.LastSearchSuccessDate
        @{
            LastCheck = $lastCheck
        }
    } @{ LastCheck = $null }

    # Secure Boot
    $results.SecureBoot = Invoke-SafeCheck {
        Confirm-SecureBootUEFI -ErrorAction Stop
    } $null

    # TPM
    $results.TPM = Invoke-SafeCheck {
        $tpm = Get-Tpm -ErrorAction Stop
        @{
            Present   = $tpm.TpmPresent
            Ready     = $tpm.TpmReady
            Version   = (Get-CimInstance -Namespace "root\cimv2\Security\MicrosoftTpm" -ClassName Win32_Tpm -ErrorAction Stop).SpecVersion
        }
    } @{ Present = $false; Ready = $false; Version = "Unknown" }

    # Password Policy
    $results.PasswordPolicy = Invoke-SafeCheck {
        $netAccounts = net accounts 2>&1
        $minLen = 0; $complexity = $false; $lockout = 0
        foreach ($line in $netAccounts) {
            if ($line -match "Minimum password length:\s+(\d+)") { $minLen = [int]$Matches[1] }
            if ($line -match "Lockout threshold:\s+(\w+)") {
                $lockout = if ($Matches[1] -eq "Never") { 0 } else { [int]$Matches[1] }
            }
        }
        # Check complexity via secedit export
        $tmpFile = [System.IO.Path]::GetTempFileName()
        secedit /export /cfg $tmpFile /quiet 2>$null
        if (Test-Path $tmpFile) {
            $secContent = Get-Content $tmpFile -Raw
            if ($secContent -match "PasswordComplexity\s*=\s*1") { $complexity = $true }
            Remove-Item $tmpFile -Force -ErrorAction SilentlyContinue
        }
        @{ MinLength = $minLen; Complexity = $complexity; LockoutThreshold = $lockout }
    } @{ MinLength = 0; Complexity = $false; LockoutThreshold = 0 }

    # Guest Account
    $results.GuestDisabled = Invoke-SafeCheck {
        $guest = Get-LocalUser -Name "Guest" -ErrorAction Stop
        -not $guest.Enabled
    } $null

    # Auto-Login
    $results.AutoLoginDisabled = Invoke-SafeCheck {
        $autoLogon = Get-RegistryValue "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" "AutoAdminLogon" "0"
        $autoLogon -ne "1"
    } $null

    # Remote Desktop
    $results.RDP = Invoke-SafeCheck {
        $rdpEnabled = (Get-RegistryValue "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server" "fDenyTSConnections" 1) -eq 0
        $nla = Get-RegistryValue "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" "UserAuthentication" 0
        @{ Enabled = $rdpEnabled; NLA = $nla -eq 1 }
    } @{ Enabled = $null; NLA = $null }

    # SMBv1
    $results.SMBv1Disabled = Invoke-SafeCheck {
        $smb1 = Get-SmbServerConfiguration -ErrorAction Stop
        -not $smb1.EnableSMB1Protocol
    } $null

    # NetBIOS
    $results.NetBIOS = Invoke-SafeCheck {
        $adapters = Get-CimInstance Win32_NetworkAdapterConfiguration -Filter "IPEnabled=True"
        $nbEnabled = $false
        foreach ($a in $adapters) {
            # TcpipNetbiosOptions: 0=default(usually enabled), 1=enabled, 2=disabled
            if ($a.TcpipNetbiosOptions -ne 2) { $nbEnabled = $true; break }
        }
        $nbEnabled
    } $null

    # Local Admin Accounts
    $results.LocalAdmins = Invoke-SafeCheck {
        $admins = Get-LocalGroupMember -Group "Administrators" -ErrorAction Stop
        @{
            Count = $admins.Count
            Names = ($admins | ForEach-Object { $_.Name }) -join ", "
        }
    } @{ Count = 0; Names = "Unable to determine" }

    # ── Privacy & Data Protection ──
    $results.Privacy = @{}
    $results.Privacy.TelemetryMinimal = Invoke-SafeCheck {
        $t1 = (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Name "AllowTelemetry" -ErrorAction SilentlyContinue).AllowTelemetry
        $t2 = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection" -Name "AllowTelemetry" -ErrorAction SilentlyContinue).AllowTelemetry
        ($null -ne $t1 -and $t1 -le 1) -or ($null -ne $t2 -and $t2 -le 1)
    } $false
    $results.Privacy.AdvertisingIdDisabled = Invoke-SafeCheck {
        $v = (Get-ItemProperty "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo" -Name "Enabled" -ErrorAction SilentlyContinue).Enabled
        $null -eq $v -or $v -ne 1
    } $true
    $results.Privacy.LocationDisabled = Invoke-SafeCheck {
        $cs = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location" -Name "Value" -ErrorAction SilentlyContinue).Value
        $svc = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\lfsvc\Service\Configuration" -Name "Status" -ErrorAction SilentlyContinue).Status
        ($cs -eq "Deny") -or ($null -ne $svc -and $svc -eq 0)
    } $false
    $results.Privacy.ActivityHistoryDisabled = Invoke-SafeCheck {
        $k = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"
        $feed = (Get-ItemProperty $k -Name "EnableActivityFeed" -ErrorAction SilentlyContinue).EnableActivityFeed
        $pub = (Get-ItemProperty $k -Name "PublishUserActivities" -ErrorAction SilentlyContinue).PublishUserActivities
        ($null -ne $feed -and $feed -ne 1) -or ($null -ne $pub -and $pub -ne 1)
    } $false
    $results.Privacy.CortanaDisabled = Invoke-SafeCheck {
        $v = (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" -Name "AllowCortana" -ErrorAction SilentlyContinue).AllowCortana
        ($null -ne $v -and $v -eq 0) -or (-not (Get-Process -Name "SearchUI","Cortana","Microsoft.Windows.Cortana" -ErrorAction SilentlyContinue))
    } $false
    $results.Privacy.FindMyDeviceEnabled = Invoke-SafeCheck {
        $v = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Settings\FindMyDevice\UserConsent" -Name "Value" -ErrorAction SilentlyContinue).Value
        $null -ne $v -and $v -eq 1
    } $false

    # ── Browser Security ──
    $results.BrowserSecurity = @{}
    $results.BrowserSecurity.ChromeNoSavedPasswords = Invoke-SafeCheck {
        $f = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Login Data"
        -not (Test-Path $f) -or (Get-Item $f -ErrorAction SilentlyContinue).Length -le 40960
    } $true
    $results.BrowserSecurity.EdgeNoSavedPasswords = Invoke-SafeCheck {
        $f = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Login Data"
        -not (Test-Path $f) -or (Get-Item $f -ErrorAction SilentlyContinue).Length -le 40960
    } $true
    $results.BrowserSecurity.SmartScreenEnabled = Invoke-SafeCheck {
        $v = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer" -Name "SmartScreenEnabled" -ErrorAction SilentlyContinue).SmartScreenEnabled
        $null -eq $v -or $v -ne "Off"
    } $true
    $results.BrowserSecurity.ExtensionCountOk = Invoke-SafeCheck {
        $count = 0
        $chromeExt = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Extensions"
        if (Test-Path $chromeExt) { $count += @(Get-ChildItem $chromeExt -Directory -ErrorAction SilentlyContinue).Count }
        $edgeExt = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Extensions"
        if (Test-Path $edgeExt) { $count += @(Get-ChildItem $edgeExt -Directory -ErrorAction SilentlyContinue).Count }
        $count -lt 15
    } $true

    # ── Network Hardening ──
    $results.NetworkHardening = @{}
    $results.NetworkHardening.NoOpenShares = Invoke-SafeCheck {
        $custom = Get-SmbShare -ErrorAction Stop | Where-Object { $_.Name -notmatch '^\w\$|^ADMIN\$|^IPC\$|^print\$' }
        ($custom | Measure-Object).Count -eq 0
    } $null
    $results.NetworkHardening.UPnPDisabled = Invoke-SafeCheck {
        $svc = Get-Service "SSDPSRV" -ErrorAction Stop
        $svc.Status -ne "Running"
    } $null
    $results.NetworkHardening.LLMNRDisabled = Invoke-SafeCheck {
        $v = (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient" -Name "EnableMulticast" -ErrorAction SilentlyContinue).EnableMulticast
        $null -ne $v -and $v -eq 0
    } $false
    $results.NetworkHardening.DoHEnabled = Invoke-SafeCheck {
        $v = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters" -Name "EnableAutoDoh" -ErrorAction SilentlyContinue).EnableAutoDoh
        $null -ne $v -and $v -ge 2
    } $false
    $results.NetworkHardening.RemoteAssistanceDisabled = Invoke-SafeCheck {
        $v = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Remote Assistance" -Name "fAllowToGetHelp" -ErrorAction SilentlyContinue).fAllowToGetHelp
        $null -ne $v -and $v -eq 0
    } $false

    # ── System Integrity ──
    $results.SystemIntegrity = @{}
    $results.SystemIntegrity.DriverSigEnforced = Invoke-SafeCheck {
        $bcd = bcdedit /enum "{current}" 2>&1 | Out-String
        $bcd -notmatch "testsigning\s+Yes"
    } $true
    $results.SystemIntegrity.PSScriptLogging = Invoke-SafeCheck {
        $v = (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging" -Name "EnableScriptBlockLogging" -ErrorAction SilentlyContinue).EnableScriptBlockLogging
        $null -ne $v -and $v -eq 1
    } $false
    $results.SystemIntegrity.LogonAuditEnabled = Invoke-SafeCheck {
        $out = auditpol /get /subcategory:"Logon" 2>&1 | Out-String
        $out -match "Success" -and $out -notmatch "No Auditing"
    } $false
    $results.SystemIntegrity.CredentialGuard = Invoke-SafeCheck {
        $dg = Get-CimInstance -ClassName Win32_DeviceGuard -Namespace "root\Microsoft\Windows\DeviceGuard" -ErrorAction Stop
        $dg.SecurityServicesRunning -contains 1
    } $false
    $results.SystemIntegrity.LSASSProtected = Invoke-SafeCheck {
        $v = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name "RunAsPPL" -ErrorAction SilentlyContinue).RunAsPPL
        $null -ne $v -and $v -eq 1
    } $false

    # ── Account Hygiene ──
    $results.AccountHygiene = @{}
    $results.AccountHygiene.NoStaleAccounts = Invoke-SafeCheck {
        $cutoff = (Get-Date).AddDays(-90)
        $stale = Get-LocalUser -ErrorAction Stop | Where-Object {
            $_.Enabled -and -not $_.SID.Value.EndsWith("-500") -and -not $_.SID.Value.EndsWith("-501") -and
            $null -ne $_.LastLogon -and $_.LastLogon -lt $cutoff
        }
        ($stale | Measure-Object).Count -eq 0
    } $true
    $results.AccountHygiene.NoEmptyPasswords = Invoke-SafeCheck {
        $users = Get-LocalUser -ErrorAction Stop | Where-Object { $_.Enabled }
        $bad = $users | Where-Object { $_.PasswordRequired -eq $false }
        ($bad | Measure-Object).Count -eq 0
    } $true
    $results.AccountHygiene.PasswordAgePolicy = Invoke-SafeCheck {
        $na = net accounts 2>&1 | Out-String
        if ($na -match "Maximum password age \(days\):\s+Unlimited") { $false } else { $true }
    } $false

    # ── Ransomware Protection ──
    $results.RansomwareProtection = @{}
    $results.RansomwareProtection.ControlledFolderAccess = Invoke-SafeCheck {
        $v = (Get-MpPreference -ErrorAction Stop).EnableControlledFolderAccess
        $v -eq 1 -or $v -eq 2
    } $false
    $results.RansomwareProtection.RecentRestorePoint = Invoke-SafeCheck {
        $cutoff = (Get-Date).AddDays(-30)
        $rp = Get-ComputerRestorePoint -ErrorAction Stop
        ($rp | Where-Object { [Management.ManagementDateTimeConverter]::ToDateTime($_.CreationTime) -gt $cutoff } | Measure-Object).Count -gt 0
    } $false
    $results.RansomwareProtection.NoSuspiciousScheduledTasks = Invoke-SafeCheck {
        $suspicious = Get-ScheduledTask -ErrorAction Stop | Where-Object { $_.State -ne "Disabled" } | ForEach-Object {
            $actions = $_.Actions | Where-Object { $_.Execute -match "\\Temp\\|\\AppData\\|encodedcommand|encodedCommand|-enc\s|-ec\s" }
            if ($actions) { $_.TaskName }
        }
        ($suspicious | Measure-Object).Count -eq 0
    } $true

    return $results
}

function Get-NetworkInfo {
    $results = @{}

    # Adapters
    $results.Adapters = Invoke-SafeCheck {
        $adapters = Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq "Up" }
        $adapterList = @()
        foreach ($a in $adapters) {
            $ipConfig = Get-NetIPAddress -InterfaceIndex $a.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
            $dnsServers = (Get-DnsClientServerAddress -InterfaceIndex $a.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).ServerAddresses
            $adapterList += @{
                Name = $a.Name
                MAC  = $a.MacAddress
                IP   = ($ipConfig | Select-Object -First 1).IPAddress
                DNS  = ($dnsServers -join ", ")
                Speed = "$([math]::Round($a.LinkSpeed.Replace(' Gbps','').Replace(' Mbps','') * 1, 0)) $($a.LinkSpeed -replace '[\d\s\.]+','')"
            }
        }
        $adapterList
    } @()

    # Open Ports
    $results.OpenPorts = Invoke-SafeCheck {
        $listening = Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
            Select-Object LocalAddress, LocalPort, OwningProcess |
            Sort-Object LocalPort -Unique
        $portList = @()
        foreach ($conn in ($listening | Select-Object -First 30)) {
            $procName = Invoke-SafeCheck { (Get-Process -Id $conn.OwningProcess -ErrorAction Stop).ProcessName } "Unknown"
            $portList += @{
                Port    = $conn.LocalPort
                Address = $conn.LocalAddress
                Process = $procName
            }
        }
        $portList
    } @()

    # WiFi
    $results.WiFi = Invoke-SafeCheck {
        $wifiOutput = netsh wlan show interfaces 2>&1
        $ssid = ""; $auth = ""; $cipher = ""
        foreach ($line in $wifiOutput) {
            if ($line -match "^\s+SSID\s+:\s+(.+)$") { $ssid = $Matches[1].Trim() }
            if ($line -match "Authentication\s+:\s+(.+)$") { $auth = $Matches[1].Trim() }
            if ($line -match "Cipher\s+:\s+(.+)$") { $cipher = $Matches[1].Trim() }
        }
        @{ SSID = $ssid; Authentication = $auth; Cipher = $cipher }
    } @{ SSID = "Not connected"; Authentication = "N/A"; Cipher = "N/A" }

    # Public IP
    $results.PublicIP = Invoke-SafeCheck {
        $response = Invoke-RestMethod -Uri "https://api.ipify.org?format=json" -TimeoutSec 5 -ErrorAction Stop
        $response.ip
    } "Unable to determine"

    return $results
}

function Get-SoftwareInfo {
    $results = @{}

    # Installed Software (from registry - fast method)
    $results.InstalledSoftware = Invoke-SafeCheck {
        $regPaths = @(
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
            "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
        )
        $software = @()
        foreach ($path in $regPaths) {
            Get-ItemProperty -Path $path -ErrorAction SilentlyContinue |
                Where-Object { $_.DisplayName -and $_.DisplayName.Trim() -ne "" } |
                ForEach-Object {
                    $software += @{
                        Name      = $_.DisplayName
                        Version   = $_.DisplayVersion
                        Publisher = $_.Publisher
                    }
                }
        }
        $software | Sort-Object { $_.Name } -Unique
    } @()

    # Startup Programs
    $results.StartupPrograms = Invoke-SafeCheck {
        $startups = @()
        # Registry Run keys
        $runKeys = @(
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run",
            "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
        )
        foreach ($key in $runKeys) {
            $props = Get-ItemProperty -Path $key -ErrorAction SilentlyContinue
            if ($props) {
                $props.PSObject.Properties | Where-Object { $_.Name -notlike "PS*" } | ForEach-Object {
                    $startups += @{ Name = $_.Name; Location = $key; Command = $_.Value }
                }
            }
        }
        # Startup folder
        $startupFolder = [System.IO.Path]::Combine($env:APPDATA, "Microsoft\Windows\Start Menu\Programs\Startup")
        if (Test-Path $startupFolder) {
            Get-ChildItem $startupFolder -File -ErrorAction SilentlyContinue | ForEach-Object {
                $startups += @{ Name = $_.Name; Location = "Startup Folder"; Command = $_.FullName }
            }
        }
        $startups
    } @()

    # Services
    $results.RunningServices = Invoke-SafeCheck {
        (Get-Service | Where-Object { $_.Status -eq "Running" }).Count
    } 0

    # Browser Extensions
    $results.BrowserExtensions = Invoke-SafeCheck {
        $extCount = @{ Chrome = 0; Edge = 0 }
        # Chrome
        $chromePath = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Extensions"
        if (Test-Path $chromePath) {
            $extCount.Chrome = (Get-ChildItem $chromePath -Directory -ErrorAction SilentlyContinue).Count
        }
        # Edge
        $edgePath = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Extensions"
        if (Test-Path $edgePath) {
            $extCount.Edge = (Get-ChildItem $edgePath -Directory -ErrorAction SilentlyContinue).Count
        }
        $extCount
    } @{ Chrome = 0; Edge = 0 }

    return $results
}

function Get-MissingPatches {
    return Invoke-SafeCheck {
        $updateSession = New-Object -ComObject Microsoft.Update.Session
        $updateSearcher = $updateSession.CreateUpdateSearcher()
        $searchResult = $updateSearcher.Search("IsInstalled=0 AND Type='Software'")
        $patches = @()
        foreach ($update in $searchResult.Updates) {
            $severity = "Unknown"
            if ($update.MsrcSeverity) { $severity = $update.MsrcSeverity }
            $kbNumbers = @()
            foreach ($kb in $update.KBArticleIDs) { $kbNumbers += "KB$kb" }
            $patches += @{
                Title    = $update.Title
                KB       = ($kbNumbers -join ", ")
                Severity = $severity
                Size     = [math]::Round($update.MaxDownloadSize / 1MB, 1)
            }
        }
        $patches
    } @()
}

function Get-PerformanceInfo {
    $results = @{}

    $results.CPUUsage = Invoke-SafeCheck {
        [math]::Round((Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average, 0)
    } 0

    $results.RAMUsage = Invoke-SafeCheck {
        $os = Get-CimInstance Win32_OperatingSystem
        [math]::Round((($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / $os.TotalVisibleMemorySize) * 100, 0)
    } 0

    $results.ProcessCount = Invoke-SafeCheck { (Get-Process).Count } 0

    $results.TopRAMConsumers = Invoke-SafeCheck {
        Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 5 |
            ForEach-Object {
                @{
                    Name = $_.ProcessName
                    RAM  = [math]::Round($_.WorkingSet64 / 1MB, 0)
                    CPU  = [math]::Round($_.CPU, 1)
                }
            }
    } @()

    $results.DiskHealth = Invoke-SafeCheck {
        $physDisks = Get-PhysicalDisk -ErrorAction Stop
        $healthList = @()
        foreach ($d in $physDisks) {
            $healthList += @{
                Model  = $d.FriendlyName
                Media  = $d.MediaType
                Health = $d.HealthStatus
                Size   = [math]::Round($d.Size / 1GB, 0)
            }
        }
        $healthList
    } @()

    return $results
}

function Get-HardwareDiagnostics {
    $results = @{}

    # Detailed RAM info per slot
    $results.RAMSticks = Invoke-SafeCheck {
        $sticks = @()
        Get-CimInstance Win32_PhysicalMemory | ForEach-Object {
            $sticks += @{
                Bank         = $_.BankLabel
                Slot         = $_.DeviceLocator
                CapacityGB   = [math]::Round($_.Capacity / 1GB, 1)
                Speed        = "$($_.ConfiguredClockSpeed) MHz"
                Type         = switch ($_.SMBIOSMemoryType) { 26 { "DDR4" }; 34 { "DDR5" }; 24 { "DDR3" }; default { "Type $($_.SMBIOSMemoryType)" } }
                Manufacturer = if ($_.Manufacturer) { $_.Manufacturer.Trim() } else { "Unknown" }
                PartNumber   = if ($_.PartNumber) { $_.PartNumber.Trim() } else { "N/A" }
            }
        }
        $sticks
    } @()

    # Total RAM slots (populated vs empty)
    $results.RAMSlots = Invoke-SafeCheck {
        $total = (Get-CimInstance Win32_PhysicalMemoryArray | Measure-Object -Property MemoryDevices -Sum).Sum
        $used = (Get-CimInstance Win32_PhysicalMemory | Measure-Object).Count
        @{ Total = $total; Used = $used; Empty = ($total - $used) }
    } @{ Total = 0; Used = 0; Empty = 0 }

    # GPU / Display Adapters
    $results.GPUs = Invoke-SafeCheck {
        $gpus = @()
        Get-CimInstance Win32_VideoController | ForEach-Object {
            $gpus += @{
                Name       = $_.Name
                DriverVer  = $_.DriverVersion
                DriverDate = if ($_.DriverDate) { $_.DriverDate.ToString("yyyy-MM-dd") } else { "Unknown" }
                VRAM_MB    = if ($_.AdapterRAM -gt 0) { [math]::Round($_.AdapterRAM / 1MB, 0) } else { 0 }
                Resolution = "$($_.CurrentHorizontalResolution)x$($_.CurrentVerticalResolution)"
                Status     = $_.Status
            }
        }
        $gpus
    } @()

    # Battery (laptops)
    $results.Battery = Invoke-SafeCheck {
        $battery = Get-CimInstance Win32_Battery -ErrorAction Stop
        if ($battery) {
            $designCap = 0; $fullChargeCap = 0; $cycleCount = 0; $healthPct = 0
            try {
                $battReport = Get-CimInstance -Namespace "root\WMI" -ClassName BatteryFullChargedCapacity -ErrorAction Stop
                $battDesign = Get-CimInstance -Namespace "root\WMI" -ClassName BatteryStaticData -ErrorAction Stop
                $fullChargeCap = $battReport.FullChargedCapacity
                $designCap = $battDesign.DesignedCapacity
                if ($designCap -gt 0) { $healthPct = [math]::Round(($fullChargeCap / $designCap) * 100, 1) }
                $cycleCount = (Get-CimInstance -Namespace "root\WMI" -ClassName BatteryCycleCount -ErrorAction Stop).CycleCount
            } catch {}
            @{
                Present        = $true
                Status         = $battery.Status
                ChargePercent  = $battery.EstimatedChargeRemaining
                DesignCapacity = $designCap
                FullCharge     = $fullChargeCap
                HealthPercent  = $healthPct
                CycleCount     = $cycleCount
                EstRuntime     = if ($battery.EstimatedRunTime -and $battery.EstimatedRunTime -lt 71582788) {
                                    "$([math]::Floor($battery.EstimatedRunTime / 60))h $($battery.EstimatedRunTime % 60)m"
                                 } else { "On AC Power" }
            }
        } else { @{ Present = $false } }
    } @{ Present = $false }

    # Motherboard + BIOS
    $results.Motherboard = Invoke-SafeCheck {
        $board = Get-CimInstance Win32_BaseBoard
        $bios = Get-CimInstance Win32_BIOS
        @{
            Manufacturer = $board.Manufacturer
            Product      = $board.Product
            Serial       = $board.SerialNumber
            BIOSVendor   = $bios.Manufacturer
            BIOSVersion  = $bios.SMBIOSBIOSVersion
            BIOSDate     = if ($bios.ReleaseDate) { $bios.ReleaseDate.ToString("yyyy-MM-dd") } else { "Unknown" }
        }
    } @{}

    # USB Devices
    $results.USBDevices = Invoke-SafeCheck {
        $devices = @()
        Get-CimInstance Win32_USBControllerDevice -ErrorAction SilentlyContinue | ForEach-Object {
            $dep = [wmi]$_.Dependent
            if ($dep.Description -and $dep.Description -notmatch "Root Hub|Host Controller|Composite|USB Input") {
                $devices += @{ Name = $dep.Description; DeviceID = $dep.DeviceID; Status = $dep.Status }
            }
        }
        $devices | Select-Object -First 20
    } @()

    # Monitors
    $results.Monitors = Invoke-SafeCheck {
        $monitors = @()
        Get-CimInstance WmiMonitorID -Namespace root\wmi -ErrorAction Stop | ForEach-Object {
            $mfr = -join ($_.ManufacturerName | Where-Object { $_ -ne 0 } | ForEach-Object { [char]$_ })
            $name = -join ($_.UserFriendlyName | Where-Object { $_ -ne 0 } | ForEach-Object { [char]$_ })
            $serial = -join ($_.SerialNumberID | Where-Object { $_ -ne 0 } | ForEach-Object { [char]$_ })
            $monitors += @{
                Manufacturer = $mfr
                Model        = $name
                Serial       = $serial
                YearMade     = $_.YearOfManufacture
                WeekMade     = $_.WeekOfManufacture
            }
        }
        $monitors
    } @()

    # Audio devices
    $results.AudioDevices = Invoke-SafeCheck {
        $audio = @()
        Get-CimInstance Win32_SoundDevice | ForEach-Object {
            $audio += @{ Name = $_.Name; Status = $_.Status; Manufacturer = $_.Manufacturer }
        }
        $audio
    } @()

    # Printer info
    $results.Printers = Invoke-SafeCheck {
        $printers = @()
        Get-CimInstance Win32_Printer | ForEach-Object {
            $printers += @{
                Name    = $_.Name
                Default = $_.Default
                Status  = switch ($_.PrinterStatus) { 1 { "Other" }; 2 { "Unknown" }; 3 { "Idle" }; 4 { "Printing" }; 5 { "Warmup" }; default { "Status $($_.PrinterStatus)" } }
                Port    = $_.PortName
                Driver  = $_.DriverName
            }
        }
        $printers
    } @()

    # Temperature (best-effort, many desktops don't expose this)
    $results.Temperatures = Invoke-SafeCheck {
        $temps = @()
        Get-CimInstance MSAcpi_ThermalZoneTemperature -Namespace root/wmi -ErrorAction Stop | ForEach-Object {
            $celsius = [math]::Round(($_.CurrentTemperature / 10) - 273.15, 1)
            $temps += @{ Zone = $_.InstanceName; TempC = $celsius; TempF = [math]::Round(($celsius * 9/5) + 32, 1) }
        }
        $temps
    } @()

    # Disk SMART details
    $results.DiskSMART = Invoke-SafeCheck {
        $smartData = @()
        Get-PhysicalDisk | ForEach-Object {
            $reliability = Get-StorageReliabilityCounter -PhysicalDisk $_ -ErrorAction SilentlyContinue
            $smartData += @{
                Model           = $_.FriendlyName
                MediaType       = "$($_.MediaType)"
                BusType         = "$($_.BusType)"
                FirmwareVersion = $_.FirmwareVersion
                Health          = "$($_.HealthStatus)"
                OpStatus        = "$($_.OperationalStatus)"
                SizeGB          = [math]::Round($_.Size / 1GB, 0)
                PowerOnHours    = if ($reliability) { $reliability.PowerOnHours } else { "N/A" }
                Temperature     = if ($reliability -and $reliability.Temperature) { "$($reliability.Temperature)C" } else { "N/A" }
                ReadErrors      = if ($reliability) { $reliability.ReadErrorsTotal } else { "N/A" }
                WriteErrors     = if ($reliability) { $reliability.WriteErrorsTotal } else { "N/A" }
                Wear            = if ($reliability -and $reliability.Wear) { "$($reliability.Wear)%" } else { "N/A" }
            }
        }
        $smartData
    } @()

    # Device Manager errors
    $results.DeviceErrors = Invoke-SafeCheck {
        $errors = @()
        Get-CimInstance Win32_PnPEntity | Where-Object { $_.ConfigManagerErrorCode -ne 0 } | ForEach-Object {
            $errorDesc = switch ($_.ConfigManagerErrorCode) {
                1  { "Not configured" }
                3  { "Driver corrupted" }
                10 { "Cannot start" }
                12 { "Not enough resources" }
                14 { "Restart required" }
                22 { "Disabled" }
                28 { "Driver not installed" }
                31 { "Not working properly" }
                default { "Error code $($_.ConfigManagerErrorCode)" }
            }
            $errors += @{
                Device    = $_.Name
                ErrorCode = $_.ConfigManagerErrorCode
                Error     = $errorDesc
                Class     = $_.PNPClass
            }
        }
        $errors
    } @()

    # Windows license status
    $results.WindowsLicense = Invoke-SafeCheck {
        $lic = Get-CimInstance SoftwareLicensingProduct | Where-Object { $_.Name -like "*Windows*" -and $_.LicenseStatus -ne 0 } | Select-Object -First 1
        if ($lic) {
            $statusText = switch ($lic.LicenseStatus) { 0 { "Unlicensed" }; 1 { "Licensed" }; 2 { "OOBGrace" }; 3 { "OOTGrace" }; 4 { "NonGenuineGrace" }; 5 { "Notification" }; 6 { "ExtendedGrace" }; default { "Unknown" } }
            @{ Status = $statusText; Description = $lic.Description; PartialKey = $lic.PartialProductKey }
        } else {
            @{ Status = "Unknown"; Description = "N/A"; PartialKey = "N/A" }
        }
    } @{ Status = "Unknown"; Description = "N/A"; PartialKey = "N/A" }

    # Windows Product Key (from BIOS OEM key + registry backup key)
    $results.WindowsProductKey = Invoke-SafeCheck {
        $keys = @()
        # OA3 key embedded in BIOS/UEFI firmware (most modern PCs)
        $oa3Key = (Get-CimInstance -Query "SELECT OA3xOriginalProductKey FROM SoftwareLicensingService" -ErrorAction Stop).OA3xOriginalProductKey
        if ($oa3Key) { $keys += @{ Source = "BIOS/UEFI (OA3)"; Key = $oa3Key } }
        # Registry backup key (decoded from DigitalProductId)
        try {
            $regPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion"
            $dpid = (Get-ItemProperty -Path $regPath -ErrorAction Stop).DigitalProductId
            if ($dpid) {
                $keyOffset = 52
                $isWin8Plus = [math]::Floor($dpid[$keyOffset + 14] / 6) -band 1
                $dpid[$keyOffset + 14] = ($dpid[$keyOffset + 14] -band 0xF7) -bor (($isWin8Plus -band 2) * 4)
                $chars = "BCDFGHJKMPQRTVWXY2346789"
                $decoded = ""
                for ($i = 24; $i -ge 0; $i--) {
                    $cur = 0
                    for ($j = 14; $j -ge 0; $j--) {
                        $cur = $cur * 256
                        $cur = $dpid[$j + $keyOffset] + $cur
                        $dpid[$j + $keyOffset] = [math]::Floor($cur / 24)
                        $cur = $cur % 24
                    }
                    $decoded = $chars[$cur] + $decoded
                    if (($i % 5 -eq 0) -and ($i -ne 0)) { $decoded = "-" + $decoded }
                }
                if ($isWin8Plus) {
                    $last = $decoded[$decoded.Length - 1]
                    $keypart1 = $decoded.Substring(1, $decoded.IndexOf($last) - 1)
                    $insert = "N"
                    $decoded = $decoded.Replace($keypart1, $keypart1 + $insert)
                    if ($decoded.Length -gt 5 -and $decoded[0] -eq $decoded[$decoded.Length - 1]) {
                        $decoded = $decoded.Substring(1)
                    }
                }
                if ($decoded -and $decoded.Length -ge 25) {
                    $keys += @{ Source = "Registry (DigitalProductId)"; Key = $decoded }
                }
            }
        } catch {}
        # ProductId (not the key but useful reference)
        $productId = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -ErrorAction SilentlyContinue).ProductId
        if ($productId) { $keys += @{ Source = "Product ID"; Key = $productId } }
        $keys
    } @()

    # Office Product Keys
    $results.OfficeKeys = Invoke-SafeCheck {
        $officeKeys = @()
        $officePaths = @(
            "HKLM:\SOFTWARE\Microsoft\Office"
            "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Office"
        )
        $versions = @("16.0", "15.0", "14.0")
        foreach ($basePath in $officePaths) {
            foreach ($ver in $versions) {
                $regPath = "$basePath\$ver\Registration"
                if (Test-Path $regPath) {
                    Get-ChildItem $regPath -ErrorAction SilentlyContinue | ForEach-Object {
                        $props = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
                        if ($props.ProductName -and $props.DigitalProductID) {
                            $dpid = $props.DigitalProductID
                            $keyOffset = 52
                            $chars = "BCDFGHJKMPQRTVWXY2346789"
                            $decoded = ""
                            try {
                                for ($i = 24; $i -ge 0; $i--) {
                                    $cur = 0
                                    for ($j = 14; $j -ge 0; $j--) {
                                        $cur = $cur * 256
                                        $cur = $dpid[$j + $keyOffset] + $cur
                                        $dpid[$j + $keyOffset] = [math]::Floor($cur / 24)
                                        $cur = $cur % 24
                                    }
                                    $decoded = $chars[$cur] + $decoded
                                    if (($i % 5 -eq 0) -and ($i -ne 0)) { $decoded = "-" + $decoded }
                                }
                            } catch { $decoded = "" }
                            if ($decoded -and $decoded.Length -ge 25) {
                                $officeKeys += @{ Product = $props.ProductName; Key = $decoded; Version = $ver }
                            }
                        }
                    }
                }
            }
        }
        # Also try ospp.vbs for Office 365/2019+
        $osppPaths = @(
            "$env:ProgramFiles\Microsoft Office\Office16\ospp.vbs"
            "${env:ProgramFiles(x86)}\Microsoft Office\Office16\ospp.vbs"
        )
        foreach ($ospp in $osppPaths) {
            if (Test-Path $ospp) {
                try {
                    $osppOutput = cscript //nologo $ospp /dstatus 2>&1
                    $productName = ""; $lastChars = ""
                    foreach ($line in $osppOutput) {
                        if ($line -match "LICENSE NAME:\s*(.+)") { $productName = $Matches[1].Trim() }
                        if ($line -match "Last 5 characters of installed product key:\s*(\S+)") { $lastChars = $Matches[1].Trim() }
                    }
                    if ($productName -and $lastChars) {
                        $officeKeys += @{ Product = $productName; Key = "XXXXX-XXXXX-XXXXX-XXXXX-$lastChars"; Version = "365/2019+" }
                    }
                } catch {}
                break
            }
        }
        $officeKeys
    } @()

    # WiFi Passwords (all saved networks)
    $results.WiFiPasswords = Invoke-SafeCheck {
        $wifiList = @()
        $profiles = netsh wlan show profiles 2>&1
        $profileNames = @()
        foreach ($line in $profiles) {
            if ($line -match "All User Profile\s*:\s*(.+)$") {
                $profileNames += $Matches[1].Trim()
            }
        }
        foreach ($name in $profileNames) {
            $detail = netsh wlan show profile name="$name" key=clear 2>&1
            $password = ""; $auth = ""; $cipher = ""
            foreach ($line in $detail) {
                if ($line -match "Key Content\s*:\s*(.+)$") { $password = $Matches[1].Trim() }
                if ($line -match "Authentication\s*:\s*(.+)$") { $auth = $Matches[1].Trim() }
                if ($line -match "Cipher\s*:\s*(.+)$") { $cipher = $Matches[1].Trim() }
            }
            $wifiList += @{
                SSID     = $name
                Password = if ($password) { $password } else { "(Open/No password)" }
                Auth     = $auth
                Cipher   = $cipher
            }
        }
        $wifiList
    } @()

    # Other Software License Keys (common apps from registry)
    $results.SoftwareKeys = Invoke-SafeCheck {
        $swKeys = @()
        # Adobe products
        $adobePaths = @(
            "HKLM:\SOFTWARE\Adobe\Adobe Acrobat\DC\Registration"
            "HKLM:\SOFTWARE\WOW6432Node\Adobe\Adobe Acrobat\DC\Registration"
        )
        foreach ($p in $adobePaths) {
            if (Test-Path $p) {
                $serial = (Get-ItemProperty $p -ErrorAction SilentlyContinue).SERIAL
                if ($serial) { $swKeys += @{ Product = "Adobe Acrobat DC"; Key = $serial } }
            }
        }
        # VLC, WinRAR, etc. from Uninstall registry
        $uninstPaths = @(
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
            "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
        )
        foreach ($up in $uninstPaths) {
            Get-ItemProperty $up -ErrorAction SilentlyContinue | ForEach-Object {
                if ($_.DisplayName -and $_.ProductKey) {
                    $swKeys += @{ Product = $_.DisplayName; Key = $_.ProductKey }
                }
            }
        }
        $swKeys
    } @()

    return $results
}

# ─────────────────────────────────────────────────────────────────────────────
# SCORING ENGINE
# ─────────────────────────────────────────────────────────────────────────────
function Calculate-SecurityScore {
    param($Security, $MissingPatches)

    $score = 0
    $breakdown = @()

    # ── Core Security (71 pts) ──

    # Antivirus active (+10)
    $avActive = ($Security.Defender.RealTimeProtection -eq $true) -or ($Security.ThirdPartyAV.Count -gt 0)
    if ($avActive) { $score += 10 }
    $breakdown += @{ Check = "Antivirus Active"; Points = 10; Passed = $avActive }

    # Firewall all profiles (+10)
    $fwAll = ($Security.Firewall.Domain -eq $true) -and ($Security.Firewall.Private -eq $true) -and ($Security.Firewall.Public -eq $true)
    if ($fwAll) { $score += 10 }
    $breakdown += @{ Check = "Firewall All Profiles"; Points = 10; Passed = $fwAll }

    # BitLocker on C: (+7)
    $blC = $false
    if ($Security.BitLocker -and $Security.BitLocker["C:"]) {
        $blC = $Security.BitLocker["C:"].Status -eq "On"
    }
    if ($blC) { $score += 7 }
    $breakdown += @{ Check = "BitLocker on C:"; Points = 7; Passed = $blC }

    # No critical patches missing (+7)
    $criticalMissing = ($MissingPatches | Where-Object { $_.Severity -eq "Critical" }).Count
    $wuCurrent = $criticalMissing -eq 0
    if ($wuCurrent) { $score += 7 }
    $breakdown += @{ Check = "No Critical Patches Missing"; Points = 7; Passed = $wuCurrent }

    # UAC enabled (+4)
    $uacOk = $Security.UAC.Enabled -eq $true
    if ($uacOk) { $score += 4 }
    $breakdown += @{ Check = "UAC Enabled"; Points = 4; Passed = $uacOk }

    # Secure Boot (+4)
    $sbOk = $Security.SecureBoot -eq $true
    if ($sbOk) { $score += 4 }
    $breakdown += @{ Check = "Secure Boot"; Points = 4; Passed = $sbOk }

    # TPM Present (+4)
    $tpmOk = $Security.TPM.Present -eq $true
    if ($tpmOk) { $score += 4 }
    $breakdown += @{ Check = "TPM Present"; Points = 4; Passed = $tpmOk }

    # Password policy (+3)
    $pwOk = $Security.PasswordPolicy.MinLength -ge 8 -or $Security.PasswordPolicy.Complexity -eq $true
    if ($pwOk) { $score += 3 }
    $breakdown += @{ Check = "Password Policy"; Points = 3; Passed = $pwOk }

    # Guest disabled (+2)
    $guestOk = $Security.GuestDisabled -eq $true
    if ($guestOk) { $score += 2 }
    $breakdown += @{ Check = "Guest Disabled"; Points = 2; Passed = $guestOk }

    # No auto-login (+2)
    $noAutoLogin = $Security.AutoLoginDisabled -eq $true
    if ($noAutoLogin) { $score += 2 }
    $breakdown += @{ Check = "No Auto-Login"; Points = 2; Passed = $noAutoLogin }

    # RDP secure (+4)
    $rdpOk = ($Security.RDP.Enabled -eq $false) -or ($Security.RDP.NLA -eq $true)
    if ($rdpOk) { $score += 4 }
    $breakdown += @{ Check = "RDP Secure"; Points = 4; Passed = $rdpOk }

    # SMBv1 disabled (+4)
    $smbOk = $Security.SMBv1Disabled -eq $true
    if ($smbOk) { $score += 4 }
    $breakdown += @{ Check = "SMBv1 Disabled"; Points = 4; Passed = $smbOk }

    # Admin accounts <= 2 (+3)
    $adminOk = $Security.LocalAdmins.Count -le 2
    if ($adminOk) { $score += 3 }
    $breakdown += @{ Check = "Admin Accounts <=2"; Points = 3; Passed = $adminOk }

    # Real-time protection (+4)
    $rtpOk = $Security.Defender.RealTimeProtection -eq $true
    if ($rtpOk) { $score += 4 }
    $breakdown += @{ Check = "Real-Time Protection"; Points = 4; Passed = $rtpOk }

    # AV definitions current (+3)
    $defOk = $Security.Defender.DefinitionsUpToDate -eq $true
    if ($defOk) { $score += 3 }
    $breakdown += @{ Check = "AV Definitions Current"; Points = 3; Passed = $defOk }

    # ── Privacy & Data Protection (6 pts) ──

    $telOk = $Security.Privacy.TelemetryMinimal -eq $true
    if ($telOk) { $score += 1 }
    $breakdown += @{ Check = "Telemetry Minimal"; Points = 1; Passed = $telOk }

    $adIdOk = $Security.Privacy.AdvertisingIdDisabled -eq $true
    if ($adIdOk) { $score += 1 }
    $breakdown += @{ Check = "Advertising ID Disabled"; Points = 1; Passed = $adIdOk }

    $locOk = $Security.Privacy.LocationDisabled -eq $true
    if ($locOk) { $score += 1 }
    $breakdown += @{ Check = "Location Tracking Off"; Points = 1; Passed = $locOk }

    $actOk = $Security.Privacy.ActivityHistoryDisabled -eq $true
    if ($actOk) { $score += 1 }
    $breakdown += @{ Check = "Activity History Off"; Points = 1; Passed = $actOk }

    $cortOk = $Security.Privacy.CortanaDisabled -eq $true
    if ($cortOk) { $score += 1 }
    $breakdown += @{ Check = "Cortana/Copilot Disabled"; Points = 1; Passed = $cortOk }

    $fmdOk = $Security.Privacy.FindMyDeviceEnabled -eq $true
    if ($fmdOk) { $score += 1 }
    $breakdown += @{ Check = "Find My Device On"; Points = 1; Passed = $fmdOk }

    # ── Browser Security (4 pts) ──

    $chrPwOk = $Security.BrowserSecurity.ChromeNoSavedPasswords -eq $true
    if ($chrPwOk) { $score += 1 }
    $breakdown += @{ Check = "Chrome No Saved Passwords"; Points = 1; Passed = $chrPwOk }

    $edgPwOk = $Security.BrowserSecurity.EdgeNoSavedPasswords -eq $true
    if ($edgPwOk) { $score += 1 }
    $breakdown += @{ Check = "Edge No Saved Passwords"; Points = 1; Passed = $edgPwOk }

    $ssOk = $Security.BrowserSecurity.SmartScreenEnabled -eq $true
    if ($ssOk) { $score += 1 }
    $breakdown += @{ Check = "SmartScreen Enabled"; Points = 1; Passed = $ssOk }

    $extOk = $Security.BrowserSecurity.ExtensionCountOk -eq $true
    if ($extOk) { $score += 1 }
    $breakdown += @{ Check = "Browser Extensions <15"; Points = 1; Passed = $extOk }

    # ── Network Hardening (5 pts) ──

    $sharesOk = $Security.NetworkHardening.NoOpenShares -eq $true
    if ($sharesOk) { $score += 1 }
    $breakdown += @{ Check = "No Open Shares"; Points = 1; Passed = $sharesOk }

    $upnpOk = $Security.NetworkHardening.UPnPDisabled -eq $true
    if ($upnpOk) { $score += 1 }
    $breakdown += @{ Check = "UPnP Disabled"; Points = 1; Passed = $upnpOk }

    $llmnrOk = $Security.NetworkHardening.LLMNRDisabled -eq $true
    if ($llmnrOk) { $score += 1 }
    $breakdown += @{ Check = "LLMNR Disabled"; Points = 1; Passed = $llmnrOk }

    $dohOk = $Security.NetworkHardening.DoHEnabled -eq $true
    if ($dohOk) { $score += 1 }
    $breakdown += @{ Check = "DNS-over-HTTPS"; Points = 1; Passed = $dohOk }

    $raOk = $Security.NetworkHardening.RemoteAssistanceDisabled -eq $true
    if ($raOk) { $score += 1 }
    $breakdown += @{ Check = "Remote Assistance Off"; Points = 1; Passed = $raOk }

    # ── System Integrity (5 pts) ──

    $drvOk = $Security.SystemIntegrity.DriverSigEnforced -eq $true
    if ($drvOk) { $score += 1 }
    $breakdown += @{ Check = "Driver Sig Enforced"; Points = 1; Passed = $drvOk }

    $psLogOk = $Security.SystemIntegrity.PSScriptLogging -eq $true
    if ($psLogOk) { $score += 1 }
    $breakdown += @{ Check = "PS Script Logging"; Points = 1; Passed = $psLogOk }

    $logonOk = $Security.SystemIntegrity.LogonAuditEnabled -eq $true
    if ($logonOk) { $score += 1 }
    $breakdown += @{ Check = "Logon Audit Enabled"; Points = 1; Passed = $logonOk }

    $cgOk = $Security.SystemIntegrity.CredentialGuard -eq $true
    if ($cgOk) { $score += 1 }
    $breakdown += @{ Check = "Credential Guard"; Points = 1; Passed = $cgOk }

    $lsaOk = $Security.SystemIntegrity.LSASSProtected -eq $true
    if ($lsaOk) { $score += 1 }
    $breakdown += @{ Check = "LSASS Protected"; Points = 1; Passed = $lsaOk }

    # ── Account Hygiene (3 pts) ──

    $staleOk = $Security.AccountHygiene.NoStaleAccounts -eq $true
    if ($staleOk) { $score += 1 }
    $breakdown += @{ Check = "No Stale Accounts"; Points = 1; Passed = $staleOk }

    $emptyPwOk = $Security.AccountHygiene.NoEmptyPasswords -eq $true
    if ($emptyPwOk) { $score += 1 }
    $breakdown += @{ Check = "No Empty Passwords"; Points = 1; Passed = $emptyPwOk }

    $pwAgeOk = $Security.AccountHygiene.PasswordAgePolicy -eq $true
    if ($pwAgeOk) { $score += 1 }
    $breakdown += @{ Check = "Password Age Policy"; Points = 1; Passed = $pwAgeOk }

    # ── Ransomware Protection (6 pts) ──

    $cfaOk = $Security.RansomwareProtection.ControlledFolderAccess -eq $true
    if ($cfaOk) { $score += 2 }
    $breakdown += @{ Check = "Controlled Folder Access"; Points = 2; Passed = $cfaOk }

    $rpOk = $Security.RansomwareProtection.RecentRestorePoint -eq $true
    if ($rpOk) { $score += 2 }
    $breakdown += @{ Check = "Recent Restore Point"; Points = 2; Passed = $rpOk }

    $taskOk = $Security.RansomwareProtection.NoSuspiciousScheduledTasks -eq $true
    if ($taskOk) { $score += 2 }
    $breakdown += @{ Check = "No Suspicious Tasks"; Points = 2; Passed = $taskOk }

    # Grade
    $grade = switch ($true) {
        ($score -ge 90) { "A" }
        ($score -ge 80) { "B" }
        ($score -ge 70) { "C" }
        ($score -ge 60) { "D" }
        default         { "F" }
    }

    $gradeColor = switch ($grade) {
        "A" { $COLOR_GREEN }
        "B" { $COLOR_GREEN }
        "C" { $COLOR_ORANGE }
        "D" { $COLOR_ORANGE }
        "F" { $COLOR_RED }
    }

    return @{
        Score     = $score
        Grade     = $grade
        Color     = $gradeColor
        Breakdown = $breakdown
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# RECOMMENDATIONS ENGINE
# ─────────────────────────────────────────────────────────────────────────────
function Get-Recommendations {
    param($Scoring, $Security, $MissingPatches)

    $recs = @()
    foreach ($item in $Scoring.Breakdown) {
        if (-not $item.Passed) {
            $rec = switch ($item.Check) {
                # Core Security
                "Antivirus Active"             { "Install and activate antivirus immediately." }
                "Firewall All Profiles"        { "Enable Windows Firewall on all profiles." }
                "BitLocker on C:"              { "Enable BitLocker drive encryption." }
                "No Critical Patches Missing"  { "Install all pending critical updates." }
                "UAC Enabled"                  { "Re-enable User Account Control." }
                "Secure Boot"                  { "Enable Secure Boot in BIOS/UEFI." }
                "TPM Present"                  { "Hardware upgrade needed for TPM 2.0." }
                "Password Policy"              { "Set minimum 8 character password with complexity." }
                "Guest Disabled"               { "Disable the Guest account." }
                "No Auto-Login"                { "Disable automatic login." }
                "RDP Secure"                   { "Disable RDP or enable NLA." }
                "SMBv1 Disabled"               { "Disable SMBv1 (ransomware vulnerability)." }
                "Admin Accounts <=2"           { "Reduce admin accounts, use standard for daily use." }
                "Real-Time Protection"         { "Enable Windows Defender real-time protection." }
                "AV Definitions Current"       { "Update antivirus definitions." }
                # Privacy & Data Protection
                "Telemetry Minimal"            { "Set Windows telemetry to Security/Basic level in Settings > Privacy." }
                "Advertising ID Disabled"      { "Disable advertising ID in Settings > Privacy > General." }
                "Location Tracking Off"        { "Disable location tracking in Settings > Privacy > Location." }
                "Activity History Off"         { "Disable activity history in Settings > Privacy > Activity History." }
                "Cortana/Copilot Disabled"     { "Disable Cortana/Copilot data collection via Group Policy or Settings." }
                "Find My Device On"            { "Enable Find My Device in Settings > Update & Security > Find My Device." }
                # Browser Security
                "Chrome No Saved Passwords"    { "Remove saved passwords from Chrome, use a dedicated password manager." }
                "Edge No Saved Passwords"      { "Remove saved passwords from Edge, use a dedicated password manager." }
                "SmartScreen Enabled"          { "Enable SmartScreen in Windows Security > App & Browser Control." }
                "Browser Extensions <15"       { "Remove unnecessary browser extensions to reduce attack surface." }
                # Network Hardening
                "No Open Shares"               { "Remove unnecessary network shares or restrict permissions." }
                "UPnP Disabled"                { "Disable UPnP (SSDP Discovery service) to prevent port-mapping exploits." }
                "LLMNR Disabled"               { "Disable LLMNR via Group Policy to prevent name resolution poisoning." }
                "DNS-over-HTTPS"               { "Enable DNS-over-HTTPS in Settings > Network > DNS for encrypted lookups." }
                "Remote Assistance Off"        { "Disable Remote Assistance in System Properties > Remote." }
                # System Integrity
                "Driver Sig Enforced"          { "Disable test signing mode: bcdedit /set testsigning off" }
                "PS Script Logging"            { "Enable PowerShell script block logging via Group Policy." }
                "Logon Audit Enabled"          { "Enable logon auditing: auditpol /set /subcategory:Logon /success:enable" }
                "Credential Guard"             { "Enable Credential Guard via Group Policy (requires UEFI + Secure Boot)." }
                "LSASS Protected"              { "Enable LSASS protection: set RunAsPPL=1 in registry." }
                # Account Hygiene
                "No Stale Accounts"            { "Remove or disable local accounts not used in 90+ days." }
                "No Empty Passwords"           { "Set passwords on all local accounts or disable them." }
                "Password Age Policy"          { "Set a maximum password age policy (e.g. 90 days)." }
                # Ransomware Protection
                "Controlled Folder Access"     { "Enable Controlled Folder Access in Windows Security > Ransomware Protection." }
                "Recent Restore Point"         { "Create a System Restore point and enable automatic restore points." }
                "No Suspicious Tasks"          { "Review scheduled tasks running from temp/AppData directories." }
                default                        { "Review and fix this configuration." }
            }
            $severity = if ($item.Points -ge 7) { "Critical" } elseif ($item.Points -ge 3) { "Warning" } else { "Advisory" }
            $recs += @{ Check = $item.Check; Recommendation = $rec; Severity = $severity; Points = $item.Points }
        }
    }
    return ($recs | Sort-Object { switch ($_.Severity) { "Critical" { 0 } "Warning" { 1 } "Advisory" { 2 } } })
}

# ─────────────────────────────────────────────────────────────────────────────
# HTML REPORT GENERATION
# ─────────────────────────────────────────────────────────────────────────────
function Build-HTMLReport {
    param(
        $Params,
        $SystemInfo,
        $Security,
        $Network,
        $Software,
        $MissingPatches,
        $Performance,
        $Hardware,
        $Scoring,
        $Recommendations
    )

    $date = Get-Date -Format "yyyy-MM-dd"
    $dateFormatted = Get-Date -Format "MMMM dd, yyyy 'at' h:mm tt"
    $passCount = ($Scoring.Breakdown | Where-Object { $_.Passed }).Count
    $failCount = ($Scoring.Breakdown | Where-Object { -not $_.Passed }).Count
    $criticalCount = ($Recommendations | Where-Object { $_.Severity -eq "Critical" }).Count
    $warningCount = ($Recommendations | Where-Object { $_.Severity -eq "Warning" }).Count

    # Icons
    $iconPass = "&#10004;"     # checkmark
    $iconFail = "&#10008;"     # X
    $iconWarn = "&#9888;"      # warning triangle

    $top3Recs = $Recommendations | Select-Object -First 3

    # ── Build score circle SVG ──
    $dashOffset = 283 - (283 * $Scoring.Score / 100)
    $scoreSVG = @"
<svg viewBox="0 0 100 100" width="180" height="180">
  <circle cx="50" cy="50" r="45" fill="none" stroke="#e0e0e0" stroke-width="8"/>
  <circle cx="50" cy="50" r="45" fill="none" stroke="$($Scoring.Color)" stroke-width="8"
          stroke-dasharray="283" stroke-dashoffset="$dashOffset"
          transform="rotate(-90 50 50)" stroke-linecap="round"/>
  <text x="50" y="45" text-anchor="middle" font-size="22" font-weight="bold" fill="$($Scoring.Color)">$($Scoring.Score)</text>
  <text x="50" y="62" text-anchor="middle" font-size="14" font-weight="bold" fill="$($Scoring.Color)">$($Scoring.Grade)</text>
</svg>
"@

    # ── Breakdown rows ──
    $breakdownRows = ""
    foreach ($item in $Scoring.Breakdown) {
        $icon = if ($item.Passed) { "<span class='pass'>$iconPass</span>" } else { "<span class='fail'>$iconFail</span>" }
        $status = if ($item.Passed) { "PASS" } else { "FAIL" }
        $statusClass = if ($item.Passed) { "pass" } else { "fail" }
        $breakdownRows += "<tr><td>$icon</td><td>$($item.Check)</td><td class='$statusClass'>$status</td><td>$($item.Points) pts</td></tr>`n"
    }

    # ── Recommendations rows ──
    $recsHTML = ""
    foreach ($rec in $Recommendations) {
        $sevClass = switch ($rec.Severity) { "Critical" { "fail" } "Warning" { "warn" } default { "info" } }
        $sevIcon = switch ($rec.Severity) { "Critical" { "<span class='fail'>$iconFail</span>" } "Warning" { "<span class='warn'>$iconWarn</span>" } default { "<span class='warn'>$iconWarn</span>" } }
        $recsHTML += "<tr><td>$sevIcon</td><td class='$sevClass'><strong>$($rec.Severity)</strong></td><td>$($rec.Check)</td><td>$($rec.Recommendation)</td></tr>`n"
    }

    # ── System info table ──
    $diskRows = ""
    foreach ($d in $SystemInfo.Disks) {
        $usageClass = if ($d.UsedPct -gt 90) { "fail" } elseif ($d.UsedPct -gt 75) { "warn" } else { "pass" }
        $diskRows += "<tr><td>$($d.Drive)</td><td>$($d.Size) GB</td><td>$($d.Free) GB</td><td class='$usageClass'>$($d.UsedPct)%</td><td>$($d.Health)</td></tr>`n"
    }

    # ── Security detail rows ──
    $securityDetailRows = ""

    # Defender
    $defenderStatus = if ($Security.Defender.RealTimeProtection -eq $true) { "<span class='pass'>$iconPass Active</span>" }
                      elseif ($Security.Defender.RealTimeProtection -eq $false) { "<span class='fail'>$iconFail Disabled</span>" }
                      else { "<span class='warn'>$iconWarn Unknown</span>" }
    $securityDetailRows += "<tr><td>Windows Defender Real-Time Protection</td><td>$defenderStatus</td></tr>`n"

    $defAge = if ($null -ne $Security.Defender.DefinitionAge) {
        if ($Security.Defender.DefinitionsUpToDate) { "<span class='pass'>$iconPass $($Security.Defender.DefinitionAge) day(s) old</span>" }
        else { "<span class='fail'>$iconFail $($Security.Defender.DefinitionAge) day(s) old</span>" }
    } else { "<span class='warn'>$iconWarn Unknown</span>" }
    $securityDetailRows += "<tr><td>AV Definition Age</td><td>$defAge</td></tr>`n"

    if ($Security.ThirdPartyAV.Count -gt 0) {
        $securityDetailRows += "<tr><td>Third-Party Antivirus</td><td><span class='pass'>$iconPass $($Security.ThirdPartyAV -join ', ')</span></td></tr>`n"
    }

    # Firewall
    foreach ($profile in @("Domain", "Private", "Public")) {
        $fwVal = $Security.Firewall.$profile
        $fwStatus = if ($fwVal -eq $true) { "<span class='pass'>$iconPass Enabled</span>" }
                    elseif ($fwVal -eq $false) { "<span class='fail'>$iconFail Disabled</span>" }
                    else { "<span class='warn'>$iconWarn Unknown</span>" }
        $securityDetailRows += "<tr><td>Firewall - $profile Profile</td><td>$fwStatus</td></tr>`n"
    }

    # UAC
    $uacStatus = if ($Security.UAC.Enabled) { "<span class='pass'>$iconPass Enabled</span>" } else { "<span class='fail'>$iconFail Disabled</span>" }
    $securityDetailRows += "<tr><td>User Account Control (UAC)</td><td>$uacStatus</td></tr>`n"

    # BitLocker
    if ($Security.BitLocker.Count -gt 0) {
        foreach ($drive in $Security.BitLocker.Keys) {
            $blInfo = $Security.BitLocker[$drive]
            $blStatus = if ($blInfo.Status -eq "On") { "<span class='pass'>$iconPass Encrypted ($($blInfo.Method))</span>" }
                        else { "<span class='fail'>$iconFail Not Encrypted</span>" }
            $securityDetailRows += "<tr><td>BitLocker - $drive</td><td>$blStatus</td></tr>`n"
        }
    } else {
        $securityDetailRows += "<tr><td>BitLocker</td><td><span class='fail'>$iconFail Not Detected / Not Supported</span></td></tr>`n"
    }

    # Secure Boot
    $sbStatus = if ($Security.SecureBoot -eq $true) { "<span class='pass'>$iconPass Enabled</span>" }
                elseif ($Security.SecureBoot -eq $false) { "<span class='fail'>$iconFail Disabled</span>" }
                else { "<span class='warn'>$iconWarn Unable to determine</span>" }
    $securityDetailRows += "<tr><td>Secure Boot</td><td>$sbStatus</td></tr>`n"

    # TPM
    $tpmStatus = if ($Security.TPM.Present) {
        $tpmVer = if ($Security.TPM.Version) { " (v$($Security.TPM.Version.Split(',')[0]))" } else { "" }
        "<span class='pass'>$iconPass Present$tpmVer</span>"
    } else { "<span class='fail'>$iconFail Not Present</span>" }
    $securityDetailRows += "<tr><td>TPM</td><td>$tpmStatus</td></tr>`n"

    # Password Policy
    $ppStatus = "<span>Min Length: $($Security.PasswordPolicy.MinLength) | Complexity: $(if($Security.PasswordPolicy.Complexity){'Yes'}else{'No'}) | Lockout: $(if($Security.PasswordPolicy.LockoutThreshold -gt 0){$Security.PasswordPolicy.LockoutThreshold}else{'None'})</span>"
    $securityDetailRows += "<tr><td>Password Policy</td><td>$ppStatus</td></tr>`n"

    # Guest
    $guestStatus = if ($Security.GuestDisabled -eq $true) { "<span class='pass'>$iconPass Disabled</span>" }
                   elseif ($Security.GuestDisabled -eq $false) { "<span class='fail'>$iconFail Enabled</span>" }
                   else { "<span class='warn'>$iconWarn Unknown</span>" }
    $securityDetailRows += "<tr><td>Guest Account</td><td>$guestStatus</td></tr>`n"

    # Auto-Login
    $alStatus = if ($Security.AutoLoginDisabled -eq $true) { "<span class='pass'>$iconPass Disabled</span>" }
                elseif ($Security.AutoLoginDisabled -eq $false) { "<span class='fail'>$iconFail Enabled</span>" }
                else { "<span class='warn'>$iconWarn Unknown</span>" }
    $securityDetailRows += "<tr><td>Auto-Login</td><td>$alStatus</td></tr>`n"

    # RDP
    $rdpStatus = if ($Security.RDP.Enabled -eq $false) { "<span class='pass'>$iconPass Disabled</span>" }
                 elseif ($Security.RDP.Enabled -eq $true -and $Security.RDP.NLA) { "<span class='warn'>$iconWarn Enabled (NLA Required)</span>" }
                 elseif ($Security.RDP.Enabled -eq $true) { "<span class='fail'>$iconFail Enabled (No NLA)</span>" }
                 else { "<span class='warn'>$iconWarn Unknown</span>" }
    $securityDetailRows += "<tr><td>Remote Desktop</td><td>$rdpStatus</td></tr>`n"

    # SMBv1
    $smbStatus = if ($Security.SMBv1Disabled -eq $true) { "<span class='pass'>$iconPass Disabled</span>" }
                 elseif ($Security.SMBv1Disabled -eq $false) { "<span class='fail'>$iconFail Enabled (Vulnerable)</span>" }
                 else { "<span class='warn'>$iconWarn Unknown</span>" }
    $securityDetailRows += "<tr><td>SMBv1 Protocol</td><td>$smbStatus</td></tr>`n"

    # NetBIOS
    $nbStatus = if ($Security.NetBIOS -eq $true) { "<span class='warn'>$iconWarn Enabled</span>" }
                elseif ($Security.NetBIOS -eq $false) { "<span class='pass'>$iconPass Disabled</span>" }
                else { "<span class='warn'>$iconWarn Unknown</span>" }
    $securityDetailRows += "<tr><td>NetBIOS over TCP/IP</td><td>$nbStatus</td></tr>`n"

    # Local Admins
    $adminCountClass = if ($Security.LocalAdmins.Count -le 2) { "pass" } else { "warn" }
    $securityDetailRows += "<tr><td>Local Admin Accounts</td><td><span class='$adminCountClass'>$($Security.LocalAdmins.Count) account(s): $($Security.LocalAdmins.Names)</span></td></tr>`n"

    # ── Privacy & Data Protection detail rows ──
    $privacyDetailRows = ""
    if ($Security.Privacy) {
        $pTel = if ($Security.Privacy.TelemetryMinimal) { "<span class='pass'>$iconPass Minimal</span>" } else { "<span class='fail'>$iconFail Not Restricted</span>" }
        $privacyDetailRows += "<tr><td>Telemetry Level</td><td>$pTel</td></tr>`n"
        $pAd = if ($Security.Privacy.AdvertisingIdDisabled) { "<span class='pass'>$iconPass Disabled</span>" } else { "<span class='fail'>$iconFail Active</span>" }
        $privacyDetailRows += "<tr><td>Advertising ID</td><td>$pAd</td></tr>`n"
        $pLoc = if ($Security.Privacy.LocationDisabled) { "<span class='pass'>$iconPass Off</span>" } else { "<span class='fail'>$iconFail Active</span>" }
        $privacyDetailRows += "<tr><td>Location Tracking</td><td>$pLoc</td></tr>`n"
        $pAct = if ($Security.Privacy.ActivityHistoryDisabled) { "<span class='pass'>$iconPass Disabled</span>" } else { "<span class='fail'>$iconFail Active</span>" }
        $privacyDetailRows += "<tr><td>Activity History</td><td>$pAct</td></tr>`n"
        $pCort = if ($Security.Privacy.CortanaDisabled) { "<span class='pass'>$iconPass Disabled</span>" } else { "<span class='warn'>$iconWarn Active</span>" }
        $privacyDetailRows += "<tr><td>Cortana/Copilot</td><td>$pCort</td></tr>`n"
        $pFmd = if ($Security.Privacy.FindMyDeviceEnabled) { "<span class='pass'>$iconPass Enabled</span>" } else { "<span class='fail'>$iconFail Off</span>" }
        $privacyDetailRows += "<tr><td>Find My Device</td><td>$pFmd</td></tr>`n"
    }

    # ── Browser Security detail rows ──
    $browserDetailRows = ""
    if ($Security.BrowserSecurity) {
        $bChr = if ($Security.BrowserSecurity.ChromeNoSavedPasswords) { "<span class='pass'>$iconPass None Saved</span>" } else { "<span class='warn'>$iconWarn Passwords Stored</span>" }
        $browserDetailRows += "<tr><td>Chrome Passwords</td><td>$bChr</td></tr>`n"
        $bEdg = if ($Security.BrowserSecurity.EdgeNoSavedPasswords) { "<span class='pass'>$iconPass None Saved</span>" } else { "<span class='warn'>$iconWarn Passwords Stored</span>" }
        $browserDetailRows += "<tr><td>Edge Passwords</td><td>$bEdg</td></tr>`n"
        $bSS = if ($Security.BrowserSecurity.SmartScreenEnabled) { "<span class='pass'>$iconPass Enabled</span>" } else { "<span class='fail'>$iconFail Disabled</span>" }
        $browserDetailRows += "<tr><td>SmartScreen</td><td>$bSS</td></tr>`n"
        $bExt = if ($Security.BrowserSecurity.ExtensionCountOk) { "<span class='pass'>$iconPass Reasonable</span>" } else { "<span class='warn'>$iconWarn 15+ Installed</span>" }
        $browserDetailRows += "<tr><td>Browser Extensions</td><td>$bExt</td></tr>`n"
    }

    # ── Network Hardening detail rows ──
    $netHardenRows = ""
    if ($Security.NetworkHardening) {
        $nShares = if ($Security.NetworkHardening.NoOpenShares) { "<span class='pass'>$iconPass None</span>" } else { "<span class='warn'>$iconWarn Shares Found</span>" }
        $netHardenRows += "<tr><td>Open Shares</td><td>$nShares</td></tr>`n"
        $nUpnp = if ($Security.NetworkHardening.UPnPDisabled) { "<span class='pass'>$iconPass Disabled</span>" } else { "<span class='fail'>$iconFail Running</span>" }
        $netHardenRows += "<tr><td>UPnP (SSDP)</td><td>$nUpnp</td></tr>`n"
        $nLlmnr = if ($Security.NetworkHardening.LLMNRDisabled) { "<span class='pass'>$iconPass Disabled</span>" } else { "<span class='warn'>$iconWarn Active</span>" }
        $netHardenRows += "<tr><td>LLMNR</td><td>$nLlmnr</td></tr>`n"
        $nDoh = if ($Security.NetworkHardening.DoHEnabled) { "<span class='pass'>$iconPass Enabled</span>" } else { "<span class='warn'>$iconWarn Off</span>" }
        $netHardenRows += "<tr><td>DNS-over-HTTPS</td><td>$nDoh</td></tr>`n"
        $nRa = if ($Security.NetworkHardening.RemoteAssistanceDisabled) { "<span class='pass'>$iconPass Disabled</span>" } else { "<span class='warn'>$iconWarn Enabled</span>" }
        $netHardenRows += "<tr><td>Remote Assistance</td><td>$nRa</td></tr>`n"
    }

    # ── System Integrity detail rows ──
    $integrityDetailRows = ""
    if ($Security.SystemIntegrity) {
        $iDrv = if ($Security.SystemIntegrity.DriverSigEnforced) { "<span class='pass'>$iconPass Enforced</span>" } else { "<span class='fail'>$iconFail Test Mode</span>" }
        $integrityDetailRows += "<tr><td>Driver Signing</td><td>$iDrv</td></tr>`n"
        $iPs = if ($Security.SystemIntegrity.PSScriptLogging) { "<span class='pass'>$iconPass On</span>" } else { "<span class='warn'>$iconWarn Off</span>" }
        $integrityDetailRows += "<tr><td>PS Script Logging</td><td>$iPs</td></tr>`n"
        $iLog = if ($Security.SystemIntegrity.LogonAuditEnabled) { "<span class='pass'>$iconPass Enabled</span>" } else { "<span class='warn'>$iconWarn Off</span>" }
        $integrityDetailRows += "<tr><td>Logon Auditing</td><td>$iLog</td></tr>`n"
        $iCg = if ($Security.SystemIntegrity.CredentialGuard) { "<span class='pass'>$iconPass Running</span>" } else { "<span class='warn'>$iconWarn Off</span>" }
        $integrityDetailRows += "<tr><td>Credential Guard</td><td>$iCg</td></tr>`n"
        $iLsa = if ($Security.SystemIntegrity.LSASSProtected) { "<span class='pass'>$iconPass PPL</span>" } else { "<span class='warn'>$iconWarn Unprotected</span>" }
        $integrityDetailRows += "<tr><td>LSASS Protection</td><td>$iLsa</td></tr>`n"
    }

    # ── Account Hygiene detail rows ──
    $accountDetailRows = ""
    if ($Security.AccountHygiene) {
        $aStale = if ($Security.AccountHygiene.NoStaleAccounts) { "<span class='pass'>$iconPass None</span>" } else { "<span class='warn'>$iconWarn Found</span>" }
        $accountDetailRows += "<tr><td>Stale Accounts</td><td>$aStale</td></tr>`n"
        $aEmpty = if ($Security.AccountHygiene.NoEmptyPasswords) { "<span class='pass'>$iconPass None</span>" } else { "<span class='fail'>$iconFail Found</span>" }
        $accountDetailRows += "<tr><td>Empty Passwords</td><td>$aEmpty</td></tr>`n"
        $aAge = if ($Security.AccountHygiene.PasswordAgePolicy) { "<span class='pass'>$iconPass Set</span>" } else { "<span class='warn'>$iconWarn Unlimited</span>" }
        $accountDetailRows += "<tr><td>Password Expiry</td><td>$aAge</td></tr>`n"
    }

    # ── Ransomware Protection detail rows ──
    $ransomDetailRows = ""
    if ($Security.RansomwareProtection) {
        $rCfa = if ($Security.RansomwareProtection.ControlledFolderAccess) { "<span class='pass'>$iconPass On</span>" } else { "<span class='fail'>$iconFail Off</span>" }
        $ransomDetailRows += "<tr><td>Controlled Folders</td><td>$rCfa</td></tr>`n"
        $rRp = if ($Security.RansomwareProtection.RecentRestorePoint) { "<span class='pass'>$iconPass Recent</span>" } else { "<span class='fail'>$iconFail None Recent</span>" }
        $ransomDetailRows += "<tr><td>Restore Points</td><td>$rRp</td></tr>`n"
        $rTask = if ($Security.RansomwareProtection.NoSuspiciousScheduledTasks) { "<span class='pass'>$iconPass Clean</span>" } else { "<span class='fail'>$iconFail Found</span>" }
        $ransomDetailRows += "<tr><td>Suspicious Tasks</td><td>$rTask</td></tr>`n"
    }

    # ── Network detail rows ──
    $networkRows = ""
    foreach ($adapter in $Network.Adapters) {
        $networkRows += "<tr><td>$($adapter.Name)</td><td>$($adapter.IP)</td><td>$($adapter.MAC)</td><td>$($adapter.DNS)</td></tr>`n"
    }

    $wifiRow = "<tr><td>Connected SSID</td><td>$($Network.WiFi.SSID)</td></tr>`n"
    $wifiRow += "<tr><td>Authentication</td><td>$($Network.WiFi.Authentication)</td></tr>`n"
    $wifiRow += "<tr><td>Cipher</td><td>$($Network.WiFi.Cipher)</td></tr>`n"
    $wifiRow += "<tr><td>Public IP</td><td>$($Network.PublicIP)</td></tr>`n"

    # Open ports table
    $openPortRows = ""
    foreach ($port in $Network.OpenPorts) {
        $openPortRows += "<tr><td>$($port.Port)</td><td>$($port.Address)</td><td>$($port.Process)</td></tr>`n"
    }

    # ── Performance rows ──
    $cpuClass = if ($Performance.CPUUsage -gt 80) { "fail" } elseif ($Performance.CPUUsage -gt 50) { "warn" } else { "pass" }
    $ramClass = if ($Performance.RAMUsage -gt 85) { "fail" } elseif ($Performance.RAMUsage -gt 60) { "warn" } else { "pass" }

    $topProcRows = ""
    foreach ($proc in $Performance.TopRAMConsumers) {
        $topProcRows += "<tr><td>$($proc.Name)</td><td>$($proc.RAM) MB</td></tr>`n"
    }

    $diskHealthRows = ""
    foreach ($dh in $Performance.DiskHealth) {
        $dhClass = if ($dh.Health -eq "Healthy") { "pass" } else { "fail" }
        $diskHealthRows += "<tr><td>$($dh.Model)</td><td>$($dh.Media)</td><td>$($dh.Size) GB</td><td class='$dhClass'>$($dh.Health)</td></tr>`n"
    }

    # ── Missing patches ──
    $patchRows = ""
    foreach ($patch in $MissingPatches) {
        $sevClass = switch ($patch.Severity) { "Critical" { "fail" } "Important" { "warn" } default { "" } }
        $patchRows += "<tr><td>$($patch.KB)</td><td>$($patch.Title)</td><td class='$sevClass'>$($patch.Severity)</td><td>$($patch.Size) MB</td></tr>`n"
    }
    if ($MissingPatches.Count -eq 0) {
        $patchRows = "<tr><td colspan='4' class='pass' style='text-align:center;'>$iconPass No missing patches detected</td></tr>"
    }

    # ── Software list ──
    $softwareRows = ""
    $swCount = 0
    foreach ($sw in $Software.InstalledSoftware) {
        $softwareRows += "<tr><td>$($sw.Name)</td><td>$($sw.Version)</td><td>$($sw.Publisher)</td></tr>`n"
        $swCount++
    }

    # ── Startup programs ──
    $startupRows = ""
    foreach ($su in $Software.StartupPrograms) {
        $startupRows += "<tr><td>$($su.Name)</td><td>$($su.Location)</td></tr>`n"
    }

    # ── Top 3 recs for exec summary ──
    $top3HTML = ""
    $recNum = 1
    foreach ($rec in $top3Recs) {
        $top3HTML += "<div class='rec-item'><strong>$recNum. $($rec.Check)</strong><br/>$($rec.Recommendation)</div>`n"
        $recNum++
    }
    if ($top3Recs.Count -eq 0) {
        $top3HTML = "<div class='rec-item pass-bg'><strong>$iconPass Excellent!</strong> No critical recommendations at this time.</div>"
    }

    # Contact info
    $contactLine = ""
    if ($Params.ContactName) { $contactLine = "<p class='meta'>Contact: $($Params.ContactName)</p>" }

    # ── FULL HTML ──
    $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1.0"/>
<title>Hardware &amp; Security Audit Report - $($Params.CustomerName)</title>
<style>
    @page {
        size: letter;
        margin: 0.6in 0.7in;
        @bottom-center {
            content: "$COMPANY_NAME | $COMPANY_WEBSITE | $COMPANY_PHONE";
            font-size: 8pt;
            color: #888;
        }
    }
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body {
        font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
        font-size: 10pt;
        color: #333;
        line-height: 1.5;
        background: #fff;
    }
    .page-break { page-break-before: always; }

    /* Cover Page */
    .cover {
        height: 100vh;
        display: flex;
        flex-direction: column;
        justify-content: center;
        align-items: center;
        text-align: center;
        page-break-after: always;
    }
    .cover-logo {
        background: $COLOR_NAVY;
        color: #fff;
        padding: 20px 50px;
        font-size: 22pt;
        font-weight: bold;
        letter-spacing: 3px;
        border-radius: 6px;
        margin-bottom: 40px;
    }
    .cover-title {
        font-size: 28pt;
        font-weight: 300;
        color: $COLOR_NAVY;
        margin-bottom: 10px;
        letter-spacing: 2px;
    }
    .cover-subtitle {
        font-size: 14pt;
        color: #666;
        margin-bottom: 40px;
    }
    .cover .score-circle {
        margin: 20px 0;
    }
    .cover .meta {
        font-size: 11pt;
        color: #555;
        margin: 4px 0;
    }

    /* Headers */
    .section-header {
        background: $COLOR_NAVY;
        color: #fff;
        padding: 10px 18px;
        font-size: 13pt;
        font-weight: 600;
        margin: 25px 0 12px 0;
        border-radius: 4px;
        letter-spacing: 0.5px;
    }
    .sub-header {
        color: $COLOR_ACCENT;
        font-size: 11pt;
        font-weight: 600;
        margin: 18px 0 8px 0;
        padding-bottom: 4px;
        border-bottom: 2px solid $COLOR_ACCENT;
    }

    /* Tables */
    table {
        width: 100%;
        border-collapse: collapse;
        margin-bottom: 16px;
        font-size: 9.5pt;
    }
    th {
        background: $COLOR_NAVY;
        color: #fff;
        padding: 8px 10px;
        text-align: left;
        font-weight: 600;
        font-size: 9pt;
        text-transform: uppercase;
        letter-spacing: 0.3px;
    }
    td {
        padding: 7px 10px;
        border-bottom: 1px solid #e8e8e8;
        vertical-align: top;
    }
    tr:nth-child(even) td { background: $COLOR_LIGHT_BG; }
    tr:hover td { background: #eef5fb; }

    /* Status indicators */
    .pass { color: $COLOR_GREEN; font-weight: 600; }
    .fail { color: $COLOR_RED; font-weight: 600; }
    .warn { color: $COLOR_ORANGE; font-weight: 600; }
    .info { color: $COLOR_ACCENT; font-weight: 600; }

    .pass-bg { background: #eafaf1; padding: 12px; border-radius: 4px; border-left: 4px solid $COLOR_GREEN; }

    /* Score summary boxes */
    .summary-grid {
        display: flex;
        gap: 16px;
        margin: 16px 0;
    }
    .summary-box {
        flex: 1;
        text-align: center;
        padding: 16px;
        border-radius: 6px;
        border: 1px solid #e0e0e0;
    }
    .summary-box .number {
        font-size: 28pt;
        font-weight: bold;
        display: block;
    }
    .summary-box .label {
        font-size: 9pt;
        color: #666;
        text-transform: uppercase;
        letter-spacing: 0.5px;
    }

    /* Recommendation items */
    .rec-item {
        padding: 12px 16px;
        margin: 8px 0;
        border-radius: 4px;
        border-left: 4px solid $COLOR_RED;
        background: #fef5f5;
    }

    /* Footer */
    .report-footer {
        margin-top: 30px;
        padding: 16px 0;
        border-top: 2px solid $COLOR_NAVY;
        text-align: center;
        font-size: 9pt;
        color: #888;
    }
    .report-footer strong { color: $COLOR_NAVY; }

    /* Print helpers */
    @media print {
        .page-break { page-break-before: always; }
        body { -webkit-print-color-adjust: exact; print-color-adjust: exact; }
    }
</style>
</head>
<body>

<!-- ════════════════════════════════════════════════════════════════════ -->
<!-- PAGE 1: COVER -->
<!-- ════════════════════════════════════════════════════════════════════ -->
<div class="cover">
    <div class="cover-logo">PC PLUS COMPUTING</div>
    <div class="cover-title">HARDWARE &amp; SECURITY AUDIT</div>
    <div class="cover-subtitle">Comprehensive Hardware Diagnostic &amp; Security Assessment</div>

    <div class="score-circle">
        $scoreSVG
    </div>

    <p class="meta" style="font-size:14pt;color:$($Scoring.Color);font-weight:bold;margin-top:10px;">
        Score: $($Scoring.Score) / 100 &mdash; Grade $($Scoring.Grade)
    </p>

    <div style="margin-top:40px;">
        <p class="meta"><strong>Customer:</strong> $($Params.CustomerName)</p>
        $contactLine
        <p class="meta"><strong>Device:</strong> $($SystemInfo.ComputerName)</p>
        <p class="meta"><strong>Date:</strong> $dateFormatted</p>
        <p class="meta"><strong>Technician:</strong> $($Params.TechName)</p>
    </div>
</div>

<!-- ════════════════════════════════════════════════════════════════════ -->
<!-- PAGE 2: EXECUTIVE SUMMARY -->
<!-- ════════════════════════════════════════════════════════════════════ -->
<div class="page-break"></div>

<div class="section-header">Executive Summary</div>

<div class="summary-grid">
    <div class="summary-box" style="border-color:$COLOR_GREEN;">
        <span class="number pass">$passCount</span>
        <span class="label">Checks Passed</span>
    </div>
    <div class="summary-box" style="border-color:$COLOR_ORANGE;">
        <span class="number warn">$warningCount</span>
        <span class="label">Warnings</span>
    </div>
    <div class="summary-box" style="border-color:$COLOR_RED;">
        <span class="number fail">$criticalCount</span>
        <span class="label">Critical Issues</span>
    </div>
    <div class="summary-box" style="border-color:$COLOR_ACCENT;">
        <span class="number" style="color:$COLOR_ACCENT;">$($Scoring.Score)</span>
        <span class="label">Security Score</span>
    </div>
</div>

<div class="sub-header">Score Breakdown</div>
<table>
    <tr><th></th><th>Security Check</th><th>Status</th><th>Weight</th></tr>
    $breakdownRows
</table>

<div class="sub-header">Top Recommendations</div>
$top3HTML

<!-- ════════════════════════════════════════════════════════════════════ -->
<!-- PAGE 3+: DETAILED FINDINGS -->
<!-- ════════════════════════════════════════════════════════════════════ -->
<div class="page-break"></div>

<div class="section-header">Detailed Security Findings</div>
<table>
    <tr><th style="width:40%;">Check</th><th>Status / Details</th></tr>
    $securityDetailRows
</table>

$(if ($privacyDetailRows) {
@"
<div class="sub-header">Privacy &amp; Data Protection</div>
<table>
    <tr><th style="width:40%;">Check</th><th>Status / Details</th></tr>
    $privacyDetailRows
</table>
"@
})

$(if ($browserDetailRows) {
@"
<div class="sub-header">Browser Security</div>
<table>
    <tr><th style="width:40%;">Check</th><th>Status / Details</th></tr>
    $browserDetailRows
</table>
"@
})

$(if ($netHardenRows) {
@"
<div class="sub-header">Network Hardening</div>
<table>
    <tr><th style="width:40%;">Check</th><th>Status / Details</th></tr>
    $netHardenRows
</table>
"@
})

$(if ($integrityDetailRows) {
@"
<div class="sub-header">System Integrity</div>
<table>
    <tr><th style="width:40%;">Check</th><th>Status / Details</th></tr>
    $integrityDetailRows
</table>
"@
})

$(if ($accountDetailRows) {
@"
<div class="sub-header">Account Hygiene</div>
<table>
    <tr><th style="width:40%;">Check</th><th>Status / Details</th></tr>
    $accountDetailRows
</table>
"@
})

$(if ($ransomDetailRows) {
@"
<div class="sub-header">Ransomware Protection</div>
<table>
    <tr><th style="width:40%;">Check</th><th>Status / Details</th></tr>
    $ransomDetailRows
</table>
"@
})

$(if ($Recommendations.Count -gt 0) {
@"
<div class="section-header">All Recommendations</div>
<table>
    <tr><th></th><th>Severity</th><th>Check</th><th>Recommendation</th></tr>
    $recsHTML
</table>
"@
})

<div class="page-break"></div>

<div class="section-header">Network Information</div>
<div class="sub-header">Network Adapters</div>
<table>
    <tr><th>Adapter</th><th>IP Address</th><th>MAC Address</th><th>DNS Servers</th></tr>
    $networkRows
</table>

<div class="sub-header">Wireless</div>
<table>
    <tr><th style="width:30%;">Property</th><th>Value</th></tr>
    $wifiRow
</table>

<div class="sub-header">Listening Ports (Top 30)</div>
<table>
    <tr><th>Port</th><th>Address</th><th>Process</th></tr>
    $openPortRows
</table>

<div class="page-break"></div>

<div class="section-header">System Performance</div>
<table>
    <tr><th style="width:40%;">Metric</th><th>Value</th></tr>
    <tr><td>CPU Usage</td><td class='$cpuClass'>$($Performance.CPUUsage)%</td></tr>
    <tr><td>RAM Usage</td><td class='$ramClass'>$($Performance.RAMUsage)%</td></tr>
    <tr><td>Running Processes</td><td>$($Performance.ProcessCount)</td></tr>
</table>

<div class="sub-header">Top 5 Memory Consumers</div>
<table>
    <tr><th>Process</th><th>RAM Usage</th></tr>
    $topProcRows
</table>

<div class="sub-header">Physical Disk Health</div>
<table>
    <tr><th>Model</th><th>Type</th><th>Size</th><th>Health</th></tr>
    $diskHealthRows
</table>

<div class="page-break"></div>

<!-- ════════════════════════════════════════════════════════════════════ -->
<!-- HARDWARE DIAGNOSTICS -->
<!-- ════════════════════════════════════════════════════════════════════ -->
<div class="section-header">Hardware Diagnostics</div>

<div class="sub-header">Motherboard &amp; BIOS</div>
<table>
    <tr><th style="width:35%;">Property</th><th>Value</th></tr>
    <tr><td>Motherboard</td><td>$(if($Hardware.Motherboard.Manufacturer){"$($Hardware.Motherboard.Manufacturer) $($Hardware.Motherboard.Product)"}else{"Unknown"})</td></tr>
    <tr><td>Board Serial</td><td>$(if($Hardware.Motherboard.Serial){$Hardware.Motherboard.Serial}else{"N/A"})</td></tr>
    <tr><td>BIOS Vendor</td><td>$(if($Hardware.Motherboard.BIOSVendor){$Hardware.Motherboard.BIOSVendor}else{"Unknown"})</td></tr>
    <tr><td>BIOS Version</td><td>$(if($Hardware.Motherboard.BIOSVersion){$Hardware.Motherboard.BIOSVersion}else{"Unknown"})</td></tr>
    <tr><td>BIOS Date</td><td>$(if($Hardware.Motherboard.BIOSDate){$Hardware.Motherboard.BIOSDate}else{"Unknown"})</td></tr>
</table>

<div class="sub-header">Memory (RAM) - $($Hardware.RAMSlots.Used) of $($Hardware.RAMSlots.Total) slots used$(if($Hardware.RAMSlots.Empty -gt 0){" ($($Hardware.RAMSlots.Empty) empty)"})</div>
<table>
    <tr><th>Slot</th><th>Capacity</th><th>Speed</th><th>Type</th><th>Manufacturer</th><th>Part Number</th></tr>
    $(($Hardware.RAMSticks | ForEach-Object { "<tr><td>$($_.Slot)</td><td>$($_.CapacityGB) GB</td><td>$($_.Speed)</td><td>$($_.Type)</td><td>$($_.Manufacturer)</td><td>$($_.PartNumber)</td></tr>" }) -join "`n    ")
</table>

<div class="sub-header">Graphics / Display Adapters</div>
<table>
    <tr><th>GPU</th><th>VRAM</th><th>Driver Version</th><th>Driver Date</th><th>Resolution</th><th>Status</th></tr>
    $(($Hardware.GPUs | ForEach-Object { "<tr><td>$($_.Name)</td><td>$(if($_.VRAM_MB -gt 0){"$($_.VRAM_MB) MB"}else{"Shared"})</td><td>$($_.DriverVer)</td><td>$($_.DriverDate)</td><td>$($_.Resolution)</td><td>$($_.Status)</td></tr>" }) -join "`n    ")
</table>

$(if($Hardware.Monitors.Count -gt 0) {
@"
<div class="sub-header">Connected Monitors</div>
<table>
    <tr><th>Model</th><th>Manufacturer</th><th>Serial</th><th>Year Made</th></tr>
    $(($Hardware.Monitors | ForEach-Object { "<tr><td>$($_.Model)</td><td>$($_.Manufacturer)</td><td>$($_.Serial)</td><td>$(if($_.YearMade){$_.YearMade}else{'N/A'})</td></tr>" }) -join "`n    ")
</table>
"@
})

<div class="sub-header">Storage - Detailed SMART Diagnostics</div>
<table>
    <tr><th>Model</th><th>Type</th><th>Bus</th><th>Size</th><th>Health</th><th>Power-On Hours</th><th>Temp</th><th>Read Errors</th><th>Wear</th></tr>
    $(($Hardware.DiskSMART | ForEach-Object {
        $dhClass = if($_.Health -eq "Healthy"){"pass"}else{"fail"}
        "<tr><td>$($_.Model)</td><td>$($_.MediaType)</td><td>$($_.BusType)</td><td>$($_.SizeGB) GB</td><td class='$dhClass'>$($_.Health)</td><td>$($_.PowerOnHours)</td><td>$($_.Temperature)</td><td>$($_.ReadErrors)</td><td>$($_.Wear)</td></tr>"
    }) -join "`n    ")
</table>

$(if($Hardware.Battery.Present) {
    $battHealthClass = if($Hardware.Battery.HealthPercent -ge 80){"pass"}elseif($Hardware.Battery.HealthPercent -ge 50){"warn"}else{"fail"}
@"
<div class="sub-header">Battery Health</div>
<table>
    <tr><th style="width:35%;">Property</th><th>Value</th></tr>
    <tr><td>Status</td><td>$($Hardware.Battery.Status)</td></tr>
    <tr><td>Current Charge</td><td>$($Hardware.Battery.ChargePercent)%</td></tr>
    <tr><td>Battery Health</td><td class='$battHealthClass'>$($Hardware.Battery.HealthPercent)%</td></tr>
    <tr><td>Design Capacity</td><td>$($Hardware.Battery.DesignCapacity) mWh</td></tr>
    <tr><td>Full Charge Capacity</td><td>$($Hardware.Battery.FullCharge) mWh</td></tr>
    <tr><td>Cycle Count</td><td>$($Hardware.Battery.CycleCount)</td></tr>
    <tr><td>Estimated Runtime</td><td>$($Hardware.Battery.EstRuntime)</td></tr>
</table>
"@
})

$(if($Hardware.Temperatures.Count -gt 0) {
@"
<div class="sub-header">Temperature Readings</div>
<table>
    <tr><th>Sensor Zone</th><th>Temperature (C)</th><th>Temperature (F)</th></tr>
    $(($Hardware.Temperatures | ForEach-Object {
        $tempClass = if($_.TempC -gt 80){"fail"}elseif($_.TempC -gt 60){"warn"}else{"pass"}
        "<tr><td>$($_.Zone)</td><td class='$tempClass'>$($_.TempC) C</td><td class='$tempClass'>$($_.TempF) F</td></tr>"
    }) -join "`n    ")
</table>
"@
})

$(if($Hardware.Printers.Count -gt 0) {
@"
<div class="sub-header">Printers</div>
<table>
    <tr><th>Name</th><th>Status</th><th>Port</th><th>Default</th></tr>
    $(($Hardware.Printers | ForEach-Object { "<tr><td>$($_.Name)</td><td>$($_.Status)</td><td>$($_.Port)</td><td>$(if($_.Default){'Yes'}else{'No'})</td></tr>" }) -join "`n    ")
</table>
"@
})

$(if($Hardware.AudioDevices.Count -gt 0) {
@"
<div class="sub-header">Audio Devices</div>
<table>
    <tr><th>Device</th><th>Manufacturer</th><th>Status</th></tr>
    $(($Hardware.AudioDevices | ForEach-Object { "<tr><td>$($_.Name)</td><td>$($_.Manufacturer)</td><td>$($_.Status)</td></tr>" }) -join "`n    ")
</table>
"@
})

$(if($Hardware.USBDevices.Count -gt 0) {
@"
<div class="sub-header">USB Devices</div>
<table>
    <tr><th>Device</th><th>Status</th></tr>
    $(($Hardware.USBDevices | ForEach-Object { "<tr><td>$($_.Name)</td><td>$($_.Status)</td></tr>" }) -join "`n    ")
</table>
"@
})

$(if($Hardware.DeviceErrors.Count -gt 0) {
@"
<div class="sub-header" style="color:$COLOR_RED;">Device Manager Errors ($($Hardware.DeviceErrors.Count) issues found)</div>
<table>
    <tr><th>Device</th><th>Class</th><th>Error</th></tr>
    $(($Hardware.DeviceErrors | ForEach-Object { "<tr><td class='fail'>$($_.Device)</td><td>$($_.Class)</td><td class='fail'>$($_.Error)</td></tr>" }) -join "`n    ")
</table>
"@
} else {
@"
<div class="sub-header" style="color:$COLOR_GREEN;">Device Manager - No Errors</div>
<p class="pass-bg"><span class="pass">$iconPass</span> All devices functioning properly. No driver errors or hardware issues detected.</p>
"@
})

<div class="sub-header">Windows License</div>
<table>
    <tr><th style="width:35%;">Property</th><th>Value</th></tr>
    <tr><td>License Status</td><td>$(if($Hardware.WindowsLicense.Status -eq 'Licensed'){"<span class='pass'>$iconPass Licensed</span>"}else{"<span class='fail'>$iconFail $($Hardware.WindowsLicense.Status)</span>"})</td></tr>
    <tr><td>Product Key (Partial)</td><td>$($Hardware.WindowsLicense.PartialKey)</td></tr>
</table>

<div class="page-break"></div>

<!-- ════════════════════════════════════════════════════════════════════ -->
<!-- LICENSE KEYS & CREDENTIALS RECOVERY -->
<!-- ════════════════════════════════════════════════════════════════════ -->
<div class="section-header">License Keys &amp; Credentials Recovery</div>
<p style="color:#888;font-size:8.5pt;margin-bottom:12px;">CONFIDENTIAL - This section contains product keys and passwords recovered from this system. Store securely.</p>

<div class="sub-header">Windows Product Key</div>
<table>
    <tr><th>Source</th><th>Key</th></tr>
    $(if($Hardware.WindowsProductKey.Count -gt 0) {
        ($Hardware.WindowsProductKey | ForEach-Object { "<tr><td>$($_.Source)</td><td><strong style='font-family:Consolas,monospace;letter-spacing:1px;'>$($_.Key)</strong></td></tr>" }) -join "`n    "
    } else {
        "<tr><td colspan='2' class='warn'>$iconWarn No Windows product key found in BIOS or registry</td></tr>"
    })
</table>

$(if($Hardware.OfficeKeys.Count -gt 0) {
@"
<div class="sub-header">Microsoft Office Product Keys</div>
<table>
    <tr><th>Product</th><th>Version</th><th>Key</th></tr>
    $(($Hardware.OfficeKeys | ForEach-Object { "<tr><td>$($_.Product)</td><td>$($_.Version)</td><td><strong style='font-family:Consolas,monospace;letter-spacing:1px;'>$($_.Key)</strong></td></tr>" }) -join "`n    ")
</table>
"@
} else {
@"
<div class="sub-header">Microsoft Office Product Keys</div>
<table><tr><td class='warn'>$iconWarn No Office product keys found (Office may use Microsoft 365 account activation)</td></tr></table>
"@
})

$(if($Hardware.SoftwareKeys.Count -gt 0) {
@"
<div class="sub-header">Other Software License Keys</div>
<table>
    <tr><th>Product</th><th>Key</th></tr>
    $(($Hardware.SoftwareKeys | ForEach-Object { "<tr><td>$($_.Product)</td><td><strong style='font-family:Consolas,monospace;'>$($_.Key)</strong></td></tr>" }) -join "`n    ")
</table>
"@
})

<div class="sub-header">Saved WiFi Networks &amp; Passwords</div>
<table>
    <tr><th>Network (SSID)</th><th>Password</th><th>Authentication</th><th>Cipher</th></tr>
    $(if($Hardware.WiFiPasswords.Count -gt 0) {
        ($Hardware.WiFiPasswords | ForEach-Object { "<tr><td><strong>$($_.SSID)</strong></td><td style='font-family:Consolas,monospace;'>$($_.Password)</td><td>$($_.Auth)</td><td>$($_.Cipher)</td></tr>" }) -join "`n    "
    } else {
        "<tr><td colspan='4'>No saved WiFi profiles found</td></tr>"
    })
</table>

<div class="page-break"></div>

<div class="section-header">Missing Windows Updates ($($MissingPatches.Count))</div>
<table>
    <tr><th>KB</th><th>Title</th><th>Severity</th><th>Size</th></tr>
    $patchRows
</table>

<div class="page-break"></div>

<div class="section-header">System Information</div>
<table>
    <tr><th style="width:35%;">Property</th><th>Value</th></tr>
    <tr><td>Computer Name</td><td>$($SystemInfo.ComputerName)</td></tr>
    <tr><td>Manufacturer / Model</td><td>$($SystemInfo.Manufacturer) $($SystemInfo.Model)</td></tr>
    <tr><td>Serial Number</td><td>$($SystemInfo.Serial)</td></tr>
    <tr><td>Operating System</td><td>$($SystemInfo.OSVersion)</td></tr>
    <tr><td>OS Build</td><td>$($SystemInfo.OSBuild)</td></tr>
    <tr><td>Architecture</td><td>$($SystemInfo.Architecture)</td></tr>
    <tr><td>CPU</td><td>$($SystemInfo.CPUModel)</td></tr>
    <tr><td>CPU Cores / Threads</td><td>$($SystemInfo.CPUCores) / $($SystemInfo.CPUThreads)</td></tr>
    <tr><td>RAM Total / Free</td><td>$($SystemInfo.RAMTotal) GB / $($SystemInfo.RAMFree) GB</td></tr>
    <tr><td>Network Membership</td><td>$($SystemInfo.Domain)</td></tr>
    <tr><td>System Uptime</td><td>$($SystemInfo.Uptime)</td></tr>
</table>

<div class="sub-header">Storage</div>
<table>
    <tr><th>Drive</th><th>Capacity</th><th>Free</th><th>Used</th><th>Health</th></tr>
    $diskRows
</table>

<div class="sub-header">Installed Software ($swCount applications)</div>
<table>
    <tr><th>Name</th><th>Version</th><th>Publisher</th></tr>
    $softwareRows
</table>

<div class="sub-header">Startup Programs ($($Software.StartupPrograms.Count) items)</div>
<table>
    <tr><th>Name</th><th>Location</th></tr>
    $startupRows
</table>

<div class="sub-header">Additional Details</div>
<table>
    <tr><th style="width:40%;">Property</th><th>Value</th></tr>
    <tr><td>Running Services</td><td>$($Software.RunningServices)</td></tr>
    <tr><td>Chrome Extensions</td><td>$($Software.BrowserExtensions.Chrome)</td></tr>
    <tr><td>Edge Extensions</td><td>$($Software.BrowserExtensions.Edge)</td></tr>
</table>

<!-- ════════════════════════════════════════════════════════════════════ -->
<!-- FOOTER -->
<!-- ════════════════════════════════════════════════════════════════════ -->
<div class="report-footer">
    <p><strong>$COMPANY_NAME</strong></p>
    <p>$COMPANY_WEBSITE &nbsp;|&nbsp; $COMPANY_PHONE</p>
    <p style="margin-top:8px;font-size:8pt;">Report generated on $dateFormatted &nbsp;|&nbsp; Technician: $($Params.TechName)</p>
    <p style="font-size:8pt;">This report is a point-in-time assessment. Security posture changes as updates and configurations are modified.</p>
</div>

</body>
</html>
"@

    return $html
}

# ─────────────────────────────────────────────────────────────────────────────
# HTML-TO-PDF CONVERSION
# ─────────────────────────────────────────────────────────────────────────────
function Convert-HTMLtoPDF {
    param([string]$HTMLPath, [string]$PDFPath)

    # Try Edge first, then Chrome
    $browsers = @()

    # Edge locations
    $edgePaths = @(
        "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
        "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe",
        "$env:LOCALAPPDATA\Microsoft\Edge\Application\msedge.exe"
    )
    foreach ($p in $edgePaths) { if (Test-Path $p) { $browsers += $p; break } }

    # Chrome locations
    $chromePaths = @(
        "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
        "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
        "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe"
    )
    foreach ($p in $chromePaths) { if (Test-Path $p) { $browsers += $p; break } }

    foreach ($browser in $browsers) {
        try {
            $arguments = @(
                "--headless"
                "--disable-gpu"
                "--no-sandbox"
                "--print-to-pdf=`"$PDFPath`""
                "--print-to-pdf-no-header"
                "--run-all-compositor-stages-before-draw"
                "--disable-extensions"
                "`"file:///$($HTMLPath.Replace('\','/'))`""
            )
            $process = Start-Process -FilePath $browser -ArgumentList ($arguments -join " ") -PassThru -WindowStyle Hidden -Wait
            if (Test-Path $PDFPath) {
                return $true
            }
        } catch {
            continue
        }
    }

    return $false
}

# ─────────────────────────────────────────────────────────────────────────────
# MAIN EXECUTION
# ─────────────────────────────────────────────────────────────────────────────

# Show launch dialog
$params = Show-LaunchDialog
if ($null -eq $params) { exit }

# Ensure output folder exists
if (-not (Test-Path $params.OutputFolder)) {
    try { New-Item -Path $params.OutputFolder -ItemType Directory -Force | Out-Null }
    catch {
        [System.Windows.Forms.MessageBox]::Show("Cannot create output folder: $($params.OutputFolder)", "Error", "OK", "Error")
        exit
    }
}

# Show progress window
$progressForm = New-ProgressWindow

$auditStart = Get-Date

# ── SYSTEM INFO ──
Update-Progress $progressForm "Collecting system information..." 5
$systemInfo = Get-SystemInfo

# ── SECURITY STATUS ──
Update-Progress $progressForm "Scanning security configuration..." 20
$security = Get-SecurityStatus

# ── NETWORK INFO ──
Update-Progress $progressForm "Analyzing network configuration..." 45
$network = Get-NetworkInfo

# ── SOFTWARE INVENTORY ──
Update-Progress $progressForm "Inventorying installed software..." 55
$software = Get-SoftwareInfo

# ── MISSING PATCHES ──
Update-Progress $progressForm "Checking for missing Windows updates (this may take a moment)..." 65
$missingPatches = Get-MissingPatches

# ── PERFORMANCE ──
Update-Progress $progressForm "Measuring system performance..." 70
$performance = Get-PerformanceInfo

# ── HARDWARE DIAGNOSTICS ──
Update-Progress $progressForm "Running hardware diagnostics..." 78
$hardware = Get-HardwareDiagnostics

# ── SCORING ──
Update-Progress $progressForm "Calculating security score..." 85
$scoring = Calculate-SecurityScore $security $missingPatches
$recommendations = Get-Recommendations $scoring $security $missingPatches

# ── GENERATE REPORT ──
Update-Progress $progressForm "Generating report..." 90

$safeCustName = $params.CustomerName -replace '[\\/:*?"<>|]', '_'
$safeCompName = $systemInfo.ComputerName -replace '[\\/:*?"<>|]', '_'
$dateStr = Get-Date -Format "yyyy-MM-dd"
$baseFileName = "$safeCustName - $safeCompName - Hardware Security Audit $dateStr"

$htmlPath = Join-Path $params.OutputFolder "$baseFileName.html"
$pdfPath  = Join-Path $params.OutputFolder "$baseFileName.pdf"

$htmlContent = Build-HTMLReport $params $systemInfo $security $network $software $missingPatches $performance $hardware $scoring $recommendations
[System.IO.File]::WriteAllText($htmlPath, $htmlContent, [System.Text.Encoding]::UTF8)

# ── CONVERT TO PDF ──
Update-Progress $progressForm "Converting to PDF..." 95
$pdfSuccess = Convert-HTMLtoPDF $htmlPath $pdfPath

$auditEnd = Get-Date
$duration = ($auditEnd - $auditStart).TotalSeconds

Update-Progress $progressForm "Audit complete!" 100
Start-Sleep -Milliseconds 500
$progressForm.Close()
$progressForm.Dispose()

# ── COMPLETION DIALOG ──
$resultMsg = "Hardware & Security Audit Complete!`n`n"
$resultMsg += "Score: $($scoring.Score)/100 (Grade $($scoring.Grade))`n"
$resultMsg += "Checks Passed: $(($scoring.Breakdown | Where-Object { $_.Passed }).Count) / $($scoring.Breakdown.Count)`n"
$resultMsg += "Duration: $([math]::Round($duration, 1)) seconds`n`n"

if ($pdfSuccess) {
    $resultMsg += "PDF Report: $pdfPath`n"
} else {
    $resultMsg += "PDF conversion unavailable (Edge/Chrome not found).`n"
}
$resultMsg += "HTML Report: $htmlPath"

$completionForm = New-Object System.Windows.Forms.Form
$completionForm.Text = "PC Plus Computing - Hardware & Security Audit Complete"
$completionForm.Size = New-Object System.Drawing.Size(520, 320)
$completionForm.StartPosition = "CenterScreen"
$completionForm.FormBorderStyle = "FixedDialog"
$completionForm.MaximizeBox = $false
$completionForm.BackColor = [System.Drawing.Color]::White
$completionForm.Font = New-Object System.Drawing.Font("Segoe UI", 9)

$chdr = New-Object System.Windows.Forms.Panel
$chdr.Dock = "Top"
$chdr.Height = 45
$chdr.BackColor = [System.Drawing.ColorTranslator]::FromHtml($COLOR_NAVY)
$completionForm.Controls.Add($chdr)

$chl = New-Object System.Windows.Forms.Label
$chl.Text = "AUDIT COMPLETE"
$chl.ForeColor = [System.Drawing.Color]::White
$chl.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
$chl.AutoSize = $false
$chl.Size = New-Object System.Drawing.Size(500, 45)
$chl.TextAlign = "MiddleCenter"
$chdr.Controls.Add($chl)

$scoreLbl = New-Object System.Windows.Forms.Label
$scoreLbl.Text = "Score: $($scoring.Score)/100  -  Grade $($scoring.Grade)"
$scoreLbl.Location = New-Object System.Drawing.Point(30, 60)
$scoreLbl.Size = New-Object System.Drawing.Size(450, 30)
$scoreLbl.Font = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
$scoreLbl.ForeColor = [System.Drawing.ColorTranslator]::FromHtml($scoring.Color)
$completionForm.Controls.Add($scoreLbl)

$infoLbl = New-Object System.Windows.Forms.Label
$infoLbl.Text = "Passed: $(($scoring.Breakdown | Where-Object { $_.Passed }).Count) / $($scoring.Breakdown.Count) checks  |  Duration: $([math]::Round($duration, 1))s"
$infoLbl.Location = New-Object System.Drawing.Point(30, 95)
$infoLbl.Size = New-Object System.Drawing.Size(450, 20)
$completionForm.Controls.Add($infoLbl)

$fileLbl = New-Object System.Windows.Forms.Label
if ($pdfSuccess) {
    $fileLbl.Text = "Report saved to: $pdfPath"
} else {
    $fileLbl.Text = "HTML Report saved to: $htmlPath`n(Install Edge or Chrome for PDF output)"
}
$fileLbl.Location = New-Object System.Drawing.Point(30, 125)
$fileLbl.Size = New-Object System.Drawing.Size(450, 40)
$fileLbl.Font = New-Object System.Drawing.Font("Segoe UI", 8)
$fileLbl.ForeColor = [System.Drawing.Color]::Gray
$completionForm.Controls.Add($fileLbl)

# Buttons
$btnOpen = New-Object System.Windows.Forms.Button
$btnOpen.Text = "Open Report"
$btnOpen.Location = New-Object System.Drawing.Point(100, 185)
$btnOpen.Size = New-Object System.Drawing.Size(130, 36)
$btnOpen.BackColor = [System.Drawing.ColorTranslator]::FromHtml($COLOR_ACCENT)
$btnOpen.ForeColor = [System.Drawing.Color]::White
$btnOpen.FlatStyle = "Flat"
$btnOpen.FlatAppearance.BorderSize = 0
$btnOpen.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$btnOpen.Add_Click({
    $fileToOpen = if ($pdfSuccess -and (Test-Path $pdfPath)) { $pdfPath } else { $htmlPath }
    Start-Process $fileToOpen
})
$completionForm.Controls.Add($btnOpen)

$btnFolder = New-Object System.Windows.Forms.Button
$btnFolder.Text = "Open Folder"
$btnFolder.Location = New-Object System.Drawing.Point(245, 185)
$btnFolder.Size = New-Object System.Drawing.Size(130, 36)
$btnFolder.FlatStyle = "Flat"
$btnFolder.Add_Click({
    Start-Process explorer.exe -ArgumentList $params.OutputFolder
})
$completionForm.Controls.Add($btnFolder)

$btnClose = New-Object System.Windows.Forms.Button
$btnClose.Text = "Close"
$btnClose.Location = New-Object System.Drawing.Point(200, 235)
$btnClose.Size = New-Object System.Drawing.Size(100, 30)
$btnClose.Add_Click({ $completionForm.Close() })
$completionForm.Controls.Add($btnClose)

$completionForm.ShowDialog() | Out-Null
$completionForm.Dispose()

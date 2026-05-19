<#
.SYNOPSIS
    PC Plus Computing - Windows 10/11 Debloat & Lockdown Tool
.DESCRIPTION
    Removes bloatware, disables telemetry, strips unnecessary features from
    Windows 10/11. Designed for office PCs (realtors, basic browsing + print).
    Runs from USB with no installation required.
.NOTES
    Company:  PC Plus Computing
    Website:  pcpluscomputing.com
    Phone:    604-760-1662
    Version:  1.0.0
    Requires: PowerShell 5.1+, Windows 10/11, Administrator privileges
#>

#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

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
        Add-Type -AssemblyName System.Windows.Forms
        [System.Windows.Forms.MessageBox]::Show(
            "This tool requires Administrator privileges.`nPlease right-click and 'Run as Administrator'.",
            "PC Plus Debloat - Elevation Required",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
    }
    exit
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$COLOR_NAVY   = "#0a1628"
$COLOR_ACCENT = "#2596be"
$COLOR_GREEN  = "#27ae60"
$COLOR_RED    = "#e74c3c"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
if ([string]::IsNullOrEmpty($ScriptDir)) { $ScriptDir = Get-Location }
$LogFile = Join-Path $ScriptDir "PCPlus-Debloat-$(Get-Date -Format 'yyyy-MM-dd-HHmm').log"

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$timestamp] [$Level] $Message"
    Add-Content -Path $LogFile -Value $line -ErrorAction SilentlyContinue
}

# ─────────────────────────────────────────────────────────────────────────────
# BLOATWARE APPS TO REMOVE
# ─────────────────────────────────────────────────────────────────────────────
$BloatwareApps = @(
    # Microsoft bloat
    "Microsoft.3DBuilder"
    "Microsoft.549981C3F5F10"          # Cortana
    "Microsoft.BingFinance"
    "Microsoft.BingNews"
    "Microsoft.BingSports"
    "Microsoft.BingTranslator"
    "Microsoft.BingWeather"
    "Microsoft.GamingApp"
    "Microsoft.GetHelp"
    "Microsoft.Getstarted"
    "Microsoft.Messaging"
    "Microsoft.Microsoft3DViewer"
    "Microsoft.MicrosoftOfficeHub"
    "Microsoft.MicrosoftSolitaireCollection"
    "Microsoft.MicrosoftStickyNotes"
    "Microsoft.MixedReality.Portal"
    "Microsoft.OneConnect"
    "Microsoft.People"
    "Microsoft.PowerAutomateDesktop"
    "Microsoft.SkypeApp"
    "Microsoft.Todos"
    "Microsoft.Wallet"
    "Microsoft.WindowsAlarms"
    "Microsoft.WindowsCommunicationsApps"  # Mail & Calendar
    "Microsoft.WindowsFeedbackHub"
    "Microsoft.WindowsMaps"
    "Microsoft.WindowsSoundRecorder"
    "Microsoft.Xbox.TCUI"
    "Microsoft.XboxApp"
    "Microsoft.XboxGameOverlay"
    "Microsoft.XboxGamingOverlay"
    "Microsoft.XboxIdentityProvider"
    "Microsoft.XboxSpeechToTextOverlay"
    "Microsoft.YourPhone"
    "Microsoft.ZuneMusic"
    "Microsoft.ZuneVideo"
    "MicrosoftCorporationII.QuickAssist"
    "MicrosoftTeams"
    "Microsoft.Clipchamp"
    "Microsoft.WindowsCamera"
    # Third-party bloat (pre-installed by OEMs)
    "ACGMediaPlayer"
    "ActiproSoftwareLLC"
    "AdobeSystemsIncorporated.AdobePhotoshopExpress"
    "Amazon.com.Amazon"
    "Asphalt8Airborne"
    "AutodeskSketchBook"
    "BubbleWitch3Saga"
    "CandyCrush"
    "CandyCrushSodaSaga"
    "COOKINGFEVER"
    "CyberLinkMediaSuiteEssentials"
    "DisneyMagicKingdoms"
    "Dolby"
    "DrawboardPDF"
    "Duolingo-LearnLanguagesforFree"
    "EclipseManager"
    "Facebook"
    "FarmVille2CountryEscape"
    "Fitbit.FitbitCoach"
    "Flipboard"
    "HiddenCity"
    "HULULLC.HULUPLUS"
    "iHeartRadio"
    "king.com.BubbleWitch3Saga"
    "king.com.CandyCrushSodaSaga"
    "LinkedIn"
    "MarchofEmpires"
    "Netflix"
    "NYTCrossword"
    "PandoraMediaInc"
    "Plex"
    "Royal Revolt"
    "Shazam"
    "Spotify"
    "SpotifyAB.SpotifyMusic"
    "SlingTV"
    "TikTok"
    "Twitter"
    "Viber"
    "WinZipComputing.WinZipUniversal"
    "Wunderlist"
    "XING"
)

# Apps to KEEP (never remove)
$KeepApps = @(
    "Microsoft.WindowsStore"
    "Microsoft.WindowsCalculator"
    "Microsoft.Windows.Photos"
    "Microsoft.WindowsNotepad"
    "Microsoft.Paint"
    "Microsoft.ScreenSketch"         # Snipping Tool
    "Microsoft.StorePurchaseApp"
    "Microsoft.DesktopAppInstaller"
    "Microsoft.HEIFImageExtension"
    "Microsoft.VP9VideoExtensions"
    "Microsoft.WebMediaExtensions"
    "Microsoft.WebpImageExtension"
)

# ─────────────────────────────────────────────────────────────────────────────
# MAIN FORM
# ─────────────────────────────────────────────────────────────────────────────
function Show-MainForm {
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "PC Plus Computing - Windows Debloat & Lockdown"
    $form.Size = New-Object System.Drawing.Size(600, 620)
    $form.StartPosition = "CenterScreen"
    $form.FormBorderStyle = "FixedDialog"
    $form.MaximizeBox = $false
    $form.BackColor = [System.Drawing.Color]::White
    $form.Font = New-Object System.Drawing.Font("Segoe UI", 9)

    $header = New-Object System.Windows.Forms.Panel
    $header.Dock = "Top"
    $header.Height = 50
    $header.BackColor = [System.Drawing.ColorTranslator]::FromHtml($COLOR_NAVY)
    $form.Controls.Add($header)

    $hl = New-Object System.Windows.Forms.Label
    $hl.Text = "PC PLUS COMPUTING - WINDOWS DEBLOAT TOOL"
    $hl.ForeColor = [System.Drawing.Color]::White
    $hl.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
    $hl.AutoSize = $false
    $hl.Size = New-Object System.Drawing.Size(580, 50)
    $hl.TextAlign = "MiddleCenter"
    $header.Controls.Add($hl)

    $y = 65

    $warningLbl = New-Object System.Windows.Forms.Label
    $warningLbl.Text = "Select which cleanup actions to perform. Check items and click Run."
    $warningLbl.Location = New-Object System.Drawing.Point(20, $y)
    $warningLbl.Size = New-Object System.Drawing.Size(550, 20)
    $warningLbl.ForeColor = [System.Drawing.Color]::Gray
    $form.Controls.Add($warningLbl)
    $y += 30

    $checkboxes = @{}

    $options = @(
        @{ Key = "RemoveBloatware";    Label = "Remove bloatware apps (Cortana, Xbox, Solitaire, TikTok, etc.)"; Default = $true }
        @{ Key = "DisableTelemetry";   Label = "Disable Windows telemetry & data collection"; Default = $true }
        @{ Key = "DisableCortana";     Label = "Disable Cortana"; Default = $true }
        @{ Key = "DisableWidgets";     Label = "Disable Widgets (Win 11)"; Default = $true }
        @{ Key = "DisableGameBar";     Label = "Disable Xbox Game Bar & Game DVR"; Default = $true }
        @{ Key = "DisableOneDrive";    Label = "Remove OneDrive"; Default = $false }
        @{ Key = "CleanStartMenu";     Label = "Clean Start Menu layout (remove pinned bloat)"; Default = $true }
        @{ Key = "DisableSearchWeb";   Label = "Disable web search in Start Menu"; Default = $true }
        @{ Key = "CleanTaskbar";       Label = "Clean taskbar (remove Chat, Widgets, Task View icons)"; Default = $true }
        @{ Key = "DisableAutoInstall"; Label = "Prevent Windows from reinstalling removed apps"; Default = $true }
        @{ Key = "DisableAds";         Label = "Disable Windows suggestions, tips, and ads"; Default = $true }
        @{ Key = "OptimizeServices";   Label = "Disable unnecessary services (Print Spooler kept)"; Default = $false }
        @{ Key = "ScheduleCleanup";    Label = "Create daily Downloads folder cleanup task"; Default = $false }
        @{ Key = "BlockInstalls";      Label = "Block non-admin software installs (UAC + AppLocker)"; Default = $false }
        @{ Key = "DisableStore";       Label = "Disable Microsoft Store (prevents app installs)"; Default = $false }
        @{ Key = "PowerSettings";      Label = "Optimize power settings (high performance, no sleep)"; Default = $false }
    )

    foreach ($opt in $options) {
        $cb = New-Object System.Windows.Forms.CheckBox
        $cb.Text = $opt.Label
        $cb.Location = New-Object System.Drawing.Point(30, $y)
        $cb.Size = New-Object System.Drawing.Size(530, 22)
        $cb.Checked = $opt.Default
        if ($opt.Key -in @("BlockInstalls", "DisableStore", "DisableOneDrive")) {
            $cb.ForeColor = [System.Drawing.Color]::DarkRed
        }
        $form.Controls.Add($cb)
        $checkboxes[$opt.Key] = $cb
        $y += 24
    }

    $y += 10

    $selectAllBtn = New-Object System.Windows.Forms.Button
    $selectAllBtn.Text = "Select All"
    $selectAllBtn.Location = New-Object System.Drawing.Point(30, $y)
    $selectAllBtn.Size = New-Object System.Drawing.Size(100, 30)
    $selectAllBtn.Add_Click({ foreach ($cb in $checkboxes.Values) { $cb.Checked = $true } })
    $form.Controls.Add($selectAllBtn)

    $selectNoneBtn = New-Object System.Windows.Forms.Button
    $selectNoneBtn.Text = "Deselect All"
    $selectNoneBtn.Location = New-Object System.Drawing.Point(140, $y)
    $selectNoneBtn.Size = New-Object System.Drawing.Size(100, 30)
    $selectNoneBtn.Add_Click({ foreach ($cb in $checkboxes.Values) { $cb.Checked = $false } })
    $form.Controls.Add($selectNoneBtn)

    $runBtn = New-Object System.Windows.Forms.Button
    $runBtn.Text = "Run Debloat"
    $runBtn.Location = New-Object System.Drawing.Point(360, $y)
    $runBtn.Size = New-Object System.Drawing.Size(180, 36)
    $runBtn.BackColor = [System.Drawing.ColorTranslator]::FromHtml($COLOR_ACCENT)
    $runBtn.ForeColor = [System.Drawing.Color]::White
    $runBtn.FlatStyle = "Flat"
    $runBtn.FlatAppearance.BorderSize = 0
    $runBtn.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
    $runBtn.Add_Click({
        $selected = @{}
        foreach ($kv in $checkboxes.GetEnumerator()) {
            $selected[$kv.Key] = $kv.Value.Checked
        }
        $form.Tag = $selected
        $form.DialogResult = "OK"
        $form.Close()
    })
    $form.Controls.Add($runBtn)
    $form.AcceptButton = $runBtn

    if ($form.ShowDialog() -eq "OK") { return $form.Tag }
    return $null
}

# ─────────────────────────────────────────────────────────────────────────────
# DEBLOAT FUNCTIONS
# ─────────────────────────────────────────────────────────────────────────────

function Remove-BloatwareApps {
    Write-Log "Removing bloatware apps..."
    $removed = 0
    foreach ($app in $BloatwareApps) {
        $packages = Get-AppxPackage -AllUsers -Name "*$app*" -ErrorAction SilentlyContinue
        foreach ($pkg in $packages) {
            $skip = $false
            foreach ($keep in $KeepApps) {
                if ($pkg.Name -like "*$keep*") { $skip = $true; break }
            }
            if (-not $skip) {
                try {
                    Remove-AppxPackage -Package $pkg.PackageFullName -AllUsers -ErrorAction Stop
                    Write-Log "Removed: $($pkg.Name)"
                    $removed++
                } catch {
                    Write-Log "Failed to remove $($pkg.Name): $($_.Exception.Message)" "WARN"
                }
            }
        }
        # Also remove provisioned packages (prevent reinstall for new users)
        $provisioned = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like "*$app*" }
        foreach ($prov in $provisioned) {
            try {
                Remove-AppxProvisionedPackage -Online -PackageName $prov.PackageName -ErrorAction Stop
                Write-Log "De-provisioned: $($prov.DisplayName)"
            } catch {
                Write-Log "Failed to de-provision $($prov.DisplayName): $($_.Exception.Message)" "WARN"
            }
        }
    }
    Write-Log "Bloatware removal complete. Removed $removed packages."
    return $removed
}

function Disable-Telemetry {
    Write-Log "Disabling telemetry..."
    $regKeys = @(
        @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"; Name = "AllowTelemetry"; Value = 0; Type = "DWord" }
        @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection"; Name = "AllowTelemetry"; Value = 0; Type = "DWord" }
        @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"; Name = "DoNotShowFeedbackNotifications"; Value = 1; Type = "DWord" }
        @{ Path = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; Name = "ContentDeliveryAllowed"; Value = 0; Type = "DWord" }
        @{ Path = "HKCU:\SOFTWARE\Microsoft\Siuf\Rules"; Name = "NumberOfSIUFInPeriod"; Value = 0; Type = "DWord" }
    )
    foreach ($reg in $regKeys) {
        try {
            if (-not (Test-Path $reg.Path)) { New-Item -Path $reg.Path -Force | Out-Null }
            Set-ItemProperty -Path $reg.Path -Name $reg.Name -Value $reg.Value -Type $reg.Type -Force
        } catch { Write-Log "Registry error: $($_.Exception.Message)" "WARN" }
    }
    # Disable telemetry services
    $services = @("DiagTrack", "dmwappushservice")
    foreach ($svc in $services) {
        try {
            Stop-Service -Name $svc -Force -ErrorAction Stop
            Set-Service -Name $svc -StartupType Disabled -ErrorAction Stop
            Write-Log "Disabled service: $svc"
        } catch { Write-Log "Could not disable $svc`: $($_.Exception.Message)" "WARN" }
    }
    # Disable scheduled telemetry tasks
    $tasks = @(
        "\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser"
        "\Microsoft\Windows\Application Experience\ProgramDataUpdater"
        "\Microsoft\Windows\Autochk\Proxy"
        "\Microsoft\Windows\Customer Experience Improvement Program\Consolidator"
        "\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip"
        "\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector"
    )
    foreach ($task in $tasks) {
        try { Disable-ScheduledTask -TaskName $task -ErrorAction Stop; Write-Log "Disabled task: $task" }
        catch { Write-Log "Could not disable task $task" "WARN" }
    }
    Write-Log "Telemetry disabled."
}

function Disable-Cortana {
    Write-Log "Disabling Cortana..."
    $path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search"
    if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
    Set-ItemProperty -Path $path -Name "AllowCortana" -Value 0 -Type DWord -Force
    Set-ItemProperty -Path $path -Name "AllowCortanaAboveLock" -Value 0 -Type DWord -Force
    Set-ItemProperty -Path $path -Name "AllowSearchToUseLocation" -Value 0 -Type DWord -Force
    Write-Log "Cortana disabled."
}

function Disable-Widgets {
    Write-Log "Disabling Widgets..."
    $path = "HKLM:\SOFTWARE\Policies\Microsoft\Dsh"
    if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
    Set-ItemProperty -Path $path -Name "AllowNewsAndInterests" -Value 0 -Type DWord -Force
    $path2 = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
    Set-ItemProperty -Path $path2 -Name "TaskbarDa" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
    Write-Log "Widgets disabled."
}

function Disable-GameBar {
    Write-Log "Disabling Game Bar & Game DVR..."
    $paths = @(
        @{ Path = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR"; Name = "AppCaptureEnabled"; Value = 0 }
        @{ Path = "HKCU:\System\GameConfigStore"; Name = "GameDVR_Enabled"; Value = 0 }
        @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR"; Name = "AllowGameDVR"; Value = 0 }
    )
    foreach ($reg in $paths) {
        try {
            if (-not (Test-Path $reg.Path)) { New-Item -Path $reg.Path -Force | Out-Null }
            Set-ItemProperty -Path $reg.Path -Name $reg.Name -Value $reg.Value -Type DWord -Force
        } catch { Write-Log "Registry error: $($_.Exception.Message)" "WARN" }
    }
    Write-Log "Game Bar disabled."
}

function Remove-OneDrive {
    Write-Log "Removing OneDrive..."
    try {
        taskkill /f /im OneDrive.exe 2>$null
        $onedrivePaths = @(
            "$env:SystemRoot\System32\OneDriveSetup.exe"
            "$env:SystemRoot\SysWOW64\OneDriveSetup.exe"
        )
        foreach ($p in $onedrivePaths) {
            if (Test-Path $p) {
                Start-Process $p -ArgumentList "/uninstall" -Wait -NoNewWindow -ErrorAction SilentlyContinue
                Write-Log "Uninstalled OneDrive via $p"
                break
            }
        }
        # Clean up folders
        $folders = @("$env:USERPROFILE\OneDrive", "$env:LOCALAPPDATA\Microsoft\OneDrive", "$env:PROGRAMDATA\Microsoft OneDrive")
        foreach ($f in $folders) {
            if (Test-Path $f) { Remove-Item $f -Recurse -Force -ErrorAction SilentlyContinue }
        }
        # Remove from Explorer sidebar
        $regPath = "HKCR:\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}"
        if (Test-Path $regPath) {
            Set-ItemProperty -Path $regPath -Name "System.IsPinnedToNameSpaceTree" -Value 0 -ErrorAction SilentlyContinue
        }
    } catch { Write-Log "OneDrive removal error: $($_.Exception.Message)" "WARN" }
    Write-Log "OneDrive removed."
}

function Disable-WebSearch {
    Write-Log "Disabling web search in Start Menu..."
    $path = "HKCU:\SOFTWARE\Policies\Microsoft\Windows\Explorer"
    if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
    Set-ItemProperty -Path $path -Name "DisableSearchBoxSuggestions" -Value 1 -Type DWord -Force
    $path2 = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search"
    if (-not (Test-Path $path2)) { New-Item -Path $path2 -Force | Out-Null }
    Set-ItemProperty -Path $path2 -Name "DisableWebSearch" -Value 1 -Type DWord -Force
    Set-ItemProperty -Path $path2 -Name "ConnectedSearchUseWeb" -Value 0 -Type DWord -Force
    Write-Log "Web search disabled."
}

function Clean-Taskbar {
    Write-Log "Cleaning taskbar..."
    $path = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
    Set-ItemProperty -Path $path -Name "TaskbarMn" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue  # Chat
    Set-ItemProperty -Path $path -Name "TaskbarDa" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue  # Widgets
    Set-ItemProperty -Path $path -Name "ShowTaskViewButton" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $path -Name "TaskbarAl" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue  # Left align
    # Hide search box (show as icon only)
    $searchPath = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search"
    Set-ItemProperty -Path $searchPath -Name "SearchboxTaskbarMode" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
    Write-Log "Taskbar cleaned."
}

function Disable-AutoReinstall {
    Write-Log "Preventing app auto-reinstall..."
    $cdmPath = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
    $cdmKeys = @(
        "SilentInstalledAppsEnabled"
        "SystemPaneSuggestionsEnabled"
        "SoftLandingEnabled"
        "SubscribedContent-338388Enabled"
        "SubscribedContent-338389Enabled"
        "SubscribedContent-353694Enabled"
        "SubscribedContent-353696Enabled"
        "OemPreInstalledAppsEnabled"
        "PreInstalledAppsEnabled"
        "PreInstalledAppsEverEnabled"
    )
    foreach ($key in $cdmKeys) {
        Set-ItemProperty -Path $cdmPath -Name $key -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
    }
    # Disable consumer features
    $cfPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent"
    if (-not (Test-Path $cfPath)) { New-Item -Path $cfPath -Force | Out-Null }
    Set-ItemProperty -Path $cfPath -Name "DisableWindowsConsumerFeatures" -Value 1 -Type DWord -Force
    Set-ItemProperty -Path $cfPath -Name "DisableCloudOptimizedContent" -Value 1 -Type DWord -Force
    Write-Log "Auto-reinstall prevention enabled."
}

function Disable-WindowsAds {
    Write-Log "Disabling Windows ads and suggestions..."
    $path = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
    $keys = @(
        "SubscribedContent-310093Enabled"
        "SubscribedContent-338387Enabled"
        "SubscribedContent-338388Enabled"
        "SubscribedContent-338389Enabled"
        "SubscribedContent-338393Enabled"
        "SubscribedContent-353694Enabled"
        "SubscribedContent-353696Enabled"
        "RotatingLockScreenEnabled"
        "RotatingLockScreenOverlayEnabled"
    )
    foreach ($key in $keys) {
        Set-ItemProperty -Path $path -Name $key -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
    }
    # Disable tips and suggestions in Settings
    $expPath = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
    Set-ItemProperty -Path $expPath -Name "Start_IrisRecommendations" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
    # Disable lock screen tips
    Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "SubscribedContent-338387Enabled" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
    Write-Log "Windows ads disabled."
}

function Optimize-Services {
    Write-Log "Optimizing services..."
    $disableServices = @(
        "XblAuthManager"          # Xbox Live Auth
        "XblGameSave"             # Xbox Live Game Save
        "XboxGipSvc"              # Xbox Accessory
        "XboxNetApiSvc"           # Xbox Live Networking
        "WMPNetworkSvc"           # Windows Media Player Sharing
        "WSearch"                 # Windows Search (saves CPU on old PCs)
        "MapsBroker"              # Downloaded Maps Manager
        "lfsvc"                   # Geolocation
        "RetailDemo"              # Retail Demo
        "wisvc"                   # Windows Insider
        "WerSvc"                  # Windows Error Reporting
        "Fax"                     # Fax (but keep Print Spooler)
    )
    foreach ($svc in $disableServices) {
        try {
            $service = Get-Service -Name $svc -ErrorAction Stop
            if ($service.Status -eq "Running") { Stop-Service -Name $svc -Force -ErrorAction Stop }
            Set-Service -Name $svc -StartupType Disabled -ErrorAction Stop
            Write-Log "Disabled service: $svc"
        } catch { Write-Log "Could not process service $svc`: $($_.Exception.Message)" "WARN" }
    }
    Write-Log "Service optimization complete."
}

function Create-DownloadsCleanupTask {
    Write-Log "Creating daily Downloads cleanup task..."
    try {
        $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument @"
-NoProfile -WindowStyle Hidden -Command "Get-ChildItem '$env:USERPROFILE\Downloads' -File | Where-Object { `$_.LastWriteTime -lt (Get-Date).AddDays(-1) } | Remove-Item -Force -ErrorAction SilentlyContinue"
"@
        $trigger = New-ScheduledTaskTrigger -Daily -At "3:00AM"
        $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
        Register-ScheduledTask -TaskName "PCPlus-CleanDownloads" -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force
        Write-Log "Downloads cleanup task created (daily at 3 AM, files older than 1 day)."
    } catch { Write-Log "Failed to create cleanup task: $($_.Exception.Message)" "ERROR" }
}

function Block-SoftwareInstalls {
    Write-Log "Blocking non-admin software installs..."
    # Enforce UAC to max
    $uacPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
    Set-ItemProperty -Path $uacPath -Name "ConsentPromptBehaviorAdmin" -Value 2 -Type DWord -Force  # Prompt for consent
    Set-ItemProperty -Path $uacPath -Name "ConsentPromptBehaviorUser" -Value 0 -Type DWord -Force   # Auto-deny for standard users
    Set-ItemProperty -Path $uacPath -Name "EnableInstallerDetection" -Value 1 -Type DWord -Force
    # Block exe from Downloads/Temp for standard users via Software Restriction Policy
    $srpPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Safer\CodeIdentifiers"
    if (-not (Test-Path $srpPath)) { New-Item -Path $srpPath -Force | Out-Null }
    Set-ItemProperty -Path $srpPath -Name "DefaultLevel" -Value 262144 -Type DWord -Force  # Unrestricted default
    Set-ItemProperty -Path $srpPath -Name "TransparentEnabled" -Value 1 -Type DWord -Force
    Write-Log "Software install blocking configured."
}

function Disable-MicrosoftStore {
    Write-Log "Disabling Microsoft Store..."
    $path = "HKLM:\SOFTWARE\Policies\Microsoft\WindowsStore"
    if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
    Set-ItemProperty -Path $path -Name "RemoveWindowsStore" -Value 1 -Type DWord -Force
    Set-ItemProperty -Path $path -Name "DisableStoreApps" -Value 1 -Type DWord -Force
    Write-Log "Microsoft Store disabled."
}

function Optimize-PowerSettings {
    Write-Log "Optimizing power settings..."
    # Set to High Performance
    powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c 2>$null
    # Never sleep on AC
    powercfg /change standby-timeout-ac 0
    powercfg /change monitor-timeout-ac 30
    powercfg /change hibernate-timeout-ac 0
    # Disable hibernation (frees disk space)
    powercfg /hibernate off
    Write-Log "Power settings optimized."
}

function Clean-StartMenuLayout {
    Write-Log "Cleaning Start Menu layout..."
    # Win 11: Remove pinned items from Start
    $startPath = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Start"
    if (Test-Path $startPath) {
        Set-ItemProperty -Path $startPath -Name "ShowRecentList" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $startPath -Name "ShowFrequentList" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
    }
    Write-Log "Start Menu cleaned."
}

# ─────────────────────────────────────────────────────────────────────────────
# MAIN EXECUTION
# ─────────────────────────────────────────────────────────────────────────────
$selections = Show-MainForm
if ($null -eq $selections) { exit }

Write-Log "========================================="
Write-Log "PC Plus Debloat Tool v1.0.0 starting"
Write-Log "Computer: $env:COMPUTERNAME"
Write-Log "OS: $((Get-CimInstance Win32_OperatingSystem).Caption)"
Write-Log "========================================="

$progressForm = New-Object System.Windows.Forms.Form
$progressForm.Text = "PC Plus - Debloating..."
$progressForm.Size = New-Object System.Drawing.Size(520, 200)
$progressForm.StartPosition = "CenterScreen"
$progressForm.FormBorderStyle = "FixedDialog"
$progressForm.MaximizeBox = $false
$progressForm.ControlBox = $false
$progressForm.BackColor = [System.Drawing.Color]::White

$pHeader = New-Object System.Windows.Forms.Panel
$pHeader.Dock = "Top"
$pHeader.Height = 40
$pHeader.BackColor = [System.Drawing.ColorTranslator]::FromHtml($COLOR_NAVY)
$progressForm.Controls.Add($pHeader)

$phl = New-Object System.Windows.Forms.Label
$phl.Text = "DEBLOATING IN PROGRESS..."
$phl.ForeColor = [System.Drawing.Color]::White
$phl.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
$phl.AutoSize = $false
$phl.Size = New-Object System.Drawing.Size(500, 40)
$phl.TextAlign = "MiddleCenter"
$pHeader.Controls.Add($phl)

$statusLbl = New-Object System.Windows.Forms.Label
$statusLbl.Name = "StatusLabel"
$statusLbl.Text = "Starting..."
$statusLbl.Location = New-Object System.Drawing.Point(30, 60)
$statusLbl.Size = New-Object System.Drawing.Size(450, 25)
$progressForm.Controls.Add($statusLbl)

$pb = New-Object System.Windows.Forms.ProgressBar
$pb.Name = "ProgressBar"
$pb.Location = New-Object System.Drawing.Point(30, 95)
$pb.Size = New-Object System.Drawing.Size(445, 28)
$pb.Minimum = 0; $pb.Maximum = 100; $pb.Style = "Continuous"
$progressForm.Controls.Add($pb)

$pctLbl = New-Object System.Windows.Forms.Label
$pctLbl.Name = "PctLabel"
$pctLbl.Text = "0%"
$pctLbl.Location = New-Object System.Drawing.Point(30, 128)
$pctLbl.Size = New-Object System.Drawing.Size(450, 20)
$pctLbl.TextAlign = "MiddleCenter"
$progressForm.Controls.Add($pctLbl)

$progressForm.Show()
$progressForm.Refresh()

function Update-DebloatProgress {
    param([string]$Status, [int]$Pct)
    $progressForm.Controls["StatusLabel"].Text = $Status
    $progressForm.Controls["ProgressBar"].Value = [Math]::Min($Pct, 100)
    $progressForm.Controls["PctLabel"].Text = "$Pct%"
    $progressForm.Refresh()
    [System.Windows.Forms.Application]::DoEvents()
}

$step = 0
$totalSteps = ($selections.Values | Where-Object { $_ -eq $true }).Count
if ($totalSteps -eq 0) { $totalSteps = 1 }

$taskMap = @{
    "RemoveBloatware"    = @{ Fn = { Remove-BloatwareApps }; Label = "Removing bloatware..." }
    "DisableTelemetry"   = @{ Fn = { Disable-Telemetry }; Label = "Disabling telemetry..." }
    "DisableCortana"     = @{ Fn = { Disable-Cortana }; Label = "Disabling Cortana..." }
    "DisableWidgets"     = @{ Fn = { Disable-Widgets }; Label = "Disabling Widgets..." }
    "DisableGameBar"     = @{ Fn = { Disable-GameBar }; Label = "Disabling Game Bar..." }
    "DisableOneDrive"    = @{ Fn = { Remove-OneDrive }; Label = "Removing OneDrive..." }
    "CleanStartMenu"     = @{ Fn = { Clean-StartMenuLayout }; Label = "Cleaning Start Menu..." }
    "DisableSearchWeb"   = @{ Fn = { Disable-WebSearch }; Label = "Disabling web search..." }
    "CleanTaskbar"       = @{ Fn = { Clean-Taskbar }; Label = "Cleaning taskbar..." }
    "DisableAutoInstall" = @{ Fn = { Disable-AutoReinstall }; Label = "Blocking auto-reinstall..." }
    "DisableAds"         = @{ Fn = { Disable-WindowsAds }; Label = "Disabling ads..." }
    "OptimizeServices"   = @{ Fn = { Optimize-Services }; Label = "Optimizing services..." }
    "ScheduleCleanup"    = @{ Fn = { Create-DownloadsCleanupTask }; Label = "Creating cleanup task..." }
    "BlockInstalls"      = @{ Fn = { Block-SoftwareInstalls }; Label = "Blocking installs..." }
    "DisableStore"       = @{ Fn = { Disable-MicrosoftStore }; Label = "Disabling Store..." }
    "PowerSettings"      = @{ Fn = { Optimize-PowerSettings }; Label = "Optimizing power..." }
}

foreach ($key in $taskMap.Keys) {
    if ($selections[$key] -eq $true) {
        $step++
        $pct = [math]::Round(($step / $totalSteps) * 100)
        Update-DebloatProgress $taskMap[$key].Label $pct
        try {
            & $taskMap[$key].Fn
        } catch {
            Write-Log "Error in ${key}: $($_.Exception.Message)" "ERROR"
        }
    }
}

Update-DebloatProgress "Complete!" 100
Start-Sleep -Milliseconds 500
$progressForm.Close()
$progressForm.Dispose()

Write-Log "========================================="
Write-Log "Debloat complete."
Write-Log "========================================="

$doneMsg = "Windows Debloat Complete!`n`n"
$doneMsg += "Actions performed: $step`n"
$doneMsg += "Log file: $LogFile`n`n"
$doneMsg += "A restart is recommended for all changes to take effect."

$result = [System.Windows.Forms.MessageBox]::Show(
    $doneMsg,
    "PC Plus Computing - Debloat Complete",
    [System.Windows.Forms.MessageBoxButtons]::YesNo,
    [System.Windows.Forms.MessageBoxIcon]::Information
)

if ($result -eq "Yes") {
    Write-Log "User chose to restart."
    Restart-Computer -Force
}

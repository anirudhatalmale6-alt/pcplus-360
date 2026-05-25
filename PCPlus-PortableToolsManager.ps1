<#
.SYNOPSIS
    PC Plus Computing 360 - Portable Tools Manager
.DESCRIPTION
    Manages a collection of portable diagnostic and repair tools for the USB toolkit.
    Provides a WinForms UI for browsing, installing, updating, and launching portable
    tools. Downloads and extracts tools to the Tools\ subfolder with SHA256 verification.
    Uses a bundled tools-manifest.json for version tracking.
.NOTES
    Company:  PC Plus Computing
    Website:  pcpluscomputing.com
    Phone:    604-760-1662 | 236-500-2700
    Version:  1.0.0
    Requires: PowerShell 5.1+, Windows 10/11, Administrator privileges
    Part of:  PC Plus 360 USB Diagnostic Toolkit
.EXAMPLE
    PowerShell.exe -ExecutionPolicy Bypass -File .\PCPlus-PortableToolsManager.ps1
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
            "PC Plus Portable Tools Manager - Elevation Required",
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

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
if ([string]::IsNullOrEmpty($ScriptDir)) { $ScriptDir = Get-Location }
$ToolsDir     = Join-Path $ScriptDir "Tools"
$ManifestFile = Join-Path $ScriptDir "tools-manifest.json"

if (-not (Test-Path $ToolsDir)) { New-Item -Path $ToolsDir -ItemType Directory -Force | Out-Null }

# ─────────────────────────────────────────────────────────────────────────────
# HELPERS
# ─────────────────────────────────────────────────────────────────────────────
function Invoke-Safe {
    param([scriptblock]$Block, $Default = $null)
    try { return (& $Block) } catch { return $Default }
}

function Get-FolderSizeMB {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return 0 }
    try {
        $bytes = (Get-ChildItem -Path $Path -Recurse -File -ErrorAction SilentlyContinue |
            Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
        if ($bytes) { return [Math]::Round($bytes / 1MB, 2) }
        return 0
    } catch { return 0 }
}

function Get-FileVersionFromExe {
    param([string]$ExePath)
    if (-not (Test-Path $ExePath)) { return "" }
    try {
        $ver = (Get-Item $ExePath -ErrorAction Stop).VersionInfo.FileVersion
        if ($ver) { return $ver.Trim() }
        return ""
    } catch { return "" }
}

# ─────────────────────────────────────────────────────────────────────────────
# DEFAULT TOOL MANIFEST
# ─────────────────────────────────────────────────────────────────────────────
$DefaultManifest = @(
    @{
        id          = "sysinternals"
        name        = "Microsoft Sysinternals Suite"
        description = "Full Sysinternals Suite - Process Explorer, ProcMon, PsExec, BGInfo, Disk2vhd, and 70+ tools."
        category    = "System Diagnostics"
        downloadUrl = "https://download.sysinternals.com/files/SysinternalsSuite.zip"
        fileName    = "SysinternalsSuite.zip"
        executable  = "procexp64.exe"
        version     = "2024.1"
        sha256      = ""
        isZip       = $true
        extractTo   = "Sysinternals"
    },
    @{
        id          = "crystaldiskinfo"
        name        = "CrystalDiskInfo Portable"
        description = "Disk health monitoring - SMART data, temperature, health status, SSD wear leveling."
        category    = "Disk Diagnostics"
        downloadUrl = "https://sourceforge.net/projects/crystaldiskinfo/files/latest/download"
        fileName    = "CrystalDiskInfo.zip"
        executable  = "DiskInfo64.exe"
        version     = "9.3.2"
        sha256      = ""
        isZip       = $true
        extractTo   = "CrystalDiskInfo"
    },
    @{
        id          = "librehardwaremonitor"
        name        = "LibreHardwareMonitor"
        description = "Open-source hardware monitoring - CPU/GPU temps, fan speeds, voltages, clocks, power draw."
        category    = "Hardware Monitoring"
        downloadUrl = "https://github.com/LibreHardwareMonitor/LibreHardwareMonitor/releases/latest"
        fileName    = "LibreHardwareMonitor.zip"
        executable  = "LibreHardwareMonitor.exe"
        version     = "0.9.3"
        sha256      = ""
        isZip       = $true
        extractTo   = "LibreHardwareMonitor"
    },
    @{
        id          = "nmap"
        name        = "Nmap Portable"
        description = "Network scanner and security auditing tool - port scanning, OS detection, service enumeration."
        category    = "Network Security"
        downloadUrl = "https://nmap.org/dist/nmap-7.95-win32.zip"
        fileName    = "nmap-portable.zip"
        executable  = "nmap.exe"
        version     = "7.95"
        sha256      = ""
        isZip       = $true
        extractTo   = "Nmap"
    },
    @{
        id          = "wireshark"
        name        = "Wireshark Portable"
        description = "Network protocol analyzer - deep packet inspection, traffic capture, protocol decode."
        category    = "Network Security"
        downloadUrl = "https://www.wireshark.org/download.html"
        fileName    = "WiresharkPortable64.exe"
        executable  = "Wireshark.exe"
        version     = "4.4.2"
        sha256      = ""
        isZip       = $false
        extractTo   = "Wireshark"
    },
    @{
        id          = "adwcleaner"
        name        = "Malwarebytes AdwCleaner"
        description = "Removes adware, PUPs, browser hijackers, unwanted toolbars, and pre-installed bloatware."
        category    = "Malware Removal"
        downloadUrl = "https://adwcleaner.malwarebytes.com/adwcleaner?channel=release"
        fileName    = "adwcleaner.exe"
        executable  = "adwcleaner.exe"
        version     = "8.4.2"
        sha256      = ""
        isZip       = $false
        extractTo   = "AdwCleaner"
    },
    @{
        id          = "autoruns"
        name        = "Autoruns"
        description = "Shows all auto-start programs - startup entries, services, drivers, scheduled tasks, Winlogon."
        category    = "System Diagnostics"
        downloadUrl = "https://download.sysinternals.com/files/Autoruns.zip"
        fileName    = "Autoruns.zip"
        executable  = "Autoruns64.exe"
        version     = "14.11"
        sha256      = ""
        isZip       = $true
        extractTo   = "Autoruns"
    },
    @{
        id          = "tcpview"
        name        = "TCPView"
        description = "Real-time TCP/UDP endpoint viewer - shows all active connections, listening ports, owning process."
        category    = "Network Security"
        downloadUrl = "https://download.sysinternals.com/files/TCPView.zip"
        fileName    = "TCPView.zip"
        executable  = "tcpview64.exe"
        version     = "4.19"
        sha256      = ""
        isZip       = $true
        extractTo   = "TCPView"
    },
    @{
        id          = "smartmontools"
        name        = "smartmontools"
        description = "Command-line SMART monitoring and analysis - smartctl for HDD/SSD health diagnostics."
        category    = "Disk Diagnostics"
        downloadUrl = "https://sourceforge.net/projects/smartmontools/files/latest/download"
        fileName    = "smartmontools-win.zip"
        executable  = "smartctl.exe"
        version     = "7.4"
        sha256      = ""
        isZip       = $true
        extractTo   = "smartmontools"
    },
    @{
        id          = "occt"
        name        = "OCCT Portable"
        description = "Stability and stress testing - CPU, GPU, memory, power supply testing with thermal monitoring."
        category    = "Stress Testing"
        downloadUrl = "https://www.ocbase.com/download"
        fileName    = "OCCT.zip"
        executable  = "OCCT.exe"
        version     = "12.1"
        sha256      = ""
        isZip       = $true
        extractTo   = "OCCT"
    },
    @{
        id          = "yara"
        name        = "YARA"
        description = "Pattern matching tool for malware researchers - identify and classify malware samples by rules."
        category    = "Threat Detection"
        downloadUrl = "https://github.com/VirusTotal/yara/releases/latest"
        fileName    = "yara-master-win64.zip"
        executable  = "yara64.exe"
        version     = "4.5.2"
        sha256      = ""
        isZip       = $true
        extractTo   = "YARA"
    },
    @{
        id          = "sigma"
        name        = "Sigma Rules"
        description = "Generic signature format for SIEM/log detection - threat detection rules for Windows event logs."
        category    = "Threat Detection"
        downloadUrl = "https://github.com/SigmaHQ/sigma/archive/refs/heads/master.zip"
        fileName    = "sigma-master.zip"
        executable  = ""
        version     = "latest"
        sha256      = ""
        isZip       = $true
        extractTo   = "SigmaRules"
    },
    @{
        id          = "sysmon"
        name        = "Sysmon"
        description = "System Monitor - advanced Windows event logging for process creation, network, file changes."
        category    = "Threat Detection"
        downloadUrl = "https://download.sysinternals.com/files/Sysmon.zip"
        fileName    = "Sysmon.zip"
        executable  = "Sysmon64.exe"
        version     = "15.15"
        sha256      = ""
        isZip       = $true
        extractTo   = "Sysmon"
    },
    @{
        id          = "velociraptor"
        name        = "Velociraptor Lite"
        description = "Endpoint visibility and forensic tool - collect artifacts, hunt threats, incident response."
        category    = "Threat Detection"
        downloadUrl = "https://github.com/Velocidex/velociraptor/releases/latest"
        fileName    = "velociraptor-v0.73-windows-amd64.exe"
        executable  = "velociraptor.exe"
        version     = "0.73"
        sha256      = ""
        isZip       = $false
        extractTo   = "Velociraptor"
    }
)

# ─────────────────────────────────────────────────────────────────────────────
# MANIFEST MANAGEMENT
# ─────────────────────────────────────────────────────────────────────────────
function Load-Manifest {
    if (Test-Path $ManifestFile) {
        try {
            $json = Get-Content $ManifestFile -Raw -ErrorAction Stop | ConvertFrom-Json
            $tools = [System.Collections.ArrayList]::new()
            foreach ($t in $json) {
                [void]$tools.Add(@{
                    id          = $t.id
                    name        = $t.name
                    description = $t.description
                    category    = $t.category
                    downloadUrl = $t.downloadUrl
                    fileName    = $t.fileName
                    executable  = $t.executable
                    version     = $t.version
                    sha256      = $t.sha256
                    isZip       = [bool]$t.isZip
                    extractTo   = $t.extractTo
                })
            }
            return $tools
        } catch {
            return $null
        }
    }
    return $null
}

function Save-Manifest {
    param([System.Collections.ArrayList]$Tools)
    $jsonArray = @()
    foreach ($t in $Tools) {
        $jsonArray += [PSCustomObject]@{
            id          = $t.id
            name        = $t.name
            description = $t.description
            category    = $t.category
            downloadUrl = $t.downloadUrl
            fileName    = $t.fileName
            executable  = $t.executable
            version     = $t.version
            sha256      = $t.sha256
            isZip       = $t.isZip
            extractTo   = $t.extractTo
        }
    }
    $jsonArray | ConvertTo-Json -Depth 5 | Out-File -FilePath $ManifestFile -Encoding UTF8 -Force
}

function Initialize-Manifest {
    $loaded = Load-Manifest
    if ($loaded -and $loaded.Count -gt 0) {
        # Merge in any new default tools that aren't in the saved manifest
        $existingIds = @{}
        foreach ($t in $loaded) { $existingIds[$t.id] = $true }
        $added = 0
        foreach ($t in $DefaultManifest) {
            if (-not $existingIds.ContainsKey($t.id)) {
                [void]$loaded.Add($t)
                $added++
            }
        }
        if ($added -gt 0) { Save-Manifest $loaded }
        return $loaded
    }
    # Create from default
    $tools = [System.Collections.ArrayList]::new()
    foreach ($t in $DefaultManifest) {
        [void]$tools.Add($t)
    }
    Save-Manifest $tools
    return $tools
}

# ─────────────────────────────────────────────────────────────────────────────
# TOOL STATUS CHECK
# ─────────────────────────────────────────────────────────────────────────────
function Get-ToolStatus {
    param([hashtable]$Tool)

    $toolDir   = Join-Path $ToolsDir $Tool.extractTo
    $installed = $false
    $localVer  = ""
    $sizeMB    = 0
    $foundPath = ""

    # Tools without an executable (e.g. rule collections like Sigma)
    if (-not $Tool.executable -or $Tool.executable -eq "") {
        $installed = Test-Path $toolDir
        $foundPath = $toolDir
    } else {
        $exePath = Join-Path $toolDir $Tool.executable
        $foundPath = $exePath
        $installed = Test-Path $exePath

        if (-not $installed) {
            # Search in Tools root folder (user may have dropped EXEs directly there)
            $rootExe = Join-Path $ToolsDir $Tool.executable
            if (Test-Path $rootExe) {
                $installed = $true
                $foundPath = $rootExe
            }
        }

        if (-not $installed) {
            # Recursive search anywhere under Tools folder
            $found = Get-ChildItem -Path $ToolsDir -Filter $Tool.executable -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($found) {
                $installed = $true
                $foundPath = $found.FullName
                $toolDir = $found.DirectoryName
            }
        }
    }

    if ($installed) {
        $localVer = Get-FileVersionFromExe $foundPath
        if (-not $localVer) { $localVer = "Installed" }
        $sizeMB = Get-FolderSizeMB $toolDir
    }

    $updateAvailable = $false
    if ($installed -and $localVer -and $localVer -ne "Installed" -and $Tool.version) {
        if ($localVer -ne $Tool.version) {
            $updateAvailable = $true
        }
    }

    return @{
        Installed       = $installed
        LocalVersion    = $localVer
        ManifestVersion = $Tool.version
        UpdateAvailable = $updateAvailable
        SizeMB          = $sizeMB
        ExePath         = $foundPath
        ToolDir         = $toolDir
    }
}

function Get-CategoryLookup {
    # Load the categorized manifest for proper category assignment
    $catManifest = Join-Path $ScriptDir "tools-manifest.json"
    $lookup = @{}
    if (Test-Path $catManifest) {
        try {
            $catData = Get-Content $catManifest -Raw | ConvertFrom-Json
            foreach ($cat in $catData.categories) {
                foreach ($tool in $cat.tools) {
                    $lookup[$tool.exe.ToLower()] = @{
                        Category    = $cat.name
                        Name        = $tool.name
                        Description = $tool.description
                    }
                }
            }
        } catch { }
    }
    return $lookup
}

function Find-UnregisteredTools {
    # Scan Tools folder for EXEs not in the manifest and auto-add them
    $knownExes = @{}
    foreach ($t in $script:Manifest) {
        $knownExes[$t.executable.ToLower()] = $true
    }

    $catLookup = Get-CategoryLookup
    $newTools = [System.Collections.ArrayList]::new()
    $allExes = Get-ChildItem -Path $ToolsDir -Filter "*.exe" -Recurse -ErrorAction SilentlyContinue

    foreach ($exe in $allExes) {
        $exeName = $exe.Name.ToLower()
        if ($knownExes.ContainsKey($exeName)) { continue }
        # Skip common non-tool EXEs
        if ($exeName -match "^(uninstall|setup|update|uninst|install)") { continue }

        $ver = Get-FileVersionFromExe $exe.FullName
        $desc = ""
        $category = "Auto-Detected"
        $displayName = $exe.BaseName

        # Check categorized manifest first
        if ($catLookup.ContainsKey($exeName)) {
            $catInfo = $catLookup[$exeName]
            $category = $catInfo.Category
            $displayName = $catInfo.Name
            $desc = $catInfo.Description
        } else {
            try {
                $fi = $exe.VersionInfo
                if ($fi.FileDescription) { $desc = $fi.FileDescription }
                elseif ($fi.ProductName) { $desc = $fi.ProductName }
            } catch {}
            if (-not $desc) { $desc = "Portable tool" }
        }

        $relDir = $exe.DirectoryName
        $extractTo = if ($relDir -eq $ToolsDir) { $exe.BaseName } else {
            $relDir.Replace($ToolsDir, "").TrimStart("\", "/")
            $parts = $relDir.Replace($ToolsDir, "").TrimStart("\", "/").Split("\", "/")
            $parts[0]
        }

        $toolEntry = @{
            id          = "auto_" + ($exe.BaseName.ToLower() -replace '[^a-z0-9]', '_')
            name        = $displayName
            description = $desc
            category    = $category
            downloadUrl = ""
            fileName    = $exe.Name
            executable  = $exe.Name
            version     = if ($ver) { $ver } else { "" }
            sha256      = ""
            isZip       = $false
            extractTo   = $extractTo
        }

        [void]$newTools.Add($toolEntry)
        $knownExes[$exeName] = $true
    }

    return $newTools
}

# ─────────────────────────────────────────────────────────────────────────────
# DOWNLOAD & INSTALL
# ─────────────────────────────────────────────────────────────────────────────
function Install-Tool {
    param(
        [hashtable]$Tool,
        [System.Windows.Forms.TextBox]$Log,
        [System.Windows.Forms.ProgressBar]$Progress
    )

    $toolDir   = Join-Path $ToolsDir $Tool.extractTo
    $downloadPath = Join-Path $env:TEMP $Tool.fileName

    if (-not (Test-Path $toolDir)) {
        New-Item -Path $toolDir -ItemType Directory -Force | Out-Null
    }

    $Log.AppendText("Downloading $($Tool.name)...`r`n")
    $Log.AppendText("  URL: $($Tool.downloadUrl)`r`n")
    $Progress.Value = 10

    try {
        # Check if URL is a placeholder
        if ($Tool.downloadUrl -match "PLACEHOLDER|example\.com|TODO") {
            $Log.AppendText("  [SKIP] Download URL is a placeholder - update tools-manifest.json with the real URL`r`n")
            $Progress.Value = 0
            return $false
        }

        $webClient = New-Object System.Net.WebClient
        $webClient.Headers.Add("User-Agent", "PCPlus360-ToolsManager/$SCRIPT_VERSION")

        try {
            $webClient.DownloadFile($Tool.downloadUrl, $downloadPath)
        } finally {
            $webClient.Dispose()
        }

        $Progress.Value = 50
        $Log.AppendText("  Downloaded to: $downloadPath`r`n")

        # Verify SHA256 if not a placeholder
        if ($Tool.sha256 -and $Tool.sha256 -notmatch "PLACEHOLDER") {
            $Log.AppendText("  Verifying SHA256 hash...`r`n")
            $fileHash = (Get-FileHash -Path $downloadPath -Algorithm SHA256 -ErrorAction Stop).Hash
            if ($fileHash -ne $Tool.sha256) {
                $Log.AppendText("  [FAIL] SHA256 mismatch!`r`n")
                $Log.AppendText("    Expected: $($Tool.sha256)`r`n")
                $Log.AppendText("    Got:      $fileHash`r`n")
                $Log.AppendText("  File NOT installed for security reasons.`r`n")
                Remove-Item -Path $downloadPath -Force -ErrorAction SilentlyContinue
                $Progress.Value = 0
                return $false
            }
            $Log.AppendText("  [PASS] SHA256 verified`r`n")
        } else {
            $Log.AppendText("  [WARN] SHA256 hash is a placeholder - skipping verification`r`n")
        }

        $Progress.Value = 70

        # Extract or copy
        if ($Tool.isZip) {
            $Log.AppendText("  Extracting to: $toolDir`r`n")
            try {
                # Use .NET for extraction (compatible with PS 5.1)
                Add-Type -AssemblyName System.IO.Compression.FileSystem
                # Clean existing contents
                if (Test-Path $toolDir) {
                    Get-ChildItem $toolDir -Recurse | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
                }
                [System.IO.Compression.ZipFile]::ExtractToDirectory($downloadPath, $toolDir)
            } catch {
                $Log.AppendText("  [FAIL] Extraction failed: $($_.Exception.Message)`r`n")
                $Progress.Value = 0
                return $false
            }
        } else {
            $Log.AppendText("  Copying to: $toolDir`r`n")
            Copy-Item -Path $downloadPath -Destination (Join-Path $toolDir $Tool.executable) -Force
        }

        $Progress.Value = 90

        # Clean up temp file
        Remove-Item -Path $downloadPath -Force -ErrorAction SilentlyContinue

        # Verify executable exists
        $exePath = Join-Path $toolDir $Tool.executable
        if (Test-Path $exePath) {
            $Log.AppendText("  [PASS] $($Tool.name) installed successfully`r`n")
            $Progress.Value = 100
            return $true
        } else {
            # Check if it's in a subfolder (common with ZIP files)
            $found = Get-ChildItem -Path $toolDir -Filter $Tool.executable -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($found) {
                $Log.AppendText("  [PASS] $($Tool.name) installed (found at: $($found.FullName))`r`n")
                $Progress.Value = 100
                return $true
            }
            $Log.AppendText("  [WARN] Installed but executable not found at expected path`r`n")
            $Log.AppendText("         Expected: $exePath`r`n")
            $Progress.Value = 100
            return $true
        }
    } catch {
        $Log.AppendText("  [FAIL] Download/install failed: $($_.Exception.Message)`r`n")
        Remove-Item -Path $downloadPath -Force -ErrorAction SilentlyContinue
        $Progress.Value = 0
        return $false
    }
}

function Launch-Tool {
    param([hashtable]$Tool, [System.Windows.Forms.TextBox]$Log)

    $status = Get-ToolStatus $Tool
    if ($status.Installed -and (Test-Path $status.ExePath)) {
        $Log.AppendText("Launching $($Tool.name)...`r`n")
        try {
            Start-Process -FilePath $status.ExePath -WorkingDirectory $status.ToolDir
        } catch {
            $Log.AppendText("  [FAIL] Could not launch: $($_.Exception.Message)`r`n")
        }
    } else {
        $Log.AppendText("[FAIL] $($Tool.name) not found. Install it first.`r`n")
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# WINFORMS UI
# ═══════════════════════════════════════════════════════════════════════════════

function Show-MainForm {
    $script:Manifest = Initialize-Manifest

    # Auto-detect tools dropped directly into the Tools folder
    $discovered = Find-UnregisteredTools
    if ($discovered -and $discovered.Count -gt 0) {
        foreach ($newTool in $discovered) {
            [void]$script:Manifest.Add($newTool)
        }
        Save-Manifest $script:Manifest
    }

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "PC Plus Computing 360 - Portable Tools Manager"
    $form.Size = New-Object System.Drawing.Size(1100, 760)
    $form.StartPosition = "CenterScreen"
    $form.BackColor = [System.Drawing.ColorTranslator]::FromHtml($COLOR_NAVY)
    $form.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $form.MinimumSize = New-Object System.Drawing.Size(900, 600)

    # ── Header Panel ──
    $headerPanel = New-Object System.Windows.Forms.Panel
    $headerPanel.Dock = "Top"
    $headerPanel.Height = 70
    $headerPanel.BackColor = [System.Drawing.ColorTranslator]::FromHtml("#0d2137")
    $form.Controls.Add($headerPanel)

    $lblTitle = New-Object System.Windows.Forms.Label
    $lblTitle.Text = "PC PLUS COMPUTING 360 - PORTABLE TOOLS MANAGER"
    $lblTitle.ForeColor = [System.Drawing.Color]::White
    $lblTitle.Font = New-Object System.Drawing.Font("Segoe UI", 16, [System.Drawing.FontStyle]::Bold)
    $lblTitle.AutoSize = $false
    $lblTitle.Size = New-Object System.Drawing.Size(750, 35)
    $lblTitle.Location = New-Object System.Drawing.Point(20, 8)
    $headerPanel.Controls.Add($lblTitle)

    $lblSubtitle = New-Object System.Windows.Forms.Label
    $lblSubtitle.Text = "Tools directory: $ToolsDir"
    $lblSubtitle.ForeColor = [System.Drawing.ColorTranslator]::FromHtml("#8b949e")
    $lblSubtitle.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $lblSubtitle.AutoSize = $true
    $lblSubtitle.Location = New-Object System.Drawing.Point(20, 42)
    $headerPanel.Controls.Add($lblSubtitle)

    # ── Search/Filter Panel ──
    $filterPanel = New-Object System.Windows.Forms.Panel
    $filterPanel.Dock = "Top"
    $filterPanel.Height = 40
    $filterPanel.BackColor = [System.Drawing.ColorTranslator]::FromHtml("#161b22")
    $form.Controls.Add($filterPanel)

    $lblSearch = New-Object System.Windows.Forms.Label
    $lblSearch.Text = "Search:"
    $lblSearch.ForeColor = [System.Drawing.ColorTranslator]::FromHtml("#8b949e")
    $lblSearch.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $lblSearch.AutoSize = $true
    $lblSearch.Location = New-Object System.Drawing.Point(10, 10)
    $filterPanel.Controls.Add($lblSearch)

    $txtSearch = New-Object System.Windows.Forms.TextBox
    $txtSearch.Size = New-Object System.Drawing.Size(250, 24)
    $txtSearch.Location = New-Object System.Drawing.Point(70, 8)
    $txtSearch.BackColor = [System.Drawing.ColorTranslator]::FromHtml("#0d1117")
    $txtSearch.ForeColor = [System.Drawing.ColorTranslator]::FromHtml("#c9d1d9")
    $txtSearch.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $filterPanel.Controls.Add($txtSearch)

    $lblCategory = New-Object System.Windows.Forms.Label
    $lblCategory.Text = "Category:"
    $lblCategory.ForeColor = [System.Drawing.ColorTranslator]::FromHtml("#8b949e")
    $lblCategory.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $lblCategory.AutoSize = $true
    $lblCategory.Location = New-Object System.Drawing.Point(340, 10)
    $filterPanel.Controls.Add($lblCategory)

    $cmbCategory = New-Object System.Windows.Forms.ComboBox
    $cmbCategory.Size = New-Object System.Drawing.Size(200, 24)
    $cmbCategory.Location = New-Object System.Drawing.Point(420, 8)
    $cmbCategory.BackColor = [System.Drawing.ColorTranslator]::FromHtml("#0d1117")
    $cmbCategory.ForeColor = [System.Drawing.ColorTranslator]::FromHtml("#c9d1d9")
    $cmbCategory.DropDownStyle = "DropDownList"
    $cmbCategory.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    [void]$cmbCategory.Items.Add("All Categories")
    $categories = $script:Manifest | ForEach-Object { $_.category } | Sort-Object -Unique
    foreach ($cat in $categories) { [void]$cmbCategory.Items.Add($cat) }
    $cmbCategory.SelectedIndex = 0
    $filterPanel.Controls.Add($cmbCategory)

    $lblDiskUsage = New-Object System.Windows.Forms.Label
    $lblDiskUsage.Text = "Total disk usage: calculating..."
    $lblDiskUsage.ForeColor = [System.Drawing.ColorTranslator]::FromHtml($COLOR_ACCENT)
    $lblDiskUsage.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $lblDiskUsage.AutoSize = $true
    $lblDiskUsage.Location = New-Object System.Drawing.Point(650, 12)
    $filterPanel.Controls.Add($lblDiskUsage)

    # ── Main Split Container ──
    $splitContainer = New-Object System.Windows.Forms.SplitContainer
    $splitContainer.Dock = "Fill"
    $splitContainer.Orientation = "Horizontal"
    $splitContainer.SplitterDistance = 400
    $splitContainer.BackColor = [System.Drawing.ColorTranslator]::FromHtml($COLOR_NAVY)
    $splitContainer.Panel1.BackColor = [System.Drawing.ColorTranslator]::FromHtml("#0d1117")
    $splitContainer.Panel2.BackColor = [System.Drawing.ColorTranslator]::FromHtml("#0d1117")
    $form.Controls.Add($splitContainer)

    # ── Tools Grid ──
    $dgv = New-Object System.Windows.Forms.DataGridView
    $dgv.Dock = "Fill"
    $dgv.BackgroundColor = [System.Drawing.ColorTranslator]::FromHtml("#0d1117")
    $dgv.ForeColor = [System.Drawing.ColorTranslator]::FromHtml("#c9d1d9")
    $dgv.GridColor = [System.Drawing.ColorTranslator]::FromHtml("#30363d")
    $dgv.BorderStyle = "None"
    $dgv.CellBorderStyle = "SingleHorizontal"
    $dgv.ColumnHeadersBorderStyle = "Single"
    $dgv.EnableHeadersVisualStyles = $false
    $dgv.RowHeadersVisible = $false
    $dgv.AllowUserToAddRows = $false
    $dgv.AllowUserToDeleteRows = $false
    $dgv.ReadOnly = $true
    $dgv.SelectionMode = "FullRowSelect"
    $dgv.MultiSelect = $false
    $dgv.AutoSizeColumnsMode = "Fill"
    $dgv.DefaultCellStyle.BackColor = [System.Drawing.ColorTranslator]::FromHtml("#0d1117")
    $dgv.DefaultCellStyle.ForeColor = [System.Drawing.ColorTranslator]::FromHtml("#c9d1d9")
    $dgv.DefaultCellStyle.SelectionBackColor = [System.Drawing.ColorTranslator]::FromHtml("#1a2d4a")
    $dgv.DefaultCellStyle.SelectionForeColor = [System.Drawing.Color]::White
    $dgv.DefaultCellStyle.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $dgv.ColumnHeadersDefaultCellStyle.BackColor = [System.Drawing.ColorTranslator]::FromHtml("#21262d")
    $dgv.ColumnHeadersDefaultCellStyle.ForeColor = [System.Drawing.ColorTranslator]::FromHtml("#8b949e")
    $dgv.ColumnHeadersDefaultCellStyle.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $dgv.ColumnHeadersHeight = 32
    $dgv.RowTemplate.Height = 28
    $splitContainer.Panel1.Controls.Add($dgv)

    # Define columns
    $colDefs = @("Name", "Category", "Status", "Installed Ver", "Latest Ver", "Size (MB)", "Description")
    foreach ($col in $colDefs) {
        $c = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
        $c.Name = $col
        $c.HeaderText = $col
        [void]$dgv.Columns.Add($c)
    }
    # Adjust column widths
    $dgv.Columns["Name"].FillWeight = 15
    $dgv.Columns["Category"].FillWeight = 13
    $dgv.Columns["Status"].FillWeight = 12
    $dgv.Columns["Installed Ver"].FillWeight = 10
    $dgv.Columns["Latest Ver"].FillWeight = 10
    $dgv.Columns["Size (MB)"].FillWeight = 8
    $dgv.Columns["Description"].FillWeight = 32

    # ── Log Panel ──
    $txtLog = New-Object System.Windows.Forms.TextBox
    $txtLog.Multiline = $true
    $txtLog.ReadOnly = $true
    $txtLog.ScrollBars = "Vertical"
    $txtLog.Dock = "Fill"
    $txtLog.BackColor = [System.Drawing.ColorTranslator]::FromHtml("#0d1117")
    $txtLog.ForeColor = [System.Drawing.ColorTranslator]::FromHtml("#c9d1d9")
    $txtLog.Font = New-Object System.Drawing.Font("Consolas", 9)
    $splitContainer.Panel2.Controls.Add($txtLog)

    # ── Progress Bar ──
    $progressBar = New-Object System.Windows.Forms.ProgressBar
    $progressBar.Dock = "Bottom"
    $progressBar.Height = 8
    $progressBar.Style = "Continuous"
    $progressBar.Minimum = 0
    $progressBar.Maximum = 100
    $progressBar.Value = 0
    $splitContainer.Panel2.Controls.Add($progressBar)

    # ── Bottom Button Panel ──
    $panelBtn = New-Object System.Windows.Forms.Panel
    $panelBtn.Dock = "Bottom"
    $panelBtn.Height = 50
    $panelBtn.BackColor = [System.Drawing.ColorTranslator]::FromHtml("#161b22")
    $form.Controls.Add($panelBtn)

    $btnX = 10

    $btnRefresh = New-Object System.Windows.Forms.Button
    $btnRefresh.Text = "Refresh"
    $btnRefresh.Size = New-Object System.Drawing.Size(100, 35)
    $btnRefresh.Location = New-Object System.Drawing.Point($btnX, 8)
    $btnRefresh.BackColor = [System.Drawing.ColorTranslator]::FromHtml($COLOR_ACCENT)
    $btnRefresh.ForeColor = [System.Drawing.Color]::White
    $btnRefresh.FlatStyle = "Flat"
    $btnRefresh.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $btnRefresh.Cursor = [System.Windows.Forms.Cursors]::Hand
    $panelBtn.Controls.Add($btnRefresh)
    $btnX += 115

    $btnInstall = New-Object System.Windows.Forms.Button
    $btnInstall.Text = "Install"
    $btnInstall.Size = New-Object System.Drawing.Size(100, 35)
    $btnInstall.Location = New-Object System.Drawing.Point($btnX, 8)
    $btnInstall.BackColor = [System.Drawing.ColorTranslator]::FromHtml($COLOR_GREEN)
    $btnInstall.ForeColor = [System.Drawing.Color]::White
    $btnInstall.FlatStyle = "Flat"
    $btnInstall.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $btnInstall.Cursor = [System.Windows.Forms.Cursors]::Hand
    $panelBtn.Controls.Add($btnInstall)
    $btnX += 115

    $btnLaunch = New-Object System.Windows.Forms.Button
    $btnLaunch.Text = "Launch"
    $btnLaunch.Size = New-Object System.Drawing.Size(100, 35)
    $btnLaunch.Location = New-Object System.Drawing.Point($btnX, 8)
    $btnLaunch.BackColor = [System.Drawing.ColorTranslator]::FromHtml($COLOR_ORANGE)
    $btnLaunch.ForeColor = [System.Drawing.Color]::White
    $btnLaunch.FlatStyle = "Flat"
    $btnLaunch.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $btnLaunch.Cursor = [System.Windows.Forms.Cursors]::Hand
    $panelBtn.Controls.Add($btnLaunch)
    $btnX += 115

    $btnInstallAll = New-Object System.Windows.Forms.Button
    $btnInstallAll.Text = "Install All"
    $btnInstallAll.Size = New-Object System.Drawing.Size(120, 35)
    $btnInstallAll.Location = New-Object System.Drawing.Point($btnX, 8)
    $btnInstallAll.BackColor = [System.Drawing.ColorTranslator]::FromHtml("#2ecc71")
    $btnInstallAll.ForeColor = [System.Drawing.Color]::White
    $btnInstallAll.FlatStyle = "Flat"
    $btnInstallAll.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $btnInstallAll.Cursor = [System.Windows.Forms.Cursors]::Hand
    $panelBtn.Controls.Add($btnInstallAll)
    $btnX += 135

    $btnUpdateAll = New-Object System.Windows.Forms.Button
    $btnUpdateAll.Text = "Update All"
    $btnUpdateAll.Size = New-Object System.Drawing.Size(120, 35)
    $btnUpdateAll.Location = New-Object System.Drawing.Point($btnX, 8)
    $btnUpdateAll.BackColor = [System.Drawing.ColorTranslator]::FromHtml($COLOR_ACCENT)
    $btnUpdateAll.ForeColor = [System.Drawing.Color]::White
    $btnUpdateAll.FlatStyle = "Flat"
    $btnUpdateAll.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $btnUpdateAll.Cursor = [System.Windows.Forms.Cursors]::Hand
    $panelBtn.Controls.Add($btnUpdateAll)
    $btnX += 135

    $btnCheckUpdates = New-Object System.Windows.Forms.Button
    $btnCheckUpdates.Text = "Check Updates"
    $btnCheckUpdates.Size = New-Object System.Drawing.Size(140, 35)
    $btnCheckUpdates.Location = New-Object System.Drawing.Point($btnX, 8)
    $btnCheckUpdates.BackColor = [System.Drawing.ColorTranslator]::FromHtml("#6c757d")
    $btnCheckUpdates.ForeColor = [System.Drawing.Color]::White
    $btnCheckUpdates.FlatStyle = "Flat"
    $btnCheckUpdates.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $btnCheckUpdates.Cursor = [System.Windows.Forms.Cursors]::Hand
    $panelBtn.Controls.Add($btnCheckUpdates)

    $btnOpenFolder = New-Object System.Windows.Forms.Button
    $btnOpenFolder.Text = "Open Tools Folder"
    $btnOpenFolder.Size = New-Object System.Drawing.Size(160, 35)
    $btnOpenFolder.Location = New-Object System.Drawing.Point(($form.ClientSize.Width - 180), 8)
    $btnOpenFolder.Anchor = "Top, Right"
    $btnOpenFolder.BackColor = [System.Drawing.ColorTranslator]::FromHtml("#484f58")
    $btnOpenFolder.ForeColor = [System.Drawing.Color]::White
    $btnOpenFolder.FlatStyle = "Flat"
    $btnOpenFolder.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $btnOpenFolder.Cursor = [System.Windows.Forms.Cursors]::Hand
    $panelBtn.Controls.Add($btnOpenFolder)

    # ── Populate Grid Function ──
    $populateGrid = {
        $dgv.Rows.Clear()
        $searchText = $txtSearch.Text.Trim().ToLower()
        $selectedCategory = $cmbCategory.SelectedItem

        $totalSizeMB = 0

        foreach ($tool in $script:Manifest) {
            # Apply search filter
            if ($searchText -and
                -not ($tool.name.ToLower().Contains($searchText)) -and
                -not ($tool.description.ToLower().Contains($searchText)) -and
                -not ($tool.category.ToLower().Contains($searchText))) {
                continue
            }

            # Apply category filter
            if ($selectedCategory -and $selectedCategory -ne "All Categories" -and $tool.category -ne $selectedCategory) {
                continue
            }

            $status = Get-ToolStatus $tool
            $statusText = if (-not $status.Installed) { "Not Installed" }
                          elseif ($status.UpdateAvailable) { "Update Available" }
                          else { "Installed" }
            $localVer = if ($status.LocalVersion) { $status.LocalVersion } else { "-" }
            $sizeText = if ($status.SizeMB -gt 0) { $status.SizeMB.ToString("F1") } else { "-" }
            $totalSizeMB += $status.SizeMB

            $rowIdx = $dgv.Rows.Add(
                $tool.name,
                $tool.category,
                $statusText,
                $localVer,
                $tool.version,
                $sizeText,
                $tool.description
            )

            # Color the status cell
            $row = $dgv.Rows[$rowIdx]
            $statusCell = $row.Cells["Status"]
            if (-not $status.Installed) {
                $statusCell.Style.ForeColor = [System.Drawing.ColorTranslator]::FromHtml("#484f58")
            } elseif ($status.UpdateAvailable) {
                $statusCell.Style.ForeColor = [System.Drawing.ColorTranslator]::FromHtml($COLOR_ORANGE)
            } else {
                $statusCell.Style.ForeColor = [System.Drawing.ColorTranslator]::FromHtml($COLOR_GREEN)
            }

            # Store tool ID in tag for later retrieval
            $row.Tag = $tool.id
        }

        $totalSizeText = if ($totalSizeMB -gt 1024) {
            "$([Math]::Round($totalSizeMB / 1024, 2)) GB"
        } else {
            "$([Math]::Round($totalSizeMB, 1)) MB"
        }
        $lblDiskUsage.Text = "Total disk usage: $totalSizeText"
    }

    # ── Event Handlers ──
    $btnRefresh.Add_Click({
        # Re-scan Tools folder for newly added EXEs
        $discovered = Find-UnregisteredTools
        if ($discovered -and $discovered.Count -gt 0) {
            foreach ($newTool in $discovered) {
                [void]$script:Manifest.Add($newTool)
            }
            Save-Manifest $script:Manifest
            $txtLog.AppendText("Found $($discovered.Count) new tool(s) in Tools folder.`r`n")
        }
        & $populateGrid
        $txtLog.AppendText("Tool list refreshed.`r`n")
    })

    $txtSearch.Add_TextChanged({ & $populateGrid })
    $cmbCategory.Add_SelectedIndexChanged({ & $populateGrid })

    $btnInstall.Add_Click({
        if ($dgv.SelectedRows.Count -eq 0) {
            $txtLog.AppendText("[WARN] Select a tool first.`r`n")
            return
        }
        $selectedRow = $dgv.SelectedRows[0]
        $toolId = $selectedRow.Tag
        $tool = $script:Manifest | Where-Object { $_.id -eq $toolId }
        if ($tool) {
            $result = Install-Tool -Tool $tool -Log $txtLog -Progress $progressBar
            [System.Windows.Forms.Application]::DoEvents()
            & $populateGrid
        }
    })

    $btnLaunch.Add_Click({
        if ($dgv.SelectedRows.Count -eq 0) {
            $txtLog.AppendText("[WARN] Select a tool first.`r`n")
            return
        }
        $selectedRow = $dgv.SelectedRows[0]
        $toolId = $selectedRow.Tag
        $tool = $script:Manifest | Where-Object { $_.id -eq $toolId }
        if ($tool) {
            Launch-Tool -Tool $tool -Log $txtLog
        }
    })

    $btnInstallAll.Add_Click({
        $confirm = [System.Windows.Forms.MessageBox]::Show(
            "This will download and install all $($script:Manifest.Count) tools.`nThis may take a while depending on your internet connection.`n`nContinue?",
            "Install All Tools",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Question
        )
        if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) { return }

        $btnInstallAll.Enabled = $false
        $installed = 0
        $failed = 0

        foreach ($tool in $script:Manifest) {
            $status = Get-ToolStatus $tool
            if (-not $status.Installed) {
                $txtLog.AppendText("`r`n--- Installing $($tool.name) ---`r`n")
                [System.Windows.Forms.Application]::DoEvents()
                $result = Install-Tool -Tool $tool -Log $txtLog -Progress $progressBar
                if ($result) { $installed++ } else { $failed++ }
                [System.Windows.Forms.Application]::DoEvents()
            }
        }

        $txtLog.AppendText("`r`nInstall All complete: $installed installed, $failed failed`r`n")
        $progressBar.Value = 0
        & $populateGrid
        $btnInstallAll.Enabled = $true
    })

    $btnUpdateAll.Add_Click({
        $btnUpdateAll.Enabled = $false
        $updated = 0
        $failed = 0

        foreach ($tool in $script:Manifest) {
            $status = Get-ToolStatus $tool
            if ($status.Installed -and $status.UpdateAvailable) {
                $txtLog.AppendText("`r`n--- Updating $($tool.name) ---`r`n")
                [System.Windows.Forms.Application]::DoEvents()
                $result = Install-Tool -Tool $tool -Log $txtLog -Progress $progressBar
                if ($result) { $updated++ } else { $failed++ }
                [System.Windows.Forms.Application]::DoEvents()
            }
        }

        if ($updated -eq 0 -and $failed -eq 0) {
            $txtLog.AppendText("All tools are up to date.`r`n")
        } else {
            $txtLog.AppendText("`r`nUpdate All complete: $updated updated, $failed failed`r`n")
        }
        $progressBar.Value = 0
        & $populateGrid
        $btnUpdateAll.Enabled = $true
    })

    $btnCheckUpdates.Add_Click({
        $txtLog.AppendText("`r`n=== Checking for updates ===`r`n")
        $updatesAvailable = 0

        foreach ($tool in $script:Manifest) {
            $status = Get-ToolStatus $tool
            if ($status.Installed) {
                if ($status.UpdateAvailable) {
                    $updatesAvailable++
                    $txtLog.AppendText("  [UPDATE] $($tool.name): $($status.LocalVersion) -> $($tool.version)`r`n")
                } else {
                    $txtLog.AppendText("  [OK]     $($tool.name): $($status.LocalVersion)`r`n")
                }
            }
        }

        if ($updatesAvailable -gt 0) {
            $txtLog.AppendText("`r`n$updatesAvailable update(s) available. Click 'Update All' to update.`r`n")
        } else {
            $txtLog.AppendText("`r`nAll installed tools are up to date.`r`n")
        }
        & $populateGrid
    })

    $btnOpenFolder.Add_Click({
        if (Test-Path $ToolsDir) {
            Start-Process "explorer.exe" -ArgumentList $ToolsDir
        } else {
            $txtLog.AppendText("[WARN] Tools directory does not exist yet.`r`n")
        }
    })

    # Double-click to launch
    $dgv.Add_CellDoubleClick({
        param($sender, $e)
        if ($e.RowIndex -lt 0) { return }
        $toolId = $dgv.Rows[$e.RowIndex].Tag
        $tool = $script:Manifest | Where-Object { $_.id -eq $toolId }
        if ($tool) {
            $status = Get-ToolStatus $tool
            if ($status.Installed) {
                Launch-Tool -Tool $tool -Log $txtLog
            } else {
                $txtLog.AppendText("$($tool.name) is not installed. Use the Install button.`r`n")
            }
        }
    })

    # Initial population
    & $populateGrid
    $txtLog.AppendText("PC Plus Computing 360 - Portable Tools Manager v$SCRIPT_VERSION`r`n")
    $txtLog.AppendText("Tools directory: $ToolsDir`r`n")
    $txtLog.AppendText("Manifest: $ManifestFile`r`n")
    $txtLog.AppendText("$($script:Manifest.Count) tools in catalog.`r`n`r`n")
    $txtLog.AppendText("Select a tool and click Install, Launch, or double-click to launch.`r`n")
    $txtLog.AppendText("Click 'Install All' for first-time USB toolkit setup.`r`n")
    $txtLog.AppendText("`r`nNOTE: Update tools-manifest.json with correct download URLs before using Install.`r`n")

    # Show form
    $form.Add_Shown({ $form.Activate() })
    [void]$form.ShowDialog()
    $form.Dispose()
}

# ═══════════════════════════════════════════════════════════════════════════════
# ENTRY POINT
# ═══════════════════════════════════════════════════════════════════════════════

Show-MainForm

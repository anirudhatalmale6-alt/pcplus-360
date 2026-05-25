<#
.SYNOPSIS
    PC Plus Computing - Browser Security & Extension Risk Audit
.DESCRIPTION
    Standalone PowerShell script that performs a comprehensive audit of all installed
    browsers, their extensions, hijack indicators, saved password risk, update status,
    tracking cookies, and suspicious downloads. Generates a branded HTML report with
    per-browser and overall security scores.
    Runs from a USB drive with no installation required.
.NOTES
    Company:  PC Plus Computing
    Website:  pcpluscomputing.com
    Phone:    604-760-1662 | 236-500-2700
    Version:  1.0.0
    Requires: PowerShell 5.1+, Windows 10/11, Administrator privileges
.EXAMPLE
    PowerShell.exe -ExecutionPolicy Bypass -File .\PCPlus-BrowserRiskAudit.ps1
.EXAMPLE
    PowerShell.exe -ExecutionPolicy Bypass -File .\PCPlus-BrowserRiskAudit.ps1 -CustomerName "John Smith" -TechnicianName "Paul"
#>

#Requires -Version 5.1

param(
    [string]$CustomerName   = "Customer",
    [string]$TechnicianName = "PC Plus Technician",
    [switch]$OpenReport
)

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
    Write-Host "`n[!] This script requires Administrator privileges." -ForegroundColor Red
    Write-Host "    Attempting to relaunch elevated...`n" -ForegroundColor Yellow
    try {
        $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$($MyInvocation.MyCommand.Definition)`""
        if ($CustomerName -ne "Customer")   { $arguments += " -CustomerName `"$CustomerName`"" }
        if ($TechnicianName -ne "PC Plus Technician") { $arguments += " -TechnicianName `"$TechnicianName`"" }
        Start-Process powershell.exe -ArgumentList $arguments -Verb RunAs
    } catch {
        Write-Host "[X] Failed to elevate. Right-click the script and select 'Run as Administrator'." -ForegroundColor Red
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
$COMPANY_PHONE1  = "604-760-1662"
$COMPANY_PHONE2  = "236-500-2700"
$COMPANY_WEBSITE = "pcpluscomputing.com"
$SCRIPT_VERSION  = "1.0.0"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
if ([string]::IsNullOrEmpty($ScriptDir)) { $ScriptDir = Get-Location }
$ReportDir  = Join-Path $ScriptDir "reports"
$TimeStamp  = Get-Date -Format "yyyyMMdd-HHmmss"
$ComputerSafe = $env:COMPUTERNAME -replace '[^\w\-]', '_'

if (-not (Test-Path $ReportDir)) { New-Item -ItemType Directory -Path $ReportDir -Force | Out-Null }

# ─────────────────────────────────────────────────────────────────────────────
# KNOWN MALICIOUS / SUSPICIOUS EXTENSION IDS
# ─────────────────────────────────────────────────────────────────────────────
$KnownBadExtensions = @{
    # Crypto miners
    "hnfmiofpblonoagfjjgaeipalmbnjaph" = "CryptoTab / Crypto Miner"
    "jiofmdififlbbopfbeeclkfmhmpfkdgp" = "CoinHive Miner Extension"
    "kbfnbcaeplbcioakkpcpgfkobkghlhen" = "Grammarly Impersonator (Crypto Miner)"
    "oaikpkmjlhaapcgflnpfanmfadfgkdmj" = "FacexWorm (Crypto Miner/Stealer)"
    # Adware / Spyware
    "gighmmpiobklfepjocnamgkkbiglidom" = "Suspicious AdBlock Clone (Adware)"
    "lmjnegcaeklhafolokijcfjliaokphfk" = "DataSpii / Hover Zoom Spyware"
    "noaborknpfcmbajhgaflcpfddcldjfnp" = "Particle (Browsing Data Harvester)"
    "fjnbnpbmkenffdnngjfgmeleoegfcffe" = "Stylish (User Data Collector)"
    "bpoadfkcbjbfhfodiogcnhhhpibjhbnh" = "Web of Trust (Data Harvester)"
    "cgbcahbpdhpcegmbfconpfhkjoiazpng" = "SearchManager Hijacker"
    "pkehgijcmpdhfbdbbnkijodmdjhbjlgp" = "SweetPage / Sweet-Page Hijacker"
    "eofcbnmajmjmplflapaojjnihcjkigck" = "Coupon Companion (Adware Injector)"
    "niloccemoadcdkdjlinkgdfekeahmflj" = "WebNavigator Browser Hijacker"
    "mhkaehfgehbkaghfpbmfjoahjmebkpjn" = "Browser Guardian Adware"
    # Keyloggers / Stealers
    "ohgndoajamamhlkapjefklmfbnmkagdb" = "CopyFish OCR Hijacked (Keylogger)"
    "caljgklbbfbcjjanaijlacgncafpegll" = "Web Developer Hijacked (Credential Stealer)"
    "apjmmoplbclmiabodhfnmgmfopkgigck" = "SafeBrowse (Data Exfiltrator)"
    # Fake utilities
    "hemlmgggokggmncimchkllhcjcaimcmo" = "Fake PDF Converter (Malware Dropper)"
    "kgjfgplpablkjnlkjmjdecgdpfankdle" = "Zoom Meeting Impersonator"
    "dhdgffkkebhmkfjojejmpbldmpobfkfo" = "TamperMonkey (Verify Source - Commonly Cloned)"
    "fgddmllnllkalaagkghckoinaemmogpe" = "Fake ChatGPT Extension (Stealer)"
}

# Suspicious permission patterns (Chrome/Edge manifest.json)
$SuspiciousPermissions = @(
    "webRequestBlocking"
    "nativeMessaging"
    "debugger"
    "clipboardRead"
    "management"
    "proxy"
    "desktopCapture"
    "pageCapture"
    "tabCapture"
    "cookies"
)

# Suspicious file types in Downloads
$SuspiciousFileTypes = @("*.exe","*.bat","*.cmd","*.scr","*.vbs","*.vbe","*.js","*.jse",
                         "*.wsf","*.wsh","*.ps1","*.pif","*.msi","*.com","*.hta","*.cpl",
                         "*.reg","*.inf","*.lnk")

# ─────────────────────────────────────────────────────────────────────────────
# CONSOLE HELPERS
# ─────────────────────────────────────────────────────────────────────────────
function Write-Banner {
    $width = 72
    $line  = [string]::new([char]0x2550, $width)
    Write-Host ""
    Write-Host "  $line" -ForegroundColor Cyan
    Write-Host "    $COMPANY_NAME - Browser Security & Extension Risk Audit" -ForegroundColor Cyan
    Write-Host "    Phone: $COMPANY_PHONE1 | $COMPANY_PHONE2" -ForegroundColor DarkCyan
    Write-Host "    Web:   $COMPANY_WEBSITE" -ForegroundColor DarkCyan
    Write-Host "  $line" -ForegroundColor Cyan
    Write-Host "    Computer:   $env:COMPUTERNAME" -ForegroundColor White
    Write-Host "    Customer:   $CustomerName" -ForegroundColor White
    Write-Host "    Technician: $TechnicianName" -ForegroundColor White
    Write-Host "    Date:       $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor White
    Write-Host "    Version:    $SCRIPT_VERSION" -ForegroundColor White
    Write-Host "  $line" -ForegroundColor Cyan
    Write-Host ""
}

function Write-Section ([string]$Title) {
    Write-Host ""
    Write-Host ("  [{0}]" -f $Title.ToUpper()) -ForegroundColor Yellow
    Write-Host ("  " + ("-" * 60)) -ForegroundColor DarkGray
}

function Write-Info ([string]$Label, [string]$Value) {
    Write-Host "    $Label" -ForegroundColor Gray -NoNewline
    Write-Host " $Value" -ForegroundColor White
}

function Write-Good ([string]$Msg)    { Write-Host "    [OK]   $Msg" -ForegroundColor Green }
function Write-Warn ([string]$Msg)    { Write-Host "    [!!]   $Msg" -ForegroundColor Yellow }
function Write-Bad  ([string]$Msg)    { Write-Host "    [XX]   $Msg" -ForegroundColor Red }
function Write-Note ([string]$Msg)    { Write-Host "    [--]   $Msg" -ForegroundColor DarkGray }

function Get-ScoreColor ([int]$Score) {
    if ($Score -ge 80) { return "Green" }
    if ($Score -ge 60) { return "Yellow" }
    return "Red"
}

# ─────────────────────────────────────────────────────────────────────────────
# REPORT DATA ACCUMULATOR
# ─────────────────────────────────────────────────────────────────────────────
$global:ReportSections = New-Object System.Collections.ArrayList
$global:Recommendations = New-Object System.Collections.ArrayList
$global:BrowserScores = @{}

function Add-ReportSection ([string]$Title, [string]$Html) {
    [void]$global:ReportSections.Add(@{ Title = $Title; Html = $Html })
}

function Add-Recommendation ([string]$Severity, [string]$Text) {
    [void]$global:Recommendations.Add(@{ Severity = $Severity; Text = $Text })
}

# ─────────────────────────────────────────────────────────────────────────────
# 1. BROWSER DETECTION
# ─────────────────────────────────────────────────────────────────────────────
function Get-InstalledBrowsers {
    Write-Section "Installed Browsers"
    $browsers = New-Object System.Collections.ArrayList

    $browserPaths = @(
        @{ Name = "Google Chrome";      Exe = "$env:ProgramFiles\Google\Chrome\Application\chrome.exe";       Alt = "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe" }
        @{ Name = "Microsoft Edge";     Exe = "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe";       Alt = "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe" }
        @{ Name = "Mozilla Firefox";    Exe = "$env:ProgramFiles\Mozilla Firefox\firefox.exe";                  Alt = "${env:ProgramFiles(x86)}\Mozilla Firefox\firefox.exe" }
        @{ Name = "Brave Browser";      Exe = "$env:ProgramFiles\BraveSoftware\Brave-Browser\Application\brave.exe"; Alt = "${env:ProgramFiles(x86)}\BraveSoftware\Brave-Browser\Application\brave.exe" }
        @{ Name = "Opera";              Exe = "$env:LocalAppData\Programs\Opera\launcher.exe";                  Alt = "$env:ProgramFiles\Opera\launcher.exe" }
        @{ Name = "Opera GX";           Exe = "$env:LocalAppData\Programs\Opera GX\launcher.exe";              Alt = "$env:ProgramFiles\Opera GX\launcher.exe" }
        @{ Name = "Vivaldi";            Exe = "$env:LocalAppData\Vivaldi\Application\vivaldi.exe";             Alt = "$env:ProgramFiles\Vivaldi\Application\vivaldi.exe" }
    )

    $htmlRows = ""
    foreach ($b in $browserPaths) {
        $path = $null
        if (Test-Path $b.Exe)  { $path = $b.Exe }
        elseif (Test-Path $b.Alt) { $path = $b.Alt }

        if ($path) {
            $ver = "Unknown"
            try { $ver = (Get-Item $path).VersionInfo.ProductVersion } catch {}
            $info = @{ Name = $b.Name; Path = $path; Version = $ver }
            [void]$browsers.Add($info)
            Write-Good "$($b.Name) v$ver"
            $htmlRows += "<tr><td>$($b.Name)</td><td>$ver</td><td style='color:green;'>Installed</td></tr>"
        }
    }

    if ($browsers.Count -eq 0) {
        Write-Warn "No supported browsers detected."
        $htmlRows = "<tr><td colspan='3'>No supported browsers detected</td></tr>"
    }

    $html = "<table><tr><th>Browser</th><th>Version</th><th>Status</th></tr>$htmlRows</table>"
    Add-ReportSection "Installed Browsers" $html

    return $browsers
}

# ─────────────────────────────────────────────────────────────────────────────
# 2 & 3. CHROMIUM EXTENSION AUDIT (Chrome, Edge, Brave, Vivaldi, Opera)
# ─────────────────────────────────────────────────────────────────────────────
function Get-ChromiumExtensions {
    param(
        [string]$BrowserName,
        [string]$UserDataPath
    )

    Write-Section "$BrowserName Extensions"
    $results = New-Object System.Collections.ArrayList
    $score = 100

    $extDir = Join-Path $UserDataPath "Default\Extensions"
    if (-not (Test-Path $extDir)) {
        # Check other profile folders
        $profiles = @("Default", "Profile 1", "Profile 2", "Profile 3")
        $found = $false
        foreach ($p in $profiles) {
            $testPath = Join-Path $UserDataPath "$p\Extensions"
            if (Test-Path $testPath) { $extDir = $testPath; $found = $true; break }
        }
        if (-not $found) {
            Write-Note "No extension directory found for $BrowserName."
            return @{ Extensions = $results; Score = $score }
        }
    }

    $extFolders = @()
    try { $extFolders = Get-ChildItem -Path $extDir -Directory -ErrorAction SilentlyContinue } catch {}

    $flaggedCount = 0
    $excessivePermCount = 0

    foreach ($extFolder in $extFolders) {
        $extId = $extFolder.Name
        # Find the latest version subfolder
        $versionFolders = @()
        try { $versionFolders = Get-ChildItem -Path $extFolder.FullName -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending } catch {}
        if (@($versionFolders).Count -eq 0) { continue }

        $manifestPath = Join-Path $versionFolders[0].FullName "manifest.json"
        if (-not (Test-Path $manifestPath)) { continue }

        $extName    = $extId
        $extVersion = "Unknown"
        $permissions = @()
        $isMalicious = $false
        $malwareLabel = ""

        try {
            $manifest = Get-Content -Path $manifestPath -Raw -ErrorAction Stop | ConvertFrom-Json
            if ($manifest.name)    { $extName    = $manifest.name }
            if ($manifest.version) { $extVersion = $manifest.version }

            # Collect permissions
            if ($manifest.permissions) {
                $permissions += @($manifest.permissions)
            }
            if ($manifest.optional_permissions) {
                $permissions += @($manifest.optional_permissions)
            }
            # Manifest V3 host_permissions
            if ($manifest.host_permissions) {
                $permissions += @($manifest.host_permissions)
            }
        } catch {
            # Ignore parse errors
        }

        # Skip internal/system extension name tokens (e.g. __MSG_...)
        if ($extName -match '^__MSG_') { $extName = "$extId (localized)" }

        # Check against known bad list
        if ($KnownBadExtensions.ContainsKey($extId)) {
            $isMalicious = $true
            $malwareLabel = $KnownBadExtensions[$extId]
            $score -= 15
            $flaggedCount++
            Write-Bad "MALICIOUS: $extName - $malwareLabel [$extId]"
            Add-Recommendation "CRITICAL" "Remove malicious $BrowserName extension: $extName ($malwareLabel) [ID: $extId]"
        }

        # Check for suspicious permissions
        $suspPerms = @()
        foreach ($p in $permissions) {
            if ($p -is [string]) {
                foreach ($sp in $SuspiciousPermissions) {
                    if ($p -eq $sp) { $suspPerms += $p }
                }
                # Flag <all_urls> or broad host access
                if ($p -eq "<all_urls>" -or $p -match '^\*://\*/') { $suspPerms += $p }
            }
        }

        $permStatus = "OK"
        if ($suspPerms.Count -ge 3) {
            $permStatus = "EXCESSIVE"
            $excessivePermCount++
            $score -= 3
            if (-not $isMalicious) {
                Write-Warn "Excessive permissions: $extName ($($suspPerms.Count) risky perms)"
            }
        }

        [void]$results.Add(@{
            Id          = $extId
            Name        = $extName
            Version     = $extVersion
            Permissions = ($suspPerms -join ", ")
            PermStatus  = $permStatus
            IsMalicious = $isMalicious
            MalwareLabel = $malwareLabel
        })
    }

    if ($results.Count -eq 0) {
        Write-Good "No extensions installed or extension folder is empty."
    } else {
        $cleanCount = $results.Count - $flaggedCount
        Write-Info "Total extensions:" "$($results.Count)"
        if ($flaggedCount -gt 0) { Write-Bad "$flaggedCount flagged as malicious/suspicious" }
        if ($excessivePermCount -gt 0) { Write-Warn "$excessivePermCount with excessive permissions" }
        if ($cleanCount -gt 0) { Write-Good "$cleanCount appear clean" }
    }

    # Build HTML
    $htmlRows = ""
    foreach ($r in $results) {
        $rowColor = ""
        if ($r.IsMalicious) { $rowColor = " style='background:#ffe0e0;'" }
        elseif ($r.PermStatus -eq "EXCESSIVE") { $rowColor = " style='background:#fff3cd;'" }

        $statusCell = if ($r.IsMalicious) { "<span style='color:red;font-weight:bold;'>MALICIOUS: $($r.MalwareLabel)</span>" }
                      elseif ($r.PermStatus -eq "EXCESSIVE") { "<span style='color:#cc7700;'>Excessive Permissions</span>" }
                      else { "<span style='color:green;'>OK</span>" }

        $htmlRows += "<tr$rowColor><td>$($r.Name)</td><td style='font-family:monospace;font-size:11px;'>$($r.Id)</td><td>$($r.Version)</td><td>$($r.Permissions)</td><td>$statusCell</td></tr>"
    }

    $html = "<table><tr><th>Extension</th><th>ID</th><th>Version</th><th>Risky Permissions</th><th>Status</th></tr>$htmlRows</table>"
    Add-ReportSection "$BrowserName Extensions ($($results.Count) found)" $html

    if ($score -lt 0) { $score = 0 }
    return @{ Extensions = $results; Score = $score }
}

# ─────────────────────────────────────────────────────────────────────────────
# 4. FIREFOX ADD-ONS
# ─────────────────────────────────────────────────────────────────────────────
function Get-FirefoxAddons {
    Write-Section "Firefox Add-ons"
    $results = New-Object System.Collections.ArrayList
    $score = 100

    $profilesDir = "$env:APPDATA\Mozilla\Firefox\Profiles"
    if (-not (Test-Path $profilesDir)) {
        Write-Note "Firefox profiles directory not found."
        return @{ Extensions = $results; Score = $score }
    }

    $profiles = @()
    try { $profiles = Get-ChildItem -Path $profilesDir -Directory -ErrorAction SilentlyContinue } catch {}

    foreach ($profile in $profiles) {
        $extJsonPath = Join-Path $profile.FullName "extensions.json"
        $addonsJsonPath = Join-Path $profile.FullName "addons.json"

        $addonList = @()

        # Try extensions.json first
        if (Test-Path $extJsonPath) {
            try {
                $extData = Get-Content -Path $extJsonPath -Raw -ErrorAction Stop | ConvertFrom-Json
                if ($extData.addons) { $addonList = $extData.addons }
            } catch {}
        }

        # Fallback to addons.json
        if (@($addonList).Count -eq 0 -and (Test-Path $addonsJsonPath)) {
            try {
                $addonsData = Get-Content -Path $addonsJsonPath -Raw -ErrorAction Stop | ConvertFrom-Json
                if ($addonsData.addons) { $addonList = $addonsData.addons }
            } catch {}
        }

        foreach ($addon in $addonList) {
            # Skip system/built-in addons
            if ($addon.location -and $addon.location -ne "app-profile") { continue }
            if ($addon.type -and $addon.type -ne "extension") { continue }

            $addonName = if ($addon.defaultLocale -and $addon.defaultLocale.name) { $addon.defaultLocale.name }
                         elseif ($addon.name) { $addon.name }
                         else { $addon.id }
            $addonId      = if ($addon.id) { $addon.id } else { "unknown" }
            $addonVersion = if ($addon.version) { $addon.version } else { "Unknown" }
            $isActive     = if ($null -ne $addon.active) { $addon.active } else { $true }

            # Check if from AMO
            $fromAMO = $false
            if ($addon.sourceURI -and $addon.sourceURI -match "addons\.mozilla\.org") { $fromAMO = $true }
            if ($addon.installTelemetryInfo -and $addon.installTelemetryInfo.source -eq "amo") { $fromAMO = $true }
            # Default: most legitimate addons are from AMO
            if (-not $addon.sourceURI -and -not $addon.installTelemetryInfo) { $fromAMO = $true }

            $status = "OK"
            if (-not $fromAMO -and $addonId -notmatch '@mozilla\.org$') {
                $status = "Non-AMO Source"
                $score -= 5
                Write-Warn "Non-AMO addon: $addonName [$addonId]"
                Add-Recommendation "MEDIUM" "Firefox addon '$addonName' may not be from Mozilla AMO. Verify its source."
            }

            if (-not $isActive) { $status = "Disabled" }

            [void]$results.Add(@{
                Name    = $addonName
                Id      = $addonId
                Version = $addonVersion
                Active  = $isActive
                FromAMO = $fromAMO
                Status  = $status
                Profile = $profile.Name
            })
        }
    }

    if ($results.Count -eq 0) {
        Write-Good "No user-installed Firefox add-ons found."
    } else {
        Write-Info "Total add-ons:" "$($results.Count)"
    }

    # Build HTML
    $htmlRows = ""
    foreach ($r in $results) {
        $rowColor = if ($r.Status -eq "Non-AMO Source") { " style='background:#fff3cd;'" } else { "" }
        $statusHtml = if ($r.Status -eq "OK") { "<span style='color:green;'>OK</span>" }
                      elseif ($r.Status -eq "Non-AMO Source") { "<span style='color:#cc7700;'>Non-AMO</span>" }
                      else { "<span style='color:gray;'>$($r.Status)</span>" }
        $htmlRows += "<tr$rowColor><td>$($r.Name)</td><td style='font-family:monospace;font-size:11px;'>$($r.Id)</td><td>$($r.Version)</td><td>$($r.Profile)</td><td>$statusHtml</td></tr>"
    }

    $html = "<table><tr><th>Add-on</th><th>ID</th><th>Version</th><th>Profile</th><th>Status</th></tr>$htmlRows</table>"
    Add-ReportSection "Firefox Add-ons ($($results.Count) found)" $html

    if ($score -lt 0) { $score = 0 }
    return @{ Extensions = $results; Score = $score }
}

# ─────────────────────────────────────────────────────────────────────────────
# 5. BROWSER HIJACK INDICATORS
# ─────────────────────────────────────────────────────────────────────────────
function Test-BrowserHijackIndicators {
    Write-Section "Browser Hijack Indicators"
    $findings = New-Object System.Collections.ArrayList
    $score = 100

    # --- Default Search Engine (Registry) ---
    $searchRegPaths = @(
        "HKCU:\Software\Microsoft\Internet Explorer\SearchScopes"
        "HKLM:\SOFTWARE\Microsoft\Internet Explorer\SearchScopes"
    )
    foreach ($regPath in $searchRegPaths) {
        if (Test-Path $regPath) {
            $defaultScope = $null
            try { $defaultScope = Get-ItemProperty -Path $regPath -Name "DefaultScope" -ErrorAction SilentlyContinue } catch {}
            if ($defaultScope -and $defaultScope.DefaultScope) {
                $scopePath = Join-Path $regPath $defaultScope.DefaultScope
                if (Test-Path $scopePath) {
                    try {
                        $scopeProps = Get-ItemProperty -Path $scopePath -ErrorAction SilentlyContinue
                        $searchUrl = $scopeProps.URL
                        if ($searchUrl -and $searchUrl -notmatch '(bing\.com|google\.com|duckduckgo\.com|yahoo\.com|ecosia\.org)') {
                            $score -= 15
                            Write-Bad "Suspicious default search engine: $searchUrl"
                            [void]$findings.Add(@{ Check = "Default Search"; Detail = $searchUrl; Status = "SUSPICIOUS" })
                            Add-Recommendation "HIGH" "Default search engine is set to a non-standard URL: $searchUrl - Possible browser hijack."
                        } else {
                            Write-Good "Default search engine appears normal."
                            [void]$findings.Add(@{ Check = "Default Search"; Detail = $searchUrl; Status = "OK" })
                        }
                    } catch {}
                }
            }
        }
    }

    # --- IE/Edge Start Page ---
    $startPages = @(
        @{ Path = "HKCU:\Software\Microsoft\Internet Explorer\Main"; Key = "Start Page" }
        @{ Path = "HKLM:\SOFTWARE\Microsoft\Internet Explorer\Main"; Key = "Start Page" }
    )
    foreach ($sp in $startPages) {
        if (Test-Path $sp.Path) {
            try {
                $val = (Get-ItemProperty -Path $sp.Path -Name $sp.Key -ErrorAction SilentlyContinue).($sp.Key)
                if ($val -and $val -notmatch '(msn\.com|bing\.com|microsoft\.com|google\.com|about:blank|about:home|about:start)') {
                    $score -= 10
                    Write-Warn "Modified start page: $val"
                    [void]$findings.Add(@{ Check = "IE Start Page"; Detail = $val; Status = "MODIFIED" })
                    Add-Recommendation "MEDIUM" "Browser start page set to non-standard URL: $val"
                }
            } catch {}
        }
    }

    # --- Browser Helper Objects (BHOs) ---
    $bhoPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Browser Helper Objects"
    if (Test-Path $bhoPath) {
        $bhos = @()
        try { $bhos = Get-ChildItem -Path $bhoPath -ErrorAction SilentlyContinue } catch {}
        if ($bhos.Count -gt 0) {
            Write-Info "Browser Helper Objects found:" "$($bhos.Count)"
            foreach ($bho in $bhos) {
                $clsid = $bho.PSChildName
                $bhoName = "Unknown"
                try {
                    $clsidPath = "HKLM:\SOFTWARE\Classes\CLSID\$clsid"
                    if (Test-Path $clsidPath) {
                        $bhoName = (Get-ItemProperty -Path $clsidPath -ErrorAction SilentlyContinue).'(default)'
                        if (-not $bhoName) { $bhoName = $clsid }
                    }
                } catch {}
                Write-Warn "BHO: $bhoName [$clsid]"
                [void]$findings.Add(@{ Check = "BHO"; Detail = "$bhoName ($clsid)"; Status = "PRESENT" })
            }
            if ($bhos.Count -gt 2) {
                $score -= 10
                Add-Recommendation "MEDIUM" "$($bhos.Count) Browser Helper Objects detected. Review and remove any unknown BHOs."
            }
        } else {
            Write-Good "No Browser Helper Objects found."
        }
    }

    # --- Proxy Settings ---
    $proxyPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings"
    if (Test-Path $proxyPath) {
        try {
            $proxyProps = Get-ItemProperty -Path $proxyPath -ErrorAction SilentlyContinue
            $proxyEnabled = $proxyProps.ProxyEnable
            $proxyServer  = $proxyProps.ProxyServer
            $autoConfig   = $proxyProps.AutoConfigURL

            if ($proxyEnabled -eq 1 -and $proxyServer) {
                $score -= 15
                Write-Bad "Proxy ENABLED: $proxyServer"
                [void]$findings.Add(@{ Check = "Proxy Server"; Detail = $proxyServer; Status = "ENABLED" })
                Add-Recommendation "HIGH" "A proxy server is configured ($proxyServer). If not intentional, this may indicate malware."
            } else {
                Write-Good "No manual proxy configured."
                [void]$findings.Add(@{ Check = "Proxy Server"; Detail = "None"; Status = "OK" })
            }

            if ($autoConfig) {
                $score -= 10
                Write-Warn "Auto-config proxy URL: $autoConfig"
                [void]$findings.Add(@{ Check = "Auto-Config Proxy"; Detail = $autoConfig; Status = "SET" })
                Add-Recommendation "MEDIUM" "Proxy auto-config URL is set: $autoConfig"
            }
        } catch {}
    }

    # Build HTML
    $htmlRows = ""
    foreach ($f in $findings) {
        $statusColor = switch ($f.Status) {
            "OK"         { "green" }
            "SUSPICIOUS" { "red" }
            "MODIFIED"   { "#cc7700" }
            "ENABLED"    { "red" }
            default      { "#cc7700" }
        }
        $htmlRows += "<tr><td>$($f.Check)</td><td>$($f.Detail)</td><td style='color:$statusColor;font-weight:bold;'>$($f.Status)</td></tr>"
    }
    $html = "<table><tr><th>Check</th><th>Detail</th><th>Status</th></tr>$htmlRows</table>"
    Add-ReportSection "Browser Hijack Indicators" $html

    if ($score -lt 0) { $score = 0 }
    return $score
}

# ─────────────────────────────────────────────────────────────────────────────
# 6. SAVED PASSWORDS RISK
# ─────────────────────────────────────────────────────────────────────────────
function Test-SavedPasswordsRisk {
    Write-Section "Saved Passwords Risk Assessment"
    $results = New-Object System.Collections.ArrayList
    $score = 100

    # Chrome Login Data
    $chromeLogin = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Login Data"
    $edgeLogin   = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Login Data"
    $braveLogin  = "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data\Default\Login Data"

    $loginDbs = @(
        @{ Browser = "Chrome"; Path = $chromeLogin }
        @{ Browser = "Edge";   Path = $edgeLogin }
        @{ Browser = "Brave";  Path = $braveLogin }
    )

    foreach ($db in $loginDbs) {
        if (Test-Path $db.Path) {
            $fileSize = (Get-Item $db.Path).Length
            # A Login Data file > 40KB likely has saved passwords
            $hasPasswords = $fileSize -gt 40960
            if ($hasPasswords) {
                $estimatedCount = [math]::Round(($fileSize - 40960) / 200)  # rough estimate
                if ($estimatedCount -lt 1) { $estimatedCount = 1 }
                $score -= 10
                Write-Warn "$($db.Browser): Login Data file is $([math]::Round($fileSize/1024))KB - likely contains saved passwords (est. ~$estimatedCount)"
                [void]$results.Add(@{ Browser = $db.Browser; Status = "PASSWORDS_LIKELY"; Estimate = $estimatedCount; FileSize = $fileSize })
                Add-Recommendation "MEDIUM" "$($db.Browser) likely has saved passwords. Consider using a dedicated password manager instead."
            } else {
                Write-Good "$($db.Browser): Login Data file is small - few or no saved passwords."
                [void]$results.Add(@{ Browser = $db.Browser; Status = "MINIMAL"; Estimate = 0; FileSize = $fileSize })
            }
        }
    }

    # Firefox logins.json
    $ffProfileDir = "$env:APPDATA\Mozilla\Firefox\Profiles"
    if (Test-Path $ffProfileDir) {
        $ffProfiles = @()
        try { $ffProfiles = Get-ChildItem -Path $ffProfileDir -Directory -ErrorAction SilentlyContinue } catch {}
        foreach ($prof in $ffProfiles) {
            $loginsPath = Join-Path $prof.FullName "logins.json"
            if (Test-Path $loginsPath) {
                try {
                    $loginsData = Get-Content -Path $loginsPath -Raw -ErrorAction Stop | ConvertFrom-Json
                    $count = 0
                    if ($loginsData.logins) { $count = $loginsData.logins.Count }
                    if ($count -gt 0) {
                        $score -= 10
                        Write-Warn "Firefox ($($prof.Name)): $count saved login(s) found"
                        [void]$results.Add(@{ Browser = "Firefox ($($prof.Name))"; Status = "HAS_PASSWORDS"; Estimate = $count; FileSize = 0 })
                        Add-Recommendation "MEDIUM" "Firefox profile '$($prof.Name)' has $count saved password(s). Consider a dedicated password manager."
                    } else {
                        Write-Good "Firefox ($($prof.Name)): No saved passwords."
                        [void]$results.Add(@{ Browser = "Firefox ($($prof.Name))"; Status = "NONE"; Estimate = 0; FileSize = 0 })
                    }
                } catch {}
            }
        }
    }

    if ($results.Count -eq 0) {
        Write-Good "No browser password stores found."
    }

    # HTML
    $htmlRows = ""
    foreach ($r in $results) {
        $statusColor = if ($r.Status -match "PASSWORD") { "#cc7700" } else { "green" }
        $htmlRows += "<tr><td>$($r.Browser)</td><td style='color:$statusColor;'>$($r.Status)</td><td>$($r.Estimate)</td></tr>"
    }
    $html = "<table><tr><th>Browser</th><th>Status</th><th>Est. Passwords</th></tr>$htmlRows</table>"
    Add-ReportSection "Saved Passwords Risk" $html

    if ($score -lt 0) { $score = 0 }
    return $score
}

# ─────────────────────────────────────────────────────────────────────────────
# 7. BROWSER UPDATE STATUS
# ─────────────────────────────────────────────────────────────────────────────
function Test-BrowserUpdateStatus {
    param([System.Collections.ArrayList]$Browsers)

    Write-Section "Browser Update Status"
    $score = 100

    # Known latest major versions (approximate - updated periodically)
    $latestMajor = @{
        "Google Chrome"   = 136
        "Microsoft Edge"  = 136
        "Mozilla Firefox" = 138
        "Brave Browser"   = 136
        "Opera"           = 118
        "Opera GX"        = 118
        "Vivaldi"         = 7
    }

    $htmlRows = ""
    foreach ($b in $Browsers) {
        $currentMajor = 0
        try {
            if ($b.Version -match '^(\d+)') { $currentMajor = [int]$Matches[1] }
        } catch {}

        $expectedMajor = 0
        if ($latestMajor.ContainsKey($b.Name)) { $expectedMajor = $latestMajor[$b.Name] }

        $status = "Unknown"
        $statusColor = "gray"
        if ($expectedMajor -gt 0 -and $currentMajor -gt 0) {
            $diff = $expectedMajor - $currentMajor
            if ($diff -le 1) {
                $status = "Up to Date"
                $statusColor = "green"
                Write-Good "$($b.Name) v$currentMajor - Up to date"
            } elseif ($diff -le 3) {
                $status = "Slightly Outdated ($diff versions behind)"
                $statusColor = "#cc7700"
                $score -= 5
                Write-Warn "$($b.Name) v$currentMajor - $diff major version(s) behind"
                Add-Recommendation "LOW" "Update $($b.Name) - currently $diff major version(s) behind."
            } else {
                $status = "OUTDATED ($diff versions behind)"
                $statusColor = "red"
                $score -= 15
                Write-Bad "$($b.Name) v$currentMajor - $diff major version(s) behind!"
                Add-Recommendation "HIGH" "URGENT: Update $($b.Name) immediately - $diff major versions behind. Security vulnerabilities likely unpatched."
            }
        } else {
            Write-Note "$($b.Name) v$($b.Version) - Cannot determine update status"
        }

        $htmlRows += "<tr><td>$($b.Name)</td><td>$($b.Version)</td><td style='color:$statusColor;font-weight:bold;'>$status</td></tr>"
    }

    $html = "<table><tr><th>Browser</th><th>Installed Version</th><th>Status</th></tr>$htmlRows</table>"
    Add-ReportSection "Browser Update Status" $html

    if ($score -lt 0) { $score = 0 }
    return $score
}

# ─────────────────────────────────────────────────────────────────────────────
# 9. COOKIE / TRACKER ANALYSIS
# ─────────────────────────────────────────────────────────────────────────────
function Test-CookieTrackerAnalysis {
    Write-Section "Cookie & Tracker Analysis"
    $results = New-Object System.Collections.ArrayList
    $score = 100

    $knownTrackers = @(
        "doubleclick.net", "googlesyndication.com", "facebook.com", "fbcdn.net",
        "analytics.google.com", "googleadservices.com", "adnxs.com", "rubiconproject.com",
        "criteo.com", "outbrain.com", "taboola.com", "scorecardresearch.com",
        "quantserve.com", "bluekai.com", "demdex.net", "krxd.net",
        "pubmatic.com", "openx.net", "casalemedia.com", "adsrvr.org"
    )

    $cookieDbs = @(
        @{ Browser = "Chrome"; Path = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Network\Cookies" }
        @{ Browser = "Edge";   Path = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Network\Cookies" }
        @{ Browser = "Brave";  Path = "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data\Default\Network\Cookies" }
    )

    # Also try legacy cookie path (pre-network-service)
    $legacyCookieDbs = @(
        @{ Browser = "Chrome"; Path = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cookies" }
        @{ Browser = "Edge";   Path = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cookies" }
    )

    $htmlRows = ""

    foreach ($cdb in ($cookieDbs + $legacyCookieDbs)) {
        if (Test-Path $cdb.Path) {
            $fileSize = (Get-Item $cdb.Path).Length
            $estimatedCookies = [math]::Round($fileSize / 300)  # rough estimate
            $trackerEstimate  = [math]::Round($estimatedCookies * 0.3)  # ~30% are typically trackers

            if ($estimatedCookies -gt 1000) {
                $score -= 10
                Write-Warn "$($cdb.Browser): ~$estimatedCookies cookies (est. ~$trackerEstimate tracking)"
                Add-Recommendation "LOW" "Consider clearing cookies in $($cdb.Browser) - high cookie count may include many trackers."
            } elseif ($estimatedCookies -gt 100) {
                Write-Info "$($cdb.Browser) cookies:" "~$estimatedCookies (est. ~$trackerEstimate tracking)"
            } else {
                Write-Good "$($cdb.Browser): Low cookie count (~$estimatedCookies)"
            }

            [void]$results.Add(@{ Browser = $cdb.Browser; Cookies = $estimatedCookies; Trackers = $trackerEstimate; FileSize = $fileSize })
            $htmlRows += "<tr><td>$($cdb.Browser)</td><td>~$estimatedCookies</td><td>~$trackerEstimate</td><td>$([math]::Round($fileSize/1024))KB</td></tr>"
            break  # Skip legacy if network path exists for same browser
        }
    }

    # Firefox cookies
    $ffProfileDir = "$env:APPDATA\Mozilla\Firefox\Profiles"
    if (Test-Path $ffProfileDir) {
        $ffProfiles = @()
        try { $ffProfiles = Get-ChildItem -Path $ffProfileDir -Directory -ErrorAction SilentlyContinue } catch {}
        foreach ($prof in $ffProfiles) {
            $cookiePath = Join-Path $prof.FullName "cookies.sqlite"
            if (Test-Path $cookiePath) {
                $fileSize = (Get-Item $cookiePath).Length
                $estimatedCookies = [math]::Round($fileSize / 350)
                $trackerEstimate  = [math]::Round($estimatedCookies * 0.3)

                if ($estimatedCookies -gt 1000) {
                    $score -= 10
                    Write-Warn "Firefox ($($prof.Name)): ~$estimatedCookies cookies"
                } else {
                    Write-Info "Firefox ($($prof.Name)) cookies:" "~$estimatedCookies"
                }

                $htmlRows += "<tr><td>Firefox ($($prof.Name))</td><td>~$estimatedCookies</td><td>~$trackerEstimate</td><td>$([math]::Round($fileSize/1024))KB</td></tr>"
            }
        }
    }

    if ($results.Count -eq 0 -and $htmlRows -eq "") {
        Write-Note "No cookie databases found to analyze."
        $htmlRows = "<tr><td colspan='4'>No cookie databases found</td></tr>"
    }

    $html = "<p><em>Note: Cookie counts are estimates based on database file size. Tracking cookie estimates assume ~30% of cookies are from known ad/tracking networks.</em></p>"
    $html += "<table><tr><th>Browser</th><th>Est. Total Cookies</th><th>Est. Tracking Cookies</th><th>DB Size</th></tr>$htmlRows</table>"
    Add-ReportSection "Cookie & Tracker Analysis" $html

    if ($score -lt 0) { $score = 0 }
    return $score
}

# ─────────────────────────────────────────────────────────────────────────────
# 10. DOWNLOADS FOLDER SCAN
# ─────────────────────────────────────────────────────────────────────────────
function Test-DownloadsFolderRisk {
    Write-Section "Downloads Folder Scan"
    $score = 100
    $suspiciousFiles = New-Object System.Collections.ArrayList

    $downloadsPath = [Environment]::GetFolderPath("UserProfile") + "\Downloads"
    if (-not (Test-Path $downloadsPath)) {
        $downloadsPath = "$env:USERPROFILE\Downloads"
    }

    if (-not (Test-Path $downloadsPath)) {
        Write-Note "Downloads folder not found."
        return $score
    }

    $allFiles = @()
    try {
        $allFiles = @(Get-ChildItem -Path $downloadsPath -File -Recurse -Depth 2 -ErrorAction SilentlyContinue)
    } catch {}

    Write-Info "Total files in Downloads:" "$($allFiles.Count)"

    foreach ($pattern in $SuspiciousFileTypes) {
        $ext = $pattern.Replace("*", "")
        $matches = @($allFiles | Where-Object { $_.Extension -eq $ext })
        if ($matches.Count -gt 0) {
            foreach ($m in $matches) {
                [void]$suspiciousFiles.Add(@{
                    FileName = $m.Name
                    Size     = "$([math]::Round($m.Length/1024))KB"
                    Modified = $m.LastWriteTime.ToString("yyyy-MM-dd HH:mm")
                    Type     = $ext
                })
            }
        }
    }

    if ($suspiciousFiles.Count -eq 0) {
        Write-Good "No suspicious file types found in Downloads."
    } else {
        $score -= [math]::Min(30, $suspiciousFiles.Count * 2)
        Write-Warn "$($suspiciousFiles.Count) potentially risky file(s) found:"
        $shown = 0
        foreach ($sf in $suspiciousFiles) {
            if ($shown -lt 15) {
                Write-Note "  $($sf.FileName) ($($sf.Size), modified $($sf.Modified))"
                $shown++
            }
        }
        if ($suspiciousFiles.Count -gt 15) {
            Write-Note "  ... and $($suspiciousFiles.Count - 15) more"
        }
        Add-Recommendation "LOW" "$($suspiciousFiles.Count) executable/script file(s) in Downloads folder. Review and remove any unknown files."
    }

    # HTML
    $htmlRows = ""
    foreach ($sf in $suspiciousFiles) {
        $htmlRows += "<tr><td>$($sf.FileName)</td><td>$($sf.Type)</td><td>$($sf.Size)</td><td>$($sf.Modified)</td></tr>"
    }
    if ($htmlRows -eq "") { $htmlRows = "<tr><td colspan='4' style='color:green;'>No suspicious files found</td></tr>" }
    $html = "<table><tr><th>File Name</th><th>Type</th><th>Size</th><th>Last Modified</th></tr>$htmlRows</table>"
    Add-ReportSection "Downloads Folder Scan ($($suspiciousFiles.Count) risky files)" $html

    if ($score -lt 0) { $score = 0 }
    return $score
}

# ─────────────────────────────────────────────────────────────────────────────
# SCORE CALCULATION
# ─────────────────────────────────────────────────────────────────────────────
function Get-OverallScore {
    param([hashtable]$Scores)

    if ($Scores.Count -eq 0) { return 50 }

    $total = 0
    $count = 0
    foreach ($key in $Scores.Keys) {
        $total += $Scores[$key]
        $count++
    }

    return [math]::Round($total / $count)
}

# ─────────────────────────────────────────────────────────────────────────────
# HTML REPORT GENERATION
# ─────────────────────────────────────────────────────────────────────────────
function Build-HtmlReport {
    param(
        [int]$OverallScore,
        [hashtable]$CategoryScores
    )

    $scoreColor = if ($OverallScore -ge 80) { "#27ae60" }
                  elseif ($OverallScore -ge 60) { "#f39c12" }
                  else { "#e74c3c" }

    $scoreLabel = if ($OverallScore -ge 90) { "EXCELLENT" }
                  elseif ($OverallScore -ge 80) { "GOOD" }
                  elseif ($OverallScore -ge 60) { "FAIR" }
                  elseif ($OverallScore -ge 40) { "POOR" }
                  else { "CRITICAL" }

    # Category score bars
    $categoryHtml = ""
    foreach ($key in $CategoryScores.Keys | Sort-Object) {
        $s = $CategoryScores[$key]
        $barColor = if ($s -ge 80) { "#27ae60" } elseif ($s -ge 60) { "#f39c12" } else { "#e74c3c" }
        $categoryHtml += @"
        <div style="margin:6px 0;">
            <div style="display:flex;align-items:center;gap:10px;">
                <span style="width:220px;font-weight:500;">$key</span>
                <div style="flex:1;background:#e9ecef;border-radius:4px;height:22px;overflow:hidden;">
                    <div style="width:${s}%;background:$barColor;height:100%;border-radius:4px;transition:width 0.3s;"></div>
                </div>
                <span style="width:50px;text-align:right;font-weight:bold;color:$barColor;">$s/100</span>
            </div>
        </div>
"@
    }

    # Recommendations
    $recsHtml = ""
    $sortedRecs = $global:Recommendations | Sort-Object { switch ($_.Severity) { "CRITICAL" { 0 } "HIGH" { 1 } "MEDIUM" { 2 } "LOW" { 3 } default { 4 } } }
    foreach ($rec in $sortedRecs) {
        $recColor = switch ($rec.Severity) { "CRITICAL" { "#e74c3c" } "HIGH" { "#e67e22" } "MEDIUM" { "#f39c12" } "LOW" { "#3498db" } default { "#95a5a6" } }
        $recsHtml += "<div style='padding:8px 12px;margin:4px 0;border-left:4px solid $recColor;background:#f8f9fa;border-radius:0 4px 4px 0;'><span style='color:$recColor;font-weight:bold;'>[$($rec.Severity)]</span> $($rec.Text)</div>"
    }
    if ($recsHtml -eq "") { $recsHtml = "<p style='color:#27ae60;font-weight:bold;'>No issues found - all checks passed.</p>" }

    # Sections
    $sectionsHtml = ""
    foreach ($sec in $global:ReportSections) {
        $sectionsHtml += @"
        <div style="margin-bottom:24px;">
            <h2 style="color:#0a1628;border-bottom:2px solid #2596be;padding-bottom:6px;margin-top:30px;">$($sec.Title)</h2>
            $($sec.Html)
        </div>
"@
    }

    $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Browser Security Audit - $env:COMPUTERNAME - $COMPANY_NAME</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; background: #f4f6f8; color: #333; line-height: 1.6; }
        .header { background: linear-gradient(135deg, #0a1628 0%, #1a3a5c 100%); color: white; padding: 30px 40px; }
        .header h1 { font-size: 24px; margin-bottom: 4px; }
        .header .subtitle { color: #7fb3d8; font-size: 14px; }
        .header .meta { display: flex; gap: 30px; margin-top: 12px; font-size: 13px; color: #a0c4e0; flex-wrap: wrap; }
        .container { max-width: 1100px; margin: 0 auto; padding: 24px 40px 40px; }
        .score-card { background: white; border-radius: 12px; box-shadow: 0 2px 12px rgba(0,0,0,0.08); padding: 30px; margin: -40px 40px 24px; position: relative; z-index: 1; display: flex; align-items: center; gap: 40px; flex-wrap: wrap; }
        .score-circle { width: 140px; height: 140px; border-radius: 50%; border: 8px solid $scoreColor; display: flex; flex-direction: column; align-items: center; justify-content: center; flex-shrink: 0; }
        .score-circle .number { font-size: 42px; font-weight: 700; color: $scoreColor; line-height: 1; }
        .score-circle .label { font-size: 11px; font-weight: 600; color: $scoreColor; text-transform: uppercase; letter-spacing: 1px; }
        .score-breakdown { flex: 1; min-width: 300px; }
        table { width: 100%; border-collapse: collapse; margin: 10px 0; font-size: 13px; }
        th { background: #0a1628; color: white; padding: 10px 12px; text-align: left; font-weight: 600; }
        td { padding: 8px 12px; border-bottom: 1px solid #e9ecef; }
        tr:hover { background: #f8f9fa; }
        .recommendations { background: white; border-radius: 8px; padding: 20px; margin-bottom: 24px; box-shadow: 0 1px 6px rgba(0,0,0,0.06); }
        .section { background: white; border-radius: 8px; padding: 20px 24px; margin-bottom: 16px; box-shadow: 0 1px 6px rgba(0,0,0,0.06); }
        .footer { text-align: center; padding: 20px; color: #888; font-size: 12px; border-top: 1px solid #e0e0e0; margin-top: 30px; }
        .footer a { color: #2596be; text-decoration: none; }
        @media print { body { background: white; } .header { page-break-after: avoid; } .score-card { box-shadow: none; border: 1px solid #ddd; margin: 10px 0; } }
    </style>
</head>
<body>
    <div class="header">
        <h1>$COMPANY_NAME</h1>
        <div class="subtitle">Browser Security & Extension Risk Audit Report</div>
        <div class="meta">
            <span>Computer: <strong>$env:COMPUTERNAME</strong></span>
            <span>Customer: <strong>$CustomerName</strong></span>
            <span>Technician: <strong>$TechnicianName</strong></span>
            <span>Date: <strong>$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</strong></span>
            <span>OS: <strong>$((Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue).Caption)</strong></span>
        </div>
    </div>

    <div class="score-card">
        <div class="score-circle">
            <div class="number">$OverallScore</div>
            <div class="label">$scoreLabel</div>
        </div>
        <div class="score-breakdown">
            <h3 style="margin-bottom:10px;color:#0a1628;">Security Score Breakdown</h3>
            $categoryHtml
        </div>
    </div>

    <div class="container">
        <div class="recommendations">
            <h2 style="color:#0a1628;margin-bottom:12px;">Recommendations ($($global:Recommendations.Count) findings)</h2>
            $recsHtml
        </div>

        <div class="section">
            $sectionsHtml
        </div>
    </div>

    <div class="footer">
        <p><strong>$COMPANY_NAME</strong> | $COMPANY_PHONE1 | $COMPANY_PHONE2 | <a href="https://$COMPANY_WEBSITE">$COMPANY_WEBSITE</a></p>
        <p>Report generated on $(Get-Date -Format 'yyyy-MM-dd') at $(Get-Date -Format 'HH:mm:ss') | Script v$SCRIPT_VERSION</p>
        <p style="margin-top:6px;color:#aaa;">This report is for informational purposes. No passwords or private data were extracted.</p>
    </div>
</body>
</html>
"@

    return $html
}

# ─────────────────────────────────────────────────────────────────────────────
# MAIN EXECUTION
# ─────────────────────────────────────────────────────────────────────────────
$startTime = Get-Date
Write-Banner

$allScores = @{}

# --- 1. Detect Browsers ---
$browsers = Get-InstalledBrowsers

# --- 2 & 3. Chromium Extensions ---
$chromiumBrowsers = @(
    @{ Name = "Chrome"; UserData = "$env:LOCALAPPDATA\Google\Chrome\User Data" }
    @{ Name = "Edge";   UserData = "$env:LOCALAPPDATA\Microsoft\Edge\User Data" }
    @{ Name = "Brave";  UserData = "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data" }
    @{ Name = "Opera";  UserData = "$env:APPDATA\Opera Software\Opera Stable" }
    @{ Name = "Vivaldi"; UserData = "$env:LOCALAPPDATA\Vivaldi\User Data" }
)

foreach ($cb in $chromiumBrowsers) {
    if (Test-Path $cb.UserData) {
        $extResult = Get-ChromiumExtensions -BrowserName $cb.Name -UserDataPath $cb.UserData
        $allScores["$($cb.Name) Extensions"] = $extResult.Score
    }
}

# --- 4. Firefox Add-ons ---
$ffResult = Get-FirefoxAddons
if ($ffResult.Extensions.Count -gt 0 -or (Test-Path "$env:APPDATA\Mozilla\Firefox\Profiles")) {
    $allScores["Firefox Add-ons"] = $ffResult.Score
}

# --- 5. Browser Hijack Indicators ---
$hijackScore = Test-BrowserHijackIndicators
$allScores["Hijack Protection"] = $hijackScore

# --- 6. Saved Passwords Risk ---
$passwordScore = Test-SavedPasswordsRisk
$allScores["Password Security"] = $passwordScore

# --- 7. Browser Update Status ---
if ($browsers.Count -gt 0) {
    $updateScore = Test-BrowserUpdateStatus -Browsers $browsers
    $allScores["Update Status"] = $updateScore
}

# --- 9. Cookie/Tracker Analysis ---
$cookieScore = Test-CookieTrackerAnalysis
$allScores["Cookie/Tracker Risk"] = $cookieScore

# --- 10. Downloads Folder Scan ---
$downloadScore = Test-DownloadsFolderRisk
$allScores["Downloads Safety"] = $downloadScore

# ─────────────────────────────────────────────────────────────────────────────
# OVERALL SCORE & REPORT
# ─────────────────────────────────────────────────────────────────────────────
$overallScore = Get-OverallScore -Scores $allScores

Write-Section "Overall Browser Security Score"
$scoreColor = Get-ScoreColor $overallScore
Write-Host ""
Write-Host "    =============================================" -ForegroundColor $scoreColor
Write-Host "       OVERALL SCORE:  $overallScore / 100" -ForegroundColor $scoreColor
Write-Host "    =============================================" -ForegroundColor $scoreColor
Write-Host ""

# Per-category scores
foreach ($key in $allScores.Keys | Sort-Object) {
    $s = $allScores[$key]
    $c = Get-ScoreColor $s
    Write-Host "    $($key.PadRight(25)) " -ForegroundColor Gray -NoNewline
    Write-Host "$s/100" -ForegroundColor $c
}

# Recommendations summary
if ($global:Recommendations.Count -gt 0) {
    Write-Section "Top Recommendations"
    $shown = 0
    foreach ($rec in ($global:Recommendations | Sort-Object { switch ($_.Severity) { "CRITICAL" { 0 } "HIGH" { 1 } "MEDIUM" { 2 } "LOW" { 3 } default { 4 } } })) {
        if ($shown -ge 10) { Write-Note "... and $($global:Recommendations.Count - 10) more in the full report."; break }
        $recColor = switch ($rec.Severity) { "CRITICAL" { "Red" } "HIGH" { "Red" } "MEDIUM" { "Yellow" } "LOW" { "Cyan" } default { "Gray" } }
        Write-Host "    [$($rec.Severity)]" -ForegroundColor $recColor -NoNewline
        Write-Host " $($rec.Text)" -ForegroundColor White
        $shown++
    }
}

# Generate HTML report
Write-Section "Generating Report"
try {
    $htmlContent = Build-HtmlReport -OverallScore $overallScore -CategoryScores $allScores
    $reportFileName = "BrowserAudit-${ComputerSafe}-${TimeStamp}.html"
    $reportPath = Join-Path $ReportDir $reportFileName
    $htmlContent | Out-File -FilePath $reportPath -Encoding UTF8 -Force
    Write-Good "HTML report saved: $reportPath"

    if ($OpenReport) {
        Start-Process $reportPath
    }
} catch {
    Write-Bad "Failed to generate HTML report: $($_.Exception.Message)"
}

$elapsed = (Get-Date) - $startTime
Write-Host ""
Write-Host "  Audit completed in $([math]::Round($elapsed.TotalSeconds, 1)) seconds." -ForegroundColor Cyan
Write-Host "  $COMPANY_NAME | $COMPANY_PHONE1 | $COMPANY_PHONE2 | $COMPANY_WEBSITE" -ForegroundColor DarkCyan
Write-Host ""

# Keep console open
Write-Host "  Press any key to exit..." -ForegroundColor DarkGray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

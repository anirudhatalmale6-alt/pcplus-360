#Requires -Version 5.1
<#
.SYNOPSIS
    PC Plus 360 - RMM Software Inventory Scanner
.DESCRIPTION
    Self-contained silent software inventory script designed for Tactical RMM deployment.
    Collects comprehensive software data, generates a branded HTML report, uploads it
    to the dashboard server, and outputs a JSON summary to stdout for RMM console display.
    Runs without admin rights for basic inventory; admin elevates license details.
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
    [string]$CompanyName  = "",
    [string]$TechName     = "PC Plus RMM",
    [switch]$SkipUpload,
    [string]$OutputDir    = "C:\PCPlus360-Reports"
)

$ErrorActionPreference = "SilentlyContinue"
$ProgressPreference    = "SilentlyContinue"
$scanStart = Get-Date

# ── HELPER ──
function Invoke-Safe { param([scriptblock]$Block, $Default = $null); try { return (& $Block) } catch { return $Default } }
if (-not (Test-Path $OutputDir)) { New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null }

# ── 1. SYSTEM INFO ──
$os = Invoke-Safe { Get-CimInstance Win32_OperatingSystem } $null
$cs = Invoke-Safe { Get-CimInstance Win32_ComputerSystem } $null

$sysInfo = @{
    ComputerName = $env:COMPUTERNAME
    OSVersion    = if ($os) { $os.Caption } else { "Unknown" }
    OSBuild      = if ($os) { $os.BuildNumber } else { "Unknown" }
    Architecture = if ($os) { $os.OSArchitecture } else { "Unknown" }
    Domain       = if ($cs) { if ($cs.PartOfDomain) { $cs.Domain } else { $cs.Workgroup } } else { "Unknown" }
    LastBoot     = Invoke-Safe { $os.LastBootUpTime.ToString("yyyy-MM-dd HH:mm:ss") } "Unknown"
    Manufacturer = if ($cs) { $cs.Manufacturer } else { "Unknown" }
    Model        = if ($cs) { $cs.Model } else { "Unknown" }
}

# ── 2. INSTALLED SOFTWARE (Registry - both 64-bit and 32-bit) ──
$regPaths = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
)

$rawSoftware = @()
foreach ($rp in $regPaths) {
    $items = Invoke-Safe { Get-ItemProperty $rp -ErrorAction SilentlyContinue } @()
    foreach ($item in $items) {
        $name = $item.DisplayName
        if ([string]::IsNullOrWhiteSpace($name)) { continue }
        $rawSoftware += @{
            Name            = $name.Trim()
            Version         = if ($item.DisplayVersion) { $item.DisplayVersion.Trim() } else { "" }
            Publisher       = if ($item.Publisher) { $item.Publisher.Trim() } else { "" }
            InstallDate     = if ($item.InstallDate) { $item.InstallDate } else { "" }
            InstallLocation = if ($item.InstallLocation) { $item.InstallLocation } else { "" }
            EstimatedSizeMB = if ($item.EstimatedSize) { [math]::Round($item.EstimatedSize / 1024, 1) } else { 0 }
            UninstallString = if ($item.UninstallString) { $item.UninstallString } else { "" }
        }
    }
}

# Deduplicate by Name+Version
$seenKeys = @{}
$software = @()
foreach ($s in ($rawSoftware | Sort-Object { $_.Name })) {
    $key = "$($s.Name)|$($s.Version)".ToLower()
    if (-not $seenKeys.ContainsKey($key)) {
        $seenKeys[$key] = $true
        $software += $s
    }
}

# ── 3. WINDOWS LICENSE INFO ──
$winLicense = Invoke-Safe {
    $prodName = (Get-CimInstance SoftwareLicensingProduct -ErrorAction Stop |
        Where-Object { $_.PartialProductKey -and $_.Name -like "Windows*" } |
        Select-Object -First 1)

    $activationStatus = switch ($prodName.LicenseStatus) {
        0 { "Unlicensed" }
        1 { "Activated" }
        2 { "Grace Period" }
        3 { "Out-of-Tolerance Grace" }
        4 { "Non-Genuine Grace" }
        5 { "Notification" }
        6 { "Extended Grace" }
        default { "Unknown" }
    }

    $productId = Invoke-Safe {
        (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -Name "ProductId" -ErrorAction Stop).ProductId
    } "Unknown"

    $oa3Key = Invoke-Safe {
        $sls = Get-CimInstance SoftwareLicensingService -ErrorAction Stop
        if ($sls.OA3xOriginalProductKey) { $sls.OA3xOriginalProductKey } else { "N/A" }
    } "N/A"

    @{
        ProductName = if ($prodName.Name) { $prodName.Name } else { $sysInfo.OSVersion }
        ProductId   = $productId
        OA3Key      = $oa3Key
        Status      = $activationStatus
        PartialKey  = if ($prodName.PartialProductKey) { $prodName.PartialProductKey } else { "N/A" }
    }
} @{ ProductName = $sysInfo.OSVersion; ProductId = "N/A"; OA3Key = "N/A"; Status = "Unknown (requires admin)"; PartialKey = "N/A" }

# ── 4. MICROSOFT OFFICE INFO ──
$officeInfo = Invoke-Safe {
    # Detect Office from registry
    $officeVersions = @(
        @{ Key = "HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration"; Type = "C2R" },
        @{ Key = "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Office\ClickToRun\Configuration"; Type = "C2R" }
    )

    $found = $null
    foreach ($ov in $officeVersions) {
        if (Test-Path $ov.Key) {
            $cfg = Get-ItemProperty $ov.Key -ErrorAction SilentlyContinue
            if ($cfg) {
                $found = @{
                    ProductName = if ($cfg.ProductReleaseIds) { $cfg.ProductReleaseIds } else { "Microsoft Office" }
                    Version     = if ($cfg.VersionToReport) { $cfg.VersionToReport } else { "" }
                    InstallPath = if ($cfg.InstallationPath) { $cfg.InstallationPath } else { "" }
                    Channel     = if ($cfg.CDNBaseUrl) {
                        if ($cfg.CDNBaseUrl -match "492350f6") { "Monthly Enterprise" }
                        elseif ($cfg.CDNBaseUrl -match "55336b82") { "Monthly" }
                        elseif ($cfg.CDNBaseUrl -match "64256afe") { "Current" }
                        elseif ($cfg.CDNBaseUrl -match "7ffbc6bf") { "Semi-Annual Enterprise" }
                        else { "Other" }
                    } else { "" }
                }
                break
            }
        }
    }

    # Fallback: detect from installed software list
    if (-not $found) {
        $officeEntry = $software | Where-Object {
            $_.Name -match "Microsoft (365|Office|Visio|Project)" -and $_.Name -notmatch "Update|Proof|MUI|Tool"
        } | Select-Object -First 1
        if ($officeEntry) {
            $found = @{
                ProductName = $officeEntry.Name
                Version     = $officeEntry.Version
                InstallPath = $officeEntry.InstallLocation
                Channel     = ""
            }
        }
    }

    # Try ospp.vbs for license key
    $licenseKey = "N/A"
    if ($found -and $found.InstallPath) {
        $osppPath = Join-Path $found.InstallPath "Office16\ospp.vbs"
        if (-not (Test-Path $osppPath)) { $osppPath = Join-Path $found.InstallPath "Office15\ospp.vbs" }
        if (Test-Path $osppPath) {
            $osppOutput = Invoke-Safe { cscript //nologo $osppPath /dstatus 2>&1 | Out-String } ""
            if ($osppOutput -match "Last 5 characters of installed product key:\s*(\S+)") {
                $licenseKey = $Matches[1]
            }
        }
    }

    if ($found) {
        $found["LicenseKey"] = $licenseKey
        $found
    } else {
        @{ ProductName = "Not Installed"; Version = ""; InstallPath = ""; Channel = ""; LicenseKey = "N/A" }
    }
} @{ ProductName = "Not Installed"; Version = ""; InstallPath = ""; Channel = ""; LicenseKey = "N/A" }

# Friendly Office name
$officeDisplayName = $officeInfo.ProductName
if ($officeDisplayName -match "O365") { $officeDisplayName = "Microsoft 365 Apps" }
elseif ($officeDisplayName -match "2021") { $officeDisplayName = "Microsoft Office 2021" }
elseif ($officeDisplayName -match "2019") { $officeDisplayName = "Microsoft Office 2019" }
elseif ($officeDisplayName -match "2016") { $officeDisplayName = "Microsoft Office 2016" }

# ── 5. BROWSER VERSIONS ──
$browsers = @{}

$browsers.Chrome = Invoke-Safe {
    $chromePaths = @(
        "${env:ProgramFiles}\Google\Chrome\Application\chrome.exe",
        "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
        "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe"
    )
    foreach ($cp in $chromePaths) {
        if (Test-Path $cp) {
            return (Get-Item $cp).VersionInfo.ProductVersion
        }
    }
    # Fallback: registry
    $regVer = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe" -ErrorAction SilentlyContinue)
    if ($regVer -and $regVer.'(Default)' -and (Test-Path $regVer.'(Default)')) {
        return (Get-Item $regVer.'(Default)').VersionInfo.ProductVersion
    }
    return "Not Installed"
} "Not Installed"

$browsers.Edge = Invoke-Safe {
    $edgePaths = @(
        "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
        "${env:ProgramFiles}\Microsoft\Edge\Application\msedge.exe"
    )
    foreach ($ep in $edgePaths) {
        if (Test-Path $ep) {
            return (Get-Item $ep).VersionInfo.ProductVersion
        }
    }
    return "Not Installed"
} "Not Installed"

$browsers.Firefox = Invoke-Safe {
    $ffPaths = @(
        "${env:ProgramFiles}\Mozilla Firefox\firefox.exe",
        "${env:ProgramFiles(x86)}\Mozilla Firefox\firefox.exe"
    )
    foreach ($fp in $ffPaths) {
        if (Test-Path $fp) {
            return (Get-Item $fp).VersionInfo.ProductVersion
        }
    }
    return "Not Installed"
} "Not Installed"

# ── 6. SECURITY SOFTWARE ──
$securitySoftware = @{}

$securitySoftware.AntivirusProducts = Invoke-Safe {
    $avList = @()
    Get-CimInstance -Namespace "root\SecurityCenter2" -ClassName AntiVirusProduct -ErrorAction Stop | ForEach-Object {
        $avList += $_.displayName
    }
    $avList
} @()

$securitySoftware.DefenderStatus = Invoke-Safe {
    $mp = Get-MpComputerStatus -ErrorAction Stop
    @{
        RealTimeProtection = $mp.RealTimeProtectionEnabled
        DefinitionAge      = $mp.AntivirusSignatureAge
        EngineVersion      = $mp.AMEngineVersion
        ProductVersion     = $mp.AMProductVersion
    }
} @{ RealTimeProtection = "Unknown"; DefinitionAge = "Unknown"; EngineVersion = "Unknown"; ProductVersion = "Unknown" }

$securitySoftware.Firewall = Invoke-Safe {
    $fw = Get-NetFirewallProfile -ErrorAction Stop
    @{
        Domain  = ($fw | Where-Object { $_.Name -eq "Domain" }).Enabled
        Private = ($fw | Where-Object { $_.Name -eq "Private" }).Enabled
        Public  = ($fw | Where-Object { $_.Name -eq "Public" }).Enabled
    }
} @{ Domain = "Unknown"; Private = "Unknown"; Public = "Unknown" }

# ── 7. FLAGGED / RISKY SOFTWARE DETECTION ──
$unwantedPatterns = @(
    "toolbar", "ask\.com", "conduit", "babylon", "coupon",
    "dealply", "superfish", "wajam", "mywebsearch", "mindspark",
    "crossrider", "shopathome", "pricegong", "sweetim"
)
$unwantedRegex = ($unwantedPatterns | ForEach-Object { "($_)" }) -join "|"

$remoteAccessTools = @("TeamViewer", "AnyDesk", "LogMeIn", "ScreenConnect", "Splashtop Remote")

$flaggedItems = @()
foreach ($s in $software) {
    $reason = $null
    $nameLower = $s.Name.ToLower()

    # Java 8 or older
    if ($nameLower -match "java\s*[1-8]\b" -or $nameLower -match "java\(tm\)\s*(se\s*)?(runtime|development).*\s[1-8][\.\s]") {
        $reason = "outdated"
    }
    # Flash Player (any version = EOL)
    elseif ($nameLower -match "adobe\s*flash\s*player|shockwave\s*flash") {
        $reason = "EOL"
    }
    # Silverlight
    elseif ($nameLower -match "microsoft\s*silverlight") {
        $reason = "EOL"
    }
    # .NET Framework < 4.8 (only flag standalone installs of old versions)
    elseif ($nameLower -match "\.net\s*framework\s*([1-3]\.|4\.[0-7][^0-9])") {
        $reason = "outdated"
    }
    # Adobe Reader/Acrobat below current
    elseif ($nameLower -match "adobe\s*(acrobat\s*reader|reader)" -and $s.Version) {
        $majorVer = Invoke-Safe { [int]($s.Version -split '\.')[0] } 0
        if ($majorVer -gt 0 -and $majorVer -lt 24) { $reason = "outdated" }
    }
    # Remote access tools
    elseif ($remoteAccessTools | Where-Object { $nameLower -match $_.ToLower() }) {
        $matched = $remoteAccessTools | Where-Object { $nameLower -match $_.ToLower() } | Select-Object -First 1
        $flaggedItems += @{ Name = $s.Name; Version = $s.Version; Reason = "remote access"; Label = "$($s.Name) (remote access)" }
        continue
    }
    # Unwanted / adware
    elseif ($nameLower -match $unwantedRegex) {
        $reason = "potentially unwanted"
    }

    if ($reason) {
        $flaggedItems += @{ Name = $s.Name; Version = $s.Version; Reason = $reason; Label = "$($s.Name) ($reason)" }
    }
}

# ── 7B. KNOWN VULNERABLE SOFTWARE VERSIONS ──
$knownVulnerable = @(
    @{ Pattern = "google\s*chrome";        MinSafe = "136.0";  CVE = "CVE-2025-4664"; Severity = "High" }
    @{ Pattern = "mozilla\s*firefox";      MinSafe = "138.0";  CVE = "CVE-2025-3028"; Severity = "High" }
    @{ Pattern = "microsoft\s*edge";       MinSafe = "136.0";  CVE = "CVE-2025-29834"; Severity = "High" }
    @{ Pattern = "adobe\s*acrobat\s*reader"; MinSafe = "24.4"; CVE = "CVE-2025-27174"; Severity = "Critical" }
    @{ Pattern = "adobe\s*acrobat\s*dc";   MinSafe = "24.4";   CVE = "CVE-2025-27174"; Severity = "Critical" }
    @{ Pattern = "7-zip";                  MinSafe = "24.09";  CVE = "CVE-2024-11477"; Severity = "High" }
    @{ Pattern = "winrar";                 MinSafe = "7.01";   CVE = "CVE-2024-36052"; Severity = "High" }
    @{ Pattern = "notepad\+\+";            MinSafe = "8.7";    CVE = "CVE-2024-32042"; Severity = "Medium" }
    @{ Pattern = "putty";                  MinSafe = "0.81";   CVE = "CVE-2024-31497"; Severity = "Critical" }
    @{ Pattern = "filezilla";              MinSafe = "3.67";   CVE = "CVE-2024-22911"; Severity = "Medium" }
    @{ Pattern = "vlc\s*media\s*player";   MinSafe = "3.0.21"; CVE = "CVE-2024-46461"; Severity = "High" }
    @{ Pattern = "zoom";                   MinSafe = "6.3";    CVE = "CVE-2025-0145"; Severity = "Medium" }
    @{ Pattern = "libreoffice";            MinSafe = "24.8";   CVE = "CVE-2024-12425"; Severity = "Medium" }
    @{ Pattern = "thunderbird";            MinSafe = "128.5";  CVE = "CVE-2024-50340"; Severity = "High" }
    @{ Pattern = "python\s*3";             MinSafe = "3.12.8"; CVE = "CVE-2024-12254"; Severity = "Medium" }
    @{ Pattern = "node\.?js";              MinSafe = "22.12";  CVE = "CVE-2025-23083"; Severity = "High" }
    @{ Pattern = "git\s";                  MinSafe = "2.48";   CVE = "CVE-2024-50349"; Severity = "High" }
    @{ Pattern = "teamviewer";             MinSafe = "15.62";  CVE = "CVE-2024-7479"; Severity = "High" }
    @{ Pattern = "wireshark";              MinSafe = "4.4.2";  CVE = "CVE-2024-11595"; Severity = "Medium" }
    @{ Pattern = "openssl";                MinSafe = "3.4.0";  CVE = "CVE-2024-9143"; Severity = "Medium" }
    @{ Pattern = "java.*jdk|java.*jre|openjdk"; MinSafe = "21.0.5"; CVE = "CVE-2024-21235"; Severity = "Medium" }
)

$vulnerabilities = @()
foreach ($s in $software) {
    $nameLower = $s.Name.ToLower()
    $version = $s.Version
    if (-not $version) { continue }

    foreach ($vuln in $knownVulnerable) {
        if ($nameLower -match $vuln.Pattern) {
            # Compare versions
            try {
                $installedParts = ($version -split '[.\-]' | Where-Object { $_ -match '^\d+$' } | Select-Object -First 3)
                $safeParts = ($vuln.MinSafe -split '[.\-]' | Where-Object { $_ -match '^\d+$' } | Select-Object -First 3)

                $isVulnerable = $false
                for ($i = 0; $i -lt [math]::Max($installedParts.Count, $safeParts.Count); $i++) {
                    $iv = if ($i -lt $installedParts.Count) { [int]$installedParts[$i] } else { 0 }
                    $sv = if ($i -lt $safeParts.Count) { [int]$safeParts[$i] } else { 0 }
                    if ($iv -lt $sv) { $isVulnerable = $true; break }
                    if ($iv -gt $sv) { break }
                }

                if ($isVulnerable) {
                    $vulnerabilities += @{
                        Name      = $s.Name
                        Version   = $version
                        MinSafe   = $vuln.MinSafe
                        CVE       = $vuln.CVE
                        Severity  = $vuln.Severity
                    }
                    # Also add to flagged items
                    $flaggedItems += @{
                        Name    = $s.Name
                        Version = $version
                        Reason  = "vulnerable"
                        Label   = "$($s.Name) $version (vuln: $($vuln.CVE))"
                    }
                }
            } catch {}
            break
        }
    }
}

# ── 7C. LICENSE COMPLIANCE DETECTION ──
$commercialSoftware = @(
    @{ Pattern = "adobe\s*(photoshop|illustrator|indesign|premiere|after\s*effects|creative\s*cloud|acrobat\s*pro)"; Name = "Adobe Creative Suite" }
    @{ Pattern = "autodesk\s*(autocad|revit|3ds\s*max|maya|inventor)"; Name = "Autodesk Product" }
    @{ Pattern = "vmware\s*(workstation|fusion)\s*pro"; Name = "VMware Workstation" }
    @{ Pattern = "visual\s*studio\s*(enterprise|professional)\s*20"; Name = "Visual Studio" }
    @{ Pattern = "jetbrains\s*(intellij|pycharm|webstorm|phpstorm|rider|clion|goland|rubymine|datagrip)"; Name = "JetBrains IDE" }
    @{ Pattern = "sublime\s*text"; Name = "Sublime Text" }
    @{ Pattern = "corel\s*(draw|paintshop|wordperfect)"; Name = "Corel Product" }
    @{ Pattern = "winzip|winrar"; Name = "Archive Utility" }
    @{ Pattern = "quickbooks"; Name = "QuickBooks" }
    @{ Pattern = "sage\s*(50|100|200|300)"; Name = "Sage Accounting" }
    @{ Pattern = "solidworks"; Name = "SolidWorks" }
    @{ Pattern = "matlab"; Name = "MATLAB" }
    @{ Pattern = "tableau\s*(desktop|prep)"; Name = "Tableau" }
    @{ Pattern = "sketchup\s*pro"; Name = "SketchUp Pro" }
    @{ Pattern = "camtasia"; Name = "Camtasia" }
    @{ Pattern = "snagit"; Name = "Snagit" }
    @{ Pattern = "beyond\s*compare"; Name = "Beyond Compare" }
)

$licenseFlags = @()
foreach ($s in $software) {
    $nameLower = $s.Name.ToLower()
    foreach ($cs in $commercialSoftware) {
        if ($nameLower -match $cs.Pattern) {
            $licenseFlags += @{
                Name       = $s.Name
                Version    = $s.Version
                Category   = $cs.Name
                Publisher  = $s.Publisher
                Note       = "Verify license compliance"
            }
            break
        }
    }
}

# ── 7D. SOFTWARE AGE TRACKING ──
$staleThresholdDays = 180  # 6 months
$staleSoftware = @()
$today = Get-Date

foreach ($s in $software) {
    if (-not $s.InstallDate -or $s.InstallDate -eq "") { continue }
    try {
        $installDate = $null
        if ($s.InstallDate -match '^\d{8}$') {
            $installDate = [DateTime]::ParseExact($s.InstallDate, "yyyyMMdd", $null)
        }
        if ($installDate) {
            $ageInDays = ($today - $installDate).Days
            if ($ageInDays -gt $staleThresholdDays) {
                $staleSoftware += @{
                    Name        = $s.Name
                    Version     = $s.Version
                    InstallDate = $installDate.ToString("yyyy-MM-dd")
                    AgeDays     = $ageInDays
                    AgeMonths   = [math]::Round($ageInDays / 30, 0)
                }
            }
        }
    } catch {}
}

# ── 7E. END-OF-LIFE SOFTWARE DETECTION ──
$eolItems = @()

# Windows 10 EOL versions (mainstream support ending 2025-10-14)
if ($sysInfo.OSVersion -match "Windows 10") {
    $buildNum = $sysInfo.OSBuild
    $win10EOL = @{
        "19041" = @{ Version = "2004"; EOL = "2021-12-14" }
        "19042" = @{ Version = "20H2"; EOL = "2022-05-10" }
        "19043" = @{ Version = "21H1"; EOL = "2022-12-13" }
        "19044" = @{ Version = "21H2"; EOL = "2023-06-13" }
        "19045" = @{ Version = "22H2"; EOL = "2025-10-14" }
    }
    if ($win10EOL.ContainsKey($buildNum)) {
        $eolDate = [DateTime]::ParseExact($win10EOL[$buildNum].EOL, "yyyy-MM-dd", $null)
        $daysUntilEOL = ($eolDate - $today).Days
        $eolStatus = if ($daysUntilEOL -lt 0) { "PAST EOL" } elseif ($daysUntilEOL -lt 180) { "EOL IMMINENT" } else { "Active" }
        if ($eolStatus -ne "Active") {
            $eolItems += @{
                Name    = "Windows 10 $($win10EOL[$buildNum].Version)"
                EOLDate = $win10EOL[$buildNum].EOL
                Status  = $eolStatus
                DaysRemaining = [math]::Max($daysUntilEOL, 0)
                Action  = if ($eolStatus -eq "PAST EOL") { "Upgrade to Windows 11 immediately" } else { "Plan upgrade before $($win10EOL[$buildNum].EOL)" }
            }
        }
    }
    # Windows 10 overall is approaching EOL
    $win10FinalEOL = [DateTime]::ParseExact("2025-10-14", "yyyy-MM-dd", $null)
    $daysToWin10EOL = ($win10FinalEOL - $today).Days
    if ($daysToWin10EOL -lt 365 -and $daysToWin10EOL -gt 0) {
        $eolItems += @{
            Name    = "Windows 10 (all versions)"
            EOLDate = "2025-10-14"
            Status  = "EOL APPROACHING"
            DaysRemaining = $daysToWin10EOL
            Action  = "Windows 10 end of support: $daysToWin10EOL days remaining. Plan Windows 11 upgrade."
        }
    } elseif ($daysToWin10EOL -le 0) {
        $eolItems += @{
            Name    = "Windows 10 (all versions)"
            EOLDate = "2025-10-14"
            Status  = "PAST EOL"
            DaysRemaining = 0
            Action  = "Windows 10 is past end of support. Upgrade to Windows 11 urgently."
        }
    }
}

# Office version EOL checks
$officeEOLVersions = @(
    @{ Pattern = "office\s*(2013|15\.)";  Name = "Office 2013"; EOL = "2023-04-11"; Status = "PAST EOL" }
    @{ Pattern = "office\s*(2016|16\.\d)"; Name = "Office 2016"; EOL = "2025-10-14"; Status = "EOL IMMINENT" }
    @{ Pattern = "office\s*(2019|16\.0\.(10|11|12))"; Name = "Office 2019"; EOL = "2025-10-14"; Status = "EOL IMMINENT" }
)

foreach ($s in $software) {
    $nameLower = $s.Name.ToLower()
    if ($nameLower -notmatch "microsoft.*office|microsoft.*365") { continue }
    foreach ($oev in $officeEOLVersions) {
        if ($nameLower -match $oev.Pattern) {
            $eolDate = [DateTime]::ParseExact($oev.EOL, "yyyy-MM-dd", $null)
            $daysUntil = ($eolDate - $today).Days
            $eolItems += @{
                Name    = "$($oev.Name) ($($s.Name))"
                EOLDate = $oev.EOL
                Status  = if ($daysUntil -lt 0) { "PAST EOL" } else { $oev.Status }
                DaysRemaining = [math]::Max($daysUntil, 0)
                Action  = if ($daysUntil -lt 0) { "Upgrade to Microsoft 365 or Office 2024" } else { "EOL in $daysUntil days - plan upgrade" }
            }
            break
        }
    }
}

# Other known EOL software
foreach ($s in $software) {
    $nameLower = $s.Name.ToLower()
    if ($nameLower -match "internet\s*explorer" -and $nameLower -notmatch "mode") {
        $eolItems += @{ Name = "Internet Explorer"; EOLDate = "2022-06-15"; Status = "PAST EOL"; DaysRemaining = 0; Action = "Use Microsoft Edge" }
    }
    if ($nameLower -match "visual\s*basic\s*6|vb6") {
        $eolItems += @{ Name = "Visual Basic 6.0"; EOLDate = "2008-04-08"; Status = "PAST EOL"; DaysRemaining = 0; Action = "Migrate to .NET" }
    }
    if ($nameLower -match "python\s*2\b") {
        $eolItems += @{ Name = "Python 2.x"; EOLDate = "2020-01-01"; Status = "PAST EOL"; DaysRemaining = 0; Action = "Migrate to Python 3.x" }
    }
}

# ── 8. STARTUP PROGRAMS ──
$startupItems = @()

# Registry Run keys
$runKeys = @(
    @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"; Scope = "Machine" },
    @{ Path = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"; Scope = "User" },
    @{ Path = "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run"; Scope = "Machine (32-bit)" }
)
foreach ($rk in $runKeys) {
    if (Test-Path $rk.Path) {
        $props = Invoke-Safe { Get-ItemProperty $rk.Path -ErrorAction SilentlyContinue } $null
        if ($props) {
            $props.PSObject.Properties | Where-Object {
                $_.Name -notin @("PSPath","PSParentPath","PSChildName","PSDrive","PSProvider")
            } | ForEach-Object {
                $startupItems += @{ Name = $_.Name; Command = "$($_.Value)"; Source = "Registry ($($rk.Scope))"; Type = "Registry" }
            }
        }
    }
}

# Startup folder
$startupFolders = @(
    [Environment]::GetFolderPath("Startup"),
    [Environment]::GetFolderPath("CommonStartup")
)
foreach ($sf in $startupFolders) {
    if ($sf -and (Test-Path $sf)) {
        Get-ChildItem $sf -File -ErrorAction SilentlyContinue | ForEach-Object {
            $startupItems += @{ Name = $_.BaseName; Command = $_.FullName; Source = "Startup Folder"; Type = "Folder" }
        }
    }
}

# Scheduled tasks at logon
$logonTasks = Invoke-Safe {
    $tasks = @()
    Get-ScheduledTask -ErrorAction Stop | Where-Object { $_.State -ne "Disabled" } | ForEach-Object {
        $hasTrigger = $false
        foreach ($t in $_.Triggers) {
            if ($t -is [Microsoft.Management.Infrastructure.CimInstance] -and $t.CimClass.CimClassName -eq "MSFT_TaskLogonTrigger") {
                $hasTrigger = $true; break
            }
        }
        if ($hasTrigger) {
            $action = ($_.Actions | Select-Object -First 1)
            $cmd = if ($action.Execute) { $action.Execute } else { "" }
            $tasks += @{ Name = $_.TaskName; Command = $cmd; Source = "Scheduled Task (Logon)"; Type = "Task" }
        }
    }
    $tasks
} @()
$startupItems += $logonTasks

# ── 9. WINDOWS STORE APPS (non-framework) ──
$storeApps = Invoke-Safe {
    $apps = @()
    Get-AppxPackage -ErrorAction Stop | Where-Object {
        -not $_.IsFramework -and $_.SignatureKind -ne "System"
    } | ForEach-Object {
        $apps += @{ Name = $_.Name; Version = $_.Version }
    }
    $apps
} @()

# ── 10. SOFTWARE COUNTS SUMMARY ──
$totalSoftware    = $software.Count
$totalStoreApps   = $storeApps.Count
$flaggedCount     = $flaggedItems.Count
$vulnCount        = $vulnerabilities.Count
$licenseCount     = $licenseFlags.Count
$staleCount       = $staleSoftware.Count
$eolCount         = $eolItems.Count

# Top 10 publishers
$publisherCounts = @{}
foreach ($s in $software) {
    $pub = if ($s.Publisher) { $s.Publisher } else { "(Unknown)" }
    if ($publisherCounts.ContainsKey($pub)) { $publisherCounts[$pub]++ }
    else { $publisherCounts[$pub] = 1 }
}
$topPublishers = $publisherCounts.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 10

# ── 11. HTML REPORT GENERATION ──
$scanDate   = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
$dateStamp  = (Get-Date).ToString("yyyyMMdd-HHmmss")
$reportFile = Join-Path $OutputDir "PCPlus360-Inventory-$($env:COMPUTERNAME)-$dateStamp.html"

# Build flagged software rows
$flaggedRowsHtml = ""
if ($flaggedItems.Count -gt 0) {
    foreach ($f in $flaggedItems) {
        $reasonBadge = switch ($f.Reason) {
            "EOL"                  { '<span style="background:#e74c3c;color:#fff;padding:2px 8px;border-radius:3px;font-size:11px">EOL</span>' }
            "outdated"             { '<span style="background:#f39c12;color:#fff;padding:2px 8px;border-radius:3px;font-size:11px">OUTDATED</span>' }
            "remote access"        { '<span style="background:#8e44ad;color:#fff;padding:2px 8px;border-radius:3px;font-size:11px">REMOTE ACCESS</span>' }
            "potentially unwanted" { '<span style="background:#e67e22;color:#fff;padding:2px 8px;border-radius:3px;font-size:11px">PUP</span>' }
            default                { '<span style="background:#95a5a6;color:#fff;padding:2px 8px;border-radius:3px;font-size:11px">FLAG</span>' }
        }
        $flaggedRowsHtml += "<tr><td>$($f.Name)</td><td>$($f.Version)</td><td>$reasonBadge</td></tr>`n"
    }
} else {
    $flaggedRowsHtml = '<tr><td colspan="3" style="text-align:center;color:#27ae60;padding:20px">No flagged software detected</td></tr>'
}

# Build vulnerability rows
$vulnRowsHtml = ""
if ($vulnerabilities.Count -gt 0) {
    foreach ($v in $vulnerabilities) {
        $sevBadge = switch ($v.Severity) {
            "Critical" { '<span style="background:#e74c3c;color:#fff;padding:2px 8px;border-radius:3px;font-size:11px">CRITICAL</span>' }
            "High"     { '<span style="background:#e67e22;color:#fff;padding:2px 8px;border-radius:3px;font-size:11px">HIGH</span>' }
            "Medium"   { '<span style="background:#f39c12;color:#fff;padding:2px 8px;border-radius:3px;font-size:11px">MEDIUM</span>' }
            default    { '<span style="background:#95a5a6;color:#fff;padding:2px 8px;border-radius:3px;font-size:11px">LOW</span>' }
        }
        $vulnRowsHtml += "<tr style=`"background:#fef5f5`"><td>$($v.Name)</td><td>$($v.Version)</td><td>$($v.MinSafe)+</td><td>$($v.CVE)</td><td>$sevBadge</td></tr>`n"
    }
} else {
    $vulnRowsHtml = '<tr><td colspan="5" style="text-align:center;color:#27ae60;padding:16px">No known vulnerable versions detected</td></tr>'
}

# Build license compliance rows
$licenseRowsHtml = ""
if ($licenseFlags.Count -gt 0) {
    foreach ($lf in $licenseFlags) {
        $licenseRowsHtml += "<tr><td>$($lf.Name)</td><td>$($lf.Version)</td><td>$($lf.Category)</td><td>$($lf.Publisher)</td><td><span style=`"color:#e67e22;font-weight:600`">$($lf.Note)</span></td></tr>`n"
    }
} else {
    $licenseRowsHtml = '<tr><td colspan="5" style="text-align:center;color:#27ae60;padding:16px">No commercial software requiring license verification</td></tr>'
}

# Build EOL rows
$eolRowsHtml = ""
if ($eolItems.Count -gt 0) {
    foreach ($eol in $eolItems) {
        $eolBadge = switch ($eol.Status) {
            "PAST EOL"       { '<span style="background:#e74c3c;color:#fff;padding:2px 8px;border-radius:3px;font-size:11px">PAST EOL</span>' }
            "EOL IMMINENT"   { '<span style="background:#e67e22;color:#fff;padding:2px 8px;border-radius:3px;font-size:11px">EOL SOON</span>' }
            "EOL APPROACHING" { '<span style="background:#f39c12;color:#fff;padding:2px 8px;border-radius:3px;font-size:11px">APPROACHING</span>' }
            default          { '<span style="background:#95a5a6;color:#fff;padding:2px 8px;border-radius:3px;font-size:11px">CHECK</span>' }
        }
        $eolRowsHtml += "<tr style=`"background:#fef5f5`"><td>$($eol.Name)</td><td>$($eol.EOLDate)</td><td>$eolBadge</td><td>$($eol.DaysRemaining) days</td><td style=`"font-size:12px`">$($eol.Action)</td></tr>`n"
    }
} else {
    $eolRowsHtml = '<tr><td colspan="5" style="text-align:center;color:#27ae60;padding:16px">No end-of-life software detected</td></tr>'
}

# Build stale software rows (top 15)
$staleRowsHtml = ""
$staleSorted = $staleSoftware | Sort-Object { $_.AgeDays } -Descending | Select-Object -First 15
if ($staleSorted.Count -gt 0) {
    foreach ($ss in $staleSorted) {
        $ageColor = if ($ss.AgeDays -gt 365) { "#e74c3c" } elseif ($ss.AgeDays -gt 270) { "#e67e22" } else { "#f39c12" }
        $staleRowsHtml += "<tr><td>$($ss.Name)</td><td>$($ss.Version)</td><td>$($ss.InstallDate)</td><td style=`"color:${ageColor};font-weight:600`">$($ss.AgeMonths) months</td></tr>`n"
    }
} else {
    $staleRowsHtml = '<tr><td colspan="4" style="text-align:center;color:#27ae60;padding:16px">No stale software detected (all installed within 6 months)</td></tr>'
}

# Build full software inventory rows
$softwareRowsHtml = ""
foreach ($s in $software) {
    $isFlagged = $flaggedItems | Where-Object { $_.Name -eq $s.Name -and $_.Version -eq $s.Version }
    $rowStyle = if ($isFlagged) { ' style="background:#fef5f5"' } else { "" }
    $installDateFormatted = if ($s.InstallDate -and $s.InstallDate -match '^\d{8}$') {
        "$($s.InstallDate.Substring(0,4))-$($s.InstallDate.Substring(4,2))-$($s.InstallDate.Substring(6,2))"
    } else { $s.InstallDate }
    $softwareRowsHtml += "<tr$rowStyle><td>$($s.Name)</td><td>$($s.Version)</td><td>$($s.Publisher)</td><td>$installDateFormatted</td></tr>`n"
}

# Build browser rows
$browserRowsHtml = ""
$browserList = @(
    @{ Name = "Google Chrome"; Version = $browsers.Chrome; Icon = "&#127760;" },
    @{ Name = "Microsoft Edge"; Version = $browsers.Edge; Icon = "&#127760;" },
    @{ Name = "Mozilla Firefox"; Version = $browsers.Firefox; Icon = "&#127760;" }
)
foreach ($b in $browserList) {
    $statusColor = if ($b.Version -eq "Not Installed") { "#95a5a6" } else { "#27ae60" }
    $browserRowsHtml += "<tr><td>$($b.Icon) $($b.Name)</td><td style=`"color:$statusColor;font-weight:600`">$($b.Version)</td></tr>`n"
}

# Build startup rows
$startupRowsHtml = ""
foreach ($si in $startupItems) {
    $cmdTruncated = if ($si.Command.Length -gt 120) { $si.Command.Substring(0, 117) + "..." } else { $si.Command }
    $startupRowsHtml += "<tr><td>$($si.Name)</td><td style=`"font-size:11px;word-break:break-all`">$cmdTruncated</td><td>$($si.Source)</td></tr>`n"
}
if ($startupItems.Count -eq 0) {
    $startupRowsHtml = '<tr><td colspan="3" style="text-align:center;color:#888">No startup items detected</td></tr>'
}

# Build top publishers horizontal bar chart (CSS-based)
$publisherChartHtml = ""
$maxPubCount = if ($topPublishers.Count -gt 0) { ($topPublishers | Select-Object -First 1).Value } else { 1 }
foreach ($pub in $topPublishers) {
    $barWidth = [math]::Round(($pub.Value / $maxPubCount) * 100, 0)
    $publisherChartHtml += @"
<div style="display:flex;align-items:center;margin-bottom:6px">
  <div style="width:200px;font-size:12px;text-align:right;padding-right:10px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap" title="$($pub.Key)">$($pub.Key)</div>
  <div style="flex:1;background:#e8ecf1;border-radius:4px;height:22px;overflow:hidden">
    <div style="background:linear-gradient(90deg,#2596be,#0a1628);height:100%;width:${barWidth}%;border-radius:4px;min-width:30px;display:flex;align-items:center;justify-content:flex-end;padding-right:6px">
      <span style="color:#fff;font-size:11px;font-weight:600">$($pub.Value)</span>
    </div>
  </div>
</div>
"@
}

# Firewall status display
$fwDomainLabel  = if ($securitySoftware.Firewall.Domain  -eq $true) { '<span style="color:#27ae60;font-weight:600">ON</span>' } elseif ($securitySoftware.Firewall.Domain  -eq $false) { '<span style="color:#e74c3c;font-weight:600">OFF</span>' } else { '<span style="color:#888">Unknown</span>' }
$fwPrivateLabel = if ($securitySoftware.Firewall.Private -eq $true) { '<span style="color:#27ae60;font-weight:600">ON</span>' } elseif ($securitySoftware.Firewall.Private -eq $false) { '<span style="color:#e74c3c;font-weight:600">OFF</span>' } else { '<span style="color:#888">Unknown</span>' }
$fwPublicLabel  = if ($securitySoftware.Firewall.Public  -eq $true) { '<span style="color:#27ae60;font-weight:600">ON</span>' } elseif ($securitySoftware.Firewall.Public  -eq $false) { '<span style="color:#e74c3c;font-weight:600">OFF</span>' } else { '<span style="color:#888">Unknown</span>' }

# Defender status display
$defenderRTP = $securitySoftware.DefenderStatus.RealTimeProtection
$defenderRTPLabel = if ($defenderRTP -eq $true) { '<span style="color:#27ae60;font-weight:600">Enabled</span>' } elseif ($defenderRTP -eq $false) { '<span style="color:#e74c3c;font-weight:600">Disabled</span>' } else { '<span style="color:#888">Unknown</span>' }

# AV list for display
$avListDisplay = if ($securitySoftware.AntivirusProducts.Count -gt 0) {
    ($securitySoftware.AntivirusProducts -join ", ")
} else { "None detected" }

# Summary card colors
$flaggedColor = if ($flaggedCount -gt 0) { "#e74c3c" } else { "#27ae60" }
$licenseColor = if ($winLicense.Status -eq "Activated") { "#27ae60" } else { "#f39c12" }

$html = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>PC Plus 360 - Software Inventory - $($env:COMPUTERNAME)</title>
<style>
  *{margin:0;padding:0;box-sizing:border-box}
  body{font-family:'Segoe UI',Tahoma,Geneva,Verdana,sans-serif;background:#f4f6f9;color:#333;line-height:1.5}
  .header{background:linear-gradient(135deg,#0a1628 0%,#1a2d4a 100%);color:#fff;padding:30px 40px}
  .header .brand{color:#2596be;font-weight:700;font-size:20px;margin-bottom:6px}
  .header h1{font-size:22px;margin-bottom:4px}
  .header .subtitle{color:#8899aa;font-size:13px}
  .header .meta{display:flex;gap:30px;margin-top:12px;font-size:13px;color:#bbb;flex-wrap:wrap}
  .container{max-width:1100px;margin:0 auto;padding:20px}
  .section{background:#fff;border-radius:8px;box-shadow:0 1px 3px rgba(0,0,0,.08);padding:24px;margin-bottom:20px}
  .section h2{font-size:18px;color:#0a1628;margin-bottom:16px;border-bottom:2px solid #2596be;padding-bottom:8px}
  .card-row{display:flex;gap:16px;flex-wrap:wrap}
  .card{flex:1;min-width:160px;background:#f8f9fc;border-radius:6px;padding:16px;text-align:center;border:1px solid #e8ecf1}
  .card-label{font-size:11px;text-transform:uppercase;color:#888;letter-spacing:.5px;margin-bottom:4px}
  .card-value{font-size:22px;font-weight:700;color:#0a1628}
  table{width:100%;border-collapse:collapse;font-size:13px}
  th{background:#f0f2f5;text-align:left;padding:10px 12px;font-weight:600;color:#555;border-bottom:2px solid #ddd;cursor:pointer;user-select:none}
  th:hover{background:#e4e7eb}
  td{padding:8px 12px;border-bottom:1px solid #eee}
  .flagged-section table td{background:#fef5f5}
  .info-grid{display:grid;grid-template-columns:1fr 1fr;gap:8px 24px;font-size:13px}
  .info-grid .label{color:#888;font-weight:600}
  .info-grid .value{color:#333}
  .footer{text-align:center;padding:20px;color:#888;font-size:12px;border-top:1px solid #e0e0e0;margin-top:20px}
  .footer a{color:#2596be;text-decoration:none}
  .sort-arrow{font-size:10px;margin-left:4px;color:#aaa}
  @media print{body{background:#fff}.section{box-shadow:none;border:1px solid #ddd}}
</style>
</head>
<body>

<div class="header">
  <div class="brand">PC Plus Computing</div>
  <h1>Software Inventory Report</h1>
  <div class="subtitle">Comprehensive Software Audit &amp; Risk Assessment</div>
  <div class="meta">
    <span>Computer: <strong>$($env:COMPUTERNAME)</strong></span>
    <span>Company: <strong>$(if($CompanyName){$CompanyName}elseif($CustomerName){$CustomerName}else{'N/A'})</strong></span>
    <span>Tech: <strong>$TechName</strong></span>
    <span>Date: <strong>$scanDate</strong></span>
  </div>
</div>

<div class="container">

<!-- Summary Cards -->
<div class="section">
  <h2>Summary</h2>
  <div class="card-row">
    <div class="card">
      <div class="card-label">Total Software</div>
      <div class="card-value">$totalSoftware</div>
    </div>
    <div class="card">
      <div class="card-label">Flagged Items</div>
      <div class="card-value" style="color:$flaggedColor">$flaggedCount</div>
    </div>
    <div class="card">
      <div class="card-label">Vulnerabilities</div>
      <div class="card-value" style="color:$(if($vulnCount -gt 0){'#e74c3c'}else{'#27ae60'})">$vulnCount</div>
    </div>
    <div class="card">
      <div class="card-label">EOL Software</div>
      <div class="card-value" style="color:$(if($eolCount -gt 0){'#e67e22'}else{'#27ae60'})">$eolCount</div>
    </div>
  </div>
  <div class="card-row" style="margin-top:12px">
    <div class="card">
      <div class="card-label">Windows</div>
      <div class="card-value" style="font-size:14px">$($sysInfo.OSVersion)</div>
    </div>
    <div class="card">
      <div class="card-label">Office</div>
      <div class="card-value" style="font-size:14px">$officeDisplayName</div>
    </div>
    <div class="card">
      <div class="card-label">License Checks</div>
      <div class="card-value" style="color:$(if($licenseCount -gt 0){'#f39c12'}else{'#27ae60'})">$licenseCount</div>
    </div>
    <div class="card">
      <div class="card-label">Stale (6+ mo)</div>
      <div class="card-value" style="color:$(if($staleCount -gt 0){'#f39c12'}else{'#27ae60'})">$staleCount</div>
    </div>
  </div>
</div>

<!-- Flagged Software -->
<div class="section flagged-section">
  <h2>&#9888; Flagged Software - Needs Attention ($flaggedCount)</h2>
  <table>
    <thead><tr><th>Software</th><th>Version</th><th>Issue</th></tr></thead>
    <tbody>$flaggedRowsHtml</tbody>
  </table>
</div>

<!-- Vulnerability Report -->
<div class="section">
  <h2>&#128274; Known Vulnerabilities ($vulnCount)</h2>
  <table>
    <thead><tr><th>Software</th><th>Installed</th><th>Min Safe</th><th>CVE</th><th>Severity</th></tr></thead>
    <tbody>$vulnRowsHtml</tbody>
  </table>
</div>

<!-- EOL Software -->
<div class="section">
  <h2>&#9201; End-of-Life Software ($eolCount)</h2>
  <table>
    <thead><tr><th>Software</th><th>EOL Date</th><th>Status</th><th>Remaining</th><th>Action</th></tr></thead>
    <tbody>$eolRowsHtml</tbody>
  </table>
</div>

<!-- License Compliance -->
<div class="section">
  <h2>&#128196; License Compliance ($licenseCount)</h2>
  <table>
    <thead><tr><th>Software</th><th>Version</th><th>Category</th><th>Publisher</th><th>Note</th></tr></thead>
    <tbody>$licenseRowsHtml</tbody>
  </table>
</div>

<!-- Stale Software -->
<div class="section">
  <h2>&#128197; Software Age ($staleCount not updated in 6+ months)</h2>
  <table>
    <thead><tr><th>Software</th><th>Version</th><th>Install Date</th><th>Age</th></tr></thead>
    <tbody>$staleRowsHtml</tbody>
  </table>
</div>

<!-- Full Software Inventory -->
<div class="section">
  <h2>Full Software Inventory ($totalSoftware)</h2>
  <table id="softwareTable">
    <thead>
      <tr>
        <th onclick="sortTable('softwareTable',0)">Name <span class="sort-arrow">&#9650;&#9660;</span></th>
        <th onclick="sortTable('softwareTable',1)">Version <span class="sort-arrow">&#9650;&#9660;</span></th>
        <th onclick="sortTable('softwareTable',2)">Publisher <span class="sort-arrow">&#9650;&#9660;</span></th>
        <th onclick="sortTable('softwareTable',3)">Install Date <span class="sort-arrow">&#9650;&#9660;</span></th>
      </tr>
    </thead>
    <tbody>$softwareRowsHtml</tbody>
  </table>
</div>

<!-- Browser Versions -->
<div class="section">
  <h2>Browser Versions</h2>
  <table>
    <thead><tr><th>Browser</th><th>Version</th></tr></thead>
    <tbody>$browserRowsHtml</tbody>
  </table>
</div>

<!-- Windows & Office License -->
<div class="section">
  <h2>Windows &amp; Office License</h2>
  <div style="display:flex;gap:40px;flex-wrap:wrap">
    <div style="flex:1;min-width:280px">
      <h3 style="font-size:15px;color:#0a1628;margin-bottom:12px;border-bottom:1px solid #eee;padding-bottom:6px">Windows License</h3>
      <div class="info-grid">
        <div class="label">Product</div><div class="value">$($winLicense.ProductName)</div>
        <div class="label">Product ID</div><div class="value">$($winLicense.ProductId)</div>
        <div class="label">Status</div><div class="value" style="color:$licenseColor;font-weight:600">$($winLicense.Status)</div>
        <div class="label">Partial Key</div><div class="value">$($winLicense.PartialKey)</div>
        <div class="label">OA3 Key</div><div class="value">$($winLicense.OA3Key)</div>
      </div>
    </div>
    <div style="flex:1;min-width:280px">
      <h3 style="font-size:15px;color:#0a1628;margin-bottom:12px;border-bottom:1px solid #eee;padding-bottom:6px">Microsoft Office</h3>
      <div class="info-grid">
        <div class="label">Product</div><div class="value">$officeDisplayName</div>
        <div class="label">Version</div><div class="value">$($officeInfo.Version)</div>
        <div class="label">Channel</div><div class="value">$(if($officeInfo.Channel){$officeInfo.Channel}else{'N/A'})</div>
        <div class="label">License Key (last 5)</div><div class="value">$($officeInfo.LicenseKey)</div>
        <div class="label">Install Path</div><div class="value" style="font-size:11px;word-break:break-all">$(if($officeInfo.InstallPath){$officeInfo.InstallPath}else{'N/A'})</div>
      </div>
    </div>
  </div>
</div>

<!-- Security Software -->
<div class="section">
  <h2>Security Software</h2>
  <div class="info-grid" style="max-width:600px">
    <div class="label">Antivirus Products</div><div class="value">$avListDisplay</div>
    <div class="label">Defender Real-Time</div><div class="value">$defenderRTPLabel</div>
    <div class="label">Defender Engine</div><div class="value">$($securitySoftware.DefenderStatus.EngineVersion)</div>
    <div class="label">Definition Age</div><div class="value">$($securitySoftware.DefenderStatus.DefinitionAge) day(s)</div>
    <div class="label">Firewall (Domain)</div><div class="value">$fwDomainLabel</div>
    <div class="label">Firewall (Private)</div><div class="value">$fwPrivateLabel</div>
    <div class="label">Firewall (Public)</div><div class="value">$fwPublicLabel</div>
  </div>
</div>

<!-- Startup Programs -->
<div class="section">
  <h2>Startup Programs ($($startupItems.Count))</h2>
  <table>
    <thead><tr><th>Name</th><th>Command</th><th>Source</th></tr></thead>
    <tbody>$startupRowsHtml</tbody>
  </table>
</div>

<!-- Top Publishers Chart -->
<div class="section">
  <h2>Top Publishers</h2>
  <div style="max-width:700px">$publisherChartHtml</div>
</div>

<!-- Footer -->
<div class="footer">
  <strong>PC Plus Computing</strong> | <a href="https://pcpluscomputing.com">pcpluscomputing.com</a> | 604-760-1662<br>
  Report generated by PCPlus 360 v1.0.0 - Software Inventory Scanner | $scanDate
</div>

</div>

<script>
var sortDirs={};
function sortTable(tableId,colIdx){
  var table=document.getElementById(tableId);
  if(!table)return;
  var tbody=table.tBodies[0];
  var rows=Array.prototype.slice.call(tbody.rows);
  var key=tableId+'_'+colIdx;
  sortDirs[key]=sortDirs[key]===1?-1:1;
  var dir=sortDirs[key];
  rows.sort(function(a,b){
    var aText=(a.cells[colIdx]||{}).textContent||'';
    var bText=(b.cells[colIdx]||{}).textContent||'';
    return dir*aText.localeCompare(bText,undefined,{numeric:true,sensitivity:'base'});
  });
  for(var i=0;i<rows.length;i++){tbody.appendChild(rows[i]);}
}
</script>

</body>
</html>
"@

$html | Out-File -FilePath $reportFile -Encoding UTF8 -Force

# ── 12. AUTO-UPLOAD ──
$uploaded = $false
$uploadMsg = ""

if (-not $SkipUpload -and -not [string]::IsNullOrWhiteSpace($UploadUrl)) {
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls11

        $boundary = [System.Guid]::NewGuid().ToString("N")
        $LF = "`r`n"
        $fileName = [IO.Path]::GetFileName($reportFile)
        $fileBytes = [IO.File]::ReadAllBytes($reportFile)

        $fields = @{
            customer_name  = $CustomerName
            company_name   = $CompanyName
            computer_name  = $env:COMPUTERNAME
            tech_name      = $TechName
            scan_date      = $scanDate
            file_type      = "HTML"
            source         = "rmm-inventory"
            total_software = "$totalSoftware"
            flagged_count  = "$flaggedCount"
        }

        $bodyParts = [System.Collections.ArrayList]::new()
        foreach ($key in $fields.Keys) {
            [void]$bodyParts.Add("--$boundary$LF")
            [void]$bodyParts.Add("Content-Disposition: form-data; name=`"$key`"$LF$LF")
            [void]$bodyParts.Add("$($fields[$key])$LF")
        }

        $fileHeader = "--$boundary${LF}Content-Disposition: form-data; name=`"report_file`"; filename=`"$fileName`"${LF}Content-Type: text/html${LF}${LF}"
        $fileFooter = "${LF}--${boundary}--${LF}"

        $enc = [Text.Encoding]::UTF8
        $textPreamble = $enc.GetBytes(($bodyParts -join ""))
        $headerBytes  = $enc.GetBytes($fileHeader)
        $footerBytes  = $enc.GetBytes($fileFooter)

        $bodyStream = [IO.MemoryStream]::new()
        $bodyStream.Write($textPreamble, 0, $textPreamble.Length)
        $bodyStream.Write($headerBytes,  0, $headerBytes.Length)
        $bodyStream.Write($fileBytes,    0, $fileBytes.Length)
        $bodyStream.Write($footerBytes,  0, $footerBytes.Length)
        $fullBody = $bodyStream.ToArray()
        $bodyStream.Close()

        $headers = @{ "Content-Type" = "multipart/form-data; boundary=$boundary" }
        if (-not [string]::IsNullOrWhiteSpace($ApiKey)) {
            $headers["Authorization"] = "Bearer $ApiKey"
        }

        $response = Invoke-RestMethod -Uri $UploadUrl -Method Post -Headers $headers -Body $fullBody -ContentType "multipart/form-data; boundary=$boundary" -TimeoutSec 60 -ErrorAction Stop
        $uploaded = $true
        $uploadMsg = "Upload successful"
    }
    catch {
        $uploaded = $false
        $uploadMsg = "Upload failed: $($_.Exception.Message)"
    }
} else {
    $uploadMsg = if ($SkipUpload) { "Upload skipped (SkipUpload flag)" } else { "Upload skipped (no URL)" }
}

# ── 13. JSON SUMMARY OUTPUT ──
$scanEnd  = Get-Date
$duration = [math]::Round(($scanEnd - $scanStart).TotalSeconds, 0)

# Build top publishers hashtable for JSON
$topPubHash = @{}
foreach ($pub in $topPublishers) {
    $topPubHash[$pub.Key] = $pub.Value
}

# Build flagged labels array
$flaggedLabels = @()
foreach ($f in $flaggedItems) {
    $flaggedLabels += $f.Label
}

# Build vulnerability details for JSON
$vulnDetails = @()
foreach ($v in $vulnerabilities) {
    $vulnDetails += @{
        name     = $v.Name
        version  = $v.Version
        min_safe = $v.MinSafe
        cve      = $v.CVE
        severity = $v.Severity
    }
}

# Build EOL details for JSON
$eolDetails = @()
foreach ($eol in $eolItems) {
    $eolDetails += @{
        name           = $eol.Name
        eol_date       = $eol.EOLDate
        status         = $eol.Status
        days_remaining = $eol.DaysRemaining
        action         = $eol.Action
    }
}

# Build license flags for JSON
$licenseDetails = @()
foreach ($lf in $licenseFlags) {
    $licenseDetails += @{
        name      = $lf.Name
        version   = $lf.Version
        category  = $lf.Category
        publisher = $lf.Publisher
    }
}

$summary = @{
    computer              = $env:COMPUTERNAME
    company               = if ($CompanyName) { $CompanyName } elseif ($CustomerName) { $CustomerName } else { "" }
    os                    = $sysInfo.OSVersion
    os_build              = $sysInfo.OSBuild
    domain                = $sysInfo.Domain
    total_software        = $totalSoftware
    total_store_apps      = $totalStoreApps
    flagged_count         = $flaggedCount
    flagged_items         = $flaggedLabels
    vulnerabilities_count = $vulnCount
    vulnerabilities       = $vulnDetails
    eol_count             = $eolCount
    eol_items             = $eolDetails
    license_flags_count   = $licenseCount
    license_flags         = $licenseDetails
    stale_software_count  = $staleCount
    windows_license       = "$($winLicense.ProductName) - $($winLicense.Status)"
    office_version        = $officeDisplayName
    chrome_version        = $browsers.Chrome
    edge_version          = $browsers.Edge
    firefox_version       = $browsers.Firefox
    top_publishers        = $topPubHash
    startup_count         = $startupItems.Count
    report_path           = $reportFile
    uploaded              = $uploaded
    upload_message        = $uploadMsg
    scan_duration_seconds = $duration
}

$jsonOutput = $summary | ConvertTo-Json -Depth 5 -Compress
Write-Output $jsonOutput

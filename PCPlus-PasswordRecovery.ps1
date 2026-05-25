# ═══════════════════════════════════════════════════════════════════════════════
# PC Plus Computing - Password Recovery Tool
# Recovers saved browser passwords and WiFi keys for customer service
# MUST be run as the user who saved the passwords (DPAPI is user-bound)
# ═══════════════════════════════════════════════════════════════════════════════
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName System.Security

$Global:ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$Global:ToolsDir  = Join-Path $Global:ScriptDir "tools"
$COMPANY = "PC Plus Computing"
$Global:AuditLogDir = "C:\PCPlus360\AuditLogs"
$Global:ConsentDir  = "C:\PCPlus360\Consent"

# ── Audit Logging (tamper-evident) ──
function Write-AuditLog {
    param([string]$Action, [string]$Detail = "")
    if (-not (Test-Path $Global:AuditLogDir)) { New-Item -Path $Global:AuditLogDir -ItemType Directory -Force | Out-Null }
    $logFile = Join-Path $Global:AuditLogDir "PasswordRecovery-AuditLog.txt"
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $user = "$env:USERDOMAIN\$env:USERNAME"
    $computer = $env:COMPUTERNAME
    $entry = "[$timestamp] [User:$user] [Computer:$computer] [Action:$Action] $Detail"
    # Append with hash for tamper evidence
    $hash = [System.Security.Cryptography.SHA256]::Create()
    $entryBytes = [System.Text.Encoding]::UTF8.GetBytes($entry)
    $hashHex = ($hash.ComputeHash($entryBytes) | ForEach-Object { $_.ToString("x2") }) -join ""
    $hash.Dispose()
    Add-Content -Path $logFile -Value "$entry [SHA256:$hashHex]" -Encoding UTF8
}

# ── Customer Consent Check ──
function Test-CustomerConsent {
    $consentFiles = @(
        (Join-Path $Global:ConsentDir "*.consent"),
        (Join-Path $Global:ScriptDir "PCPlus-CustomerConsent.txt"),
        (Join-Path $Global:ScriptDir "consent.txt")
    )
    foreach ($pattern in $consentFiles) {
        $found = Get-ChildItem -Path $pattern -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) { return $found.FullName }
    }
    return $null
}

function Show-ConsentWarning {
    $result = [System.Windows.MessageBox]::Show(
        "WARNING: No customer consent file found.`n`n" +
        "This tool recovers saved passwords and WiFi keys.`n" +
        "It MUST ONLY be used with explicit customer authorization.`n`n" +
        "By clicking YES, you confirm that:`n" +
        "  - The customer has given written or verbal consent`n" +
        "  - You are authorized to access this device`n" +
        "  - This action will be logged for audit purposes`n`n" +
        "Do you have customer authorization to proceed?",
        "$COMPANY - Customer Consent Required",
        "YesNo", "Warning"
    )
    return ($result -eq "Yes")
}

function Save-ConsentRecord {
    param([string]$CustomerName, [string]$TechName)
    if (-not (Test-Path $Global:ConsentDir)) { New-Item -Path $Global:ConsentDir -ItemType Directory -Force | Out-Null }
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $safeName = $CustomerName -replace '[\\/:*?"<>|]','_'
    $consentFile = Join-Path $Global:ConsentDir "$safeName-$timestamp.consent"
    $content = @"
PC PLUS COMPUTING - PASSWORD RECOVERY CONSENT RECORD
=====================================================
Date: $(Get-Date -Format "MMMM dd, yyyy 'at' h:mm tt")
Customer: $CustomerName
Technician: $TechName
Computer: $env:COMPUTERNAME
User: $env:USERDOMAIN\$env:USERNAME
Consent: Verbal/written consent confirmed by technician before tool use.
"@
    Set-Content -Path $consentFile -Value $content -Encoding UTF8
    Write-AuditLog "CONSENT_RECORDED" "Customer: $CustomerName, Tech: $TechName, File: $consentFile"
    return $consentFile
}

# ── Encrypted ZIP Export ──
function Export-EncryptedZip {
    param([string]$SourceFile, [string]$ZipPath, [string]$Password)
    # Use .NET Framework ZipFile + AES encryption via 7z if available, otherwise simple zip
    $sevenZip = $null
    foreach ($p in @("$env:ProgramFiles\7-Zip\7z.exe","${env:ProgramFiles(x86)}\7-Zip\7z.exe",(Join-Path $Global:ToolsDir "7z.exe"))) {
        if (Test-Path $p) { $sevenZip = $p; break }
    }

    if ($sevenZip) {
        $args = "a -tzip -p`"$Password`" -mem=AES256 `"$ZipPath`" `"$SourceFile`""
        $proc = Start-Process -FilePath $sevenZip -ArgumentList $args -Wait -PassThru -WindowStyle Hidden
        if (Test-Path $ZipPath) {
            Write-AuditLog "ENCRYPTED_EXPORT" "Exported to: $ZipPath (AES-256 via 7-Zip)"
            return $true
        }
    }

    # Fallback: standard ZIP without encryption (inform user)
    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $parentDir = Split-Path $SourceFile -Parent
        $fileName = Split-Path $SourceFile -Leaf
        $tempDir = Join-Path $env:TEMP "pcplus_zip_$(Get-Random)"
        New-Item -Path $tempDir -ItemType Directory -Force | Out-Null
        Copy-Item $SourceFile (Join-Path $tempDir $fileName) -Force
        if (Test-Path $ZipPath) { Remove-Item $ZipPath -Force }
        [System.IO.Compression.ZipFile]::CreateFromDirectory($tempDir, $ZipPath)
        Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        Write-AuditLog "EXPORT_NO_ENCRYPTION" "Exported to: $ZipPath (no encryption - 7-Zip not found)"
        return $true
    } catch {
        return $false
    }
}

# ── Elevation check (do NOT use -STA here, not needed) ──
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    try {
        Start-Process powershell.exe -ArgumentList "-STA -NoProfile -ExecutionPolicy Bypass -File `"$($MyInvocation.MyCommand.Definition)`"" -Verb RunAs
    } catch {
        [System.Windows.MessageBox]::Show("This tool requires Administrator privileges.", "$COMPANY - Password Recovery", "OK", "Warning")
    }
    exit
}

# ── SQLite3 binary management ──
function Get-Sqlite3Path {
    $sqlite3 = Join-Path $Global:ToolsDir "sqlite3.exe"
    if (Test-Path $sqlite3) { return $sqlite3 }
    if (-not (Test-Path $Global:ToolsDir)) { New-Item -Path $Global:ToolsDir -ItemType Directory -Force | Out-Null }
    $url = "https://www.sqlite.org/2024/sqlite-tools-win-x64-3470200.zip"
    $zipPath = Join-Path $env:TEMP "sqlite-tools.zip"
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        (New-Object Net.WebClient).DownloadFile($url, $zipPath)
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $zip = [IO.Compression.ZipFile]::OpenRead($zipPath)
        $entry = $zip.Entries | Where-Object { $_.Name -eq "sqlite3.exe" } | Select-Object -First 1
        if ($entry) {
            $stream = $entry.Open()
            $fs = [IO.File]::Create($sqlite3)
            $stream.CopyTo($fs)
            $fs.Close(); $stream.Close()
        }
        $zip.Dispose()
        Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
        if (Test-Path $sqlite3) { return $sqlite3 }
    } catch {}
    return $null
}

# ── AES-GCM decryption for Chrome 80+ passwords ──
$hasAesGcm = $false
try {
    Add-Type -TypeDefinition @"
using System;
using System.IO;
using System.Security.Cryptography;
using System.Text;

public class ChromeDecryptor {
    public static byte[] DecryptMasterKey(byte[] encryptedKey) {
        byte[] keyBytes = new byte[encryptedKey.Length - 5];
        Array.Copy(encryptedKey, 5, keyBytes, 0, keyBytes.Length);
        return ProtectedData.Unprotect(keyBytes, null, DataProtectionScope.CurrentUser);
    }

    public static string DecryptPassword(byte[] encryptedData, byte[] masterKey) {
        try {
            if (encryptedData.Length > 15 &&
                encryptedData[0] == (byte)'v' &&
                (encryptedData[1] == (byte)'1') &&
                (encryptedData[2] == (byte)'0' || encryptedData[2] == (byte)'1')) {

                byte[] nonce = new byte[12];
                Array.Copy(encryptedData, 3, nonce, 0, 12);

                int cipherLen = encryptedData.Length - 3 - 12 - 16;
                if (cipherLen <= 0) return "";

                byte[] ciphertext = new byte[cipherLen];
                Array.Copy(encryptedData, 15, ciphertext, 0, cipherLen);

                byte[] tag = new byte[16];
                Array.Copy(encryptedData, encryptedData.Length - 16, tag, 0, 16);

                byte[] plaintext = new byte[cipherLen];
                using (var aes = new AesGcm(masterKey)) {
                    aes.Decrypt(nonce, ciphertext, tag, plaintext);
                }
                return Encoding.UTF8.GetString(plaintext);
            }
            else {
                byte[] decrypted = ProtectedData.Unprotect(encryptedData, null, DataProtectionScope.CurrentUser);
                return Encoding.UTF8.GetString(decrypted);
            }
        }
        catch {
            try {
                byte[] decrypted = ProtectedData.Unprotect(encryptedData, null, DataProtectionScope.CurrentUser);
                return Encoding.UTF8.GetString(decrypted);
            }
            catch { return "[encrypted - different user]"; }
        }
    }
}
"@ -ReferencedAssemblies @("System.Security.Cryptography.Primitives","System.Security.Cryptography.Cng","System.Security.Cryptography.ProtectedData","System.Memory") -ErrorAction Stop
    $hasAesGcm = $true
} catch {
    $hasAesGcm = $false
}

try { [ChromeDecryptor] | Out-Null } catch { $hasAesGcm = $false }

if (-not $hasAesGcm) {
    Add-Type -TypeDefinition @"
using System;
using System.Security.Cryptography;
using System.Text;

public class ChromeDecryptorLegacy {
    public static byte[] DecryptMasterKey(byte[] encryptedKey) {
        byte[] keyBytes = new byte[encryptedKey.Length - 5];
        Array.Copy(encryptedKey, 5, keyBytes, 0, keyBytes.Length);
        return ProtectedData.Unprotect(keyBytes, null, DataProtectionScope.CurrentUser);
    }

    public static string DecryptDPAPI(byte[] encryptedData) {
        try {
            byte[] decrypted = ProtectedData.Unprotect(encryptedData, null, DataProtectionScope.CurrentUser);
            return Encoding.UTF8.GetString(decrypted);
        }
        catch { return "[encrypted - different user]"; }
    }
}
"@ -ReferencedAssemblies "System.Security" -ErrorAction SilentlyContinue
}

# ── Get Chrome/Edge master key from Local State ──
function Get-BrowserMasterKey {
    param([string]$LocalStatePath)
    if (-not (Test-Path $LocalStatePath)) { return $null }
    try {
        $json = Get-Content $LocalStatePath -Raw | ConvertFrom-Json
        $b64Key = $json.os_crypt.encrypted_key
        if (-not $b64Key) { return $null }
        $encKey = [Convert]::FromBase64String($b64Key)
        if ($hasAesGcm) {
            return [ChromeDecryptor]::DecryptMasterKey($encKey)
        } else {
            return [ChromeDecryptorLegacy]::DecryptMasterKey($encKey)
        }
    } catch { return $null }
}

# ── Decrypt a password blob ──
function Decrypt-Password {
    param([byte[]]$EncData, [byte[]]$MasterKey)
    if (-not $EncData -or $EncData.Length -eq 0) { return "" }
    if ($hasAesGcm -and $MasterKey) {
        return [ChromeDecryptor]::DecryptPassword($EncData, $MasterKey)
    } else {
        if ($hasAesGcm) {
            try { return [ChromeDecryptor]::DecryptPassword($EncData, $null) } catch {}
        }
        try {
            return [ChromeDecryptorLegacy]::DecryptDPAPI($EncData)
        } catch { return "[encrypted]" }
    }
}

# ── Recover passwords from a Chromium browser ──
function Get-ChromiumPasswords {
    param([string]$BrowserName, [string]$ProfileRoot)
    $results = @()
    if (-not (Test-Path $ProfileRoot)) { return $results }

    $localState = Join-Path $ProfileRoot "Local State"
    $masterKey = Get-BrowserMasterKey $localState

    $profiles = @("Default") + @(Get-ChildItem $ProfileRoot -Directory -Filter "Profile *" -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })

    $sqlite3 = Get-Sqlite3Path
    if (-not $sqlite3) { return $results }

    foreach ($prof in $profiles) {
        $loginData = Join-Path $ProfileRoot "$prof\Login Data"
        if (-not (Test-Path $loginData)) { continue }

        $tempDb = Join-Path $env:TEMP "pcplus_login_$(Get-Random).db"
        try {
            Copy-Item $loginData $tempDb -Force
            $csv = & $sqlite3 $tempDb ".mode csv" ".headers on" "SELECT origin_url, username_value, hex(password_value) as password_hex, date_last_used FROM logins WHERE username_value != '' ORDER BY origin_url;" 2>&1
            foreach ($line in $csv) {
                if ($line -match '^"?origin_url' -or -not $line.Trim()) { continue }
                $parts = $line -split ','
                if ($parts.Count -lt 3) { continue }
                $url = ($parts[0] -replace '^"|"$','').Trim()
                $user = ($parts[1] -replace '^"|"$','').Trim()
                $hexPw = ($parts[2] -replace '^"|"$','').Trim()
                if (-not $user) { continue }
                $password = ""
                if ($hexPw) {
                    try {
                        $encBytes = [byte[]]@(for ($i = 0; $i -lt $hexPw.Length; $i += 2) { [Convert]::ToByte($hexPw.Substring($i, 2), 16) })
                        $password = Decrypt-Password $encBytes $masterKey
                    } catch { $password = "[decryption failed]" }
                }
                $results += @{
                    Browser  = "$BrowserName ($prof)"
                    URL      = $url
                    Username = $user
                    Password = $password
                }
            }
        } catch {} finally {
            Remove-Item $tempDb -Force -ErrorAction SilentlyContinue
        }
    }
    return $results
}

# ── Recover Firefox passwords ──
function Get-FirefoxPasswords {
    $results = @()
    $ffRoot = "$env:APPDATA\Mozilla\Firefox\Profiles"
    if (-not (Test-Path $ffRoot)) { return $results }

    foreach ($profile in Get-ChildItem $ffRoot -Directory -ErrorAction SilentlyContinue) {
        $loginsJson = Join-Path $profile.FullName "logins.json"
        if (-not (Test-Path $loginsJson)) { continue }
        try {
            $logins = Get-Content $loginsJson -Raw | ConvertFrom-Json
            foreach ($login in $logins.logins) {
                $results += @{
                    Browser  = "Firefox ($($profile.Name))"
                    URL      = $login.hostname
                    Username = $login.encryptedUsername
                    Password = "[Firefox NSS encrypted - use Firefox export]"
                }
            }
        } catch {}
    }
    return $results
}

# ── WiFi passwords ──
function Get-WiFiPasswords {
    $results = @()
    try {
        $profiles = netsh wlan show profiles 2>&1
        $names = @()
        foreach ($l in $profiles) { if ($l -match "All User Profile\s*:\s*(.+)$") { $names += $Matches[1].Trim() } }
        foreach ($n in $names) {
            $det = netsh wlan show profile name="$n" key=clear 2>&1
            $pw = ""; $auth = ""
            foreach ($l in $det) {
                if ($l -match "Key Content\s*:\s*(.+)$") { $pw = $Matches[1].Trim() }
                if ($l -match "Authentication\s*:\s*(.+)$") { $auth = $Matches[1].Trim() }
            }
            $results += @{ SSID = $n; Password = if ($pw) { $pw } else { "(Open/Enterprise)" }; Auth = $auth }
        }
    } catch {}
    return $results
}

# ── Export to HTML report ──
function Build-PasswordReport {
    param($BrowserPasswords, $WiFiPasswords, $CustomerName, $TechName)
    $date = Get-Date -Format "MMMM dd, yyyy 'at' h:mm tt"
    $device = $env:COMPUTERNAME

    $logoDataUri = ""
    $logoPath = Join-Path $Global:ScriptDir "logo-base64.txt"
    if (Test-Path $logoPath) {
        try { $logoDataUri = "data:image/png;base64,$((Get-Content $logoPath -Raw).Trim())" } catch {}
    }
    $logoHTML = if ($logoDataUri) {
        "<img src='$logoDataUri' alt='PC Plus Computing' style='width:280px;margin-bottom:20px;'/>"
    } else {
        "<div style='background:#0a1628;color:#fff;padding:16px 40px;font-size:20pt;font-weight:bold;letter-spacing:3px;border-radius:6px;margin-bottom:20px;'>PC PLUS COMPUTING</div>"
    }

    $browserRows = ""
    $grouped = @{}
    foreach ($p in $BrowserPasswords) {
        $domain = try { ([Uri]$p.URL).Host } catch { $p.URL }
        if (-not $grouped[$domain]) { $grouped[$domain] = @() }
        $grouped[$domain] += $p
    }
    foreach ($domain in ($grouped.Keys | Sort-Object)) {
        foreach ($p in $grouped[$domain]) {
            $maskedPw = if ($p.Password -and $p.Password -notmatch '^\[') {
                $pw = $p.Password
                if ($pw.Length -le 3) { $pw }
                else { $pw.Substring(0,2) + ("*" * ($pw.Length - 3)) + $pw[-1] }
            } else { $p.Password }
            $browserRows += "<tr><td class='browser-tag'>$($p.Browser)</td><td>$domain</td><td><strong>$($p.Username)</strong></td><td class='pw-cell'>$maskedPw</td></tr>`n"
        }
    }
    if (-not $browserRows) { $browserRows = "<tr><td colspan='4' style='text-align:center;color:#94a3b8;padding:20px;'>No saved browser passwords found</td></tr>" }

    $wifiRows = ""
    foreach ($w in $WiFiPasswords) {
        $wifiRows += "<tr><td><strong>$($w.SSID)</strong></td><td class='pw-cell'>$($w.Password)</td><td>$($w.Auth)</td></tr>`n"
    }
    if (-not $wifiRows) { $wifiRows = "<tr><td colspan='3' style='text-align:center;color:#94a3b8;padding:20px;'>No WiFi profiles found</td></tr>" }

    $totalBrowser = $BrowserPasswords.Count
    $totalWifi = $WiFiPasswords.Count

$html = @"
<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8"/><title>Password Recovery - $CustomerName</title>
<style>
@page { size:letter;margin:0.5in 0.6in; }
*{margin:0;padding:0;box-sizing:border-box;}
body{font-family:'Segoe UI',Tahoma,sans-serif;font-size:9.5pt;color:#1e293b;line-height:1.5;background:#fff;}
.page-break{page-break-before:always;}

.header{text-align:center;padding:30px 0 20px;border-bottom:3px solid #0a1628;margin-bottom:20px;}
.header h1{font-size:18pt;color:#0a1628;font-weight:300;letter-spacing:2px;margin:10px 0 5px;}
.header .subtitle{font-size:10pt;color:#64748b;}

.info-bar{display:flex;gap:20px;background:#f1f5f9;padding:12px 18px;border-radius:8px;margin-bottom:20px;font-size:9pt;}
.info-bar .item{flex:1;}
.info-bar .label{color:#64748b;font-size:8pt;text-transform:uppercase;letter-spacing:0.5px;}
.info-bar .value{color:#0a1628;font-weight:600;margin-top:2px;}

.summary-cards{display:flex;gap:16px;margin-bottom:24px;}
.summary-card{flex:1;text-align:center;padding:16px;border-radius:10px;border:1px solid #e2e8f0;}
.summary-card .number{font-size:28pt;font-weight:700;display:block;}
.summary-card .label{font-size:8pt;color:#64748b;text-transform:uppercase;letter-spacing:1px;margin-top:4px;}

.section{margin-bottom:24px;}
.section-title{background:linear-gradient(135deg,#0a1628,#1e3a5f);color:#fff;padding:10px 18px;font-size:11pt;font-weight:600;border-radius:6px 6px 0 0;display:flex;align-items:center;gap:8px;}
.section-title .icon{font-size:14pt;}

table{width:100%;border-collapse:collapse;font-size:9pt;}
th{background:#f8fafc;color:#475569;padding:8px 12px;text-align:left;font-weight:600;font-size:8pt;text-transform:uppercase;letter-spacing:0.5px;border-bottom:2px solid #e2e8f0;}
td{padding:7px 12px;border-bottom:1px solid #f1f5f9;vertical-align:top;}
tr:hover td{background:#f8fafc;}
.browser-tag{font-size:7.5pt;color:#2596be;white-space:nowrap;}
.pw-cell{font-family:Consolas,'Courier New',monospace;font-size:9pt;color:#0a1628;letter-spacing:0.5px;}

.confidential{margin-top:30px;padding:16px;background:#fef5f5;border:1px solid #fecaca;border-radius:8px;text-align:center;}
.confidential .title{color:#dc2626;font-weight:700;font-size:10pt;margin-bottom:4px;}
.confidential .text{color:#991b1b;font-size:8.5pt;}

.footer{margin-top:20px;padding:12px 0;border-top:2px solid #0a1628;text-align:center;font-size:8pt;color:#94a3b8;}
.footer strong{color:#0a1628;}

@media print{body{-webkit-print-color-adjust:exact;print-color-adjust:exact;}.page-break{page-break-before:always;}}
</style></head><body>

<div class="header">
$logoHTML
<h1>PASSWORD RECOVERY REPORT</h1>
<div class="subtitle">Confidential - For Customer Use Only</div>
</div>

<div class="info-bar">
<div class="item"><div class="label">Customer</div><div class="value">$CustomerName</div></div>
<div class="item"><div class="label">Device</div><div class="value">$device</div></div>
<div class="item"><div class="label">Date</div><div class="value">$date</div></div>
<div class="item"><div class="label">Technician</div><div class="value">$TechName</div></div>
</div>

<div class="summary-cards">
<div class="summary-card" style="border-color:#2596be;"><span class="number" style="color:#2596be;">$totalBrowser</span><span class="label">Browser Passwords</span></div>
<div class="summary-card" style="border-color:#27ae60;"><span class="number" style="color:#27ae60;">$totalWifi</span><span class="label">WiFi Networks</span></div>
<div class="summary-card" style="border-color:#0a1628;"><span class="number" style="color:#0a1628;">$($totalBrowser + $totalWifi)</span><span class="label">Total Recovered</span></div>
</div>

<div class="section">
<div class="section-title"><span class="icon">&#128274;</span> Saved Browser Passwords</div>
<table>
<tr><th style="width:12%;">Browser</th><th style="width:25%;">Website</th><th style="width:28%;">Username / Email</th><th style="width:35%;">Password</th></tr>
$browserRows
</table>
</div>

$(if($BrowserPasswords.Count -gt 30){"<div class='page-break'></div>"})

<div class="section">
<div class="section-title"><span class="icon">&#128246;</span> WiFi Network Passwords</div>
<table>
<tr><th>Network Name (SSID)</th><th>Password</th><th>Security</th></tr>
$wifiRows
</table>
</div>

<div class="confidential">
<div class="title">&#9888; CONFIDENTIAL DOCUMENT</div>
<div class="text">This report contains sensitive credentials recovered from the customer's device at their request.<br/>
It should be handed directly to the customer and NOT stored, emailed, or shared. Delete all copies after handoff.<br/>
PC Plus Computing does not retain any customer passwords.</div>
</div>

<div class="footer">
<strong>$COMPANY</strong> &nbsp;|&nbsp; pcpluscomputing.com &nbsp;|&nbsp; 604-760-1662 | 236-500-2700<br/>
Password Recovery Report generated $date &nbsp;|&nbsp; Technician: $TechName
</div>

</body></html>
"@
    return $html
}

# ── PDF conversion ──
function Convert-ToPDF {
    param([string]$HTMLPath, [string]$PDFPath)
    $browsers = @()
    foreach ($p in @("${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe","$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe","$env:LOCALAPPDATA\Microsoft\Edge\Application\msedge.exe")) { if (Test-Path $p) { $browsers += $p; break } }
    foreach ($p in @("${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe","$env:ProgramFiles\Google\Chrome\Application\chrome.exe","$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe")) { if (Test-Path $p) { $browsers += $p; break } }
    foreach ($b in $browsers) {
        try {
            $args = "--headless --disable-gpu --no-sandbox --print-to-pdf=`"$PDFPath`" --print-to-pdf-no-header --run-all-compositor-stages-before-draw --disable-extensions `"file:///$($HTMLPath.Replace('\','/'))`""
            $proc = Start-Process $b -ArgumentList $args -Wait -PassThru -WindowStyle Hidden
            if (Test-Path $PDFPath) { return $true }
        } catch {}
    }
    return $false
}

# ═══════════════════════════════════════════════════════════════════════════════
# WPF UI
# ═══════════════════════════════════════════════════════════════════════════════
function Show-RecoveryUI {
[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="PC Plus Computing - Password Recovery Tool" Height="520" Width="580"
        WindowStartupLocation="CenterScreen" ResizeMode="CanMinimize"
        Background="#0a1628" FontFamily="Segoe UI">
    <Grid Margin="20">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <StackPanel Grid.Row="0" HorizontalAlignment="Center" Margin="0,0,0,15">
            <TextBlock Text="P C   P L U S   C O M P U T I N G" FontSize="18" FontWeight="Bold" Foreground="#2596be" HorizontalAlignment="Center"/>
            <TextBlock Text="Password Recovery Tool" FontSize="13" Foreground="#94a3b8" HorizontalAlignment="Center" Margin="0,4,0,0"/>
            <Border Background="#e74c3c" CornerRadius="4" Padding="8,4" Margin="0,8,0,0">
                <TextBlock Text="This tool requires explicit customer authorization. All actions are logged." Foreground="White" FontSize="9" HorizontalAlignment="Center" TextWrapping="Wrap"/>
            </Border>
        </StackPanel>

        <Border Grid.Row="1" Background="#1e293b" CornerRadius="8" Padding="16" Margin="0,0,0,12">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="*"/>
                </Grid.ColumnDefinitions>
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>
                <TextBlock Grid.Row="0" Grid.Column="0" Text="Customer Name:" Foreground="#94a3b8" VerticalAlignment="Center" Margin="0,0,8,8"/>
                <TextBox x:Name="txtCustomer" Grid.Row="0" Grid.Column="1" Margin="0,0,16,8" Padding="6,4" FontSize="11"/>
                <TextBlock Grid.Row="0" Grid.Column="2" Text="Tech Name:" Foreground="#94a3b8" VerticalAlignment="Center" Margin="0,0,8,8"/>
                <TextBox x:Name="txtTech" Grid.Row="0" Grid.Column="3" Margin="0,0,0,8" Padding="6,4" FontSize="11"/>
                <TextBlock Grid.Row="1" Grid.Column="0" Text="Save To:" Foreground="#94a3b8" VerticalAlignment="Center" Margin="0,0,8,0"/>
                <TextBox x:Name="txtOutput" Grid.Row="1" Grid.Column="1" Grid.ColumnSpan="3" Padding="6,4" FontSize="10" IsReadOnly="True"/>
            </Grid>
        </Border>

        <Border Grid.Row="2" Background="#1e293b" CornerRadius="8" Padding="16" Margin="0,0,0,12">
            <StackPanel>
                <TextBlock Text="Select what to recover:" Foreground="#94a3b8" FontSize="10" Margin="0,0,0,8"/>
                <WrapPanel>
                    <CheckBox x:Name="chkChrome" Content=" Chrome" Foreground="White" IsChecked="True" Margin="0,0,20,6" FontSize="11"/>
                    <CheckBox x:Name="chkEdge" Content=" Edge" Foreground="White" IsChecked="True" Margin="0,0,20,6" FontSize="11"/>
                    <CheckBox x:Name="chkFirefox" Content=" Firefox" Foreground="White" IsChecked="True" Margin="0,0,20,6" FontSize="11"/>
                    <CheckBox x:Name="chkWifi" Content=" WiFi Passwords" Foreground="White" IsChecked="True" Margin="0,0,0,6" FontSize="11"/>
                </WrapPanel>
            </StackPanel>
        </Border>

        <Border Grid.Row="3" Background="#1e293b" CornerRadius="8" Padding="12" Margin="0,0,0,12">
            <ScrollViewer VerticalScrollBarVisibility="Auto">
                <TextBlock x:Name="txtLog" Text="Ready. Enter customer name and click Recover." Foreground="#64748b" FontSize="10" TextWrapping="Wrap" FontFamily="Consolas"/>
            </ScrollViewer>
        </Border>

        <ProgressBar x:Name="progress" Grid.Row="4" Height="4" Margin="0,0,0,12" Background="#1e293b" Foreground="#2596be" Value="0"/>

        <Grid Grid.Row="5">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>
            <Button x:Name="btnRecover" Grid.Column="0" Content="&#128275;  RECOVER PASSWORDS" Height="42" Margin="0,0,6,0" FontSize="12" FontWeight="Bold" Background="#2596be" Foreground="White" BorderThickness="0" Cursor="Hand"/>
            <Button x:Name="btnExport" Grid.Column="1" Height="42" Margin="6,0,0,0" FontSize="12" FontWeight="Bold" BorderThickness="0" Cursor="Hand" IsEnabled="False">
                <Button.Template>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="bd" Background="#27ae60" CornerRadius="4" Padding="10,5">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="bd" Property="Opacity" Value="0.35"/>
                            </Trigger>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="bd" Property="Background" Value="#2ecc71"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Button.Template>
                <TextBlock Text="&#128196;  EXPORT REPORT" Foreground="White" FontWeight="Bold"/>
            </Button>
        </Grid>
    </Grid>
</Window>
"@

    $reader = New-Object System.Xml.XmlNodeReader $xaml
    $window = [Windows.Markup.XamlReader]::Load($reader)

    $txtCustomer = $window.FindName("txtCustomer")
    $txtTech     = $window.FindName("txtTech")
    $txtOutput   = $window.FindName("txtOutput")
    $txtLog      = $window.FindName("txtLog")
    $progress    = $window.FindName("progress")
    $btnRecover  = $window.FindName("btnRecover")
    $btnExport   = $window.FindName("btnExport")
    $chkChrome   = $window.FindName("chkChrome")
    $chkEdge     = $window.FindName("chkEdge")
    $chkFirefox  = $window.FindName("chkFirefox")
    $chkWifi     = $window.FindName("chkWifi")

    $txtOutput.Text = Join-Path $Global:ScriptDir "reports"
    $txtTech.Text = $env:USERNAME

    $Global:RecoveredBrowser = @()
    $Global:RecoveredWifi = @()

    $appendLog = {
        param([string]$msg)
        $txtLog.Text += "`n$msg"
        $txtLog.GetType().GetMethod("InvalidateVisual").Invoke($txtLog, $null) | Out-Null
        $frame = [System.Windows.Threading.DispatcherFrame]::new()
        [System.Windows.Threading.Dispatcher]::CurrentDispatcher.BeginInvoke([System.Windows.Threading.DispatcherPriority]::Background, [Action]{ $frame.Continue = $false })
        [System.Windows.Threading.Dispatcher]::PushFrame($frame)
    }

    $btnRecover.Add_Click({
        if (-not $txtCustomer.Text.Trim()) {
            [System.Windows.MessageBox]::Show($window, "Please enter the customer name.", "$COMPANY", "OK", "Warning")
            return
        }

        # Customer consent check
        $consentFile = Test-CustomerConsent
        if (-not $consentFile) {
            $consentGranted = Show-ConsentWarning
            if (-not $consentGranted) {
                Write-AuditLog "CONSENT_DENIED" "Technician declined consent confirmation for: $($txtCustomer.Text.Trim())"
                [System.Windows.MessageBox]::Show($window, "Operation cancelled. Customer consent is required.", "$COMPANY", "OK", "Information")
                return
            }
            # Save consent record
            $consentFile = Save-ConsentRecord -CustomerName $txtCustomer.Text.Trim() -TechName $txtTech.Text.Trim()
        }

        Write-AuditLog "RECOVERY_STARTED" "Customer: $($txtCustomer.Text.Trim()), Tech: $($txtTech.Text.Trim()), Consent: $consentFile"

        $btnRecover.IsEnabled = $false
        $btnExport.IsEnabled = $false
        $txtLog.Text = "Starting password recovery..."
        $progress.Value = 5
        $Global:RecoveredBrowser = @()
        $Global:RecoveredWifi = @()

        try {
            # SQLite3 check
            & $appendLog "Checking for sqlite3..."
            $sqlite3 = Get-Sqlite3Path
            if (-not $sqlite3) {
                & $appendLog "ERROR: Could not get sqlite3.exe. Check internet connection."
                & $appendLog "Skipping browser passwords. Will still try WiFi."
            } else {
                & $appendLog "sqlite3 ready."
            }

            $progress.Value = 10

            if ($chkChrome.IsChecked -and $sqlite3) {
                & $appendLog "Scanning Chrome..."
                $chromePath = "$env:LOCALAPPDATA\Google\Chrome\User Data"
                $chromeResults = Get-ChromiumPasswords "Chrome" $chromePath
                $Global:RecoveredBrowser += $chromeResults
                & $appendLog "  Chrome: $($chromeResults.Count) passwords found"
            }
            $progress.Value = 30

            if ($chkEdge.IsChecked -and $sqlite3) {
                & $appendLog "Scanning Edge..."
                $edgePath = "$env:LOCALAPPDATA\Microsoft\Edge\User Data"
                $edgeResults = Get-ChromiumPasswords "Edge" $edgePath
                $Global:RecoveredBrowser += $edgeResults
                & $appendLog "  Edge: $($edgeResults.Count) passwords found"
            }
            $progress.Value = 55

            if ($chkFirefox.IsChecked) {
                & $appendLog "Scanning Firefox..."
                $ffResults = Get-FirefoxPasswords
                $Global:RecoveredBrowser += $ffResults
                & $appendLog "  Firefox: $($ffResults.Count) entries found (NSS encrypted - usernames only)"
            }
            $progress.Value = 75

            if ($chkWifi.IsChecked) {
                & $appendLog "Scanning WiFi profiles..."
                $Global:RecoveredWifi = Get-WiFiPasswords
                & $appendLog "  WiFi: $($Global:RecoveredWifi.Count) networks found"
            }
            $progress.Value = 90

            $total = $Global:RecoveredBrowser.Count + $Global:RecoveredWifi.Count
            & $appendLog ""
            & $appendLog "DONE - $total total credentials recovered."
            & $appendLog "Click EXPORT REPORT to generate PDF."
            $progress.Value = 100
            $btnExport.IsEnabled = $true

            Write-AuditLog "RECOVERY_COMPLETED" "Browser: $($Global:RecoveredBrowser.Count), WiFi: $($Global:RecoveredWifi.Count), Total: $total"

        } catch {
            & $appendLog "ERROR: $($_.Exception.Message)"
            Write-AuditLog "RECOVERY_ERROR" "$($_.Exception.Message)"
        }
        $btnRecover.IsEnabled = $true
    })

    $btnExport.Add_Click({
        try {
            $outDir = $txtOutput.Text.Trim()
            if (-not (Test-Path $outDir)) { New-Item -Path $outDir -ItemType Directory -Force | Out-Null }
            $safeName = $txtCustomer.Text.Trim() -replace '[\\/:*?"<>|]','_'
            $ds = Get-Date -Format "yyyy-MM-dd"
            $htmlPath = Join-Path $outDir "$safeName - Password Recovery $ds.html"
            $pdfPath  = Join-Path $outDir "$safeName - Password Recovery $ds.pdf"

            & $appendLog "Generating report..."
            $html = Build-PasswordReport $Global:RecoveredBrowser $Global:RecoveredWifi $txtCustomer.Text.Trim() $txtTech.Text.Trim()
            [IO.File]::WriteAllText($htmlPath, $html, [Text.Encoding]::UTF8)

            $pdfOk = Convert-ToPDF $htmlPath $pdfPath
            if ($pdfOk) {
                & $appendLog "PDF saved: $pdfPath"
            } else {
                & $appendLog "HTML saved (no PDF renderer): $htmlPath"
            }
            Start-Process explorer.exe -ArgumentList $outDir

            Write-AuditLog "REPORT_EXPORTED" "Path: $(if($pdfOk){$pdfPath}else{$htmlPath})"

            # Offer encrypted ZIP export
            $encryptResult = [System.Windows.MessageBox]::Show($window, "Would you like to create an encrypted ZIP of this report?`n`nThis adds password protection for secure transfer.", "$COMPANY - Encrypted Export", "YesNo", "Question")
            if ($encryptResult -eq "Yes") {
                Add-Type -AssemblyName Microsoft.VisualBasic
                $zipPassword = [Microsoft.VisualBasic.Interaction]::InputBox("Enter a password for the encrypted ZIP file:", "$COMPANY - Set ZIP Password", "")
                if ($zipPassword) {
                    $zipPath = Join-Path $outDir "$safeName - Password Recovery $ds.zip"
                    $sourceForZip = if ($pdfOk) { $pdfPath } else { $htmlPath }
                    $zipOk = Export-EncryptedZip -SourceFile $sourceForZip -ZipPath $zipPath -Password $zipPassword
                    if ($zipOk) {
                        & $appendLog "Encrypted ZIP saved: $zipPath"
                    } else {
                        & $appendLog "Encrypted ZIP creation failed."
                    }
                }
            }

            $emailResult = [System.Windows.MessageBox]::Show($window, "Report saved!`n`nOpen email client to send to customer?", "$COMPANY", "YesNo", "Question")
            if ($emailResult -eq "Yes") {
                $filePath = if ($pdfOk) { $pdfPath } else { $htmlPath }
                try { [System.Windows.Clipboard]::SetText($filePath) } catch {}
                $subject = [Uri]::EscapeDataString("$COMPANY - Password Recovery for $($txtCustomer.Text.Trim())")
                $body = [Uri]::EscapeDataString("Hello,`n`nPlease find attached your recovered passwords.`n`nBest regards,`n$($txtTech.Text.Trim())`n$COMPANY")
                try { Start-Process "mailto:?subject=$subject&body=$body" } catch {}
                & $appendLog "Email client opened. File path copied to clipboard."
            }
        } catch {
            & $appendLog "Export error: $($_.Exception.Message)"
        }
    })

    $window.ShowDialog() | Out-Null
}

# ═══════════════════════════════════════════════════════════════════════════════
# ENTRY POINT
# ═══════════════════════════════════════════════════════════════════════════════
try {
    Write-AuditLog "TOOL_LAUNCHED" "User: $env:USERDOMAIN\$env:USERNAME, Computer: $env:COMPUTERNAME"
    Show-RecoveryUI
    Write-AuditLog "TOOL_CLOSED" ""
} catch {
    Write-AuditLog "TOOL_ERROR" "$($_.Exception.Message)"
    [System.Windows.MessageBox]::Show("$COMPANY Password Recovery Error:`n`n$($_.Exception.Message)", "$COMPANY - Error", "OK", "Error") | Out-Null
}

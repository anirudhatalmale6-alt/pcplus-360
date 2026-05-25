<#
.SYNOPSIS
    PC Plus Computing 360 - Customer Consent & Intake Form
.DESCRIPTION
    Professional customer consent and intake workflow for computer repair shops.
    Captures customer information, consent for diagnostic/repair work, digital
    handwritten signature via WPF InkCanvas, and generates both HTML and JSON
    records with embedded signature image and SHA256 tamper-detection hash.
    Creates a lock file that subsequent tools check before running repairs.
.NOTES
    Company:  PC Plus Computing
    Phone:    604-760-1662 | 236-500-2700
    Website:  pcpluscomputing.com
    Version:  2.0.0
    Requires: PowerShell 5.1+, .NET Framework 4.x, Windows 10/11
    Part of:  PC Plus 360 USB Diagnostic Toolkit
.EXAMPLE
    PowerShell.exe -ExecutionPolicy Bypass -File .\PCPlus-CustomerConsent.ps1
#>

#Requires -Version 5.1

$ErrorActionPreference = 'Continue'

# ─────────────────────────────────────────────────────────────────────────────
# ASSEMBLIES & VISUAL STYLES
# ─────────────────────────────────────────────────────────────────────────────
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName WindowsFormsIntegration
Add-Type -AssemblyName System.Security
[System.Windows.Forms.Application]::EnableVisualStyles()

# ─────────────────────────────────────────────────────────────────────────────
# BRANDING CONSTANTS
# ─────────────────────────────────────────────────────────────────────────────
$COMPANY_NAME    = "PC Plus Computing"
$COMPANY_FULL    = "PC Plus Computing 360"
$COMPANY_WEBSITE = "pcpluscomputing.com"
$COMPANY_PHONE1  = "604-760-1662"
$COMPANY_PHONE2  = "236-500-2700"
$COLOR_NAVY      = "#0a1628"
$COLOR_CARD_BG   = "#111d2e"
$COLOR_ACCENT    = "#2596be"
$COLOR_GREEN     = "#27ae60"
$COLOR_RED       = "#e74c3c"
$COLOR_ORANGE    = "#f39c12"
$COLOR_LIGHT_BG  = "#f8f9fa"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
if ([string]::IsNullOrEmpty($ScriptDir)) { $ScriptDir = Get-Location }
$ReportsDir = Join-Path $ScriptDir "reports"
if (-not (Test-Path $ReportsDir)) { New-Item -Path $ReportsDir -ItemType Directory -Force | Out-Null }

# ─────────────────────────────────────────────────────────────────────────────
# WORK ORDER NUMBER GENERATOR
# ─────────────────────────────────────────────────────────────────────────────
function New-WorkOrderNumber {
    $datePart = Get-Date -Format "yyyyMMdd"
    $existingOrders = @()
    try {
        $existingOrders = Get-ChildItem -Path $ReportsDir -Filter "Consent-PCPLUS-${datePart}-*.json" -ErrorAction SilentlyContinue
    } catch {}
    $seq = $existingOrders.Count + 1
    $seqStr = $seq.ToString("0000")
    return "PCPLUS-${datePart}-${seqStr}"
}

# ─────────────────────────────────────────────────────────────────────────────
# CONSENT LOCK FILE MANAGEMENT
# ─────────────────────────────────────────────────────────────────────────────
function Save-ConsentLock {
    param(
        [string]$WorkOrderNumber,
        [string]$CustomerName,
        [hashtable]$Consents
    )
    $lockPath = Join-Path $ScriptDir ".consent-lock"
    $lockData = @{
        WorkOrderNumber = $WorkOrderNumber
        CustomerName    = $CustomerName
        Timestamp       = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        ComputerName    = $env:COMPUTERNAME
        ConsentDiag     = $Consents.Diagnostic
        ConsentRepair   = $Consents.Repair
        ConsentBackup   = $Consents.Backup
        ConsentRestore  = $Consents.RestorePoint
        ConsentAccess   = $Consents.AccessSettings
        Valid           = $true
    }
    $lockData | ConvertTo-Json -Depth 5 | Set-Content -Path $lockPath -Encoding UTF8 -Force
    return $lockPath
}

function Test-ConsentLock {
    $lockPath = Join-Path $ScriptDir ".consent-lock"
    if (-not (Test-Path $lockPath)) { return $false }
    try {
        $lock = Get-Content -Path $lockPath -Raw -ErrorAction Stop | ConvertFrom-Json
        return ($lock.Valid -eq $true)
    } catch {
        return $false
    }
}

function Get-ConsentLockInfo {
    $lockPath = Join-Path $ScriptDir ".consent-lock"
    if (-not (Test-Path $lockPath)) { return $null }
    try {
        return (Get-Content -Path $lockPath -Raw -ErrorAction Stop | ConvertFrom-Json)
    } catch {
        return $null
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# HTML REPORT GENERATION
# ─────────────────────────────────────────────────────────────────────────────
function New-ConsentHtmlReport {
    param(
        [hashtable]$FormData
    )

    $consentItems = @(
        @{ Label = "Diagnostic scanning of this computer"; Checked = $FormData.ConsentDiagnostic }
        @{ Label = "Software repairs and optimization"; Checked = $FormData.ConsentRepair }
        @{ Label = "Data backup if needed"; Checked = $FormData.ConsentBackup }
        @{ Label = "Restore point creation before any changes"; Checked = $FormData.ConsentRestorePoint }
        @{ Label = "PC Plus Computing access to system settings"; Checked = $FormData.ConsentAccessSettings }
    )

    $consentRowsHtml = ""
    foreach ($item in $consentItems) {
        $icon = if ($item.Checked) { "&#10004;" } else { "&#10008;" }
        $color = if ($item.Checked) { $COLOR_GREEN } else { $COLOR_RED }
        $status = if ($item.Checked) { "GRANTED" } else { "NOT GRANTED" }
        $consentRowsHtml += @"
            <tr>
                <td style="padding: 10px 15px; border-bottom: 1px solid #1e2d45;">
                    <span style="color: $color; font-size: 18px; margin-right: 10px;">$icon</span>
                    $($item.Label)
                </td>
                <td style="padding: 10px 15px; border-bottom: 1px solid #1e2d45; text-align: center;">
                    <span style="background: $color; color: white; padding: 3px 12px; border-radius: 12px; font-size: 12px; font-weight: bold;">$status</span>
                </td>
            </tr>
"@
    }

    $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Customer Consent Form - $($FormData.WorkOrderNumber)</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: ${COLOR_NAVY};
            color: #e0e0e0;
            line-height: 1.6;
        }
        .container {
            max-width: 800px;
            margin: 0 auto;
            padding: 20px;
        }
        .header {
            background: linear-gradient(135deg, ${COLOR_NAVY} 0%, #142238 100%);
            border: 2px solid ${COLOR_ACCENT};
            border-radius: 12px;
            padding: 30px;
            text-align: center;
            margin-bottom: 25px;
        }
        .header h1 {
            color: ${COLOR_ACCENT};
            font-size: 28px;
            margin-bottom: 5px;
        }
        .header h2 {
            color: #8899aa;
            font-size: 16px;
            font-weight: 400;
        }
        .section {
            background: #0f1f35;
            border: 1px solid #1e2d45;
            border-radius: 10px;
            padding: 25px;
            margin-bottom: 20px;
        }
        .section-title {
            color: ${COLOR_ACCENT};
            font-size: 18px;
            font-weight: 600;
            margin-bottom: 15px;
            padding-bottom: 8px;
            border-bottom: 2px solid ${COLOR_ACCENT};
        }
        .info-grid {
            display: grid;
            grid-template-columns: 1fr 1fr;
            gap: 12px;
        }
        .info-item {
            padding: 8px 0;
        }
        .info-label {
            color: #8899aa;
            font-size: 12px;
            text-transform: uppercase;
            letter-spacing: 1px;
        }
        .info-value {
            color: #ffffff;
            font-size: 16px;
            font-weight: 500;
            margin-top: 3px;
        }
        .consent-table {
            width: 100%;
            border-collapse: collapse;
        }
        .consent-table td {
            color: #e0e0e0;
            font-size: 14px;
        }
        .signature-section {
            background: #0f1f35;
            border: 2px solid ${COLOR_ACCENT};
            border-radius: 10px;
            padding: 25px;
            margin-bottom: 20px;
        }
        .signature-box {
            background: #1a2a40;
            border: 1px dashed #3a4a5a;
            border-radius: 8px;
            padding: 20px;
            text-align: center;
            margin-top: 15px;
        }
        .signature-name {
            color: ${COLOR_ACCENT};
            font-size: 24px;
            font-style: italic;
            font-family: 'Georgia', serif;
        }
        .signature-date {
            color: #8899aa;
            font-size: 12px;
            margin-top: 8px;
        }
        .work-order-badge {
            display: inline-block;
            background: ${COLOR_ACCENT};
            color: white;
            padding: 8px 20px;
            border-radius: 20px;
            font-size: 14px;
            font-weight: 700;
            letter-spacing: 1px;
            margin-top: 10px;
        }
        .footer {
            text-align: center;
            padding: 20px;
            color: #5a6a7a;
            font-size: 12px;
            border-top: 1px solid #1e2d45;
            margin-top: 30px;
        }
        .device-desc {
            background: #1a2a40;
            border: 1px solid #1e2d45;
            border-radius: 6px;
            padding: 12px 15px;
            color: #e0e0e0;
            font-size: 14px;
            margin-top: 5px;
            white-space: pre-wrap;
        }
        .legal-text {
            color: #7a8a9a;
            font-size: 11px;
            line-height: 1.5;
            margin-top: 15px;
            padding: 15px;
            background: #0a1628;
            border-radius: 6px;
            border: 1px solid #1e2d45;
        }
        @media print {
            body { background: white; color: #333; }
            .container { max-width: 100%; }
            .header { border-color: #2596be; background: white; }
            .header h1 { color: #0a1628; }
            .section { background: #f8f9fa; border-color: #ddd; }
            .section-title { color: #0a1628; border-color: #2596be; }
            .info-label { color: #666; }
            .info-value { color: #333; }
            .consent-table td { color: #333; }
            .signature-section { background: #f8f9fa; border-color: #2596be; }
            .signature-box { background: white; border-color: #999; }
            .signature-name { color: #0a1628; }
            .device-desc { background: #f0f0f0; color: #333; border-color: #ddd; }
            .legal-text { background: #f8f9fa; color: #666; border-color: #ddd; }
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>$COMPANY_FULL</h1>
            <h2>Customer Consent &amp; Service Authorization Form</h2>
            <div class="work-order-badge">$($FormData.WorkOrderNumber)</div>
        </div>

        <div class="section">
            <div class="section-title">Customer Information</div>
            <div class="info-grid">
                <div class="info-item">
                    <div class="info-label">Customer Name</div>
                    <div class="info-value">$([System.Web.HttpUtility]::HtmlEncode($FormData.CustomerName))</div>
                </div>
                <div class="info-item">
                    <div class="info-label">Phone Number</div>
                    <div class="info-value">$([System.Web.HttpUtility]::HtmlEncode($FormData.CustomerPhone))</div>
                </div>
                <div class="info-item">
                    <div class="info-label">Email Address</div>
                    <div class="info-value">$([System.Web.HttpUtility]::HtmlEncode($FormData.CustomerEmail))</div>
                </div>
                <div class="info-item">
                    <div class="info-label">Date &amp; Time</div>
                    <div class="info-value">$($FormData.DateTime)</div>
                </div>
            </div>
        </div>

        <div class="section">
            <div class="section-title">Device Description</div>
            <div class="device-desc">$([System.Web.HttpUtility]::HtmlEncode($FormData.DeviceDescription))</div>
        </div>

        <div class="section">
            <div class="section-title">Service Authorization &amp; Consent</div>
            <table class="consent-table">
                $consentRowsHtml
            </table>
        </div>

        <div class="section">
            <div class="section-title">Service Details</div>
            <div class="info-grid">
                <div class="info-item">
                    <div class="info-label">Technician</div>
                    <div class="info-value">$([System.Web.HttpUtility]::HtmlEncode($FormData.TechnicianName))</div>
                </div>
                <div class="info-item">
                    <div class="info-label">Computer Name</div>
                    <div class="info-value">$($FormData.ComputerName)</div>
                </div>
            </div>
        </div>

        <div class="signature-section">
            <div class="section-title">Digital Signature</div>
            <p style="color: #8899aa; font-size: 13px;">
                By signing below, the customer acknowledges and agrees to the
                authorizations indicated above and understands that a system restore point will
                be created prior to any modifications.
            </p>
            <div class="signature-box">
                <div style="color: #8899aa; font-size: 11px; text-transform: uppercase; margin-bottom: 8px;">Handwritten Signature</div>
                $(if ($FormData.SignatureBase64) {
                    "<img src=`"data:image/png;base64,$($FormData.SignatureBase64)`" alt=`"Customer Signature`" style=`"max-width: 480px; height: auto; border: 1px solid #3a4a5a; border-radius: 4px; background: #ffffff;`" />"
                } else {
                    "<div class=`"signature-name`">$([System.Web.HttpUtility]::HtmlEncode($FormData.DigitalSignature))</div>"
                })
                <div style="color: #8899aa; font-size: 11px; margin-top: 10px;">Typed Name: <strong style="color: #e0e0e0;">$([System.Web.HttpUtility]::HtmlEncode($FormData.DigitalSignature))</strong></div>
                <div class="signature-date">Signed electronically on $($FormData.DateTime)</div>
            </div>
            <div class="legal-text">
                This consent form authorizes $COMPANY_NAME to perform the services indicated above
                on the customer's device. All work is performed on a best-effort basis. $COMPANY_NAME
                is not liable for pre-existing hardware failures, data loss due to failing drives, or
                issues caused by third-party software. A system restore point will be created before
                any system modifications. The customer may revoke consent at any time by contacting
                $COMPANY_NAME at $COMPANY_PHONE1 or $COMPANY_PHONE2.
            </div>
        </div>

        <div class="section" style="background: #0a1020; border: 1px solid #1e2d45;">
            <div class="section-title" style="font-size: 14px;">Document Integrity</div>
            <div style="font-family: 'Consolas', 'Courier New', monospace; font-size: 11px; color: #6a8a5a; word-break: break-all;">
                SHA-256: $($FormData.ContentHash)
            </div>
            <div style="color: #5a6a7a; font-size: 10px; margin-top: 5px;">
                This hash can be used to verify that this consent form has not been altered after signing.
            </div>
        </div>

        <div class="footer">
            <p>$COMPANY_NAME &nbsp;|&nbsp; $COMPANY_PHONE1 &nbsp;|&nbsp; $COMPANY_PHONE2 &nbsp;|&nbsp; $COMPANY_WEBSITE</p>
            <p style="margin-top: 5px;">Work Order: $($FormData.WorkOrderNumber) &nbsp;|&nbsp; Generated: $($FormData.DateTime)</p>
        </div>
    </div>
</body>
</html>
"@
    return $html
}

# ─────────────────────────────────────────────────────────────────────────────
# JSON EXPORT
# ─────────────────────────────────────────────────────────────────────────────
function Save-ConsentJson {
    param(
        [hashtable]$FormData,
        [string]$OutputPath
    )
    $jsonObj = [ordered]@{
        ToolName          = "CustomerConsent"
        Version           = "2.0.0"
        WorkOrderNumber   = $FormData.WorkOrderNumber
        ComputerName      = $FormData.ComputerName
        DateTime          = $FormData.DateTime
        TimestampUTC      = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        Customer          = [ordered]@{
            Name          = $FormData.CustomerName
            Phone         = $FormData.CustomerPhone
            Email         = $FormData.CustomerEmail
        }
        DeviceDescription = $FormData.DeviceDescription
        Consents          = [ordered]@{
            Diagnostic    = $FormData.ConsentDiagnostic
            Repair        = $FormData.ConsentRepair
            Backup        = $FormData.ConsentBackup
            RestorePoint  = $FormData.ConsentRestorePoint
            AccessSettings = $FormData.ConsentAccessSettings
        }
        DigitalSignature  = $FormData.DigitalSignature
        SignatureImageFile = $FormData.SignatureImageFile
        TechnicianName    = $FormData.TechnicianName
        ContentHash       = $FormData.ContentHash
        AllConsentsGranted = (
            $FormData.ConsentDiagnostic -and
            $FormData.ConsentRepair -and
            $FormData.ConsentBackup -and
            $FormData.ConsentRestorePoint -and
            $FormData.ConsentAccessSettings
        )
    }
    $jsonObj | ConvertTo-Json -Depth 5 | Set-Content -Path $OutputPath -Encoding UTF8 -Force
}

# ─────────────────────────────────────────────────────────────────────────────
# VALIDATION HELPERS
# ─────────────────────────────────────────────────────────────────────────────
function Test-EmailFormat {
    param([string]$Email)
    if ([string]::IsNullOrWhiteSpace($Email)) { return $true }  # Email is optional
    return ($Email -match '^[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}$')
}

function Test-PhoneFormat {
    param([string]$Phone)
    if ([string]::IsNullOrWhiteSpace($Phone)) { return $false }
    $digits = $Phone -replace '[^0-9]', ''
    return ($digits.Length -ge 7)
}

# ─────────────────────────────────────────────────────────────────────────────
# INKCANVAS SIGNATURE HELPERS
# ─────────────────────────────────────────────────────────────────────────────
function Save-InkCanvasToPng {
    param(
        [System.Windows.Controls.InkCanvas]$InkCanvas,
        [string]$FilePath
    )
    # Use the full canvas dimensions for a clean capture
    $canvasWidth  = [int]$InkCanvas.ActualWidth
    $canvasHeight = [int]$InkCanvas.ActualHeight
    if ($canvasWidth  -lt 1) { $canvasWidth  = 500 }
    if ($canvasHeight -lt 1) { $canvasHeight = 150 }

    # Render InkCanvas to a RenderTargetBitmap
    $dpiX = 96
    $dpiY = 96
    $rtb = New-Object System.Windows.Media.Imaging.RenderTargetBitmap(
        $canvasWidth, $canvasHeight, $dpiX, $dpiY,
        [System.Windows.Media.PixelFormats]::Pbgra32
    )
    # Force layout so ActualWidth/Height are valid
    $InkCanvas.Measure(
        (New-Object System.Windows.Size($canvasWidth, $canvasHeight))
    )
    $InkCanvas.Arrange(
        (New-Object System.Windows.Rect(0, 0, $canvasWidth, $canvasHeight))
    )
    $rtb.Render($InkCanvas)

    # Encode as PNG
    $encoder = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
    $encoder.Frames.Add(
        [System.Windows.Media.Imaging.BitmapFrame]::Create($rtb)
    )
    $stream = [System.IO.File]::Create($FilePath)
    try {
        $encoder.Save($stream)
    } finally {
        $stream.Close()
        $stream.Dispose()
    }
}

function Get-SignatureBase64 {
    param([string]$PngPath)
    if (-not (Test-Path $PngPath)) { return "" }
    $bytes = [System.IO.File]::ReadAllBytes($PngPath)
    return [System.Convert]::ToBase64String($bytes)
}

function Get-ContentSHA256 {
    param([string]$Content)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Content)
    $hash  = $sha.ComputeHash($bytes)
    $sha.Dispose()
    $sb = New-Object System.Text.StringBuilder
    foreach ($b in $hash) {
        [void]$sb.Append($b.ToString("x2"))
    }
    return $sb.ToString()
}

# ─────────────────────────────────────────────────────────────────────────────
# WINFORMS UI - MAIN INTAKE FORM
# ─────────────────────────────────────────────────────────────────────────────
function Show-ConsentForm {
    # Load System.Web for HtmlEncode
    Add-Type -AssemblyName System.Web

    $workOrder = New-WorkOrderNumber

    # --- Main Form ---
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "$COMPANY_FULL - Customer Consent & Intake"
    $form.Size = New-Object System.Drawing.Size(680, 920)
    $form.StartPosition = "CenterScreen"
    $form.FormBorderStyle = "FixedSingle"
    $form.MaximizeBox = $false
    $form.BackColor = [System.Drawing.ColorTranslator]::FromHtml($COLOR_NAVY)
    $form.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $form.ForeColor = [System.Drawing.Color]::White

    # ── Scrollable Panel ──
    $panel = New-Object System.Windows.Forms.Panel
    $panel.Location = New-Object System.Drawing.Point(0, 0)
    $panel.Size = New-Object System.Drawing.Size(664, 880)
    $panel.AutoScroll = $true
    $panel.BackColor = [System.Drawing.ColorTranslator]::FromHtml($COLOR_NAVY)
    $form.Controls.Add($panel)

    $yPos = 15

    # ── Header ──
    $lblTitle = New-Object System.Windows.Forms.Label
    $lblTitle.Text = "$COMPANY_FULL"
    $lblTitle.Font = New-Object System.Drawing.Font("Segoe UI", 18, [System.Drawing.FontStyle]::Bold)
    $lblTitle.ForeColor = [System.Drawing.ColorTranslator]::FromHtml($COLOR_ACCENT)
    $lblTitle.AutoSize = $false
    $lblTitle.Size = New-Object System.Drawing.Size(630, 35)
    $lblTitle.Location = New-Object System.Drawing.Point(20, $yPos)
    $lblTitle.TextAlign = "MiddleCenter"
    $panel.Controls.Add($lblTitle)
    $yPos += 38

    $lblSubtitle = New-Object System.Windows.Forms.Label
    $lblSubtitle.Text = "Customer Consent & Service Authorization"
    $lblSubtitle.Font = New-Object System.Drawing.Font("Segoe UI", 11)
    $lblSubtitle.ForeColor = [System.Drawing.Color]::FromArgb(136, 153, 170)
    $lblSubtitle.AutoSize = $false
    $lblSubtitle.Size = New-Object System.Drawing.Size(630, 22)
    $lblSubtitle.Location = New-Object System.Drawing.Point(20, $yPos)
    $lblSubtitle.TextAlign = "MiddleCenter"
    $panel.Controls.Add($lblSubtitle)
    $yPos += 30

    # ── Work Order Badge ──
    $lblWO = New-Object System.Windows.Forms.Label
    $lblWO.Text = "Work Order: $workOrder"
    $lblWO.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $lblWO.ForeColor = [System.Drawing.Color]::White
    $lblWO.BackColor = [System.Drawing.ColorTranslator]::FromHtml($COLOR_ACCENT)
    $lblWO.AutoSize = $false
    $lblWO.Size = New-Object System.Drawing.Size(250, 28)
    $lblWO.Location = New-Object System.Drawing.Point(205, $yPos)
    $lblWO.TextAlign = "MiddleCenter"
    $panel.Controls.Add($lblWO)
    $yPos += 40

    # ── Separator ──
    $sep1 = New-Object System.Windows.Forms.Label
    $sep1.Text = ""
    $sep1.BorderStyle = "Fixed3D"
    $sep1.AutoSize = $false
    $sep1.Size = New-Object System.Drawing.Size(620, 2)
    $sep1.Location = New-Object System.Drawing.Point(20, $yPos)
    $panel.Controls.Add($sep1)
    $yPos += 15

    # ── Helper to add labeled text field ──
    $addField = {
        param([string]$LabelText, [int]$YStart, [int]$Width, [System.Windows.Forms.Panel]$Parent)
        $lbl = New-Object System.Windows.Forms.Label
        $lbl.Text = $LabelText
        $lbl.Font = New-Object System.Drawing.Font("Segoe UI", 9)
        $lbl.ForeColor = [System.Drawing.ColorTranslator]::FromHtml($COLOR_ACCENT)
        $lbl.AutoSize = $true
        $lbl.Location = New-Object System.Drawing.Point(25, $YStart)
        $Parent.Controls.Add($lbl)

        $txt = New-Object System.Windows.Forms.TextBox
        $txt.Font = New-Object System.Drawing.Font("Segoe UI", 11)
        $txt.Size = New-Object System.Drawing.Size($Width, 28)
        $txt.Location = New-Object System.Drawing.Point(25, ($YStart + 20))
        $txt.BackColor = [System.Drawing.Color]::FromArgb(26, 42, 64)
        $txt.ForeColor = [System.Drawing.Color]::White
        $txt.BorderStyle = "FixedSingle"
        $Parent.Controls.Add($txt)
        return $txt
    }

    # ── Section: Customer Information ──
    $lblSec1 = New-Object System.Windows.Forms.Label
    $lblSec1.Text = "CUSTOMER INFORMATION"
    $lblSec1.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $lblSec1.ForeColor = [System.Drawing.ColorTranslator]::FromHtml($COLOR_ACCENT)
    $lblSec1.AutoSize = $true
    $lblSec1.Location = New-Object System.Drawing.Point(25, $yPos)
    $panel.Controls.Add($lblSec1)
    $yPos += 28

    $txtName  = & $addField "Customer Full Name *" $yPos 590 $panel
    $yPos += 55

    $txtPhone = & $addField "Phone Number *" $yPos 280 $panel
    $txtEmail = New-Object System.Windows.Forms.TextBox
    $txtEmail.Font = New-Object System.Drawing.Font("Segoe UI", 11)
    $txtEmail.Size = New-Object System.Drawing.Size(280, 28)
    $txtEmail.Location = New-Object System.Drawing.Point(335, ($yPos + 20))
    $txtEmail.BackColor = [System.Drawing.Color]::FromArgb(26, 42, 64)
    $txtEmail.ForeColor = [System.Drawing.Color]::White
    $txtEmail.BorderStyle = "FixedSingle"
    $panel.Controls.Add($txtEmail)

    $lblEmail = New-Object System.Windows.Forms.Label
    $lblEmail.Text = "Email Address"
    $lblEmail.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $lblEmail.ForeColor = [System.Drawing.ColorTranslator]::FromHtml($COLOR_ACCENT)
    $lblEmail.AutoSize = $true
    $lblEmail.Location = New-Object System.Drawing.Point(335, $yPos)
    $panel.Controls.Add($lblEmail)
    $yPos += 55

    # ── Device Description ──
    $lblDevice = New-Object System.Windows.Forms.Label
    $lblDevice.Text = "Device Description (make, model, issue) *"
    $lblDevice.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $lblDevice.ForeColor = [System.Drawing.ColorTranslator]::FromHtml($COLOR_ACCENT)
    $lblDevice.AutoSize = $true
    $lblDevice.Location = New-Object System.Drawing.Point(25, $yPos)
    $panel.Controls.Add($lblDevice)
    $yPos += 20

    $txtDevice = New-Object System.Windows.Forms.TextBox
    $txtDevice.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $txtDevice.Size = New-Object System.Drawing.Size(590, 65)
    $txtDevice.Location = New-Object System.Drawing.Point(25, $yPos)
    $txtDevice.BackColor = [System.Drawing.Color]::FromArgb(26, 42, 64)
    $txtDevice.ForeColor = [System.Drawing.Color]::White
    $txtDevice.BorderStyle = "FixedSingle"
    $txtDevice.Multiline = $true
    $txtDevice.ScrollBars = "Vertical"
    $panel.Controls.Add($txtDevice)
    $yPos += 80

    # ── Separator ──
    $sep2 = New-Object System.Windows.Forms.Label
    $sep2.Text = ""
    $sep2.BorderStyle = "Fixed3D"
    $sep2.AutoSize = $false
    $sep2.Size = New-Object System.Drawing.Size(620, 2)
    $sep2.Location = New-Object System.Drawing.Point(20, $yPos)
    $panel.Controls.Add($sep2)
    $yPos += 15

    # ── Section: Consent Checkboxes ──
    $lblSec2 = New-Object System.Windows.Forms.Label
    $lblSec2.Text = "SERVICE AUTHORIZATION"
    $lblSec2.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $lblSec2.ForeColor = [System.Drawing.ColorTranslator]::FromHtml($COLOR_ACCENT)
    $lblSec2.AutoSize = $true
    $lblSec2.Location = New-Object System.Drawing.Point(25, $yPos)
    $panel.Controls.Add($lblSec2)
    $yPos += 28

    $addCheckbox = {
        param([string]$Text, [int]$Y, [System.Windows.Forms.Panel]$Parent)
        $cb = New-Object System.Windows.Forms.CheckBox
        $cb.Text = $Text
        $cb.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)
        $cb.ForeColor = [System.Drawing.Color]::White
        $cb.AutoSize = $false
        $cb.Size = New-Object System.Drawing.Size(590, 24)
        $cb.Location = New-Object System.Drawing.Point(30, $Y)
        $cb.FlatStyle = "Flat"
        $Parent.Controls.Add($cb)
        return $cb
    }

    $chkDiag    = & $addCheckbox "I consent to diagnostic scanning of this computer" $yPos $panel
    $yPos += 30
    $chkRepair  = & $addCheckbox "I consent to software repairs and optimization" $yPos $panel
    $yPos += 30
    $chkBackup  = & $addCheckbox "I consent to data backup if needed" $yPos $panel
    $yPos += 30
    $chkRestore = & $addCheckbox "I understand a restore point will be created before any changes" $yPos $panel
    $yPos += 30
    $chkAccess  = & $addCheckbox "I authorize PC Plus Computing to access system settings" $yPos $panel
    $yPos += 38

    # ── Select All / Clear All ──
    $btnSelectAll = New-Object System.Windows.Forms.Button
    $btnSelectAll.Text = "Select All"
    $btnSelectAll.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $btnSelectAll.Size = New-Object System.Drawing.Size(100, 28)
    $btnSelectAll.Location = New-Object System.Drawing.Point(30, $yPos)
    $btnSelectAll.FlatStyle = "Flat"
    $btnSelectAll.BackColor = [System.Drawing.ColorTranslator]::FromHtml($COLOR_GREEN)
    $btnSelectAll.ForeColor = [System.Drawing.Color]::White
    $btnSelectAll.Add_Click({
        $chkDiag.Checked = $true
        $chkRepair.Checked = $true
        $chkBackup.Checked = $true
        $chkRestore.Checked = $true
        $chkAccess.Checked = $true
    })
    $panel.Controls.Add($btnSelectAll)

    $btnClearAll = New-Object System.Windows.Forms.Button
    $btnClearAll.Text = "Clear All"
    $btnClearAll.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $btnClearAll.Size = New-Object System.Drawing.Size(100, 28)
    $btnClearAll.Location = New-Object System.Drawing.Point(140, $yPos)
    $btnClearAll.FlatStyle = "Flat"
    $btnClearAll.BackColor = [System.Drawing.Color]::FromArgb(60, 70, 85)
    $btnClearAll.ForeColor = [System.Drawing.Color]::White
    $btnClearAll.Add_Click({
        $chkDiag.Checked = $false
        $chkRepair.Checked = $false
        $chkBackup.Checked = $false
        $chkRestore.Checked = $false
        $chkAccess.Checked = $false
    })
    $panel.Controls.Add($btnClearAll)
    $yPos += 42

    # ── Separator ──
    $sep3 = New-Object System.Windows.Forms.Label
    $sep3.Text = ""
    $sep3.BorderStyle = "Fixed3D"
    $sep3.AutoSize = $false
    $sep3.Size = New-Object System.Drawing.Size(620, 2)
    $sep3.Location = New-Object System.Drawing.Point(20, $yPos)
    $panel.Controls.Add($sep3)
    $yPos += 15

    # ── Section: Technician & Signature ──
    $lblSec3 = New-Object System.Windows.Forms.Label
    $lblSec3.Text = "TECHNICIAN & SIGNATURE"
    $lblSec3.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $lblSec3.ForeColor = [System.Drawing.ColorTranslator]::FromHtml($COLOR_ACCENT)
    $lblSec3.AutoSize = $true
    $lblSec3.Location = New-Object System.Drawing.Point(25, $yPos)
    $panel.Controls.Add($lblSec3)
    $yPos += 28

    $txtTech = & $addField "Technician Name *" $yPos 280 $panel

    # Date/Time (auto-populated, read-only)
    $lblDateTime = New-Object System.Windows.Forms.Label
    $lblDateTime.Text = "Date & Time"
    $lblDateTime.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $lblDateTime.ForeColor = [System.Drawing.ColorTranslator]::FromHtml($COLOR_ACCENT)
    $lblDateTime.AutoSize = $true
    $lblDateTime.Location = New-Object System.Drawing.Point(335, $yPos)
    $panel.Controls.Add($lblDateTime)

    $txtDateTime = New-Object System.Windows.Forms.TextBox
    $txtDateTime.Font = New-Object System.Drawing.Font("Segoe UI", 11)
    $txtDateTime.Size = New-Object System.Drawing.Size(280, 28)
    $txtDateTime.Location = New-Object System.Drawing.Point(335, ($yPos + 20))
    $txtDateTime.BackColor = [System.Drawing.Color]::FromArgb(20, 32, 50)
    $txtDateTime.ForeColor = [System.Drawing.Color]::LightGray
    $txtDateTime.BorderStyle = "FixedSingle"
    $txtDateTime.ReadOnly = $true
    $txtDateTime.Text = Get-Date -Format "yyyy-MM-dd hh:mm tt"
    $panel.Controls.Add($txtDateTime)
    $yPos += 55

    # Digital Signature
    $lblSig = New-Object System.Windows.Forms.Label
    $lblSig.Text = "Digital Signature - Type your full name to sign *"
    $lblSig.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $lblSig.ForeColor = [System.Drawing.ColorTranslator]::FromHtml($COLOR_ACCENT)
    $lblSig.AutoSize = $true
    $lblSig.Location = New-Object System.Drawing.Point(25, $yPos)
    $panel.Controls.Add($lblSig)
    $yPos += 20

    $txtSignature = New-Object System.Windows.Forms.TextBox
    $txtSignature.Font = New-Object System.Drawing.Font("Georgia", 14, [System.Drawing.FontStyle]::Italic)
    $txtSignature.Size = New-Object System.Drawing.Size(590, 35)
    $txtSignature.Location = New-Object System.Drawing.Point(25, $yPos)
    $txtSignature.BackColor = [System.Drawing.Color]::FromArgb(26, 42, 64)
    $txtSignature.ForeColor = [System.Drawing.ColorTranslator]::FromHtml($COLOR_ACCENT)
    $txtSignature.BorderStyle = "FixedSingle"
    $txtSignature.TextAlign = "Center"
    $panel.Controls.Add($txtSignature)
    $yPos += 50

    # ── InkCanvas Handwritten Signature Pad ──
    $lblSignPad = New-Object System.Windows.Forms.Label
    $lblSignPad.Text = "SIGN HERE"
    $lblSignPad.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $lblSignPad.ForeColor = [System.Drawing.ColorTranslator]::FromHtml($COLOR_ACCENT)
    $lblSignPad.AutoSize = $false
    $lblSignPad.Size = New-Object System.Drawing.Size(500, 20)
    $lblSignPad.Location = New-Object System.Drawing.Point(25, $yPos)
    $lblSignPad.TextAlign = "BottomLeft"
    $panel.Controls.Add($lblSignPad)

    $lblSignHint = New-Object System.Windows.Forms.Label
    $lblSignHint.Text = "Use your mouse, touchpad, or touchscreen to draw your signature"
    $lblSignHint.Font = New-Object System.Drawing.Font("Segoe UI", 8)
    $lblSignHint.ForeColor = [System.Drawing.Color]::FromArgb(120, 140, 160)
    $lblSignHint.AutoSize = $true
    $lblSignHint.Location = New-Object System.Drawing.Point(25, ($yPos + 18))
    $panel.Controls.Add($lblSignHint)
    $yPos += 40

    # Create the WPF InkCanvas inside an ElementHost
    $inkCanvas = New-Object System.Windows.Controls.InkCanvas
    $inkCanvas.Background = [System.Windows.Media.Brushes]::White
    $inkCanvas.Width  = 500
    $inkCanvas.Height = 150
    $inkCanvas.EditingMode = [System.Windows.Controls.InkCanvasEditingMode]::Ink

    # Dark blue ink, medium thickness
    $drawingAttrs = New-Object System.Windows.Ink.DrawingAttributes
    $drawingAttrs.Color   = [System.Windows.Media.Color]::FromRgb(10, 30, 80)
    $drawingAttrs.Width   = 2.5
    $drawingAttrs.Height  = 2.5
    $drawingAttrs.FitToCurve    = $true
    $drawingAttrs.StylusTip     = [System.Windows.Ink.StylusTip]::Ellipse
    $drawingAttrs.IgnorePressure = $false
    $inkCanvas.DefaultDrawingAttributes = $drawingAttrs

    # WPF Grid container with a dashed Rectangle border behind the InkCanvas
    # (WPF Border doesn't support dashed lines, so we layer a styled Rectangle)
    $wpfContainer = New-Object System.Windows.Controls.Grid
    $wpfContainer.Width  = 504
    $wpfContainer.Height = 154

    # Dashed border rectangle
    $dashRect = New-Object System.Windows.Shapes.Rectangle
    $dashRect.Stroke          = New-Object System.Windows.Media.SolidColorBrush(
        [System.Windows.Media.Color]::FromRgb(140, 150, 165)
    )
    $dashRect.StrokeThickness = 1.5
    $dashRect.StrokeDashArray = New-Object System.Windows.Media.DoubleCollection
    $dashRect.StrokeDashArray.Add(6.0)
    $dashRect.StrokeDashArray.Add(3.0)
    $dashRect.RadiusX = 6
    $dashRect.RadiusY = 6
    $dashRect.Fill    = [System.Windows.Media.Brushes]::White
    [void]$wpfContainer.Children.Add($dashRect)

    # Add InkCanvas on top with small margin so the dashes show
    $inkCanvas.Margin = New-Object System.Windows.Thickness(2)
    [void]$wpfContainer.Children.Add($inkCanvas)

    # Host inside WinForms via ElementHost
    $elementHost = New-Object System.Windows.Forms.Integration.ElementHost
    $elementHost.Size     = New-Object System.Drawing.Size(508, 158)
    $elementHost.Location = New-Object System.Drawing.Point(60, $yPos)
    $elementHost.Child    = $wpfContainer
    $elementHost.BackColor = [System.Drawing.ColorTranslator]::FromHtml($COLOR_NAVY)
    $panel.Controls.Add($elementHost)
    $yPos += 165

    # ── Clear Signature Button ──
    $btnClearSig = New-Object System.Windows.Forms.Button
    $btnClearSig.Text = "Clear Signature"
    $btnClearSig.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $btnClearSig.Size = New-Object System.Drawing.Size(130, 28)
    $btnClearSig.Location = New-Object System.Drawing.Point(60, $yPos)
    $btnClearSig.FlatStyle = "Flat"
    $btnClearSig.BackColor = [System.Drawing.Color]::FromArgb(60, 70, 85)
    $btnClearSig.ForeColor = [System.Drawing.Color]::White
    $btnClearSig.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btnClearSig.Add_Click({ $inkCanvas.Strokes.Clear() })
    $panel.Controls.Add($btnClearSig)
    $yPos += 42

    # ── Separator ──
    $sep4 = New-Object System.Windows.Forms.Label
    $sep4.Text = ""
    $sep4.BorderStyle = "Fixed3D"
    $sep4.AutoSize = $false
    $sep4.Size = New-Object System.Drawing.Size(620, 2)
    $sep4.Location = New-Object System.Drawing.Point(20, $yPos)
    $panel.Controls.Add($sep4)
    $yPos += 20

    # ── Action Buttons ──
    $btnSubmit = New-Object System.Windows.Forms.Button
    $btnSubmit.Text = "Submit Consent Form"
    $btnSubmit.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
    $btnSubmit.Size = New-Object System.Drawing.Size(200, 40)
    $btnSubmit.Location = New-Object System.Drawing.Point(25, $yPos)
    $btnSubmit.FlatStyle = "Flat"
    $btnSubmit.BackColor = [System.Drawing.ColorTranslator]::FromHtml($COLOR_GREEN)
    $btnSubmit.ForeColor = [System.Drawing.Color]::White
    $btnSubmit.Cursor = [System.Windows.Forms.Cursors]::Hand
    $panel.Controls.Add($btnSubmit)

    $btnPrint = New-Object System.Windows.Forms.Button
    $btnPrint.Text = "Preview"
    $btnPrint.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $btnPrint.Size = New-Object System.Drawing.Size(85, 40)
    $btnPrint.Location = New-Object System.Drawing.Point(235, $yPos)
    $btnPrint.FlatStyle = "Flat"
    $btnPrint.BackColor = [System.Drawing.ColorTranslator]::FromHtml($COLOR_ACCENT)
    $btnPrint.ForeColor = [System.Drawing.Color]::White
    $btnPrint.Enabled = $false
    $btnPrint.Cursor = [System.Windows.Forms.Cursors]::Hand
    $panel.Controls.Add($btnPrint)

    $btnPrintConsent = New-Object System.Windows.Forms.Button
    $btnPrintConsent.Text = "Print Consent Form"
    $btnPrintConsent.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $btnPrintConsent.Size = New-Object System.Drawing.Size(140, 40)
    $btnPrintConsent.Location = New-Object System.Drawing.Point(328, $yPos)
    $btnPrintConsent.FlatStyle = "Flat"
    $btnPrintConsent.BackColor = [System.Drawing.ColorTranslator]::FromHtml($COLOR_ORANGE)
    $btnPrintConsent.ForeColor = [System.Drawing.Color]::White
    $btnPrintConsent.Enabled = $false
    $btnPrintConsent.Cursor = [System.Windows.Forms.Cursors]::Hand
    $panel.Controls.Add($btnPrintConsent)

    $btnViewExisting = New-Object System.Windows.Forms.Button
    $btnViewExisting.Text = "View Active"
    $btnViewExisting.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $btnViewExisting.Size = New-Object System.Drawing.Size(100, 40)
    $btnViewExisting.Location = New-Object System.Drawing.Point(476, $yPos)
    $btnViewExisting.FlatStyle = "Flat"
    $btnViewExisting.BackColor = [System.Drawing.Color]::FromArgb(60, 70, 85)
    $btnViewExisting.ForeColor = [System.Drawing.Color]::White
    $btnViewExisting.Cursor = [System.Windows.Forms.Cursors]::Hand
    $panel.Controls.Add($btnViewExisting)

    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = "Cancel"
    $btnCancel.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $btnCancel.Size = New-Object System.Drawing.Size(70, 40)
    $btnCancel.Location = New-Object System.Drawing.Point(584, $yPos)
    $btnCancel.FlatStyle = "Flat"
    $btnCancel.BackColor = [System.Drawing.ColorTranslator]::FromHtml($COLOR_RED)
    $btnCancel.ForeColor = [System.Drawing.Color]::White
    $btnCancel.Cursor = [System.Windows.Forms.Cursors]::Hand
    $panel.Controls.Add($btnCancel)
    $yPos += 55

    # ── Status Bar ──
    $lblStatus = New-Object System.Windows.Forms.Label
    $lblStatus.Text = "$COMPANY_NAME  |  $COMPANY_PHONE1  |  $COMPANY_WEBSITE"
    $lblStatus.Font = New-Object System.Drawing.Font("Segoe UI", 8)
    $lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(90, 106, 122)
    $lblStatus.AutoSize = $false
    $lblStatus.Size = New-Object System.Drawing.Size(630, 20)
    $lblStatus.Location = New-Object System.Drawing.Point(20, $yPos)
    $lblStatus.TextAlign = "MiddleCenter"
    $panel.Controls.Add($lblStatus)

    # ── Track the saved HTML path for Print button ──
    $script:savedHtmlPath = $null

    # ── Button Handlers ──
    $btnCancel.Add_Click({ $form.Close() })

    $btnViewExisting.Add_Click({
        $lockInfo = Get-ConsentLockInfo
        if ($null -eq $lockInfo) {
            [System.Windows.Forms.MessageBox]::Show(
                "No active consent form found.`nPlease submit a new consent form first.",
                "No Active Consent",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            )
            return
        }
        $msg = @"
Active Consent Lock
-------------------
Work Order:     $($lockInfo.WorkOrderNumber)
Customer:       $($lockInfo.CustomerName)
Computer:       $($lockInfo.ComputerName)
Date/Time:      $($lockInfo.Timestamp)

Diagnostic:     $(if ($lockInfo.ConsentDiag) { 'Granted' } else { 'Not Granted' })
Repair:         $(if ($lockInfo.ConsentRepair) { 'Granted' } else { 'Not Granted' })
Backup:         $(if ($lockInfo.ConsentBackup) { 'Granted' } else { 'Not Granted' })
Restore Point:  $(if ($lockInfo.ConsentRestore) { 'Granted' } else { 'Not Granted' })
Access:         $(if ($lockInfo.ConsentAccess) { 'Granted' } else { 'Not Granted' })
"@
        [System.Windows.Forms.MessageBox]::Show(
            $msg,
            "Active Consent Information",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        )
    })

    $btnPrint.Add_Click({
        if ($script:savedHtmlPath -and (Test-Path $script:savedHtmlPath)) {
            Start-Process $script:savedHtmlPath
        }
    })

    $btnPrintConsent.Add_Click({
        if ($script:savedHtmlPath -and (Test-Path $script:savedHtmlPath)) {
            # Open the HTML consent form in default browser for printing
            Start-Process $script:savedHtmlPath
            [System.Windows.Forms.MessageBox]::Show(
                "The signed consent form has been opened in your default browser.`nUse Ctrl+P or File > Print to print.",
                "Print Consent Form",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            )
        } else {
            [System.Windows.Forms.MessageBox]::Show(
                "No consent form has been saved yet.`nPlease submit the form first.",
                "Print Unavailable",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            )
        }
    })

    $btnSubmit.Add_Click({
        # ── Validation ──
        $errors = [System.Collections.ArrayList]::new()

        if ([string]::IsNullOrWhiteSpace($txtName.Text)) {
            [void]$errors.Add("Customer name is required.")
        }
        if (-not (Test-PhoneFormat $txtPhone.Text)) {
            [void]$errors.Add("A valid phone number is required (minimum 7 digits).")
        }
        if (-not [string]::IsNullOrWhiteSpace($txtEmail.Text) -and -not (Test-EmailFormat $txtEmail.Text)) {
            [void]$errors.Add("Email address format is invalid.")
        }
        if ([string]::IsNullOrWhiteSpace($txtDevice.Text)) {
            [void]$errors.Add("Device description is required.")
        }
        if ([string]::IsNullOrWhiteSpace($txtTech.Text)) {
            [void]$errors.Add("Technician name is required.")
        }
        if ([string]::IsNullOrWhiteSpace($txtSignature.Text)) {
            [void]$errors.Add("Digital signature (type your full name) is required.")
        }
        if ($inkCanvas.Strokes.Count -eq 0) {
            [void]$errors.Add("Handwritten signature is required. Please sign in the signature pad above.")
        }
        if (-not $chkDiag.Checked) {
            [void]$errors.Add("Diagnostic consent must be granted to proceed.")
        }

        if ($errors.Count -gt 0) {
            $errMsg = "Please correct the following:`n`n" + ($errors -join "`n")
            [System.Windows.Forms.MessageBox]::Show(
                $errMsg,
                "Validation Error",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            )
            return
        }

        # ── Gather Form Data ──
        $formData = @{
            WorkOrderNumber     = $workOrder
            CustomerName        = $txtName.Text.Trim()
            CustomerPhone       = $txtPhone.Text.Trim()
            CustomerEmail       = $txtEmail.Text.Trim()
            DeviceDescription   = $txtDevice.Text.Trim()
            ConsentDiagnostic   = $chkDiag.Checked
            ConsentRepair       = $chkRepair.Checked
            ConsentBackup       = $chkBackup.Checked
            ConsentRestorePoint = $chkRestore.Checked
            ConsentAccessSettings = $chkAccess.Checked
            DigitalSignature    = $txtSignature.Text.Trim()
            TechnicianName      = $txtTech.Text.Trim()
            DateTime            = $txtDateTime.Text
            ComputerName        = $env:COMPUTERNAME
            SignatureBase64     = ""
            SignatureImageFile  = ""
            ContentHash         = ""
        }

        try {
            $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
            $safeName  = ($formData.CustomerName -replace '[^a-zA-Z0-9\-]', '_')

            # Save signature image from InkCanvas
            $sigFileName = "${safeName}-signature.png"
            $sigPath     = Join-Path $ReportsDir $sigFileName
            Save-InkCanvasToPng -InkCanvas $inkCanvas -FilePath $sigPath
            $formData.SignatureBase64    = Get-SignatureBase64 -PngPath $sigPath
            $formData.SignatureImageFile = $sigFileName

            # Compute SHA256 hash of the consent content for tamper detection
            $hashInput = @(
                $formData.WorkOrderNumber
                $formData.CustomerName
                $formData.CustomerPhone
                $formData.CustomerEmail
                $formData.DeviceDescription
                $formData.ConsentDiagnostic.ToString()
                $formData.ConsentRepair.ToString()
                $formData.ConsentBackup.ToString()
                $formData.ConsentRestorePoint.ToString()
                $formData.ConsentAccessSettings.ToString()
                $formData.DigitalSignature
                $formData.TechnicianName
                $formData.DateTime
                $formData.SignatureBase64
            ) -join "|"
            $formData.ContentHash = Get-ContentSHA256 -Content $hashInput

            # Save HTML report (with embedded signature)
            $htmlFileName = "Consent-$workOrder-$timestamp.html"
            $htmlPath = Join-Path $ReportsDir $htmlFileName
            $html = New-ConsentHtmlReport -FormData $formData
            $html | Set-Content -Path $htmlPath -Encoding UTF8 -Force
            $script:savedHtmlPath = $htmlPath

            # Save JSON
            $jsonFileName = "Consent-$workOrder-$timestamp.json"
            $jsonPath = Join-Path $ReportsDir $jsonFileName
            Save-ConsentJson -FormData $formData -OutputPath $jsonPath

            # Save consent lock file
            $lockPath = Save-ConsentLock -WorkOrderNumber $workOrder -CustomerName $formData.CustomerName -Consents @{
                Diagnostic     = $formData.ConsentDiagnostic
                Repair         = $formData.ConsentRepair
                Backup         = $formData.ConsentBackup
                RestorePoint   = $formData.ConsentRestorePoint
                AccessSettings = $formData.ConsentAccessSettings
            }

            # Enable print button
            $btnPrint.Enabled = $true
            $btnPrintConsent.Enabled = $true

            # Disable submit to prevent duplicate
            $btnSubmit.Enabled = $false
            $btnSubmit.BackColor = [System.Drawing.Color]::FromArgb(60, 70, 85)
            $btnSubmit.Text = "Submitted"

            # Lock the signature pad
            $inkCanvas.EditingMode = [System.Windows.Controls.InkCanvasEditingMode]::None
            $btnClearSig.Enabled = $false

            $successMsg = @"
Consent form submitted successfully!

Work Order:    $workOrder
HTML Report:   $htmlFileName
JSON Record:   $jsonFileName
Signature:     $sigFileName
SHA-256 Hash:  $($formData.ContentHash.Substring(0,16))...

The consent lock file has been created.
Other PC Plus 360 tools will now be authorized to perform repairs.

Click 'Print Consent Form' to open the signed form in your browser for printing.
"@
            [System.Windows.Forms.MessageBox]::Show(
                $successMsg,
                "Consent Form Saved",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            )
        } catch {
            [System.Windows.Forms.MessageBox]::Show(
                "Error saving consent form:`n$($_.Exception.Message)",
                "Save Error",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            )
        }
    })

    # ── Timer to update date/time ──
    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 30000  # 30 seconds
    $timer.Add_Tick({ $txtDateTime.Text = Get-Date -Format "yyyy-MM-dd hh:mm tt" })
    $timer.Start()

    $form.Add_FormClosed({ $timer.Stop(); $timer.Dispose() })

    [void]$form.ShowDialog()
}

# ─────────────────────────────────────────────────────────────────────────────
# MAIN ENTRY POINT
# ─────────────────────────────────────────────────────────────────────────────
Show-ConsentForm

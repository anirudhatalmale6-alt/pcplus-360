# PC Plus Computing - 360 Diagnostic Suite

Complete USB toolkit for PC technicians. Hardware diagnostics, security audits, stress tests, license key recovery, and Windows debloat - all from one branded dashboard.

## Tools Included

### 1. PCPlus-360.ps1 (Main Launcher)

The all-in-one diagnostic dashboard with WPF UI.

**Quick Diagnostic (10-15 min)**
- Full hardware inventory (RAM, GPU, motherboard, BIOS, battery, disks, monitors, printers)
- 15-point security audit (antivirus, firewall, BitLocker, patches, password policy, Secure Boot, TPM, etc.)
- Network diagnostics (adapters, DNS, gateway, internet connectivity)
- Software inventory
- Missing Windows patches list
- License key recovery (Windows, Office, Adobe, WiFi passwords)
- Performance snapshot (CPU/RAM/disk usage, top processes)

**Full Diagnostic (30-60 min)**
- Everything in Quick Diagnostic, plus:
- CPU Stress Test (prime number sieve, multi-threaded, 2 min)
- RAM Stress Test (pattern write/verify blocks, 2 min)
- Disk Benchmark (sequential read/write, 512MB test file)

**Individual Tests**
Run any single test from the dashboard: Hardware Scan, Security Audit, Network Test, Stress Tests (CPU/RAM/Disk), License Keys, Software Inventory

**Two Separate PDF Reports**
- Hardware Report: specs, health score (0-100), stress test results, SMART data, license keys, technician notes
- Security Report: 15-point audit, security score (0-100, A-F grade), recommendations, missing patches

**Portable Tool Integration**
Place these in the `tools/` folder and the dashboard will detect and launch them:
- CrystalDiskInfo
- HWiNFO
- CPU-Z
- GPU-Z
- HWMonitor
- BatteryInfoView
- Prime95
- FurMark
- CrystalDiskMark
- Victoria

### 2. PCPlus-SecurityAudit.ps1 (Standalone)

Standalone hardware + security audit with branded PDF report. Use this when you just need a quick audit without stress tests or the full dashboard.

### 3. PCPlus-Debloat.ps1 (Windows Debloat & Lockdown)

Strips bloatware from Windows 10/11. Checkbox UI - pick what you need:
- Remove 80+ bloatware apps (Cortana, Xbox, Solitaire, TikTok, Netflix, etc.)
- Disable telemetry, Cortana, Widgets, Game Bar
- Remove OneDrive
- Clean Start Menu and taskbar
- Block app reinstalls and ads
- Disable unnecessary services (keeps Print Spooler)
- Daily Downloads folder cleanup
- Block non-admin installs
- Disable Microsoft Store
- Optimize power settings

## USB Setup

```
USB Drive/
├── PCPlus-360.ps1          (main launcher)
├── PCPlus-SecurityAudit.ps1 (standalone audit)
├── PCPlus-Debloat.ps1      (debloat tool)
└── tools/                  (portable tools - optional)
    ├── CrystalDiskInfo/
    ├── HWiNFO/
    ├── CPU-Z/
    ├── GPU-Z/
    ├── HWMonitor/
    └── BatteryInfoView/
```

## Usage

```powershell
# Right-click any .ps1 file > Run with PowerShell, or:
Set-ExecutionPolicy Bypass -Scope Process -Force
.\PCPlus-360.ps1
```

All scripts auto-elevate to admin if needed.

## Reports Output

Reports saved to a `reports/` folder next to the script:
- `CustomerName - HOSTNAME - Hardware Report 2026-05-19.pdf`
- `CustomerName - HOSTNAME - Security Report 2026-05-19.pdf`

## Requirements

- Windows 10 or Windows 11
- PowerShell 5.1+ (built into Windows)
- Administrator privileges
- Edge or Chrome (for PDF generation)

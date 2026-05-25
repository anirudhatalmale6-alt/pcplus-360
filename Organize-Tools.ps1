param(
    [switch]$DryRun,
    [switch]$Silent
)

<#
.SYNOPSIS
    Organize tools into category subfolders based on tools-manifest.json
.DESCRIPTION
    Reads the tools-manifest.json and moves tools from the flat Tools/ folder
    into category subfolders. Run with -DryRun to preview without moving.
.EXAMPLE
    .\Organize-Tools.ps1 -DryRun
    .\Organize-Tools.ps1
#>

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
if ([string]::IsNullOrEmpty($ScriptDir)) { $ScriptDir = Get-Location }
$ToolsDir = Join-Path $ScriptDir "Tools"
$ManifestPath = Join-Path $ScriptDir "tools-manifest.json"

if (-not (Test-Path $ManifestPath)) {
    Write-Host "ERROR: tools-manifest.json not found at $ManifestPath" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $ToolsDir)) {
    Write-Host "ERROR: Tools folder not found at $ToolsDir" -ForegroundColor Red
    exit 1
}

$manifest = Get-Content $ManifestPath -Raw | ConvertFrom-Json
$moved = 0
$skipped = 0

Write-Host ""
Write-Host "  PC Plus 360 - Tool Organizer" -ForegroundColor Cyan
Write-Host "  =============================" -ForegroundColor Cyan
Write-Host "  Tools folder: $ToolsDir" -ForegroundColor Gray
if ($DryRun) { Write-Host "  MODE: DRY RUN (no files will be moved)" -ForegroundColor Yellow }
Write-Host ""

foreach ($category in $manifest.categories) {
    $catFolder = Join-Path $ToolsDir ($category.name -replace '[<>:"/\\|?*]', '-')

    foreach ($tool in $category.tools) {
        $sourcePath = Join-Path $ToolsDir $tool.exe

        if (-not (Test-Path $sourcePath)) { continue }

        if (-not $DryRun) {
            if (-not (Test-Path $catFolder)) {
                New-Item -Path $catFolder -ItemType Directory -Force | Out-Null
            }
            $destPath = Join-Path $catFolder $tool.exe
            if (-not (Test-Path $destPath)) {
                Move-Item -Path $sourcePath -Destination $destPath -Force
                if (-not $Silent) {
                    Write-Host "    [MOVED] $($tool.exe) -> $($category.name)/" -ForegroundColor Green
                }
                $moved++
            } else {
                $skipped++
            }
        } else {
            Write-Host "    [WOULD MOVE] $($tool.exe) -> $($category.name)/" -ForegroundColor DarkGray
            $moved++
        }
    }
}

Write-Host ""
Write-Host "  Summary:" -ForegroundColor Cyan
Write-Host "    Files moved:   $moved" -ForegroundColor White
Write-Host "    Skipped:       $skipped" -ForegroundColor Gray
Write-Host "    Categories:    $($manifest.categories.Count)" -ForegroundColor White
Write-Host ""

if ($DryRun) {
    Write-Host "  Run without -DryRun to actually move files." -ForegroundColor Yellow
}

if (-not $Silent) { Read-Host "  Press Enter to exit" }

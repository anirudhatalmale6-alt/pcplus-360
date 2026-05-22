<#
.SYNOPSIS
    PC Plus Computing 360 Hardware & Security Diagnostic Suite
.DESCRIPTION
    Complete diagnostic platform with branded launcher, built-in stress tests,
    third-party tool integration, and dual report generation (Hardware + Security).
    Runs from USB drive with no installation required.
.NOTES
    Company:  PC Plus Computing
    Version:  2.6.0
    Requires: PowerShell 5.1+, Windows 10/11, Administrator privileges
#>

#Requires -Version 5.1

# ─────────────────────────────────────────────────────────────────────────────
# DEBUG LOG (writes to file next to script so we can see crashes)
# ─────────────────────────────────────────────────────────────────────────────
$Global:DebugLogPath = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Definition) "PCPlus360-debug.log"
function Write-DebugLog {
    param([string]$Msg)
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "[$ts] $Msg" | Out-File -FilePath $Global:DebugLogPath -Append -Encoding UTF8
}

Write-DebugLog "Script starting..."
Write-DebugLog "PowerShell version: $($PSVersionTable.PSVersion)"
Write-DebugLog "Script path: $($MyInvocation.MyCommand.Definition)"
Write-DebugLog "Current user: $env:USERNAME"

$ErrorActionPreference = 'Continue'

# ─────────────────────────────────────────────────────────────────────────────
# ELEVATION
# ─────────────────────────────────────────────────────────────────────────────
Write-DebugLog "Loading assemblies..."
try {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    Add-Type -AssemblyName PresentationFramework
    Add-Type -AssemblyName PresentationCore
    Add-Type -AssemblyName WindowsBase
    Write-DebugLog "Assemblies loaded OK"
} catch {
    Write-DebugLog "Assembly load FAILED: $($_.Exception.Message)"
}

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

$isAdmin = Test-IsAdmin
Write-DebugLog "Is Admin: $isAdmin"

if (-not $isAdmin) {
    Write-DebugLog "Not admin - attempting elevation..."
    try {
        $scriptPath = $MyInvocation.MyCommand.Definition
        Start-Process powershell.exe -ArgumentList "-STA -NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`"" -Verb RunAs
        Write-DebugLog "Elevation launched OK, exiting non-admin instance"
    } catch {
        Write-DebugLog "Elevation FAILED: $($_.Exception.Message)"
        [System.Windows.Forms.MessageBox]::Show("This tool requires Administrator privileges.`n`n$($_.Exception.Message)", "PC Plus 360 - Elevation Required", "OK", "Warning")
    }
    exit
}

Write-DebugLog "Running as admin, continuing..."

# ─────────────────────────────────────────────────────────────────────────────
# GLOBALS
# ─────────────────────────────────────────────────────────────────────────────
$Global:ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
if ([string]::IsNullOrEmpty($Global:ScriptDir)) { $Global:ScriptDir = Get-Location }
Write-DebugLog "ScriptDir: $Global:ScriptDir"
$Global:ToolsDir = Join-Path $Global:ScriptDir "tools"
$Global:ReportsDir = Join-Path $Global:ScriptDir "reports"
$Global:DiagResults = @{}
$Global:SelectedScanMode = $null
$Global:LogLines = [System.Collections.ArrayList]::new()

$COMPANY      = "PC Plus Computing"
$PHONE        = "604-760-1662 | 236-500-2700"
$WEBSITE      = "pcpluscomputing.com"
$VERSION      = "2.9.0"

if (-not (Test-Path $Global:ReportsDir)) { New-Item -Path $Global:ReportsDir -ItemType Directory -Force | Out-Null }
if (-not (Test-Path $Global:ToolsDir)) { New-Item -Path $Global:ToolsDir -ItemType Directory -Force | Out-Null }

function Write-DiagLog {
    param([string]$Message, [string]$Level = "INFO")
    $ts = Get-Date -Format "HH:mm:ss"
    $line = "[$ts][$Level] $Message"
    $Global:LogLines.Add($line) | Out-Null
}

function Invoke-Safe {
    param([scriptblock]$Block, $Default = $null)
    try { return (& $Block) } catch { Write-DiagLog "Error: $($_.Exception.Message)" "WARN"; return $Default }
}

# ─────────────────────────────────────────────────────────────────────────────
# MODULE LOADING - Edit tests/reports in separate files without touching UI
# ─────────────────────────────────────────────────────────────────────────────
$testsFile = Join-Path $Global:ScriptDir "PCPlus-Tests.ps1"
$reportsFile = Join-Path $Global:ScriptDir "PCPlus-Reports.ps1"

if (Test-Path $testsFile) {
    Write-DebugLog "Loading PCPlus-Tests.ps1..."
    . $testsFile
    Write-DebugLog "Tests module loaded OK"
} else {
    Write-DebugLog "WARNING: PCPlus-Tests.ps1 not found at $testsFile"
    [System.Windows.Forms.MessageBox]::Show("PCPlus-Tests.ps1 not found next to the launcher.`nMake sure all files are in the same folder.", "Missing Module", "OK", "Error")
    exit
}

if (Test-Path $reportsFile) {
    Write-DebugLog "Loading PCPlus-Reports.ps1..."
    . $reportsFile
    Write-DebugLog "Reports module loaded OK"
} else {
    Write-DebugLog "WARNING: PCPlus-Reports.ps1 not found at $reportsFile"
    [System.Windows.Forms.MessageBox]::Show("PCPlus-Reports.ps1 not found next to the launcher.`nMake sure all files are in the same folder.", "Missing Module", "OK", "Error")
    exit
}

# ─────────────────────────────────────────────────────────────────────────────
# WPF LAUNCHER
# ─────────────────────────────────────────────────────────────────────────────


function Show-Launcher {

$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="PC Plus 360 Hardware Diagnostic Suite" Height="720" Width="960" MinHeight="600" MinWidth="800"
        WindowStartupLocation="CenterScreen" ResizeMode="CanResizeWithGrip"
        Background="#eef4f8" FontFamily="Segoe UI">
    <Window.Resources>
        <Style x:Key="FlatBtn" TargetType="Button">
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="bd" Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="6" Padding="{TemplateBinding Padding}">
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
        <Style x:Key="SideNav" TargetType="Button">
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="HorizontalContentAlignment" Value="Left"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="bd" Background="Transparent" CornerRadius="5" Padding="10,7" Margin="0,1">
                            <ContentPresenter HorizontalAlignment="Left"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="bd" Property="Background" Value="#0d4b71"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter Property="Opacity" Value="0.4"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>
    <Grid>
        <Grid.ColumnDefinitions>
            <ColumnDefinition Width="216"/>
            <ColumnDefinition Width="*"/>
        </Grid.ColumnDefinitions>

        <!-- SIDEBAR -->
        <Border Grid.Column="0" Background="#0a3a56">
            <DockPanel LastChildFill="True">
                <Border DockPanel.Dock="Top" Padding="14,16,14,12" BorderBrush="#0d4b71" BorderThickness="0,0,0,1">
                    <StackPanel Orientation="Horizontal">
                        <Border Width="38" Height="38" CornerRadius="9" Margin="0,0,10,0">
                            <Border.Background>
                                <LinearGradientBrush StartPoint="0,0" EndPoint="1,1">
                                    <GradientStop Color="#2596be" Offset="0"/>
                                    <GradientStop Color="#3bbde0" Offset="1"/>
                                </LinearGradientBrush>
                            </Border.Background>
                            <TextBlock Text="360" FontSize="13" FontWeight="Bold" Foreground="White" HorizontalAlignment="Center" VerticalAlignment="Center" FontFamily="Consolas"/>
                        </Border>
                        <StackPanel VerticalAlignment="Center">
                            <TextBlock Text="PC Plus Computing" FontSize="12.5" FontWeight="SemiBold" Foreground="White"/>
                            <TextBlock Text="YOUR SECURITY, OUR PRIORITY" FontSize="7.5" Foreground="#3bbde0" FontWeight="SemiBold" Margin="0,1,0,0"/>
                        </StackPanel>
                    </StackPanel>
                </Border>

                <Border DockPanel.Dock="Bottom" Padding="14,8" BorderBrush="#0d4b71" BorderThickness="0,1,0,0">
                    <StackPanel>
                        <TextBlock x:Name="lblVersion" Text="v2.6.0" FontSize="10" Foreground="#2596be" FontFamily="Consolas"/>
                        <TextBlock Text="604-760-1662 | 236-500-2700" FontSize="8.5" Foreground="#4a7a8a" Margin="0,2,0,0"/>
                        <TextBlock Text="pcpluscomputing.com" FontSize="8.5" Foreground="#3a6a7a"/>
                        <Button x:Name="btnCheckUpdate" Cursor="Hand" Background="Transparent" BorderThickness="0" HorizontalAlignment="Left" Margin="0,4,0,0" Padding="0">
                            <Button.Template>
                                <ControlTemplate TargetType="Button">
                                    <Border x:Name="bd" Background="Transparent" CornerRadius="3" Padding="4,2">
                                        <TextBlock x:Name="txt" Text="Check for Updates" FontSize="8.5" Foreground="#4a7a8a"/>
                                    </Border>
                                    <ControlTemplate.Triggers>
                                        <Trigger Property="IsMouseOver" Value="True">
                                            <Setter TargetName="txt" Property="Foreground" Value="#3bbde0"/>
                                            <Setter TargetName="txt" Property="TextDecorations" Value="Underline"/>
                                        </Trigger>
                                    </ControlTemplate.Triggers>
                                </ControlTemplate>
                            </Button.Template>
                        </Button>
                        <TextBlock x:Name="lblUpdateStatus" Text="" FontSize="8" Foreground="#34d399" Margin="0,2,0,0" TextWrapping="Wrap"/>
                    </StackPanel>
                </Border>

                <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
                    <StackPanel Margin="6,8,6,8">
                        <TextBlock Text="  MAIN" FontSize="9" FontWeight="SemiBold" Foreground="#4a7a8a" Margin="0,6,0,4"/>
                        <Border Background="#0d4b71" CornerRadius="5" Padding="10,7" Margin="0,1">
                            <TextBlock Text="Dashboard" FontSize="12" Foreground="White" FontWeight="SemiBold"/>
                        </Border>

                        <TextBlock Text="  TOOLS" FontSize="9" FontWeight="SemiBold" Foreground="#4a7a8a" Margin="0,12,0,4"/>
                        <Button x:Name="btnNavNirSoft" Style="{StaticResource SideNav}"><TextBlock Text="  NirSoft Suite" FontSize="11.5" Foreground="#8aabb8"/></Button>
                        <Button x:Name="btnNavPassRecovery" Style="{StaticResource SideNav}"><TextBlock Text="  Password Recovery" FontSize="11.5" Foreground="#8aabb8"/></Button>
                        <Button x:Name="btnNavWinDeep" Style="{StaticResource SideNav}"><TextBlock Text="  Windows Deep Test" FontSize="11.5" Foreground="#8aabb8"/></Button>
                        <Button x:Name="btnNavDebloat" Style="{StaticResource SideNav}"><TextBlock Text="  Windows Debloat" FontSize="11.5" Foreground="#dd4444"/></Button>
                        <Button x:Name="btnNavRAMIso" Style="{StaticResource SideNav}"><TextBlock Text="  RAM Isolation Test" FontSize="11.5" Foreground="#8aabb8"/></Button>

                        <TextBlock Text="  PORTABLE" FontSize="9" FontWeight="SemiBold" Foreground="#4a7a8a" Margin="0,12,0,4"/>
                        <Button x:Name="btnCDI" Style="{StaticResource SideNav}"><TextBlock Text="    CrystalDiskInfo" FontSize="10.5" Foreground="#6a8a98"/></Button>
                        <Button x:Name="btnHWiNFO" Style="{StaticResource SideNav}"><TextBlock Text="    HWiNFO" FontSize="10.5" Foreground="#6a8a98"/></Button>
                        <Button x:Name="btnCPUZ" Style="{StaticResource SideNav}"><TextBlock Text="    CPU-Z" FontSize="10.5" Foreground="#6a8a98"/></Button>
                        <Button x:Name="btnGPUZ" Style="{StaticResource SideNav}"><TextBlock Text="    GPU-Z" FontSize="10.5" Foreground="#6a8a98"/></Button>
                        <Button x:Name="btnHWMon" Style="{StaticResource SideNav}"><TextBlock Text="    HWMonitor" FontSize="10.5" Foreground="#6a8a98"/></Button>
                        <Button x:Name="btnBattView" Style="{StaticResource SideNav}"><TextBlock Text="    BatteryInfoView" FontSize="10.5" Foreground="#6a8a98"/></Button>

                        <TextBlock Text="  DIAGNOSTICS" FontSize="9" FontWeight="SemiBold" Foreground="#4a7a8a" Margin="0,12,0,4"/>
                        <Button x:Name="btnNavWearTear" Style="{StaticResource SideNav}"><TextBlock Text="  Wear &amp; Tear Report" FontSize="11.5" Foreground="#e879f9"/></Button>
                        <Button x:Name="btnGamingPerfTest" Style="{StaticResource SideNav}"><TextBlock Text="  Gaming Perf Test" FontSize="11.5" Foreground="#f97316" FontWeight="SemiBold"/></Button>
                        <Button x:Name="btnLCDDisplay" Style="{StaticResource SideNav}"><TextBlock Text="  LCD Display Test" FontSize="11.5" Foreground="#06b6d4" FontWeight="SemiBold"/></Button>
                        <Button x:Name="btnQuickFix" Style="{StaticResource SideNav}"><TextBlock Text="  Quick Fix" FontSize="11.5" Foreground="#f43f5e" FontWeight="SemiBold"/></Button>

                        <TextBlock Text="  REPORTS" FontSize="9" FontWeight="SemiBold" Foreground="#4a7a8a" Margin="0,12,0,4"/>
                        <Button x:Name="btnHWReport" Style="{StaticResource SideNav}"><TextBlock Text="  Hardware Report" FontSize="11.5" Foreground="#22c55e"/></Button>
                        <Button x:Name="btnSecReport" Style="{StaticResource SideNav}"><TextBlock Text="  Security Report" FontSize="11.5" Foreground="#f59e0b"/></Button>
                        <Button x:Name="btnBothReports" Style="{StaticResource SideNav}"><TextBlock Text="  Both Reports" FontSize="11.5" Foreground="#2596be"/></Button>
                        <Button x:Name="btnCustomerSummary" Style="{StaticResource SideNav}"><TextBlock Text="  Customer Summary" FontSize="11.5" Foreground="#3bbde0" FontWeight="SemiBold"/></Button>
                        <Button x:Name="btnGamingReport" Style="{StaticResource SideNav}"><TextBlock Text="  Gaming PC Report" FontSize="11.5" Foreground="#f472b6" FontWeight="SemiBold"/></Button>
                        <Button x:Name="btnPaperless" Style="{StaticResource SideNav}"><TextBlock Text="  Send Report" FontSize="11.5" Foreground="#34d399" FontWeight="SemiBold"/></Button>
                        <Button x:Name="btnBenchmarks" Style="{StaticResource SideNav}"><TextBlock Text="  Benchmarks" FontSize="11.5" Foreground="#a78bfa" FontWeight="SemiBold"/></Button>
                    </StackPanel>
                </ScrollViewer>
            </DockPanel>
        </Border>

        <!-- CONTENT -->
        <Grid Grid.Column="1">
            <Grid.RowDefinitions>
                <RowDefinition Height="*"/>
                <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>

            <ScrollViewer Grid.Row="0" VerticalScrollBarVisibility="Auto">
                <StackPanel Margin="20,16,20,10">
                    <Grid Margin="0,0,0,12">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/>
                        </Grid.ColumnDefinitions>
                        <StackPanel>
                            <TextBlock Text="Dashboard" FontSize="21" FontWeight="Bold" Foreground="#1a2b3c"/>
                            <TextBlock Text="System overview and diagnostics" FontSize="11.5" Foreground="#5a7080"/>
                        </StackPanel>
                        <Button x:Name="btnQuickScan" Grid.Column="1" Style="{StaticResource FlatBtn}" Background="#2596be" Padding="16,8" VerticalAlignment="Center">
                            <TextBlock Text="Quick Scan" FontSize="12" FontWeight="SemiBold" Foreground="White"/>
                        </Button>
                    </Grid>

                    <!-- Customer Info -->
                    <Border Background="White" CornerRadius="7" Padding="12" Margin="0,0,0,10" BorderBrush="#d8e8f0" BorderThickness="1">
                        <Grid>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/>
                            </Grid.ColumnDefinitions>
                            <Grid.RowDefinitions><RowDefinition/><RowDefinition/><RowDefinition/></Grid.RowDefinitions>
                            <StackPanel Grid.Column="0" Margin="0,0,6,0">
                                <TextBlock Text="CUSTOMER NAME *" FontSize="8.5" FontWeight="SemiBold" Foreground="#8a9baa" Margin="0,0,0,2"/>
                                <TextBox x:Name="txtCustomer" FontSize="12" Padding="6,4" Background="#f6f9fb" Foreground="#1a2b3c" BorderBrush="#d8e8f0"/>
                            </StackPanel>
                            <StackPanel Grid.Column="1" Margin="3,0,3,0">
                                <TextBlock Text="PHONE *" FontSize="8.5" FontWeight="SemiBold" Foreground="#8a9baa" Margin="0,0,0,2"/>
                                <TextBox x:Name="txtPhone" FontSize="12" Padding="6,4" Background="#f6f9fb" Foreground="#1a2b3c" BorderBrush="#d8e8f0"/>
                            </StackPanel>
                            <StackPanel Grid.Column="2" Margin="6,0,0,0">
                                <TextBlock Text="EMAIL" FontSize="8.5" FontWeight="SemiBold" Foreground="#8a9baa" Margin="0,0,0,2"/>
                                <TextBox x:Name="txtEmail" FontSize="12" Padding="6,4" Background="#f6f9fb" Foreground="#1a2b3c" BorderBrush="#d8e8f0"/>
                            </StackPanel>
                            <StackPanel Grid.Row="1" Grid.Column="0" Margin="0,6,6,0">
                                <TextBlock Text="CONTACT NAME" FontSize="8.5" FontWeight="SemiBold" Foreground="#8a9baa" Margin="0,0,0,2"/>
                                <TextBox x:Name="txtContact" FontSize="12" Padding="6,4" Background="#f6f9fb" Foreground="#1a2b3c" BorderBrush="#d8e8f0"/>
                            </StackPanel>
                            <StackPanel Grid.Row="1" Grid.Column="1" Margin="3,6,3,0">
                                <TextBlock Text="DEVICE NAME (auto)" FontSize="8.5" FontWeight="SemiBold" Foreground="#8a9baa" Margin="0,0,0,2"/>
                                <TextBox x:Name="txtDeviceName" FontSize="12" Padding="6,4" Background="#eef4f8" Foreground="#1a2b3c" BorderBrush="#d8e8f0" IsReadOnly="True"/>
                            </StackPanel>
                            <StackPanel Grid.Row="1" Grid.Column="2" Margin="3,6,0,0">
                                <TextBlock Text="TECHNICIAN" FontSize="8.5" FontWeight="SemiBold" Foreground="#8a9baa" Margin="0,0,0,2"/>
                                <TextBox x:Name="txtTech" Text="Paul" FontSize="12" Padding="6,4" Background="#f6f9fb" Foreground="#1a2b3c" BorderBrush="#d8e8f0"/>
                            </StackPanel>
                            <StackPanel Grid.Row="2" Grid.ColumnSpan="3" Margin="0,6,0,0">
                                <TextBlock Text="NOTES (optional - appears in report)" FontSize="8.5" FontWeight="SemiBold" Foreground="#8a9baa" Margin="0,0,0,2"/>
                                <TextBox x:Name="txtNotes" FontSize="11" Padding="6,4" Height="32" Background="#f6f9fb" Foreground="#1a2b3c" BorderBrush="#d8e8f0" AcceptsReturn="True" TextWrapping="Wrap"/>
                            </StackPanel>
                        </Grid>
                    </Border>

                    <!-- System Info Cards -->
                    <Grid Margin="0,0,0,10">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*"/><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>
                        <Border Grid.Column="0" Background="White" CornerRadius="7" Padding="10" Margin="0,0,4,0" BorderBrush="#d8e8f0" BorderThickness="1">
                            <StackPanel>
                                <TextBlock Text="COMPUTER" FontSize="8.5" FontWeight="SemiBold" Foreground="#8a9baa"/>
                                <TextBlock x:Name="lblComputer" Text="---" FontSize="12" FontWeight="SemiBold" Foreground="#1a2b3c" FontFamily="Consolas" Margin="0,2,0,0"/>
                                <TextBlock x:Name="lblOS" Text="" FontSize="9.5" Foreground="#5a7080"/>
                            </StackPanel>
                        </Border>
                        <Border Grid.Column="1" Background="White" CornerRadius="7" Padding="10" Margin="2,0,2,0" BorderBrush="#d8e8f0" BorderThickness="1">
                            <StackPanel>
                                <TextBlock Text="HARDWARE" FontSize="8.5" FontWeight="SemiBold" Foreground="#8a9baa"/>
                                <TextBlock x:Name="lblCPU" Text="---" FontSize="12" FontWeight="SemiBold" Foreground="#1a2b3c" FontFamily="Consolas" Margin="0,2,0,0"/>
                                <TextBlock x:Name="lblRAMInfo" Text="" FontSize="9.5" Foreground="#5a7080"/>
                            </StackPanel>
                        </Border>
                        <Border Grid.Column="2" Background="White" CornerRadius="7" Padding="10" Margin="2,0,2,0" BorderBrush="#d8e8f0" BorderThickness="1">
                            <StackPanel>
                                <TextBlock Text="STORAGE" FontSize="8.5" FontWeight="SemiBold" Foreground="#8a9baa"/>
                                <TextBlock x:Name="lblStorage" Text="---" FontSize="12" FontWeight="SemiBold" Foreground="#1a2b3c" FontFamily="Consolas" Margin="0,2,0,0"/>
                                <TextBlock x:Name="lblStorageDetail" Text="" FontSize="9.5" Foreground="#5a7080"/>
                            </StackPanel>
                        </Border>
                        <Border Grid.Column="3" Background="White" CornerRadius="7" Padding="10" Margin="4,0,0,0" BorderBrush="#d8e8f0" BorderThickness="1">
                            <StackPanel>
                                <TextBlock Text="NETWORK" FontSize="8.5" FontWeight="SemiBold" Foreground="#8a9baa"/>
                                <TextBlock x:Name="lblNetwork" Text="---" FontSize="12" FontWeight="SemiBold" Foreground="#1a2b3c" FontFamily="Consolas" Margin="0,2,0,0"/>
                                <TextBlock x:Name="lblNetDetail" Text="" FontSize="9.5" Foreground="#5a7080"/>
                            </StackPanel>
                        </Border>
                    </Grid>

                    <!-- Health Score -->
                    <Border Background="White" CornerRadius="7" Padding="14" Margin="0,0,0,12" BorderBrush="#d8e8f0" BorderThickness="1">
                        <Grid>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/>
                            </Grid.ColumnDefinitions>
                            <Grid Grid.Column="0" Width="62" Height="62" Margin="0,0,14,0">
                                <Ellipse Stroke="#e0e8ec" StrokeThickness="5" Fill="Transparent"/>
                                <Ellipse x:Name="healthRing" Stroke="#22c55e" StrokeThickness="5" Fill="White"/>
                                <TextBlock x:Name="lblScore" Text="--" FontSize="18" FontWeight="Bold" Foreground="#16a34a" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                            </Grid>
                            <StackPanel Grid.Column="1" VerticalAlignment="Center">
                                <TextBlock Text="System Health Score" FontSize="15" FontWeight="SemiBold" Foreground="#1a2b3c"/>
                                <Border x:Name="gradeBadge" Background="#dcfce7" CornerRadius="10" Padding="8,2" HorizontalAlignment="Left" Margin="0,3,0,0">
                                    <TextBlock x:Name="lblGrade" Text="Run a diagnostic to see score" FontSize="10.5" FontWeight="SemiBold" Foreground="#16a34a"/>
                                </Border>
                                <TextBlock x:Name="lblLastScan" Text="" FontSize="9.5" Foreground="#8a9baa" Margin="0,3,0,0"/>
                            </StackPanel>
                        </Grid>
                    </Border>

                    <!-- Scan Modes -->
                    <TextBlock Text="SCAN MODES" FontSize="12" FontWeight="Bold" Foreground="#1a2b3c" Margin="0,0,0,6"/>
                    <Grid Margin="0,0,0,12">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*"/><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>
                        <Button x:Name="btnQuick" Grid.Column="0" Style="{StaticResource FlatBtn}" Background="White" BorderBrush="#d8e8f0" BorderThickness="2" Padding="10" Margin="0,0,3,0" HorizontalContentAlignment="Left">
                            <StackPanel>
                                <TextBlock Text="Quick Test" FontSize="12.5" FontWeight="SemiBold" Foreground="#1a2b3c"/>
                                <TextBlock Text="5 - 10 min" FontSize="10" Foreground="#2596be" FontFamily="Consolas" Margin="0,2,0,0"/>
                                <TextBlock Text="System info, SMART, crash history." FontSize="9.5" Foreground="#5a7080" TextWrapping="Wrap" Margin="0,3,0,0"/>
                            </StackPanel>
                        </Button>
                        <Button x:Name="btnStandard" Grid.Column="1" Style="{StaticResource FlatBtn}" Background="White" BorderBrush="#2596be" BorderThickness="2" Padding="10" Margin="1,0,2,0" HorizontalContentAlignment="Left">
                            <StackPanel>
                                <TextBlock Text="Standard" FontSize="12.5" FontWeight="SemiBold" Foreground="#1a2b3c"/>
                                <TextBlock Text="20 - 30 min" FontSize="10" Foreground="#2596be" FontFamily="Consolas" Margin="0,2,0,0"/>
                                <TextBlock Text="Diagnostics + stress tests." FontSize="9.5" Foreground="#5a7080" TextWrapping="Wrap" Margin="0,3,0,0"/>
                            </StackPanel>
                        </Button>
                        <Button x:Name="btnFull" Grid.Column="2" Style="{StaticResource FlatBtn}" Background="White" BorderBrush="#d8e8f0" BorderThickness="2" Padding="10" Margin="2,0,1,0" HorizontalContentAlignment="Left">
                            <StackPanel>
                                <TextBlock Text="Deep Test" FontSize="12.5" FontWeight="SemiBold" Foreground="#1a2b3c"/>
                                <TextBlock Text="60 - 90 min" FontSize="10" Foreground="#2596be" FontFamily="Consolas" Margin="0,2,0,0"/>
                                <TextBlock Text="Extended stress + thermal." FontSize="9.5" Foreground="#5a7080" TextWrapping="Wrap" Margin="0,3,0,0"/>
                            </StackPanel>
                        </Button>
                        <Button x:Name="btnMRI" Grid.Column="3" Style="{StaticResource FlatBtn}" Background="#0a3a56" BorderBrush="#2596be" BorderThickness="2" Padding="10" Margin="3,0,0,0" HorizontalContentAlignment="Left">
                            <StackPanel>
                                <TextBlock Text="Full MRI" FontSize="12.5" FontWeight="Bold" Foreground="#3bbde0"/>
                                <TextBlock Text="90 - 120 min" FontSize="10" Foreground="#5aafcc" FontFamily="Consolas" Margin="0,2,0,0"/>
                                <TextBlock Text="Everything. MRI + X-Ray." FontSize="9.5" Foreground="#8ab8cc" TextWrapping="Wrap" Margin="0,3,0,0"/>
                            </StackPanel>
                        </Button>
                    </Grid>

                    <!-- Individual Tests -->
                    <TextBlock Text="INDIVIDUAL TESTS" FontSize="12" FontWeight="Bold" Foreground="#1a2b3c" Margin="0,0,0,6"/>
                    <Grid Margin="0,0,0,10">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*"/><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>
                        <Grid.RowDefinitions>
                            <RowDefinition Height="30"/><RowDefinition Height="30"/><RowDefinition Height="30"/><RowDefinition Height="30"/><RowDefinition Height="30"/><RowDefinition Height="30"/><RowDefinition Height="30"/>
                        </Grid.RowDefinitions>
                        <Border Grid.Row="0" Grid.Column="0" Background="White" CornerRadius="4" Padding="6,4" Margin="1" BorderBrush="#d8e8f0" BorderThickness="1">
                            <CheckBox x:Name="chkCPU" Content=" CPU Stress Test" FontSize="11" Foreground="#1a2b3c" VerticalContentAlignment="Center"/>
                        </Border>
                        <Border Grid.Row="0" Grid.Column="1" Background="White" CornerRadius="4" Padding="6,4" Margin="1" BorderBrush="#d8e8f0" BorderThickness="1">
                            <CheckBox x:Name="chkRAM" Content=" RAM Test" FontSize="11" Foreground="#1a2b3c" VerticalContentAlignment="Center"/>
                        </Border>
                        <Border Grid.Row="0" Grid.Column="2" Background="White" CornerRadius="4" Padding="6,4" Margin="1" BorderBrush="#d8e8f0" BorderThickness="1">
                            <CheckBox x:Name="chkDisk" Content=" Disk Benchmark" FontSize="11" Foreground="#1a2b3c" VerticalContentAlignment="Center"/>
                        </Border>
                        <Border Grid.Row="1" Grid.Column="0" Background="White" CornerRadius="4" Padding="6,4" Margin="1" BorderBrush="#d8e8f0" BorderThickness="1">
                            <CheckBox x:Name="chkSMART" Content=" SMART Check" FontSize="11" Foreground="#1a2b3c" VerticalContentAlignment="Center"/>
                        </Border>
                        <Border Grid.Row="1" Grid.Column="1" Background="White" CornerRadius="4" Padding="6,4" Margin="1" BorderBrush="#d8e8f0" BorderThickness="1">
                            <CheckBox x:Name="chkBattery" Content=" Battery Report" FontSize="11" Foreground="#1a2b3c" VerticalContentAlignment="Center"/>
                        </Border>
                        <Border Grid.Row="1" Grid.Column="2" Background="White" CornerRadius="4" Padding="6,4" Margin="1" BorderBrush="#d8e8f0" BorderThickness="1">
                            <CheckBox x:Name="chkNetwork" Content=" Network Test" FontSize="11" Foreground="#1a2b3c" VerticalContentAlignment="Center"/>
                        </Border>
                        <Border Grid.Row="2" Grid.Column="0" Background="White" CornerRadius="4" Padding="6,4" Margin="1" BorderBrush="#d8e8f0" BorderThickness="1">
                            <CheckBox x:Name="chkSecurity" Content=" Security Audit" FontSize="11" Foreground="#1a2b3c" VerticalContentAlignment="Center"/>
                        </Border>
                        <Border Grid.Row="2" Grid.Column="1" Background="White" CornerRadius="4" Padding="6,4" Margin="1" BorderBrush="#d8e8f0" BorderThickness="1">
                            <CheckBox x:Name="chkKeys" Content=" License Keys" FontSize="11" Foreground="#1a2b3c" VerticalContentAlignment="Center"/>
                        </Border>
                        <Border Grid.Row="2" Grid.Column="2" Background="White" CornerRadius="4" Padding="6,4" Margin="1" BorderBrush="#d8e8f0" BorderThickness="1">
                            <CheckBox x:Name="chkDebloat" Content=" Windows Debloat" FontSize="11" Foreground="#cc2222" VerticalContentAlignment="Center"/>
                        </Border>
                        <Border Grid.Row="3" Grid.Column="0" Background="White" CornerRadius="4" Padding="6,4" Margin="1" BorderBrush="#d8e8f0" BorderThickness="1">
                            <CheckBox x:Name="chkRAMIso" Content=" RAM Isolation" FontSize="11" Foreground="#1a2b3c" VerticalContentAlignment="Center"/>
                        </Border>
                        <Border Grid.Row="3" Grid.Column="1" Background="White" CornerRadius="4" Padding="6,4" Margin="1" BorderBrush="#d8e8f0" BorderThickness="1">
                            <CheckBox x:Name="chkPassRecovery" Content=" Password Recovery" FontSize="11" Foreground="#1a2b3c" VerticalContentAlignment="Center"/>
                        </Border>
                        <Border Grid.Row="3" Grid.Column="2" Background="White" CornerRadius="4" Padding="6,4" Margin="1" BorderBrush="#d8e8f0" BorderThickness="1">
                            <CheckBox x:Name="chkWinDeep" Content=" Windows Deep Test" FontSize="11" Foreground="#1a2b3c" VerticalContentAlignment="Center"/>
                        </Border>
                        <Border Grid.Row="4" Grid.Column="0" Background="White" CornerRadius="4" Padding="6,4" Margin="1" BorderBrush="#d8e8f0" BorderThickness="1">
                            <CheckBox x:Name="chkNirSoft" Content=" NirSoft Suite" FontSize="11" Foreground="#1a2b3c" VerticalContentAlignment="Center"/>
                        </Border>
                        <Border Grid.Row="4" Grid.Column="1" Background="White" CornerRadius="4" Padding="6,4" Margin="1" BorderBrush="#d8e8f0" BorderThickness="1">
                            <CheckBox x:Name="chkSSDLife" Content=" SSD Life Report" FontSize="11" Foreground="#1a2b3c" VerticalContentAlignment="Center"/>
                        </Border>
                        <Border Grid.Row="4" Grid.Column="2" Background="White" CornerRadius="4" Padding="6,4" Margin="1" BorderBrush="#d8e8f0" BorderThickness="1">
                            <CheckBox x:Name="chkGPU" Content=" GPU Stress Test" FontSize="11" Foreground="#1a2b3c" VerticalContentAlignment="Center"/>
                        </Border>
                        <Border Grid.Row="5" Grid.Column="0" Background="#fdf4ff" CornerRadius="4" Padding="6,4" Margin="1" BorderBrush="#e879f9" BorderThickness="1">
                            <CheckBox x:Name="chkWearTear" Content=" Wear &amp; Tear" FontSize="11" Foreground="#7e22ce" VerticalContentAlignment="Center"/>
                        </Border>
                        <Border Grid.Row="5" Grid.Column="1" Background="White" CornerRadius="4" Padding="6,4" Margin="1" BorderBrush="#d8e8f0" BorderThickness="1">
                            <CheckBox x:Name="chkSpeedTest" Content=" Speed Test" FontSize="11" Foreground="#1a2b3c" VerticalContentAlignment="Center"/>
                        </Border>
                        <Border Grid.Row="5" Grid.Column="2" Background="White" CornerRadius="4" Padding="6,4" Margin="1" BorderBrush="#d8e8f0" BorderThickness="1">
                            <CheckBox x:Name="chkThermal" Content=" Thermal Check" FontSize="11" Foreground="#1a2b3c" VerticalContentAlignment="Center"/>
                        </Border>
                        <Border Grid.Row="6" Grid.Column="0" Background="#ecfeff" CornerRadius="4" Padding="6,4" Margin="1" BorderBrush="#06b6d4" BorderThickness="1">
                            <CheckBox x:Name="chkLCDDisplay" Content=" LCD Display" FontSize="11" Foreground="#0e7490" VerticalContentAlignment="Center"/>
                        </Border>
                    </Grid>

                    <!-- Run Bar -->
                    <Border Background="White" CornerRadius="7" Padding="12" Margin="0,0,0,8" BorderBrush="#d8e8f0" BorderThickness="1">
                        <Grid>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/>
                            </Grid.ColumnDefinitions>
                            <Button x:Name="btnRunSelected" Style="{StaticResource FlatBtn}" Background="#2596be" Padding="18,9">
                                <TextBlock x:Name="lblRunBtn" Text="RUN SELECTED TESTS" FontSize="12" FontWeight="Bold" Foreground="White"/>
                            </Button>
                            <Button x:Name="btnAbort" Grid.Column="1" Style="{StaticResource FlatBtn}" Background="#dc2626" Padding="14,9" Margin="6,0,0,0" Visibility="Collapsed">
                                <TextBlock Text="STOP" FontSize="12" FontWeight="Bold" Foreground="White"/>
                            </Button>
                            <StackPanel Grid.Column="2" Margin="12,0,0,0" VerticalAlignment="Center">
                                <TextBlock x:Name="lblSelectedCount" Text="0 tests selected" FontSize="11.5" FontWeight="SemiBold" Foreground="#1a2b3c"/>
                                <TextBlock x:Name="lblEstTime" Text="Select tests to begin" FontSize="9.5" Foreground="#8a9baa"/>
                            </StackPanel>
                            <StackPanel Grid.Column="3" Orientation="Horizontal" VerticalAlignment="Center">
                                <Border Background="#dcfce7" CornerRadius="10" Padding="8,3" Margin="0,0,8,0">
                                    <TextBlock x:Name="lblReadyStatus" Text="Ready" FontSize="10.5" FontWeight="SemiBold" Foreground="#22c55e"/>
                                </Border>
                                <CheckBox x:Name="chkBeep" Content=" Beep on done" FontSize="10" Foreground="#8a9baa" IsChecked="True" VerticalAlignment="Center"/>
                            </StackPanel>
                        </Grid>
                    </Border>
                </StackPanel>
            </ScrollViewer>

            <!-- Status Bar -->
            <Border Grid.Row="1" Background="White" BorderBrush="#d8e8f0" BorderThickness="0,1,0,0" Padding="16,8">
                <Grid>
                    <Grid.RowDefinitions><RowDefinition/><RowDefinition/></Grid.RowDefinitions>
                    <TextBlock x:Name="txtStatus" Grid.Row="0" Text="Ready. Enter customer info and select a diagnostic mode." FontSize="10.5" Foreground="#5a7080" Margin="0,0,0,4"/>
                    <ProgressBar x:Name="progressBar" Grid.Row="1" Height="5" Background="#e0e8ec" Foreground="#2596be" Value="0" BorderThickness="0"/>
                </Grid>
            </Border>
        </Grid>
    </Grid>
</Window>
"@

    Write-DebugLog "Parsing XAML..."
    $reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($xaml))
    $window = [System.Windows.Markup.XamlReader]::Load($reader)
    Write-DebugLog "XAML parsed OK, window created"

    # Get controls
    $txtCustomer = $window.FindName("txtCustomer")
    $txtPhone = $window.FindName("txtPhone")
    $txtEmail = $window.FindName("txtEmail")
    $txtContact = $window.FindName("txtContact")
    $txtTech = $window.FindName("txtTech")
    $txtNotes = $window.FindName("txtNotes")
    $txtDeviceName = $window.FindName("txtDeviceName")
    $txtStatus = $window.FindName("txtStatus")
    $progressBar = $window.FindName("progressBar")
    $btnAbort = $window.FindName("btnAbort")
    $Global:AbortRequested = $false
    $lblComputer = $window.FindName("lblComputer")
    $lblOS = $window.FindName("lblOS")
    $lblCPU = $window.FindName("lblCPU")
    $lblRAMInfo = $window.FindName("lblRAMInfo")
    $lblStorage = $window.FindName("lblStorage")
    $lblStorageDetail = $window.FindName("lblStorageDetail")
    $lblNetwork = $window.FindName("lblNetwork")
    $lblNetDetail = $window.FindName("lblNetDetail")
    $lblScore = $window.FindName("lblScore")
    $lblGrade = $window.FindName("lblGrade")
    $lblLastScan = $window.FindName("lblLastScan")
    $lblSelectedCount = $window.FindName("lblSelectedCount")
    $lblEstTime = $window.FindName("lblEstTime")
    $lblReadyStatus = $window.FindName("lblReadyStatus")
    $chkBeep = $window.FindName("chkBeep")
    $chkCPU = $window.FindName("chkCPU")
    $chkRAM = $window.FindName("chkRAM")
    $chkDisk = $window.FindName("chkDisk")
    $chkSMART = $window.FindName("chkSMART")
    $chkBattery = $window.FindName("chkBattery")
    $chkNetwork = $window.FindName("chkNetwork")
    $chkSecurity = $window.FindName("chkSecurity")
    $chkKeys = $window.FindName("chkKeys")
    $chkDebloat = $window.FindName("chkDebloat")
    $chkRAMIso = $window.FindName("chkRAMIso")
    $chkPassRecovery = $window.FindName("chkPassRecovery")
    $chkWinDeep = $window.FindName("chkWinDeep")
    $chkNirSoft = $window.FindName("chkNirSoft")
    $chkSSDLife = $window.FindName("chkSSDLife")
    $chkGPU = $window.FindName("chkGPU")
    $chkWearTear = $window.FindName("chkWearTear")
    $chkSpeedTest = $window.FindName("chkSpeedTest")
    $chkThermal = $window.FindName("chkThermal")
    $chkLCDDisplay = $window.FindName("chkLCDDisplay")

    $allTestCheckboxes = @($chkCPU,$chkRAM,$chkDisk,$chkSMART,$chkBattery,$chkNetwork,$chkSecurity,$chkKeys,$chkDebloat,$chkRAMIso,$chkPassRecovery,$chkWinDeep,$chkNirSoft,$chkSSDLife,$chkGPU,$chkWearTear,$chkSpeedTest,$chkThermal,$chkLCDDisplay)
    foreach ($cb in $allTestCheckboxes) {
        if ($cb) {
            $cb.Add_Checked({ Clear-ScanModeSelection; Update-CheckboxCount })
            $cb.Add_Unchecked({ Update-CheckboxCount })
        }
    }
    function Update-CheckboxCount {
        $count = ($allTestCheckboxes | Where-Object { $_ -and $_.IsChecked }).Count
        if ($count -gt 0 -and -not $Global:SelectedScanMode) {
            $lblSelectedCount.Text = "$count tests selected"
            $lblEstTime.Text = "Click RUN to start"
        } elseif (-not $Global:SelectedScanMode) {
            $lblSelectedCount.Text = "0 tests selected"
            $lblEstTime.Text = "Select a scan mode or individual tests"
        }
    }

    $tools = Get-ToolStatus

    function Set-Status { param([string]$Msg, [int]$Pct = -1)
        $txtStatus.Text = $Msg
        if ($Pct -ge 0) { $progressBar.Value = $Pct }
        $window.Title = "PC Plus 360 - $Msg"
        Write-DebugLog "STATUS: $Msg ($Pct%)"
        $frame = New-Object System.Windows.Threading.DispatcherFrame
        [System.Windows.Threading.Dispatcher]::CurrentDispatcher.BeginInvoke(
            [System.Windows.Threading.DispatcherPriority]::Background,
            [System.Action]{ $frame.Continue = $false }
        )
        [System.Windows.Threading.Dispatcher]::PushFrame($frame)
    }

    function Get-Params {
        if ([string]::IsNullOrWhiteSpace($txtCustomer.Text)) {
            Write-DebugLog "Validation failed: Customer Name is empty"
            [System.Windows.MessageBox]::Show($window, "Please enter a Customer Name before running tests.", "Customer Name Required", "OK", "Warning")
            $txtCustomer.Focus()
            return $null
        }
        if ([string]::IsNullOrWhiteSpace($txtPhone.Text)) {
            Write-DebugLog "Validation failed: Phone is empty"
            [System.Windows.MessageBox]::Show($window, "Please enter a Phone Number before running tests.", "Phone Number Required", "OK", "Warning")
            $txtPhone.Focus()
            return $null
        }
        Write-DebugLog "Params OK: Customer=$($txtCustomer.Text.Trim()), Phone=$($txtPhone.Text.Trim())"
        return @{ CustomerName = $txtCustomer.Text.Trim(); CustomerPhone = $txtPhone.Text.Trim(); CustomerEmail = $txtEmail.Text.Trim(); ContactName = $txtContact.Text.Trim(); TechName = $txtTech.Text.Trim(); TechNotes = $txtNotes.Text.Trim(); OutputFolder = $Global:ReportsDir }
    }

    function Update-SystemInfo {
        if ($Global:DiagResults.SystemInfo) {
            $si = $Global:DiagResults.SystemInfo
            $lblComputer.Text = $si.ComputerName
            $lblOS.Text = ($si.OSVersion -replace 'Microsoft ','')
            $cpuName = ($si.CPUModel -replace '\(R\)','' -replace '\(TM\)','' -replace 'CPU ','').Trim()
            if ($cpuName.Length -gt 20) { $cpuName = $cpuName.Substring(0,20) }
            $lblCPU.Text = $cpuName
            $lblRAMInfo.Text = "$($si.RAMTotal) GB RAM"
            $d = $si.Disks | Select-Object -First 1
            if ($d) { $lblStorage.Text = "$($d.Size) GB"; $lblStorageDetail.Text = "$($d.Free) GB free ($($d.UsedPct)%)" }
            if ($Global:DiagResults.Network) {
                $n = $Global:DiagResults.Network
                $lblNetwork.Text = if ($n.InternetTest.Success) { "Online" } else { "Offline" }
                $lblNetDetail.Text = if ($n.PublicIP) { $n.PublicIP } else { "" }
            }
        }
    }

    function Update-HealthScore {
        if ($Global:DiagResults.Scoring) {
            $s = $Global:DiagResults.Scoring
            $lblScore.Text = "$($s.Score)"
            $gradeText = if ($s.Score -ge 80) { "Good" } elseif ($s.Score -ge 60) { "Fair" } else { "Needs Attention" }
            $lblGrade.Text = "Grade $($s.Grade) - $gradeText"
            $lblLastScan.Text = "Last scan: $(Get-Date -Format 'MMM dd, yyyy') - $($Global:DiagResults.ScanMode) Test"
            $converter = New-Object System.Windows.Media.BrushConverter
            if ($s.Score -ge 80) {
                $window.FindName("healthRing").Stroke = $converter.ConvertFrom("#22c55e")
                $lblScore.Foreground = $converter.ConvertFrom("#16a34a")
                $window.FindName("gradeBadge").Background = $converter.ConvertFrom("#dcfce7")
                $lblGrade.Foreground = $converter.ConvertFrom("#16a34a")
            } elseif ($s.Score -ge 60) {
                $window.FindName("healthRing").Stroke = $converter.ConvertFrom("#f59e0b")
                $lblScore.Foreground = $converter.ConvertFrom("#d97706")
                $window.FindName("gradeBadge").Background = $converter.ConvertFrom("#fef3c7")
                $lblGrade.Foreground = $converter.ConvertFrom("#d97706")
            } else {
                $window.FindName("healthRing").Stroke = $converter.ConvertFrom("#dc2626")
                $lblScore.Foreground = $converter.ConvertFrom("#dc2626")
                $window.FindName("gradeBadge").Background = $converter.ConvertFrom("#fee2e2")
                $lblGrade.Foreground = $converter.ConvertFrom("#dc2626")
            }
        }
    }

    function Play-CompletionBeep {
        if ($chkBeep.IsChecked) {
            try { [Console]::Beep(800, 200); Start-Sleep -Milliseconds 100; [Console]::Beep(1000, 200); Start-Sleep -Milliseconds 100; [Console]::Beep(1200, 300) } catch {}
        }
    }

    function Complete-Scan {
        Update-SystemInfo
        Update-HealthScore
        Play-CompletionBeep
        $lblReadyStatus.Text = "Done"
    }

    function Invoke-SaveBenchmark {
        param([string]$TestType = "Standard")
        try {
            $si = $Global:DiagResults.SystemInfo
            if (-not $si) { Write-DiagLog "No SystemInfo for benchmark save, skipping" "WARN"; return }
            $cpuModel = if ($si.CPUModel) { $si.CPUModel } else { "Unknown" }
            $gpuModel = if ($si.GPUs -and $si.GPUs.Count -gt 0) { $si.GPUs[0].Name } else { "Unknown" }
            $ramTotal = if ($si.RAMTotal) { [double]$si.RAMTotal } else { 0 }
            $storageType = "Unknown"
            if ($si.SMART -and $si.SMART.Count -gt 0) {
                $mt = $si.SMART[0].MediaType; $bt = $si.SMART[0].BusType
                if ($bt -match 'NVMe') { $storageType = "NVMe" }
                elseif ($mt -match 'SSD' -or $mt -match 'Solid') { $storageType = "SSD" }
                elseif ($mt -match 'HDD' -or $mt -match 'Unspecified') { $storageType = "HDD" }
                else { $storageType = "$mt" }
            }
            # Build normalized scores hashtable
            $scores = @{ Overall = 0; Thermal = 0; Storage = 0; Network = 0; Security = 0; Grade = "N/A" }
            # Pull from Scoring if available
            if ($Global:DiagResults.Scoring) {
                $scores.Security = if ($Global:DiagResults.Scoring.Score) { $Global:DiagResults.Scoring.Score } else { 0 }
            }
            # Pull from stress results for storage
            if ($Global:DiagResults.DiskBench -and $Global:DiagResults.DiskBench.SeqReadMBps) {
                $r = $Global:DiagResults.DiskBench.SeqReadMBps
                $scores.Storage = if ($r -gt 1000) { 100 } elseif ($r -gt 300) { 80 } elseif ($r -gt 100) { 55 } else { 25 }
            }
            # Network from Network diag
            if ($Global:DiagResults.Network -and $Global:DiagResults.Network.InternetTest) {
                $scores.Network = if ($Global:DiagResults.Network.InternetTest.Success) { 80 } else { 20 }
            }
            if ($Global:DiagResults.SpeedTest -and $Global:DiagResults.SpeedTest.DownloadMbps -and $Global:DiagResults.SpeedTest.DownloadMbps -ne "N/A") {
                $dl = 0; try { $dl = [double]($Global:DiagResults.SpeedTest.DownloadMbps -replace '[^\d.]','') } catch {}
                if ($dl -gt 100) { $scores.Network = 95 } elseif ($dl -gt 50) { $scores.Network = 80 } elseif ($dl -gt 20) { $scores.Network = 65 } elseif ($dl -gt 5) { $scores.Network = 45 }
            }
            # Thermal from stress test
            if ($Global:DiagResults.CPUStress -and $Global:DiagResults.CPUStress.MaxTemp) {
                $t = $Global:DiagResults.CPUStress.MaxTemp
                $scores.Thermal = if ($t -lt 60) { 100 } elseif ($t -lt 70) { 90 } elseif ($t -lt 80) { 75 } elseif ($t -lt 90) { 55 } else { 30 }
            } elseif ($Global:DiagResults.Thermal -and $Global:DiagResults.Thermal.CPUTemp) {
                $t = $Global:DiagResults.Thermal.CPUTemp
                $scores.Thermal = if ($t -lt 50) { 100 } elseif ($t -lt 60) { 85 } elseif ($t -lt 70) { 70 } elseif ($t -lt 80) { 55 } else { 35 }
            }
            # Overall weighted average
            $wSum = 0; $wTotal = 0
            if ($scores.Thermal -gt 0) { $wSum += $scores.Thermal * 25; $wTotal += 25 }
            if ($scores.Storage -gt 0) { $wSum += $scores.Storage * 25; $wTotal += 25 }
            if ($scores.Network -gt 0) { $wSum += $scores.Network * 20; $wTotal += 20 }
            if ($scores.Security -gt 0) { $wSum += $scores.Security * 30; $wTotal += 30 }
            if ($wTotal -gt 0) { $scores.Overall = [math]::Round($wSum / $wTotal) } else { $scores.Overall = 50 }
            $scores.Overall = [math]::Max(0, [math]::Min(100, $scores.Overall))
            $scores.Grade = if ($scores.Overall -ge 90){"A"} elseif ($scores.Overall -ge 80){"B"} elseif ($scores.Overall -ge 70){"C"} elseif ($scores.Overall -ge 60){"D"} else{"F"}
            # For Gaming Performance Test, override with its scores
            if ($TestType -eq "Gaming" -and $Global:DiagResults.GamingPerformance) {
                $gp = $Global:DiagResults.GamingPerformance.Scores
                $scores.Overall = if ($gp.Overall) { $gp.Overall } else { $scores.Overall }
                $scores.Thermal = if ($gp.Thermal) { $gp.Thermal } else { $scores.Thermal }
                $scores.Network = if ($gp.NetworkScore) { $gp.NetworkScore } else { $scores.Network }
                $scores.Grade   = if ($gp.Grade) { $gp.Grade } else { $scores.Grade }
                if ($gp.FPSStability) { $scores.FPSStability = $gp.FPSStability }
                if ($gp.PowerStability) { $scores.PowerStability = $gp.PowerStability }
            }
            Save-BenchmarkResult -ComputerName $si.ComputerName -CPUModel $cpuModel -GPUModel $gpuModel -RAMTotal $ramTotal -StorageType $storageType -Scores $scores -TestType $TestType
        } catch {
            Write-DiagLog "Benchmark save failed: $($_.Exception.Message)" "WARN"
        }
    }

    # Checkbox count update
    $updateCount = {
        $allChecks = @($chkCPU,$chkRAM,$chkDisk,$chkSMART,$chkBattery,$chkNetwork,$chkSecurity,$chkKeys,$chkDebloat,$chkRAMIso,$chkPassRecovery,$chkWinDeep,$chkNirSoft,$chkSSDLife,$chkGPU,$chkWearTear,$chkSpeedTest,$chkThermal)
        $count = ($allChecks | Where-Object { $_.IsChecked }).Count
        $lblSelectedCount.Text = "$count tests selected"
        if ($count -gt 0) {
            $inlineCnt = @($chkCPU,$chkRAM,$chkDisk,$chkSMART,$chkBattery,$chkNetwork,$chkSecurity,$chkKeys,$chkSSDLife,$chkGPU,$chkWearTear,$chkSpeedTest,$chkThermal).Where({$_.IsChecked}).Count
            $extCnt = @($chkDebloat,$chkRAMIso,$chkPassRecovery,$chkWinDeep,$chkNirSoft).Where({$_.IsChecked}).Count
            $mins = ($inlineCnt * 2) + ($extCnt * 5)
            if ($chkGPU.IsChecked) { $mins += 1 }
            if ($chkWinDeep.IsChecked) { $mins += 10 }
            if ($chkWearTear.IsChecked) { $mins += 3 }
            if ($chkSpeedTest.IsChecked) { $mins += 2 }
            if ($mins -lt 1) { $mins = 1 }
            $lblEstTime.Text = "Estimated: ~$mins min"
        } else { $lblEstTime.Text = "Select tests to begin" }
    }
    foreach ($chk in @($chkCPU,$chkRAM,$chkDisk,$chkSMART,$chkBattery,$chkNetwork,$chkSecurity,$chkKeys,$chkDebloat,$chkRAMIso,$chkPassRecovery,$chkWinDeep,$chkNirSoft,$chkSSDLife,$chkGPU,$chkWearTear,$chkSpeedTest,$chkThermal)) {
        $chk.Add_Checked($updateCount)
        $chk.Add_Unchecked($updateCount)
    }

    # Portable tool detection
    foreach ($btn in @(@{N="btnCDI";T=$tools.CrystalDiskInfo},@{N="btnHWiNFO";T=$tools.HWiNFO},@{N="btnCPUZ";T=$tools.CPUZ},@{N="btnGPUZ";T=$tools.GPUZ},@{N="btnHWMon";T=$tools.HWMonitor},@{N="btnBattView";T=$tools.BatteryInfoView})) {
        $b = $window.FindName($btn.N)
        if (-not $btn.T) { $b.IsEnabled = $false; $b.Opacity = 0.4 }
    }
    $toolPaths = @{
        btnCDI = $tools.CrystalDiskInfo; btnHWiNFO = $tools.HWiNFO
        btnCPUZ = $tools.CPUZ; btnGPUZ = $tools.GPUZ
        btnHWMon = $tools.HWMonitor; btnBattView = $tools.BatteryInfoView
    }
    foreach ($key in $toolPaths.Keys) {
        $b = $window.FindName($key)
        if ($toolPaths[$key]) {
            $b.Tag = $toolPaths[$key]
            $b.Add_Click({ param($sender,$e); Start-Process $sender.Tag -ErrorAction SilentlyContinue })
        }
    }

    # Sidebar tool nav buttons
    $window.FindName("btnNavNirSoft").Add_Click({
        $s = Join-Path $Global:ScriptDir "PCPlus-NirSoftSuite.ps1"
        if (Test-Path $s) { Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$s`"" -Verb RunAs }
        else { [System.Windows.MessageBox]::Show($window, "PCPlus-NirSoftSuite.ps1 not found in $Global:ScriptDir", "Not Found", "OK", "Warning") }
    })
    $window.FindName("btnNavPassRecovery").Add_Click({
        $s = Join-Path $Global:ScriptDir "PCPlus-PasswordRecovery.ps1"
        if (Test-Path $s) { Start-Process powershell.exe -ArgumentList "-STA -NoProfile -ExecutionPolicy Bypass -File `"$s`"" -Verb RunAs }
        else { [System.Windows.MessageBox]::Show($window, "PCPlus-PasswordRecovery.ps1 not found in $Global:ScriptDir", "Not Found", "OK", "Warning") }
    })
    $window.FindName("btnNavWinDeep").Add_Click({
        $s = Join-Path $Global:ScriptDir "PCPlus-WindowsDeepTest.ps1"
        if (Test-Path $s) { Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$s`"" -Verb RunAs }
        else { [System.Windows.MessageBox]::Show($window, "PCPlus-WindowsDeepTest.ps1 not found in $Global:ScriptDir", "Not Found", "OK", "Warning") }
    })
    $window.FindName("btnNavDebloat").Add_Click({
        $s = Join-Path $Global:ScriptDir "PCPlus-Debloat.ps1"
        if (Test-Path $s) { Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$s`"" -Verb RunAs }
        else { [System.Windows.MessageBox]::Show($window, "PCPlus-Debloat.ps1 not found in $Global:ScriptDir", "Not Found", "OK", "Warning") }
    })
    $window.FindName("btnNavRAMIso").Add_Click({
        $s = Join-Path $Global:ScriptDir "PCPlus-RAMIsolation.ps1"
        if (Test-Path $s) { Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$s`"" -Verb RunAs }
        else { [System.Windows.MessageBox]::Show($window, "PCPlus-RAMIsolation.ps1 not found in $Global:ScriptDir", "Not Found", "OK", "Warning") }
    })
    $window.FindName("btnNavWearTear").Add_Click({
        $p = Get-Params; if (-not $p) { return }
        Set-ScanButtons $false
        $lblReadyStatus.Text = "Running..."
        try {
            Set-Status "Running Wear & Tear lifecycle analysis..." 10
            if (-not $Global:DiagResults.SystemInfo) {
                Set-Status "Collecting system info first..." 5
                $Global:DiagResults.SystemInfo = Get-FullSystemInfo
                Update-SystemInfo
            }
            $Global:DiagResults.WearTear = Invoke-WearAndTearReport
            $wt = $Global:DiagResults.WearTear
            Set-Status "Generating Wear & Tear report..." 70
            $wtHTML = Build-WearAndTearHTMLReport -Params $p -SystemInfo $Global:DiagResults.SystemInfo -WearTear $wt
            $safeName = $p.CustomerName -replace '[\\/:*?"<>|]','_'
            $safeDev = $Global:DiagResults.SystemInfo.ComputerName -replace '[\\/:*?"<>|]','_'
            $ds = Get-Date -Format "yyyy-MM-dd"
            $wtHTMLPath = Join-Path $p.OutputFolder "$safeName - $safeDev - Wear and Tear Report $ds.html"
            $wtPDFPath = Join-Path $p.OutputFolder "$safeName - $safeDev - Wear and Tear Report $ds.pdf"
            [IO.File]::WriteAllText($wtHTMLPath, $wtHTML, [Text.Encoding]::UTF8)
            $pdfOK = Convert-ToPDF $wtHTMLPath $wtPDFPath
            Invoke-Safe { Invoke-AutoUploadReport -ReportPath $(if($pdfOK){$wtPDFPath}else{$wtHTMLPath}) -CustomerName $p.CustomerName -ComputerName $Global:DiagResults.SystemInfo.ComputerName -TechName $p.TechName -ScanMode "Wear and Tear" }
            Set-Status "Wear & Tear: Score=$($wt.Score)/100 ($($wt.Grade)) - $($wt.RiskLevel) risk" 100
            Complete-Scan
            Start-Process explorer.exe -ArgumentList $p.OutputFolder
            [System.Windows.MessageBox]::Show($window, "Wear & Tear Report Complete!`n`nScore: $($wt.Score)/100 ($($wt.Grade))`nRisk: $($wt.RiskLevel)`nEst. Life: $($wt.EstimatedLifeYears) years`n`n$(($wt.Recommendations | Select-Object -First 3) -join "`n")", "Wear & Tear Complete", "OK", "Information")
        } catch {
            Write-DebugLog "Wear&Tear ERROR: $($_.Exception.Message)"
            Set-Status "ERROR: $($_.Exception.Message)" 0
            [System.Windows.MessageBox]::Show($window, "Error: $($_.Exception.Message)", "Error", "OK", "Error")
        } finally { Set-ScanButtons $true; $lblReadyStatus.Text = "Ready" }
    })

    # Startup: populate system info cards immediately
    $window.Add_Loaded({
        try {
            $cs = Get-CimInstance Win32_ComputerSystem
            $os = Get-CimInstance Win32_OperatingSystem
            $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
            $lblComputer.Text = $cs.Name
            $txtDeviceName.Text = $cs.Name
            $lblOS.Text = ($os.Caption -replace 'Microsoft ','')
            $cpuName = ($cpu.Name -replace '\(R\)','' -replace '\(TM\)','' -replace 'CPU ','').Trim()
            if ($cpuName.Length -gt 20) { $cpuName = $cpuName.Substring(0,20) }
            $lblCPU.Text = $cpuName
            $lblRAMInfo.Text = "$([math]::Round($cs.TotalPhysicalMemory / 1GB)) GB RAM"
            $disk = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" | Select-Object -First 1
            if ($disk) {
                $lblStorage.Text = "$([math]::Round($disk.Size / 1GB)) GB"
                $lblStorageDetail.Text = "$([math]::Round($disk.FreeSpace / 1GB)) GB free"
            }
            $adapter = Get-CimInstance Win32_NetworkAdapterConfiguration | Where-Object { $_.IPEnabled -and $_.DefaultIPGateway } | Select-Object -First 1
            if ($adapter) { $lblNetwork.Text = "Connected"; $lblNetDetail.Text = $adapter.IPAddress[0] }
        } catch { Write-DebugLog "Startup info error: $($_.Exception.Message)" }
    })

    function Set-ScanButtons($enabled) {
        foreach ($bn in @("btnQuick","btnStandard","btnFull","btnMRI","btnRunSelected","btnQuickScan","btnNavWearTear")) {
            $b = $window.FindName($bn)
            if ($b) { $b.IsEnabled = $enabled }
        }
        if ($enabled) {
            $btnAbort.Visibility = "Collapsed"
            $Global:AbortRequested = $false
        } else {
            $btnAbort.Visibility = "Visible"
        }
    }

    $btnAbort.Add_Click({
        $Global:AbortRequested = $true
        $btnAbort.IsEnabled = $false
        $txtStatus.Text = "Stopping... will halt after current test finishes."
        Write-DebugLog "ABORT requested by user"
    })

    function Test-AbortRequested {
        if ($Global:AbortRequested) {
            Set-Status "Test aborted by user." 0
            $lblReadyStatus.Text = "Aborted"
            Set-ScanButtons $true
            return $true
        }
        return $false
    }

    $scanModeButtons = @{
        Quick    = $window.FindName("btnQuick")
        Standard = $window.FindName("btnStandard")
        Deep     = $window.FindName("btnFull")
        MRI      = $window.FindName("btnMRI")
    }
    $scanModeEstimates = @{ Quick = "5 - 10 min"; Standard = "20 - 30 min"; Deep = "60 - 90 min"; MRI = "90 - 120 min" }

    function Select-ScanMode($mode) {
        $Global:SelectedScanMode = $mode
        foreach ($key in @("Quick","Standard","Deep","MRI")) {
            $btn = $scanModeButtons[$key]
            if ($key -eq $mode) {
                if ($key -eq "MRI") {
                    $btn.Background = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#0d4b71")
                    $btn.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#3bbde0")
                    $btn.BorderThickness = [System.Windows.Thickness]::new(3)
                } else {
                    $btn.Background = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#e8f4fa")
                    $btn.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#2596be")
                    $btn.BorderThickness = [System.Windows.Thickness]::new(3)
                }
            } else {
                if ($key -eq "MRI") {
                    $btn.Background = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#0a3a56")
                    $btn.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#2596be")
                    $btn.BorderThickness = [System.Windows.Thickness]::new(2)
                } else {
                    $btn.Background = [System.Windows.Media.Brushes]::White
                    $btn.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#d8e8f0")
                    $btn.BorderThickness = [System.Windows.Thickness]::new(2)
                }
            }
        }
        $lblSelectedCount.Text = "$mode Test selected"
        $lblEstTime.Text = "Estimated: $($scanModeEstimates[$mode])"
        $lblRunBtn = $window.FindName("lblRunBtn")
        if ($lblRunBtn) { $lblRunBtn.Text = "RUN $($mode.ToUpper()) TEST" }
    }

    function Clear-ScanModeSelection {
        if (-not $Global:SelectedScanMode) { return }
        $Global:SelectedScanMode = $null
        foreach ($key in @("Quick","Standard","Deep","MRI")) {
            $btn = $scanModeButtons[$key]
            if ($key -eq "MRI") {
                $btn.Background = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#0a3a56")
                $btn.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#2596be")
                $btn.BorderThickness = [System.Windows.Thickness]::new(2)
            } else {
                $btn.Background = [System.Windows.Media.Brushes]::White
                $btn.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#d8e8f0")
                $btn.BorderThickness = [System.Windows.Thickness]::new(2)
            }
        }
        $lblRunBtn = $window.FindName("lblRunBtn")
        if ($lblRunBtn) { $lblRunBtn.Text = "RUN SELECTED TESTS" }
    }

    # Quick Scan header button selects Quick mode and runs
    $window.FindName("btnQuickScan").Add_Click({
        Select-ScanMode "Quick"
        Invoke-ScanMode "Quick"
    })

    # ── RUN SELECTED TESTS ──
    $window.FindName("btnRunSelected").Add_Click({
        try {
            if ($Global:SelectedScanMode) {
                Invoke-ScanMode $Global:SelectedScanMode
                return
            }
            $p = Get-Params; if (-not $p) { return }
            $anyChecked = $false
            foreach ($c in @($chkCPU,$chkRAM,$chkDisk,$chkSMART,$chkBattery,$chkNetwork,$chkSecurity,$chkKeys,$chkDebloat,$chkRAMIso,$chkPassRecovery,$chkWinDeep,$chkNirSoft,$chkSSDLife,$chkGPU,$chkWearTear,$chkSpeedTest,$chkThermal)) {
                if ($c.IsChecked) { $anyChecked = $true; break }
            }
            if (-not $anyChecked) {
                [System.Windows.MessageBox]::Show($window, "Select a scan mode above OR check individual tests below.", "Nothing Selected", "OK", "Warning")
                return
            }
            Set-ScanButtons $false
            $lblReadyStatus.Text = "Running..."
            $Global:DiagResults.ScanMode = "Custom"

            Set-Status "Collecting system info..." 5
            $Global:DiagResults.SystemInfo = Get-FullSystemInfo
            Update-SystemInfo

            $inlineTests = @($chkCPU,$chkRAM,$chkDisk,$chkSMART,$chkBattery,$chkNetwork,$chkSecurity,$chkKeys,$chkSSDLife,$chkGPU,$chkWinDeep,$chkWearTear,$chkSpeedTest,$chkThermal)
            $totalInline = ($inlineTests | Where-Object { $_.IsChecked }).Count
            if ($totalInline -eq 0) { $totalInline = 1 }
            $stepsDone = 0

            if ($chkCPU.IsChecked) {
                if (Test-AbortRequested) { return }
                $stepsDone++
                Set-Status "Running CPU stress test (60 sec)..." ([int](10 + ($stepsDone / $totalInline) * 80))
                $Global:DiagResults.CPUStress = Start-CPUStressTest -DurationSeconds 60
                $r = $Global:DiagResults.CPUStress
                Set-Status "CPU: $(if($r.Passed){'PASS'}else{'FAIL'}) - $($r.Iterations) iterations" ([int](10 + ($stepsDone / $totalInline) * 80))
            }
            if ($chkRAM.IsChecked) {
                if (Test-AbortRequested) { return }
                $stepsDone++
                Set-Status "Running RAM test (60 sec)..." ([int](10 + ($stepsDone / $totalInline) * 80))
                $Global:DiagResults.RAMStress = Start-RAMStressTest -DurationSeconds 60
                $r = $Global:DiagResults.RAMStress
                Set-Status "RAM: $(if($r.Passed){'PASS'}else{'FAIL'}) - $($r.TotalMBTested) MB tested" ([int](10 + ($stepsDone / $totalInline) * 80))
            }
            if ($chkDisk.IsChecked) {
                if (Test-AbortRequested) { return }
                $stepsDone++
                Set-Status "Running disk benchmark (256MB)..." ([int](10 + ($stepsDone / $totalInline) * 80))
                $Global:DiagResults.DiskBench = Start-DiskBenchmark -FileSizeMB 256
                $r = $Global:DiagResults.DiskBench
                Set-Status "Disk: W=$($r.SeqWriteMBps) R=$($r.SeqReadMBps) MB/s" ([int](10 + ($stepsDone / $totalInline) * 80))
            }
            if ($chkSMART.IsChecked) {
                if (Test-AbortRequested) { return }
                $stepsDone++
                Set-Status "Reading SMART data..." ([int](10 + ($stepsDone / $totalInline) * 80))
                $smart = Invoke-Safe { Get-PhysicalDisk | ForEach-Object { $r=Get-StorageReliabilityCounter -PhysicalDisk $_ -ErrorAction SilentlyContinue; "$($_.FriendlyName): $($_.HealthStatus)" } } "Error"
                Set-Status "SMART: $($smart -join ' | ')" ([int](10 + ($stepsDone / $totalInline) * 80))
            }
            if ($chkBattery.IsChecked) {
                if (Test-AbortRequested) { return }
                $stepsDone++
                Set-Status "Checking battery..." ([int](10 + ($stepsDone / $totalInline) * 80))
                $Global:DiagResults.BatteryDetail = Get-DetailedBatteryInfo
            }
            if ($chkNetwork.IsChecked) {
                if (Test-AbortRequested) { return }
                $stepsDone++
                Set-Status "Testing network..." ([int](10 + ($stepsDone / $totalInline) * 80))
                $Global:DiagResults.Network = Get-NetworkDiagnostics
                $net = $Global:DiagResults.Network
                Set-Status "Network: DNS $(if($net.DNSTest.Success){'OK'}else{'FAIL'}), Internet $(if($net.InternetTest.Success){'OK'}else{'FAIL'})" ([int](10 + ($stepsDone / $totalInline) * 80))
            }
            if ($chkSecurity.IsChecked) {
                if (Test-AbortRequested) { return }
                $stepsDone++
                Set-Status "Running security audit..." ([int](10 + ($stepsDone / $totalInline) * 80))
                $Global:DiagResults.Security = Get-FullSecurityInfo
                $Global:DiagResults.Patches = Get-MissingPatchesList
                $Global:DiagResults.Scoring = Calculate-Score $Global:DiagResults.Security $Global:DiagResults.Patches
            }
            if ($chkKeys.IsChecked) {
                if (Test-AbortRequested) { return }
                $stepsDone++
                Set-Status "Recovering license keys..." ([int](10 + ($stepsDone / $totalInline) * 80))
                $Global:DiagResults.LicenseKeys = Get-LicenseKeys
                $lk = $Global:DiagResults.LicenseKeys
                $wk = if ($lk.WindowsKeys.Count -gt 0) { $lk.WindowsKeys[0].Key } else { "Not found" }
                Set-Status "Windows Key: $wk | WiFi: $($lk.WiFiPasswords.Count) networks" ([int](10 + ($stepsDone / $totalInline) * 80))
            }
            if ($chkSSDLife.IsChecked) {
                if (Test-AbortRequested) { return }
                $stepsDone++
                Set-Status "Analyzing SSD/HDD life and health..." ([int](10 + ($stepsDone / $totalInline) * 80))
                $Global:DiagResults.SSDLife = Get-SSDLifeReport
                $driveCount = $Global:DiagResults.SSDLife.Drives.Count
                $healthy = $Global:DiagResults.SSDLife.OverallHealthy
                Set-Status "SSD Life: $driveCount drive(s) - $(if($healthy){'All Healthy'}else{'Issues Found'})" ([int](10 + ($stepsDone / $totalInline) * 80))
            }
            if ($chkGPU.IsChecked) {
                if (Test-AbortRequested) { return }
                $stepsDone++
                Set-Status "Running GPU stress test (60 sec)..." ([int](10 + ($stepsDone / $totalInline) * 80))
                $Global:DiagResults.GPUStress = Start-GPUStressTest -DurationSeconds 60
                $r = $Global:DiagResults.GPUStress
                Set-Status "GPU: $(if($r.Passed){'PASS'}else{'FAIL'}) - $($r.GPUName), $($r.Iterations) iterations" ([int](10 + ($stepsDone / $totalInline) * 80))
            }
            if ($chkWinDeep.IsChecked) {
                if (Test-AbortRequested) { return }
                $stepsDone++
                Set-Status "Running Deep Windows test (SFC, DISM, services, file system)..." ([int](10 + ($stepsDone / $totalInline) * 80))
                $Global:DiagResults.WindowsDeep = Invoke-DeepWindowsTest
                $wd = $Global:DiagResults.WindowsDeep
                Set-Status "Windows Deep: Score=$($wd.Score)/100 ($($wd.Grade))" ([int](10 + ($stepsDone / $totalInline) * 80))
            }
            if ($chkWearTear.IsChecked) {
                if (Test-AbortRequested) { return }
                $stepsDone++
                Set-Status "Running Wear & Tear lifecycle analysis..." ([int](10 + ($stepsDone / $totalInline) * 80))
                $Global:DiagResults.WearTear = Invoke-WearAndTearReport
                $wt = $Global:DiagResults.WearTear
                Set-Status "Wear & Tear: Score=$($wt.Score)/100 ($($wt.Grade)) - $($wt.RiskLevel) risk" ([int](10 + ($stepsDone / $totalInline) * 80))
            }
            if ($chkSpeedTest.IsChecked) {
                if (Test-AbortRequested) { return }
                $stepsDone++
                Set-Status "Running internet speed test..." ([int](10 + ($stepsDone / $totalInline) * 80))
                $Global:DiagResults.SpeedTest = Get-NetworkSpeedTest
                $Global:DiagResults.SpeedTest2 = Invoke-SpeedtestCLI
                $st = $Global:DiagResults.SpeedTest
                Set-Status "Speed: Down=$($st.DownloadMbps) Up=$($st.UploadMbps) Mbps, Ping=$($st.PingMs)ms" ([int](10 + ($stepsDone / $totalInline) * 80))
            }
            if ($chkThermal.IsChecked) {
                if (Test-AbortRequested) { return }
                $stepsDone++
                Set-Status "Checking thermal status and DPC latency..." ([int](10 + ($stepsDone / $totalInline) * 80))
                $Global:DiagResults.Thermal = Get-ThermalSnapshot
                $Global:DiagResults.DPCLatency = Test-DPCLatency
                $Global:DiagResults.FanInfo = Get-FanInfo
                $th = $Global:DiagResults.Thermal
                Set-Status "Thermal: CPU=$($th.CPUTemp)C $(if($th.OverheatDetected){'OVERHEAT!'}else{'OK'})" ([int](10 + ($stepsDone / $totalInline) * 80))
            }

            # External scripts launch in separate windows
            if ($chkDebloat.IsChecked) {
                $s = Join-Path $Global:ScriptDir "PCPlus-Debloat.ps1"
                if (Test-Path $s) { Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$s`"" -Verb RunAs }
                else { Set-Status "PCPlus-Debloat.ps1 not found" 0 }
            }
            if ($chkRAMIso.IsChecked) {
                $s = Join-Path $Global:ScriptDir "PCPlus360-Advanced-RAM-Isolation-Test.ps1"
                if (-not (Test-Path $s)) { $s = Join-Path $Global:ScriptDir "PCPlus-RAMIsolation.ps1" }
                if (Test-Path $s) { Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$s`"" -Verb RunAs }
                else { Set-Status "RAM Isolation script not found" 0 }
            }
            if ($chkPassRecovery.IsChecked) {
                $s = Join-Path $Global:ScriptDir "PCPlus-PasswordRecovery.ps1"
                if (Test-Path $s) { Start-Process powershell.exe -ArgumentList "-STA -NoProfile -ExecutionPolicy Bypass -File `"$s`"" -Verb RunAs }
                else { Set-Status "PCPlus-PasswordRecovery.ps1 not found" 0 }
            }
            if ($chkNirSoft.IsChecked) {
                $s = Join-Path $Global:ScriptDir "PCPlus-NirSoftSuite.ps1"
                if (Test-Path $s) { Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$s`"" -Verb RunAs }
                else { Set-Status "PCPlus-NirSoftSuite.ps1 not found" 0 }
            }

            Set-Status "All selected tests complete!" 100
            Complete-Scan
            Invoke-SaveBenchmark -TestType "Custom"
            [System.Windows.MessageBox]::Show($window, "All selected tests complete!", "Tests Complete", "OK", "Information")
        } catch {
            Write-DebugLog "Run Selected ERROR: $($_.Exception.Message) at line $($_.InvocationInfo.ScriptLineNumber)"
            Set-Status "ERROR: $($_.Exception.Message)" 0
            [System.Windows.MessageBox]::Show($window, "Error: $($_.Exception.Message)", "Error", "OK", "Error")
        } finally { Set-ScanButtons $true; $lblReadyStatus.Text = "Ready" }
    })

    # ── SCAN MODE SELECTION (click to select, RUN button to execute) ──
    $window.FindName("btnQuick").Add_Click({ Select-ScanMode "Quick" })
    $window.FindName("btnStandard").Add_Click({ Select-ScanMode "Standard" })
    $window.FindName("btnFull").Add_Click({ Select-ScanMode "Deep" })
    $window.FindName("btnMRI").Add_Click({ Select-ScanMode "MRI" })

    function Invoke-QuickTest {
        try {
            $p = Get-Params; if (-not $p) { return }
            Set-ScanButtons $false
            $lblReadyStatus.Text = "Running..."
            $Global:DiagResults.ScanMode = "Quick"
            Set-Status "Quick Test: Collecting system info..." 5
            $Global:DiagResults.SystemInfo = Get-FullSystemInfo
            if (Test-AbortRequested) { return }
            Set-Status "Quick Test: Security scan..." 20
            $Global:DiagResults.Security = Get-FullSecurityInfo
            if (Test-AbortRequested) { return }
            Set-Status "Quick Test: Network info..." 35
            $Global:DiagResults.Network = Get-NetworkDiagnostics
            if (Test-AbortRequested) { return }
            Set-Status "Quick Test: Software inventory..." 50
            $Global:DiagResults.Software = Get-SoftwareInventory
            if (Test-AbortRequested) { return }
            Set-Status "Quick Test: Checking updates..." 60
            $Global:DiagResults.Patches = Get-MissingPatchesList
            if (Test-AbortRequested) { return }
            Set-Status "Quick Test: Performance snapshot..." 70
            $Global:DiagResults.Performance = Get-PerformanceSnapshot
            if (Test-AbortRequested) { return }
            Set-Status "Quick Test: License keys..." 78
            $Global:DiagResults.LicenseKeys = Get-LicenseKeys
            if (Test-AbortRequested) { return }
            Set-Status "Quick Test: Crash history..." 85
            $Global:DiagResults.Stability = Get-CrashStabilityHistory
            if (Test-AbortRequested) { return }
            Set-Status "Quick Test: Battery info..." 86
            $Global:DiagResults.BatteryDetail = Get-DetailedBatteryInfo
            if (Test-AbortRequested) { return }
            Set-Status "Quick Test: Boot performance..." 90
            $Global:DiagResults.BootPerf = Get-BootPerformance
            if (Test-AbortRequested) { return }
            Set-Status "Quick Test: Windows 11 readiness..." 93
            $Global:DiagResults.Win11Ready = Get-Windows11Readiness
            if (Test-AbortRequested) { return }
            Set-Status "Quick Test: Calculating scores..." 97
            $Global:DiagResults.Scoring = Calculate-Score $Global:DiagResults.Security $Global:DiagResults.Patches
            $Global:DiagResults.StressResults = @{}
            $Global:DiagResults.SpeedTest = $null; $Global:DiagResults.Gaming = $null; $Global:DiagResults.PowerInfo = $null
            Set-Status "DONE! Quick Test complete. Generate reports from sidebar." 100
            Complete-Scan
            Invoke-SaveBenchmark -TestType "Quick"
            [System.Windows.MessageBox]::Show($window, "Quick Test complete!`nStability: $($Global:DiagResults.Stability.StabilityRating)`n`nClick a Report button in the sidebar to save PDFs.", "Quick Test Complete", "OK", "Information")
        } catch {
            Write-DebugLog "Quick Test ERROR: $($_.Exception.Message) at line $($_.InvocationInfo.ScriptLineNumber)"
            Set-Status "ERROR: $($_.Exception.Message)" 0
            [System.Windows.MessageBox]::Show($window, "Error during Quick Test:`n`n$($_.Exception.Message)", "Error", "OK", "Error")
        } finally { Set-ScanButtons $true; $lblReadyStatus.Text = "Ready" }
    }

    function Invoke-StandardTest {
        try {
            $p = Get-Params; if (-not $p) { return }
            Set-ScanButtons $false
            $lblReadyStatus.Text = "Running..."
            $Global:DiagResults.ScanMode = "Standard"
            Set-Status "Standard Test: Collecting system info..." 2
            $Global:DiagResults.SystemInfo = Get-FullSystemInfo
            if (Test-AbortRequested) { return }
            Set-Status "Standard Test: Security scan..." 8
            $Global:DiagResults.Security = Get-FullSecurityInfo
            if (Test-AbortRequested) { return }
            Set-Status "Standard Test: Network analysis..." 14
            $Global:DiagResults.Network = Get-NetworkDiagnostics
            if (Test-AbortRequested) { return }
            Set-Status "Standard Test: Network speed test..." 18
            $Global:DiagResults.SpeedTest = Get-NetworkSpeedTest
            if (Test-AbortRequested) { return }
            Set-Status "Standard Test: Software inventory..." 24
            $Global:DiagResults.Software = Get-SoftwareInventory
            if (Test-AbortRequested) { return }
            Set-Status "Standard Test: Checking updates..." 28
            $Global:DiagResults.Patches = Get-MissingPatchesList
            if (Test-AbortRequested) { return }
            Set-Status "Standard Test: Performance snapshot..." 32
            $Global:DiagResults.Performance = Get-PerformanceSnapshot
            if (Test-AbortRequested) { return }
            Set-Status "Standard Test: License keys..." 36
            $Global:DiagResults.LicenseKeys = Get-LicenseKeys
            if (Test-AbortRequested) { return }
            Set-Status "Standard Test: Crash history..." 40
            $Global:DiagResults.Stability = Get-CrashStabilityHistory
            if (Test-AbortRequested) { return }
            Set-Status "Standard Test: Battery report..." 44
            $Global:DiagResults.BatteryDetail = Get-DetailedBatteryInfo
            if (Test-AbortRequested) { return }
            Set-Status "Standard Test: Power stability..." 47
            $Global:DiagResults.PowerInfo = Get-PowerStabilityInfo
            if (Test-AbortRequested) { return }
            Set-Status "Standard Test: Gaming readiness..." 49
            $Global:DiagResults.Gaming = Get-GamingReadiness
            if (Test-AbortRequested) { return }
            Set-Status "Standard Test: Boot performance..." 51
            $Global:DiagResults.BootPerf = Get-BootPerformance
            if (Test-AbortRequested) { return }
            Set-Status "Standard Test: Windows 11 readiness..." 53
            $Global:DiagResults.Win11Ready = Get-Windows11Readiness
            if (Test-AbortRequested) { return }
            Set-Status "Standard Test: CPU stress (5 min)..." 55
            $Global:DiagResults.CPUStress = Start-CPUStressTest -DurationSeconds 300
            if (Test-AbortRequested) { return }
            Set-Status "Standard Test: GPU stress (2 min)..." 70
            $Global:DiagResults.GPUStress = Start-GPUStressTest -DurationSeconds 120
            if (Test-AbortRequested) { return }
            Set-Status "Standard Test: RAM test (5 min)..." 78
            $Global:DiagResults.RAMStress = Start-RAMStressTest -DurationSeconds 300
            if (Test-AbortRequested) { return }
            Set-Status "Standard Test: Disk benchmark (512MB)..." 90
            $Global:DiagResults.DiskBench = Start-DiskBenchmark -FileSizeMB 512
            if (Test-AbortRequested) { return }
            Set-Status "Standard Test: Calculating scores..." 96
            $Global:DiagResults.Scoring = Calculate-Score $Global:DiagResults.Security $Global:DiagResults.Patches
            $Global:DiagResults.StressResults = @{ CPU = $Global:DiagResults.CPUStress; RAM = $Global:DiagResults.RAMStress; Disk = $Global:DiagResults.DiskBench; GPU = $Global:DiagResults.GPUStress }
            $cs = $Global:DiagResults.CPUStress; $rs = $Global:DiagResults.RAMStress; $ds = $Global:DiagResults.DiskBench; $gs = $Global:DiagResults.GPUStress
            Set-Status "DONE! CPU:$(if($cs.Passed){'PASS'}else{'FAIL'}) RAM:$(if($rs.Passed){'PASS'}else{'FAIL'}) GPU:$(if($gs.Passed){'PASS'}else{'FAIL'}) Disk:W=$($ds.SeqWriteMBps)/$($ds.SeqReadMBps)" 100
            Complete-Scan
            Invoke-SaveBenchmark -TestType "Standard"
            [System.Windows.MessageBox]::Show($window, "Standard Test complete!`nCPU: $(if($cs.Passed){'PASS'}else{'FAIL'})`nRAM: $(if($rs.Passed){'PASS'}else{'FAIL'})`nGPU: $(if($gs.Passed){'PASS'}else{'FAIL'})`nDisk: W=$($ds.SeqWriteMBps) / R=$($ds.SeqReadMBps) MB/s`nStability: $($Global:DiagResults.Stability.StabilityRating)`n`nClick a Report button in the sidebar.", "Standard Test Complete", "OK", "Information")
        } catch {
            Write-DebugLog "Standard Test ERROR: $($_.Exception.Message) at line $($_.InvocationInfo.ScriptLineNumber)"
            Set-Status "ERROR: $($_.Exception.Message)" 0
            [System.Windows.MessageBox]::Show($window, "Error during Standard Test:`n`n$($_.Exception.Message)", "Error", "OK", "Error")
        } finally { Set-ScanButtons $true; $lblReadyStatus.Text = "Ready" }
    }

    function Invoke-DeepTest {
        try {
            $p = Get-Params; if (-not $p) { return }
            Set-ScanButtons $false
            $lblReadyStatus.Text = "Running..."
            $Global:DiagResults.ScanMode = "Deep"
            Set-Status "Deep Test: Collecting system info..." 2
            $Global:DiagResults.SystemInfo = Get-FullSystemInfo
            if (Test-AbortRequested) { return }
            Set-Status "Deep Test: Security scan..." 5
            $Global:DiagResults.Security = Get-FullSecurityInfo
            if (Test-AbortRequested) { return }
            Set-Status "Deep Test: Network analysis..." 8
            $Global:DiagResults.Network = Get-NetworkDiagnostics
            if (Test-AbortRequested) { return }
            Set-Status "Deep Test: Network speed test..." 11
            $Global:DiagResults.SpeedTest = Get-NetworkSpeedTest
            if (Test-AbortRequested) { return }
            Set-Status "Deep Test: Software inventory..." 14
            $Global:DiagResults.Software = Get-SoftwareInventory
            if (Test-AbortRequested) { return }
            Set-Status "Deep Test: Checking updates..." 17
            $Global:DiagResults.Patches = Get-MissingPatchesList
            if (Test-AbortRequested) { return }
            Set-Status "Deep Test: Performance snapshot..." 20
            $Global:DiagResults.Performance = Get-PerformanceSnapshot
            if (Test-AbortRequested) { return }
            Set-Status "Deep Test: License keys..." 22
            $Global:DiagResults.LicenseKeys = Get-LicenseKeys
            if (Test-AbortRequested) { return }
            Set-Status "Deep Test: Crash history..." 25
            $Global:DiagResults.Stability = Get-CrashStabilityHistory
            if (Test-AbortRequested) { return }
            Set-Status "Deep Test: Battery report..." 28
            $Global:DiagResults.BatteryDetail = Get-DetailedBatteryInfo
            if (Test-AbortRequested) { return }
            Set-Status "Deep Test: Power stability..." 30
            $Global:DiagResults.PowerInfo = Get-PowerStabilityInfo
            if (Test-AbortRequested) { return }
            Set-Status "Deep Test: Gaming readiness..." 32
            $Global:DiagResults.Gaming = Get-GamingReadiness
            if (Test-AbortRequested) { return }
            Set-Status "Deep Test: Boot performance..." 34
            $Global:DiagResults.BootPerf = Get-BootPerformance
            if (Test-AbortRequested) { return }
            Set-Status "Deep Test: Windows 11 readiness..." 35
            $Global:DiagResults.Win11Ready = Get-Windows11Readiness
            if (Test-AbortRequested) { return }
            Set-Status "Deep Test: CPU stress (15 min)..." 37
            $Global:DiagResults.CPUStress = Start-CPUStressTest -DurationSeconds 900
            if (Test-AbortRequested) { return }
            Set-Status "Deep Test: GPU stress (5 min)..." 56
            $Global:DiagResults.GPUStress = Start-GPUStressTest -DurationSeconds 300
            if (Test-AbortRequested) { return }
            Set-Status "Deep Test: RAM test (15 min)..." 66
            $Global:DiagResults.RAMStress = Start-RAMStressTest -DurationSeconds 900
            if (Test-AbortRequested) { return }
            Set-Status "Deep Test: Disk benchmark (1GB)..." 86
            $Global:DiagResults.DiskBench = Start-DiskBenchmark -FileSizeMB 1024
            if (Test-AbortRequested) { return }
            Set-Status "Deep Test: Calculating scores..." 92
            $Global:DiagResults.Scoring = Calculate-Score $Global:DiagResults.Security $Global:DiagResults.Patches
            $Global:DiagResults.StressResults = @{ CPU = $Global:DiagResults.CPUStress; RAM = $Global:DiagResults.RAMStress; Disk = $Global:DiagResults.DiskBench; GPU = $Global:DiagResults.GPUStress }
            Set-Status "Deep Test: Loading scan history..." 95
            $history = Get-ScanHistory -ComputerName $Global:DiagResults.SystemInfo.ComputerName
            $Global:DiagResults.HistoryComparison = Compare-ScanHistory -Current @{
                HardwareScore = $Global:DiagResults.StressResults.CPU.Passed; SecurityScore = $Global:DiagResults.Scoring.Score
                SSDHealth = ($Global:DiagResults.SystemInfo.SMART | ForEach-Object { "$($_.Model):$($_.Health)" }) -join "; "
                BatteryHealth = if($Global:DiagResults.BatteryDetail.Present){$Global:DiagResults.BatteryDetail.HealthPct}else{"N/A"}
                CPUPeakTemp = if($Global:DiagResults.CPUStress){$Global:DiagResults.CPUStress.MaxTemp}else{"N/A"}
                CrashCount = $Global:DiagResults.Stability.TotalBSODs + $Global:DiagResults.Stability.TotalUnexpected
                DiskWriteMBps = if($Global:DiagResults.DiskBench){$Global:DiagResults.DiskBench.SeqWriteMBps}else{"N/A"}
            } -Previous $history
            $cs = $Global:DiagResults.CPUStress; $rs = $Global:DiagResults.RAMStress; $ds = $Global:DiagResults.DiskBench; $gs = $Global:DiagResults.GPUStress
            Set-Status "DONE! Deep Test complete. CPU:$(if($cs.Passed){'PASS'}else{'FAIL'}) RAM:$(if($rs.Passed){'PASS'}else{'FAIL'}) GPU:$(if($gs.Passed){'PASS'}else{'FAIL'})" 100
            $histMsg = if ($Global:DiagResults.HistoryComparison -and $Global:DiagResults.HistoryComparison.HasPrevious) { "`nPrevious scan: $($Global:DiagResults.HistoryComparison.PreviousDate)" } else { "`nNo previous scan history." }
            Complete-Scan
            Invoke-SaveBenchmark -TestType "Deep"
            [System.Windows.MessageBox]::Show($window, "Deep Test complete!`nCPU: $(if($cs.Passed){'PASS'}else{'FAIL'})`nRAM: $(if($rs.Passed){'PASS'}else{'FAIL'})`nGPU: $(if($gs.Passed){'PASS'}else{'FAIL'})`nDisk: W=$($ds.SeqWriteMBps) / R=$($ds.SeqReadMBps) MB/s`nStability: $($Global:DiagResults.Stability.StabilityRating)$histMsg`n`nClick a Report button in the sidebar.", "Deep Test Complete", "OK", "Information")
        } catch {
            Write-DebugLog "Deep Test ERROR: $($_.Exception.Message) at line $($_.InvocationInfo.ScriptLineNumber)"
            Set-Status "ERROR: $($_.Exception.Message)" 0
            [System.Windows.MessageBox]::Show($window, "Error during Deep Test:`n`n$($_.Exception.Message)", "Error", "OK", "Error")
        } finally { Set-ScanButtons $true; $lblReadyStatus.Text = "Ready" }
    }

    function Invoke-MRITest {
        try {
            $p = Get-Params; if (-not $p) { return }
            $confirm = [System.Windows.MessageBox]::Show($window, "Full System MRI runs EVERY diagnostic:`n- All hardware info and inventory`n- CPU, RAM, GPU, Disk stress tests`n- SSD life and SMART analysis`n- Deep Windows integrity (SFC, DISM, CHKDSK)`n- Security audit + activation check`n- Thermal monitoring + DPC latency`n- Memory leak detection`n- All event logs and crash history`n- Network + speed test`n- Display, drivers, fragmentation check`n`nThis takes 90-120 minutes. Continue?", "Full System MRI", "YesNo", "Question")
            if ($confirm -ne "Yes") { return }
            Set-ScanButtons $false
            $lblReadyStatus.Text = "MRI Running..."
            $Global:DiagResults.ScanMode = "MRI"

            Set-Status "MRI Phase 1: System inventory..." 2
            $Global:DiagResults.SystemInfo = Get-FullSystemInfo
            Update-SystemInfo
            if (Test-AbortRequested) { return }
            Set-Status "MRI Phase 1: Security audit..." 5
            $Global:DiagResults.Security = Get-FullSecurityInfo
            if (Test-AbortRequested) { return }
            Set-Status "MRI Phase 1: Network diagnostics..." 8
            $Global:DiagResults.Network = Get-NetworkDiagnostics
            if (Test-AbortRequested) { return }
            Set-Status "MRI Phase 1: Software inventory..." 10
            $Global:DiagResults.Software = Get-SoftwareInventory
            if (Test-AbortRequested) { return }
            Set-Status "MRI Phase 1: Updates check..." 12
            $Global:DiagResults.Patches = Get-MissingPatchesList
            $Global:DiagResults.Scoring = Calculate-Score $Global:DiagResults.Security $Global:DiagResults.Patches
            if (Test-AbortRequested) { return }
            Set-Status "MRI Phase 1: License keys..." 14
            $Global:DiagResults.LicenseKeys = Get-LicenseKeys
            if (Test-AbortRequested) { return }
            Set-Status "MRI Phase 1: Performance snapshot..." 16
            $Global:DiagResults.Performance = Get-PerformanceSnapshot
            if (Test-AbortRequested) { return }
            Set-Status "MRI Phase 1: Crash & stability history..." 18
            $Global:DiagResults.Stability = Get-CrashStabilityHistory
            if (Test-AbortRequested) { return }
            Set-Status "MRI Phase 1: Battery report..." 20
            $Global:DiagResults.BatteryDetail = Get-DetailedBatteryInfo
            if (Test-AbortRequested) { return }
            Set-Status "MRI Phase 1: Power stability..." 21
            $Global:DiagResults.PowerInfo = Get-PowerStabilityInfo
            if (Test-AbortRequested) { return }
            Set-Status "MRI Phase 1: Gaming readiness..." 22
            $Global:DiagResults.Gaming = Get-GamingReadiness
            if (Test-AbortRequested) { return }
            Set-Status "MRI Phase 1: Boot performance..." 23
            $Global:DiagResults.BootPerf = Get-BootPerformance
            if (Test-AbortRequested) { return }
            Set-Status "MRI Phase 1: Windows 11 readiness..." 24
            $Global:DiagResults.Win11Ready = Get-Windows11Readiness
            if (Test-AbortRequested) { return }
            Set-Status "MRI Phase 1: Fan info..." 25
            $Global:DiagResults.FanInfo = Get-FanInfo
            if (Test-AbortRequested) { return }
            Set-Status "MRI Phase 1: Display info..." 26
            $Global:DiagResults.DisplayInfo = Get-DisplayInfo
            if (Test-AbortRequested) { return }
            Set-Status "MRI Phase 1: Windows activation..." 27
            $Global:DiagResults.Activation = Get-WindowsActivation
            if (Test-AbortRequested) { return }
            Set-Status "MRI Phase 1: Memory leak check..." 28
            $Global:DiagResults.MemoryLeaks = Test-MemoryLeaks
            if (Test-AbortRequested) { return }
            Set-Status "MRI Phase 1: Thermal snapshot..." 29
            $Global:DiagResults.Thermal = Get-ThermalSnapshot
            if (Test-AbortRequested) { return }

            Set-Status "MRI Phase 2: SSD/HDD life report..." 30
            $Global:DiagResults.SSDLife = Get-SSDLifeReport
            if (Test-AbortRequested) { return }
            Set-Status "MRI Phase 2: Disk fragmentation..." 32
            $Global:DiagResults.Fragmentation = Get-DiskFragmentation
            if (Test-AbortRequested) { return }
            Set-Status "MRI Phase 2: CrystalDiskInfo SMART scan..." 33
            $Global:DiagResults.CrystalDiskInfo = Invoke-CrystalDiskInfoScan
            if (Test-AbortRequested) { return }
            Set-Status "MRI Phase 2: Wear & Tear lifecycle analysis..." 34
            $Global:DiagResults.WearTear = Invoke-WearAndTearReport
            if (Test-AbortRequested) { return }
            Set-Status "MRI Phase 3: CPU stress test (2 min)..." 36
            $Global:DiagResults.CPUStress = Start-CPUStressTest -DurationSeconds 120
            if (Test-AbortRequested) { return }
            Set-Status "MRI Phase 3: RAM stress test (2 min)..." 50
            $Global:DiagResults.RAMStress = Start-RAMStressTest -DurationSeconds 120
            if (Test-AbortRequested) { return }
            Set-Status "MRI Phase 3: Disk benchmark (512 MB)..." 64
            $Global:DiagResults.DiskBench = Start-DiskBenchmark -FileSizeMB 512
            if (Test-AbortRequested) { return }
            Set-Status "MRI Phase 3: GPU stress test (90 sec)..." 70
            $Global:DiagResults.GPUStress = Start-GPUStressTest -DurationSeconds 90
            $Global:DiagResults.StressResults = @{ CPU=$Global:DiagResults.CPUStress; RAM=$Global:DiagResults.RAMStress; Disk=$Global:DiagResults.DiskBench; GPU=$Global:DiagResults.GPUStress }

            if (Test-AbortRequested) { return }
            Set-Status "MRI Phase 4: Deep Windows integrity (SFC, DISM, services)..." 78
            $Global:DiagResults.WindowsDeep = Invoke-DeepWindowsTest
            if (Test-AbortRequested) { return }
            Set-Status "MRI Phase 4: DPC latency check..." 90
            $Global:DiagResults.DPCLatency = Test-DPCLatency

            Set-Status "MRI Phase 5: Internet speed test..." 93
            $Global:DiagResults.SpeedTest2 = Invoke-SpeedtestCLI
            if (-not $Global:DiagResults.SpeedTest) { $Global:DiagResults.SpeedTest = Get-NetworkSpeedTest }

            Set-Status "MRI: Calculating overall score..." 97
            $overallScore = 100; $issues = @()
            $cs = $Global:DiagResults.CPUStress; $rs = $Global:DiagResults.RAMStress; $gs = $Global:DiagResults.GPUStress; $ds = $Global:DiagResults.DiskBench
            if ($cs -and -not $cs.Passed) { $overallScore -= 15; $issues += "CPU stress failed" }
            if ($rs -and -not $rs.Passed) { $overallScore -= 15; $issues += "RAM stress failed" }
            if ($gs -and -not $gs.Passed) { $overallScore -= 10; $issues += "GPU stress failed" }
            if ($Global:DiagResults.WindowsDeep) { $wdScore = $Global:DiagResults.WindowsDeep.Score; $overallScore -= [math]::Max(0, 20 - [math]::Round($wdScore * 0.2)) }
            if ($Global:DiagResults.Scoring) { $overallScore -= [math]::Max(0, 25 - [math]::Round($Global:DiagResults.Scoring.Score * 0.25)) }
            if ($Global:DiagResults.Thermal -and $Global:DiagResults.Thermal.OverheatDetected) { $overallScore -= 10; $issues += "Overheating" }
            if ($Global:DiagResults.WearTear) { $wtScore = $Global:DiagResults.WearTear.Score; $overallScore -= [math]::Max(0, 10 - [math]::Round($wtScore * 0.1)); if ($Global:DiagResults.WearTear.RiskLevel -eq "Critical") { $issues += "Critical wear detected" } }
            if ($overallScore -lt 0) { $overallScore = 0 }
            $mriGrade = if ($overallScore -ge 90){"A"} elseif ($overallScore -ge 80){"B"} elseif ($overallScore -ge 70){"C"} elseif ($overallScore -ge 60){"D"} else {"F"}
            $Global:DiagResults.MRIScore = $overallScore
            $Global:DiagResults.MRIGrade = $mriGrade

            Set-Status "DONE! Full System MRI complete. Score: $overallScore/100 ($mriGrade)" 100
            Complete-Scan
            Invoke-SaveBenchmark -TestType "MRI"
            $msg = "Full System MRI Complete!`n`nOverall Score: $overallScore/100 ($mriGrade)`n`nCPU: $(if($cs.Passed){'PASS'}else{'FAIL'})`nRAM: $(if($rs.Passed){'PASS'}else{'FAIL'})`nGPU: $(if($gs.Passed){'PASS'}else{'FAIL'})`nDisk: W=$($ds.SeqWriteMBps) / R=$($ds.SeqReadMBps) MB/s"
            if ($Global:DiagResults.WindowsDeep) { $msg += "`nWindows Health: $($Global:DiagResults.WindowsDeep.Score)/100 ($($Global:DiagResults.WindowsDeep.Grade))" }
            if ($Global:DiagResults.Scoring) { $msg += "`nSecurity: $($Global:DiagResults.Scoring.Score)/100 ($($Global:DiagResults.Scoring.Grade))" }
            if ($Global:DiagResults.WearTear) { $msg += "`nWear & Tear: $($Global:DiagResults.WearTear.Score)/100 ($($Global:DiagResults.WearTear.Grade)) - $($Global:DiagResults.WearTear.RiskLevel) risk" }
            $msg += "`n`nClick Report buttons in sidebar to generate PDFs."
            [System.Windows.MessageBox]::Show($window, $msg, "Full System MRI Complete", "OK", "Information")
        } catch {
            Write-DebugLog "MRI ERROR: $($_.Exception.Message) at line $($_.InvocationInfo.ScriptLineNumber)"
            Set-Status "ERROR: $($_.Exception.Message)" 0
            [System.Windows.MessageBox]::Show($window, "Error during MRI:`n`n$($_.Exception.Message)", "Error", "OK", "Error")
        } finally { Set-ScanButtons $true; $lblReadyStatus.Text = "Ready" }
    }

    function Invoke-ScanMode($mode) {
        switch ($mode) {
            "Quick"    { Invoke-QuickTest }
            "Standard" { Invoke-StandardTest }
            "Deep"     { Invoke-DeepTest }
            "MRI"      { Invoke-MRITest }
        }
    }

    # ── REPORT GENERATION ──
    $generateReports = {
        param([bool]$DoHW, [bool]$DoSec)
        $p = Get-Params; if (-not $p) { return }
        if (-not $Global:DiagResults.SystemInfo) { [System.Windows.MessageBox]::Show($window, "Run a diagnostic first.", "No Data", "OK", "Warning"); return }
        $safeName = $p.CustomerName -replace '[\\/:*?"<>|]','_'
        $safeDev = $Global:DiagResults.SystemInfo.ComputerName -replace '[\\/:*?"<>|]','_'
        $ds = Get-Date -Format "yyyy-MM-dd"
        if ($DoHW) {
            Set-Status "Generating Hardware Report..." 20
            $hwHTML = Build-HardwareReport $p $Global:DiagResults.SystemInfo $Global:DiagResults.Network $Global:DiagResults.Software $Global:DiagResults.Performance $Global:DiagResults.StressResults $Global:DiagResults.LicenseKeys $Global:DiagResults.Stability $Global:DiagResults.BatteryDetail $Global:DiagResults.PowerInfo $Global:DiagResults.SpeedTest $Global:DiagResults.Gaming $Global:DiagResults.HistoryComparison $Global:DiagResults.ScanMode $Global:DiagResults.BootPerf $Global:DiagResults.Win11Ready
            $hwHTMLPath = Join-Path $p.OutputFolder "$safeName - $safeDev - Hardware Report $ds.html"
            $hwPDFPath = Join-Path $p.OutputFolder "$safeName - $safeDev - Hardware Report $ds.pdf"
            [IO.File]::WriteAllText($hwHTMLPath, $hwHTML, [Text.Encoding]::UTF8)
            $hwPDF = Convert-ToPDF $hwHTMLPath $hwPDFPath
            Invoke-Safe { Invoke-AutoUploadReport -ReportPath $(if($hwPDF){$hwPDFPath}else{$hwHTMLPath}) -CustomerName $p.CustomerName -ComputerName $Global:DiagResults.SystemInfo.ComputerName -TechName $p.TechName -ScanMode "Hardware" }
            Set-Status "Hardware Report: $(if($hwPDF){"PDF saved"}else{"HTML saved (no PDF browser)"}) to reports folder" 40
        }
        if ($DoSec) {
            Set-Status "Generating Security Report..." 70
            $secHTML = Build-SecurityReport $p $Global:DiagResults.SystemInfo $Global:DiagResults.Security $Global:DiagResults.Patches $Global:DiagResults.Scoring
            $secHTMLPath = Join-Path $p.OutputFolder "$safeName - $safeDev - Security Report $ds.html"
            $secPDFPath = Join-Path $p.OutputFolder "$safeName - $safeDev - Security Report $ds.pdf"
            [IO.File]::WriteAllText($secHTMLPath, $secHTML, [Text.Encoding]::UTF8)
            $secPDF = Convert-ToPDF $secHTMLPath $secPDFPath
            Invoke-Safe { Invoke-AutoUploadReport -ReportPath $(if($secPDF){$secPDFPath}else{$secHTMLPath}) -CustomerName $p.CustomerName -ComputerName $Global:DiagResults.SystemInfo.ComputerName -TechName $p.TechName -ScanMode "Security" }
            Set-Status "Security Report: $(if($secPDF){"PDF saved"}else{"HTML saved"}) to reports folder" 90
        }
        Set-Status "Exporting data files..." 92
        try {
            $exportData = @{
                CustomerName = $p.CustomerName; TechName = $p.TechName; TechNotes = $p.TechNotes
                ScanDate = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss"); ScanMode = $Global:DiagResults.ScanMode
                SystemInfo = $Global:DiagResults.SystemInfo; StressResults = $Global:DiagResults.StressResults
                Stability = $Global:DiagResults.Stability; BatteryDetail = $Global:DiagResults.BatteryDetail
                SpeedTest = $Global:DiagResults.SpeedTest; Gaming = $Global:DiagResults.Gaming
                PowerInfo = $Global:DiagResults.PowerInfo; Scoring = $Global:DiagResults.Scoring
                HardwareScore = if($DoHW){ $Global:DiagResults.StressResults.Count }else{0}
                SecurityScore = if($Global:DiagResults.Scoring){ $Global:DiagResults.Scoring.Score }else{0}
                Battery = $Global:DiagResults.BatteryDetail
            }
            Export-ScanJSON -ScanData $exportData -OutputFolder $p.OutputFolder
            Export-ScanCSV -ScanData $exportData -OutputFolder $p.OutputFolder
            Save-ScanHistory -ScanData $exportData
        } catch { Write-DiagLog "Export error: $($_.Exception.Message)" "WARN" }

        # Generate benchmark comparison data and save as HTML snippet
        try {
            Set-Status "Generating benchmark comparison..." 95
            $cpuModel = if ($Global:DiagResults.SystemInfo.CPUModel) { $Global:DiagResults.SystemInfo.CPUModel } else { "all" }
            # Build current scores from whatever is available
            $curScores = @{ Overall = 50; Thermal = 50; Storage = 50; Network = 50 }
            if ($Global:DiagResults.Scoring -and $Global:DiagResults.Scoring.Score) { $curScores.Overall = $Global:DiagResults.Scoring.Score }
            if ($Global:DiagResults.CPUStress -and $Global:DiagResults.CPUStress.MaxTemp) {
                $t = $Global:DiagResults.CPUStress.MaxTemp
                $curScores.Thermal = if ($t -lt 60) { 100 } elseif ($t -lt 70) { 90 } elseif ($t -lt 80) { 75 } elseif ($t -lt 90) { 55 } else { 30 }
            }
            if ($Global:DiagResults.DiskBench -and $Global:DiagResults.DiskBench.SeqReadMBps) {
                $r = $Global:DiagResults.DiskBench.SeqReadMBps
                $curScores.Storage = if ($r -gt 1000) { 100 } elseif ($r -gt 300) { 80 } elseif ($r -gt 100) { 55 } else { 25 }
            }
            if ($Global:DiagResults.SpeedTest -and $Global:DiagResults.SpeedTest.DownloadMbps -and $Global:DiagResults.SpeedTest.DownloadMbps -ne "N/A") {
                $dl = 0; try { $dl = [double]($Global:DiagResults.SpeedTest.DownloadMbps -replace '[^\d.]','') } catch {}
                $curScores.Network = if ($dl -gt 100) { 95 } elseif ($dl -gt 50) { 80 } elseif ($dl -gt 20) { 65 } elseif ($dl -gt 5) { 45 } else { 20 }
            }
            $pctOverall = Get-BenchmarkPercentile -CPUModel $cpuModel -ScoreType "Overall" -ScoreValue $curScores.Overall
            $pctThermal = Get-BenchmarkPercentile -CPUModel $cpuModel -ScoreType "Thermal" -ScoreValue $curScores.Thermal
            $pctStorage = Get-BenchmarkPercentile -CPUModel "all"    -ScoreType "Storage" -ScoreValue $curScores.Storage
            $pctNetwork = Get-BenchmarkPercentile -CPUModel "all"    -ScoreType "Network" -ScoreValue $curScores.Network
            if ($pctOverall.TotalSamples -gt 0) {
                $benchHTML = Build-BenchmarkComparisonHTML -CurrentScores $curScores -PercentileOverall $pctOverall -PercentileThermal $pctThermal -PercentileStorage $pctStorage -PercentileNetwork $pctNetwork
                $benchHTMLPath = Join-Path $p.OutputFolder "$safeName - $safeDev - Benchmark Comparison $ds.html"
                $benchPage = "<!DOCTYPE html><html><head><meta charset='UTF-8'><title>Benchmark Comparison</title></head><body style='margin:20px;background:#0f172a;'>$benchHTML</body></html>"
                [IO.File]::WriteAllText($benchHTMLPath, $benchPage, [Text.Encoding]::UTF8)
                Write-DiagLog "Benchmark comparison saved: $benchHTMLPath"
            }
        } catch { Write-DiagLog "Benchmark comparison error: $($_.Exception.Message)" "WARN" }

        Set-Status "All reports and data saved to: $($p.OutputFolder)" 100
        Start-Process explorer.exe -ArgumentList $p.OutputFolder

        $emailResult = [System.Windows.MessageBox]::Show($window, "Reports saved successfully!`n`nWould you like to open your email client to send the report?", "Email Report?", "YesNo", "Question")
        if ($emailResult -eq "Yes") {
            $pdfToEmail = ""
            if ($DoHW -and (Test-Path $hwPDFPath)) { $pdfToEmail = $hwPDFPath }
            elseif ($DoSec -and (Test-Path $secPDFPath)) { $pdfToEmail = $secPDFPath }
            elseif ($DoHW -and (Test-Path $hwHTMLPath)) { $pdfToEmail = $hwHTMLPath }
            elseif ($DoSec -and (Test-Path $secHTMLPath)) { $pdfToEmail = $secHTMLPath }
            if ($pdfToEmail) { try { [System.Windows.Clipboard]::SetText($pdfToEmail) } catch {} }
            $subjectText = "PC Plus Computing - Diagnostic Report for $($p.CustomerName)"
            $bodyText = "Hello,`n`nPlease find attached the diagnostic report for $($p.CustomerName) - $($Global:DiagResults.SystemInfo.ComputerName).`n`nGenerated on $(Get-Date -Format 'MMMM dd, yyyy').`n`nBest regards,`n$($p.TechName)`nPC Plus Computing`n$WEBSITE | $PHONE"
            $encodedSubject = [Uri]::EscapeDataString($subjectText)
            $encodedBody = [Uri]::EscapeDataString($bodyText)
            try {
                Start-Process "mailto:?subject=$encodedSubject&body=$encodedBody"
                Set-Status "Email client opened. Report path copied to clipboard." 100
            } catch { Set-Status "Could not open email client. Report path copied to clipboard." 100 }
        }
    }

    $window.FindName("btnHWReport").Add_Click({ & $generateReports $true $false })
    $window.FindName("btnSecReport").Add_Click({ & $generateReports $false $true })
    $window.FindName("btnBothReports").Add_Click({ & $generateReports $true $true })

    $window.FindName("btnCustomerSummary").Add_Click({
        $p = Get-Params; if (-not $p) { return }
        if (-not $Global:DiagResults.SystemInfo) { [System.Windows.MessageBox]::Show($window, "Run a diagnostic first.", "No Data", "OK", "Warning"); return }
        Set-Status "Generating Customer Summary..." 30
        $summaryHTML = Build-CustomerSummary -Params $p -SystemInfo $Global:DiagResults.SystemInfo -Security $Global:DiagResults.Security -Patches $Global:DiagResults.Patches -Scoring $Global:DiagResults.Scoring -StressResults $Global:DiagResults.StressResults -Stability $Global:DiagResults.Stability -BatteryDetail $Global:DiagResults.BatteryDetail -Network $Global:DiagResults.Network -SpeedTest $Global:DiagResults.SpeedTest -ScanMode $Global:DiagResults.ScanMode
        $safeName = $p.CustomerName -replace '[\\/:*?"<>|]','_'
        $safeDev = $Global:DiagResults.SystemInfo.ComputerName -replace '[\\/:*?"<>|]','_'
        $ds = Get-Date -Format "yyyy-MM-dd"
        $summaryHTMLPath = Join-Path $p.OutputFolder "$safeName - $safeDev - Health Summary $ds.html"
        $summaryPDFPath = Join-Path $p.OutputFolder "$safeName - $safeDev - Health Summary $ds.pdf"
        [IO.File]::WriteAllText($summaryHTMLPath, $summaryHTML, [Text.Encoding]::UTF8)
        Set-Status "Converting to PDF..." 70
        $pdfOK = Convert-ToPDF $summaryHTMLPath $summaryPDFPath
        Invoke-Safe { Invoke-AutoUploadReport -ReportPath $(if($pdfOK){$summaryPDFPath}else{$summaryHTMLPath}) -CustomerName $p.CustomerName -ComputerName $Global:DiagResults.SystemInfo.ComputerName -TechName $p.TechName -ScanMode "Customer Summary" }
        Set-Status "Customer Summary: $(if($pdfOK){'PDF saved'}else{'HTML saved'}) to reports folder" 100
        Start-Process explorer.exe -ArgumentList $p.OutputFolder
        [System.Windows.MessageBox]::Show($window, "Customer Health Summary saved!`n`nThis is a customer-friendly 1-2 page report with donut charts and plain English - ready to hand to the customer.", "Summary Ready", "OK", "Information")
    })

    # ── GAMING PC REPORT ──
    $window.FindName("btnGamingReport").Add_Click({
        $p = Get-Params; if (-not $p) { return }
        if (-not $Global:DiagResults.SystemInfo) { [System.Windows.MessageBox]::Show($window, "Run a diagnostic first.", "No Data", "OK", "Warning"); return }
        Set-Status "Generating Gaming PC Report with visual graphs..." 30
        $gamingHTML = Build-GamingPCReport -Params $p -SystemInfo $Global:DiagResults.SystemInfo -StressResults $Global:DiagResults.StressResults -Network $Global:DiagResults.Network -SpeedTest $Global:DiagResults.SpeedTest -SSDLife $Global:DiagResults.SSDLife -Thermal $Global:DiagResults.Thermal -Gaming $Global:DiagResults.Gaming -BatteryDetail $Global:DiagResults.BatteryDetail -Performance $Global:DiagResults.Performance -FanInfo $Global:DiagResults.FanInfo -ScanMode $Global:DiagResults.ScanMode
        $safeName = $p.CustomerName -replace '[\\/:*?"<>|]','_'
        $safeDev = $Global:DiagResults.SystemInfo.ComputerName -replace '[\\/:*?"<>|]','_'
        $ds = Get-Date -Format "yyyy-MM-dd"
        $gamingHTMLPath = Join-Path $p.OutputFolder "$safeName - $safeDev - Gaming PC Report $ds.html"
        $gamingPDFPath = Join-Path $p.OutputFolder "$safeName - $safeDev - Gaming PC Report $ds.pdf"
        [IO.File]::WriteAllText($gamingHTMLPath, $gamingHTML, [Text.Encoding]::UTF8)
        Set-Status "Converting Gaming Report to PDF..." 70
        $pdfOK = Convert-ToPDF $gamingHTMLPath $gamingPDFPath
        Invoke-Safe { Invoke-AutoUploadReport -ReportPath $(if($pdfOK){$gamingPDFPath}else{$gamingHTMLPath}) -CustomerName $p.CustomerName -ComputerName $Global:DiagResults.SystemInfo.ComputerName -TechName $p.TechName -ScanMode "Gaming PC" }
        Set-Status "Gaming PC Report: $(if($pdfOK){'PDF saved'}else{'HTML saved'}) to reports folder" 100
        Start-Process explorer.exe -ArgumentList $p.OutputFolder
        [System.Windows.MessageBox]::Show($window, "Gaming PC Report saved!`n`nIncludes visual charts for:`n- Temperature bars (CPU/GPU)`n- Storage read/write speed bars`n- Network speed gauge`n- Component health donuts`n- RAM usage and fan speeds`n`nPrint-ready format with full branding.", "Gaming Report Ready", "OK", "Information")
    })

    # ── GAMING PERFORMANCE & STABILITY TEST ──
    $window.FindName("btnGamingPerfTest").Add_Click({
        $p = Get-Params; if (-not $p) { return }
        $confirm = [System.Windows.MessageBox]::Show($window, "This will run a full Gaming Performance & Stability Test:`n`n- CPU+GPU stress test with time-series sampling`n- Storage benchmark (DiskSpd or fallback)`n- Deep network test with jitter/packet loss`n- PresentMon FPS capture (if available)`n- Power stability analysis`n- Cooling recovery measurement`n`nEstimated time: 5-8 minutes.`nThe system will be under heavy load during testing.`n`nProceed?", "Gaming Performance Test", "YesNo", "Question")
        if ($confirm -ne [System.Windows.MessageBoxResult]::Yes) { return }

        $window.Dispatcher.Invoke([Action]{
            $window.FindName("btnGamingPerfTest").IsEnabled = $false
        })

        Set-Status "Starting Gaming Performance & Stability Test..." 5
        $statusCB = {
            param($Phase, $Message)
            $window.Dispatcher.Invoke([Action]{
                param($m)
                $window.FindName("txtStatus").Text = $m
            }, $Message)
        }

        $gamingResult = Invoke-GamingPerformanceTest -StressDurationSec 120 -StatusCallback $statusCB
        $Global:DiagResults.GamingPerformance = $gamingResult

        Set-Status "Generating Gaming Performance & Stability Report..." 85
        $gamingPerfHTML = Build-GamingPerformanceReport `
            -Params $p `
            -SystemInfo $gamingResult.SystemInfo `
            -TimeSeries $gamingResult.TimeSeries `
            -Storage $gamingResult.Storage `
            -NetworkDeep $gamingResult.Network `
            -FPS $gamingResult.FPS `
            -PowerStability $gamingResult.PowerStability `
            -PreStress $gamingResult.PreStressThermal `
            -PostStress $gamingResult.PostStressThermal `
            -Recovery $gamingResult.RecoveryThermal `
            -Scores $gamingResult.Scores `
            -Recommendations $gamingResult.Recommendations `
            -ScanMode "Gaming Performance Test"

        $safeName = $p.CustomerName -replace '[\\/:*?"<>|]','_'
        $safeDev = if ($gamingResult.SystemInfo.ComputerName) { $gamingResult.SystemInfo.ComputerName -replace '[\\/:*?"<>|]','_' } else { "PC" }
        $ds = Get-Date -Format "yyyy-MM-dd"
        $gamingPerfHTMLPath = Join-Path $p.OutputFolder "$safeName - $safeDev - Gaming Performance Report $ds.html"
        $gamingPerfPDFPath  = Join-Path $p.OutputFolder "$safeName - $safeDev - Gaming Performance Report $ds.pdf"
        [IO.File]::WriteAllText($gamingPerfHTMLPath, $gamingPerfHTML, [Text.Encoding]::UTF8)

        Set-Status "Converting Gaming Performance Report to PDF..." 92
        $pdfOK = Convert-ToPDF $gamingPerfHTMLPath $gamingPerfPDFPath
        Invoke-Safe { Invoke-AutoUploadReport -ReportPath $(if($pdfOK){$gamingPerfPDFPath}else{$gamingPerfHTMLPath}) -CustomerName $p.CustomerName -ComputerName $(if($gamingResult.SystemInfo.ComputerName){$gamingResult.SystemInfo.ComputerName}else{"PC"}) -TechName $p.TechName -ScanMode "Gaming Performance" }

        $window.Dispatcher.Invoke([Action]{
            $window.FindName("btnGamingPerfTest").IsEnabled = $true
        })

        $grade = $gamingResult.Scores.Grade
        $overall = $gamingResult.Scores.Overall
        $recCount = $gamingResult.Recommendations.Count
        Invoke-SaveBenchmark -TestType "Gaming"
        Set-Status "Gaming Performance Test complete: Grade $grade ($overall/100)" 100
        Start-Process explorer.exe -ArgumentList $p.OutputFolder
        [System.Windows.MessageBox]::Show($window, "Gaming Performance & Stability Test Complete!`n`nOverall Score: $overall / 100 (Grade $grade)`nThermal Score: $($gamingResult.Scores.Thermal)`nStorage: $($gamingResult.Scores.StorageSpeed)`nFPS Stability: $($gamingResult.Scores.FPSStability)`nPower: $($gamingResult.Scores.PowerStability)`nNetwork: $($gamingResult.Scores.NetworkScore)/100`n`nRecommendations: $recCount`nDuration: $($gamingResult.TotalMinutes) minutes`n`nReport includes time-series SVG charts for:`n- CPU/GPU temperature over time`n- CPU/GPU usage over time`n- Clock speed with throttle detection`n- Fan RPM over time`n- Storage benchmarks (DiskSpd)`n- Network performance`n- FPS analysis (if PresentMon available)", "Gaming Performance Report Ready", "OK", "Information")
    })

    # ── LCD DISPLAY WEAR & LIFE TEST ──
    $window.FindName("btnLCDDisplay").Add_Click({
        $p = Get-Params; if (-not $p) { return }
        $confirm = [System.Windows.MessageBox]::Show($window, "This will run an LCD Display Wear & Life Test:`n`n- Monitor EDID / panel detection`n- Display adapter & driver analysis`n- Brightness capability check`n- Display/GPU stability event history (180 days)`n- Thermal correlation risk`n- Wear score calculation`n- Visual test page generator (dead pixels, burn-in, etc.)`n`nEstimated time: 1-2 minutes.`n`nProceed?", "LCD Display Test", "YesNo", "Question")
        if ($confirm -ne [System.Windows.MessageBoxResult]::Yes) { return }

        $window.Dispatcher.Invoke([Action]{
            $window.FindName("btnLCDDisplay").IsEnabled = $false
        })

        Set-Status "Starting LCD Display Wear & Life Test..." 5

        Set-Status "Collecting monitor and display data..." 15
        $lcdResult = Invoke-LCDDisplayTest
        $Global:DiagResults.LCDDisplay = $lcdResult

        Set-Status "Generating LCD Display Wear Report..." 70
        $lcdHTML = Build-LCDDisplayReport -Params $p -LCDData $lcdResult

        $safeName = $p.CustomerName -replace '[\\/:*?"<>|]','_'
        $safeDev = if ($lcdResult.System.ComputerName) { $lcdResult.System.ComputerName -replace '[\\/:*?"<>|]','_' } else { "PC" }
        $ds = Get-Date -Format "yyyy-MM-dd"
        $lcdHTMLPath = Join-Path $p.OutputFolder "$safeName - $safeDev - LCD Display Report $ds.html"
        $lcdPDFPath  = Join-Path $p.OutputFolder "$safeName - $safeDev - LCD Display Report $ds.pdf"
        $lcdVisualPath = Join-Path $p.OutputFolder "$safeName - $safeDev - LCD Visual Test $ds.html"

        [IO.File]::WriteAllText($lcdHTMLPath, $lcdHTML, [Text.Encoding]::UTF8)

        # Save the visual test page as a separate file
        if ($lcdResult.VisualTestHTML) {
            [IO.File]::WriteAllText($lcdVisualPath, $lcdResult.VisualTestHTML, [Text.Encoding]::UTF8)
        }

        Set-Status "Converting LCD Display Report to PDF..." 85
        $pdfOK = Convert-ToPDF $lcdHTMLPath $lcdPDFPath

        $window.Dispatcher.Invoke([Action]{
            $window.FindName("btnLCDDisplay").IsEnabled = $true
        })

        $lcdScore = $lcdResult.Score.Score
        $lcdGrade = $lcdResult.Score.Grade
        $lcdRisk  = $lcdResult.Score.Risk
        $findingCount = if ($lcdResult.Score.Findings) { $lcdResult.Score.Findings.Count } else { 0 }
        Set-Status "LCD Display Test complete: $lcdGrade ($lcdScore/100)" 100
        Start-Process explorer.exe -ArgumentList $p.OutputFolder
        [System.Windows.MessageBox]::Show($window, "LCD Display Wear & Life Test Complete!`n`nDisplay Wear Score: $lcdScore / 100`nGrade: $lcdGrade`nRisk Level: $lcdRisk`n`nApprox Life: $($lcdResult.Score.ApproxLife)`n`nFindings: $findingCount`nMonitors Detected: $($lcdResult.Monitor.MonitorCount)`nBrightness Supported: $($lcdResult.Brightness.BrightnessSupported)`nDisplay Events (180d): $($lcdResult.Events.EventCount)`nDriver Resets: $($lcdResult.Events.DriverResetCount)`nThermal Events: $($lcdResult.Thermal.ThermalEventCount)`n`nReport saved to output folder.`nA separate LCD Visual Test HTML file has also been saved.", "LCD Display Report Ready", "OK", "Information")
    })

    # ── QUICK FIX (REMEDIATION DIALOG) ──
    $window.FindName("btnQuickFix").Add_Click({
        $qfXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="PC Plus 360 - Quick Fix" Height="620" Width="560"
        WindowStartupLocation="CenterScreen" ResizeMode="NoResize"
        Background="#eef4f8" FontFamily="Segoe UI">
    <Window.Resources>
        <Style x:Key="FlatBtn" TargetType="Button">
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="bd" Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="6" Padding="{TemplateBinding Padding}">
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
    </Window.Resources>
    <Grid>
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <!-- Header -->
        <Border Grid.Row="0" Background="#0a3a56" Padding="16,14">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="*"/>
                </Grid.ColumnDefinitions>
                <Border Width="36" Height="36" CornerRadius="8" Margin="0,0,12,0">
                    <Border.Background>
                        <LinearGradientBrush StartPoint="0,0" EndPoint="1,1">
                            <GradientStop Color="#f43f5e" Offset="0"/>
                            <GradientStop Color="#fb7185" Offset="1"/>
                        </LinearGradientBrush>
                    </Border.Background>
                    <TextBlock Text="&#xE15E;" FontFamily="Segoe MDL2 Assets" FontSize="16" Foreground="White" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                </Border>
                <StackPanel Grid.Column="1" VerticalAlignment="Center">
                    <TextBlock Text="Quick Fix - One-Click Remediation" FontSize="15" FontWeight="SemiBold" Foreground="White"/>
                    <TextBlock Text="Select fixes to apply and click Run" FontSize="10.5" Foreground="#fb7185"/>
                </StackPanel>
            </Grid>
        </Border>

        <!-- Content -->
        <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto" Margin="0">
            <StackPanel Margin="18,14,18,10">

                <!-- Fix Options -->
                <Border Background="White" CornerRadius="7" Padding="12" Margin="0,0,0,10" BorderBrush="#d8e8f0" BorderThickness="1">
                    <StackPanel>
                        <TextBlock Text="SELECT FIXES TO APPLY" FontSize="8.5" FontWeight="SemiBold" Foreground="#8a9baa" Margin="0,0,0,8"/>
                        <CheckBox x:Name="chkCleanTemp" Margin="0,4" IsChecked="True">
                            <StackPanel>
                                <TextBlock Text="Clean Temp Files" FontSize="12" FontWeight="SemiBold" Foreground="#1a2b3c"/>
                                <TextBlock Text="Remove Windows temp, user temp, prefetch, browser caches" FontSize="9.5" Foreground="#5a7080"/>
                            </StackPanel>
                        </CheckBox>
                        <CheckBox x:Name="chkPowerPlan" Margin="0,4">
                            <StackPanel>
                                <TextBlock Text="Optimize Power Plan" FontSize="12" FontWeight="SemiBold" Foreground="#1a2b3c"/>
                                <TextBlock Text="High Performance (desktop) or Balanced (laptop on battery)" FontSize="9.5" Foreground="#5a7080"/>
                            </StackPanel>
                        </CheckBox>
                        <CheckBox x:Name="chkStartupBloat" Margin="0,4">
                            <StackPanel>
                                <TextBlock Text="Disable Startup Bloat" FontSize="12" FontWeight="SemiBold" Foreground="#1a2b3c"/>
                                <TextBlock Text="Disable Cortana, OneDrive, Teams, Skype, Adobe updater, etc." FontSize="9.5" Foreground="#5a7080"/>
                            </StackPanel>
                        </CheckBox>
                        <CheckBox x:Name="chkDNSCache" Margin="0,4">
                            <StackPanel>
                                <TextBlock Text="Clear DNS Cache" FontSize="12" FontWeight="SemiBold" Foreground="#1a2b3c"/>
                                <TextBlock Text="Flush DNS resolver cache to fix stale lookups" FontSize="9.5" Foreground="#5a7080"/>
                            </StackPanel>
                        </CheckBox>
                        <CheckBox x:Name="chkRepairImage" Margin="0,4">
                            <StackPanel>
                                <TextBlock Text="Repair Windows Image" FontSize="12" FontWeight="SemiBold" Foreground="#1a2b3c"/>
                                <TextBlock Text="Run DISM RestoreHealth + SFC scannow (takes several minutes)" FontSize="9.5" Foreground="#f59e0b"/>
                            </StackPanel>
                        </CheckBox>
                        <CheckBox x:Name="chkUpdateDrivers" Margin="0,4">
                            <StackPanel>
                                <TextBlock Text="Check for Driver Updates" FontSize="12" FontWeight="SemiBold" Foreground="#1a2b3c"/>
                                <TextBlock Text="Opens Windows Update and triggers update scan" FontSize="9.5" Foreground="#5a7080"/>
                            </StackPanel>
                        </CheckBox>
                        <CheckBox x:Name="chkVisualEffects" Margin="0,4">
                            <StackPanel>
                                <TextBlock Text="Optimize Visual Effects" FontSize="12" FontWeight="SemiBold" Foreground="#1a2b3c"/>
                                <TextBlock Text="Set to 'Best Performance' - disables animations and shadows" FontSize="9.5" Foreground="#5a7080"/>
                            </StackPanel>
                        </CheckBox>
                    </StackPanel>
                </Border>

                <!-- Results Log -->
                <Border Background="White" CornerRadius="7" Padding="12" Margin="0,0,0,4" BorderBrush="#d8e8f0" BorderThickness="1">
                    <StackPanel>
                        <TextBlock Text="RESULTS" FontSize="8.5" FontWeight="SemiBold" Foreground="#8a9baa" Margin="0,0,0,6"/>
                        <TextBox x:Name="txtQFResults" Height="140" IsReadOnly="True" TextWrapping="Wrap"
                                 VerticalScrollBarVisibility="Auto" FontSize="10.5" FontFamily="Consolas"
                                 Background="#f8fafc" Foreground="#1a2b3c" BorderBrush="#d8e8f0" Padding="8"
                                 Text="Select fixes above and click 'Run Selected Fixes' to begin."/>
                    </StackPanel>
                </Border>
            </StackPanel>
        </ScrollViewer>

        <!-- Footer Buttons -->
        <Border Grid.Row="2" Background="#f0f5f9" Padding="18,10" BorderBrush="#d8e8f0" BorderThickness="0,1,0,0">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <TextBlock Grid.Column="0" VerticalAlignment="Center" FontSize="9.5" Foreground="#5a7080">
                    <Run Text="PC Plus Computing"/>
                    <Run Text=" | "/>
                    <Run Text="Quick Fix Toolkit"/>
                </TextBlock>
                <Button x:Name="btnQFClose" Grid.Column="1" Style="{StaticResource FlatBtn}" Background="#e2e8f0" Padding="18,8" Margin="0,0,8,0">
                    <TextBlock Text="Close" FontSize="11.5" FontWeight="SemiBold" Foreground="#475569"/>
                </Button>
                <Button x:Name="btnQFRun" Grid.Column="2" Style="{StaticResource FlatBtn}" Background="#f43f5e" Padding="22,8">
                    <TextBlock Text="Run Selected Fixes" FontSize="11.5" FontWeight="SemiBold" Foreground="White"/>
                </Button>
            </Grid>
        </Border>
    </Grid>
</Window>
"@

        try {
            $qfReader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($qfXaml))
            $qfDlg = [System.Windows.Markup.XamlReader]::Load($qfReader)
        }
        catch {
            Write-DiagLog "Failed to load Quick Fix dialog XAML: $($_.Exception.Message)" "ERROR"
            [System.Windows.MessageBox]::Show($window, "Could not open Quick Fix dialog: $($_.Exception.Message)", "Error", "OK", "Error")
            return
        }

        # Grab controls
        $chkCleanTemp    = $qfDlg.FindName("chkCleanTemp")
        $chkPowerPlan    = $qfDlg.FindName("chkPowerPlan")
        $chkStartupBloat = $qfDlg.FindName("chkStartupBloat")
        $chkDNSCache     = $qfDlg.FindName("chkDNSCache")
        $chkRepairImage  = $qfDlg.FindName("chkRepairImage")
        $chkUpdateDrivers = $qfDlg.FindName("chkUpdateDrivers")
        $chkVisualEffects = $qfDlg.FindName("chkVisualEffects")
        $txtQFResults    = $qfDlg.FindName("txtQFResults")
        $btnQFRun        = $qfDlg.FindName("btnQFRun")
        $btnQFClose      = $qfDlg.FindName("btnQFClose")

        $btnQFClose.Add_Click({ $qfDlg.Close() })

        $btnQFRun.Add_Click({
            $actions = [System.Collections.ArrayList]::new()
            if ($chkCleanTemp.IsChecked)    { $null = $actions.Add("CleanTempFiles") }
            if ($chkPowerPlan.IsChecked)    { $null = $actions.Add("OptimizePowerPlan") }
            if ($chkStartupBloat.IsChecked) { $null = $actions.Add("DisableStartupBloat") }
            if ($chkDNSCache.IsChecked)     { $null = $actions.Add("ClearDNSCache") }
            if ($chkRepairImage.IsChecked)  { $null = $actions.Add("RepairWindowsImage") }
            if ($chkUpdateDrivers.IsChecked){ $null = $actions.Add("UpdateDrivers") }
            if ($chkVisualEffects.IsChecked){ $null = $actions.Add("OptimizeVisualEffects") }

            if ($actions.Count -eq 0) {
                $txtQFResults.Text = "Please select at least one fix to run."
                return
            }

            $btnQFRun.IsEnabled = $false
            $btnQFClose.IsEnabled = $false
            $txtQFResults.Text = "Running $($actions.Count) fix(es)...`r`n"
            $qfDlg.Dispatcher.Invoke([Action]{}, [System.Windows.Threading.DispatcherPriority]::Background)

            $totalRecovered = [long]0
            $successCount = 0
            $failCount = 0

            foreach ($action in $actions) {
                $txtQFResults.Text += "`r`n[$action] Running..."
                $qfDlg.Dispatcher.Invoke([Action]{}, [System.Windows.Threading.DispatcherPriority]::Background)

                $res = Invoke-Safe { Invoke-QuickRemediation -Action $action } $null

                if ($res -and $res.Success) {
                    $successCount++
                    $statusIcon = "OK"
                    if ($res.BytesRecovered -gt 0) { $totalRecovered += $res.BytesRecovered }
                }
                else {
                    $failCount++
                    $statusIcon = "FAIL"
                }

                $detail = if ($res) { $res.Details } else { "Unknown error" }
                $txtQFResults.Text += "`r`n[$action] $statusIcon - $detail"
                $qfDlg.Dispatcher.Invoke([Action]{}, [System.Windows.Threading.DispatcherPriority]::Background)
            }

            $summaryLine = "`r`n`r`n--- SUMMARY ---`r`nCompleted: $successCount succeeded, $failCount failed"
            if ($totalRecovered -gt 0) {
                $summaryLine += " | Space recovered: $([math]::Round($totalRecovered / 1MB, 1)) MB"
            }
            $txtQFResults.Text += $summaryLine

            $btnQFRun.IsEnabled = $true
            $btnQFClose.IsEnabled = $true
        })

        $qfDlg.ShowDialog() | Out-Null
    })

    # ── SEND REPORT (PAPERLESS) ──
    $window.FindName("btnPaperless").Add_Click({
        $p = Get-Params; if (-not $p) { return }
        if (-not $Global:DiagResults.SystemInfo) { [System.Windows.MessageBox]::Show($window, "Run a diagnostic and generate a report first.", "No Data", "OK", "Warning"); return }
        $reportFiles = @()
        Get-ChildItem $p.OutputFolder -Filter "*.pdf" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 5 | ForEach-Object { $reportFiles += $_.FullName }
        if ($reportFiles.Count -eq 0) {
            Get-ChildItem $p.OutputFolder -Filter "*.html" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 5 | ForEach-Object { $reportFiles += $_.FullName }
        }
        if ($reportFiles.Count -eq 0) { [System.Windows.MessageBox]::Show($window, "No reports found. Generate a report first.", "No Reports", "OK", "Warning"); return }
        $latestReport = $reportFiles[0]
        Show-PaperlessDialog -ReportPath $latestReport -CustomerName $p.CustomerName -ComputerName $Global:DiagResults.SystemInfo.ComputerName -TechName $p.TechName -ScanMode $Global:DiagResults.ScanMode
    })

    # ── BENCHMARKS DATABASE VIEWER ──
    $window.FindName("btnBenchmarks").Add_Click({
        try {
            Set-Status "Loading benchmark database..." 30
            $benchSummary = Get-BenchmarkSummary
            if (-not $benchSummary.DatabaseExists -or $benchSummary.TotalBenchmarks -eq 0) {
                [System.Windows.MessageBox]::Show($window, "No benchmark data yet.`n`nBenchmark results are saved automatically after each scan completes. Run a Quick, Standard, Deep, MRI, or Gaming test to start building your comparison database.", "Benchmark Database", "OK", "Information")
                Set-Status "Ready" 0
                return
            }

            # Build summary message
            $msg = "BENCHMARK DATABASE SUMMARY`n"
            $msg += "================================`n`n"
            $msg += "Total Benchmarks: $($benchSummary.TotalBenchmarks)`n"
            $msg += "Unique Systems: $($benchSummary.UniqueComputers)`n"
            $msg += "Unique CPUs: $($benchSummary.UniqueCPUs)`n"
            $msg += "Last Benchmark: $($benchSummary.LastBenchmarkDate)`n`n"

            $msg += "AVERAGE SCORES`n"
            $msg += "----------------------------`n"
            $msg += "Overall:  $($benchSummary.AverageScores.Overall)/100`n"
            $msg += "Thermal:  $($benchSummary.AverageScores.Thermal)/100`n"
            $msg += "Storage:  $($benchSummary.AverageScores.Storage)/100`n"
            $msg += "Network:  $($benchSummary.AverageScores.Network)/100`n"
            $msg += "Security: $($benchSummary.AverageScores.Security)/100`n`n"

            if ($benchSummary.ScoresByTestType.Count -gt 0) {
                $msg += "BY TEST TYPE`n"
                $msg += "----------------------------`n"
                foreach ($tt in $benchSummary.ScoresByTestType.Keys) {
                    $ttData = $benchSummary.ScoresByTestType[$tt]
                    $msg += "$($tt): $($ttData.Count) tests, avg $($ttData.AvgScore)/100`n"
                }
                $msg += "`n"
            }

            if ($benchSummary.HardwareTiers.Count -gt 0) {
                $msg += "BY HARDWARE TIER`n"
                $msg += "----------------------------`n"
                foreach ($tier in $benchSummary.HardwareTiers) {
                    $msg += "$($tier.RAMRange) RAM: $($tier.Count) systems, avg $($tier.AvgScore)/100`n"
                }
                $msg += "`n"
            }

            if ($benchSummary.Top10.Count -gt 0) {
                $msg += "TOP PERFORMERS`n"
                $msg += "----------------------------`n"
                $rank = 1
                foreach ($top in $benchSummary.Top10) {
                    $cpuShort = $top.CPUModel
                    if ($cpuShort.Length -gt 30) { $cpuShort = $cpuShort.Substring(0, 30) + "..." }
                    $msg += "$rank. $($top.ComputerName) - $($top.Overall)/100 ($($top.Grade)) - $cpuShort`n"
                    $rank++
                }
            }

            Set-Status "Benchmark database loaded: $($benchSummary.TotalBenchmarks) entries" 100
            [System.Windows.MessageBox]::Show($window, $msg, "PC Plus 360 - Benchmark Database", "OK", "Information")
        } catch {
            Write-DebugLog "Benchmarks ERROR: $($_.Exception.Message)"
            [System.Windows.MessageBox]::Show($window, "Error loading benchmarks: $($_.Exception.Message)", "Error", "OK", "Error")
        }
    })

    # ── CHECK FOR UPDATES (BUTTON) ──
    $window.FindName("btnCheckUpdate").Add_Click({
        Write-DiagLog "Manual update check triggered"
        $window.FindName("lblUpdateStatus").Text = "Checking..."
        $window.FindName("lblUpdateStatus").Foreground = [System.Windows.Media.Brushes]::Gray

        # Force a UI refresh before the blocking call
        $frame = New-Object System.Windows.Threading.DispatcherFrame
        [System.Windows.Threading.Dispatcher]::CurrentDispatcher.BeginInvoke(
            [System.Windows.Threading.DispatcherPriority]::Background,
            [System.Action]{ $frame.Continue = $false }
        )
        [System.Windows.Threading.Dispatcher]::PushFrame($frame)

        $updateInfo = Test-ToolkitUpdate -CurrentVersion $VERSION -ScriptDir $Global:ScriptDir
        if ($updateInfo.UpdateAvailable) {
            Write-DiagLog "Update available: $($updateInfo.LatestVersion) from $($updateInfo.Source)"
            $window.FindName("lblUpdateStatus").Text = "v$($updateInfo.LatestVersion) available!"
            $window.FindName("lblUpdateStatus").Foreground = [System.Windows.Media.Brushes]::Orange
            $answer = [System.Windows.MessageBox]::Show(
                $window,
                "A newer version is available!`n`nCurrent: v$($updateInfo.CurrentVersion)`nLatest:  v$($updateInfo.LatestVersion)`nSource:  $($updateInfo.Source)`n`nWould you like to update now?`n(Current files will be backed up with .bak extension)",
                "PC Plus 360 - Update Available",
                "YesNo",
                "Information"
            )
            if ($answer -eq [System.Windows.MessageBoxResult]::Yes) {
                Write-DiagLog "User accepted update"
                $window.FindName("lblUpdateStatus").Text = "Updating..."
                $frame2 = New-Object System.Windows.Threading.DispatcherFrame
                [System.Windows.Threading.Dispatcher]::CurrentDispatcher.BeginInvoke(
                    [System.Windows.Threading.DispatcherPriority]::Background,
                    [System.Action]{ $frame2.Continue = $false }
                )
                [System.Windows.Threading.Dispatcher]::PushFrame($frame2)

                $result = Invoke-ToolkitUpdate -UpdateInfo $updateInfo -ScriptDir $Global:ScriptDir
                if ($result.Success) {
                    Write-DiagLog "Update applied successfully: $($result.Message)"
                    $window.FindName("lblUpdateStatus").Text = "Updated! Restart required."
                    $window.FindName("lblUpdateStatus").Foreground = [System.Windows.Media.Brushes]::LimeGreen
                    [System.Windows.MessageBox]::Show(
                        $window,
                        "Update applied successfully!`n`n$($result.Message)`n`nPlease restart PC Plus 360 to use the new version.",
                        "Update Complete",
                        "OK",
                        "Information"
                    )
                } else {
                    Write-DiagLog "Update failed: $($result.Message)"
                    $window.FindName("lblUpdateStatus").Text = "Update failed"
                    $window.FindName("lblUpdateStatus").Foreground = [System.Windows.Media.Brushes]::Red
                    [System.Windows.MessageBox]::Show(
                        $window,
                        "Update failed:`n`n$($result.Message)",
                        "Update Error",
                        "OK",
                        "Error"
                    )
                }
            }
        } else {
            Write-DiagLog "No update available (current: $VERSION)"
            $window.FindName("lblUpdateStatus").Text = "Up to date"
            $window.FindName("lblUpdateStatus").Foreground = [System.Windows.Media.Brushes]::LimeGreen
            [System.Windows.MessageBox]::Show(
                $window,
                "You are running the latest version (v$VERSION).",
                "PC Plus 360 - No Updates",
                "OK",
                "Information"
            )
        }
    })

    # ── STARTUP VERSION CHECK (non-blocking notification) ──
    $window.Add_ContentRendered({
        Write-DiagLog "Startup update check..."
        try {
            $updateInfo = Test-ToolkitUpdate -CurrentVersion $VERSION -ScriptDir $Global:ScriptDir
            if ($updateInfo.UpdateAvailable) {
                Write-DiagLog "Startup check: update available v$($updateInfo.LatestVersion)"
                $window.FindName("lblUpdateStatus").Text = "v$($updateInfo.LatestVersion) available"
                $window.FindName("lblUpdateStatus").Foreground = [System.Windows.Media.Brushes]::Orange
                $window.FindName("txtStatus").Text = "Update available: v$($updateInfo.LatestVersion) from $($updateInfo.Source). Click 'Check for Updates' in the sidebar."
            } else {
                Write-DiagLog "Startup check: up to date"
            }
        } catch {
            Write-DiagLog "Startup update check failed: $($_.Exception.Message)" "WARN"
        }
    })

    $window.ShowDialog() | Out-Null
}


# ─────────────────────────────────────────────────────────────────────────────
# ENTRY POINT
# ─────────────────────────────────────────────────────────────────────────────
Write-DebugLog "About to call Show-Launcher..."
try {
    Show-Launcher
    Write-DebugLog "Show-Launcher completed normally"
} catch {
    $errMsg = "$($_.Exception.Message)`nLine: $($_.InvocationInfo.ScriptLineNumber)`n$($_.Exception.StackTrace)"
    Write-DebugLog "FATAL ERROR: $errMsg"
    [System.Windows.Forms.MessageBox]::Show("PC Plus 360 Error:`n`n$errMsg", "PC Plus 360 - Error", "OK", "Error") | Out-Null
}
Write-DebugLog "Script finished."

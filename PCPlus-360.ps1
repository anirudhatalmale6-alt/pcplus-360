<#
.SYNOPSIS
    PC Plus Computing 360 Hardware & Security Diagnostic Suite
.DESCRIPTION
    Complete diagnostic platform with branded launcher, built-in stress tests,
    third-party tool integration, and dual report generation (Hardware + Security).
    Runs from USB drive with no installation required.
.NOTES
    Company:  PC Plus Computing
    Version:  2.3.0
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
$Global:LogLines = [System.Collections.ArrayList]::new()

$COMPANY      = "PC Plus Computing"
$PHONE        = "604-760-1662 | 236-500-2700"
$WEBSITE      = "pcpluscomputing.com"
$VERSION      = "2.3.0"

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
        Title="PC Plus 360 Hardware Diagnostic Suite" Height="720" Width="960"
        WindowStartupLocation="CenterScreen" ResizeMode="CanMinimize"
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
                        <TextBlock Text="v2.3.0" FontSize="10" Foreground="#2596be" FontFamily="Consolas"/>
                        <TextBlock Text="604-760-1662 | 236-500-2700" FontSize="8.5" Foreground="#4a7a8a" Margin="0,2,0,0"/>
                        <TextBlock Text="pcpluscomputing.com" FontSize="8.5" Foreground="#3a6a7a"/>
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

                        <TextBlock Text="  REPORTS" FontSize="9" FontWeight="SemiBold" Foreground="#4a7a8a" Margin="0,12,0,4"/>
                        <Button x:Name="btnHWReport" Style="{StaticResource SideNav}"><TextBlock Text="  Hardware Report" FontSize="11.5" Foreground="#22c55e"/></Button>
                        <Button x:Name="btnSecReport" Style="{StaticResource SideNav}"><TextBlock Text="  Security Report" FontSize="11.5" Foreground="#f59e0b"/></Button>
                        <Button x:Name="btnBothReports" Style="{StaticResource SideNav}"><TextBlock Text="  Both Reports" FontSize="11.5" Foreground="#2596be"/></Button>
                        <Button x:Name="btnCustomerSummary" Style="{StaticResource SideNav}"><TextBlock Text="  Customer Summary" FontSize="11.5" Foreground="#3bbde0" FontWeight="SemiBold"/></Button>
                        <Button x:Name="btnGamingReport" Style="{StaticResource SideNav}"><TextBlock Text="  Gaming PC Report" FontSize="11.5" Foreground="#f472b6" FontWeight="SemiBold"/></Button>
                        <Button x:Name="btnPaperless" Style="{StaticResource SideNav}"><TextBlock Text="  Send Report" FontSize="11.5" Foreground="#34d399" FontWeight="SemiBold"/></Button>
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
                            <Grid.RowDefinitions><RowDefinition/><RowDefinition/></Grid.RowDefinitions>
                            <StackPanel Grid.Column="0" Margin="0,0,6,0">
                                <TextBlock Text="CUSTOMER NAME *" FontSize="8.5" FontWeight="SemiBold" Foreground="#8a9baa" Margin="0,0,0,2"/>
                                <TextBox x:Name="txtCustomer" FontSize="12" Padding="6,4" Background="#f6f9fb" Foreground="#1a2b3c" BorderBrush="#d8e8f0"/>
                            </StackPanel>
                            <StackPanel Grid.Column="1" Margin="3,0,3,0">
                                <TextBlock Text="CONTACT NAME" FontSize="8.5" FontWeight="SemiBold" Foreground="#8a9baa" Margin="0,0,0,2"/>
                                <TextBox x:Name="txtContact" FontSize="12" Padding="6,4" Background="#f6f9fb" Foreground="#1a2b3c" BorderBrush="#d8e8f0"/>
                            </StackPanel>
                            <StackPanel Grid.Column="2" Margin="6,0,0,0">
                                <TextBlock Text="TECHNICIAN" FontSize="8.5" FontWeight="SemiBold" Foreground="#8a9baa" Margin="0,0,0,2"/>
                                <TextBox x:Name="txtTech" Text="Paul" FontSize="12" Padding="6,4" Background="#f6f9fb" Foreground="#1a2b3c" BorderBrush="#d8e8f0"/>
                            </StackPanel>
                            <StackPanel Grid.Row="1" Grid.ColumnSpan="3" Margin="0,6,0,0">
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
                            <RowDefinition Height="30"/><RowDefinition Height="30"/><RowDefinition Height="30"/><RowDefinition Height="30"/><RowDefinition Height="30"/><RowDefinition Height="30"/>
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
                    </Grid>

                    <!-- Run Bar -->
                    <Border Background="White" CornerRadius="7" Padding="12" Margin="0,0,0,8" BorderBrush="#d8e8f0" BorderThickness="1">
                        <Grid>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/>
                            </Grid.ColumnDefinitions>
                            <Button x:Name="btnRunSelected" Style="{StaticResource FlatBtn}" Background="#2596be" Padding="18,9">
                                <TextBlock Text="RUN SELECTED TESTS" FontSize="12" FontWeight="Bold" Foreground="White"/>
                            </Button>
                            <StackPanel Grid.Column="1" Margin="12,0,0,0" VerticalAlignment="Center">
                                <TextBlock x:Name="lblSelectedCount" Text="0 tests selected" FontSize="11.5" FontWeight="SemiBold" Foreground="#1a2b3c"/>
                                <TextBlock x:Name="lblEstTime" Text="Select tests to begin" FontSize="9.5" Foreground="#8a9baa"/>
                            </StackPanel>
                            <StackPanel Grid.Column="2" Orientation="Horizontal" VerticalAlignment="Center">
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
    $txtContact = $window.FindName("txtContact")
    $txtTech = $window.FindName("txtTech")
    $txtNotes = $window.FindName("txtNotes")
    $txtStatus = $window.FindName("txtStatus")
    $progressBar = $window.FindName("progressBar")
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
            [System.Windows.MessageBox]::Show($window, "Please enter a Customer Name in the first field.", "Customer Name Required", "OK", "Warning")
            $txtCustomer.Focus()
            return $null
        }
        Write-DebugLog "Params OK: Customer=$($txtCustomer.Text.Trim())"
        return @{ CustomerName = $txtCustomer.Text.Trim(); ContactName = $txtContact.Text.Trim(); TechName = $txtTech.Text.Trim(); TechNotes = $txtNotes.Text.Trim(); OutputFolder = $Global:ReportsDir }
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
    }

    # Quick Scan header button triggers Quick Test
    $window.FindName("btnQuickScan").Add_Click({
        $window.FindName("btnQuick").RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))
    })

    # ── RUN SELECTED TESTS ──
    $window.FindName("btnRunSelected").Add_Click({
        try {
            $p = Get-Params; if (-not $p) { return }
            $anyChecked = $false
            foreach ($c in @($chkCPU,$chkRAM,$chkDisk,$chkSMART,$chkBattery,$chkNetwork,$chkSecurity,$chkKeys,$chkDebloat,$chkRAMIso,$chkPassRecovery,$chkWinDeep,$chkNirSoft,$chkSSDLife,$chkGPU,$chkWearTear,$chkSpeedTest,$chkThermal)) {
                if ($c.IsChecked) { $anyChecked = $true; break }
            }
            if (-not $anyChecked) {
                [System.Windows.MessageBox]::Show($window, "Please check at least one test to run.", "No Tests Selected", "OK", "Warning")
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
                $stepsDone++
                Set-Status "Running CPU stress test (60 sec)..." ([int](10 + ($stepsDone / $totalInline) * 80))
                $Global:DiagResults.CPUStress = Start-CPUStressTest -DurationSeconds 60
                $r = $Global:DiagResults.CPUStress
                Set-Status "CPU: $(if($r.Passed){'PASS'}else{'FAIL'}) - $($r.Iterations) iterations" ([int](10 + ($stepsDone / $totalInline) * 80))
            }
            if ($chkRAM.IsChecked) {
                $stepsDone++
                Set-Status "Running RAM test (60 sec)..." ([int](10 + ($stepsDone / $totalInline) * 80))
                $Global:DiagResults.RAMStress = Start-RAMStressTest -DurationSeconds 60
                $r = $Global:DiagResults.RAMStress
                Set-Status "RAM: $(if($r.Passed){'PASS'}else{'FAIL'}) - $($r.TotalMBTested) MB tested" ([int](10 + ($stepsDone / $totalInline) * 80))
            }
            if ($chkDisk.IsChecked) {
                $stepsDone++
                Set-Status "Running disk benchmark (256MB)..." ([int](10 + ($stepsDone / $totalInline) * 80))
                $Global:DiagResults.DiskBench = Start-DiskBenchmark -FileSizeMB 256
                $r = $Global:DiagResults.DiskBench
                Set-Status "Disk: W=$($r.SeqWriteMBps) R=$($r.SeqReadMBps) MB/s" ([int](10 + ($stepsDone / $totalInline) * 80))
            }
            if ($chkSMART.IsChecked) {
                $stepsDone++
                Set-Status "Reading SMART data..." ([int](10 + ($stepsDone / $totalInline) * 80))
                $smart = Invoke-Safe { Get-PhysicalDisk | ForEach-Object { $r=Get-StorageReliabilityCounter -PhysicalDisk $_ -ErrorAction SilentlyContinue; "$($_.FriendlyName): $($_.HealthStatus)" } } "Error"
                Set-Status "SMART: $($smart -join ' | ')" ([int](10 + ($stepsDone / $totalInline) * 80))
            }
            if ($chkBattery.IsChecked) {
                $stepsDone++
                Set-Status "Checking battery..." ([int](10 + ($stepsDone / $totalInline) * 80))
                $Global:DiagResults.BatteryDetail = Get-DetailedBatteryInfo
            }
            if ($chkNetwork.IsChecked) {
                $stepsDone++
                Set-Status "Testing network..." ([int](10 + ($stepsDone / $totalInline) * 80))
                $Global:DiagResults.Network = Get-NetworkDiagnostics
                $net = $Global:DiagResults.Network
                Set-Status "Network: DNS $(if($net.DNSTest.Success){'OK'}else{'FAIL'}), Internet $(if($net.InternetTest.Success){'OK'}else{'FAIL'})" ([int](10 + ($stepsDone / $totalInline) * 80))
            }
            if ($chkSecurity.IsChecked) {
                $stepsDone++
                Set-Status "Running security audit..." ([int](10 + ($stepsDone / $totalInline) * 80))
                $Global:DiagResults.Security = Get-FullSecurityInfo
                $Global:DiagResults.Patches = Get-MissingPatchesList
                $Global:DiagResults.Scoring = Calculate-Score $Global:DiagResults.Security $Global:DiagResults.Patches
            }
            if ($chkKeys.IsChecked) {
                $stepsDone++
                Set-Status "Recovering license keys..." ([int](10 + ($stepsDone / $totalInline) * 80))
                $Global:DiagResults.LicenseKeys = Get-LicenseKeys
                $lk = $Global:DiagResults.LicenseKeys
                $wk = if ($lk.WindowsKeys.Count -gt 0) { $lk.WindowsKeys[0].Key } else { "Not found" }
                Set-Status "Windows Key: $wk | WiFi: $($lk.WiFiPasswords.Count) networks" ([int](10 + ($stepsDone / $totalInline) * 80))
            }
            if ($chkSSDLife.IsChecked) {
                $stepsDone++
                Set-Status "Analyzing SSD/HDD life and health..." ([int](10 + ($stepsDone / $totalInline) * 80))
                $Global:DiagResults.SSDLife = Get-SSDLifeReport
                $driveCount = $Global:DiagResults.SSDLife.Drives.Count
                $healthy = $Global:DiagResults.SSDLife.OverallHealthy
                Set-Status "SSD Life: $driveCount drive(s) - $(if($healthy){'All Healthy'}else{'Issues Found'})" ([int](10 + ($stepsDone / $totalInline) * 80))
            }
            if ($chkGPU.IsChecked) {
                $stepsDone++
                Set-Status "Running GPU stress test (60 sec)..." ([int](10 + ($stepsDone / $totalInline) * 80))
                $Global:DiagResults.GPUStress = Start-GPUStressTest -DurationSeconds 60
                $r = $Global:DiagResults.GPUStress
                Set-Status "GPU: $(if($r.Passed){'PASS'}else{'FAIL'}) - $($r.GPUName), $($r.Iterations) iterations" ([int](10 + ($stepsDone / $totalInline) * 80))
            }
            if ($chkWinDeep.IsChecked) {
                $stepsDone++
                Set-Status "Running Deep Windows test (SFC, DISM, services, file system)..." ([int](10 + ($stepsDone / $totalInline) * 80))
                $Global:DiagResults.WindowsDeep = Invoke-DeepWindowsTest
                $wd = $Global:DiagResults.WindowsDeep
                Set-Status "Windows Deep: Score=$($wd.Score)/100 ($($wd.Grade))" ([int](10 + ($stepsDone / $totalInline) * 80))
            }
            if ($chkWearTear.IsChecked) {
                $stepsDone++
                Set-Status "Running Wear & Tear lifecycle analysis..." ([int](10 + ($stepsDone / $totalInline) * 80))
                $Global:DiagResults.WearTear = Invoke-WearAndTearReport
                $wt = $Global:DiagResults.WearTear
                Set-Status "Wear & Tear: Score=$($wt.Score)/100 ($($wt.Grade)) - $($wt.RiskLevel) risk" ([int](10 + ($stepsDone / $totalInline) * 80))
            }
            if ($chkSpeedTest.IsChecked) {
                $stepsDone++
                Set-Status "Running internet speed test..." ([int](10 + ($stepsDone / $totalInline) * 80))
                $Global:DiagResults.SpeedTest = Get-NetworkSpeedTest
                $Global:DiagResults.SpeedTest2 = Invoke-SpeedtestCLI
                $st = $Global:DiagResults.SpeedTest
                Set-Status "Speed: Down=$($st.DownloadMbps) Up=$($st.UploadMbps) Mbps, Ping=$($st.PingMs)ms" ([int](10 + ($stepsDone / $totalInline) * 80))
            }
            if ($chkThermal.IsChecked) {
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
            [System.Windows.MessageBox]::Show($window, "All selected tests complete!", "Tests Complete", "OK", "Information")
        } catch {
            Write-DebugLog "Run Selected ERROR: $($_.Exception.Message) at line $($_.InvocationInfo.ScriptLineNumber)"
            Set-Status "ERROR: $($_.Exception.Message)" 0
            [System.Windows.MessageBox]::Show($window, "Error: $($_.Exception.Message)", "Error", "OK", "Error")
        } finally { Set-ScanButtons $true; $lblReadyStatus.Text = "Ready" }
    })

    # ── QUICK TEST (5-10 min) ──
    $window.FindName("btnQuick").Add_Click({
        try {
            $p = Get-Params; if (-not $p) { return }
            Set-ScanButtons $false
            $lblReadyStatus.Text = "Running..."
            $Global:DiagResults.ScanMode = "Quick"
            Set-Status "Quick Test: Collecting system info..." 5
            $Global:DiagResults.SystemInfo = Get-FullSystemInfo
            Set-Status "Quick Test: Security scan..." 20
            $Global:DiagResults.Security = Get-FullSecurityInfo
            Set-Status "Quick Test: Network info..." 35
            $Global:DiagResults.Network = Get-NetworkDiagnostics
            Set-Status "Quick Test: Software inventory..." 50
            $Global:DiagResults.Software = Get-SoftwareInventory
            Set-Status "Quick Test: Checking updates..." 60
            $Global:DiagResults.Patches = Get-MissingPatchesList
            Set-Status "Quick Test: Performance snapshot..." 70
            $Global:DiagResults.Performance = Get-PerformanceSnapshot
            Set-Status "Quick Test: License keys..." 78
            $Global:DiagResults.LicenseKeys = Get-LicenseKeys
            Set-Status "Quick Test: Crash history..." 85
            $Global:DiagResults.Stability = Get-CrashStabilityHistory
            Set-Status "Quick Test: Battery info..." 86
            $Global:DiagResults.BatteryDetail = Get-DetailedBatteryInfo
            Set-Status "Quick Test: Boot performance..." 90
            $Global:DiagResults.BootPerf = Get-BootPerformance
            Set-Status "Quick Test: Windows 11 readiness..." 93
            $Global:DiagResults.Win11Ready = Get-Windows11Readiness
            Set-Status "Quick Test: Calculating scores..." 97
            $Global:DiagResults.Scoring = Calculate-Score $Global:DiagResults.Security $Global:DiagResults.Patches
            $Global:DiagResults.StressResults = @{}
            $Global:DiagResults.SpeedTest = $null; $Global:DiagResults.Gaming = $null; $Global:DiagResults.PowerInfo = $null
            Set-Status "DONE! Quick Test complete. Generate reports from sidebar." 100
            Complete-Scan
            [System.Windows.MessageBox]::Show($window, "Quick Test complete!`nStability: $($Global:DiagResults.Stability.StabilityRating)`n`nClick a Report button in the sidebar to save PDFs.", "Quick Test Complete", "OK", "Information")
        } catch {
            Write-DebugLog "Quick Test ERROR: $($_.Exception.Message) at line $($_.InvocationInfo.ScriptLineNumber)"
            Set-Status "ERROR: $($_.Exception.Message)" 0
            [System.Windows.MessageBox]::Show($window, "Error during Quick Test:`n`n$($_.Exception.Message)", "Error", "OK", "Error")
        } finally { Set-ScanButtons $true; $lblReadyStatus.Text = "Ready" }
    })

    # ── STANDARD TEST (20-30 min) ──
    $window.FindName("btnStandard").Add_Click({
        try {
            $p = Get-Params; if (-not $p) { return }
            Set-ScanButtons $false
            $lblReadyStatus.Text = "Running..."
            $Global:DiagResults.ScanMode = "Standard"
            Set-Status "Standard Test: Collecting system info..." 2
            $Global:DiagResults.SystemInfo = Get-FullSystemInfo
            Set-Status "Standard Test: Security scan..." 8
            $Global:DiagResults.Security = Get-FullSecurityInfo
            Set-Status "Standard Test: Network analysis..." 14
            $Global:DiagResults.Network = Get-NetworkDiagnostics
            Set-Status "Standard Test: Network speed test..." 18
            $Global:DiagResults.SpeedTest = Get-NetworkSpeedTest
            Set-Status "Standard Test: Software inventory..." 24
            $Global:DiagResults.Software = Get-SoftwareInventory
            Set-Status "Standard Test: Checking updates..." 28
            $Global:DiagResults.Patches = Get-MissingPatchesList
            Set-Status "Standard Test: Performance snapshot..." 32
            $Global:DiagResults.Performance = Get-PerformanceSnapshot
            Set-Status "Standard Test: License keys..." 36
            $Global:DiagResults.LicenseKeys = Get-LicenseKeys
            Set-Status "Standard Test: Crash history..." 40
            $Global:DiagResults.Stability = Get-CrashStabilityHistory
            Set-Status "Standard Test: Battery report..." 44
            $Global:DiagResults.BatteryDetail = Get-DetailedBatteryInfo
            Set-Status "Standard Test: Power stability..." 47
            $Global:DiagResults.PowerInfo = Get-PowerStabilityInfo
            Set-Status "Standard Test: Gaming readiness..." 49
            $Global:DiagResults.Gaming = Get-GamingReadiness
            Set-Status "Standard Test: Boot performance..." 51
            $Global:DiagResults.BootPerf = Get-BootPerformance
            Set-Status "Standard Test: Windows 11 readiness..." 53
            $Global:DiagResults.Win11Ready = Get-Windows11Readiness
            Set-Status "Standard Test: CPU stress (5 min)..." 55
            $Global:DiagResults.CPUStress = Start-CPUStressTest -DurationSeconds 300
            Set-Status "Standard Test: GPU stress (2 min)..." 70
            $Global:DiagResults.GPUStress = Start-GPUStressTest -DurationSeconds 120
            Set-Status "Standard Test: RAM test (5 min)..." 78
            $Global:DiagResults.RAMStress = Start-RAMStressTest -DurationSeconds 300
            Set-Status "Standard Test: Disk benchmark (512MB)..." 90
            $Global:DiagResults.DiskBench = Start-DiskBenchmark -FileSizeMB 512
            Set-Status "Standard Test: Calculating scores..." 96
            $Global:DiagResults.Scoring = Calculate-Score $Global:DiagResults.Security $Global:DiagResults.Patches
            $Global:DiagResults.StressResults = @{ CPU = $Global:DiagResults.CPUStress; RAM = $Global:DiagResults.RAMStress; Disk = $Global:DiagResults.DiskBench; GPU = $Global:DiagResults.GPUStress }
            $cs = $Global:DiagResults.CPUStress; $rs = $Global:DiagResults.RAMStress; $ds = $Global:DiagResults.DiskBench; $gs = $Global:DiagResults.GPUStress
            Set-Status "DONE! CPU:$(if($cs.Passed){'PASS'}else{'FAIL'}) RAM:$(if($rs.Passed){'PASS'}else{'FAIL'}) GPU:$(if($gs.Passed){'PASS'}else{'FAIL'}) Disk:W=$($ds.SeqWriteMBps)/$($ds.SeqReadMBps)" 100
            Complete-Scan
            [System.Windows.MessageBox]::Show($window, "Standard Test complete!`nCPU: $(if($cs.Passed){'PASS'}else{'FAIL'})`nRAM: $(if($rs.Passed){'PASS'}else{'FAIL'})`nGPU: $(if($gs.Passed){'PASS'}else{'FAIL'})`nDisk: W=$($ds.SeqWriteMBps) / R=$($ds.SeqReadMBps) MB/s`nStability: $($Global:DiagResults.Stability.StabilityRating)`n`nClick a Report button in the sidebar.", "Standard Test Complete", "OK", "Information")
        } catch {
            Write-DebugLog "Standard Test ERROR: $($_.Exception.Message) at line $($_.InvocationInfo.ScriptLineNumber)"
            Set-Status "ERROR: $($_.Exception.Message)" 0
            [System.Windows.MessageBox]::Show($window, "Error during Standard Test:`n`n$($_.Exception.Message)", "Error", "OK", "Error")
        } finally { Set-ScanButtons $true; $lblReadyStatus.Text = "Ready" }
    })

    # ── DEEP TEST (60-90 min) ──
    $window.FindName("btnFull").Add_Click({
        try {
            $p = Get-Params; if (-not $p) { return }
            Set-ScanButtons $false
            $lblReadyStatus.Text = "Running..."
            $Global:DiagResults.ScanMode = "Deep"
            Set-Status "Deep Test: Collecting system info..." 2
            $Global:DiagResults.SystemInfo = Get-FullSystemInfo
            Set-Status "Deep Test: Security scan..." 5
            $Global:DiagResults.Security = Get-FullSecurityInfo
            Set-Status "Deep Test: Network analysis..." 8
            $Global:DiagResults.Network = Get-NetworkDiagnostics
            Set-Status "Deep Test: Network speed test..." 11
            $Global:DiagResults.SpeedTest = Get-NetworkSpeedTest
            Set-Status "Deep Test: Software inventory..." 14
            $Global:DiagResults.Software = Get-SoftwareInventory
            Set-Status "Deep Test: Checking updates..." 17
            $Global:DiagResults.Patches = Get-MissingPatchesList
            Set-Status "Deep Test: Performance snapshot..." 20
            $Global:DiagResults.Performance = Get-PerformanceSnapshot
            Set-Status "Deep Test: License keys..." 22
            $Global:DiagResults.LicenseKeys = Get-LicenseKeys
            Set-Status "Deep Test: Crash history..." 25
            $Global:DiagResults.Stability = Get-CrashStabilityHistory
            Set-Status "Deep Test: Battery report..." 28
            $Global:DiagResults.BatteryDetail = Get-DetailedBatteryInfo
            Set-Status "Deep Test: Power stability..." 30
            $Global:DiagResults.PowerInfo = Get-PowerStabilityInfo
            Set-Status "Deep Test: Gaming readiness..." 32
            $Global:DiagResults.Gaming = Get-GamingReadiness
            Set-Status "Deep Test: Boot performance..." 34
            $Global:DiagResults.BootPerf = Get-BootPerformance
            Set-Status "Deep Test: Windows 11 readiness..." 35
            $Global:DiagResults.Win11Ready = Get-Windows11Readiness
            Set-Status "Deep Test: CPU stress (15 min)..." 37
            $Global:DiagResults.CPUStress = Start-CPUStressTest -DurationSeconds 900
            Set-Status "Deep Test: GPU stress (5 min)..." 56
            $Global:DiagResults.GPUStress = Start-GPUStressTest -DurationSeconds 300
            Set-Status "Deep Test: RAM test (15 min)..." 66
            $Global:DiagResults.RAMStress = Start-RAMStressTest -DurationSeconds 900
            Set-Status "Deep Test: Disk benchmark (1GB)..." 86
            $Global:DiagResults.DiskBench = Start-DiskBenchmark -FileSizeMB 1024
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
            [System.Windows.MessageBox]::Show($window, "Deep Test complete!`nCPU: $(if($cs.Passed){'PASS'}else{'FAIL'})`nRAM: $(if($rs.Passed){'PASS'}else{'FAIL'})`nGPU: $(if($gs.Passed){'PASS'}else{'FAIL'})`nDisk: W=$($ds.SeqWriteMBps) / R=$($ds.SeqReadMBps) MB/s`nStability: $($Global:DiagResults.Stability.StabilityRating)$histMsg`n`nClick a Report button in the sidebar.", "Deep Test Complete", "OK", "Information")
        } catch {
            Write-DebugLog "Deep Test ERROR: $($_.Exception.Message) at line $($_.InvocationInfo.ScriptLineNumber)"
            Set-Status "ERROR: $($_.Exception.Message)" 0
            [System.Windows.MessageBox]::Show($window, "Error during Deep Test:`n`n$($_.Exception.Message)", "Error", "OK", "Error")
        } finally { Set-ScanButtons $true; $lblReadyStatus.Text = "Ready" }
    })

    # ── FULL MRI (90-120 min) ──
    $window.FindName("btnMRI").Add_Click({
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
            Set-Status "MRI Phase 1: Security audit..." 5
            $Global:DiagResults.Security = Get-FullSecurityInfo
            Set-Status "MRI Phase 1: Network diagnostics..." 8
            $Global:DiagResults.Network = Get-NetworkDiagnostics
            Set-Status "MRI Phase 1: Software inventory..." 10
            $Global:DiagResults.Software = Get-SoftwareInventory
            Set-Status "MRI Phase 1: Updates check..." 12
            $Global:DiagResults.Patches = Get-MissingPatchesList
            $Global:DiagResults.Scoring = Calculate-Score $Global:DiagResults.Security $Global:DiagResults.Patches
            Set-Status "MRI Phase 1: License keys..." 14
            $Global:DiagResults.LicenseKeys = Get-LicenseKeys
            Set-Status "MRI Phase 1: Performance snapshot..." 16
            $Global:DiagResults.Performance = Get-PerformanceSnapshot
            Set-Status "MRI Phase 1: Crash & stability history..." 18
            $Global:DiagResults.Stability = Get-CrashStabilityHistory
            Set-Status "MRI Phase 1: Battery report..." 20
            $Global:DiagResults.BatteryDetail = Get-DetailedBatteryInfo
            Set-Status "MRI Phase 1: Power stability..." 21
            $Global:DiagResults.PowerInfo = Get-PowerStabilityInfo
            Set-Status "MRI Phase 1: Gaming readiness..." 22
            $Global:DiagResults.Gaming = Get-GamingReadiness
            Set-Status "MRI Phase 1: Boot performance..." 23
            $Global:DiagResults.BootPerf = Get-BootPerformance
            Set-Status "MRI Phase 1: Windows 11 readiness..." 24
            $Global:DiagResults.Win11Ready = Get-Windows11Readiness
            Set-Status "MRI Phase 1: Fan info..." 25
            $Global:DiagResults.FanInfo = Get-FanInfo
            Set-Status "MRI Phase 1: Display info..." 26
            $Global:DiagResults.DisplayInfo = Get-DisplayInfo
            Set-Status "MRI Phase 1: Windows activation..." 27
            $Global:DiagResults.Activation = Get-WindowsActivation
            Set-Status "MRI Phase 1: Memory leak check..." 28
            $Global:DiagResults.MemoryLeaks = Test-MemoryLeaks
            Set-Status "MRI Phase 1: Thermal snapshot..." 29
            $Global:DiagResults.Thermal = Get-ThermalSnapshot

            Set-Status "MRI Phase 2: SSD/HDD life report..." 30
            $Global:DiagResults.SSDLife = Get-SSDLifeReport
            Set-Status "MRI Phase 2: Disk fragmentation..." 32
            $Global:DiagResults.Fragmentation = Get-DiskFragmentation
            Set-Status "MRI Phase 2: CrystalDiskInfo SMART scan..." 33
            $Global:DiagResults.CrystalDiskInfo = Invoke-CrystalDiskInfoScan
            Set-Status "MRI Phase 2: Wear & Tear lifecycle analysis..." 34
            $Global:DiagResults.WearTear = Invoke-WearAndTearReport

            Set-Status "MRI Phase 3: CPU stress test (2 min)..." 36
            $Global:DiagResults.CPUStress = Start-CPUStressTest -DurationSeconds 120
            Set-Status "MRI Phase 3: RAM stress test (2 min)..." 50
            $Global:DiagResults.RAMStress = Start-RAMStressTest -DurationSeconds 120
            Set-Status "MRI Phase 3: Disk benchmark (512 MB)..." 64
            $Global:DiagResults.DiskBench = Start-DiskBenchmark -FileSizeMB 512
            Set-Status "MRI Phase 3: GPU stress test (90 sec)..." 70
            $Global:DiagResults.GPUStress = Start-GPUStressTest -DurationSeconds 90
            $Global:DiagResults.StressResults = @{ CPU=$Global:DiagResults.CPUStress; RAM=$Global:DiagResults.RAMStress; Disk=$Global:DiagResults.DiskBench; GPU=$Global:DiagResults.GPUStress }

            Set-Status "MRI Phase 4: Deep Windows integrity (SFC, DISM, services)..." 78
            $Global:DiagResults.WindowsDeep = Invoke-DeepWindowsTest
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
    })

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
            Set-Status "Hardware Report: $(if($hwPDF){"PDF saved"}else{"HTML saved (no PDF browser)"}) to reports folder" 40
        }
        if ($DoSec) {
            Set-Status "Generating Security Report..." 70
            $secHTML = Build-SecurityReport $p $Global:DiagResults.SystemInfo $Global:DiagResults.Security $Global:DiagResults.Patches $Global:DiagResults.Scoring
            $secHTMLPath = Join-Path $p.OutputFolder "$safeName - $safeDev - Security Report $ds.html"
            $secPDFPath = Join-Path $p.OutputFolder "$safeName - $safeDev - Security Report $ds.pdf"
            [IO.File]::WriteAllText($secHTMLPath, $secHTML, [Text.Encoding]::UTF8)
            $secPDF = Convert-ToPDF $secHTMLPath $secPDFPath
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
        Set-Status "Gaming PC Report: $(if($pdfOK){'PDF saved'}else{'HTML saved'}) to reports folder" 100
        Start-Process explorer.exe -ArgumentList $p.OutputFolder
        [System.Windows.MessageBox]::Show($window, "Gaming PC Report saved!`n`nIncludes visual charts for:`n- Temperature bars (CPU/GPU)`n- Storage read/write speed bars`n- Network speed gauge`n- Component health donuts`n- RAM usage and fan speeds`n`nPrint-ready format with full branding.", "Gaming Report Ready", "OK", "Information")
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

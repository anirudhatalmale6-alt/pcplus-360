using System.Diagnostics;
using System.IO;
using System.Text.Json;
using System.Windows;
using System.Windows.Input;
using Microsoft.Web.WebView2.Core;
using PCPlus360Launcher.Models;
using PCPlus360Launcher.Services;

namespace PCPlus360Launcher;

public partial class MainWindow : Window
{
    private readonly PowerShellRunner _psRunner = new();
    private readonly SafeRepairEngine _repairEngine = new();

    public MainWindow()
    {
        InitializeComponent();
        Loaded += MainWindow_Loaded;
    }

    private async void MainWindow_Loaded(object sender, RoutedEventArgs e)
    {
        await InitializeWebView();
    }

    private async Task InitializeWebView()
    {
        try
        {
            var userDataFolder = Path.Combine(Path.GetTempPath(), "PCPlus360");
            var env = await CoreWebView2Environment.CreateAsync(null, userDataFolder);
            await WebView.EnsureCoreWebView2Async(env);

            WebView.CoreWebView2.Settings.IsStatusBarEnabled = false;
            WebView.CoreWebView2.Settings.AreDefaultContextMenusEnabled = false;
            WebView.CoreWebView2.Settings.IsZoomControlEnabled = false;
            WebView.CoreWebView2.Settings.AreDevToolsEnabled =
#if DEBUG
                true;
#else
                false;
#endif

            WebView.CoreWebView2.WebMessageReceived += CoreWebView2_WebMessageReceived;

            var dashboardPath = ResolveDashboardPath();
            if (dashboardPath != null)
            {
                WebView.CoreWebView2.Navigate(new Uri(dashboardPath).AbsoluteUri);
            }
            else
            {
                await SendToJs("error", new { message = "Dashboard HTML file not found." });
            }
        }
        catch (WebView2RuntimeNotFoundException)
        {
            WebView.Visibility = Visibility.Collapsed;
            FallbackPanel.Visibility = Visibility.Visible;
        }
        catch (Exception ex)
        {
            MessageBox.Show(
                $"Failed to initialize WebView2:\n\n{ex.Message}",
                "PC Plus 360",
                MessageBoxButton.OK,
                MessageBoxImage.Error);
        }
    }

    private static string? ResolveDashboardPath()
    {
        var baseDir = AppDomain.CurrentDomain.BaseDirectory;

        // Try relative path: ../PCPlus360-Dashboard.html from the exe location
        var candidates = new[]
        {
            Path.GetFullPath(Path.Combine(baseDir, "..", "PCPlus360-Dashboard.html")),
            Path.GetFullPath(Path.Combine(baseDir, "..", "..", "PCPlus360-Dashboard.html")),
            Path.GetFullPath(Path.Combine(baseDir, "PCPlus360-Dashboard.html")),
        };

        return candidates.FirstOrDefault(File.Exists);
    }

    private async void CoreWebView2_WebMessageReceived(object? sender, CoreWebView2WebMessageReceivedEventArgs e)
    {
        try
        {
            // postMessage(JSON.stringify({...})) arrives as a string via TryGetWebMessageAsString
            // postMessage({...}) arrives as JSON via WebMessageAsJson
            string raw;
            try
            {
                raw = e.TryGetWebMessageAsString();
            }
            catch
            {
                raw = e.WebMessageAsJson;
            }

            using var doc = JsonDocument.Parse(raw);
            var root = doc.RootElement;

            var action = root.GetProperty("action").GetString();

            switch (action)
            {
                case "minimize":
                    WindowState = WindowState.Minimized;
                    break;

                case "maximize":
                    WindowState = WindowState == WindowState.Maximized
                        ? WindowState.Normal
                        : WindowState.Maximized;
                    break;

                case "close":
                    Close();
                    break;

                case "launchScript":
                    HandleLaunchScript(root);
                    break;

                case "runScript":
                    await HandleRunScript(root);
                    break;

                case "getSystemInfo":
                    await HandleGetSystemInfo();
                    break;

                case "createRestorePoint":
                    await HandleCreateRestorePoint(root);
                    break;

                case "getRestorePoints":
                    await HandleGetRestorePoints();
                    break;

                case "executeRepair":
                    await HandleExecuteRepair(root);
                    break;

                case "rollback":
                    await HandleRollback();
                    break;

                default:
                    await SendToJs("error", new { message = $"Unknown action: {action}" });
                    break;
            }
        }
        catch (Exception ex)
        {
            await SendToJs("error", new { message = ex.Message });
        }
    }

    private void HandleLaunchScript(JsonElement root)
    {
        var script = root.GetProperty("script").GetString()!;

        var baseDir = AppDomain.CurrentDomain.BaseDirectory;
        var candidates = new[]
        {
            Path.GetFullPath(Path.Combine(baseDir, "..", script)),
            Path.GetFullPath(Path.Combine(baseDir, "..", "..", script)),
            Path.GetFullPath(Path.Combine(baseDir, script)),
        };
        var scriptPath = candidates.FirstOrDefault(File.Exists);

        if (scriptPath == null)
        {
            MessageBox.Show(
                $"{script} not found in toolkit folder.\nMake sure it is in the same directory as PCPlus360-Dashboard.html",
                "Script Not Found", MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }

        var args = $"-NoProfile -ExecutionPolicy Bypass -File \"{scriptPath}\"";

        if (root.TryGetProperty("parameters", out var paramsEl))
        {
            foreach (var prop in paramsEl.EnumerateObject())
            {
                var escaped = (prop.Value.GetString() ?? "").Replace("\"", "`\"");
                args += $" -{prop.Name} \"{escaped}\"";
            }
        }

        try
        {
            Process.Start(new ProcessStartInfo
            {
                FileName = "powershell.exe",
                Arguments = args,
                Verb = "runas",
                UseShellExecute = true
            });
        }
        catch (System.ComponentModel.Win32Exception)
        {
            // User cancelled UAC prompt - that's fine
        }
    }

    private async Task HandleRunScript(JsonElement root)
    {
        var script = root.GetProperty("script").GetString()!;
        var requestId = root.TryGetProperty("requestId", out var rid) ? rid.GetString() : null;

        var parameters = new Dictionary<string, string>();
        if (root.TryGetProperty("parameters", out var paramsEl))
        {
            foreach (var prop in paramsEl.EnumerateObject())
            {
                parameters[prop.Name] = prop.Value.GetString() ?? "";
            }
        }

        var baseDir = AppDomain.CurrentDomain.BaseDirectory;
        var candidates = new[]
        {
            Path.GetFullPath(Path.Combine(baseDir, "..", script)),
            Path.GetFullPath(Path.Combine(baseDir, "..", "..", script)),
            Path.GetFullPath(Path.Combine(baseDir, script)),
        };
        var scriptPath = candidates.FirstOrDefault(File.Exists) ?? Path.Combine(baseDir, "..", script);

        if (!File.Exists(scriptPath))
        {
            await SendToJs("scriptResult", new
            {
                requestId,
                script,
                success = false,
                error = $"Script not found: {script}"
            });
            return;
        }

        await SendToJs("scriptStarted", new { requestId, script });

        try
        {
            var output = await _psRunner.RunScriptAsync(scriptPath, parameters);
            var parsed = ScriptResultParser.Parse(output);

            await SendToJs("scriptResult", new
            {
                requestId,
                script,
                success = true,
                data = parsed
            });
        }
        catch (OperationCanceledException)
        {
            await SendToJs("scriptResult", new
            {
                requestId,
                script,
                success = false,
                error = "Script execution was cancelled."
            });
        }
        catch (Exception ex)
        {
            await SendToJs("scriptResult", new
            {
                requestId,
                script,
                success = false,
                error = ex.Message
            });
        }
    }

    private async Task HandleGetSystemInfo()
    {
        try
        {
            var info = await SystemInfo.GatherAsync();
            var primaryDrive = info.Drives.FirstOrDefault();
            var storageText = primaryDrive != null
                ? $"{primaryDrive.TotalSizeGb:F0} GB ({primaryDrive.FileSystem})"
                : "Unknown";
            var uptimeText = info.UptimeHours >= 24
                ? $"{(int)(info.UptimeHours / 24)} Days, {(int)(info.UptimeHours % 24)} Hours"
                : $"{info.UptimeHours:F1} Hours";

            await SendToJs("systemInfo", new
            {
                deviceName = info.ComputerName,
                os = info.OsVersion,
                processor = !string.IsNullOrEmpty(info.ProcessorName) ? info.ProcessorName : $"{info.ProcessorCount} cores ({info.Architecture})",
                memory = $"{info.TotalMemoryMb / 1024} GB",
                storage = storageText,
                uptime = uptimeText
            });
        }
        catch (Exception ex)
        {
            await SendToJs("error", new { message = $"Failed to gather system info: {ex.Message}" });
        }
    }

    private async Task HandleCreateRestorePoint(JsonElement root)
    {
        var description = root.TryGetProperty("description", out var desc)
            ? desc.GetString() ?? "PC Plus 360 Restore Point"
            : "PC Plus 360 Restore Point";

        var result = await _repairEngine.CreateRestorePointAsync(description);
        await SendToJs("restorePointResult", new { success = result });
    }

    private async Task HandleGetRestorePoints()
    {
        var points = await _repairEngine.GetRestorePointsAsync();
        await SendToJs("restorePoints", new { points });
    }

    private async Task HandleExecuteRepair(JsonElement root)
    {
        var action = new RepairAction
        {
            Id = root.TryGetProperty("id", out var id) ? id.GetString() ?? "" : Guid.NewGuid().ToString(),
            Name = root.GetProperty("name").GetString() ?? "",
            Script = root.TryGetProperty("script", out var s) ? s.GetString() ?? "" : "",
            DryRun = root.TryGetProperty("dryRun", out var dr) && dr.GetBoolean()
        };

        var result = await _repairEngine.ExecuteRepairAsync(action, _psRunner);
        await SendToJs("repairResult", result);
    }

    private async Task HandleRollback()
    {
        var result = await _repairEngine.RollbackLastRepairAsync();
        await SendToJs("rollbackResult", new { success = result });
    }

    private async Task SendToJs(string type, object data)
    {
        var payload = JsonSerializer.Serialize(new { type, data },
            new JsonSerializerOptions { PropertyNamingPolicy = JsonNamingPolicy.CamelCase });
        await WebView.CoreWebView2.ExecuteScriptAsync(
            $"window.dispatchEvent(new MessageEvent('message', {{ data: {payload} }}))");
    }

    // Window chrome handlers
    private void TitleBar_MouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        if (e.ClickCount == 2)
        {
            WindowState = WindowState == WindowState.Maximized
                ? WindowState.Normal
                : WindowState.Maximized;
        }
        else
        {
            DragMove();
        }
    }

    private void MinBtn_Click(object sender, RoutedEventArgs e) => WindowState = WindowState.Minimized;

    private void MaxBtn_Click(object sender, RoutedEventArgs e) =>
        WindowState = WindowState == WindowState.Maximized ? WindowState.Normal : WindowState.Maximized;

    private void CloseBtn_Click(object sender, RoutedEventArgs e) => Close();

    private void DownloadLink_Click(object sender, MouseButtonEventArgs e)
    {
        Process.Start(new ProcessStartInfo
        {
            FileName = "https://developer.microsoft.com/en-us/microsoft-edge/webview2/",
            UseShellExecute = true
        });
    }
}

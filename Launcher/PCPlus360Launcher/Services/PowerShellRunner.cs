using System.Collections.Concurrent;
using System.Diagnostics;
using System.IO;

namespace PCPlus360Launcher.Services;

public class PowerShellRunner
{
    private readonly ConcurrentDictionary<string, CancellationTokenSource> _running = new();
    private static readonly TimeSpan DefaultTimeout = TimeSpan.FromMinutes(5);

    public async Task<string> RunScriptAsync(
        string scriptPath,
        Dictionary<string, string>? parameters = null,
        CancellationToken cancellation = default)
    {
        var scriptKey = Path.GetFileName(scriptPath);

        if (_running.ContainsKey(scriptKey))
            throw new InvalidOperationException($"Script '{scriptKey}' is already running.");

        using var linkedCts = CancellationTokenSource.CreateLinkedTokenSource(cancellation);
        linkedCts.CancelAfter(DefaultTimeout);

        if (!_running.TryAdd(scriptKey, linkedCts))
            throw new InvalidOperationException($"Script '{scriptKey}' is already running.");

        try
        {
            var args = BuildArguments(scriptPath, parameters);

            using var process = new Process
            {
                StartInfo = new ProcessStartInfo
                {
                    FileName = "powershell.exe",
                    Arguments = args,
                    UseShellExecute = false,
                    RedirectStandardOutput = true,
                    RedirectStandardError = true,
                    CreateNoWindow = true,
                    WorkingDirectory = Path.GetDirectoryName(scriptPath) ?? ""
                },
                EnableRaisingEvents = true
            };

            var tcs = new TaskCompletionSource<int>();
            process.Exited += (_, _) => tcs.TrySetResult(process.ExitCode);

            process.Start();

            await using var reg = linkedCts.Token.Register(() =>
            {
                try { process.Kill(true); } catch { }
                tcs.TrySetCanceled();
            });

            var stdout = await process.StandardOutput.ReadToEndAsync(linkedCts.Token);
            var stderr = await process.StandardError.ReadToEndAsync(linkedCts.Token);
            var exitCode = await tcs.Task;

            if (exitCode != 0 && !string.IsNullOrWhiteSpace(stderr))
                throw new Exception($"PowerShell exited with code {exitCode}: {stderr.Trim()}");

            return stdout;
        }
        finally
        {
            _running.TryRemove(scriptKey, out _);
        }
    }

    public bool CancelScript(string scriptName)
    {
        if (_running.TryRemove(scriptName, out var cts))
        {
            cts.Cancel();
            return true;
        }
        return false;
    }

    public IReadOnlyList<string> GetRunningScripts() => _running.Keys.ToList();

    private static string BuildArguments(string scriptPath, Dictionary<string, string>? parameters)
    {
        var args = $"-NoProfile -NonInteractive -ExecutionPolicy Bypass -File \"{scriptPath}\"";

        if (parameters is { Count: > 0 })
        {
            foreach (var (key, value) in parameters)
            {
                var escaped = value.Replace("\"", "`\"");
                args += $" -{key} \"{escaped}\"";
            }
        }

        args += " -JsonOutput";
        return args;
    }
}

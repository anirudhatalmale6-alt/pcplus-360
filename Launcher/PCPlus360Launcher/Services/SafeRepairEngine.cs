using System.IO;
using System.Text.Json;
using PCPlus360Launcher.Models;

namespace PCPlus360Launcher.Services;

public class SafeRepairEngine
{
    private readonly List<RepairAction> _history = [];

    public async Task<bool> CreateRestorePointAsync(string description)
    {
        var runner = new PowerShellRunner();
        try
        {
            var script = BuildInlineScript(
                $"Checkpoint-Computer -Description '{EscapeSingleQuote(description)}' -RestorePointType 'MODIFY_SETTINGS'");
            await runner.RunScriptAsync(script);
            return true;
        }
        catch
        {
            return false;
        }
    }

    public async Task<List<RestorePointInfo>> GetRestorePointsAsync()
    {
        var runner = new PowerShellRunner();
        try
        {
            var script = BuildInlineScript(
                "Get-ComputerRestorePoint | Select-Object SequenceNumber, Description, CreationTime | ConvertTo-Json -Compress");
            var output = await runner.RunScriptAsync(script);
            var trimmed = output.Trim();

            if (string.IsNullOrEmpty(trimmed))
                return [];

            // Handle single object vs array
            if (trimmed.StartsWith('['))
            {
                return JsonSerializer.Deserialize<List<RestorePointInfo>>(trimmed,
                    new JsonSerializerOptions { PropertyNameCaseInsensitive = true }) ?? [];
            }

            var single = JsonSerializer.Deserialize<RestorePointInfo>(trimmed,
                new JsonSerializerOptions { PropertyNameCaseInsensitive = true });
            return single != null ? [single] : [];
        }
        catch
        {
            return [];
        }
    }

    public async Task<RepairResult> ExecuteRepairAsync(RepairAction action, PowerShellRunner runner)
    {
        var result = new RepairResult { ActionId = action.Id, ActionName = action.Name };

        if (action.DryRun)
        {
            result.Success = true;
            result.IsDryRun = true;
            result.Message = $"[DRY RUN] Would execute: {action.Name}";
            return result;
        }

        // Create restore point before repair
        var restoreCreated = await CreateRestorePointAsync($"Before: {action.Name}");
        result.RestorePointCreated = restoreCreated;

        if (string.IsNullOrEmpty(action.Script))
        {
            result.Success = false;
            result.Message = "No repair script specified.";
            return result;
        }

        try
        {
            var output = await runner.RunScriptAsync(action.Script, action.Parameters);
            result.Success = true;
            result.Message = "Repair completed successfully.";
            result.Output = ScriptResultParser.Parse(output);

            action.ExecutedAt = DateTime.Now;
            action.RestorePointCreated = restoreCreated;
            _history.Add(action);
        }
        catch (Exception ex)
        {
            result.Success = false;
            result.Message = $"Repair failed: {ex.Message}";
        }

        return result;
    }

    public async Task<bool> RollbackLastRepairAsync()
    {
        if (_history.Count == 0)
            return false;

        var last = _history[^1];
        if (!last.RestorePointCreated)
            return false;

        var runner = new PowerShellRunner();
        try
        {
            var points = await GetRestorePointsAsync();
            if (points.Count == 0)
                return false;

            var latest = points[^1];
            var script = BuildInlineScript(
                $"Restore-Computer -RestorePoint {latest.SequenceNumber} -Confirm:$false");
            await runner.RunScriptAsync(script);

            _history.RemoveAt(_history.Count - 1);
            return true;
        }
        catch
        {
            return false;
        }
    }

    public IReadOnlyList<RepairAction> GetRepairHistory() => _history.AsReadOnly();

    private static string BuildInlineScript(string command)
    {
        var tempScript = Path.Combine(Path.GetTempPath(), $"pcplus360_{Guid.NewGuid():N}.ps1");
        File.WriteAllText(tempScript, command);
        return tempScript;
    }

    private static string EscapeSingleQuote(string value) => value.Replace("'", "''");
}

public class RestorePointInfo
{
    public int SequenceNumber { get; set; }
    public string Description { get; set; } = "";
    public string CreationTime { get; set; } = "";
}

public class RepairResult
{
    public string ActionId { get; set; } = "";
    public string ActionName { get; set; } = "";
    public bool Success { get; set; }
    public bool IsDryRun { get; set; }
    public bool RestorePointCreated { get; set; }
    public string Message { get; set; } = "";
    public object? Output { get; set; }
}

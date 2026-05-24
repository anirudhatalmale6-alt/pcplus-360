namespace PCPlus360Launcher.Models;

public class RepairAction
{
    public string Id { get; set; } = "";
    public string Name { get; set; } = "";
    public string Description { get; set; } = "";
    public string Script { get; set; } = "";
    public string Category { get; set; } = "";
    public bool DryRun { get; set; }
    public bool RequiresAdmin { get; set; }
    public Dictionary<string, string>? Parameters { get; set; }
    public DateTime? ExecutedAt { get; set; }
    public bool RestorePointCreated { get; set; }
}

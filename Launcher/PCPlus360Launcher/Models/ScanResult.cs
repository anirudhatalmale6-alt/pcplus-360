namespace PCPlus360Launcher.Models;

public class ScanResult
{
    public string Category { get; set; } = "";
    public string Status { get; set; } = "";
    public string Message { get; set; } = "";
    public string Severity { get; set; } = "info";
    public string? Details { get; set; }
    public DateTime Timestamp { get; set; } = DateTime.Now;
}

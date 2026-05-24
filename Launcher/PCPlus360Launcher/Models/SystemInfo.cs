using System.Diagnostics;
using System.IO;
using System.Management;
using System.Runtime.InteropServices;

namespace PCPlus360Launcher.Models;

public class SystemInfo
{
    public string ComputerName { get; set; } = "";
    public string UserName { get; set; } = "";
    public string OsVersion { get; set; } = "";
    public string OsBuild { get; set; } = "";
    public string Architecture { get; set; } = "";
    public string ProcessorName { get; set; } = "";
    public long TotalMemoryMb { get; set; }
    public long AvailableMemoryMb { get; set; }
    public int ProcessorCount { get; set; }
    public string DotNetVersion { get; set; } = "";
    public double UptimeHours { get; set; }
    public List<DriveInfoModel> Drives { get; set; } = [];

    public static async Task<SystemInfo> GatherAsync()
    {
        return await Task.Run(() =>
        {
            var info = new SystemInfo
            {
                ComputerName = Environment.MachineName,
                UserName = Environment.UserName,
                OsVersion = RuntimeInformation.OSDescription,
                OsBuild = Environment.OSVersion.Version.ToString(),
                Architecture = RuntimeInformation.OSArchitecture.ToString(),
                ProcessorCount = Environment.ProcessorCount,
                DotNetVersion = RuntimeInformation.FrameworkDescription,
                UptimeHours = Math.Round(Environment.TickCount64 / 3_600_000.0, 1)
            };

            // Processor name via WMI
            try
            {
                using var searcher = new ManagementObjectSearcher("SELECT Name FROM Win32_Processor");
                foreach (var obj in searcher.Get())
                {
                    info.ProcessorName = obj["Name"]?.ToString()?.Trim() ?? "";
                    break;
                }
            }
            catch { info.ProcessorName = $"{info.ProcessorCount} cores ({info.Architecture})"; }

            // Memory via WMI for accuracy
            try
            {
                using var searcher = new ManagementObjectSearcher("SELECT TotalPhysicalMemory FROM Win32_ComputerSystem");
                foreach (var obj in searcher.Get())
                {
                    var totalBytes = Convert.ToInt64(obj["TotalPhysicalMemory"]);
                    info.TotalMemoryMb = totalBytes / (1024 * 1024);
                    break;
                }
                info.AvailableMemoryMb = info.TotalMemoryMb - (Process.GetCurrentProcess().WorkingSet64 / (1024 * 1024));
            }
            catch
            {
                var gcInfo = GC.GetGCMemoryInfo();
                info.TotalMemoryMb = gcInfo.TotalAvailableMemoryBytes / (1024 * 1024);
                info.AvailableMemoryMb = info.TotalMemoryMb - (Process.GetCurrentProcess().WorkingSet64 / (1024 * 1024));
            }

            // Drive info
            foreach (var drive in DriveInfo.GetDrives())
            {
                if (!drive.IsReady) continue;
                info.Drives.Add(new DriveInfoModel
                {
                    Name = drive.Name,
                    Label = drive.VolumeLabel,
                    DriveType = drive.DriveType.ToString(),
                    FileSystem = drive.DriveFormat,
                    TotalSizeGb = Math.Round(drive.TotalSize / 1_073_741_824.0, 1),
                    FreeSpaceGb = Math.Round(drive.AvailableFreeSpace / 1_073_741_824.0, 1),
                    UsedPercent = Math.Round((1 - (double)drive.AvailableFreeSpace / drive.TotalSize) * 100, 1)
                });
            }

            return info;
        });
    }
}

public class DriveInfoModel
{
    public string Name { get; set; } = "";
    public string Label { get; set; } = "";
    public string DriveType { get; set; } = "";
    public string FileSystem { get; set; } = "";
    public double TotalSizeGb { get; set; }
    public double FreeSpaceGb { get; set; }
    public double UsedPercent { get; set; }
}

using System.Diagnostics;
using System.Runtime.InteropServices;

namespace MixlitAudioService.Services;

public class ProcessDiscoveryService
{
    private readonly ILogger<ProcessDiscoveryService> _logger;

    // P/Invoke declarations for checking if a process has a window
    [DllImport("user32.dll")]
    private static extern bool IsWindowVisible(IntPtr hWnd);

    [DllImport("user32.dll")]
    private static extern IntPtr GetShellWindow();

    public ProcessDiscoveryService(ILogger<ProcessDiscoveryService> logger)
    {
        _logger = logger;
    }

    public List<ProcessInfo> GetRunningApplications()
    {
        var applications = new List<ProcessInfo>();
        var shellWindow = GetShellWindow();

        try
        {
            var processes = Process.GetProcesses()
                .Where(p => HasMainWindow(p, shellWindow))
                .OrderBy(p => p.ProcessName)
                .ToList();

            foreach (var process in processes)
            {
                try
                {
                    var processInfo = new ProcessInfo
                    {
                        ProcessId = process.Id,
                        ProcessName = process.ProcessName + ".exe",
                        ProcessPath = process.MainModule?.FileName ?? string.Empty,
                        MainWindowTitle = process.MainWindowTitle
                    };

                    // Only add if we have a valid path
                    if (!string.IsNullOrEmpty(processInfo.ProcessPath))
                    {
                        applications.Add(processInfo);
                    }
                }
                catch (Exception ex)
                {
                    // Skip processes we can't access (usually system processes)
                    _logger.LogDebug("Skipping process {ProcessName}: {Error}",
                        process.ProcessName, ex.Message);
                }
            }

            _logger.LogDebug("Found {Count} running applications", applications.Count);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting running applications");
        }

        return applications;
    }

    private bool HasMainWindow(Process process, IntPtr shellWindow)
    {
        try
        {
            if (process.MainWindowHandle == IntPtr.Zero)
                return false;

            if (process.MainWindowHandle == shellWindow)
                return false;

            return IsWindowVisible(process.MainWindowHandle);
        }
        catch
        {
            return false;
        }
    }
}

public class ProcessInfo
{
    public int ProcessId { get; set; }
    public string ProcessName { get; set; } = string.Empty;
    public string ProcessPath { get; set; } = string.Empty;
    public string MainWindowTitle { get; set; } = string.Empty;
}
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
>
    public List<ProcessInfo> GetRunningApplications()
    {
        var applications = new List<ProcessInfo>();
        var shellWindow = GetShellWindow();

        try
        {
            var processes = Process.GetProcesses()
                .Where(p => !string.IsNullOrEmpty(p.ProcessName))
                .OrderBy(p => p.ProcessName)
                .ToList();

            foreach (var process in processes)
            {
                try
                {
                    string processPath;

                    try
                    {
                        processPath = process.MainModule?.FileName ?? string.Empty;
                    }
                    catch
                    {
                        continue;
                    }

                    if (string.IsNullOrEmpty(processPath))
                        continue;

                    var processName = process.ProcessName + ".exe";
                    var hasWindow = HasMainWindow(process, shellWindow);
                    var isLikelyGame = IsLikelyGameProcess(processName);

                    if (!hasWindow && !isLikelyGame)
                        continue;

                    applications.Add(new ProcessInfo
                    {
                        ProcessId = process.Id,
                        ProcessName = processName,
                        ProcessPath = processPath,
                        MainWindowTitle = process.MainWindowTitle ?? string.Empty
                    });
                }
                catch (Exception ex)
                {
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

    private bool IsLikelyGameProcess(string processName)
    {
        var gamePatterns = new[] { "win64", "win32", "game", "launcher", "client", "ship", "dx11", "dx12" };
        return gamePatterns.Any(p => processName.ToLowerInvariant().Contains(p));
    }

    private bool HasMainWindow(Process process, IntPtr shellWindow)
    {
        try
        {
            if (process.MainWindowHandle == IntPtr.Zero) return false;
            if (process.MainWindowHandle == shellWindow) return false;
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
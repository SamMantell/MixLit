using System.Runtime.InteropServices;

namespace MixlitAudioService.Services
{
    public class ActiveWindowService
    {
        private readonly ILogger<ActiveWindowService> _logger;

        [DllImport("user32.dll")]
        private static extern IntPtr GetForegroundWindow();

        [DllImport("user32.dll")]
        private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);

        public ActiveWindowService(ILogger<ActiveWindowService> logger)
        {
            _logger = logger;
        }

        public string? GetActiveWindowProcessName()
        {
            try
            {
                IntPtr hWnd = GetForegroundWindow();
                if (hWnd == IntPtr.Zero)
                {
                    _logger.LogWarning("No active window found.");
                    return null;
                }
                GetWindowThreadProcessId(hWnd, out uint processId);
                var process = System.Diagnostics.Process.GetProcessById((int)processId);
                return process.ProcessName;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error getting active window process name.");
                return null;
            }
        }

        public (string? ProcessName, int ProcessID) GetActiveWindowProcessInfo()
        {
            try
            {
                IntPtr hWnd = GetForegroundWindow();
                if (hWnd == IntPtr.Zero)
                {
                    _logger.LogWarning("No active window found.");
                    return (null, 0);
                }
                GetWindowThreadProcessId(hWnd, out uint processId);
                var process = System.Diagnostics.Process.GetProcessById((int)processId);
                return (process.ProcessName, process.Id);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error getting active window process info.");
                return (null, 0);
            }
        }

    }
}

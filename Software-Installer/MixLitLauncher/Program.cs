using System;
using System.Diagnostics;
using System.Net.Http;
using System.Threading;
using System.Threading.Tasks;
using System.Linq;
using System.IO;

namespace MixLitLauncher;

class Program
{
    private static readonly string AppDirectory = AppDomain.CurrentDomain.BaseDirectory;
    private static readonly string ServiceExe = Path.Combine(AppDirectory, "AudioService", "MixlitAudioService.exe");
    private static readonly string FlutterExe = Path.Combine(AppDirectory, "MixLit.exe");
    private static readonly string ServiceUrl = "http://localhost:8765";
    private static Process? serviceProcess;
    private static readonly HttpClient httpClient = new();

    static async Task<int> Main(string[] args)
    {
        //if launched with --auto-start (Windows startup)
        var isAutoStart = args.Contains("--auto-start");

        if (!isAutoStart)
        {
            Console.WriteLine("MixLit Launcher starting...");
        }

        try
        {
            if (!File.Exists(ServiceExe))
            {
                if (!isAutoStart)
                {
                    Console.WriteLine($"ERROR: Audio service not found at: {ServiceExe}");
                    Console.WriteLine("Press any key to exit...");
                    Console.ReadKey();
                }
                return 1;
            }

            if (!File.Exists(FlutterExe))
            {
                if (!isAutoStart)
                {
                    Console.WriteLine($"ERROR: MixLit application not found at: {FlutterExe}");
                    Console.WriteLine("Press any key to exit...");
                    Console.ReadKey();
                }
                return 1;
            }

            if (!await StartAudioService())
            {
                if (!isAutoStart)
                {
                    Console.WriteLine("WARNING: Audio service may not have started correctly");
                }
            }

            if (!isAutoStart)
            {
                Console.WriteLine("Launching MixLit application...");
            }

            var startInfo = new ProcessStartInfo
            {
                FileName = FlutterExe,
                WorkingDirectory = AppDirectory,
                UseShellExecute = false
            };

            if (isAutoStart)
            {
                startInfo.Arguments = "--auto-start";
            }

            var flutterProcess = new Process { StartInfo = startInfo };
            flutterProcess.Start();

            if (!isAutoStart)
            {
                Console.WriteLine("MixLit is running...");
            }

            await flutterProcess.WaitForExitAsync();

            if (!isAutoStart)
            {
                Console.WriteLine("MixLit closed. Cleaning up...");
            }

            StopAudioService();

            if (!isAutoStart)
            {
                Console.WriteLine("Shutdown complete");
            }
            return 0;
        }
        catch (Exception ex)
        {
            if (!isAutoStart)
            {
                Console.WriteLine($"ERROR: {ex.Message}");
                Console.WriteLine("Press any key to exit...");
                Console.ReadKey();
            }
            StopAudioService();
            return 1;
        }
    }

    private static async Task<bool> StartAudioService()
    {
        if (await IsServiceHealthy())
        {
            return true;
        }

        serviceProcess = new Process
        {
            StartInfo = new ProcessStartInfo
            {
                FileName = ServiceExe,
                WorkingDirectory = Path.GetDirectoryName(ServiceExe)!,
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardOutput = false,
                RedirectStandardError = false
            }
        };

        serviceProcess.Start();

        var maxRetries = 15;
        for (int i = 0; i < maxRetries; i++)
        {
            await Task.Delay(1000);

            if (await IsServiceHealthy())
            {
                return true;
            }
        }

        return false;
    }

    private static async Task<bool> IsServiceHealthy()
    {
        try
        {
            httpClient.Timeout = TimeSpan.FromSeconds(2);
            var response = await httpClient.GetAsync($"{ServiceUrl}/health");
            return response.IsSuccessStatusCode;
        }
        catch
        {
            return false;
        }
    }

    private static void StopAudioService()
    {
        try
        {
            if (serviceProcess != null && !serviceProcess.HasExited)
            {
                serviceProcess.Kill(true);
                serviceProcess.WaitForExit(5000);
            }

            var processes = Process.GetProcessesByName("MixlitAudioService");
            foreach (var process in processes)
            {
                try
                {
                    process.Kill(true);
                }
                catch { }
            }

            Thread.Sleep(1000);
        }
        catch (Exception){}
    }
}
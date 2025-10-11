using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

namespace MixlitAudioService.Services;

public class IconExtractionService
{
    private readonly ILogger<IconExtractionService> _logger;
    private readonly string _cacheDirectory;
    private readonly Dictionary<string, string> _iconCache = new();

    [DllImport("shell32.dll", CharSet = CharSet.Auto)]
    private static extern IntPtr ExtractIcon(IntPtr hInst, string lpszExeFileName, int nIconIndex);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool DestroyIcon(IntPtr hIcon);

    public IconExtractionService(ILogger<IconExtractionService> logger)
    {
        _logger = logger;
        _cacheDirectory = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
            "MixlitAudioService",
            "IconCache"
        );

        Directory.CreateDirectory(_cacheDirectory);
    }

    public async Task<string?> GetIconBase64Async(string executablePath)
    {
        if (string.IsNullOrEmpty(executablePath) || !File.Exists(executablePath))
        {
            return null;
        }

        var processName = Path.GetFileNameWithoutExtension(executablePath);

        if (_iconCache.TryGetValue(processName, out var cachedBase64))
        {
            return cachedBase64;
        }

        try
        {
            var iconBytes = await ExtractIconBytesAsync(executablePath);
            if (iconBytes == null || iconBytes.Length == 0)
            {
                return null;
            }

            var base64 = Convert.ToBase64String(iconBytes);
            _iconCache[processName] = base64;

            return base64;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to extract icon for {Path}", executablePath);
            return null;
        }
    }

    private async Task<byte[]?> ExtractIconBytesAsync(string executablePath)
    {
        return await Task.Run(() =>
        {
            IntPtr hIcon = IntPtr.Zero;

            try
            {
                hIcon = ExtractIcon(IntPtr.Zero, executablePath, 0);

                if (hIcon == IntPtr.Zero || hIcon.ToInt32() == 1)
                {
                    return null;
                }

                using var icon = Icon.FromHandle(hIcon);
                using var bitmap = icon.ToBitmap();
                using var ms = new MemoryStream();

                bitmap.Save(ms, ImageFormat.Png);
                return ms.ToArray();
            }
            finally
            {
                if (hIcon != IntPtr.Zero && hIcon.ToInt32() != 1)
                {
                    DestroyIcon(hIcon);
                }
            }
        });
    }

    public void ClearCache()
    {
        _iconCache.Clear();

        try
        {
            if (Directory.Exists(_cacheDirectory))
            {
                Directory.Delete(_cacheDirectory, true);
                Directory.CreateDirectory(_cacheDirectory);
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to clear icon cache");
        }
    }
}
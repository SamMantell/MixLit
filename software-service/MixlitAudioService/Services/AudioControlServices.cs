using MixlitAudioService.Models;
using NAudio.CoreAudioApi;
using NAudio.CoreAudioApi.Interfaces;
using System.Collections.Concurrent;
using System.Diagnostics;

namespace MixlitAudioService.Services;

public class AudioControlService : IDisposable
{
    private readonly MMDeviceEnumerator _deviceEnumerator;
    private MMDevice? _defaultDevice;
    private readonly ConcurrentDictionary<string, List<AudioSessionControl>> _sessionCache;
    private readonly SemaphoreSlim _cacheLock = new(1, 1);
    private DateTime _lastCacheUpdate = DateTime.MinValue;
    private static readonly TimeSpan CacheDuration = TimeSpan.FromSeconds(2);

    private readonly ILogger<AudioControlService> _logger;
    private readonly ActiveWindowService _activeWindowService;

    public AudioControlService(ILogger<AudioControlService> logger, ActiveWindowService activeWindowService)
    {
        _logger = logger;
        _deviceEnumerator = new MMDeviceEnumerator();
        _sessionCache = new ConcurrentDictionary<string, List<AudioSessionControl>>();
        _activeWindowService = activeWindowService;
        InitializeDefaultDevice();
    }

    private void InitializeDefaultDevice()
    {
        try
        {
            _defaultDevice = _deviceEnumerator.GetDefaultAudioEndpoint(DataFlow.Render, Role.Multimedia);
            _logger.LogInformation("Default audio device initialized: {DeviceName}", _defaultDevice.FriendlyName);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to initialize default audio device");
        }
    }

    public async Task<List<AudioSessionInfo>> GetAllAudioSessionsAsync()
    {
        await UpdateSessionCacheAsync();

        var sessions = new List<AudioSessionInfo>();

        foreach (var kvp in _sessionCache)
        {
            foreach (var session in kvp.Value)
            {
                try
                {
                    if (session.State == AudioSessionState.AudioSessionStateActive)
                    {
                        sessions.Add(new AudioSessionInfo
                        {
                            ProcessName = kvp.Key,
                            ProcessPath = GetProcessPath(session),
                            ProcessId = (int)session.GetProcessID,
                            Volume = session.SimpleAudioVolume.Volume,
                            IsMuted = session.SimpleAudioVolume.Mute
                        });
                    }
                }
                catch (Exception ex)
                {
                    _logger.LogWarning(ex, "Error reading session info for {ProcessName}", kvp.Key);
                }
            }
        }

        return sessions;
    }

    public async Task SetAppVolumeAsync(string processName, float volume)
    {
        var normalizedName = NormalizeProcessName(processName);
        await UpdateSessionCacheAsync();

        if (!_sessionCache.TryGetValue(normalizedName, out var sessions))
        {
            _logger.LogWarning("No audio sessions found for process: {ProcessName}", processName);
            return;
        }

        var tasks = sessions
            .Where(s => s.State == AudioSessionState.AudioSessionStateActive)
            .Select(session => Task.Run(() =>
            {
                try
                {
                    session.SimpleAudioVolume.Volume = Math.Clamp(volume, 0f, 1f);
                    _logger.LogDebug("Set volume for {ProcessName} (PID: {Pid}) to {Volume}",
                        processName, session.GetProcessID, volume);
                }
                catch (Exception ex)
                {
                    _logger.LogError(ex, "Failed to set volume for session {ProcessName}", processName);
                }
            }));

        await Task.WhenAll(tasks);
    }

    public async Task SetActiveAppVolumeAsync(float volume)
    {
        var activeProcessName = _activeWindowService.GetActiveWindowProcessName();
        if (string.IsNullOrEmpty(activeProcessName))
        {
            _logger.LogWarning("No active window process found");
            return;
        }
        _logger.LogInformation("Setting volume for active window process: {ProcessName} to {Volume}",
            activeProcessName, volume);
        await SetAppVolumeAsync(activeProcessName, volume);
    }

    public async Task SetGroupVolumeAsync(List<string> processNames, float volume)
    {
        _logger.LogInformation("Setting group volume to {Volume} for {Count} processes",
            volume, processNames.Count);

        var tasks = processNames.Select(processName =>
            SetAppVolumeAsync(processName, volume));

        await Task.WhenAll(tasks);
    }

    public async Task MuteAppAsync(string processName, bool mute)
    {
        var normalizedName = NormalizeProcessName(processName);
        await UpdateSessionCacheAsync();

        if (!_sessionCache.TryGetValue(normalizedName, out var sessions))
        {
            _logger.LogWarning("No audio sessions found for process: {ProcessName}", processName);
            return;
        }

        var tasks = sessions
            .Where(s => s.State == AudioSessionState.AudioSessionStateActive)
            .Select(session => Task.Run(() =>
            {
                try
                {
                    session.SimpleAudioVolume.Mute = mute;
                    _logger.LogDebug("Set mute state for {ProcessName} (PID: {Pid}) to {Mute}",
                        processName, session.GetProcessID, mute);
                }
                catch (Exception ex)
                {
                    _logger.LogError(ex, "Failed to mute session {ProcessName}", processName);
                }
            }));

        await Task.WhenAll(tasks);
    }

    public async Task MuteActiveAppAsync(bool mute)
    {
        var activeProcessName = _activeWindowService.GetActiveWindowProcessName();
        if (string.IsNullOrEmpty(activeProcessName))
        {
            _logger.LogWarning("No active window process found");
            return;
        }
        _logger.LogInformation("Setting mute state for active window process: {ProcessName} to {Mute}",
            activeProcessName, mute);
        await MuteAppAsync(activeProcessName, mute);
    }

    public async Task MuteGroupAsync(List<string> processNames, bool mute)
    {
        var tasks = processNames.Select(processName =>
            MuteAppAsync(processName, mute));

        await Task.WhenAll(tasks);
    }

    public async Task SetMasterVolumeAsync(float volume)
    {
        await Task.Run(() =>
        {
            try
            {
                if (_defaultDevice == null)
                {
                    InitializeDefaultDevice();
                }

                if (_defaultDevice != null)
                {
                    _defaultDevice.AudioEndpointVolume.MasterVolumeLevelScalar = Math.Clamp(volume, 0f, 1f);
                    _logger.LogDebug("Set master volume to {Volume}", volume);
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Failed to set master volume");
                throw;
            }
        });
    }

    public async Task MuteMasterVolumeAsync(bool mute)
    {
        await Task.Run(() =>
        {
            try
            {
                if (_defaultDevice == null)
                {
                    InitializeDefaultDevice();
                }

                if (_defaultDevice != null)
                {
                    _defaultDevice.AudioEndpointVolume.Mute = mute;
                    _logger.LogDebug("Set master mute state to {Mute}", mute);
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Failed to mute master volume");
                throw;
            }
        });
    }

    public float GetMasterVolume()
    {
        try
        {
            if (_defaultDevice == null)
            {
                InitializeDefaultDevice();
            }

            return _defaultDevice?.AudioEndpointVolume.MasterVolumeLevelScalar ?? 0f;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to get master volume");
            return 0f;
        }
    }

    public async Task<AudioSessionInfo?> GetActiveAppSessionAsync()
    {
        var (processName, processId) = _activeWindowService.GetActiveWindowProcessInfo();

        if (string.IsNullOrEmpty(processName))
        {
            return null;
        }

        await UpdateSessionCacheAsync();
        var normalizedName = NormalizeProcessName(processName);

        if (!_sessionCache.TryGetValue(normalizedName, out var sessions))
        {
            _logger.LogWarning("No audio sessions found for active process: {ProcessName}", processName);
            return null;
        }

        var session = sessions.FirstOrDefault(s => s.GetProcessID == processId && s.State == AudioSessionState.AudioSessionStateActive);

        if (session == null)
        {
            _logger.LogWarning("No active audio session found for process: {ProcessName} with PID: {Pid}",
                processName, processId);
            return null;
        }

        try
        {
            return new AudioSessionInfo
            {
                ProcessName = normalizedName,
                ProcessPath = GetProcessPath(session),
                ProcessId = (int)session.GetProcessID,
                Volume = session.SimpleAudioVolume.Volume,
                IsMuted = session.SimpleAudioVolume.Mute
            };
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error reading session info for active process: {ProcessName}", processName);
            return null;
        }
    }

    private async Task UpdateSessionCacheAsync()
    {
        if (DateTime.UtcNow - _lastCacheUpdate < CacheDuration)
        {
            return;
        }

        await _cacheLock.WaitAsync();
        try
        {
            if (DateTime.UtcNow - _lastCacheUpdate < CacheDuration)
            {
                return;
            }

            if (_defaultDevice == null)
            {
                InitializeDefaultDevice();
            }

            if (_defaultDevice == null)
            {
                return;
            }

            var sessionManager = _defaultDevice.AudioSessionManager;
            var sessions = sessionManager.Sessions;

            var newCache = new ConcurrentDictionary<string, List<AudioSessionControl>>();

            for (int i = 0; i < sessions.Count; i++)
            {
                try
                {
                    var session = sessions[i];
                    var processId = session.GetProcessID;

                    if (processId == 0) continue;

                    var processName = GetProcessNameFromSession(session);
                    if (string.IsNullOrEmpty(processName)) continue;

                    var normalizedName = NormalizeProcessName(processName);

                    if (!newCache.ContainsKey(normalizedName))
                    {
                        newCache[normalizedName] = new List<AudioSessionControl>();
                    }

                    newCache[normalizedName].Add(session);
                }
                catch (Exception ex)
                {
                    _logger.LogWarning(ex, "Error processing audio session at index {Index}", i);
                }
            }

            _sessionCache.Clear();
            foreach (var kvp in newCache)
            {
                _sessionCache[kvp.Key] = kvp.Value;
            }

            _lastCacheUpdate = DateTime.UtcNow;
            _logger.LogDebug("Session cache updated with {Count} unique processes", _sessionCache.Count);
        }
        finally
        {
            _cacheLock.Release();
        }
    }

    private string GetProcessNameFromSession(AudioSessionControl session)
    {
        try
        {
            var processId = session.GetProcessID;
            if (processId == 0) return string.Empty;

            var process = Process.GetProcessById((int)processId);
            return process.ProcessName + ".exe";
        }
        catch
        {
            return string.Empty;
        }
    }

    private string GetProcessPath(AudioSessionControl session)
    {
        try
        {
            var processId = session.GetProcessID;
            if (processId == 0) return string.Empty;

            var process = Process.GetProcessById((int)processId);
            return process.MainModule?.FileName ?? string.Empty;
        }
        catch
        {
            return string.Empty;
        }
    }

    private string NormalizeProcessName(string processName)
    {
        return processName.ToLowerInvariant().Replace(".exe", "");
    }

    public void InvalidateCache()
    {
        _lastCacheUpdate = DateTime.MinValue;
        _logger.LogDebug("Session cache invalidated");
    }

    public void Dispose()
    {
        _defaultDevice?.Dispose();
        _deviceEnumerator?.Dispose();
        _cacheLock?.Dispose();
    }
}
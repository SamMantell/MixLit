using MixlitAudioService.Models;
using NAudio.CoreAudioApi;
using NAudio.CoreAudioApi.Interfaces;
using System.Collections.Concurrent;
using System.Diagnostics;

namespace MixlitAudioService.Services;

public class AudioControlService : IDisposable, IMMNotificationClient
{
    private readonly MMDeviceEnumerator _deviceEnumerator;
    private MMDevice? _defaultDevice;
    private readonly ConcurrentDictionary<string, List<AudioSessionControl>> _sessionCache;
    private readonly ConcurrentDictionary<string, List<int>> _processIdCache;
    private readonly SemaphoreSlim _cacheLock = new(1, 1);
    private readonly SemaphoreSlim _deviceLock = new(1, 1); // Lock for device access
    private DateTime _lastCacheUpdate = DateTime.MinValue;
    private static readonly TimeSpan CacheDuration = TimeSpan.FromMilliseconds(500);

    private readonly ILogger<AudioControlService> _logger;
    private readonly ActiveWindowService _activeWindowService;

    public AudioControlService(
        ILogger<AudioControlService> logger,
        ActiveWindowService activeWindowService)
    {
        _logger = logger;
        _activeWindowService = activeWindowService;
        _deviceEnumerator = new MMDeviceEnumerator();
        _sessionCache = new ConcurrentDictionary<string, List<AudioSessionControl>>();
        _processIdCache = new ConcurrentDictionary<string, List<int>>();

        InitializeDefaultDevice();

        // Register for device change notifications
        _deviceEnumerator.RegisterEndpointNotificationCallback(this);
    }

    private void InitializeDefaultDevice()
    {
        try
        {
            _defaultDevice?.Dispose();
            _defaultDevice = _deviceEnumerator.GetDefaultAudioEndpoint(DataFlow.Render, Role.Multimedia);
            _logger.LogInformation("Default audio device initialized: {DeviceName}", _defaultDevice.FriendlyName);

            // Clear cache when device changes
            InvalidateCache();
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to initialize default audio device");
        }
    }

    // IMMNotificationClient implementation for device change detection
    public void OnDeviceStateChanged(string deviceId, DeviceState newState)
    {
        _logger.LogInformation("Device state changed: {DeviceId}, State: {State}", deviceId, newState);
    }

    public void OnDeviceAdded(string pwstrDeviceId)
    {
        _logger.LogInformation("Device added: {DeviceId}", pwstrDeviceId);
    }

    public void OnDeviceRemoved(string deviceId)
    {
        _logger.LogInformation("Device removed: {DeviceId}", deviceId);
    }

    public void OnDefaultDeviceChanged(DataFlow flow, Role role, string defaultDeviceId)
    {
        if (flow == DataFlow.Render && (role == Role.Multimedia || role == Role.Console))
        {
            _logger.LogInformation("Default audio device changed, reinitializing...");
            Task.Run(async () =>
            {
                await _deviceLock.WaitAsync();
                try
                {
                    InitializeDefaultDevice();
                }
                finally
                {
                    _deviceLock.Release();
                }
            });
        }
    }

    public void OnPropertyValueChanged(string pwstrDeviceId, PropertyKey key)
    {
        // Not needed for our use case
    }

    private async Task<MMDevice?> GetDefaultDeviceSafe()
    {
        await _deviceLock.WaitAsync();
        try
        {
            if (_defaultDevice == null)
            {
                InitializeDefaultDevice();
            }
            return _defaultDevice;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to get default device");
            return null;
        }
        finally
        {
            _deviceLock.Release();
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
                    // Include ALL sessions, not just active ones
                    sessions.Add(new AudioSessionInfo
                    {
                        ProcessName = kvp.Key,
                        ProcessPath = GetProcessPath(session),
                        ProcessId = (int)session.GetProcessID,
                        Volume = session.SimpleAudioVolume.Volume,
                        IsMuted = session.SimpleAudioVolume.Mute
                    });
                }
                catch (Exception ex)
                {
                    _logger.LogWarning(ex, "Error reading session info for {ProcessName}", kvp.Key);
                }
            }
        }

        return sessions;
    }

    public async Task<List<AudioSessionInfo>> GetFreshAudioSessionsAsync()
    {
        InvalidateCache();
        return await GetAllAudioSessionsAsync();
    }

    public async Task SetAppVolumeAsync(string processName, float volume)
    {
        var normalizedName = NormalizeProcessName(processName);
        await UpdateSessionCacheAsync();

        // Try to set volume via active sessions first
        if (_sessionCache.TryGetValue(normalizedName, out var sessions) && sessions.Any())
        {
            var tasks = sessions.Select(session => Task.Run(() =>
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
            return;
        }

        // If no active sessions, try to set volume by process ID
        if (_processIdCache.TryGetValue(normalizedName, out var processIds))
        {
            _logger.LogInformation("No active audio session for {ProcessName}, attempting to set volume by PID", processName);

            foreach (var pid in processIds)
            {
                await TrySetVolumeByProcessId(pid, volume, processName);
            }
        }
        else
        {
            _logger.LogWarning("No audio sessions or process IDs found for process: {ProcessName}", processName);
        }
    }

    private async Task TrySetVolumeByProcessId(int processId, float volume, string processName)
    {
        var device = await GetDefaultDeviceSafe();
        if (device == null) return;

        await Task.Run(() =>
        {
            try
            {
                var sessionManager = device.AudioSessionManager;
                var sessions = sessionManager.Sessions;

                for (int i = 0; i < sessions.Count; i++)
                {
                    var session = sessions[i];
                    if (session.GetProcessID == processId)
                    {
                        session.SimpleAudioVolume.Volume = Math.Clamp(volume, 0f, 1f);
                        _logger.LogDebug("Set volume for {ProcessName} (PID: {Pid}) to {Volume} via PID lookup",
                            processName, processId, volume);
                        return;
                    }
                }
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Failed to set volume by PID {Pid} for {ProcessName}", processId, processName);
            }
        });
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

        // Try active sessions first
        if (_sessionCache.TryGetValue(normalizedName, out var sessions) && sessions.Any())
        {
            var tasks = sessions.Select(session => Task.Run(() =>
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
            return;
        }

        // Try by process ID if no active sessions
        if (_processIdCache.TryGetValue(normalizedName, out var processIds))
        {
            _logger.LogInformation("No active audio session for {ProcessName}, attempting to mute by PID", processName);

            foreach (var pid in processIds)
            {
                await TryMuteByProcessId(pid, mute, processName);
            }
        }
        else
        {
            _logger.LogWarning("No audio sessions or process IDs found for process: {ProcessName}", processName);
        }
    }

    private async Task TryMuteByProcessId(int processId, bool mute, string processName)
    {
        var device = await GetDefaultDeviceSafe();
        if (device == null) return;

        await Task.Run(() =>
        {
            try
            {
                var sessionManager = device.AudioSessionManager;
                var sessions = sessionManager.Sessions;

                for (int i = 0; i < sessions.Count; i++)
                {
                    var session = sessions[i];
                    if (session.GetProcessID == processId)
                    {
                        session.SimpleAudioVolume.Mute = mute;
                        _logger.LogDebug("Set mute state for {ProcessName} (PID: {Pid}) to {Mute} via PID lookup",
                            processName, processId, mute);
                        return;
                    }
                }
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Failed to mute by PID {Pid} for {ProcessName}", processId, processName);
            }
        });
    }

    public async Task MuteGroupAsync(List<string> processNames, bool mute)
    {
        var tasks = processNames.Select(processName =>
            MuteAppAsync(processName, mute));

        await Task.WhenAll(tasks);
    }

    public async Task SetMasterVolumeAsync(float volume)
    {
        var device = await GetDefaultDeviceSafe();
        if (device == null)
        {
            _logger.LogError("Cannot set master volume - no default device available");
            throw new InvalidOperationException("No default audio device available");
        }

        await _deviceLock.WaitAsync();
        try
        {
            device.AudioEndpointVolume.MasterVolumeLevelScalar = Math.Clamp(volume, 0f, 1f);
            _logger.LogDebug("Set master volume to {Volume}", volume);
        }
        catch (System.Runtime.InteropServices.InvalidComObjectException)
        {
            _logger.LogWarning("COM object invalidated, reinitializing device and retrying...");
            InitializeDefaultDevice();

            // Retry once after reinitializing
            if (_defaultDevice != null)
            {
                _defaultDevice.AudioEndpointVolume.MasterVolumeLevelScalar = Math.Clamp(volume, 0f, 1f);
                _logger.LogDebug("Set master volume to {Volume} after reinit", volume);
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to set master volume");
            throw;
        }
        finally
        {
            _deviceLock.Release();
        }
    }

    public async Task MuteMasterVolumeAsync(bool mute)
    {
        var device = await GetDefaultDeviceSafe();
        if (device == null)
        {
            _logger.LogError("Cannot mute master volume - no default device available");
            throw new InvalidOperationException("No default audio device available");
        }

        await _deviceLock.WaitAsync();
        try
        {
            device.AudioEndpointVolume.Mute = mute;
            _logger.LogDebug("Set master mute state to {Mute}", mute);
        }
        catch (System.Runtime.InteropServices.InvalidComObjectException)
        {
            _logger.LogWarning("COM object invalidated, reinitializing device and retrying...");
            InitializeDefaultDevice();

            // Retry once after reinitializing
            if (_defaultDevice != null)
            {
                _defaultDevice.AudioEndpointVolume.Mute = mute;
                _logger.LogDebug("Set master mute state to {Mute} after reinit", mute);
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to mute master volume");
            throw;
        }
        finally
        {
            _deviceLock.Release();
        }
    }

    public async Task<float> GetMasterVolumeAsync()
    {
        var device = await GetDefaultDeviceSafe();
        if (device == null)
        {
            _logger.LogError("Cannot get master volume - no default device available");
            return 0f;
        }

        await _deviceLock.WaitAsync();
        try
        {
            return device.AudioEndpointVolume.MasterVolumeLevelScalar;
        }
        catch (System.Runtime.InteropServices.InvalidComObjectException)
        {
            _logger.LogWarning("COM object invalidated, reinitializing device and retrying...");
            InitializeDefaultDevice();

            // Retry once after reinitializing
            if (_defaultDevice != null)
            {
                return _defaultDevice.AudioEndpointVolume.MasterVolumeLevelScalar;
            }
            return 0f;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to get master volume");
            return 0f;
        }
        finally
        {
            _deviceLock.Release();
        }
    }

    public float GetMasterVolume()
    {
        return GetMasterVolumeAsync().GetAwaiter().GetResult();
    }

    public async Task SetActiveAppVolumeAsync(float volume)
    {
        var processName = _activeWindowService.GetActiveWindowProcessName();

        if (string.IsNullOrEmpty(processName))
        {
            _logger.LogWarning("No active window detected for volume adjustment");
            return;
        }

        _logger.LogInformation("Setting volume for active app: {ProcessName}", processName);
        await SetAppVolumeAsync(processName, volume);
    }

    public async Task MuteActiveAppAsync(bool mute)
    {
        var processName = _activeWindowService.GetActiveWindowProcessName();

        if (string.IsNullOrEmpty(processName))
        {
            _logger.LogWarning("No active window detected for mute adjustment");
            return;
        }

        _logger.LogInformation("Setting mute state for active app: {ProcessName} to {Mute}",
            processName, mute);
        await MuteAppAsync(processName, mute);
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
            return null;
        }

        var session = sessions.FirstOrDefault(s => s.GetProcessID == processId);

        if (session == null)
        {
            return null;
        }

        try
        {
            return new AudioSessionInfo
            {
                ProcessName = processName,
                ProcessPath = GetProcessPath(session),
                ProcessId = processId,
                Volume = session.SimpleAudioVolume.Volume,
                IsMuted = session.SimpleAudioVolume.Mute
            };
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting active app session info");
            return null;
        }
    }

    private async Task UpdateSessionCacheAsync()
    {
        if (DateTime.UtcNow - _lastCacheUpdate < CacheDuration)
        {
            return; // Cache is still fresh
        }

        await _cacheLock.WaitAsync();
        try
        {
            // Double-check after acquiring lock
            if (DateTime.UtcNow - _lastCacheUpdate < CacheDuration)
            {
                return;
            }

            var device = await GetDefaultDeviceSafe();
            if (device == null)
            {
                return;
            }

            var sessionManager = device.AudioSessionManager;
            var sessions = sessionManager.Sessions;

            var newCache = new ConcurrentDictionary<string, List<AudioSessionControl>>();
            var newProcessIdCache = new ConcurrentDictionary<string, List<int>>();

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

                    // Cache sessions
                    if (!newCache.ContainsKey(normalizedName))
                    {
                        newCache[normalizedName] = new List<AudioSessionControl>();
                    }
                    newCache[normalizedName].Add(session);

                    // Cache process IDs for ALL sessions (active or not)
                    if (!newProcessIdCache.ContainsKey(normalizedName))
                    {
                        newProcessIdCache[normalizedName] = new List<int>();
                    }
                    if (!newProcessIdCache[normalizedName].Contains((int)processId))
                    {
                        newProcessIdCache[normalizedName].Add((int)processId);
                    }
                }
                catch (Exception ex)
                {
                    _logger.LogWarning(ex, "Error processing audio session at index {Index}", i);
                }
            }

            // Update both caches
            _sessionCache.Clear();
            foreach (var kvp in newCache)
            {
                _sessionCache[kvp.Key] = kvp.Value;
            }

            _processIdCache.Clear();
            foreach (var kvp in newProcessIdCache)
            {
                _processIdCache[kvp.Key] = kvp.Value;
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
        try
        {
            _deviceEnumerator?.UnregisterEndpointNotificationCallback(this);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Error unregistering endpoint notification callback");
        }

        _deviceLock?.Wait();
        try
        {
            _defaultDevice?.Dispose();
            _defaultDevice = null;
        }
        finally
        {
            _deviceLock?.Release();
        }

        _deviceEnumerator?.Dispose();
        _cacheLock?.Dispose();
        _deviceLock?.Dispose();
    }
}
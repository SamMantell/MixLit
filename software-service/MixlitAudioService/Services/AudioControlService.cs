using MixlitAudioService.Models;
using NAudio.CoreAudioApi;
using NAudio.CoreAudioApi.Interfaces;
using System.Collections.Concurrent;
using System.Diagnostics;

namespace MixlitAudioService.Services;

public class AudioControlService : IDisposable, IMMNotificationClient
{
    private readonly MMDeviceEnumerator _deviceEnumerator;
    private readonly SemaphoreSlim _deviceLock = new(1, 1);

    // Track the latest pending volume for each process
    private readonly ConcurrentDictionary<string, float?> _pendingVolumes = new();
    private readonly ConcurrentDictionary<string, SemaphoreSlim> _processLocks = new();

    private readonly ILogger<AudioControlService> _logger;
    private readonly ActiveWindowService _activeWindowService;

    public AudioControlService(
        ILogger<AudioControlService> logger,
        ActiveWindowService activeWindowService)
    {
        _logger = logger;
        _activeWindowService = activeWindowService;
        _deviceEnumerator = new MMDeviceEnumerator();
        _deviceEnumerator.RegisterEndpointNotificationCallback(this);
    }

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
            _logger.LogInformation("Default audio device changed to {DeviceId}", defaultDeviceId);
        }
    }

    public void OnPropertyValueChanged(string pwstrDeviceId, PropertyKey key)
    {
    }

    private MMDevice? GetFreshDevice()
    {
        try
        {
            return _deviceEnumerator.GetDefaultAudioEndpoint(DataFlow.Render, Role.Multimedia);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to get default device");
            return null;
        }
    }

    private SemaphoreSlim GetProcessLock(string processName)
    {
        var normalizedName = NormalizeProcessName(processName);
        return _processLocks.GetOrAdd(normalizedName, _ => new SemaphoreSlim(1, 1));
    }

    private async Task<List<AudioSessionControl>> GetFreshSessionsForProcess(string processName)
    {
        var normalizedName = NormalizeProcessName(processName);
        var sessions = new List<AudioSessionControl>();

        var device = GetFreshDevice();
        if (device == null)
        {
            _logger.LogWarning("Could not get default audio device");
            return sessions;
        }

        try
        {
            var sessionManager = device.AudioSessionManager;
            var allSessions = sessionManager.Sessions;

            _logger.LogDebug("Scanning {Count} total audio sessions for {ProcessName}",
                allSessions.Count, processName);

            for (int i = 0; i < allSessions.Count; i++)
            {
                try
                {
                    var session = allSessions[i];
                    var processId = session.GetProcessID;

                    if (processId == 0) continue;

                    var sessionProcessName = GetProcessNameFromPid((int)processId);
                    if (string.IsNullOrEmpty(sessionProcessName)) continue;

                    var sessionNormalizedName = NormalizeProcessName(sessionProcessName);

                    if (sessionNormalizedName == normalizedName)
                    {
                        sessions.Add(session);
                    }
                }
                catch (Exception ex)
                {
                    _logger.LogDebug("Error checking session {Index}: {Error}", i, ex.Message);
                }
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting fresh sessions for {ProcessName}", processName);
        }
        finally
        {
            device?.Dispose();
        }

        return sessions;
    }

    public async Task<List<AudioSessionInfo>> GetAllAudioSessionsAsync()
    {
        var sessions = new List<AudioSessionInfo>();
        var device = GetFreshDevice();
        if (device == null) return sessions;

        try
        {
            var sessionManager = device.AudioSessionManager;
            var allSessions = sessionManager.Sessions;

            for (int i = 0; i < allSessions.Count; i++)
            {
                try
                {
                    var session = allSessions[i];
                    var processId = session.GetProcessID;

                    if (processId == 0) continue;

                    var processName = GetProcessNameFromPid((int)processId);
                    if (string.IsNullOrEmpty(processName)) continue;

                    sessions.Add(new AudioSessionInfo
                    {
                        ProcessName = processName,
                        ProcessPath = GetProcessPathFromPid((int)processId),
                        ProcessId = (int)processId,
                        Volume = session.SimpleAudioVolume.Volume,
                        IsMuted = session.SimpleAudioVolume.Mute
                    });
                }
                catch (Exception ex)
                {
                    _logger.LogWarning(ex, "Error reading session info at index {Index}", i);
                }
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting all audio sessions");
        }
        finally
        {
            device?.Dispose();
        }

        return sessions;
    }

    public async Task<List<AudioSessionInfo>> GetFreshAudioSessionsAsync()
    {
        return await GetAllAudioSessionsAsync();
    }

    public async Task SetAppVolumeAsync(string processName, float volume)
    {
        var normalizedName = NormalizeProcessName(processName);
        var processLock = GetProcessLock(processName);

        _pendingVolumes[normalizedName] = volume;

        if (!processLock.Wait(0))
        {
            _logger.LogDebug("Volume change for {ProcessName} queued (operation in progress)", processName);
            return;
        }

        try
        {
            while (true)
            {
                if (!_pendingVolumes.TryRemove(normalizedName, out var targetVolume) || !targetVolume.HasValue)
                {
                    break;
                }

                var sessions = await GetFreshSessionsForProcess(processName);

                if (!sessions.Any())
                {
                    _logger.LogDebug("No audio sessions found for {ProcessName}", processName);
                    break;
                }

                _logger.LogDebug("Setting volume for {Count} session(s) of {ProcessName} to {Volume}",
                    sessions.Count, processName, targetVolume.Value);

                foreach (var session in sessions)
                {
                    try
                    {
                        session.SimpleAudioVolume.Volume = Math.Clamp(targetVolume.Value, 0f, 1f);
                    }
                    catch (Exception ex)
                    {
                        _logger.LogError(ex, "Failed to set volume for session {ProcessName} (PID: {Pid})",
                            processName, session.GetProcessID);
                    }
                }

                if (!_pendingVolumes.ContainsKey(normalizedName))
                {
                    break;
                }
            }
        }
        finally
        {
            processLock.Release();
        }
    }

    public async Task MuteAppAsync(string processName, bool mute)
    {
        var processLock = GetProcessLock(processName);

        await processLock.WaitAsync();

        try
        {
            var sessions = await GetFreshSessionsForProcess(processName);

            if (!sessions.Any())
            {
                _logger.LogWarning("No audio sessions found for {ProcessName}", processName);
                return;
            }

            _logger.LogInformation("Setting mute state for {Count} session(s) of {ProcessName} to {Mute}",
                sessions.Count, processName, mute);

            foreach (var session in sessions)
            {
                try
                {
                    session.SimpleAudioVolume.Mute = mute;
                    _logger.LogDebug("Set mute state for {ProcessName} (PID: {Pid}) to {Mute}",
                        processName, session.GetProcessID, mute);
                }
                catch (Exception ex)
                {
                    _logger.LogError(ex, "Failed to set mute state for session {ProcessName} (PID: {Pid})",
                        processName, session.GetProcessID);
                }
            }
        }
        finally
        {
            processLock.Release();
        }
    }

    public async Task SetGroupVolumeAsync(List<string> processNames, float volume)
    {
        _logger.LogInformation("Setting group volume to {Volume} for {Count} processes",
            volume, processNames.Count);

        var tasks = processNames.Select(processName =>
            SetAppVolumeAsync(processName, volume));

        await Task.WhenAll(tasks);
    }

    public async Task MuteGroupAsync(List<string> processNames, bool mute)
    {
        var tasks = processNames.Select(processName =>
            MuteAppAsync(processName, mute));

        await Task.WhenAll(tasks);
    }

    public async Task SetMasterVolumeAsync(float volume)
    {
        var device = GetFreshDevice();
        if (device == null)
        {
            _logger.LogError("Cannot set master volume - no default device available");
            throw new InvalidOperationException("No default audio device available");
        }

        try
        {
            device.AudioEndpointVolume.MasterVolumeLevelScalar = Math.Clamp(volume, 0f, 1f);
            _logger.LogDebug("Set master volume to {Volume}", volume);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to set master volume");
            throw;
        }
        finally
        {
            device?.Dispose();
        }
    }

    public async Task MuteMasterVolumeAsync(bool mute)
    {
        var device = GetFreshDevice();
        if (device == null)
        {
            _logger.LogError("Cannot mute master volume - no default device available");
            throw new InvalidOperationException("No default audio device available");
        }

        try
        {
            device.AudioEndpointVolume.Mute = mute;
            _logger.LogDebug("Set master mute state to {Mute}", mute);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to mute master volume");
            throw;
        }
        finally
        {
            device?.Dispose();
        }
    }

    public async Task<float> GetMasterVolumeAsync()
    {
        var device = GetFreshDevice();
        if (device == null)
        {
            _logger.LogError("Cannot get master volume - no default device available");
            return 0f;
        }

        try
        {
            return device.AudioEndpointVolume.MasterVolumeLevelScalar;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to get master volume");
            return 0f;
        }
        finally
        {
            device?.Dispose();
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

        var sessions = await GetFreshSessionsForProcess(processName);
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
                ProcessPath = GetProcessPathFromPid(processId),
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

    private string GetProcessNameFromPid(int processId)
    {
        try
        {
            var process = Process.GetProcessById(processId);
            return process.ProcessName + ".exe";
        }
        catch
        {
            return string.Empty;
        }
    }

    private string GetProcessPathFromPid(int processId)
    {
        try
        {
            var process = Process.GetProcessById(processId);
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
        _logger.LogDebug("InvalidateCache called (no-op - always using fresh sessions)");
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

        foreach (var lockPair in _processLocks)
        {
            lockPair.Value?.Dispose();
        }
        _processLocks.Clear();

        _deviceEnumerator?.Dispose();
        _deviceLock?.Dispose();
    }
}
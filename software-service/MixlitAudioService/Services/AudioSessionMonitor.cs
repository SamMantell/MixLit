using Microsoft.AspNetCore.SignalR;
using MixlitAudioService.Models;
using NAudio.CoreAudioApi;
using System.Collections.Concurrent;

namespace MixlitAudioService.Services;

public class AudioSessionMonitor : BackgroundService
{
    private readonly ILogger<AudioSessionMonitor> _logger;
    private readonly IServiceProvider _serviceProvider;
    private readonly ConcurrentDictionary<string, List<AudioSessionInfo>> _currentSessions = new();
    private readonly ConcurrentDictionary<string, DateTime> _lastSeenProcesses = new();
    private MMDeviceEnumerator? _deviceEnumerator;
    private MMDevice? _defaultDevice;
    private string? _currentDeviceId;
    private int _monitorCycles = 0;

    public AudioSessionMonitor(
        ILogger<AudioSessionMonitor> logger,
        IServiceProvider serviceProvider)
    {
        _logger = logger;
        _serviceProvider = serviceProvider;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        _logger.LogInformation("Audio Session Monitor started");

        try
        {
            _deviceEnumerator = new MMDeviceEnumerator();
            _defaultDevice = _deviceEnumerator.GetDefaultAudioEndpoint(DataFlow.Render, Role.Multimedia);
            _currentDeviceId = _defaultDevice?.ID;

            while (!stoppingToken.IsCancellationRequested)
            {
                await MonitorSessionsAsync(stoppingToken);
                await Task.Delay(TimeSpan.FromSeconds(1), stoppingToken);
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error in Audio Session Monitor");
        }
        finally
        {
            _defaultDevice?.Dispose();
            _deviceEnumerator?.Dispose();
        }
    }

    private async Task MonitorSessionsAsync(CancellationToken cancellationToken)
    {
        try
        {
            using var scope = _serviceProvider.CreateScope();
            var audioService = scope.ServiceProvider.GetRequiredService<AudioControlService>();
            var hubContext = scope.ServiceProvider.GetRequiredService<IHubContext<AudioHub>>();

            //check default device change
            var newDefaultDevice = _deviceEnumerator?.GetDefaultAudioEndpoint(DataFlow.Render, Role.Multimedia);
            if (newDefaultDevice?.ID != _currentDeviceId)
            {
                _logger.LogInformation("Audio device changed from {OldDevice} to {NewDevice}",
                    _currentDeviceId, newDefaultDevice?.ID);
                _currentDeviceId = newDefaultDevice?.ID;
                _defaultDevice?.Dispose();
                _defaultDevice = newDefaultDevice;

                // Mark all current sessions as needing update check
                foreach (var processName in _currentSessions.Keys.ToList())
                {
                    _lastSeenProcesses[processName] = DateTime.UtcNow;
                }
            }

            audioService.InvalidateCache();
            var currentSessions = await audioService.GetFreshAudioSessionsAsync();
            var currentProcessMap = new Dictionary<string, List<AudioSessionInfo>>();

            // Group current sessions by process name
            foreach (var session in currentSessions)
            {
                var normalizedName = session.ProcessName.ToLowerInvariant().Replace(".exe", "");
                if (!currentProcessMap.ContainsKey(normalizedName))
                {
                    currentProcessMap[normalizedName] = new List<AudioSessionInfo>();
                }
                currentProcessMap[normalizedName].Add(session);
            }

            // Check for new or restored sessions
            foreach (var kvp in currentProcessMap)
            {
                var processName = kvp.Key;
                var sessions = kvp.Value;

                bool wasRemoved = _lastSeenProcesses.ContainsKey(processName) &&
                                  !_currentSessions.ContainsKey(processName);

                bool hasNewPids = false;
                if (_currentSessions.ContainsKey(processName))
                {
                    var oldPids = _currentSessions[processName].Select(s => s.ProcessId).ToHashSet();
                    var newPids = sessions.Select(s => s.ProcessId).ToHashSet();
                    hasNewPids = !oldPids.SetEquals(newPids);
                }

                if (!_currentSessions.ContainsKey(processName) || wasRemoved || hasNewPids)
                {
                    string eventType = wasRemoved ? "RESTORED" : (hasNewPids ? "UPDATED" : "ADDED");
                    _currentSessions[processName] = sessions;
                    _lastSeenProcesses[processName] = DateTime.UtcNow;

                    foreach (var session in sessions)
                    {
                        _logger.LogInformation("Audio session {EventType}: {ProcessName} (PID: {ProcessId})",
                            eventType, session.ProcessName, session.ProcessId);

                        // Send update for restored/changed sessions, add for new
                        if (wasRemoved || hasNewPids)
                        {
                            await hubContext.Clients.All.SendAsync("SessionUpdated", new SessionEvent
                            {
                                EventType = "SESSION_UPDATED",
                                Session = session
                            }, cancellationToken);
                        }
                        else
                        {
                            await hubContext.Clients.All.SendAsync("SessionAdded", new SessionEvent
                            {
                                EventType = "SESSION_ADDED",
                                Session = session
                            }, cancellationToken);
                        }
                    }
                }

                _lastSeenProcesses[processName] = DateTime.UtcNow;
            }

            // Check for removed processes
            var removedProcesses = _currentSessions.Keys
                .Where(k => !currentProcessMap.ContainsKey(k))
                .ToList();

            foreach (var processName in removedProcesses)
            {
                if (_currentSessions.TryRemove(processName, out var removedSessions))
                {
                    _lastSeenProcesses[processName] = DateTime.UtcNow;

                    foreach (var session in removedSessions)
                    {
                        _logger.LogInformation("Audio session removed: {ProcessName} (PID: {ProcessId})",
                            session.ProcessName, session.ProcessId);

                        await hubContext.Clients.All.SendAsync("SessionRemoved", new SessionEvent
                        {
                            EventType = "SESSION_REMOVED",
                            Session = session
                        }, cancellationToken);
                    }
                }
            }

            var cutoffTime = DateTime.UtcNow.AddMinutes(-2);
            var staleProcesses = _lastSeenProcesses
                .Where(kvp => kvp.Value < cutoffTime && !_currentSessions.ContainsKey(kvp.Key))
                .Select(kvp => kvp.Key)
                .ToList();

            foreach (var processName in staleProcesses)
            {
                _lastSeenProcesses.TryRemove(processName, out _);
                _logger.LogDebug("Cleaned up stale process entry: {ProcessName}", processName);
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error monitoring audio sessions");
        }

        if (++_monitorCycles % 60 == 0) // Every minute
        {
            GC.Collect();
            GC.WaitForPendingFinalizers();
        }

    }
}
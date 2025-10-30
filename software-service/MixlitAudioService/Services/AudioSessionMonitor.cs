using Microsoft.AspNetCore.SignalR;
using MixlitAudioService.Models;
using NAudio.CoreAudioApi;
using System.Collections.Concurrent;

namespace MixlitAudioService.Services;

public class AudioSessionMonitor : BackgroundService
{
    private readonly ILogger<AudioSessionMonitor> _logger;
    private readonly IServiceProvider _serviceProvider;
    // Track both current and previously known sessions
    private readonly ConcurrentDictionary<string, List<AudioSessionInfo>> _currentSessions = new();
    private readonly ConcurrentDictionary<string, DateTime> _lastSeenProcesses = new();
    private MMDeviceEnumerator? _deviceEnumerator;
    private MMDevice? _defaultDevice;

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

            while (!stoppingToken.IsCancellationRequested)
            {
                await MonitorSessionsAsync(stoppingToken);
                await Task.Delay(TimeSpan.FromSeconds(1), stoppingToken); // Reduced to 1 second for faster detection
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

            // Force cache refresh
            audioService.InvalidateCache();

            var currentSessions = await audioService.GetAllAudioSessionsAsync();
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

                // Check if this is a known process that came back
                bool wasRemoved = _lastSeenProcesses.ContainsKey(processName) &&
                                  !_currentSessions.ContainsKey(processName);

                if (!_currentSessions.ContainsKey(processName) || wasRemoved)
                {
                    // New process or restored process
                    _currentSessions[processName] = sessions;
                    _lastSeenProcesses[processName] = DateTime.UtcNow;

                    string eventType = wasRemoved ? "RESTORED" : "ADDED";

                    foreach (var session in sessions)
                    {
                        _logger.LogInformation("Audio session {EventType}: {ProcessName} (PID: {ProcessId})",
                            eventType, session.ProcessName, session.ProcessId);

                        // Send appropriate event
                        if (wasRemoved)
                        {
                            // Send update event for restored sessions
                            await hubContext.Clients.All.SendAsync("SessionUpdated", new SessionEvent
                            {
                                EventType = "SESSION_UPDATED",
                                Session = session
                            }, cancellationToken);
                        }
                        else
                        {
                            // Send add event for new sessions
                            await hubContext.Clients.All.SendAsync("SessionAdded", new SessionEvent
                            {
                                EventType = "SESSION_ADDED",
                                Session = session
                            }, cancellationToken);
                        }
                    }
                }
                else
                {
                    // Check if PIDs changed for existing process
                    var oldPids = _currentSessions[processName].Select(s => s.ProcessId).ToHashSet();
                    var newPids = sessions.Select(s => s.ProcessId).ToHashSet();

                    if (!oldPids.SetEquals(newPids))
                    {
                        _logger.LogInformation("Process {ProcessName} PIDs changed", processName);
                        _currentSessions[processName] = sessions;

                        foreach (var session in sessions)
                        {
                            await hubContext.Clients.All.SendAsync("SessionUpdated", new SessionEvent
                            {
                                EventType = "SESSION_UPDATED",
                                Session = session
                            }, cancellationToken);
                        }
                    }
                }

                // Update last seen time
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
                    // Keep track that we've seen this process before
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

            // Clean up old entries from _lastSeenProcesses (older than 5 minutes)
            var cutoffTime = DateTime.UtcNow.AddMinutes(-5);
            var staleProcesses = _lastSeenProcesses
                .Where(kvp => kvp.Value < cutoffTime && !_currentSessions.ContainsKey(kvp.Key))
                .Select(kvp => kvp.Key)
                .ToList();

            foreach (var processName in staleProcesses)
            {
                _lastSeenProcesses.TryRemove(processName, out _);
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error monitoring audio sessions");
        }
    }
}
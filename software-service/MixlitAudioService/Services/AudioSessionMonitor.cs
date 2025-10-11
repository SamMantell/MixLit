using Microsoft.AspNetCore.SignalR;
using MixlitAudioService.Models;
using NAudio.CoreAudioApi;
using System.Collections.Concurrent;

namespace MixlitAudioService.Services;

public class AudioSessionMonitor : BackgroundService
{
    private readonly ILogger<AudioSessionMonitor> _logger;
    private readonly IServiceProvider _serviceProvider;
    private readonly ConcurrentDictionary<string, AudioSessionInfo> _knownSessions = new();
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
                await Task.Delay(TimeSpan.FromSeconds(2), stoppingToken);
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

            var currentSessions = await audioService.GetAllAudioSessionsAsync();
            var currentSessionKeys = new HashSet<string>();

            foreach (var session in currentSessions)
            {
                var key = $"{session.ProcessName}_{session.ProcessId}";
                currentSessionKeys.Add(key);

                if (!_knownSessions.ContainsKey(key))
                {
                    _knownSessions[key] = session;

                    _logger.LogInformation("New audio session detected: {ProcessName} (PID: {ProcessId})",
                        session.ProcessName, session.ProcessId);

                    await hubContext.Clients.All.SendAsync("SessionAdded", new SessionEvent
                    {
                        EventType = "SESSION_ADDED",
                        Session = session
                    }, cancellationToken);
                }
            }

            var removedSessions = _knownSessions.Keys
                .Where(k => !currentSessionKeys.Contains(k))
                .ToList();

            foreach (var key in removedSessions)
            {
                if (_knownSessions.TryRemove(key, out var removedSession))
                {
                    _logger.LogInformation("Audio session removed: {ProcessName} (PID: {ProcessId})",
                        removedSession.ProcessName, removedSession.ProcessId);

                    await hubContext.Clients.All.SendAsync("SessionRemoved", new SessionEvent
                    {
                        EventType = "SESSION_REMOVED",
                        Session = removedSession
                    }, cancellationToken);
                }
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error monitoring audio sessions");
        }
    }
}
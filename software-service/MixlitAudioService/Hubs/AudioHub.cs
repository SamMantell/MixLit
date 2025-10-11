using Microsoft.AspNetCore.SignalR;
using MixlitAudioService.Models;

namespace MixlitAudioService.Services;

public class AudioHub : Hub
{
    private readonly ILogger<AudioHub> _logger;

    public AudioHub(ILogger<AudioHub> logger)
    {
        _logger = logger;
    }

    public override async Task OnConnectedAsync()
    {
        _logger.LogInformation("Client connected: {ConnectionId}", Context.ConnectionId);
        await base.OnConnectedAsync();
    }

    public override async Task OnDisconnectedAsync(Exception? exception)
    {
        _logger.LogInformation("Client disconnected: {ConnectionId}", Context.ConnectionId);
        await base.OnDisconnectedAsync(exception);
    }

    public async Task SendVolumeCommand(VolumeCommand command)
    {
        await Clients.Others.SendAsync("VolumeChanged", command);
    }
}
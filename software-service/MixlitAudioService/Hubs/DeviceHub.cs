using Microsoft.AspNetCore.SignalR;
using MixlitAudioService.Services;

namespace MixlitAudioService.Hubs;

/// <summary>
/// Pushes serial device events to connected Flutter clients.
/// Events sent by SerialDeviceService via IHubContext:
///   SliderDataReceived      Dictionary&lt;int,int&gt;
///   ButtonEventReceived     { buttonId: string, state: int }
///   DeviceConnectionChanged bool
///   InitialHardwareValues   Dictionary&lt;int,int&gt;
/// </summary>
public class DeviceHub : Hub
{
    private readonly SerialDeviceService _deviceService;

    public DeviceHub(SerialDeviceService deviceService)
    {
        _deviceService = deviceService;
    }

    /// <summary>
    /// Immediately send the current device state to a newly connected client
    /// so it doesn't have to wait for the next event broadcast.
    /// </summary>
    public override async Task OnConnectedAsync()
    {
        await Clients.Caller.SendAsync(
            "DeviceConnectionChanged",
            _deviceService.IsConnected);

        if (_deviceService.IsConnected && _deviceService.LastKnownHardwareValues?.Count > 0)
            await Clients.Caller.SendAsync(
                "InitialHardwareValues",
                _deviceService.LastKnownHardwareValues);

        await base.OnConnectedAsync();
    }
}
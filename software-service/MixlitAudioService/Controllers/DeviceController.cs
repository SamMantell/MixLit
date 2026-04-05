using Microsoft.AspNetCore.Mvc;
using MixlitAudioService.Services;

namespace MixlitAudioService.Controllers;

[ApiController]
[Route("api/device")]
public class DeviceController : ControllerBase
{
    private readonly SerialDeviceService _deviceService;
    private readonly ILogger<DeviceController> _logger;

    public DeviceController(SerialDeviceService deviceService, ILogger<DeviceController> logger)
    {
        _deviceService = deviceService;
        _logger = logger;
    }

    /// <summary>POST /api/device/command - send an LED or other raw command.</summary>
    [HttpPost("command")]
    public async Task<IActionResult> SendCommand([FromBody] DeviceCommandRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.Command))
            return BadRequest(new { success = false, error = "Command is required" });

        var success = await _deviceService.SendCommandAsync(request.Command);

        return success
            ? Ok(new { success = true })
            : StatusCode(503, new { success = false, error = "Device not connected" });
    }

    /// <summary>GET /api/device/status - current connection state.</summary>
    [HttpGet("status")]
    public IActionResult GetStatus() =>
        Ok(new
        {
            success = true,
            data = new
            {
                isConnected = _deviceService.IsConnected,
                port = _deviceService.ConnectedPort
            }
        });

    /// <summary>GET /api/device/hardware-values - last known slider positions.</summary>
    [HttpGet("hardware-values")]
    public IActionResult GetHardwareValues() =>
        Ok(new
        {
            success = true,
            data = _deviceService.LastKnownHardwareValues
        });
}

public record DeviceCommandRequest(string Command);
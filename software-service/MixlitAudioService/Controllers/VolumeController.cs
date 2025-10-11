using Microsoft.AspNetCore.Mvc;
using MixlitAudioService.Models;
using MixlitAudioService.Services;

namespace MixlitAudioService.Controllers;

[ApiController]
[Route("api/[controller]")]
public class VolumeController : ControllerBase
{
    private readonly AudioControlService _audioService;
    private readonly ILogger<VolumeController> _logger;

    public VolumeController(
        AudioControlService audioService,
        ILogger<VolumeController> logger)
    {
        _audioService = audioService;
        _logger = logger;
    }

    [HttpPost("set")]
    public async Task<IActionResult> SetVolume([FromBody] VolumeCommand command)
    {
        try
        {
            _logger.LogInformation("Setting volume for slider {Index} to {Volume}",
                command.SliderIndex, command.Volume);

            switch (command.TargetType)
            {
                case TargetType.App:
                    if (string.IsNullOrEmpty(command.ProcessName))
                    {
                        return BadRequest(ApiResponse<object>.Fail("ProcessName is required for App target"));
                    }
                    await _audioService.SetAppVolumeAsync(command.ProcessName, command.Volume);
                    break;

                case TargetType.ActiveApp:
                    await _audioService.SetActiveAppVolumeAsync(command.Volume);
                    break;

                case TargetType.Group:
                    if (command.ProcessNames == null || !command.ProcessNames.Any())
                    {
                        return BadRequest(ApiResponse<object>.Fail("ProcessNames is required for Group target"));
                    }
                    await _audioService.SetGroupVolumeAsync(command.ProcessNames, command.Volume);
                    break;

                case TargetType.MasterVolume:
                case TargetType.DefaultDevice:
                    await _audioService.SetMasterVolumeAsync(command.Volume);
                    break;

                default:
                    return BadRequest(ApiResponse<object>.Fail($"Unsupported target type: {command.TargetType}"));
            }

            return Ok(ApiResponse<object>.Ok(new { message = "Volume set successfully" }));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error setting volume");
            return StatusCode(500, ApiResponse<object>.Fail(ex.Message));
        }
    }

    [HttpPost("mute")]
    public async Task<IActionResult> SetMute([FromBody] MuteCommand command)
    {
        try
        {
            _logger.LogInformation("Setting mute state for slider {Index} to {Mute}",
                command.SliderIndex, command.IsMuted);

            switch (command.TargetType)
            {
                case TargetType.App:
                    if (string.IsNullOrEmpty(command.ProcessName))
                    {
                        return BadRequest(ApiResponse<object>.Fail("ProcessName is required for App target"));
                    }
                    await _audioService.MuteAppAsync(command.ProcessName, command.IsMuted);
                    break;

                case TargetType.ActiveApp:
                    await _audioService.MuteActiveAppAsync(command.IsMuted);
                    break;

                case TargetType.Group:
                    if (command.ProcessNames == null || !command.ProcessNames.Any())
                    {
                        return BadRequest(ApiResponse<object>.Fail("ProcessNames is required for Group target"));
                    }
                    await _audioService.MuteGroupAsync(command.ProcessNames, command.IsMuted);
                    break;

                case TargetType.MasterVolume:
                case TargetType.DefaultDevice:
                    await _audioService.MuteMasterVolumeAsync(command.IsMuted);
                    break;

                default:
                    return BadRequest(ApiResponse<object>.Fail($"Unsupported target type: {command.TargetType}"));
            }

            return Ok(ApiResponse<object>.Ok(new { message = "Mute state set successfully" }));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error setting mute state");
            return StatusCode(500, ApiResponse<object>.Fail(ex.Message));
        }
    }

    [HttpGet("active-app")]
    public async Task<IActionResult> GetActiveApp()
    {
        try
        {
            var activeSession = await _audioService.GetActiveAppSessionAsync();

            if (activeSession == null)
            {
                return NotFound(ApiResponse<AudioSessionInfo>.Fail("No active audio session found"));
            }

            return Ok(ApiResponse<AudioSessionInfo>.Ok(activeSession));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting active audio session");
            return StatusCode(500, ApiResponse<AudioSessionInfo>.Fail(ex.Message));
        }
    }

    [HttpGet("master")]
    public IActionResult GetMasterVolume()
    {
        try
        {
            var volume = _audioService.GetMasterVolume();
            return Ok(ApiResponse<float>.Ok(volume));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting master volume");
            return StatusCode(500, ApiResponse<float>.Fail(ex.Message));
        }
    }
}
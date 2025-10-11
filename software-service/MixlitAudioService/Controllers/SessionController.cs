using Microsoft.AspNetCore.Mvc;
using MixlitAudioService.Models;
using MixlitAudioService.Services;

namespace MixlitAudioService.Controllers;

[ApiController]
[Route("api/[controller]")]
public class SessionController : ControllerBase
{
    private readonly AudioControlService _audioService;
    private readonly IconExtractionService _iconService;
    private readonly ILogger<SessionController> _logger;

    public SessionController(
        AudioControlService audioService,
        IconExtractionService iconService,
        ILogger<SessionController> logger)
    {
        _audioService = audioService;
        _iconService = iconService;
        _logger = logger;
    }

    [HttpGet("list")]
    public async Task<IActionResult> GetAllSessions([FromQuery] bool includeIcons = false)
    {
        try
        {
            var sessions = await _audioService.GetAllAudioSessionsAsync();

            if (includeIcons)
            {
                var tasks = sessions.Select(async session =>
                {
                    if (!string.IsNullOrEmpty(session.ProcessPath))
                    {
                        session.IconBase64 = await _iconService.GetIconBase64Async(session.ProcessPath);
                    }
                });

                await Task.WhenAll(tasks);
            }

            return Ok(ApiResponse<List<AudioSessionInfo>>.Ok(sessions));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting audio sessions");
            return StatusCode(500, ApiResponse<List<AudioSessionInfo>>.Fail(ex.Message));
        }
    }

    [HttpGet("icon")]
    public async Task<IActionResult> GetIcon([FromQuery] string processPath)
    {
        try
        {
            if (string.IsNullOrEmpty(processPath))
            {
                return BadRequest(ApiResponse<string>.Fail("processPath is required"));
            }

            var iconBase64 = await _iconService.GetIconBase64Async(processPath);

            if (iconBase64 == null)
            {
                return NotFound(ApiResponse<string>.Fail("Icon not found"));
            }

            return Ok(ApiResponse<string>.Ok(iconBase64));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting icon");
            return StatusCode(500, ApiResponse<string>.Fail(ex.Message));
        }
    }

    [HttpPost("refresh")]
    public IActionResult RefreshSessions()
    {
        try
        {
            _audioService.InvalidateCache();
            return Ok(ApiResponse<object>.Ok(new { message = "Cache invalidated successfully" }));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error refreshing sessions");
            return StatusCode(500, ApiResponse<object>.Fail(ex.Message));
        }
    }
}
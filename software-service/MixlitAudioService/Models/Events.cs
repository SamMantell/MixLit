using System;

namespace MixlitAudioService.Models;

public class AudioSessionInfo
{
    public string ProcessName { get; set; } = string.Empty;
    public string ProcessPath { get; set; } = string.Empty;
    public int ProcessId { get; set; }
    public float Volume { get; set; }
    public bool IsMuted { get; set; }
    public string? IconBase64 { get; set; }
}

public class SessionEvent
{
    public string EventType { get; set; } = string.Empty; //SESSION_ADDED or SESSION_REMOVED
    public AudioSessionInfo Session { get; set; } = new();
    public DateTime Timestamp { get; set; } = DateTime.UtcNow;
}

public class VolumeChangedEvent
{
    public int SliderIndex { get; set; }
    public string ProcessName { get; set; } = string.Empty;
    public float Volume { get; set; }
    public bool IsMuted { get; set; }
}

public class ApiResponse<T>
{
    public bool Success { get; set; }
    public T? Data { get; set; }
    public string? Error { get; set; }

    public static ApiResponse<T> Ok(T data) => new() { Success = true, Data = data };
    public static ApiResponse<T> Fail(string error) => new() { Success = false, Error = error };
}
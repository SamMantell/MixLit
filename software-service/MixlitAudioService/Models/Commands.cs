namespace MixlitAudioService.Models
{
    public enum TargetType
    {
        App,
        Group,
        MasterVolume,
        DefaultDevice,
        ActiveApp
    }

    public class VolumeCommand
    {
        public int SliderIndex { get; set; }
        public float Volume { get; set; } // 0.0 to 1.0
        public TargetType TargetType { get; set; }
        public string? ProcessName { get; set; }
        public string? GroupId { get; set; }
        public List<string>? ProcessNames { get; set; }
    }

    public class MuteCommand
    {
        public int SliderIndex { get; set; }
        public bool IsMuted { get; set; }
        public TargetType TargetType { get; set; }
        public string? ProcessName { get; set; }
        public string? GroupId { get; set; }
        public List<string>? ProcessNames { get; set; }
    }

    public class AssignmentCommand
    {
        public int SliderIndex { get; set; }
        public TargetType TargetType { get; set; }
        public string? ProcessName { get; set; }
        public string? ProcessPath { get; set; }
        public string? GroupId { get; set; }
        public List<string>? ProcessNames { get; set; }
    }
}

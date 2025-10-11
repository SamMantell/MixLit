namespace MixlitAudioService.Models;

public class AppGroup
{
    public string Id { get; set; } = Guid.NewGuid().ToString();
    public string Name { get; set; } = string.Empty;
    public List<string> ProcessNames { get; set; } = new();
    public string Color { get; set; } = "#FFFFFF";
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}
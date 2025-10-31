using Microsoft.AspNetCore.Builder;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using MixlitAudioService.Services;

var builder = WebApplication.CreateBuilder(args);

// Configure to run as Windows Service
builder.Host.UseWindowsService();

// Add services to the container
builder.Services.AddControllers();
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();

// SignalR for real-time
builder.Services.AddSignalR();

// CORS for Flutter
builder.Services.AddCors(options =>
{
    options.AddPolicy("FlutterApp", policy =>
    {
        policy.WithOrigins("http://localhost:*", "http://127.0.0.1:*")
              .AllowAnyHeader()
              .AllowAnyMethod()
              .AllowCredentials();
    });
});

// Register services
builder.Services.AddSingleton<AudioControlService>();
builder.Services.AddSingleton<ActiveWindowService>();
builder.Services.AddSingleton<IconExtractionService>();
builder.Services.AddHostedService<AudioSessionMonitor>();
builder.Services.AddSingleton<ProcessDiscoveryService>();

// Port
builder.WebHost.ConfigureKestrel(options =>
{
    options.ListenLocalhost(8765);
});

// Logging config
builder.Logging.ClearProviders();
builder.Logging.AddConsole();
builder.Logging.AddDebug();
builder.Logging.AddEventLog(); // For Windows Event Log when running as service

var app = builder.Build();

// Configure the HTTP request pipeline
if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

app.UseCors("FlutterApp");

app.MapControllers();
app.MapHub<AudioHub>("/hub/audio");

// Health check endpoint
app.MapGet("/health", () => Results.Ok(new { status = "healthy", timestamp = DateTime.UtcNow }));

app.Logger.LogInformation("Mixlit Audio Service starting on port 8765");

app.Run();
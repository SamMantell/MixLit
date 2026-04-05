using Microsoft.AspNetCore.SignalR;
using MixlitAudioService.Hubs;
using NAudio.CoreAudioApi;
using System.IO.Ports;
using System.Text;

namespace MixlitAudioService.Services;

public class SerialDeviceService : BackgroundService
{
    private const string DeviceIdentifier = "mixlit";
    private const int BaudRate = 38400;
    private const string IdentificationRequest = "?\n";
    private const int ScanIntervalMs = 2000;
    private const int ReadIntervalMs = 10;

    private SerialPort? _port;
    private bool _isConnected;
    private string? _lastKnownPort;
    private Dictionary<int, int>? _lastKnownHardwareValues;
    private readonly SemaphoreSlim _writeLock = new(1, 1);

    private readonly IHubContext<DeviceHub> _hubContext;
    private readonly ILogger<SerialDeviceService> _logger;

    public bool IsConnected => _isConnected;
    public string? ConnectedPort => _lastKnownPort;
    public Dictionary<int, int>? LastKnownHardwareValues => _lastKnownHardwareValues;

    public SerialDeviceService(
        IHubContext<DeviceHub> hubContext,
        ILogger<SerialDeviceService> logger)
    {
        _hubContext = hubContext;
        _logger = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        _logger.LogInformation("Serial Device Service starting");

        while (!stoppingToken.IsCancellationRequested)
        {
            if (!_isConnected)
            {
                await TryConnectAsync(stoppingToken);

                if (!_isConnected)
                    await Task.Delay(ScanIntervalMs, stoppingToken)
                              .ContinueWith(_ => { }); // swallow cancellation
            }
            else
            {
                await Task.Delay(500, stoppingToken)
                          .ContinueWith(_ => { });
            }
        }

        await HandleDisconnectionAsync(notify: false);
    }

    private async Task TryConnectAsync(CancellationToken ct)
    {
        var ports = SerialPort.GetPortNames();
        _logger.LogDebug("Available ports: {Ports}", string.Join(", ", ports));

        // Try last known port first
        if (_lastKnownPort != null && ports.Contains(_lastKnownPort))
            if (await TryConnectToPortAsync(_lastKnownPort, ct)) return;

        foreach (var portName in ports)
        {
            if (portName == _lastKnownPort) continue;
            if (await TryConnectToPortAsync(portName, ct)) return;
        }
    }

    private async Task<bool> TryConnectToPortAsync(string portName, CancellationToken ct)
    {
        SerialPort? port = null;
        try
        {
            _logger.LogDebug("Trying {Port}...", portName);

            port = new SerialPort(portName, BaudRate, Parity.None, 8, StopBits.One)
            {
                DtrEnable = true,
                RtsEnable = true,
                ReadTimeout = 500,
                WriteTimeout = 500
            };

            port.Open();

            var (identified, hardwareValues) = await VerifyDeviceAsync(port, ct);
            if (!identified)
            {
                port.Close();
                port.Dispose();
                return false;
            }

            _port = port;
            _lastKnownPort = portName;
            _isConnected = true;

            if (hardwareValues != null)
                _lastKnownHardwareValues = hardwareValues;

            // Start background read loop
            _ = Task.Run(() => ReadLoopAsync(ct), ct);

            await _hubContext.Clients.All.SendAsync("DeviceConnectionChanged", true, ct);
            _logger.LogInformation("Connected to MixLit on {Port}", portName);

            if (hardwareValues?.Count > 0)
                await _hubContext.Clients.All.SendAsync("InitialHardwareValues", hardwareValues, ct);

            return true;
        }
        catch (Exception ex)
        {
            _logger.LogDebug("Could not connect to {Port}: {Error}", portName, ex.Message);
            try { port?.Close(); port?.Dispose(); } catch { }
            return false;
        }
    }

    private async Task<(bool Identified, Dictionary<int, int>? HardwareValues)>
        VerifyDeviceAsync(SerialPort port, CancellationToken ct)
    {
        bool identified = false;
        var lineBuffer = new StringBuilder();
        var rxBuffer = new byte[256];

        try
        {
            port.DiscardInBuffer();

            for (int attempt = 0; attempt < 3 && !ct.IsCancellationRequested; attempt++)
            {
                _logger.LogDebug("Identification request attempt {N}", attempt + 1);
                port.Write(IdentificationRequest);

                var deadline = DateTime.UtcNow.AddMilliseconds(600);
                while (DateTime.UtcNow < deadline && !ct.IsCancellationRequested)
                {
                    if (port.BytesToRead > 0)
                    {
                        var toRead = Math.Min(port.BytesToRead, rxBuffer.Length);
                        var read = port.Read(rxBuffer, 0, toRead);

                        for (int i = 0; i < read; i++)
                        {
                            var ch = (char)rxBuffer[i];
                            if (ch is '\n' or '\r')
                            {
                                var line = lineBuffer.ToString().Trim();
                                lineBuffer.Clear();

                                if (string.IsNullOrEmpty(line)) continue;
                                _logger.LogDebug("Verification line: {Line}", line);

                                if (line.Contains(DeviceIdentifier))
                                    identified = true;

                                if (identified && line.Contains('|'))
                                {
                                    var parsed = ParseSliderData(line);
                                    if (parsed.Count > 0)
                                    {
                                        var accumulated = new Dictionary<int, int>(parsed);
                                        var accDeadline = DateTime.UtcNow.AddMilliseconds(300);
                                        while (DateTime.UtcNow < accDeadline && !ct.IsCancellationRequested)
                                        {
                                            if (port.BytesToRead > 0)
                                            {
                                                var toRead2 = Math.Min(port.BytesToRead, rxBuffer.Length);
                                                var read2 = port.Read(rxBuffer, 0, toRead2);
                                                for (int j = 0; j < read2; j++)
                                                {
                                                    var ch2 = (char)rxBuffer[j];
                                                    if (ch2 is '\n' or '\r')
                                                    {
                                                        var line2 = lineBuffer.ToString().Trim();
                                                        lineBuffer.Clear();
                                                        if (!string.IsNullOrEmpty(line2) && line2.Contains('|'))
                                                        {
                                                            var more = ParseSliderData(line2);
                                                            foreach (var kvp in more)
                                                                accumulated[kvp.Key] = kvp.Value;
                                                        }
                                                    }
                                                    else lineBuffer.Append(ch2);
                                                }
                                            }
                                            else await Task.Delay(10, ct).ContinueWith(_ => { });
                                        }
                                        return (true, accumulated);
                                    }
                                }
                            }
                            else
                            {
                                lineBuffer.Append(ch);
                            }
                        }
                    }
                    else
                    {
                        await Task.Delay(10, ct).ContinueWith(_ => { });
                    }
                }
            }
        }
        catch (Exception ex)
        {
            _logger.LogDebug("Verification error: {Error}", ex.Message);
        }

        return (identified, null);
    }

    private async Task ReadLoopAsync(CancellationToken ct)
    {
        _logger.LogDebug("Read loop started on {Port}", _lastKnownPort);

        var lineBuffer = new StringBuilder();
        var rxBuffer = new byte[256];

        try
        {
            while (!ct.IsCancellationRequested && _isConnected && _port?.IsOpen == true)
            {
                try
                {
                    if (_port!.BytesToRead > 0)
                    {
                        var toRead = Math.Min(_port.BytesToRead, rxBuffer.Length);
                        var read = _port.Read(rxBuffer, 0, toRead);

                        for (int i = 0; i < read; i++)
                        {
                            var ch = (char)rxBuffer[i];
                            if (ch is '\n' or '\r')
                            {
                                var line = lineBuffer.ToString().Trim();
                                lineBuffer.Clear();
                                if (!string.IsNullOrEmpty(line))
                                    await ProcessLineAsync(line, ct);
                            }
                            else
                            {
                                lineBuffer.Append(ch);
                                if (lineBuffer.Length > 1024) lineBuffer.Clear();
                            }
                        }
                    }
                    else
                    {
                        await Task.Delay(ReadIntervalMs, ct).ContinueWith(_ => { });
                    }
                }
                catch (OperationCanceledException) { break; }
                catch (Exception ex)
                {
                    _logger.LogWarning(ex, "Read error — disconnecting");
                    break;
                }
            }
        }
        finally
        {
            await HandleDisconnectionAsync();
        }
    }

    private async Task ProcessLineAsync(string line, CancellationToken ct)
    {
        var parts = line.Split('|');
        if (parts.Length < 2) return;

        if (parts[0].Length == 1 &&
            parts[0][0] is >= 'A' and <= 'E' &&
            int.TryParse(parts[1].Trim(), out var state))
        {
            await _hubContext.Clients.All.SendAsync(
                "ButtonEventReceived",
                new { buttonId = parts[0], state },
                ct);
            return;
        }

        var sliderData = ParseSliderData(line);
        if (sliderData.Count > 0)
        {
            _lastKnownHardwareValues ??= new Dictionary<int, int>();
            foreach (var kvp in sliderData)
                _lastKnownHardwareValues[kvp.Key] = kvp.Value;

            await _hubContext.Clients.All.SendAsync("SliderDataReceived", sliderData, ct);
        }
    }

    private static Dictionary<int, int> ParseSliderData(string data)
    {
        var result = new Dictionary<int, int>();
        var parts = data.Split('|');

        for (int i = 0; i + 1 < parts.Length; i += 2)
        {
            if (int.TryParse(parts[i].Trim(), out var id) &&
                int.TryParse(parts[i + 1].Trim(), out var value) &&
                id is >= 0 and <= 7)
            {
                result[id] = value;
            }
        }

        return result;
    }

    public async Task<bool> SendCommandAsync(string command)
    {
        if (!_isConnected || _port?.IsOpen != true)
        {
            _logger.LogWarning("Cannot send command — device not connected");
            return false;
        }

        await _writeLock.WaitAsync();
        try
        {
            // Mirror the "0" prefix prepended by SerialWorker._sendToDevice
            var data = Encoding.ASCII.GetBytes("0" + command);
            _port!.Write(data, 0, data.Length);
            _port.BaseStream.Flush();
            return true;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to send command — disconnecting");
            _ = HandleDisconnectionAsync();
            return false;
        }
        finally
        {
            _writeLock.Release();
        }
    }

    private async Task HandleDisconnectionAsync(bool notify = true)
    {
        if (!_isConnected && _port == null) return;

        var wasConnected = _isConnected;
        _isConnected = false;

        _logger.LogInformation("Device disconnected from {Port}", _lastKnownPort);

        try { _port?.Close(); _port?.Dispose(); }
        catch { }
        _port = null;

        if (wasConnected && notify)
            await _hubContext.Clients.All.SendAsync("DeviceConnectionChanged", false);
    }

    public override void Dispose()
    {
        _port?.Close();
        _port?.Dispose();
        _writeLock.Dispose();
        base.Dispose();
    }
}
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:signalr_netcore/signalr_client.dart';

class DeviceServiceClient {
  static const String _baseUrl = 'http://localhost:8765';
  static const String _hubUrl = '$_baseUrl/hub/device';

  late HubConnection _hubConnection;
  bool _deviceConnected = false;
  bool _serviceConnected = false;

  final _sliderDataController = StreamController<Map<int, int>>.broadcast();
  final _buttonDataController = StreamController<Map<String, int>>.broadcast();
  final _connectionStateController = StreamController<bool>.broadcast();
  final _initialHardwareValuesController =
      StreamController<Map<int, int>>.broadcast();
  final _rawDataController = StreamController<String>.broadcast();

  Stream<Map<int, int>> get sliderData => _sliderDataController.stream;
  Stream<Map<String, int>> get buttonData => _buttonDataController.stream;
  Stream<bool> get connectionState => _connectionStateController.stream;
  Stream<Map<int, int>> get initialHardwareValues =>
      _initialHardwareValuesController.stream;
  Stream<String> get rawData => _rawDataController.stream;

  bool get isDeviceConnected => _deviceConnected;

  // NOISE MITIGATION SYSTEM
  static const Duration _bypassHoldDuration = Duration(milliseconds: 600);

  double _noiseThreshold = 20.0;
  final Map<int, double> _noiseLastApplied = {};
  final Map<int, bool> _noiseBypassed = {};
  final Map<int, double> _noiseBypassAnchor = {};
  final Map<int, Timer> _noiseBypassTimers = {};

  set noiseThreshold(double value) => _noiseThreshold = value;

  void seedNoiseBaseline(Map<int, int> hardwareValues) {
    hardwareValues.forEach((id, raw) {
      _noiseLastApplied[id] = raw.toDouble();
    });
  }

  bool _noiseGate(int id, double value) {
    if (_noiseThreshold <= 0) return true;

    final last = _noiseLastApplied[id];

    if (_noiseBypassed[id] == true) {
      // allow full data flow during bypass period
      _noiseLastApplied[id] = value;

      // extend bypass period if slider is being adjusted
      final anchor = _noiseBypassAnchor[id] ?? value;
      if ((value - anchor).abs() >= _noiseThreshold) {
        _noiseBypassAnchor[id] = value;
        _resetBypassTimer(id);
      }

      return true;
    }

    if (last == null || (value - last).abs() >= _noiseThreshold) {
      _noiseLastApplied[id] = value;
      _noiseBypassed[id] = true;
      _noiseBypassAnchor[id] = value;
      _resetBypassTimer(id);
      return true;
    }

    return false;
  }

  void _resetBypassTimer(int id) {
    _noiseBypassTimers[id]?.cancel();
    _noiseBypassTimers[id] = Timer(_bypassHoldDuration, () {
      _noiseBypassed[id] = false;
      _noiseBypassAnchor.remove(id);
      // _noiseLastApplied[id] already holds the settled value - no update needed.
      print('[DeviceServiceClient] Noise gate re-engaged for slider $id '
          '(settled at ${_noiseLastApplied[id]?.toStringAsFixed(0)})');
    });
  }

  Future<void> connect() async {
    _hubConnection = HubConnectionBuilder()
        .withUrl(_hubUrl)
        .withAutomaticReconnect()
        .build();

    _hubConnection.on('SliderDataReceived', _onSliderData);
    _hubConnection.on('ButtonEventReceived', _onButtonEvent);
    _hubConnection.on('DeviceConnectionChanged', _onConnectionChanged);
    _hubConnection.on('InitialHardwareValues', _onInitialHardwareValues);

    _hubConnection.onclose(({Exception? error}) {
      _serviceConnected = false;
      print('[DeviceServiceClient] SignalR closed: $error');
    });
    _hubConnection.onreconnecting(({Exception? error}) {
      _serviceConnected = false;
    });
    _hubConnection.onreconnected(({String? connectionId}) {
      _serviceConnected = true;
    });

    await _hubConnection.start();
    _serviceConnected = true;
    print('[DeviceServiceClient] Connected to device hub');

    await _syncInitialDeviceStatus();
  }

  Future<void> _syncInitialDeviceStatus() async {
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/api/device/status'))
          .timeout(const Duration(seconds: 2));

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        if (body['success'] == true) {
          final data = body['data'] as Map<String, dynamic>;
          final isConnected = data['isConnected'] as bool? ?? false;
          _deviceConnected = isConnected;
          _connectionStateController.add(_deviceConnected);
          print(
              '[DeviceServiceClient] Initial device status: connected=$_deviceConnected');
        }
      }
    } catch (e) {
      print('[DeviceServiceClient] Could not sync initial device status: $e');
    }
  }

  void _onSliderData(List<Object?>? args) {
    if (args == null || args.isEmpty) return;
    try {
      final raw = Map<String, dynamic>.from(args[0] as Map);
      final all = raw.map((k, v) => MapEntry(int.parse(k), (v as num).toInt()));

      // Raw stream: always forward unfiltered (used by the terminal debug window)
      _rawDataController.add(raw.toString());

      // apply noise gate for sliders
      final filtered = Map<int, int>.fromEntries(
        all.entries.where((e) => _noiseGate(e.key, e.value.toDouble())),
      );

      if (filtered.isNotEmpty) {
        _sliderDataController.add(filtered);
      }
    } catch (e) {
      print('[DeviceServiceClient] Error parsing slider data: $e');
    }
  }

  void _onButtonEvent(List<Object?>? args) {
    if (args == null || args.isEmpty) return;
    try {
      final data = Map<String, dynamic>.from(args[0] as Map);
      final buttonId = data['buttonId'] as String;
      final state = (data['state'] as num).toInt();
      _buttonDataController.add({buttonId: state});
    } catch (e) {
      print('[DeviceServiceClient] Error parsing button event: $e');
    }
  }

  void _onConnectionChanged(List<Object?>? args) {
    if (args == null || args.isEmpty) return;
    _deviceConnected = args[0] as bool;
    _connectionStateController.add(_deviceConnected);
    print('[DeviceServiceClient] Device connected: $_deviceConnected');
  }

  void _onInitialHardwareValues(List<Object?>? args) {
    if (args == null || args.isEmpty) return;
    try {
      final raw = Map<String, dynamic>.from(args[0] as Map);
      final values =
          raw.map((k, v) => MapEntry(int.parse(k), (v as num).toInt()));
      print('[DeviceServiceClient] Initial hardware values: $values');
      _initialHardwareValuesController.add(values);
    } catch (e) {
      print('[DeviceServiceClient] Error parsing hardware values: $e');
    }
  }

  Future<Map<int, int>?> requestInitialHardwareValues() async {
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/api/device/hardware-values'))
          .timeout(const Duration(seconds: 3));

      if (response.statusCode != 200) return null;
      final body = jsonDecode(response.body);
      if (body['success'] != true || body['data'] == null) return null;

      final raw = Map<String, dynamic>.from(body['data'] as Map);
      return raw.map((k, v) => MapEntry(int.parse(k), (v as num).toInt()));
    } catch (e) {
      print('[DeviceServiceClient] requestInitialHardwareValues error: $e');
      return null;
    }
  }

  Future<void> sendCommand(String command) async {
    if (!_deviceConnected) {
      print('[DeviceServiceClient] Cannot send command - device not connected');
      return;
    }
    try {
      await http.post(
        Uri.parse('$_baseUrl/api/device/command'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'command': command}),
      );
    } catch (e) {
      print('[DeviceServiceClient] sendCommand error: $e');
    }
  }

  Future<void> dispose() async {
    for (final t in _noiseBypassTimers.values) t.cancel();
    _noiseBypassTimers.clear();

    try {
      await _hubConnection.stop();
    } catch (_) {}
    await _sliderDataController.close();
    await _buttonDataController.close();
    await _connectionStateController.close();
    await _initialHardwareValuesController.close();
    await _rawDataController.close();
  }
}

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_libserialport/flutter_libserialport.dart'
    show SerialPort, SerialPortConfig, SerialPortParity;
import 'package:mixlit/backend/application/ConfigManager.dart';
import 'package:mixlit/backend/serial/SerialPortReader.dart'
    show SerialPortReader;

class SerialConnectionManager {
  static const int BAUD_RATE = 115200;
  static const int SCAN_TIMEOUT_MS = 200;
  static const String DEVICE_IDENTIFIER = "mixlit";
  static Uint8List DEVICE_IDENTIFICATION_REQUEST =
      Uint8List.fromList('?\n'.codeUnits);
  static const int DEVICE_IDENTIFICATION_RESPONSE_TIMEOUT = 200;

  SerialPort? _port;
  SerialPortReader? _reader;
  bool _isConnected = false;
  bool _isInitializing = false;
  Timer? _reconnectTimer;
  String? _lastKnownPort;
  StreamSubscription? _readerSubscription;

  Timer? _connectionHealthCheckTimer;
  int _connectionHealthCheckFailures = 0;
  static const int MAX_CONNECTION_HEALTH_FAILURES = 3;

  final StreamController<bool> _connectionStateController;
  final void Function(List<int>) onDataReceived;
  final void Function(dynamic) onError;

  final ConfigManager _configManager = ConfigManager.instance;

  final _portConfig = SerialPortConfig()
    ..baudRate = BAUD_RATE
    ..bits = 8
    ..parity = SerialPortParity.none
    ..stopBits = 1
    ..xonXoff = 0
    ..rts = 1
    ..cts = 0
    ..dsr = 0
    ..dtr = 1;

  Completer<void> _initCompleter = Completer<void>();
  Future<void> get initialized => _initCompleter.future;

  SerialConnectionManager({
    required StreamController<bool> connectionStateController,
    required this.onDataReceived,
    required this.onError,
  }) : _connectionStateController = connectionStateController {
    Future.delayed(Duration(milliseconds: 100), () {
      _initializeConnection();
    });
  }

  void _startConnectionHealthCheck() {
    _connectionHealthCheckTimer?.cancel();

    _connectionHealthCheckTimer = Timer.periodic(
        const Duration(seconds: 1), (_) => _checkConnectionHealth());
  }

  Future<void> _checkConnectionHealth() async {
    if (!_isConnected || _port == null || !_port!.isOpen) {
      await _handleDisconnection();
      return;
    }

    try {
      final healthCheckSuccessful = await _performDeviceHealthCheck();

      if (!healthCheckSuccessful) {
        _connectionHealthCheckFailures++;

        if (_connectionHealthCheckFailures >= MAX_CONNECTION_HEALTH_FAILURES) {
          print(
              'Device health check failed multiple times. Triggering disconnection.');
          await _handleDisconnection();
        }
      } else {
        _connectionHealthCheckFailures = 0;
      }
    } catch (e) {
      print('Connection health check error: $e');
      _connectionHealthCheckFailures++;

      if (_connectionHealthCheckFailures >= MAX_CONNECTION_HEALTH_FAILURES) {
        await _handleDisconnection();
      }
    }
  }

  Future<bool> _performDeviceHealthCheck() async {
    if (_port == null || !_port!.isOpen) return false;

    try {
      _port!.write(DEVICE_IDENTIFICATION_REQUEST);
      _port!.flush();

      await Future.delayed(const Duration(milliseconds: 200));

      return _port!.isOpen;
    } catch (e) {
      print('Device health check failed: $e');
      return false;
    }
  }

  Stream<bool> get connectionState => _connectionStateController.stream;
  bool get isConnected => _isConnected;

  Future<void> _initializeConnection() async {
    if (_isInitializing) return;
    _isInitializing = true;

    try {
      print('Starting serial port initialization...');

      _lastKnownPort = await _configManager.getLastComPort();
      print('Retrieved last known port from config: $_lastKnownPort');

      if (_lastKnownPort != null) {
        try {
          print('Attempting to connect to last known port: $_lastKnownPort');
          final port = SerialPort(_lastKnownPort!);

          if (!port.openReadWrite()) {
            print('Failed to open $_lastKnownPort for read/write');
            _lastKnownPort = null;
          } else {
            try {
              port.config = _portConfig;
              await Future.delayed(const Duration(milliseconds: 100));
              port.flush();
            } catch (e) {
              print('Error configuring port: $e');
              _lastKnownPort = null;
              if (port.isOpen) port.close();
            }

            if (_lastKnownPort != null) {
              if (await _verifyDevice(port)) {
                print('Device verified on port: $_lastKnownPort');
                await _establishConnection(port);
                _isInitializing = false;
                if (!_initCompleter.isCompleted) _initCompleter.complete();
                return;
              } else {
                print('Device verification failed on port: $_lastKnownPort');
                if (port.isOpen) port.close();
                _lastKnownPort = null;
              }
            }
          }
        } catch (e) {
          print('Failed to reconnect to last known port: $e');
          _lastKnownPort = null;
        }
      }

      await _scanAndConnect();
    } catch (e) {
      print('Error during initialization: $e');
      _startReconnectionTimer();
    } finally {
      _isInitializing = false;
      if (!_initCompleter.isCompleted) _initCompleter.complete();
    }
  }

  Future<void> _scanAndConnect() async {
    print('Starting device scan...');
    final availablePorts = SerialPort.availablePorts;
    print('Available ports: $availablePorts');

    if (availablePorts.isEmpty) {
      print('No serial ports available');
      _startReconnectionTimer();
      return;
    }

    try {
      await _cleanupExistingConnection();

      for (final portName in availablePorts) {
        print('Attempting to connect to $portName...');
        final result = await _attemptConnection(portName);

        if (result != null) {
          _lastKnownPort = portName;
          print('Found device on port: $_lastKnownPort');

          await _configManager.saveLastComPort(portName);

          await _establishConnection(result);
          return;
        }
      }

      print('No MixLit device found on any available port');
      _startReconnectionTimer();
    } catch (e) {
      print('Error during port scanning: $e');
      _startReconnectionTimer();
    }
  }

  Future<bool> _verifyDevice(SerialPort port) async {
    if (!port.isOpen) return false;

    final completer = Completer<bool>();
    Timer? timeoutTimer;
    SerialPortReader? verificationReader;
    StreamSubscription? subscription;

    try {
      print('Verifying device on port ${port.name}...');
      port.flush();
      await Future.delayed(const Duration(milliseconds: 50));

      verificationReader = SerialPortReader(port);

      subscription = verificationReader.stream.listen(
        (data) {
          try {
            final response = String.fromCharCodes(data).trim();
            print('Received verification response: "$response"');
            if (response.contains(DEVICE_IDENTIFIER) &&
                !completer.isCompleted) {
              print('Device identified as a MixLit - yippee!');
              completer.complete(true);
            }
          } catch (e) {
            print('Error processing verification data: $e');
          }
        },
        onError: (error) {
          print('Verification stream error: $error');
          if (!completer.isCompleted) completer.complete(false);
        },
        cancelOnError: false,
      );

      for (var i = 0; i < 3 && !completer.isCompleted; i++) {
        print('Sending verification request attempt ${i + 1}...');
        port.write(Uint8List.fromList('?\n'.codeUnits));
        port.flush();
        await Future.delayed(const Duration(milliseconds: 200));
      }

      timeoutTimer = Timer(const Duration(milliseconds: 2000), () {
        if (!completer.isCompleted) {
          print('Verification timed out');
          completer.complete(false);
        }
      });

      final result = await completer.future;
      print('Verification result: ${result ? "success" : "failed"}');
      return result;
    } catch (e) {
      print('Exception during verification: $e');
      return false;
    } finally {
      timeoutTimer?.cancel();
      await subscription?.cancel();
      await verificationReader?.dispose();
    }
  }

  Future<void> _setupPortReader() async {
    if (_port == null || !_port!.isOpen) {
      print('Port not ready for reader setup');
      return;
    }

    await _readerSubscription?.cancel();
    await _reader?.dispose();

    try {
      _reader = SerialPortReader(_port!);

      _readerSubscription = _reader!.stream.listen(
        onDataReceived,
        onError: (error) {
          print('Reader error: $error');
          onError(error);
          _handleDisconnection();
        },
        cancelOnError: false,
      );
    } catch (e, stack) {
      print('Error setting up port reader: $e');
      print('Stack trace: $stack');
      rethrow;
    }
  }

  Future<void> _handleDisconnection({bool notify = true}) async {
    final wasConnected = _isConnected;
    _isConnected = false;
    _isInitializing = false;

    try {
      await _readerSubscription?.cancel();
      _readerSubscription = null;

      await _reader?.dispose();
      _reader = null;

      if (_port?.isOpen ?? false) {
        try {
          _port!.flush();
          _port!.close();
        } catch (e) {
          print('Error closing port: $e');
        }
      }
      _port = null;
    } catch (e) {
      print('Error during disconnection cleanup: $e');
    } finally {
      if (wasConnected && notify) {
        _connectionStateController.add(false);
        print('Device disconnected, starting continuous port scanning...');
        _startReconnectionTimer();
      }
    }
  }

  Future<void> dispose() async {
    print('Disposing SerialConnectionManager...');
    _reconnectTimer?.cancel();
    _connectionHealthCheckTimer?.cancel();
    await _handleDisconnection();
    await _readerSubscription?.cancel();
    await _reader?.dispose();
    print('SerialConnectionManager disposal complete');
  }

  Future<void> _cleanupExistingConnection() async {
    try {
      await _handleDisconnection(notify: false);
      await Future.delayed(const Duration(milliseconds: 100));
    } catch (e) {
      print('Error cleaning up existing connection: $e');
    }
  }

  Future<SerialPort?> _attemptConnection(String portName) async {
    print('Attempting connection on port: $portName');
    SerialPort? port;
    bool verificationSuccess = false;

    try {
      port = SerialPort(portName);

      if (port.isOpen) {
        port.close();
        await Future.delayed(const Duration(milliseconds: 100));
      }

      if (!port.openReadWrite()) {
        print('Failed to open $portName for read/write');
        return null;
      }

      try {
        port.config = _portConfig;
        await Future.delayed(const Duration(milliseconds: 100));
        port.flush();
      } catch (e) {
        print('Error configuring port: $e');
        return null;
      }

      verificationSuccess = await _verifyDevice(port);
      return verificationSuccess ? port : null;
    } catch (e) {
      print('Error during connection attempt: $e');
      return null;
    } finally {
      if (port != null && port.isOpen && !verificationSuccess) {
        try {
          port.close();
        } catch (e) {
          print('Error closing port: $e');
        }
      }
    }
  }

  void _startReconnectionTimer() {
    print('Starting reconnection timer...');
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) async {
        if (!_isConnected && !_isInitializing) {
          await _scanAndConnect();
        }
      },
    );
  }

  Future<void> _establishConnection(SerialPort port) async {
    if (_isConnected) return;

    try {
      _port = port;
      _port!.config = _portConfig;

      _isConnected = true;
      _connectionStateController.add(true);
      _reconnectTimer?.cancel();

      _connectionHealthCheckFailures = 0;
      _startConnectionHealthCheck();

      await _setupPortReader();
      print('Connection established successfully on port: ${_lastKnownPort}');

      if (_lastKnownPort != null) {
        await _configManager.saveLastComPort(_lastKnownPort!);
      }
    } catch (e) {
      print('Error establishing connection: $e');
      await _handleDisconnection();
    }
  }

  Future<bool> writeToPort(List<int> data) async {
    if (!isConnected || _port == null || !_port!.isOpen) {
      print('Cannot write to port: Not connected');
      return false;
    }

    try {
      _port!.write(Uint8List.fromList(data));
      _port!.flush();
      return true;
    } catch (e) {
      print('Error writing to port: $e');
      _handleDisconnection();
      return false;
    }
  }
}

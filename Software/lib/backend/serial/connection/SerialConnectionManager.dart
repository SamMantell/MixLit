import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_libserialport/flutter_libserialport.dart'
    show SerialPort, SerialPortConfig, SerialPortParity;
import 'package:mixlit/backend/serial/SerialPortReader.dart'
    show SerialPortReader;

class SerialConnectionManager {
  static const int BAUD_RATE = 115200;
  static const int SCAN_TIMEOUT_MS = 6000;
  static const String DEVICE_IDENTIFIER = "mixlit";

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

  // Port configuration
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

  SerialConnectionManager({
    required StreamController<bool> connectionStateController,
    required this.onDataReceived,
    required this.onError,
  }) : _connectionStateController = connectionStateController {
    _initializeConnection();
  }

  void _startConnectionHealthCheck() {
    _connectionHealthCheckTimer?.cancel();

    // timer for checking connection status
    _connectionHealthCheckTimer = Timer.periodic(
        const Duration(seconds: 1), (_) => _checkConnectionHealth());
  }

  Future<void> _checkConnectionHealth() async {
    if (!_isConnected || _port == null || !_port!.isOpen) {
      await _handleDisconnection();
      return;
    }

    try {
      // Perform a simple health check
      // This could be a device-specific verification method
      final healthCheckSuccessful = await _performDeviceHealthCheck();

      if (!healthCheckSuccessful) {
        _connectionHealthCheckFailures++;

        if (_connectionHealthCheckFailures >= MAX_CONNECTION_HEALTH_FAILURES) {
          print(
              'Device health check failed multiple times. Triggering disconnection.');
          await _handleDisconnection();
        }
      } else {
        // Reset failure counter on successful health check
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
      // Send a verification request
      _port!.write(Uint8List.fromList('?\n'.codeUnits));
      _port!.flush();

      // Wait for a short time to allow for a response
      await Future.delayed(const Duration(milliseconds: 200));

      // You might want to add more specific verification logic here
      // For example, check if the port is still responsive or if a specific response is received
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
      if (_lastKnownPort != null) {
        try {
          final port = SerialPort(_lastKnownPort!);
          if (await _verifyDevice(port)) {
            await _establishConnection(port);
            _isInitializing = false;
            return;
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
          await _establishConnection(result);
          return; // Exit after successful connection
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
      port.flush();
      await Future.delayed(const Duration(milliseconds: 50));

      verificationReader = SerialPortReader(port);

      subscription = verificationReader.stream.listen(
        (data) {
          try {
            final response = String.fromCharCodes(data).trim();
            if (response.contains(DEVICE_IDENTIFIER) &&
                !completer.isCompleted) {
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

      // Send multiple verification attempts
      for (var i = 0; i < 3 && !completer.isCompleted; i++) {
        port.write(Uint8List.fromList('?\n'.codeUnits));
        port.flush();
        await Future.delayed(const Duration(milliseconds: 200));
      }

      timeoutTimer = Timer(const Duration(milliseconds: 2000), () {
        if (!completer.isCompleted) completer.complete(false);
      });

      return await completer.future;
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
    _lastKnownPort = null;

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
    _reconnectTimer?.cancel();
    await _handleDisconnection();
    await _readerSubscription?.cancel();
    await _reader?.dispose();
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
      print('Connection established successfully');
    } catch (e) {
      print('Error establishing connection: $e');
      await _handleDisconnection();
    }
  }
}

import 'dart:async';
import 'dart:typed_data';
import 'dart:isolate';
import 'package:flutter_libserialport/flutter_libserialport.dart';

class SerialWorker {
  static const int BAUD_RATE = 115200;
  static const int SCAN_TIMEOUT_MS = 6000;
  static const String DEVICE_IDENTIFIER = "mixlit";
  static const String DEBUG_PORT = "COM20";
  
  SerialPort? _port;
  SerialPortReader? _reader;
  bool _isConnected = false;
  bool _isListening = false;
  Timer? _reconnectTimer;
  Isolate? _dataProcessingIsolate;
  ReceivePort? _receivePort;
  SendPort? _isolateSendPort;
  String? _lastKnownPort;
  
  final _sliderDataController = StreamController<Map<int, int>>.broadcast();
  final _rawDataController = StreamController<String>.broadcast();
  final _connectionStateController = StreamController<bool>.broadcast();
  
  Stream<Map<int, int>> get sliderData => _sliderDataController.stream;
  Stream<String> get rawData => _rawDataController.stream;
  Stream<bool> get connectionState => _connectionStateController.stream;
  
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

  SerialWorker() {
    _initializeConnection();
  }

  Future<void> _initializeConnection() async {
    if (_lastKnownPort != null) {
      try {
        final port = SerialPort(_lastKnownPort!);
        if (await _verifyDevice(port)) {
          await _establishConnection(port);
          return;
        }
      } catch (e) {
        print('Failed to reconnect to last known port: $e');
        _lastKnownPort = null;
      }
    }

    // if last known port failed, scan all available ports
    await _scanAndConnect();
  }

  Future<void> _scanAndConnect() async {
    print('Starting device scan...');
    
    // arduino moment pt2
    await Future.delayed(Duration(milliseconds: 500));
    
    if (!SerialPort.availablePorts.contains(DEBUG_PORT)) {
      print('DEBUG: COM20 is not available!');
      print('Available ports: ${SerialPort.availablePorts}');
      return;
    }

    try {
      // yeet any existing connections
      await _cleanupExistingConnection();
      
      print('Attempting to connect to $DEBUG_PORT...');
      final result = await _attemptConnection(DEBUG_PORT);
      
      if (result != null) {
        final port = result;
        _lastKnownPort = DEBUG_PORT;
        await _establishConnection(port);
      } else {
        print('No MixLit device found on $DEBUG_PORT');
        _startReconnectionTimer();
      }
    } catch (e) {
      print('Error during port scanning: $e');
      _startReconnectionTimer();
    }
  }

  Future<void> _cleanupExistingConnection() async {
    if (_port != null) {
      try {
        if (_port!.isOpen) {
          _port!.flush();
          _port!.close();
        }
        _port = null;
      } catch (e) {
        print('Error cleaning up existing port: $e');
      }
    }
    
    // the fuck is wrong with arduino and why does this fix my nightmares
    await Future.delayed(Duration(milliseconds: 100));
  }

  Future<SerialPort?> _attemptConnection(String portName) async {
  print('Attempting connection on port: $portName');
  SerialPort? port;
  bool verificationSuccess = false;
  
  try {
    // Create port instance
    port = SerialPort(portName);
    print('Created SerialPort instance for $portName');
    
    // Ensure port is closed before we start
    if (port.isOpen) {
      print('Port was already open, closing first');
      port.close();
      await Future.delayed(Duration(milliseconds: 100));
    }

    // Open port
    if (!port.openReadWrite()) {
      print('Failed to open $portName for read/write');
      return null;
    }
    
    print('Successfully opened $portName for read/write');
    
    // Configure port
    try {
      port.config = _portConfig;
      await Future.delayed(Duration(milliseconds: 100));
      port.flush();
      print('Port configured successfully');
    } catch (e) {
      print('Error configuring port: $e');
      return null;
    }

    // Verify device
    verificationSuccess = await _verifyDevice(port);
    if (verificationSuccess) {
      print('Device verified successfully on $portName');
      return port;
    } else {
      print('Device verification failed on $portName');
      return null;
    }
  } catch (e) {
    print('Error during connection attempt: $e');
    return null;
  } finally {
    // close port if verification failed
    if (port != null && port.isOpen && !verificationSuccess) {
      try {
        port.close();
        print('Closed port $portName after failed verification');
      } catch (e) {
        print('Error closing port: $e');
      }
    }
  }
}

  Future<(String, SerialPort)?> _scanPort(String portName) async {
    print('Scanning port: $portName');
    SerialPort? port;
    
    try {
      port = SerialPort(portName);
      print('Created SerialPort instance for $portName');
      
      if (!port.openReadWrite()) {
        print('Failed to open $portName for read/write');
        return null;
      }
      
      print('Successfully opened $portName for read/write');
      
      if (await _verifyDevice(port)) {
        print('Device verified on $portName');
        return (portName, port);
      } else {
        print('Device verification failed on $portName');
      }
    } catch (e) {
      print('Error scanning port $portName: $e');
    } finally {
      if (port != null && port.isOpen) {
        try {
          port.close();
          print('Closed port $portName after scanning');
        } catch (e) {
          print('Error closing port during scan: $e');
        }
      }
    }
    return null;
  }


  Future<bool> _verifyDevice(SerialPort port) async {
    print('Starting device verification for Arduino...');
    
    if (!port.isOpen) {
      print('Port is not open for verification');
      return false;
    }
    
    try {
      final completer = Completer<bool>();
      Timer? timeoutTimer;
      SerialPortReader? verificationReader;
      StreamSubscription? subscription;
      
      // clear existing buffer data
      port.flush();
      await Future.delayed(Duration(milliseconds: 50));
      
      print('Setting up verification reader...');
      verificationReader = SerialPortReader(port, timeout: 50);
      
      print('Setting up verification subscription...');
      subscription = verificationReader.stream.listen(
        (data) {
          try {
            final response = String.fromCharCodes(data).trim();
            print('Raw data received: ${data.length} bytes');
            print('Decoded response: "$response"');
            
            if (response.contains("mixlit") && !completer.isCompleted) {
              print('Found MixLit device');
              completer.complete(true);
            }
          } catch (e) {
            print('Error processing response data: $e');
          }
        },
        onError: (error) {
          print('Stream error during verification: $error');
          if (!completer.isCompleted) {
            completer.complete(false);
          }
        },
        cancelOnError: false,
      );

      // query with increased delays between attempts
      for (var i = 0; i < 3; i++) {
        if (completer.isCompleted) break;
        print('Sending query attempt ${i + 1}...');
        port.write(Uint8List.fromList('?\n'.codeUnits));
        port.flush();
        await Future.delayed(Duration(milliseconds: 200));
      }

      // timeout timer with longer duration
      timeoutTimer = Timer(Duration(milliseconds: 2000), () {
        if (!completer.isCompleted) {
          print('Verification timed out.');
          completer.complete(false);
        }
      });

      try {
        final result = await completer.future;
        print('Verification completed with result: $result');
        return result;
      } finally {
        timeoutTimer.cancel();
        await subscription.cancel();
         verificationReader.close();
      }
    } catch (e) {
      print('Exception during verification: $e');
      return false;
    }
  }

  void _startReconnectionTimer() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) {
        if (!_isConnected) _initializeConnection();
      },
    );
  }

  Future<void> _establishConnection(SerialPort port) async {
    if (_isConnected) return;
    
    try {
      _port = port;
      _port!.config = _portConfig;
      
      await _initializeDataProcessing();
      await _setupPortReader();
      
      _isConnected = true;
      _connectionStateController.add(true);
      _reconnectTimer?.cancel();
      
      print('Connection established successfully');
    } catch (e) {
      print('Error establishing connection: $e');
      await _handleDisconnection();
    }
  }

  Future<void> _initializeDataProcessing() async {
  print('Starting data processing initialization');
  _receivePort?.close();
  _receivePort = ReceivePort();
  
  final errorPort = ReceivePort();
  final completer = Completer<void>();
  
  void handleError(error) {
    print('Isolate error: $error');
    _handleDisconnection();
  }
  
  errorPort.listen(handleError);
  
  _receivePort!.listen((message) {
    print('Received message in main isolate: $message');
    if (message is SendPort) {
      print('Received SendPort from isolate');
      _isolateSendPort = message;
      if (!completer.isCompleted) completer.complete();
    } else if (message is Map<int, int>) {
      print('Received slider data: $message');
      _sliderDataController.add(message);
    } else if (message is String) {
      print('Received raw data: $message');
      _rawDataController.add(message);
    } else {
      print('Received unknown message type: ${message.runtimeType}');
    }
  });
  
  try {
    print('Spawning isolate...');
    _dataProcessingIsolate = await Isolate.spawn(
      _processDataIsolate,
      _receivePort!.sendPort,
      onError: errorPort.sendPort,
      errorsAreFatal: true,
    );
    
    print('Waiting for isolate initialization...');
    await completer.future.timeout(
      const Duration(seconds: 1),
      onTimeout: () => throw TimeoutException('Isolate initialization timeout'),
    );
    print('Data processing initialization complete');
  } catch (e) {
    print('Error initializing data processing: $e');
    rethrow;
  }
}

  Future<void> _setupPortReader() async {
    if (_port == null || !_port!.isOpen) return;
    
    try {
      _reader?.close();
      await Future.delayed(Duration(milliseconds: 50));
      
      _reader = SerialPortReader(_port!, timeout: 100);
      _isListening = true;
      
      print('Setting up data processing subscription...');
      _reader!.stream.listen(
        (data) {
          if (data.isNotEmpty) {
            try {
              final response = String.fromCharCodes(data);
              print('Received data: "$response"');
              print('Forwarding to isolate for processing: ${data.length} bytes');
              
              if (_isolateSendPort != null) {
                _isolateSendPort!.send(data);
                
                // keep port alive by flushing
                _port?.flush();
              } else {
                print('Warning: isolateSendPort is null, data not forwarded');
              }
            } catch (e) {
              print('Error processing received data: $e');
            }
          }
        },
        onError: (error) {
          print('Serial port read error: $error');
          _handleDisconnection();
        },
        onDone: () {
          print('Serial port read stream closed');
          if (_port?.isOpen ?? false) {
            _handleDisconnection();
          }
        },
        cancelOnError: false,  // prevent premature cancellation
      );
      
      // keepalive timer
      Timer.periodic(Duration(milliseconds: 500), (timer) {
        if (!(_port?.isOpen ?? false)) {
          timer.cancel();
          return;
        }
        try {
          _port?.flush();
        } catch (e) {
          print('Error in keepalive flush: $e');
          timer.cancel();
          _handleDisconnection();
        }
      });
      
      print('Port reader setup complete');
    } catch (e) {
      print('Error setting up port reader: $e');
      rethrow;
    }
  }

  Future<void> _handleDisconnection() async {
    if (!_isConnected) return;
    
    _isConnected = false;
    _isListening = false;
    
    // close reader first
    try {
      _reader?.close();
    } catch (e) {
      print('Error closing reader: $e');
    }
    _reader = null;
    
    // then close port
    if (_port?.isOpen ?? false) {
      try {
        _port!.flush();
        _port!.close();
      } catch (e) {
        print('Error closing port: $e');
      }
    }
    _port = null;
    
    _dataProcessingIsolate?.kill();
    _dataProcessingIsolate = null;
    _receivePort?.close();
    _receivePort = null;
    _isolateSendPort = null;
    
    _connectionStateController.add(false);
    
    // delay before starting the reconnection timer
    await Future.delayed(Duration(seconds: 2));
    _startReconnectionTimer();
  }

  static void _processDataIsolate(SendPort mainSendPort) {
  final receivePort = ReceivePort();
  final buffer = StringBuffer();
  String? remainingData;
  
  print('Isolate: Starting data processing isolate');
  mainSendPort.send(receivePort.sendPort);
  
  receivePort.listen((data) {
    print('Isolate: Received data in isolate');
    if (data is! Uint8List) {
      print('Isolate: Received non-Uint8List data: ${data.runtimeType}');
      return;
    }
    
    try {
      print('Isolate: Processing ${data.length} bytes');
      
      if (remainingData != null) {
        print('Isolate: Adding remaining data: $remainingData');
        buffer.write(remainingData);
        remainingData = null;
      }

      final newData = String.fromCharCodes(data);
      print('Isolate: Decoded data: "$newData"');
      buffer.write(newData);
      final bufferedData = buffer.toString();
      print('Isolate: Buffer contents: "$bufferedData"');
      
      if (bufferedData.contains('\n')) {
        final lines = bufferedData.split('\n');
        print('Isolate: Processing ${lines.length} lines');
        
        for (var i = 0; i < lines.length - 1; i++) {
          final line = lines[i].trim();
          if (line.isNotEmpty) {
            print('Isolate: Processing line: "$line"');
            _parseAndSendData(line, mainSendPort);
          }
        }
        
        buffer.clear();
        if (!bufferedData.endsWith('\n')) {
          remainingData = lines.last;
          print('Isolate: Storing remaining data: "$remainingData"');
        }
      } else {
        print('Isolate: No newline found, waiting for more data');
      }
    } catch (e) {
      print('Isolate: Error processing data: $e');
      buffer.clear();
      remainingData = null;
    }
  });
}

  static void _parseAndSendData(String line, SendPort mainSendPort) {
  print('Isolate: Parsing line: "$line"');
  try {
    final sliderData = <int, int>{};
    final parts = line.split('|');
    print('Isolate: Split into ${parts.length} parts');
    
    for (var i = 0; i < parts.length - 1; i += 2) {
      try {
        final sliderId = int.parse(parts[i].trim());
        final sliderValue = int.parse(parts[i + 1].trim());
        print('Isolate: Parsed slider $sliderId = $sliderValue');
        sliderData[sliderId] = sliderValue;
      } catch (e) {
        print('Isolate: Error parsing slider data part: $e');
        continue;
      }
    }
    
    if (sliderData.isNotEmpty) {
      print('Isolate: Sending slider data: $sliderData');
      mainSendPort.send(sliderData);
    } else {
      print('Isolate: No valid slider data found');
    }
  } catch (e) {
    print('Isolate: Error in data parsing: $e');
  }
}

  Future<void> dispose() async {
    _reconnectTimer?.cancel();
    await _handleDisconnection();
    
    await _sliderDataController.close();
    await _rawDataController.close();
    await _connectionStateController.close();
  }
}
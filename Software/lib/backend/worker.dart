import 'dart:async';
import 'dart:typed_data';
import 'dart:isolate';
import 'package:flutter_libserialport/flutter_libserialport.dart';

class Worker {
  SerialPort? _serialPort;
  Timer? _readTimer;
  final _config = SerialPortConfig()
    ..baudRate = 115200
    ..bits = 8
    ..parity = SerialPortParity.none
    ..stopBits = 1
    ..xonXoff = 0
    ..rts = 1
    ..cts = 0
    ..dsr = 0
    ..dtr = 1;

  final StreamController<Map<int, int>> _sliderStreamController = StreamController.broadcast();
  final StreamController<String> _rawDataStreamController = StreamController.broadcast();
  final StreamController<bool> _connectionStreamController = StreamController.broadcast();
  Timer? _connectionCheckTimer;
  SendPort? _isolateSendPort;
  ReceivePort? _receivePort;
  Isolate? _isolate;
  bool deviceConnected = false;
  bool _isListening = false;
  
  Stream<Map<int, int>> get sliderStream => _sliderStreamController.stream;
  Stream<String> get rawDataStream => _rawDataStreamController.stream;
  Stream<bool> get connectionStream => _connectionStreamController.stream;

  Worker() {
    _startConnectionCheck();
  }

  Future<(String, SerialPort)?> _findDevicePort() async {
    final availablePorts = SerialPort.availablePorts;
    final completer = Completer<(String, SerialPort)?>();
    int checkedPorts = 0;
    
    if (availablePorts.isEmpty) {
      return null;
    }

    for (final portName in availablePorts) {
      try {
        final port = SerialPort(portName);
        if (port.openReadWrite()) {
          port.config = _config;
          port.flush();
          
          await Future.delayed(const Duration(milliseconds: 100));
          
          bool deviceFound = false;
          final buffer = List<int>.empty(growable: true);
          
          // Set up manual reading for device detection
          Timer.periodic(Duration(milliseconds: 50), (timer) async {
            if (deviceFound || !port.isOpen) {
              timer.cancel();
              return;
            }
            
            try {
              if (port.bytesAvailable > 0) {
                final bytes = port.read(port.bytesAvailable);
                if (bytes != null && bytes.isNotEmpty) {
                  buffer.addAll(bytes);
                  final responseStr = String.fromCharCodes(buffer).trim().toLowerCase();
                  
                  if (responseStr.contains("mixlit")) {
                    deviceFound = true;
                    timer.cancel();
                    
                    if (!completer.isCompleted) {
                      print("Found MixLit device on port: $portName");
                      completer.complete((portName, port));
                    }
                    return;
                  }
                }
              }
            } catch (e) {
              timer.cancel();
              port.close();
              if (!completer.isCompleted) {
                checkedPorts++;
                if (checkedPorts == availablePorts.length) {
                  completer.complete(null);
                }
              }
            }
          });

          // Send query command
          String str2 = '?';
          Uint8List uint8list2 = Uint8List.fromList(str2.codeUnits);
          port.write(uint8list2);
          port.flush();

          // Wait for response or timeout
          await Future.delayed(const Duration(milliseconds: 2000));
          
          if (!completer.isCompleted && !deviceFound) {
            port.close();
            checkedPorts++;
            if (checkedPorts == availablePorts.length) {
              completer.complete(null);
            }
          }
        }
      } catch (e) {
        print("Error with port $portName: $e");
        checkedPorts++;
        if (checkedPorts == availablePorts.length && !completer.isCompleted) {
          completer.complete(null);
        }
      }
    }

    return completer.future;
  }

  void _startConnectionCheck() {
    _checkConnection();
    _connectionCheckTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      _checkConnection();
    });
  }

  Future<void> _setupIsolate() async {
    if (_isolate != null) {
      _isolateSendPort = null;
      _receivePort?.close();
      _receivePort = null;
      _isolate?.kill();
      _isolate = null;
    }
    
    _receivePort = ReceivePort();
    final errorPort = ReceivePort();
    
    final completer = Completer<void>();
    
    _receivePort!.listen((message) {
      if (message is SendPort) {
        _isolateSendPort = message;
        if (!completer.isCompleted) completer.complete();
      } else if (message is Map<int, int>) {
        _sliderStreamController.add(message);
      } else if (message is String) {
        _rawDataStreamController.add(message);
      }
    });

    errorPort.listen((error) {
      print("Isolate error: $error");
      _cleanupConnection();
    });

    try {
      _isolate = await Isolate.spawn(
        _isolateEntry,
        _receivePort!.sendPort,
        debugName: 'SerialWorkerIsolate',
        errorsAreFatal: true,
        onError: errorPort.sendPort,
      );
      
      await completer.future.timeout(
        const Duration(seconds: 2),
        onTimeout: () {
          print("Isolate setup timed out");
          _cleanupConnection();
          throw TimeoutException("Isolate setup timed out");
        },
      );
    } catch (e) {
      print("Error setting up isolate: $e");
      _cleanupConnection();
      rethrow;
    }
  }

  Future<void> _initializePort() async {
    if (!_isListening && deviceConnected) {
      try {
        await Future.delayed(const Duration(milliseconds: 100));
        
        _serialPort?.config = _config;
        
        if (!(_serialPort?.isOpen ?? false)) {
          _serialPort?.openReadWrite();
        }
        
        String str2 = '?';
        Uint8List uint8list2 = Uint8List.fromList(str2.codeUnits);
        _serialPort?.write(uint8list2);
        _serialPort?.flush();

        await _setupIsolate();

        if (!_isListening) {
          // set up stream listening
          final reader = SerialPortReader(_serialPort!, timeout: 0);
          
          reader.stream.listen(
            (data) {
              if (data.isNotEmpty) {
                _isolateSendPort?.send(data);
              }
            },
            onError: (error) {
              print("Serial port error: $error");
              _cleanupConnection();
            },
            onDone: () {
              print("Serial port stream closed");
              _cleanupConnection();
            },
            cancelOnError: true,
          );
          
          _isListening = true;
        }
      } catch (e, stack) {
        print("Error in _initializePort: $e");
        print("Stack trace: $stack");
        _cleanupConnection();
      }
    }
  }

  void _startReading() {
    _readTimer?.cancel();
    _readTimer = Timer.periodic(const Duration(milliseconds: 1), (timer) {
      if (!_isListening || _serialPort == null || !(_serialPort?.isOpen ?? false)) {
        timer.cancel();
        _cleanupConnection();
        return;
      }

      try {
        final available = _serialPort!.bytesAvailable;
        if (available > 0) {
          final chunkSize = available > 1024 ? 1024 : available;
          final bytes = _serialPort!.read(chunkSize);
          if (bytes != null && bytes.isNotEmpty) {
            _isolateSendPort?.send(bytes);
          }
        }
      } catch (e) {
        print("Error reading from port: $e");
        timer.cancel();
        _cleanupConnection();
      }
    });
  }

  void _cleanupConnection() {
    _isListening = false;
    deviceConnected = false;
    
    _readTimer?.cancel();
    _readTimer = null;
    
    if (_serialPort?.isOpen ?? false) {
      try {
        _serialPort!.flush();
        _serialPort!.close();
      } catch (e) {
        print("Error closing serial port: $e");
      }
    }
    _serialPort = null;
    
    _isolateSendPort = null;
    _receivePort?.close();
    _receivePort = null;
    _isolate?.kill();
    _isolate = null;
    
    _connectionStreamController.add(false);
  }

  Future<void> _checkConnection() async {
    if (deviceConnected && _isListening) return;
    
    bool wasConnected = deviceConnected;
    try {
      print("Scanning for MixLit device...");
      final deviceInfo = await _findDevicePort();
      
      if (deviceInfo != null) {
        final (portName, port) = deviceInfo;
        _serialPort = port;
        deviceConnected = true;
        if (!wasConnected) {
          print("Successfully connected to device on port $portName");
          _connectionStreamController.add(true);
          await _initializePort();
        }
      } else {
        print("No MixLit device found");
        _cleanupConnection();
      }
    } catch (e, stackTrace) {
      print("Error connecting to device: $e");
      print("Stack trace: $stackTrace");
      _cleanupConnection();
    }
  }

  static void _isolateEntry(SendPort mainSendPort) {
    print("Isolate starting...");
    final buffer = StringBuffer();
    final receivePort = ReceivePort();
    String? remainingData;

    // Send port immediately to prevent timeout
    mainSendPort.send(receivePort.sendPort);
    print("Isolate sent SendPort");

    receivePort.listen((data) {
      if (data is Uint8List) {
        try {
          // Append any remaining data from previous processing
          if (remainingData != null) {
            buffer.write(remainingData);
            remainingData = null;
          }

          String dataString = String.fromCharCodes(data);
          buffer.write(dataString);

          String bufferedData = buffer.toString();
          
          // Only process if we have a complete line
          if (bufferedData.contains('\n')) {
            List<String> lines = bufferedData.split('\n');
            
            // Process complete lines
            for (int i = 0; i < lines.length - 1; i++) {
              String line = lines[i].trim();
              if (line.isNotEmpty) {
                _processData(line, mainSendPort);
              }
            }

            // Store any incomplete data
            buffer.clear();
            if (!bufferedData.endsWith('\n')) {
              remainingData = lines.last;
            }
          }
        } catch (e) {
          print("Error processing data in isolate: $e");
          buffer.clear();
          remainingData = null;
        }
      }
    });
  }

  static void _processData(String line, SendPort mainSendPort) {
    try {
      Map<int, int> sliderData = {};
      List<String> parts = line.split('|');

      for (int i = 0; i < parts.length - 1; i += 2) {
        try {
          int sliderId = int.parse(parts[i].trim());
          int sliderValue = int.parse(parts[i + 1].trim());
          sliderData[sliderId] = sliderValue;
        } catch (e) {
          print("Error parsing slider data: $e");
          continue;
        }
      }

      if (sliderData.isNotEmpty) {
        mainSendPort.send(sliderData);
      }
    } catch (e) {
      print("Error in _processData: $e");
    }
  }

  void dispose() {
    _connectionCheckTimer?.cancel();
    _readTimer?.cancel();
    if (_serialPort?.isOpen ?? false) {
      try {
        _serialPort?.close();
      } catch (e) {
        print("Error closing port during dispose: $e");
      }
    }
    _cleanupConnection();
    _sliderStreamController.close();
    _rawDataStreamController.close();
    _connectionStreamController.close();
  }
}
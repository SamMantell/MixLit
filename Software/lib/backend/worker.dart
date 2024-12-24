import 'dart:async';
import 'dart:typed_data';
import 'dart:isolate';
import 'package:flutter_libserialport/flutter_libserialport.dart';

class Worker {
  final _serialPort = SerialPort('COM20');
  var config = SerialPortConfig()
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
  SerialPortReader? _portReader;
  
  Stream<Map<int, int>> get sliderStream => _sliderStreamController.stream;
  Stream<String> get rawDataStream => _rawDataStreamController.stream;
  Stream<bool> get connectionStream => _connectionStreamController.stream;

  Worker() {
    _startConnectionCheck();
  }

  void _startConnectionCheck() {
    _checkConnection(); //immediately call to prevent device not detected on launch
    _connectionCheckTimer = Timer.periodic(const Duration(seconds: 5), (timer) { //check every 5 seconds for connection status
      _checkConnection();
    });
  }

  Future<void> _setupIsolate() async {
    _receivePort?.close();
    _receivePort = ReceivePort();
    
    // Create a completer to wait for the SendPort
    final completer = Completer<void>();
    
    // Set up the receive port listener
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

    // Create the isolate
    _isolate = await Isolate.spawn(_isolateEntry, _receivePort!.sendPort);
    
    // Wait for the SendPort to be received
    await completer.future;
  }

  Future<void> _initializePort() async {
    if (!_isListening && deviceConnected) {
      try {
        _serialPort.config = config;
        
        String str = '40FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF';
        Uint8List uint8list = Uint8List.fromList(str.codeUnits);
        _serialPort.write(uint8list);

        // Set up the isolate and wait for it to be ready
        await _setupIsolate();

        if (!_isListening) {
          _portReader = SerialPortReader(_serialPort);
          _portReader!.stream.listen(
            (Uint8List data) {
              _isolateSendPort?.send(data);
            },
            onDone: () => _cleanupConnection(),
            onError: (error) {
              print("Serial port error: $error");
              _cleanupConnection();
            }
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

  void _cleanupConnection() {
    _isListening = false;
    deviceConnected = false;
    _portReader = null;
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
      if (_serialPort.isOpen) {
        print("Port is already open, closing first...");
        _serialPort.close();
        await Future.delayed(const Duration(milliseconds: 100));
      }

      print("Attempting to open port...");
      _serialPort.config = config;
      bool opened = _serialPort.openReadWrite();
      print("Port open result: $opened");
      
      if (opened) {
        deviceConnected = true;
        if (!wasConnected) {
          print("Successfully connected to device");
          _connectionStreamController.add(true);
          await _initializePort();
        }
      } else {
        _cleanupConnection();
      }
    } catch (e, stackTrace) {
      print("Error connecting to COM port: $e");
      print("Stack trace: $stackTrace");
      _cleanupConnection();
    }
  }

  static void _isolateEntry(SendPort mainSendPort) {
    final buffer = StringBuffer();
    final receivePort = ReceivePort();

    mainSendPort.send(receivePort.sendPort);

    receivePort.listen((data) {
      if (data is Uint8List) {
        String dataString = String.fromCharCodes(data);
        buffer.write(dataString);

        String bufferedData = buffer.toString();
        List<String> lines = bufferedData.split('\n');
        
        for (int i = 0; i < lines.length - 1; i++) {
          String line = lines[i];
          _processData(line, mainSendPort);
        }

        buffer.clear();
        if (lines.isNotEmpty && !bufferedData.endsWith('\n')) {
          buffer.write(lines.last);
        }
      }
    });
  }

  static void _processData(String line, SendPort mainSendPort) {
    Map<int, int> sliderData = {};

    List<String> parts = line.split('|');

    for (int i = 0; i < parts.length - 1; i += 2) {
      int sliderId = int.parse(parts[i].trim());
      int sliderValue = int.parse(parts[i + 1].trim());
      sliderData[sliderId] = sliderValue;
    }

    if (sliderData.isNotEmpty) {
      mainSendPort.send(sliderData);
    }
  }

  void dispose() {
    _connectionCheckTimer?.cancel();
    _portReader = null;
    if (_serialPort.isOpen) {
      _serialPort.close();
    }
    _cleanupConnection();
    _sliderStreamController.close();
    _rawDataStreamController.close();
    _connectionStreamController.close();
  }
}
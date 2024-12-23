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
  late final SendPort _isolateSendPort;
  late final ReceivePort _receivePort = ReceivePort();
  Isolate? _isolate;
  bool deviceConnected = false;
  bool _isListening = false;
  
  Stream<Map<int, int>> get sliderStream => _sliderStreamController.stream;
  Stream<String> get rawDataStream => _rawDataStreamController.stream;
  Stream<bool> get connectionStream => _connectionStreamController.stream;

  Worker() {
    _startConnectionCheck();
  }

  void _startConnectionCheck() {
    _checkConnection();
    _connectionCheckTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      _checkConnection();
    });
  }

  Future<void> _checkConnection() async {
    if (deviceConnected && _isListening){
      return;
    }
    bool wasConnected = deviceConnected;
    try {
      if (deviceConnected) {
        _receivePort.close();
        _isolate?.kill(priority: Isolate.immediate);
        _isolate = null;
      }
      print("Attempting to connect to COM20...");
      if (_serialPort.isOpen && !deviceConnected) {
        print("Port is already open, closing first...");
        _serialPort.endBreak();
        _serialPort.close();
        await Future.delayed(const Duration(milliseconds: 100));
      }

      if (!_isListening) {
        print("Attempting to open port...");
        _serialPort.config = config;
        bool opened = _serialPort.openReadWrite();
        print("Port open result: $opened");
        if (opened) {
          deviceConnected = true;
          if (!wasConnected) {
            print("Successfully connected to device");
            _connectionStreamController.add(true);
            _initializePort();
          }
        } else {
          _serialPort.close();
          _receivePort.close();
          _connectionStreamController.add(false);
        }
      }
    } catch (e, stackTrace) {
      print("Error connecting to COM port: $e");
      print("Stack trace: $stackTrace");
      deviceConnected = false;
      if (wasConnected) {
        _connectionStreamController.add(false);
      }
    }
  }

  Future<void> _initializePort() async {
    if (!_isListening && deviceConnected) {
      _serialPort.config = config;
      
      String str = '40FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF';
      Uint8List uint8list = Uint8List.fromList(str.codeUnits);
      _serialPort.write(uint8list);

      _isolate ??= await Isolate.spawn(_isolateEntry, _receivePort.sendPort);
      
      _receivePort.listen((message) {
        if (message is SendPort) {
          _isolateSendPort = message;
        } else if (message is Map<int, int>) {
          _sliderStreamController.add(message);
        } else if (message is String) {
          _rawDataStreamController.add(message);
        }
      });

      if (!_isListening) {
      // Start listening to serial port data
      SerialPortReader(_serialPort).stream.listen(
        (Uint8List data) {
          _isolateSendPort.send(data);
        },
        onDone: () {
          _isListening = false;
          deviceConnected = false;
          _connectionStreamController.add(false);
        },
        onError: (error) {
          _isListening = false;
          deviceConnected = false;
          _connectionStreamController.add(false);
        }
      );
      }

      _isListening = true;
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
          _processData(line, mainSendPort); // send to main isolate
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
    _serialPort.close();
    _sliderStreamController.close();
    _rawDataStreamController.close();
    _connectionStreamController.close();
    _receivePort.close();
    _isolate?.kill(priority: Isolate.immediate);
  }
}
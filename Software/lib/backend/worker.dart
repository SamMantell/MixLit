import 'dart:async';
import 'dart:typed_data';
import 'dart:isolate';
import 'package:flutter_libserialport/flutter_libserialport.dart';

class Worker {
  final _serialPort = SerialPort('COM20');
  final StreamController<Map<int, int>> _sliderStreamController = StreamController.broadcast();
  final StreamController<String> _rawDataStreamController = StreamController.broadcast();
  late final SendPort _isolateSendPort;
  late final ReceivePort _receivePort;
  Isolate? _isolate;
  
  Stream<Map<int, int>> get sliderStream => _sliderStreamController.stream;
  Stream<String> get rawDataStream => _rawDataStreamController.stream;

  Worker() {
    _initializePort();
  }

  Future<void> _initializePort() async {
    if (!_serialPort.openReadWrite()) {
      print("Failed to open port");
    }

    _serialPort.config.baudRate = 115200;
    _serialPort.config.bits = 8;
    _serialPort.config.parity = SerialPortParity.none;
    _serialPort.config.stopBits = 1;
    _serialPort.config.setFlowControl(SerialPortFlowControl.none);

    

    String str = '40FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF';
    Uint8List uint8list = Uint8List.fromList(str.codeUnits);
    print (_serialPort.write(uint8list));




    _receivePort = ReceivePort();
    _isolate = await Isolate.spawn(_isolateEntry, _receivePort.sendPort);

    _receivePort.listen((message) {
      if (message is SendPort) {

        _isolateSendPort = message;
      } else if (message is Map<int, int>) {
        _sliderStreamController.add(message);
      } else if (message is String) {
        _rawDataStreamController.add(message);
      }
    });

    // Listen to serial port data and send it to the isolate for processing
    SerialPortReader(_serialPort).stream.listen((Uint8List data) {
      if (_isolateSendPort != null) {
        _isolateSendPort.send(data);
      }
    });
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

    //if (line.contains('|')) {
    //  List<String> parts = line.split('|');
    //  if (parts.length == 2) {
    //    try {
    //      int sliderId = int.parse(parts[0].trim());
    //      int sliderValue = int.parse(parts[1].trim());
    //      mainSendPort.send({sliderId: sliderValue});
    //    } catch (e) {
    //      print("Error parsing slider data: $e");
    //    }
    //  }
    //}
  }

  void dispose() {
    _serialPort.close();
    _sliderStreamController.close();
    _rawDataStreamController.close();
    _receivePort.close();
    _isolate?.kill(priority: Isolate.immediate);
  }
}

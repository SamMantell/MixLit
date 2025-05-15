import 'dart:async';
import 'dart:isolate';
import 'package:mixlit/backend/serial/connection/SerialConnectionManager.dart';

class SerialWorker {
  final _sliderDataController = StreamController<Map<int, int>>.broadcast();
  final _buttonDataController = StreamController<Map<String, int>>.broadcast();
  final _rawDataController = StreamController<String>.broadcast();
  final _connectionStateController = StreamController<bool>.broadcast();

  late final SerialConnectionManager _connectionManager;
  Isolate? _dataProcessingIsolate;
  ReceivePort? _receivePort;
  SendPort? _isolateSendPort;
  StreamSubscription? _connectionStateSubscription;
  final Completer<void> _initCompleter = Completer<void>();
  Future<void> get initialized => _initCompleter.future;

  Stream<Map<int, int>> get sliderData => _sliderDataController.stream;
  Stream<Map<String, int>> get buttonData => _buttonDataController.stream;
  Stream<String> get rawData => _rawDataController.stream;
  Stream<bool> get connectionState => _connectionStateController.stream;

  SerialWorker() {
    _connectionManager = SerialConnectionManager(
      connectionStateController: _connectionStateController,
      onDataReceived: _handleData,
      onError: _handleError,
    );
    _connectionManager.initialized.then((_) {
      _connectionStateSubscription =
          _connectionStateController.stream.listen((connected) {
        print('Connection state changed: $connected');
        if (!connected) {
          _cleanupDataProcessing();
        } else {
          _initializeDataProcessing();
        }
      });

      _initializeDataProcessing().then((_) {
        print('SerialWorker initialization complete');
        if (!_initCompleter.isCompleted) {
          _initCompleter.complete();
        }
      });
    });
  }

  void _cleanupDataProcessing() {
    print('Cleaning up data processing...');
    _dataProcessingIsolate?.kill();
    _dataProcessingIsolate = null;
    _receivePort?.close();
    _receivePort = null;
    _isolateSendPort = null;
  }

  void _handleData(List<int> data) {
    if (_isolateSendPort != null) {
      final line = String.fromCharCodes(data).trim();
      if (line.isNotEmpty) {
        _isolateSendPort!.send(line);
      }
    }
  }

  void _handleError(dynamic error) {
    print('Serial error: $error');
  }

  Future<void> dispose() async {
    print('Disposing SerialWorker...');
    await _connectionStateSubscription?.cancel();
    await _connectionManager.dispose();
    _cleanupDataProcessing();
    await _sliderDataController.close();
    await _buttonDataController.close();
    await _rawDataController.close();
    await _connectionStateController.close();
    print('SerialWorker disposal complete');
  }

  Future<void> _initializeDataProcessing() async {
    _receivePort?.close();
    _receivePort = ReceivePort();

    try {
      print('Initializing data processing isolate...');
      final errorPort = ReceivePort();
      final completer = Completer<void>();

      _receivePort!.listen((message) {
        if (message is SendPort) {
          print('Received isolate send port');
          _isolateSendPort = message;
          if (!completer.isCompleted) completer.complete();
        } else if (message is Map<int, int>) {
          _sliderDataController.add(message);
        } else if (message is Map<String, int>) {
          _buttonDataController.add(message);
        } else if (message is String) {
          _rawDataController.add(message);
        }
      });

      _dataProcessingIsolate = await Isolate.spawn(
        _processDataIsolate,
        _receivePort!.sendPort,
        onError: errorPort.sendPort,
        errorsAreFatal: true,
      );

      errorPort.listen((error) {
        print('Isolate error: $error');
        if (!completer.isCompleted) {
          completer.completeError(error);
        }
      });

      await completer.future.timeout(
        const Duration(seconds: 1),
        onTimeout: () {
          print('Isolate initialization timeout');
          throw TimeoutException('Isolate initialization timeout');
        },
      );
    } catch (e) {
      print('Error initializing data processing: $e');
      rethrow;
    }
  }

  static void _processDataIsolate(SendPort mainSendPort) {
    final receivePort = ReceivePort();
    bool isProcessing = false;

    mainSendPort.send(receivePort.sendPort);

    receivePort.listen((message) async {
      if (isProcessing) return;
      isProcessing = true;

      try {
        if (message is String && message.isNotEmpty) {
          await _parseAndSendData(message, mainSendPort);
        }
      } catch (e) {
        print('Isolate: Error processing data: $e');
      } finally {
        isProcessing = false;
      }
    });
  }

  static Future<void> _parseAndSendData(
      String line, SendPort mainSendPort) async {
    try {
      final parts = line.split('|');
      if (parts.isEmpty) return;

      if (parts.isNotEmpty &&
          parts[0].length == 1 &&
          parts[0].codeUnitAt(0) >= 'A'.codeUnitAt(0) &&
          parts[0].codeUnitAt(0) <= 'E'.codeUnitAt(0)) {
        try {
          if (parts.length >= 2) {
            final buttonId = parts[0];
            final buttonState = int.parse(parts[1].trim());

            final buttonData = <String, int>{};
            buttonData[buttonId] = buttonState;
            mainSendPort.send(buttonData);
          }
        } catch (e) {
          print('Error parsing button data: $e');
        }
        return;
      }

      final sliderData = <int, int>{};

      for (var i = 0; i < parts.length - 1; i += 2) {
        if (parts[i].isEmpty || parts[i + 1].isEmpty) continue;

        try {
          final sliderId = int.parse(parts[i].trim());
          final sliderValue = int.parse(parts[i + 1].trim());
          sliderData[sliderId] = sliderValue;
        } catch (e) {
          continue;
        }
      }

      if (sliderData.isNotEmpty) {
        mainSendPort.send(sliderData);
      }
    } catch (e) {
      print('Isolate: Error parsing data: $e');
    }
  }

  Future<void> sendCommand(String command) async {
    if (!isDeviceConnected) {
      print('Cannot send command: device not connected');
      return;
    }

    try {
      if (command.length < 2) {
        print('Invalid command format: too short');
        return;
      }

      _rawDataController.add(command);

      await _sendToDevice(command);
    } catch (e) {
      print('Error sending command to MixLit: $e');
    }
  }

  Future<void> _sendToDevice(String data) async {
    try {
      final bytes = data.codeUnits;

      if (_connectionManager.isConnected) {
        final success = await _connectionManager.writeToPort(bytes);
        if (success) {
          //print('Data sent to device: $data');
        } else {
          throw Exception('Failed to write to port');
        }
      } else {
        throw Exception('Not connected to device');
      }
    } catch (e) {
      print('Error sending data to device: $e');
      rethrow;
    }
  }

  bool get isDeviceConnected {
    bool connected = _connectionManager.isConnected;
    return connected;
  }
}

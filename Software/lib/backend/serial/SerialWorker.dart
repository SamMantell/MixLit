import 'dart:async';
import 'dart:isolate';
import 'package:mixlit/backend/serial/connection/SerialConnectionManager.dart';

class SerialWorker {
  final _sliderDataController = StreamController<Map<int, int>>.broadcast();
  final _rawDataController = StreamController<String>.broadcast();
  final _connectionStateController = StreamController<bool>.broadcast();

  late final SerialConnectionManager _connectionManager;
  Isolate? _dataProcessingIsolate;
  ReceivePort? _receivePort;
  SendPort? _isolateSendPort;
  StreamSubscription? _connectionStateSubscription;

  Stream<Map<int, int>> get sliderData => _sliderDataController.stream;
  Stream<String> get rawData => _rawDataController.stream;
  Stream<bool> get connectionState => _connectionStateController.stream;

  SerialWorker() {
    _connectionManager = SerialConnectionManager(
      connectionStateController: _connectionStateController,
      onDataReceived: _handleData,
      onError: _handleError,
    );

    // Listen to connection state changes
    _connectionStateSubscription =
        _connectionStateController.stream.listen((connected) {
      if (!connected) {
        // Clean up data processing when disconnected
        _cleanupDataProcessing();
      } else {
        // Reinitialize data processing when connected
        _initializeDataProcessing();
      }
    });

    // Initial setup of data processing
    _initializeDataProcessing();
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
    // Additional error handling if needed
  }

  Future<void> dispose() async {
    await _connectionStateSubscription?.cancel();
    await _connectionManager.dispose();
    _cleanupDataProcessing();
    await _sliderDataController.close();
    await _rawDataController.close();
    await _connectionStateController.close();
  }

  Future<void> _initializeDataProcessing() async {
    _receivePort?.close();
    _receivePort = ReceivePort();

    try {
      final errorPort = ReceivePort();
      final completer = Completer<void>();

      _receivePort!.listen((message) {
        if (message is SendPort) {
          _isolateSendPort = message;
          if (!completer.isCompleted) completer.complete();
        } else if (message is Map<int, int>) {
          _sliderDataController.add(message);
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

      await completer.future.timeout(
        const Duration(seconds: 1),
        onTimeout: () =>
            throw TimeoutException('Isolate initialization timeout'),
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

      final sliderData = <int, int>{};

      for (var i = 0; i < parts.length - 1; i += 2) {
        if (parts[i].isEmpty || parts[i + 1].isEmpty) continue;

        try {
          final sliderId = int.parse(parts[i].trim());
          final sliderValue = int.parse(parts[i + 1].trim());
          sliderData[sliderId] = sliderValue;
        } catch (e) {
          print('Error parsing slider data: $e');
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
}

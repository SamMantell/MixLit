import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_libserialport/flutter_libserialport.dart';

class SerialPortReader {
  static const int CHUNK_SIZE = 256;
  static const int READ_INTERVAL_MS = 10;

  final SerialPort _port;
  final StreamController<List<int>> _controller = StreamController<List<int>>();
  final List<int> _buffer = [];
  Timer? _readTimer;
  bool _isReading = false;
  bool _isClosed = false;

  SerialPortReader(this._port) {
    _controller.onListen = _startReading;
    _controller.onPause = _stopReading;
    _controller.onResume = _startReading;
    _controller.onCancel = _cleanup;
  }

  Stream<List<int>> get stream => _controller.stream;

  void _startReading() {
    if (_isReading || _isClosed) return;
    _isReading = true;

    _readTimer =
        Timer.periodic(Duration(milliseconds: READ_INTERVAL_MS), (timer) {
      if (!_isReading || _isClosed) {
        timer.cancel();
        return;
      }
      _readChunk();
    });
  }

  void _stopReading() {
    _isReading = false;
    _readTimer?.cancel();
    _readTimer = null;
  }

  void _readChunk() {
    if (!_port.isOpen || _controller.isClosed) {
      _cleanup();
      return;
    }

    try {
      final available = _port.bytesAvailable;
      if (available <= 0) return;

      final toRead = available.clamp(0, CHUNK_SIZE);
      final data = _port.read(toRead);
      if (data.isEmpty) return;

      _processData(data);
    } catch (e) {
      _handleError(e);
    }
  }

  void _processData(Uint8List data) {
    try {
      _buffer.addAll(data);

      var start = 0;
      for (var i = 0; i < _buffer.length; i++) {
        if (_buffer[i] == 10) {
          // newline character
          if (i > start) {
            final message = _buffer.sublist(start, i);
            if (!_controller.isClosed && _controller.hasListener) {
              _controller.add(Uint8List.fromList(message));
            }
          }
          start = i + 1;
        }
      }

      if (start > 0) {
        _buffer.removeRange(0, start);
      }

      if (_buffer.length > 1024) {
        _buffer.clear();
      }
    } catch (e) {
      print('Error processing data: $e');
      _handleError(e);
    }
  }

  void _handleError(Object error) {
    if (!_isClosed && !_controller.isClosed) {
      _controller.addError(error);
    }
    _cleanup();
  }

  Future<void> _cleanup() async {
    if (_isClosed) return;
    _isClosed = true;
    _stopReading();
    _buffer.clear();

    // Ensure we're not adding events to a closed controller
    if (!_controller.isClosed) {
      await _controller.close();
    }
  }

  Future<void> dispose() async {
    await _cleanup();
  }
}

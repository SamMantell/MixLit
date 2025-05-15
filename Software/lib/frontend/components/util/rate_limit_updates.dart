import 'dart:async';
import 'package:flutter/material.dart';

class RateLimitedUpdater {
  Timer? _timer;
  bool _hasPendingUpdate = false;
  final Duration _delay;
  final VoidCallback _callback;
  bool _disposed = false;

  RateLimitedUpdater(this._delay, this._callback);

  void requestUpdate() {
    if (_disposed || _hasPendingUpdate) return;

    _hasPendingUpdate = true;
    _timer?.cancel();
    _timer = Timer(_delay, () {
      if (!_disposed) {
        _hasPendingUpdate = false;
        _callback();
      }
    });
  }

  void forceUpdate() {
    if (_disposed) return;

    _timer?.cancel();
    _hasPendingUpdate = false;
    _callback();
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _hasPendingUpdate = false;
  }
}

class BatchedValueUpdater<T> {
  final Map<String, T> _pendingValues = {};
  late final RateLimitedUpdater _updater;
  final void Function(Map<String, T>) _onUpdate;

  BatchedValueUpdater(Duration delay, this._onUpdate) {
    _updater = RateLimitedUpdater(delay, _flushUpdates);
  }

  void updateValue(String key, T value) {
    _pendingValues[key] = value;
    _updater.requestUpdate();
  }

  void _flushUpdates() {
    if (_pendingValues.isNotEmpty) {
      final updates = Map<String, T>.from(_pendingValues);
      _pendingValues.clear();
      _onUpdate(updates);
    }
  }

  void dispose() {
    _updater.dispose();
    _pendingValues.clear();
  }
}

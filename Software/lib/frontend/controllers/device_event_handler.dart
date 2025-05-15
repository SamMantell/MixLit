import 'dart:async';
import 'package:flutter/material.dart';
import 'package:mixlit/backend/serial/SerialWorker.dart';
import 'package:mixlit/frontend/controllers/mute_button_controller.dart';

class DeviceEventHandler {
  final SerialWorker worker;
  final Function(Map<int, int>) onSliderDataReceived;
  final Function(int, bool, bool) onButtonEvent;
  final Function(bool) onConnectionStateChanged;

  final List<StreamSubscription> _subscriptions = [];

  DeviceEventHandler({
    required this.worker,
    required this.onSliderDataReceived,
    required this.onButtonEvent,
    required this.onConnectionStateChanged,
  });

  void initialize() {
    _setupConnectionListener();
    _setupSliderListener();
    _setupButtonListener();
  }

  void _setupConnectionListener() {
    final subscription = worker.connectionState.listen(
      (connected) {
        onConnectionStateChanged(connected);
      },
      onError: (error) {
        print('Connection stream error: $error');
      },
    );
    _subscriptions.add(subscription);
  }

  void _setupSliderListener() {
    final subscription = worker.sliderData.listen(
      (data) {
        onSliderDataReceived(data);
      },
      onError: (error) {
        print('Slider stream error: $error');
      },
    );
    _subscriptions.add(subscription);
  }

  void _setupButtonListener() {
    final subscription = worker.buttonData.listen(
      (data) {
        data.forEach((buttonId, state) {
          // Parse button (A-E) (0-4)
          if (buttonId.length == 1 &&
              buttonId.codeUnitAt(0) >= 'A'.codeUnitAt(0) &&
              buttonId.codeUnitAt(0) <= 'E'.codeUnitAt(0)) {
            final index = buttonId.codeUnitAt(0) - 'A'.codeUnitAt(0);
            final isPressed = state == 1;
            final isReleased = state == 0;

            onButtonEvent(index, isPressed, isReleased);
          }
        });
      },
      onError: (error) {
        print('Button stream error: $error');
      },
    );
    _subscriptions.add(subscription);
  }

  void dispose() {
    for (var subscription in _subscriptions) {
      subscription.cancel();
    }
    _subscriptions.clear();
  }
}

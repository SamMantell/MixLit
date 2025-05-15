import 'dart:async';
import 'package:flutter/services.dart';
import 'package:mixlit/backend/serial/SerialWorker.dart';
import 'package:mixlit/frontend/components/icon_colour_extractor.dart';
import 'package:mixlit/backend/application/ConfigManager.dart';
import 'package:mixlit/backend/application/ApplicationManager.dart';
import 'package:mixlit/frontend/components/util/rate_limit_updates.dart';
import 'package:win32audio/win32audio.dart';

/// LED controller for setting LEDs
class LEDController {
  final SerialWorker _serialWorker;
  final ApplicationManager _applicationManager;
  Timer? _updateTimer;
  final Map<int, Color> _currentSliderColors = {};
  final List<double> _sliderValues;
  final List<String> _sliderTags;
  final Map<String, Uint8List?> _appIcons;
  bool _isAnimated = false;

  late final RateLimitedUpdater _ledUpdater;
  final Map<int, bool> _pendingSliderUpdates = {};

  static const int LED_UPDATE_INTERVAL_MS = 100; // Reduced from 50ms

  LEDController({
    required SerialWorker serialWorker,
    required ApplicationManager applicationManager,
    required List<double> sliderValues,
    required List<String> sliderTags,
    required Map<String, Uint8List?> appIcons,
    bool isAnimated = false,
  })  : _serialWorker = serialWorker,
        _applicationManager = applicationManager,
        _sliderValues = List<double>.from(sliderValues),
        _sliderTags = List<String>.from(sliderTags),
        _appIcons = Map<String, Uint8List?>.from(appIcons),
        _isAnimated = isAnimated {
    _ledUpdater = RateLimitedUpdater(
      Duration(milliseconds: LED_UPDATE_INTERVAL_MS ~/ 2),
      _processPendingUpdates,
    );

    _startUpdateTimer();
  }

  void _startUpdateTimer() {
    _updateTimer?.cancel();
    if (_isAnimated) {
      _updateTimer = Timer.periodic(
          Duration(milliseconds: LED_UPDATE_INTERVAL_MS),
          (_) => _requestAllLEDUpdate());
    }
  }

  void setAnimated(bool animated) {
    if (_isAnimated != animated) {
      _isAnimated = animated;
      _startUpdateTimer();
      updateAllLEDs();
    }
  }

  void toggleAnimation() {
    setAnimated(!_isAnimated);
  }

  // rate limited update request
  void _requestAllLEDUpdate() {
    for (int i = 0; i < _sliderValues.length; i++) {
      _pendingSliderUpdates[i] = true;
    }
    _ledUpdater.requestUpdate();
  }

  void _processPendingUpdates() {
    _pendingSliderUpdates.forEach((sliderIndex, _) {
      _updateSingleSliderLED(sliderIndex);
    });
    _pendingSliderUpdates.clear();
  }

  Future<void> updateAllLEDs() async {
    if (!_serialWorker.isDeviceConnected) {
      return;
    }

    for (int i = 0; i < _sliderValues.length; i++) {
      await _updateSingleSliderLED(i);
    }
  }

  /// Update specific slider LEDs with colors and value, anim state etc.. (rate limiting added too)
  Future<void> updateSliderLEDs(int sliderIndex) async {
    if (!_serialWorker.isDeviceConnected ||
        sliderIndex >= _sliderValues.length) {
      return;
    }
    _pendingSliderUpdates[sliderIndex] = true;
    _ledUpdater.requestUpdate();
  }

  Future<void> _updateSingleSliderLED(int sliderIndex) async {
    if (!_serialWorker.isDeviceConnected ||
        sliderIndex >= _sliderValues.length) {
      return;
    }

    Color sliderColor = await _getColorForSlider(sliderIndex);
    _currentSliderColors[sliderIndex] = sliderColor;

    final command = _generateLEDCommand(sliderIndex, sliderColor);
    await _serialWorker.sendCommand(command);
  }

  String _generateLEDCommand(int sliderIndex, Color color) {
    StringBuffer command = StringBuffer();

    command.write(sliderIndex.toRadixString(16));
    command.write(_isAnimated ? '1' : '0');

    final colorHex = _colorToHex(color);

    for (int i = 0; i < 8; i++) {
      command.write(colorHex);
    }

    Color animationColor = _isAnimated
        ? Color.fromARGB(color.alpha, (color.red + 128) % 255,
            (color.green + 128) % 255, (color.blue + 128) % 255)
        : color;

    final animationColorHex = _colorToHex(animationColor);

    for (int i = 0; i < 8; i++) {
      command.write(animationColorHex);
    }

    return command.toString();
  }

  String _colorToHex(Color color) {
    String red = color.red.toRadixString(16).padLeft(2, '0').toUpperCase();
    String green = color.green.toRadixString(16).padLeft(2, '0').toUpperCase();
    String blue = color.blue.toRadixString(16).padLeft(2, '0').toUpperCase();
    return red + green + blue;
  }

  Future<Color> _getColorForSlider(int sliderIndex) async {
    final sliderTag = _sliderTags[sliderIndex];

    const Color deviceColor = Color.fromARGB(255, 129, 191, 205);
    const Color masterColor = Color.fromARGB(255, 255, 255, 255);
    const Color activeAppColor = Color.fromARGB(255, 69, 205, 255);
    const Color unassignedColor = Color.fromARGB(255, 51, 51, 51);
    const Color defaultAppColor = Color.fromARGB(255, 243, 237, 191);

    switch (sliderTag) {
      case ConfigManager.TAG_DEFAULT_DEVICE:
        return deviceColor;
      case ConfigManager.TAG_MASTER_VOLUME:
        return masterColor;
      case ConfigManager.TAG_ACTIVE_APP:
        return activeAppColor;
      case ConfigManager.TAG_UNASSIGNED:
        return unassignedColor;
      case ConfigManager.TAG_APP:
        final app = _getAppForSlider(sliderIndex);
        if (app != null) {
          final appPath = app.processPath;
          if (_appIcons.containsKey(appPath)) {
            final iconData = _appIcons[appPath];
            if (iconData != null) {
              try {
                return await IconColorExtractor.extractDominantColor(
                  iconData,
                  appPath,
                  defaultColor: defaultAppColor,
                );
              } catch (e) {
                print('Error extracting color: $e');
                return defaultAppColor;
              }
            }
          }
        }
        return defaultAppColor;
      default:
        return defaultAppColor;
    }
  }

  ProcessVolume? _getAppForSlider(int sliderIndex) {
    if (sliderIndex < 0 || sliderIndex >= _sliderTags.length) {
      return null;
    }

    try {
      return _applicationManager.assignedApplications[sliderIndex];
    } catch (e) {
      print('Error accessing ApplicationManager: $e');
      return null;
    }
  }

  void updateSliderValues(List<double> sliderValues) {
    bool hasChanges = false;
    for (int i = 0; i < sliderValues.length && i < _sliderValues.length; i++) {
      if (_sliderValues[i] != sliderValues[i]) {
        _sliderValues[i] = sliderValues[i];
        hasChanges = true;
      }
    }

    if (hasChanges && !_isAnimated) {
      _requestAllLEDUpdate();
    }
  }

  void updateSliderValue(int sliderIndex, double value) {
    if (sliderIndex < 0 || sliderIndex >= _sliderValues.length) return;

    if (_sliderValues[sliderIndex] != value) {
      _sliderValues[sliderIndex] = value;

      if (!_isAnimated) {
        updateSliderLEDs(sliderIndex);
      }
    }
  }

  void updateAppIcons(Map<String, Uint8List?> appIcons) {
    _appIcons.clear();
    _appIcons.addAll(appIcons);
    _requestAllLEDUpdate();
  }

  void updateSliderTags(List<String> sliderTags) {
    bool hasChanges = false;
    for (int i = 0; i < sliderTags.length && i < _sliderTags.length; i++) {
      if (_sliderTags[i] != sliderTags[i]) {
        _sliderTags[i] = sliderTags[i];
        hasChanges = true;
      }
    }

    if (hasChanges) {
      _requestAllLEDUpdate();
    }
  }

  void dispose() {
    _updateTimer?.cancel();
    _ledUpdater.dispose();
    _pendingSliderUpdates.clear();
  }
}

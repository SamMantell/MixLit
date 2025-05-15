import 'dart:async';
import 'package:flutter/services.dart';
import 'package:mixlit/backend/serial/SerialWorker.dart';
import 'package:mixlit/frontend/components/icon_colour_extractor.dart';
import 'package:mixlit/backend/application/ConfigManager.dart';
import 'package:mixlit/backend/application/ApplicationManager.dart';
import 'package:win32audio/win32audio.dart';

/// LED controller for setting LEDs
/// TODO: ask sam about firmware improvements
class LEDController {
  final SerialWorker _serialWorker;
  final ApplicationManager _applicationManager;
  Timer? _updateTimer;
  final Map<int, Color> _currentSliderColors = {};
  final List<double> _sliderValues;
  final List<String> _sliderTags;
  final Map<String, Uint8List?> _appIcons;
  bool _isAnimated = false;

  // LEDController instance
  //
  // [serialWorker]: serial communication worker
  // [applicationManager]: application manager instance
  // [sliderValues]: List of current slider values
  // [sliderTags]: List of slider tags (app, master, etc..)
  // [appIcons]: Map of application paths to respective icons
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
    _startUpdateTimer();
  }

  void _startUpdateTimer() {
    _updateTimer?.cancel();
    if (_isAnimated) {
      _updateTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
        updateAllLEDs();
      });
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

  Future<void> updateAllLEDs() async {
    if (!_serialWorker.isDeviceConnected) {
      return;
    }

    for (int i = 0; i < _sliderValues.length; i++) {
      await updateSliderLEDs(i);
    }
  }

  /// Update specific slider LEDs with colors and value, anim state etc..
  Future<void> updateSliderLEDs(int sliderIndex) async {
    if (!_serialWorker.isDeviceConnected ||
        sliderIndex >= _sliderValues.length) {
      return;
    }

    Color sliderColor = await _getColorForSlider(sliderIndex);

    _currentSliderColors[sliderIndex] = sliderColor;

    final command = _generateLEDCommand(sliderIndex, sliderColor);

    // debug slider colour data
    //print('\n\nSending LED command for slider $sliderIndex: $command');

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

    //TODO: centralise these colour variables somewhere for easy customisability
    if (sliderTag == ConfigManager.TAG_DEFAULT_DEVICE) {
      return const Color.fromARGB(255, 129, 191, 205);
    } else if (sliderTag == ConfigManager.TAG_MASTER_VOLUME) {
      return const Color.fromARGB(255, 255, 255, 255);
    } else if (sliderTag == ConfigManager.TAG_ACTIVE_APP) {
      return const Color.fromARGB(255, 69, 205, 255);
    } else if (sliderTag == ConfigManager.TAG_UNASSIGNED) {
      return const Color.fromARGB(255, 51, 51, 51);
    } else if (sliderTag == ConfigManager.TAG_APP) {
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
                defaultColor: const Color.fromARGB(255, 243, 237, 191),
              );
            } catch (e) {
              print('Error extracting color: $e');
              return const Color.fromARGB(255, 243, 237, 191); // Default yellow
            }
          }
        }
      }
      //fallback app colour
      return const Color.fromARGB(255, 243, 237, 191);
    }
    //fallback default colour
    return const Color.fromARGB(255, 243, 237, 191);
  }

  ProcessVolume? _getAppForSlider(int sliderIndex) {
    if (sliderIndex < 0 || sliderIndex >= _sliderTags.length) {
      return null;
    }

    try {
      if (_applicationManager.assignedApplications.length > sliderIndex) {
        return _applicationManager.assignedApplications[sliderIndex];
      }
    } catch (e) {
      print('Error accessing ApplicationManager: $e');
    }

    return null;
  }

  void updateSliderValues(List<double> sliderValues) {
    for (int i = 0; i < sliderValues.length && i < _sliderValues.length; i++) {
      _sliderValues[i] = sliderValues[i];
    }

    if (!_isAnimated) {
      updateAllLEDs();
    }
  }

  void updateSliderValue(int sliderIndex, double value) {
    if (sliderIndex < 0 || sliderIndex >= _sliderValues.length) return;

    _sliderValues[sliderIndex] = value;

    if (!_isAnimated) {
      updateSliderLEDs(sliderIndex);
    }
  }

  void updateAppIcons(Map<String, Uint8List?> appIcons) {
    _appIcons.clear();
    _appIcons.addAll(appIcons);

    updateAllLEDs();
  }

  void updateSliderTags(List<String> sliderTags) {
    for (int i = 0; i < sliderTags.length && i < _sliderTags.length; i++) {
      _sliderTags[i] = sliderTags[i];
    }

    updateAllLEDs();
  }

  void dispose() {
    _updateTimer?.cancel();
  }
}

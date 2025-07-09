import 'dart:async';
import 'package:flutter/material.dart';
import 'package:mixlit/backend/application/audio/VolumeController.dart';

class MuteButtonController {
  final List<bool> muteStates;
  final List<AnimationController> buttonAnimControllers;
  final List<Animation<double>> buttonAnimations;
  final List<DateTime?> buttonPressStartTimes;
  final List<bool> isLongPressing;
  final List<bool> wasUnmutedBeforeLongPress;
  final List<double> previousVolumeValues;

  static const Duration longPressDuration = Duration(milliseconds: 500);
  static const double muteVolume = 0.0001;
  static const Duration debounceDelay = Duration(milliseconds: 50);

  final Function(int, double) onVolumeAdjustment;
  final Function(int, double)? onSliderValueUpdated;

  VolumeController? _volumeController;

  final Map<int, Timer> _debounceTimers = {};
  final Map<int, Timer> _longPressTimers = {};
  final Map<int, bool> _processingMute = {};
  final Map<int, bool> _wasToggledMute = {};

  MuteButtonController({
    required int buttonCount,
    required TickerProvider vsync,
    required this.onVolumeAdjustment,
    this.onSliderValueUpdated,
  })  : muteStates = List.filled(buttonCount, false),
        buttonAnimControllers = List.generate(
          buttonCount,
          (_) => AnimationController(
            duration: const Duration(milliseconds: 200),
            vsync: vsync,
          ),
        ),
        buttonAnimations = [],
        buttonPressStartTimes = List.filled(buttonCount, null),
        isLongPressing = List.filled(buttonCount, false),
        wasUnmutedBeforeLongPress = List.filled(buttonCount, false),
        previousVolumeValues = List.filled(buttonCount, 0.0) {
    for (var controller in buttonAnimControllers) {
      buttonAnimations.add(CurvedAnimation(
        parent: controller,
        curve: Curves.easeOut,
      ));
    }
  }

  void setVolumeController(VolumeController volumeController) {
    _volumeController = volumeController;
  }

  void updatePreviousVolumeValue(int sliderIndex, double value) {
    if (!muteStates[sliderIndex] && !(_processingMute[sliderIndex] ?? false)) {
      previousVolumeValues[sliderIndex] = value;
    }
  }

  Future<void> muteAudio(int sliderIndex, {bool isTemporary = false}) async {
    if (_processingMute[sliderIndex] == true) return;

    _processingMute[sliderIndex] = true;

    try {
      if (!muteStates[sliderIndex] && _volumeController != null) {
        previousVolumeValues[sliderIndex] =
            _volumeController!.applicationManager.sliderValues[sliderIndex];
        print(
            'Storing volume ${previousVolumeValues[sliderIndex]} before muting slider $sliderIndex ${isTemporary ? "(temporary)" : "(toggle)"}');
      }

      muteStates[sliderIndex] = true;

      if (!isTemporary) {
        _wasToggledMute[sliderIndex] = true;
      }

      if (_volumeController != null) {
        _volumeController!.updateMuteState(sliderIndex, true);
        await _volumeController!.setMuteState(sliderIndex, true);
      }

      if (onSliderValueUpdated != null) {
        onSliderValueUpdated!(sliderIndex, muteVolume);
      }

      buttonAnimControllers[sliderIndex].forward();
      print(
          'Muted slider $sliderIndex successfully ${isTemporary ? "(temporary)" : "(toggle)"}');
    } catch (e) {
      print('Error muting slider $sliderIndex: $e');
      muteStates[sliderIndex] = false;
      _wasToggledMute[sliderIndex] = false;
    } finally {
      _processingMute[sliderIndex] = false;
    }
  }

  Future<void> unmuteAudio(int sliderIndex) async {
    if (_processingMute[sliderIndex] == true) return;

    _processingMute[sliderIndex] = true;

    try {
      muteStates[sliderIndex] = false;
      _wasToggledMute[sliderIndex] = false;

      if (_volumeController != null) {
        _volumeController!.updateMuteState(sliderIndex, false);
        await _volumeController!.setMuteState(sliderIndex, false);
      }

      final restoredVolume = previousVolumeValues[sliderIndex];
      if (onSliderValueUpdated != null) {
        onSliderValueUpdated!(sliderIndex, restoredVolume);
      }

      buttonAnimControllers[sliderIndex].duration =
          const Duration(milliseconds: 100);
      buttonAnimControllers[sliderIndex].reverse().then((_) {
        buttonAnimControllers[sliderIndex].duration =
            const Duration(milliseconds: 200);
      });

      print('Unmuted slider $sliderIndex, restored volume: $restoredVolume');
    } catch (e) {
      print('Error unmuting slider $sliderIndex: $e');
      muteStates[sliderIndex] = true;
    } finally {
      _processingMute[sliderIndex] = false;
    }
  }

  void toggleMuteState(int sliderIndex) {
    print('UI-initiated mute toggle for slider $sliderIndex');

    if (muteStates[sliderIndex]) {
      unmuteAudio(sliderIndex);
    } else {
      muteAudio(sliderIndex, isTemporary: false);
    }
  }

  void updateDirectly(int sliderIndex, double value) {
    if (_processingMute[sliderIndex] == true) {
      print(
          'Ignoring direct update for slider $sliderIndex - mute operation in progress');
      return;
    }

    if (!muteStates[sliderIndex]) {
      previousVolumeValues[sliderIndex] = value;
    }

    if (onSliderValueUpdated != null) {
      onSliderValueUpdated!(sliderIndex, value);
    }
    onVolumeAdjustment(sliderIndex, value);
  }

  void handleButtonDown(int buttonIndex) {
    print('Button $buttonIndex pressed down');

    _debounceTimers[buttonIndex]?.cancel();

    _debounceTimers[buttonIndex] = Timer(debounceDelay, () {
      _processButtonDown(buttonIndex);
    });
  }

  void _processButtonDown(int buttonIndex) {
    print('Processing button down for $buttonIndex (debounced)');

    buttonPressStartTimes[buttonIndex] = DateTime.now();
    wasUnmutedBeforeLongPress[buttonIndex] = !muteStates[buttonIndex];
    isLongPressing[buttonIndex] = false;

    if (!muteStates[buttonIndex] && _volumeController != null) {
      previousVolumeValues[buttonIndex] =
          _volumeController!.applicationManager.sliderValues[buttonIndex];
      print(
          'Stored volume ${previousVolumeValues[buttonIndex]} for button $buttonIndex');
    }

    if (!muteStates[buttonIndex]) {
      muteAudio(buttonIndex, isTemporary: true);
    } else if (_wasToggledMute[buttonIndex] == true) {
      unmuteAudio(buttonIndex);
    }

    _longPressTimers[buttonIndex]?.cancel();
    _longPressTimers[buttonIndex] = Timer(longPressDuration, () {
      _handleLongPress(buttonIndex);
    });
  }

  void _handleLongPress(int buttonIndex) {
    print('Long press detected for button $buttonIndex');
    isLongPressing[buttonIndex] = true;
  }

  void handleButtonUp(int buttonIndex) {
    print('Button $buttonIndex released');

    _debounceTimers[buttonIndex]?.cancel();

    _longPressTimers[buttonIndex]?.cancel();

    final pressStartTime = buttonPressStartTimes[buttonIndex];
    if (pressStartTime == null) {
      print('No press start time found for button $buttonIndex');
      return;
    }

    buttonPressStartTimes[buttonIndex] = null;

    if (isLongPressing[buttonIndex]) {
      _handleLongPressRelease(buttonIndex);
    } else {
      _handleShortPressRelease(buttonIndex);
    }

    isLongPressing[buttonIndex] = false;
  }

  void _handleShortPressRelease(int buttonIndex) {
    print('Short press release for button $buttonIndex');
    if (wasUnmutedBeforeLongPress[buttonIndex] && muteStates[buttonIndex]) {
      _wasToggledMute[buttonIndex] = true;
      print('Converted to toggle mute for button $buttonIndex');
    }
  }

  void _handleLongPressRelease(int buttonIndex) {
    print('Long press release for button $buttonIndex - ending temporary mute');
    if (wasUnmutedBeforeLongPress[buttonIndex] && muteStates[buttonIndex]) {
      unmuteAudio(buttonIndex);
    } else if (!wasUnmutedBeforeLongPress[buttonIndex] &&
        !muteStates[buttonIndex]) {
      muteAudio(buttonIndex, isTemporary: false);
    }
  }

  Future<void> checkLongPress(int buttonIndex) async {
    //TODO: remove this lol
  }

  void dispose() {
    for (var timer in _debounceTimers.values) {
      timer.cancel();
    }
    for (var timer in _longPressTimers.values) {
      timer.cancel();
    }
    _debounceTimers.clear();
    _longPressTimers.clear();

    for (var controller in buttonAnimControllers) {
      controller.dispose();
    }
  }
}

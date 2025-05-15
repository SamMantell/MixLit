import 'package:flutter/material.dart';
import 'package:mixlit/backend/application/VolumeController.dart';

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

  final Function(int, double) onVolumeAdjustment;
  final Function(int, double)? onSliderValueUpdated;

  VolumeController? _volumeController;

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
    if (!muteStates[sliderIndex]) {
      previousVolumeValues[sliderIndex] = value;
    }
  }

  void muteAudio(int sliderIndex) {
    muteStates[sliderIndex] = true;

    _volumeController?.updateMuteState(sliderIndex, true);

    _volumeController?.setMuteState(sliderIndex, true);

    buttonAnimControllers[sliderIndex].forward();
  }

  void unmuteAudio(int sliderIndex) {
    muteStates[sliderIndex] = false;

    _volumeController?.updateMuteState(sliderIndex, false);

    _volumeController?.setMuteState(sliderIndex, false);

    buttonAnimControllers[sliderIndex].duration =
        const Duration(milliseconds: 100);
    buttonAnimControllers[sliderIndex].reverse().then((_) {
      buttonAnimControllers[sliderIndex].duration =
          const Duration(milliseconds: 200);
    });
  }

  void toggleMuteState(int sliderIndex) {
    if (muteStates[sliderIndex]) {
      unmuteAudio(sliderIndex);
    } else {
      muteAudio(sliderIndex);
    }
  }

  void updateDirectly(int sliderIndex, double value) {
    if (!muteStates[sliderIndex]) {
      previousVolumeValues[sliderIndex] = value;
    }

    if (onSliderValueUpdated != null) {
      onSliderValueUpdated!(sliderIndex, value);
    }
    onVolumeAdjustment(sliderIndex, value);
  }

  void handleButtonDown(int buttonIndex) {
    buttonPressStartTimes[buttonIndex] = DateTime.now();

    wasUnmutedBeforeLongPress[buttonIndex] = !muteStates[buttonIndex];
    if (!muteStates[buttonIndex]) {
      if (_volumeController != null) {
        previousVolumeValues[buttonIndex] =
            _volumeController!.applicationManager.sliderValues[buttonIndex];
      }
    }

    if (muteStates[buttonIndex]) {
      unmuteAudio(buttonIndex);
    } else {
      muteAudio(buttonIndex);
    }

    isLongPressing[buttonIndex] = false;
  }

  void handleButtonUp(int buttonIndex) {
    final pressStartTime = buttonPressStartTimes[buttonIndex];
    if (pressStartTime == null) {
      return;
    }

    final pressDuration = DateTime.now().difference(pressStartTime);
    buttonPressStartTimes[buttonIndex] = null;

    if (isLongPressing[buttonIndex]) {
      if (wasUnmutedBeforeLongPress[buttonIndex]) {
        if (muteStates[buttonIndex]) {
          unmuteAudio(buttonIndex);
        } else {
          muteAudio(buttonIndex);
        }
      }

      isLongPressing[buttonIndex] = false;
    }
  }

  Future<void> checkLongPress(int buttonIndex) async {
    await Future.delayed(longPressDuration);
    final pressStartTime = buttonPressStartTimes[buttonIndex];

    if (pressStartTime != null) {
      isLongPressing[buttonIndex] = true;
    }
  }

  void dispose() {
    for (var controller in buttonAnimControllers) {
      controller.dispose();
    }
  }
}

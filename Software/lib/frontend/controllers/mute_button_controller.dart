import 'package:flutter/material.dart';

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
        previousVolumeValues = List.filled(buttonCount, 1.0) {
    for (var controller in buttonAnimControllers) {
      buttonAnimations.add(CurvedAnimation(
        parent: controller,
        curve: Curves.easeOut,
      ));
    }
  }

  void muteAudio(int sliderIndex) {
    if (!muteStates[sliderIndex]) {
      previousVolumeValues[sliderIndex] = previousVolumeValues[sliderIndex];
    }

    muteStates[sliderIndex] = true;

    if (onSliderValueUpdated != null) {
      onSliderValueUpdated!(sliderIndex, muteVolume);
    }

    onVolumeAdjustment(sliderIndex, muteVolume);

    buttonAnimControllers[sliderIndex].forward();
  }

  void unmuteAudio(int sliderIndex) {
    muteStates[sliderIndex] = false;

    if (onSliderValueUpdated != null) {
      onSliderValueUpdated!(sliderIndex, previousVolumeValues[sliderIndex]);
    }

    onVolumeAdjustment(sliderIndex, previousVolumeValues[sliderIndex]);

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
    if (onSliderValueUpdated != null) {
      onSliderValueUpdated!(sliderIndex, value);
    }
    onVolumeAdjustment(sliderIndex, value);
  }

  void handleButtonDown(int buttonIndex) {
    buttonPressStartTimes[buttonIndex] = DateTime.now();

    wasUnmutedBeforeLongPress[buttonIndex] = !muteStates[buttonIndex];
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

import 'dart:async';
import 'package:mixlit/backend/application/audio/ApplicationManager.dart';
import 'package:mixlit/backend/application/audio/AppInstanceManager.dart';
import 'package:mixlit/backend/application/data/ConfigManager.dart';
import 'package:win32audio/win32audio.dart';

class VolumeController {
  final ApplicationManager applicationManager;
  List<String> sliderTags;
  List<ProcessVolume?> assignedApps;
  final AppInstanceManager _appInstanceManager = AppInstanceManager.instance;

  static const int RATE_LIMIT_MS = 10;
  DateTime _lastVolumeUpdate = DateTime.now();
  Timer? _pendingVolumeTimer;
  final Map<int, double> _pendingVolumeChanges = {};

  final Map<int, double> _storedVolumeValues = {};
  final Map<int, bool> _muteStates = {};

  static const double muteVolume = 0.0001;

  VolumeController({
    required this.applicationManager,
    required this.sliderTags,
    required this.assignedApps,
  }) {
    for (int i = 0; i < applicationManager.muteStates.length; i++) {
      _muteStates[i] = applicationManager.muteStates[i];
      if (_muteStates[i] == true) {
        _storedVolumeValues[i] = applicationManager.sliderValues[i];
      }
    }
  }

  void updateSliderTags(List<String> newTags) {
    sliderTags = newTags;
  }

  void updateAssignedApps(List<ProcessVolume?> newApps) {
    assignedApps = newApps;
  }

  void updateMuteState(int sliderId, bool isMuted) {
    _muteStates[sliderId] = isMuted;
  }

  bool isSliderMuted(int sliderId) {
    return _muteStates[sliderId] ?? false;
  }

  void storeVolumeValue(int sliderId, double value) {
    _storedVolumeValues[sliderId] = value;
    applicationManager.sliderValues[sliderId] = value;
  }

  double getStoredVolumeValue(int sliderId) {
    return _storedVolumeValues[sliderId] ??
        applicationManager.sliderValues[sliderId];
  }

  void adjustVolume(int sliderId, double value,
      {bool bypassRateLimit = false, bool fromRestore = false}) {
    applicationManager.sliderValues[sliderId] = value;

    if (isSliderMuted(sliderId) && value > muteVolume) {
      storeVolumeValue(sliderId, value);
      return;
    }

    if (value <= muteVolume || bypassRateLimit) {
      directVolumeAdjustment(sliderId, value, fromRestore: fromRestore);
      return;
    }

    _pendingVolumeChanges[sliderId] = value;
    _scheduleVolumeUpdate();
  }

  void _scheduleVolumeUpdate() {
    if (_pendingVolumeTimer?.isActive ?? false) return;

    final now = DateTime.now();
    final timeSinceLastUpdate =
        now.difference(_lastVolumeUpdate).inMilliseconds;

    if (timeSinceLastUpdate < RATE_LIMIT_MS) {
      final delayMs = RATE_LIMIT_MS - timeSinceLastUpdate;
      _pendingVolumeTimer =
          Timer(Duration(milliseconds: delayMs), _applyPendingChanges);
    } else {
      _applyPendingChanges();
    }
  }

  void _applyPendingChanges() {
    _lastVolumeUpdate = DateTime.now();

    final changes = Map<int, double>.from(_pendingVolumeChanges);
    _pendingVolumeChanges.clear();

    changes.forEach((sliderId, value) {
      if (!isSliderMuted(sliderId) || value <= muteVolume) {
        directVolumeAdjustment(sliderId, value, fromRestore: false);
      } else {
        storeVolumeValue(sliderId, value);
      }
    });
  }

  Future<void> directVolumeAdjustment(int sliderId, double value,
      {bool fromRestore = false}) async {
    final tag = sliderTags[sliderId];

    applicationManager.sliderValues[sliderId] = value;

    if (tag == ConfigManager.TAG_DEFAULT_DEVICE ||
        tag == ConfigManager.TAG_MASTER_VOLUME) {
      int volumeLevel = ((value / 1024) * 100).round();

      Audio.setVolume(volumeLevel / 100, AudioDeviceType.output);
    } else if (tag == ConfigManager.TAG_APP && assignedApps[sliderId] != null) {
      final app = assignedApps[sliderId];
      if (app != null) {
        double volumeLevel = value / 1024;
        if (volumeLevel <= 0.009) {
          volumeLevel = 0.0001;
        }

        try {
          bool hasMultipleInstances =
              await _appInstanceManager.hasMultipleInstances(app);
          if (hasMultipleInstances) {
            await _appInstanceManager.setVolumeForAllInstances(
                app, volumeLevel);
          } else {
            Audio.setAudioMixerVolume(app.processId, volumeLevel);
          }
        } catch (e) {
          print('Error adjusting app volume: $e');
          try {
            Audio.setAudioMixerVolume(app.processId, volumeLevel);
          } catch (fallbackError) {
            print('Fallback volume adjustment failed: $fallbackError');
          }
        }
      }
    } else if (tag == ConfigManager.TAG_ACTIVE_APP) {}

    bool isMuted =
        fromRestore ? _muteStates[sliderId] ?? false : (value <= muteVolume);
    applicationManager.updateSliderConfig(sliderId, value, isMuted);
  }

  Future<void> setMuteState(int sliderId, bool isMuted) async {
    applicationManager.enableVolumeRestorationForUserAction();

    updateMuteState(sliderId, isMuted);

    if (isMuted) {
      _storedVolumeValues[sliderId] = applicationManager.sliderValues[sliderId];
      await Future.delayed(const Duration(milliseconds: 10));
      await directVolumeAdjustment(sliderId, muteVolume);
    } else {
      await Future.delayed(const Duration(milliseconds: 10));
      final storedValue = getStoredVolumeValue(sliderId);
      await directVolumeAdjustment(sliderId, storedValue);
    }

    applicationManager.setMuteState(sliderId, isMuted);
  }

  void assignSpecialFeature(int sliderId, String featureTag) {
    applicationManager.assignSpecialFeatureToSlider(sliderId, featureTag);
  }

  void dispose() {
    _pendingVolumeTimer?.cancel();
    _pendingVolumeChanges.clear();
    _storedVolumeValues.clear();
    _muteStates.clear();
  }
}

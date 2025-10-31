import 'dart:async';
import 'package:mixlit/backend/application/audio/ApplicationManager.dart';
import 'package:mixlit/backend/application/audio/audio_service_client.dart';
import 'package:mixlit/backend/application/data/ConfigManager.dart';

class VolumeController {
  final ApplicationManager applicationManager;
  List<String> sliderTags;
  List<AudioSessionInfo?> assignedApps;

  static const int RATE_LIMIT_MS = 1;
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

  void updateAssignedApps(List<AudioSessionInfo?> newApps) {
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

  bool _shouldBypassRateLimit(int sliderId, double value) {
    final tag = sliderTags[sliderId];
    if (tag == ConfigManager.TAG_DEFAULT_DEVICE ||
        tag == ConfigManager.TAG_MASTER_VOLUME) {
      return true;
    }
    return value <= muteVolume;
  }

  void adjustVolume(int sliderId, double value,
      {bool bypassRateLimit = false, bool fromRestore = false}) {
    applicationManager.sliderValues[sliderId] = value;

    if (isSliderMuted(sliderId) && value > muteVolume) {
      storeVolumeValue(sliderId, value);
      return;
    }

    final shouldBypass =
        bypassRateLimit || _shouldBypassRateLimit(sliderId, value);

    if (shouldBypass) {
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

    // All volume adjustments now go through ApplicationManager
    await applicationManager.adjustVolume(sliderId, value);

    bool isMuted =
        fromRestore ? _muteStates[sliderId] ?? false : (value <= muteVolume);
  }

  Future<void> setMuteState(int sliderId, bool isMuted) async {
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

    await applicationManager.setMuteState(sliderId, isMuted);
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

import 'package:mixlit/backend/application/ApplicationManager.dart';
import 'package:mixlit/backend/application/AppInstanceManager.dart';
import 'package:mixlit/backend/application/ConfigManager.dart';
import 'package:win32audio/win32audio.dart';

class VolumeController {
  final ApplicationManager applicationManager;
  final List<String> sliderTags;
  final List<ProcessVolume?> assignedApps;
  final AppInstanceManager _appInstanceManager = AppInstanceManager.instance;
  static const double muteVolume = 0.0001;

  VolumeController({
    required this.applicationManager,
    required this.sliderTags,
    required this.assignedApps,
  });

  void adjustVolume(int sliderId, double value,
      {bool bypassRateLimit = false}) {
    if (bypassRateLimit || value <= muteVolume) {
      directVolumeAdjustment(sliderId, value);
      return;
    }

    final tag = sliderTags[sliderId];

    if (tag == ConfigManager.TAG_DEFAULT_DEVICE ||
        tag == ConfigManager.TAG_MASTER_VOLUME) {
      applicationManager.adjustDeviceVolume(value);
    } else if (tag == ConfigManager.TAG_APP && assignedApps[sliderId] != null) {
      applicationManager.adjustVolume(sliderId, value);
    } else if (tag == ConfigManager.TAG_ACTIVE_APP) {
      applicationManager.sliderValues[sliderId] = value;
    }
  }

  Future<void> directVolumeAdjustment(int sliderId, double value) async {
    final tag = sliderTags[sliderId];

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
        bool hasMultipleInstances =
            await _appInstanceManager.hasMultipleInstances(app);
        if (hasMultipleInstances) {
          await _appInstanceManager.setVolumeForAllInstances(app, volumeLevel);
        } else {
          Audio.setAudioMixerVolume(app.processId, volumeLevel);
        }
      }
    } else if (tag == ConfigManager.TAG_ACTIVE_APP) {
      applicationManager.sliderValues[sliderId] = value;
    }

    applicationManager.updateSliderConfig(sliderId, value, value <= muteVolume);

    if (tag == ConfigManager.TAG_APP && assignedApps[sliderId] != null) {
    } else if (tag == ConfigManager.TAG_DEFAULT_DEVICE ||
        tag == ConfigManager.TAG_MASTER_VOLUME) {
      applicationManager.adjustDeviceVolume(value);
    }
  }

  Future<void> setMuteState(int sliderId, bool isMuted) async {
    if (isMuted) {
      await directVolumeAdjustment(sliderId, muteVolume);
    } else {
      await directVolumeAdjustment(
          sliderId, applicationManager.sliderValues[sliderId]);
    }

    applicationManager.setMuteState(sliderId, isMuted);
  }

  void assignSpecialFeature(int sliderId, String featureTag) {
    applicationManager.assignSpecialFeatureToSlider(sliderId, featureTag);
  }
}

import 'package:mixlit/backend/application/ApplicationManager.dart';
import 'package:win32audio/win32audio.dart';

class VolumeController {
  final ApplicationManager applicationManager;
  final List<String> sliderTags;
  final List<ProcessVolume?> assignedApps;

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

    if (sliderTags[sliderId] == 'defaultDevice') {
      applicationManager.adjustDeviceVolume(value);
    } else if (sliderTags[sliderId] == 'app' &&
        assignedApps[sliderId] != null) {
      applicationManager.adjustVolume(sliderId, value);
    }
  }

  void directVolumeAdjustment(int sliderId, double value) {
    if (sliderTags[sliderId] == 'defaultDevice') {
      int volumeLevel = ((value / 1024) * 100).round();
      Audio.setVolume(volumeLevel / 100, AudioDeviceType.output);
    } else if (sliderTags[sliderId] == 'app' &&
        assignedApps[sliderId] != null) {
      final app = assignedApps[sliderId];
      if (app != null) {
        double volumeLevel = value / 1024;
        if (volumeLevel <= 0.009) {
          volumeLevel = 0.0001;
        }
        Audio.setAudioMixerVolume(app.processId, volumeLevel);
      }
    }

    if (sliderTags[sliderId] == 'defaultDevice') {
      applicationManager.sliderValues[sliderId] = value;
    } else if (sliderTags[sliderId] == 'app') {
      applicationManager.sliderValues[sliderId] = value;
    }
  }
}

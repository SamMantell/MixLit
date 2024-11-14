// lib/backend/application/get_application.dart

import 'package:win32audio/win32audio.dart';

class ApplicationManager {
  Map<int, ProcessVolume> assignedApplications = {};

  Future<List<ProcessVolume>> getRunningApplicationsWithAudio() async {
    return await Audio.enumAudioMixer() ?? [];
  }

  void assignApplicationToSlider(int sliderIndex, ProcessVolume processVolume) {
    assignedApplications[sliderIndex] = processVolume;
  }

  void adjustVolume(int sliderIndex, double sliderValue) {
    ProcessVolume? appProcess = assignedApplications[sliderIndex];
    if (appProcess != null) {
      // Scale sliderValue from 0-1024 to 0-100 and round to the nearest integer
      int volumeLevel = ((sliderValue / 1024) * 100).round();

      // Set the volume only if it's different from the current level to reduce updates
      if (appProcess.peakVolume * 100 != volumeLevel) {
        Audio.setAudioMixerVolume(appProcess.processId, volumeLevel / 100);
        print("Set volume of ${appProcess.processPath} to $volumeLevel%");
      }
    }
  }
}

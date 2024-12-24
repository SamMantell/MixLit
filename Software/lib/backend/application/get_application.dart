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
      // More precise volume calculation
      double volumeLevel = sliderValue / 1024;
      Audio.setAudioMixerVolume(appProcess.processId, volumeLevel);
      if (volumeLevel <= 0.001) {
        Audio.setAudioMixerVolume(appProcess.processId, 0);
      }
      
      //muting
      if (volumeLevel == 0) {
        Audio.setAudioMixerVolume(appProcess.processId, 0.0001);
      }

      print("Set volume of ${appProcess.processPath} to ${(volumeLevel * 100).round()}%");
    }
    }

    void adjustDeviceVolume(double sliderValue) {
    int volumeLevel = ((sliderValue / 1024) * 100).round();
    Audio.setVolume(volumeLevel / 100, AudioDeviceType.output);
    print("Set device volume to $volumeLevel%");
  }
}

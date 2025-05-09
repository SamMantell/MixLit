import 'dart:async';

import 'package:mixlit/backend/data/StorageManager.dart';
import 'package:win32audio/win32audio.dart';

class ApplicationManager {
  Map<int, ProcessVolume> assignedApplications = {};
  List<double> sliderValues = List.filled(8, 0.5); // Assuming 8 sliders
  List<String> sliderTags = List.filled(8, 'defaultDevice');

  // Rate limiting due to windows buffering volume requests (for some reason)
  static const int RATE_LIMIT_MS = 32; //milliseconds
  DateTime _lastVolumeAdjustment = DateTime.now();
  Timer? _pendingVolumeTimer;
  Map<int, double> _pendingAppVolumes = {};
  double? _pendingDeviceVolume;

  ApplicationManager() {
    _loadSavedConfiguration();
  }

  Future<void> _loadSavedConfiguration() async {
    try {
      // Retrieve saved slider configurations
      final savedSliderValues =
          await StorageManager.instance.getData('sliderValues');
      final savedSliderTags =
          await StorageManager.instance.getData('sliderTags');
      final savedAssignedApps =
          await StorageManager.instance.getData('assignedApps');

      // Restore slider values
      if (savedSliderValues != null) {
        sliderValues = List<double>.from(savedSliderValues);
      }

      // Restore slider tags
      if (savedSliderTags != null) {
        sliderTags = List<String>.from(savedSliderTags);
      }

      // Restore assigned applications
      if (savedAssignedApps != null) {
        final runningApps = await getRunningApplicationsWithAudio();

        savedAssignedApps.forEach((index, appData) {
          if (appData != null) {
            // Find the matching process volume for the saved process path
            final matchingApp = runningApps.firstWhere((app) {
              // Compare process paths, ignoring case and potential path differences
              return _normalizeProcessPath(app.processPath) ==
                  _normalizeProcessPath(appData['processPath'] ?? '');
            });

            assignedApplications[index] = matchingApp;

            // Restore volume for the app
            if (sliderTags[index] == 'app') {
              adjustVolume(index, sliderValues[index]);
            }
          }
        });
      }

      // If device volume was saved, restore it
      final savedDeviceVolume =
          await StorageManager.instance.getData('deviceVolume');
      if (savedDeviceVolume != null) {
        adjustDeviceVolume(savedDeviceVolume);
      }
    } catch (e) {
      print('Error loading saved configuration: $e');
    }
  }

  // Helper method to normalize process path for comparison
  String _normalizeProcessPath(String path) {
    if (path.isEmpty) return '';
    return path.toLowerCase().split(r'\').last.replaceAll('.exe', '');
  }

  Future<void> _saveConfiguration() async {
    try {
      await StorageManager.instance.saveData('sliderValues', sliderValues);
      await StorageManager.instance.saveData('sliderTags', sliderTags);

      // Save assigned applications
      final assignedAppsToSave =
          assignedApplications.map((index, app) => MapEntry(index, {
                'processPath': app.processPath,
                'processId': app.processId,
              }));
      await StorageManager.instance
          .saveData('assignedApps', assignedAppsToSave);
    } catch (e) {
      print('Error saving configuration: $e');
    }
  }

  Future<List<ProcessVolume>> getRunningApplicationsWithAudio() async {
    return await Audio.enumAudioMixer() ?? [];
  }

  void assignApplicationToSlider(int sliderIndex, ProcessVolume processVolume) {
    assignedApplications[sliderIndex] = processVolume;
    sliderTags[sliderIndex] = 'app';
    _saveConfiguration();
  }

  void adjustVolume(int sliderIndex, double sliderValue) {
    // Update slider value
    sliderValues[sliderIndex] = sliderValue;

    _pendingAppVolumes[sliderIndex] = sliderValue;

    _scheduleVolumeUpdate();
  }

  void _scheduleVolumeUpdate() {
    if (_pendingVolumeTimer != null && _pendingVolumeTimer!.isActive) {
      return;
    }

    final now = DateTime.now();
    final timeSinceLastUpdate =
        now.difference(_lastVolumeAdjustment).inMilliseconds;

    if (timeSinceLastUpdate < RATE_LIMIT_MS) {
      final delayMs = RATE_LIMIT_MS - timeSinceLastUpdate;
      _pendingVolumeTimer =
          Timer(Duration(milliseconds: delayMs), _applyPendingVolumeChanges);
    } else {
      _applyPendingVolumeChanges();
    }
  }

  void _applyPendingVolumeChanges() {
    _lastVolumeAdjustment = DateTime.now();

    _pendingAppVolumes.forEach((sliderIndex, sliderValue) {
      ProcessVolume? appProcess = assignedApplications[sliderIndex];
      if (appProcess != null) {
        double volumeLevel = sliderValue / 1024;
        Audio.setAudioMixerVolume(appProcess.processId, volumeLevel);
        if (volumeLevel <= 0.009) {
          Audio.setAudioMixerVolume(appProcess.processId, 0.0001);
        }
      }
    });
    _pendingAppVolumes.clear();

    if (_pendingDeviceVolume != null) {
      int volumeLevel = ((_pendingDeviceVolume! / 1024) * 100).round();
      Audio.setVolume(volumeLevel / 100, AudioDeviceType.output);
      _pendingDeviceVolume = null;
    }
  }

  void adjustDeviceVolume(double sliderValue) {
    _pendingDeviceVolume = sliderValue;

    _scheduleVolumeUpdate();

    // Save device volume
    StorageManager.instance.saveData('deviceVolume', sliderValue);
  }

  void resetSliderConfiguration(int sliderIndex) {
    // Reset specific slider configuration
    assignedApplications.remove(sliderIndex);
    sliderValues[sliderIndex] = 0.5; // Reset to middle
    sliderTags[sliderIndex] = 'defaultDevice';
    _saveConfiguration();
  }

  void clearAllConfigurations() {
    // Clear all saved configurations
    assignedApplications.clear();
    sliderValues = List.filled(8, 0.5);
    sliderTags = List.filled(8, 'defaultDevice');

    // Remove saved data from storage
    StorageManager.instance
      ..removeData('sliderValues')
      ..removeData('sliderTags')
      ..removeData('assignedApps')
      ..removeData('deviceVolume');
  }

  void dispose() {
    _pendingVolumeTimer?.cancel();
  }
}

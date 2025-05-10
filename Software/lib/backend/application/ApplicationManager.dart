import 'dart:async';

import 'package:mixlit/backend/application/ConfigManager.dart';
import 'package:mixlit/backend/data/StorageManager.dart';
import 'package:win32audio/win32audio.dart';

class ApplicationManager {
  Map<int, ProcessVolume> assignedApplications = {};
  List<double> sliderValues = List.filled(8, 0.5);
  List<String> sliderTags = List.filled(8, 'defaultDevice');
  List<bool> muteStates = List.filled(8, false);

  // Rate limiting due to windows buffering volume requests
  static const int RATE_LIMIT_MS = 40;
  DateTime _lastVolumeAdjustment = DateTime.now();
  Timer? _pendingVolumeTimer;
  Map<int, double> _pendingAppVolumes = {};
  double? _pendingDeviceVolume;

  bool _isConfigLoaded = false;
  Completer<void> _configLoadCompleter = Completer<void>();

  final ConfigManager _configManager = ConfigManager.instance;

  ApplicationManager() {
    _loadSavedConfiguration();
  }

  Future<void> get configLoaded => _configLoadCompleter.future;

  Future<void> _loadSavedConfiguration() async {
    try {
      print('Starting to load saved configuration...');

      final configs = await _configManager.loadAllSliderConfigs();
      print('Loaded config data: $configs');

      sliderValues = List<double>.from(configs['sliderValues']);
      print('Restored slider values: $sliderValues');

      sliderTags = List<String>.from(configs['sliderTags']);
      print('Restored slider tags: $sliderTags');

      muteStates = List<bool>.from(configs['muteStates']);
      print('Restored mute states: $muteStates');

      final sliderConfigs = configs['sliderConfigs'];
      List<ProcessVolume> runningApps = [];

      try {
        runningApps = await getRunningApplicationsWithAudio();
        print('Found ${runningApps.length} running apps with audio');
      } catch (e) {
        print('Error getting running applications: $e');
      }

      for (var i = 0; i < sliderConfigs.length; i++) {
        final config = sliderConfigs[i];
        if (config == null) {
          print('Slider $i has no configuration (reset)');
          sliderTags[i] = ConfigManager.TAG_UNASSIGNED;
          continue;
        }

        final sliderTag = config['sliderTag'] ?? 'unassigned';
        print('Processing slider $i with tag: $sliderTag');

        if (sliderTag == ConfigManager.TAG_APP &&
            config['processName'] != null) {
          print(
              'Attempting to find match for slider $i: ${config['processName']}');

          final matchingApp = await _configManager.findMatchingApp(
              runningApps, config['processName']);

          if (matchingApp != null) {
            assignedApplications[i] = matchingApp;
            print(
                'Found and assigned app ${matchingApp.processPath} to slider $i');

            final volumeValue = sliderValues[i];
            final isMuted = muteStates[i];

            print(
                'Restoring volume for slider $i: value=$volumeValue, muted=$isMuted');

            if (isMuted) {
              adjustVolume(i, 0.0001);
            } else {
              adjustVolume(i, volumeValue);
            }
          } else {
            print(
                'No matching app found for ${config['processName']} on slider $i');
            sliderTags[i] = ConfigManager.TAG_UNASSIGNED;
          }
        } else if (sliderTag == ConfigManager.TAG_DEFAULT_DEVICE ||
            sliderTag == ConfigManager.TAG_MASTER_VOLUME) {
          print(
              'Restoring device/master volume for slider $i: ${sliderValues[i]}');

          final volumeValue = sliderValues[i];
          final isMuted = muteStates[i];

          if (isMuted) {
            adjustDeviceVolume(0.0001);
          } else {
            adjustDeviceVolume(volumeValue);
          }
        } else if (sliderTag == ConfigManager.TAG_ACTIVE_APP) {
          print('Restored active app control for slider $i');
        } else {
          sliderTags[i] = ConfigManager.TAG_UNASSIGNED;
        }
      }

      _isConfigLoaded = true;
      _configLoadCompleter.complete();
      print('Configuration loading completed successfully');
    } catch (e) {
      print('Error loading saved configuration: $e');
      if (!_configLoadCompleter.isCompleted) {
        _configLoadCompleter.complete();
      }
    }
  }

  Future<List<ProcessVolume>> getRunningApplicationsWithAudio() async {
    final apps = await Audio.enumAudioMixer() ?? [];

    // filter duplicate applications based on process name
    final filteredApps = _configManager.filterDuplicateApps(
        apps, assignedApplications.entries.map((e) => e.value).toList());

    for (var app in filteredApps) {
      final name = _configManager.extractProcessName(app.processPath);
    }

    return filteredApps;
  }

  void assignApplicationToSlider(int sliderIndex, ProcessVolume processVolume) {
    assignedApplications[sliderIndex] = processVolume;
    sliderTags[sliderIndex] = ConfigManager.TAG_APP;
    print('Assigned app ${processVolume.processPath} to slider $sliderIndex');

    _configManager.onApplicationAssigned(
        sliderIndex,
        processVolume,
        sliderValues[sliderIndex],
        ConfigManager.TAG_APP,
        muteStates[sliderIndex]);
  }

  void assignSpecialFeatureToSlider(int sliderIndex, String featureTag) {
    assignedApplications.remove(sliderIndex);

    sliderTags[sliderIndex] = featureTag;
    print('Assigned special feature "$featureTag" to slider $sliderIndex');

    _configManager.onSpecialSliderAssigned(sliderIndex, featureTag,
        sliderValues[sliderIndex], muteStates[sliderIndex]);
  }

  void adjustVolume(int sliderIndex, double sliderValue) {
    sliderValues[sliderIndex] = sliderValue;

    _pendingAppVolumes[sliderIndex] = sliderValue;

    _scheduleVolumeUpdate();

    final app = assignedApplications[sliderIndex];
    if (app != null) {
      _configManager.updateSliderConfig(sliderIndex, app.processPath,
          sliderValue, sliderTags[sliderIndex], muteStates[sliderIndex]);
    } else {
      _configManager.updateSliderConfig(sliderIndex, null, sliderValue,
          sliderTags[sliderIndex], muteStates[sliderIndex]);
    }
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
        _configManager.adjustVolumeForAllInstances(appProcess, volumeLevel);

        muteStates[sliderIndex] = volumeLevel <= 0.009;
      }
    });
    _pendingAppVolumes.clear();

    if (_pendingDeviceVolume != null) {
      int volumeLevel = ((_pendingDeviceVolume! / 1024) * 100).round();
      Audio.setVolume(volumeLevel / 100, AudioDeviceType.output);
      _pendingDeviceVolume = null;

      for (var i = 0; i < sliderTags.length; i++) {
        if (sliderTags[i] == ConfigManager.TAG_DEFAULT_DEVICE ||
            sliderTags[i] == ConfigManager.TAG_MASTER_VOLUME) {
          muteStates[i] = volumeLevel <= 1;

          _configManager.updateSliderConfig(
              i, null, sliderValues[i], sliderTags[i], muteStates[i]);

          break;
        }
      }
    }
  }

  void adjustDeviceVolume(double sliderValue) {
    _pendingDeviceVolume = sliderValue;
    _scheduleVolumeUpdate();

    for (var i = 0; i < sliderTags.length; i++) {
      if (sliderTags[i] == ConfigManager.TAG_DEFAULT_DEVICE ||
          sliderTags[i] == ConfigManager.TAG_MASTER_VOLUME) {
        sliderValues[i] = sliderValue;
        _configManager.updateSliderConfig(
            i, null, sliderValue, sliderTags[i], sliderValue <= 0.009);
        break;
      }
    }
  }

  void setMuteState(int sliderIndex, bool isMuted) {
    muteStates[sliderIndex] = isMuted;
    ProcessVolume? app = assignedApplications[sliderIndex];
    _configManager.updateSliderConfig(sliderIndex, app?.processPath,
        sliderValues[sliderIndex], sliderTags[sliderIndex], isMuted);
  }

  void updateSliderConfig(int sliderIndex, double value, bool isMuted) {
    sliderValues[sliderIndex] = value;
    muteStates[sliderIndex] = isMuted;

    ProcessVolume? app = assignedApplications[sliderIndex];
    String tag = sliderTags[sliderIndex];

    _configManager.updateSliderConfig(
        sliderIndex, app?.processPath, value, tag, isMuted);
  }

  void resetSliderConfiguration(int sliderIndex) {
    assignedApplications.remove(sliderIndex);

    sliderValues[sliderIndex] = 0;
    sliderTags[sliderIndex] = ConfigManager.TAG_UNASSIGNED;
    muteStates[sliderIndex] = false;

    _configManager.removeSliderConfig(sliderIndex);

    print('Slider $sliderIndex reset and configuration removed');
  }

  void clearAllConfigurations() {
    assignedApplications.clear();
    sliderValues = List.filled(8, 0.5);
    sliderTags = List.filled(8, ConfigManager.TAG_DEFAULT_DEVICE);
    muteStates = List.filled(8, false);

    StorageManager.instance
      ..removeData('sliderValues')
      ..removeData('sliderTags')
      ..removeData('assignedApps')
      ..removeData('deviceVolume')
      ..removeData('sliderConfigs')
      ..removeData('buttonStates');

    print('All configurations cleared');
  }

  void dispose() {
    _pendingVolumeTimer?.cancel();
    _configManager.saveApplicationState(
        sliderValues,
        assignedApplications.entries.map((e) => e.value).toList(),
        sliderTags,
        muteStates);

    print('!!!!!! Attempted save on close????');
  }
}

import 'dart:async';
import 'package:mixlit/backend/application/ConfigManager.dart';
import 'package:win32audio/win32audio.dart';

/// The AppInstanceManager is purely here to fix the issue with some apps registering multiple sound sources under one executable (Discord for example)
class AppInstanceManager {
  static final AppInstanceManager _instance = AppInstanceManager._internal();
  static AppInstanceManager get instance => _instance;

  AppInstanceManager._internal();

  final ConfigManager _configManager = ConfigManager.instance;

  final Map<String, List<ProcessVolume>> _processInstancesCache = {};
  DateTime? _lastCacheUpdate;
  static const cacheDuration = Duration(seconds: 5); // Cache validity period

  Future<List<ProcessVolume>> getAppInstances(String processPath) async {
    final processName = _configManager.extractProcessName(processPath);
    print('Getting instances for process: $processName');

    if (_shouldUpdateCache()) {
      await _updateProcessCache();
    }

    final instances = _processInstancesCache[processName.toLowerCase()] ?? [];
    print('Found ${instances.length} instances of $processName');
    return instances;
  }

  Future<Map<String, List<ProcessVolume>>> getAllProcessGroups() async {
    if (_shouldUpdateCache()) {
      await _updateProcessCache();
    }

    return Map.from(_processInstancesCache);
  }

  bool _shouldUpdateCache() {
    if (_lastCacheUpdate == null) return true;

    final now = DateTime.now();
    return now.difference(_lastCacheUpdate!) > cacheDuration;
  }

  Future<void> _updateProcessCache() async {
    _processInstancesCache.clear();

    try {
      final allApps = await Audio.enumAudioMixer() ?? [];
      print('Updating process cache with ${allApps.length} apps');

      for (var app in allApps) {
        final processName =
            _configManager.extractProcessName(app.processPath).toLowerCase();

        if (!_processInstancesCache.containsKey(processName)) {
          _processInstancesCache[processName] = [];
        }

        _processInstancesCache[processName]!.add(app);
      }

      for (var entry in _processInstancesCache.entries) {
        print('Process ${entry.key} has ${entry.value.length} instances');
      }

      _lastCacheUpdate = DateTime.now();
    } catch (e) {
      print('Error updating process cache: $e');
    }
  }

  // filter duplicate apps in app selector menu
  Future<List<ProcessVolume>> getUniqueApps() async {
    final Map<String, ProcessVolume> uniqueApps = {};

    if (_shouldUpdateCache()) {
      await _updateProcessCache();
    }

    for (var group in _processInstancesCache.entries) {
      if (group.value.isNotEmpty) {
        uniqueApps[group.key] = group.value.first;
      }
    }

    return uniqueApps.values.toList();
  }

  Future<void> setVolumeForAllInstances(
      ProcessVolume appInstance, double volumeLevel) async {
    try {
      final processName = _configManager.normalizeProcessName(
          _configManager.extractProcessName(appInstance.processPath));

      final instances = await getAppInstances(appInstance.processPath);

      print(
          'Setting volume for ${instances.length} instances of $processName to $volumeLevel');

      for (var instance in instances) {
        double actualVolume = volumeLevel;
        if (volumeLevel <= 0.009) {
          actualVolume = 0.0001;
        }

        Audio.setAudioMixerVolume(instance.processId, actualVolume);
      }
    } catch (e) {
      print('Error setting volume for application instances: $e');
    }
  }

  Future<bool> hasMultipleInstances(ProcessVolume app) async {
    final instances = await getAppInstances(app.processPath);
    final result = instances.length > 1;
    print(
        'App ${_configManager.extractProcessName(app.processPath)} has multiple instances: $result');
    return result;
  }
}

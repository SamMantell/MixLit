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

  static const cacheDuration = Duration(seconds: 3);
  static const maxCacheEntries = 50;

  final Map<String, Timer> _volumeAdjustmentTimers = {};
  static const volumeAdjustmentDelay = Duration(milliseconds: 80);

  Future<List<ProcessVolume>> getAppInstances(String processPath) async {
    final processName = _configManager.extractProcessName(processPath);

    if (_shouldUpdateCache()) {
      await _updateProcessCache();
    }

    final instances = _processInstancesCache[processName.toLowerCase()] ?? [];
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
    try {
      final allApps = await Audio.enumAudioMixer() ?? [];

      // clear old cache
      if (_processInstancesCache.length > maxCacheEntries) {
        _processInstancesCache.clear();
      }

      final tempCache = <String, List<ProcessVolume>>{};

      for (var app in allApps) {
        final processName =
            _configManager.extractProcessName(app.processPath).toLowerCase();

        tempCache.putIfAbsent(processName, () => []).add(app);
      }

      _processInstancesCache.clear();
      _processInstancesCache.addAll(tempCache);

      _lastCacheUpdate = DateTime.now();
    } catch (e) {
      print('Error updating process cache: $e');
    }
  }

  Future<List<ProcessVolume>> getUniqueApps() async {
    if (_shouldUpdateCache()) {
      await _updateProcessCache();
    }

    final uniqueApps = <String, ProcessVolume>{};

    for (var entry in _processInstancesCache.entries) {
      if (entry.value.isNotEmpty) {
        uniqueApps[entry.key] = entry.value.first;
      }
    }

    return uniqueApps.values.toList();
  }

  Future<void> setVolumeForAllInstances(
      ProcessVolume appInstance, double volumeLevel) async {
    final processName = _configManager.normalizeProcessName(
        _configManager.extractProcessName(appInstance.processPath));

    _volumeAdjustmentTimers[processName]?.cancel();

    _volumeAdjustmentTimers[processName] =
        Timer(volumeAdjustmentDelay, () async {
      try {
        final instances = await getAppInstances(appInstance.processPath);

        if (instances.isEmpty) {
          return;
        }

        // batch process volume adjustments
        final futures = <Future<void>>[];

        for (var instance in instances) {
          futures.add(
              _adjustSingleVolumeWithRetry(instance.processId, volumeLevel));
        }

        await Future.wait(futures).timeout(
          const Duration(seconds: 2),
        );
      } catch (e) {
        _adjustSingleVolume(appInstance.processId, volumeLevel);
      } finally {
        _volumeAdjustmentTimers.remove(processName);
      }
    });
  }

  Future<void> _adjustSingleVolumeWithRetry(
      int processId, double volumeLevel) async {
    int attempts = 0;
    const maxAttempts = 3;

    while (attempts < maxAttempts) {
      try {
        _adjustSingleVolume(processId, volumeLevel);
        return;
      } catch (e) {
        attempts++;
        if (attempts >= maxAttempts) {
          rethrow;
        }
        await Future.delayed(const Duration(milliseconds: 10));
      }
    }
  }

  void _adjustSingleVolume(int processId, double volumeLevel) {
    double actualVolume = volumeLevel;
    if (volumeLevel <= 0.009) {
      actualVolume = 0.0001;
    }

    Audio.setAudioMixerVolume(processId, actualVolume);
  }

  Future<bool> hasMultipleInstances(ProcessVolume app) async {
    try {
      final instances = await getAppInstances(app.processPath);
      return instances.length > 1;
    } catch (e) {
      print('Error checking multiple instances: $e');
      return false;
    }
  }

  void clearCache() {
    _processInstancesCache.clear();
    _lastCacheUpdate = null;

    for (var timer in _volumeAdjustmentTimers.values) {
      timer.cancel();
    }
    _volumeAdjustmentTimers.clear();
  }

  void dispose() {
    clearCache();
  }
}

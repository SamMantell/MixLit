import 'dart:io';
import 'dart:typed_data';
import 'package:mixlit/backend/application/util/IconExtractor.dart';
import 'package:path/path.dart' as path;
import 'package:win32audio/win32audio.dart';
import 'package:mixlit/backend/application/data/StorageManager.dart';

class ConfigManager {
  static final ConfigManager _instance = ConfigManager._internal();
  static ConfigManager get instance => _instance;

  ConfigManager._internal();

  final _storageManager = StorageManager.instance;
  List<Map<String, dynamic>?> _sliderConfigsCache = List.filled(8, null);
  bool _sliderConfigsDirty = false;

  static const String TAG_APP = 'app';
  static const String TAG_DEFAULT_DEVICE = 'defaultDevice';
  static const String TAG_MASTER_VOLUME = 'mixlit.master';
  static const String TAG_ACTIVE_APP = 'mixlit.active';
  static const String TAG_UNASSIGNED = 'unassigned';

  //icon caching
  String? _iconCachePath;
  final Map<String, String> _iconPathCache = {};

  Future<String> get _getIconCachePath async {
    if (_iconCachePath != null) return _iconCachePath!;

    final configPath = await _storageManager.getConfigPath();
    _iconCachePath = path.join(configPath, '.cache');

    final cacheDir = Directory(_iconCachePath!);
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
      print('Created icon cache directory: $_iconCachePath');
    }

    return _iconCachePath!;
  }

  Future<void> cacheAppIcon(String processPath) async {
    try {
      final processName = extractProcessName(processPath);
      final normalizedName = normalizeProcessName(processName);

      if (_iconPathCache.containsKey(normalizedName)) {
        print('Icon already cached for $processName');
        return;
      }

      final cachePath = await _getIconCachePath;
      final iconFileName = '${normalizedName}_icon.ico';
      final cachedIconPath = path.join(cachePath, iconFileName);

      if (await File(cachedIconPath).exists()) {
        _iconPathCache[normalizedName] = cachedIconPath;
        print('Found existing cached icon for $processName at $cachedIconPath');
        return;
      }

      if (Platform.isWindows && await File(processPath).exists()) {
        final iconData = await _extractWindowsIcon(processPath);
        if (iconData != null) {
          await File(cachedIconPath).writeAsBytes(iconData);
          _iconPathCache[normalizedName] = cachedIconPath;
          print('Cached icon for $processName at $cachedIconPath');
        }
      }
    } catch (e) {
      print('Error caching icon for $processPath: $e');
    }
  }

  Future<Uint8List?> _extractWindowsIcon(String executablePath) async {
    try {
      final processName = extractProcessName(executablePath);
      final normalizedName = normalizeProcessName(processName);
      final cachePath = await _getIconCachePath;
      final iconFileName = '${normalizedName}_icon.ico';
      final cachedIconPath = path.join(cachePath, iconFileName);

      final success =
          await IconExtractor.extractIconToFile(executablePath, cachedIconPath);

      if (success) {
        final iconData = await File(cachedIconPath).readAsBytes();
        return Uint8List.fromList(iconData);
      }

      return null;
    } catch (e) {
      print('Error extracting icon from $executablePath: $e');
      return null;
    }
  }

  Future<String?> getCachedIconPath(String processPath) async {
    final processName = extractProcessName(processPath);
    final normalizedName = normalizeProcessName(processName);

    if (_iconPathCache.containsKey(normalizedName)) {
      final cachedPath = _iconPathCache[normalizedName]!;
      if (await File(cachedPath).exists()) {
        return cachedPath;
      } else {
        _iconPathCache.remove(normalizedName);
      }
    }

    final cachePath = await _getIconCachePath;
    final iconFileName = '${normalizedName}_icon.ico';
    final cachedIconPath = path.join(cachePath, iconFileName);

    if (await File(cachedIconPath).exists()) {
      _iconPathCache[normalizedName] = cachedIconPath;
      return cachedIconPath;
    }

    return null;
  }

  Future<String?> getCachedIconByProcessName(String processName) async {
    final normalizedName = normalizeProcessName(processName);

    if (_iconPathCache.containsKey(normalizedName)) {
      final cachedPath = _iconPathCache[normalizedName]!;
      if (await File(cachedPath).exists()) {
        return cachedPath;
      } else {
        _iconPathCache.remove(normalizedName);
      }
    }

    final cachePath = await _getIconCachePath;
    final iconFileName = '${normalizedName}_icon.ico';
    final cachedIconPath = path.join(cachePath, iconFileName);

    if (await File(cachedIconPath).exists()) {
      _iconPathCache[normalizedName] = cachedIconPath;
      return cachedIconPath;
    }

    return null;
  }

  Future<void> clearIconCache() async {
    try {
      final cachePath = await _getIconCachePath;
      final cacheDir = Directory(cachePath);

      if (await cacheDir.exists()) {
        await for (final entity in cacheDir.list()) {
          if (entity is File && entity.path.endsWith('_icon.ico')) {
            await entity.delete();
          }
        }
        _iconPathCache.clear();
        print('Icon cache cleared');
      }
    } catch (e) {
      print('Error clearing icon cache: $e');
    }
  }

  Future<void> cleanupUnusedIcons(List<String> activeProcPaths) async {
    try {
      final activeProcessNames = activeProcPaths
          .map((path) => normalizeProcessName(extractProcessName(path)))
          .toSet();

      final cachePath = await _getIconCachePath;
      final cacheDir = Directory(cachePath);

      if (await cacheDir.exists()) {
        await for (final entity in cacheDir.list()) {
          if (entity is File && entity.path.endsWith('_icon.ico')) {
            final fileName = path.basenameWithoutExtension(entity.path);
            final processName = fileName.replaceAll('_icon', '');

            if (!activeProcessNames.contains(processName)) {
              await entity.delete();
              _iconPathCache.remove(processName);
              print('Removed unused icon cache for $processName');
            }
          }
        }
      }
    } catch (e) {
      print('Error cleaning up unused icons: $e');
    }
  }

  Future<void> saveLastComPort(String portName) async {
    await _storageManager.saveData('last-com-port', portName);
    print('Saved last COM port: $portName');
  }

  Future<String?> getLastComPort() async {
    final port = await _storageManager.getData('last-com-port');
    print('Found last COM port on: $port');
    return port;
  }

  void updateSliderConfig(
      int sliderIndex, String? processPath, String sliderTag, bool isMuted,
      {double? volumeValue}) {
    if (_sliderConfigsCache.length <= sliderIndex) {
      _sliderConfigsCache = List.filled(8, null);
    }

    String? processName;
    if (processPath != null && sliderTag == TAG_APP) {
      processName = extractProcessName(processPath);
    }

    _sliderConfigsCache[sliderIndex] = {
      'processName': processName,
      'processPath': processPath, // Store full path
      'sliderTag': sliderTag,
      'isMuted': isMuted,
      'volumeValue': volumeValue,
    };

    _sliderConfigsDirty = true;
  }

  Future<void> saveAllSliderConfigs() async {
    if (!_sliderConfigsDirty) return;

    try {
      final sliderConfigs = <Map<String, dynamic>>[];

      for (int i = 0; i < _sliderConfigsCache.length; i++) {
        final config = _sliderConfigsCache[i];
        if (config != null) {
          final Map<String, dynamic> indexedConfig = {'index': i, ...config};
          sliderConfigs.add(indexedConfig);
        }
      }

      await _storageManager.saveData('sliderConfigs', sliderConfigs);
      print('Saved slider configurations to disk: $sliderConfigs');
      _sliderConfigsDirty = false;
    } catch (e) {
      print('Error saving slider configurations: $e');
    }
  }

  String extractProcessName(String processPath) {
    if (processPath.isEmpty) return '';

    final fileName = path.basename(processPath).toLowerCase();
    return fileName;
  }

  String normalizeProcessName(String processName) {
    return processName.toLowerCase().replaceAll('.exe', '');
  }

  Future<void> _loadSliderConfigsFromDisk() async {
    try {
      _sliderConfigsCache = List.filled(8, null);

      final storedConfigs = await _storageManager.getData('sliderConfigs');
      print('Loaded raw slider configs from disk: $storedConfigs');

      if (storedConfigs == null) return;

      for (final config in storedConfigs) {
        final index = config['index'];
        if (index != null && index >= 0 && index < 8) {
          _sliderConfigsCache[index] = Map<String, dynamic>.from(config);
          _sliderConfigsCache[index]!.remove('index');
          print(
              'Loaded config for slider $index: ${_sliderConfigsCache[index]}');
        }
      }

      _sliderConfigsDirty = false;
    } catch (e) {
      print('Error loading slider configurations: $e');
    }
  }

  Future<Map<String, dynamic>?> getSliderConfig(int sliderIndex) async {
    if (_sliderConfigsCache.any((c) => c == null)) {
      await _loadSliderConfigsFromDisk();
    }

    if (sliderIndex >= 0 && sliderIndex < _sliderConfigsCache.length) {
      final config = _sliderConfigsCache[sliderIndex];
      if (config == null) return null;

      return Map<String, dynamic>.from(config);
    }
    return null;
  }

  Future<void> removeSliderConfig(int sliderIndex) async {
    if (sliderIndex >= 0 && sliderIndex < _sliderConfigsCache.length) {
      _sliderConfigsCache[sliderIndex] = null;
      _sliderConfigsDirty = true;

      await saveAllSliderConfigs();
      print('Removed configuration for slider $sliderIndex');
    }
  }

  Future<void> resetSliderConfiguration(int sliderIndex) async {
    await removeSliderConfig(sliderIndex);
    print('Reset configuration for slider $sliderIndex');
  }

  Future<Map<String, dynamic>> loadAllSliderConfigs() async {
    if (_sliderConfigsCache.any((c) => c == null)) {
      await _loadSliderConfigsFromDisk();
    }

    final sliderValues = List<double>.filled(8, 100.0);
    final sliderTags = List<String>.filled(8, TAG_UNASSIGNED);
    final muteStates = List<bool>.filled(8, false);

    for (var i = 0; i < _sliderConfigsCache.length; i++) {
      final config = _sliderConfigsCache[i];
      if (config != null) {
        sliderValues[i] = config['volumeValue'] ?? 0.0;
        sliderTags[i] = config['sliderTag'] ?? TAG_UNASSIGNED;
        muteStates[i] = config['isMuted'] ?? false;
      }
    }

    return {
      'sliderValues': sliderValues,
      'sliderTags': sliderTags,
      'muteStates': muteStates,
      'sliderConfigs': _sliderConfigsCache
    };
  }

  Future<ProcessVolume?> findMatchingApp(
      List<ProcessVolume> runningApps, String? savedProcessName) async {
    if (savedProcessName == null || savedProcessName.isEmpty) {
      return null;
    }

    final normalizedSavedName = normalizeProcessName(savedProcessName);

    for (var app in runningApps) {
      final appName = extractProcessName(app.processPath);
      final normalizedAppName = normalizeProcessName(appName);

      if (normalizedAppName == normalizedSavedName) {
        return app;
      }
    }

    for (var app in runningApps) {
      final appName = extractProcessName(app.processPath);
      final normalizedAppName = normalizeProcessName(appName);

      if (normalizedAppName.contains(normalizedSavedName) ||
          normalizedSavedName.contains(normalizedAppName)) {
        return app;
      }
    }

    print('No match found for $savedProcessName');
    return null;
  }

  bool isDuplicateProcess(
      List<ProcessVolume?> assignedApps, ProcessVolume candidateApp) {
    final candidateName =
        normalizeProcessName(extractProcessName(candidateApp.processPath));

    for (var assignedApp in assignedApps) {
      if (assignedApp == null) continue;

      final assignedName =
          normalizeProcessName(extractProcessName(assignedApp.processPath));

      if (candidateName == assignedName) {
        return true;
      }
    }

    return false;
  }

  List<ProcessVolume> filterDuplicateApps(
      List<ProcessVolume> runningApps, List<ProcessVolume?> assignedApps) {
    final Map<String, ProcessVolume> uniqueApps = {};
    final List<ProcessVolume> result = [];

    for (var assignedApp in assignedApps) {
      if (assignedApp == null) continue;

      final appName =
          normalizeProcessName(extractProcessName(assignedApp.processPath));

      uniqueApps[appName] = assignedApp;
    }

    for (var app in runningApps) {
      final appName = normalizeProcessName(extractProcessName(app.processPath));

      if (!uniqueApps.containsKey(appName)) {
        uniqueApps[appName] = app;
        result.add(app);
      }
    }

    return result;
  }

  Future<void> adjustVolumeForAllInstances(
      ProcessVolume targetApp, double volumeLevel) async {
    try {
      final allRunningApps = await Audio.enumAudioMixer() ?? [];

      final targetName =
          normalizeProcessName(extractProcessName(targetApp.processPath));

      for (var app in allRunningApps) {
        final appName =
            normalizeProcessName(extractProcessName(app.processPath));

        if (appName == targetName) {
          if (volumeLevel <= 0.009) {
            volumeLevel = 0.0001;
          }

          Audio.setAudioMixerVolume(app.processId, volumeLevel);
        }
      }
    } catch (e) {
      print('Error adjusting volume for all instances: $e');
    }
  }

  Future<void> saveApplicationState(
      List<double> sliderValues,
      List<ProcessVolume?> assignedApps,
      List<String> sliderTags,
      List<bool> muteStates) async {
    for (var i = 0; i < sliderTags.length && i < 8; i++) {
      final tag = sliderTags[i];
      String? processPath;

      if (tag == TAG_APP &&
          i < assignedApps.length &&
          assignedApps[i] != null) {
        processPath = assignedApps[i]?.processPath;
      }

      updateSliderConfig(i, processPath, sliderTags[i], muteStates[i],
          volumeValue: sliderValues[i]);
    }

    await saveAllSliderConfigs();
    print('App state saved!!!!!');
  }

  Future<void> onApplicationAssigned(int sliderIndex, ProcessVolume app,
      double volume, String sliderTag, bool isMuted) async {
    updateSliderConfig(sliderIndex, app.processPath, sliderTag, isMuted,
        volumeValue: volume);

    await saveAllSliderConfigs();
    print('Application assigned to slider $sliderIndex and saved to disk');
  }

  Future<void> onSpecialSliderAssigned(
      int sliderIndex, String specialTag, double volume, bool isMuted) async {
    updateSliderConfig(sliderIndex, null, specialTag, isMuted,
        volumeValue: volume);

    await saveAllSliderConfigs();
    print(
        'Special feature "$specialTag" assigned to slider $sliderIndex and saved');
  }
}

import 'dart:io';
import 'dart:typed_data';
import 'package:mixlit/backend/application/util/IconExtractor.dart';
import 'package:mixlit/backend/application/audio/AppGroup.dart';
import 'package:path/path.dart' as path;
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
  static const String TAG_GROUP = 'mixlit.group';
  static const String TAG_INTEGRATION = 'integration';

  Future<void> saveAppGroup(AppGroup group) async {
    try {
      final existingGroups = await loadAppGroups();
      existingGroups.removeWhere((g) => g.id == group.id);
      existingGroups.add(group);
      final groupsJson = existingGroups.map((g) => g.toJson()).toList();
      await _storageManager.saveData('appGroups', groupsJson);
      print(
          'Saved app group: ${group.name} with ${group.processNames.length} apps');
    } catch (e, stackTrace) {
      print('Error saving app group: $e');
      print('Stack trace: $stackTrace');
    }
  }

  Future<List<AppGroup>> loadAppGroups() async {
    try {
      final groupsData = await _storageManager.getData('appGroups');

      if (groupsData == null) {
        print('No groups data found in storage');
        return [];
      }

      final List<dynamic> groupsList;
      if (groupsData is List) {
        groupsList = List<dynamic>.from(groupsData);
      } else {
        print('ERROR: Expected List but got ${groupsData.runtimeType}');
        return [];
      }

      print('Found ${groupsList.length} groups in raw data');

      final groups = <AppGroup>[];
      for (var i = 0; i < groupsList.length; i++) {
        try {
          final groupData = groupsList[i];
          if (groupData is Map) {
            final groupMap = Map<String, dynamic>.from(groupData);
            if (groupMap['processNames'] is! List<String>) {
              groupMap['processNames'] =
                  List<String>.from(groupMap['processNames'] as List);
            }
            print('Parsing group $i: ${groupMap['name']}');
            groups.add(AppGroup.fromJson(groupMap));
          } else {
            print('WARNING: Group $i is not a Map, skipping');
          }
        } catch (e) {
          print('Error parsing group $i: $e');
        }
      }

      return groups;
    } catch (e, stackTrace) {
      print('Error loading app groups: $e');
      print('Stack trace: $stackTrace');
      return [];
    }
  }

  Future<void> debugDumpStorage() async {
    await _storageManager.dumpStorageContents();
  }

  Future<void> deleteAppGroup(String groupId) async {
    try {
      final existingGroups = await loadAppGroups();
      existingGroups.removeWhere((g) => g.id == groupId);
      final groupsJson = existingGroups.map((g) => g.toJson()).toList();
      await _storageManager.saveData('appGroups', groupsJson);
      print('Deleted app group with ID: $groupId');
    } catch (e) {
      print('Error deleting app group: $e');
    }
  }

  Future<AppGroup?> getAppGroupById(String groupId) async {
    try {
      final groups = await loadAppGroups();
      return groups.where((g) => g.id == groupId).firstOrNull;
    } catch (e) {
      print('Error getting app group by ID: $e');
      return null;
    }
  }

  void updateSliderConfigForIntegration(
    int sliderIndex,
    Map<String, dynamic> integrationData,
    bool isMuted,
  ) {
    final config = {
      'sliderTag': TAG_INTEGRATION,
      'integration': integrationData,
      'isMuted': isMuted,
    };

    if (integrationData['type'] == 'spotify') {
      config['brandColor'] = '#1DB954';
      config['iconPath'] =
          'lib/frontend/assets/images/logo/integrations/Spotify.png';
    } else if (integrationData['type'] == 'sonos') {
      config['brandColor'] = '#D8A158';
      config['iconPath'] =
          'lib/frontend/assets/images/logo/integrations/Sonos.png';
    }

    _sliderConfigsCache[sliderIndex] = config;
    _sliderConfigsDirty = true;
    saveAllSliderConfigs();
  }

  void updateSliderConfigForGroup(int sliderIndex, AppGroup group, bool isMuted,
      {double? volumeValue}) {
    updateSliderConfig(sliderIndex, null, TAG_GROUP, isMuted,
        volumeValue: volumeValue, groupId: group.id);
  }

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
          .map((p) => normalizeProcessName(extractProcessName(p)))
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

  void updateSliderConfig(
    int sliderIndex,
    String? processPath,
    String sliderTag,
    bool isMuted, {
    double? volumeValue,
    String? groupId,
  }) {
    try {
      final config = <String, dynamic>{
        'sliderTag': sliderTag,
        'isMuted': isMuted,
      };

      if (sliderTag == TAG_APP && processPath != null) {
        config['processName'] = extractProcessName(processPath);
      } else if (sliderTag == TAG_GROUP && groupId != null) {
        config['groupId'] = groupId;
      }

      _saveSliderConfig(sliderIndex, config);
      print('Updated slider $sliderIndex config: $sliderTag'
          '${groupId != null ? ' (group: $groupId)' : ''}');
    } catch (e) {
      print('Error updating slider config: $e');
    }
  }

  void _saveSliderConfig(int sliderIndex, Map<String, dynamic> config) {
    if (sliderIndex >= 0 && sliderIndex < _sliderConfigsCache.length) {
      _sliderConfigsCache[sliderIndex] = config;
      _sliderConfigsDirty = true;
      Future.delayed(const Duration(milliseconds: 100), saveAllSliderConfigs);
    }
  }

  Future<void> saveAllSliderConfigs() async {
    if (!_sliderConfigsDirty) return;

    try {
      final sliderConfigs = <Map<String, dynamic>>[];

      for (int i = 0; i < _sliderConfigsCache.length; i++) {
        final config = _sliderConfigsCache[i];
        if (config != null) {
          sliderConfigs.add({'index': i, ...config});
        }
      }

      await _storageManager.saveData('sliderConfigs', sliderConfigs);
      print('Saved slider configurations to disk: $sliderConfigs');
      _sliderConfigsDirty = false;
    } catch (e) {
      print('Error saving slider configurations: $e');
    }
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

  Future<Map<String, dynamic>> _loadAllSliderConfigs() async {
    try {
      await _loadSliderConfigsFromDisk();

      final List<double> sliderValues = List.filled(8, 0.5);
      final List<String> sliderTags = List.filled(8, TAG_DEFAULT_DEVICE);
      final List<bool> muteStates = List.filled(8, false);
      final List<Map<String, dynamic>?> sliderConfigs = List.filled(8, null);

      for (int i = 0; i < 8; i++) {
        final config = _sliderConfigsCache[i];
        if (config != null) {
          sliderConfigs[i] = config;
          sliderTags[i] = config['sliderTag'] ?? TAG_DEFAULT_DEVICE;
          muteStates[i] = config['isMuted'] ?? false;
          sliderValues[i] = 0.1;
        }
      }

      return {
        'sliderValues': sliderValues,
        'sliderTags': sliderTags,
        'muteStates': muteStates,
        'sliderConfigs': sliderConfigs,
      };
    } catch (e) {
      print('Error in _loadAllSliderConfigs: $e');
      return _getDefaultConfigs();
    }
  }

  Map<String, dynamic> _getDefaultConfigs() {
    return {
      'sliderValues': List.filled(8, 0.5),
      'sliderTags': List.filled(8, TAG_DEFAULT_DEVICE),
      'muteStates': List.filled(8, false),
      'sliderConfigs': List.filled(8, null),
    };
  }

  Future<Map<String, dynamic>> loadAllSliderConfigs() async {
    try {
      final configs = await _loadAllSliderConfigs();

      for (int i = 0; i < (configs['sliderConfigs'] as List).length; i++) {
        final config = configs['sliderConfigs'][i];
        if (config != null && config['sliderTag'] == TAG_GROUP) {
          final groupId = config['groupId'];
          if (groupId != null) {
            final group = await getAppGroupById(groupId);
            if (group != null) {
              config['group'] = group.toJson();
            } else {
              // Group was deleted, reset slider
              configs['sliderConfigs'][i] = null;
              configs['sliderTags'][i] = TAG_UNASSIGNED;
            }
          }
        }
      }

      return configs;
    } catch (e) {
      print('Error loading slider configs with groups: $e');
      return _getDefaultConfigs();
    }
  }

  String extractProcessName(String processPath) {
    if (processPath.isEmpty) return '';
    return path.basename(processPath).toLowerCase();
  }

  String normalizeProcessName(String processName) {
    return processName.toLowerCase().replaceAll('.exe', '');
  }
}

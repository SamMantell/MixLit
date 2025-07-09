import 'dart:async';
import 'dart:io';

import 'package:mixlit/backend/application/data/ConfigManager.dart';
import 'package:mixlit/backend/application/data/StorageManager.dart';
import 'package:win32audio/win32audio.dart';

class MissingApp {
  final String processName;
  final String? processPath;
  final String? cachedIconPath;
  final String displayName;
  final double volumeValue;
  final bool isMuted;

  MissingApp({
    required this.processName,
    this.processPath,
    this.cachedIconPath,
    required this.displayName,
    required this.volumeValue,
    required this.isMuted,
  });
}

class ApplicationManager {
  Map<int, ProcessVolume> assignedApplications = {};
  Map<int, MissingApp> missingApplications = {};
  List<double> sliderValues = List.filled(8, 0.5);
  List<String> sliderTags = List.filled(8, 'defaultDevice');
  List<bool> muteStates = List.filled(8, false);

  //Audio session monitoring
  Timer? _audioSessionMonitor;
  static const Duration _monitorInterval = Duration(seconds: 2);

  final Map<int, DateTime> _recentlyRestoredApps = {};
  static const Duration _restorationGracePeriod = Duration(seconds: 5);

  final Map<int, int> _failedValidationCounts = {};
  static const int _maxFailedValidations = 3;

  // rate limiting due to windows buffering volume requests
  static const int RATE_LIMIT_MS = 40;
  DateTime _lastVolumeAdjustment = DateTime.now();
  Timer? _pendingVolumeTimer;
  final Map<int, double> _pendingAppVolumes = {};
  double? _pendingDeviceVolume;

  bool _isConfigLoaded = false;
  final Completer<void> _configLoadCompleter = Completer<void>();

  // flags for when volume restoration should occur
  bool _allowVolumeRestoration = false;
  bool _isInitialStartup = true;
  bool _deviceJustConnected = false;

  final ConfigManager _configManager = ConfigManager.instance;

  ApplicationManager() {
    _loadSavedConfiguration();
    _startAudioSessionMonitoring();
  }

  Future<void> get configLoaded => _configLoadCompleter.future;

  void enableVolumeRestorationOnDeviceConnect() {
    print('Device connected - enabling volume restoration');
    _deviceJustConnected = true;
    _allowVolumeRestoration = true;
    _isInitialStartup = false;
  }

  void enableVolumeRestorationForUserAction() {
    if (!_isInitialStartup) {
      _allowVolumeRestoration = true;
    }
  }

  void _startAudioSessionMonitoring() {
    _audioSessionMonitor = Timer.periodic(_monitorInterval, (timer) async {
      await _monitorAudioSessions();
    });
    print('Audio session monitoring started');
  }

  Future<void> _monitorAudioSessions() async {
    try {
      final now = DateTime.now();
      _recentlyRestoredApps.removeWhere((sliderIndex, restorationTime) =>
          now.difference(restorationTime) > _restorationGracePeriod);

      if (missingApplications.isNotEmpty) {
        await _checkForMissingAudioSessions();
      }

      await _validateAssignedApplications();
    } catch (e) {
      print('Error monitoring audio sessions: $e');
    }
  }

  Future<void> _validateAssignedApplications() async {
    final List<int> potentiallyMissingApps = [];

    for (var entry in assignedApplications.entries) {
      final sliderIndex = entry.key;
      final app = entry.value;

      if (_recentlyRestoredApps.containsKey(sliderIndex)) {
        continue;
      }

      final isStillControllable = await _testAudioSessionControl(app);

      if (!isStillControllable) {
        _failedValidationCounts[sliderIndex] =
            (_failedValidationCounts[sliderIndex] ?? 0) + 1;

        print(
            'App ${app.processPath} failed audio session validation (attempt ${_failedValidationCounts[sliderIndex]})');

        if (_failedValidationCounts[sliderIndex]! >= _maxFailedValidations) {
          print(
              'App ${app.processPath} failed validation $_maxFailedValidations times, marking as missing');
          potentiallyMissingApps.add(sliderIndex);
        }
      } else {
        _failedValidationCounts.remove(sliderIndex);
      }
    }

    for (var sliderIndex in potentiallyMissingApps) {
      await _moveAppToMissing(sliderIndex);
    }
  }

  Future<bool> _testAudioSessionControl(ProcessVolume app) async {
    try {
      if (!await _isAppInAudioEnumeration(app)) {
        print(
            'App ${app.processPath} (PID: ${app.processId}) not found in audio enumeration');
        return false;
      }

      return await _testVolumeControl(app);
    } catch (e) {
      print('Audio session control test failed for ${app.processPath}: $e');
      return false;
    }
  }

  Future<bool> _isAppInAudioEnumeration(ProcessVolume app) async {
    try {
      final allApps = await Audio.enumAudioMixer() ?? [];

      final matchingApp =
          allApps.where((a) => a.processId == app.processId).firstOrNull;

      if (matchingApp != null) {
        final normalizedStoredPath = _configManager.normalizeProcessName(
            _configManager.extractProcessName(app.processPath));
        final normalizedFoundPath = _configManager.normalizeProcessName(
            _configManager.extractProcessName(matchingApp.processPath));

        return normalizedStoredPath == normalizedFoundPath;
      }

      return false;
    } catch (e) {
      print('Error checking app in audio enumeration: $e');
      return false;
    }
  }

  Future<bool> _testVolumeControl(ProcessVolume app) async {
    try {
      final sliderIndex = _getSliderIndexForApp(app);
      if (sliderIndex == -1) return false;

      final currentStoredVolume = sliderValues[sliderIndex] / 1024;

      if (_allowVolumeRestoration) {
        Audio.setAudioMixerVolume(app.processId, currentStoredVolume);
      }

      return true;
    } catch (e) {
      print('Volume control test failed for ${app.processPath}: $e');
      return false;
    }
  }

  int _getSliderIndexForApp(ProcessVolume app) {
    for (var entry in assignedApplications.entries) {
      if (entry.value.processId == app.processId) {
        return entry.key;
      }
    }
    return -1;
  }

  Future<void> _moveAppToMissing(int sliderIndex) async {
    final app = assignedApplications[sliderIndex];
    if (app == null) return;

    print(
        'Moving app ${app.processPath} to missing applications (slider $sliderIndex)');

    //new instance of a missing app
    final missingApp = MissingApp(
      processName: _configManager.extractProcessName(app.processPath),
      processPath: app.processPath,
      cachedIconPath: await _configManager.getCachedIconPath(app.processPath),
      displayName: _createDisplayName(
          _configManager.extractProcessName(app.processPath)),
      volumeValue: sliderValues[sliderIndex],
      isMuted: muteStates[sliderIndex],
    );

    missingApplications[sliderIndex] = missingApp;
    assignedApplications.remove(sliderIndex);
    _failedValidationCounts.remove(sliderIndex);
  }

  Future<void> _checkForMissingAudioSessions() async {
    try {
      final runningApps = await getRunningApplicationsWithAudio();
      final foundApps = <int>[];

      for (var entry in missingApplications.entries) {
        final sliderIndex = entry.key;
        final missingApp = entry.value;

        final matchingApp = await _configManager.findMatchingApp(
            runningApps, missingApp.processName);

        if (matchingApp != null) {
          print(
              'Found missing app ${missingApp.processName} for slider $sliderIndex');

          assignedApplications[sliderIndex] = matchingApp;

          _recentlyRestoredApps[sliderIndex] = DateTime.now();

          final currentSliderValue = sliderValues[sliderIndex];
          final isMuted = missingApp.isMuted;

          print(
              'Found app restoration: currentSliderValue=$currentSliderValue, muted=$isMuted, allowVolumeRestoration=$_allowVolumeRestoration');

          if (_allowVolumeRestoration) {
            Timer(const Duration(milliseconds: 500), () async {
              await _restoreVolumeForApp(
                  sliderIndex, matchingApp, currentSliderValue, isMuted);
            });
          } else {
            print('Skipping volume restoration during startup for found app');
          }

          foundApps.add(sliderIndex);
        }
      }

      for (var sliderIndex in foundApps) {
        missingApplications.remove(sliderIndex);
        print('Removed slider $sliderIndex from missing applications list');
      }

      if (missingApplications.isEmpty && foundApps.isNotEmpty) {
        print('All missing applications found and restored');
      }
    } catch (e) {
      print('Error checking for missing audio sessions: $e');
    }
  }

  Future<void> _restoreVolumeForApp(int sliderIndex, ProcessVolume app,
      double volumeValue, bool isMuted) async {
    try {
      print(
          'Starting volume restoration for slider $sliderIndex: ${app.processPath}');

      sliderValues[sliderIndex] = volumeValue;
      muteStates[sliderIndex] = isMuted;

      await Future.delayed(const Duration(milliseconds: 200));

      double targetVolume;
      if (isMuted) {
        targetVolume = 0.0001;
      } else {
        targetVolume = volumeValue / 1024;
        if (targetVolume <= 0.009) {
          targetVolume = 0.0001;
        }
      }

      bool success = false;
      int attempts = 0;
      const maxAttempts = 3;

      while (!success && attempts < maxAttempts) {
        try {
          await _configManager.adjustVolumeForAllInstances(app, targetVolume);
          success = true;
          print(
              'Successfully restored and synced volume for ${app.processPath}: target=$targetVolume, muted=$isMuted (attempt ${attempts + 1})');
        } catch (e) {
          attempts++;
          print('Volume restoration attempt $attempts failed: $e');
          if (attempts < maxAttempts) {
            await Future.delayed(Duration(milliseconds: 100 * attempts));
          }
        }
      }

      if (!success) {
        print(
            'Failed to restore volume after $maxAttempts attempts, trying direct fallback');
        try {
          Audio.setAudioMixerVolume(app.processId, targetVolume);
          print('Fallback volume setting succeeded');
        } catch (e) {
          print('Fallback volume setting also failed: $e');
        }
      }

      _configManager.updateSliderConfig(
          sliderIndex, app.processPath, sliderTags[sliderIndex], isMuted,
          volumeValue: volumeValue);

      _notifyAppRestored(sliderIndex, app);

      print('Volume restoration and sync completed for slider $sliderIndex');
    } catch (e) {
      print('Error in volume restoration for app: $e');
    }
  }

  Function(int sliderIndex, ProcessVolume app)? onAppRestored;

  void _notifyAppRestored(int sliderIndex, ProcessVolume app) {
    if (onAppRestored != null) {
      onAppRestored!(sliderIndex, app);
    }
  }

  String _createDisplayName(String processName) {
    String displayName = processName.replaceAll('.exe', '');
    displayName = displayName.replaceAll('_', ' ');
    displayName = displayName
        .split(' ')
        .map((word) =>
            word.isNotEmpty ? word[0].toUpperCase() + word.substring(1) : '')
        .join(' ');
    return displayName;
  }

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
            _recentlyRestoredApps[i] = DateTime.now();
            print(
                'Found and assigned app ${matchingApp.processPath} to slider $i (NO volume restoration during startup)');

            //DONT restore volume during startup - just assign app
          } else {
            await _createMissingAppEntry(i, config);
          }
        } else if (sliderTag == ConfigManager.TAG_DEFAULT_DEVICE ||
            sliderTag == ConfigManager.TAG_MASTER_VOLUME) {
          print(
              'Device/master volume slider $i found - NO restoration during startup');
          // DON'T restore device volume during startup
        } else if (sliderTag == ConfigManager.TAG_ACTIVE_APP) {
          print('Restored active app control for slider $i');
        } else {
          sliderTags[i] = ConfigManager.TAG_UNASSIGNED;
        }
      }

      _isConfigLoaded = true;
      _configLoadCompleter.complete();

      // marks initial startup as complete after short delay
      Timer(const Duration(seconds: 1), () {
        _isInitialStartup = false;
        print(
            'Initial startup completed - volume restoration will be enabled for user actions');
      });

      print(
          'Configuration loading completed successfully (volumes NOT restored)');

      if (missingApplications.isNotEmpty) {
        print(
            'Missing applications: ${missingApplications.keys.map((k) => '$k: ${missingApplications[k]!.displayName}').join(', ')}');
      }
    } catch (e) {
      print('Error loading saved configuration: $e');
      if (!_configLoadCompleter.isCompleted) {
        _configLoadCompleter.complete();
      }
    }
  }

  Future<void> _createMissingAppEntry(
      int sliderIndex, Map<String, dynamic> config) async {
    final processName = config['processName'] as String;
    final volumeValue = sliderValues[sliderIndex];
    final isMuted = muteStates[sliderIndex];

    String? cachedIconPath;
    String? fullProcessPath;

    if (config.containsKey('processPath')) {
      fullProcessPath = config['processPath'];
      cachedIconPath =
          await _configManager.getCachedIconPath(fullProcessPath.toString());
    } else {
      cachedIconPath =
          await _configManager.getCachedIconByProcessName(processName);
    }

    final displayName = _createDisplayName(processName);

    final missingApp = MissingApp(
      processName: processName,
      processPath: fullProcessPath,
      cachedIconPath: cachedIconPath,
      displayName: displayName,
      volumeValue: volumeValue,
      isMuted: isMuted,
    );

    missingApplications[sliderIndex] = missingApp;
    sliderTags[sliderIndex] = ConfigManager.TAG_APP;

    print('Created missing app entry for slider $sliderIndex: $displayName');
    if (cachedIconPath != null) {
      print('Found cached icon at: $cachedIconPath');
    }
  }

  Map<String, dynamic> getSliderDisplayInfo(int sliderIndex) {
    if (assignedApplications.containsKey(sliderIndex)) {
      final app = assignedApplications[sliderIndex]!;
      final processName = _configManager.extractProcessName(app.processPath);
      final displayName = _createDisplayName(processName);

      return {
        'type': 'active_app',
        'displayName': displayName,
        'processName': processName,
        'processPath': app.processPath,
        'isActive': true,
        'cachedIconPath': null,
      };
    }

    if (missingApplications.containsKey(sliderIndex)) {
      final missingApp = missingApplications[sliderIndex]!;
      return {
        'type': 'missing_app',
        'displayName': missingApp.displayName,
        'processName': missingApp.processName,
        'processPath': missingApp.processPath,
        'isActive': false,
        'cachedIconPath': missingApp.cachedIconPath,
      };
    }

    final tag = sliderTags[sliderIndex];
    if (tag == ConfigManager.TAG_DEFAULT_DEVICE) {
      return {
        'type': 'device',
        'displayName': 'Default Device',
        'isActive': true,
      };
    } else if (tag == ConfigManager.TAG_MASTER_VOLUME) {
      return {
        'type': 'master',
        'displayName': 'Master Volume',
        'isActive': true,
      };
    } else if (tag == ConfigManager.TAG_ACTIVE_APP) {
      return {
        'type': 'active_app_control',
        'displayName': 'Active App',
        'isActive': true,
      };
    }

    return {
      'type': 'unassigned',
      'displayName': 'Unassigned',
      'isActive': false,
    };
  }

  Future<List<ProcessVolume>> getRunningApplicationsWithAudio() async {
    final apps = await Audio.enumAudioMixer() ?? [];

    // filter duplicate applications based on process name
    final filteredApps = _configManager.filterDuplicateApps(
        apps, assignedApplications.entries.map((e) => e.value).toList());

    return filteredApps;
  }

  void assignApplicationToSlider(
      int sliderIndex, ProcessVolume processVolume) async {
    assignedApplications[sliderIndex] = processVolume;
    sliderTags[sliderIndex] = ConfigManager.TAG_APP;

    missingApplications.remove(sliderIndex);

    _recentlyRestoredApps[sliderIndex] = DateTime.now();

    _failedValidationCounts.remove(sliderIndex);

    print('Assigned app ${processVolume.processPath} to slider $sliderIndex');

    await _configManager.cacheAppIcon(processVolume.processPath);

    _configManager.onApplicationAssigned(
        sliderIndex,
        processVolume,
        sliderValues[sliderIndex],
        ConfigManager.TAG_APP,
        muteStates[sliderIndex]);

    enableVolumeRestorationForUserAction();
  }

  void assignSpecialFeatureToSlider(int sliderIndex, String featureTag) {
    assignedApplications.remove(sliderIndex);
    missingApplications.remove(sliderIndex);
    _recentlyRestoredApps.remove(sliderIndex);
    _failedValidationCounts.remove(sliderIndex);

    sliderTags[sliderIndex] = featureTag;
    print('Assigned special feature "$featureTag" to slider $sliderIndex');

    _configManager.onSpecialSliderAssigned(sliderIndex, featureTag,
        sliderValues[sliderIndex], muteStates[sliderIndex]);

    enableVolumeRestorationForUserAction();
  }

  void adjustVolume(int sliderIndex, double sliderValue,
      {bool fromRestore = false}) {
    sliderValues[sliderIndex] = sliderValue;

    if (_allowVolumeRestoration || _deviceJustConnected) {
      _pendingAppVolumes[sliderIndex] = sliderValue;
      _scheduleVolumeUpdate();
    }

    final app = assignedApplications[sliderIndex];
    if (app != null) {
      //auto-detect mute state if NOT restoring
      bool muteState =
          fromRestore ? muteStates[sliderIndex] : (sliderValue <= 0.009);
      _configManager.updateSliderConfig(
          sliderIndex, app.processPath, sliderTags[sliderIndex], muteState);
    } else {
      bool muteState =
          fromRestore ? muteStates[sliderIndex] : (sliderValue <= 0.009);
      _configManager.updateSliderConfig(
          sliderIndex, null, sliderTags[sliderIndex], muteState);
    }

    if (_deviceJustConnected) {
      _deviceJustConnected = false;
    }

    enableVolumeRestorationForUserAction();
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
          _configManager.updateSliderConfig(
              i, null, sliderTags[i], muteStates[i]);
          break;
        }
      }
    }
  }

  void adjustDeviceVolume(double sliderValue, {bool fromRestore = false}) {
    if (_allowVolumeRestoration || _deviceJustConnected) {
      _pendingDeviceVolume = sliderValue;
      _scheduleVolumeUpdate();
    }

    for (var i = 0; i < sliderTags.length; i++) {
      if (sliderTags[i] == ConfigManager.TAG_DEFAULT_DEVICE ||
          sliderTags[i] == ConfigManager.TAG_MASTER_VOLUME) {
        sliderValues[i] = sliderValue;

        //auto-detect mute state if NOT restoring from saved config
        if (!fromRestore) {
          _configManager.updateSliderConfig(
              i, null, sliderTags[i], sliderValue <= 0.009);
        } else {
          _configManager.updateSliderConfig(
              i, null, sliderTags[i], muteStates[i]);
        }
        break;
      }
    }

    if (_deviceJustConnected) {
      _deviceJustConnected = false;
    }

    enableVolumeRestorationForUserAction();
  }

  void setMuteState(int sliderIndex, bool isMuted) {
    muteStates[sliderIndex] = isMuted;
    ProcessVolume? app = assignedApplications[sliderIndex];
    _configManager.updateSliderConfig(
        sliderIndex, app?.processPath, sliderTags[sliderIndex], isMuted);

    enableVolumeRestorationForUserAction();
  }

  void updateSliderConfig(int sliderIndex, double value, bool isMuted) {
    sliderValues[sliderIndex] = value;
    muteStates[sliderIndex] = isMuted;

    ProcessVolume? app = assignedApplications[sliderIndex];
    String tag = sliderTags[sliderIndex];

    _configManager.updateSliderConfig(
        sliderIndex, app?.processPath, tag, isMuted);

    enableVolumeRestorationForUserAction();
  }

  void resetSliderConfiguration(int sliderIndex) {
    assignedApplications.remove(sliderIndex);
    missingApplications.remove(sliderIndex);
    _recentlyRestoredApps.remove(sliderIndex);
    _failedValidationCounts.remove(sliderIndex);

    sliderValues[sliderIndex] = 0;
    sliderTags[sliderIndex] = ConfigManager.TAG_UNASSIGNED;
    muteStates[sliderIndex] = false;

    _configManager.removeSliderConfig(sliderIndex);

    print('Slider $sliderIndex reset and configuration removed');

    enableVolumeRestorationForUserAction();
  }

  void clearAllConfigurations() {
    assignedApplications.clear();
    missingApplications.clear();
    _recentlyRestoredApps.clear();
    _failedValidationCounts.clear();
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

    enableVolumeRestorationForUserAction();
  }

  void dispose() {
    _audioSessionMonitor?.cancel();
    _pendingVolumeTimer?.cancel();
    _configManager.saveApplicationState(
        sliderValues,
        assignedApplications.entries.map((e) => e.value).toList(),
        sliderTags,
        muteStates);

    print('!!!!!! Attempted save on close????');
  }
}

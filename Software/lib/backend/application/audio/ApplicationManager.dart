import 'dart:async';
import 'package:mixlit/backend/application/data/ConfigManager.dart';
import 'package:mixlit/backend/application/data/StorageManager.dart';
import 'package:mixlit/backend/application/audio/audio_service_client.dart';
import 'package:mixlit/frontend/menus/AssignApplicationMenu.dart';

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
  final AudioServiceClient _serviceClient;
  final ConfigManager _configManager = ConfigManager.instance;

  AudioServiceClient get audioServiceClient => _serviceClient;

  Map<int, AudioSessionInfo> assignedApplications = {};
  Map<int, MissingApp> missingApplications = {};
  Map<int, AppGroup> assignedGroups = {};
  List<double> sliderValues = List.filled(8, 0.5);
  List<String> sliderTags = List.filled(8, 'defaultDevice');
  List<bool> muteStates = List.filled(8, false);

  StreamSubscription? _sessionAddedSubscription;
  StreamSubscription? _sessionRemovedSubscription;
  StreamSubscription? _sessionUpdatedSubscription;

  Timer? _audioSessionMonitor;
  static const Duration _monitorInterval = Duration(seconds: 2);

  final Map<int, DateTime> _recentlyRestoredApps = {};
  static const Duration _restorationGracePeriod = Duration(seconds: 5);

  bool _isConfigLoaded = false;
  final Completer<void> _configLoadCompleter = Completer<void>();

  ApplicationManager(this._serviceClient) {
    _initialize();
  }

  Future<void> get configLoaded => _configLoadCompleter.future;

  Future<void> _initialize() async {
    await _serviceClient.connect();

    // listen for session changes
    _sessionAddedSubscription =
        _serviceClient.sessionAdded.listen(_onSessionAdded);
    _sessionRemovedSubscription =
        _serviceClient.sessionRemoved.listen(_onSessionRemoved);
    _sessionUpdatedSubscription =
        _serviceClient.sessionUpdated.listen(_onSessionUpdated);

    _startAudioSessionMonitoring();

    await _loadSavedConfiguration();
  }

  void _onSessionAdded(AudioSessionInfo session) {
    //TODO: Update logging to show up on in-app terminal
    print('New session detected: ${session.processName}');
    _checkForMissingAudioSessions();
  }

  void _onSessionRemoved(AudioSessionInfo session) {
    //TODO: Update logging to show up on in-app terminal
    print('Session removed: ${session.processName}');
    _validateAssignedApplications();
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

      // Force refresh sessions from service
      await _serviceClient.refreshSessions();

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
    final allSessions = await _serviceClient.getAllSessions();

    for (var entry in assignedApplications.entries) {
      final sliderIndex = entry.key;
      final app = entry.value;

      if (_recentlyRestoredApps.containsKey(sliderIndex)) {
        continue;
      }

      // Only check by process name, not PID since PID changes on restart
      final stillActive = allSessions.any((session) =>
          _configManager.normalizeProcessName(session.processName) ==
          _configManager.normalizeProcessName(app.processName));

      if (!stillActive) {
        print('App ${app.processName} session no longer active');
        potentiallyMissingApps.add(sliderIndex);
      } else {
        // Update the stored session with the new PID if it changed
        final currentSession = allSessions.firstWhere((session) =>
            _configManager.normalizeProcessName(session.processName) ==
            _configManager.normalizeProcessName(app.processName));

        if (currentSession.processId != app.processId) {
          print(
              'Updating PID for ${app.processName}: ${app.processId} -> ${currentSession.processId}');
          assignedApplications[sliderIndex] = currentSession;
        }
      }
    }

    for (var sliderIndex in potentiallyMissingApps) {
      await _moveAppToMissing(sliderIndex);
    }
  }

  Future<void> _moveAppToMissing(int sliderIndex) async {
    final app = assignedApplications[sliderIndex];
    if (app == null) return;

    print(
        'Moving app ${app.processPath} to missing applications (slider $sliderIndex)');

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
  }

  Future<void> _checkForMissingAudioSessions() async {
    try {
      final runningApps = await getRunningApplicationsWithAudio();
      final foundApps = <int>[];

      for (var entry in missingApplications.entries) {
        final sliderIndex = entry.key;
        final missingApp = entry.value;

        // Find by process name only, not path or PID
        final matchingApps = runningApps
            .where((app) =>
                _configManager.normalizeProcessName(app.processName) ==
                _configManager.normalizeProcessName(missingApp.processName))
            .toList();

        if (matchingApps.isNotEmpty) {
          // Take the first matching app (or implement logic to choose the best match)
          final matchingApp = matchingApps.first;

          print(
              'Found missing app ${missingApp.processName} for slider $sliderIndex with new PID ${matchingApp.processId}');

          assignedApplications[sliderIndex] = matchingApp;
          _recentlyRestoredApps[sliderIndex] = DateTime.now();

          await _restoreVolumeForApp(
            sliderIndex,
            matchingApp,
            missingApp.volumeValue,
            missingApp.isMuted,
          );

          foundApps.add(sliderIndex);
        }
      }

      for (var sliderIndex in foundApps) {
        missingApplications.remove(sliderIndex);
        print('Removed slider $sliderIndex from missing applications list');
      }
    } catch (e) {
      print('Error checking for missing audio sessions: $e');
    }
  }

  Future<void> _restoreVolumeForApp(
    int sliderIndex,
    AudioSessionInfo app,
    double volumeValue,
    bool isMuted,
  ) async {
    try {
      print('Restoring volume for slider $sliderIndex: ${app.processPath}');

      sliderValues[sliderIndex] = volumeValue;
      muteStates[sliderIndex] = isMuted;

      await Future.delayed(const Duration(milliseconds: 200));

      if (isMuted) {
        await setMuteState(sliderIndex, true);
      } else {
        // Restore volume
        await adjustVolume(sliderIndex, volumeValue);
      }

      _configManager.updateSliderConfig(
        sliderIndex,
        app.processPath,
        sliderTags[sliderIndex],
        isMuted,
      );

      print('Volume restoration completed for slider $sliderIndex');
    } catch (e) {
      print('Error in volume restoration for app: $e');
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

      //TODO: Fix connection handshake & hardware-deterministic volume definition
      sliderValues = List.filled(8, 0.1); // Default values
      sliderTags = List<String>.from(configs['sliderTags']);
      muteStates = List<bool>.from(configs['muteStates']);

      final sliderConfigs = configs['sliderConfigs'];
      List<AudioSessionInfo> runningApps = [];

      try {
        runningApps = await getRunningApplicationsWithAudio();
        print('Found ${runningApps.length} running apps with audio');
      } catch (e) {
        print('Error getting running applications: $e');
      }

      for (var i = 0; i < sliderConfigs.length; i++) {
        final config = sliderConfigs[i];
        if (config == null) {
          sliderTags[i] = ConfigManager.TAG_UNASSIGNED;
          continue;
        }

        final sliderTag = config['sliderTag'] ?? 'unassigned';
        print('Processing slider $i with tag: $sliderTag');

        if (sliderTag == ConfigManager.TAG_GROUP && config['group'] != null) {
          try {
            final group = AppGroup.fromJson(config['group']);
            assignedGroups[i] = group;
            print('Restored group "${group.name}" for slider $i');
          } catch (e) {
            print('Error restoring group for slider $i: $e');
            sliderTags[i] = ConfigManager.TAG_UNASSIGNED;
          }
        } else if (sliderTag == ConfigManager.TAG_APP &&
            config['processName'] != null) {
          final processName = config['processName'] as String;
          final matchingApp = runningApps.firstWhere(
            (app) =>
                _configManager.normalizeProcessName(app.processName) ==
                _configManager.normalizeProcessName(processName),
            orElse: () => AudioSessionInfo(
              processName: '',
              processPath: '',
              processId: 0,
              volume: 0,
              isMuted: false,
            ),
          );

          if (matchingApp.processName.isNotEmpty) {
            assignedApplications[i] = matchingApp;
            _recentlyRestoredApps[i] = DateTime.now();
            print(
                'Found and assigned app ${matchingApp.processPath} to slider $i');
          } else {
            await _createMissingAppEntry(i, config);
          }
        } else if (sliderTag == ConfigManager.TAG_DEFAULT_DEVICE ||
            sliderTag == ConfigManager.TAG_MASTER_VOLUME ||
            sliderTag == ConfigManager.TAG_ACTIVE_APP) {
          print('Special slider $i: $sliderTag');
        } else {
          sliderTags[i] = ConfigManager.TAG_UNASSIGNED;
        }
      }

      _isConfigLoaded = true;
      _configLoadCompleter.complete();

      print('Configuration loading completed successfully');

      if (missingApplications.isNotEmpty) {
        print(
            'Missing applications: ${missingApplications.keys.map((k) => '$k: ${missingApplications[k]!.displayName}').join(', ')}');
      }

      if (assignedGroups.isNotEmpty) {
        print(
            'Assigned groups: ${assignedGroups.keys.map((k) => '$k: ${assignedGroups[k]!.name}').join(', ')}');
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
  }

  // ==================== NEW API SYSTEM YIPPEE ====================

  Map<String, dynamic> getSliderDisplayInfo(int sliderIndex) {
    if (assignedGroups.containsKey(sliderIndex)) {
      final group = assignedGroups[sliderIndex]!;
      return {
        'type': 'group',
        'displayName': group.name,
        'groupId': group.id,
        'processNames': group.processNames,
        'color': group.color,
        'isActive': true,
        'appCount': group.processNames.length,
      };
    }

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

  Future<List<AudioSessionInfo>> getRunningApplicationsWithAudio() async {
    return await _serviceClient.getAllSessions(includeIcons: true);
  }

  Future<AudioSessionInfo?> getActiveAppInfo() async {
    try {
      return await _serviceClient.getActiveApp();
    } catch (e) {
      print('Error getting active app info: $e');
      return null;
    }
  }

  Future<void> assignApplicationToSlider(
      int sliderIndex, AudioSessionInfo session) async {
    assignedApplications[sliderIndex] = session;
    sliderTags[sliderIndex] = ConfigManager.TAG_APP;

    missingApplications.remove(sliderIndex);
    assignedGroups.remove(sliderIndex);
    _recentlyRestoredApps[sliderIndex] = DateTime.now();

    print('Assigned app ${session.processPath} to slider $sliderIndex');

    await _configManager.cacheAppIcon(session.processPath);

    _configManager.updateSliderConfig(
      sliderIndex,
      session.processPath,
      ConfigManager.TAG_APP,
      muteStates[sliderIndex],
    );
  }

  void assignSpecialFeatureToSlider(int sliderIndex, String featureTag) {
    assignedApplications.remove(sliderIndex);
    missingApplications.remove(sliderIndex);
    assignedGroups.remove(sliderIndex);
    _recentlyRestoredApps.remove(sliderIndex);

    sliderTags[sliderIndex] = featureTag;
    print('Assigned special feature "$featureTag" to slider $sliderIndex');

    _configManager.updateSliderConfig(
      sliderIndex,
      null,
      featureTag,
      muteStates[sliderIndex],
    );
  }

  Future<void> assignGroupToSlider(int sliderIndex, AppGroup group) async {
    assignedGroups[sliderIndex] = group;
    sliderTags[sliderIndex] = ConfigManager.TAG_GROUP;

    assignedApplications.remove(sliderIndex);
    missingApplications.remove(sliderIndex);
    _recentlyRestoredApps.remove(sliderIndex);

    print('Assigned group "${group.name}" to slider $sliderIndex');

    await _configManager.saveAppGroup(group);

    _configManager.updateSliderConfigForGroup(
      sliderIndex,
      group,
      muteStates[sliderIndex],
    );
  }

  Future<void> adjustVolume(int sliderIndex, double sliderValue) async {
    sliderValues[sliderIndex] = sliderValue;
    final normalizedVolume = sliderValue / 1024.0;

    // Group?
    if (assignedGroups.containsKey(sliderIndex)) {
      final group = assignedGroups[sliderIndex]!;
      await _serviceClient.setVolume(
        sliderIndex: sliderIndex,
        volume: normalizedVolume,
        targetType: TargetType.Group,
        processNames: group.processNames,
      );
      return;
    }

    // App?
    if (assignedApplications.containsKey(sliderIndex)) {
      final app = assignedApplications[sliderIndex]!;
      await _serviceClient.setVolume(
        sliderIndex: sliderIndex,
        volume: normalizedVolume,
        targetType: TargetType.App,
        processName: app.processName,
      );
      return;
    }

    // Check tag for any special types (via tagging)
    final tag = sliderTags[sliderIndex];
    if (tag == ConfigManager.TAG_ACTIVE_APP) {
      await _serviceClient.setVolume(
        sliderIndex: sliderIndex,
        volume: normalizedVolume,
        targetType: TargetType.ActiveApp,
      );
    } else if (tag == ConfigManager.TAG_DEFAULT_DEVICE ||
        tag == ConfigManager.TAG_MASTER_VOLUME) {
      await _serviceClient.setVolume(
        sliderIndex: sliderIndex,
        volume: normalizedVolume,
        targetType: TargetType.MasterVolume,
      );
    }
  }

  Future<void> setMuteState(int sliderIndex, bool isMuted) async {
    muteStates[sliderIndex] = isMuted;

    // Group?
    if (assignedGroups.containsKey(sliderIndex)) {
      final group = assignedGroups[sliderIndex]!;
      await _serviceClient.setMute(
        sliderIndex: sliderIndex,
        isMuted: isMuted,
        targetType: TargetType.Group,
        processNames: group.processNames,
      );

      _configManager.updateSliderConfigForGroup(
        sliderIndex,
        group,
        isMuted,
      );
      return;
    }

    // App?
    if (assignedApplications.containsKey(sliderIndex)) {
      final app = assignedApplications[sliderIndex]!;
      await _serviceClient.setMute(
        sliderIndex: sliderIndex,
        isMuted: isMuted,
        targetType: TargetType.App,
        processName: app.processName,
      );

      _configManager.updateSliderConfig(
        sliderIndex,
        app.processPath,
        sliderTags[sliderIndex],
        isMuted,
      );
      return;
    }

    // Check tag for any special types (via tagging)
    final tag = sliderTags[sliderIndex];

    if (tag == ConfigManager.TAG_ACTIVE_APP) {
      await _serviceClient.setMute(
          sliderIndex: sliderIndex,
          isMuted: isMuted,
          targetType: TargetType.ActiveApp);

      _configManager.updateSliderConfig(sliderIndex, null, tag, isMuted);
    } else if (tag == ConfigManager.TAG_DEFAULT_DEVICE ||
        tag == ConfigManager.TAG_MASTER_VOLUME) {
      await _serviceClient.setMute(
        sliderIndex: sliderIndex,
        isMuted: isMuted,
        targetType: TargetType.MasterVolume,
      );

      _configManager.updateSliderConfig(
        sliderIndex,
        null,
        tag,
        isMuted,
      );
    }
  }

  void resetSliderConfiguration(int sliderIndex) {
    assignedApplications.remove(sliderIndex);
    missingApplications.remove(sliderIndex);
    assignedGroups.remove(sliderIndex);
    _recentlyRestoredApps.remove(sliderIndex);

    sliderValues[sliderIndex] = 0;
    sliderTags[sliderIndex] = ConfigManager.TAG_UNASSIGNED;
    muteStates[sliderIndex] = false;

    _configManager.removeSliderConfig(sliderIndex);

    print('Slider $sliderIndex reset and configuration removed');
  }

  void clearAllConfigurations() {
    assignedApplications.clear();
    missingApplications.clear();
    assignedGroups.clear();
    _recentlyRestoredApps.clear();
    sliderValues = List.filled(8, 0.5);
    sliderTags = List.filled(8, ConfigManager.TAG_DEFAULT_DEVICE);
    muteStates = List.filled(8, false);

    StorageManager.instance
      ..removeData('sliderValues')
      ..removeData('sliderTags')
      ..removeData('assignedApps')
      ..removeData('deviceVolume')
      ..removeData('sliderConfigs')
      ..removeData('buttonStates')
      ..removeData('appGroups');

    print('All configurations cleared');
  }

  void _onSessionUpdated(AudioSessionInfo session) {
    // ADD THIS METHOD
    print(
        'Session updated: ${session.processName} with new PID: ${session.processId}');

    // Find if this process is assigned to any slider
    for (var entry in assignedApplications.entries) {
      final sliderIndex = entry.key;
      final app = entry.value;

      if (_configManager.normalizeProcessName(app.processName) ==
          _configManager.normalizeProcessName(session.processName)) {
        // Update with new session info (new PID)
        assignedApplications[sliderIndex] = session;
        print(
            'Updated slider $sliderIndex with new PID for ${session.processName}');

        // Restore volume settings
        _restoreVolumeForApp(
          sliderIndex,
          session,
          sliderValues[sliderIndex],
          muteStates[sliderIndex],
        );
        break;
      }
    }
  }

  Future<void> dispose() async {
    _audioSessionMonitor?.cancel();
    await _sessionAddedSubscription?.cancel();
    await _sessionRemovedSubscription?.cancel();
    await _sessionUpdatedSubscription?.cancel();
    await _configManager.saveAllSliderConfigs();
    await _serviceClient.dispose();
  }
}

import 'dart:async';
import 'package:mixlit/backend/application/audio/AppGroup.dart';
import 'package:mixlit/backend/application/data/ConfigManager.dart';
import 'package:mixlit/backend/application/data/StorageManager.dart';
import 'package:mixlit/backend/application/audio/audio_service_client.dart';
import 'package:mixlit/backend/application/integration/SonosIntegration.dart';
import 'package:mixlit/backend/application/integration/SpotifyIntegration.dart';

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

  final List<AudioSessionInfo> _knownSessions = [];
  List<AudioSessionInfo> get knownSessions => List.unmodifiable(_knownSessions);

  Map<int, AudioSessionInfo> assignedApplications = {};
  Map<int, MissingApp> missingApplications = {};
  Map<int, AppGroup> assignedGroups = {};
  Map<int, Map<String, dynamic>> assignedIntegrations = {};
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

  // IMPORTANT: Do NOT call _serviceClient.connect() here - the connection is
  // already established by HomePage before ApplicationManager is constructed.

  Future<void> _initialize() async {
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
    _upsertKnownSession(session);
    _checkForMissingAudioSessions();
  }

  // Moves the specific app to missing directly rather than re-scanning all sessions
  void _onSessionRemoved(AudioSessionInfo session) {
    final normalized = _configManager.normalizeProcessName(session.processName);
    _knownSessions.removeWhere((s) =>
        _configManager.normalizeProcessName(s.processName) == normalized);
    _removeAssignedAppByProcessName(session.processName);
  }

  void _removeAssignedAppByProcessName(String processName) {
    final normalized = _configManager.normalizeProcessName(processName);
    for (final entry in assignedApplications.entries) {
      if (_configManager.normalizeProcessName(entry.value.processName) ==
          normalized) {
        _moveAppToMissing(entry.key);
        return;
      }
    }
  }

  void _onSessionUpdated(AudioSessionInfo session) {
    _upsertKnownSession(session);

    for (final entry in assignedApplications.entries) {
      final sliderIndex = entry.key;
      final app = entry.value;

      if (_configManager.normalizeProcessName(app.processName) ==
          _configManager.normalizeProcessName(session.processName)) {
        assignedApplications[sliderIndex] = session;
        _reapplyCurrentVolume(sliderIndex, session);
        break;
      }
    }
  }

  void _upsertKnownSession(AudioSessionInfo session) {
    final normalized = _configManager.normalizeProcessName(session.processName);
    final idx = _knownSessions.indexWhere((s) =>
        _configManager.normalizeProcessName(s.processName) == normalized);
    if (idx != -1) {
      _knownSessions[idx] = session;
    } else {
      _knownSessions.add(session);
    }
  }

  Future<void> _reapplyCurrentVolume(
      int sliderIndex, AudioSessionInfo session) async {
    try {
      final currentVolume = sliderValues[sliderIndex];
      final currentMuteState = muteStates[sliderIndex];
      if (currentVolume <= 0) {
        return;
      }

      await Future.delayed(const Duration(milliseconds: 150));

      if (currentMuteState) {
        await setMuteState(sliderIndex, true);
      } else {
        await adjustVolume(sliderIndex, currentVolume);
      }
    } catch (e) {
      print('Error reapplying volume for slider $sliderIndex: $e');
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
      _recentlyRestoredApps
          .removeWhere((_, t) => now.difference(t) > _restorationGracePeriod);

      await _serviceClient.refreshSessions();

      if (missingApplications.isNotEmpty) {
        await _checkForMissingAudioSessions();
      }
    } catch (e) {
      print('Error monitoring audio sessions: $e');
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

        final matchingApps = runningApps
            .where((app) =>
                _configManager.normalizeProcessName(app.processName) ==
                _configManager.normalizeProcessName(missingApp.processName))
            .toList();

        if (matchingApps.isNotEmpty) {
          final matchingApp = matchingApps.first;

          print(
              'Found missing app ${missingApp.processName} for slider $sliderIndex with new PID ${matchingApp.processId}');

          assignedApplications[sliderIndex] = matchingApp;
          _recentlyRestoredApps[sliderIndex] = DateTime.now();

          final storedVolume = sliderValues[sliderIndex];

          if (storedVolume > 0) {
            // hardware data processing
            await _restoreVolumeForApp(
              sliderIndex,
              matchingApp,
              storedVolume,
              muteStates[sliderIndex],
            );
          } else {
            _configManager.updateSliderConfig(
              sliderIndex,
              matchingApp.processPath,
              sliderTags[sliderIndex],
              muteStates[sliderIndex],
            );
          }

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
      print(
          'Restoring volume for slider $sliderIndex: ${app.processPath} to $volumeValue (muted: $isMuted)');

      sliderValues[sliderIndex] = volumeValue;
      muteStates[sliderIndex] = isMuted;

      await Future.delayed(const Duration(milliseconds: 200));

      if (isMuted) {
        await setMuteState(sliderIndex, true);
      } else {
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

      sliderValues = List.filled(8, 0.0);
      sliderTags = List<String>.from(configs['sliderTags']);
      muteStates = List<bool>.from(configs['muteStates']);

      final sliderConfigs = configs['sliderConfigs'];
      List<AudioSessionInfo> runningApps = [];

      try {
        print('Fetching running applications (without icons for speed)...');
        for (int attempt = 0; attempt < 3; attempt++) {
          runningApps = await _serviceClient
              .getAllSessions(includeIcons: false)
              .timeout(const Duration(seconds: 5));

          if (runningApps.isNotEmpty) {
            _knownSessions
              ..clear()
              ..addAll(runningApps);
            print(
                '[ApplicationManager] Seeded ${_knownSessions.length} known session(s) from startup fetch');
            break;
          }

          if (attempt < 2) {
            print('No sessions found on attempt ${attempt + 1}, retrying...');
            await Future.delayed(const Duration(milliseconds: 800));
          }
        }
        print('Found ${runningApps.length} running apps with audio');
      } catch (e) {
        print('Error getting running applications: $e');
        runningApps = [];
      }

      for (var i = 0; i < sliderConfigs.length; i++) {
        final config = sliderConfigs[i];
        if (config == null) {
          sliderTags[i] = ConfigManager.TAG_UNASSIGNED;
          continue;
        }

        final sliderTag = config['sliderTag'] ?? 'unassigned';
        print('Processing slider $i with tag: $sliderTag');

        if (sliderTag == ConfigManager.TAG_INTEGRATION &&
            config['integration'] != null) {
          final integration = config['integration'] as Map<String, dynamic>;
          bool integrationValid = false;

          if (integration['type'] == 'spotify') {
            integrationValid = await _restoreSpotifyIntegration(i, integration);
          } else if (integration['type'] == 'sonos') {
            integrationValid = await _restoreSonosIntegration(i, integration);
          }

          if (integrationValid) {
            assignedIntegrations[i] = integration;
          } else {
            print(
                'Failed to restore ${integration['type']} integration for slider $i - marking as unassigned');
            sliderTags[i] = ConfigManager.TAG_UNASSIGNED;
          }
        } else if (sliderTag == ConfigManager.TAG_GROUP &&
            config['group'] != null) {
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
      if (!_configLoadCompleter.isCompleted) {
        _configLoadCompleter.complete();
      }

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
      print('Stack trace: ${StackTrace.current}');
      _isConfigLoaded = true;
      if (!_configLoadCompleter.isCompleted) {
        _configLoadCompleter.complete();
      }
    }
  }

  void updateGroupAcrossSliders(AppGroup updatedGroup) {
    for (int i = 0; i < sliderTags.length; i++) {
      if (sliderTags[i] == ConfigManager.TAG_GROUP &&
          assignedGroups[i]?.id == updatedGroup.id) {
        assignedGroups[i] = updatedGroup;

        _configManager.updateSliderConfigForGroup(
          i,
          updatedGroup,
          muteStates[i],
        );
      }
    }
  }

  Future<bool> _restoreSpotifyIntegration(
    int sliderIndex,
    Map<String, dynamic> integration,
  ) async {
    try {
      if (!SpotifyIntegration.instance.isAuthenticated) {
        print('Spotify not authenticated, cannot restore integration');
        return false;
      }

      final deviceId = integration['deviceId'] as String?;
      if (deviceId == null) {
        print('No deviceId in saved Spotify integration');
        return false;
      }

      final devices = await SpotifyIntegration.instance.getAvailableDevices();
      final deviceExists = devices.any((d) => d.id == deviceId);

      if (!deviceExists) {
        print('Saved Spotify device $deviceId no longer available');
        return false;
      }

      await SpotifyIntegration.instance.selectDevice(deviceId);
      print('Restored Spotify device: $deviceId');
      return true;
    } catch (e) {
      print('Error restoring Spotify integration: $e');
      return false;
    }
  }

  Future<bool> _restoreSonosIntegration(
    int sliderIndex,
    Map<String, dynamic> integration,
  ) async {
    try {
      if (!SonosIntegration.instance.isAuthenticated) {
        print('Sonos not authenticated, cannot restore integration');
        return false;
      }

      final deviceId = integration['deviceId'] as String?;
      final groupId = integration['groupId'] as String?;
      final deviceName = integration['deviceName'] as String?;

      if (deviceId == null || deviceName == null) {
        print('Missing deviceId or deviceName in saved Sonos integration');
        return false;
      }

      print('Discovering Sonos devices to validate saved device...');
      final devices = await SonosIntegration.instance.discoverDevices(
        useCache: false,
      );

      final deviceExists =
          devices.any((d) => d.id == deviceId || d.groupId == groupId);

      if (!deviceExists) {
        print('Saved Sonos device $deviceName no longer available');
        print(
            'Available devices: ${devices.map((d) => '${d.name} (${d.id})').join(', ')}');
        return false;
      }

      final matchingDevice = devices.firstWhere(
        (d) => d.id == deviceId || d.groupId == groupId,
      );

      integration['deviceId'] = matchingDevice.id;
      integration['groupId'] = matchingDevice.groupId;
      integration['deviceName'] = matchingDevice.name;
      integration['displayName'] = matchingDevice.name;

      await SonosIntegration.instance.selectDevice(
        matchingDevice.id,
        matchingDevice.ipAddress,
        matchingDevice.name,
      );
      return true;
    } catch (e) {
      print('Error restoring Sonos integration: $e');
      return false;
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

  Map<String, dynamic> getSliderDisplayInfo(int sliderIndex) {
    if (assignedIntegrations.containsKey(sliderIndex)) {
      final integration = assignedIntegrations[sliderIndex]!;
      return {
        'type': 'integration',
        'integrationType': integration['type'],
        'displayName': integration['displayName'] ?? 'Integration',
        'isActive': true,
        'hasIntegration': true,
      };
    }

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
        'isActive': true
      };
    } else if (tag == ConfigManager.TAG_MASTER_VOLUME) {
      return {
        'type': 'master',
        'displayName': 'Master Volume',
        'isActive': true
      };
    } else if (tag == ConfigManager.TAG_ACTIVE_APP) {
      return {
        'type': 'active_app_control',
        'displayName': 'Active App',
        'isActive': true
      };
    }

    return {
      'type': 'unassigned',
      'displayName': 'Unassigned',
      'isActive': false
    };
  }

  Future<void> assignIntegrationToSlider(
    int sliderIndex,
    Map<String, dynamic> integrationData,
  ) async {
    assignedIntegrations[sliderIndex] = integrationData;
    sliderTags[sliderIndex] = 'integration';

    assignedApplications.remove(sliderIndex);
    missingApplications.remove(sliderIndex);
    assignedGroups.remove(sliderIndex);
    _recentlyRestoredApps.remove(sliderIndex);

    print(
        'Assigned ${integrationData['type']} integration to slider $sliderIndex');

    _configManager.updateSliderConfigForIntegration(
      sliderIndex,
      integrationData,
      muteStates[sliderIndex],
    );
  }

  Future<List<AudioSessionInfo>> getRunningApplicationsWithAudio(
      {bool includeIcons = false}) async {
    return await _serviceClient.getAllSessions(includeIcons: includeIcons);
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

    if (assignedIntegrations.containsKey(sliderIndex)) {
      final integration = assignedIntegrations[sliderIndex]!;
      if (integration['type'] == 'spotify') {
        SpotifyIntegration.instance
            .setVolume(normalizedVolume, deviceId: integration['deviceId']);
        return;
      } else if (integration['type'] == 'sonos') {
        SonosIntegration.instance.setVolume(normalizedVolume,
            deviceId: integration['deviceId'], groupId: integration['groupId']);
        return;
      }
    }

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

    if (assignedIntegrations.containsKey(sliderIndex)) {
      final integration = assignedIntegrations[sliderIndex]!;
      if (integration['type'] == 'sonos') {
        await SonosIntegration.instance.setMute(isMuted,
            deviceId: integration['deviceId'], groupId: integration['groupId']);
        _configManager.updateSliderConfigForIntegration(
            sliderIndex, integration, isMuted);
        return;
      }
    }

    if (assignedGroups.containsKey(sliderIndex)) {
      final group = assignedGroups[sliderIndex]!;
      await _serviceClient.setMute(
        sliderIndex: sliderIndex,
        isMuted: isMuted,
        targetType: TargetType.Group,
        processNames: group.processNames,
      );
      _configManager.updateSliderConfigForGroup(sliderIndex, group, isMuted);
      return;
    }

    if (assignedApplications.containsKey(sliderIndex)) {
      final app = assignedApplications[sliderIndex]!;
      await _serviceClient.setMute(
        sliderIndex: sliderIndex,
        isMuted: isMuted,
        targetType: TargetType.App,
        processName: app.processName,
      );
      _configManager.updateSliderConfig(
          sliderIndex, app.processPath, sliderTags[sliderIndex], isMuted);
      return;
    }

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
      _configManager.updateSliderConfig(sliderIndex, null, tag, isMuted);
    }
  }

  void resetSliderConfiguration(int sliderIndex) {
    assignedApplications.remove(sliderIndex);
    missingApplications.remove(sliderIndex);
    assignedGroups.remove(sliderIndex);
    assignedIntegrations.remove(sliderIndex);
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

  Future<void> dispose() async {
    _audioSessionMonitor?.cancel();
    await _sessionAddedSubscription?.cancel();
    await _sessionRemovedSubscription?.cancel();
    await _sessionUpdatedSubscription?.cancel();
    await _configManager.saveAllSliderConfigs();
    await _serviceClient.dispose();
  }
}

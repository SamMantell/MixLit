import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:signalr_netcore/signalr_client.dart';

class AudioServiceClient {
  static const String baseUrl = 'http://localhost:8765';
  static const String hubUrl = '$baseUrl/hub/audio';

  late HubConnection _hubConnection;
  bool _isConnected = false;

  final _sessionAddedController =
      StreamController<AudioSessionInfo>.broadcast();
  final _sessionRemovedController =
      StreamController<AudioSessionInfo>.broadcast();
  final _sessionUpdatedController =
      StreamController<AudioSessionInfo>.broadcast();
  final _volumeChangedController =
      StreamController<VolumeChangedEvent>.broadcast();

  Stream<AudioSessionInfo> get sessionAdded => _sessionAddedController.stream;
  Stream<AudioSessionInfo> get sessionRemoved =>
      _sessionRemovedController.stream;
  Stream<AudioSessionInfo> get sessionUpdated =>
      _sessionUpdatedController.stream;
  Stream<VolumeChangedEvent> get volumeChanged =>
      _volumeChangedController.stream;

  bool get isConnected => _isConnected;

  Future<void> connect() async {
    try {
      _hubConnection = HubConnectionBuilder()
          .withUrl(hubUrl)
          .withAutomaticReconnect()
          .build();

      _hubConnection.on('SessionAdded', _handleSessionAdded);
      _hubConnection.on('SessionUpdated', _handleSessionUpdated);
      _hubConnection.on('SessionRemoved', _handleSessionRemoved);
      _hubConnection.on('VolumeChanged', _handleVolumeChanged);

      _hubConnection.onclose(({Exception? error}) {
        _isConnected = false;
        print('SignalR connection closed: $error');
      });

      _hubConnection.onreconnecting(({Exception? error}) {
        _isConnected = false;
        print('SignalR reconnecting: $error');
      });

      _hubConnection.onreconnected(({String? connectionId}) {
        _isConnected = true;
        print('SignalR reconnected: $connectionId');
      });

      await _hubConnection.start();
      _isConnected = true;
      print('Connected to audio service');
    } catch (e) {
      print('Failed to connect to audio service: $e');
      rethrow;
    }
  }

  void _handleSessionAdded(List<Object?>? arguments) {
    if (arguments == null || arguments.isEmpty) return;
    try {
      final data = arguments[0] as Map<String, dynamic>;
      _sessionAddedController.add(AudioSessionInfo.fromJson(data['session']));
    } catch (e) {
      print('Error parsing SessionAdded event: $e');
    }
  }

  void _handleSessionRemoved(List<Object?>? arguments) {
    if (arguments == null || arguments.isEmpty) return;
    try {
      final data = arguments[0] as Map<String, dynamic>;
      _sessionRemovedController.add(AudioSessionInfo.fromJson(data['session']));
    } catch (e) {
      print('Error parsing SessionRemoved event: $e');
    }
  }

  void _handleSessionUpdated(List<Object?>? arguments) {
    if (arguments == null || arguments.isEmpty) return;
    try {
      final data = arguments[0] as Map<String, dynamic>;
      _sessionUpdatedController.add(AudioSessionInfo.fromJson(data['session']));
    } catch (e) {
      print('Error parsing SessionUpdated event: $e');
    }
  }

  void _handleVolumeChanged(List<Object?>? arguments) {
    if (arguments == null || arguments.isEmpty) return;
    try {
      final data = arguments[0] as Map<String, dynamic>;
      _volumeChangedController.add(VolumeChangedEvent.fromJson(data));
    } catch (e) {
      print('Error parsing VolumeChanged event: $e');
    }
  }

  Future<void> setVolume({
    required int sliderIndex,
    required double volume,
    required TargetType targetType,
    String? processName,
    String? groupId,
    List<String>? processNames,
  }) async {
    try {
      final command = {
        'SliderIndex': sliderIndex,
        'Volume': volume,
        'TargetType': targetType.index,
        if (processName != null) 'ProcessName': processName,
        if (groupId != null) 'GroupId': groupId,
        if (processNames != null) 'ProcessNames': processNames,
      };

      final response = await http.post(
        Uri.parse('$baseUrl/api/volume/set'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(command),
      );

      if (response.statusCode != 200) {
        print('Volume set failed ${response.statusCode}: ${response.body}');
        throw Exception('Failed to set volume: ${response.body}');
      }
    } catch (e) {
      print('Error setting volume: $e');
      rethrow;
    }
  }

  Future<void> setMute({
    required int sliderIndex,
    required bool isMuted,
    required TargetType targetType,
    String? processName,
    String? groupId,
    List<String>? processNames,
  }) async {
    try {
      final command = {
        'SliderIndex': sliderIndex,
        'IsMuted': isMuted,
        'TargetType': targetType.index,
        if (processName != null) 'ProcessName': processName,
        if (groupId != null) 'GroupId': groupId,
        if (processNames != null) 'ProcessNames': processNames,
      };

      final response = await http.post(
        Uri.parse('$baseUrl/api/volume/mute'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(command),
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to set mute: ${response.body}');
      }
    } catch (e) {
      print('Error setting mute: $e');
      rethrow;
    }
  }

  Future<List<AudioSessionInfo>> getAllSessions({
    bool includeIcons = false,
  }) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/session/list?includeIcons=$includeIcons'),
      );

      if (response.statusCode != 200) {
        print('getAllSessions: unexpected status ${response.statusCode}');
        return [];
      }

      final data = jsonDecode(response.body);
      if (data['success'] != true) {
        print('getAllSessions: service returned error: ${data['error']}');
        return [];
      }

      final List<dynamic> sessionsJson = data['data'];
      final sessions =
          sessionsJson.map((j) => AudioSessionInfo.fromJson(j)).toList();
      return sessions;
    } catch (e) {
      print('getAllSessions error: $e');
      return [];
    }
  }

  Future<AudioSessionInfo?> getActiveApp() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/volume/active-app'),
      );
      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body);
      if (data['success'] == true &&
          data['data'] is Map &&
          data['data']['processName'] != null) {
        return AudioSessionInfo.fromJson(data['data']);
      }
      return null;
    } catch (e) {
      print('Error getting active app: $e');
      return null;
    }
  }

  Future<String?> getIcon(String processPath) async {
    try {
      final response = await http.get(
        Uri.parse(
          '$baseUrl/api/session/icon?processPath=${Uri.encodeComponent(processPath)}',
        ),
      );
      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body);
      return data['success'] == true ? data['data'] as String? : null;
    } catch (e) {
      print('Error getting icon: $e');
      return null;
    }
  }

  Future<double> getMasterVolume() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/api/volume/master'));
      if (response.statusCode != 200) {
        throw Exception('Failed to get master volume: ${response.body}');
      }
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        return (data['data'] as num).toDouble();
      }
      throw Exception(data['error'] ?? 'Unknown error');
    } catch (e) {
      print('Error getting master volume: $e');
      rethrow;
    }
  }

  Future<void> refreshSessions() async {
    try {
      await http
          .post(Uri.parse('$baseUrl/api/session/refresh'))
          .timeout(const Duration(seconds: 2));
    } catch (e) {
      // Timeout or network error — not fatal, dialog will auto-refresh.
      print('refreshSessions: $e');
    }
  }

  Future<bool> checkHealth() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/health'))
          .timeout(const Duration(seconds: 2));
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  Future<void> dispose() async {
    try {
      await _hubConnection.stop();
    } catch (e) {
      print('Error stopping hub connection: $e');
    }
    await _sessionAddedController.close();
    await _sessionRemovedController.close();
    await _sessionUpdatedController.close();
    await _volumeChangedController.close();
  }
}

enum TargetType {
  App, // 0
  Group, // 1
  MasterVolume, // 2
  DefaultDevice, // 3
  ActiveApp, // 4
}

class AudioSessionInfo {
  final String processName;
  final String processPath;
  final int processId;
  final double volume;
  final bool isMuted;
  final String? iconBase64;

  AudioSessionInfo({
    required this.processName,
    required this.processPath,
    required this.processId,
    required this.volume,
    required this.isMuted,
    this.iconBase64,
  });

  factory AudioSessionInfo.fromJson(Map<String, dynamic> json) {
    return AudioSessionInfo(
      processName: json['processName'] ?? '',
      processPath: json['processPath'] ?? '',
      processId: json['processId'] ?? 0,
      volume: (json['volume'] ?? 0.0).toDouble(),
      isMuted: json['isMuted'] ?? false,
      iconBase64: json['iconBase64'],
    );
  }

  Map<String, dynamic> toJson() => {
        'processName': processName,
        'processPath': processPath,
        'processId': processId,
        'volume': volume,
        'isMuted': isMuted,
        'iconBase64': iconBase64,
      };
}

class VolumeChangedEvent {
  final int sliderIndex;
  final String processName;
  final double volume;
  final bool isMuted;

  VolumeChangedEvent({
    required this.sliderIndex,
    required this.processName,
    required this.volume,
    required this.isMuted,
  });

  factory VolumeChangedEvent.fromJson(Map<String, dynamic> json) {
    return VolumeChangedEvent(
      sliderIndex: json['sliderIndex'] ?? 0,
      processName: json['processName'] ?? '',
      volume: (json['volume'] ?? 0.0).toDouble(),
      isMuted: json['isMuted'] ?? false,
    );
  }
}

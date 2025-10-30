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

      // Event handlers
      _hubConnection.on('SessionAdded', (arguments) {
        _handleSessionAdded(arguments);
      });

      _hubConnection.on('SessionUpdated', (arguments) {
        _handleSessionUpdated(arguments);
      });

      _hubConnection.on('SessionRemoved', (arguments) {
        _handleSessionRemoved(arguments);
      });

      _hubConnection.on('VolumeChanged', (arguments) {
        _handleVolumeChanged(arguments);
      });

      // Connection state handlers
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
    if (arguments != null && arguments.isNotEmpty) {
      try {
        final data = arguments[0] as Map<String, dynamic>;
        final session = AudioSessionInfo.fromJson(data['session']);
        _sessionAddedController.add(session);
      } catch (e) {
        print('Error parsing SessionAdded event: $e');
      }
    }
  }

  void _handleSessionRemoved(List<Object?>? arguments) {
    if (arguments != null && arguments.isNotEmpty) {
      try {
        final data = arguments[0] as Map<String, dynamic>;
        final session = AudioSessionInfo.fromJson(data['session']);
        _sessionRemovedController.add(session);
      } catch (e) {
        print('Error parsing SessionRemoved event: $e');
      }
    }
  }

  void _handleVolumeChanged(List<Object?>? arguments) {
    if (arguments != null && arguments.isNotEmpty) {
      try {
        final data = arguments[0] as Map<String, dynamic>;
        final event = VolumeChangedEvent.fromJson(data);
        _volumeChangedController.add(event);
      } catch (e) {
        print('Error parsing VolumeChanged event: $e');
      }
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
        'TargetType':
            targetType.index, // 0 = App, 1 = Group, 2 = MasterVolume, etc...
        if (processName != null) 'ProcessName': processName,
        if (groupId != null) 'GroupId': groupId,
        if (processNames != null) 'ProcessNames': processNames,
      };

      print('Sending volume command: ${jsonEncode(command)}');

      final response = await http.post(
        Uri.parse('$baseUrl/api/volume/set'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(command),
      );

      if (response.statusCode != 200) {
        print(
            'Volume set failed with status ${response.statusCode}: ${response.body}');
        throw Exception('Failed to set volume: ${response.body}');
      }

      print('Volume set successfully for slider $sliderIndex');
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

      print('Sending mute command: ${jsonEncode(command)}');

      final response = await http.post(
        Uri.parse('$baseUrl/api/volume/mute'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(command),
      );

      if (response.statusCode != 200) {
        print(
            'Mute set failed with status ${response.statusCode}: ${response.body}');
        throw Exception('Failed to set mute: ${response.body}');
      }

      print('Mute state set successfully for slider $sliderIndex');
    } catch (e) {
      print('Error setting mute: $e');
      rethrow;
    }
  }

  Future<List<AudioSessionInfo>> getAllSessions(
      {bool includeIcons = false}) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/session/list?includeIcons=$includeIcons'),
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to get sessions: ${response.body}');
      }

      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        final List<dynamic> sessionsJson = data['data'];
        return sessionsJson
            .map((json) => AudioSessionInfo.fromJson(json))
            .toList();
      } else {
        throw Exception(data['error'] ?? 'Unknown error');
      }
    } catch (e) {
      print('Error getting sessions: $e');
      rethrow;
    }
  }

  Future<AudioSessionInfo?> getActiveApp() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/volume/active-app'),
      );

      if (response.statusCode != 200) {
        print('Failed to get active app: ${response.body}');
        return null;
      }

      final data = jsonDecode(response.body);
      if (data['success'] == true && data['data'] != null) {
        if (data['data'] is Map && data['data']['processName'] != null) {
          return AudioSessionInfo.fromJson(data['data']);
        }
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
            '$baseUrl/api/session/icon?processPath=${Uri.encodeComponent(processPath)}'),
      );

      if (response.statusCode != 200) {
        return null;
      }

      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        return data['data'];
      }
      return null;
    } catch (e) {
      print('Error getting icon: $e');
      return null;
    }
  }

  Future<double> getMasterVolume() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/volume/master'),
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to get master volume: ${response.body}');
      }

      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        return (data['data'] as num).toDouble();
      } else {
        throw Exception(data['error'] ?? 'Unknown error');
      }
    } catch (e) {
      print('Error getting master volume: $e');
      rethrow;
    }
  }

  Future<void> refreshSessions() async {
    try {
      await http.post(Uri.parse('$baseUrl/api/session/refresh'));
      print('Sessions refreshed');
    } catch (e) {
      print('Error refreshing sessions: $e');
    }
  }

  Future<bool> checkHealth() async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/health'),
          )
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

  void _handleSessionUpdated(List<Object?>? arguments) {
    if (arguments != null && arguments.isNotEmpty) {
      try {
        final data = arguments[0] as Map<String, dynamic>;
        final session = AudioSessionInfo.fromJson(data['session']);
        // Trigger an event that ApplicationManager can listen to
        _sessionUpdatedController.add(session);
      } catch (e) {
        print('Error parsing SessionUpdated event: $e');
      }
    }
  }
}

// Updated enum with proper mapping
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

  Map<String, dynamic> toJson() {
    return {
      'processName': processName,
      'processPath': processPath,
      'processId': processId,
      'volume': volume,
      'isMuted': isMuted,
      'iconBase64': iconBase64,
    };
  }
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

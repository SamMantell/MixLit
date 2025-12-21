import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class SonosDevice {
  final String id; // This will be the player ID
  final String groupId; // Store the group ID separately
  final String name;
  final String ipAddress;
  final String roomName;
  final bool isCoordinator;
  final int volume;

  SonosDevice({
    required this.id,
    required this.groupId,
    required this.name,
    required this.ipAddress,
    required this.roomName,
    required this.isCoordinator,
    required this.volume,
  });

  factory SonosDevice.fromXml(String xml, String ipAddress) {
    final friendlyNameMatch =
        RegExp(r'<friendlyName>(.*?)</friendlyName>').firstMatch(xml);
    final roomNameMatch = RegExp(r'<roomName>(.*?)</roomName>').firstMatch(xml);
    final udnMatch = RegExp(r'<UDN>(.*?)</UDN>').firstMatch(xml);

    return SonosDevice(
      id: udnMatch?.group(1) ?? ipAddress,
      groupId: udnMatch?.group(1) ?? ipAddress, // Same for local discovery
      name: friendlyNameMatch?.group(1) ?? 'Unknown Sonos Device',
      ipAddress: ipAddress,
      roomName: roomNameMatch?.group(1) ??
          friendlyNameMatch?.group(1) ??
          'Unknown Room',
      isCoordinator: true,
      volume: 0,
    );
  }

  factory SonosDevice.fromCloudApi(Map<String, dynamic> json, String playerId) {
    return SonosDevice(
      id: playerId, // Use the player ID passed in
      groupId: json['id'], // Store the group ID
      name: json['name'] ?? 'Unknown Device',
      ipAddress: '', // Cloud API doesn't expose IP
      roomName: json['name'] ?? 'Unknown Room',
      isCoordinator: json.containsKey('coordinatorId'),
      volume: 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'groupId': groupId,
      'name': name,
      'ipAddress': ipAddress,
      'roomName': roomName,
      'isCoordinator': isCoordinator,
      'volume': volume,
    };
  }
}

class SonosIntegration {
  // Storage keys
  static const String _clientIdKey = 'sonos_client_id';
  static const String _clientSecretKey = 'sonos_client_secret';
  static const String _accessTokenKey = 'sonos_access_token';
  static const String _refreshTokenKey = 'sonos_refresh_token';
  static const String _tokenExpiryKey = 'sonos_token_expiry';
  static const String _selectedDeviceKey = 'sonos_selected_device';
  static const String _selectedHouseholdKey = 'sonos_selected_household';

  // Sonos Cloud API endpoints
  static const String authorizationEndpoint =
      'https://api.sonos.com/login/v3/oauth';
  static const String tokenEndpoint =
      'https://api.sonos.com/login/v3/oauth/access';
  static const String apiBaseUrl = 'https://api.ws.sonos.com/control/api/v1';

  static const List<String> requiredScopes = ['playback-control-all'];

  // Rate limiting
  final List<DateTime> _requestTimestamps = [];
  static const int _maxRequestsPer30Seconds = 100;
  static const Duration _rateLimitWindow = Duration(seconds: 30);

  // Volume change batching
  Timer? _volumeUpdateTimer;
  double? _pendingVolume;
  String? _pendingGroupId; // ADD: Track group ID for pending volume changes
  static const Duration _volumeUpdateDelay = Duration(milliseconds: 500);

  // Authentication state
  String? _accessToken;
  String? _refreshToken;
  DateTime? _tokenExpiry;
  String? _selectedDeviceId; // (playerID)
  String? _selectedHouseholdId;

  // Cache for discovered devices
  List<SonosDevice>? _cachedDevices;
  DateTime? _lastDiscoveryTime;
  static const Duration _cacheExpiration = Duration(minutes: 5);

  // Singleton pattern
  static final SonosIntegration _instance = SonosIntegration._internal();
  static SonosIntegration get instance => _instance;
  SonosIntegration._internal();

  bool get isAuthenticated =>
      _accessToken != null && (_tokenExpiry?.isAfter(DateTime.now()) ?? false);
  String? get selectedDeviceId => _selectedDeviceId;
  String? get selectedDeviceIp => null; // Cloud API doesn't use IPs

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    _accessToken = prefs.getString(_accessTokenKey);
    _refreshToken = prefs.getString(_refreshTokenKey);
    _selectedDeviceId = prefs.getString(_selectedDeviceKey);
    _selectedHouseholdId = prefs.getString(_selectedHouseholdKey);

    final expiryString = prefs.getString(_tokenExpiryKey);
    if (expiryString != null) {
      _tokenExpiry = DateTime.parse(expiryString);
    }

    // Refresh token if expired
    if (_accessToken != null && _tokenExpiry != null) {
      if (_tokenExpiry!.isBefore(DateTime.now()) && _refreshToken != null) {
        await _refreshAccessToken();
      }
    }
  }

  /// Get authorization URL for OAuth flow
  Future<String> getAuthorizationUrl(
      String clientId, String redirectUri) async {
    final params = {
      'client_id': clientId,
      'response_type': 'code',
      'scope': requiredScopes.join(' '),
      'redirect_uri': redirectUri,
      'state': DateTime.now().millisecondsSinceEpoch.toString(),
    };

    final uri =
        Uri.parse(authorizationEndpoint).replace(queryParameters: params);
    return uri.toString();
  }

  /// Exchange authorization code for access token
  Future<bool> exchangeCodeForToken(
    String code,
    String clientId,
    String clientSecret,
    String redirectUri,
  ) async {
    try {
      final credentials = base64Encode(utf8.encode('$clientId:$clientSecret'));

      final response = await http.post(
        Uri.parse(tokenEndpoint),
        headers: {
          'Authorization': 'Basic $credentials',
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: {
          'grant_type': 'authorization_code',
          'code': code,
          'redirect_uri': redirectUri,
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        await _saveTokens(data, clientId, clientSecret);
        return true;
      } else {
        print(
            'Token exchange failed: ${response.statusCode} - ${response.body}');
        return false;
      }
    } catch (e) {
      print('Error exchanging code for token: $e');
      return false;
    }
  }

  Future<void> _saveTokens(Map<String, dynamic> tokenData, String? clientId,
      String? clientSecret) async {
    _accessToken = tokenData['access_token'];
    _refreshToken = tokenData['refresh_token'];

    final expiresIn = tokenData['expires_in'] as int;
    _tokenExpiry = DateTime.now().add(Duration(seconds: expiresIn));

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_accessTokenKey, _accessToken!);
    if (_refreshToken != null) {
      await prefs.setString(_refreshTokenKey, _refreshToken!);
    }
    if (clientId != null) {
      await prefs.setString(_clientIdKey, clientId);
    }
    if (clientSecret != null) {
      await prefs.setString(_clientSecretKey, clientSecret);
    }
    await prefs.setString(_tokenExpiryKey, _tokenExpiry!.toIso8601String());
  }

  Future<bool> _refreshAccessToken() async {
    if (_refreshToken == null) return false;

    try {
      final prefs = await SharedPreferences.getInstance();
      final clientId = prefs.getString(_clientIdKey);
      final clientSecret = prefs.getString(_clientSecretKey);

      if (clientId == null || clientSecret == null) {
        print('Missing client credentials for token refresh');
        return false;
      }

      final credentials = base64Encode(utf8.encode('$clientId:$clientSecret'));

      final response = await http.post(
        Uri.parse(tokenEndpoint),
        headers: {
          'Authorization': 'Basic $credentials',
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: {
          'grant_type': 'refresh_token',
          'refresh_token': _refreshToken!,
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        await _saveTokens(data, null, null);
        return true;
      } else {
        print(
            'Token refresh failed: ${response.statusCode} - ${response.body}');
        return false;
      }
    } catch (e) {
      print('Error refreshing token: $e');
      return false;
    }
  }

  /// Discover Sonos devices using Cloud API (requires authentication)
  Future<List<SonosDevice>> discoverDevices({
    bool useCache = true,
    Function(SonosDevice)? onDeviceFound,
  }) async {
    // Return cached devices if available
    if (useCache &&
        _cachedDevices != null &&
        _lastDiscoveryTime != null &&
        DateTime.now().difference(_lastDiscoveryTime!) < _cacheExpiration) {
      print('Returning ${_cachedDevices!.length} cached Sonos devices');
      if (onDeviceFound != null) {
        for (final device in _cachedDevices!) {
          onDeviceFound(device);
        }
      }
      return _cachedDevices!;
    }

    if (!isAuthenticated) {
      print('Cannot discover devices: Not authenticated');
      return [];
    }

    try {
      // Get households
      final households = await _getHouseholds();
      if (households.isEmpty) {
        print('No households found');
        return [];
      }

      // Use first household or previously selected one
      final householdId = _selectedHouseholdId ?? households.first['id'];
      _selectedHouseholdId = householdId;

      // Save household
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_selectedHouseholdKey, householdId);

      // Get groups (which represent devices/rooms)
      final groups = await _getGroups(householdId);
      final devices = <SonosDevice>[];

      for (final group in groups) {
        print('Processing group: ${group['name']} (ID: ${group['id']})');

        // Extract player IDs from the group
        final playerIds = group['playerIds'] as List<dynamic>?;

        if (playerIds == null || playerIds.isEmpty) {
          print('Warning: Group ${group['id']} has no players, skipping');
          continue;
        }

        // Use the first player ID (usually the coordinator)
        final playerId = playerIds[0] as String;
        print('Using player ID: $playerId for group ${group['name']}');

        // Create device using the player ID
        final device = SonosDevice.fromCloudApi(group, playerId);
        devices.add(device);

        if (onDeviceFound != null) {
          onDeviceFound(device);
        }
      }

      // Update cache
      _cachedDevices = devices;
      _lastDiscoveryTime = DateTime.now();

      print('Discovery complete: Found ${devices.length} Sonos device(s)');
      return devices;
    } catch (e) {
      print('Error discovering devices: $e');
      return [];
    }
  }

  Future<List<String>> getPlayersInGroup(String groupId) async {
    if (!isAuthenticated) {
      print('Cannot get players: Not authenticated');
      return [];
    }

    try {
      final households = await _getHouseholds();
      if (households.isEmpty) return [];

      final householdId = _selectedHouseholdId ?? households.first['id'];
      final groups = await _getGroups(householdId);

      final group = groups.firstWhere(
        (g) => g['id'] == groupId,
        orElse: () => <String, dynamic>{},
      );

      if (group.isEmpty) {
        print('Group $groupId not found');
        return [];
      }

      final playerIds = group['playerIds'] as List<dynamic>? ?? [];
      return playerIds.map((id) => id as String).toList();
    } catch (e) {
      print('Error getting players in group: $e');
      return [];
    }
  }

  Future<bool> setGroupVolume(String groupId, int volumePercent) async {
    final playerIds = await getPlayersInGroup(groupId);

    if (playerIds.isEmpty) {
      print('No players found in group $groupId');
      return false;
    }

    bool allSuccess = true;
    for (final playerId in playerIds) {
      final success =
          await _executeVolumeChange(volumePercent, deviceId: playerId);
      if (!success) {
        allSuccess = false;
        print('Failed to set volume for player $playerId');
      }
    }

    return allSuccess;
  }

  Future<List<Map<String, dynamic>>> _getHouseholds() async {
    final response = await _makeAuthenticatedRequest('/households', 'GET');

    if (response == null || response.statusCode != 200) {
      print('Failed to get households: ${response?.statusCode}');
      return [];
    }

    try {
      final data = jsonDecode(response.body);
      return List<Map<String, dynamic>>.from(data['households'] ?? []);
    } catch (e) {
      print('Error parsing households: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> _getGroups(String householdId) async {
    final response = await _makeAuthenticatedRequest(
        '/households/$householdId/groups', 'GET');

    if (response == null || response.statusCode != 200) {
      print('Failed to get groups: ${response?.statusCode}');
      return [];
    }

    try {
      final data = jsonDecode(response.body);
      return List<Map<String, dynamic>>.from(data['groups'] ?? []);
    } catch (e) {
      print('Error parsing groups: $e');
      return [];
    }
  }

  Future<bool> _checkAndWaitForRateLimit() async {
    final now = DateTime.now();

    _requestTimestamps.removeWhere(
        (timestamp) => now.difference(timestamp) > _rateLimitWindow);

    if (_requestTimestamps.length >= _maxRequestsPer30Seconds) {
      final oldestTimestamp = _requestTimestamps.first;
      final waitTime = _rateLimitWindow - now.difference(oldestTimestamp);

      if (waitTime.inMilliseconds > 0) {
        print('Rate limit reached, waiting ${waitTime.inMilliseconds}ms');
        await Future.delayed(waitTime);
        return await _checkAndWaitForRateLimit();
      }
    }

    _requestTimestamps.add(now);
    return true;
  }

  Future<http.Response?> _makeAuthenticatedRequest(
    String endpoint,
    String method, {
    Map<String, dynamic>? body,
  }) async {
    // Ensure we have a valid token
    if (!isAuthenticated) {
      if (_refreshToken != null) {
        final refreshed = await _refreshAccessToken();
        if (!refreshed) {
          print('Failed to refresh token');
          return null;
        }
      } else {
        print('Not authenticated and no refresh token available');
        return null;
      }
    }

    await _checkAndWaitForRateLimit();

    try {
      final uri = Uri.parse('$apiBaseUrl$endpoint');
      final headers = {
        'Authorization': 'Bearer $_accessToken',
        'Content-Type': 'application/json',
      };

      http.Response response;

      switch (method.toUpperCase()) {
        case 'GET':
          response = await http.get(uri, headers: headers);
          break;
        case 'POST':
          response = await http.post(
            uri,
            headers: headers,
            body: body != null ? jsonEncode(body) : null,
          );
          break;
        case 'PUT':
          response = await http.put(
            uri,
            headers: headers,
            body: body != null ? jsonEncode(body) : null,
          );
          break;
        default:
          throw Exception('Unsupported HTTP method: $method');
      }

      // Handle rate limit
      if (response.statusCode == 429) {
        final retryAfter = response.headers['retry-after'];
        if (retryAfter != null) {
          final waitSeconds = int.tryParse(retryAfter) ?? 30;
          print('Rate limited by Sonos, waiting $waitSeconds seconds');
          await Future.delayed(Duration(seconds: waitSeconds));
          return await _makeAuthenticatedRequest(endpoint, method, body: body);
        }
      }

      return response;
    } catch (e) {
      print('Error making authenticated request: $e');
      return null;
    }
  }

  /// Set volume with batching to reduce API calls
  /// UPDATED: Support both individual players and groups
  void setVolume(double normalizedVolume, {String? deviceId, String? groupId}) {
    _pendingVolume = (normalizedVolume * 100).clamp(0, 100);
    _pendingGroupId = groupId; // Store group ID if provided

    _volumeUpdateTimer?.cancel();
    _volumeUpdateTimer = Timer(_volumeUpdateDelay, () async {
      if (_pendingVolume != null) {
        await _executeVolumeChange(
          _pendingVolume!.round(),
          deviceId: deviceId,
          groupId: _pendingGroupId,
        );
        _pendingVolume = null;
        _pendingGroupId = null;
      }
    });
  }

  Future<bool> _executeVolumeChange(int volumePercent,
      {String? deviceId, String? groupId}) async {
    final targetDeviceId = deviceId ?? _selectedDeviceId;
    if (targetDeviceId == null && groupId == null) {
      print('Cannot set volume: No device or group selected');
      return false;
    }

    // If groupId is provided, set volume for entire group
    if (groupId != null) {
      return await setGroupVolume(groupId, volumePercent);
    }

    // Otherwise, set volume for individual player
    final response = await _makeAuthenticatedRequest(
      '/players/$targetDeviceId/playerVolume',
      'POST',
      body: {'volume': volumePercent},
    );

    if (response == null) {
      print('Failed to set volume: No response');
      return false;
    }

    if (response.statusCode == 200) {
      print('Successfully set Sonos volume to $volumePercent%');
      return true;
    } else {
      print('Failed to set volume: ${response.statusCode} - ${response.body}');
      return false;
    }
  }

  Future<int?> getCurrentVolume({String? deviceId}) async {
    final targetDeviceId = deviceId ?? _selectedDeviceId;
    if (targetDeviceId == null) return null;

    final response = await _makeAuthenticatedRequest(
      '/players/$targetDeviceId/playerVolume',
      'GET',
    );

    if (response == null || response.statusCode != 200) {
      return null;
    }

    try {
      final data = jsonDecode(response.body);
      return data['volume'] as int?;
    } catch (e) {
      print('Error getting volume: $e');
      return null;
    }
  }

  Future<bool> setMute(bool muted, {String? deviceId, String? groupId}) async {
    final targetDeviceId = deviceId ?? _selectedDeviceId;
    if (targetDeviceId == null && groupId == null) {
      print('Cannot set mute: No device or group selected');
      return false;
    }

    // If groupId is provided, mute entire group
    if (groupId != null) {
      final playerIds = await getPlayersInGroup(groupId);
      if (playerIds.isEmpty) {
        print('No players found in group $groupId');
        return false;
      }

      bool allSuccess = true;
      for (final playerId in playerIds) {
        final response = await _makeAuthenticatedRequest(
          '/players/$playerId/playerVolume',
          'POST',
          body: {'muted': muted},
        );

        if (response == null || response.statusCode != 200) {
          allSuccess = false;
          print('Failed to set mute for player $playerId');
        }
      }
      return allSuccess;
    }

    // Otherwise, mute individual player
    final response = await _makeAuthenticatedRequest(
      '/players/$targetDeviceId/playerVolume',
      'POST',
      body: {'muted': muted},
    );

    if (response == null) {
      print('Failed to set mute: No response');
      return false;
    }

    if (response.statusCode == 200) {
      print('Successfully ${muted ? "muted" : "unmuted"} Sonos device');
      return true;
    } else {
      print('Failed to set mute: ${response.statusCode} - ${response.body}');
      return false;
    }
  }

  Future<bool?> getMute({String? deviceId}) async {
    final targetDeviceId = deviceId ?? _selectedDeviceId;
    if (targetDeviceId == null) return null;

    final response = await _makeAuthenticatedRequest(
      '/players/$targetDeviceId/playerVolume',
      'GET',
    );

    if (response == null || response.statusCode != 200) {
      return null;
    }

    try {
      final data = jsonDecode(response.body);
      return data['muted'] as bool?;
    } catch (e) {
      print('Error getting mute state: $e');
      return null;
    }
  }

  Future<void> selectDevice(
      String deviceId, String deviceIp, String deviceName) async {
    _selectedDeviceId = deviceId;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_selectedDeviceKey, deviceId);

    print('Selected Sonos device: $deviceName (ID: $deviceId)');
  }

  Future<void> disconnect() async {
    _accessToken = null;
    _refreshToken = null;
    _tokenExpiry = null;
    _selectedDeviceId = null;
    _selectedHouseholdId = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_accessTokenKey);
    await prefs.remove(_refreshTokenKey);
    await prefs.remove(_tokenExpiryKey);
    await prefs.remove(_selectedDeviceKey);
    await prefs.remove(_selectedHouseholdKey);

    _volumeUpdateTimer?.cancel();
    _cachedDevices = null;
    _lastDiscoveryTime = null;

    print('Disconnected from Sonos');
  }

  void clearCache() {
    _cachedDevices = null;
    _lastDiscoveryTime = null;
    print('Sonos device cache cleared');
  }

  void dispose() {
    _volumeUpdateTimer?.cancel();
    _requestTimestamps.clear();
  }
}

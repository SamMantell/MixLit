import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class SpotifyDevice {
  final String id;
  final String name;
  final String type;
  final bool isActive;
  final int volumePercent;

  SpotifyDevice({
    required this.id,
    required this.name,
    required this.type,
    required this.isActive,
    required this.volumePercent,
  });

  factory SpotifyDevice.fromJson(Map<String, dynamic> json) {
    return SpotifyDevice(
      id: json['id'] ?? '',
      name: json['name'] ?? 'Unknown Device',
      type: json['type'] ?? 'Unknown',
      isActive: json['is_active'] ?? false,
      volumePercent: json['volume_percent'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'type': type,
      'is_active': isActive,
      'volume_percent': volumePercent,
    };
  }
}

class SpotifyIntegration {
  static const String _clientIdKey = 'spotify_client_id';
  static const String _clientSecretKey = 'spotify_client_secret';
  static const String _accessTokenKey = 'spotify_access_token';
  static const String _refreshTokenKey = 'spotify_refresh_token';
  static const String _tokenExpiryKey = 'spotify_token_expiry';
  static const String _selectedDeviceKey = 'spotify_selected_device';

  static const String authorizationEndpoint =
      'https://accounts.spotify.com/authorize';
  static const String tokenEndpoint = 'https://accounts.spotify.com/api/token';
  static const String apiBaseUrl = 'https://api.spotify.com/v1';

  static const List<String> requiredScopes = [
    'user-modify-playback-state',
    'user-read-playback-state',
  ];

  // Rate limiting
  final List<DateTime> _requestTimestamps = [];
  static const int _maxRequestsPer30Seconds = 100; // Conservative limit
  static const Duration _rateLimitWindow = Duration(seconds: 30);

  Timer? _volumeUpdateTimer;
  double? _pendingVolume;
  static const Duration _volumeUpdateDelay = Duration(milliseconds: 500);

  String? _accessToken;
  String? _refreshToken;
  DateTime? _tokenExpiry;
  String? _selectedDeviceId;

  static final SpotifyIntegration _instance = SpotifyIntegration._internal();
  static SpotifyIntegration get instance => _instance;
  SpotifyIntegration._internal();

  // Authentication status
  bool get isAuthenticated =>
      _accessToken != null && (_tokenExpiry?.isAfter(DateTime.now()) ?? false);

  String? get selectedDeviceId => _selectedDeviceId;

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    _accessToken = prefs.getString(_accessTokenKey);
    _refreshToken = prefs.getString(_refreshTokenKey);
    _selectedDeviceId = prefs.getString(_selectedDeviceKey);

    final expiryString = prefs.getString(_tokenExpiryKey);
    if (expiryString != null) {
      _tokenExpiry = DateTime.parse(expiryString);
    }

    if (_accessToken != null && _tokenExpiry != null) {
      if (_tokenExpiry!.isBefore(DateTime.now()) && _refreshToken != null) {
        await _refreshAccessToken();
      }
    }
  }

  Future<String> getAuthorizationUrl(
      String clientId, String redirectUri) async {
    final params = {
      'client_id': clientId,
      'response_type': 'code',
      'redirect_uri': redirectUri,
      'scope': requiredScopes.join(' '),
      'show_dialog': 'true',
    };

    final uri =
        Uri.parse(authorizationEndpoint).replace(queryParameters: params);
    return uri.toString();
  }

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
        await _saveTokens(data);
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

  Future<void> _saveTokens(Map<String, dynamic> tokenData) async {
    _accessToken = tokenData['access_token'];
    _refreshToken = tokenData['refresh_token'];

    final expiresIn = tokenData['expires_in'] as int;
    _tokenExpiry = DateTime.now().add(Duration(seconds: expiresIn));

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_accessTokenKey, _accessToken!);
    if (_refreshToken != null) {
      await prefs.setString(_refreshTokenKey, _refreshToken!);
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
        await _saveTokens(data);
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
    Map<String, String>? queryParams,
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
      final uri = Uri.parse('$apiBaseUrl$endpoint')
          .replace(queryParameters: queryParams);

      final headers = {
        'Authorization': 'Bearer $_accessToken',
        'Content-Type': 'application/json',
      };

      http.Response response;

      switch (method.toUpperCase()) {
        case 'GET':
          response = await http.get(uri, headers: headers);
          break;
        case 'PUT':
          response = await http.put(
            uri,
            headers: headers,
            body: body != null ? jsonEncode(body) : null,
          );
          break;
        case 'POST':
          response = await http.post(
            uri,
            headers: headers,
            body: body != null ? jsonEncode(body) : null,
          );
          break;
        default:
          throw Exception('Unsupported HTTP method: $method');
      }

      if (response.statusCode == 429) {
        final retryAfter = response.headers['retry-after'];
        if (retryAfter != null) {
          final waitSeconds = int.tryParse(retryAfter) ?? 30;
          print('Rate limited by Spotify, waiting $waitSeconds seconds');
          await Future.delayed(Duration(seconds: waitSeconds));
          // Retry the request
          return await _makeAuthenticatedRequest(endpoint, method,
              queryParams: queryParams, body: body);
        }
      }

      return response;
    } catch (e) {
      print('Error making authenticated request: $e');
      return null;
    }
  }

  Future<List<SpotifyDevice>> getAvailableDevices() async {
    final response =
        await _makeAuthenticatedRequest('/me/player/devices', 'GET');

    if (response == null || response.statusCode != 200) {
      print('Failed to get devices: ${response?.statusCode}');
      return [];
    }

    try {
      final data = jsonDecode(response.body);
      final devices = (data['devices'] as List)
          .map((device) => SpotifyDevice.fromJson(device))
          .toList();
      return devices;
    } catch (e) {
      print('Error parsing devices: $e');
      return [];
    }
  }

  Future<void> selectDevice(String deviceId) async {
    _selectedDeviceId = deviceId;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_selectedDeviceKey, deviceId);
  }

  Future<void> clearSelectedDevice() async {
    _selectedDeviceId = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_selectedDeviceKey);
  }

  void setVolume(double normalizedVolume, {String? deviceId}) {
    _pendingVolume = (normalizedVolume * 100).clamp(0, 100);

    _volumeUpdateTimer?.cancel();
    _volumeUpdateTimer = Timer(_volumeUpdateDelay, () async {
      if (_pendingVolume != null) {
        await _executeVolumeChange(_pendingVolume!.round(), deviceId: deviceId);
        _pendingVolume = null;
      }
    });
  }

  Future<bool> _executeVolumeChange(int volumePercent,
      {String? deviceId}) async {
    final targetDeviceId = deviceId ?? _selectedDeviceId;

    final queryParams = {
      'volume_percent': volumePercent.toString(),
      if (targetDeviceId != null) 'device_id': targetDeviceId,
    };

    final response = await _makeAuthenticatedRequest(
      '/me/player/volume',
      'PUT',
      queryParams: queryParams,
    );

    if (response == null) {
      print('Failed to set volume: No response');
      return false;
    }

    if (response.statusCode == 204 || response.statusCode == 200) {
      return true;
    } else {
      print('Failed to set volume: ${response.statusCode} - ${response.body}');
      return false;
    }
  }

  Future<Map<String, dynamic>?> getCurrentPlayback() async {
    final response = await _makeAuthenticatedRequest('/me/player', 'GET');

    if (response == null || response.statusCode == 204) {
      return null;
    }

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }

    return null;
  }

  Future<void> disconnect() async {
    _accessToken = null;
    _refreshToken = null;
    _tokenExpiry = null;
    _selectedDeviceId = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_accessTokenKey);
    await prefs.remove(_refreshTokenKey);
    await prefs.remove(_tokenExpiryKey);
    await prefs.remove(_selectedDeviceKey);

    _volumeUpdateTimer?.cancel();
  }

  void dispose() {
    _volumeUpdateTimer?.cancel();
  }
}

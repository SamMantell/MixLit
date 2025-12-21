import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:mixlit/backend/application/integration/OAuthCallbackServer.dart';
import 'package:mixlit/backend/application/integration/SpotifyIntegration.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SpotifyIntegrationDialog extends StatefulWidget {
  final int? sliderIndex;

  const SpotifyIntegrationDialog({
    super.key,
    this.sliderIndex,
  });

  @override
  State<SpotifyIntegrationDialog> createState() =>
      _SpotifyIntegrationDialogState();
}

class _SpotifyIntegrationDialogState extends State<SpotifyIntegrationDialog> {
  bool _isLoading = false;
  String? _error;
  bool _isAuthenticated = false;
  List<SpotifyDevice> _availableDevices = [];
  SpotifyDevice? _selectedDevice;

  final _clientIdController = TextEditingController();
  final _clientSecretController = TextEditingController();

  static const String _redirectUri = 'http://127.0.0.1:8888/callback';

  @override
  void initState() {
    super.initState();
    _loadSavedCredentials();
    _checkAuthStatus();
  }

  Future<void> _loadSavedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final clientId = prefs.getString('spotify_client_id');
    final clientSecret = prefs.getString('spotify_client_secret');

    if (clientId != null) _clientIdController.text = clientId;
    if (clientSecret != null) _clientSecretController.text = clientSecret;
  }

  Future<void> _checkAuthStatus() async {
    setState(() => _isLoading = true);

    try {
      await SpotifyIntegration.instance.initialize();
      _isAuthenticated = SpotifyIntegration.instance.isAuthenticated;

      if (_isAuthenticated) {
        await _loadDevices();
      }
    } catch (e) {
      print('Error checking auth status: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadDevices() async {
    setState(() => _isLoading = true);

    try {
      final devices = await SpotifyIntegration.instance.getAvailableDevices();
      setState(() {
        _availableDevices = devices;

        final selectedId = SpotifyIntegration.instance.selectedDeviceId;
        if (selectedId != null && devices.isNotEmpty) {
          try {
            _selectedDevice = devices.firstWhere((d) => d.id == selectedId);
          } catch (e) {
            _selectedDevice = devices.firstWhere(
              (d) => d.isActive,
              orElse: () => devices.first,
            );
          }
        } else if (devices.isNotEmpty) {
          _selectedDevice = devices.firstWhere(
            (d) => d.isActive,
            orElse: () => devices.first,
          );
        } else {
          _selectedDevice = null;
        }
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load devices: $e';
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _startOAuthFlow() async {
    if (_clientIdController.text.isEmpty ||
        _clientSecretController.text.isEmpty) {
      setState(() {
        _error = 'Please enter both Client ID and Client Secret';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          'spotify_client_id', _clientIdController.text.trim());
      await prefs.setString(
          'spotify_client_secret', _clientSecretController.text.trim());

      final callbackServer = OAuthCallbackServer();
      final codeFuture = callbackServer.waitForCallback();

      final authUrl = await SpotifyIntegration.instance.getAuthorizationUrl(
        _clientIdController.text.trim(),
        _redirectUri,
      );

      final uri = Uri.parse(authUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);

        final code = await codeFuture.timeout(
          const Duration(minutes: 5),
          onTimeout: () {
            callbackServer.close();
            return null;
          },
        );

        if (code != null) {
          final success =
              await SpotifyIntegration.instance.exchangeCodeForToken(
            code,
            _clientIdController.text.trim(),
            _clientSecretController.text.trim(),
            _redirectUri,
          );

          if (success) {
            setState(() {
              _isAuthenticated = true;
              _error = null;
            });
            await _loadDevices();
          } else {
            setState(() {
              _error = 'Failed to authenticate with Spotify. Please try again.';
            });
          }
        } else {
          setState(() {
            _error =
                'Authorization timed out or was cancelled. Please try again.';
          });
        }
      } else {
        setState(() {
          _error =
              'Could not launch browser. Please check your system settings.';
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Error during authorization: ${e.toString()}';
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveAndClose() async {
    if (_selectedDevice != null) {
      await SpotifyIntegration.instance.selectDevice(_selectedDevice!.id);

      if (mounted) {
        Navigator.pop(context, {
          'type': 'spotify',
          'deviceId': _selectedDevice!.id,
          'deviceName': _selectedDevice!.name,
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
      child: Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: 500,
          constraints: const BoxConstraints(maxHeight: 700),
          decoration: BoxDecoration(
            color:
                isDarkMode ? const Color(0xFF1E1E1E) : const Color(0xFFF5F5F5),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDarkMode
                  ? Colors.white.withOpacity(0.1)
                  : Colors.black.withOpacity(0.1),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 20,
                spreadRadius: 5,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHeader(isDarkMode),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: _isAuthenticated
                      ? _buildDeviceSelection(isDarkMode)
                      : _buildAuthenticationForm(isDarkMode),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(bool isDarkMode) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: isDarkMode
                ? Colors.white.withOpacity(0.1)
                : Colors.black.withOpacity(0.1),
          ),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            child: Padding(
              padding: const EdgeInsets.all(2.0),
              child: Image.asset(
                'lib/frontend/assets/images/logo/integrations/Spotify.png',
                fit: BoxFit.contain,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Link Spotify',
                  style: TextStyle(
                    fontFamily: 'BitstreamVeraSans',
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: isDarkMode ? Colors.white : Colors.black87,
                  ),
                ),
                if (widget.sliderIndex != null)
                  Text(
                    'Slider ${widget.sliderIndex! + 1}',
                    style: TextStyle(
                      fontFamily: 'BitstreamVeraSans',
                      fontSize: 12,
                      color: isDarkMode ? Colors.white60 : Colors.black54,
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: Icon(
              Icons.close,
              color: isDarkMode ? Colors.white70 : Colors.black54,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAuthenticationForm(bool isDarkMode) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Spotify Developer Credentials',
          style: TextStyle(
            fontFamily: 'BitstreamVeraSans',
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: isDarkMode ? Colors.white : Colors.black87,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Create an app at developer.spotify.com and set the redirect URI to: http://127.0.0.1:8888/callback',
          style: TextStyle(
            fontFamily: 'BitstreamVeraSans',
            fontSize: 12,
            color: isDarkMode ? Colors.white60 : Colors.black54,
          ),
        ),
        const SizedBox(height: 24),
        _buildTextField(
          controller: _clientIdController,
          label: 'Client ID',
          isDarkMode: isDarkMode,
        ),
        const SizedBox(height: 16),
        _buildTextField(
          controller: _clientSecretController,
          label: 'Client Secret',
          isDarkMode: isDarkMode,
          obscureText: true,
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _startOAuthFlow,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1DB954),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: _isLoading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Text(
                    'Authorize with Spotify',
                    style: TextStyle(
                      fontFamily: 'BitstreamVeraSans',
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
          ),
        ),
        if (_isLoading) ...[
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1DB954).withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: const Color(0xFF1DB954).withOpacity(0.3),
              ),
            ),
            child: Row(
              children: [
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor:
                        AlwaysStoppedAnimation<Color>(Color(0xFF1DB954)),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    'Waiting for authorization in your browser...\n\nA success page will appear once you authorize.',
                    style: TextStyle(
                      fontFamily: 'BitstreamVeraSans',
                      fontSize: 12,
                      color: isDarkMode ? Colors.white70 : Colors.black54,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _error!,
                    style: const TextStyle(
                      fontFamily: 'BitstreamVeraSans',
                      color: Colors.red,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildDeviceSelection(bool isDarkMode) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.check_circle,
              color: Color(0xFF1DB954),
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              'Connected to Spotify',
              style: TextStyle(
                fontFamily: 'BitstreamVeraSans',
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: const Color(0xFF1DB954),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Select Playback Device',
              style: TextStyle(
                fontFamily: 'BitstreamVeraSans',
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: isDarkMode ? Colors.white : Colors.black87,
              ),
            ),
            IconButton(
              onPressed: _loadDevices,
              icon: Icon(
                Icons.refresh,
                color: isDarkMode ? Colors.white70 : Colors.black54,
                size: 20,
              ),
              tooltip: 'Refresh devices',
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_isLoading)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(24.0),
              child: CircularProgressIndicator(),
            ),
          )
        else if (_availableDevices.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: isDarkMode
                  ? Colors.white.withOpacity(0.05)
                  : Colors.black.withOpacity(0.05),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.devices_other,
                  size: 48,
                  color: isDarkMode ? Colors.white30 : Colors.black26,
                ),
                const SizedBox(height: 16),
                Text(
                  'No devices found',
                  style: TextStyle(
                    fontFamily: 'BitstreamVeraSans',
                    fontSize: 14,
                    color: isDarkMode ? Colors.white60 : Colors.black54,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Open Spotify on a device to see it here',
                  style: TextStyle(
                    fontFamily: 'BitstreamVeraSans',
                    fontSize: 12,
                    color: isDarkMode ? Colors.white38 : Colors.black38,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          )
        else
          ..._availableDevices.map((device) {
            final isSelected = _selectedDevice?.id == device.id;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    setState(() {
                      _selectedDevice = device;
                    });
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFF1DB954).withOpacity(0.1)
                          : (isDarkMode
                              ? Colors.white.withOpacity(0.05)
                              : Colors.black.withOpacity(0.05)),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isSelected
                            ? const Color(0xFF1DB954)
                            : (isDarkMode
                                ? Colors.white.withOpacity(0.1)
                                : Colors.black.withOpacity(0.1)),
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _getDeviceIcon(device.type),
                          color: isSelected
                              ? const Color(0xFF1DB954)
                              : (isDarkMode ? Colors.white70 : Colors.black54),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                device.name,
                                style: TextStyle(
                                  fontFamily: 'BitstreamVeraSans',
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: isDarkMode
                                      ? Colors.white
                                      : Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                device.type,
                                style: TextStyle(
                                  fontFamily: 'BitstreamVeraSans',
                                  fontSize: 12,
                                  color: isDarkMode
                                      ? Colors.white60
                                      : Colors.black54,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (device.isActive)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1DB954).withOpacity(0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'Active',
                              style: TextStyle(
                                fontFamily: 'BitstreamVeraSans',
                                fontSize: 10,
                                color: Color(0xFF1DB954),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: TextButton(
                onPressed: () async {
                  await SpotifyIntegration.instance.disconnect();
                  setState(() {
                    _isAuthenticated = false;
                    _availableDevices = [];
                    _selectedDevice = null;
                  });
                },
                child: const Text(
                  'Disconnect',
                  style: TextStyle(
                    fontFamily: 'BitstreamVeraSans',
                    color: Colors.red,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              flex: 2,
              child: ElevatedButton(
                onPressed: _selectedDevice == null ? null : _saveAndClose,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1DB954),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text(
                  'Save & Link',
                  style: TextStyle(
                    fontFamily: 'BitstreamVeraSans',
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required bool isDarkMode,
    bool obscureText = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontFamily: 'BitstreamVeraSans',
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: isDarkMode ? Colors.white70 : Colors.black54,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          obscureText: obscureText,
          style: TextStyle(
            fontFamily: 'BitstreamVeraSans',
            color: isDarkMode ? Colors.white : Colors.black87,
          ),
          decoration: InputDecoration(
            filled: true,
            fillColor: isDarkMode
                ? Colors.white.withOpacity(0.05)
                : Colors.black.withOpacity(0.05),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: isDarkMode
                    ? Colors.white.withOpacity(0.1)
                    : Colors.black.withOpacity(0.1),
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: isDarkMode
                    ? Colors.white.withOpacity(0.1)
                    : Colors.black.withOpacity(0.1),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(
                color: Color(0xFF1DB954),
                width: 2,
              ),
            ),
          ),
        ),
      ],
    );
  }

  IconData _getDeviceIcon(String type) {
    switch (type.toLowerCase()) {
      case 'computer':
        return Icons.computer;
      case 'smartphone':
        return Icons.smartphone;
      case 'speaker':
        return Icons.speaker;
      case 'tv':
        return Icons.tv;
      case 'avr':
        return Icons.speaker_group;
      case 'stb':
        return Icons.settings_input_hdmi;
      case 'audio_dongle':
        return Icons.usb;
      case 'game_console':
        return Icons.games;
      case 'cast_video':
      case 'cast_audio':
        return Icons.cast;
      case 'automobile':
        return Icons.directions_car;
      default:
        return Icons.devices;
    }
  }

  @override
  void dispose() {
    _clientIdController.dispose();
    _clientSecretController.dispose();
    super.dispose();
  }
}

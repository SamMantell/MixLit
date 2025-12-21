import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:mixlit/backend/application/integration/SonosIntegration.dart';
import 'package:mixlit/backend/application/integration/OAuthCallbackServer.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SonosIntegrationDialog extends StatefulWidget {
  final int? sliderIndex;

  const SonosIntegrationDialog({
    super.key,
    this.sliderIndex,
  });

  @override
  State<SonosIntegrationDialog> createState() => _SonosIntegrationDialogState();
}

class _SonosIntegrationDialogState extends State<SonosIntegrationDialog> {
  bool _isLoading = false;
  String? _error;
  bool _isAuthenticated = false;
  List<SonosDevice> _availableDevices = [];
  SonosDevice? _selectedDevice;
  bool _isScanning = false;
  bool _waitingForCallback = false;

  // OAuth credentials
  final _clientIdController = TextEditingController();
  final _clientSecretController = TextEditingController();
  final _manualCodeController = TextEditingController();

  static const String _redirectUri =
      'https://mixlit.net/api/integration/sonos/callback';

  @override
  void initState() {
    super.initState();
    _loadSavedCredentials();
    _checkAuthStatus();
  }

  @override
  void dispose() {
    _clientIdController.dispose();
    _clientSecretController.dispose();
    _manualCodeController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final clientId = prefs.getString('sonos_client_id');
    final clientSecret = prefs.getString('sonos_client_secret');

    if (clientId != null) _clientIdController.text = clientId;
    if (clientSecret != null) _clientSecretController.text = clientSecret;
  }

  Future<void> _checkAuthStatus() async {
    setState(() => _isLoading = true);

    try {
      await SonosIntegration.instance.initialize();
      _isAuthenticated = SonosIntegration.instance.isAuthenticated;

      if (_isAuthenticated) {
        await _loadDevices();
      }
    } catch (e) {
      print('Error checking Sonos auth status: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
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
      _waitingForCallback = true;
      _error = null;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('sonos_client_id', _clientIdController.text.trim());
      await prefs.setString(
          'sonos_client_secret', _clientSecretController.text.trim());

      // Start local callback server
      final callbackServer = OAuthCallbackServer(port: 8889);
      final codeFuture = callbackServer.waitForCallback(service: 'Sonos');

      final authUrl = await SonosIntegration.instance.getAuthorizationUrl(
        _clientIdController.text.trim(),
        _redirectUri,
      );

      final uri = Uri.parse(authUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);

        // Wait for callback with timeout
        final code = await codeFuture.timeout(
          const Duration(minutes: 5),
          onTimeout: () {
            callbackServer.close();
            return null;
          },
        );

        if (code != null) {
          await _handleAuthorizationCode(code);
        } else {
          setState(() {
            _error =
                'Authorization timed out or was cancelled. Please try again.';
            _waitingForCallback = false;
          });
        }
      } else {
        setState(() {
          _error =
              'Could not launch browser. Please check your system settings.';
          _isLoading = false;
          _waitingForCallback = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Error during authorization: ${e.toString()}';
        _isLoading = false;
        _waitingForCallback = false;
      });
    }
  }

  Future<void> _handleAuthorizationCode(String code) async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _waitingForCallback = false;
    });

    try {
      final success = await SonosIntegration.instance.exchangeCodeForToken(
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
          _error = 'Failed to authenticate with Sonos. Please try again.';
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Error completing authorization: ${e.toString()}';
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadDevices() async {
    setState(() {
      _isLoading = true;
      _isScanning = true;
      _availableDevices = [];
      _error = null;
    });

    try {
      await SonosIntegration.instance.discoverDevices(
        useCache: false,
        onDeviceFound: (device) {
          if (mounted) {
            setState(() {
              _availableDevices.add(device);

              if (_selectedDevice == null) {
                _selectedDevice = device;
              }
            });
          }
        },
      );

      if (mounted) {
        final selectedId = SonosIntegration.instance.selectedDeviceId;
        if (selectedId != null && _availableDevices.isNotEmpty) {
          try {
            _selectedDevice =
                _availableDevices.firstWhere((d) => d.id == selectedId);
          } catch (e) {
            // Keep first device selected
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to discover Sonos devices: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isScanning = false;
        });
      }
    }
  }

  Future<void> _saveAndClose() async {
    if (_selectedDevice != null) {
      await SonosIntegration.instance.selectDevice(
        _selectedDevice!.id,
        _selectedDevice!.ipAddress,
        _selectedDevice!.name,
      );

      if (mounted) {
        Navigator.pop(context, {
          'type': 'sonos',
          'deviceId': _selectedDevice!.id,
          'deviceIp': _selectedDevice!.ipAddress,
          'deviceName': _selectedDevice!.roomName,
          'groupId': _selectedDevice!.groupId,
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
                'lib/frontend/assets/images/logo/integrations/Sonos.png',
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
                  'Link Sonos',
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
          'Sonos Control Integration Credentials',
          style: TextStyle(
            fontFamily: 'BitstreamVeraSans',
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: isDarkMode ? Colors.white : Colors.black87,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Create a Control Integration at integration.sonos.com and set the redirect URI to: $_redirectUri',
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
            onPressed:
                (_isLoading || _waitingForCallback) ? null : _startOAuthFlow,
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  isDarkMode ? Colors.white.withOpacity(0.9) : Colors.black87,
              foregroundColor: isDarkMode ? Colors.black87 : Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: _isLoading && !_waitingForCallback
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Text(
                    'Authorize with Sonos',
                    style: TextStyle(
                      fontFamily: 'BitstreamVeraSans',
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
          ),
        ),
        if (_waitingForCallback) ...[
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDarkMode
                  ? Colors.white.withOpacity(0.1)
                  : Colors.black.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isDarkMode
                    ? Colors.white.withOpacity(0.2)
                    : Colors.black.withOpacity(0.2),
              ),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      isDarkMode ? Colors.white70 : Colors.black54,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    'Waiting for authorization in your browser...\n\nComplete the authorization and this dialog will automatically continue.',
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
          const SizedBox(height: 16),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text(
              'Having trouble? Enter code manually',
              style: TextStyle(
                fontFamily: 'BitstreamVeraSans',
                fontSize: 12,
                color: isDarkMode ? Colors.white70 : Colors.black54,
              ),
            ),
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'If the authorization doesn\'t complete automatically, copy the code from your browser and paste it here:',
                      style: TextStyle(
                        fontFamily: 'BitstreamVeraSans',
                        fontSize: 11,
                        color: isDarkMode ? Colors.white60 : Colors.black54,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _manualCodeController,
                      style: TextStyle(
                        fontFamily: 'BitstreamVeraSans',
                        fontSize: 12,
                        color: isDarkMode ? Colors.white : Colors.black87,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Authorization Code',
                        hintText: 'Paste code here',
                        isDense: true,
                        contentPadding: const EdgeInsets.all(12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          if (_manualCodeController.text.isNotEmpty) {
                            _handleAuthorizationCode(
                                _manualCodeController.text.trim());
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isDarkMode
                              ? Colors.white.withOpacity(0.9)
                              : Colors.black87,
                          foregroundColor:
                              isDarkMode ? Colors.black87 : Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: const Text(
                          'Submit Code',
                          style: TextStyle(
                            fontFamily: 'BitstreamVeraSans',
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
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
              color: Colors.green,
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              'Connected to Sonos',
              style: TextStyle(
                fontFamily: 'BitstreamVeraSans',
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Colors.green,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Select Speaker/Group',
              style: TextStyle(
                fontFamily: 'BitstreamVeraSans',
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: isDarkMode ? Colors.white : Colors.black87,
              ),
            ),
            IconButton(
              onPressed: _isScanning ? null : _loadDevices,
              icon: Icon(
                Icons.refresh,
                color: _isScanning
                    ? (isDarkMode ? Colors.white30 : Colors.black26)
                    : (isDarkMode ? Colors.white70 : Colors.black54),
                size: 20,
              ),
              tooltip: 'Refresh devices',
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_isScanning && _availableDevices.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isDarkMode
                    ? Colors.white.withOpacity(0.2)
                    : Colors.black.withOpacity(0.2),
              ),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      isDarkMode ? Colors.white70 : Colors.black54,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    'Loading your Sonos devices...',
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
        if (_isScanning && _availableDevices.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      isDarkMode ? Colors.white70 : Colors.black54,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'Loading...',
                  style: TextStyle(
                    fontFamily: 'BitstreamVeraSans',
                    fontSize: 12,
                    color: isDarkMode ? Colors.white60 : Colors.black54,
                  ),
                ),
              ],
            ),
          ),
        if (!_isScanning && !_isLoading && _availableDevices.isEmpty)
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
                  Icons.speaker_group_outlined,
                  size: 48,
                  color: isDarkMode ? Colors.white30 : Colors.black26,
                ),
                const SizedBox(height: 16),
                Text(
                  'No Sonos devices found',
                  style: TextStyle(
                    fontFamily: 'BitstreamVeraSans',
                    fontSize: 14,
                    color: isDarkMode ? Colors.white60 : Colors.black54,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Make sure your Sonos system is set up\nand connected to your account',
                  style: TextStyle(
                    fontFamily: 'BitstreamVeraSans',
                    fontSize: 12,
                    color: isDarkMode ? Colors.white38 : Colors.black38,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: _loadDevices,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text(
                    'Refresh',
                    style: TextStyle(
                      fontFamily: 'BitstreamVeraSans',
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isDarkMode
                        ? Colors.white.withOpacity(0.1)
                        : Colors.black.withOpacity(0.1),
                    foregroundColor: isDarkMode ? Colors.white : Colors.black87,
                  ),
                ),
              ],
            ),
          )
        else
          ..._availableDevices.asMap().entries.map((entry) {
            final device = entry.value;
            final isSelected = _selectedDevice?.id == device.id;

            return TweenAnimationBuilder<double>(
              key: ValueKey(device.id),
              duration: const Duration(milliseconds: 300),
              tween: Tween(begin: 0.0, end: 1.0),
              curve: Curves.easeOutBack,
              builder: (context, animValue, child) {
                final clampedValue = animValue.clamp(0.0, 1.0);

                return Transform.scale(
                  scale: clampedValue,
                  child: Opacity(
                    opacity: clampedValue,
                    child: Padding(
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
                                  ? (isDarkMode
                                      ? Colors.white.withOpacity(0.1)
                                      : Colors.black.withOpacity(0.1))
                                  : (isDarkMode
                                      ? Colors.white.withOpacity(0.05)
                                      : Colors.black.withOpacity(0.05)),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isSelected
                                    ? (isDarkMode
                                        ? Colors.white
                                        : Colors.black87)
                                    : (isDarkMode
                                        ? Colors.white.withOpacity(0.1)
                                        : Colors.black.withOpacity(0.1)),
                                width: isSelected ? 2 : 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? (isDarkMode
                                            ? Colors.white.withOpacity(0.2)
                                            : Colors.black.withOpacity(0.2))
                                        : (isDarkMode
                                            ? Colors.white.withOpacity(0.1)
                                            : Colors.black.withOpacity(0.1)),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(
                                    Icons.speaker,
                                    color: isSelected
                                        ? (isDarkMode
                                            ? Colors.white
                                            : Colors.black87)
                                        : (isDarkMode
                                            ? Colors.white70
                                            : Colors.black54),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        device.roomName,
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
                                        device.name,
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
                                if (isSelected)
                                  Icon(
                                    Icons.check_circle,
                                    color: isDarkMode
                                        ? Colors.white
                                        : Colors.black87,
                                    size: 24,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
          }).toList(),
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
        if (_availableDevices.isNotEmpty) ...[
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () async {
                    await SonosIntegration.instance.disconnect();
                    if (mounted) {
                      setState(() {
                        _isAuthenticated = false;
                        _availableDevices = [];
                        _selectedDevice = null;
                      });
                    }
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
                    backgroundColor: isDarkMode
                        ? Colors.white.withOpacity(0.9)
                        : Colors.black87,
                    foregroundColor: isDarkMode ? Colors.black87 : Colors.white,
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
              borderSide: BorderSide(
                color: isDarkMode ? Colors.white : Colors.black87,
                width: 2,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

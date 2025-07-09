import 'dart:convert';
import 'dart:ui';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:mixlit/backend/application/data/ConfigManager.dart';
import 'package:window_manager/window_manager.dart';

class SettingsManager {
  static const String _autoStartupKey = 'auto_startup_enabled';
  static const String _minimizeToTrayKey = 'minimize_to_tray';
  static const String _minimizeOnStartupKey = 'minimize_on_startup';
  static const String _darkThemeKey = 'dark_theme_enabled';
  static const String _ledBrightnessKey = 'led_brightness';
  static const String _appGradientsKey = 'app_gradients_enabled';
  static const String _updateNotificationsKey = 'update_notifications_enabled';
  static const String _saveLastComPortKey = 'save_last_com_port';

  static Future<bool> getAutoStartup() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_autoStartupKey) ?? true;
  }

  static Future<void> setAutoStartup(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoStartupKey, enabled);
    if (enabled) {
      await launchAtStartup.enable();
    } else {
      await launchAtStartup.disable();
    }
  }

  static Future<bool> getMinimizeToTray() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_minimizeToTrayKey) ?? true;
  }

  static Future<void> setMinimizeToTray(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_minimizeToTrayKey, enabled);

    await windowManager.setPreventClose(enabled);
  }

  static Future<bool> getMinimizeOnStartup() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_minimizeOnStartupKey) ?? true;
  }

  static Future<void> setMinimizeOnStartup(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_minimizeOnStartupKey, enabled);
  }

  static Future<bool> getDarkTheme() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_darkThemeKey) ?? true;
  }

  static Future<void> setDarkTheme(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_darkThemeKey, enabled);
  }

  static Future<double> getLedBrightness() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_ledBrightnessKey) ?? 1.0;
  }

  static Future<void> setLedBrightness(double brightness) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_ledBrightnessKey, brightness);
  }

  static Future<bool> getAppGradients() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_appGradientsKey) ?? true;
  }

  static Future<void> setAppGradients(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_appGradientsKey, enabled);
  }

  static Future<bool> getUpdateNotifications() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_updateNotificationsKey) ?? true;
  }

  static Future<void> setUpdateNotifications(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_updateNotificationsKey, enabled);
  }

  static Future<bool> getSaveLastComPort() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_saveLastComPortKey) ?? true;
  }

  static Future<void> setSaveLastComPort(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_saveLastComPortKey, enabled);
  }
}

class TerminalWindow extends StatefulWidget {
  final Stream<String>? rawDataStream;
  final Stream<Map<int, int>>? sliderDataStream;
  final Stream<Map<String, int>>? buttonDataStream;

  const TerminalWindow({
    super.key,
    this.rawDataStream,
    this.sliderDataStream,
    this.buttonDataStream,
  });

  @override
  _TerminalWindowState createState() => _TerminalWindowState();
}

class _TerminalWindowState extends State<TerminalWindow> {
  final ScrollController _scrollController = ScrollController();
  final List<String> _terminalLines = [];
  static const int maxLines = 1000;

  @override
  void initState() {
    super.initState();

    _addTerminalLine('Started serial data stream listening...');

    widget.rawDataStream?.listen((data) {
      _addTerminalLine('RAW: $data');
    }, onError: (error) {
      _addTerminalLine('RAW ERROR: $error');
    });

    widget.sliderDataStream?.listen((data) {
      String formatted =
          data.entries.map((e) => 'S${e.key}:${e.value}').join(' ');
      _addTerminalLine('SLIDERS: $formatted');
    }, onError: (error) {
      _addTerminalLine('SLIDER ERROR: $error');
    });

    widget.buttonDataStream?.listen((data) {
      String formatted =
          data.entries.map((e) => '${e.key}:${e.value}').join(' ');
      _addTerminalLine('BUTTONS: $formatted');
    }, onError: (error) {
      _addTerminalLine('BUTTON ERROR: $error');
    });
  }

  void _addTerminalLine(String data) {
    if (mounted) {
      setState(() {
        String timestamp = DateTime.now().toString().substring(11, 23);
        _terminalLines.add('[$timestamp] $data');
        if (_terminalLines.length > maxLines) {
          _terminalLines.removeAt(0);
        }
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 100),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Container(
      height: 300,
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF1A1A1A) : const Color(0xFFF8F8F8),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDarkMode
              ? Colors.white.withOpacity(0.1)
              : Colors.black.withOpacity(0.1),
        ),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isDarkMode
                  ? const Color(0xFF2A2A2A)
                  : const Color(0xFFE8E8E8),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(8),
                topRight: Radius.circular(8),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.terminal,
                  size: 16,
                  color: isDarkMode
                      ? Colors.white.withOpacity(0.7)
                      : Colors.black.withOpacity(0.7),
                ),
                const SizedBox(width: 8),
                Text(
                  'Serial Terminal',
                  style: TextStyle(
                    fontFamily: 'BitstreamVeraSans',
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: isDarkMode
                        ? Colors.white.withOpacity(0.9)
                        : Colors.black.withOpacity(0.9),
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: Icon(
                    Icons.clear,
                    size: 16,
                    color: isDarkMode
                        ? Colors.white.withOpacity(0.7)
                        : Colors.black.withOpacity(0.7),
                  ),
                  onPressed: () {
                    setState(() {
                      _terminalLines.clear();
                    });
                  },
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 24, minHeight: 24),
                ),
              ],
            ),
          ),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(8),
              child: ListView.builder(
                controller: _scrollController,
                itemCount: _terminalLines.length,
                itemBuilder: (context, index) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 1),
                    child: Text(
                      _terminalLines[index],
                      style: TextStyle(
                        fontFamily: 'Courier New',
                        fontSize: 12,
                        color: isDarkMode
                            ? Colors.green.withOpacity(0.9)
                            : Colors.black.withOpacity(0.8),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> showSettingsDialog(
  BuildContext context, {
  Stream<String>? rawDataStream,
  Stream<Map<int, int>>? sliderDataStream,
  Stream<Map<String, int>>? buttonDataStream,
  Function(bool)? onThemeChanged,
}) async {
  const String noiseTextureBase64 =
      'PHN2ZyB3aWR0aD0iMjAwIiBoZWlnaHQ9IjIwMCIgeG1sbnM9Imh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnIj4KICA8ZGVmcz4KICAgIDxmaWx0ZXIgaWQ9Im5vaXNlIj4KICAgICAgPGZlVHVyYnVsZW5jZSBiYXNlRnJlcXVlbmN5PSIwLjkiIG51bU9jdGF2ZXM9IjQiIHNlZWQ9IjIiLz4KICAgICAgPGZlQ29sb3JNYXRyaXggdHlwZT0ic2F0dXJhdGUiIHZhbHVlcz0iMCIvPgogICAgPC9maWx0ZXI+CiAgPC9kZWZzPgogIDxyZWN0IHdpZHRoPSIxMDAlIiBoZWlnaHQ9IjEwMCUiIGZpbHRlcj0idXJsKCNub2lzZSkiIG9wYWNpdHk9IjAuMDUiLz4KPC9zdmc+';
  final Uint8List noiseTextureBytes = base64Decode(noiseTextureBase64);

  await showDialog(
    context: context,
    barrierDismissible: true,
    builder: (BuildContext context) {
      return SettingsDialog(
        noiseTextureBytes: noiseTextureBytes,
        rawDataStream: rawDataStream,
        sliderDataStream: sliderDataStream,
        buttonDataStream: buttonDataStream,
        onThemeChanged: onThemeChanged,
      );
    },
  );
}

class SettingsDialog extends StatefulWidget {
  final Uint8List noiseTextureBytes;
  final Stream<String>? rawDataStream;
  final Stream<Map<int, int>>? sliderDataStream;
  final Stream<Map<String, int>>? buttonDataStream;
  final Function(bool)? onThemeChanged;

  const SettingsDialog({
    super.key,
    required this.noiseTextureBytes,
    this.rawDataStream,
    this.sliderDataStream,
    this.buttonDataStream,
    this.onThemeChanged,
  });

  @override
  _SettingsDialogState createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  bool _autoStartup = true;
  bool _minimizeToTray = true;
  bool _minimizeOnStartup = true;
  bool _darkTheme = true;
  double _ledBrightness = 1.0;
  bool _appGradients = true;
  bool _updateNotifications = true;
  bool _saveLastComPort = true;
  bool _showTerminal = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final autoStartup = await SettingsManager.getAutoStartup();
    final minimizeToTray = await SettingsManager.getMinimizeToTray();
    final minimizeOnStartup = await SettingsManager.getMinimizeOnStartup();
    final darkTheme = await SettingsManager.getDarkTheme();
    final ledBrightness = await SettingsManager.getLedBrightness();
    final appGradients = await SettingsManager.getAppGradients();
    final updateNotifications = await SettingsManager.getUpdateNotifications();
    final saveLastComPort = await SettingsManager.getSaveLastComPort();

    setState(() {
      _autoStartup = autoStartup;
      _minimizeToTray = minimizeToTray;
      _minimizeOnStartup = minimizeOnStartup;
      _darkTheme = darkTheme;
      _ledBrightness = ledBrightness;
      _appGradients = appGradients;
      _updateNotifications = updateNotifications;
      _saveLastComPort = saveLastComPort;
    });
  }

  Widget _buildSettingItem({
    required String title,
    required String subtitle,
    required bool value,
    required Function(bool) onChanged,
    IconData? icon,
    bool enabled = true,
  }) {
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: Colors.transparent,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: enabled ? () => onChanged(!value) : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                if (icon != null) ...[
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      color: isDarkMode
                          ? Colors.white.withOpacity(0.1)
                          : Colors.black.withOpacity(0.1),
                    ),
                    child: Icon(
                      icon,
                      color: enabled
                          ? (isDarkMode ? Colors.white : Colors.black54)
                          : (isDarkMode
                              ? Colors.white.withOpacity(0.3)
                              : Colors.black26),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 16),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontFamily: 'BitstreamVeraSans',
                          color: enabled
                              ? (isDarkMode
                                  ? Colors.white
                                  : const Color.fromARGB(255, 92, 92, 92))
                              : (isDarkMode
                                  ? Colors.white.withOpacity(0.3)
                                  : Colors.black26),
                          fontWeight: FontWeight.w500,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontFamily: 'BitstreamVeraSans',
                          color: enabled
                              ? (isDarkMode
                                  ? Colors.white.withOpacity(0.6)
                                  : const Color.fromARGB(255, 92, 92, 92)
                                      .withOpacity(0.6))
                              : (isDarkMode
                                  ? Colors.white.withOpacity(0.2)
                                  : Colors.black26),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: value,
                  onChanged: enabled ? onChanged : null,
                  activeColor: const Color.fromARGB(214, 255, 254, 209),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSliderItem({
    required String title,
    required String subtitle,
    required double value,
    required Function(double) onChanged,
    required double min,
    required double max,
    IconData? icon,
    bool enabled = true,
  }) {
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: Colors.transparent,
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            if (icon != null) ...[
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: isDarkMode
                      ? Colors.white.withOpacity(0.1)
                      : Colors.black.withOpacity(0.1),
                ),
                child: Icon(
                  icon,
                  color: enabled
                      ? (isDarkMode ? Colors.white : Colors.black54)
                      : (isDarkMode
                          ? Colors.white.withOpacity(0.3)
                          : Colors.black26),
                  size: 20,
                ),
              ),
              const SizedBox(width: 16),
            ],
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontFamily: 'BitstreamVeraSans',
                      color: enabled
                          ? (isDarkMode
                              ? Colors.white
                              : const Color.fromARGB(255, 92, 92, 92))
                          : (isDarkMode
                              ? Colors.white.withOpacity(0.3)
                              : Colors.black26),
                      fontWeight: FontWeight.w500,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontFamily: 'BitstreamVeraSans',
                      color: enabled
                          ? (isDarkMode
                              ? Colors.white.withOpacity(0.6)
                              : const Color.fromARGB(255, 92, 92, 92)
                                  .withOpacity(0.6))
                          : (isDarkMode
                              ? Colors.white.withOpacity(0.2)
                              : Colors.black26),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 3,
              child: Row(
                children: [
                  Expanded(
                    child: Slider(
                      value: value,
                      min: min,
                      max: max,
                      onChanged: enabled ? onChanged : null,
                      activeColor: const Color.fromARGB(222, 254, 255, 255),
                      inactiveColor: isDarkMode
                          ? Colors.white.withOpacity(0.2)
                          : Colors.black.withOpacity(0.2),
                    ),
                  ),
                  Container(
                    width: 45,
                    child: Text(
                      '${(value * 100).round()}%',
                      style: TextStyle(
                        fontFamily: 'BitstreamVeraSans',
                        color: enabled
                            ? (isDarkMode
                                ? Colors.white.withOpacity(0.9)
                                : Colors.black.withOpacity(0.9))
                            : (isDarkMode
                                ? Colors.white.withOpacity(0.3)
                                : Colors.black26),
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionItem({
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    IconData? icon,
    bool enabled = true,
    Color? iconColor,
  }) {
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: Colors.transparent,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: enabled ? onTap : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                if (icon != null) ...[
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      color: iconColor?.withOpacity(0.1) ??
                          (isDarkMode
                              ? Colors.white.withOpacity(0.1)
                              : Colors.black.withOpacity(0.1)),
                    ),
                    child: Icon(
                      icon,
                      color: enabled
                          ? (iconColor ??
                              (isDarkMode ? Colors.white : Colors.black54))
                          : (isDarkMode
                              ? Colors.white.withOpacity(0.3)
                              : Colors.black26),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 16),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontFamily: 'BitstreamVeraSans',
                          color: enabled
                              ? (iconColor ??
                                  (isDarkMode
                                      ? Colors.white
                                      : const Color.fromARGB(255, 92, 92, 92)))
                              : (isDarkMode
                                  ? Colors.white.withOpacity(0.3)
                                  : Colors.black26),
                          fontWeight: FontWeight.w500,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontFamily: 'BitstreamVeraSans',
                          color: enabled
                              ? (iconColor?.withOpacity(0.7) ??
                                  (isDarkMode
                                      ? Colors.white.withOpacity(0.6)
                                      : const Color.fromARGB(255, 92, 92, 92)
                                          .withOpacity(0.6)))
                              : (isDarkMode
                                  ? Colors.white.withOpacity(0.2)
                                  : Colors.black26),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: enabled
                      ? (isDarkMode
                          ? Colors.white.withOpacity(0.5)
                          : Colors.black.withOpacity(0.5))
                      : (isDarkMode
                          ? Colors.white.withOpacity(0.2)
                          : Colors.black26),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
      child: Stack(
        children: [
          DefaultTabController(
            length: 3,
            child: Dialog(
              backgroundColor: Colors.transparent,
              child: Container(
                width: MediaQuery.of(context).size.width * 0.7,
                height: MediaQuery.of(context).size.height * 0.8,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  image: DecorationImage(
                    image: MemoryImage(widget.noiseTextureBytes),
                    repeat: ImageRepeat.repeat,
                    opacity: 0.05,
                  ),
                  color: isDarkMode
                      ? const Color(0xFF1E1E1E)
                      : const Color.fromARGB(255, 214, 214, 214),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isDarkMode
                        ? Colors.white.withOpacity(0.1)
                        : Colors.black.withOpacity(0.1),
                    width: 1,
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
                    const TabBar(
                      tabs: [
                        Tab(
                          child: Text(
                            'General',
                            style: TextStyle(
                              fontFamily: 'BitstreamVeraSans',
                            ),
                          ),
                        ),
                        Tab(
                          child: Text(
                            'Device',
                            style: TextStyle(
                              fontFamily: 'BitstreamVeraSans',
                            ),
                          ),
                        ),
                        Tab(
                          child: Text(
                            'Advanced',
                            style: TextStyle(
                              fontFamily: 'BitstreamVeraSans',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: TabBarView(
                        children: [
                          // General Tab
                          ListView(
                            children: [
                              _buildSettingItem(
                                title: 'Open on Start-Up',
                                subtitle:
                                    'Launch the MixLit app when your device starts',
                                value: _autoStartup,
                                onChanged: (value) async {
                                  await SettingsManager.setAutoStartup(value);
                                  setState(() => _autoStartup = value);
                                },
                                icon: Icons.play_arrow,
                              ),
                              _buildSettingItem(
                                title: 'Minimise on Start-Up',
                                subtitle: 'Start minimised to the system tray',
                                value: _minimizeOnStartup,
                                onChanged: (value) async {
                                  await SettingsManager.setMinimizeOnStartup(
                                      value);
                                  setState(() => _minimizeOnStartup = value);
                                },
                                icon: Icons.visibility_off,
                              ),
                              _buildSettingItem(
                                title: 'Minimise to System Tray',
                                subtitle: 'Hide to tray upon app closure',
                                value: _minimizeToTray,
                                onChanged: (value) async {
                                  await SettingsManager.setMinimizeToTray(
                                      value);
                                  setState(() => _minimizeToTray = value);
                                },
                                icon: Icons.minimize,
                              ),
                              _buildSettingItem(
                                title: 'Dark Theme',
                                subtitle:
                                    'pls keep this on, not done with light mode yet lol',
                                value: _darkTheme,
                                onChanged: (value) async {
                                  await SettingsManager.setDarkTheme(value);
                                  setState(() => _darkTheme = value);
                                  if (widget.onThemeChanged != null) {
                                    widget.onThemeChanged!(value);
                                  }
                                  Navigator.of(context).pop();
                                  Future.delayed(Duration(milliseconds: 100),
                                      () {
                                    showSettingsDialog(
                                      context,
                                      rawDataStream: widget.rawDataStream,
                                      sliderDataStream: widget.sliderDataStream,
                                      buttonDataStream: widget.buttonDataStream,
                                      onThemeChanged: widget.onThemeChanged,
                                    );
                                  });
                                },
                                icon: Icons.dark_mode,
                              ),
                              _buildSettingItem(
                                title: 'Update Notification',
                                subtitle:
                                    'Toggle update notifications on app launch',
                                value: _updateNotifications,
                                onChanged: (value) async {
                                  await SettingsManager.setUpdateNotifications(
                                      value);
                                  setState(() => _updateNotifications = value);
                                },
                                icon: Icons.notifications,
                              ),
                            ],
                          ),

                          //Device Tab
                          ListView(
                            children: [
                              _buildSliderItem(
                                title: 'LED Brightness',
                                subtitle: 'Adjust overall LED brightness',
                                value: _ledBrightness,
                                onChanged: (value) async {
                                  await SettingsManager.setLedBrightness(value);
                                  setState(() => _ledBrightness = value);
                                },
                                min: 0.1,
                                max: 1.0,
                                icon: Icons.lightbulb,
                              ),
                              _buildSettingItem(
                                title: 'App Gradients for LEDs',
                                subtitle:
                                    'Use colour gradients based on app icons',
                                value: _appGradients,
                                onChanged: (value) async {
                                  await SettingsManager.setAppGradients(value);
                                  setState(() => _appGradients = value);
                                },
                                icon: Icons.gradient,
                              ),
                              const SizedBox(height: 16),
                              Container(
                                padding: const EdgeInsets.all(16),
                                margin:
                                    const EdgeInsets.symmetric(horizontal: 16),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).brightness ==
                                          Brightness.dark
                                      ? Color(0xFFEAE1B4).withOpacity(0.1)
                                      : Color(0xFFEAE1B4).withOpacity(0.05),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: Color(0xFFEAE1B4).withOpacity(0.3),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.info_outline,
                                      color: Color(0xFFEAE1B4),
                                      size: 20,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        'LED functionality coming soon, lemme procrastinate it for now 🙏',
                                        style: TextStyle(
                                          fontFamily: 'BitstreamVeraSans',
                                          color: Color.fromARGB(
                                              255, 242, 234, 199),
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),

                          //Advanced Tab
                          ListView(
                            children: [
                              _buildSettingItem(
                                title: 'Save Last COM Port',
                                subtitle: 'Remember last connected serial port',
                                value: _saveLastComPort,
                                onChanged: (value) async {
                                  await SettingsManager.setSaveLastComPort(
                                      value);
                                  setState(() => _saveLastComPort = value);
                                },
                                icon: Icons.usb,
                              ),
                              const SizedBox(height: 8),
                              _buildActionItem(
                                title: _showTerminal
                                    ? 'Hide Terminal Window'
                                    : 'Show Terminal Window',
                                subtitle: 'is it or isn'
                                    't it a software problem? 🤔',
                                onTap: () {
                                  setState(
                                      () => _showTerminal = !_showTerminal);
                                },
                                icon: Icons.terminal,
                                iconColor:
                                    const Color.fromARGB(222, 254, 255, 210),
                              ),
                              if (_showTerminal) ...[
                                const SizedBox(height: 16),
                                TerminalWindow(
                                  rawDataStream: widget.rawDataStream,
                                  sliderDataStream: widget.sliderDataStream,
                                  buttonDataStream: widget.buttonDataStream,
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          //Close button
          Positioned(
            top: MediaQuery.of(context).size.height / 12,
            right: MediaQuery.of(context).size.width * 0.15 - 12,
            child: Transform.rotate(
              angle: 8 * (3.14159 / 180),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => Navigator.pop(context),
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3F1E5).withOpacity(0.9),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: const Color(0xFFF3F1E5).withOpacity(0.5),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.close,
                      color: Color(0xFF333333),
                      size: 30,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

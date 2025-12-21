import 'dart:io';
import 'package:flutter/material.dart';
import 'package:mixlit/frontend/pages/HomePage.dart';
import 'package:mixlit/frontend/Theme.dart';
import 'package:mixlit/frontend/menus/SettingsMenu.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as path;
import 'dart:async';

class StartupConfig {
  static const String _autoStartupEnabledKey = 'auto_startup_enabled';
  static const String _hideOnStartupKey = 'hide_on_startup';

  static Future<bool> get autoStartupEnabled async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_autoStartupEnabledKey) ?? true;
  }

  static Future<void> setAutoStartupEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoStartupEnabledKey, enabled);
    if (enabled) {
      await _enableLauncherStartup();
    } else {
      await launchAtStartup.disable();
    }
  }

  /// Start up launcher app (for starting service first + this app)
  static Future<void> _enableLauncherStartup() async {
    try {
      final appDir = path.dirname(Platform.resolvedExecutable);
      final launcherPath = path.join(appDir, 'MixLit-Launcher.exe');

      if (await File(launcherPath).exists()) {
        launchAtStartup.setup(
          appName: "MixLit",
          appPath: launcherPath,
          args: ['--auto-start'],
        );
        await launchAtStartup.enable();
        print('Configured startup to launch: $launcherPath');
      } else {
        print(
            'Warning: Launcher not found at $launcherPath, using direct launch');
        launchAtStartup.setup(
          appName: "MixLit",
          appPath: Platform.resolvedExecutable,
          args: ['--auto-start'],
        );
        await launchAtStartup.enable();
      }
    } catch (e) {
      print('Error setting up launcher startup: $e');
      launchAtStartup.setup(
        appName: "MixLit",
        appPath: Platform.resolvedExecutable,
        args: ['--auto-start'],
      );
      await launchAtStartup.enable();
    }
  }

  static Future<bool> get hideOnStartup async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_hideOnStartupKey) ?? true;
  }

  static Future<void> setHideOnStartup(bool hide) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_hideOnStartupKey, hide);
  }
}

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  final bool isAutoStarted = args.contains('--auto-start');
  final bool hideOnStartup = await StartupConfig.hideOnStartup;
  final bool autoStartupEnabled = await StartupConfig.autoStartupEnabled;
  final bool minimizeToTray = await SettingsManager.getMinimizeToTray();

  WindowOptions windowOptions = const WindowOptions(
    size: Size(780, 880),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden,
  );

  windowManager.waitUntilReadyToShow(windowOptions, () async {
    if (!isAutoStarted || !hideOnStartup) {
      await windowManager.show();
      await windowManager.focus();
    } else {
      await windowManager.hide();
    }
  });

  windowManager.setPreventClose(minimizeToTray);

  // Setup initial launch configuration (will be overridden by StartupConfig)
  final appDir = path.dirname(Platform.resolvedExecutable);
  final launcherPath = path.join(appDir, 'MixLit-Launcher.exe');

  if (await File(launcherPath).exists()) {
    launchAtStartup.setup(
      appName: "MixLit",
      appPath: launcherPath,
      args: ['--auto-start'],
    );
  } else {
    launchAtStartup.setup(
      appName: "MixLit",
      appPath: Platform.resolvedExecutable,
      args: ['--auto-start'],
    );
  }

  if (autoStartupEnabled) {
    await StartupConfig.setAutoStartupEnabled(true);
  } else {
    await launchAtStartup.disable();
  }

  runApp(MyApp(isAutoStarted: isAutoStarted));
}

class MyApp extends StatefulWidget {
  final bool isAutoStarted;

  const MyApp({super.key, required this.isAutoStarted});

  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WindowListener {
  ThemeMode _themeMode = ThemeMode.system;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _loadThemePreference();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  Future<void> _loadThemePreference() async {
    final isDark = await SettingsManager.getDarkTheme();
    setState(() {
      _themeMode = isDark ? ThemeMode.dark : ThemeMode.light;
    });
  }

  void _updateThemeMode(bool isDark) {
    setState(() {
      _themeMode = isDark ? ThemeMode.dark : ThemeMode.light;
    });
  }

  @override
  void onWindowClose() async {
    final bool minimizeToTray = await SettingsManager.getMinimizeToTray();

    if (minimizeToTray) {
      await windowManager.hide();
    } else {
      trayManager.destroy();
      windowManager.destroy();
    }
  }

  Future<void> updatePreventCloseSetting() async {
    final bool minimizeToTray = await SettingsManager.getMinimizeToTray();
    windowManager.setPreventClose(minimizeToTray);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MixLit',
      themeMode: _themeMode,
      theme: AppTheme.lightTheme(),
      darkTheme: AppTheme.darkTheme(),
      home: HomePage(
        isAutoStarted: widget.isAutoStarted,
        onThemeChanged: _updateThemeMode,
        onSettingsChanged: updatePreventCloseSetting,
      ),
      debugShowCheckedModeBanner: false,
    );
  }
}

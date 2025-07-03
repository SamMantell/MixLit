import 'dart:io';
import 'package:flutter/material.dart';
import 'package:mixlit/frontend/home_page.dart';
import 'package:mixlit/frontend/theme/app_theme.dart';
import 'package:window_manager/window_manager.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
      await launchAtStartup.enable();
    } else {
      await launchAtStartup.disable();
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

  //TODO: Settings page for togglable startup/hide behaviopur
  final bool hideOnStartup = await StartupConfig.hideOnStartup;
  final bool autoStartupEnabled = await StartupConfig.autoStartupEnabled;

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

  windowManager.setPreventClose(true);

  launchAtStartup.setup(
    appName: "MixLit",
    appPath: Platform.resolvedExecutable,
    args: ['--auto-start'],
  );

  if (autoStartupEnabled) {
    await launchAtStartup.enable();
  } else {
    await launchAtStartup.disable();
  }

  runApp(MyApp(isAutoStarted: isAutoStarted));
}

class MyApp extends StatelessWidget {
  final bool isAutoStarted;

  const MyApp({super.key, required this.isAutoStarted});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MixLit',
      themeMode: ThemeMode.system,
      theme: AppTheme.lightTheme(),
      darkTheme: AppTheme.darkTheme(),
      home: HomePage(isAutoStarted: isAutoStarted),
      debugShowCheckedModeBanner: false,
    );
  }
}

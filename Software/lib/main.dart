import 'dart:io';

import 'package:flutter/material.dart';
import 'package:mixlit/frontend/home_page.dart';
import 'package:mixlit/frontend/theme/app_theme.dart';
import 'package:window_manager/window_manager.dart';
import 'package:launch_at_startup/launch_at_startup.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  WindowOptions windowOptions = const WindowOptions(
    size: Size(780, 880),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden,
  );

  //TODO: also add to settings page for hide on startup
  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.hide();
  });

  windowManager.setPreventClose(true);

  launchAtStartup.setup(
    appName: "MixLit",
    appPath: Platform.resolvedExecutable,
  );

  //TODO: add settings page & toggle for this auto startup option
  await launchAtStartup.enable();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MixLit',
      themeMode: ThemeMode.system, // Use system theme by default
      theme: AppTheme.lightTheme(),
      darkTheme: AppTheme.darkTheme(),
      home: const HomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

import 'package:flutter/material.dart';
import 'package:mixlit/frontend/home_page.dart';
import 'package:mixlit/frontend/theme/app_theme.dart';
import 'package:window_manager/window_manager.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  windowManager.setPreventClose(true);
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

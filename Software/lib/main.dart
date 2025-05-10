import 'package:flutter/material.dart';
import 'package:mixlit/frontend/home_page.dart';
import 'package:mixlit/frontend/theme/app_theme.dart';

void main() {
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

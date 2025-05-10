import 'package:flutter/material.dart';

class AppTheme {
  static const String fontFamily = 'BitstreamVeraSans';

  static ThemeData lightTheme() {
    return ThemeData(
      useMaterial3: true,
      fontFamily: fontFamily,
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.blue,
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: const Color(0xFFF5F5F5),
      cardColor: Colors.white,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        titleTextStyle: TextStyle(
          fontFamily: fontFamily,
          color: Color(0xFF333333),
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
        iconTheme: IconThemeData(
          color: Color(0xFF333333),
        ),
      ),
      textTheme: const TextTheme(
        displayLarge: TextStyle(
          fontFamily: fontFamily,
          fontSize: 42,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.2,
        ),
        headlineMedium: TextStyle(
          fontFamily: fontFamily,
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: Color(0xFF333333),
        ),
        bodyLarge: TextStyle(
          fontFamily: fontFamily,
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
        bodyMedium: TextStyle(
          fontFamily: fontFamily,
          fontSize: 14,
        ),
      ),
      sliderTheme: SliderThemeData(
        trackHeight: 4,
        thumbColor: Colors.blue,
        activeTrackColor: Colors.blue,
        inactiveTrackColor: Colors.blue.withOpacity(0.2),
        thumbShape: const RoundSliderThumbShape(
          enabledThumbRadius: 8,
          elevation: 2,
        ),
      ),
    );
  }

  static ThemeData darkTheme() {
    return ThemeData(
      useMaterial3: true,
      fontFamily: fontFamily,
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.blue,
        brightness: Brightness.dark,
      ),
      scaffoldBackgroundColor: const Color(0xFF121212),
      cardColor: const Color(0xFF1E1E1E),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        titleTextStyle: TextStyle(
          fontFamily: fontFamily,
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
        iconTheme: IconThemeData(
          color: Colors.white,
        ),
      ),
      textTheme: const TextTheme(
        displayLarge: TextStyle(
          fontFamily: fontFamily,
          fontSize: 42,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.2,
          color: Colors.white,
        ),
        headlineMedium: TextStyle(
          fontFamily: fontFamily,
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
        bodyLarge: TextStyle(
          fontFamily: fontFamily,
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: Colors.white,
        ),
        bodyMedium: TextStyle(
          fontFamily: fontFamily,
          fontSize: 14,
          color: Colors.white,
        ),
      ),
      sliderTheme: SliderThemeData(
        trackHeight: 4,
        thumbColor: Colors.blue,
        activeTrackColor: Colors.blue,
        inactiveTrackColor: Colors.blue.withOpacity(0.2),
        thumbShape: const RoundSliderThumbShape(
          enabledThumbRadius: 8,
          elevation: 2,
        ),
      ),
    );
  }
}

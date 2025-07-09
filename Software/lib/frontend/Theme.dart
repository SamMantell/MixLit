import 'package:flutter/material.dart';

class AppTheme {
  static const String fontFamily = 'BitstreamVeraSans';

  //
  // COLOUR PALETTE
  //

  //Base
  static const Color primaryColor = Color(0xFFEAE1B4);
  static const Color accentColor = Color(0xFFE4D274);

  //Background
  static const Color lightBackground = Color.fromARGB(255, 227, 225, 215);
  static const Color lightSecondaryBackground = Color(0xFFE8E0C8);
  static const Color darkBackground = Color(0xFF181716);
  static const Color darkSecondaryBackground = Color(0xFF121111);

  //Cards
  static const Color lightCardColor = Color(0xFFFAF5E5);
  static const Color darkCardColor = Color(0xFF1E1D1C);

  //Text
  static const Color lightTextPrimary = Color(0xFF363431);
  static const Color lightTextSecondary = Color(0xFF5A5754);
  static const Color darkTextPrimary = Color(0xFFFFF9F0);
  static const Color darkTextSecondary = Color(0xFFE6DFD4);

  //theme-specific
  static const Color lightPrimaryColor = Color(0xFFEAE1B4);
  static const Color lightSecondaryColor = Color(0xFFB1BBEB);
  static const Color lightAccentColor = Color(0xFFE4D274);

  static const Color darkPrimaryColor = Color(0xFFE9DEA5);
  static const Color darkSecondaryColor = Color(0xFFCED4F3);
  static const Color darkAccentColor = Color(0xFFE9DEA5);

  //based-assigned-apps specific colours
  static const Color defaultAppColor = Color(0xFFE9DEA5);
  static const Color deviceVolumeColor = Color(0xFFE9DEA5);
  static const Color masterVolumeColor = Color(0xFFE9DEA5);
  static const Color activeAppColor = Color(0xFFCED4F3);
  static const Color unassignedColor = Color(0xFF5A5754);
  static const Color missingAppColor = Color(0xFFE4D274);

  //status colours
  static const Color connectedColor = Color.fromARGB(255, 133, 219, 102);
  static const Color disconnectedColor = Color(0xFFF44336);
  static const Color warningColor = Color(0xFFFF9800);
  static const Color errorColor = Color(0xFFF44336);
  static const Color successColor = Color.fromARGB(255, 133, 219, 102);

  //slider-tag-specific colours
  static const Color deviceSliderColor = Color(0xFFB1BBEB);
  static const Color masterSliderColor = Color(0xFF8BC34A);
  static const Color activeSliderColor = Color(0xFFCED4F3);
  static const Color appSliderColor = Color(0xFFE4D274);
  static const Color unassignedSliderColor = Color(0xFF9E9B98);

  //fancy close buttons
  static const Color closeButtonColor = Color(0xFFF2ECD7);
  static const Color closeButtonBorder = Color(0xFFE8E0C8);
  static const Color closeButtonIcon = Color(0xFF363431);

  //
  // borders & scale?
  //

  //border radiuses
  static const double borderRadiusSmall = 8.0;
  static const double borderRadiusMedium = 16.0;
  static const double borderRadiusLarge = 20.0;
  static const double borderRadiusXLarge = 30.0;

  //spacing
  static const double spacingTiny = 2.0;
  static const double spacingXSmall = 4.0;
  static const double spacingSmall = 8.0;
  static const double spacingMedium = 16.0;
  static const double spacingLarge = 20.0;
  static const double spacingXLarge = 24.0;

  //icons
  static const double iconSizeSmall = 18.0;
  static const double iconSizeMedium = 20.0;
  static const double iconSizeLarge = 32.0;
  static const double iconSizeXLarge = 60.0;

  //other components
  static const double dialCardHeight = 120.0;
  static const double buttonHeight = 40.0;
  static const double statusIndicatorHeight = 36.0;

  //
  // shadows & other fx
  //

  static List<BoxShadow> get lightElevationLow => [
        BoxShadow(
          color: Colors.black.withOpacity(0.1),
          blurRadius: 4,
          offset: const Offset(0, 2),
        ),
      ];

  static List<BoxShadow> get lightElevationMedium => [
        BoxShadow(
          color: Colors.black.withOpacity(0.15),
          blurRadius: 8,
          offset: const Offset(0, 4),
        ),
      ];

  static List<BoxShadow> get lightElevationHigh => [
        BoxShadow(
          color: Colors.black.withOpacity(0.2),
          blurRadius: 16,
          offset: const Offset(0, 8),
        ),
      ];

  static List<BoxShadow> get darkElevationLow => [
        BoxShadow(
          color: Colors.black.withOpacity(0.2),
          blurRadius: 4,
          offset: const Offset(0, 2),
        ),
      ];

  static List<BoxShadow> get darkElevationMedium => [
        BoxShadow(
          color: Colors.black.withOpacity(0.3),
          blurRadius: 8,
          offset: const Offset(0, 4),
        ),
      ];

  static List<BoxShadow> get darkElevationHigh => [
        BoxShadow(
          color: Colors.black.withOpacity(0.4),
          blurRadius: 16,
          offset: const Offset(0, 8),
        ),
      ];

  // Dialog Shadows
  static List<BoxShadow> get dialogShadow => [
        BoxShadow(
          color: Colors.black.withOpacity(0.3),
          blurRadius: 20,
          spreadRadius: 5,
        ),
      ];

  //
  // opacity
  //

  static const double opacityDisabled = 0.5;
  static const double opacitySubtle = 0.1;
  static const double opacityMedium = 0.2;
  static const double opacityStrong = 0.3;
  static const double opacityVeryStrong = 0.6;
  static const double opacityAlmostOpaque = 0.8;
  static const double opacityTransparent = 0.9;

  //
  // hlepers
  //

  static Color getBackgroundColor(bool isDarkMode) {
    return isDarkMode ? darkBackground : lightBackground;
  }

  static Color getSecondaryBackgroundColor(bool isDarkMode) {
    return isDarkMode ? darkSecondaryBackground : lightSecondaryBackground;
  }

  static Color getCardColor(bool isDarkMode) {
    return isDarkMode ? darkCardColor : lightCardColor;
  }

  static Color getPrimaryTextColor(bool isDarkMode) {
    return isDarkMode ? darkTextPrimary : lightTextPrimary;
  }

  static Color getSecondaryTextColor(bool isDarkMode) {
    return isDarkMode ? darkTextSecondary : lightTextSecondary;
  }

  static Color getPrimaryColor(bool isDarkMode) {
    return isDarkMode ? darkPrimaryColor : lightPrimaryColor;
  }

  static Color getSecondaryColor(bool isDarkMode) {
    return isDarkMode ? darkSecondaryColor : lightSecondaryColor;
  }

  static Color getAccentColor(bool isDarkMode) {
    return isDarkMode ? darkAccentColor : lightAccentColor;
  }

  static List<BoxShadow> getElevationLow(bool isDarkMode) {
    return isDarkMode ? darkElevationLow : lightElevationLow;
  }

  static List<BoxShadow> getElevationMedium(bool isDarkMode) {
    return isDarkMode ? darkElevationMedium : lightElevationMedium;
  }

  static List<BoxShadow> getElevationHigh(bool isDarkMode) {
    return isDarkMode ? darkElevationHigh : lightElevationHigh;
  }

  static Color getConnectionColor(bool isConnected) {
    return isConnected ? connectedColor : disconnectedColor;
  }

  static Color getSliderColorByTag(String tag, {Color? fallback}) {
    switch (tag) {
      case 'default_device':
        return deviceSliderColor;
      case 'master_volume':
        return masterSliderColor;
      case 'active_app':
        return activeSliderColor;
      case 'app':
        return appSliderColor;
      case 'unassigned':
        return unassignedSliderColor;
      default:
        return fallback ?? unassignedSliderColor;
    }
  }

  static BoxDecoration getButtonDecoration(
    bool isDarkMode, {
    Color? customColor,
    bool isDestructive = false,
  }) {
    Color baseColor = customColor ?? getPrimaryColor(isDarkMode);
    if (isDestructive) baseColor = errorColor;

    return BoxDecoration(
      color: baseColor.withOpacity(opacitySubtle),
      borderRadius: BorderRadius.circular(borderRadiusLarge),
      border: Border.all(
        color: baseColor.withOpacity(opacityMedium),
      ),
      boxShadow: getElevationLow(isDarkMode),
    );
  }

  static BoxDecoration getStatusIndicatorDecoration(
      bool isConnected, bool isDarkMode) {
    return BoxDecoration(
      color: getConnectionColor(isConnected).withOpacity(opacitySubtle),
      borderRadius: BorderRadius.circular(borderRadiusXLarge),
      border: Border.all(
        color: getConnectionColor(isConnected).withOpacity(opacityStrong),
      ),
      boxShadow: getElevationLow(isDarkMode),
    );
  }

  static BoxDecoration getCloseButtonDecoration() {
    return BoxDecoration(
      color: closeButtonColor.withOpacity(opacityTransparent),
      borderRadius: BorderRadius.circular(borderRadiusLarge),
      border: Border.all(
        color: closeButtonBorder.withOpacity(opacityDisabled),
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(opacityMedium),
          blurRadius: 4,
          offset: const Offset(0, 2),
        ),
      ],
    );
  }

  //
  // main theming
  //

  static ThemeData lightTheme() {
    return ThemeData(
      useMaterial3: true,
      fontFamily: fontFamily,
      colorScheme: ColorScheme.fromSeed(
        seedColor: lightPrimaryColor,
        brightness: Brightness.light,
        primary: lightPrimaryColor,
        secondary: lightSecondaryColor,
        surface: lightCardColor,
        background: lightBackground,
        onPrimary: lightTextPrimary,
        onSecondary: lightTextPrimary,
        onSurface: lightTextPrimary,
        onBackground: lightTextPrimary,
      ),
      scaffoldBackgroundColor: lightBackground,
      cardColor: lightCardColor,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        titleTextStyle: TextStyle(
          fontFamily: fontFamily,
          color: lightTextPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
        iconTheme: IconThemeData(
          color: lightTextPrimary,
        ),
      ),
      textTheme: TextTheme(
        displayLarge: TextStyle(
          fontFamily: fontFamily,
          fontSize: 42,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.2,
          color: lightTextPrimary,
        ),
        headlineMedium: TextStyle(
          fontFamily: fontFamily,
          fontSize: 22,
          fontWeight: FontWeight.w100,
          letterSpacing: 1,
          color: lightTextSecondary,
        ),
        bodyLarge: TextStyle(
          fontFamily: fontFamily,
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: lightTextPrimary,
        ),
        bodyMedium: TextStyle(
          fontFamily: fontFamily,
          fontSize: 14,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.3,
          color: lightTextPrimary,
        ),
        bodySmall: TextStyle(
          fontFamily: fontFamily,
          fontSize: 13,
          color: lightTextSecondary,
        ),
      ),
      sliderTheme: SliderThemeData(
        trackHeight: 4,
        thumbColor: lightPrimaryColor,
        activeTrackColor: lightPrimaryColor,
        inactiveTrackColor: lightPrimaryColor.withOpacity(opacityMedium),
        thumbShape: const RoundSliderThumbShape(
          enabledThumbRadius: 8,
          elevation: 2,
        ),
      ),
      tabBarTheme: const TabBarTheme(
        labelStyle: TextStyle(
          fontFamily: fontFamily,
        ),
        unselectedLabelStyle: TextStyle(
          fontFamily: fontFamily,
        ),
      ),
    );
  }

  static ThemeData darkTheme() {
    return ThemeData(
      useMaterial3: true,
      fontFamily: fontFamily,
      colorScheme: ColorScheme.fromSeed(
        seedColor: darkPrimaryColor,
        brightness: Brightness.dark,
        primary: darkPrimaryColor,
        secondary: darkSecondaryColor,
        surface: darkCardColor,
        background: darkBackground,
        onPrimary: darkTextPrimary,
        onSecondary: darkTextPrimary,
        onSurface: darkTextPrimary,
        onBackground: darkTextPrimary,
      ),
      scaffoldBackgroundColor: darkBackground,
      cardColor: darkCardColor,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        titleTextStyle: TextStyle(
          fontFamily: fontFamily,
          color: darkTextPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
        iconTheme: IconThemeData(
          color: darkTextPrimary,
        ),
      ),
      textTheme: TextTheme(
        displayLarge: TextStyle(
          fontFamily: fontFamily,
          fontSize: 42,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.2,
          color: darkTextPrimary,
        ),
        headlineMedium: TextStyle(
          fontFamily: fontFamily,
          fontSize: 22,
          fontWeight: FontWeight.w100,
          letterSpacing: 1,
          color: darkTextPrimary,
        ),
        bodyLarge: TextStyle(
          fontFamily: fontFamily,
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: darkTextPrimary,
        ),
        bodyMedium: TextStyle(
          fontFamily: fontFamily,
          fontSize: 14,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.3,
          color: darkTextPrimary,
        ),
        bodySmall: TextStyle(
          fontFamily: fontFamily,
          fontSize: 13,
          color: darkTextSecondary,
        ),
      ),
      sliderTheme: SliderThemeData(
        trackHeight: 4,
        thumbColor: darkPrimaryColor,
        activeTrackColor: darkPrimaryColor,
        inactiveTrackColor: darkPrimaryColor.withOpacity(opacityMedium),
        thumbShape: const RoundSliderThumbShape(
          enabledThumbRadius: 8,
          elevation: 2,
        ),
      ),
      tabBarTheme: const TabBarTheme(
        labelStyle: TextStyle(
          fontFamily: fontFamily,
        ),
        unselectedLabelStyle: TextStyle(
          fontFamily: fontFamily,
        ),
      ),
    );
  }
}

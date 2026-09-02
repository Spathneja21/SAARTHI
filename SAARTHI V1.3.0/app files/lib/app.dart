import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'features/splash/splash_screen.dart';

final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.light);

class SaarthiApp extends StatelessWidget {
  const SaarthiApp({super.key});

  @override
  Widget build(BuildContext context) {
    // --- SHAPE ---
    const cardRadius = 18.0;
    const controlRadius = 14.0;
    const buttonRadius = 14.0;

    // --- COLOR PALETTE ---
    // Primary Branding: Oceanic Blue (used to be secondary)
    const primaryLight = Color(0xFF007AFF);
    const primaryDark = Color(0xFF0A84FF);
    
    // Backgrounds: Frost White (Light) & Pure Black (Dark)
    const bgLight = Color(0xFFF2F2F7);
    const bgDark = Color(0xFF000000);
    
    // Surfaces/Cards: Pure White (Light) & Elevated Gray (Dark)
    const surfaceLight = Color(0xFFFFFFFF);
    const surfaceDark = Color(0xFF1C1C1E);
    
    // Text: Dark Gray (Light) & Pure White (Dark)
    const textLight = Color(0xFF1C1C1E);
    const textDark = Color(0xFFFFFFFF);
    const textMutedLight = Color(0xFF8E8E93);
    const textMutedDark = Color(0xFF98989D);

    // --- TYPOGRAPHY ---
    final baseTextThemeLight = GoogleFonts.interTextTheme(ThemeData.light().textTheme);
    final baseTextThemeDark = GoogleFonts.interTextTheme(ThemeData.dark().textTheme);

    final customTextThemeLight = baseTextThemeLight.copyWith(
      displaySmall: baseTextThemeLight.displaySmall?.copyWith(fontWeight: FontWeight.w700, color: textLight),
      headlineMedium: baseTextThemeLight.headlineMedium?.copyWith(fontWeight: FontWeight.w700, color: textLight),
      titleLarge: baseTextThemeLight.titleLarge?.copyWith(fontWeight: FontWeight.w600, color: textLight),
      titleMedium: baseTextThemeLight.titleMedium?.copyWith(fontWeight: FontWeight.w600, color: textLight),
      bodyLarge: baseTextThemeLight.bodyLarge?.copyWith(color: textLight),
      bodyMedium: baseTextThemeLight.bodyMedium?.copyWith(color: textLight),
      labelSmall: baseTextThemeLight.labelSmall?.copyWith(fontWeight: FontWeight.w600, color: textMutedLight),
    );

    final customTextThemeDark = baseTextThemeDark.copyWith(
      displaySmall: baseTextThemeDark.displaySmall?.copyWith(fontWeight: FontWeight.w700, color: textDark),
      headlineMedium: baseTextThemeDark.headlineMedium?.copyWith(fontWeight: FontWeight.w700, color: textDark),
      titleLarge: baseTextThemeDark.titleLarge?.copyWith(fontWeight: FontWeight.w600, color: textDark),
      titleMedium: baseTextThemeDark.titleMedium?.copyWith(fontWeight: FontWeight.w600, color: textDark),
      bodyLarge: baseTextThemeDark.bodyLarge?.copyWith(color: textDark),
      bodyMedium: baseTextThemeDark.bodyMedium?.copyWith(color: textDark),
      labelSmall: baseTextThemeDark.labelSmall?.copyWith(fontWeight: FontWeight.w600, color: textMutedDark),
    );

    // --- LIGHT THEME ---
    final lightTheme = ThemeData(
      brightness: Brightness.light,
      scaffoldBackgroundColor: bgLight,
      dividerColor: Colors.black.withValues(alpha: 0.06),
      colorScheme: const ColorScheme.light(
        primary: primaryLight,
        secondary: Color(0xFF007AFF), // Oceanic Blue
        surface: surfaceLight,
        error: Color(0xFFFF3B30),
        onPrimary: Colors.white,
        onSurface: textLight,
      ),
      textTheme: customTextThemeLight,
      appBarTheme: const AppBarTheme(
        backgroundColor: bgLight,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: IconThemeData(color: primaryLight),
        titleTextStyle: TextStyle(
          fontFamily: 'Inter',
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: textLight,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceLight,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.05)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: primaryLight, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        hintStyle: const TextStyle(color: textMutedLight),
      ),
      cardTheme: CardThemeData(
        color: surfaceLight,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cardRadius),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surfaceLight,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cardRadius),
        ),
        titleTextStyle: customTextThemeLight.titleLarge,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryLight,
          foregroundColor: Colors.white,
          disabledBackgroundColor: textMutedLight.withValues(alpha: 0.25),
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(buttonRadius),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primaryLight,
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: primaryLight),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: primaryLight,
        inactiveTrackColor: primaryLight.withValues(alpha: 0.15),
        thumbColor: primaryLight,
        overlayColor: primaryLight.withValues(alpha: 0.12),
        valueIndicatorColor: primaryLight,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: bgLight,
        selectedColor: primaryLight,
        disabledColor: textMutedLight.withValues(alpha: 0.15),
        labelStyle: const TextStyle(fontWeight: FontWeight.w600, color: textLight),
        secondaryLabelStyle: const TextStyle(fontWeight: FontWeight.w600, color: Colors.white),
        side: BorderSide(color: Colors.black.withValues(alpha: 0.06)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(controlRadius),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: primaryLight,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(controlRadius),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: textLight,
        contentTextStyle: const TextStyle(color: Colors.white),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(controlRadius),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: surfaceLight,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(controlRadius),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: Colors.black.withValues(alpha: 0.06),
        thickness: 1,
        space: 1,
      ),
    );

    // --- DARK THEME ---
    final darkTheme = ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bgDark,
      dividerColor: Colors.white.withValues(alpha: 0.08),
      colorScheme: const ColorScheme.dark(
        primary: primaryDark,
        secondary: Color(0xFF0A84FF), // Oceanic Blue
        surface: surfaceDark,
        error: Color(0xFFFF453A),
        onPrimary: Colors.white,
        onSurface: textDark,
      ),
      textTheme: customTextThemeDark,
      appBarTheme: const AppBarTheme(
        backgroundColor: bgDark,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: IconThemeData(color: primaryDark),
        titleTextStyle: TextStyle(
          fontFamily: 'Inter',
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: textDark,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceDark,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: primaryDark, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        hintStyle: const TextStyle(color: textMutedDark),
      ),
      cardTheme: CardThemeData(
        color: surfaceDark,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cardRadius),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surfaceDark,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cardRadius),
        ),
        titleTextStyle: customTextThemeDark.titleLarge,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryDark,
          foregroundColor: Colors.white,
          disabledBackgroundColor: textMutedDark.withValues(alpha: 0.25),
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(buttonRadius),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primaryDark,
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: primaryDark),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: primaryDark,
        inactiveTrackColor: primaryDark.withValues(alpha: 0.2),
        thumbColor: primaryDark,
        overlayColor: primaryDark.withValues(alpha: 0.12),
        valueIndicatorColor: primaryDark,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surfaceDark,
        selectedColor: primaryDark,
        disabledColor: textMutedDark.withValues(alpha: 0.15),
        labelStyle: const TextStyle(fontWeight: FontWeight.w600, color: textDark),
        secondaryLabelStyle: const TextStyle(fontWeight: FontWeight.w600, color: Colors.white),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(controlRadius),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: primaryDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(controlRadius),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surfaceDark,
        contentTextStyle: const TextStyle(color: textDark),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(controlRadius),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: surfaceDark,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(controlRadius),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: Colors.white.withValues(alpha: 0.08),
        thickness: 1,
        space: 1,
      ),
    );

    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (context, ThemeMode currentMode, child) {
        return MaterialApp(
          title: 'Saarthi',
          debugShowCheckedModeBanner: false,
          themeMode: currentMode,
          theme: lightTheme,
          darkTheme: darkTheme,
          home: const SplashScreen(),
        );
      },
    );
  }
}


import 'package:flutter/material.dart';

abstract final class AppColors {
  static const background = Color(0xFF0E0F13);
  static const surface = Color(0xFF171920);
  static const surfaceRaised = Color(0xFF20232C);
  static const outline = Color(0xFF2C303B);
  static const textPrimary = Color(0xFFECEDF2);
  static const textMuted = Color(0xFF9BA1B0);
  static const error = Color(0xFFFF8A80);

  // One accent per metric family, so a colour means the same thing on every
  // screen. Each one clears WCAG AA (4.5:1) on background and surface.
  static const sleep = Color(0xFFA78BFA);
  static const heart = Color(0xFFFF7A6B);
  static const activity = Color(0xFF4ADE80);
  static const oxygen = Color(0xFF22D3EE);
  static const stress = Color(0xFFFBBF24);

  static const List<Color> metricAccents = [
    sleep,
    heart,
    activity,
    oxygen,
    stress,
  ];
}

abstract final class AppTheme {
  static ThemeData get dark {
    const scheme = ColorScheme.dark(
      primary: AppColors.textPrimary,
      onPrimary: AppColors.background,
      secondary: AppColors.textMuted,
      onSecondary: AppColors.background,
      surface: AppColors.surface,
      onSurface: AppColors.textPrimary,
      onSurfaceVariant: AppColors.textMuted,
      surfaceContainerHighest: AppColors.surfaceRaised,
      outline: AppColors.outline,
      error: AppColors.error,
      onError: AppColors.background,
    );
    return ThemeData(
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.background,
      dividerColor: AppColors.outline,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: AppColors.surface,
        indicatorColor: AppColors.surfaceRaised,
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }
}

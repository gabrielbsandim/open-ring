import 'package:flutter/material.dart';
import 'package:open_ring/app/theme/app_colors.dart';

abstract final class AppTheme {
  static ThemeData dark() => _build(AppColors.dark, Brightness.dark);

  static ThemeData light() => _build(AppColors.light, Brightness.light);

  static ColorScheme colorScheme(AppColors colors, Brightness brightness) =>
      ColorScheme(
        brightness: brightness,
        primary: colors.textPrimary,
        onPrimary: colors.onAccent,
        primaryContainer: colors.surfaceInner,
        onPrimaryContainer: colors.textPrimary,
        secondary: colors.textLabel,
        onSecondary: colors.onAccent,
        secondaryContainer: colors.surfaceInner,
        onSecondaryContainer: colors.textPrimary,
        tertiary: colors.sleep,
        onTertiary: colors.onAccent,
        error: colors.heart,
        onError: colors.onAccent,
        surface: colors.surface,
        onSurface: colors.textPrimary,
        onSurfaceVariant: colors.textLabel,
        surfaceDim: colors.background,
        surfaceBright: colors.surface,
        surfaceContainerLowest: colors.background,
        surfaceContainerLow: colors.surface,
        surfaceContainer: colors.surface,
        surfaceContainerHigh: colors.surfaceInner,
        surfaceContainerHighest: colors.surfaceInner,
        outline: colors.strongBorder,
        outlineVariant: colors.surfaceBorder,
        inverseSurface: colors.textPrimary,
        onInverseSurface: colors.background,
        inversePrimary: colors.surface,
        surfaceTint: Colors.transparent,
      );

  static ThemeData _build(AppColors colors, Brightness brightness) {
    final scheme = colorScheme(colors, brightness);
    return ThemeData(
      colorScheme: scheme,
      scaffoldBackgroundColor: colors.background,
      canvasColor: colors.background,
      dividerColor: colors.surfaceBorder,
      dividerTheme: DividerThemeData(color: colors.surfaceBorder),
      appBarTheme: AppBarTheme(
        backgroundColor: colors.background,
        foregroundColor: colors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: colors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: colors.surfaceBorder),
        ),
      ),
      extensions: [colors],
    );
  }
}

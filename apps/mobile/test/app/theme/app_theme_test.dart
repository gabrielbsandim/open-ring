import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/app/theme/app_theme.dart';

void main() {
  final themes = {
    Brightness.dark: (AppTheme.dark(), AppColors.dark),
    Brightness.light: (AppTheme.light(), AppColors.light),
  };

  for (final MapEntry(key: brightness, value: (theme, colors))
      in themes.entries) {
    group('${brightness.name} theme', () {
      test('has the matching brightness', () {
        expect(theme.brightness, brightness);
        expect(theme.colorScheme.brightness, brightness);
      });

      test('carries the token extension of its mode', () {
        expect(theme.extension<AppColors>(), same(colors));
      });

      test('maps the colour scheme onto the tokens', () {
        final scheme = theme.colorScheme;
        expect(theme.scaffoldBackgroundColor, colors.background);
        expect(scheme.surface, colors.surface);
        expect(scheme.onSurface, colors.textPrimary);
        expect(scheme.onSurfaceVariant, colors.textLabel);
        expect(scheme.outlineVariant, colors.surfaceBorder);
        expect(scheme.outline, colors.strongBorder);
        expect(scheme.error, colors.heart);
        expect(scheme.onPrimary, colors.onAccent);
      });
    });
  }
}

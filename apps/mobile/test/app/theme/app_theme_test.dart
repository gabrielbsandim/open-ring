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

      test(
        'uses a rounded floating SnackBar theme with violet action text',
        () {
          final snack = theme.snackBarTheme;
          final expectedBg = brightness == Brightness.dark
              ? colors.surfaceInner
              : colors.textPrimary;
          expect(snack.behavior, SnackBarBehavior.floating);
          expect(snack.dismissDirection, DismissDirection.horizontal);
          expect(snack.backgroundColor, expectedBg);
          expect(snack.actionTextColor, AppColors.dark.sleep);
          expect(snack.shape, isA<RoundedRectangleBorder>());
          final shape = snack.shape! as RoundedRectangleBorder;
          expect(shape.borderRadius, BorderRadius.circular(14));
        },
      );
    });
  }
}

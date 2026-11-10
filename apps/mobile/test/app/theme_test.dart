import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/app/theme/app_theme.dart';

double contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final light = la > lb ? la : lb;
  final dark = la > lb ? lb : la;
  return (light + 0.05) / (dark + 0.05);
}

void main() {
  const grounds = [AppColors.background, AppColors.surface];

  test('every metric accent clears 4.5:1 on background and surface', () {
    for (final accent in AppColors.metricAccents) {
      for (final ground in grounds) {
        expect(contrast(accent, ground), greaterThanOrEqualTo(4.5));
      }
    }
  });

  test('body and muted text clear 4.5:1 on background and surface', () {
    for (final text in [AppColors.textPrimary, AppColors.textMuted]) {
      for (final ground in grounds) {
        expect(contrast(text, ground), greaterThanOrEqualTo(4.5));
      }
    }
  });

  test('metric accents are distinct', () {
    expect(AppColors.metricAccents.toSet().length, 5);
  });

  test('the theme is dark and uses the token background', () {
    final theme = AppTheme.dark;
    expect(theme.brightness, Brightness.dark);
    expect(theme.scaffoldBackgroundColor, AppColors.background);
    expect(theme.colorScheme.surface, AppColors.surface);
  });
}

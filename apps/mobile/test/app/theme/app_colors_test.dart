import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/app/theme/app_colors.dart';

double contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final light = la > lb ? la : lb;
  final dark = la > lb ? lb : la;
  return (light + 0.05) / (dark + 0.05);
}

Map<String, Color> accents(AppColors c) => {
  'sleep': c.sleep,
  'heart': c.heart,
  'activity': c.activity,
  'oxygen': c.oxygen,
  'stress': c.stress,
};

Map<String, Color> textTokens(AppColors c) => {
  'textPrimary': c.textPrimary,
  'textSecondary': c.textSecondary,
  'textLabel': c.textLabel,
};

const modes = <String, AppColors>{
  'dark': AppColors.dark,
  'light': AppColors.light,
};

void main() {
  for (final MapEntry(key: mode, value: colors) in modes.entries) {
    group('$mode mode', () {
      final grounds = {
        'background': colors.background,
        'surface': colors.surface,
      };

      test('every accent and text token clears 4.5:1 on background and '
          'surface', () {
        final tokens = {...accents(colors), ...textTokens(colors)};
        for (final MapEntry(key: name, value: token) in tokens.entries) {
          for (final MapEntry(key: groundName, value: ground)
              in grounds.entries) {
            expect(
              contrast(token, ground),
              greaterThanOrEqualTo(4.5),
              reason: '$name on $groundName',
            );
          }
        }
      });

      test('onAccent clears 4.5:1 on every accent fill', () {
        for (final MapEntry(key: name, value: accent) in accents(
          colors,
        ).entries) {
          expect(
            contrast(colors.onAccent, accent),
            greaterThanOrEqualTo(4.5),
            reason: 'onAccent on $name',
          );
        }
      });

      test('metric accents are distinct', () {
        expect(accents(colors).values.toSet(), hasLength(5));
      });

      test('sleep stages step down in lightness from awake to deep', () {
        final stages = [
          colors.sleepAwake,
          colors.sleepRem,
          colors.sleepLight,
          colors.sleepDeep,
        ].map((color) => color.computeLuminance()).toList();
        for (var i = 1; i < stages.length; i++) {
          expect(stages[i], lessThan(stages[i - 1]));
        }
      });
    });
  }

  test('copyWith replaces only the given token', () {
    final copy = AppColors.dark.copyWith(heart: AppColors.light.heart);
    expect(copy.heart, AppColors.light.heart);
    expect(copy.sleep, AppColors.dark.sleep);
    expect(copy.background, AppColors.dark.background);
  });

  test('lerp lands on each end and blends between', () {
    expect(
      AppColors.dark.lerp(AppColors.light, 0).background,
      AppColors.dark.background,
    );
    expect(
      AppColors.dark.lerp(AppColors.light, 1).sleepDeep,
      AppColors.light.sleepDeep,
    );
    expect(AppColors.dark.lerp(null, 0.5), same(AppColors.dark));
  });
}

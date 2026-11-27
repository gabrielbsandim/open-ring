import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _locales = [
  'en',
  'de',
  'es',
  'fr',
  'id',
  'it',
  'ja',
  'pt',
  'pt_PT',
  'ru',
  'zh',
];

const _expectedEnglish = <String, String>{
  'foodMealTimeHint': 'Tap to change the time',
  'foodMealTimeFailed': 'Could not update the time',
  'foodMealTagsTitle': 'Tags',
  'foodMealTagsHint': 'Optional. Tap once to mark, again to clear.',
  'foodMealKcalTile': 'Calories of this meal?',
  'foodMealKcalTileHint': 'Why the app does not show them.',
  'foodMealKcalTitle': 'Why this meal has no calories',
  'foodMealKcalBody':
      'A photo does not show cooking oil, sauce, sugar in a drink, or what '
      'was left on the plate. Photo estimates miss by a wide margin and '
      'mostly run low.',
  'foodMealKcalNoCount':
      'A calorie number per plate turns a meal into something to shrink. '
      'OpenRing refuses to build that.',
  'foodMealKcalInstead':
      'Instead, Food tracks your eating window, your tags, and how your meals '
      'line up with your sleep and recovery over time.',
  'foodMealClose': 'Close',
  'foodMealDeleteTile': 'Delete this meal',
  'foodMealDeleteTileHint': 'The photo and tags are removed from this phone.',
  'foodMealDeleteTitle': 'Delete this meal?',
  'foodMealDeleteBody':
      'Its photo, time and tags are removed from this phone. If it closed the '
      'day, the day no longer has its last meal marked.',
  'foodMealDeleteCancel': 'Cancel',
  'foodMealDeleteConfirm': 'Delete',
  'foodMealDeleteFailed': 'Could not delete the meal',
  'foodMealNotFound': 'Meal not found',
  'foodMealFoot':
      'No tag is good or bad, and nothing from this meal enters a score.',
};

final _dashes = RegExp(
  '[${String.fromCharCode(0x2013)}${String.fromCharCode(0x2014)}]',
);

final _placeholder = RegExp(r'\{(\w+)\}');

Map<String, dynamic> _arb(String locale) =>
    jsonDecode(File('lib/l10n/app_$locale.arb').readAsStringSync())
        as Map<String, dynamic>;

List<String> _missing(Map<String, dynamic> arb) => [
  for (final key in _expectedEnglish.keys)
    if (arb[key] is! String || (arb[key] as String).trim().isEmpty) key,
];

void main() {
  group('F8 meal screen ARB keys across all 11 locales', () {
    test('spec lists 20 distinct plain keys', () {
      expect(_expectedEnglish.keys.toSet(), hasLength(20));
    });

    for (final locale in _locales) {
      test('$locale holds all 20 meal keys, each non-empty', () {
        expect(_missing(_arb(locale)), isEmpty);
      });

      test('$locale has no en dash or em dash in the 20 meal keys', () {
        final arb = _arb(locale);
        expect(_missing(arb), isEmpty);
        final offenders = [
          for (final key in _expectedEnglish.keys)
            if ((arb[key] as String).contains(_dashes)) key,
        ];
        expect(offenders, isEmpty);
      });

      test('$locale has zero placeholders on the 20 plain meal keys', () {
        final arb = _arb(locale);
        expect(_missing(arb), isEmpty);
        for (final key in _expectedEnglish.keys) {
          expect(
            _placeholder.allMatches(arb[key] as String),
            isEmpty,
            reason: '$locale $key',
          );
        }
      });
    }

    test('English strings match spec', () {
      final en = _arb('en');
      expect(_missing(en), isEmpty);
      for (final entry in _expectedEnglish.entries) {
        expect(en[entry.key], entry.value, reason: entry.key);
      }
    });
  });
}

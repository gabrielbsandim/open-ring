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

const _plainKeys = [
  'foodTabDay',
  'foodTabWeek',
  'foodWeekLast',
  'foodWeekCompleteLegend',
  'foodWeekIncompleteLegend',
  'foodWeekEmpty',
  'foodWeekSoftTitle',
  'foodWeekSoftBody',
  'foodPlateTitle',
  'foodPlateTag',
  'foodPlateNote',
];

const _placeholderTypes = <String, Map<String, String>>{
  'foodWeekSummary': {'complete': 'int', 'records': 'int'},
  'foodWeekThumbLabel': {'day': 'String', 'slot': 'String', 'time': 'String'},
  'foodPlateSummary': {'score': 'String', 'mains': 'int', 'days': 'int'},
  'foodPlateCounts': {
    'protein': 'int',
    'veg': 'int',
    'processed': 'int',
    'sugaryDays': 'int',
    'drinks': 'String',
  },
  'foodPlateDrinks': {'count': 'String'},
  'foodPlateBuilding': {
    'neededDays': 'int',
    'neededMains': 'int',
    'completeDays': 'int',
    'mains': 'int',
  },
};

const _pluralKey = 'foodWeekSummary';

final List<String> _allKeys = [..._plainKeys, ..._placeholderTypes.keys];

const _expectedEnglish = <String, String>{
  'foodTabDay': 'Day',
  'foodTabWeek': 'Week',
  'foodWeekLast': 'Last week',
  'foodWeekCompleteLegend': 'complete day',
  'foodWeekIncompleteLegend': 'last meal not marked',
  'foodWeekEmpty': 'No meals logged last week.',
  'foodWeekSoftTitle': 'Soft mode',
  'foodWeekSoftBody':
      'With Goals soft mode on, Food shows only your diary, timing, and '
      'comparisons. Plate pattern stays off.',
  'foodPlateTitle': 'Plate pattern',
  'foodPlateTag': 'week',
  'foodPlateNote':
      'Counts what you tagged. It does not know portions and is not a health '
      'score.',
  'foodWeekSummary':
      '{complete} of 7 complete days \u00b7 '
      '{records, plural, =1{1 record} other{{records} records}}',
  'foodWeekThumbLabel': '{day}, {slot} at {time}',
  'foodPlateSummary': '{score} of 10, from {mains} main meals in {days} days',
  'foodPlateCounts':
      'Protein in {protein} \u00b7 veg or fruit in {veg} \u00b7 mostly '
      'processed in {processed} \u00b7 sugary drink on {sugaryDays} days '
      '\u00b7 {drinks}',
  'foodPlateDrinks': '{count} drinks',
  'foodPlateBuilding':
      'Needs {neededDays} complete days and {neededMains} main meals. '
      '{completeDays} of {neededDays} days and {mains} of {neededMains} main '
      'meals so far.',
};

final _dashes = RegExp(
  '[${String.fromCharCode(0x2013)}${String.fromCharCode(0x2014)}]',
);

final _placeholder = RegExp(r'\{(\w+)\}');
final _pluralBranch = RegExp(r'(?:=\d+|zero|one|two|few|many|other)\s*\{');
final _pluralPlaceholder = RegExp(r'\{(\w+)(?:\s*,|\})');

Map<String, dynamic> _arb(String locale) =>
    jsonDecode(File('lib/l10n/app_$locale.arb').readAsStringSync())
        as Map<String, dynamic>;

List<String> _missing(Map<String, dynamic> arb) => [
  for (final key in _allKeys)
    if (arb[key] is! String || (arb[key] as String).trim().isEmpty) key,
];

Set<String> _pluralPlaceholders(String icu) {
  final stripped = icu.replaceAll(_pluralBranch, ' ');
  return {
    for (final match in _pluralPlaceholder.allMatches(stripped))
      match.group(1)!,
  };
}

void main() {
  group('F9a food week ARB keys across all 11 locales', () {
    for (final locale in _locales) {
      test('$locale holds all 17 food week keys, each non-empty', () {
        expect(_allKeys.toSet(), hasLength(17));
        expect(_missing(_arb(locale)), isEmpty);
      });

      test('$locale has no en dash or em dash in the 17 food week keys', () {
        final arb = _arb(locale);
        expect(_missing(arb), isEmpty);
        final offenders = [
          for (final key in _allKeys)
            if ((arb[key] as String).contains(_dashes)) key,
        ];
        expect(offenders, isEmpty);
      });

      test('$locale preserves exact placeholder sets on the 6 parameterized '
          'keys and zero placeholders on the 11 plain keys', () {
        final arb = _arb(locale);
        expect(_missing(arb), isEmpty);

        for (final key in _plainKeys) {
          expect(
            _placeholder.allMatches(arb[key] as String),
            isEmpty,
            reason: '$locale $key',
          );
        }

        for (final entry in _placeholderTypes.entries) {
          final key = entry.key;
          final expected = entry.value.keys.toSet();
          final value = arb[key] as String;
          if (key == _pluralKey) {
            expect(
              value,
              contains('{records, plural,'),
              reason: '$locale $key',
            );
            expect(
              _pluralPlaceholders(value),
              expected,
              reason: '$locale $key',
            );
            continue;
          }
          final actual = {
            for (final m in _placeholder.allMatches(value)) m.group(1)!,
          };
          expect(actual, expected, reason: '$locale $key');
        }
      });
    }

    test('English strings and typed placeholder metadata match spec', () {
      expect(_allKeys.toSet(), hasLength(17));
      expect(_plainKeys, hasLength(11));
      expect(_placeholderTypes, hasLength(6));

      final en = _arb('en');
      expect(_missing(en), isEmpty);
      for (final entry in _expectedEnglish.entries) {
        expect(en[entry.key], entry.value, reason: entry.key);
      }

      for (final entry in _placeholderTypes.entries) {
        final meta = en['@${entry.key}'] as Map<String, dynamic>?;
        final placeholders = meta?['placeholders'] as Map<String, dynamic>?;
        expect(
          placeholders?.keys.toSet(),
          entry.value.keys.toSet(),
          reason: entry.key,
        );
        for (final typeEntry in entry.value.entries) {
          final def = placeholders?[typeEntry.key] as Map<String, dynamic>?;
          expect(
            def?['type'],
            typeEntry.value,
            reason: '${entry.key}.${typeEntry.key}',
          );
        }
      }
    });
  });
}

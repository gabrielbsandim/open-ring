import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

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
  'foodPlateOfTen',
  'foodPlateCompProtein',
  'foodPlateCompVeg',
  'foodPlateCompProcessed',
  'foodPlateCompSugar',
  'foodPlateDisclaimer',
  'foodPlateWeeksTitle',
  'foodPlateRuleTitle',
  'foodPlateRuleNote',
  'foodPlateOurs1',
  'foodPlateOurs2',
];

const _placeholderTypes = <String, Map<String, String>>{
  'foodPlateLead': {'range': 'String'},
  'foodPlateMainsInDays': {'mains': 'int', 'days': 'int'},
  'foodPlateCountOf': {'count': 'int', 'total': 'int'},
  'foodPlateDaysOf': {'days': 'int', 'total': 'int'},
  'foodPlatePointsOf': {'points': 'String', 'max': 'String'},
  'foodPlateWeekShort': {'days': 'int', 'mains': 'int'},
  'foodPlateWeeksNote': {'days': 'int', 'mains': 'int'},
  'foodPlateRulePattern': {
    'mains': 'int',
    'p': 'String',
    'v': 'String',
    'w': 'String',
    's': 'String',
    'a': 'String',
    'sum': 'String',
  },
  'foodPlateRuleGeneral': {
    'p0': 'String',
    'p1': 'String',
    'v0': 'String',
    'v1': 'String',
    'w0': 'String',
    'w1': 'String',
    's0': 'String',
    's1': 'String',
    'a0': 'String',
    'a1': 'String',
    'd1': 'String',
    'd2': 'String',
  },
};

final List<String> _allKeys = [..._plainKeys, ..._placeholderTypes.keys];

final _dashes = RegExp(
  '[${String.fromCharCode(0x2013)}${String.fromCharCode(0x2014)}]',
);

final _placeholder = RegExp(r'\{(\w+)\}');

Map<String, dynamic> _arb(String locale) =>
    jsonDecode(File('lib/l10n/app_$locale.arb').readAsStringSync())
        as Map<String, dynamic>;

List<String> _missing(Map<String, dynamic> arb) => [
  for (final key in _allKeys)
    if (arb[key] is! String || (arb[key] as String).trim().isEmpty) key,
];

Locale _toLocale(String code) {
  final parts = code.split('_');
  return parts.length == 2 ? Locale(parts[0], parts[1]) : Locale(parts[0]);
}

void main() {
  group('F10a food plate ARB keys across all 11 locales', () {
    for (final locale in _locales) {
      test('$locale holds all 20 F10a keys, non-empty, no em/en dashes', () {
        expect(_allKeys.toSet(), hasLength(20));
        final arb = _arb(locale);
        expect(_missing(arb), isEmpty);
        final offenders = [
          for (final key in _allKeys)
            if ((arb[key] as String).contains(_dashes)) key,
        ];
        expect(offenders, isEmpty);
      });

      test('$locale preserves exact placeholders and renders copy', () {
        final arb = _arb(locale);
        for (final key in _plainKeys) {
          expect(
            _placeholder.allMatches(arb[key] as String),
            isEmpty,
            reason: '$locale $key',
          );
        }
        for (final entry in _placeholderTypes.entries) {
          final actual = {
            for (final m in _placeholder.allMatches(arb[entry.key] as String))
              m.group(1)!,
          };
          expect(
            actual,
            entry.value.keys.toSet(),
            reason: '$locale ${entry.key}',
          );
        }

        final l10n = lookupAppLocalizations(_toLocale(locale));
        expect(
          l10n.foodPlateLead('Nov 9 to Nov 15'),
          contains('Nov 9 to Nov 15'),
        );
        expect(
          l10n.foodPlateWeekShort(4, 9),
          allOf(contains('4'), contains('9')),
        );
      });
    }

    test('English ARB metadata defines expected placeholder types', () {
      expect(_allKeys.toSet(), hasLength(20));
      expect(_plainKeys, hasLength(11));
      expect(_placeholderTypes, hasLength(9));

      final en = _arb('en');
      expect(en['foodPlateOfTen'], 'of 10');
      expect(en['foodPlateWeeksTitle'], 'Weeks');
      expect(en['foodPlateRuleTitle'], 'Rule and math');

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

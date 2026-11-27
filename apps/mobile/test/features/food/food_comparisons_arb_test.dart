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
  'foodTabComparisons',
  'foodLinkAlcoholThreeOrMore',
  'foodLinkAlcoholOneToTwo',
  'foodLinkLateLastMeal',
  'foodLinkHeavyDinner',
  'foodRegTitle',
  'foodRegTag',
  'foodRegNote',
  'foodCompFoot',
];

const _placeholderTypes = <String, Map<String, String>>{
  'foodCompLead': {'days': 'int', 'date': 'String'},
  'foodLinkCaffeineAfter14': {'time': 'String'},
  'foodCompTag': {'state': 'String'},
  'foodCompCollecting': {'pairs': 'int', 'minimum': 'int'},
  'foodCompNoClear': {'pairs': 'int'},
  'foodCompPatternLine': {
    'pairs': 'int',
    'outcome': 'String',
    'delta': 'String',
    'range': 'String',
  },
  'foodCompDelta': {'direction': 'String', 'value': 'String'},
  'foodOutcomeName': {'outcome': 'String'},
  'foodRegCollecting': {'days': 'int', 'minimum': 'int'},
  'foodRegSummary': {'sd': 'String', 'days': 'int'},
  'foodRegWeekend': {'direction': 'String', 'shift': 'String'},
};

final List<String> _allKeys = [..._plainKeys, ..._placeholderTypes.keys];

final _dashes = RegExp(
  '[${String.fromCharCode(0x2013)}${String.fromCharCode(0x2014)}]',
);

final _outerPlaceholder = RegExp(r'\{(\w+)(?:,|})');

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
  group('F12a food comparisons ARB keys across all 11 locales', () {
    for (final locale in _locales) {
      test('$locale holds all 20 F12a keys, non-empty, no em/en dashes', () {
        expect(_allKeys.toSet(), hasLength(20));
        final arb = _arb(locale);
        expect(_missing(arb), isEmpty);
        final offenders = [
          for (final key in _allKeys)
            if ((arb[key] as String).contains(_dashes)) key,
        ];
        expect(offenders, isEmpty);
      });

      test(
        '$locale preserves placeholders and renders all select branches',
        () {
          final arb = _arb(locale);
          for (final key in _plainKeys) {
            expect(
              _outerPlaceholder.allMatches(arb[key] as String),
              isEmpty,
              reason: '$locale $key',
            );
          }
          for (final entry in _placeholderTypes.entries) {
            final text = arb[entry.key] as String;
            for (final placeholder in entry.value.keys) {
              expect(
                text.contains('{$placeholder}') ||
                    text.contains('{$placeholder,'),
                isTrue,
                reason: '$locale ${entry.key} missing $placeholder',
              );
            }
          }

          final l10n = lookupAppLocalizations(_toLocale(locale));
          expect(
            l10n.foodCompLead(90, 'Mon, Nov 16'),
            allOf(contains('90'), contains('Mon, Nov 16')),
          );
          expect(l10n.foodLinkCaffeineAfter14('14:00'), contains('14:00'));
          expect(
            l10n.foodCompCollecting(4, 14),
            allOf(contains('4'), contains('14')),
          );
          expect(l10n.foodCompNoClear(16), contains('16'));
          expect(
            l10n.foodRegCollecting(6, 10),
            allOf(contains('6'), contains('10')),
          );
          expect(
            l10n.foodRegSummary('1 h 8 min', 14),
            allOf(contains('1 h 8 min'), contains('14')),
          );
          for (final state in ['pattern', 'none', 'collecting']) {
            expect(l10n.foodCompTag(state).trim(), isNotEmpty);
          }
          for (final dir in ['higher', 'lower', 'later', 'earlier']) {
            expect(l10n.foodCompDelta(dir, '5 bpm'), contains('5 bpm'));
          }
          for (final outcome in ['heartRate', 'hrv', 'onset']) {
            expect(l10n.foodOutcomeName(outcome).trim(), isNotEmpty);
          }
          for (final dir in ['later', 'earlier']) {
            expect(l10n.foodRegWeekend(dir, '2 h'), contains('2 h'));
          }
        },
      );
    }

    test('English ARB metadata defines expected placeholder types', () {
      expect(_allKeys.toSet(), hasLength(20));
      expect(_plainKeys, hasLength(9));
      expect(_placeholderTypes, hasLength(11));

      final en = _arb('en');
      expect(en['foodTabComparisons'], 'Comparisons');
      expect(en['foodRegTitle'], 'Meal times');

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

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
  'foodTimingTitle',
  'foodTimingLegendWindow',
  'foodTimingLegendSleep',
  'foodWeekWindowSub',
  'foodWeekGapTitle',
  'foodWeekGapSub',
  'foodSheetKind',
  'foodSheetUnitMedian',
  'foodSheetWindowWhat',
  'foodSheetWindowRule',
  'foodSheetMedianMath',
  'foodSheetWindowOurs',
  'foodSheetWindowLimits',
  'foodSheetGapWhat',
  'foodSheetGapRule',
  'foodSheetGapOurs',
  'foodSheetGapLimits',
];

const _placeholderTypes = <String, Map<String, String>>{
  'foodTimingCompleteDays': {'count': 'int'},
  'foodTimingChartLabel': {'complete': 'int'},
  'foodSheetDaysYours': {'days': 'int', 'values': 'String', 'median': 'String'},
};

final List<String> _allKeys = [..._plainKeys, ..._placeholderTypes.keys];

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

Locale _toLocale(String code) {
  final parts = code.split('_');
  return parts.length == 2 ? Locale(parts[0], parts[1]) : Locale(parts[0]);
}

void main() {
  group('F9b food timing ARB keys across all 11 locales', () {
    for (final locale in _locales) {
      test('$locale holds all 20 F9b keys, non-empty, no em/en dashes', () {
        expect(_allKeys.toSet(), hasLength(20));
        final arb = _arb(locale);
        expect(_missing(arb), isEmpty);
        final offenders = [
          for (final key in _allKeys)
            if ((arb[key] as String).contains(_dashes)) key,
        ];
        expect(offenders, isEmpty);
      });

      test('$locale preserves exact placeholders and renders plurals', () {
        final arb = _arb(locale);
        for (final key in _plainKeys) {
          expect(
            _placeholder.allMatches(arb[key] as String),
            isEmpty,
            reason: '$locale $key',
          );
        }

        expect(
          arb['foodTimingCompleteDays'],
          contains('{count, plural,'),
          reason: locale,
        );
        expect(
          _pluralPlaceholders(arb['foodTimingCompleteDays'] as String),
          const {'count'},
          reason: locale,
        );
        expect(
          arb['foodSheetDaysYours'],
          contains('{days, plural,'),
          reason: locale,
        );
        expect(_pluralPlaceholders(arb['foodSheetDaysYours'] as String), const {
          'days',
          'values',
          'median',
        }, reason: locale);
        expect(
          {
            for (final m in _placeholder.allMatches(
              arb['foodTimingChartLabel'] as String,
            ))
              m.group(1)!,
          },
          const {'complete'},
          reason: locale,
        );

        final l10n = lookupAppLocalizations(_toLocale(locale));
        expect(l10n.foodTimingCompleteDays(0), contains('0'));
        expect(l10n.foodTimingCompleteDays(1), isNotEmpty);
        expect(l10n.foodTimingCompleteDays(5), contains('5'));
        expect(l10n.foodSheetDaysYours(0, '', ''), isNotEmpty);
        expect(
          l10n.foodSheetDaysYours(1, '8 h', '8 h'),
          allOf(contains('8 h')),
        );
        expect(
          l10n.foodSheetDaysYours(3, '7 h, 8 h, 9 h', '8 h'),
          allOf(contains('3'), contains('7 h, 8 h, 9 h'), contains('8 h')),
        );
      });
    }

    test('English ARB metadata defines expected placeholder types', () {
      expect(_allKeys.toSet(), hasLength(20));
      expect(_plainKeys, hasLength(17));
      expect(_placeholderTypes, hasLength(3));

      final en = _arb('en');
      expect(en['foodTimingTitle'], 'Timing');
      expect(en['foodWeekGapTitle'], 'Last meal to sleep');

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

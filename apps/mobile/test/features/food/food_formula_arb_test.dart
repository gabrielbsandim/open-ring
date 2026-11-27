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
  'foodFormulaIntro',
  'foodFormulaMealTitle',
  'foodFormulaCompleteTitle',
  'foodFormulaTimingExpr',
  'foodFormulaCompTitle',
  'foodFormulaCompNote',
  'foodFormulaSource1',
  'foodFormulaUnchecked1',
  'foodFormulaUnchecked2',
  'foodFormulaUnchecked3',
  'foodFormulaUnchecked4',
  'foodFormulaCannot1',
  'foodFormulaCannot2',
  'foodFormulaCannot3',
];

const _placeholderTypes = <String, Map<String, String>>{
  'foodFormulaMealBody': {'start': 'String'},
  'foodFormulaMealSlots': {
    'lunch': 'String',
    'afternoon': 'String',
    'dinner': 'String',
    'supper': 'String',
  },
  'foodFormulaCompBody': {'days': 'int', 'pairDays': 'int'},
  'foodFormulaCompExpr': {
    'alcMin': 'int',
    'otherMin': 'int',
    'hr': 'String',
    'hrv': 'String',
    'onset': 'String',
  },
  'foodFormulaOurs1': {'start': 'String'},
  'foodFormulaOurs2': {'days': 'int', 'pairDays': 'int'},
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
  group('F10b food formula ARB keys across all 11 locales', () {
    for (final locale in _locales) {
      test('$locale holds all 20 F10b keys, non-empty, no em/en dashes', () {
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
        expect(l10n.foodFormulaMealBody('05:00'), contains('05:00'));
        expect(l10n.foodFormulaOurs1('05:00'), contains('05:00'));
        expect(
          l10n.foodFormulaCompBody(90, 10),
          allOf(contains('90'), contains('10')),
        );
        expect(
          l10n.foodFormulaOurs2(90, 10),
          allOf(contains('90'), contains('10')),
        );
      });
    }

    test('English ARB metadata defines expected placeholder types', () {
      expect(_allKeys.toSet(), hasLength(20));
      expect(_plainKeys, hasLength(14));
      expect(_placeholderTypes, hasLength(6));

      final en = _arb('en');
      expect(en['foodFormulaMealTitle'], 'The meal');
      expect(en['foodFormulaCompleteTitle'], 'The complete day');
      expect(en['foodFormulaCompTitle'], 'Comparisons');

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

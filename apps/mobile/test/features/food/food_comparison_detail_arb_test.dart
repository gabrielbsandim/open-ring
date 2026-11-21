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
  'foodCompDetailNotFound',
  'foodCompAlsoTitle',
  'foodCompPairsTitle',
  'foodCompPairsNote',
  'foodCompPairsWith',
  'foodCompPairsWithout',
  'foodCompPairsDiff',
  'foodCompCannotTagged',
  'foodCompCannotRing',
];

const _placeholderTypes = <String, Map<String, String>>{
  'foodCompDetailTitle': {'link': 'String'},
  'foodCompDetailLead': {'range': 'String', 'updated': 'String'},
  'foodCompAlt': {'link': 'String'},
  'foodCompPatternWhy': {'alt': 'String'},
  'foodCompNoneWhy': {'pairs': 'int', 'threshold': 'String'},
  'foodCompCollectingWhy': {'minimum': 'int'},
  'foodCompAlsoPattern': {
    'outcome': 'String',
    'delta': 'String',
    'range': 'String',
    'pairs': 'int',
  },
  'foodCompAlsoNone': {'outcome': 'String', 'range': 'String', 'pairs': 'int'},
  'foodCompAlsoCollecting': {
    'outcome': 'String',
    'pairs': 'int',
    'minimum': 'int',
  },
  'foodCompRuleExpr': {
    'pairs': 'int',
    'minimum': 'int',
    'mean': 'String',
    'sd': 'String',
    'df': 'int',
    't': 'String',
    'low': 'String',
    'high': 'String',
    'threshold': 'String',
  },
  'foodCompRuleNote': {
    'alcoholOnly': 'String',
    'pairDays': 'int',
    'module': 'String',
  },
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
  group('F12b food comparison detail ARB keys across all 11 locales', () {
    for (final locale in _locales) {
      test('$locale holds all 20 F12b keys, non-empty, no em/en dashes', () {
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
            l10n.foodCompDetailTitle('Heavy dinner'),
            contains('Heavy dinner'),
          );
          expect(
            l10n.foodCompDetailLead('Aug 18 to Nov 15', 'Mon, Nov 16'),
            allOf(contains('Aug 18 to Nov 15'), contains('Mon, Nov 16')),
          );
          for (final link in const [
            'alcoholThreeOrMore',
            'alcoholOneToTwo',
            'lateLastMeal',
            'caffeineAfter14',
            'heavyDinner',
          ]) {
            final alt = l10n.foodCompAlt(link);
            expect(alt.trim(), isNotEmpty);
            expect(l10n.foodCompPatternWhy(alt), contains(alt));
          }
          expect(
            l10n.foodCompNoneWhy(16, '15 min'),
            allOf(contains('16'), contains('15 min')),
          );
          expect(l10n.foodCompCollectingWhy(14), contains('14'));
          expect(
            l10n.foodCompAlsoCollecting('Nightly HRV', 9, 14),
            allOf(contains('Nightly HRV'), contains('9'), contains('14')),
          );
          expect(
            l10n.foodCompRuleExpr(
              12,
              10,
              '+5.1 bpm',
              '2.8',
              11,
              '3.106',
              '+1.6 bpm',
              '+8.6 bpm',
              '2 bpm',
            ),
            allOf(contains('3.106'), contains('12'), contains('11')),
          );
          for (final alcoholOnly in const ['yes', 'no']) {
            expect(
              l10n.foodCompRuleNote(alcoholOnly, 10, l10n.moduleOpenScoreName),
              allOf(contains('10'), contains(l10n.moduleOpenScoreName)),
            );
          }
        },
      );
    }

    test('English ARB metadata defines expected placeholder types', () {
      expect(_allKeys.toSet(), hasLength(20));
      expect(_plainKeys, hasLength(9));
      expect(_placeholderTypes, hasLength(11));

      final en = _arb('en');
      expect(en['foodCompAlsoTitle'], 'Also');
      expect(en['foodCompPairsTitle'], 'The pairs');
      expect(
        en['foodCompCannotTagged'],
        isNot(contains('photo')),
        reason: 'Must reflect food_compare.dart complete tagged days rule',
      );

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

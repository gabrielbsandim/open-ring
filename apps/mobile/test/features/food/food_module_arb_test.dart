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
  'moduleFoodDetail',
  'moduleFoodKept',
  'moduleFoodAddsPatterns',
  'moduleFoodStoresMeals',
  'moduleFoodNeverCalories',
  'moduleFoodNeverUploads',
  'moduleFoodFormulaCaption',
  'moduleFoodDataTitle',
  'moduleFoodDataEmpty',
  'moduleFoodDelete',
  'moduleFoodDeleteTitle',
  'moduleFoodDeleteBody',
  'moduleFoodDeleted',
  'moduleFoodDeleteFailed',
  'moduleFoodTurnOn',
  'moduleFoodTurnOff',
];

const _placeholderTypes = <String, Map<String, String>>{
  'moduleFoodTurnedOn': {'tab': 'String'},
  'moduleFoodAddsToday': {'tab': 'String'},
  'moduleFoodDataCount': {'meals': 'int', 'photos': 'int', 'size': 'String'},
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
  group('F14a Food module ARB keys across all 11 locales', () {
    for (final locale in _locales) {
      test('$locale holds all 19 F14a keys, non-empty, no em/en dashes', () {
        expect(_allKeys.toSet(), hasLength(19));
        final arb = _arb(locale);
        expect(_missing(arb), isEmpty);
        final offenders = [
          for (final key in _allKeys)
            if ((arb[key] as String).contains(_dashes)) key,
        ];
        expect(offenders, isEmpty);
      });

      test('$locale preserves placeholders and plural branches', () {
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

        final l = lookupAppLocalizations(_toLocale(locale));
        expect(l.moduleFoodTurnedOn(l.tabToday), contains(l.tabToday));
        expect(l.moduleFoodAddsToday(l.tabToday), contains(l.tabToday));
        for (final m in const [0, 1, 2, 5, 21]) {
          expect(l.moduleFoodDataCount(m, 1, '1.5 MB'), contains('1.5 MB'));
        }
        expect(l.moduleFoodDataCount(0, 0, '500 KB'), contains('500 KB'));
      });
    }

    test('Russian moduleFoodDataCount defines one/few/many without =1 override warning', () {
      final ru = _arb('ru')['moduleFoodDataCount'] as String;
      expect(ru, contains('one{'));
      expect(ru, contains('few{'));
      expect(ru, contains('many{'));
      expect(ru, isNot(contains('=1{')));
    });

    test('English ARB metadata defines expected placeholder types', () {
      expect(_allKeys.toSet(), hasLength(19));
      final en = _arb('en');
      expect(en['moduleFoodNeverCalories'], isNot(contains('AI')));
      expect(en['moduleFoodDetail'], isNot(contains('energy')));
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

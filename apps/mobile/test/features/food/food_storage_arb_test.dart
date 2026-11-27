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
  'foodPhotosTitle',
  'foodPhotosAverageLabel',
  'foodPhotosOldestLabel',
  'foodPhotosPaceLabel',
  'foodPhotosDeleteButton',
  'foodPhotosSheetTitle',
  'foodPhotosSheetBody',
  'foodPhotosConfirmTitle',
  'foodPhotosDeleteFailed',
  'foodPhotosFootnote',
];

const _placeholderTypes = <String, Map<String, String>>{
  'foodPhotosCount': {'count': 'int'},
  'foodPhotosSizeMb': {'size': 'String'},
  'foodPhotosSizeKb': {'size': 'String'},
  'foodPhotosPaceValue': {'size': 'String'},
  'foodPhotosRangeLabel': {'range': 'String'},
  'foodPhotosPreviewLine': {'count': 'int', 'size': 'String'},
  'foodPhotosPreviewOrphan': {'size': 'String'},
  'foodPhotosConfirmBody': {'count': 'int', 'size': 'String'},
  'foodPhotosDeleted': {'count': 'int', 'size': 'String'},
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
  group('F13 food photo storage ARB keys across all 11 locales', () {
    for (final locale in _locales) {
      test('$locale holds all 19 F13 keys, non-empty, no em/en dashes', () {
        expect(_allKeys.toSet(), hasLength(19));
        final arb = _arb(locale);
        expect(_missing(arb), isEmpty);
        final offenders = [
          for (final key in _allKeys)
            if ((arb[key] as String).contains(_dashes)) key,
        ];
        expect(offenders, isEmpty);
      });

      test('$locale preserves placeholders and renders all branches', () {
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
        for (final c in const [0, 1, 9]) {
          expect(l.foodPhotosCount(c).trim(), isNotEmpty);
          expect(l.foodPhotosPreviewLine(c, '1.5 MB').trim(), isNotEmpty);
          expect(l.foodPhotosConfirmBody(c, '1.5 MB').trim(), isNotEmpty);
          expect(l.foodPhotosDeleted(c, '1.5 MB').trim(), isNotEmpty);
        }
        expect(l.foodPhotosSizeMb('45.2'), contains('45.2'));
        expect(l.foodPhotosSizeKb('165'), contains('165'));
        expect(l.foodPhotosPaceValue('175 MB'), contains('175 MB'));
        expect(l.foodPhotosPreviewOrphan('300 KB'), contains('300 KB'));
        for (final range in const [
          'olderThanThreeMonths',
          'olderThanOneYear',
          'all',
        ]) {
          expect(l.foodPhotosRangeLabel(range).trim(), isNotEmpty);
        }
      });
    }

    test('English ARB metadata defines expected placeholder types', () {
      expect(_allKeys.toSet(), hasLength(19));
      final en = _arb('en');
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

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
  'foodGalleryTitle',
  'foodGallerySubtitle',
  'foodGalleryNoTimeTitle',
  'foodGalleryNoTimeBody',
  'foodGalleryPickTime',
  'foodGallerySkipped',
  'foodGalleryAnotherMeal',
  'foodGallerySkip',
  'foodGalleryOldBody',
  'foodGallerySaveAnyway',
  'foodGalleryStripNote',
  'foodGalleryPickerNote',
  'foodGalleryUnreadable',
  'foodGalleryPickFailed',
];

const _stringPlaceholderKeys = <String, Set<String>>{
  'foodGalleryChosenTime': {'time'},
  'foodGalleryDuplicateBody': {'time'},
  'foodGalleryFromPhoto': {'slot'},
};

const _pluralCountKeys = [
  'foodGallerySaveButton',
  'foodGalleryOpenChoices',
  'foodGallerySavedCount',
];

final List<String> _allKeys = [
  ..._plainKeys,
  ..._stringPlaceholderKeys.keys,
  ..._pluralCountKeys,
];

const _expectedEnglish = <String, String>{
  'foodGalleryTitle': 'From gallery',
  'foodGallerySubtitle':
      'Up to 20 photos at once. The time comes from each photo; without one, '
      'you choose.',
  'foodGalleryNoTimeTitle': 'No time on photo',
  'foodGalleryNoTimeBody':
      'Screenshots and photos sent by message often have no time. The app '
      'never uses the file date.',
  'foodGalleryPickTime': 'Choose time',
  'foodGalleryChosenTime': 'Chosen time: {time}',
  'foodGalleryFromPhoto': '{slot} \u00b7 from photo',
  'foodGallerySkipped': 'Skipped. Not saved as a meal.',
  'foodGalleryDuplicateBody':
      'Within 2 minutes of a saved meal ({time}). It could be the same photo '
      'twice.',
  'foodGalleryAnotherMeal': 'Another meal',
  'foodGallerySkip': 'Skip',
  'foodGalleryOldBody': 'Over a year ago. Save anyway?',
  'foodGallerySaveAnyway': 'Save',
  'foodGallerySaveButton':
      '{count, plural, =0{Save 0 meals} =1{Save 1 meal} '
      'other{Save {count} meals}}',
  'foodGalleryOpenChoices':
      '{count, plural, =1{1 photo asks for a choice. It stays out if you save '
      'now.} other{{count} photos ask for a choice. They stay out if you save '
      'now.}}',
  'foodGalleryStripNote':
      'Each photo is resized and loses location and camera data before saving.',
  'foodGalleryPickerNote':
      'The Android photo picker shares only the photos you choose. The app '
      'does not ask for gallery access.',
  'foodGalleryUnreadable': 'Could not read this photo',
  'foodGalleryPickFailed': 'Could not open the photo picker',
  'foodGallerySavedCount':
      '{count, plural, =1{1 meal saved} other{{count} meals saved}}',
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
  group('F7b gallery ARB keys across all 11 locales', () {
    test('spec lists 20 distinct keys (14 plain, 3 string, 3 plural)', () {
      expect(_allKeys.toSet(), hasLength(20));
      expect(_plainKeys, hasLength(14));
      expect(_stringPlaceholderKeys, hasLength(3));
      expect(_pluralCountKeys, hasLength(3));
    });

    for (final locale in _locales) {
      test('$locale holds all 20 gallery keys, each non-empty', () {
        expect(_missing(_arb(locale)), isEmpty);
      });

      test('$locale has no en dash or em dash in the 20 gallery keys', () {
        final arb = _arb(locale);
        expect(_missing(arb), isEmpty);
        final offenders = [
          for (final key in _allKeys)
            if ((arb[key] as String).contains(_dashes)) key,
        ];
        expect(offenders, isEmpty);
      });

      test('$locale preserves exact placeholder sets on the 6 parameterized '
          'keys and zero placeholders on the 14 plain keys', () {
        final arb = _arb(locale);
        expect(_missing(arb), isEmpty);

        for (final key in _plainKeys) {
          expect(
            _placeholder.allMatches(arb[key] as String),
            isEmpty,
            reason: '$locale $key',
          );
        }

        for (final entry in _stringPlaceholderKeys.entries) {
          final value = arb[entry.key] as String;
          final actual = {
            for (final m in _placeholder.allMatches(value)) m.group(1)!,
          };
          expect(actual, entry.value, reason: '$locale ${entry.key}');
        }

        for (final key in _pluralCountKeys) {
          final value = arb[key] as String;
          expect(value, contains('{count, plural,'), reason: '$locale $key');
          expect(_pluralPlaceholders(value), {'count'}, reason: '$locale $key');
        }
      });
    }

    test('English strings and typed placeholder metadata match spec', () {
      final en = _arb('en');
      expect(_missing(en), isEmpty);
      for (final entry in _expectedEnglish.entries) {
        expect(en[entry.key], entry.value, reason: entry.key);
      }

      for (final entry in _stringPlaceholderKeys.entries) {
        final meta = en['@${entry.key}'] as Map<String, dynamic>?;
        final placeholders = meta?['placeholders'] as Map<String, dynamic>?;
        expect(placeholders?.keys.toSet(), entry.value, reason: entry.key);
        for (final name in entry.value) {
          final def = placeholders?[name] as Map<String, dynamic>?;
          expect(def?['type'], 'String', reason: '${entry.key}.$name');
        }
      }

      for (final key in _pluralCountKeys) {
        final meta = en['@$key'] as Map<String, dynamic>?;
        final placeholders = meta?['placeholders'] as Map<String, dynamic>?;
        expect(placeholders?.keys.toSet(), {'count'}, reason: key);
        final def = placeholders?['count'] as Map<String, dynamic>?;
        expect(def?['type'], 'int', reason: '$key.count');
      }
    });
  });
}

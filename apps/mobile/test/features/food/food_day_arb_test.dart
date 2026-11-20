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

const _newKeys = [
  'foodDayPrevious',
  'foodDayNext',
  'foodDayToday',
  'foodDayEmptyTitle',
  'foodDayEmptyBody',
  'foodDayBlankNote',
  'foodWindowTitle',
  'foodWindowOpen',
  'foodWindowSpan',
  'foodDayCompleteNote',
  'foodMealNoTags',
  'foodSlotBreakfast',
  'foodSlotLunch',
  'foodSlotAfternoonSnack',
  'foodSlotDinner',
  'foodSlotSupper',
  'foodNoPhoto',
  'foodPhotoMissing',
];

const _plainKeys = [
  'foodDayPrevious',
  'foodDayNext',
  'foodDayToday',
  'foodDayEmptyTitle',
  'foodDayEmptyBody',
  'foodDayBlankNote',
  'foodWindowTitle',
  'foodDayCompleteNote',
  'foodMealNoTags',
  'foodSlotBreakfast',
  'foodSlotLunch',
  'foodSlotAfternoonSnack',
  'foodSlotDinner',
  'foodSlotSupper',
  'foodNoPhoto',
  'foodPhotoMissing',
];

final _dashes = RegExp(
  '[${String.fromCharCode(0x2013)}${String.fromCharCode(0x2014)}]',
);

Map<String, dynamic> _arb(String locale) =>
    jsonDecode(File('lib/l10n/app_$locale.arb').readAsStringSync())
        as Map<String, dynamic>;

List<String> _missing(Map<String, dynamic> arb) => [
  for (final key in _newKeys)
    if (arb[key] is! String || (arb[key] as String).trim().isEmpty) key,
];

void main() {
  group('criterion 10: the 18 food day ARB keys across all 11 locales', () {
    for (final locale in _locales) {
      test('$locale holds the 18 new keys, each non-empty', () {
        expect(_newKeys.toSet(), hasLength(18), reason: 'the spec list');
        expect(_missing(_arb(locale)), isEmpty);
      });
    }

    for (final locale in _locales) {
      test('$locale has no en dash or em dash in the 18 new keys', () {
        final arb = _arb(locale);
        expect(_missing(arb), isEmpty, reason: 'new strings');
        final offenders = [
          for (final key in _newKeys)
            if ((arb[key] as String).contains(_dashes)) key,
        ];
        expect(offenders, isEmpty);
      });
    }

    test('English window, no-tags and thumbnail strings match the spec', () {
      final arb = _arb('en');
      expect(arb['foodWindowOpen'], 'Open since {time}, {duration} so far');
      expect(arb['foodWindowSpan'], '{from} to {to}, {duration}');
      expect(arb['foodMealNoTags'], 'no tags');
      expect(arb['foodNoPhoto'], 'No photo');
      expect(arb['foodPhotoMissing'], 'Photo not found');
    });

    for (final locale in _locales) {
      test('$locale preserves the window placeholders and adds none to the '
          'other 16 keys', () {
        final arb = _arb(locale);
        expect(_missing(arb), isEmpty, reason: 'new strings');
        final open = arb['foodWindowOpen'] as String;
        final span = arb['foodWindowSpan'] as String;
        expect(open, contains('{time}'));
        expect(open, contains('{duration}'));
        expect(span, contains('{from}'));
        expect(span, contains('{to}'));
        expect(span, contains('{duration}'));
        final placeholder = RegExp(r'\{\w+\}');
        final unexpected = [
          for (final key in _plainKeys)
            if ((arb[key] as String).contains(placeholder)) key,
        ];
        expect(unexpected, isEmpty);
      });
    }

    test('D7: foodNoSpaceNote stays unchanged alongside the 18 new keys', () {
      final en = _arb('en');
      expect(_missing(en), isEmpty);
      expect(
        en['foodNoSpaceNote'],
        'Without a photo, the meal keeps its time but has no tags yet, so the '
        'comparisons skip that night.',
      );
      for (final locale in _locales) {
        final arb = _arb(locale);
        expect(_missing(arb), isEmpty, reason: locale);
        final note = arb['foodNoSpaceNote'];
        expect(note, isA<String>(), reason: locale);
        expect((note as String).trim(), isNotEmpty, reason: locale);
        expect(note.contains(_dashes), isFalse, reason: locale);
      }
    });
  });
}

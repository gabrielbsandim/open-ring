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

const _keys = [
  'goalsPickTitle',
  'goalsPickLead',
  'goalsPickGroup',
  'goalsPickNone',
  'goalsPickNoneDetail',
  'goalsPickLoseFat',
  'goalsPickLoseFatDetail',
  'goalsPickGetFitter',
  'goalsPickGetFitterDetail',
  'goalsPickSleepBetter',
  'goalsPickSleepBetterDetail',
  'goalsPickUsesBody',
  'goalsPickNeedsBody',
  'goalsPickOpenBody',
  'goalsPickBodyNote',
  'goalsPickContinue',
  'goalsPickContinueNone',
  'goalsPickNoteWeight',
  'goalsPickNoteNone',
  'goalsPickNoteOther',
  'goalsPickActive',
  'goalsStartFailed',
  'goalsRefusalRule',
  'goalsRefusalFoot',
  'goalsRefusalSeeNoWeight',
  'goalsRefusalSeeOthers',
  'goalsUnder18Title',
  'goalsUnder18Body1',
  'goalsUnder18Body2',
  'goalsUnder18Rule',
  'goalsBmiTitle',
  'goalsBmiBody1',
  'goalsBmiBody1Hidden',
  'goalsBmiBody2',
  'goalsBmiRule',
  'goalsBmiRuleHidden',
  'goalsProfileTitle',
  'goalsProfileBody',
  'goalsProfileOpen',
];

final _dashes = RegExp(
  '[${String.fromCharCode(0x2013)}${String.fromCharCode(0x2014)}]',
);

Map<String, dynamic> _arb(String locale) =>
    jsonDecode(File('lib/l10n/app_$locale.arb').readAsStringSync())
        as Map<String, dynamic>;

void main() {
  group('12. the picker strings', () {
    test('the spec lists 39 distinct keys', () {
      expect(_keys.toSet(), hasLength(39));
    });

    for (final locale in _locales) {
      test('$locale holds the 39 keys, each with a text', () {
        final arb = _arb(locale);
        final missing = [
          for (final key in _keys)
            if (arb[key] is! String || (arb[key] as String).trim().isEmpty) key,
        ];
        expect(missing, isEmpty);
      });
    }

    for (final locale in _locales) {
      test('$locale has no en dash or em dash in any value', () {
        final arb = _arb(locale);
        expect(arb.containsKey(_keys.first), isTrue, reason: 'new strings');
        final offenders = [
          for (final entry in arb.entries)
            if (entry.value is String &&
                (entry.value as String).contains(_dashes))
              entry.key,
        ];
        expect(offenders, isEmpty);
      });
    }

    test('the placeholders of every locale match the English ones', () {
      final english = _arb('en');
      expect(english['goalsUnder18Body1'], contains('{age}'));
      expect(english['goalsUnder18Rule'], contains('{year}'));
      expect(
        english['goalsBmiRule'],
        allOf(contains('{bmi}'), contains('{floor}')),
      );
      final names = RegExp(r'\{(\w+)\}');
      for (final locale in _locales) {
        final arb = _arb(locale);
        for (final key in _keys) {
          final expected = {
            for (final m in names.allMatches('${english[key]}')) m.group(1),
          };
          final actual = {
            for (final m in names.allMatches('${arb[key]}')) m.group(1),
          };
          expect(actual, expected, reason: '$locale $key');
        }
      }
    });
  });
}

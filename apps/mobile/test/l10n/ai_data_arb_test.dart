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
  'moduleAiDataTitle',
  'moduleAiDataEmpty',
  'moduleAiDataReadings',
  'moduleAiDataKey',
  'moduleAiDelete',
  'moduleAiDeleteTitle',
  'moduleAiDeleteBody',
  'moduleAiDeleteNotes',
  'moduleAiDeleteConfirm',
  'moduleAiDeleted',
  'moduleAiDeleteFailed',
  'moduleFoodAddsAi',
  'moduleFoodStoresAi',
  'moduleFoodAiPhotos',
  'moduleFoodFormulaCaptionAi',
];

const _placeholders = {
  'moduleAiDataReadings': {'count'},
  'moduleAiDataKey': {'state', 'last4'},
  'moduleAiDeleteBody': {'count'},
  'moduleAiDeleteNotes': {'item', 'host'},
  'moduleFoodAddsAi': {'state'},
  'moduleFoodAiPhotos': {'host'},
};

const _selects = {
  'moduleAiDataKey': ['none', 'hidden', 'other'],
  'moduleAiDeleteNotes': ['received', 'key', 'other'],
  'moduleFoodAddsAi': ['on', 'other'],
};

const _plurals = ['moduleAiDataReadings', 'moduleAiDeleteBody'];

// Flutter reads =1 and one as one branch, so Russian carries one instead.
List<String> _plural(String locale) => locale == 'ru'
    ? const ['one', 'few', 'many', 'other']
    : const ['=1', 'other'];

final _dashes = RegExp(
  '[${String.fromCharCode(0x2013)}${String.fromCharCode(0x2014)}]',
);

// A case body such as other{...} is not a placeholder.
final _placeholder = RegExp(
  r'(?<![A-Za-z0-9_=])\{([A-Za-z]\w*)(?:\}|, ?(?:select|plural),)',
);

Map<String, dynamic> _arb(String locale) =>
    jsonDecode(File('lib/l10n/app_$locale.arb').readAsStringSync())
        as Map<String, dynamic>;

bool _hasCase(String value, String name) =>
    RegExp('(?<![A-Za-z=])${RegExp.escape(name)}\\{').hasMatch(value);

void main() {
  group('A14c AI data and Food AI strings', () {
    test('15 distinct keys, with English placeholder metadata', () {
      expect(_keys.toSet(), hasLength(15));
      final english = _arb('en');
      for (final entry in _placeholders.entries) {
        final meta = english['@${entry.key}'] as Map<String, dynamic>;
        final names = (meta['placeholders'] as Map<String, dynamic>).keys;
        expect(names.toSet(), entry.value, reason: entry.key);
      }
    });

    for (final locale in _locales) {
      test('$locale holds every key with its placeholders and branches', () {
        final arb = _arb(locale);
        for (final key in _keys) {
          final value = arb[key];
          expect(value, isA<String>(), reason: '$locale $key');
          final text = value as String;
          expect(text.trim(), isNotEmpty, reason: '$locale $key');
          expect(text.contains(_dashes), isFalse, reason: '$locale $key');
          expect(
            {for (final m in _placeholder.allMatches(text)) m.group(1)},
            _placeholders[key] ?? <String>{},
            reason: '$locale $key',
          );
          for (final name in _selects[key] ?? const <String>[]) {
            expect(_hasCase(text, name), isTrue, reason: '$locale $key $name');
          }
        }
        for (final key in _plurals) {
          final text = arb[key] as String;
          for (final name in _plural(locale)) {
            expect(_hasCase(text, name), isTrue, reason: '$locale $key $name');
          }
          if (locale == 'ru') expect(_hasCase(text, '=1'), isFalse);
        }
      });

      test('$locale no longer says the Food module has no calories at all', () {
        final arb = _arb(locale);
        final never = arb['moduleFoodNeverCalories'] as String;
        expect(never.contains(_dashes), isFalse);
        expect(never, isNot(_arbBefore[locale]), reason: locale);
      });
    }
  });
}

// The pre A14c values, which Weekly energy made false.
const _arbBefore = {
  'en':
      'No calorie estimates, no macro targets and no good or bad meal scores.',
  'de': 'Keine Kalorienschätzungen, keine Makroziele und keine Bewertungen in gut oder schlecht.',
  'es': 'Sin estimaciones de calorías, sin metas de macros y sin notas de bueno o malo.',
  'fr': 'Pas d’estimation de calories, pas d’objectifs de macros et pas de notes bien ou mal.',
  'id': 'Tanpa perkiraan kalori, tanpa target makro, dan tanpa skor baik atau buruk.',
  'it': 'Nessuna stima delle calorie, nessun obiettivo di macro e nessun punteggio buono o cattivo.',
  'ja': 'カロリー推定、マクロ目標、良い悪いの採点は一切行いません。',
  'pt': 'Sem estimativas de calorias, sem metas de macros e sem notas de bom ou ruim.',
  'pt_PT': 'Sem estimativas de calorias, sem metas de macros e sem notas de bom ou mau.',
  'ru': 'Без расчёта калорий, норм нутриентов и оценок «хорошо» или «плохо».',
  'zh': '不估算热量，不设宏量营养素目标，也不给餐食打好坏分数。',
};

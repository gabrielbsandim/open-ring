import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/ai/domain/meal_photo_result.dart';

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
  'foodAiItemsTitle',
  'foodAiMeasure',
  'foodAiItemLine',
  'foodAiItemRemoved',
  'foodAiItemLess',
  'foodAiItemMore',
  'foodAiHiddenTitle',
  'foodAiHiddenOil',
  'foodAiHiddenSauce',
  'foodAiHiddenSugar',
  'foodAiItemsNote',
];

const _placeholders = {
  'foodAiMeasure': {'measure'},
  'foodAiItemLine': {'count', 'measure', 'grams'},
  'foodAiItemLess': {'name'},
  'foodAiItemMore': {'name'},
};

// Every measure but unit, which the select reads as other.
final Map<String, List<String>> _cases = {
  'foodAiMeasure': [
    for (final m in MealPhotoMeasure.values)
      if (m != MealPhotoMeasure.unit) m.name,
    'other',
  ],
};

final _dashes = RegExp(
  '[${String.fromCharCode(0x2013)}${String.fromCharCode(0x2014)}]',
);

final _argument = RegExp(r'(?<![\w=])\{(\w+)[,}]');

Map<String, dynamic> _arb(String locale) =>
    jsonDecode(File('lib/l10n/app_$locale.arb').readAsStringSync())
        as Map<String, dynamic>;

void main() {
  test('the 11 A12e keys are distinct and the en metadata names their '
      'placeholders', () {
    expect(_keys.toSet(), hasLength(11));
    final en = _arb('en');
    for (final key in _keys) {
      final meta = en['@$key'] as Map<String, dynamic>?;
      final names = (meta?['placeholders'] as Map<String, dynamic>?)?.keys;
      expect(names?.toSet() ?? <String>{}, _placeholders[key] ?? <String>{});
    }
  });

  for (final locale in _locales) {
    test('$locale holds the 11 A12e keys with the same placeholders, every '
        'measure, no dash and no number', () {
      final arb = _arb(locale);
      for (final key in _keys) {
        final value = arb[key];
        expect(value, isA<String>(), reason: '$locale $key');
        final text = value as String;
        expect(text.contains(_dashes), isFalse, reason: '$locale $key');
        expect(
          text.contains(RegExp(r'\d|kcal')),
          isFalse,
          reason: '$locale $key',
        );
        final used = {for (final m in _argument.allMatches(text)) m.group(1)};
        expect(used, _placeholders[key] ?? <String>{}, reason: '$locale $key');
        for (final c in _cases[key] ?? const <String>[]) {
          expect(text, contains(' $c{'), reason: '$locale $key $c');
        }
      }
    });
  }

  test('pt_PT keeps the formal register', () {
    final informal = RegExp(
      r'(?<!\p{L})(você|tu|teu|tua)(?!\p{L})',
      caseSensitive: false,
      unicode: true,
    );
    final pt = _arb('pt_PT');
    for (final key in _keys) {
      expect(pt[key] as String, isNot(contains(informal)), reason: key);
    }
  });
}

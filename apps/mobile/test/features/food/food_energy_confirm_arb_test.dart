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

const _keys = ['foodAiItemsConfirm', 'foodAiItemsCheck', 'foodAiItemsDone'];

const _check =
    'Check the items and the chips below, then confirm. Only meals you '
    'confirm count in the weekly energy.';

final _dashes = RegExp(
  '[${String.fromCharCode(0x2013)}${String.fromCharCode(0x2014)}]',
);

Map<String, dynamic> _arb(String locale) =>
    jsonDecode(File('lib/l10n/app_$locale.arb').readAsStringSync())
        as Map<String, dynamic>;

void main() {
  test('the en text of the 3 A13b keys is the spec text', () {
    final en = _arb('en');
    expect(
      [for (final key in _keys) en[key]],
      [
        'These items look right',
        _check,
        'Checked. This meal counts in the weekly energy.',
      ],
    );
  });

  for (final locale in _locales) {
    test('$locale holds the 3 A13b keys with no placeholder, dash or '
        'number', () {
      final arb = _arb(locale);
      for (final key in _keys) {
        final value = arb[key];
        expect(value, isA<String>(), reason: '$locale $key');
        final text = value as String;
        expect(text, isNotEmpty, reason: '$locale $key');
        expect(text.contains(_dashes), isFalse, reason: '$locale $key');
        expect(text.contains(RegExp(r'[{}\d]|kcal')), isFalse);
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

  test('id addresses the reader as Anda, like the other foodAi strings', () {
    final text = _arb('id')['foodAiItemsCheck'] as String;
    expect(text, contains('Anda'));
    expect(text, isNot(contains(RegExp(r'\bkamu\b', caseSensitive: false))));
  });

  test('es, it and ru call the chips options, not the meal tag word', () {
    const tagWords = {'es': 'etiqueta', 'it': 'etichett', 'ru': 'метк'};
    for (final MapEntry(key: locale, value: tag) in tagWords.entries) {
      final text = _arb(locale)['foodAiItemsCheck'] as String;
      expect(text.toLowerCase(), isNot(contains(tag)), reason: locale);
    }
  });
}

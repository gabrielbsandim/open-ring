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
  'foodAiSuggestedHint',
  'foodAiConfirmAll',
  'foodAiChecked',
  'foodAiSuggestedChip',
  'foodAiConfirmed',
  'foodAiBatch',
  'foodAiBatchQueued',
  'foodAiBatchPartial',
  'foodAiBadge',
];

const _placeholders = {
  'foodAiConfirmAll': {'count'},
  'foodAiSuggestedChip': {'tag'},
  'foodAiBatch': {'count'},
  'foodAiBatchQueued': {'count'},
  'foodAiBatchPartial': {'count'},
  'foodAiBadge': {'state'},
};

const _cases = {
  'foodAiBadge': ['suggestions', 'queued', 'sending', 'failed', 'other'],
};

final _dashes = RegExp(
  '[${String.fromCharCode(0x2013)}${String.fromCharCode(0x2014)}]',
);

// A select or plural case body such as `=0{Resume}` is not an argument.
final _argument = RegExp(r'(?<![\w=])\{(\w+)[,}]');

Map<String, dynamic> _arb(String locale) =>
    jsonDecode(File('lib/l10n/app_$locale.arb').readAsStringSync())
        as Map<String, dynamic>;

void main() {
  test('the 9 A12d keys are distinct and the en metadata names their '
      'placeholders', () {
    expect(_keys.toSet(), hasLength(9));
    final en = _arb('en');
    for (final key in _keys) {
      final meta = en['@$key'] as Map<String, dynamic>?;
      final names = (meta?['placeholders'] as Map<String, dynamic>?)?.keys;
      expect(names?.toSet() ?? <String>{}, _placeholders[key] ?? <String>{});
    }
  });

  for (final locale in _locales) {
    test('$locale holds the 9 A12d keys with the same placeholders, every '
        'select case and no dash', () {
      final arb = _arb(locale);
      for (final key in _keys) {
        final value = arb[key];
        expect(value, isA<String>(), reason: '$locale $key');
        final text = value as String;
        expect(text.contains(_dashes), isFalse, reason: '$locale $key');
        final used = {for (final m in _argument.allMatches(text)) m.group(1)};
        expect(used, _placeholders[key] ?? <String>{}, reason: '$locale $key');
        for (final c in _cases[key] ?? const <String>[]) {
          expect(text, contains('$c{'), reason: '$locale $key $c');
        }
      }
    });

    test('$locale names the Plate pattern the way its screen does', () {
      final arb = _arb(locale);
      final plate = (arb['foodPlateTitle'] as String).split(' ').first;
      final stem = plate.substring(0, plate.length - 1);
      for (final key in ['foodAiChecked', 'foodAiConfirmed']) {
        expect(arb[key] as String, contains(stem), reason: '$locale $key');
      }
    });
  }

  test('the id lines use Anda, never kamu or -mu', () {
    final informal = RegExp(r'\bkamu\b|\w+mu\b', caseSensitive: false);
    final id = _arb('id');
    for (final key in _keys) {
      expect(id[key] as String, isNot(contains(informal)), reason: key);
    }
  });

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

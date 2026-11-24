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
  'foodAiConsentFirst',
  'foodAiConsentTitle',
  'foodAiConsentHow',
  'foodAiConsentWhat',
  'foodAiConsentShows',
  'foodAiConsentAfter',
  'foodAiConsentRough',
  'foodAiConsentUnencrypted',
  'foodAiConsentTick',
  'foodAiConsentScope',
  'foodAiProbeRunning',
  'foodAiProbeTextOnly',
  'foodAiOpenPhotos',
  'foodAiAnalyze',
  'foodAiKeepTitle',
  'foodAiKeepHint',
  'foodAiQueued',
  'foodAiLimit',
  'foodAiUnavailable',
  'aiConsentWhereNoKey',
];

const _placeholders = {
  'foodAiConsentTitle': {'host'},
  'foodAiConsentHow': {'width', 'height', 'size'},
  'foodAiConsentAfter': {'host'},
  'foodAiConsentTick': {'host'},
  'foodAiProbeRunning': {'model'},
  'foodAiProbeTextOnly': {'model'},
  'foodAiLimit': {'count'},
  'aiConsentWhereNoKey': {'host'},
};

final _dashes = RegExp(
  '[${String.fromCharCode(0x2013)}${String.fromCharCode(0x2014)}]',
);

// An argument name is followed by a comma (select, plural) or a brace.
final _argument = RegExp(r'\{(\w+)[,}]');

Map<String, dynamic> _arb(String locale) =>
    jsonDecode(File('lib/l10n/app_$locale.arb').readAsStringSync())
        as Map<String, dynamic>;

void main() {
  test('the 20 A12b keys are distinct and the en metadata names their '
      'placeholders', () {
    expect(_keys.toSet(), hasLength(20));
    final en = _arb('en');
    for (final key in _keys) {
      final meta = en['@$key'] as Map<String, dynamic>?;
      final names = (meta?['placeholders'] as Map<String, dynamic>?)?.keys;
      expect(names?.toSet() ?? <String>{}, _placeholders[key] ?? <String>{});
    }
  });

  for (final locale in _locales) {
    test('$locale holds the 20 A12b keys with the same placeholders and '
        'no dash', () {
      final arb = _arb(locale);
      for (final key in _keys) {
        final value = arb[key];
        expect(value, isA<String>(), reason: '$locale $key');
        final text = value as String;
        expect(text.trim(), isNotEmpty, reason: '$locale $key');
        expect(text.contains(_dashes), isFalse, reason: '$locale $key');
        final used = {for (final m in _argument.allMatches(text)) m.group(1)};
        expect(used, _placeholders[key] ?? <String>{}, reason: '$locale $key');
      }
    });

    test('$locale keep switch reads as aiPhotosSends quotes it', () {
      final arb = _arb(locale);
      final keep = arb['foodAiKeepTitle'] as String;
      expect(arb['aiPhotosSends'] as String, contains(keep));
    });
  }

  test('the id food AI lines use Anda, never kamu or -mu', () {
    final informal = RegExp(r'\bkamu\b|\w+mu\b', caseSensitive: false);
    final id = _arb('id');
    for (final key in _keys.where((k) => k.startsWith('foodAi'))) {
      expect(id[key] as String, isNot(contains(informal)), reason: key);
    }
  });

  test('pt_PT asks for the key in the formal register', () {
    expect(_arb('pt_PT')['aiConsentWhere'] as String, contains('a sua chave'));
  });
}

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
  'aiPhotosTitle',
  'aiPhotosLead',
  'aiPhotosTile',
  'aiPhotosVisionTitle',
  'aiPhotosVisionState',
  'aiPhotosVisionTest',
  'aiPhotosVisionBody',
  'aiPhotosVisionChance',
  'aiPhotosVisionRunning',
  'aiPhotosVisionUnreadable',
  'aiPhotosModelTitle',
  'aiPhotosModelSame',
  'aiPhotosModelClear',
  'aiPhotosLimitTitle',
  'aiPhotosLimitValue',
  'aiPhotosConsentTitle',
  'aiPhotosConsentNone',
  'aiPhotosWithdrawn',
  'aiPhotosSends',
];

const _placeholders = {
  'aiPhotosVisionState': {'state', 'model'},
  'aiPhotosVisionRunning': {'host'},
  'aiPhotosLimitValue': {'count'},
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
  test('the 19 keys are distinct and the en metadata names their '
      'placeholders', () {
    expect(_keys.toSet(), hasLength(19));
    final en = _arb('en');
    for (final key in _keys) {
      final meta = en['@$key'] as Map<String, dynamic>?;
      final names = (meta?['placeholders'] as Map<String, dynamic>?)?.keys;
      expect(names?.toSet() ?? <String>{}, _placeholders[key] ?? <String>{});
    }
  });

  for (final locale in _locales) {
    test('$locale holds the 19 photo keys with the same placeholders and no '
        'dash', () {
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
  }
}

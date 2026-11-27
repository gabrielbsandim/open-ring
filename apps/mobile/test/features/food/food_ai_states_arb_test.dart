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
  'foodAiSectionTitle',
  'foodAiIntro',
  'foodAiAnalyzeThis',
  'foodAiKept',
  'foodAiWaiting',
  'foodAiSending',
  'foodAiMayBill',
  'foodAiNotFood',
  'foodAiRejected',
  'foodAiStopped',
  'foodAiSkipped',
  'foodAiPaused',
  'foodAiAnalyzeAgain',
  'foodAiBy',
  'aiPhotosPausedTitle',
  'aiPhotosPausedBody',
  'aiPhotosResume',
  'aiPhotosExpiry',
];

const _placeholders = {
  'foodAiSending': {'host'},
  'foodAiStopped': {'reason'},
  'foodAiSkipped': {'reason'},
  'foodAiPaused': {'reason'},
  'foodAiBy': {'model', 'date', 'level'},
  'aiPhotosPausedTitle': {'count'},
  'aiPhotosResume': {'count'},
};

const _cases = {
  'foodAiStopped': ['cancelled', 'interrupted', 'other'],
  'foodAiSkipped': [
    'expired',
    'keptOnPhone',
    'noConsent',
    'photoMissing',
    'targetChanged',
    'urlRejected',
    'other',
  ],
  'foodAiPaused': ['noVision', 'noCredit', 'forbidden', 'other'],
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
  test('the 18 A12c keys are distinct and the en metadata names their '
      'placeholders', () {
    expect(_keys.toSet(), hasLength(18));
    final en = _arb('en');
    for (final key in _keys) {
      final meta = en['@$key'] as Map<String, dynamic>?;
      final names = (meta?['placeholders'] as Map<String, dynamic>?)?.keys;
      expect(names?.toSet() ?? <String>{}, _placeholders[key] ?? <String>{});
    }
  });

  for (final locale in _locales) {
    test('$locale holds the 18 A12c keys with the same placeholders, every '
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

    test('$locale skip and pause lines name the labels the screens show', () {
      final arb = _arb(locale);
      final keep = arb['foodAiKeepTitle'] as String;
      expect(arb['foodAiSkipped'] as String, contains(keep));
      final resume = RegExp(r'=0\{([^}]*)\}')
          .firstMatch(arb['aiPhotosResume'] as String)!
          .group(1)!;
      expect(arb['foodAiPaused'] as String, contains(resume));
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

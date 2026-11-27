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
  'foodEnergyTitle',
  'foodEnergyLead',
  'foodEnergyOffTitle',
  'foodEnergyOffBody',
  'foodEnergyNeed',
  'foodEnergyNeedCount',
  'foodEnergyTurnOn',
  'foodEnergyFirst',
  'foodEnergyNever',
  'foodEnergySheetTitle',
  'foodEnergySheetScreened',
  'foodEnergySheetPoints',
  'foodEnergySheetOn',
  'foodEnergyOnDone',
  'foodEnergyOffDone',
  'foodEnergySwitch',
  'foodEnergyScreenFirst',
  'foodEnergyAnswer',
  'foodEnergyBlocked',
  'foodEnergyTileOff',
];

final _dashes = RegExp(
  '[${String.fromCharCode(0x2013)}${String.fromCharCode(0x2014)}]',
);
final _placeholder = RegExp(
  r'\{([A-Za-z][A-Za-z0-9_]*)(?:\}|, ?(select|plural),)',
);

Map<String, dynamic> _arb(String locale) =>
    jsonDecode(File('lib/l10n/app_$locale.arb').readAsStringSync())
        as Map<String, dynamic>;

Set<String> _placeholders(String text) => {
  for (final m in _placeholder.allMatches(text)) m.group(1)!,
};

void main() {
  final en = _arb('en');

  test('the en text of the select keys names every case', () {
    expect(
      en['foodEnergyNeed'],
      startsWith('{need, select, ai{AI analysis on} body{Body on} '),
    );
    for (final block in [
      'bodyOff',
      'softMode',
      'under18',
      'bmiUnderFloor',
      'pregnancy',
      'ageMissing',
      'heightMissing',
      'other',
    ]) {
      expect(en['foodEnergyBlocked'] as String, contains('$block{'));
    }
    expect(en['foodEnergyNeedCount'], '{count} of {total}');
  });

  for (final locale in _locales) {
    test('$locale holds the 20 A13c keys with the en placeholders and no '
        'dash', () {
      final arb = _arb(locale);
      for (final key in _keys) {
        final value = arb[key];
        expect(value, isA<String>(), reason: '$locale $key');
        final text = value as String;
        expect(text, isNotEmpty, reason: '$locale $key');
        expect(text.contains(_dashes), isFalse, reason: '$locale $key');
        expect(
          _placeholders(text),
          _placeholders(en[key] as String),
          reason: '$locale $key',
        );
        expect(text.toLowerCase(), isNot(contains('kcal')));
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

  test('id addresses the reader as Anda, never kamu', () {
    final id = _arb('id');
    expect(id['foodEnergySheetScreened'] as String, contains('Anda'));
    for (final key in _keys) {
      expect(
        id[key] as String,
        isNot(contains(RegExp(r'\bkamu\b', caseSensitive: false))),
        reason: key,
      );
    }
  });
}

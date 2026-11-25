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
  'foodEnergyTag',
  'foodEnergyRange',
  'foodEnergyRangeNote',
  'foodEnergyRing',
  'foodEnergyGapTitle',
  'foodEnergyGap',
  'foodEnergyGapNote',
  'foodEnergyChangeTitle',
  'foodEnergyChange',
  'foodEnergyChangeNote',
  'foodEnergyHoldTitle',
  'foodEnergyHold',
  'foodEnergyLastRange',
  'foodEnergyMath',
  'foodEnergyMathWeight',
  'foodEnergyMathNote',
  'foodEnergyLimits',
  'foodEnergySample',
  'foodFormulaAiBody',
  'foodFormulaEnergyExpr',
];

const _cases = {
  'foodEnergyTag': ['range', 'holding', 'other'],
  'foodEnergyGap': ['under', 'over', 'other'],
  'foodEnergyChange': ['less', 'more', 'other'],
  'foodEnergyHold': [
    'modelChanged',
    'goalStart',
    'weighIns',
    'days',
    'ringDays',
    'other',
  ],
};

final _dashes = RegExp(
  '[${String.fromCharCode(0x2013)}${String.fromCharCode(0x2014)}]',
);

// A case body such as range{range} is not a placeholder.
final _placeholder = RegExp(
  r'(?<![A-Za-z0-9_])\{([A-Za-z][A-Za-z0-9_]*)(?:\}|, ?(select|plural),)',
);

Map<String, dynamic> _arb(String locale) =>
    jsonDecode(File('lib/l10n/app_$locale.arb').readAsStringSync())
        as Map<String, dynamic>;

Set<String> _placeholders(String text) => {
  for (final m in _placeholder.allMatches(text)) m.group(1)!,
};

void main() {
  final en = _arb('en');

  test('the en arithmetic names its twelve placeholders in order', () {
    final meta = en['@foodEnergyMath'] as Map<String, dynamic>;
    expect((meta['placeholders'] as Map).keys, const [
      'from',
      'to',
      'weighIns',
      'days',
      'log',
      'expenditure',
      'ring',
      'factorLow',
      'factorHigh',
      'week',
      'low',
      'high',
    ]);
  });

  for (final locale in _locales) {
    test('$locale holds the 20 A13d keys with the en placeholders, every '
        'case and no dash', () {
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
        for (final c in _cases[key] ?? const <String>[]) {
          expect(text, contains('$c{'), reason: '$locale $key $c');
        }
      }
      expect(
        '\n'.allMatches(arb['foodEnergyMath'] as String),
        hasLength(7),
        reason: locale,
      );
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
    expect(id['foodEnergyLimits'] as String, contains('Anda'));
    for (final key in _keys) {
      expect(
        id[key] as String,
        isNot(contains(RegExp(r'\bkamu\b', caseSensitive: false))),
        reason: key,
      );
    }
  });
}

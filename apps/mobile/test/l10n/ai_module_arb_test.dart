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
  'moduleAiName',
  'moduleAiDetail',
  'moduleAiAdds',
  'moduleAiUses',
  'moduleAiSendsTitle',
  'moduleAiSends',
  'moduleAiStores',
  'moduleAiNever',
  'moduleAiReadingsNone',
  'moduleAiReadingsLast',
  'moduleAiConnection',
  'moduleAiUsageTitle',
  'moduleAiUsage',
  'moduleAiGuideCaption',
  'moduleAiFormulaCaption',
  'moduleAiTurnOn',
  'moduleAiTurnOff',
  'moduleAiTurnOnNote',
  'moduleAiTurnOffNote',
];

const _placeholders = {
  'moduleAiAdds': {'item'},
  'moduleAiUses': {'item'},
  'moduleAiSends': {'item'},
  'moduleAiStores': {'item', 'count', 'days'},
  'moduleAiNever': {'item'},
  'moduleAiReadingsLast': {'date', 'kind'},
  'moduleAiConnection': {'state', 'host', 'model'},
  'moduleAiUsage': {'count', 'tokens'},
};

const _selects = {
  'moduleAiAdds': ['readings', 'goals', 'food', 'other'],
  'moduleAiUses': ['service', 'summary', 'other'],
  'moduleAiSends': ['summary', 'never', 'other'],
  'moduleAiStores': ['config', 'key', 'other'],
  'moduleAiNever': ['today', 'auto', 'score', 'unchecked', 'other'],
  'moduleAiConnection': ['none', 'untested', 'other'],
};

// Flutter reads =1 and one as one branch, so Russian carries one instead.
List<String> _plural(String locale) => locale == 'ru'
    ? const ['=0', 'one', 'few', 'many', 'other']
    : const ['=0', '=1', 'other'];

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
  group('A14b module strings', () {
    test('19 distinct keys, with English placeholder metadata', () {
      expect(_keys.toSet(), hasLength(19));
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
        final usage = arb['moduleAiUsage'] as String;
        for (final name in _plural(locale)) {
          expect(_hasCase(usage, name), isTrue, reason: '$locale usage $name');
        }
        if (locale == 'ru') expect(_hasCase(usage, '=1'), isFalse);
      });
    }
  });
}

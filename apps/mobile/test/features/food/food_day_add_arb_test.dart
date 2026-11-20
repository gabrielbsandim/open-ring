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

const _newKeys = [
  'foodAddPhoto',
  'foodAddWithoutPhoto',
  'foodAddFutureError',
  'foodAddFailed',
];

const List<String> _checkedKeys = [..._newKeys, 'foodDayEmptyBody'];

const _oldEmptyBody = <String, String>{
  'en':
      'Take a photo on Today when you eat. The time comes from the photo '
      'itself, and tags are optional.',
  'de':
      'Mach beim Essen in Heute ein Foto. Die Uhrzeit kommt aus dem Foto '
      'selbst, und Merkmale sind freiwillig.',
  'es':
      'Toma una foto en Hoy a la hora de comer. La hora viene de la propia '
      'foto y las marcas son opcionales.',
  'fr':
      'Prenez une photo dans Aujourd\u2019hui au moment de manger. L\u2019heure '
      'vient de la photo, et les rep\u00e8res sont facultatifs.',
  'id':
      'Ambil foto di Hari ini saat makan. Waktu diambil dari foto itu sendiri, '
      'dan penanda bersifat opsional.',
  'it':
      'Scatta una foto in Oggi quando mangi. L\u2019ora viene dalla foto '
      'stessa e i contrassegni sono facoltativi.',
  'ja':
      '\u98df\u4e8b\u306e\u3068\u304d\u306b\u300c\u4eca\u65e5\u300d\u3067\u5199'
      '\u771f\u3092\u64ae\u3063\u3066\u304f\u3060\u3055\u3044\u3002\u6642\u523b'
      '\u306f\u5199\u771f\u304b\u3089\u8aad\u307f\u53d6\u3089\u308c\u3001'
      '\u30bf\u30b0\u306f\u4efb\u610f\u3067\u3059\u3002',
  'pt':
      'Tire uma foto em Hoje na hora de comer. A hora vem da pr\u00f3pria '
      'foto, e as marcas s\u00e3o opcionais.',
  'pt_PT':
      'Tire uma foto em Hoje na hora de comer. A hora vem da pr\u00f3pria '
      'foto, e as marcas s\u00e3o opcionais.',
  'ru':
      '\u0421\u0434\u0435\u043b\u0430\u0439\u0442\u0435 \u0444\u043e\u0442\u043e '
      '\u043d\u0430 \u0432\u043a\u043b\u0430\u0434\u043a\u0435 '
      '\u00ab\u0421\u0435\u0433\u043e\u0434\u043d\u044f\u00bb \u0432\u043e '
      '\u0432\u0440\u0435\u043c\u044f \u0435\u0434\u044b. '
      '\u0412\u0440\u0435\u043c\u044f \u0431\u0435\u0440\u0451\u0442\u0441\u044f '
      '\u0438\u0437 \u0441\u0430\u043c\u043e\u0433\u043e '
      '\u0444\u043e\u0442\u043e, \u0430 \u043c\u0435\u0442\u043a\u0438 '
      '\u043d\u0435\u043e\u0431\u044f\u0437\u0430\u0442\u0435\u043b\u044c\u043d\u044b.',
  'zh':
      '\u7528\u9910\u65f6\u5728\u201c\u4eca\u5929\u201d\u62cd\u7167\u3002'
      '\u65f6\u95f4\u6765\u81ea\u7167\u7247\u672c\u8eab\uff0c\u6807\u8bb0'
      '\u4e3a\u53ef\u9009\u9879\u3002',
};

final _dashes = RegExp(
  '[${String.fromCharCode(0x2013)}${String.fromCharCode(0x2014)}]',
);

final _placeholder = RegExp(r'\{\w+\}');

Map<String, dynamic> _arb(String locale) =>
    jsonDecode(File('lib/l10n/app_$locale.arb').readAsStringSync())
        as Map<String, dynamic>;

List<String> _missing(Map<String, dynamic> arb) => [
  for (final key in _checkedKeys)
    if (arb[key] is! String || (arb[key] as String).trim().isEmpty) key,
];

void main() {
  group('criterion 7: food add ARB keys and updated foodDayEmptyBody', () {
    for (final locale in _locales) {
      test('$locale holds the 4 new add keys and foodDayEmptyBody, each '
          'non-empty', () {
        expect(_missing(_arb(locale)), isEmpty);
      });

      test('$locale has no en dash, em dash, or placeholders in the 5 '
          'checked keys', () {
        final arb = _arb(locale);
        expect(_missing(arb), isEmpty);
        final dashed = [
          for (final key in _checkedKeys)
            if ((arb[key] as String).contains(_dashes)) key,
        ];
        final withPlaceholders = [
          for (final key in _checkedKeys)
            if ((arb[key] as String).contains(_placeholder)) key,
        ];
        expect(dashed, isEmpty);
        expect(withPlaceholders, isEmpty);
      });

      test('$locale updated foodDayEmptyBody away from the F6a wording', () {
        final arb = _arb(locale);
        expect(_missing(arb), isEmpty);
        expect(arb['foodDayEmptyBody'], isNot(_oldEmptyBody[locale]));
      });
    }

    test('English strings match the spec', () {
      final en = _arb('en');
      expect(_missing(en), isEmpty);
      expect(en['foodAddPhoto'], 'Photo');
      expect(en['foodAddWithoutPhoto'], 'Without photo');
      expect(en['foodAddFutureError'], 'The meal time cannot be in the future');
      expect(en['foodAddFailed'], 'Could not save the meal');
      expect(
        en['foodDayEmptyBody'],
        'Tap Photo when you eat. The time comes from the photo itself, and '
        'tags are optional.',
      );
    });
  });
}

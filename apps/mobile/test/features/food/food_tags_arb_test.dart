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
  'foodKindLabel',
  'foodKindMain',
  'foodKindSnack',
  'foodKindDrink',
  'foodProteinLabel',
  'foodProtein',
  'foodVegLabel',
  'foodVegSome',
  'foodVegHalf',
  'foodAlcoholLabel',
  'foodAlcoholOneToTwo',
  'foodAlcoholThreeOrMore',
  'foodCaffeineLabel',
  'foodCaffeine',
  'foodHeavyLabel',
  'foodHeavy',
  'foodFriedLabel',
  'foodFried',
  'foodSugarLabel',
  'foodSugar',
  'foodProcessedLabel',
  'foodProcessedMostly',
  'foodProcessedUnsure',
  'foodPlaceLabel',
  'foodPlaceHome',
  'foodPlaceRestaurant',
  'foodPlacePackaged',
];

const List<String> _keys = [..._newKeys, 'foodSavedNote'];

// The F5a text of foodSavedNote, which D6 replaces in every locale.
const _oldSavedNote = <String, String>{
  'en': 'It is already saved. Closing keeps it too.',
  'de': 'Sie ist schon gespeichert. Auch Schließen behält sie.',
  'es': 'Ya está guardada. Cerrar también la guarda.',
  'fr': 'C’est déjà enregistré. Fermer le garde aussi.',
  'id': 'Sudah tersimpan. Menutup juga tetap menyimpannya.',
  'it': 'È già salvato. Anche chiudere lo conserva.',
  'ja': '保存済みです。閉じても残ります。',
  'pt': 'Já está salva. Fechar também guarda.',
  'pt_PT': 'Já está guardada. Fechar também guarda.',
  'ru': 'Уже сохранено. Если закрыть, запись тоже останется.',
  'zh': '已经保存。关闭也会保留。',
};

final _dashes = RegExp(
  '[${String.fromCharCode(0x2013)}${String.fromCharCode(0x2014)}]',
);

Map<String, dynamic> _arb(String locale) =>
    jsonDecode(File('lib/l10n/app_$locale.arb').readAsStringSync())
        as Map<String, dynamic>;

List<String> _missing(Map<String, dynamic> arb) => [
  for (final key in _keys)
    if (arb[key] is! String || (arb[key] as String).trim().isEmpty) key,
];

void main() {
  group('criterion 9: the kind and tag strings', () {
    for (final locale in _locales) {
      test('$locale holds the 28 keys, each with a text', () {
        expect(_newKeys.toSet(), hasLength(27), reason: 'the spec list');
        expect(_keys.toSet(), hasLength(28), reason: 'the spec list');
        expect(_missing(_arb(locale)), isEmpty);
      });
    }

    for (final locale in _locales) {
      test('$locale has no en dash or em dash in the 28 keys', () {
        final arb = _arb(locale);
        expect(_missing(arb), isEmpty, reason: 'new strings');
        final offenders = [
          for (final key in _keys)
            if ((arb[key] as String).contains(_dashes)) key,
        ];
        expect(offenders, isEmpty);
      });
    }

    for (final locale in _locales) {
      test('$locale changes foodSavedNote from the F5a text', () {
        final note = _arb(locale)['foodSavedNote'];
        expect(note, isA<String>());
        expect(note, isNot(_oldSavedNote[locale]));
      });
    }

    test('English foodSavedNote says tags are optional', () {
      expect(
        _arb('en')['foodSavedNote'],
        'It is already saved. Tags are optional; closing keeps them too.',
      );
    });

    test('the 28 keys carry no placeholder in any locale', () {
      expect(_missing(_arb('en')), isEmpty, reason: 'English first');
      final placeholder = RegExp(r'\{\w+\}');
      final found = [
        for (final locale in _locales)
          for (final key in _keys)
            if ('${_arb(locale)[key]}'.contains(placeholder)) '$locale $key',
      ];
      expect(found, isEmpty);
    });
  });
}

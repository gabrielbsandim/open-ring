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
  'workoutNotificationsOffTitle',
  'workoutNotificationsOffBody',
  'workoutNotificationsAllow',
  'permissionsNotificationsWhy',
];

const _oldWhy = {
  'en': 'To tell you when the ring battery is low or a sync fails.',
  'de':
      'Um dir zu sagen, wenn der Akku des Rings schwach ist oder eine '
      'Synchronisierung fehlschlägt.',
  'es':
      'Para avisarte cuando la batería del anillo esté baja o falle una '
      'sincronización.',
  'fr':
      "Pour vous prévenir quand la batterie de la bague est faible ou qu'une "
      'synchronisation échoue.',
  'id': 'Untuk memberi tahu saat baterai cincin lemah atau sinkronisasi gagal.',
  'it':
      "Per avvisarti quando la batteria dell'anello è scarica o una "
      'sincronizzazione non riesce.',
  'ja': 'リングの電池残量が少ないときや同期に失敗したときにお知らせします。',
  'pt':
      'Para avisar quando a bateria do anel estiver baixa ou quando uma '
      'sincronização falhar.',
  'pt_PT':
      'Para avisar quando a bateria do anel estiver fraca ou uma '
      'sincronização falhar.',
  'ru':
      'Чтобы сообщать, когда батарея кольца разряжается или синхронизация '
      'не удалась.',
  'zh': '在戒指电量低或同步失败时提醒你。',
};

final _dashes = RegExp(
  '[${String.fromCharCode(0x2013)}${String.fromCharCode(0x2014)}]',
);

Map<String, dynamic> _arb(String locale) =>
    jsonDecode(File('lib/l10n/app_$locale.arb').readAsStringSync())
        as Map<String, dynamic>;

void main() {
  group('11. the notifications off strings', () {
    for (final locale in _locales) {
      test('$locale holds the 4 keys, each with a text and no dash', () {
        final arb = _arb(locale);
        final missing = [
          for (final key in _keys)
            if (arb[key] is! String || (arb[key] as String).trim().isEmpty) key,
        ];
        final dashed = [
          for (final key in _keys)
            if ('${arb[key]}'.contains(_dashes)) key,
        ];
        expect(missing, isEmpty);
        expect(dashed, isEmpty);
      });

      test('$locale carries the new notifications reason', () {
        expect(
          _arb(locale)['permissionsNotificationsWhy'],
          isNot(_oldWhy[locale]),
        );
      });
    }

    test('English and Portuguese read as the spec says', () {
      final en = _arb('en');
      final pt = _arb('pt');
      expect(en['workoutNotificationsOffTitle'], 'Notifications off');
      expect(en['workoutNotificationsAllow'], 'Allow notifications');
      expect(pt['workoutNotificationsOffTitle'], 'Notificações desligadas');
      expect(pt['workoutNotificationsAllow'], 'Permitir notificações');
    });
  });
}

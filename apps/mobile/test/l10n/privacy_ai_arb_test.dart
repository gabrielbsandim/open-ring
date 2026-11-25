import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/ai/domain/ai_config.dart';

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
  'privacyStoresAi',
  'privacyStoresAiWhy',
  'privacyStoresAiKey',
  'privacyStoresAiKeyWhy',
  'privacyStoresMealAi',
  'privacyStoresMealAiWhy',
  'privacyAiHeading',
  'privacyAiSends',
  'privacyAiNever',
  'privacyAiPhotos',
  'privacyAiProvider',
  'privacyAiLocal',
  'privacyDeleteAi',
];

const _changed = [
  'privacyEffective',
  'privacyShortInternet',
  'privacyShortLeaves',
  'exportIntro',
  'moduleBodyStoresLocal',
  'moduleFoodNeverUploads',
  'settingsDeleteBody',
];

// Each value must name the module or button as that locale already calls it.
const _names = {
  'privacyStoresAi': ['moduleAiName'],
  'privacyStoresMealAi': ['moduleAiName', 'foodEnergyTitle'],
  'privacyAiSends': ['moduleAiName'],
  'privacyAiPhotos': ['foodAiAnalyze'],
  'privacyDeleteAi': ['moduleAiDelete', 'moduleAiName'],
  'privacyShortInternet': ['moduleAiName'],
  'moduleBodyStoresLocal': ['moduleAiName'],
  'moduleFoodNeverUploads': ['moduleAiName', 'foodAiAnalyze'],
};

final _dashes = RegExp(
  '[${String.fromCharCode(0x2013)}${String.fromCharCode(0x2014)}]',
);

Map<String, dynamic> _arb(String locale) =>
    jsonDecode(File('lib/l10n/app_$locale.arb').readAsStringSync())
        as Map<String, dynamic>;

void main() {
  group('A14d privacy strings', () {
    test('13 distinct new keys and 7 changed values', () {
      expect(_keys.toSet(), hasLength(13));
      expect(_changed.toSet(), hasLength(7));
    });

    for (final locale in _locales) {
      test('$locale holds every key, names the module and keeps the date', () {
        final arb = _arb(locale);
        for (final key in [..._keys, ..._changed]) {
          final text = arb[key] as String;
          expect(text.trim(), isNotEmpty, reason: '$locale $key');
          expect(text.contains(_dashes), isFalse, reason: '$locale $key');
          for (final name in _names[key] ?? const <String>[]) {
            expect(text, contains(arb[name] as String), reason: '$locale $key');
          }
        }
        for (final key in _keys) {
          expect(arb[key], isNot(contains('{')), reason: '$locale $key');
        }
        expect(arb['privacyAiHeading'], arb['moduleAiName']);
        expect(arb['privacyEffective'], contains(aiCurrentPolicyEffectiveDate));
        expect(arb['settingsDeleteBody'], contains('{platform}'));
      });

      test('$locale no longer says the internet is only for updates', () {
        final arb = _arb(locale);
        expect(arb['privacyShortInternet'], isNot(_internetBefore[locale]));
        expect(arb['moduleFoodNeverUploads'], isNot(_photosBefore[locale]));
        final all = arb.values.whereType<String>();
        expect(all, isNot(contains(_internetBefore[locale])));
      });
    }
  });
}

// The pre A14d values, which the AI analysis module made false.
const _internetBefore = {
  'en': 'The app uses the internet for one thing only: checking for and downloading app updates. Your health data never goes over the network.',
  'de': 'Die App nutzt das Internet nur für eines: um nach App-Updates zu suchen und sie herunterzuladen. Deine Gesundheitsdaten gehen nie über das Netzwerk.',
  'es': 'La app usa internet para una sola cosa: buscar y descargar actualizaciones de la app. Tus datos de salud nunca pasan por la red.',
  'fr': "L'application n'utilise internet que pour une chose : rechercher et télécharger ses mises à jour. Vos données de santé ne passent jamais par le réseau.",
  'id': 'Aplikasi memakai internet hanya untuk satu hal: memeriksa dan mengunduh pembaruan aplikasi. Data kesehatan Anda tidak pernah melewati jaringan.',
  'it': "L'app usa internet per una sola cosa: cercare e scaricare gli aggiornamenti dell'app. I tuoi dati sanitari non passano mai dalla rete.",
  'ja': 'アプリがインターネットを使うのは、アプリのアップデートの確認とダウンロードのときだけです。健康データがネットワークを通ることはありません。',
  'pt': 'O app usa a internet para uma única coisa: verificar e baixar atualizações do app. Os seus dados de saúde nunca passam pela rede.',
  'pt_PT': 'A app usa a internet para uma única coisa: verificar e transferir atualizações da app. Os seus dados de saúde nunca passam pela rede.',
  'ru': 'Приложение использует интернет только для одного: проверять и загружать свои обновления. Ваши данные о здоровье никогда не передаются по сети.',
  'zh': '应用仅在一件事上使用互联网：检查并下载应用更新。您的健康数据绝不会经过网络。',
};

const _photosBefore = {
  'en': 'Your meal photos and tags never leave this phone.',
  'de': 'Deine Mahlzeitenfotos und Markierungen verlassen niemals dieses Telefon.',
  'es': 'Tus fotos de comidas y etiquetas nunca salen de este teléfono.',
  'fr': 'Vos photos de repas et étiquettes ne quittent jamais ce téléphone.',
  'id': 'Foto makan dan tag Anda tidak pernah keluar dari ponsel ini.',
  'it':
      'Le foto dei tuoi pasti e le etichette non lasciano mai questo telefono.',
  'ja': '食事写真やタグがこの端末の外に送信されることはありません。',
  'pt': 'Suas fotos de refeições e etiquetas nunca saem deste telefone.',
  'pt_PT': 'As tuas fotos e etiquetas nunca saem deste telemóvel.',
  'ru': 'Фотографии еды и теги никогда не покидают этот телефон.',
  'zh': '你的餐食照片和标签永远不会离开这台手机。',
};

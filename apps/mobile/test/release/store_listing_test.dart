import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const metadataRoot = 'fastlane/metadata/android';

const storeLocales = {
  'en-US',
  'pt-BR',
  'pt-PT',
  'es-ES',
  'fr-FR',
  'de-DE',
  'it-IT',
  'ru-RU',
  'zh-CN',
  'ja-JP',
  'id',
};

const limits = {
  'title.txt': 30,
  'short_description.txt': 80,
  'full_description.txt': 4000,
};

String readListing(String locale, String file) =>
    File('$metadataRoot/$locale/$file').readAsStringSync().trimRight();

void main() {
  test('ships one listing folder per app locale', () {
    final folders = Directory(metadataRoot)
        .listSync()
        .whereType<Directory>()
        .map((dir) => dir.uri.pathSegments.lastWhere((s) => s.isNotEmpty))
        .toSet();
    expect(folders, storeLocales);
  });

  for (final locale in storeLocales) {
    group(locale, () {
      for (final MapEntry(key: file, value: limit) in limits.entries) {
        test('$file is filled and at most $limit characters', () {
          final text = readListing(locale, file);
          expect(text, isNotEmpty);
          expect(text.runes.length, lessThanOrEqualTo(limit));
        });

        test('$file has no em or en dash', () {
          final text = readListing(locale, file);
          expect(text.contains(String.fromCharCode(0x2014)), isFalse);
          expect(text.contains(String.fromCharCode(0x2013)), isFalse);
        });
      }

      test('title is the app name', () {
        expect(readListing(locale, 'title.txt'), 'OpenRing');
      });
    });
  }
}

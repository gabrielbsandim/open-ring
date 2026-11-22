import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/ai/domain/secret_store.dart';
import 'package:open_ring/features/ai/infrastructure/secure_storage_secret_store.dart';
import 'package:xml/xml.dart';

final class _FakeFlutterSecureStorage extends FlutterSecureStorage {
  new();

  final Map<String, String> values = {};
  Object? readError;
  Object? deleteError;
  int deleteCalls = 0;

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (readError != null) {
      Error.throwWithStackTrace(readError!, StackTrace.current);
    }
    return values[key];
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      values.remove(key);
      return;
    }
    values[key] = value;
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    deleteCalls++;
    if (deleteError != null) {
      Error.throwWithStackTrace(deleteError!, StackTrace.current);
    }
    values.remove(key);
  }
}

void main() {
  group('SecureStorageSecretStore', () {
    test(
      'uses default v11 AndroidOptions without encryptedSharedPreferences',
      () {
        const store = SecureStorageSecretStore();
        final map = store.androidOptions.toMap();
        expect(
          map['keyCipherAlgorithm'],
          'RSA_ECB_OAEPwithSHA_256andMGF1Padding',
        );
        expect(map['storageCipherAlgorithm'], 'AES_GCM_NoPadding');
        expect(map['enforceBiometrics'], 'false');
        expect(map.containsKey('encryptedSharedPreferences'), isFalse);
      },
    );

    test('reads, writes, and deletes keys cleanly', () async {
      final plugin = _FakeFlutterSecureStorage();
      final store = SecureStorageSecretStore(plugin);

      expect(await store.read(aiApiKeySecretName), isNull);
      await store.write(aiApiKeySecretName, 'sk-secret-1234');
      expect(await store.read(aiApiKeySecretName), 'sk-secret-1234');

      await store.delete(aiApiKeySecretName);
      expect(plugin.deleteCalls, 1);
      expect(await store.read(aiApiKeySecretName), isNull);
    });

    test(
      'deletes corrupted entry once and returns null on keystore error',
      () async {
        final plugin = _FakeFlutterSecureStorage()
          ..values[aiApiKeySecretName] = 'corrupt-ciphertext'
          ..readError = PlatformException(
            code: 'read_failed',
            message: 'BadPaddingException: Failed to unwrap key',
          );
        final store = SecureStorageSecretStore(plugin);

        expect(await store.read(aiApiKeySecretName), isNull);
        expect(plugin.deleteCalls, 1);
        expect(plugin.values.containsKey(aiApiKeySecretName), isFalse);

        plugin.deleteError = StateError('delete also failed');
        expect(await store.read(aiApiKeySecretName), isNull);
        expect(plugin.deleteCalls, 2);
      },
    );
  });

  group('Secret storage security invariants', () {
    test('only secure_storage_secret_store imports flutter_secure_storage', () {
      final importers = <String>[];
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final text = entity.readAsStringSync();
        if (text.contains('package:flutter_secure_storage/')) {
          importers.add(entity.path.replaceAll(r'\', '/'));
        }
      }
      expect(importers, [
        'lib/features/ai/infrastructure/secure_storage_secret_store.dart',
      ]);
    });

    test(
      'AndroidManifest and dataExtractionRules exclude backups and keys',
      () {
        final manifest = XmlDocument.parse(
          File('android/app/src/main/AndroidManifest.xml').readAsStringSync(),
        );
        final app = manifest.findAllElements('application').single;
        expect(app.getAttribute('android:allowBackup'), 'false');
        expect(
          app.getAttribute('android:dataExtractionRules'),
          '@xml/data_extraction_rules',
        );

        final rules = XmlDocument.parse(
          File('android/app/src/main/res/xml/data_extraction_rules.xml')
              .readAsStringSync(),
        );
        final cloudExcludes = rules
            .findAllElements('cloud-backup')
            .single
            .findElements('exclude')
            .map((e) => (e.getAttribute('domain'), e.getAttribute('path')))
            .toSet();
        expect(cloudExcludes, const {
          ('root', '.'),
          ('file', '.'),
          ('database', '.'),
          ('sharedpref', '.'),
          ('external', '.'),
        });

        final transferExcludes = rules
            .findAllElements('device-transfer')
            .single
            .findElements('exclude')
            .map((e) => (e.getAttribute('domain'), e.getAttribute('path')))
            .toSet();
        expect(transferExcludes, const {
          ('sharedpref', 'FlutterSecureStorage.xml'),
          ('sharedpref', 'FlutterSecureKeyStorage.xml'),
          (
            'sharedpref',
            'FlutterSecureStorageConfiguration:FlutterSecureStorage.xml',
          ),
          ('sharedpref', 'FlutterSecureStorageConfiguration.xml'),
        });
      },
    );
  });
}

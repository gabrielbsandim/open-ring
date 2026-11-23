import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/ai/domain/ai_config.dart';
import 'package:open_ring/features/ai/domain/ai_wire_types.dart';
import 'package:open_ring/features/ai/domain/secret_store.dart';
import 'package:open_ring/features/ai/infrastructure/shared_preferences_ai_config_store.dart';
import 'package:open_ring/features/food/domain/photo_store.dart';
import 'package:open_ring/features/settings/infrastructure/device_local_data_eraser.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import '../../../helpers/ai_fakes.dart';
import '../../../helpers/database.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.withData({'some_plugin_key': 'kept'});
  });

  test('the allow list covers every AI preference key', () {
    expect(
      DeviceLocalDataEraser.preferenceKeys,
      containsAll(SharedPreferencesAiConfigStore.keys),
    );
  });

  test('deletes the API key and every ai_ preference', () async {
    final secrets = InMemorySecretStore();
    await secrets.write(aiApiKeySecretName, 'sk-secret');
    final store = SharedPreferencesAiConfigStore();
    await store.writeConfig(const AiConfig(baseUrl: 'https://a.example'));
    await store.writeCapabilityProfile('h', 'm', AiCapabilityProfile.defaults);

    await DeviceLocalDataEraser(
      await pairedDatabase(),
      InMemoryPhotoStore(),
      secrets: secrets,
    ).eraseAll();

    expect(await secrets.read(aiApiKeySecretName), isNull);
    expect(await SharedPreferencesAsync().getKeys(), {'some_plugin_key'});
  });

  test('a keystore failure still erases the rest and fails the run', () async {
    final db = await pairedDatabase();
    final secrets = FailingSecretStore(
      failDelete: true,
      error: PlatformException(code: 'keystore'),
    );
    await SharedPreferencesAiConfigStore().writeConfig(AiConfig.defaults);

    await expectLater(
      DeviceLocalDataEraser(
        db,
        InMemoryPhotoStore(),
        secrets: secrets,
      ).eraseAll(),
      throwsA(isA<PlatformException>()),
    );
    expect(secrets.deleteCalls, 1);
    expect(await SharedPreferencesAsync().getKeys(), {'some_plugin_key'});
    for (final table in db.allTables) {
      expect(await rowCount(db, table.actualTableName), 0);
    }
  });
}

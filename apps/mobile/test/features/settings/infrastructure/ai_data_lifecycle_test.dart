import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/ai/domain/ai_config.dart';
import 'package:open_ring/features/ai/domain/ai_wire_types.dart';
import 'package:open_ring/features/ai/domain/secret_store.dart';
import 'package:open_ring/features/ai/infrastructure/drift_ai_report_store.dart';
import 'package:open_ring/features/ai/infrastructure/shared_preferences_ai_config_store.dart';
import 'package:open_ring/features/ai/infrastructure/shared_preferences_ai_run_marker_store.dart';
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
    expect(
      DeviceLocalDataEraser.preferenceKeys,
      containsAll(SharedPreferencesAiRunMarkerStore.keys),
    );
  });

  test('deletes the API key and every ai_ preference', () async {
    final secrets = InMemorySecretStore();
    await secrets.write(aiApiKeySecretName, 'sk-secret');
    final store = SharedPreferencesAiConfigStore();
    await store.writeConfig(const AiConfig(baseUrl: 'https://a.example'));
    await store.writeCapabilityProfile('h', 'm', AiCapabilityProfile.defaults);
    final markers = SharedPreferencesAiRunMarkerStore();
    await markers.write(sampleAiReport(at: DateTime.utc(2026, 11, 20)));
    await markers.addMonthTokens('2026-11', 150);

    await DeviceLocalDataEraser(
      await pairedDatabase(),
      InMemoryPhotoStore(),
      secrets: secrets,
    ).eraseAll();

    expect(await secrets.read(aiApiKeySecretName), isNull);
    expect(await SharedPreferencesAsync().getKeys(), {'some_plugin_key'});
  });

  test('Delete all data removes ai_photo_day_uses and '
      'ai_photo_queue_pause', () async {
    await SharedPreferencesAiRunMarkerStore().addPhotoUses('2026-11-24', 3);
    await SharedPreferencesAiConfigStore().writePhotoQueuePause(
      const AiPhotoQueuePause(
        reason: AiPhotoQueuePauseReason.unauthorized,
        hostKey: 'https://api.example.com:443',
        model: 'vision-m',
        keyLastFour: '1234',
        atUtcMs: 1,
      ),
    );
    final prefs = SharedPreferencesAsync();
    expect(
      await prefs.getKeys(),
      containsAll(['ai_photo_day_uses', 'ai_photo_queue_pause']),
    );

    await DeviceLocalDataEraser(
      await pairedDatabase(),
      InMemoryPhotoStore(),
      secrets: InMemorySecretStore(),
    ).eraseAll();

    expect(await prefs.getKeys(), {'some_plugin_key'});
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

  test('Delete all data empties ai_reports', () async {
    final db = await pairedDatabase();
    await DriftAiReportStore(db)
        .insert(sampleAiReport(at: DateTime.utc(2026, 11, 23)));
    expect(await rowCount(db, 'ai_reports'), 1);

    await DeviceLocalDataEraser(
      db,
      InMemoryPhotoStore(),
      secrets: InMemorySecretStore(),
    ).eraseAll();

    expect(await rowCount(db, 'ai_reports'), 0);
  });
}

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/core/database/app_database.dart';
import 'package:open_ring/core/database/app_database_provider.dart';
import 'package:open_ring/core/records/health_record_kind.dart';
import 'package:open_ring/features/health_sync/application/health_sync_controller.dart';
import 'package:open_ring/features/health_sync/infrastructure/health_outbox_dao.dart';
import 'package:open_ring/features/ring/application/ring_sync_controller.dart';
import 'package:open_ring/features/ring/infrastructure/drift_sync_store.dart';
import 'package:open_ring/features/ring/infrastructure/sync_locks_dao.dart';

import '../../../helpers/database.dart';
import '../../../helpers/fake_health_writer.dart';
import '../../../helpers/fake_ring_driver.dart';
import '../../../helpers/sync_fixtures.dart';

ProviderContainer containerFor(
  AppDatabase db, {
  FakeHealthWriter? writer,
  FakeRingDriver? driver,
}) {
  final container = ProviderContainer(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      clockProvider.overrideWithValue(() => syncNow),
      syncClockProvider.overrideWithValue(() => syncNow),
      syncStoreProvider.overrideWithValue(DriftSyncStore(db)),
      syncLockProvider.overrideWithValue(SyncLocksDao(db)),
      smartRingDriverProvider.overrideWithValue(driver ?? loadedDriver()),
      if (writer != null) healthWriterProvider.overrideWithValue(writer),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('a completed ring sync writes the outbox in the background', () async {
    final db = await pairedDatabase();
    final writer = FakeHealthWriter();
    final container = containerFor(db, writer: writer);

    await container.read(ringSyncProvider.notifier).sync();
    await container.read(healthSyncProvider.notifier).process();

    expect(writer.entriesOf(HealthRecordKind.sleep), hasLength(1));
    expect(await HealthOutboxDao(db).pending(), isEmpty);
    final state = container.read(healthSyncProvider);
    expect(state.lastRunAt, syncNow);
    expect(state.blocked, isFalse);
  });

  test('a denied kind is exposed as blocked and its rows wait', () async {
    final db = await pairedDatabase();
    final writer = FakeHealthWriter()..denied.add(HealthRecordKind.sleep);
    final container = containerFor(db, writer: writer);
    await container.read(ringSyncProvider.notifier).sync();

    await container.read(healthSyncProvider.notifier).process();

    final state = container.read(healthSyncProvider);
    expect(state.denied, {HealthRecordKind.sleep});
    expect(state.blocked, isTrue);
    expect((await HealthOutboxDao(db).pending()).map((r) => r.kind), [
      HealthRecordKind.sleep,
    ]);
  });

  test('requesting access asks for every writable kind, then writes', () async {
    final db = await pairedDatabase();
    final writer = FakeHealthWriter()..denied.addAll(HealthRecordKind.values);
    final container = containerFor(db, writer: writer);
    await container.read(ringSyncProvider.notifier).sync();
    await container.read(healthSyncProvider.notifier).process();

    final granted = await container
        .read(healthSyncProvider.notifier)
        .requestAccess();

    expect(granted, isTrue);
    expect(writer.requests.single, isNot(contains(HealthRecordKind.stress)));
    expect(writer.requests.single, contains(HealthRecordKind.workout));
    expect(container.read(healthSyncProvider).blocked, isFalse);
    expect(await HealthOutboxDao(db).pending(), isEmpty);
  });

  test(
    'a processor that cannot start ends with an error, not a throw',
    () async {
      final container = containerFor(await pairedDatabase());

      await container.read(healthSyncProvider.notifier).process();

      final state = container.read(healthSyncProvider);
      expect(state.running, isFalse);
      expect(state.lastError, contains('healthWriterProvider'));
    },
  );
}

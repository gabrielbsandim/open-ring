import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/core/database/app_database.dart';
import 'package:open_ring/core/records/record_kind.dart';
import 'package:open_ring/features/ring/application/sync_paired_ring.dart';
import 'package:open_ring/features/ring/domain/auto_measurements.dart';
import 'package:open_ring/features/ring/domain/sync_run.dart';
import 'package:open_ring/features/ring/infrastructure/drift_sync_store.dart';
import 'package:ring_driver/ring_driver.dart';

import '../../../helpers/database.dart';
import '../../../helpers/fake_ring_driver.dart';
import '../../../helpers/ring_fakes.dart';
import '../../../helpers/sync_fixtures.dart';

void main() {
  late AppDatabase db;
  late FakeRingDriver driver;
  late DriftSyncStore store;

  setUp(() async {
    db = await pairedDatabase();
    driver = loadedDriver();
    store = DriftSyncStore(db);
  });

  SyncPairedRing syncer() => SyncPairedRing(
    driver: driver,
    store: store,
    lock: InMemorySyncLock(),
    clock: () => syncNow,
  );

  test('a completed sync is logged with its kinds and records', () async {
    final outcome = await syncer()();

    expect(outcome, isA<SyncCompleted>());
    final run = (await store.recentRuns(ringId)).single;
    expect(run.outcome, SyncRunOutcome.completed);
    expect(run.at, syncNow);
    expect(run.kinds, RecordKind.values.toSet());
    expect(run.recordCount, 13);
  });

  test(
    'a connect that never answers ends the run and frees the lock',
    () async {
      driver.connectGate = Completer<void>();
      final lock = InMemorySyncLock();

      final outcome = await SyncPairedRing(
        driver: driver,
        store: store,
        lock: lock,
        clock: () => syncNow,
        runTimeout: const Duration(milliseconds: 10),
      )();

      expect(outcome, isA<SyncFailed>());
      expect(driver.disconnects, greaterThan(0));
      final run = (await store.recentRuns(ringId)).single;
      expect(run.outcome, SyncRunOutcome.unreachable);
      final free = await lock.acquire(
        'next',
        at: syncNow,
        timeout: const Duration(minutes: 1),
      );
      expect(free, isTrue);
    },
  );

  test('a capability failure is logged as partial', () async {
    driver.failing[RingCapability.hrv] = StateError('nope');

    await syncer()();

    final run = (await store.recentRuns(ringId)).single;
    expect(run.outcome, SyncRunOutcome.partial);
    expect(run.kinds, isNot(contains(RecordKind.hrv)));
    expect(run.failures, {RingCapability.hrv});
  });

  test('a run logs the battery and the interval the ring had', () async {
    await syncer()();

    final run = (await store.recentRuns(ringId)).single;
    expect(run.battery?.percent, driver.battery.percent);
    expect(run.heartRateIntervalSeen, const Duration(minutes: 30));
  });

  test('a ring out of reach is logged as unreachable', () async {
    driver.connectError = StateError('GATT_ERROR 133');

    final outcome = await syncer()();

    expect(outcome, isA<SyncFailed>());
    final run = (await store.recentRuns(ringId)).single;
    expect(run.outcome, SyncRunOutcome.unreachable);
    expect(run.failed, isTrue);
  });

  test('a sync stopped after connecting is logged as stopped', () async {
    driver.syncTimeError = StateError('timeout');

    await syncer()();

    expect(
      (await store.recentRuns(ringId)).single.outcome,
      SyncRunOutcome.stopped,
    );
  });

  test('applies the stored measurement choice to the ring', () async {
    await store.saveMeasurements(
      ringId,
      const AutoMeasurements(off: {AutoMeasurement.spo2}),
    );

    await syncer()();

    expect(driver.monitors[RingMonitor.spo2], isFalse);
  });

  test('a forgotten ring is not synced', () async {
    await store.forget(ringId, at: syncNow);

    final outcome = await syncer()();

    expect(outcome, isA<NothingPaired>());
    expect(driver.connects, 0);
  });
}

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/core/database/app_database.dart';
import 'package:open_ring/core/records/data_revision.dart';
import 'package:open_ring/core/records/record_kind.dart';
import 'package:open_ring/features/ring/application/ring_sync_controller.dart';
import 'package:open_ring/features/ring/application/ring_sync_state.dart';
import 'package:open_ring/features/ring/infrastructure/drift_sync_store.dart';
import 'package:open_ring/features/ring/infrastructure/ring_devices_dao.dart';
import 'package:open_ring/features/ring/infrastructure/sync_locks_dao.dart';
import 'package:ring_driver/ring_driver.dart';

import '../../../helpers/database.dart';
import '../../../helpers/fake_ring_driver.dart';
import '../../../helpers/sync_fixtures.dart';

class Harness {
  new(this.db, this.driver, {Stream<void>? finished}) {
    container = ProviderContainer(
      overrides: [
        syncStoreProvider.overrideWithValue(DriftSyncStore(db)),
        syncLockProvider.overrideWithValue(SyncLocksDao(db)),
        smartRingDriverProvider.overrideWithValue(driver),
        syncClockProvider.overrideWithValue(() => syncNow),
        backgroundSyncFinishedProvider.overrideWithValue(
          finished ?? const Stream.empty(),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.listen(
      ringSyncProvider,
      (_, next) => states.add(next),
      fireImmediately: true,
    );
  }

  final AppDatabase db;
  final FakeRingDriver driver;
  final states = <RingSyncState>[];
  late final ProviderContainer container;

  RingSyncState get state => container.read(ringSyncProvider);

  Future<void> sync() => container.read(ringSyncProvider.notifier).sync();

  Future<void> refresh() => container.read(ringSyncProvider.notifier).refresh();

  Future<void> autoSync() =>
      container.read(ringSyncProvider.notifier).autoSync();

  int get revision => container.read(dataRevisionProvider);
}

void main() {
  Future<Harness> paired() async =>
      Harness(await pairedDatabase(), loadedDriver());

  test('starts idle with no error', () async {
    final h = await paired();

    expect(h.state.syncing, isFalse);
    expect(h.state.lastError, isNull);
  });

  test('reports each step and ends idle with the success time', () async {
    final h = await paired();

    await h.sync();

    final steps = [
      for (final state in h.states)
        if (state.progress case final progress?) progress.step,
    ];
    expect(steps.toSet().toList(), SyncStep.values);
    expect(
      h.states.map((s) => s.progress?.kind),
      containsAllInOrder(RecordKind.values),
    );
    expect(h.state.syncing, isFalse);
    expect(h.state.lastSuccessAt, syncNow);
    expect(h.state.lastError, isNull);
  });

  test('a failed capability is a partial success', () async {
    final h = await paired();
    h.driver.failing[RingCapability.hrv] = StateError('no reply');

    await h.sync();

    expect(h.state.lastSuccessAt, syncNow);
    expect(
      h.state.lastError,
      isA<CapabilitiesFailed>().having((e) => e.capabilities, 'capabilities', {
        RingCapability.hrv,
      }),
    );
  });

  test('an aborted sync keeps the last success and names the step', () async {
    final h = await paired();
    await h.sync();
    h.driver.connectError = const BleTransportException('out of range');

    await h.sync();

    expect(h.state.syncing, isFalse);
    expect(h.state.lastSuccessAt, syncNow);
    expect(
      h.state.lastError,
      isA<SyncAborted>().having((e) => e.step, 'step', SyncStep.connecting),
    );
    expect(h.driver.disconnects, 2);
  });

  test('without a paired ring it fails without touching the ring', () async {
    final h = Harness(memoryDatabase(), loadedDriver());

    await h.sync();

    expect(h.state.lastError, isA<NoPairedRing>());
    expect(h.state.syncing, isFalse);
    expect(h.driver.calls, isEmpty);
  });

  test('a sync requested while one runs joins it', () async {
    final h = await paired();

    await Future.wait([h.sync(), h.sync()]);

    expect(h.driver.connects, 1);
  });

  test('pull to refresh runs a full sync', () async {
    final h = await paired();

    await h.refresh();

    expect(h.driver.connects, 1);
    expect(h.state.lastSuccessAt, syncNow);
  });

  test('a background sync holding the lock is reported, not joined', () async {
    final h = await paired();
    await SyncLocksDao(
      h.db,
    ).acquire('background', at: syncNow, timeout: const Duration(minutes: 10));

    await h.refresh();

    expect(h.state.lastError, isA<AnotherSyncRunning>());
    expect(h.state.syncing, isFalse);
    expect(h.driver.calls, isEmpty);
  });

  test('an automatic sync that loses the lock is not a failure', () async {
    final h = await paired();
    await SyncLocksDao(
      h.db,
    ).acquire('background', at: syncNow, timeout: const Duration(minutes: 10));

    await h.autoSync();

    expect(h.state.lastError, isNull);
    expect(h.state.syncing, isFalse);
    expect(h.driver.calls, isEmpty);
  });

  test(
    'an automatic sync keeps an earlier error when it stands down',
    () async {
      final h = await paired();
      h.driver.connectError = const BleTransportException('out of range');
      await h.sync();
      await SyncLocksDao(h.db).acquire(
        'background',
        at: syncNow,
        timeout: const Duration(minutes: 10),
      );

      await h.autoSync();

      expect(h.state.lastError, isA<SyncAborted>());
      expect(h.state.syncing, isFalse);
    },
  );

  group('when the background engine finishes', () {
    late StreamController<void> finished;

    setUp(() {
      finished = StreamController<void>.broadcast();
      addTearDown(finished.close);
    });

    Future<void> finish() async {
      finished.add(null);
      await pumpEventQueue();
    }

    test('adopts the new sync time and refreshes the data', () async {
      final h = Harness(
        await pairedDatabase(),
        loadedDriver(),
        finished: finished.stream,
      );
      await pumpEventQueue();
      final before = h.revision;
      await RingDevicesDao(h.db)
          .recordSync(ringId, identity: ringIdentity, at: syncNow);

      await finish();

      expect(h.state.lastSuccessAt, syncNow);
      expect(h.revision, before + 1);
    });

    test('clears the notice from a user sync that lost the lock', () async {
      final h = Harness(
        await pairedDatabase(),
        loadedDriver(),
        finished: finished.stream,
      );
      final lock = SyncLocksDao(h.db);
      await lock.acquire(
        'background',
        at: syncNow,
        timeout: const Duration(minutes: 10),
      );
      await h.refresh();
      expect(h.state.lastError, isA<AnotherSyncRunning>());
      await lock.release('background');

      await finish();

      expect(h.state.lastError, isNull);
    });

    test('keeps a failure when no newer sync happened', () async {
      final h = Harness(
        await pairedDatabase(),
        loadedDriver()
          ..connectError = const BleTransportException('out of range'),
        finished: finished.stream,
      );
      await h.sync();

      await finish();

      expect(h.state.lastError, isA<SyncAborted>());
      expect(h.state.lastSuccessAt, isNull);
    });

    test('does not move the sync time backwards', () async {
      final db = await pairedDatabase();
      final h = Harness(db, loadedDriver(), finished: finished.stream);
      await h.sync();
      await RingDevicesDao(db).recordSync(
        ringId,
        identity: ringIdentity,
        at: syncNow.subtract(const Duration(hours: 1)),
      );

      await finish();

      expect(h.state.lastSuccessAt, syncNow);
    });
  });

  test('releases the lock so the next sync can run', () async {
    final h = await paired();

    await h.sync();

    expect(await SyncLocksDao(h.db).current(), isNull);
  });

  test('restores the last success time from the store', () async {
    final db = await pairedDatabase();
    await RingDevicesDao(db)
        .recordSync(ringId, identity: ringIdentity, at: syncNow);

    final h = Harness(db, loadedDriver());
    await Future<void>.delayed(Duration.zero);

    expect(h.state.lastSuccessAt, syncNow);
  });
}

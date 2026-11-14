import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/core/database/app_database.dart';
import 'package:open_ring/core/records/data_revision.dart';
import 'package:open_ring/core/records/health_record_kind.dart';
import 'package:open_ring/core/records/record_kind.dart';
import 'package:open_ring/features/health_sync/application/health_read_controller.dart';
import 'package:open_ring/features/health_sync/domain/health_read_store.dart';
import 'package:open_ring/features/health_sync/domain/health_reader.dart';
import 'package:open_ring/features/health_sync/domain/health_writer.dart';
import 'package:open_ring/features/ring/application/ring_sync_controller.dart';
import 'package:open_ring/features/ring/application/ring_sync_state.dart';
import 'package:open_ring/features/ring/infrastructure/drift_sync_store.dart';
import 'package:open_ring/features/ring/infrastructure/ring_devices_dao.dart';
import 'package:open_ring/features/ring/infrastructure/sync_locks_dao.dart';
import 'package:ring_driver/ring_driver.dart';

import '../../../helpers/database.dart';
import '../../../helpers/fake_health_reader.dart';
import '../../../helpers/fake_ring_driver.dart';
import '../../../helpers/sync_fixtures.dart';

class Harness {
  new(
    this.db,
    this.driver, {
    Stream<void>? finished,
    List<Override> overrides = const [],
  }) {
    container = ProviderContainer(
      overrides: [
        ...overrides,
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

  group('without a ring and with a read on', () {
    const watch = 'com.garmin.android.apps.connectmobile';
    late FakeHealthReader reader;
    late InMemoryHealthReadStore readStore;

    Future<Harness> ringless({bool sleep = true, bool workout = true}) async {
      reader = FakeHealthReader(
        access: HealthAccess.granted,
        nights: [externalNight(watch, DateTime.utc(2026, 11, 9, 23))],
        sessions: [externalWorkout(watch, DateTime.utc(2026, 11, 9, 18))],
      );
      readStore = InMemoryHealthReadStore();
      if (sleep) {
        await readStore.setEnabled(HealthRecordKind.sleep, enabled: true);
      }
      if (workout) {
        await readStore.setEnabled(HealthRecordKind.workout, enabled: true);
      }
      return Harness(
        memoryDatabase(),
        loadedDriver(),
        overrides: [
          healthReaderProvider.overrideWithValue(reader),
          healthReadStoreProvider.overrideWithValue(readStore),
          clockProvider.overrideWithValue(syncNow.toUtc),
        ],
      );
    }

    test('a sync never reports connecting and ends without error', () async {
      final h = await ringless();

      await h.sync();

      expect(
        h.states.map((s) => s.progress?.step),
        isNot(contains(SyncStep.connecting)),
      );
      expect(h.state.lastError, isNull);
      expect(h.state.syncing, isFalse);
      expect(h.state.lastSuccessAt, isNull);
      expect(h.driver.calls, isEmpty);
    });

    test('a sync has imported sleep and workouts when it returns', () async {
      final h = await ringless();

      await h.sync();

      expect(readStore.nights, hasLength(1));
      expect(readStore.workouts, hasLength(1));
    });

    test('pull to refresh does the same', () async {
      final h = await ringless();

      await h.refresh();

      expect(h.state.lastError, isNull);
      expect(h.state.syncing, isFalse);
      expect(readStore.nights, hasLength(1));
    });

    test('only the workout read on still imports and never errors', () async {
      final h = await ringless(sleep: false);

      await h.sync();

      expect(h.state.lastError, isNull);
      expect(readStore.workouts, hasLength(1));
      expect(readStore.nights, isEmpty);
      expect(h.driver.calls, isEmpty);
    });

    test('reads without a ring is true only while no ring is paired', () async {
      final h = await ringless();

      expect(await h.container.read(readsWithoutRingProvider.future), isTrue);

      await RingDevicesDao(h.db).pair(ringIdentity, at: DateTime(2026, 11));
      h.container.read(dataRevisionProvider.notifier).bump();

      expect(await h.container.read(readsWithoutRingProvider.future), isFalse);
    });

    test('a ring paired while the import runs gets its sync', () async {
      await ringless();
      final gate = Completer<void>();
      final gated = _GatedReader(reader, gate.future);
      final h = Harness(
        memoryDatabase(),
        loadedDriver(),
        overrides: [
          healthReaderProvider.overrideWithValue(gated),
          healthReadStoreProvider.overrideWithValue(readStore),
          clockProvider.overrideWithValue(syncNow.toUtc),
        ],
      );

      final running = h.sync();
      await gated.reading.future;
      await RingDevicesDao(h.db).pair(ringIdentity, at: DateTime(2026, 11));
      gate.complete();
      await running;

      expect(h.driver.calls, isNotEmpty);
      expect(h.state.lastSuccessAt, isNotNull);
    });

    test(
      'an automatic run that meets a ring and a held lock reports it',
      () async {
        await ringless();
        final gate = Completer<void>();
        final gated = _GatedReader(reader, gate.future);
        final h = Harness(
          memoryDatabase(),
          loadedDriver(),
          overrides: [
            healthReaderProvider.overrideWithValue(gated),
            healthReadStoreProvider.overrideWithValue(readStore),
            clockProvider.overrideWithValue(syncNow.toUtc),
          ],
        );

        final running = h.autoSync();
        await gated.reading.future;
        await RingDevicesDao(h.db).pair(ringIdentity, at: DateTime(2026, 11));
        await SyncLocksDao(h.db).acquire(
          'background',
          at: syncNow,
          timeout: const Duration(minutes: 10),
        );
        gate.complete();
        await running;

        expect(h.state.lastError, isA<AnotherSyncRunning>());
      },
    );

    test(
      'access revoked since turning it on ends idle with no error',
      () async {
        final h = await ringless();
        reader.access = HealthAccess.denied;

        await h.sync();

        expect(h.state.syncing, isFalse);
        expect(h.state.lastError, isNull);
        expect(h.driver.calls, isEmpty);
      },
    );
  });

  test('without a ring and with every read off it says no ring', () async {
    final h = Harness(
      memoryDatabase(),
      loadedDriver(),
      overrides: [
        healthReadStoreProvider.overrideWithValue(InMemoryHealthReadStore()),
        healthReaderProvider.overrideWithValue(FakeHealthReader()),
      ],
    );

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

final class _GatedReader implements HealthReader {
  new(this.inner, this.gate);

  final HealthReader inner;
  final Future<void> gate;
  final reading = Completer<void>();

  @override
  Future<HealthAccess> readAccess(HealthRecordKind kind) =>
      inner.readAccess(kind);

  @override
  Future<bool> requestReadAccess(HealthRecordKind kind) =>
      inner.requestReadAccess(kind);

  @override
  Future<ExternalRead<ExternalSleepNight>> sleepNights({
    required DateTime from,
    required DateTime to,
  }) async {
    if (!reading.isCompleted) reading.complete();
    await gate;
    return await inner.sleepNights(from: from, to: to);
  }

  @override
  Future<ExternalRead<ExternalWorkout>> workouts({
    required DateTime from,
    required DateTime to,
  }) => inner.workouts(from: from, to: to);
}

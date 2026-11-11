import 'package:flutter_riverpod/misc.dart';
import 'package:open_ring/core/records/record_kind.dart';
import 'package:open_ring/features/heart/application/measure_controller.dart';
import 'package:open_ring/features/heart/application/measure_state.dart';
import 'package:open_ring/features/heart/domain/spot_reading_store.dart';
import 'package:open_ring/features/ring/application/auto_measurements_controller.dart';
import 'package:open_ring/features/ring/application/ring_sync_controller.dart';
import 'package:open_ring/features/ring/application/ring_sync_state.dart';
import 'package:open_ring/features/ring/application/sync_interval_controller.dart';
import 'package:open_ring/features/ring/domain/auto_measurements.dart';
import 'package:open_ring/features/ring/domain/battery_settings.dart';
import 'package:open_ring/features/ring/domain/ring_sync_batch.dart';
import 'package:open_ring/features/ring/domain/sync_interval.dart';
import 'package:open_ring/features/ring/domain/sync_lock.dart';
import 'package:open_ring/features/ring/domain/sync_run.dart';
import 'package:open_ring/features/ring/domain/sync_store.dart';
import 'package:ring_driver/ring_driver.dart';

import 'fake_ring_driver.dart';
import 'fake_sync_scheduler.dart';
import 'in_memory_sync_interval_store.dart';

const fakeRingId = 'R09_C0FE';

class FakeSyncStore implements SyncStore {
  new({this.ring, this.written = const {}, List<SyncRun>? runs})
    : runs = runs ?? [];

  PairedRing? ring;
  Map<RecordKind, int> written;
  final saved = <RingSyncBatch>[];
  final List<SyncRun> runs;
  final forgotten = <String>[];
  Exception? forgetError;

  @override
  Future<PairedRing?> pairedRing() async => ring;

  @override
  Future<Map<RecordKind, DateTime>> cursors(String deviceId) async => const {};

  @override
  Future<Map<RecordKind, int>> save(RingSyncBatch batch) async {
    saved.add(batch);
    return written;
  }

  @override
  Future<void> advanceCursors(
    String deviceId,
    Map<RecordKind, DateTime> cursors, {
    required DateTime at,
  }) async {}

  @override
  Future<void> saveMeasurements(
    String deviceId,
    AutoMeasurements measurements,
  ) async {
    final current = ring;
    if (current == null) return;
    ring = PairedRing(
      deviceId: current.deviceId,
      lastSyncAt: current.lastSyncAt,
      measurements: measurements,
    );
  }

  @override
  Future<void> recordRun(String deviceId, SyncRun run) async =>
      runs.insert(0, run);

  @override
  Future<List<SyncRun>> recentRuns(String deviceId) async => [...runs];

  @override
  Future<void> forget(String deviceId, {required DateTime at}) async {
    if (forgetError case final error?) throw error;
    forgotten.add(deviceId);
    ring = null;
  }
}

class FakeBatterySettings implements BatterySettings {
  int opened = 0;

  @override
  Future<void> open() async => opened++;
}

class InMemorySyncLock implements SyncLock {
  String? holder;
  int releases = 0;

  @override
  Future<bool> acquire(
    String owner, {
    required DateTime at,
    required Duration timeout,
  }) async {
    if (holder != null) return false;
    holder = owner;
    return true;
  }

  @override
  Future<void> release(String owner) async {
    if (holder != owner) return;
    holder = null;
    releases++;
  }
}

class RecordingSpotStore implements SpotReadingStore {
  new({this.failure});

  final Exception? failure;
  final saved = <({String deviceId, LiveReading reading})>[];

  @override
  Future<void> save(String deviceId, LiveReading reading) async {
    final error = failure;
    if (error != null) throw error;
    saved.add((deviceId: deviceId, reading: reading));
  }
}

class SeededRingSyncController extends RingSyncController {
  new(this.seed);

  final RingSyncState seed;

  @override
  RingSyncState build() => seed;
}

class SeededMeasureController extends MeasureController {
  new(this.seed);

  final MeasureState seed;

  @override
  MeasureState build() {
    super.build();
    return seed;
  }
}

List<Override> ringOverrides({
  PairedRing? paired,
  Map<RecordKind, int> written = const {},
  FakeSyncStore? store,
  FakeSyncScheduler? scheduler,
  FakeBatterySettings? batterySettings,
  FakeRingDriver? driver,
  SyncLock? lock,
  RingSyncState? seed,
  SyncInterval? interval,
  SpotReadingStore? spotStore,
  MeasureTiming? timing,
  MeasureState? measure,
  DateTime Function()? clock,
}) => [
  syncStoreProvider.overrideWithValue(
    store ?? FakeSyncStore(ring: paired, written: written),
  ),
  syncLockProvider.overrideWithValue(lock ?? InMemorySyncLock()),
  smartRingDriverProvider.overrideWithValue(driver ?? FakeRingDriver()),
  syncIntervalStoreProvider.overrideWithValue(
    InMemorySyncIntervalStore(interval),
  ),
  syncSchedulerProvider.overrideWithValue(scheduler ?? FakeSyncScheduler()),
  batterySettingsProvider.overrideWithValue(
    batterySettings ?? FakeBatterySettings(),
  ),
  spotReadingStoreProvider.overrideWithValue(spotStore ?? RecordingSpotStore()),
  if (clock != null) syncClockProvider.overrideWithValue(clock),
  if (timing != null) measureTimingProvider.overrideWithValue(timing),
  if (seed != null)
    ringSyncProvider.overrideWith(() => SeededRingSyncController(seed)),
  if (measure != null)
    measureProvider.overrideWith(() => SeededMeasureController(measure)),
];

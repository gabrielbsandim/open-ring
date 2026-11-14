import 'dart:async';

import 'package:open_ring/core/database/app_database.dart';
import 'package:open_ring/features/health_sync/application/health_sync_controller.dart';
import 'package:open_ring/features/health_sync/application/import_external_sleep.dart';
import 'package:open_ring/features/health_sync/application/import_external_workouts.dart';
import 'package:open_ring/features/health_sync/domain/health_reader.dart';
import 'package:open_ring/features/health_sync/domain/health_write_preferences.dart';
import 'package:open_ring/features/health_sync/domain/health_writer.dart';
import 'package:open_ring/features/health_sync/infrastructure/drift_health_read_store.dart';
import 'package:open_ring/features/ring/application/ring_sync_state.dart';
import 'package:open_ring/features/ring/application/sync_paired_ring.dart';
import 'package:open_ring/features/ring/application/sync_ring.dart';
import 'package:open_ring/features/ring/domain/sync_lock.dart';
import 'package:open_ring/features/ring/infrastructure/drift_sync_store.dart';
import 'package:open_ring/features/ring/infrastructure/sync_locks_dao.dart';
import 'package:ring_driver/ring_driver.dart';

final class BackgroundSyncRunner {
  const new({
    required this.database,
    required this.driver,
    this.healthWriter,
    this.healthReader,
    this.healthWrites = const AllHealthWritesEnabled(),
    this.clock = DateTime.now,
    this.lockTimeout = SyncPairedRing.defaultLockTimeout,
    this.timeout = defaultTimeout,
    this.cleanupTimeout = defaultCleanupTimeout,
  });

  // Under the 10 minute worker limit and the lock lease, with room left for
  // the widget publish and teardown steps.
  static const defaultTimeout = Duration(minutes: 8);
  static const defaultCleanupTimeout = Duration(seconds: 5);

  final AppDatabase database;
  final SmartRingDriver driver;
  final HealthWriter? healthWriter;
  final HealthReader? healthReader;
  final HealthWritePreferences healthWrites;
  final DateTime Function() clock;
  final Duration lockTimeout;
  final Duration timeout;
  final Duration cleanupTimeout;

  Future<SyncOutcome> run() async {
    final lock = SyncLocksDao(database);
    final owner = randomLockOwner();
    SyncOutcome? finished;
    Future<SyncOutcome> work() async {
      final outcome = await SyncPairedRing(
        driver: driver,
        store: DriftSyncStore(database),
        lock: lock,
        clock: clock,
        lockTimeout: lockTimeout,
        newOwner: () => owner,
      )();
      finished = outcome;
      if (outcome is SyncCompleted) await _writeHealth();
      await _readHealth();
      return outcome;
    }

    try {
      return await work().timeout(timeout);
    } on TimeoutException catch (error) {
      await _abandon(lock, owner);
      final done = finished;
      if (done != null) return done;
      final failure = SyncAbortedException(SyncStep.connecting, error);
      await _attempt(() => _recordTimedOut(failure), limit: cleanupTimeout);
      return SyncFailed(failure);
    }
  }

  // A run cut off here never reaches its own log write, and the failure alert
  // counts that log, so the streak has to see this attempt too.
  Future<void> _recordTimedOut(SyncAbortedException failure) async {
    final store = DriftSyncStore(database);
    final ring = await store.pairedRing();
    if (ring == null) return;
    await store.recordRun(
      ring.deviceId,
      SyncPairedRing.failedRun(failure, at: clock()),
    );
  }

  // The hung call keeps running until the engine is torn down, so the ring
  // and the lock are released here rather than by its finally blocks.
  Future<void> _abandon(SyncLock lock, String owner) async {
    await _attempt(driver.disconnect, limit: cleanupTimeout);
    await _attempt(() => lock.release(owner), limit: cleanupTimeout);
  }

  // Runs whatever the ring did: a night the ring missed is the one another
  // source fills.
  Future<void> _readHealth() async {
    final reader = healthReader;
    if (reader == null) return;
    final store = DriftHealthReadStore(database);
    final imports = <ExternalImport>[
      ImportExternalSleep(reader: reader, store: store, clock: clock),
      ImportExternalWorkouts(reader: reader, store: store, clock: clock),
    ];
    for (final task in imports) {
      await _quietly(task);
    }
  }

  static Future<void> _quietly(ExternalImport task) async {
    try {
      await task();
    } on Object {
      return;
    }
  }

  // The ring lock is already released here, and a failing health write must
  // never turn a completed ring sync into a failed worker run.
  Future<void> _writeHealth() async {
    final writer = healthWriter;
    if (writer == null) return;
    try {
      await healthOutboxProcessor(
        database: database,
        writer: writer,
        writes: healthWrites,
        clock: clock,
      )();
    } on Object {
      return;
    }
  }
}

const defaultBackgroundStepTimeout = Duration(seconds: 30);

// Shorter than a step so the whole budget stays under the 10 minute limit.
const defaultBackgroundAlertTimeout = Duration(seconds: 10);

// An unanswered task stays RUNNING in WorkManager, so every step is bounded
// and the worker always answers.
Future<bool> superviseBackgroundSync({
  required Future<void> Function() sync,
  required Future<void> Function() sendAlerts,
  required Future<void> Function() publishWidgets,
  required void Function() announceFinished,
  required List<Future<void> Function()> teardown,
  Future<void> Function()? keepAlive,
  Future<bool> Function()? demoMode,
  Future<bool> Function()? ringPaired,
  Duration stepTimeout = defaultBackgroundStepTimeout,
  Duration alertTimeout = defaultBackgroundAlertTimeout,
}) async {
  if (await _isDemo(demoMode)) {
    await _tearDown(teardown, stepTimeout);
    return true;
  }
  if (keepAlive != null) {
    await _attempt(
      () => _keepAliveForRing(keepAlive, ringPaired),
      limit: alertTimeout,
    );
  }
  await _attempt(sync);
  announceFinished();
  await _attempt(sendAlerts, limit: alertTimeout);
  await _attempt(publishWidgets, limit: stepTimeout);
  await _tearDown(teardown, stepTimeout);
  return true;
}

// Without a ring the service notice would show a ring sync that never runs;
// a store read that throws keeps the service a ring sync needs.
Future<void> _keepAliveForRing(
  Future<void> Function() keepAlive,
  Future<bool> Function()? ringPaired,
) async {
  if (!await _ringPaired(ringPaired)) return;
  await keepAlive();
}

Future<bool> _ringPaired(Future<bool> Function()? ringPaired) async {
  if (ringPaired == null) return true;
  try {
    return await ringPaired();
  } on Object {
    return true;
  }
}

// The demo ring has nothing to sync, and the service notice would only show
// a sync that never happens.
Future<bool> _isDemo(Future<bool> Function()? demoMode) async {
  if (demoMode == null) return false;
  try {
    return await demoMode();
  } on Object {
    return false;
  }
}

Future<void> _tearDown(
  List<Future<void> Function()> teardown,
  Duration limit,
) async {
  for (final step in teardown) {
    await _attempt(step, limit: limit);
  }
}

Future<void> _attempt(Future<void> Function() step, {Duration? limit}) async {
  try {
    final running = step();
    await (limit == null ? running : running.timeout(limit));
  } on Object {
    return;
  }
}

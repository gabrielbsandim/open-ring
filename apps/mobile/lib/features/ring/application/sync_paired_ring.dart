import 'dart:async';
import 'dart:math';

import 'package:meta/meta.dart';
import 'package:open_ring/features/ring/application/ring_sync_state.dart';
import 'package:open_ring/features/ring/application/sync_ring.dart';
import 'package:open_ring/features/ring/domain/sync_lock.dart';
import 'package:open_ring/features/ring/domain/sync_run.dart';
import 'package:open_ring/features/ring/domain/sync_store.dart';
import 'package:ring_driver/ring_driver.dart';

@immutable
sealed class SyncOutcome {
  const new();
}

final class NothingPaired extends SyncOutcome {
  const new();
}

final class AlreadySyncing extends SyncOutcome {
  const new();
}

final class SyncCompleted extends SyncOutcome {
  const new(this.report);

  final SyncReport report;
}

final class SyncFailed extends SyncOutcome {
  const new(this.error);

  final SyncAbortedException error;
}

String randomLockOwner() {
  final random = Random.secure();
  return List.generate(
    16,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

final class SyncPairedRing {
  const new({
    required this.driver,
    required this.store,
    required this.lock,
    required this.clock,
    this.lockTimeout = defaultLockTimeout,
    this.runTimeout = defaultRunTimeout,
    this.newOwner = randomLockOwner,
  });

  // Android stops a worker after 10 minutes, so a lock older than that belongs
  // to a run that was killed and can never release it.
  static const defaultLockTimeout = Duration(minutes: 10);

  // A platform call that never answers would otherwise hold the lock and leave
  // the app showing a sync that cannot end.
  static const defaultRunTimeout = Duration(minutes: 3);
  static const _disconnectTimeout = Duration(seconds: 5);

  final SmartRingDriver driver;
  final SyncStore store;
  final SyncLock lock;
  final DateTime Function() clock;
  final Duration lockTimeout;
  final Duration runTimeout;
  final String Function() newOwner;

  Future<SyncOutcome> call({
    SyncProgressListener? onProgress,
    SyncBatteryListener? onBattery,
  }) async {
    final ring = await store.pairedRing();
    if (ring == null) return const NothingPaired();
    final owner = newOwner();
    final acquired = await lock.acquire(
      owner,
      at: clock(),
      timeout: lockTimeout,
    );
    if (!acquired) return const AlreadySyncing();
    var step = SyncStep.connecting;
    try {
      final sync = SyncRing(
        driver: driver,
        store: store,
        clock: clock,
        measurements: ring.measurements,
      );
      final report = await sync(
        ring.deviceId,
        onProgress: (progress) {
          step = progress.step;
          onProgress?.call(progress);
        },
        onBattery: onBattery,
      ).timeout(runTimeout);
      await _record(ring.deviceId, completedRun(report));
      return SyncCompleted(report);
    } on SyncAbortedException catch (error) {
      await _record(ring.deviceId, failedRun(error, at: clock()));
      return SyncFailed(error);
    } on TimeoutException catch (cause) {
      await _disconnectQuietly();
      final error = SyncAbortedException(step, cause);
      await _record(ring.deviceId, failedRun(error, at: clock()));
      return SyncFailed(error);
    } finally {
      await lock.release(owner);
    }
  }

  static SyncRun completedRun(SyncReport report) => SyncRun(
    at: report.syncedAt,
    outcome: report.failures.isEmpty
        ? SyncRunOutcome.completed
        : SyncRunOutcome.partial,
    kinds: {
      for (final MapEntry(:key, :value) in report.written.entries)
        if (value > 0) key,
    },
    recordCount: report.written.values.fold(0, (sum, count) => sum + count),
  );

  static SyncRun failedRun(
    SyncAbortedException error, {
    required DateTime at,
  }) => SyncRun(
    at: at,
    outcome: error.step == SyncStep.connecting
        ? SyncRunOutcome.unreachable
        : SyncRunOutcome.stopped,
  );

  Future<void> _disconnectQuietly() async {
    try {
      await driver.disconnect().timeout(_disconnectTimeout);
    } on Object {
      return;
    }
  }

  // The log is a convenience; failing to write it must not change the outcome.
  Future<void> _record(String deviceId, SyncRun run) async {
    try {
      await store.recordRun(deviceId, run);
    } on Object {
      return;
    }
  }
}

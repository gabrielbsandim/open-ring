import 'package:meta/meta.dart';
import 'package:open_ring/core/records/health_record_kind.dart';
import 'package:open_ring/features/health_sync/domain/health_outbox_store.dart';
import 'package:open_ring/features/health_sync/domain/health_write_preferences.dart';
import 'package:open_ring/features/health_sync/domain/health_writer.dart';
import 'package:open_ring/features/health_sync/domain/retry_policy.dart';
import 'package:open_ring/features/ring/application/sync_paired_ring.dart';
import 'package:open_ring/features/ring/domain/sync_lock.dart';

@immutable
final class HealthOutboxReport {
  new({
    this.busy = false,
    this.written = 0,
    this.notApplicable = 0,
    this.retrying = 0,
    this.dead = 0,
    this.disabled = 0,
    Set<HealthRecordKind> denied = const {},
    this.unavailable = false,
  }) : denied = Set.unmodifiable(denied);

  final bool busy;
  final int written;
  final int notApplicable;
  final int retrying;
  final int dead;
  final int disabled;
  final Set<HealthRecordKind> denied;
  final bool unavailable;
}

final class ProcessHealthOutbox {
  const new({
    required this.outbox,
    required this.source,
    required this.writer,
    required this.lock,
    required this.clock,
    this.writes = const AllHealthWritesEnabled(),
    this.retry = const RetryPolicy(),
    this.batchSize = 200,
    this.lockTimeout = const Duration(minutes: 10),
    this.newOwner = randomLockOwner,
  });

  final HealthOutboxStore outbox;
  final HealthRecordSource source;
  final HealthWriter writer;
  final HealthWritePreferences writes;
  final SyncLock lock;
  final DateTime Function() clock;
  final RetryPolicy retry;
  final int batchSize;
  final Duration lockTimeout;
  final String Function() newOwner;

  Future<HealthOutboxReport> call() async {
    final owner = newOwner();
    final acquired = await lock.acquire(
      owner,
      at: clock(),
      timeout: lockTimeout,
    );
    if (!acquired) return HealthOutboxReport(busy: true);
    try {
      final run = _Run();
      for (final entry in await outbox.due(clock())) {
        if (run.unavailable) break;
        await _process(entry, run);
      }
      return run.report();
    } finally {
      await lock.release(owner);
    }
  }

  Future<void> _process(OutboxEntry entry, _Run run) async {
    final kind = entry.kind;
    if (!kind.hasPlatformType) {
      await outbox.markNotApplicable(entry.id, at: clock());
      run.notApplicable++;
      return;
    }
    try {
      // Read per row so a toggle flipped during a long pass stops the rest.
      if ((await writes.disabled()).contains(kind)) {
        await outbox.markDisabled(entry.id, at: clock());
        run.disabled++;
        return;
      }
      if (run.denied.contains(kind)) return;
      final access = run.access[kind] ??= await writer.access(kind);
      final proceed = switch (access) {
        HealthAccess.granted => true,
        HealthAccess.denied => run.deny(kind),
        HealthAccess.unavailable => run.markUnavailable(),
        HealthAccess.deferred => false,
      };
      if (!proceed) return;
      for (final batch in await source.batches(entry, batchSize: batchSize)) {
        await writer.replace(batch);
      }
      await outbox.markDone(entry.id, at: clock());
      run.written++;
    } on Object catch (error) {
      await _fail(entry, '$error', run);
    }
  }

  Future<void> _fail(OutboxEntry entry, String error, _Run run) async {
    final now = clock();
    final next = retry.nextAttempt(entry.attempts + 1, now);
    if (next == null) {
      await outbox.markDead(entry.id, error: error, at: now);
      run.dead++;
      return;
    }
    await outbox.markFailed(
      entry.id,
      error: error,
      at: now,
      nextAttemptAt: next,
    );
    run.retrying++;
  }
}

final class _Run {
  final access = <HealthRecordKind, HealthAccess>{};
  final denied = <HealthRecordKind>{};
  bool unavailable = false;
  int written = 0;
  int notApplicable = 0;
  int retrying = 0;
  int dead = 0;
  int disabled = 0;

  bool deny(HealthRecordKind kind) {
    denied.add(kind);
    return false;
  }

  bool markUnavailable() {
    unavailable = true;
    return false;
  }

  HealthOutboxReport report() => HealthOutboxReport(
    written: written,
    notApplicable: notApplicable,
    retrying: retrying,
    dead: dead,
    disabled: disabled,
    denied: denied,
    unavailable: unavailable,
  );
}

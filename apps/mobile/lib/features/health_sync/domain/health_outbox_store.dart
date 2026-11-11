import 'package:meta/meta.dart';
import 'package:open_ring/core/records/health_record_kind.dart';
import 'package:open_ring/features/health_sync/domain/health_entries.dart';

@immutable
final class OutboxEntry {
  const new({
    required this.id,
    required this.kind,
    required this.from,
    required this.to,
    required this.enqueuedAt,
    this.deviceId,
    this.attempts = 0,
  });

  final int id;
  final HealthRecordKind kind;
  final String? deviceId;
  final DateTime from;
  final DateTime to;
  final DateTime enqueuedAt;
  final int attempts;

  int get version => enqueuedAt.millisecondsSinceEpoch;
}

abstract interface class HealthOutboxStore {
  Future<List<OutboxEntry>> due(DateTime now);

  Future<void> markDone(int id, {required DateTime at});

  Future<void> markNotApplicable(int id, {required DateTime at});

  Future<void> markDisabled(int id, {required DateTime at});

  Future<void> markFailed(
    int id, {
    required String error,
    required DateTime at,
    required DateTime nextAttemptAt,
  });

  Future<void> markDead(int id, {required String error, required DateTime at});
}

abstract interface class DeadOutboxStore {
  Future<Map<HealthRecordKind, String?>> lastDeadErrors();

  // Back to pending with a fresh retry budget; null resets every kind.
  Future<int> resetDead({HealthRecordKind? kind});
}

abstract interface class HealthWriteToggleStore {
  // Every pending row of the kind, backed off ones too, leaves the queue.
  Future<int> disablePending(HealthRecordKind kind, {required DateTime at});

  // Back to pending with a fresh retry budget: the user asked for them again.
  Future<int> restoreDisabled(HealthRecordKind kind);
}

abstract interface class HealthRecordSource {
  Future<List<HealthWriteBatch>> batches(
    OutboxEntry entry, {
    required int batchSize,
  });
}

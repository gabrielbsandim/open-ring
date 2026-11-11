import 'package:drift/drift.dart';
import 'package:open_ring/core/database/app_database.dart';
import 'package:open_ring/core/records/epoch.dart';
import 'package:open_ring/core/records/health_record_kind.dart';
import 'package:open_ring/features/health_sync/domain/health_status.dart';

final class DriftOutboxSummaryReader implements OutboxSummaryReader {
  const new(this._db);

  final AppDatabase _db;

  @override
  Future<OutboxSummary> summary() async {
    final rows = await _db
        .customSelect(
          'SELECT status, kind, COUNT(*) AS batches, '
          'SUM(record_count) AS records, '
          'MIN(enqueued_at_utc_ms) AS oldest, '
          'MAX(completed_at_utc_ms) AS last_done '
          'FROM health_outbox GROUP BY status, kind',
          readsFrom: {_db.healthOutbox},
        )
        .get();
    final pending = <HealthRecordKind, int>{};
    final disabled = <HealthRecordKind, int>{};
    var pendingRows = 0;
    var deadRows = 0;
    int? oldest;
    int? lastDone;
    for (final row in rows) {
      final kind = HealthRecordKind.values
          .asNameMap()[row.read<String>('kind')];
      if (kind == null || !kind.hasPlatformType) continue;
      final batches = row.read<int>('batches');
      switch (OutboxStatus.values.asNameMap()[row.read<String>('status')]) {
        case OutboxStatus.pending:
          pending[kind] = (pending[kind] ?? 0) + row.read<int>('records');
          pendingRows += batches;
          oldest = _min(oldest, row.read<int>('oldest'));
        case OutboxStatus.dead:
          deadRows += batches;
        case OutboxStatus.done:
          lastDone = _max(lastDone, row.readNullable<int>('last_done'));
        case OutboxStatus.disabled:
          disabled[kind] = (disabled[kind] ?? 0) + row.read<int>('records');
        case OutboxStatus.notApplicable || null:
          break;
      }
    }
    return OutboxSummary(
      pendingRecords: pending,
      disabledRecords: disabled,
      pendingRows: pendingRows,
      deadRows: deadRows,
      lastDeadError: deadRows == 0 ? null : await _lastDeadError(),
      oldestPendingAt: oldest == null ? null : fromUtcMs(oldest),
      lastSentAt: lastDone == null ? null : fromUtcMs(lastDone),
    );
  }

  Future<String?> _lastDeadError() async {
    final row = await _db
        .customSelect(
          'SELECT last_error FROM health_outbox WHERE status = ? '
          'ORDER BY last_attempt_at_utc_ms DESC, id DESC LIMIT 1',
          variables: [Variable.withString(OutboxStatus.dead.name)],
          readsFrom: {_db.healthOutbox},
        )
        .getSingleOrNull();
    return row?.readNullable<String>('last_error');
  }

  static int _min(int? current, int value) =>
      current == null || value < current ? value : current;

  static int? _max(int? current, int? value) {
    if (value == null) return current;
    if (current == null || value > current) return value;
    return current;
  }
}

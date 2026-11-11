import 'package:drift/drift.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/core/database/app_database.dart';
import 'package:open_ring/core/records/epoch.dart';
import 'package:open_ring/core/records/health_record_kind.dart';
import 'package:open_ring/core/records/source_priority.dart';
import 'package:open_ring/features/sleep/domain/imported_sleep_reader.dart';
import 'package:open_ring/features/sleep/infrastructure/drift_sleep_history_reader.dart';
import 'package:ring_driver/ring_driver.dart';

final class DriftImportedSleepReader implements ImportedSleepReader {
  const new(this._db);

  final AppDatabase _db;

  @override
  Future<ImportedSleep> importedSleep({
    required DateTime from,
    required DateTime to,
  }) async {
    if (!await _enabled()) return noImportedSleep;
    final rows = await _db
        .customSelect(
          'SELECT s.source AS source, g.start_utc_ms AS start_ms, '
          'g.end_utc_ms AS end_ms, g.stage AS stage, '
          's.offset_minutes AS offset_minutes '
          'FROM imported_sleep_stages g JOIN imported_sleep_sessions s '
          'ON s.record_id = g.record_id '
          'WHERE g.start_utc_ms < ? AND g.end_utc_ms > ? '
          'ORDER BY g.start_utc_ms',
          variables: [Variable.withInt(to.utcMs), Variable.withInt(from.utcMs)],
          readsFrom: {_db.importedSleepStages, _db.importedSleepSessions},
        )
        .get();
    final spans = <String, List<SleepSpan>>{};
    for (final row in rows) {
      final stage = SleepStage.values.asNameMap()[row.read<String>('stage')];
      if (stage == null) continue;
      (spans[row.read<String>('source')] ??= []).add(
        SleepSpan(
          start: utcInstant(row.read<int>('start_ms')),
          end: utcInstant(row.read<int>('end_ms')),
          phase: DriftSleepHistoryReader.phaseOf(stage),
          utcOffset: offsetOf(row.read<int>('offset_minutes')),
        ),
      );
    }
    return (priority: await _priority(), spans: spans);
  }

  Future<bool> _enabled() async {
    final row =
        await (_db.select(_db.healthReads)
              ..where((r) => r.kind.equalsValue(HealthRecordKind.sleep)))
            .getSingleOrNull();
    return row?.enabled ?? false;
  }

  Future<List<String>> _priority() async {
    final stored =
        await (_db.select(_db.sourcePriorities)
              ..where((r) => r.metric.equals(HealthRecordKind.sleep.name))
              ..orderBy([(r) => OrderingTerm.asc(r.priority)]))
            .get();
    final seen = await _db
        .customSelect(
          'SELECT DISTINCT source FROM imported_sleep_sessions',
          readsFrom: {_db.importedSleepSessions},
        )
        .get();
    return resolveSourcePriority(
      [for (final row in stored) row.source],
      [for (final row in seen) row.read<String>('source')],
    );
  }
}

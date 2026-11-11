import 'package:drift/drift.dart';
import 'package:open_ring/core/database/app_database.dart';
import 'package:open_ring/core/records/epoch.dart';
import 'package:open_ring/core/records/health_record_kind.dart';
import 'package:open_ring/core/records/source_priority.dart';
import 'package:open_ring/features/workout/domain/workout_history.dart';
import 'package:open_ring/features/workout/domain/workout_type.dart';

final class DriftImportedWorkoutReader implements ImportedWorkoutReader {
  const new(this._db);

  final AppDatabase _db;

  @override
  Future<ImportedWorkouts> recent({required int limit}) async {
    if (limit <= 0 || !await _enabled()) return noImportedWorkouts;
    final rows =
        await (_db.select(_db.importedWorkouts)
              ..orderBy([(w) => OrderingTerm.desc(w.startUtcMs)])
              ..limit(limit))
            .get();
    return (priority: await _priority(), workouts: rows.map(_workout).toList());
  }

  @override
  Future<ImportedWorkout?> byRecordId(String recordId) async {
    if (!await _enabled()) return null;
    final row = await (_db.select(
      _db.importedWorkouts,
    )..where((w) => w.recordId.equals(recordId))).getSingleOrNull();
    if (row == null) return null;
    return _workout(row);
  }

  static ImportedWorkout _workout(ImportedWorkoutRow row) => ImportedWorkout(
    recordId: row.recordId,
    source: row.source,
    type: WorkoutType.ofActivityType(row.activityType),
    start: fromUtcMs(row.startUtcMs),
    end: fromUtcMs(row.endUtcMs),
    utcOffset: offsetOf(row.offsetMinutes),
  );

  Future<bool> _enabled() async {
    final row =
        await (_db.select(_db.healthReads)
              ..where((r) => r.kind.equalsValue(HealthRecordKind.workout)))
            .getSingleOrNull();
    return row?.enabled ?? false;
  }

  Future<List<String>> _priority() async {
    final stored =
        await (_db.select(_db.sourcePriorities)
              ..where((r) => r.metric.equals(HealthRecordKind.workout.name))
              ..orderBy([(r) => OrderingTerm.asc(r.priority)]))
            .get();
    final seen = await _db
        .customSelect(
          'SELECT DISTINCT source FROM imported_workouts',
          readsFrom: {_db.importedWorkouts},
        )
        .get();
    return resolveSourcePriority(
      [for (final row in stored) row.source],
      [for (final row in seen) row.read<String>('source')],
    );
  }
}

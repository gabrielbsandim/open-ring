import 'package:drift/drift.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/core/database/app_database.dart';
import 'package:open_ring/features/activity/domain/step_goal_history.dart';

final class DriftStepGoalHistory implements StepGoalHistory {
  new(this._db);

  final AppDatabase _db;

  @override
  Future<List<StepGoalChange>> changes() async {
    final rows = await (_db.select(
      _db.stepGoalChanges,
    )..orderBy([(row) => OrderingTerm.asc(row.effectiveDate)])).get();
    return [
      for (final row in rows)
        if (LocalDate.tryParse(row.effectiveDate) case final date?)
          (from: date, steps: row.steps),
    ];
  }

  @override
  Future<void> record({
    required LocalDate on,
    required int steps,
    required int previous,
  }) => _db.transaction(() async {
    final newest =
        await (_db.select(_db.stepGoalChanges)
              ..orderBy([(row) => OrderingTerm.desc(row.effectiveDate)])
              ..limit(1))
            .getSingleOrNull();
    if (newest == null) await _put(stepGoalBaselineDate.iso, previous);
    final ahead = newest != null && newest.effectiveDate.compareTo(on.iso) > 0;
    await _put(ahead ? newest.effectiveDate : on.iso, steps);
  });

  Future<void> _put(String date, int steps) => _db
      .into(_db.stepGoalChanges)
      .insertOnConflictUpdate(
        StepGoalChangesCompanion.insert(effectiveDate: date, steps: steps),
      );
}

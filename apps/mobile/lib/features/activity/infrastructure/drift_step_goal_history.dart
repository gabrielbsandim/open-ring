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
    final stored = await (_db.select(
      _db.stepGoalChanges,
    )..limit(1)).getSingleOrNull();
    if (stored == null) await _put(stepGoalBaselineDate, previous);
    await (_db.delete(
      _db.stepGoalChanges,
    )..where((row) => row.effectiveDate.isBiggerThanValue(on.iso))).go();
    await _put(on, steps);
  });

  Future<void> _put(LocalDate date, int steps) => _db
      .into(_db.stepGoalChanges)
      .insertOnConflictUpdate(
        StepGoalChangesCompanion.insert(effectiveDate: date.iso, steps: steps),
      );
}

import 'package:drift/drift.dart';
import 'package:open_ring/core/database/app_database.dart';
import 'package:open_ring/features/workout/domain/workout_rating_store.dart';

final class DriftWorkoutRatingStore implements WorkoutRatingStore {
  const new(this._db);

  final AppDatabase _db;

  @override
  Future<bool> rateRecorded(int id, int? rating) async {
    _check(rating);
    final changed =
        await (_db.update(_db.workouts)..where((w) => w.id.equals(id))).write(
          WorkoutsCompanion(effortRating: Value(rating)),
        );
    return changed > 0;
  }

  @override
  Future<bool> rateImported(String recordId, int? rating) async {
    _check(rating);
    final changed =
        await (_db.update(_db.importedWorkouts)
              ..where((w) => w.recordId.equals(recordId)))
            .write(ImportedWorkoutsCompanion(effortRating: Value(rating)));
    return changed > 0;
  }

  @override
  Future<int> countRatings() async {
    final recorded = await _db.workouts
        .count(where: (w) => w.effortRating.isNotNull())
        .getSingle();
    final imported = await _db.importedWorkouts
        .count(where: (w) => w.effortRating.isNotNull())
        .getSingle();
    return recorded + imported;
  }

  @override
  Future<int> clearRatings() => _db.transaction(() async {
    final recorded =
        await (_db.update(_db.workouts)
              ..where((w) => w.effortRating.isNotNull()))
            .write(const WorkoutsCompanion(effortRating: Value(null)));
    final imported =
        await (_db.update(_db.importedWorkouts)
              ..where((w) => w.effortRating.isNotNull()))
            .write(const ImportedWorkoutsCompanion(effortRating: Value(null)));
    return recorded + imported;
  });

  static void _check(int? rating) {
    if (rating == null || isEffortRating(rating)) return;
    throw ArgumentError.value(rating, 'rating');
  }
}

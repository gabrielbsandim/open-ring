import 'package:open_ring/core/database/app_database.dart';
import 'package:open_ring/core/records/epoch.dart';
import 'package:open_ring/features/health_sync/infrastructure/health_outbox_dao.dart';
import 'package:open_ring/features/workout/domain/workout_recovery.dart';
import 'package:open_ring/features/workout/domain/workout_type.dart';
import 'package:open_ring/features/workout/infrastructure/workouts_dao.dart';

final class DriftOpenWorkoutStore implements OpenWorkoutStore {
  new(this._db) : _workouts = WorkoutsDao(_db), _outbox = HealthOutboxDao(_db);

  final AppDatabase _db;
  final WorkoutsDao _workouts;
  final HealthOutboxDao _outbox;

  @override
  Future<List<DateTime>> openStarts() => _workouts.openStarts();

  // A demo row carries a device id and is never queued for Health, as the
  // demo store never queues one when it saves.
  @override
  Future<RecoveredWorkout?> close(DateTime start, {required DateTime at}) =>
      _db.transaction(() async {
        final row = await _workouts.closeOpen(start);
        if (row == null) return null;
        final recovered = _recoveredOf(row);
        if (row.deviceId == null) {
          await _outbox.enqueueWorkout(
            start: recovered.start,
            end: recovered.end,
            at: at,
          );
        }
        return recovered;
      });

  RecoveredWorkout _recoveredOf(WorkoutRow row) {
    final end = row.endUtcMs!;
    return RecoveredWorkout(
      id: row.id,
      type: WorkoutType.ofActivityType(row.activityType),
      start: utcInstant(row.startUtcMs),
      end: utcInstant(end),
      elapsed: Duration(milliseconds: row.elapsedMs ?? end - row.startUtcMs),
      distanceMeters: row.distanceMeters,
      offsetMinutes: row.offsetMinutes,
    );
  }
}

import 'package:open_ring/core/database/app_database.dart';
import 'package:open_ring/features/health_sync/infrastructure/health_outbox_dao.dart';
import 'package:open_ring/features/workout/domain/workout_session.dart';
import 'package:open_ring/features/workout/domain/workout_store.dart';
import 'package:open_ring/features/workout/infrastructure/workouts_dao.dart';

final class DriftWorkoutStore implements WorkoutStore {
  new(this._db) : _workouts = WorkoutsDao(_db), _outbox = HealthOutboxDao(_db);

  final AppDatabase _db;
  final WorkoutsDao _workouts;
  final HealthOutboxDao _outbox;

  // One outbox row carries the session, its HR series and its route: the
  // record source loads all three for every workout in the row's window.
  @override
  Future<int> save(FinishedWorkout workout, {required DateTime at}) =>
      _db.transaction(() async {
        final id = await _workouts.closeOrInsert(workout);
        await _outbox.enqueueWorkout(
          start: workout.start,
          end: workout.end,
          at: at,
        );
        return id;
      });

  // Deleting enqueues nothing: a copy already sent to Health stays there, and
  // a still pending outbox row finds no workout in its window and writes none.
  @override
  Future<bool> delete(int id) => _workouts.deleteById(id);

  // The progress is taken before the first await, so later samples wait for
  // the next checkpoint. Nothing is queued for Health until save.
  @override
  Future<void> checkpoint(WorkoutSession session, {required DateTime at}) {
    final progress = session.progressAt(at);
    return _workouts.writeCheckpoint(progress, at: progress.end);
  }

  @override
  Future<void> dropCheckpoint(WorkoutSession session) =>
      _workouts.deleteOpen(session.startedAt);
}

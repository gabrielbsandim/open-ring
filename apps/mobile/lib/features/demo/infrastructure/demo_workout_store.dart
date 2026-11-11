import 'package:open_ring/core/database/app_database.dart';
import 'package:open_ring/features/demo/domain/demo_data.dart';
import 'package:open_ring/features/workout/domain/live_heart_rate_source.dart';
import 'package:open_ring/features/workout/domain/workout_session.dart';
import 'package:open_ring/features/workout/domain/workout_store.dart';
import 'package:open_ring/features/workout/infrastructure/workouts_dao.dart';

// Tagged with the demo ring so leaving the demo deletes it, and never queued
// for Health Connect.
final class DemoWorkoutStore implements WorkoutStore {
  new(AppDatabase db) : _workouts = WorkoutsDao(db);

  final WorkoutsDao _workouts;

  @override
  Future<int> save(FinishedWorkout workout, {required DateTime at}) =>
      _workouts.insertFinished(workout, deviceId: demoDeviceId);

  @override
  Future<bool> delete(int id) => _workouts.deleteById(id);
}

final class NoRingHeartRateSource implements LiveHeartRateSource {
  const new();

  @override
  Stream<int> bpm() =>
      Stream.error(const HeartRateUnavailable(HeartRateProblem.noRing));
}

import 'package:open_ring/features/workout/domain/workout_session.dart';

const workoutCheckpointInterval = Duration(seconds: 60);

abstract interface class WorkoutStore {
  Future<int> save(FinishedWorkout workout, {required DateTime at});

  Future<bool> delete(int id);

  Future<void> checkpoint(WorkoutSession session, {required DateTime at});

  Future<void> dropCheckpoint(WorkoutSession session);
}

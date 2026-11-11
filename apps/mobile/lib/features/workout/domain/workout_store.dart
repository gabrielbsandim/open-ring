import 'package:open_ring/features/workout/domain/workout_session.dart';

abstract interface class WorkoutStore {
  Future<int> save(FinishedWorkout workout, {required DateTime at});

  Future<bool> delete(int id);
}

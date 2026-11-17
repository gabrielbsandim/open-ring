import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_ring/features/workout/domain/workout_lock_preferences.dart';

final workoutLockPreferencesProvider = Provider<WorkoutLockPreferences>(
  (ref) => InMemoryWorkoutLockPreferences(),
);

final workoutLockHeartRateProvider =
    AsyncNotifierProvider<WorkoutLockHeartRate, bool>(WorkoutLockHeartRate.new);

class WorkoutLockHeartRate extends AsyncNotifier<bool> {
  @override
  Future<bool> build() =>
      ref.watch(workoutLockPreferencesProvider).showHeartRate();

  Future<void> set({required bool show}) async {
    state = AsyncData(show);
    await ref.read(workoutLockPreferencesProvider).setShowHeartRate(show: show);
  }
}

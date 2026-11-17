import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_ring/features/workout/domain/workout_alert_preferences.dart';

final workoutAlertPreferencesProvider = Provider<WorkoutAlertPreferences>(
  (ref) => InMemoryWorkoutAlertPreferences(),
);

final workoutRingLostAlertProvider =
    AsyncNotifierProvider<WorkoutRingLostAlert, bool>(WorkoutRingLostAlert.new);

class WorkoutRingLostAlert extends AsyncNotifier<bool> {
  @override
  Future<bool> build() =>
      ref.watch(workoutAlertPreferencesProvider).alertRingLost();

  Future<void> set({required bool alert}) async {
    state = AsyncData(alert);
    await ref
        .read(workoutAlertPreferencesProvider)
        .setAlertRingLost(alert: alert);
  }
}

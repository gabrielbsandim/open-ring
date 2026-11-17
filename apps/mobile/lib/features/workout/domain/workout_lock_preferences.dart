abstract interface class WorkoutLockPreferences {
  /// Whether the lock screen shows the heart rate and its zone.
  Future<bool> showHeartRate();

  Future<void> setShowHeartRate({required bool show});
}

final class InMemoryWorkoutLockPreferences implements WorkoutLockPreferences {
  new({this.show = true});

  bool show;

  @override
  Future<bool> showHeartRate() async => show;

  @override
  Future<void> setShowHeartRate({required bool show}) async => this.show = show;
}

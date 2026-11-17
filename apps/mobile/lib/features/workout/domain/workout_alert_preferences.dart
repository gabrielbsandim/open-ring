abstract interface class WorkoutAlertPreferences {
  /// Whether a ring that stops sending heart rate vibrates once.
  Future<bool> alertRingLost();

  Future<void> setAlertRingLost({required bool alert});
}

final class InMemoryWorkoutAlertPreferences implements WorkoutAlertPreferences {
  new({this.alert = true});

  bool alert;

  @override
  Future<bool> alertRingLost() async => alert;

  @override
  Future<void> setAlertRingLost({required bool alert}) async =>
      this.alert = alert;
}

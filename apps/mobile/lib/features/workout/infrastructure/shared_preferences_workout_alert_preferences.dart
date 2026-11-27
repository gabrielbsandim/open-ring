import 'package:open_ring/features/workout/domain/workout_alert_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

final class SharedPreferencesWorkoutAlertPreferences
    implements WorkoutAlertPreferences {
  new([SharedPreferencesAsync? preferences]) : _preferences = preferences;

  static const key = 'workout_ring_lost_alert';

  SharedPreferencesAsync? _preferences;

  SharedPreferencesAsync get _store =>
      _preferences ??= SharedPreferencesAsync();

  @override
  Future<bool> alertRingLost() async => await _store.getBool(key) ?? true;

  @override
  Future<void> setAlertRingLost({required bool alert}) =>
      _store.setBool(key, alert);
}

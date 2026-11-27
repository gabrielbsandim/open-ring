import 'package:open_ring/features/workout/domain/workout_lock_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

final class SharedPreferencesWorkoutLockPreferences
    implements WorkoutLockPreferences {
  new([SharedPreferencesAsync? preferences]) : _preferences = preferences;

  static const key = 'workout_lock_heart_rate';

  SharedPreferencesAsync? _preferences;

  SharedPreferencesAsync get _store =>
      _preferences ??= SharedPreferencesAsync();

  @override
  Future<bool> showHeartRate() async => await _store.getBool(key) ?? true;

  @override
  Future<void> setShowHeartRate({required bool show}) =>
      _store.setBool(key, show);
}

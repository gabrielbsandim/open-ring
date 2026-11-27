import 'package:open_ring/features/open_score/domain/week_goal_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

final class SharedPreferencesWeekGoalStore implements WeekGoalStore {
  new([SharedPreferencesAsync? preferences]) : _preferences = preferences;

  static const key = 'open_score_week_goal';

  SharedPreferencesAsync? _preferences;

  SharedPreferencesAsync get _store =>
      _preferences ??= SharedPreferencesAsync();

  @override
  Future<int?> read() => _store.getInt(key);

  @override
  Future<void> write(int goal) => _store.setInt(key, goal);

  @override
  Future<void> clear() => _store.remove(key);
}

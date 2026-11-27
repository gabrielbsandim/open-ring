import 'package:open_ring/features/open_score/domain/celebration_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

final class SharedPreferencesCelebrationStore implements CelebrationStore {
  new([SharedPreferencesAsync? preferences]) : _preferences = preferences;

  static const key = 'open_score_celebration_closed';

  SharedPreferencesAsync? _preferences;

  SharedPreferencesAsync get _store =>
      _preferences ??= SharedPreferencesAsync();

  @override
  Future<String?> read() => _store.getString(key);

  @override
  Future<void> write(String isoDate) => _store.setString(key, isoDate);

  @override
  Future<void> clear() => _store.remove(key);
}

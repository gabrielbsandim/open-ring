import 'package:open_ring/features/ring/domain/sync_interval.dart';
import 'package:open_ring/features/ring/domain/sync_interval_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SharedPreferencesSyncIntervalStore implements SyncIntervalStore {
  const new(this._preferences);

  static const key = 'sync_interval_minutes';

  final SharedPreferencesWithCache _preferences;

  static Future<SharedPreferencesSyncIntervalStore> open() async {
    final preferences = await SharedPreferencesWithCache.create(
      cacheOptions: const SharedPreferencesWithCacheOptions(allowList: {key}),
    );
    return SharedPreferencesSyncIntervalStore(preferences);
  }

  @override
  SyncInterval? read() => SyncInterval.fromMinutes(_preferences.getInt(key));

  @override
  Future<void> write(SyncInterval interval) =>
      _preferences.setInt(key, interval.minutes);
}

import 'package:open_ring/features/demo/domain/demo_mode_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

// The background worker has no provider container, so it reads the flag here.
Future<bool> readStoredDemoMode([SharedPreferencesAsync? preferences]) async {
  final store = preferences ?? SharedPreferencesAsync();
  return await store.getBool(SharedPreferencesDemoModeStore.key) ?? false;
}

class SharedPreferencesDemoModeStore implements DemoModeStore {
  const new(this._preferences);

  static const key = 'demo_mode';

  final SharedPreferencesWithCache _preferences;

  static Future<SharedPreferencesDemoModeStore> open() async {
    final preferences = await SharedPreferencesWithCache.create(
      cacheOptions: const SharedPreferencesWithCacheOptions(allowList: {key}),
    );
    return SharedPreferencesDemoModeStore(preferences);
  }

  @override
  bool get enabled => _preferences.getBool(key) ?? false;

  @override
  Future<void> enable() => _preferences.setBool(key, true);

  @override
  Future<void> disable() => _preferences.remove(key);
}

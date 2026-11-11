import 'package:open_ring/features/settings/domain/app_language.dart';
import 'package:shared_preferences/shared_preferences.dart';

// The worker runs in its own isolate without the UI's cached store.
Future<AppLanguage?> readStoredAppLanguage([
  SharedPreferencesAsync? preferences,
]) async {
  final store = preferences ?? SharedPreferencesAsync();
  final name = await store.getString(SharedPreferencesAppLanguageStore.key);
  return AppLanguage.values.asNameMap()[name];
}

final class SharedPreferencesAppLanguageStore implements AppLanguageStore {
  const new(this._preferences);

  static const key = 'app_language';

  final SharedPreferencesWithCache _preferences;

  // Cached so the first frame is already in the chosen language.
  static Future<SharedPreferencesAppLanguageStore> open() async {
    final preferences = await SharedPreferencesWithCache.create(
      cacheOptions: const SharedPreferencesWithCacheOptions(allowList: {key}),
    );
    return SharedPreferencesAppLanguageStore(preferences);
  }

  @override
  AppLanguage? read() =>
      AppLanguage.values.asNameMap()[_preferences.getString(key)];

  @override
  Future<void> write(AppLanguage language) =>
      _preferences.setString(key, language.name);
}

import 'package:open_ring/features/onboarding/domain/onboarding_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SharedPreferencesOnboardingStore implements OnboardingStore {
  const new(this._preferences);

  static const key = 'onboarding_completed';

  final SharedPreferencesWithCache _preferences;

  // Cached so the router knows the first route before the first frame.
  static Future<SharedPreferencesOnboardingStore> open() async {
    final preferences = await SharedPreferencesWithCache.create(
      cacheOptions: const SharedPreferencesWithCacheOptions(allowList: {key}),
    );
    return SharedPreferencesOnboardingStore(preferences);
  }

  @override
  bool get completed => _preferences.getBool(key) ?? false;

  @override
  Future<void> complete() => _preferences.setBool(key, true);

  @override
  Future<void> reset() => _preferences.remove(key);
}

import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/settings/infrastructure/legacy_preferences.dart';
import 'package:open_ring/features/settings/infrastructure/shared_preferences_unit_system_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  test('an old stored language is removed, other settings stay', () async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.withData({
          'app_language': 'japanese',
          SharedPreferencesUnitSystemStore.key: 'imperial',
        });

    await clearLegacyPreferences();

    final keys = await SharedPreferencesAsync().getKeys();
    expect(keys, {SharedPreferencesUnitSystemStore.key});
  });

  test('nothing stored is fine', () async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();

    await clearLegacyPreferences();

    expect(await SharedPreferencesAsync().getKeys(), isEmpty);
  });
}

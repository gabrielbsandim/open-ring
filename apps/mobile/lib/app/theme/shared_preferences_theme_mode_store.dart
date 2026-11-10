import 'package:flutter/material.dart';
import 'package:open_ring/app/theme/theme_mode_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SharedPreferencesThemeModeStore implements ThemeModeStore {
  const new(this._preferences);

  static const key = 'theme_mode';

  final SharedPreferencesWithCache _preferences;

  // A cached instance keeps read() synchronous, so the first frame already
  // has the saved mode and never flashes the wrong theme.
  static Future<SharedPreferencesThemeModeStore> open() async {
    final preferences = await SharedPreferencesWithCache.create(
      cacheOptions: const SharedPreferencesWithCacheOptions(allowList: {key}),
    );
    return SharedPreferencesThemeModeStore(preferences);
  }

  @override
  ThemeMode? read() =>
      ThemeMode.values.asNameMap()[_preferences.getString(key)];

  @override
  Future<void> write(ThemeMode mode) => _preferences.setString(key, mode.name);
}

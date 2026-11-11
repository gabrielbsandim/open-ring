import 'package:open_ring/app/theme/shared_preferences_theme_mode_store.dart';
import 'package:open_ring/core/database/app_database.dart';
import 'package:open_ring/features/health_sync/infrastructure/shared_preferences_health_write_preferences.dart';
import 'package:open_ring/features/ring/infrastructure/shared_preferences_ring_alert_preferences.dart';
import 'package:open_ring/features/ring/infrastructure/shared_preferences_sync_interval_store.dart';
import 'package:open_ring/features/settings/application/delete_all_data_controller.dart';
import 'package:open_ring/features/settings/infrastructure/shared_preferences_app_language_store.dart';
import 'package:open_ring/features/settings/infrastructure/shared_preferences_unit_system_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

final class DeviceLocalDataEraser implements LocalDataEraser {
  new(this._db, [SharedPreferencesAsync? preferences])
    : _preferences = preferences;

  static const Set<String> preferenceKeys = {
    SharedPreferencesUnitSystemStore.key,
    SharedPreferencesAppLanguageStore.key,
    SharedPreferencesThemeModeStore.key,
    SharedPreferencesSyncIntervalStore.key,
    SharedPreferencesRingAlertPreferences.offKey,
    SharedPreferencesRingAlertPreferences.warnedKey,
    SharedPreferencesHealthWritePreferences.key,
  };

  final AppDatabase _db;
  SharedPreferencesAsync? _preferences;

  SharedPreferencesAsync get _store =>
      _preferences ??= SharedPreferencesAsync();

  @override
  Future<void> eraseAll() async {
    await _db.transaction(() async {
      await _db.customStatement('PRAGMA defer_foreign_keys = ON');
      for (final table in _db.allTables) {
        await _db.delete(table).go();
      }
    });
    await _store.clear(allowList: preferenceKeys);
  }
}

import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/app/theme/shared_preferences_theme_mode_store.dart';
import 'package:open_ring/features/body/infrastructure/shared_preferences_hide_numbers_store.dart';
import 'package:open_ring/features/modules/infrastructure/shared_preferences_module_store.dart';
import 'package:open_ring/features/onboarding/infrastructure/shared_preferences_onboarding_store.dart';
import 'package:open_ring/features/open_score/infrastructure/shared_preferences_celebration_store.dart';
import 'package:open_ring/features/open_score/infrastructure/shared_preferences_week_goal_store.dart';
import 'package:open_ring/features/settings/domain/user_profile.dart';
import 'package:open_ring/features/settings/infrastructure/device_local_data_eraser.dart';
import 'package:open_ring/features/settings/infrastructure/drift_user_profile_store.dart';
import 'package:open_ring/features/settings/infrastructure/legacy_preferences.dart';
import 'package:open_ring/features/settings/infrastructure/shared_preferences_unit_system_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import '../../../helpers/database.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.withData({
          SharedPreferencesUnitSystemStore.key: 'imperial',
          legacyPreferenceKeys.first: 'german',
          SharedPreferencesThemeModeStore.key: 'dark',
          SharedPreferencesOnboardingStore.key: true,
          SharedPreferencesModuleStore.key: ['body', 'trajectory'],
          SharedPreferencesModuleStore.shortcutKey: true,
          SharedPreferencesHideNumbersStore.key: true,
          SharedPreferencesWeekGoalStore.key: 5,
          SharedPreferencesCelebrationStore.key: '2026-11-15',
          'some_plugin_key': 'kept',
        });
  });

  test('empties every table, the paired ring included', () async {
    final db = await pairedDatabase();
    await db.customStatement(
      'INSERT INTO hr_samples (device_id, at_utc_ms, offset_minutes, bpm) '
      "VALUES ('$ringId', 1, 0, 61)",
    );
    await db.customStatement(
      'INSERT INTO weigh_ins (at_utc_ms, offset_minutes, kilograms, source) '
      "VALUES (1, 0, 78.2, 'manual')",
    );
    await DriftUserProfileStore(db)
        .save(const UserProfile(birthYear: 1990), at: DateTime(2026, 11));

    await DeviceLocalDataEraser(db).eraseAll();

    for (final table in db.allTables) {
      expect(
        await rowCount(db, table.actualTableName),
        0,
        reason: table.actualTableName,
      );
    }
  });

  test('removes the app preferences and leaves the rest', () async {
    await DeviceLocalDataEraser(memoryDatabase()).eraseAll();

    final keys = await SharedPreferencesAsync().getKeys();
    expect(keys, {SharedPreferencesOnboardingStore.key, 'some_plugin_key'});
  });
}

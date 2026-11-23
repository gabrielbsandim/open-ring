import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/app/theme/shared_preferences_theme_mode_store.dart';
import 'package:open_ring/core/database/app_database.dart';
import 'package:open_ring/features/body/infrastructure/shared_preferences_hide_numbers_store.dart';
import 'package:open_ring/features/food/domain/photo_store.dart';
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

import '../../../helpers/ai_fakes.dart';
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

    await DeviceLocalDataEraser(
      db,
      InMemoryPhotoStore(),
      secrets: InMemorySecretStore(),
    ).eraseAll();

    for (final table in db.allTables) {
      expect(
        await rowCount(db, table.actualTableName),
        0,
        reason: table.actualTableName,
      );
    }
  });

  test('leaves no rated workout, recorded or imported', () async {
    final db = memoryDatabase();
    await db.customStatement(
      'INSERT INTO workouts (client_id, activity_type, start_utc_ms, '
      'end_utc_ms, offset_minutes, effort_rating) '
      "VALUES ('phone:1', 'running', 1, 2, 0, 7)",
    );
    await db.customStatement(
      'INSERT INTO imported_workouts (record_id, source, activity_type, '
      'start_utc_ms, end_utc_ms, offset_minutes, imported_at_utc_ms, '
      "effort_rating) VALUES ('w1', 'com.example', 'running', 1, 2, 0, 3, 8)",
    );

    await DeviceLocalDataEraser(
      db,
      InMemoryPhotoStore(),
      secrets: InMemorySecretStore(),
    ).eraseAll();

    expect(await rowCount(db, 'workouts'), 0);
    expect(await rowCount(db, 'imported_workouts'), 0);
    final rated = await db
        .customSelect(
          'SELECT (SELECT COUNT(*) FROM workouts '
          'WHERE effort_rating IS NOT NULL) + (SELECT COUNT(*) '
          'FROM imported_workouts WHERE effort_rating IS NOT NULL) AS c',
        )
        .getSingle();
    expect(rated.read<int>('c'), 0);
  });

  test('removes the app preferences and leaves the rest', () async {
    await DeviceLocalDataEraser(
      memoryDatabase(),
      InMemoryPhotoStore(),
      secrets: InMemorySecretStore(),
    ).eraseAll();

    final keys = await SharedPreferencesAsync().getKeys();
    expect(keys, {SharedPreferencesOnboardingStore.key, 'some_plugin_key'});
  });

  group('criterion 13: meals and their photos', () {
    test('one meal row and two photos leave no row and no byte', () async {
      final db = await pairedDatabase();
      await db.customStatement(_meal);
      final photos = InMemoryPhotoStore();
      await photos.save('a.jpg', Uint8List.fromList([1, 2, 3]));
      await photos.save('b.jpg', Uint8List.fromList([4, 5]));

      await DeviceLocalDataEraser(
        db,
        photos,
        secrets: InMemorySecretStore(),
      ).eraseAll();

      expect(await rowCount(db, 'meals'), 0);
      for (final table in db.allTables) {
        expect(
          await rowCount(db, table.actualTableName),
          0,
          reason: table.actualTableName,
        );
      }
      expect(await photos.totalBytes(), 0);
    });
  });

  group('criterion 14: a photo folder that fails to empty', () {
    late AppDatabase db;
    late InMemoryPhotoStore photos;

    setUp(() async {
      db = await pairedDatabase();
      await db.customStatement(_meal);
      photos = InMemoryPhotoStore();
      await photos.save('a.jpg', Uint8List.fromList([1, 2, 3]));
    });

    test('eraseAll throws the FileSystemException', () async {
      await expectLater(
        DeviceLocalDataEraser(
          db,
          _FailingPhotoStore(photos),
          secrets: InMemorySecretStore(),
        ).eraseAll(),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('the tables are already empty when it throws', () async {
      await DeviceLocalDataEraser(
        db,
        _FailingPhotoStore(photos),
        secrets: InMemorySecretStore(),
      ).eraseAll().catchError((Object _) {}, test: (e) => e is Exception);

      expect(await rowCount(db, 'meals'), 0);
      expect(await rowCount(db, 'ring_devices'), 0);
    });

    test('a second eraseAll with a working store empties the photos', () async {
      await DeviceLocalDataEraser(
        db,
        _FailingPhotoStore(photos),
        secrets: InMemorySecretStore(),
      ).eraseAll().catchError((Object _) {}, test: (e) => e is Exception);
      expect(await photos.totalBytes(), 3);

      await DeviceLocalDataEraser(
        db,
        photos,
        secrets: InMemorySecretStore(),
      ).eraseAll();

      expect(await photos.totalBytes(), 0);
    });
  });
}

const _meal =
    'INSERT INTO meals (at_utc_ms, offset_minutes, photo, created_at_utc_ms) '
    "VALUES (1764559800000, -180, 'a.jpg', 1764559800000)";

final class _FailingPhotoStore implements PhotoStore {
  const new(this._inner);

  final PhotoStore _inner;

  @override
  Future<void> save(String name, Uint8List bytes) => _inner.save(name, bytes);

  @override
  Future<Uint8List?> read(String name) => _inner.read(name);

  @override
  Future<bool> delete(String name) => _inner.delete(name);

  @override
  Future<int> deleteAll() async =>
      throw const FileSystemException('Directory not empty', 'meal_photos');

  @override
  Future<Map<String, int>> fileBytes() => _inner.fileBytes();

  @override
  Future<int> totalBytes() => _inner.totalBytes();
}

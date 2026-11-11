import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/core/database/app_database.dart';

import '../../helpers/database.dart';

void main() {
  const planTables = {
    'ring_devices',
    'sync_cursors',
    'sync_locks',
    'sync_runs',
    'activity_buckets',
    'hr_samples',
    'spo2_samples',
    'stress_samples',
    'hrv_samples',
    'sleep_sessions',
    'sleep_segments',
    'workouts',
    'workout_hr_samples',
    'workout_route_points',
    'workout_pauses',
    'health_outbox',
    'source_priorities',
    'user_profile',
    'imported_sleep_sessions',
    'imported_sleep_stages',
    'health_reads',
    'imported_workouts',
  };

  test('creates every table listed in the plan', () async {
    final db = memoryDatabase();

    final rows = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table' "
          "AND name NOT LIKE 'sqlite_%'",
        )
        .get();

    expect(rows.map((r) => r.read<String>('name')).toSet(), planTables);
  });

  test('enforces foreign keys', () async {
    final db = memoryDatabase();

    final row = await db.customSelect('PRAGMA foreign_keys').getSingle();

    expect(row.read<int>('foreign_keys'), 1);
  });

  test('keeps a single user profile row', () async {
    final db = memoryDatabase();
    await db
        .into(db.userProfile)
        .insert(UserProfileCompanion.insert(updatedAtUtcMs: 1));

    await expectLater(
      db
          .into(db.userProfile)
          .insert(
            UserProfileCompanion.insert(id: const Value(2), updatedAtUtcMs: 1),
          ),
      throwsA(anything),
    );
  });

  test('a workout client id is unique', () async {
    final db = memoryDatabase();
    WorkoutsCompanion workout() => WorkoutsCompanion.insert(
      clientId: 'w-1',
      activityType: 'run',
      startUtcMs: 1,
      offsetMinutes: 0,
    );
    await db.into(db.workouts).insert(workout());

    await expectLater(
      db.into(db.workouts).insert(workout()),
      throwsA(anything),
    );
  });
}

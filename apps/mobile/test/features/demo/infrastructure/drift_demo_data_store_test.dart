import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/core/database/app_database.dart';
import 'package:open_ring/features/activity/application/activity_providers.dart';
import 'package:open_ring/features/activity/infrastructure/drift_activity_history_reader.dart';
import 'package:open_ring/features/demo/domain/demo_data.dart';
import 'package:open_ring/features/demo/domain/demo_data_generator.dart';
import 'package:open_ring/features/demo/infrastructure/demo_workout_store.dart';
import 'package:open_ring/features/demo/infrastructure/drift_demo_data_store.dart';
import 'package:open_ring/features/heart/application/heart_providers.dart';
import 'package:open_ring/features/heart/infrastructure/drift_heart_history_reader.dart';
import 'package:open_ring/features/ring/infrastructure/ring_devices_dao.dart';
import 'package:open_ring/features/ring/infrastructure/ring_samples_dao.dart';
import 'package:open_ring/features/settings/application/user_profile_providers.dart';
import 'package:open_ring/features/settings/domain/user_profile.dart';
import 'package:open_ring/features/sleep/application/sleep_providers.dart';
import 'package:open_ring/features/sleep/infrastructure/drift_imported_sleep_reader.dart';
import 'package:open_ring/features/sleep/infrastructure/drift_rem_reporting_reader.dart';
import 'package:open_ring/features/sleep/infrastructure/drift_sleep_history_reader.dart';
import 'package:open_ring/features/today/application/today_providers.dart';
import 'package:open_ring/features/today/application/today_view.dart';
import 'package:open_ring/features/today/infrastructure/drift_ring_status_reader.dart';
import 'package:open_ring/features/trends/application/trends_providers.dart';
import 'package:open_ring/features/trends/domain/trend_metric.dart';
import 'package:open_ring/features/workout/application/workout_history_providers.dart';
import 'package:open_ring/features/workout/infrastructure/drift_imported_workout_reader.dart';
import 'package:open_ring/features/workout/infrastructure/drift_workout_history_reader.dart';
import 'package:ring_driver/ring_driver.dart';

import '../../../helpers/database.dart';

final now = DateTime(2026, 11, 11, 14, 37);

// The first two keep the real ring's rows after a wipe.
const deviceTables = [
  'ring_devices',
  'hr_samples',
  'activity_buckets',
  'hrv_samples',
  'spo2_samples',
  'stress_samples',
  'sleep_sessions',
  'sleep_segments',
  'sync_runs',
  'workouts',
  'workout_hr_samples',
];

ProviderContainer screensOver(AppDatabase db) {
  final container = ProviderContainer.test(
    overrides: [
      clockProvider.overrideWithValue(() => now),
      ringStatusReaderProvider.overrideWithValue(DriftRingStatusReader(db)),
      sleepHistoryReaderProvider.overrideWithValue(DriftSleepHistoryReader(db)),
      importedSleepReaderProvider.overrideWithValue(
        DriftImportedSleepReader(db),
      ),
      remReportingReaderProvider.overrideWithValue(DriftRemReportingReader(db)),
      heartHistoryReaderProvider.overrideWithValue(DriftHeartHistoryReader(db)),
      activityHistoryReaderProvider.overrideWithValue(
        DriftActivityHistoryReader(db),
      ),
      workoutHistoryReaderProvider.overrideWithValue(
        DriftWorkoutHistoryReader(db),
      ),
      importedWorkoutReaderProvider.overrideWithValue(
        DriftImportedWorkoutReader(db),
      ),
      userProfileStoreProvider.overrideWithValue(InMemoryUserProfileStore()),
    ],
  );
  return container;
}

void main() {
  late AppDatabase db;
  late DemoData data;

  setUp(() {
    db = memoryDatabase();
    data = DemoDataGenerator(now: now).generate();
  });

  test('seeds every kind without queuing anything for Health', () async {
    await DriftDemoDataStore(db).replace(data);

    expect(await rowCount(db, 'ring_devices'), 1);
    expect(await rowCount(db, 'hr_samples'), data.heartRate.length);
    expect(await rowCount(db, 'hrv_samples'), data.hrv.length);
    expect(await rowCount(db, 'spo2_samples'), data.spo2.length);
    expect(await rowCount(db, 'stress_samples'), data.stress.length);
    expect(await rowCount(db, 'activity_buckets'), data.activity.length);
    expect(await rowCount(db, 'sleep_sessions'), 15);
    expect(await rowCount(db, 'sleep_segments'), data.sleep.length);
    expect(await rowCount(db, 'workouts'), 2);
    expect(await rowCount(db, 'workout_hr_samples'), greaterThan(0));
    expect(await rowCount(db, 'sync_runs'), 3);
    expect(await rowCount(db, 'health_outbox'), 0);
  });

  test('a second seed replaces the first instead of adding to it', () async {
    final store = DriftDemoDataStore(db);
    await store.replace(data);
    await store.replace(
      DemoDataGenerator(now: now.add(const Duration(hours: 2))).generate(),
    );

    expect(await rowCount(db, 'ring_devices'), 1);
    expect(await rowCount(db, 'workouts'), 2);
    expect(await rowCount(db, 'sync_runs'), 3);
  });

  test('every main screen reads realistic numbers', () async {
    await DriftDemoDataStore(db).replace(data);
    final container = screensOver(db);

    final today = await container.read(todayViewProvider.future);
    final readiness = await container.read(readinessProvider.future);
    final heart = await container.read(heartDayProvider.future);
    final week = await container.read(sleepWeekProvider.future);
    final workouts = await container.read(recentWorkoutsProvider.future);
    final trends = await container.read(trendHistoryProvider.future);

    expect(today.freshness, SyncFreshness.fresh);
    expect(today.ring.name, 'R09 Demo');
    expect(today.ring.batteryPercent, 76);
    expect(today.activity!.steps, greaterThan(1000));
    expect(readiness.score, isA<Scored<ReadinessFactor>>());
    expect(readiness.value, inInclusiveRange(40, 100));
    expect(readiness.activityLoad, isNotNull);
    expect(week.latest.night, isNotNull);
    expect(week.latest.score, isA<Scored<SleepFactor>>());
    expect(heart.spo2Night, isNotNull);
    expect(heart.stressSummary, isNotNull);
    expect(workouts, hasLength(2));
    expect(trends.values(TrendMetric.restingHeartRate), isNotEmpty);
  });

  test('wiping removes the demo ring and keeps a real one', () async {
    await DriftDemoDataStore(db).replace(data);
    await RingDevicesDao(db).pair(ringIdentity, at: now);
    await RingSamplesDao(db)
        .upsertHeartRate(ringId, [HeartRateSample(at: now, bpm: 61)]);
    final recorded = DemoDataGenerator(
      now: now.subtract(const Duration(days: 30)),
    ).generate().workouts.first;
    await DemoWorkoutStore(db).save(recorded, at: now);

    await DriftDemoDataStore(db).wipe();

    expect(await rowCount(db, 'ring_devices'), 1);
    expect(await rowCount(db, 'hr_samples'), 1);
    for (final table in deviceTables.skip(2)) {
      expect(await rowCount(db, table), 0, reason: table);
    }
  });

  test('a demo workout is never queued for Health', () async {
    await DemoWorkoutStore(db).save(data.workouts.last, at: now);

    expect(await rowCount(db, 'workouts'), 1);
    expect(await rowCount(db, 'health_outbox'), 0);
  });
}

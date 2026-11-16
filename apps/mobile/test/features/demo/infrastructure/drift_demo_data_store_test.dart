import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/core/database/app_database.dart';
import 'package:open_ring/features/activity/application/activity_providers.dart';
import 'package:open_ring/features/activity/infrastructure/drift_activity_history_reader.dart';
import 'package:open_ring/features/body/application/weigh_in_providers.dart';
import 'package:open_ring/features/body/application/weight_summary.dart';
import 'package:open_ring/features/body/domain/weigh_in.dart';
import 'package:open_ring/features/body/infrastructure/drift_weigh_in_store.dart';
import 'package:open_ring/features/demo/domain/demo_data.dart';
import 'package:open_ring/features/demo/domain/demo_data_generator.dart';
import 'package:open_ring/features/demo/infrastructure/demo_workout_store.dart';
import 'package:open_ring/features/demo/infrastructure/drift_demo_data_store.dart';
import 'package:open_ring/features/effort/application/effort_providers.dart';
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
import 'package:open_ring/features/workout/domain/workout_session.dart';
import 'package:open_ring/features/workout/domain/workout_type.dart';
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
      weighInStoreProvider.overrideWithValue(DriftWeighInStore(db)),
    ],
  );
  return container;
}

Future<Map<int, int?>> ratingsByStart(AppDatabase db) async {
  final rows = await db
      .customSelect('SELECT start_utc_ms, effort_rating FROM workouts')
      .get();
  return {
    for (final row in rows)
      row.read<int>('start_utc_ms'): row.read<int?>('effort_rating'),
  };
}

Future<int> ratedRows(AppDatabase db) async {
  final row = await db
      .customSelect(
        'SELECT COUNT(*) AS c FROM workouts WHERE effort_rating IS NOT NULL',
      )
      .getSingle();
  return row.read<int>('c');
}

DemoData withRatings(DemoData data, Map<DateTime, int> ratings) => DemoData(
  pairedAt: data.pairedAt,
  syncedAt: data.syncedAt,
  battery: data.battery,
  activity: data.activity,
  heartRate: data.heartRate,
  hrv: data.hrv,
  spo2: data.spo2,
  stress: data.stress,
  sleep: data.sleep,
  workouts: data.workouts,
  syncRuns: data.syncRuns,
  weighIns: data.weighIns,
  workoutRatings: ratings,
);

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
    expect(await rowCount(db, 'weigh_ins'), data.weighIns.length);
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
    expect(await rowCount(db, 'weigh_ins'), data.weighIns.length);
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

  group('weigh-ins', () {
    final typed = WeighInDraft(
      at: DateTime(2026, 11, 10, 8),
      offsetMinutes: 0,
      kilograms: 81.4,
    );

    test('the Body screen reads a trend and a rate from the demo', () async {
      await DriftDemoDataStore(db).replace(data);
      final container = screensOver(db);

      final summary = await container.read(weightSummaryProvider.future);

      expect(summary!.last.source, WeighInSource.demo);
      expect(summary.rate, isA<WeightRateReady>());
      expect((summary.rate as WeightRateReady).perWeek, lessThan(0));
    });

    test('a refresh keeps a weigh-in the user typed', () async {
      final store = DriftDemoDataStore(db);
      await store.replace(data);
      await DriftWeighInStore(db).add(typed);
      await store.replace(data);

      expect(await rowCount(db, 'weigh_ins'), data.weighIns.length + 1);
    });

    test('wiping removes the demo ones and keeps the typed one', () async {
      await DriftDemoDataStore(db).replace(data);
      await DriftWeighInStore(db).add(typed);

      await DriftDemoDataStore(db).wipe();

      final left = await DriftWeighInStore(db).all();
      expect(left.single.kilograms, 81.4);
      expect(left.single.source, WeighInSource.manual);
    });
  });

  test('a demo workout is never queued for Health', () async {
    await DemoWorkoutStore(db).save(data.workouts.last, at: now);

    expect(await rowCount(db, 'workouts'), 1);
    expect(await rowCount(db, 'health_outbox'), 0);
  });

  group('workout ratings', () {
    FinishedWorkout workoutOf(WorkoutType type) =>
        data.workouts.singleWhere((w) => w.type == type);

    test(
      'replace stores 7 on the treadmill row and none on strength',
      () async {
        await DriftDemoDataStore(db).replace(data);

        final stored = await ratingsByStart(db);
        final treadmill = workoutOf(WorkoutType.treadmill).start;
        final strength = workoutOf(WorkoutType.strength).start;
        expect(stored[treadmill.millisecondsSinceEpoch], 7);
        expect(stored[strength.millisecondsSinceEpoch], isNull);
        expect(await ratedRows(db), 1);
      },
    );

    test(
      'the Effort read model returns the treadmill session rated 7',
      () async {
        await DriftDemoDataStore(db).replace(data);
        final container = screensOver(db);

        final sessions = await container.read(effortSessionsProvider.future);

        final treadmill = sessions.singleWhere(
          (s) => s.type == WorkoutType.treadmill,
        );
        final strength = sessions.singleWhere(
          (s) => s.type == WorkoutType.strength,
        );
        expect(treadmill.rating, 7);
        expect(strength.rating, isNull);
      },
    );

    test('replace twice leaves one rated demo row', () async {
      final store = DriftDemoDataStore(db);
      await store.replace(data);
      await store.replace(
        DemoDataGenerator(now: now.add(const Duration(hours: 2))).generate(),
      );

      expect(await rowCount(db, 'workouts'), 2);
      expect(await ratedRows(db), 1);
    });

    test('wipe leaves no rated demo row', () async {
      final store = DriftDemoDataStore(db);
      await store.replace(data);

      await store.wipe();

      expect(await rowCount(db, 'workouts'), 0);
      expect(await ratedRows(db), 0);
    });

    test('a workout saved through DemoWorkoutStore stays unrated', () async {
      await DemoWorkoutStore(db)
          .save(workoutOf(WorkoutType.treadmill), at: now);

      expect(await rowCount(db, 'workouts'), 1);
      expect(await ratedRows(db), 0);
    });

    test(
      'a rating keyed by a start that matches no workout is ignored',
      () async {
        final stray = withRatings(data, {DateTime(2001, 1, 1, 8): 9});

        await DriftDemoDataStore(db).replace(stray);

        expect(await rowCount(db, 'workouts'), 2);
        expect(await ratedRows(db), 0);
      },
    );

    test('the demo rating does not change the coach verdict', () async {
      await DriftDemoDataStore(db).replace(data);
      final rated = await screensOver(db).read(effortCoachProvider.future);
      await DriftDemoDataStore(db).replace(withRatings(data, const {}));
      final unrated = await screensOver(db).read(effortCoachProvider.future);

      expect(rated.rule, unrated.rule);
    });
  });
}

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:open_ring/core/database/app_database.steps.dart';
import 'package:open_ring/core/database/tables/ai_tables.dart';
import 'package:open_ring/core/database/tables/body_tables.dart';
import 'package:open_ring/core/database/tables/goal_tables.dart';
import 'package:open_ring/core/database/tables/health_tables.dart';
import 'package:open_ring/core/database/tables/import_tables.dart';
import 'package:open_ring/core/database/tables/meal_tables.dart';
import 'package:open_ring/core/database/tables/open_score_tables.dart';
import 'package:open_ring/core/database/tables/ring_tables.dart';
import 'package:open_ring/core/database/tables/sample_tables.dart';
import 'package:open_ring/core/database/tables/sleep_tables.dart';
import 'package:open_ring/core/database/tables/workout_tables.dart';
import 'package:open_ring/core/records/health_record_kind.dart';
import 'package:open_ring/core/records/record_kind.dart';
import 'package:ring_driver/ring_driver.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [
    RingDevices,
    SyncCursors,
    SyncLocks,
    SyncRuns,
    ActivityBuckets,
    HrSamples,
    Spo2Samples,
    StressSamples,
    HrvSamples,
    SleepSessions,
    SleepSegments,
    Workouts,
    WorkoutHrSamples,
    WorkoutRoutePoints,
    WorkoutPauses,
    HealthOutbox,
    SourcePriorities,
    UserProfile,
    ImportedSleepSessions,
    ImportedSleepStages,
    HealthReads,
    ImportedWorkouts,
    WeighIns,
    DayTags,
    StepGoalChanges,
    Goals,
    GoalWeeks,
    GoalScreenings,
    Meals,
    AiReports,
    MealAnalyses,
    MealItems,
  ],
)
class AppDatabase extends _$AppDatabase {
  new(super.e);

  @override
  int get schemaVersion => 19;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) => migrator.createAll(),
    onUpgrade: stepByStep(
      from1To2: (migrator, schema) => migrator.createTable(schema.syncLocks),
      from2To3: (migrator, schema) async {
        final outbox = schema.healthOutbox;
        await migrator.addColumn(outbox, outbox.status);
        await migrator.addColumn(outbox, outbox.lastAttemptAtUtcMs);
        await migrator.addColumn(outbox, outbox.nextAttemptAtUtcMs);
        await customStatement(
          "UPDATE health_outbox SET status = 'done' "
          'WHERE completed_at_utc_ms IS NOT NULL',
        );
      },
      from3To4: (migrator, schema) async {
        final profile = schema.userProfile;
        await migrator.addColumn(profile, profile.maxHeartRate);
        await migrator.addColumn(profile, profile.dailyStepGoal);
      },
      from4To5: (migrator, schema) async {
        final workouts = schema.workouts;
        await migrator.addColumn(workouts, workouts.elapsedMs);
        await migrator.addColumn(workouts, workouts.averageHeartRate);
        await migrator.addColumn(workouts, workouts.maxHeartRate);
        await migrator.createTable(schema.workoutPauses);
      },
      from5To6: (migrator, schema) async {
        await migrator.createTable(schema.importedSleepSessions);
        await migrator.createTable(schema.importedSleepStages);
        await migrator.createTable(schema.healthReads);
      },
      from6To7: (migrator, schema) =>
          migrator.createTable(schema.importedWorkouts),
      from7To8: (migrator, schema) async {
        final devices = schema.ringDevices;
        await migrator.addColumn(devices, devices.unpairedAtUtcMs);
        await migrator.addColumn(devices, devices.autoHeartRate);
        await migrator.addColumn(devices, devices.autoSpo2);
        await migrator.addColumn(devices, devices.autoStress);
        await migrator.addColumn(devices, devices.autoHrv);
        await migrator.createTable(schema.syncRuns);
      },
      from8To9: (migrator, schema) async {
        final runs = schema.syncRuns;
        await migrator.addColumn(runs, runs.batteryPercent);
        await migrator.addColumn(runs, runs.batteryCharging);
        await migrator.addColumn(runs, runs.failures);
        await migrator.addColumn(runs, runs.heartRateIntervalSeenMinutes);
      },
      from9To10: (migrator, schema) => _requeueRecentWorkouts(),
      from10To11: (migrator, schema) => migrator.createTable(schema.weighIns),
      from11To12: (migrator, schema) => migrator.createTable(schema.dayTags),
      from12To13: (migrator, schema) async {
        final workouts = schema.workouts;
        final imported = schema.importedWorkouts;
        await migrator.addColumn(workouts, workouts.effortRating);
        await migrator.addColumn(imported, imported.effortRating);
      },
      from13To14: (migrator, schema) =>
          migrator.createTable(schema.stepGoalChanges),
      from14To15: (migrator, schema) async {
        await migrator.createTable(schema.goals);
        await migrator.createTable(schema.goalWeeks);
        await migrator.createTable(schema.goalScreenings);
      },
      from15To16: (migrator, schema) => migrator.createTable(schema.meals),
      from16To17: (migrator, schema) async {
        final workouts = schema.workouts;
        await migrator.addColumn(workouts, workouts.checkpointUtcMs);
      },
      from17To18: (migrator, schema) async {
        await migrator.createTable(schema.aiReports);
        await migrator.createIndex(schema.aiReportsCacheKey);
      },
      from18To19: (migrator, schema) async {
        await migrator.addColumn(schema.meals, schema.meals.keepOnPhone);
        await migrator.createTable(schema.mealAnalyses);
        await migrator.createTable(schema.mealItems);
        await migrator.createIndex(schema.mealAnalysesCacheKey);
        await migrator.createIndex(schema.mealAnalysesStatus);
        await migrator.createIndex(schema.mealItemsAnalysis);
      },
    ),
    beforeOpen: (details) => customStatement('PRAGMA foreign_keys = ON'),
  );

  // Workouts went to Health Connect as automatically recorded, which readers
  // drop; writing the recent ones again stamps them as actively recorded.
  Future<void> _requeueRecentWorkouts() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    final since = DateTime.now().subtract(const Duration(days: 7));
    await customStatement(
      "UPDATE health_outbox SET status = 'pending', attempts = 0, "
      'last_error = NULL, completed_at_utc_ms = NULL, '
      'next_attempt_at_utc_ms = NULL '
      "WHERE kind = ? AND status = 'done' AND from_utc_ms >= ?",
      [HealthRecordKind.workout.name, since.millisecondsSinceEpoch],
    );
  }
}

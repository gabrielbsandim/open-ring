import 'package:drift/drift.dart';
import 'package:open_ring/core/database/app_database.steps.dart';
import 'package:open_ring/core/database/tables/health_tables.dart';
import 'package:open_ring/core/database/tables/import_tables.dart';
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
  ],
)
class AppDatabase extends _$AppDatabase {
  new(super.e);

  @override
  int get schemaVersion => 8;

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
    ),
    beforeOpen: (details) => customStatement('PRAGMA foreign_keys = ON'),
  );
}

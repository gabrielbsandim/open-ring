import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/core/database/app_database.dart';

import '../../helpers/database.dart';
import 'generated/schema.dart';
import 'generated/schema_v1.dart' as v1;
import 'generated/schema_v10.dart' as v10;
import 'generated/schema_v11.dart' as v11;
import 'generated/schema_v12.dart' as v12;
import 'generated/schema_v13.dart' as v13;
import 'generated/schema_v14.dart' as v14;
import 'generated/schema_v15.dart' as v15;
import 'generated/schema_v16.dart' as v16;
import 'generated/schema_v2.dart' as v2;
import 'generated/schema_v3.dart' as v3;
import 'generated/schema_v4.dart' as v4;
import 'generated/schema_v5.dart' as v5;
import 'generated/schema_v6.dart' as v6;
import 'generated/schema_v7.dart' as v7;
import 'generated/schema_v8.dart' as v8;
import 'generated/schema_v9.dart' as v9;

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late SchemaVerifier verifier;

  setUpAll(() => verifier = SchemaVerifier(GeneratedHelper()));

  test('the code schema version has a dumped schema', () {
    expect(memoryDatabase().schemaVersion, GeneratedHelper.versions.last);
  });

  test(
    'a database created from code matches the latest dumped schema',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      await verifier.migrateAndValidate(db, GeneratedHelper.versions.last);
    },
  );

  test('v1 migrates to v2 and keeps the paired ring', () async {
    const ring = v1.RingDevicesData(
      deviceId: ringId,
      name: 'R09_C0FE',
      pairedAtUtcMs: 1762732800000,
    );

    await verifier.testWithDataIntegrity(
      oldVersion: 1,
      newVersion: 2,
      createOld: v1.DatabaseAtV1.new,
      createNew: v2.DatabaseAtV2.new,
      openTestedDatabase: AppDatabase.new,
      createItems: (batch, oldDb) => batch.insert(oldDb.ringDevices, ring),
      validateItems: (newDb) async {
        expect(await newDb.select(newDb.ringDevices).get(), [
          const v2.RingDevicesData(
            deviceId: ringId,
            name: 'R09_C0FE',
            pairedAtUtcMs: 1762732800000,
          ),
        ]);
        expect(await newDb.select(newDb.syncLocks).get(), isEmpty);
      },
    );
  });

  test(
    'v2 migrates to v3 and keeps the outbox, done rows marked done',
    () async {
      v2.HealthOutboxData row(int id, {int? completedAt}) =>
          v2.HealthOutboxData(
            id: id,
            kind: 'sleep',
            deviceId: ringId,
            fromUtcMs: 1762729200000,
            toUtcMs: 1762758000000,
            recordCount: 5,
            enqueuedAtUtcMs: 1762758000000,
            attempts: 1,
            lastError: 'denied',
            completedAtUtcMs: completedAt,
          );

      await verifier.testWithDataIntegrity(
        oldVersion: 2,
        newVersion: 3,
        createOld: v2.DatabaseAtV2.new,
        createNew: v3.DatabaseAtV3.new,
        openTestedDatabase: AppDatabase.new,
        createItems: (batch, oldDb) => batch.insertAll(oldDb.healthOutbox, [
          row(1),
          row(2, completedAt: 1762758060000),
        ]),
        validateItems: (newDb) async {
          final rows = await newDb.select(newDb.healthOutbox).get();
          expect(
            rows.map((r) => (r.id, r.status, r.attempts, r.nextAttemptAtUtcMs)),
            [(1, 'pending', 1, null), (2, 'done', 1, null)],
          );
          expect(rows.first.lastError, 'denied');
        },
      );
    },
  );

  test(
    'v3 migrates to v4 and keeps the profile with empty new fields',
    () async {
      const profile = v3.UserProfileData(
        id: 1,
        birthYear: 1990,
        sex: 'female',
        heightCentimeters: 168,
        weightKilograms: 61.5,
        updatedAtUtcMs: 1762732800000,
      );

      await verifier.testWithDataIntegrity(
        oldVersion: 3,
        newVersion: 4,
        createOld: v3.DatabaseAtV3.new,
        createNew: v4.DatabaseAtV4.new,
        openTestedDatabase: AppDatabase.new,
        createItems: (batch, oldDb) => batch.insert(oldDb.userProfile, profile),
        validateItems: (newDb) async {
          expect(await newDb.select(newDb.userProfile).get(), [
            const v4.UserProfileData(
              id: 1,
              birthYear: 1990,
              sex: 'female',
              heightCentimeters: 168,
              weightKilograms: 61.5,
              updatedAtUtcMs: 1762732800000,
            ),
          ]);
        },
      );
    },
  );

  test('v4 migrates to v5 and keeps workouts with empty new fields', () async {
    const workout = v4.WorkoutsData(
      id: 1,
      clientId: 'phone:1762758000000',
      activityType: 'running',
      startUtcMs: 1762758000000,
      endUtcMs: 1762759800000,
      offsetMinutes: -180,
      distanceMeters: 5012.5,
      activeKilocalories: 410,
    );
    const sample = v4.WorkoutHrSamplesData(
      workoutId: 1,
      atUtcMs: 1762758060000,
      offsetMinutes: -180,
      bpm: 142,
    );

    await verifier.testWithDataIntegrity(
      oldVersion: 4,
      newVersion: 5,
      createOld: v4.DatabaseAtV4.new,
      createNew: v5.DatabaseAtV5.new,
      openTestedDatabase: AppDatabase.new,
      createItems: (batch, oldDb) => batch
        ..insert(oldDb.workouts, workout)
        ..insert(oldDb.workoutHrSamples, sample),
      validateItems: (newDb) async {
        expect(await newDb.select(newDb.workouts).get(), [
          const v5.WorkoutsData(
            id: 1,
            clientId: 'phone:1762758000000',
            activityType: 'running',
            startUtcMs: 1762758000000,
            endUtcMs: 1762759800000,
            offsetMinutes: -180,
            distanceMeters: 5012.5,
            activeKilocalories: 410,
          ),
        ]);
        expect(await newDb.select(newDb.workoutHrSamples).get(), hasLength(1));
        expect(await newDb.select(newDb.workoutPauses).get(), isEmpty);
      },
    );
  });

  test(
    'v5 migrates to v6, keeps the ring nights and adds empty import tables',
    () async {
      const ring = v5.RingDevicesData(
        deviceId: ringId,
        name: 'R09_C0FE',
        pairedAtUtcMs: 1762732800000,
      );
      const night = v5.SleepSessionsData(
        deviceId: ringId,
        startUtcMs: 1762729080000,
        endUtcMs: 1762753320000,
        offsetMinutes: -180,
      );

      await verifier.testWithDataIntegrity(
        oldVersion: 5,
        newVersion: 6,
        createOld: v5.DatabaseAtV5.new,
        createNew: v6.DatabaseAtV6.new,
        openTestedDatabase: AppDatabase.new,
        createItems: (batch, oldDb) => batch
          ..insert(oldDb.ringDevices, ring)
          ..insert(oldDb.sleepSessions, night),
        validateItems: (newDb) async {
          expect(await newDb.select(newDb.sleepSessions).get(), [
            const v6.SleepSessionsData(
              deviceId: ringId,
              startUtcMs: 1762729080000,
              endUtcMs: 1762753320000,
              offsetMinutes: -180,
            ),
          ]);
          expect(
            await newDb.select(newDb.importedSleepSessions).get(),
            isEmpty,
          );
          expect(await newDb.select(newDb.importedSleepStages).get(), isEmpty);
          expect(await newDb.select(newDb.healthReads).get(), isEmpty);
        },
      );
    },
  );

  test(
    'v6 migrates to v7, keeps imported nights and adds empty workouts',
    () async {
      const session = v6.ImportedSleepSessionsData(
        recordId: 'n1',
        source: 'com.garmin.android.apps.connectmobile',
        startUtcMs: 1762729080000,
        endUtcMs: 1762753320000,
        offsetMinutes: -180,
        importedAtUtcMs: 1762765200000,
      );
      const read = v6.HealthReadsData(
        kind: 'sleep',
        enabled: 1,
        lastReadAtUtcMs: 1762765200000,
      );

      await verifier.testWithDataIntegrity(
        oldVersion: 6,
        newVersion: 7,
        createOld: v6.DatabaseAtV6.new,
        createNew: v7.DatabaseAtV7.new,
        openTestedDatabase: AppDatabase.new,
        createItems: (batch, oldDb) => batch
          ..insert(oldDb.importedSleepSessions, session)
          ..insert(oldDb.healthReads, read),
        validateItems: (newDb) async {
          expect(await newDb.select(newDb.importedSleepSessions).get(), [
            const v7.ImportedSleepSessionsData(
              recordId: 'n1',
              source: 'com.garmin.android.apps.connectmobile',
              startUtcMs: 1762729080000,
              endUtcMs: 1762753320000,
              offsetMinutes: -180,
              importedAtUtcMs: 1762765200000,
            ),
          ]);
          expect(await newDb.select(newDb.healthReads).get(), [
            const v7.HealthReadsData(
              kind: 'sleep',
              enabled: 1,
              lastReadAtUtcMs: 1762765200000,
            ),
          ]);
          expect(await newDb.select(newDb.importedWorkouts).get(), isEmpty);
        },
      );
    },
  );

  test(
    'v7 migrates to v8, keeps the ring paired with every measurement on',
    () async {
      const ring = v7.RingDevicesData(
        deviceId: ringId,
        name: 'R09_C0FE',
        pairedAtUtcMs: 1762732800000,
        lastSyncAtUtcMs: 1762765200000,
      );

      await verifier.testWithDataIntegrity(
        oldVersion: 7,
        newVersion: 8,
        createOld: v7.DatabaseAtV7.new,
        createNew: v8.DatabaseAtV8.new,
        openTestedDatabase: AppDatabase.new,
        createItems: (batch, oldDb) => batch.insert(oldDb.ringDevices, ring),
        validateItems: (newDb) async {
          expect(await newDb.select(newDb.ringDevices).get(), [
            const v8.RingDevicesData(
              deviceId: ringId,
              name: 'R09_C0FE',
              pairedAtUtcMs: 1762732800000,
              lastSyncAtUtcMs: 1762765200000,
              autoHeartRate: 1,
              autoSpo2: 1,
              autoStress: 1,
              autoHrv: 1,
            ),
          ]);
          expect(await newDb.select(newDb.syncRuns).get(), isEmpty);
        },
      );
    },
  );

  test('v8 migrates to v9 and keeps the sync log', () async {
    const ring = v8.RingDevicesData(
      deviceId: ringId,
      name: 'R09_C0FE',
      pairedAtUtcMs: 1762732800000,
      autoHeartRate: 1,
      autoSpo2: 1,
      autoStress: 1,
      autoHrv: 1,
    );
    const run = v8.SyncRunsData(
      id: 1,
      deviceId: ringId,
      atUtcMs: 1762765200000,
      outcome: 'partial',
      kinds: 'heartRate',
      recordCount: 12,
    );

    await verifier.testWithDataIntegrity(
      oldVersion: 8,
      newVersion: 9,
      createOld: v8.DatabaseAtV8.new,
      createNew: v9.DatabaseAtV9.new,
      openTestedDatabase: AppDatabase.new,
      createItems: (batch, oldDb) {
        batch
          ..insert(oldDb.ringDevices, ring)
          ..insert(oldDb.syncRuns, run);
      },
      validateItems: (newDb) async {
        expect(await newDb.select(newDb.syncRuns).get(), [
          const v9.SyncRunsData(
            id: 1,
            deviceId: ringId,
            atUtcMs: 1762765200000,
            outcome: 'partial',
            kinds: 'heartRate',
            recordCount: 12,
            failures: '',
          ),
        ]);
      },
    );
  });

  test(
    'v10 migrates to v11, keeps the data and adds an empty weigh_ins',
    () async {
      const ring = v10.RingDevicesData(
        deviceId: ringId,
        name: 'R09_C0FE',
        pairedAtUtcMs: 1762732800000,
        autoHeartRate: 1,
        autoSpo2: 1,
        autoStress: 1,
        autoHrv: 1,
      );
      const profile = v10.UserProfileData(id: 1, updatedAtUtcMs: 1762765200000);

      await verifier.testWithDataIntegrity(
        oldVersion: 10,
        newVersion: 11,
        createOld: v10.DatabaseAtV10.new,
        createNew: v11.DatabaseAtV11.new,
        openTestedDatabase: AppDatabase.new,
        createItems: (batch, oldDb) => batch
          ..insert(oldDb.ringDevices, ring)
          ..insert(oldDb.userProfile, profile),
        validateItems: (newDb) async {
          expect(await newDb.select(newDb.ringDevices).get(), [
            const v11.RingDevicesData(
              deviceId: ringId,
              name: 'R09_C0FE',
              pairedAtUtcMs: 1762732800000,
              autoHeartRate: 1,
              autoSpo2: 1,
              autoStress: 1,
              autoHrv: 1,
            ),
          ]);
          expect(await newDb.select(newDb.userProfile).get(), [
            const v11.UserProfileData(id: 1, updatedAtUtcMs: 1762765200000),
          ]);
          expect(await newDb.select(newDb.weighIns).get(), isEmpty);
        },
      );
    },
  );

  test(
    'v11 migrates to v12, keeps the data and adds an empty day_tags',
    () async {
      const ring = v11.RingDevicesData(
        deviceId: ringId,
        name: 'R09_C0FE',
        pairedAtUtcMs: 1762732800000,
        autoHeartRate: 1,
        autoSpo2: 1,
        autoStress: 1,
        autoHrv: 1,
      );
      const profile = v11.UserProfileData(id: 1, updatedAtUtcMs: 1762765200000);
      const weighIn = v11.WeighInsData(
        id: 1,
        atUtcMs: 1762765200000,
        offsetMinutes: -180,
        kilograms: 80.4,
        source: 'manual',
      );

      await verifier.testWithDataIntegrity(
        oldVersion: 11,
        newVersion: 12,
        createOld: v11.DatabaseAtV11.new,
        createNew: v12.DatabaseAtV12.new,
        openTestedDatabase: AppDatabase.new,
        createItems: (batch, oldDb) => batch
          ..insert(oldDb.ringDevices, ring)
          ..insert(oldDb.userProfile, profile)
          ..insert(oldDb.weighIns, weighIn),
        validateItems: (newDb) async {
          expect(await newDb.select(newDb.ringDevices).get(), [
            const v12.RingDevicesData(
              deviceId: ringId,
              name: 'R09_C0FE',
              pairedAtUtcMs: 1762732800000,
              autoHeartRate: 1,
              autoSpo2: 1,
              autoStress: 1,
              autoHrv: 1,
            ),
          ]);
          expect(await newDb.select(newDb.userProfile).get(), [
            const v12.UserProfileData(id: 1, updatedAtUtcMs: 1762765200000),
          ]);
          expect(await newDb.select(newDb.weighIns).get(), [
            const v12.WeighInsData(
              id: 1,
              atUtcMs: 1762765200000,
              offsetMinutes: -180,
              kilograms: 80.4,
              source: 'manual',
            ),
          ]);
          expect(await newDb.select(newDb.dayTags).get(), isEmpty);
        },
      );
    },
  );

  test(
    'v12 migrates to v13, keeps a workout and an imported workout unrated',
    () async {
      const workout = v12.WorkoutsData(
        id: 1,
        clientId: 'phone:1762758000000',
        activityType: 'running',
        startUtcMs: 1762758000000,
        endUtcMs: 1762759800000,
        offsetMinutes: -180,
      );
      const imported = v12.ImportedWorkoutsData(
        recordId: 'w1',
        source: 'com.garmin.android.apps.connectmobile',
        activityType: 'running',
        startUtcMs: 1762758000000,
        endUtcMs: 1762760400000,
        offsetMinutes: -180,
        importedAtUtcMs: 1762765200000,
      );

      await verifier.testWithDataIntegrity(
        oldVersion: 12,
        newVersion: 13,
        createOld: v12.DatabaseAtV12.new,
        createNew: v13.DatabaseAtV13.new,
        openTestedDatabase: AppDatabase.new,
        createItems: (batch, oldDb) => batch
          ..insert(oldDb.workouts, workout)
          ..insert(oldDb.importedWorkouts, imported),
        validateItems: (newDb) async {
          expect(await newDb.select(newDb.workouts).get(), [
            const v13.WorkoutsData(
              id: 1,
              clientId: 'phone:1762758000000',
              activityType: 'running',
              startUtcMs: 1762758000000,
              endUtcMs: 1762759800000,
              offsetMinutes: -180,
            ),
          ]);
          expect(await newDb.select(newDb.importedWorkouts).get(), [
            const v13.ImportedWorkoutsData(
              recordId: 'w1',
              source: 'com.garmin.android.apps.connectmobile',
              activityType: 'running',
              startUtcMs: 1762758000000,
              endUtcMs: 1762760400000,
              offsetMinutes: -180,
              importedAtUtcMs: 1762765200000,
            ),
          ]);
        },
      );
    },
  );

  test('v13 migrates to v14, keeps the profile and starts with no goal '
      'changes', () async {
    const profile = v13.UserProfileData(
      id: 1,
      dailyStepGoal: 9000,
      updatedAtUtcMs: 1762765200000,
    );

    await verifier.testWithDataIntegrity(
      oldVersion: 13,
      newVersion: 14,
      createOld: v13.DatabaseAtV13.new,
      createNew: v14.DatabaseAtV14.new,
      openTestedDatabase: AppDatabase.new,
      createItems: (batch, oldDb) => batch.insert(oldDb.userProfile, profile),
      validateItems: (newDb) async {
        expect(await newDb.select(newDb.userProfile).get(), [
          const v14.UserProfileData(
            id: 1,
            dailyStepGoal: 9000,
            updatedAtUtcMs: 1762765200000,
          ),
        ]);
        expect(await newDb.select(newDb.stepGoalChanges).get(), isEmpty);
      },
    );
  });

  test('v14 migrates to v15, keeps the step goal changes and starts with no '
      'goals', () async {
    const change = v14.StepGoalChangesData(
      effectiveDate: '2026-12-07',
      steps: 10000,
    );

    await verifier.testWithDataIntegrity(
      oldVersion: 14,
      newVersion: 15,
      createOld: v14.DatabaseAtV14.new,
      createNew: v15.DatabaseAtV15.new,
      openTestedDatabase: AppDatabase.new,
      createItems: (batch, oldDb) =>
          batch.insert(oldDb.stepGoalChanges, change),
      validateItems: (newDb) async {
        expect(await newDb.select(newDb.stepGoalChanges).get(), [
          const v15.StepGoalChangesData(
            effectiveDate: '2026-12-07',
            steps: 10000,
          ),
        ]);
        expect(await newDb.select(newDb.goals).get(), isEmpty);
        expect(await newDb.select(newDb.goalWeeks).get(), isEmpty);
        expect(await newDb.select(newDb.goalScreenings).get(), isEmpty);
      },
    );
  });

  test(
    'v15 migrates to v16, keeps the goals and starts with no meals',
    () async {
      const goal = v15.GoalsData(
        id: 1,
        kind: 'loseFat',
        startedOn: '2026-11-16',
        blockStartedOn: '2026-11-16',
        phase: 'block',
        phaseSince: '2026-11-16',
        levers: '{"v":1,"levers":[]}',
      );

      await verifier.testWithDataIntegrity(
        oldVersion: 15,
        newVersion: 16,
        createOld: v15.DatabaseAtV15.new,
        createNew: v16.DatabaseAtV16.new,
        openTestedDatabase: AppDatabase.new,
        createItems: (batch, oldDb) => batch.insert(oldDb.goals, goal),
        validateItems: (newDb) async {
          expect(await newDb.select(newDb.goals).get(), [
            const v16.GoalsData(
              id: 1,
              kind: 'loseFat',
              startedOn: '2026-11-16',
              blockStartedOn: '2026-11-16',
              phase: 'block',
              phaseSince: '2026-11-16',
              levers: '{"v":1,"levers":[]}',
            ),
          ]);
          expect(await newDb.select(newDb.meals).get(), isEmpty);
        },
      );
    },
  );
}

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/core/database/app_database.dart';

import '../../helpers/database.dart';
import 'generated/schema.dart';
import 'generated/schema_v1.dart' as v1;
import 'generated/schema_v2.dart' as v2;
import 'generated/schema_v3.dart' as v3;
import 'generated/schema_v4.dart' as v4;
import 'generated/schema_v5.dart' as v5;
import 'generated/schema_v6.dart' as v6;
import 'generated/schema_v7.dart' as v7;
import 'generated/schema_v8.dart' as v8;

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
}

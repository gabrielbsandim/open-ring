import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/core/database/app_database.dart';
import 'package:open_ring/core/records/epoch.dart';
import 'package:open_ring/core/records/health_record_kind.dart';
import 'package:open_ring/features/health_sync/application/import_external_sleep.dart';
import 'package:open_ring/features/health_sync/application/import_external_workouts.dart';
import 'package:open_ring/features/health_sync/domain/health_writer.dart';
import 'package:open_ring/features/health_sync/infrastructure/drift_health_read_store.dart';

import '../../../helpers/database.dart';
import '../../../helpers/fake_health_reader.dart';

void main() {
  const watch = 'com.garmin.android.apps.connectmobile';
  final firstRead = DateTime.utc(2026, 11, 10, 9);
  final secondRead = DateTime.utc(2026, 11, 11, 9);
  final oldNight = DateTime.utc(2026, 10, 20, 23);
  final deletedNight = DateTime.utc(2026, 11, 9, 23);
  final keptNight = DateTime.utc(2026, 11, 10, 23);
  final oldRun = DateTime.utc(2026, 10, 20, 18);
  final deletedRun = DateTime.utc(2026, 11, 9, 18);
  final keptRun = DateTime.utc(2026, 11, 10, 18);

  late AppDatabase db;
  late DriftHealthReadStore store;
  late FakeHealthReader reader;
  late DateTime now;

  setUp(() async {
    db = await pairedDatabase();
    store = DriftHealthReadStore(db);
    reader = FakeHealthReader(access: HealthAccess.granted);
    now = firstRead;
  });

  Future<List<String>> ids(String table) async {
    final rows = await db
        .customSelect('SELECT record_id FROM $table ORDER BY record_id')
        .get();
    return [for (final row in rows) row.read<String>('record_id')];
  }

  group('sleep', () {
    ImportExternalSleep importer() =>
        ImportExternalSleep(reader: reader, store: store, clock: () => now);

    setUp(() async {
      await store.setEnabled(HealthRecordKind.sleep, enabled: true);
      await db
          .into(db.sleepSessions)
          .insert(
            SleepSessionsCompanion.insert(
              deviceId: ringId,
              startUtcMs: deletedNight.utcMs,
              endUtcMs: deletedNight.add(const Duration(hours: 7)).utcMs,
              offsetMinutes: 0,
            ),
          );
      reader.nights = [
        externalNight(watch, oldNight, id: 'old'),
        externalNight(watch, deletedNight, id: 'deleted'),
      ];
      await importer()();
      now = secondRead;
    });

    test(
      'a night deleted in the source app disappears with its stages',
      () async {
        reader.nights = [externalNight(watch, keptNight, id: 'kept')];

        await importer()();

        expect(await ids('imported_sleep_sessions'), ['kept', 'old']);
        expect(await rowCount(db, 'imported_sleep_stages'), 4);
      },
    );

    test('a night outside the read window stays', () async {
      reader.nights = [];

      await importer()();

      expect(reader.reads.last.from, firstRead.subtract(importOverlap));
      expect(await ids('imported_sleep_sessions'), ['old']);
    });

    test('OpenRing own sleep is untouched', () async {
      reader.nights = [];

      await importer()();

      expect(await rowCount(db, 'sleep_sessions'), 1);
    });

    test('a read that cannot prove absence deletes nothing', () async {
      reader
        ..nights = []
        ..complete = false;

      await importer()();

      expect(await ids('imported_sleep_sessions'), ['deleted', 'old']);
    });
  });

  group('workouts', () {
    ImportExternalWorkouts importer() =>
        ImportExternalWorkouts(reader: reader, store: store, clock: () => now);

    setUp(() async {
      await store.setEnabled(HealthRecordKind.workout, enabled: true);
      await db
          .into(db.workouts)
          .insert(
            WorkoutsCompanion.insert(
              clientId: 'openring:run',
              activityType: 'running',
              startUtcMs: deletedRun.utcMs,
              offsetMinutes: 0,
            ),
          );
      reader.sessions = [
        externalWorkout(watch, oldRun, id: 'old'),
        externalWorkout(watch, deletedRun, id: 'deleted'),
      ];
      await importer()();
      now = secondRead;
    });

    test('a workout deleted in the source app disappears', () async {
      reader.sessions = [externalWorkout(watch, keptRun, id: 'kept')];

      await importer()();

      expect(await ids('imported_workouts'), ['kept', 'old']);
    });

    test('a workout outside the read window stays', () async {
      reader.sessions = [];

      await importer()();

      expect(await ids('imported_workouts'), ['old']);
    });

    test('OpenRing own workouts are untouched', () async {
      reader.sessions = [];

      await importer()();

      expect(await rowCount(db, 'workouts'), 1);
    });

    test('a read that cannot prove absence deletes nothing', () async {
      reader
        ..sessions = []
        ..complete = false;

      await importer()();

      expect(await ids('imported_workouts'), ['deleted', 'old']);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/core/records/health_record_kind.dart';
import 'package:open_ring/core/records/source_priority.dart';
import 'package:open_ring/features/health_sync/infrastructure/drift_health_read_store.dart';
import 'package:ring_driver/ring_driver.dart';

import '../../../helpers/database.dart';
import '../../../helpers/fake_health_reader.dart';

void main() {
  const watch = 'com.garmin.android.apps.connectmobile';
  const band = 'com.mi.health';
  final readAt = DateTime.utc(2026, 11, 10, 9);
  final lastNight = DateTime.utc(2026, 11, 9, 23);

  test('reading starts off and remembers the switch', () async {
    final store = DriftHealthReadStore(memoryDatabase());

    expect((await store.settings(HealthRecordKind.sleep)).enabled, isFalse);
    await store.setEnabled(HealthRecordKind.sleep, enabled: true);
    expect((await store.settings(HealthRecordKind.sleep)).enabled, isTrue);
    await store.setEnabled(HealthRecordKind.sleep, enabled: false);
    expect((await store.settings(HealthRecordKind.sleep)).enabled, isFalse);
  });

  test('saved nights keep their source and stages, never the outbox', () async {
    final db = memoryDatabase();
    final store = DriftHealthReadStore(db);

    await store.saveSleep([
      externalNight(watch, lastNight, id: 'n1'),
    ], readAt: readAt);

    expect(await rowCount(db, 'imported_sleep_sessions'), 1);
    expect(await rowCount(db, 'imported_sleep_stages'), 2);
    expect(await rowCount(db, 'health_outbox'), 0);
    final sources = await store.sources(HealthRecordKind.sleep);
    expect(sources.single.id, watch);
    expect(sources.single.lastEnd, lastNight.add(const Duration(hours: 7)));
    expect((await store.settings(HealthRecordKind.sleep)).lastReadAt, readAt);
  });

  test('a night read again replaces its stages', () async {
    final db = memoryDatabase();
    final store = DriftHealthReadStore(db);
    await store.saveSleep([
      externalNight(watch, lastNight, id: 'n1'),
    ], readAt: readAt);
    final end = lastNight.add(const Duration(hours: 6));

    await store.saveSleep([
      externalNight(
        watch,
        lastNight,
        id: 'n1',
        hours: 6,
        stages: [(start: lastNight, end: end, stage: SleepStage.deep)],
      ),
    ], readAt: readAt);

    expect(await rowCount(db, 'imported_sleep_sessions'), 1);
    expect(await rowCount(db, 'imported_sleep_stages'), 1);
  });

  test('a new source joins the priority after the ring', () async {
    final store = DriftHealthReadStore(memoryDatabase());
    await store.savePriority(HealthRecordKind.sleep, const [watch, ringSource]);

    await store.saveSleep([
      externalNight(watch, lastNight),
      externalNight(band, lastNight.subtract(const Duration(days: 1))),
    ], readAt: readAt);

    expect(await store.storedPriority(HealthRecordKind.sleep), [
      watch,
      ringSource,
      band,
    ]);
  });

  test(
    'saved workouts upsert by record id, keep the sleep order apart',
    () async {
      final db = memoryDatabase();
      final store = DriftHealthReadStore(db);
      final run = DateTime.utc(2026, 11, 9, 18);

      await store.saveWorkouts([
        externalWorkout(band, run, id: 'w1'),
        externalWorkout(watch, run.subtract(const Duration(days: 1)), id: 'w2'),
      ], readAt: readAt);
      await store.saveWorkouts([
        externalWorkout(band, run, id: 'w1', minutes: 55),
      ], readAt: readAt);

      expect(await rowCount(db, 'imported_workouts'), 2);
      expect(await rowCount(db, 'health_outbox'), 0);
      final sources = await store.sources(HealthRecordKind.workout);
      expect(sources.map((s) => (s.id, s.records)), [(watch, 1), (band, 1)]);
      expect(sources.last.lastEnd, run.add(const Duration(minutes: 55)));
      expect(await store.sources(HealthRecordKind.sleep), isEmpty);
      expect(await store.storedPriority(HealthRecordKind.workout), [
        ringSource,
        watch,
        band,
      ]);
      expect(await store.storedPriority(HealthRecordKind.sleep), isEmpty);
      expect(
        (await store.settings(HealthRecordKind.workout)).lastReadAt,
        readAt,
      );
      expect((await store.settings(HealthRecordKind.sleep)).lastReadAt, isNull);
    },
  );
}

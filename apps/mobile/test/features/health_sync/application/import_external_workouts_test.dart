import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/core/records/health_record_kind.dart';
import 'package:open_ring/core/records/source_priority.dart';
import 'package:open_ring/features/health_sync/application/external_import.dart';
import 'package:open_ring/features/health_sync/application/import_external_workouts.dart';
import 'package:open_ring/features/health_sync/domain/health_read_store.dart';
import 'package:open_ring/features/health_sync/domain/health_writer.dart';

import '../../../helpers/fake_health_reader.dart';

void main() {
  const watch = 'com.garmin.android.apps.connectmobile';
  final now = DateTime.utc(2026, 11, 10, 9);
  final lastRun = DateTime.utc(2026, 11, 9, 18);

  late FakeHealthReader reader;
  late InMemoryHealthReadStore store;

  ImportExternalWorkouts importer() =>
      ImportExternalWorkouts(reader: reader, store: store, clock: () => now);

  setUp(() {
    reader = FakeHealthReader(access: HealthAccess.granted);
    store = InMemoryHealthReadStore();
  });

  test('reads nothing while workout reading is off', () async {
    await store.setEnabled(HealthRecordKind.sleep, enabled: true);

    final report = await importer()();

    expect(report.outcome, ImportOutcome.off);
    expect(reader.reads, isEmpty);
  });

  test(
    'reads nothing without read access, or waits in the background',
    () async {
      await store.setEnabled(HealthRecordKind.workout, enabled: true);
      reader.access = HealthAccess.denied;
      expect((await importer()()).outcome, ImportOutcome.denied);

      reader.access = HealthAccess.deferred;
      expect((await importer()()).outcome, ImportOutcome.deferred);
      expect(reader.reads, isEmpty);
    },
  );

  test('keeps workouts other apps wrote and drops OpenRing own ones', () async {
    await store.setEnabled(HealthRecordKind.workout, enabled: true);
    reader.sessions = [
      externalWorkout(watch, lastRun, id: 'w1'),
      externalWorkout(ownPackage, lastRun, id: 'own'),
      externalWorkout(ringSource, lastRun, id: 'ring'),
      externalWorkout(watch, lastRun, id: 'empty', minutes: 0),
    ];

    final report = await importer()();

    expect(report.outcome, ImportOutcome.imported);
    expect(report.count, 1);
    expect(store.workouts.keys, ['w1']);
    expect(store.nights, isEmpty);
    expect(await store.storedPriority(HealthRecordKind.workout), [
      ringSource,
      watch,
    ]);
    expect(await store.storedPriority(HealthRecordKind.sleep), isEmpty);
  });

  test('reads 30 days first, then from 2 days before the last read', () async {
    await store.setEnabled(HealthRecordKind.workout, enabled: true);

    await importer()();
    expect(reader.reads.single.from, now.subtract(const Duration(days: 30)));

    await importer()();
    expect(reader.reads.last.from, now.subtract(const Duration(days: 2)));
    expect((await store.settings(HealthRecordKind.workout)).lastReadAt, now);
  });

  test('a workout read again replaces the stored one', () async {
    await store.setEnabled(HealthRecordKind.workout, enabled: true);
    reader.sessions = [externalWorkout(watch, lastRun, id: 'w1')];
    await importer()();
    reader.sessions = [externalWorkout(watch, lastRun, id: 'w1', minutes: 55)];

    await importer()();

    expect(store.workouts, hasLength(1));
    expect(store.workouts['w1']!.end, lastRun.add(const Duration(minutes: 55)));
  });

  test('a later read drops a workout the source app deleted', () async {
    await store.setEnabled(HealthRecordKind.workout, enabled: true);
    reader.sessions = [
      externalWorkout(watch, lastRun, id: 'w1'),
      externalWorkout(watch, lastRun.add(const Duration(hours: 2)), id: 'w2'),
    ];
    await importer()();
    reader.sessions = [externalWorkout(watch, lastRun, id: 'w1')];

    await importer()();

    expect(store.workouts.keys, ['w1']);
  });

  test('only a missing record wholly inside the window is gone', () {
    final from = now.subtract(const Duration(days: 2));
    final coverage = (from: from, to: now, present: {'kept'});
    bool gone(String id, DateTime start) => goneFrom(
      coverage,
      recordId: id,
      start: start,
      end: start.add(const Duration(hours: 1)),
    );

    expect(gone('missing', lastRun), isTrue);
    expect(gone('kept', lastRun), isFalse);
    expect(
      gone('missing', from.subtract(const Duration(minutes: 30))),
      isFalse,
    );
    expect(gone('missing', now.subtract(const Duration(minutes: 30))), isFalse);
  });
}

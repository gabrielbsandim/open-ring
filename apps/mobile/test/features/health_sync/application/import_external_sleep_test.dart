import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/core/records/health_record_kind.dart';
import 'package:open_ring/core/records/source_priority.dart';
import 'package:open_ring/features/health_sync/application/import_external_sleep.dart';
import 'package:open_ring/features/health_sync/domain/health_read_store.dart';
import 'package:open_ring/features/health_sync/domain/health_writer.dart';
import 'package:ring_driver/ring_driver.dart';

import '../../../helpers/fake_health_reader.dart';

void main() {
  const watch = 'com.garmin.android.apps.connectmobile';
  final now = DateTime.utc(2026, 11, 10, 9);
  final lastNight = DateTime.utc(2026, 11, 9, 23);

  late FakeHealthReader reader;
  late InMemoryHealthReadStore store;

  ImportExternalSleep importer() =>
      ImportExternalSleep(reader: reader, store: store, clock: () => now);

  setUp(() {
    reader = FakeHealthReader(access: HealthAccess.granted);
    store = InMemoryHealthReadStore();
  });

  test('reads nothing while sleep reading is off', () async {
    final report = await importer()();

    expect(report.outcome, ImportOutcome.off);
    expect(reader.reads, isEmpty);
  });

  test('reads nothing without read access', () async {
    await store.setEnabled(HealthRecordKind.sleep, enabled: true);
    reader.access = HealthAccess.denied;

    final report = await importer()();

    expect(report.outcome, ImportOutcome.denied);
    expect(reader.reads, isEmpty);
  });

  test('a background engine without background access waits', () async {
    await store.setEnabled(HealthRecordKind.sleep, enabled: true);
    reader.access = HealthAccess.deferred;

    expect((await importer()()).outcome, ImportOutcome.deferred);
    expect(reader.reads, isEmpty);
  });

  test('stores other apps and never what OpenRing wrote itself', () async {
    await store.setEnabled(HealthRecordKind.sleep, enabled: true);
    reader.nights = [
      externalNight(watch, lastNight),
      externalNight(ownPackage, lastNight),
    ];

    final report = await importer()();

    expect(report.outcome, ImportOutcome.imported);
    expect(report.count, 1);
    expect(store.nights.values.map((n) => n.source), [watch]);
    expect(await store.storedPriority(HealthRecordKind.sleep), [
      ringSource,
      watch,
    ]);
  });

  test('skips a session that holds no sleep stage', () async {
    await store.setEnabled(HealthRecordKind.sleep, enabled: true);
    final end = lastNight.add(const Duration(hours: 1));
    reader.nights = [
      externalNight(
        watch,
        lastNight,
        stages: [(start: lastNight, end: end, stage: SleepStage.awake)],
      ),
    ];

    expect((await importer()()).count, 0);
    expect(store.nights, isEmpty);
  });

  test(
    'reads 30 days first, then from two days before the last read',
    () async {
      await store.setEnabled(HealthRecordKind.sleep, enabled: true);

      await importer()();
      await importer()();

      expect(reader.reads.first.from, now.subtract(const Duration(days: 30)));
      expect(reader.reads.last.from, now.subtract(const Duration(days: 2)));
      expect(reader.reads.last.to, now);
    },
  );

  test('a read of a revised night replaces it by record id', () async {
    await store.setEnabled(HealthRecordKind.sleep, enabled: true);
    reader.nights = [externalNight(watch, lastNight, id: 'n1')];
    await importer()();
    reader.nights = [externalNight(watch, lastNight, id: 'n1', hours: 5)];

    await importer()();

    expect(store.nights, hasLength(1));
    expect(store.nights['n1']!.end, lastNight.add(const Duration(hours: 5)));
  });

  test(
    'an empty read that cannot prove absence keeps what was imported',
    () async {
      await store.setEnabled(HealthRecordKind.sleep, enabled: true);
      reader.nights = [externalNight(watch, lastNight)];
      await importer()();
      reader
        ..nights = []
        ..complete = false;

      await importer()();

      expect(store.nights, hasLength(1));
    },
  );

  test('an empty read that proves absence drops the night', () async {
    await store.setEnabled(HealthRecordKind.sleep, enabled: true);
    reader.nights = [externalNight(watch, lastNight)];
    await importer()();
    reader.nights = [];

    await importer()();

    expect(store.nights, isEmpty);
  });
}

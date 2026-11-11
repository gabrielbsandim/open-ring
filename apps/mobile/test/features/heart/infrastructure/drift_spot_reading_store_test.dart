import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/core/database/app_database.dart';
import 'package:open_ring/core/records/health_record_kind.dart';
import 'package:open_ring/features/heart/infrastructure/drift_spot_reading_store.dart';
import 'package:ring_driver/ring_driver.dart';

import '../../../helpers/database.dart';

void main() {
  late AppDatabase db;
  late DriftSpotReadingStore store;

  setUp(() async {
    db = await pairedDatabase();
    store = DriftSpotReadingStore(db);
  });

  test(
    'a heart rate reading lands in the heart rate log and the outbox',
    () async {
      final at = DateTime(2026, 11, 10, 22, 5);

      await store.save(
        ringId,
        LiveReading(kind: LiveKind.heartRate, value: 72, at: at),
      );

      final row = await db.select(db.hrSamples).getSingle();
      expect(row.atUtcMs, at.millisecondsSinceEpoch);
      expect(row.offsetMinutes, at.timeZoneOffset.inMinutes);
      expect(row.bpm, 72);
      final outbox = await db.select(db.healthOutbox).getSingle();
      expect(outbox.kind, HealthRecordKind.heartRate);
      expect(outbox.recordCount, 1);
      expect(outbox.fromUtcMs, at.millisecondsSinceEpoch);
    },
  );

  test('an SpO2 reading lands in the SpO2 log', () async {
    final at = DateTime(2026, 11, 10, 22, 6);

    await store.save(
      ringId,
      LiveReading(kind: LiveKind.spo2, value: 97, at: at),
    );

    expect((await db.select(db.spo2Samples).getSingle()).percent, 97);
    expect(await rowCount(db, 'hr_samples'), 0);
    expect(
      (await db.select(db.healthOutbox).getSingle()).kind,
      HealthRecordKind.spo2,
    );
  });

  test('saving the same reading twice queues it once', () async {
    final reading = LiveReading(
      kind: LiveKind.heartRate,
      value: 72,
      at: DateTime(2026, 11, 10, 22, 5),
    );

    await store.save(ringId, reading);
    await store.save(ringId, reading);

    expect(await rowCount(db, 'hr_samples'), 1);
    expect(await rowCount(db, 'health_outbox'), 1);
  });
}

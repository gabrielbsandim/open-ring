import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/core/database/app_database.dart';
import 'package:open_ring/features/ring/infrastructure/ring_samples_dao.dart';
import 'package:ring_driver/ring_driver.dart';

import '../../../helpers/database.dart';
import '../../../helpers/sync_fixtures.dart';

void main() {
  late AppDatabase db;
  late RingSamplesDao dao;

  setUp(() async {
    db = await pairedDatabase();
    dao = RingSamplesDao(db);
  });

  group('heart rate', () {
    test('stores UTC epoch milliseconds and the offset at capture', () async {
      await dao.upsertHeartRate(ringId, nightHeartRate.take(1).toList());

      final row = await db.select(db.hrSamples).getSingle();
      final at = nightHeartRate.first.at;
      expect(row.deviceId, ringId);
      expect(row.atUtcMs, at.toUtc().millisecondsSinceEpoch);
      expect(row.offsetMinutes, at.timeZoneOffset.inMinutes);
      expect(row.bpm, 64);
    });

    test('importing the same samples twice keeps one row each', () async {
      final first = await dao.upsertHeartRate(ringId, nightHeartRate);
      final second = await dao.upsertHeartRate(ringId, nightHeartRate);

      expect(first.count, 3);
      expect(first.from, nightHeartRate.first.at);
      expect(first.to, nightHeartRate.last.at);
      expect(second.count, 0);
      expect(second.from, isNull);
      expect(await rowCount(db, 'hr_samples'), 3);
    });

    test('a changed value updates the row and counts as written', () async {
      await dao.upsertHeartRate(ringId, nightHeartRate);
      final changed = HeartRateSample(at: nightHeartRate[1].at, bpm: 70);

      final summary = await dao.upsertHeartRate(ringId, [changed]);

      expect(summary.count, 1);
      expect(summary.from, changed.at);
      final rows = await db.select(db.hrSamples).get();
      expect(rows.map((r) => r.bpm), [64, 70, 58]);
    });
  });

  test('a growing activity bucket is updated in place', () async {
    await dao.upsertActivity(ringId, eveningActivity);
    final grown = ActivityBucket(
      start: eveningActivity.last.start,
      duration: const Duration(minutes: 15),
      steps: 300,
      distanceMeters: 220,
      activeKilocalories: 12,
    );

    final summary = await dao.upsertActivity(ringId, [
      eveningActivity.first,
      grown,
    ]);

    expect(summary.count, 1);
    expect(summary.to, grown.start.add(const Duration(minutes: 15)));
    final rows = await db.select(db.activityBuckets).get();
    expect(rows.map((r) => (r.steps, r.durationSeconds)), [
      (420, 900),
      (300, 900),
    ]);
  });

  test('SpO2, stress and HRV are idempotent per timestamp', () async {
    final spo2 = [Spo2Sample(at: syncNow, percent: 97)];
    final stress = [StressSample(at: syncNow, level: 30)];
    final hrv = [HrvSample(at: syncNow, milliseconds: 48)];

    for (var i = 0; i < 2; i++) {
      await dao.upsertSpo2(ringId, spo2);
      await dao.upsertStress(ringId, stress);
      await dao.upsertHrv(ringId, hrv);
    }

    expect(await rowCount(db, 'spo2_samples'), 1);
    expect(await rowCount(db, 'stress_samples'), 1);
    expect(await rowCount(db, 'hrv_samples'), 1);
    expect((await dao.upsertHrv(ringId, hrv)).count, 0);
  });

  test('samples for an unknown ring are rejected by the foreign key', () async {
    await expectLater(
      dao.upsertHeartRate('unknown', nightHeartRate),
      throwsA(anything),
    );
  });
}

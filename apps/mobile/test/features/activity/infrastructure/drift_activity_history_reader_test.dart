import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/core/database/app_database.dart';
import 'package:open_ring/features/activity/infrastructure/activity_buckets_dao.dart';
import 'package:open_ring/features/activity/infrastructure/drift_activity_history_reader.dart';

import '../../../helpers/database.dart';

const _nov10 = LocalDate(2026, 11, 10);

Future<void> _bucket(
  AppDatabase db,
  DateTime startUtc, {
  required int offsetMinutes,
  required int steps,
  double kcal = 10,
  int meters = 100,
}) => db
    .into(db.activityBuckets)
    .insert(
      ActivityBucketsCompanion.insert(
        deviceId: ringId,
        startUtcMs: startUtc.millisecondsSinceEpoch,
        offsetMinutes: offsetMinutes,
        durationSeconds: 900,
        steps: steps,
        distanceMeters: meters,
        activeKilocalories: kcal,
      ),
    );

void main() {
  late AppDatabase db;
  late DriftActivityHistoryReader reader;

  setUp(() async {
    db = await pairedDatabase();
    reader = DriftActivityHistoryReader(db);
  });

  group('local dates come from each bucket offset', () {
    setUp(() async {
      await _bucket(
        db,
        DateTime.utc(2026, 11, 9, 23, 30),
        offsetMinutes: 60,
        steps: 100,
      );
      await _bucket(
        db,
        DateTime.utc(2026, 11, 10, 23, 30),
        offsetMinutes: -600,
        steps: 200,
      );
      await _bucket(
        db,
        DateTime.utc(2026, 11, 10, 22),
        offsetMinutes: 180,
        steps: 400,
      );
      await _bucket(
        db,
        DateTime.utc(2026, 11, 9, 23),
        offsetMinutes: 0,
        steps: 800,
      );
    });

    test('a bucket counts on the date of its wall clock', () async {
      final slots = await reader.activitySlots(from: _nov10, to: _nov10);

      expect(slots.map((s) => s.steps), [100, 200]);
      expect(slots.first.localHour, 0);
      expect(slots.first.utcOffset, const Duration(hours: 1));
      expect(slots.last.localHour, 13);
      expect(slots.last.start.isUtc, isTrue);
    });

    test('daily totals are summed per local date and sorted', () async {
      final days = await reader.dailyActivity(
        from: _nov10.addDays(-1),
        to: _nov10.addDays(1),
      );

      expect(days.map((d) => d.date), [
        const LocalDate(2026, 11, 9),
        _nov10,
        const LocalDate(2026, 11, 11),
      ]);
      expect(days.map((d) => d.steps), [800, 300, 400]);
      expect(days[1].activeKilocalories, 20);
      expect(days[1].distanceMeters, 200);
    });
  });

  test('the range includes local midnight of from and excludes the next '
      'midnight after to', () async {
    await _bucket(db, DateTime.utc(2026, 11, 10), offsetMinutes: 0, steps: 1);
    await _bucket(
      db,
      DateTime.utc(2026, 11, 10, 23, 59),
      offsetMinutes: 0,
      steps: 2,
    );
    await _bucket(db, DateTime.utc(2026, 11, 11), offsetMinutes: 0, steps: 4);
    await _bucket(
      db,
      DateTime.utc(2026, 11, 9, 23, 59),
      offsetMinutes: 0,
      steps: 8,
    );

    final rows = await ActivityBucketsDao(db)
        .bucketsOnLocalDates(from: _nov10, to: _nov10);

    expect(rows.map((r) => r.steps), [1, 2]);
  });

  test('a day without buckets has no entry', () async {
    expect(await reader.dailyActivity(from: _nov10, to: _nov10), isEmpty);
  });
}

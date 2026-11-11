import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/core/database/app_database.dart';
import 'package:open_ring/features/ring/infrastructure/sleep_dao.dart';
import 'package:ring_driver/ring_driver.dart';

import '../../../helpers/database.dart';
import '../../../helpers/sync_fixtures.dart';

void main() {
  late AppDatabase db;
  late SleepDao dao;

  setUp(() async {
    db = await pairedDatabase();
    dao = SleepDao(db);
  });

  Future<List<(int, int)>> sessions() async => [
    for (final row in await db.select(db.sleepSessions).get())
      (row.startUtcMs, row.endUtcMs),
  ];

  test('writes one session per night with its segments linked', () async {
    final previousNight = SleepSegment(
      start: DateTime(2026, 11, 8, 23, 30),
      end: DateTime(2026, 11, 9, 6, 30),
      stage: SleepStage.light,
    );

    final summary = await dao.replaceNights(ringId, [
      ...lastNight,
      previousNight,
    ]);

    expect(summary.count, 7);
    expect(await sessions(), [
      (
        previousNight.start.millisecondsSinceEpoch,
        previousNight.end.millisecondsSinceEpoch,
      ),
      (
        nightStart.millisecondsSinceEpoch,
        lastNight.last.end.millisecondsSinceEpoch,
      ),
    ]);
    final segments = await db.select(db.sleepSegments).get();
    expect(segments, hasLength(5));
    expect(
      segments.where(
        (s) => s.sessionStartUtcMs == nightStart.millisecondsSinceEpoch,
      ),
      hasLength(4),
    );
    expect(segments.map((s) => s.stage), contains(SleepStage.rem));
  });

  test('re-importing the same night writes nothing', () async {
    await dao.replaceNights(ringId, lastNight);

    final summary = await dao.replaceNights(ringId, lastNight);

    expect(summary.count, 0);
    expect(await rowCount(db, 'sleep_sessions'), 1);
    expect(await rowCount(db, 'sleep_segments'), 4);
  });

  test('a night that grew since the last pull extends the session', () async {
    await dao.replaceNights(ringId, lastNight.take(2).toList());
    final grown = SleepSegment(
      start: lastNight[1].start,
      end: DateTime(2026, 11, 10, 2, 45),
      stage: SleepStage.deep,
    );

    final summary = await dao.replaceNights(ringId, [lastNight.first, grown]);

    expect(summary.count, 2);
    expect(await sessions(), [
      (nightStart.millisecondsSinceEpoch, grown.end.millisecondsSinceEpoch),
    ]);
  });

  test('a revised night drops the stale session and segments', () async {
    await dao.replaceNights(ringId, lastNight);
    final revised = [
      SleepSegment(
        start: DateTime(2026, 11, 9, 23, 20),
        end: DateTime(2026, 11, 10, 2),
        stage: SleepStage.light,
      ),
      SleepSegment(
        start: DateTime(2026, 11, 10, 2),
        end: DateTime(2026, 11, 10, 7),
        stage: SleepStage.deep,
      ),
    ];

    final summary = await dao.replaceNights(ringId, revised);

    expect(summary.count, greaterThan(0));
    expect(summary.from, nightStart);
    expect(summary.to, revised.last.end);
    expect(await sessions(), [
      (
        revised.first.start.millisecondsSinceEpoch,
        revised.last.end.millisecondsSinceEpoch,
      ),
    ]);
    final segments = await db.select(db.sleepSegments).get();
    expect(segments.map((s) => s.startUtcMs), [
      for (final segment in revised) segment.start.millisecondsSinceEpoch,
    ]);
  });
}

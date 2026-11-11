import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/core/database/app_database.dart';
import 'package:open_ring/features/sleep/infrastructure/drift_sleep_history_reader.dart';
import 'package:open_ring/features/sleep/infrastructure/sleep_history_dao.dart';
import 'package:ring_driver/ring_driver.dart';

import '../../../helpers/database.dart';

const int _kiritimati = 14 * 60;

Future<void> _segment(
  AppDatabase db,
  DateTime start,
  DateTime end,
  SleepStage stage, {
  int offsetMinutes = 0,
  DateTime? session,
}) => db
    .into(db.sleepSegments)
    .insert(
      SleepSegmentsCompanion.insert(
        deviceId: ringId,
        startUtcMs: start.millisecondsSinceEpoch,
        endUtcMs: end.millisecondsSinceEpoch,
        offsetMinutes: offsetMinutes,
        stage: stage,
        sessionStartUtcMs: (session ?? start).millisecondsSinceEpoch,
      ),
    );

void main() {
  late AppDatabase db;
  late DriftSleepHistoryReader reader;

  setUp(() async {
    db = await pairedDatabase();
    reader = DriftSleepHistoryReader(db);
  });

  test('maps rows to UTC spans with the offset at capture', () async {
    final start = DateTime.utc(2026, 11, 9, 9);
    await _segment(
      db,
      start,
      DateTime.utc(2026, 11, 9, 12),
      SleepStage.deep,
      offsetMinutes: _kiritimati,
    );
    await _segment(
      db,
      DateTime.utc(2026, 11, 9, 12),
      DateTime.utc(2026, 11, 9, 16),
      SleepStage.rem,
      offsetMinutes: _kiritimati,
      session: start,
    );

    final spans = await reader.sleepSpans(
      from: DateTime.utc(2026, 11, 9),
      to: DateTime.utc(2026, 11, 10),
    );

    expect(spans, hasLength(2));
    expect(spans.first.start, start);
    expect(spans.first.start.isUtc, isTrue);
    expect(spans.first.phase, SleepPhase.deep);
    expect(spans.last.phase, SleepPhase.rem);
    expect(spans.last.utcOffset, const Duration(hours: 14));
    final nights = mainNightByDate(stitchSleep(spans));
    expect(nights.keys, [const LocalDate(2026, 11, 10)]);
  });

  test('a negative offset keeps the local date of a day sleep', () async {
    await _segment(
      db,
      DateTime.utc(2026, 11, 10, 22),
      DateTime.utc(2026, 11, 11, 1),
      SleepStage.light,
      offsetMinutes: -600,
    );

    final spans = await reader.sleepSpans(
      from: DateTime.utc(2026, 11, 10),
      to: DateTime.utc(2026, 11, 12),
    );

    expect(spans.single.utcOffset, const Duration(hours: -10));
    expect(mainNightByDate(stitchSleep(spans)).keys, [
      const LocalDate(2026, 11, 10),
    ]);
  });

  test('every stage maps to its phase', () {
    expect(SleepStage.values.map(DriftSleepHistoryReader.phaseOf), [
      SleepPhase.light,
      SleepPhase.deep,
      SleepPhase.rem,
      SleepPhase.awake,
    ]);
  });

  group('range', () {
    final from = DateTime.utc(2026, 11, 10);
    final to = DateTime.utc(2026, 11, 10, 8);

    setUp(() async {
      await _segment(db, DateTime.utc(2026, 11, 9, 22), from, SleepStage.light);
      await _segment(
        db,
        DateTime.utc(2026, 11, 9, 23),
        DateTime.utc(2026, 11, 10, 1),
        SleepStage.deep,
      );
      await _segment(
        db,
        DateTime.utc(2026, 11, 10, 7),
        DateTime.utc(2026, 11, 10, 9),
        SleepStage.awake,
      );
      await _segment(db, to, DateTime.utc(2026, 11, 10, 9, 30), SleepStage.rem);
    });

    test('keeps segments that overlap the range, ordered by start', () async {
      final rows = await SleepHistoryDao(db)
          .segmentsOverlapping(from: from, to: to);

      expect(rows.map((r) => r.stage), [SleepStage.deep, SleepStage.awake]);
    });

    test('a segment that ends at from or starts at to is outside', () async {
      final spans = await reader.sleepSpans(from: from, to: to);

      expect(spans.map((s) => s.start), [
        DateTime.utc(2026, 11, 9, 23),
        DateTime.utc(2026, 11, 10, 7),
      ]);
    });
  });

  test('an empty database reads no spans', () async {
    final spans = await reader.sleepSpans(
      from: DateTime.utc(2026),
      to: DateTime.utc(2027),
    );

    expect(spans, isEmpty);
  });
}

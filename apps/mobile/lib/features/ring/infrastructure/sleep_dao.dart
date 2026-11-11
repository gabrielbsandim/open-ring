import 'package:drift/drift.dart';
import 'package:open_ring/core/database/app_database.dart';
import 'package:open_ring/core/database/tables/sleep_tables.dart';
import 'package:open_ring/core/records/epoch.dart';
import 'package:open_ring/features/ring/domain/sleep_session_span.dart';
import 'package:open_ring/features/ring/infrastructure/write_summary.dart';
import 'package:ring_driver/ring_driver.dart';

part 'sleep_dao.g.dart';

@DriftAccessor(tables: [SleepSessions, SleepSegments])
class SleepDao extends DatabaseAccessor<AppDatabase> with _$SleepDaoMixin {
  new(super.attachedDatabase);

  Future<WriteSummary> replaceNights(
    String deviceId,
    List<SleepSegment> segments,
  ) async {
    var summary = WriteSummary.empty;
    for (final night in SleepSessionSpan.group(segments)) {
      summary = summary.merge(await replaceNight(deviceId, night));
    }
    return summary;
  }

  // A revised night can move its start: overlapping older sessions are dropped,
  // and the summary covers their spans so the health outbox replaces them too.
  Future<WriteSummary> replaceNight(
    String deviceId,
    SleepSessionSpan night,
  ) async {
    final start = night.start.utcMs;
    final end = night.end.utcMs;
    final staleRows =
        await (select(sleepSessions)..where(
              (s) =>
                  s.deviceId.equals(deviceId) &
                  s.startUtcMs.isNotValue(start) &
                  s.startUtcMs.isSmallerThanValue(end) &
                  s.endUtcMs.isBiggerThanValue(start),
            ))
            .get();
    final stale = [for (final row in staleRows) row.startUtcMs];
    final kept = [for (final segment in night.segments) segment.start.utcMs];
    final removed =
        await (delete(sleepSegments)..where(
              (s) =>
                  s.deviceId.equals(deviceId) &
                  (s.sessionStartUtcMs.isIn(stale) |
                      (s.sessionStartUtcMs.equals(start) &
                          s.startUtcMs.isNotIn(kept))),
            ))
            .go() +
        await (delete(sleepSessions)..where(
              (s) => s.deviceId.equals(deviceId) & s.startUtcMs.isIn(stale),
            ))
            .go();
    final session = await into(sleepSessions).insertReturningOrNull(
      SleepSessionsCompanion.insert(
        deviceId: deviceId,
        startUtcMs: start,
        endUtcMs: end,
        offsetMinutes: night.start.offsetMinutes,
      ),
      onConflict: DoUpdate.withExcluded(
        (old, excluded) => SleepSessionsCompanion.custom(
          endUtcMs: excluded.endUtcMs,
          offsetMinutes: excluded.offsetMinutes,
        ),
        where: (old, excluded) =>
            old.endUtcMs.isNotExp(excluded.endUtcMs) |
            old.offsetMinutes.isNotExp(excluded.offsetMinutes),
      ),
    );
    final segments = await writeEach(
      night.segments,
      start: (segment) => segment.start,
      end: (segment) => segment.end,
      write: (segment) => into(sleepSegments).insertReturningOrNull(
        SleepSegmentsCompanion.insert(
          deviceId: deviceId,
          startUtcMs: segment.start.utcMs,
          endUtcMs: segment.end.utcMs,
          offsetMinutes: segment.start.offsetMinutes,
          stage: segment.stage,
          sessionStartUtcMs: start,
        ),
        onConflict: DoUpdate.withExcluded(
          (old, excluded) => SleepSegmentsCompanion.custom(
            endUtcMs: excluded.endUtcMs,
            offsetMinutes: excluded.offsetMinutes,
            stage: excluded.stage,
            sessionStartUtcMs: excluded.sessionStartUtcMs,
          ),
          where: (old, excluded) =>
              old.endUtcMs.isNotExp(excluded.endUtcMs) |
              old.offsetMinutes.isNotExp(excluded.offsetMinutes) |
              old.stage.isNotExp(excluded.stage) |
              old.sessionStartUtcMs.isNotExp(excluded.sessionStartUtcMs),
        ),
      ),
    );
    final changed = removed + (session == null ? 0 : 1);
    return staleRows.fold<WriteSummary>(
      segments.include(changed, night.start, night.end),
      (summary, row) =>
          summary.cover(fromUtcMs(row.startUtcMs), fromUtcMs(row.endUtcMs)),
    );
  }
}

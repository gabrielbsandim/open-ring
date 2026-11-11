import 'package:drift/drift.dart';
import 'package:open_ring/core/database/app_database.dart';
import 'package:open_ring/core/records/epoch.dart';
import 'package:open_ring/features/export/domain/export_kind.dart';
import 'package:open_ring/features/export/domain/export_records.dart';
import 'package:open_ring/features/export/domain/offset_time.dart';

typedef _TimeCursor = ({int at, String deviceId});
typedef _WorkoutCursor = ({int at, int id});

typedef _SampleTable = ({
  TableInfo<Table, Object?> table,
  GeneratedColumn<String> deviceId,
  GeneratedColumn<int> at,
  GeneratedColumn<int> offset,
  GeneratedColumn<int> value,
});

// Keyset pagination on (time, device) instead of OFFSET: each page is an index
// seek, and rows a sync inserts mid-export never shift later pages.
class ExportPagesDao extends DatabaseAccessor<AppDatabase> {
  new(super.attachedDatabase, {this.pageSize = defaultPageSize})
    : assert(pageSize > 0, 'pageSize must be positive');

  static const defaultPageSize = 500;

  final int pageSize;

  Stream<List<ExportRecord>> pages(
    ExportKind kind, {
    required DateTime from,
    required DateTime to,
  }) {
    final db = attachedDatabase;
    final range = (from: from.utcMs, to: to.utcMs);
    return switch (kind) {
      ExportKind.sleep => _sleep(range),
      ExportKind.heartRate => _samples((
        table: db.hrSamples,
        deviceId: db.hrSamples.deviceId,
        at: db.hrSamples.atUtcMs,
        offset: db.hrSamples.offsetMinutes,
        value: db.hrSamples.bpm,
      ), range),
      ExportKind.hrv => _samples((
        table: db.hrvSamples,
        deviceId: db.hrvSamples.deviceId,
        at: db.hrvSamples.atUtcMs,
        offset: db.hrvSamples.offsetMinutes,
        value: db.hrvSamples.milliseconds,
      ), range),
      ExportKind.spo2 => _samples((
        table: db.spo2Samples,
        deviceId: db.spo2Samples.deviceId,
        at: db.spo2Samples.atUtcMs,
        offset: db.spo2Samples.offsetMinutes,
        value: db.spo2Samples.percent,
      ), range),
      ExportKind.stress => _samples((
        table: db.stressSamples,
        deviceId: db.stressSamples.deviceId,
        at: db.stressSamples.atUtcMs,
        offset: db.stressSamples.offsetMinutes,
        value: db.stressSamples.level,
      ), range),
      ExportKind.activity => _activity(range),
      ExportKind.workouts => _workouts(range),
    };
  }

  Future<ExportDevice?> latestDevice() async {
    final row =
        await (select(attachedDatabase.ringDevices)
              ..orderBy([(d) => OrderingTerm.desc(d.pairedAtUtcMs)])
              ..limit(1))
            .getSingleOrNull();
    if (row == null) return null;
    return ExportDevice(
      id: row.deviceId,
      name: row.name,
      model: row.model,
      firmware: row.firmware,
    );
  }

  Stream<List<ExportRecord>> _samples(
    _SampleTable t,
    ({int from, int to}) range,
  ) => _paged<_TimeCursor, TypedResult>(
    (cursor) {
      final query = selectOnly(t.table)
        ..addColumns([t.deviceId, t.at, t.offset, t.value])
        ..where(_window(t.at, t.deviceId, range, cursor))
        ..orderBy([OrderingTerm.asc(t.at), OrderingTerm.asc(t.deviceId)])
        ..limit(pageSize);
      return query.get();
    },
    (row) => (at: row.read(t.at)!, deviceId: row.read(t.deviceId)!),
    (row) => SampleRecord(
      at: OffsetTime(
        utcMs: row.read(t.at)!,
        offsetMinutes: row.read(t.offset)!,
      ),
      deviceId: row.read(t.deviceId)!,
      value: row.read(t.value)!,
    ),
  );

  Stream<List<ExportRecord>> _activity(({int from, int to}) range) {
    final table = attachedDatabase.activityBuckets;
    return _paged<_TimeCursor, ActivityBucketRow>(
      (cursor) =>
          (select(table)
                ..where((b) => _window(b.startUtcMs, b.deviceId, range, cursor))
                ..orderBy([
                  (b) => OrderingTerm.asc(b.startUtcMs),
                  (b) => OrderingTerm.asc(b.deviceId),
                ])
                ..limit(pageSize))
              .get(),
      (row) => (at: row.startUtcMs, deviceId: row.deviceId),
      (row) => ActivityRecord(
        start: OffsetTime(
          utcMs: row.startUtcMs,
          offsetMinutes: row.offsetMinutes,
        ),
        duration: Duration(seconds: row.durationSeconds),
        deviceId: row.deviceId,
        steps: row.steps,
        distanceMeters: row.distanceMeters,
        activeKilocalories: row.activeKilocalories,
      ),
    );
  }

  Stream<List<ExportRecord>> _sleep(({int from, int to}) range) {
    final segments = attachedDatabase.sleepSegments;
    final sessions = attachedDatabase.sleepSessions;
    return _paged<_TimeCursor, TypedResult>(
      (cursor) {
        final query =
            select(segments).join([
                leftOuterJoin(
                  sessions,
                  sessions.deviceId.equalsExp(segments.deviceId) &
                      sessions.startUtcMs.equalsExp(segments.sessionStartUtcMs),
                ),
              ])
              ..where(
                _inRange(segments.sessionStartUtcMs, range) &
                    _after(segments.startUtcMs, segments.deviceId, cursor),
              )
              ..orderBy([
                OrderingTerm.asc(segments.startUtcMs),
                OrderingTerm.asc(segments.deviceId),
              ])
              ..limit(pageSize);
        return query.get();
      },
      (row) {
        final segment = row.readTable(segments);
        return (at: segment.startUtcMs, deviceId: segment.deviceId);
      },
      (row) {
        final segment = row.readTable(segments);
        final offset = segment.offsetMinutes;
        final sessionOffset =
            row.readTableOrNull(sessions)?.offsetMinutes ?? offset;
        return SleepStageRecord(
          sessionStart: OffsetTime(
            utcMs: segment.sessionStartUtcMs,
            offsetMinutes: sessionOffset,
          ),
          start: OffsetTime(utcMs: segment.startUtcMs, offsetMinutes: offset),
          end: OffsetTime(utcMs: segment.endUtcMs, offsetMinutes: offset),
          deviceId: segment.deviceId,
          stage: segment.stage,
        );
      },
    );
  }

  Stream<List<ExportRecord>> _workouts(({int from, int to}) range) {
    final table = attachedDatabase.workouts;
    return _paged<_WorkoutCursor, WorkoutRow>(
      (cursor) =>
          (select(table)
                ..where((w) {
                  final inRange = _inRange(w.startUtcMs, range);
                  if (cursor == null) return inRange;
                  return inRange &
                      (w.startUtcMs.isBiggerThanValue(cursor.at) |
                          (w.startUtcMs.equals(cursor.at) &
                              w.id.isBiggerThanValue(cursor.id)));
                })
                ..orderBy([
                  (w) => OrderingTerm.asc(w.startUtcMs),
                  (w) => OrderingTerm.asc(w.id),
                ])
                ..limit(pageSize))
              .get(),
      (row) => (at: row.startUtcMs, id: row.id),
      (row) => WorkoutRecord(
        start: OffsetTime(
          utcMs: row.startUtcMs,
          offsetMinutes: row.offsetMinutes,
        ),
        end: switch (row.endUtcMs) {
          null => null,
          final end => OffsetTime(utcMs: end, offsetMinutes: row.offsetMinutes),
        },
        clientId: row.clientId,
        deviceId: row.deviceId,
        activityType: row.activityType,
        distanceMeters: row.distanceMeters,
        activeKilocalories: row.activeKilocalories,
      ),
    );
  }

  Stream<List<ExportRecord>> _paged<C extends Record, R>(
    Future<List<R>> Function(C? cursor) fetch,
    C Function(R row) cursorOf,
    ExportRecord Function(R row) toRecord,
  ) async* {
    C? cursor;
    while (true) {
      final rows = await fetch(cursor);
      if (rows.isNotEmpty) yield [for (final row in rows) toRecord(row)];
      if (rows.length < pageSize) return;
      cursor = cursorOf(rows.last);
    }
  }

  static Expression<bool> _window(
    Expression<int> at,
    Expression<String> deviceId,
    ({int from, int to}) range,
    _TimeCursor? cursor,
  ) => _inRange(at, range) & _after(at, deviceId, cursor);

  static Expression<bool> _inRange(
    Expression<int> at,
    ({int from, int to}) range,
  ) => at.isBiggerOrEqualValue(range.from) & at.isSmallerThanValue(range.to);

  static Expression<bool> _after(
    Expression<int> at,
    Expression<String> deviceId,
    _TimeCursor? cursor,
  ) {
    if (cursor == null) return const Constant(true);
    return at.isBiggerThanValue(cursor.at) |
        (at.equals(cursor.at) & deviceId.isBiggerThanValue(cursor.deviceId));
  }
}

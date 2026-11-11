import 'package:drift/drift.dart';
import 'package:open_ring/core/database/app_database.dart';
import 'package:open_ring/core/records/epoch.dart';
import 'package:open_ring/core/records/health_record_kind.dart';
import 'package:open_ring/features/health_sync/domain/batch_plan.dart';
import 'package:open_ring/features/health_sync/domain/health_entries.dart';
import 'package:open_ring/features/health_sync/domain/health_outbox_store.dart';
import 'package:open_ring/features/health_sync/domain/heart_rate_series.dart';
import 'package:open_ring/features/health_sync/infrastructure/health_entry_mapper.dart';

const _tick = Duration(milliseconds: 1);

typedef _Group = ({
  DateTime from,
  DateTime to,
  List<HealthEntry> entries,
  List<TimeWindow> excluded,
});

final class DriftHealthRecordSource implements HealthRecordSource {
  const new(this._db);

  final AppDatabase _db;

  @override
  Future<List<HealthWriteBatch>> batches(
    OutboxEntry entry, {
    required int batchSize,
  }) async => [
    for (final group in await _groups(entry))
      ...planBatches(
        kind: entry.kind,
        version: entry.version,
        from: group.from,
        to: group.to,
        entries: group.entries,
        batchSize: batchSize,
        excluded: group.excluded,
      ),
  ];

  Future<List<_Group>> _groups(OutboxEntry entry) async => switch (entry.kind) {
    HealthRecordKind.activity => [_whole(entry, await _activity(entry))],
    HealthRecordKind.heartRate => [await _heartRate(entry)],
    HealthRecordKind.spo2 => [_whole(entry, await _spo2(entry))],
    HealthRecordKind.hrv => [_whole(entry, await _hrv(entry))],
    HealthRecordKind.sleep => [_whole(entry, await _sleep(entry))],
    HealthRecordKind.stress => const [],
    HealthRecordKind.workout => [
      for (final workout in await _workouts(entry))
        (
          from: workout.start,
          to: workout.end,
          entries: [workout],
          excluded: const [],
        ),
    ],
  };

  static _Group _whole(OutboxEntry entry, List<HealthEntry> entries) =>
      (from: entry.from, to: entry.to, entries: entries, excluded: const []);

  String _device(OutboxEntry entry) => entry.deviceId ?? HealthRecordId.phone;

  Future<List<HealthEntry>> _activity(OutboxEntry entry) async {
    final rows =
        await (_db.select(_db.activityBuckets)..where(
              (b) =>
                  b.deviceId.equals(_device(entry)) &
                  b.startUtcMs.isBetweenValues(
                    entry.from.utcMs,
                    entry.to.utcMs,
                  ),
            ))
            .get();
    return [for (final row in rows) ...activityEntries(row)];
  }

  // Widened to whole series buckets so a re-send rebuilds each hour record
  // from all its samples, not only the ones this row covered.
  Future<_Group> _heartRate(OutboxEntry entry) async {
    final from = seriesBucketStart(entry.from);
    final to = seriesBucketStart(entry.to).add(seriesSpan - _tick);
    final excluded = await _workoutWindows(from, to);
    final rows =
        await (_db.select(_db.hrSamples)..where(
              (s) =>
                  s.deviceId.equals(_device(entry)) &
                  s.atUtcMs.isBetweenValues(from.utcMs, to.utcMs),
            ))
            .get();
    final samples = [for (final row in rows) ?heartRateEntry(row)];
    return (
      from: from,
      to: to,
      entries: heartRateSeries(_device(entry), samples, excluded: excluded),
      excluded: excluded,
    );
  }

  Future<List<HealthEntry>> _spo2(OutboxEntry entry) async {
    final rows =
        await (_db.select(_db.spo2Samples)..where(
              (s) =>
                  s.deviceId.equals(_device(entry)) &
                  s.atUtcMs.isBetweenValues(entry.from.utcMs, entry.to.utcMs),
            ))
            .get();
    return [for (final row in rows) ?spo2Entry(row)];
  }

  Future<List<HealthEntry>> _hrv(OutboxEntry entry) async {
    final rows =
        await (_db.select(_db.hrvSamples)..where(
              (s) =>
                  s.deviceId.equals(_device(entry)) &
                  s.atUtcMs.isBetweenValues(entry.from.utcMs, entry.to.utcMs),
            ))
            .get();
    return [for (final row in rows) ?hrvEntry(row)];
  }

  Future<List<HealthEntry>> _sleep(OutboxEntry entry) async {
    final device = _device(entry);
    final sessions =
        await (_db.select(_db.sleepSessions)..where(
              (s) =>
                  s.deviceId.equals(device) &
                  s.startUtcMs.isSmallerOrEqualValue(entry.to.utcMs) &
                  s.endUtcMs.isBiggerOrEqualValue(entry.from.utcMs),
            ))
            .get();
    final starts = [for (final session in sessions) session.startUtcMs];
    final segments =
        await (_db.select(_db.sleepSegments)..where(
              (s) =>
                  s.deviceId.equals(device) & s.sessionStartUtcMs.isIn(starts),
            ))
            .get();
    return [
      for (final session in sessions)
        sleepEntry(session, [
          for (final segment in segments)
            if (segment.sessionStartUtcMs == session.startUtcMs) segment,
        ]),
    ];
  }

  Future<List<WorkoutEntry>> _workouts(OutboxEntry entry) async {
    final workouts =
        await (_db.select(_db.workouts)..where(
              (w) =>
                  w.endUtcMs.isNotNull() &
                  w.startUtcMs.isBetweenValues(
                    entry.from.utcMs,
                    entry.to.utcMs,
                  ),
            ))
            .get();
    final entries = <WorkoutEntry>[];
    for (final workout in workouts) {
      final heartRate =
          await (_db.select(_db.workoutHrSamples)
                ..where((s) => s.workoutId.equals(workout.id))
                ..orderBy([(s) => OrderingTerm.asc(s.atUtcMs)]))
              .get();
      final route =
          await (_db.select(_db.workoutRoutePoints)
                ..where((p) => p.workoutId.equals(workout.id))
                ..orderBy([(p) => OrderingTerm.asc(p.atUtcMs)]))
              .get();
      final mapped = workoutEntry(workout, heartRate, route);
      if (mapped != null) entries.add(mapped);
    }
    return entries;
  }

  // Inside a finished workout that carries its own HR series, that series is
  // the heart rate record, so ring-log samples there are left to the workout.
  Future<List<TimeWindow>> _workoutWindows(DateTime from, DateTime to) async {
    final hasHeartRate = existsQuery(
      _db.select(_db.workoutHrSamples)..where(
        (s) =>
            s.workoutId.equalsExp(_db.workouts.id) &
            s.bpm.isBetweenValues(heartRateRange.min, heartRateRange.max),
      ),
    );
    final rows =
        await (_db.select(_db.workouts)..where(
              (w) =>
                  w.endUtcMs.isNotNull() &
                  w.startUtcMs.isSmallerOrEqualValue(to.utcMs) &
                  w.endUtcMs.isBiggerOrEqualValue(from.utcMs) &
                  hasHeartRate,
            ))
            .get();
    return [
      for (final row in rows)
        if (row.endUtcMs case final end?)
          TimeWindow(fromUtcMs(row.startUtcMs), fromUtcMs(end)),
    ];
  }
}

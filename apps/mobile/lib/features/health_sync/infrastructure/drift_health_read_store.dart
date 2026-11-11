import 'package:drift/drift.dart';
import 'package:open_ring/core/database/app_database.dart';
import 'package:open_ring/core/records/epoch.dart';
import 'package:open_ring/core/records/health_record_kind.dart';
import 'package:open_ring/core/records/source_priority.dart';
import 'package:open_ring/features/health_sync/domain/health_read_store.dart';
import 'package:open_ring/features/health_sync/domain/health_reader.dart';

final class DriftHealthReadStore implements HealthReadStore {
  const new(this._db);

  final AppDatabase _db;

  @override
  Future<HealthReadSettings> settings(HealthRecordKind kind) async {
    final row = await (_db.select(
      _db.healthReads,
    )..where((r) => r.kind.equalsValue(kind))).getSingleOrNull();
    if (row == null) return const HealthReadSettings();
    final last = row.lastReadAtUtcMs;
    return HealthReadSettings(
      enabled: row.enabled,
      lastReadAt: last == null ? null : utcInstant(last),
    );
  }

  @override
  Future<void> setEnabled(HealthRecordKind kind, {required bool enabled}) => _db
      .into(_db.healthReads)
      .insert(
        HealthReadsCompanion.insert(kind: kind, enabled: Value(enabled)),
        onConflict: DoUpdate(
          (_) => HealthReadsCompanion(enabled: Value(enabled)),
        ),
      );

  @override
  Future<List<String>> storedPriority(HealthRecordKind kind) async {
    final rows =
        await (_db.select(_db.sourcePriorities)
              ..where((r) => r.metric.equals(kind.name))
              ..orderBy([(r) => OrderingTerm.asc(r.priority)]))
            .get();
    return [for (final row in rows) row.source];
  }

  @override
  Future<void> savePriority(HealthRecordKind kind, List<String> order) =>
      _db.transaction(() => _writePriority(kind, order));

  Future<void> _writePriority(HealthRecordKind kind, List<String> order) async {
    await (_db.delete(
      _db.sourcePriorities,
    )..where((r) => r.metric.equals(kind.name))).go();
    await _db.batch(
      (batch) => batch.insertAll(_db.sourcePriorities, [
        for (final (index, source) in order.indexed)
          SourcePrioritiesCompanion.insert(
            metric: kind.name,
            source: source,
            priority: index,
          ),
      ]),
    );
  }

  @override
  Future<List<ExternalSource>> sources(HealthRecordKind kind) async {
    final table = _importTable(kind);
    if (table == null) return const [];
    final rows = await _db
        .customSelect(
          'SELECT source, COUNT(*) AS records, MAX(end_utc_ms) AS last_end '
          'FROM ${table.actualTableName} GROUP BY source ORDER BY source',
          readsFrom: {table},
        )
        .get();
    return [
      for (final row in rows)
        ExternalSource(
          id: row.read<String>('source'),
          records: row.read<int>('records'),
          lastEnd: utcInstant(row.read<int>('last_end')),
        ),
    ];
  }

  TableInfo<Table, Object?>? _importTable(HealthRecordKind kind) =>
      switch (kind) {
        HealthRecordKind.sleep => _db.importedSleepSessions,
        HealthRecordKind.workout => _db.importedWorkouts,
        _ => null,
      };

  @override
  Future<void> saveSleep(
    List<ExternalSleepNight> nights, {
    required DateTime readAt,
    ReadCoverage? coverage,
  }) => _db.transaction(() async {
    if (coverage != null) {
      await (_db.delete(_db.importedSleepSessions)..where(
            (s) => _gone(coverage, s.recordId, s.startUtcMs, s.endUtcMs),
          ))
          .go();
    }
    for (final night in nights) {
      await _saveNight(night, readAt);
    }
    await _afterRead(HealthRecordKind.sleep, readAt);
  });

  @override
  Future<void> saveWorkouts(
    List<ExternalWorkout> workouts, {
    required DateTime readAt,
    ReadCoverage? coverage,
  }) => _db.transaction(() async {
    if (coverage != null) {
      await (_db.delete(_db.importedWorkouts)..where(
            (w) => _gone(coverage, w.recordId, w.startUtcMs, w.endUtcMs),
          ))
          .go();
    }
    await _db.batch(
      (batch) => batch.insertAllOnConflictUpdate(_db.importedWorkouts, [
        for (final workout in workouts)
          ImportedWorkoutsCompanion.insert(
            recordId: workout.recordId,
            source: workout.source,
            activityType: workout.activityType,
            startUtcMs: workout.start.utcMs,
            endUtcMs: workout.end.utcMs,
            offsetMinutes: workout.utcOffset.inMinutes,
            importedAtUtcMs: readAt.utcMs,
          ),
      ]),
    );
    await _afterRead(HealthRecordKind.workout, readAt);
  });

  // Same rule as goneFrom; stages go with their session by cascade.
  static Expression<bool> _gone(
    ReadCoverage coverage,
    GeneratedColumn<String> recordId,
    GeneratedColumn<int> startUtcMs,
    GeneratedColumn<int> endUtcMs,
  ) =>
      startUtcMs.isBiggerOrEqualValue(coverage.from.utcMs) &
      endUtcMs.isSmallerOrEqualValue(coverage.to.utcMs) &
      recordId.isNotIn(coverage.present);

  Future<void> _afterRead(HealthRecordKind kind, DateTime readAt) async {
    final seen = await sources(kind);
    final stored = await storedPriority(kind);
    await _writePriority(
      kind,
      resolveSourcePriority(stored, [for (final source in seen) source.id]),
    );
    await _db
        .into(_db.healthReads)
        .insert(
          HealthReadsCompanion.insert(
            kind: kind,
            lastReadAtUtcMs: Value(readAt.utcMs),
          ),
          onConflict: DoUpdate(
            (_) => HealthReadsCompanion(lastReadAtUtcMs: Value(readAt.utcMs)),
          ),
        );
  }

  Future<void> _saveNight(ExternalSleepNight night, DateTime readAt) async {
    await (_db.delete(
      _db.importedSleepStages,
    )..where((s) => s.recordId.equals(night.recordId))).go();
    await _db
        .into(_db.importedSleepSessions)
        .insertOnConflictUpdate(
          ImportedSleepSessionsCompanion.insert(
            recordId: night.recordId,
            source: night.source,
            startUtcMs: night.start.utcMs,
            endUtcMs: night.end.utcMs,
            offsetMinutes: night.utcOffset.inMinutes,
            importedAtUtcMs: readAt.utcMs,
          ),
        );
    await _db.batch(
      (batch) => batch.insertAll(_db.importedSleepStages, [
        for (final stage in night.stages)
          ImportedSleepStagesCompanion.insert(
            recordId: night.recordId,
            startUtcMs: stage.start.utcMs,
            endUtcMs: stage.end.utcMs,
            stage: stage.stage,
          ),
      ], mode: InsertMode.insertOrReplace),
    );
  }
}

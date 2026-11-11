import 'package:meta/meta.dart';
import 'package:open_ring/core/records/health_record_kind.dart';
import 'package:open_ring/core/records/source_priority.dart';
import 'package:open_ring/features/health_sync/domain/health_reader.dart';

@immutable
final class HealthReadSettings {
  const new({this.enabled = false, this.lastReadAt});

  final bool enabled;
  final DateTime? lastReadAt;
}

@immutable
final class ExternalSource {
  const new({required this.id, required this.records, this.lastEnd});

  final String id;
  final int records;
  final DateTime? lastEnd;
}

// The window one read covered and every record id the platform held there.
typedef ReadCoverage = ({DateTime from, DateTime to, Set<String> present});

// Only a record wholly inside the window is judged: one that straddles an
// edge may not be returned by the platform even though it still exists.
bool goneFrom(
  ReadCoverage coverage, {
  required String recordId,
  required DateTime start,
  required DateTime end,
}) =>
    !start.isBefore(coverage.from) &&
    !end.isAfter(coverage.to) &&
    !coverage.present.contains(recordId);

abstract interface class HealthReadStore {
  Future<HealthReadSettings> settings(HealthRecordKind kind);

  Future<void> setEnabled(HealthRecordKind kind, {required bool enabled});

  Future<List<String>> storedPriority(HealthRecordKind kind);

  Future<void> savePriority(HealthRecordKind kind, List<String> order);

  Future<List<ExternalSource>> sources(HealthRecordKind kind);

  // Upserts each night by its platform record id. Only a [coverage] deletes,
  // since the plugin returns an empty list for a failed read as well.
  Future<void> saveSleep(
    List<ExternalSleepNight> nights, {
    required DateTime readAt,
    ReadCoverage? coverage,
  });

  Future<void> saveWorkouts(
    List<ExternalWorkout> workouts, {
    required DateTime readAt,
    ReadCoverage? coverage,
  });
}

final class InMemoryHealthReadStore implements HealthReadStore {
  final Map<HealthRecordKind, HealthReadSettings> _settings = {};
  final Map<HealthRecordKind, List<String>> _priority = {};
  final Map<String, ExternalSleepNight> nights = {};
  final Map<String, ExternalWorkout> workouts = {};

  @override
  Future<HealthReadSettings> settings(HealthRecordKind kind) async =>
      _settings[kind] ?? const HealthReadSettings();

  @override
  Future<void> setEnabled(
    HealthRecordKind kind, {
    required bool enabled,
  }) async => _settings[kind] = HealthReadSettings(
    enabled: enabled,
    lastReadAt: _settings[kind]?.lastReadAt,
  );

  @override
  Future<List<String>> storedPriority(HealthRecordKind kind) async =>
      _priority[kind] ?? const [];

  @override
  Future<void> savePriority(HealthRecordKind kind, List<String> order) async =>
      _priority[kind] = List.unmodifiable(order);

  @override
  Future<List<ExternalSource>> sources(HealthRecordKind kind) async =>
      switch (kind) {
        HealthRecordKind.sleep => _grouped([
          for (final night in nights.values) (night.source, night.end),
        ]),
        HealthRecordKind.workout => _grouped([
          for (final workout in workouts.values) (workout.source, workout.end),
        ]),
        _ => const [],
      };

  static List<ExternalSource> _grouped(List<(String, DateTime)> records) {
    final ends = <String, List<DateTime>>{};
    for (final (source, end) in records) {
      (ends[source] ??= []).add(end);
    }
    final ids = ends.keys.toList()..sort();
    return [
      for (final id in ids)
        ExternalSource(
          id: id,
          records: ends[id]!.length,
          lastEnd: ends[id]!.reduce((a, b) => a.isAfter(b) ? a : b),
        ),
    ];
  }

  @override
  Future<void> saveSleep(
    List<ExternalSleepNight> nights, {
    required DateTime readAt,
    ReadCoverage? coverage,
  }) async {
    if (coverage != null) {
      this.nights.removeWhere(
        (id, night) => goneFrom(
          coverage,
          recordId: id,
          start: night.start,
          end: night.end,
        ),
      );
    }
    for (final night in nights) {
      this.nights[night.recordId] = night;
    }
    await _afterRead(HealthRecordKind.sleep, readAt);
  }

  @override
  Future<void> saveWorkouts(
    List<ExternalWorkout> workouts, {
    required DateTime readAt,
    ReadCoverage? coverage,
  }) async {
    if (coverage != null) {
      this.workouts.removeWhere(
        (id, workout) => goneFrom(
          coverage,
          recordId: id,
          start: workout.start,
          end: workout.end,
        ),
      );
    }
    for (final workout in workouts) {
      this.workouts[workout.recordId] = workout;
    }
    await _afterRead(HealthRecordKind.workout, readAt);
  }

  Future<void> _afterRead(HealthRecordKind kind, DateTime readAt) async {
    final seen = await sources(kind);
    await savePriority(
      kind,
      resolveSourcePriority(await storedPriority(kind), [
        for (final source in seen) source.id,
      ]),
    );
    _settings[kind] = HealthReadSettings(
      enabled: _settings[kind]?.enabled ?? false,
      lastReadAt: readAt,
    );
  }
}

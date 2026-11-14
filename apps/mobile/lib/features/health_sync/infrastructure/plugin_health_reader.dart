import 'package:health/health.dart';
import 'package:open_ring/core/records/health_record_kind.dart';
import 'package:open_ring/features/health_sync/domain/health_reader.dart';
import 'package:open_ring/features/health_sync/domain/health_writer.dart';
import 'package:open_ring/features/health_sync/infrastructure/plugin_health_writer.dart';
import 'package:ring_driver/ring_driver.dart';

abstract interface class HealthReadGateway {
  Future<bool> available();

  Future<bool> hasReadAccess(List<HealthDataType> types);

  Future<bool> requestReadAccess(List<HealthDataType> types);

  Future<bool> backgroundReadAllowed();

  Future<bool> requestBackgroundRead();

  Future<List<HealthDataPoint>> read(
    List<HealthDataType> types, {
    required DateTime from,
    required DateTime to,
  });
}

// The plugin's workout read also sums distance, energy and steps records of
// every app in the session window, which needs three more read permissions.
abstract interface class ExerciseSessionSource {
  Future<ExternalRead<ExternalWorkout>> read({
    required DateTime from,
    required DateTime to,
  });
}

final class NoExerciseSessions implements ExerciseSessionSource {
  const new();

  @override
  Future<ExternalRead<ExternalWorkout>> read({
    required DateTime from,
    required DateTime to,
  }) async => const ExternalRead([]);
}

// The plugin answers a failed read with an empty list, so the ids that prove
// a night is gone come from a read that reports its errors.
abstract interface class SleepSessionIdSource {
  Future<Set<String>?> ids({required DateTime from, required DateTime to});
}

final class NoSleepSessionIds implements SleepSessionIdSource {
  const new();

  @override
  Future<Set<String>?> ids({
    required DateTime from,
    required DateTime to,
  }) async => null;
}

final class PluginHealthReader implements HealthReader {
  const new(
    this._gateway,
    this.platform, {
    this.background = false,
    this.exercise = const NoExerciseSessions(),
    this.sleepIds = const NoSleepSessionIds(),
  });

  // Health Connect has no unstaged phase OpenRing can show, so plain asleep
  // counts as light and out of bed or unknown is dropped.
  static const Map<HealthDataType, SleepStage> stageTypes = {
    HealthDataType.SLEEP_LIGHT: SleepStage.light,
    HealthDataType.SLEEP_ASLEEP: SleepStage.light,
    HealthDataType.SLEEP_DEEP: SleepStage.deep,
    HealthDataType.SLEEP_REM: SleepStage.rem,
    HealthDataType.SLEEP_AWAKE: SleepStage.awake,
    HealthDataType.SLEEP_AWAKE_IN_BED: SleepStage.awake,
  };

  final HealthReadGateway _gateway;
  final HealthPlatform platform;
  final bool background;
  final ExerciseSessionSource exercise;
  final SleepSessionIdSource sleepIds;

  bool get _builtHere => platform == HealthPlatform.healthConnect;

  static List<HealthDataType> readTypes(HealthRecordKind kind) =>
      switch (kind) {
        HealthRecordKind.sleep => const [HealthDataType.SLEEP_SESSION],
        HealthRecordKind.workout => const [HealthDataType.WORKOUT],
        _ => const [],
      };

  @override
  Future<HealthAccess> readAccess(HealthRecordKind kind) async {
    final types = readTypes(kind);
    if (!_builtHere || types.isEmpty) return HealthAccess.unavailable;
    if (!await _gateway.available()) return HealthAccess.unavailable;
    if (!await _gateway.hasReadAccess(types)) return HealthAccess.denied;
    if (background && !await _gateway.backgroundReadAllowed()) {
      return HealthAccess.deferred;
    }
    return HealthAccess.granted;
  }

  @override
  Future<bool> requestReadAccess(HealthRecordKind kind) async {
    final types = readTypes(kind);
    if (!_builtHere || types.isEmpty) return false;
    if (!await _gateway.available()) return false;
    return await _gateway.requestReadAccess(types);
  }

  @override
  Future<bool> backgroundReadAllowed() async {
    if (!_builtHere) return false;
    return await _gateway.backgroundReadAllowed();
  }

  @override
  Future<bool> requestBackgroundReadAccess() async {
    if (!_builtHere) return false;
    return await _gateway.requestBackgroundRead();
  }

  @override
  Future<ExternalRead<ExternalSleepNight>> sleepNights({
    required DateTime from,
    required DateTime to,
  }) async {
    if (!_builtHere) return const ExternalRead([]);
    final sessions = await _gateway.read(
      readTypes(HealthRecordKind.sleep),
      from: from,
      to: to,
    );
    final present = await sleepIds.ids(from: from, to: to);
    if (sessions.isEmpty) return ExternalRead(const [], present: present);
    final stages = await _gateway.read(
      stageTypes.keys.toList(),
      from: from,
      to: to,
    );
    return ExternalRead(nightsOf(sessions, stages), present: present);
  }

  @override
  Future<ExternalRead<ExternalWorkout>> workouts({
    required DateTime from,
    required DateTime to,
  }) async {
    if (!_builtHere) return const ExternalRead([]);
    return await exercise.read(from: from, to: to);
  }

  // Each stage point carries the id of the session it belongs to.
  static List<ExternalSleepNight> nightsOf(
    List<HealthDataPoint> sessions,
    List<HealthDataPoint> stages,
  ) {
    final byRecord = <String, List<ExternalSleepStage>>{};
    for (final point in stages) {
      final stage = stageTypes[point.type];
      if (stage == null || point.uuid.isEmpty) continue;
      (byRecord[point.uuid] ??= []).add((
        start: point.dateFrom.toUtc(),
        end: point.dateTo.toUtc(),
        stage: stage,
      ));
    }
    return [
      for (final session in sessions)
        if (session.uuid.isNotEmpty)
          ExternalSleepNight(
            recordId: session.uuid,
            source: session.sourceName,
            start: session.dateFrom.toUtc(),
            end: session.dateTo.toUtc(),
            utcOffset: session.dateFrom.toLocal().timeZoneOffset,
            stages: _ordered(byRecord[session.uuid] ?? const []),
          ),
    ];
  }

  static List<ExternalSleepStage> _ordered(List<ExternalSleepStage> stages) =>
      [...stages]..sort((a, b) => a.start.compareTo(b.start));
}

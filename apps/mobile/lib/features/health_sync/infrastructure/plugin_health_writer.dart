import 'package:health/health.dart';
import 'package:open_ring/core/records/health_record_kind.dart';
import 'package:open_ring/features/health_sync/domain/health_entries.dart';
import 'package:open_ring/features/health_sync/domain/health_writer.dart';
import 'package:ring_driver/ring_driver.dart';

enum HealthPlatform { healthConnect, healthKit }

abstract interface class HealthGateway {
  Future<bool> available();

  Future<bool> hasWriteAccess(List<HealthDataType> types);

  Future<bool> requestWriteAccess(List<HealthDataType> types);

  Future<bool> write(
    HealthDataType type,
    double value, {
    required DateTime start,
    required DateTime end,
    required String clientRecordId,
    required int version,
  });

  Future<bool> delete(
    HealthDataType type, {
    required DateTime from,
    required DateTime to,
  });

  Future<String?> writeWorkout({
    required HealthWorkoutActivityType type,
    required DateTime start,
    required DateTime end,
    int? kilocalories,
    int? meters,
  });

  Future<bool> writeRoute(String workoutId, List<WorkoutRouteLocation> route);
}

// Health Connect sleep through the app's own channel: the plugin can only
// write one stage per session.
abstract interface class SleepSessionWriter {
  Future<void> deleteRange({required DateTime from, required DateTime to});

  Future<void> write(SleepEntry night, {required int version});
}

// Health Connect heart rate through the app's own channel: the plugin writes
// one HeartRateRecord per sample instead of a series.
abstract interface class HeartRateSeriesWriter {
  Future<void> deleteRange({required DateTime from, required DateTime to});

  Future<void> write(
    List<HeartRateSeriesEntry> series, {
    required int version,
    required bool active,
  });
}

final class PluginHealthWriter implements HealthWriter {
  const new(
    this._gateway,
    this.platform, {
    required this.sleepSessions,
    required this.heartRateSeries,
  });

  final HealthGateway _gateway;
  final HealthPlatform platform;
  final SleepSessionWriter sleepSessions;
  final HeartRateSeriesWriter heartRateSeries;

  bool get _kit => platform == HealthPlatform.healthKit;

  List<HealthDataType> writeTypes(HealthRecordKind kind) => switch (kind) {
    HealthRecordKind.activity => const [
      HealthDataType.STEPS,
      HealthDataType.ACTIVE_ENERGY_BURNED,
    ],
    HealthRecordKind.heartRate => const [HealthDataType.HEART_RATE],
    HealthRecordKind.spo2 => const [HealthDataType.BLOOD_OXYGEN],
    HealthRecordKind.hrv => [_hrvType],
    HealthRecordKind.sleep => [_sleepType],
    HealthRecordKind.stress => const [],
    HealthRecordKind.workout => [
      HealthDataType.WORKOUT,
      HealthDataType.WORKOUT_ROUTE,
      HealthDataType.HEART_RATE,
      if (!_kit) HealthDataType.DISTANCE_DELTA,
    ],
  };

  HealthDataType get _hrvType => _kit
      ? HealthDataType.HEART_RATE_VARIABILITY_SDNN
      : HealthDataType.HEART_RATE_VARIABILITY_RMSSD;

  HealthDataType get _sleepType =>
      _kit ? HealthDataType.SLEEP_IN_BED : HealthDataType.SLEEP_SESSION;

  // Health Connect upserts by client record id, so it only clears what the
  // plugin writes without one; HealthKit has no sync id through the plugin.
  List<HealthDataType> clearedTypes(HealthWriteBatch batch) =>
      switch (batch.kind) {
        HealthRecordKind.sleep => _kit ? [_sleepType] : const [],
        HealthRecordKind.workout => [
          HealthDataType.WORKOUT,
          if (_kit) HealthDataType.WORKOUT_ROUTE,
          if (_kit && _carriesHeartRate(batch)) HealthDataType.HEART_RATE,
          if (!_kit) HealthDataType.DISTANCE_DELTA,
        ],
        HealthRecordKind.stress => const [],
        final kind => _kit ? writeTypes(kind) : const [],
      };

  static bool _carriesHeartRate(HealthWriteBatch batch) => batch.entries.any(
    (entry) => entry is WorkoutEntry && entry.heartRate.isNotEmpty,
  );

  @override
  Future<HealthAccess> access(HealthRecordKind kind) async {
    if (!await _gateway.available()) return HealthAccess.unavailable;
    final granted = await _gateway.hasWriteAccess(writeTypes(kind));
    return granted ? HealthAccess.granted : HealthAccess.denied;
  }

  bool _nativeSleep(HealthRecordKind kind) =>
      !_kit && kind == HealthRecordKind.sleep;

  bool _nativeHeartRate(HealthRecordKind kind) =>
      !_kit && kind == HealthRecordKind.heartRate;

  // Also clears the one-record-per-sample heart rate older builds wrote.
  bool _clearsSeries(HealthWriteBatch batch) =>
      _nativeHeartRate(batch.kind) ||
      (!_kit &&
          batch.kind == HealthRecordKind.workout &&
          _carriesHeartRate(batch));

  @override
  Future<bool> requestAccess(Set<HealthRecordKind> kinds) async {
    if (!await _gateway.available()) return false;
    final types = {for (final kind in kinds) ...writeTypes(kind)};
    return await _gateway.requestWriteAccess(types.toList());
  }

  @override
  Future<void> replace(HealthWriteBatch batch) async {
    for (final type in clearedTypes(batch)) {
      await _expect(
        _gateway.delete(type, from: batch.from, to: batch.to),
        'delete ${type.name} from ${batch.from} to ${batch.to}',
      );
    }
    if (_nativeSleep(batch.kind)) {
      await sleepSessions.deleteRange(from: batch.from, to: batch.to);
    }
    if (_clearsSeries(batch)) {
      await heartRateSeries.deleteRange(from: batch.from, to: batch.to);
    }
    if (_nativeHeartRate(batch.kind)) {
      return await heartRateSeries.write(
        [...batch.entries.whereType<HeartRateSeriesEntry>()],
        version: batch.version,
        active: false,
      );
    }
    for (final entry in batch.entries) {
      await _write(entry, batch.version);
    }
  }

  Future<void> _write(HealthEntry entry, int version) => switch (entry) {
    StepsEntry(:final count) => _sample(
      HealthDataType.STEPS,
      count.toDouble(),
      entry,
      version,
    ),
    ActiveEnergyEntry(:final kilocalories) => _sample(
      HealthDataType.ACTIVE_ENERGY_BURNED,
      kilocalories,
      entry,
      version,
    ),
    HeartRateEntry(:final bpm) => _sample(
      HealthDataType.HEART_RATE,
      bpm.toDouble(),
      entry,
      version,
    ),
    HeartRateSeriesEntry(:final samples) => _heartRateSamples(samples, version),
    Spo2Entry(:final percent) => _sample(
      HealthDataType.BLOOD_OXYGEN,
      _kit ? percent / 100 : percent.toDouble(),
      entry,
      version,
    ),
    HrvEntry(:final milliseconds) => _sample(
      _hrvType,
      milliseconds.toDouble(),
      entry,
      version,
    ),
    SleepEntry() =>
      _kit
          ? _sleepSamples(entry, version)
          : sleepSessions.write(entry, version: version),
    WorkoutEntry() => _workout(entry, version),
  };

  Future<void> _sleepSamples(SleepEntry entry, int version) async {
    await _sample(HealthDataType.SLEEP_IN_BED, 0, entry, version);
    for (final stage in entry.stages) {
      await _record(
        stageType(stage.stage),
        0,
        id: stage.id,
        start: stage.start,
        end: stage.end,
        version: version,
      );
    }
  }

  Future<void> _workout(WorkoutEntry entry, int version) async {
    final workoutId = await _gateway.writeWorkout(
      type: workoutActivityType(entry.activityType, healthKit: _kit),
      start: entry.start,
      end: entry.end,
      kilocalories: _kit ? entry.activeKilocalories?.round() : null,
      meters: entry.distanceMeters?.round(),
    );
    if (workoutId == null) {
      throw HealthWriteException('workout ${entry.id} was not written');
    }
    await (_kit
        ? _heartRateSamples(entry.heartRate, version)
        : heartRateSeries.write(
            entry.heartRateSeries,
            version: version,
            active: true,
          ));
    if (entry.route.isEmpty) return;
    await _expect(
      _gateway.writeRoute(workoutId, [
        for (final point in entry.route)
          WorkoutRouteLocation(
            latitude: point.latitude,
            longitude: point.longitude,
            timestamp: point.at,
            altitude: point.altitudeMeters,
            horizontalAccuracy: point.accuracyMeters,
          ),
      ]),
      'route of ${entry.id}',
    );
  }

  Future<void> _heartRateSamples(
    List<HeartRateEntry> samples,
    int version,
  ) async {
    for (final sample in samples) {
      await _sample(
        HealthDataType.HEART_RATE,
        sample.bpm.toDouble(),
        sample,
        version,
      );
    }
  }

  Future<void> _sample(
    HealthDataType type,
    double value,
    HealthEntry entry,
    int version,
  ) => _record(
    type,
    value,
    id: entry.id,
    start: entry.start,
    end: entry.end,
    version: version,
  );

  Future<void> _record(
    HealthDataType type,
    double value, {
    required String id,
    required DateTime start,
    required DateTime end,
    required int version,
  }) => _expect(
    _gateway.write(
      type,
      value,
      start: start,
      end: end,
      clientRecordId: id,
      version: version,
    ),
    'write ${type.name} $id',
  );

  static Future<void> _expect(Future<bool> call, String what) async {
    if (await call) return;
    throw HealthWriteException('$what failed');
  }

  static HealthDataType stageType(SleepStage stage) => switch (stage) {
    SleepStage.light => HealthDataType.SLEEP_LIGHT,
    SleepStage.deep => HealthDataType.SLEEP_DEEP,
    SleepStage.rem => HealthDataType.SLEEP_REM,
    SleepStage.awake => HealthDataType.SLEEP_AWAKE,
  };

  // The plugin rejects STRENGTH_TRAINING and RUNNING_TREADMILL on iOS, and
  // its Android writer has no BIKING_STATIONARY entry, so those fall back.
  static HealthWorkoutActivityType workoutActivityType(
    String type, {
    bool healthKit = false,
  }) => switch (type.toLowerCase()) {
    'walking' => HealthWorkoutActivityType.WALKING,
    'running' => HealthWorkoutActivityType.RUNNING,
    'cycling' ||
    'biking' ||
    'stationary_cycling' => HealthWorkoutActivityType.BIKING,
    'hiking' => HealthWorkoutActivityType.HIKING,
    'strength_training' when healthKit =>
      HealthWorkoutActivityType.TRADITIONAL_STRENGTH_TRAINING,
    'strength_training' => HealthWorkoutActivityType.STRENGTH_TRAINING,
    'treadmill_running' when healthKit => HealthWorkoutActivityType.RUNNING,
    'treadmill_running' => HealthWorkoutActivityType.RUNNING_TREADMILL,
    'elliptical' => HealthWorkoutActivityType.ELLIPTICAL,
    'yoga' => HealthWorkoutActivityType.YOGA,
    _ => HealthWorkoutActivityType.OTHER,
  };
}

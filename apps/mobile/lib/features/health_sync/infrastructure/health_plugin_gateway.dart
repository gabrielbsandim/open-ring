import 'dart:io';

import 'package:health/health.dart';
import 'package:open_ring/features/health_sync/infrastructure/method_channel_exercise_sessions.dart';
import 'package:open_ring/features/health_sync/infrastructure/method_channel_heart_rate_series.dart';
import 'package:open_ring/features/health_sync/infrastructure/method_channel_sleep_sessions.dart';
import 'package:open_ring/features/health_sync/infrastructure/plugin_health_reader.dart';
import 'package:open_ring/features/health_sync/infrastructure/plugin_health_writer.dart';

final class HealthPluginGateway implements HealthGateway, HealthReadGateway {
  new([Health? health, HealthPlatform? platform])
    : _health = health ?? Health(),
      _platformOverride = platform;

  final Health _health;
  final HealthPlatform? _platformOverride;
  Future<void>? _configured;

  static HealthPlatform get _platform =>
      Platform.isIOS ? HealthPlatform.healthKit : HealthPlatform.healthConnect;

  static PluginHealthWriter writer() => PluginHealthWriter(
    HealthPluginGateway(),
    _platform,
    sleepSessions: const MethodChannelSleepSessions(),
    heartRateSeries: const MethodChannelHeartRateSeries(),
  );

  static PluginHealthReader reader({bool background = false}) =>
      PluginHealthReader(
        HealthPluginGateway(),
        _platform,
        background: background,
        exercise: const MethodChannelExerciseSessions(),
        sleepIds: const MethodChannelSleepSessions(),
      );

  Future<void> _ready() => _configured ??= _health.configure();

  static List<HealthDataAccess> _writeOnly(List<HealthDataType> types) => [
    for (final _ in types) HealthDataAccess.WRITE,
  ];

  static List<HealthDataAccess> _readOnly(List<HealthDataType> types) => [
    for (final _ in types) HealthDataAccess.READ,
  ];

  @override
  Future<bool> available() async {
    await _ready();
    return await _health.isHealthConnectAvailable();
  }

  @override
  Future<bool> hasWriteAccess(List<HealthDataType> types) async {
    if (types.isEmpty) return true;
    final granted = await _health.hasPermissions(
      types,
      permissions: _writeOnly(types),
    );
    return granted ?? false;
  }

  @override
  Future<bool> requestWriteAccess(List<HealthDataType> types) =>
      _health.requestAuthorization(types, permissions: _writeOnly(types));

  @override
  Future<bool> hasReadAccess(List<HealthDataType> types) async {
    if (types.isEmpty) return true;
    final granted = await _health.hasPermissions(
      types,
      permissions: _readOnly(types),
    );
    return granted ?? false;
  }

  @override
  Future<bool> requestReadAccess(List<HealthDataType> types) =>
      _health.requestAuthorization(types, permissions: _readOnly(types));

  @override
  Future<bool> backgroundReadAllowed() async {
    if (!await _health.isHealthDataInBackgroundAvailable()) return false;
    return await _health.isHealthDataInBackgroundAuthorized();
  }

  @override
  Future<List<HealthDataPoint>> read(
    List<HealthDataType> types, {
    required DateTime from,
    required DateTime to,
  }) async {
    await _ready();
    return await _health.getHealthDataFromTypes(
      types: types,
      startTime: from,
      endTime: to,
    );
  }

  @override
  Future<bool> write(
    HealthDataType type,
    double value, {
    required DateTime start,
    required DateTime end,
    required String clientRecordId,
    required int version,
  }) => _health.writeHealthData(
    value: value,
    type: type,
    startTime: start,
    endTime: end,
    clientRecordId: clientRecordId,
    clientRecordVersion: version.toDouble(),
  );

  @override
  Future<bool> delete(
    HealthDataType type, {
    required DateTime from,
    required DateTime to,
  }) => _health.delete(type: type, startTime: from, endTime: to);

  @override
  Future<String?> writeWorkout({
    required HealthWorkoutActivityType type,
    required DateTime start,
    required DateTime end,
    int? kilocalories,
    int? meters,
  }) async {
    final id = await _health.writeWorkoutDataUUID(
      activityType: type,
      start: start,
      end: end,
      totalEnergyBurned: kilocalories,
      totalDistance: meters,
      recordingMethod: _workoutRecordingMethod(_platformOverride ?? _platform),
    );
    if (id == null || id.isEmpty || id == 'null') return null;
    return id;
  }

  // health 13.3.2 sends manual as Health Connect's ACTIVELY_RECORDED (its
  // constant table is inverted), and HealthKit only takes manual or automatic.
  static RecordingMethod _workoutRecordingMethod(HealthPlatform platform) =>
      switch (platform) {
        HealthPlatform.healthConnect => RecordingMethod.manual,
        HealthPlatform.healthKit => RecordingMethod.automatic,
      };

  @override
  Future<bool> writeRoute(
    String workoutId,
    List<WorkoutRouteLocation> route,
  ) async {
    final builder = await _health.startWorkoutRoute();
    try {
      final inserted = await _health.insertWorkoutRouteData(
        builderId: builder,
        locations: route,
      );
      if (!inserted) {
        await _health.discardWorkoutRoute(builder);
        return false;
      }
      await _health.finishWorkoutRoute(
        builderId: builder,
        workoutUuid: workoutId,
      );
      return true;
    } on Object {
      await _health.discardWorkoutRoute(builder);
      rethrow;
    }
  }
}

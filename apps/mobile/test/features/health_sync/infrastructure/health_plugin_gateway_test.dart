import 'package:flutter_test/flutter_test.dart';
import 'package:health/health.dart';
import 'package:open_ring/features/health_sync/infrastructure/health_plugin_gateway.dart';
import 'package:open_ring/features/health_sync/infrastructure/plugin_health_writer.dart';

class _FakeHealth extends Fake implements Health {
  final workoutMethods = <RecordingMethod>[];
  final workoutArgs = <Map<String, Object?>>[];
  final dataMethods = <RecordingMethod>[];
  bool backgroundAvailable = true;
  bool backgroundGrant = true;
  int backgroundRequests = 0;

  @override
  Future<bool> isHealthDataInBackgroundAvailable() async => backgroundAvailable;

  @override
  Future<bool> requestHealthDataInBackgroundAuthorization() async {
    backgroundRequests++;
    return backgroundGrant;
  }

  @override
  Future<String?> writeWorkoutDataUUID({
    required HealthWorkoutActivityType activityType,
    required DateTime start,
    required DateTime end,
    int? totalEnergyBurned,
    HealthDataUnit totalEnergyBurnedUnit = HealthDataUnit.KILOCALORIE,
    int? totalDistance,
    HealthDataUnit totalDistanceUnit = HealthDataUnit.METER,
    String? title,
    RecordingMethod recordingMethod = RecordingMethod.automatic,
  }) async {
    workoutMethods.add(recordingMethod);
    workoutArgs.add({
      'type': activityType,
      'energy': totalEnergyBurned,
      'distance': totalDistance,
    });
    return 'uuid-1';
  }

  @override
  Future<bool> writeHealthData({
    required double value,
    required HealthDataType type,
    required DateTime startTime,
    HealthDataUnit? unit,
    String? clientRecordId,
    double? clientRecordVersion,
    DateTime? endTime,
    RecordingMethod recordingMethod = RecordingMethod.automatic,
  }) async {
    dataMethods.add(recordingMethod);
    return true;
  }
}

Future<String?> _writeWorkout(HealthPluginGateway gateway) =>
    gateway.writeWorkout(
      type: HealthWorkoutActivityType.RUNNING,
      start: DateTime.utc(2026, 11, 10, 8),
      end: DateTime.utc(2026, 11, 10, 9),
      kilocalories: 300,
      meters: 5000,
    );

void main() {
  test('criterion 1: Health Connect workouts pass the manual method', () async {
    final health = _FakeHealth();
    final gateway = HealthPluginGateway(health, HealthPlatform.healthConnect);

    final id = await _writeWorkout(gateway);

    expect(id, 'uuid-1');
    expect(health.workoutMethods, [RecordingMethod.manual]);
  });

  test('criterion 1: the energy and distance still travel with it', () async {
    final health = _FakeHealth();
    final gateway = HealthPluginGateway(health, HealthPlatform.healthConnect);

    await _writeWorkout(gateway);

    expect(health.workoutArgs.single, {
      'type': HealthWorkoutActivityType.RUNNING,
      'energy': 300,
      'distance': 5000,
    });
  });

  test('criterion 2: HealthKit workouts pass the automatic method', () async {
    final health = _FakeHealth();
    final gateway = HealthPluginGateway(health, HealthPlatform.healthKit);

    await _writeWorkout(gateway);

    expect(health.workoutMethods, [RecordingMethod.automatic]);
  });

  test(
    'criterion 3: write keeps the plugin default recording method',
    () async {
      final health = _FakeHealth();
      final gateway = HealthPluginGateway(health, HealthPlatform.healthConnect);

      await gateway.write(
        HealthDataType.STEPS,
        10,
        start: DateTime.utc(2026, 11, 10, 8),
        end: DateTime.utc(2026, 11, 10, 9),
        clientRecordId: 'c-1',
        version: 1,
      );

      expect(health.dataMethods, [RecordingMethod.automatic]);
    },
  );

  test('criterion 3: the background request maps to the plugin call', () async {
    final health = _FakeHealth();
    final gateway = HealthPluginGateway(health, HealthPlatform.healthConnect);

    expect(await gateway.requestBackgroundRead(), isTrue);
    expect(health.backgroundRequests, 1);
  });

  test('criterion 3: a refused background request returns false', () async {
    final health = _FakeHealth()..backgroundGrant = false;
    final gateway = HealthPluginGateway(health, HealthPlatform.healthConnect);

    expect(await gateway.requestBackgroundRead(), isFalse);
    expect(health.backgroundRequests, 1);
  });

  test(
    'criterion 3: without the background feature nothing launches',
    () async {
      final health = _FakeHealth()..backgroundAvailable = false;
      final gateway = HealthPluginGateway(health, HealthPlatform.healthConnect);

      expect(await gateway.requestBackgroundRead(), isFalse);
      expect(health.backgroundRequests, 0);
    },
  );
}

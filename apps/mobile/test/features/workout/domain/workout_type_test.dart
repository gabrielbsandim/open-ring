import 'package:flutter_test/flutter_test.dart';
import 'package:health/health.dart';
import 'package:open_ring/features/health_sync/infrastructure/plugin_health_writer.dart';
import 'package:open_ring/features/workout/domain/workout_type.dart';

void main() {
  test('the design types are all there with their GPS default', () {
    expect(
      {for (final type in WorkoutType.values) type: type.location},
      {
        WorkoutType.running: WorkoutLocation.outdoor,
        WorkoutType.walking: WorkoutLocation.outdoor,
        WorkoutType.cycling: WorkoutLocation.outdoor,
        WorkoutType.hiking: WorkoutLocation.outdoor,
        WorkoutType.strength: WorkoutLocation.indoor,
        WorkoutType.treadmill: WorkoutLocation.indoor,
        WorkoutType.stationaryBike: WorkoutLocation.indoor,
        WorkoutType.elliptical: WorkoutLocation.indoor,
        WorkoutType.yoga: WorkoutLocation.indoor,
        WorkoutType.other: WorkoutLocation.optional,
      },
    );
  });

  test('only outdoor types start with GPS, and indoor types never get it', () {
    expect(WorkoutType.running.gpsByDefault, isTrue);
    expect(WorkoutType.other.gpsByDefault, isFalse);
    expect(WorkoutType.other.allowsGps(requested: true), isTrue);
    expect(WorkoutType.yoga.allowsGps(requested: true), isFalse);
    expect(WorkoutType.walking.allowsGps(requested: false), isFalse);
  });

  test('MET values follow metrics.md section 11', () {
    expect(
      {for (final type in WorkoutType.values) type.name: type.met},
      {
        'running': 9.8,
        'walking': 3.5,
        'cycling': 7.5,
        'hiking': 6.0,
        'strength': 3.5,
        'treadmill': 9.8,
        'stationaryBike': 7.0,
        'elliptical': 5.0,
        'yoga': 2.5,
        'other': 4.0,
      },
    );
  });

  test('activity types are unique and parse back, unknown ones as other', () {
    final names = WorkoutType.values.map((t) => t.activityType).toSet();
    expect(names, hasLength(WorkoutType.values.length));
    for (final type in WorkoutType.values) {
      expect(WorkoutType.ofActivityType(type.activityType), type);
    }
    expect(WorkoutType.ofActivityType('rowing'), WorkoutType.other);
  });

  group('Health type mapping', () {
    HealthWorkoutActivityType mapped(WorkoutType type, {required bool kit}) =>
        PluginHealthWriter.workoutActivityType(
          type.activityType,
          healthKit: kit,
        );

    test('Health Connect', () {
      expect(
        {for (final type in WorkoutType.values) type: mapped(type, kit: false)},
        {
          WorkoutType.running: HealthWorkoutActivityType.RUNNING,
          WorkoutType.walking: HealthWorkoutActivityType.WALKING,
          WorkoutType.cycling: HealthWorkoutActivityType.BIKING,
          WorkoutType.hiking: HealthWorkoutActivityType.HIKING,
          WorkoutType.strength: HealthWorkoutActivityType.STRENGTH_TRAINING,
          WorkoutType.treadmill: HealthWorkoutActivityType.RUNNING_TREADMILL,
          WorkoutType.stationaryBike: HealthWorkoutActivityType.BIKING,
          WorkoutType.elliptical: HealthWorkoutActivityType.ELLIPTICAL,
          WorkoutType.yoga: HealthWorkoutActivityType.YOGA,
          WorkoutType.other: HealthWorkoutActivityType.OTHER,
        },
      );
    });

    test('HealthKit', () {
      expect(
        {for (final type in WorkoutType.values) type: mapped(type, kit: true)},
        {
          WorkoutType.running: HealthWorkoutActivityType.RUNNING,
          WorkoutType.walking: HealthWorkoutActivityType.WALKING,
          WorkoutType.cycling: HealthWorkoutActivityType.BIKING,
          WorkoutType.hiking: HealthWorkoutActivityType.HIKING,
          WorkoutType.strength:
              HealthWorkoutActivityType.TRADITIONAL_STRENGTH_TRAINING,
          WorkoutType.treadmill: HealthWorkoutActivityType.RUNNING,
          WorkoutType.stationaryBike: HealthWorkoutActivityType.BIKING,
          WorkoutType.elliptical: HealthWorkoutActivityType.ELLIPTICAL,
          WorkoutType.yoga: HealthWorkoutActivityType.YOGA,
          WorkoutType.other: HealthWorkoutActivityType.OTHER,
        },
      );
    });
  });
}

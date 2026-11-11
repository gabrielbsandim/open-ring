import 'package:meta/meta.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/features/today/application/today_view.dart';
import 'package:open_ring/features/workout/domain/workout_history.dart';

@immutable
final class WidgetSnapshot {
  const new({
    required this.date,
    required this.freshness,
    required this.stepGoal,
    this.syncedAt,
    this.readiness,
    this.restingHeartRate,
    this.hrv,
    this.baselineNights,
    this.sleepMinutes,
    this.sleepScore,
    this.steps,
    this.heartRateMean,
    this.heartRateMin,
    this.heartRateMax,
    this.spo2,
    this.stress,
    this.batteryPercent,
    this.batteryCharging,
    this.lastWorkout,
  });

  static const version = 1;

  final LocalDate date;
  final SyncFreshness freshness;
  final DateTime? syncedAt;
  final int stepGoal;
  final int? readiness;
  final int? restingHeartRate;
  final int? hrv;
  final int? baselineNights;
  final int? sleepMinutes;
  final int? sleepScore;
  final int? steps;
  final int? heartRateMean;
  final int? heartRateMin;
  final int? heartRateMax;
  final int? spo2;
  final int? stress;
  final int? batteryPercent;
  final bool? batteryCharging;
  final WorkoutEntry? lastWorkout;

  bool get paired => freshness != SyncFreshness.unpaired;

  bool get hasHealthData => [
    readiness,
    restingHeartRate,
    hrv,
    sleepMinutes,
    sleepScore,
    steps,
    heartRateMean,
    spo2,
    stress,
  ].any((value) => value != null);

  Map<String, Object?> toJson() => {
    'version': version,
    'date': date.iso,
    'paired': paired,
    'syncedAtMs': syncedAt?.millisecondsSinceEpoch,
    'staleAfterMs': staleSyncAfter.inMilliseconds,
    'stepGoal': stepGoal,
    'readiness': readiness,
    'restingHeartRate': restingHeartRate,
    'hrv': hrv,
    'baselineNights': baselineNights,
    'sleepMinutes': sleepMinutes,
    'sleepScore': sleepScore,
    'steps': steps,
    'heartRateMean': heartRateMean,
    'heartRateMin': heartRateMin,
    'heartRateMax': heartRateMax,
    'spo2': spo2,
    'stress': stress,
    'batteryPercent': batteryPercent,
    'batteryCharging': batteryCharging,
    'lastWorkout': switch (lastWorkout) {
      null => null,
      final workout => {
        'type': workout.type.name,
        'startMs': workout.start.millisecondsSinceEpoch,
        'elapsedSeconds': workout.elapsed.inSeconds,
        'distanceMeters': switch (workout) {
          WorkoutListItem(:final distanceMeters) => distanceMeters,
          ImportedWorkout() => null,
        },
      },
    },
  };
}

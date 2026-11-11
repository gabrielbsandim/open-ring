import 'package:open_ring/features/today/application/today_view.dart';
import 'package:open_ring/features/widgets/domain/widget_snapshot.dart';
import 'package:open_ring/features/workout/domain/workout_history.dart';

WidgetSnapshot buildWidgetSnapshot(
  TodayView view, {
  WorkoutEntry? lastWorkout,
}) {
  final readiness = view.readiness;
  final heart = view.heart;
  final night = view.lastNight.night;
  return WidgetSnapshot(
    date: readiness.date,
    freshness: view.freshness,
    syncedAt: view.ring.lastSyncAt,
    stepGoal: view.stepGoal,
    readiness: readiness.value,
    restingHeartRate: _round(readiness.restingHeartRate.today),
    hrv: _round(readiness.hrv.today),
    baselineNights: readiness.baselineNights,
    sleepMinutes: night == null ? null : (night.asleep.inSeconds / 60).round(),
    sleepScore: view.lastNight.scoreValue,
    steps: view.activity?.steps,
    heartRateMean: _round(heart.heartRate.mean),
    heartRateMin: _round(heart.heartRate.min),
    heartRateMax: _round(heart.heartRate.max),
    spo2: _round(heart.spo2.mean),
    stress: _round(heart.stress.mean),
    batteryPercent: view.ring.batteryPercent,
    batteryCharging: view.ring.batteryCharging,
    lastWorkout: lastWorkout,
  );
}

int? _round(double? value) => value?.round();

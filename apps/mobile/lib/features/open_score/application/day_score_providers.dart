import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/core/records/data_revision.dart';
import 'package:open_ring/features/activity/application/activity_providers.dart';
import 'package:open_ring/features/heart/application/heart_providers.dart';
import 'package:open_ring/features/open_score/domain/day_score_history.dart';
import 'package:open_ring/features/trends/application/trends_providers.dart';
import 'package:open_ring/features/workout/application/workout_history_providers.dart';
import 'package:open_ring/features/workout/application/workout_source_selection.dart';
import 'package:open_ring/features/workout/domain/workout_history.dart';

// Far above what 96 days can hold, so the scan never cuts the window short.
const dayScoreWorkoutScanLimit = 1000;

final dailyStressProvider = FutureProvider<List<DailyValue>>((ref) async {
  ref.watch(dataRevisionProvider);
  final now = ref.watch(clockProvider)();
  final today = ref.watch(currentDateProvider);
  final offset = now.timeZoneOffset;
  final readings = await ref
      .watch(heartHistoryReaderProvider)
      .stress(
        from: localMidnight(today.addDays(-dayStressDays), offset),
        to: now,
      );
  return dailyStress(readings, utcOffset: offset);
});

final dailyIntensityProvider = FutureProvider<List<DailyValue>>(
  (ref) => readDailyIntensity(ref, days: dayIntensityDays),
);

Future<List<DailyValue>> readDailyIntensity(
  Ref ref, {
  required int days,
}) async {
  ref.watch(dataRevisionProvider);
  final today = ref.watch(currentDateProvider);
  final maxHeartRate = ref.watch(savedWorkoutZonesProvider)?.maxHeartRate;
  final reader = ref.watch(workoutHistoryReaderProvider);
  final (slots, own, imported) = await (
    ref
        .watch(activityHistoryReaderProvider)
        .activitySlots(from: today.addDays(-days), to: today),
    reader.recent(limit: dayScoreWorkoutScanLimit),
    ref
        .watch(importedWorkoutReaderProvider)
        .recent(limit: dayScoreWorkoutScanLimit),
  ).wait;
  final selected = selectWorkouts([
    ...own,
    ...imported.workouts,
  ], imported.priority);
  final credits = await Future.wait([
    for (final entry in selected)
      if (_inWindow(today, _dateOf(entry), days))
        _credit(reader, entry, maxHeartRate),
  ]);
  return dailyIntensity(slots: slots, workouts: credits);
}

// Readiness on the oldest day of the history still needs its own chronic
// window of active load before it.
final dailyActiveLoadProvider = FutureProvider<List<DailyValue>>((ref) async {
  ref.watch(dataRevisionProvider);
  final today = ref.watch(currentDateProvider);
  final days = await ref
      .watch(activityHistoryReaderProvider)
      .dailyActivity(
        from: today.addDays(1 - dayScoreHistoryDays - chronicLoadDays),
        to: today,
      );
  return [for (final day in days) day.activeLoad];
});

final dayScoreHistoryProvider = FutureProvider<DayScoreHistory>((ref) async {
  final stepGoal = ref.watch(stepGoalProvider);
  final (history, stress, intensity, activeLoad) = await (
    ref.watch(trendHistoryProvider.future),
    ref.watch(dailyStressProvider.future),
    ref.watch(dailyIntensityProvider.future),
    ref.watch(dailyActiveLoadProvider.future),
  ).wait;
  return DayScoreHistory.collect(
    today: history.today,
    history: history,
    stress: stress,
    intensity: intensity,
    stepGoal: stepGoal,
    activeLoad: activeLoad,
  );
});

LocalDate _dateOf(WorkoutEntry entry) =>
    LocalDate.fromInstant(entry.start, entry.utcOffset);

bool _inWindow(LocalDate today, LocalDate date, int days) {
  final age = today.daysSince(date);
  return age >= 0 && age <= days;
}

Future<WorkoutCredit> _credit(
  WorkoutHistoryReader reader,
  WorkoutEntry entry,
  int? maxHeartRate,
) async => (
  date: _dateOf(entry),
  start: entry.start,
  end: entry.end,
  minutes: workoutPoints(
    entry,
    heartRate: await _heartRate(reader, entry),
    maxHeartRate: maxHeartRate,
  ),
);

Future<List<BpmSample>> _heartRate(
  WorkoutHistoryReader reader,
  WorkoutEntry entry,
) async => switch (entry) {
  ImportedWorkout() => const [],
  WorkoutListItem(:final id) =>
    (await reader.byId(id))?.workout.heartRate ?? const [],
};

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

final dailyIntensityProvider = FutureProvider<List<DailyValue>>((ref) async {
  ref.watch(dataRevisionProvider);
  final today = ref.watch(currentDateProvider);
  final maxHeartRate = ref.watch(savedWorkoutZonesProvider)?.maxHeartRate;
  final reader = ref.watch(workoutHistoryReaderProvider);
  final (slots, own, imported) = await (
    ref
        .watch(activityHistoryReaderProvider)
        .activitySlots(from: today.addDays(-dayIntensityDays), to: today),
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
      if (_inWindow(today, _dateOf(entry)))
        _credit(reader, entry, maxHeartRate),
  ]);
  return dailyIntensity(slots: slots, workouts: credits);
});

final dayScoreHistoryProvider = FutureProvider<DayScoreHistory>((ref) async {
  final stepGoal = ref.watch(stepGoalProvider);
  final (history, stress, intensity) = await (
    ref.watch(trendHistoryProvider.future),
    ref.watch(dailyStressProvider.future),
    ref.watch(dailyIntensityProvider.future),
  ).wait;
  return DayScoreHistory.collect(
    today: history.today,
    history: history,
    stress: stress,
    intensity: intensity,
    stepGoal: stepGoal,
  );
});

LocalDate _dateOf(WorkoutEntry entry) =>
    LocalDate.fromInstant(entry.start, entry.utcOffset);

bool _inWindow(LocalDate today, LocalDate date) {
  final age = today.daysSince(date);
  return age >= 0 && age <= dayIntensityDays;
}

Future<WorkoutCredit> _credit(
  WorkoutHistoryReader reader,
  WorkoutEntry entry,
  int? maxHeartRate,
) async => (
  date: _dateOf(entry),
  start: entry.start,
  end: entry.end,
  minutes: switch (entry) {
    ImportedWorkout() => metIntensity(entry.type.met, entry.elapsed),
    WorkoutListItem(:final id) => workoutIntensity(
      met: entry.type.met,
      elapsed: entry.elapsed,
      heartRate: (await reader.byId(id))?.workout.heartRate ?? const [],
      maxHeartRate: maxHeartRate,
    ),
  },
);

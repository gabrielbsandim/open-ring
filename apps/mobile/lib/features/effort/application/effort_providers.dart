import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/core/records/data_revision.dart';
import 'package:open_ring/features/activity/application/activity_providers.dart';
import 'package:open_ring/features/effort/domain/effort_day.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/open_score/application/day_score_providers.dart';
import 'package:open_ring/features/open_score/application/day_tag_providers.dart';
import 'package:open_ring/features/open_score/domain/day_tag.dart';
import 'package:open_ring/features/today/application/today_providers.dart';
import 'package:open_ring/features/workout/application/workout_history_providers.dart';
import 'package:open_ring/features/workout/application/workout_source_selection.dart';
import 'package:open_ring/features/workout/domain/workout_history.dart';

/// The workouts of the load window and of today, oldest first.
final effortSessionsProvider = FutureProvider<List<EffortSession>>((ref) async {
  ref.watch(dataRevisionProvider);
  final today = ref.watch(currentDateProvider);
  final zones = ref.watch(savedWorkoutZonesProvider);
  final offset = ref.watch(clockProvider)().timeZoneOffset;
  final first = today.addDays(-effortLoadDays);
  final from = localMidnight(first, offset);
  final to = localMidnight(today.addDays(1), offset);
  final reader = ref.watch(workoutHistoryReaderProvider);
  final (own, imported) = await (
    reader.intersecting(from: from, to: to),
    ref.watch(importedWorkoutReaderProvider).intersecting(from: from, to: to),
  ).wait;
  final selected = selectWorkouts([
    ...own,
    ...imported.workouts,
  ], imported.priority);
  final sessions = await Future.wait([
    for (final entry in selected)
      if (_dated(entry, from: first, to: today)) _session(reader, entry, zones),
  ]);
  return sessions..sort((a, b) => a.start.compareTo(b.start));
});

bool _dated(
  WorkoutEntry entry, {
  required LocalDate from,
  required LocalDate to,
}) {
  final date = LocalDate.fromInstant(entry.start, entry.utcOffset);
  return date.compareTo(from) >= 0 && date.compareTo(to) <= 0;
}

Future<EffortSession> _session(
  WorkoutHistoryReader reader,
  WorkoutEntry entry,
  HeartRateZones? zones,
) async => effortSessionOf(
  entry,
  heartRate: switch (entry) {
    ImportedWorkout() => const [],
    WorkoutListItem(:final id) =>
      (await reader.byId(id))?.workout.heartRate ?? const [],
  },
  zones: zones,
);

/// The daily load that ends yesterday, which the load lines are drawn over.
final effortDailyLoadProvider = FutureProvider<List<double>>((ref) async {
  ref.watch(dataRevisionProvider);
  final today = ref.watch(currentDateProvider);
  final (sessions, slots) = await (
    ref.watch(effortSessionsProvider.future),
    ref
        .watch(activityHistoryReaderProvider)
        .activitySlots(from: today.addDays(-effortLoadDays), to: today),
  ).wait;
  return effortDailyLoad(sessions: sessions, slots: slots, today: today);
});

final effortWeekProvider = FutureProvider<EffortWeek>((ref) async {
  final today = ref.watch(currentDateProvider);
  final (points, sessions) = await (
    ref.watch(dailyIntensityProvider.future),
    ref.watch(effortSessionsProvider.future),
  ).wait;
  return effortWeek(points, effortStrengthDays(sessions), today: today);
});

final effortLastSevenProvider = FutureProvider<double?>((ref) async {
  final today = ref.watch(currentDateProvider);
  final points = await ref.watch(dailyIntensityProvider.future);
  return weeklyIntensityMinutes(points, today: today);
});

// The Sick tag belongs to Open Score, so it is read only while that module
// is on. Still loading counts as not sick.
final effortSickProvider = Provider<bool>((ref) {
  final modules = ref.watch(enabledModulesProvider).value ?? const {};
  if (!modules.contains(ModuleId.openScore)) return false;
  final today = ref.watch(currentDateProvider);
  return ref.watch(dayTagsProvider).value?[today] == DayTag.sick;
});

final effortCoachProvider = FutureProvider<CoachAdvice>((ref) async {
  final sick = ref.watch(effortSickProvider);
  final (readiness, dailyLoad) = await (
    ref.watch(readinessProvider.future),
    ref.watch(effortDailyLoadProvider.future),
  ).wait;
  return coachAdvice(
    readiness: readiness.value,
    sick: sick,
    dailyLoad: dailyLoad,
  );
});

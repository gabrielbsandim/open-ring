import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/core/records/data_revision.dart';
import 'package:open_ring/features/activity/application/activity_providers.dart';
import 'package:open_ring/features/body/application/weigh_in_providers.dart';
import 'package:open_ring/features/body/domain/weigh_in.dart';
import 'package:open_ring/features/heart/application/heart_providers.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/open_score/application/day_score_providers.dart';
import 'package:open_ring/features/open_score/application/day_tag_providers.dart';
import 'package:open_ring/features/open_score/domain/overall_history.dart';
import 'package:open_ring/features/settings/application/user_profile_providers.dart';
import 'package:open_ring/features/sleep/application/sleep_providers.dart';
import 'package:open_ring/features/sleep/application/sleep_source_selection.dart';
import 'package:open_ring/features/workout/application/workout_history_providers.dart';
import 'package:open_ring/features/workout/application/workout_source_selection.dart';
import 'package:open_ring/features/workout/domain/workout_type.dart';

final overallStrengthDatesProvider = FutureProvider<List<LocalDate>>((
  ref,
) async {
  ref.watch(dataRevisionProvider);
  final (own, imported) = await (
    ref
        .watch(workoutHistoryReaderProvider)
        .recent(limit: dayScoreWorkoutScanLimit),
    ref
        .watch(importedWorkoutReaderProvider)
        .recent(limit: dayScoreWorkoutScanLimit),
  ).wait;
  return [
    for (final entry in selectWorkouts([
      ...own,
      ...imported.workouts,
    ], imported.priority))
      if (entry.type == WorkoutType.strength)
        LocalDate.fromInstant(entry.start, entry.utcOffset),
  ];
});

final overallWeighInsProvider = FutureProvider<List<WeighIn>>((ref) async {
  final modules = await ref.watch(enabledModulesProvider.future);
  if (!modules.contains(ModuleId.body)) return const [];
  return await ref.watch(weighInsProvider.future);
});

final overallHistoryProvider = FutureProvider<OverallHistory>((ref) async {
  ref.watch(dataRevisionProvider);
  final now = ref.watch(clockProvider)();
  final today = ref.watch(currentDateProvider);
  final offset = now.timeZoneOffset;
  final from = today.addDays(-overallHistoryDays);
  final profile = await ref.watch(userProfileProvider.future);
  // Two extra days so the oldest night, which starts the evening before its date, is complete.
  final start = localMidnight(from.addDays(-2), offset);
  final (
    sessions,
    heartRate,
    activity,
    intensity,
    strength,
    tags,
    weighIns,
  ) = await (
    readSleepSessions(
      ring: ref.watch(sleepHistoryReaderProvider),
      imported: ref.watch(importedSleepReaderProvider),
      from: start,
      to: now,
    ),
    ref.watch(heartHistoryReaderProvider).heartRate(from: start, to: now),
    ref
        .watch(activityHistoryReaderProvider)
        .dailyActivity(from: from, to: today),
    readDailyIntensity(ref, days: overallHistoryDays),
    ref.watch(overallStrengthDatesProvider.future),
    ref.watch(dayTagsProvider.future),
    ref.watch(overallWeighInsProvider.future),
  ).wait;
  return OverallHistory.collect(
    today: today,
    sessions: sessions,
    heartRate: heartRate,
    utcOffset: offset,
    steps: [
      for (final day in activity) (date: day.date, value: day.steps.toDouble()),
    ],
    intensity: intensity,
    strengthDates: strength,
    tags: tags,
    weighIns: weighIns,
    heightCentimeters: profile?.heightCentimeters,
    birthYear: profile?.birthYear,
  );
});

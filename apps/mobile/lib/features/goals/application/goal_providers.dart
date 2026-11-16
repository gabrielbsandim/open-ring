import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/core/records/data_revision.dart';
import 'package:open_ring/features/activity/application/activity_providers.dart';
import 'package:open_ring/features/effort/application/effort_providers.dart';
import 'package:open_ring/features/effort/domain/effort_day.dart';
import 'package:open_ring/features/goals/application/goal_store_providers.dart';
import 'package:open_ring/features/goals/application/goal_week_view.dart';
import 'package:open_ring/features/goals/application/goals_gate.dart';
import 'package:open_ring/features/goals/domain/goal.dart';
import 'package:open_ring/features/open_score/application/day_score_providers.dart';
import 'package:open_ring/features/sleep/application/sleep_providers.dart';

/// The goal under way, null with the module off. A writer of the goal store
/// bumps the data revision so this reads again.
final activeGoalProvider = FutureProvider<Goal?>((ref) async {
  ref.watch(dataRevisionProvider);
  if (!ref.watch(goalsEnabledProvider)) return null;
  return await ref.watch(goalStoreProvider).active();
});

final goalWeekProvider = FutureProvider<GoalWeekView>((ref) async {
  if (!ref.watch(goalsEnabledProvider)) return const GoalWeekOff();
  final today = ref.watch(currentDateProvider);
  final goal = await ref.watch(activeGoalProvider.future);
  if (goal == null) return const GoalWeekNoGoal();
  if (goal.phase == GoalPhase.paused) {
    return GoalWeekPaused(goal: goal, until: goal.phaseUntil);
  }
  final monday = mondayOf(today);
  final data = await _weekData(ref, {
    for (final lever in goal.levers) lever.kind,
  });
  return GoalWeekRunning(
    goal: goal,
    monday: monday,
    week: goalWeekNumber(start: goal.blockStartedOn, today: today),
    levers: [
      for (final lever in goal.levers)
        leverProgress(lever, data, monday: monday, today: today),
    ],
  );
});

final class GoalReviewView {
  const new({required this.week, required this.review});

  final GoalWeek week;
  final Review review;
}

/// The newest reviewed week of the goal under way, with the review its
/// stored inputs give.
final goalReviewProvider = FutureProvider<GoalReviewView?>((ref) async {
  ref.watch(dataRevisionProvider);
  final goal = await ref.watch(activeGoalProvider.future);
  if (goal == null) return null;
  final week = (await ref.watch(goalStoreProvider).weeks(goal.id)).lastOrNull;
  if (week == null) return null;
  return GoalReviewView(week: week, review: reviewWeek(week.inputs));
});

// A source is read only when a lever counts from it, so a goal never waits
// on, or fails with, data it does not use.
Future<GoalWeekData> _weekData(Ref ref, Set<LeverKind> kinds) async {
  final sleeps =
      kinds.contains(LeverKind.sleepWindow) ||
      kinds.contains(LeverKind.wakeTime);
  return GoalWeekData(
    steps: kinds.contains(LeverKind.steps)
        ? {
            for (final day in (await ref.watch(
              activityDaysProvider.future,
            )).values)
              day.date: day.steps,
          }
        : const {},
    nights: sleeps ? await ref.watch(sleepNightsProvider.future) : const {},
    strengthDays: kinds.contains(LeverKind.strengthDays)
        ? effortStrengthDays(await ref.watch(effortSessionsProvider.future))
        : const {},
    points: kinds.contains(LeverKind.effortPoints)
        ? await ref.watch(dailyIntensityProvider.future)
        : const [],
  );
}

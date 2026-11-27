import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/core/records/data_revision.dart';
import 'package:open_ring/features/activity/application/activity_providers.dart';
import 'package:open_ring/features/body/application/weight_summary.dart';
import 'package:open_ring/features/effort/application/effort_providers.dart';
import 'package:open_ring/features/effort/domain/effort_day.dart';
import 'package:open_ring/features/goals/application/goal_store_providers.dart';
import 'package:open_ring/features/goals/application/goal_week_view.dart';
import 'package:open_ring/features/goals/application/goals_gate.dart';
import 'package:open_ring/features/goals/domain/goal.dart';
import 'package:open_ring/features/goals/domain/goal_store.dart';
import 'package:open_ring/features/goals/domain/review_inputs.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/open_score/application/day_score_providers.dart';
import 'package:open_ring/features/sleep/application/sleep_providers.dart';

/// The goal under way, null with the module off. A writer of the goal store
/// bumps the data revision so this reads again.
final activeGoalProvider = FutureProvider<Goal?>((ref) async {
  ref.watch(dataRevisionProvider);
  if (!ref.watch(goalsEnabledProvider)) return null;
  return await ref.watch(goalStoreProvider).active();
});

/// The first state that holds, in this order: off, no goal, a pause that is
/// not over, hold, a pause that is over, base, recovery, running. Recovery
/// and running carry the maintenance weeks when the goal keeps.
final goalWeekProvider = FutureProvider<GoalWeekView>((ref) async {
  if (!ref.watch(goalsEnabledProvider)) return const GoalWeekOff();
  // A write that changes only a week row leaves the goal equal, so the goal
  // alone would not make this read again.
  ref.watch(dataRevisionProvider);
  final today = ref.watch(currentDateProvider);
  final goal = await ref.watch(activeGoalProvider.future);
  if (goal == null) return const GoalWeekNoGoal();
  final paused = goal.phase == GoalPhase.paused;
  final until = goal.phaseUntil;
  final over = paused && until != null && until.compareTo(today) < 0;
  if (paused && !over) return await _paused(ref, goal, over: false);
  // An over pause of a weight goal never restarts with Body off, so the hold
  // is the reason the person can act on.
  if (goal.kind == GoalKind.loseFat && !await _bodyOn(ref)) {
    return GoalWeekHold(goal: goal);
  }
  if (paused) return await _paused(ref, goal, over: true);
  if (goal.levers.isEmpty) {
    return GoalWeekBase(goal: goal, rate: await _baseRate(ref, goal, today));
  }
  final monday = mondayOf(today);
  final week = goalWeekNumber(start: goal.blockStartedOn, today: today);
  final row = await _rowOfThisWeek(ref, goal, monday);
  final maintenance = _maintenance(goal, today);
  if (row?.action == ReviewAction.recoveryWeek) {
    return GoalWeekRecovery(
      goal: goal,
      monday: monday,
      week: week,
      maintenance: maintenance,
    );
  }
  final data = await _weekData(ref, {
    for (final lever in goal.levers) lever.kind,
  });
  return GoalWeekRunning(
    goal: goal,
    monday: monday,
    week: week,
    levers: [
      for (final lever in goal.levers)
        leverProgress(lever, data, monday: monday, today: today),
    ],
    // A proposal left from the block lapses: maintenance takes no answer.
    review: row != null && row.pending && maintenance == null ? row : null,
    maintenance: maintenance,
  );
});

GoalMaintenance? _maintenance(Goal goal, LocalDate today) {
  final until = goal.phaseUntil;
  if (goal.phase != GoalPhase.maintenance || until == null) return null;
  return GoalMaintenance(until: until, over: until.compareTo(today) < 0);
}

// A review pauses from the Monday of its row, so that row names the rule; a
// pause the person set has no such row.
Future<GoalWeekPaused> _paused(Ref ref, Goal goal, {required bool over}) async {
  final weeks = await ref.watch(goalStoreProvider).weeks(goal.id);
  final row = weeks
      .where(
        (week) =>
            week.monday == goal.phaseSince && week.action == ReviewAction.pause,
      )
      .lastOrNull;
  return GoalWeekPaused(
    goal: goal,
    until: goal.phaseUntil,
    rule: row?.rule,
    over: over,
  );
}

Future<bool> _bodyOn(Ref ref) async =>
    (await ref.watch(enabledModulesProvider.future)).contains(ModuleId.body);

Future<WeightRate?> _baseRate(Ref ref, Goal goal, LocalDate today) async {
  if (goal.kind != GoalKind.loseFat) return null;
  final summary = await ref.watch(weightSummaryProvider.future);
  if (summary == null) return null;
  return weightSnapshot(daily: summary.daily, asOf: today).rate;
}

// Only the newest row counts, and only when it is this Monday's and was
// reviewed in the running block.
Future<GoalWeek?> _rowOfThisWeek(Ref ref, Goal goal, LocalDate monday) async {
  final newest = (await ref.watch(goalStoreProvider).weeks(goal.id)).lastOrNull;
  if (newest == null || newest.monday != monday) return null;
  if (beforeBlock(goal, monday)) return null;
  return newest;
}

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

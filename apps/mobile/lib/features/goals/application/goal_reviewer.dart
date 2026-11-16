import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/core/records/data_revision.dart';
import 'package:open_ring/features/activity/application/activity_providers.dart';
import 'package:open_ring/features/body/application/weight_summary.dart';
import 'package:open_ring/features/effort/application/effort_providers.dart';
import 'package:open_ring/features/effort/domain/effort_day.dart';
import 'package:open_ring/features/goals/application/goal_store_providers.dart';
import 'package:open_ring/features/goals/application/goals_gate.dart';
import 'package:open_ring/features/goals/domain/goal.dart';
import 'package:open_ring/features/goals/domain/review_inputs.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/open_score/application/day_score_providers.dart';
import 'package:open_ring/features/settings/application/user_profile_providers.dart';
import 'package:open_ring/features/sleep/application/sleep_providers.dart';
import 'package:open_ring/features/today/application/today_providers.dart';

const _daysInWeek = 7;
const _firstReviewedWeek = 2;

final goalReviewerProvider = NotifierProvider<GoalReviewer, void>(
  GoalReviewer.new,
);

class GoalReviewer extends Notifier<void> {
  @override
  void build() {}

  /// Writes the review of the week that closed before this Monday, once. Null
  /// when nothing is due or the week is already written.
  Future<Review?> reviewDueWeek() async {
    if (!ref.read(goalsEnabledProvider)) return null;
    final store = ref.read(goalStoreProvider);
    final monday = mondayOf(ref.read(currentDateProvider));
    final goal = await store.active();
    if (goal == null || goal.phase == GoalPhase.paused) return null;
    final week = goalWeekNumber(start: goal.blockStartedOn, today: monday);
    if (week < _firstReviewedWeek) return null;
    final weeks = await store.weeks(goal.id);
    if (weeks.any((week) => week.monday == monday)) return null;
    final sunday = monday.addDays(-1);
    final data = GoalWeekData(
      steps: {
        for (final day in (await ref.read(activityDaysProvider.future)).values)
          day.date: day.steps,
      },
      nights: await ref.read(sleepNightsProvider.future),
      strengthDays: effortStrengthDays(
        await ref.read(effortSessionsProvider.future),
      ),
      points: await ref.read(dailyIntensityProvider.future),
    );
    final modules = await ref.read(enabledModulesProvider.future);
    final bodyOn = modules.contains(ModuleId.body);
    final profile = await ref.read(userProfileProvider.future);
    final weight = await _weight(goal, sunday, bodyOn: bodyOn);
    final trend = await ref.read(readinessTrendProvider.future);
    final inputs = closedWeekInputs(
      goal: goal,
      monday: monday,
      data: data,
      baseline: leverBaseline(data, end: sunday),
      weeks: weeks,
      screenings: await store.screenings(),
      bodyOn: bodyOn,
      rate: weight.rate,
      trendKg: weight.trendKg,
      heightCm: profile?.heightCentimeters,
      readiness: weekReadiness(
        trend.values,
        last: trend.today,
        from: monday.addDays(-_daysInWeek),
      ),
    );
    final review = reviewWeek(inputs);
    final written = await store.addWeek(
      goal.id,
      monday: monday,
      inputs: inputs,
      review: review,
    );
    if (!written) return null;
    _bump();
    return review;
  }

  /// Adds the check-in answers to the week of [monday], once, and returns the
  /// review they give. Null when the week may not be amended.
  Future<Review?> checkIn(
    LocalDate monday, {
    CheckInEnergy? energy,
    bool? foodOrWeight,
  }) async {
    if (!ref.read(goalsEnabledProvider)) return null;
    final store = ref.read(goalStoreProvider);
    final goal = await store.active();
    if (goal == null) return null;
    final review = await store.amendWeek(
      goal.id,
      monday,
      energy: energy,
      foodOrWeight: foodOrWeight,
    );
    if (review == null) return null;
    _bump();
    return review;
  }

  // The weight is read only for a weight goal with Body on, so another goal
  // never waits on, or fails with, weigh-ins it does not use.
  Future<WeightSnapshot> _weight(
    Goal goal,
    LocalDate asOf, {
    required bool bodyOn,
  }) async {
    if (goal.kind != GoalKind.loseFat || !bodyOn) {
      return (rate: null, trendKg: null);
    }
    final summary = await ref.read(weightSummaryProvider.future);
    if (summary == null) return (rate: null, trendKg: null);
    return weightSnapshot(daily: summary.daily, asOf: asOf);
  }

  void _bump() {
    if (!ref.mounted) return;
    ref.read(dataRevisionProvider.notifier).bump();
  }
}

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/core/records/data_revision.dart';
import 'package:open_ring/features/activity/application/activity_providers.dart';
import 'package:open_ring/features/activity/domain/activity_history_reader.dart';
import 'package:open_ring/features/body/application/weight_summary.dart';
import 'package:open_ring/features/demo/application/demo_mode_controller.dart';
import 'package:open_ring/features/effort/application/effort_providers.dart';
import 'package:open_ring/features/effort/domain/effort_day.dart';
import 'package:open_ring/features/goals/application/goal_store_providers.dart';
import 'package:open_ring/features/goals/application/goals_gate.dart';
import 'package:open_ring/features/goals/domain/goal.dart';
import 'package:open_ring/features/goals/domain/review_inputs.dart';
import 'package:open_ring/features/goals/domain/review_step_goal.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/open_score/application/day_score_providers.dart';
import 'package:open_ring/features/settings/application/user_profile_providers.dart';
import 'package:open_ring/features/settings/domain/user_profile.dart';
import 'package:open_ring/features/sleep/application/sleep_providers.dart';
import 'package:open_ring/features/today/application/today_providers.dart';

const _daysInWeek = 7;
const _firstReviewedWeek = 2;

/// What answering a review did. [stepGoalFailed] keeps the answer: only the
/// profile step goal is left to write, through [GoalReviewer.retryStepGoal].
enum ReviewAnswerOutcome { accepted, kept, stepGoalFailed, changed, refused }

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
    if (goal.levers.isEmpty) return null;
    final week = goalWeekNumber(start: goal.blockStartedOn, today: monday);
    if (week < _firstReviewedWeek) return null;
    final weeks = await store.weeks(goal.id);
    if (weeks.any((week) => week.monday == monday)) return null;
    final sunday = monday.addDays(-1);
    final data = await _weekData();
    final modules = await ref.read(enabledModulesProvider.future);
    final bodyOn = modules.contains(ModuleId.body);
    final profile = await ref.read(userProfileProvider.future);
    final weight = await _weight(goal, sunday, bodyOn: bodyOn);
    final trend = await ref.read(readinessTrendProvider.future);
    final closing = _blockCloses(goal, monday, weight.trendKg);
    // The phase goes first: a row written without it would lose this close,
    // and only a later Monday that meets the close again would set it.
    if (closing && !await _startMaintenance(goal, monday)) return null;
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
      maintenance: closing || goal.phase == GoalPhase.maintenance,
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
    final goal = await _answerable();
    if (goal == null) return null;
    final store = ref.read(goalStoreProvider);
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

  /// Answers the week of [monday], once. Check-in answers go first: when they
  /// change the rule the person sees a new review, so nothing is answered.
  /// The answer is written before the profile step goal, since its refusal is
  /// what keeps a second accept from writing the goal twice.
  Future<ReviewAnswerOutcome> answer(
    LocalDate monday,
    WeekAnswer choice, {
    CheckInEnergy? energy,
    bool? foodOrWeight,
  }) async {
    final goal = await _answerable();
    // Maintenance proposes nothing, so a proposal left from the block lapses.
    if (goal == null || goal.phase == GoalPhase.maintenance) {
      return ReviewAnswerOutcome.refused;
    }
    final store = ref.read(goalStoreProvider);
    final week = (await store.weeks(goal.id))
        .where((week) => week.monday == monday)
        .lastOrNull;
    if (week == null) return ReviewAnswerOutcome.refused;
    if (energy != null || foodOrWeight != null) {
      final review = await store.amendWeek(
        goal.id,
        monday,
        energy: energy,
        foodOrWeight: foodOrWeight,
      );
      if (review != null) _bump();
      if (review != null && !_same(review, week)) {
        return ReviewAnswerOutcome.changed;
      }
    }
    final change = week.change;
    if (change == null) return ReviewAnswerOutcome.refused;
    if (!await store.answer(goal.id, monday, choice)) {
      return ReviewAnswerOutcome.refused;
    }
    _bump();
    if (choice == WeekAnswer.declined) return ReviewAnswerOutcome.kept;
    final to = change.to;
    if (change.kind != LeverKind.steps || to == null) {
      return ReviewAnswerOutcome.accepted;
    }
    final int? steps;
    try {
      final profile = await ref.read(userProfileProvider.future);
      steps = stepGoalAfterAccept(
        change,
        profileGoal: profile?.dailyStepGoal ?? defaultStepGoal,
      );
    } on Object catch (error) {
      debugPrint('Goal step goal was not read: $error');
      return ReviewAnswerOutcome.stepGoalFailed;
    }
    if (steps == null) return ReviewAnswerOutcome.accepted;
    if (await retryStepGoal(steps)) return ReviewAnswerOutcome.accepted;
    return ReviewAnswerOutcome.stepGoalFailed;
  }

  /// Raises the profile step goal to [steps] from today when [steps] is above
  /// the goal in force. False, with the failure logged, when it could not be.
  Future<bool> retryStepGoal(int steps) async {
    if (await _answerable() == null) return false;
    try {
      final held = await ref.read(userProfileProvider.future);
      final profile = held ?? const UserProfile();
      // A retry may come after the person set the goal again by hand, and the
      // plan still never lowers it.
      final raised = stepGoalAfterAccept(
        LeverChange(kind: LeverKind.steps, from: null, to: steps),
        profileGoal: profile.dailyStepGoal ?? defaultStepGoal,
      );
      if (raised == null) return true;
      await ref
          .read(userProfileProvider.notifier)
          .save(
            UserProfile(
              birthYear: profile.birthYear,
              sex: profile.sex,
              heightCentimeters: profile.heightCentimeters,
              weightKilograms: profile.weightKilograms,
              maxHeartRate: profile.maxHeartRate,
              dailyStepGoal: raised,
            ),
          );
      return true;
    } on Object catch (error) {
      debugPrint('Goal step goal was not saved: $error');
      return false;
    }
  }

  // Demo history shares the tables, and a weight goal with Body off holds, so
  // neither takes an answer.
  Future<Goal?> _answerable() async {
    if (!ref.read(goalsEnabledProvider) || ref.read(demoModeProvider)) {
      return null;
    }
    final goal = await ref.read(goalStoreProvider).active();
    if (goal == null) return null;
    if (goal.kind != GoalKind.loseFat) return goal;
    final modules = await ref.read(enabledModulesProvider.future);
    return modules.contains(ModuleId.body) ? goal : null;
  }

  bool _same(Review review, GoalWeek week) =>
      review.rule == week.rule && review.action == week.action;

  /// Starts the block a goal waits for: its first, once a starting lever
  /// exists, or the next after a pause that has run out. Losing fat waits for
  /// a ready weight rate, whose trend anchors the block.
  Future<bool> startDueBlock() async {
    if (!ref.read(goalsEnabledProvider)) return false;
    final store = ref.read(goalStoreProvider);
    final today = ref.read(currentDateProvider);
    final goal = await store.active();
    if (goal == null || !_waitsForBlock(goal, today)) return false;
    final weighed = goal.kind == GoalKind.loseFat;
    final anchor = weighed ? await _readyTrend(goal, today) : null;
    if (weighed && anchor == null) return false;
    final based = goal.levers.isEmpty;
    final first = based
        ? startingLever(
            goal.kind,
            leverBaseline(await _weekData(), end: today.addDays(-1)),
          )
        : null;
    if (based && first == null) return false;
    final started = await store.startBlock(
      goal.id,
      on: today,
      anchorKg: anchor,
      levers: first == null ? null : [first],
    );
    if (!started) return false;
    _bump();
    return true;
  }

  bool _waitsForBlock(Goal goal, LocalDate today) => switch (goal.phase) {
    GoalPhase.paused || GoalPhase.maintenance => _over(goal, today),
    GoalPhase.block || GoalPhase.ended => goal.levers.isEmpty,
  };

  bool _over(Goal goal, LocalDate today) {
    final until = goal.phaseUntil;
    return until != null && until.compareTo(today) < 0;
  }

  bool _blockCloses(Goal goal, LocalDate monday, double? trendKg) {
    final anchor = goal.blockAnchorKg;
    if (goal.phase != GoalPhase.block || anchor == null) return false;
    if (goal.kind != GoalKind.loseFat) return false;
    final block = goalBlock(
      startKg: anchor,
      percentPerWeek: goalPacePercent(goal.pace ?? GoalPace.standard),
      start: goal.blockStartedOn,
    );
    return blockCloses(block: block, monday: monday, trendKg: trendKg);
  }

  Future<bool> _startMaintenance(Goal goal, LocalDate monday) async {
    final started = await ref
        .read(goalStoreProvider)
        .setPhase(
          goal.id,
          GoalPhase.maintenance,
          since: monday,
          until: monday.addDays(7 * goalMaintenanceWeeks - 1),
        );
    if (started) _bump();
    return started;
  }

  Future<double?> _readyTrend(Goal goal, LocalDate today) async {
    final modules = await ref.read(enabledModulesProvider.future);
    final weight = await _weight(
      goal,
      today,
      bodyOn: modules.contains(ModuleId.body),
    );
    if (weight.rate is! WeightRateReady) return null;
    return weight.trendKg;
  }

  Future<GoalWeekData> _weekData() async => GoalWeekData(
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

import 'package:metrics/metrics.dart';
import 'package:open_ring/features/body/application/weight_summary.dart';
import 'package:open_ring/features/energy/application/energy_gate.dart';
import 'package:open_ring/features/energy/application/energy_providers.dart';
import 'package:open_ring/features/energy/domain/energy_day.dart';
import 'package:open_ring/features/goals/application/goal_week_view.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/open_score/application/day_score_view.dart';
import 'package:open_ring/features/open_score/domain/day_score_history.dart';
import 'package:open_ring/features/today/application/today_view.dart';
import 'package:open_ring/features/widgets/domain/widget_snapshot.dart';
import 'package:open_ring/features/workout/domain/workout_history.dart';

WidgetSnapshot buildWidgetSnapshot(
  TodayView view, {
  WorkoutEntry? lastWorkout,
  Set<ModuleId> enabledModules = const {},
  bool hideNumbers = false,
  DayScoreHistory? dayScoreHistory,
  WeightSummary? weightSummary,
  EnergyNow? energyNow,
  EffortWeek? effortWeek,
  GoalWeekView? goalWeek,
  DateTime? now,
}) {
  final readiness = view.readiness;
  final heart = view.heart;
  final night = view.lastNight.night;
  final today = readiness.date;
  return WidgetSnapshot(
    date: today,
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
    enabledModules: Set.unmodifiable(enabledModules),
    hideNumbers: hideNumbers,
    dayScore: _dayScore(
      view,
      today: today,
      enabledModules: enabledModules,
      history: dayScoreHistory,
      now: now,
    ),
    weight: _weight(
      enabledModules: enabledModules,
      hideNumbers: hideNumbers,
      summary: weightSummary,
    ),
    energy: _energy(
      enabledModules: enabledModules,
      hideNumbers: hideNumbers,
      energyNow: energyNow,
    ),
    effort: _effort(enabledModules: enabledModules, effortWeek: effortWeek),
    goals: _goals(
      today: today,
      enabledModules: enabledModules,
      goalWeek: goalWeek,
    ),
  );
}

int? _round(double? value) => value?.round();

WidgetDayScore? _dayScore(
  TodayView view, {
  required LocalDate today,
  required Set<ModuleId> enabledModules,
  required DayScoreHistory? history,
  required DateTime? now,
}) {
  if (!enabledModules.contains(ModuleId.openScore) || history == null) {
    return null;
  }
  final todayInputs = history.inputsOn(today);
  final todayReceipt = todayInputs == null
      ? null
      : DayScoreReceipt(todayInputs);
  if (todayReceipt?.scored case final scored?) {
    return WidgetDayScore(
      kind: scored.isFull
          ? WidgetDayScoreKind.full
          : WidgetDayScoreKind.partial,
      score: scored.value,
      band: dayScoreBand(scored.value),
      coverage: todayReceipt!.coverage.round(),
      pillarPoints: _pillars(todayReceipt),
      asOf: view.freshness == SyncFreshness.stale
          ? view.ring.lastSyncAt
          : (now ?? view.ring.lastSyncAt),
    );
  }
  final yesterday = _yesterdayScored(history, today.addDays(-1));
  if (yesterday != null) return yesterday;
  final coverage = todayReceipt?.coverage.round() ?? 0;
  if (history.firstScored == null) {
    return WidgetDayScore(
      kind: WidgetDayScoreKind.firstDays,
      coverage: coverage,
    );
  }
  return WidgetDayScore(
    kind: WidgetDayScoreKind.noScore,
    coverage: coverage,
    gap: todayReceipt?.gap ?? DayScoreGap.night,
  );
}

WidgetDayScore? _yesterdayScored(DayScoreHistory history, LocalDate yesterday) {
  final inputs = history.inputsOn(yesterday);
  if (inputs == null) return null;
  final receipt = DayScoreReceipt(inputs);
  final scored = receipt.scored;
  if (scored == null) return null;
  return WidgetDayScore(
    kind: WidgetDayScoreKind.afterMidnight,
    score: scored.value,
    band: dayScoreBand(scored.value),
    coverage: receipt.coverage.round(),
    pillarPoints: _pillars(receipt),
  );
}

List<double?> _pillars(DayScoreReceipt receipt) => [
  for (final pillar in DayScorePillar.values) _pillarPoints(receipt, pillar),
];

double? _pillarPoints(DayScoreReceipt receipt, DayScorePillar pillar) {
  final factors = factorsOf(pillar);
  if (receipt.available(factors) <= 0) return null;
  return receipt.earned(factors);
}

WidgetWeight? _weight({
  required Set<ModuleId> enabledModules,
  required bool hideNumbers,
  required WeightSummary? summary,
}) {
  if (!enabledModules.contains(ModuleId.body) || summary == null) return null;
  return WidgetWeight(
    trendKilograms: hideNumbers ? null : summary.trend,
    direction: _weightDirection(summary.rate),
  );
}

WidgetWeightDirection _weightDirection(WeightRate rate) => switch (rate) {
  WeightRateBuilding() => WidgetWeightDirection.building,
  WeightRateReady(:final stable, :final perWeek) => _readyDirection(
    stable: stable,
    perWeek: perWeek,
  ),
};

WidgetWeightDirection _readyDirection({
  required bool stable,
  required double perWeek,
}) {
  if (stable) return WidgetWeightDirection.steady;
  if (perWeek < 0) return WidgetWeightDirection.falling;
  return WidgetWeightDirection.rising;
}

WidgetEnergy? _energy({
  required Set<ModuleId> enabledModules,
  required bool hideNumbers,
  required EnergyNow? energyNow,
}) {
  if (!enabledModules.contains(ModuleId.energy) || hideNumbers) return null;
  if (energyNow?.day case EnergyDayEstimate(:final range)
      when range.low >= energyRowFloor) {
    return WidgetEnergy(lowKcal: range.low, highKcal: range.high);
  }
  return null;
}

WidgetEffort? _effort({
  required Set<ModuleId> enabledModules,
  required EffortWeek? effortWeek,
}) {
  if (!enabledModules.contains(ModuleId.effort) || effortWeek == null) {
    return null;
  }
  return WidgetEffort(
    points: effortWeek.points.round(),
    targetPoints: effortWeekPoints,
    strengthDays: effortWeek.strengthDays,
    strengthTarget: effortWeekStrengthDays,
  );
}

WidgetGoals? _goals({
  required LocalDate today,
  required Set<ModuleId> enabledModules,
  required GoalWeekView? goalWeek,
}) {
  if (!enabledModules.contains(ModuleId.goals) || goalWeek == null) {
    return null;
  }
  final fallbackMonday = mondayOf(today);
  return switch (goalWeek) {
    GoalWeekOff() || GoalWeekNoGoal() => null,
    GoalWeekPaused() => WidgetGoals(
      state: WidgetGoalsState.paused,
      monday: fallbackMonday,
      sunday: fallbackMonday.addDays(6),
    ),
    GoalWeekHold() => WidgetGoals(
      state: WidgetGoalsState.hold,
      monday: fallbackMonday,
      sunday: fallbackMonday.addDays(6),
    ),
    GoalWeekBase() => WidgetGoals(
      state: WidgetGoalsState.base,
      monday: fallbackMonday,
      sunday: fallbackMonday.addDays(6),
    ),
    GoalWeekRecovery(
      :final goal,
      :final monday,
      :final week,
      :final maintenance,
    ) =>
      WidgetGoals(
        state: WidgetGoalsState.recovery,
        monday: monday,
        sunday: monday.addDays(6),
        weekNumber: week,
        blockWeeks: goal.kind == GoalKind.loseFat ? goalBlockWeeks : null,
        maintenance: maintenance != null,
      ),
    GoalWeekRunning(
      :final goal,
      :final monday,
      :final week,
      :final levers,
      :final review,
      :final maintenance,
    ) =>
      WidgetGoals(
        state: review != null
            ? WidgetGoalsState.review
            : WidgetGoalsState.running,
        monday: monday,
        sunday: monday.addDays(6),
        weekNumber: week,
        blockWeeks: goal.kind == GoalKind.loseFat ? goalBlockWeeks : null,
        maintenance: maintenance != null,
        levers: [for (final lever in levers) _goalLever(lever)],
      ),
  };
}

WidgetGoalLever _goalLever(LeverProgress progress) => WidgetGoalLever(
  kind: progress.lever.kind,
  target: progress.lever.target,
  achieved: progress.achieved,
  goal: progress.lever.cadence == LeverCadence.daily
      ? goalDailyFitDays
      : progress.lever.target,
  days: progress.days,
);

import 'dart:math' as math;

import 'package:metrics/src/goal_rate.dart';
import 'package:metrics/src/overall_score.dart';
import 'package:metrics/src/readiness.dart';

const goalDailyFitDays = 5;
const goalShrinkBelow = 0.6;
const goalStepFrom = 0.8;
const goalMaxLevers = 3;
const goalBuildWeeks = 4;
const goalStepsStep = 1000;
const goalStepsCeiling = 10000;
const goalStepsRound = 500;
const goalEffortStepPercent = 10;
const goalEffortStepMin = 15;
const goalEffortCeiling = 300;
const goalEffortRaisesBeforeHold = 3;
const goalStrengthFloor = 2;
const goalStrengthCeiling = 4;
const goalSleepStepMinutes = 15;
const goalSleepMinMinutes = 420;
const goalSleepMaxMinutes = 540;
const goalWakeToleranceMinutes = 30;
const goalLowReadinessDays = 4;
const goalFastLossPauseDays = 28;
const goalRecoveryPauseDays = 14;

const _daysInWeek = 7;
const _noonToMidnightMinutes = 720;

enum LeverKind { strengthDays, sleepWindow, steps, effortPoints, wakeTime }

enum LeverUnit {
  daysPerWeek,
  minutesAfterNoon,
  stepsPerDay,
  pointsPerWeek,
  minutesAfterMidnight,
}

enum LeverCadence { daily, weekly }

enum CheckInEnergy { low, normal, good }

enum ReviewAction { end, pause, recoveryWeek, hold, ease, shrink, nextStep }

// The order is the order the rules are read in: the first that holds wins.
enum ReviewRule {
  end,
  pauseFastLoss,
  pauseCheckIn,
  recoveryWeek,
  ease,
  build,
  holdBuilding,
  shrink,
  holdOnTrack,
  stepSlow,
  holdOther;

  int get number => index + 1;

  bool get protection => index <= ReviewRule.recoveryWeek.index;
}

final class Lever {
  const new({required this.kind, required this.target});

  final LeverKind kind;
  final int target;

  LeverUnit get unit => switch (kind) {
    LeverKind.strengthDays => LeverUnit.daysPerWeek,
    LeverKind.sleepWindow => LeverUnit.minutesAfterNoon,
    LeverKind.steps => LeverUnit.stepsPerDay,
    LeverKind.effortPoints => LeverUnit.pointsPerWeek,
    LeverKind.wakeTime => LeverUnit.minutesAfterMidnight,
  };

  LeverCadence get cadence => switch (kind) {
    LeverKind.sleepWindow ||
    LeverKind.steps ||
    LeverKind.wakeTime => LeverCadence.daily,
    LeverKind.strengthDays || LeverKind.effortPoints => LeverCadence.weekly,
  };
}

// For a daily lever achieved is the days of seven that met it; for a weekly
// one it is the strength days done or the points earned.
final class LeverWeek {
  const new({required this.lever, required this.achieved});

  final Lever lever;
  final int achieved;
}

// A null from is a lever added, a null to is a lever removed.
final class LeverChange {
  const new({required this.kind, required this.from, required this.to});

  final LeverKind kind;
  final int? from;
  final int? to;
}

final class LeverBaseline {
  const new({
    required this.stepsMedian14,
    required this.bedMedian,
    required this.wakeMedian,
    required this.effortMean4Weeks,
    required this.strengthDaysUsual,
  });

  final int? stepsMedian14;
  final int? bedMedian;
  final int? wakeMedian;
  final double? effortMean4Weeks;
  final int strengthDaysUsual;
}

final class ReviewInputs {
  const new({
    required this.kind,
    required this.week,
    required this.levers,
    required this.adherencePrevious,
    required this.baseline,
    required this.effortRaisesInRow,
    required this.rate,
    required this.targetPercent,
    required this.capPercent,
    required this.previousPercentLow,
    required this.bmi,
    required this.pregnantOrBreastfeeding,
    required this.screeningPositive,
    required this.bodyOn,
    required this.readiness,
    required this.recoveryPrevious,
    required this.energy,
    required this.energyPrevious,
    required this.foodOrWeight,
    required this.foodOrWeightPrevious,
    this.maintenance = false,
  });

  final GoalKind kind;
  final int week;
  final List<LeverWeek> levers;
  final double? adherencePrevious;
  final LeverBaseline baseline;
  final int effortRaisesInRow;
  final LossRate? rate;
  final double targetPercent;
  final double capPercent;
  final double? previousPercentLow;
  final double? bmi;
  final bool pregnantOrBreastfeeding;
  final bool screeningPositive;
  final bool bodyOn;
  final List<int?> readiness;
  final bool recoveryPrevious;
  final CheckInEnergy? energy;
  final CheckInEnergy? energyPrevious;
  final bool? foodOrWeight;
  final bool? foodOrWeightPrevious;

  /// The week falls in the maintenance weeks after a block: the protections
  /// still apply and nothing else changes.
  final bool maintenance;
}

final class Review {
  const new({
    required this.rule,
    required this.action,
    required this.adherence,
    this.change,
    this.pauseDays,
    this.bodyOff = false,
  });

  final ReviewRule rule;
  final ReviewAction action;
  final double adherence;
  final LeverChange? change;
  final int? pauseDays;
  final bool bodyOff;

  bool get needsConsent => change != null && !rule.protection;
}

bool leverFits(LeverWeek week) => switch (week.lever.cadence) {
  LeverCadence.daily => week.achieved >= goalDailyFitDays,
  LeverCadence.weekly => week.achieved >= week.lever.target,
};

double leverFitRatio(LeverWeek week) => switch (week.lever.cadence) {
  LeverCadence.daily => week.achieved / _daysInWeek,
  LeverCadence.weekly => _weeklyRatio(week),
};

double _weeklyRatio(LeverWeek week) {
  if (week.lever.target <= 0) return 1;
  return math.min(1, week.achieved / week.lever.target);
}

double adherence(List<LeverWeek> levers) {
  if (levers.isEmpty) return 0;
  return levers.where(leverFits).length / levers.length;
}

List<LeverKind> goalLeverOrder(GoalKind kind) => switch (kind) {
  GoalKind.loseFat => const [
    LeverKind.strengthDays,
    LeverKind.sleepWindow,
    LeverKind.steps,
  ],
  GoalKind.getFitter => const [
    LeverKind.effortPoints,
    LeverKind.steps,
    LeverKind.strengthDays,
  ],
  GoalKind.sleepBetter => const [LeverKind.wakeTime, LeverKind.sleepWindow],
};

Lever? leverEntry(LeverKind kind, GoalKind goal, LeverBaseline baseline) {
  final target = switch (kind) {
    LeverKind.strengthDays => _strengthEntry(goal, baseline),
    LeverKind.sleepWindow => _sleepEntry(baseline),
    LeverKind.steps => _stepsEntry(baseline),
    LeverKind.effortPoints => _effortEntry(baseline),
    LeverKind.wakeTime => baseline.wakeMedian,
  };
  if (target == null) return null;
  return Lever(kind: kind, target: target);
}

Lever? startingLever(GoalKind kind, LeverBaseline baseline) {
  for (final lever in goalLeverOrder(kind)) {
    final entry = leverEntry(lever, kind, baseline);
    if (entry != null) return entry;
  }
  return null;
}

// A lever is added while there is room and one left to add; only then is an
// active lever raised.
LeverChange? nextStep({
  required GoalKind kind,
  required List<LeverWeek> levers,
  required LeverBaseline baseline,
  required double? adherencePrevious,
  required int effortRaisesInRow,
}) {
  final added = _added(kind, levers, baseline);
  if (added != null) return added;
  for (final raised in _raiseOrder(kind)) {
    final week = _weekOf(levers, raised);
    final to = _raised(
      week,
      baseline: baseline,
      adherencePrevious: adherencePrevious,
      effortRaisesInRow: effortRaisesInRow,
    );
    if (to != null) {
      return LeverChange(kind: raised, from: week?.lever.target, to: to);
    }
  }
  return null;
}

List<Lever> shrink(List<LeverWeek> levers, GoalKind kind) {
  final order = goalLeverOrder(kind);
  final ranked = [...levers]..sort((a, b) => _byFit(a, b, order));
  final strength = _weekOf(levers, LeverKind.strengthDays);
  final protected = kind == GoalKind.loseFat && strength != null;
  final kept = protected
      ? [strength, ...ranked.where((week) => week != strength).take(1)]
      : ranked.take(goalMaxLevers - 1);
  return [for (final week in kept) week.lever];
}

Review reviewWeek(ReviewInputs inputs) {
  final share = adherence(inputs.levers);
  final weight = inputs.kind == GoalKind.loseFat;
  final measured = weight && inputs.bodyOn;
  final state = measured
      ? pathState(
          inputs.rate,
          targetPercent: inputs.targetPercent,
          capPercent: inputs.capPercent,
        )
      : null;
  final step = nextStep(
    kind: inputs.kind,
    levers: inputs.levers,
    baseline: inputs.baseline,
    adherencePrevious: inputs.adherencePrevious,
    effortRaisesInRow: inputs.effortRaisesInRow,
  );
  final fits = share >= goalStepFrom && step != null;
  final building = !weight || (inputs.bodyOn && inputs.week <= goalBuildWeeks);

  Review of(
    ReviewRule rule,
    ReviewAction action, {
    LeverChange? change,
    int? pauseDays,
    bool bodyOff = false,
  }) => Review(
    rule: rule,
    action: action,
    adherence: share,
    change: change,
    pauseDays: pauseDays,
    bodyOff: bodyOff,
  );

  if (weight && _ends(inputs)) {
    return of(ReviewRule.end, ReviewAction.end);
  }
  if (weight && _fastTwice(inputs)) {
    return of(
      ReviewRule.pauseFastLoss,
      ReviewAction.pause,
      pauseDays: goalFastLossPauseDays,
    );
  }
  if (_checkInTwice(inputs)) {
    return of(ReviewRule.pauseCheckIn, ReviewAction.pause);
  }
  if (_lowReadiness(inputs.readiness)) {
    return of(
      ReviewRule.recoveryWeek,
      inputs.recoveryPrevious ? ReviewAction.pause : ReviewAction.recoveryWeek,
      pauseDays: inputs.recoveryPrevious ? goalRecoveryPauseDays : null,
    );
  }
  if (inputs.maintenance) return of(ReviewRule.holdOther, ReviewAction.hold);
  if (state == PathState.above) {
    return of(ReviewRule.ease, ReviewAction.ease);
  }
  if (building && fits) {
    return of(ReviewRule.build, ReviewAction.nextStep, change: step);
  }
  if (weight && !inputs.bodyOn) {
    return of(ReviewRule.holdBuilding, ReviewAction.hold, bodyOff: true);
  }
  if (weight && inputs.rate == null) {
    return of(ReviewRule.holdBuilding, ReviewAction.hold);
  }
  if (inputs.levers.length >= goalMaxLevers && share < goalShrinkBelow) {
    return of(
      ReviewRule.shrink,
      ReviewAction.shrink,
      change: _removed(inputs.levers, inputs.kind),
    );
  }
  if (state == PathState.onTrack) {
    return of(ReviewRule.holdOnTrack, ReviewAction.hold);
  }
  if (state == PathState.below && fits) {
    return of(ReviewRule.stepSlow, ReviewAction.nextStep, change: step);
  }
  return of(ReviewRule.holdOther, ReviewAction.hold);
}

bool _ends(ReviewInputs inputs) {
  final bmi = inputs.bmi;
  if (inputs.pregnantOrBreastfeeding) return true;
  if (inputs.screeningPositive) return true;
  return bmi != null && bmi < bmiFloor;
}

bool _fastTwice(ReviewInputs inputs) {
  final rate = inputs.rate;
  final previous = inputs.previousPercentLow;
  if (rate == null) return false;
  if (previous == null) return false;
  return overCap(rate, inputs.capPercent) && previous > inputs.capPercent;
}

bool _checkInTwice(ReviewInputs inputs) {
  final food =
      (inputs.foodOrWeight ?? false) && (inputs.foodOrWeightPrevious ?? false);
  final energy =
      inputs.energy == CheckInEnergy.low &&
      inputs.energyPrevious == CheckInEnergy.low;
  return food || energy;
}

bool _lowReadiness(List<int?> readiness) {
  final low = readiness.nonNulls.where((value) => value < readinessFairFrom);
  return low.length >= goalLowReadinessDays;
}

LeverChange? _removed(List<LeverWeek> levers, GoalKind kind) {
  final kept = shrink(levers, kind);
  for (final week in levers) {
    if (!kept.contains(week.lever)) {
      return LeverChange(
        kind: week.lever.kind,
        from: week.lever.target,
        to: null,
      );
    }
  }
  return null;
}

int _byFit(LeverWeek a, LeverWeek b, List<LeverKind> order) {
  final byRatio = leverFitRatio(b).compareTo(leverFitRatio(a));
  if (byRatio != 0) return byRatio;
  return order.indexOf(a.lever.kind).compareTo(order.indexOf(b.lever.kind));
}

LeverWeek? _weekOf(List<LeverWeek> levers, LeverKind kind) {
  for (final week in levers) {
    if (week.lever.kind == kind) return week;
  }
  return null;
}

LeverChange? _added(
  GoalKind kind,
  List<LeverWeek> levers,
  LeverBaseline baseline,
) {
  if (levers.length >= goalMaxLevers) return null;
  for (final candidate in goalLeverOrder(kind)) {
    final entry = _weekOf(levers, candidate) == null
        ? leverEntry(candidate, kind, baseline)
        : null;
    if (entry != null) {
      return LeverChange(kind: candidate, from: null, to: entry.target);
    }
  }
  return null;
}

List<LeverKind> _raiseOrder(GoalKind kind) => switch (kind) {
  GoalKind.loseFat => const [
    LeverKind.steps,
    LeverKind.sleepWindow,
    LeverKind.strengthDays,
  ],
  GoalKind.getFitter => const [
    LeverKind.effortPoints,
    LeverKind.steps,
    LeverKind.strengthDays,
  ],
  GoalKind.sleepBetter => const [LeverKind.sleepWindow],
};

int? _raised(
  LeverWeek? week, {
  required LeverBaseline baseline,
  required double? adherencePrevious,
  required int effortRaisesInRow,
}) {
  if (week == null) return null;
  if (!leverFits(week)) return null;
  final target = week.lever.target;
  return switch (week.lever.kind) {
    LeverKind.steps => _under(
      target,
      math.min(goalStepsCeiling, target + goalStepsStep),
    ),
    LeverKind.strengthDays => _under(
      target,
      math.min(goalStrengthCeiling, target + 1),
    ),
    LeverKind.sleepWindow => _earlierBed(target, baseline.wakeMedian),
    LeverKind.effortPoints => _moreEffort(
      target,
      adherencePrevious,
      effortRaisesInRow,
    ),
    LeverKind.wakeTime => null,
  };
}

int? _under(int target, int raised) => raised > target ? raised : null;

int? _earlierBed(int target, int? wake) {
  if (wake == null) return null;
  final bed = target - goalSleepStepMinutes;
  final inBed = wake + _noonToMidnightMinutes - bed;
  return inBed <= goalSleepMaxMinutes ? bed : null;
}

int? _moreEffort(int target, double? adherencePrevious, int raisesInRow) {
  if (adherencePrevious == null) return null;
  if (adherencePrevious < goalStepFrom) return null;
  if (raisesInRow >= goalEffortRaisesBeforeHold) return null;
  final step = math.max(
    (target * goalEffortStepPercent / 100).round(),
    goalEffortStepMin,
  );
  return _under(target, math.min(goalEffortCeiling, target + step));
}

int? _strengthEntry(GoalKind goal, LeverBaseline baseline) {
  final floor = goal == GoalKind.loseFat ? goalStrengthFloor : 1;
  return (baseline.strengthDaysUsual + 1).clamp(floor, goalStrengthCeiling);
}

int? _sleepEntry(LeverBaseline baseline) {
  final bed = baseline.bedMedian;
  final wake = baseline.wakeMedian;
  if (bed == null) return null;
  if (wake == null) return null;
  return math.min(
    bed - goalSleepStepMinutes,
    wake + _noonToMidnightMinutes - goalSleepMinMinutes,
  );
}

int? _stepsEntry(LeverBaseline baseline) {
  final median = baseline.stepsMedian14;
  if (median == null) return null;
  final rounded = (median / goalStepsRound).round() * goalStepsRound;
  return math.min(goalStepsCeiling, rounded + goalStepsStep);
}

int? _effortEntry(LeverBaseline baseline) {
  final mean = baseline.effortMean4Weeks;
  if (mean == null) return null;
  return mean.round().clamp(goalEffortStepMin, goalEffortCeiling);
}

import 'package:metrics/metrics.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/features/goals/presentation/goal_evidence_sheet.dart';
import 'package:open_ring/features/goals/presentation/goal_formula_screen.dart';
import 'package:open_ring/features/goals/presentation/goal_week_card.dart';

const _minutesPerHour = 60;

/// The evidence sheet of a plan lever, with every constant from the code.
GoalEvidenceCopy goalLeverCopy(MetricFormat format, LeverKind kind) {
  final l10n = format.l10n;
  final days = format.integer(goalDailyFitDays);
  final title = leverName(l10n, kind);
  return switch (kind) {
    LeverKind.steps => (
      title: title,
      what: l10n.goalsSheetStepsWhat,
      rule: l10n.goalsSheetStepsRule(
        days,
        format.integer(goalBaselineDays),
        format.integer(goalStepsStep),
        format.integer(goalStepsCeiling),
      ),
      source: l10n.goalsSheetStepsSource,
      ours: l10n.goalsSheetStepsOurs(
        format.integer(goalStepsStep),
        format.integer(goalStepsCeiling),
        days,
      ),
      limits: l10n.goalsSheetStepsLimits,
    ),
    LeverKind.sleepWindow => (
      title: title,
      what: l10n.goalsSheetSleepWhat,
      rule: l10n.goalsSheetSleepRule(
        days,
        format.integer(goalSleepStepMinutes),
        format.integer(goalSleepMinMinutes ~/ _minutesPerHour),
        format.integer(goalSleepMaxMinutes ~/ _minutesPerHour),
      ),
      source: l10n.goalsSheetSleepSource,
      ours: l10n.goalsSheetSleepOurs(
        format.integer(goalSleepStepMinutes),
        days,
        format.integer(goalSleepMinMinutes ~/ _minutesPerHour),
      ),
      limits: l10n.goalsSheetSleepLimits,
    ),
    LeverKind.strengthDays => (
      title: title,
      what: l10n.goalsSheetStrengthWhat,
      rule: l10n.goalsSheetStrengthRule(
        format.integer(effortStrengthMinMinutes),
        format.integer(goalStrengthCeiling),
      ),
      source: l10n.goalsSheetStrengthSource(format.integer(goalStrengthFloor)),
      ours: l10n.goalsSheetStrengthOurs(format.integer(goalStrengthFloor)),
      limits: l10n.goalsSheetStrengthLimits,
    ),
    LeverKind.effortPoints => (
      title: title,
      what: l10n.goalsSheetPointsWhat(format.integer(vigorousMinuteWeight)),
      rule: l10n.goalsSheetPointsRule(
        format.integer(goalBaselineWeeks),
        format.integer(goalEffortStepPercent),
        format.integer(goalEffortStepMin),
        format.integer(goalEffortCeiling),
        format.integer(goalStepFrom * 100),
        format.integer(goalEffortRaisesBeforeHold),
      ),
      source: l10n.goalsSheetPointsSource,
      ours: l10n.goalsSheetPointsOurs(
        format.integer(goalEffortStepPercent),
        format.integer(goalEffortStepMin),
        format.integer(goalEffortCeiling),
        format.integer(goalEffortRaisesBeforeHold),
      ),
      limits: l10n.goalsSheetPointsLimits,
    ),
    LeverKind.wakeTime => (
      title: title,
      what: l10n.goalsSheetWakeWhat(format.integer(goalWakeToleranceMinutes)),
      rule: l10n.goalsSheetWakeRule(
        format.integer(goalWakeToleranceMinutes),
        days,
      ),
      source: l10n.goalsSheetWakeSource,
      ours: l10n.goalsSheetWakeOurs(
        format.integer(goalWakeToleranceMinutes),
        days,
      ),
      limits: l10n.goalsSheetWakeLimits,
    ),
  };
}

/// The reader's own line on a lever sheet: its target and, while the week
/// runs, the count so far. A null [progress] is a plan that holds.
String goalLeverYours(
  MetricFormat format,
  Lever lever,
  LeverProgress? progress,
) {
  final l10n = format.l10n;
  final target = leverTarget(format, lever);
  if (progress == null) return l10n.goalsSheetLeverYoursHold(target);
  return l10n.goalsSheetLeverYours(
    target,
    format.integer(progress.achieved),
    format.integer(leverNeed(lever)),
  );
}

/// The evidence sheet of the rule a review answered with.
GoalEvidenceCopy goalRuleCopy(MetricFormat format, ReviewRule rule) {
  final l10n = format.l10n;
  final count = format.integer(ReviewRule.values.length);
  return (
    title: l10n.goalsSheetRuleTitle(format.integer(rule.number), count),
    what: l10n.goalsSheetRuleWhat(count),
    rule:
        '${goalRuleCondition(format, rule)}: ${goalRuleAnswer(format, rule)}.',
    source: l10n.goalsSheetRuleSource,
    ours: l10n.goalsSheetRuleOurs,
    limits: l10n.goalsSheetRuleLimits,
  );
}

/// What the rules read in a review. Weight figures stay out while numbers
/// are hidden.
String goalRuleYours(
  MetricFormat format,
  ReviewInputs inputs, {
  required bool hidden,
}) {
  final l10n = format.l10n;
  final rate = inputs.rate;
  final bmi = inputs.bmi;
  final weighed = inputs.kind == GoalKind.loseFat && !hidden;
  final low = inputs.readiness
      .where((value) => value != null && value < readinessFairFrom)
      .length;
  return [
    l10n.goalsSheetRuleWeek(format.integer(inputs.week)),
    if (inputs.levers.isNotEmpty)
      l10n.goalsSheetRuleFit(
        format.integer(inputs.levers.where(leverFits).length),
        format.integer(inputs.levers.length),
      ),
    if (weighed && rate != null)
      l10n.goalsSheetRuleRate(
        goalPercent(format, rate.percent),
        goalPercent(format, rate.percentLow),
        goalPercent(format, rate.percentHigh),
        goalPercent(format, inputs.targetPercent),
        goalPercent(format, inputs.capPercent),
      ),
    if (weighed && bmi != null)
      l10n.goalsSheetRuleBmi(format.decimal(bmi, digits: 1)),
    l10n.goalsSheetRuleReadiness(
      format.integer(low),
      format.integer(readinessFairFrom),
    ),
  ].join(' ');
}

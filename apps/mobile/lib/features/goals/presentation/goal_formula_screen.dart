import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/core/widgets/app_page.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/features/goals/application/goal_providers.dart';
import 'package:open_ring/features/goals/application/goals_gate.dart';
import 'package:open_ring/features/modules/presentation/module_widgets.dart';

abstract final class GoalFormulaKeys {
  static const rate = Key('goal_formula_rate');
  static const target = Key('goal_formula_target');
  static const levers = Key('goal_formula_levers');
  static const review = Key('goal_formula_review');
  static const current = Key('goal_formula_current');
  static const arrival = Key('goal_formula_arrival');
  static const protections = Key('goal_formula_protections');
  static const sources = Key('goal_formula_sources');
  static const ours = Key('goal_formula_ours');
  static const unchecked = Key('goal_formula_unchecked');
  static const cannot = Key('goal_formula_cannot');

  static Key rule(ReviewRule rule) => Key('goal_formula_rule_${rule.name}');
}

const _minutesPerHour = 60;
const Set<ReviewRule> _weightRules = {
  ReviewRule.end,
  ReviewRule.pauseFastLoss,
  ReviewRule.ease,
  ReviewRule.holdBuilding,
  ReviewRule.holdOnTrack,
  ReviewRule.stepSlow,
};

String _plain(MetricFormat format, double value) {
  final digits = [
    0,
    1,
  ].firstWhere((digits) => _whole(value * pow(10, digits)), orElse: () => 2);
  return format.decimal(value, digits: digits);
}

bool _whole(num value) => (value - value.round()).abs() < 1e-9;

String _percent(MetricFormat format, double share) =>
    format.integer(share * 100);

/// The condition of one review rule, with the constants it tests.
String goalRuleCondition(MetricFormat format, ReviewRule rule) {
  final l10n = format.l10n;
  return switch (rule) {
    ReviewRule.end => l10n.goalsFormulaRuleEnd(_plain(format, bmiFloor)),
    ReviewRule.pauseFastLoss => l10n.goalsFormulaRuleFastLoss,
    ReviewRule.pauseCheckIn => l10n.goalsFormulaRuleCheckIn,
    ReviewRule.recoveryWeek => l10n.goalsFormulaRuleRecovery(
      format.integer(readinessFairFrom),
      format.integer(goalLowReadinessDays),
    ),
    ReviewRule.ease => l10n.goalsFormulaRuleEase(_plain(format, goalBandHigh)),
    ReviewRule.build => l10n.goalsFormulaRuleBuild(
      _percent(format, goalStepFrom),
      format.integer(goalBuildWeeks),
    ),
    ReviewRule.holdBuilding => l10n.goalsFormulaRuleHoldBuilding,
    ReviewRule.shrink => l10n.goalsFormulaRuleShrink(
      format.integer(goalMaxLevers),
      _percent(format, goalShrinkBelow),
    ),
    ReviewRule.holdOnTrack => l10n.goalsFormulaRuleOnTrack,
    ReviewRule.stepSlow => l10n.goalsFormulaRuleSlow(
      _percent(format, goalStepFrom),
    ),
    ReviewRule.holdOther => l10n.goalsFormulaRuleOther,
  };
}

/// What the review does when [rule] is the first that holds.
String goalRuleAnswer(MetricFormat format, ReviewRule rule) {
  final l10n = format.l10n;
  return switch (rule) {
    ReviewRule.end => l10n.goalsFormulaAnswerEnd,
    ReviewRule.pauseFastLoss => l10n.goalsFormulaAnswerPauseDays(
      format.integer(goalFastLossPauseDays),
    ),
    ReviewRule.pauseCheckIn => l10n.goalsFormulaAnswerPause,
    ReviewRule.recoveryWeek => l10n.goalsFormulaAnswerRecovery(
      format.integer(goalRecoveryPauseDays),
    ),
    ReviewRule.ease => l10n.goalsFormulaAnswerEase,
    ReviewRule.build || ReviewRule.stepSlow => l10n.goalsFormulaAnswerStep,
    ReviewRule.shrink => l10n.goalsFormulaAnswerShrink,
    ReviewRule.holdBuilding ||
    ReviewRule.holdOnTrack ||
    ReviewRule.holdOther => l10n.goalsFormulaAnswerHold,
  };
}

class GoalFormulaScreen extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final format = MetricFormat.of(context);
    final l10n = format.l10n;
    final current = ref.watch(goalsEnabledProvider)
        ? ref.watch(goalReviewProvider).value?.week.rule
        : null;
    final strengthFloor = format.integer(goalStrengthFloor);
    return AppPage(
      title: l10n.formulaLink,
      children: [
        BodyText(l10n.goalsFormulaIntro),
        const SizedBox(height: 16),
        _Part(
          key: GoalFormulaKeys.rate,
          title: l10n.goalsFormulaRateTitle,
          body: l10n.goalsFormulaRateBody(
            format.integer(weightRateWindowDays),
            format.integer(weightRateMinDays),
            format.integer(weightRateMinSpanDays),
            _plain(format, goalBandLow),
            _plain(format, goalBandHigh),
          ),
        ),
        const SizedBox(height: cardGap),
        _Part(
          key: GoalFormulaKeys.target,
          title: l10n.goalsFormulaTargetTitle,
          body: l10n.goalsFormulaTargetBody(
            _plain(format, goalStandardPercent),
            _plain(format, goalGentlePercent),
            format.integer(goalCapBmiMid),
            _plain(format, lossCapPercent(0)),
            format.integer(goalCapBmiHigh),
            _plain(format, lossCapPercent(goalCapBmiMid)),
            _plain(format, lossCapPercent(goalCapBmiHigh)),
            format.integer(goalBlockWeeks),
            format.integer(goalBlockMaxLossPercent),
            format.integer(goalMaintenanceWeeks),
          ),
          notes: [l10n.goalsFormulaTargetNote],
        ),
        const SizedBox(height: cardGap),
        _Part(
          key: GoalFormulaKeys.levers,
          title: l10n.goalsFormulaLeversTitle,
          body: l10n.goalsFormulaLeversBody(
            format.integer(goalMaxLevers),
            format.integer(goalDailyFitDays),
          ),
          lines: [
            l10n.goalsFormulaLeverSteps(
              format.integer(goalBaselineDays),
              format.integer(goalStepsStep),
              format.integer(goalStepsCeiling),
            ),
            l10n.goalsFormulaLeverEffort(
              format.integer(goalBaselineWeeks),
              format.integer(goalEffortStepPercent),
              format.integer(goalEffortStepMin),
              format.integer(goalEffortCeiling),
            ),
            l10n.goalsFormulaLeverStrength(
              strengthFloor,
              format.integer(goalStrengthCeiling),
            ),
            l10n.goalsFormulaLeverSleep(
              format.integer(goalSleepStepMinutes),
              format.integer(goalSleepMinMinutes ~/ _minutesPerHour),
              format.integer(goalSleepMaxMinutes ~/ _minutesPerHour),
            ),
            l10n.goalsFormulaLeverWake(
              format.integer(goalWakeToleranceMinutes),
            ),
          ],
          notes: [l10n.goalsFormulaLeversFood],
        ),
        const SizedBox(height: cardGap),
        _Review(current: current),
        const SizedBox(height: cardGap),
        _Part(
          key: GoalFormulaKeys.arrival,
          title: l10n.goalsFormulaArrivalTitle,
          body: l10n.goalsFormulaArrivalBody(
            format.integer(goalMaintenanceWeeks),
          ),
          notes: [l10n.goalsFormulaArrivalNote],
        ),
        const SizedBox(height: cardGap),
        ModuleFactsCard(
          key: GoalFormulaKeys.protections,
          title: l10n.goalsFormulaProtectTitle,
          icon: Icons.check_rounded,
          facts: [
            l10n.goalsFormulaProtect1(format.integer(goalSoftModeYes)),
            l10n.goalsFormulaProtect2(format.integer(goalMinAge)),
            l10n.goalsFormulaProtect3(_plain(format, bmiFloor)),
            l10n.goalsFormulaProtect4(
              format.integer(goalFastLossPauseDays ~/ DateTime.daysPerWeek),
            ),
            l10n.goalsFormulaProtect5(
              format.integer(readinessFairFrom),
              format.integer(goalLowReadinessDays),
            ),
          ],
        ),
        const SizedBox(height: cardGap),
        ModuleFactsCard(
          key: GoalFormulaKeys.sources,
          title: l10n.effortFormulaSourcesTitle,
          icon: Icons.check_rounded,
          facts: [
            l10n.goalsFormulaSource1,
            l10n.goalsFormulaSource2(strengthFloor),
            l10n.goalsFormulaSource3,
          ],
        ),
        const SizedBox(height: cardGap),
        ModuleFactsCard(
          key: GoalFormulaKeys.ours,
          title: l10n.overallSheetOurs,
          icon: Icons.edit_outlined,
          facts: [
            l10n.goalsFormulaOurs1,
            l10n.goalsFormulaOurs2,
            l10n.goalsFormulaOurs3,
            l10n.goalsFormulaOurs4,
            l10n.goalsFormulaOurs5,
          ],
        ),
        const SizedBox(height: cardGap),
        ModuleFactsCard(
          key: GoalFormulaKeys.unchecked,
          title: l10n.effortFormulaUncheckedTitle,
          icon: Icons.schedule,
          facts: [
            l10n.goalsFormulaUnchecked1,
            l10n.goalsFormulaUnchecked2,
            l10n.goalsFormulaUnchecked3,
            l10n.goalsFormulaUnchecked4,
            l10n.goalsFormulaUnchecked5,
          ],
        ),
        const SizedBox(height: cardGap),
        ModuleFactsCard(
          key: GoalFormulaKeys.cannot,
          title: l10n.effortFormulaCannotTitle,
          icon: Icons.block,
          facts: [
            l10n.goalsFormulaCannot1,
            l10n.goalsFormulaCannot2,
            l10n.goalsFormulaCannot3,
            l10n.goalsFormulaCannot4,
          ],
        ),
        const SizedBox(height: 16),
        CaptionText(l10n.metricEstimateNote),
      ],
    );
  }
}

class _Part extends StatelessWidget {
  const new({
    required this.title,
    required this.body,
    this.lines = const [],
    this.notes = const [],
    super.key,
  });

  final String title;
  final String body;
  final List<String> lines;
  final List<String> notes;

  @override
  Widget build(BuildContext context) {
    return MetricCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AccentTitle(title: title, accent: AppColors.of(context).textPrimary),
          const SizedBox(height: 8),
          BodyText(body),
          for (final line in lines) ...[
            const SizedBox(height: 6),
            BodyText(line),
          ],
          for (final note in notes) ...[
            const SizedBox(height: 10),
            CaptionText(note),
          ],
        ],
      ),
    );
  }
}

class _Review extends StatelessWidget {
  const new({required this.current});

  final ReviewRule? current;

  @override
  Widget build(BuildContext context) {
    final format = MetricFormat.of(context);
    final l10n = format.l10n;
    return MetricCard(
      key: GoalFormulaKeys.review,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AccentTitle(
            title: l10n.goalsFormulaReviewTitle,
            accent: AppColors.of(context).textPrimary,
          ),
          const SizedBox(height: 8),
          BodyText(
            l10n.goalsFormulaReviewIntro(
              format.integer(ReviewRule.values.length),
            ),
          ),
          if (current case final current?) ...[
            const SizedBox(height: 6),
            BodyText(
              l10n.goalsFormulaReviewCurrent(format.integer(current.number)),
              key: GoalFormulaKeys.current,
            ),
          ],
          const SizedBox(height: 4),
          for (final rule in ReviewRule.values)
            _RuleRow(rule: rule, current: rule == current),
          const SizedBox(height: 10),
          CaptionText(
            l10n.goalsFormulaReviewNote(
              format.integer(ReviewRule.recoveryWeek.number),
            ),
          ),
        ],
      ),
    );
  }
}

class _RuleRow extends StatelessWidget {
  const new({required this.rule, required this.current});

  final ReviewRule rule;
  final bool current;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final format = MetricFormat.of(context);
    final l10n = format.l10n;
    final weight = current ? FontWeight.w700 : FontWeight.w400;
    final color = current ? colors.textPrimary : colors.textSecondary;
    final scope = _weightRules.contains(rule)
        ? l10n.goalsFormulaScopeLoseFat
        : l10n.goalsFormulaScopeAll;
    return MergeSemantics(
      key: GoalFormulaKeys.rule(rule),
      child: Semantics(
        selected: current,
        child: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 28),
                child: Text(
                  format.integer(rule.number),
                  style: theme.bodyMedium?.copyWith(
                    color: colors.textLabel,
                    fontWeight: weight,
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      goalRuleCondition(format, rule),
                      style: theme.bodyMedium?.copyWith(
                        color: color,
                        fontWeight: weight,
                        height: 1.35,
                      ),
                    ),
                    Text(
                      '${goalRuleAnswer(format, rule)} · $scope',
                      style: theme.bodySmall?.copyWith(
                        color: colors.textLabel,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

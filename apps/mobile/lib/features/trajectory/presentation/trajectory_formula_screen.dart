import 'package:flutter/material.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/core/widgets/app_page.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/features/open_score/presentation/day_score_formula_screen.dart';
import 'package:open_ring/features/trajectory/presentation/trajectory_levers_card.dart';

abstract final class TrajectoryFormulaKeys {
  static const scenario = Key('trajectory_formula_scenario');
  static const bend = Key('trajectory_formula_bend');
  static const balance = Key('trajectory_formula_balance');
  static const levers = Key('trajectory_formula_levers');
  static const whatIf = Key('trajectory_formula_what_if');
  static const projections = Key('trajectory_formula_projections');
  static const protections = Key('trajectory_formula_protections');
  static const published = Key('trajectory_formula_published');
  static const ours = Key('trajectory_formula_ours');
  static const unchecked = Key('trajectory_formula_unchecked');
  static const cannot = Key('trajectory_formula_cannot');
}

class TrajectoryFormulaScreen extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final format = MetricFormat.of(context);
    final l10n = format.l10n;
    final short = format.integer(trajectoryFirmDays ~/ 7);
    final long = format.integer(trajectoryBandDays ~/ 7);
    final tau = format.integer(trajectoryAdaptationDays);
    final perKg = format.integer(trajectoryKcalPerKgDay);
    final kcalPerKg = format.integer(foodEnergyKcalPerKg);
    final cost = format.decimal(energyWalkCostPerKgKm, digits: 1);
    final percent = format.decimal(trajectoryFastLossPercent);
    final window = format.integer(weightRateWindowDays);
    final leverDays = format.integer(leverTrendWindowDays);
    final leverMinDays = format.integer(leverTrendMinValidDays);
    final minimums = [
      for (final lever in RingLever.values) leverMinimum(format, lever),
    ];
    return AppPage(
      title: l10n.formulaLink,
      children: [
        BodyText(l10n.trajectoryFormulaIntro),
        const SizedBox(height: 16),
        _MethodCard(
          key: TrajectoryFormulaKeys.scenario,
          title: l10n.trajectoryFormulaScenarioTitle,
          body: l10n.trajectoryFormulaScenarioBody(
            window,
            format.integer(weightRateMinDays),
            format.integer(weightRateMinSpanDays),
          ),
          expression: l10n.trajectoryFormulaScenarioExpression(
            tau,
            short,
            long,
          ),
          note: l10n.trajectoryFormulaScenarioNote(
            long,
            format.decimal(scenarioDays(trajectoryBandDays), digits: 1),
            format.integer(trajectoryBandDays),
            short,
            format.decimal(scenarioDays(trajectoryFirmDays), digits: 1),
          ),
        ),
        const SizedBox(height: cardGap),
        _MethodCard(
          key: TrajectoryFormulaKeys.bend,
          title: l10n.trajectoryFormulaBendTitle,
          body: l10n.trajectoryFormulaBendBody,
          expression: l10n.trajectoryFormulaBendExpression(
            perKg,
            format.decimal(mifflinPerKilogram, digits: 2),
          ),
        ),
        const SizedBox(height: cardGap),
        _MethodCard(
          key: TrajectoryFormulaKeys.balance,
          title: l10n.trajectoryFormulaBalanceTitle(window),
          expression: l10n.trajectoryFormulaBalanceExpression(
            kcalPerKg,
            format.integer(energyRangeStep),
            format.integer(foodEnergyMinWeighIns),
            window,
            format.integer(trajectoryBalanceHoldDays),
            format.integer(foodEnergyGoalHoldDays ~/ 7),
          ),
          note: l10n.trajectoryFormulaBalanceNote,
        ),
        const SizedBox(height: cardGap),
        _MethodCard(
          key: TrajectoryFormulaKeys.levers,
          title: l10n.trajectoryLeversTitle(leverDays),
          expression: l10n.trajectoryFormulaLeversExpression(
            leverMinDays,
            leverDays,
            minimums[0],
            minimums[1],
            minimums[2],
            minimums[3],
          ),
          note: l10n.trajectoryFormulaLeversNote(window),
        ),
        const SizedBox(height: cardGap),
        _MethodCard(
          key: TrajectoryFormulaKeys.whatIf,
          title: l10n.trajectoryWhatIfTitle,
          expression: l10n.trajectoryFormulaWhatIfExpression(
            format.decimal(energyStepLengthFactor, digits: 3),
            cost,
            perKg,
            long,
            format.integer(trajectoryBandDays),
            tau,
            paluchAnchorLines(format),
          ),
          note: l10n.trajectoryFormulaWhatIfNote(
            format.integer(cohortSamePercent),
            format.integer(cohortSlightPercent),
            format.integer(cohortFifthPercent),
          ),
        ),
        const SizedBox(height: cardGap),
        MetricCard(
          key: TrajectoryFormulaKeys.projections,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AccentTitle(
                title: l10n.trajectoryProjectionsTitle,
                accent: AppColors.of(context).textPrimary,
              ),
              const SizedBox(height: 4),
              BodyText(l10n.trajectoryFormulaProjections),
            ],
          ),
        ),
        const SizedBox(height: cardGap),
        DayScoreListCard(
          key: TrajectoryFormulaKeys.protections,
          title: l10n.trajectoryFormulaProtectionsTitle,
          lines: [
            l10n.trajectoryFormulaProtection1(percent),
            l10n.trajectoryFormulaProtection2(
              format.decimal(bmiFloor, digits: 1),
            ),
            l10n.trajectoryFormulaProtection3,
            l10n.trajectoryFormulaProtection4(format.integer(energyAdultAge)),
            l10n.trajectoryFormulaProtection5,
          ],
        ),
        const SizedBox(height: cardGap),
        DayScoreListCard(
          key: TrajectoryFormulaKeys.published,
          title: l10n.effortFormulaSourcesTitle,
          lines: [
            l10n.trajectoryFormulaPublished1(perKg),
            l10n.trajectoryFormulaPublished2,
            l10n.trajectoryFormulaPublished3(
              format.integer(weightTrendAlpha * 100),
            ),
          ],
        ),
        const SizedBox(height: cardGap),
        DayScoreListCard(
          key: TrajectoryFormulaKeys.ours,
          title: l10n.dayScoreFormulaSourceOursTitle,
          lines: [
            l10n.trajectoryFormulaOurs1(short, long),
            l10n.trajectoryFormulaOurs2(percent),
            l10n.trajectoryFormulaOurs3(
              minimums[0],
              minimums[1],
              minimums[2],
              minimums[3],
              leverMinDays,
              leverDays,
            ),
            l10n.trajectoryFormulaOurs4,
            l10n.trajectoryFormulaOurs5(short),
            l10n.trajectoryFormulaOurs6,
          ],
        ),
        const SizedBox(height: cardGap),
        DayScoreListCard(
          key: TrajectoryFormulaKeys.unchecked,
          title: l10n.effortFormulaUncheckedTitle,
          lines: [
            l10n.trajectoryFormulaUnchecked1,
            l10n.trajectoryFormulaUnchecked2(kcalPerKg),
            l10n.trajectoryFormulaUnchecked3,
            l10n.trajectoryFormulaUnchecked4,
            l10n.trajectoryFormulaUnchecked5,
            l10n.trajectoryFormulaUnchecked6,
            l10n.trajectoryFormulaUnchecked7(cost),
          ],
        ),
        const SizedBox(height: cardGap),
        DayScoreListCard(
          key: TrajectoryFormulaKeys.cannot,
          title: l10n.effortFormulaCannotTitle,
          lines: [
            l10n.trajectoryFormulaCannot1,
            l10n.trajectoryFormulaCannot2,
            l10n.trajectoryFormulaCannot3,
            l10n.trajectoryFormulaCannot4,
            l10n.trajectoryFormulaCannot5,
          ],
        ),
        const SizedBox(height: 16),
        CaptionText(l10n.trajectoryFormulaFoot),
      ],
    );
  }
}

/// The Paluch anchors as (steps; hazard) pairs, two to a line.
String paluchAnchorLines(MetricFormat format) {
  final pairs = [
    for (final anchor in paluchAnchors)
      _anchor(format, anchor.steps, anchor.hazard),
  ];
  return [
    for (var i = 0; i < pairs.length; i += 2) pairs.skip(i).take(2).join(' '),
  ].join('\n');
}

String _anchor(MetricFormat format, int steps, double hazard) {
  final count = format.integer(steps);
  final ratio = format.decimal(hazard, digits: 2);
  return '($count; $ratio)';
}

class _MethodCard extends StatelessWidget {
  const new({
    required this.title,
    required this.expression,
    this.body,
    this.note,
    super.key,
  });

  final String title;
  final String? body;
  final String expression;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final body = this.body;
    final note = this.note;
    return MetricCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AccentTitle(title: title, accent: colors.textPrimary),
          if (body != null) ...[const SizedBox(height: 4), BodyText(body)],
          const SizedBox(height: 10),
          DecoratedBox(
            decoration: BoxDecoration(
              color: colors.surfaceInner,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                expression,
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ),
          if (note != null) ...[const SizedBox(height: 10), CaptionText(note)],
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/core/widgets/charts.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/core/widgets/state_views.dart';
import 'package:open_ring/features/sleep/application/sleep_view.dart';
import 'package:open_ring/features/sleep/presentation/sleep_labels.dart';

class SleepScoreBreakdown extends StatelessWidget {
  const new({
    required this.day,
    required this.goal,
    required this.remMeasured,
    super.key,
  });

  static const weightsKey = Key('sleep_score_weights');
  static const formulaLinkKey = Key('sleep_score_formula_link');

  final SleepDayView day;
  final Duration goal;
  final bool remMeasured;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final format = MetricFormat.of(context);
    final l10n = format.l10n;
    final score = day.score;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          children: [
            Semantics(
              header: true,
              child: Text(
                switch (score) {
                  Scored(:final value) => l10n.sleepScoreSourceTitle(value),
                  InsufficientData() => l10n.sleepScoreSourceTitleEmpty,
                },
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            TextButton(
              key: SleepScoreBreakdown.formulaLinkKey,
              style: TextButton.styleFrom(minimumSize: const Size(64, 48)),
              onPressed: () => context.go(AppPaths.sleepFormula),
              child: Text(l10n.sleepSeeFormula),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ...switch (score) {
          Scored(:final contributions) => [
            for (final c in contributions) ...[
              _FactorRow(contribution: c, goal: goal),
              const SizedBox(height: 12),
            ],
          ],
          InsufficientData() => [
            BodyText(l10n.sleepScoreTooShort),
            const SizedBox(height: 12),
          ],
        },
        CaptionText(
          key: SleepScoreBreakdown.weightsKey,
          remMeasured ? l10n.sleepScoreWeights : l10n.sleepRemNotMeasured,
        ),
        const SizedBox(height: 12),
        EstimateNote(lead: l10n.sleepStagesFromRing),
      ],
    );
  }
}

class _FactorRow extends StatelessWidget {
  const new({required this.contribution, required this.goal});

  final Contribution<SleepFactor> contribution;
  final Duration goal;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final format = MetricFormat.of(context);
    final factor = contribution.factor;
    final label = factor.label(format, goal);
    final value = factor.value(format, contribution.value);
    final points = format.l10n.metricPoints(
      format.points(contribution.points),
      format.points(contribution.weight),
    );
    return MergeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MetricRow(label: label, value: value),
          const SizedBox(height: 4),
          ProgressBar(
            value: contribution.subscore,
            color: colors.sleep,
            height: 4,
          ),
          const SizedBox(height: 2),
          CaptionText(points),
        ],
      ),
    );
  }
}

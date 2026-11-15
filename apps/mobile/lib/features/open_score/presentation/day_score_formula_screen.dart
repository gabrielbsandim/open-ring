import 'package:flutter/material.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/core/widgets/app_page.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/core/widgets/state_views.dart';
import 'package:open_ring/features/open_score/application/day_score_view.dart';
import 'package:open_ring/features/open_score/presentation/day_score_card.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

abstract final class DayScoreFormulaKeys {
  static const expression = Key('day_score_formula_expression');
  static const total = Key('day_score_formula_total');
  static const sources = Key('day_score_formula_sources');

  static Key factor(DayScoreFactor factor) =>
      Key('day_score_formula_${factor.name}');

  static Key band(DayScoreBand band) =>
      Key('day_score_formula_band_${band.name}');
}

const _whoSource =
    'Bull FC, et al. World Health Organization 2020 guidelines on physical '
    'activity and sedentary behaviour. Br J Sports Med. 2020.';
const _garberSource =
    'Garber CE, et al. Quantity and quality of exercise for developing and '
    'maintaining fitness in apparently healthy adults. '
    'Med Sci Sports Exerc. 2011.';
const _tudorLockeSource =
    'Tudor-Locke C, et al. How fast is fast enough? Walking cadence as a '
    'practical estimate of intensity in adults. Br J Sports Med. 2018.';

const _maxScore = 100;

class DayScoreFormulaScreen extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final format = MetricFormat.of(context);
    final l10n = format.l10n;
    return AppPage(
      title: l10n.formulaLink,
      children: [
        BodyText(l10n.dayScoreFormulaIntro),
        const SizedBox(height: 16),
        const _OneLine(),
        const SizedBox(height: cardGap),
        const _Factors(),
        const SizedBox(height: cardGap),
        const _Bands(),
        const SizedBox(height: cardGap),
        DayScoreListCard(
          title: l10n.dayScoreFormulaMissingTitle,
          lines: [
            l10n.dayScoreFormulaMissing1,
            l10n.dayScoreFormulaMissing2,
            l10n.dayScoreFormulaMissing3,
            l10n.dayScoreFormulaMissing4,
          ],
        ),
        const SizedBox(height: cardGap),
        DayScoreListCard(
          title: l10n.dayScoreFormulaRulesTitle,
          lines: [
            l10n.dayScoreFormulaRules1,
            l10n.dayScoreFormulaRules2,
            l10n.dayScoreFormulaRules3,
            l10n.dayScoreReceiptNever1,
          ],
        ),
        const SizedBox(height: cardGap),
        DayScoreListCard(
          title: l10n.dayScoreFormulaMinutesTitle,
          lines: [
            l10n.dayScoreFormulaMinutes1,
            l10n.dayScoreFormulaMinutes2,
            l10n.dayScoreFormulaMinutes3,
          ],
        ),
        const SizedBox(height: cardGap),
        DayScoreListCard(
          title: l10n.dayScoreFormulaLowTitle,
          lines: [
            l10n.dayScoreFormulaLow1(
              format.integer(readinessFairFrom),
              format.integer(lowReadinessStepGoalFactor * 100),
            ),
            l10n.dayScoreFormulaLow2,
          ],
        ),
        const SizedBox(height: cardGap),
        DayScoreListCard(
          title: l10n.dayScoreFormulaLevelTitle,
          lines: [
            l10n.dayScoreFormulaLevel1(
              l10n.metricPercent(format.decimal(levelAlpha * 100, digits: 1)),
            ),
            l10n.dayScoreFormulaLevel2,
          ],
        ),
        const SizedBox(height: cardGap),
        const _Sources(),
        const SizedBox(height: 16),
        const EstimateNote(),
      ],
    );
  }
}

class _OneLine extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final l10n = AppLocalizations.of(context);
    return MetricCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AccentTitle(
            title: l10n.dayScoreFormulaLineTitle,
            accent: colors.textPrimary,
          ),
          const SizedBox(height: 10),
          BodyText(l10n.dayScoreFormulaLineBody),
          const SizedBox(height: 10),
          DecoratedBox(
            decoration: BoxDecoration(
              color: colors.surfaceInner,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                key: DayScoreFormulaKeys.expression,
                l10n.dayScoreFormulaExpression,
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Factors extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final format = MetricFormat.of(context);
    final l10n = format.l10n;
    final strong = theme.textTheme.bodyLarge?.copyWith(
      fontWeight: FontWeight.w600,
    );
    return MetricCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AccentTitle(
            title: l10n.dayScoreFormulaFactorsTitle,
            accent: colors.textPrimary,
          ),
          for (final factor in DayScoreFactor.values)
            MergeSemantics(
              key: DayScoreFormulaKeys.factor(factor),
              child: Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _WeightLine(
                      color: dayScorePillarColor(colors, factor.pillar),
                      label: dayScoreFactorName(l10n, factor),
                      weight: format.integer(factor.weight),
                    ),
                    const SizedBox(height: 2),
                    CaptionText(_how(format, factor)),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 12),
          Divider(height: 1, color: colors.surfaceBorder),
          const SizedBox(height: 10),
          MergeSemantics(
            key: DayScoreFormulaKeys.total,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  spacing: 12,
                  children: [
                    Text(l10n.dayScoreFormulaTotal, style: strong),
                    Text(format.integer(dayScoreFullCoverage), style: strong),
                  ],
                ),
                const SizedBox(height: 2),
                CaptionText(
                  [
                    for (final pillar in DayScorePillar.values)
                      _pillarShare(format, pillar),
                  ].join(', '),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _pillarShare(MetricFormat format, DayScorePillar pillar) {
    final weight = factorsOf(pillar)
        .fold<double>(0, (sum, factor) => sum + factor.weight);
    return '${dayScorePillarLabel(format.l10n, pillar)} '
        '${format.integer(weight)}';
  }

  String _how(MetricFormat format, DayScoreFactor factor) {
    final l10n = format.l10n;
    return switch (factor) {
      DayScoreFactor.sleep => l10n.formulaReadinessSleep,
      DayScoreFactor.steps => l10n.dayScoreFormulaHowSteps,
      DayScoreFactor.intensity => l10n.dayScoreFormulaHowIntensity,
      DayScoreFactor.hrv => l10n.formulaReadinessHrv(
        format.signed(hrvZeroZ),
        format.signed(hrvFullZ),
      ),
      DayScoreFactor.restingHeartRate => l10n.formulaReadinessRestingHr(
        format.signed(restingHeartRateZeroZ),
        format.signed(restingHeartRateFullZ),
      ),
      DayScoreFactor.stress => l10n.dayScoreFormulaHowStress,
      DayScoreFactor.spo2 => l10n.dayScoreFormulaHowSpo2,
    };
  }
}

class _WeightLine extends StatelessWidget {
  const new({required this.color, required this.label, required this.weight});

  final Color color;
  final String label;
  final String weight;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyLarge;
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ExcludeSemantics(
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Flexible(child: Text(label, style: style)),
          ],
        ),
        Text(weight, style: style),
      ],
    );
  }
}

class _Bands extends StatelessWidget {
  const new();

  static const Map<DayScoreBand, int> _from = {
    DayScoreBand.great: dayScoreGreatFrom,
    DayScoreBand.good: dayScoreGoodFrom,
    DayScoreBand.mixed: dayScoreMixedFrom,
    DayScoreBand.low: 0,
  };

  static const Map<DayScoreBand, int> _to = {
    DayScoreBand.great: _maxScore,
    DayScoreBand.good: dayScoreGreatFrom - 1,
    DayScoreBand.mixed: dayScoreGoodFrom - 1,
    DayScoreBand.low: dayScoreMixedFrom - 1,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final format = MetricFormat.of(context);
    final l10n = format.l10n;
    return MetricCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AccentTitle(
            title: l10n.dayScoreFormulaBandsTitle,
            accent: colors.textPrimary,
          ),
          const SizedBox(height: 6),
          for (final band in DayScoreBand.values.reversed)
            MergeSemantics(
              key: DayScoreFormulaKeys.band(band),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  spacing: 12,
                  children: [
                    Text(
                      dayScoreBandLabel(l10n, band),
                      style: theme.textTheme.bodyLarge,
                    ),
                    Text(
                      l10n.dayScoreFormulaRange(
                        format.integer(_from[band] ?? 0),
                        format.integer(_to[band] ?? _maxScore),
                      ),
                      style: theme.textTheme.bodyLarge,
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 8),
          CaptionText(l10n.dayScoreFormulaBandsNote),
        ],
      ),
    );
  }
}

class DayScoreListCard extends StatelessWidget {
  const new({required this.title, required this.lines, super.key});

  final String title;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return MetricCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AccentTitle(title: title, accent: colors.textPrimary),
          const SizedBox(height: 4),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ExcludeSemantics(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Icon(
                        Icons.check_rounded,
                        size: 16,
                        color: colors.textLabel,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: BodyText(line)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Sources extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final l10n = AppLocalizations.of(context);
    final sources = [
      (name: _whoSource, note: l10n.dayScoreFormulaSourceWho),
      (name: _garberSource, note: l10n.dayScoreFormulaSourceGarber),
      (name: _tudorLockeSource, note: l10n.dayScoreFormulaSourceTudor),
      (
        name: l10n.dayScoreFormulaSourceOursTitle,
        note: l10n.dayScoreFormulaSourceOurs,
      ),
    ];
    return MetricCard(
      key: DayScoreFormulaKeys.sources,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AccentTitle(
            title: l10n.dayScoreFormulaSourcesTitle,
            accent: colors.textPrimary,
          ),
          for (final source in sources)
            MergeSemantics(
              child: Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      source.name,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    CaptionText(source.note),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

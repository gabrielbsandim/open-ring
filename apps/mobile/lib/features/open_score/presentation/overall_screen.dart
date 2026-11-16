import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/core/widgets/app_page.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/core/widgets/state_views.dart';
import 'package:open_ring/features/body/application/hide_numbers_controller.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/open_score/application/overall_providers.dart';
import 'package:open_ring/features/open_score/domain/overall_history.dart';
import 'package:open_ring/features/open_score/presentation/day_score_card.dart';
import 'package:open_ring/features/open_score/presentation/overall_evidence_sheet.dart';
import 'package:open_ring/features/open_score/presentation/overall_row.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

abstract final class OverallKeys {
  static const forming = Key('overall_forming');
  static const card = Key('overall_card');
  static const score = Key('overall_score');
  static const band = Key('overall_band');
  static const coverage = Key('overall_coverage');
  static const updated = Key('overall_updated');
  static const change = Key('overall_change');
  static const source = Key('overall_source');

  static Key factor(OverallFactor factor) =>
      Key('overall_factor_${factor.name}');

  static Key points(OverallFactor factor) =>
      Key('overall_points_${factor.name}');
}

String overallFactorLabel(AppLocalizations l10n, OverallFactor factor) =>
    switch (factor) {
      OverallFactor.fitness => l10n.overallFactorFitness,
      OverallFactor.restingHeartRate => l10n.overallFactorResting,
      OverallFactor.sleepDuration => l10n.overallFactorSleepDuration,
      OverallFactor.sleepRegularity => l10n.overallFactorSleepRegularity,
      OverallFactor.movement => l10n.overallFactorMovement,
      OverallFactor.body => l10n.overallFactorBody,
    };

Color overallGroupColor(AppColors colors, OverallGroup group) =>
    switch (group) {
      OverallGroup.heart => colors.heart,
      OverallGroup.sleep => colors.sleep,
      OverallGroup.movement => colors.activity,
      OverallGroup.body => colors.stress,
    };

bool _openScoreOn(WidgetRef ref) => ref.watch(
  enabledModulesProvider.select(
    (modules) => modules.value?.contains(ModuleId.openScore) ?? false,
  ),
);

class OverallScreen extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final on = _openScoreOn(ref);
    return AppPage(
      title: l10n.overallTitle,
      subtitle: on ? l10n.overallLead : null,
      children: on ? _content(ref, l10n) : [],
    );
  }

  List<Widget> _content(WidgetRef ref, AppLocalizations l10n) {
    final loaded = ref.watch(overallHistoryProvider);
    if (loaded.hasError) return [BodyText(l10n.metricLoadError)];
    final history = loaded.value;
    if (history == null) return const [SizedBox(height: 96)];
    final scored = history.scored;
    if (scored == null) return [_Forming(history: history)];
    final hidden = ref.watch(numbersHiddenProvider);
    return [
      _Summary(history: history, scored: scored, hidden: hidden),
      const SizedBox(height: cardGap),
      _Source(inputs: history.current.inputs, hidden: hidden),
      const SizedBox(height: cardGap),
      const EstimateNote(),
    ];
  }
}

class _Forming extends StatelessWidget {
  const new({required this.history});

  final OverallHistory history;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final nights = history.nights.clamp(0, overallMinDays);
    return MetricCard(
      key: OverallKeys.forming,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.overallFormingTitle,
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          BodyText(l10n.overallFormingBody(nights, overallMinDays)),
          const SizedBox(height: 12),
          DayScoreMeter(
            fill: nights / overallMinDays,
            color: AppColors.of(context).textPrimary,
          ),
        ],
      ),
    );
  }
}

String? _change(MetricFormat format, OverallHistory history, int score) {
  final previous = history.previous;
  if (previous == null) return null;
  final delta = score - previous;
  if (delta.abs() < overallNoiseBelow) return format.l10n.overallChangeNoise;
  final points = format.l10n.dayScoreReceiptPoints(format.integer(delta.abs()));
  return delta > 0
      ? format.l10n.overallChangeUp(points)
      : format.l10n.overallChangeDown(points);
}

class _Summary extends StatelessWidget {
  const new({
    required this.history,
    required this.scored,
    required this.hidden,
  });

  final OverallHistory history;
  final Scored<OverallFactor> scored;
  final bool hidden;

  @override
  Widget build(BuildContext context) {
    final format = MetricFormat.of(context);
    final l10n = format.l10n;
    final colors = AppColors.of(context);
    final theme = Theme.of(context).textTheme;
    final inputs = history.current.inputs;
    final change = _change(format, history, scored.value);
    return MetricCard(
      key: OverallKeys.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.end,
            spacing: 12,
            runSpacing: 4,
            children: [
              Text(
                format.integer(scored.value),
                key: OverallKeys.score,
                style: theme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  overallBandLabel(l10n, overallBand(scored.value)),
                  key: OverallKeys.band,
                  style: theme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          CaptionText(
            key: OverallKeys.coverage,
            inputs.isFull
                ? l10n.dayScoreCoverageFull
                : l10n.dayScoreCoveragePartial(inputs.coverage.round()),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (final factor in OverallFactor.values)
                Expanded(
                  flex: factor.weight.round(),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1),
                    child: DayScoreMeter(
                      fill: overallSecret(factor, hidden: hidden)
                          ? null
                          : scored.of(factor)?.subscore,
                      color: overallGroupColor(colors, factor.group),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          CaptionText(
            key: OverallKeys.updated,
            '${_capital(l10n.overallUpdated(format.monthDay(history.current.date)))}'
            '. '
            '${l10n.overallNext(format.monthDay(history.nextUpdate))}.',
          ),
          if (change != null) ...[
            const SizedBox(height: 4),
            CaptionText(key: OverallKeys.change, change),
          ],
        ],
      ),
    );
  }
}

String _capital(String text) =>
    text.isEmpty ? text : '${text[0].toUpperCase()}${text.substring(1)}';

class _Source extends StatelessWidget {
  const new({required this.inputs, required this.hidden});

  final OverallInputs inputs;
  final bool hidden;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final earned = {for (final c in inputs.contributions) c.factor: c};
    return MetricCard(
      key: OverallKeys.source,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.overallSourceTitle,
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 7),
          for (final factor in OverallFactor.values)
            _FactorRow(
              factor: factor,
              earned: earned[factor],
              inputs: inputs,
              hidden: hidden,
            ),
        ],
      ),
    );
  }
}

class _FactorRow extends StatelessWidget {
  const new({
    required this.factor,
    required this.earned,
    required this.inputs,
    required this.hidden,
  });

  final OverallFactor factor;
  final Contribution<OverallFactor>? earned;
  final OverallInputs inputs;
  final bool hidden;

  @override
  Widget build(BuildContext context) {
    final format = MetricFormat.of(context);
    final l10n = format.l10n;
    final colors = AppColors.of(context);
    final theme = Theme.of(context).textTheme;
    final earned = this.earned;
    return InkWell(
      key: OverallKeys.factor(factor),
      onTap: () => showOverallEvidence(
        context,
        factor: factor,
        inputs: inputs,
        earned: earned,
        hidden: hidden,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 5, right: 10),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: earned == null
                      ? null
                      : overallGroupColor(colors, factor.group),
                  border: Border.all(
                    color: overallGroupColor(colors, factor.group),
                    width: 1.5,
                  ),
                  shape: BoxShape.circle,
                ),
                child: const SizedBox.square(dimension: 10),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    spacing: 12,
                    children: [
                      Text(
                        overallFactorLabel(l10n, factor),
                        style: theme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (!(earned != null &&
                          overallSecret(factor, hidden: hidden)))
                        Text(
                          earned == null
                              ? l10n.overallOutside
                              : l10n.dayScoreReceiptOf(
                                  format.points(earned.points),
                                  format.integer(earned.weight),
                                ),
                          key: OverallKeys.points(factor),
                          style: theme.bodyMedium?.copyWith(
                            color: colors.textSecondary,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  CaptionText(
                    earned == null
                        ? l10n.overallGone(factor.weight.round())
                        : overallValueText(
                            format,
                            factor,
                            inputs,
                            hidden: hidden,
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

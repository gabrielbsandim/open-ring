import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/open_score/application/day_score_providers.dart';
import 'package:open_ring/features/open_score/application/day_score_view.dart';
import 'package:open_ring/features/open_score/domain/day_score_history.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

abstract final class DayScoreCardKeys {
  static const card = Key('today_day_score');
  static const value = Key('today_day_score_value');
  static const band = Key('today_day_score_band');
  static const coverage = Key('today_day_score_coverage');
  static const bar = Key('today_day_score_bar');
  static const line = Key('today_day_score_line');
  static const none = Key('today_day_score_none');
  static const first = Key('today_day_score_first');
}

String dayScoreBandLabel(AppLocalizations l10n, DayScoreBand band) =>
    switch (band) {
      DayScoreBand.great => l10n.dayScoreBandGreat,
      DayScoreBand.good => l10n.dayScoreBandGood,
      DayScoreBand.mixed => l10n.dayScoreBandMixed,
      DayScoreBand.low => l10n.dayScoreBandLow,
    };

String dayScoreFactorLabel(AppLocalizations l10n, DayScoreFactor factor) =>
    switch (factor) {
      DayScoreFactor.sleep => l10n.dayScoreFactorSleep,
      DayScoreFactor.steps => l10n.dayScoreFactorSteps,
      DayScoreFactor.intensity => l10n.dayScoreFactorIntensity,
      DayScoreFactor.hrv => l10n.dayScoreFactorHrv,
      DayScoreFactor.restingHeartRate => l10n.dayScoreFactorResting,
      DayScoreFactor.stress => l10n.dayScoreFactorStress,
      DayScoreFactor.spo2 => l10n.dayScoreFactorSpo2,
    };

String dayScorePillarLabel(AppLocalizations l10n, DayScorePillar pillar) =>
    switch (pillar) {
      DayScorePillar.sleep => l10n.dayScorePillarSleep,
      DayScorePillar.movement => l10n.dayScorePillarMovement,
      DayScorePillar.recovery => l10n.dayScorePillarRecovery,
      DayScorePillar.stress => l10n.dayScorePillarStress,
      DayScorePillar.oxygen => l10n.dayScorePillarOxygen,
    };

Color dayScorePillarColor(AppColors colors, DayScorePillar pillar) =>
    switch (pillar) {
      DayScorePillar.sleep => colors.sleep,
      DayScorePillar.movement => colors.activity,
      DayScorePillar.recovery => colors.heart,
      DayScorePillar.stress => colors.stress,
      DayScorePillar.oxygen => colors.oxygen,
    };

class DayScoreCardSlot extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final on = ref.watch(
      enabledModulesProvider.select(
        (modules) => modules.value?.contains(ModuleId.openScore) ?? false,
      ),
    );
    if (!on) return const SizedBox.shrink();
    return const Padding(
      padding: EdgeInsets.only(bottom: cardGap),
      child: DayScoreCard(),
    );
  }
}

class DayScoreCard extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final format = MetricFormat.of(context);
    final colors = AppColors.of(context);
    final now = ref.watch(clockProvider)();
    return MetricCard(
      key: DayScoreCardKeys.card,
      onTap: () => context.go(AppPaths.dayScore),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 4,
            children: [
              AccentTitle(
                title: format.l10n.dayScoreTitle,
                accent: colors.textPrimary,
              ),
              CaptionText(
                format.l10n.dayScoreSoFar(
                  format.clock(now, now.timeZoneOffset),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _content(ref.watch(dayScoreHistoryProvider), format),
        ],
      ),
    );
  }

  Widget _content(AsyncValue<DayScoreHistory> history, MetricFormat format) {
    if (history.hasValue) return _body(history.requireValue);
    if (history.hasError) return BodyText(format.l10n.metricLoadError);
    return const SizedBox(height: 96);
  }

  Widget _body(DayScoreHistory history) => switch (history.on(history.today)) {
    final Scored<DayScoreFactor> scored => _Scored(scored: scored),
    final InsufficientData<DayScoreFactor> lacking
        when history.firstScored == null =>
      _FirstDays(lacking: lacking),
    final InsufficientData<DayScoreFactor> lacking => _NoScore(
      lacking: lacking,
    ),
    null => const SizedBox.shrink(),
  };
}

class _Scored extends StatelessWidget {
  const new({required this.scored});

  final Scored<DayScoreFactor> scored;

  @override
  Widget build(BuildContext context) {
    final format = MetricFormat.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DayScoreHeadline(scored: scored),
        const SizedBox(height: 14),
        ExcludeSemantics(
          child: DayScoreBar(
            key: DayScoreCardKeys.bar,
            subscore: (f) => scored.of(f)?.subscore,
          ),
        ),
        const SizedBox(height: 10),
        _Legend(scored: scored),
        const SizedBox(height: 10),
        BodyText(key: DayScoreCardKeys.line, _line(format)),
      ],
    );
  }

  String _line(MetricFormat format) {
    final l10n = format.l10n;
    if (!scored.isFull) {
      return l10n.dayScoreRescaled(
        [for (final factor in scored.missing) dayScoreFactorLabel(l10n, factor)]
            .join(', '),
        scored.coverage.round(),
      );
    }
    final open = scored.open.round();
    if (open < 1) return l10n.dayScoreNothingOpen;
    return l10n.dayScoreOpen(open);
  }
}

class DayScoreHeadline extends StatelessWidget {
  const new({required this.scored, super.key});

  final Scored<DayScoreFactor> scored;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final format = MetricFormat.of(context);
    final l10n = format.l10n;
    final band = dayScoreBandLabel(l10n, dayScoreBand(scored.value));
    final coverage = scored.isFull
        ? l10n.dayScoreCoverageFull
        : l10n.dayScoreCoveragePartial(scored.coverage.round());
    return Semantics(
      container: true,
      label: l10n.dayScoreSemantics(scored.value, band, coverage),
      excludeSemantics: true,
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 16,
        runSpacing: 6,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                key: DayScoreCardKeys.value,
                format.integer(scored.value),
                style: theme.textTheme.displayMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  height: 1,
                ),
              ),
              CaptionText(l10n.readinessOf100),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                key: DayScoreCardKeys.band,
                band,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    scored.isFull ? Icons.circle : Icons.circle_outlined,
                    size: 10,
                    color: colors.textLabel,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: CaptionText(
                      key: DayScoreCardKeys.coverage,
                      coverage,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class DayScoreBar extends StatelessWidget {
  const new({required this.subscore, super.key});

  final double? Function(DayScoreFactor factor) subscore;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Row(
      children: [
        for (final pillar in DayScorePillar.values) ...[
          if (pillar != DayScorePillar.values.first) const SizedBox(width: 6),
          for (final factor in factorsOf(pillar))
            Expanded(
              flex: factor.weight.round(),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1),
                child: DayScoreMeter(
                  fill: subscore(factor),
                  color: dayScorePillarColor(colors, pillar),
                ),
              ),
            ),
        ],
      ],
    );
  }
}

class DayScoreMeter extends StatelessWidget {
  const new({required this.fill, required this.color, super.key});

  final double? fill;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final fill = this.fill;
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        height: 10,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: fill == null ? null : colors.surfaceInner,
            border: fill == null
                ? Border.all(color: colors.strongBorder)
                : null,
            borderRadius: BorderRadius.circular(4),
          ),
          child: FractionallySizedBox(
            alignment: AlignmentDirectional.centerStart,
            widthFactor: fill ?? 0,
            child: ColoredBox(color: color),
          ),
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const new({required this.scored});

  final Scored<DayScoreFactor> scored;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final l10n = AppLocalizations.of(context);
    return Wrap(
      spacing: 14,
      runSpacing: 4,
      children: [
        for (final pillar in DayScorePillar.values)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ExcludeSemantics(
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: dayScorePillarColor(colors, pillar),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Flexible(child: CaptionText(_label(l10n, pillar))),
            ],
          ),
      ],
    );
  }

  String _label(AppLocalizations l10n, DayScorePillar pillar) {
    final factors = factorsOf(pillar);
    final name = dayScorePillarLabel(l10n, pillar);
    final available = scored.available(factors).round();
    if (available == 0) return l10n.dayScorePillarOut(name);
    return l10n.dayScorePillarPoints(
      name,
      scored.earned(factors).round(),
      available,
    );
  }
}

class _NoScore extends StatelessWidget {
  const new({required this.lacking});

  final InsufficientData<DayScoreFactor> lacking;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Column(
      key: DayScoreCardKeys.none,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.dayScoreNoneTitle,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        BodyText(switch (lacking.gap) {
          DayScoreGap.night => l10n.dayScoreNoneSleep,
          DayScoreGap.steps => l10n.dayScoreNoneSteps,
          DayScoreGap.coverage => l10n.dayScoreNoneCoverage(
            lacking.coverage.round(),
          ),
        }),
        const SizedBox(height: 10),
        CaptionText(l10n.dayScoreNoneNote),
      ],
    );
  }
}

class _FirstDays extends StatelessWidget {
  const new({required this.lacking});

  final InsufficientData<DayScoreFactor> lacking;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final baselines =
        lacking.has(DayScoreFactor.hrv) &&
        lacking.has(DayScoreFactor.restingHeartRate) &&
        lacking.has(DayScoreFactor.stress);
    return Column(
      key: DayScoreCardKeys.first,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.dayScoreFirstTitle,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        BodyText(l10n.dayScoreFirstBody(lacking.coverage.round())),
        const SizedBox(height: 10),
        _Step(
          label: l10n.dayScoreFirstSleep,
          ready: lacking.has(DayScoreFactor.sleep),
        ),
        _Step(
          label: l10n.dayScoreFirstSteps,
          ready: lacking.has(DayScoreFactor.steps),
        ),
        _Step(
          label: l10n.dayScoreFirstActivity,
          ready: lacking.has(DayScoreFactor.intensity),
        ),
        _Step(label: l10n.dayScoreFirstBaselines, ready: baselines),
        const SizedBox(height: 10),
        CaptionText(l10n.dayScoreFirstNote),
      ],
    );
  }
}

class _Step extends StatelessWidget {
  const new({required this.label, required this.ready});

  final String label;
  final bool ready;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final l10n = AppLocalizations.of(context);
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            ExcludeSemantics(
              child: Icon(
                ready ? Icons.check_rounded : Icons.schedule_rounded,
                size: 18,
                color: colors.textLabel,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(child: BodyText(label)),
            const SizedBox(width: 10),
            CaptionText(ready ? l10n.dayScoreReady : l10n.dayScoreBuilding),
          ],
        ),
      ),
    );
  }
}

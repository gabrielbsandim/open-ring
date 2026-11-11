import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/core/widgets/app_page.dart';
import 'package:open_ring/core/widgets/charts.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/core/widgets/state_views.dart';
import 'package:open_ring/features/today/application/readiness_trend.dart';
import 'package:open_ring/features/today/application/readiness_view.dart';
import 'package:open_ring/features/today/application/today_providers.dart';
import 'package:open_ring/features/today/presentation/readiness_labels.dart';
import 'package:open_ring/features/today/presentation/readiness_verdict.dart';

const List<ReadinessFactor> _factorOrder = [
  ReadinessFactor.hrv,
  ReadinessFactor.restingHeartRate,
  ReadinessFactor.sleep,
  ReadinessFactor.activityLoad,
];

class ReadinessScreen extends ConsumerWidget {
  const new({super.key});

  static Key factorKey(ReadinessFactor factor) =>
      Key('readiness_factor_${factor.name}');
  static const totalKey = Key('readiness_total');
  static const trendKey = Key('readiness_trend');
  static const trendAverageKey = Key('readiness_trend_average');
  static const trendEmptyKey = Key('readiness_trend_empty');
  static const formulaLinkKey = Key('readiness_formula_link');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final format = MetricFormat.of(context);
    final readiness = ref.watch(readinessProvider);
    final date = readiness.value?.date;
    return AppPage(
      title: format.l10n.readinessTitle,
      subtitle: date == null ? null : format.date(date),
      children: [
        AsyncBody(
          value: readiness,
          builder: (view) => _ReadinessBody(view: view),
        ),
      ],
    );
  }
}

class _ReadinessBody extends StatelessWidget {
  const new({required this.view});

  final ReadinessView view;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final format = MetricFormat.of(context);
    final l10n = format.l10n;
    final value = view.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MetricCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 22),
          child: Column(
            children: [
              ScoreRing(
                value: value,
                diameter: 168,
                color: colors.textPrimary,
                caption: l10n.readinessOf100,
                semanticsLabel: value == null
                    ? l10n.readinessPendingSemantics
                    : l10n.readinessSemantics(value),
              ),
              const SizedBox(height: 12),
              if (value != null) ...[
                Text(
                  readinessVerdict(l10n, value),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
              ],
              Text(
                _summary(format),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.textSecondary,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: cardGap),
        MetricCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: Text(
                  l10n.readinessInputsTitle,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              for (final factor in _factorOrder) ...[
                Divider(height: 28, color: colors.surfaceBorder),
                _FactorSection(
                  key: ReadinessScreen.factorKey(factor),
                  view: view,
                  factor: factor,
                ),
              ],
              Divider(height: 28, color: colors.strongBorder),
              MergeSemantics(
                key: ReadinessScreen.totalKey,
                child: MetricRow(
                  label: l10n.readinessTotal,
                  value: value == null ? l10n.readinessNotScored : '$value',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: cardGap),
        const _TrendSection(),
        const SizedBox(height: cardGap),
        MetricCard(
          key: ReadinessScreen.formulaLinkKey,
          onTap: () => context.go(AppPaths.readinessFormula),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.formulaLink, style: theme.textTheme.titleSmall),
                    CaptionText(l10n.formulaLinkCaption),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right_rounded, color: colors.textLabel),
            ],
          ),
        ),
        const SizedBox(height: 16),
        CaptionText(l10n.readinessWeights),
        const SizedBox(height: 8),
        EstimateNote(lead: l10n.readinessDisclaimer),
      ],
    );
  }

  String _summary(MetricFormat format) {
    final l10n = format.l10n;
    final nights = view.baselineNights;
    final building = view.building;
    if (view.value != null && nights != null) {
      return l10n.readinessScoredSummary(nights);
    }
    if (building != null) {
      return '${l10n.metricBaselineBuilding(building.daysCollected, building.daysNeeded)} '
          '${l10n.readinessNeeds}';
    }
    return l10n.readinessNeeds;
  }
}

class _TrendSection extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) => AsyncBody(
    value: ref.watch(readinessTrendProvider),
    builder: (trend) => _TrendCard(trend: trend),
  );
}

class _TrendCard extends StatelessWidget {
  const new({required this.trend});

  final ReadinessTrend trend;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final format = MetricFormat.of(context);
    final l10n = format.l10n;
    final days = format.integer(trend.values.length);
    final average = trend.average;
    return MetricCard(
      key: ReadinessScreen.trendKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 12,
            runSpacing: 4,
            children: [
              Semantics(
                header: true,
                child: Text(
                  l10n.readinessTrendTitle(days),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (average != null)
                CaptionText(
                  key: ReadinessScreen.trendAverageKey,
                  l10n.readinessTrendAverage(format.integer(average)),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (trend.isEmpty)
            BodyText(
              key: ReadinessScreen.trendEmptyKey,
              l10n.readinessTrendEmpty,
            ),
          if (!trend.isEmpty) ...[
            HourlyBars(
              values: [for (final v in trend.values) v?.toDouble()],
              color: colors.textPrimary,
              height: 96,
              semanticsLabel: l10n.readinessTrendSemantics(
                days,
                format.integer(trend.lowest!),
                format.integer(trend.highest!),
              ),
            ),
            const SizedBox(height: 6),
            TimeAxis(
              labels: [
                _shortDate(format, trend.firstDate),
                _shortDate(
                  format,
                  trend.firstDate.addDays(trend.values.length ~/ 2),
                ),
                l10n.trendsAxisToday,
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _shortDate(MetricFormat format, LocalDate date) =>
      DateFormat.MMMd(format.locale)
          .format(DateTime.utc(date.year, date.month, date.day));
}

class _FactorSection extends StatelessWidget {
  const new({required this.view, required this.factor, super.key});

  final ReadinessView view;
  final ReadinessFactor factor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final format = MetricFormat.of(context);
    final l10n = format.l10n;
    final text = describeFactor(format, view, factor);
    final contribution = view.contribution(factor);
    final value = text.value;
    final baseline = text.baseline;
    return MergeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 12,
            runSpacing: 4,
            children: [
              AccentTitle(
                title: factor.label(format),
                accent: factor.accent(colors),
              ),
              CaptionText(
                _points(format, contribution),
                color: colors.textSecondary,
              ),
            ],
          ),
          if (value != null || baseline != null) const SizedBox(height: 8),
          if (value != null || baseline != null)
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.end,
              spacing: 8,
              runSpacing: 2,
              children: [
                if (value != null)
                  Text(
                    value,
                    style: numberStyle(theme.textTheme.headlineSmall),
                  ),
                if (baseline != null) CaptionText(baseline),
              ],
            ),
          if (contribution != null) ...[
            const SizedBox(height: 8),
            ProgressBar(
              value: contribution.subscore,
              color: factor.accent(colors),
            ),
          ],
          const SizedBox(height: 8),
          BodyText(text.note),
          if (contribution == null && view.value != null) ...[
            const SizedBox(height: 4),
            CaptionText(l10n.readinessWeightShared),
          ],
        ],
      ),
    );
  }

  String _points(MetricFormat format, Contribution<ReadinessFactor>? c) {
    if (c == null) {
      return format.l10n.readinessUpTo(format.points(factor.weight));
    }
    return format.l10n.metricPoints(
      format.points(c.points),
      format.points(c.weight),
    );
  }
}

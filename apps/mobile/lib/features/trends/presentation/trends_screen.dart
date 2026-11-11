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
import 'package:open_ring/features/ring/presentation/sync_status_banner.dart';
import 'package:open_ring/features/trends/application/trends_providers.dart';
import 'package:open_ring/features/trends/domain/trend_history.dart';
import 'package:open_ring/features/trends/domain/trend_metric.dart';
import 'package:open_ring/features/trends/domain/trend_series.dart';
import 'package:open_ring/features/trends/presentation/trend_chart.dart';
import 'package:open_ring/features/trends/presentation/trend_labels.dart';

abstract final class TrendsKeys {
  static const chart = Key('trends_chart');
  static const summary = Key('trends_summary');
  static const metricEmpty = Key('trends_metric_empty');
  static const emptyAction = Key('trends_empty_action');

  static Key metric(TrendMetric metric) => Key('trends_metric_${metric.name}');

  static Key range(TrendRange range) => Key('trends_range_${range.name}');
}

class TrendsScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<TrendsScreen> createState() => _TrendsScreenState();
}

class _TrendsScreenState extends ConsumerState<TrendsScreen> {
  TrendMetric _metric = TrendMetric.restingHeartRate;
  TrendRange _range = TrendRange.month;

  @override
  Widget build(BuildContext context) {
    final l10n = MetricFormat.of(context).l10n;
    return AppPage(
      title: l10n.trendsTitle,
      onRefresh: () => refreshRing(ref),
      children: [
        const SyncStatusBanner(),
        AsyncBody(
          value: ref.watch(trendHistoryProvider),
          builder: (history) => _TrendsBody(
            history: history,
            metric: _metric,
            range: _range,
            onMetric: (metric) => setState(() => _metric = metric),
            onRange: (range) => setState(() => _range = range),
          ),
        ),
      ],
    );
  }
}

class _TrendsBody extends StatelessWidget {
  const new({
    required this.history,
    required this.metric,
    required this.range,
    required this.onMetric,
    required this.onRange,
  });

  final TrendHistory history;
  final TrendMetric metric;
  final TrendRange range;
  final ValueChanged<TrendMetric> onMetric;
  final ValueChanged<TrendRange> onRange;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final l10n = MetricFormat.of(context).l10n;
    if (history.isEmpty) {
      return EmptyStateCard(
        icon: Icons.insights_rounded,
        accent: colors.heart,
        message: l10n.trendsEmpty,
        actionLabel: l10n.metricOpenRing,
        actionKey: TrendsKeys.emptyAction,
        onAction: () => context.go(AppTab.ring.path),
      );
    }
    final series = history.series(metric, range);
    final band = history.bands[metric];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _MetricPicker(selected: metric, onSelected: onMetric),
        const SizedBox(height: cardGap),
        _RangePicker(selected: range, onSelected: onRange),
        const SizedBox(height: cardGap),
        _ChartCard(metric: metric, range: range, series: series, band: band),
        if (series.hasStats) ...[
          const SizedBox(height: cardGap),
          _SummaryCard(metric: metric, series: series, band: band),
        ],
        const SizedBox(height: 16),
        const EstimateNote(),
      ],
    );
  }
}

class _MetricPicker extends StatelessWidget {
  const new({required this.selected, required this.onSelected});

  final TrendMetric selected;
  final ValueChanged<TrendMetric> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final l10n = MetricFormat.of(context).l10n;
    return Semantics(
      container: true,
      label: l10n.trendsMetricGroup,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final metric in TrendMetric.values)
            _MetricChip(
              key: TrendsKeys.metric(metric),
              label: metric.label(l10n),
              accent: metric.accent(colors),
              selected: metric == selected,
              onTap: () => onSelected(metric),
            ),
        ],
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const new({
    required this.label,
    required this.accent,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String label;
  final Color accent;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? colors.surfaceInner : colors.surface,
        clipBehavior: Clip.antiAlias,
        shape: StadiumBorder(
          side: BorderSide(color: selected ? accent : colors.surfaceBorder),
        ),
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      label,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: selected
                            ? colors.textPrimary
                            : colors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RangePicker extends StatelessWidget {
  const new({required this.selected, required this.onSelected});

  final TrendRange selected;
  final ValueChanged<TrendRange> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final l10n = MetricFormat.of(context).l10n;
    return Semantics(
      container: true,
      label: l10n.trendsRangeGroup,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surface,
          border: Border.all(color: colors.surfaceBorder),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, range) in TrendRange.values.indexed) ...[
                  if (i > 0) const SizedBox(width: 4),
                  Expanded(
                    child: _Segment(
                      key: TrendsKeys.range(range),
                      label: range.label(l10n),
                      selected: range == selected,
                      onTap: () => onSelected(range),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const new({
    required this.label,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? colors.textPrimary : colors.surface,
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: Center(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: selected ? colors.background : colors.textSecondary,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ChartCard extends StatelessWidget {
  const new({
    required this.metric,
    required this.range,
    required this.series,
    required this.band,
  });

  final TrendMetric metric;
  final TrendRange range;
  final TrendSeries series;
  final TrendBand? band;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final format = MetricFormat.of(context);
    final l10n = format.l10n;
    final accent = metric.accent(colors);
    final title = l10n.trendsChartTitle(metric.label(l10n), range.label(l10n));
    final mean = series.mean;
    final min = series.min;
    final max = series.max;
    if (mean == null || min == null || max == null) {
      return MetricCard(
        key: TrendsKeys.chart,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CaptionText(title),
            const SizedBox(height: 8),
            BodyText(key: TrendsKeys.metricEmpty, metric.emptyMessage(l10n)),
          ],
        ),
      );
    }
    final shownBand = band;
    return MetricCard(
      key: TrendsKeys.chart,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CaptionText(title),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.end,
            spacing: 16,
            runSpacing: 8,
            children: [
              MergeSemantics(
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.end,
                  spacing: 6,
                  children: [
                    Text(
                      metric.number(format, mean),
                      style: numberStyle(
                        theme.textTheme.displaySmall,
                        color: accent,
                      ),
                    ),
                    CaptionText(metric.averageLabel(l10n)),
                  ],
                ),
              ),
              Wrap(
                spacing: 16,
                children: [
                  _Extreme(
                    label: l10n.heartMin,
                    value: metric.number(format, min),
                  ),
                  _Extreme(
                    label: l10n.heartMax,
                    value: metric.number(format, max),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          TrendChart(
            series: series,
            color: accent,
            band: shownBand,
            semanticsLabel: l10n.trendsChartSemantics(
              metric.label(l10n),
              range.label(l10n),
              metric.withUnit(format, mean),
              metric.withUnit(format, min),
              metric.withUnit(format, max),
            ),
          ),
          const SizedBox(height: 6),
          TimeAxis(
            labels: [
              _shortDate(format, series.firstDate),
              _shortDate(format, series.firstDate.addDays(series.days ~/ 2)),
              l10n.trendsAxisToday,
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 14,
            runSpacing: 6,
            children: [
              _LegendItem(
                mark: LegendMark.average,
                color: accent,
                label: l10n.trendsLegendAverage,
              ),
              _LegendItem(
                mark: LegendMark.extremes,
                color: accent,
                label: l10n.trendsLegendMinMax,
              ),
              if (shownBand != null)
                _LegendItem(
                  mark: LegendMark.band,
                  color: accent,
                  label: l10n.trendsLegendBand(
                    metric.number(format, shownBand.low),
                    metric.number(format, shownBand.high),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  static String _shortDate(MetricFormat format, LocalDate date) =>
      DateFormat.MMMd(format.locale)
          .format(DateTime.utc(date.year, date.month, date.day));
}

class _Extreme extends StatelessWidget {
  const new({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          CaptionText(label),
          Text(
            value,
            style: numberStyle(Theme.of(context).textTheme.titleMedium),
          ),
        ],
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  const new({required this.mark, required this.color, required this.label});

  final LegendMark mark;
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        LegendSwatch(mark: mark, color: color),
        const SizedBox(width: 6),
        Flexible(child: CaptionText(label)),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const new({required this.metric, required this.series, required this.band});

  final TrendMetric metric;
  final TrendSeries series;
  final TrendBand? band;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final format = MetricFormat.of(context);
    final l10n = format.l10n;
    return MetricCard(
      key: TrendsKeys.summary,
      child: Semantics(
        liveRegion: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(
                l10n.trendsRangeTitle(series.days),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 8),
            for (final line in _lines(format)) ...[
              BodyText(line),
              const SizedBox(height: 6),
            ],
            CaptionText(metric.source(l10n)),
          ],
        ),
      ),
    );
  }

  List<String> _lines(MetricFormat format) {
    final l10n = format.l10n;
    final latest = series.latest;
    final shownBand = band;
    return [
      l10n.trendsSummary(
        metric.withUnit(format, series.mean!),
        metric.number(format, series.min!),
        metric.number(format, series.max!),
      ),
      l10n.trendsMeasuredDays(series.measuredDays, series.days),
      if (shownBand != null)
        l10n.trendsInsideBand(
          series.inside(shownBand),
          series.measuredDays,
          metric.number(format, shownBand.low),
          metric.number(format, shownBand.high),
        ),
      if (latest != null && metric.isNightly)
        l10n.trendsLastNight(metric.withUnit(format, latest)),
      if (latest != null && !metric.isNightly)
        l10n.trendsTodaySoFar(metric.withUnit(format, latest)),
      _trend(format),
    ];
  }

  String _trend(MetricFormat format) {
    final l10n = format.l10n;
    final change = series.change;
    if (change == null) return l10n.trendsTrendNotEnough;
    final amount = metric.roundedDelta(change);
    if (amount == 0) return l10n.trendsTrendStable;
    final delta = metric.delta(format, amount);
    if (change > 0) return l10n.trendsTrendUp(delta);
    return l10n.trendsTrendDown(delta);
  }
}

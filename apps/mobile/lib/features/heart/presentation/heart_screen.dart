import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/core/widgets/app_page.dart';
import 'package:open_ring/core/widgets/charts.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/core/widgets/state_views.dart';
import 'package:open_ring/features/heart/application/heart_providers.dart';
import 'package:open_ring/features/heart/application/heart_view.dart';
import 'package:open_ring/features/heart/presentation/heart_insights.dart';
import 'package:open_ring/features/heart/presentation/heart_labels.dart';
import 'package:open_ring/features/ring/presentation/sync_status_banner.dart';

class HeartScreen extends ConsumerStatefulWidget {
  const new({super.key});

  static Key metricKey(HeartMetric metric) =>
      Key('heart_metric_${metric.name}');
  static const chartKey = Key('heart_chart');
  static const insightKey = Key('heart_insight');
  static const emptyActionKey = Key('heart_empty_action');
  static const measureKey = Key('heart_measure');
  static const trendsKey = Key('heart_trends');

  @override
  ConsumerState<HeartScreen> createState() => _HeartScreenState();
}

class _HeartScreenState extends ConsumerState<HeartScreen> {
  HeartMetric _metric = HeartMetric.heartRate;

  @override
  Widget build(BuildContext context) {
    final format = MetricFormat.of(context);
    final day = ref.watch(heartDayProvider);
    final until = day.value;
    return AppPage(
      title: format.l10n.tabHeart,
      subtitle: until == null
          ? null
          : format.l10n.heartTodayUntil(
              format.clock(until.until, until.utcOffset),
            ),
      onRefresh: () => refreshRing(ref),
      children: [
        const SyncStatusBanner(),
        AsyncBody(
          value: day,
          builder: (view) => _HeartBody(
            view: view,
            metric: _metric,
            onMetric: (metric) => setState(() => _metric = metric),
          ),
        ),
        const SizedBox(height: cardGap),
        AdaptiveColumns(
          first: SecondaryButton(
            key: HeartScreen.measureKey,
            label: format.l10n.measureTitle,
            onPressed: () => context.go(AppPaths.measure),
          ),
          second: SecondaryButton(
            key: HeartScreen.trendsKey,
            label: format.l10n.trendsTitle,
            onPressed: () => context.go(AppPaths.trends),
          ),
        ),
      ],
    );
  }
}

class _HeartBody extends StatelessWidget {
  const new({required this.view, required this.metric, required this.onMetric});

  final HeartDayView view;
  final HeartMetric metric;
  final ValueChanged<HeartMetric> onMetric;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final l10n = MetricFormat.of(context).l10n;
    if (view.isEmpty) {
      return EmptyStateCard(
        icon: Icons.favorite_rounded,
        accent: colors.heart,
        message: l10n.heartEmpty,
        actionLabel: l10n.metricOpenRing,
        actionKey: HeartScreen.emptyActionKey,
        onAction: () => context.go(AppTab.ring.path),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _MetricPicker(selected: metric, onSelected: onMetric),
        const SizedBox(height: cardGap),
        _DayChartCard(view: view, metric: metric),
        const SizedBox(height: cardGap),
        MetricCard(
          key: HeartScreen.insightKey,
          child: HeartInsight(view: view, metric: metric),
        ),
        const SizedBox(height: 16),
        const EstimateNote(),
      ],
    );
  }
}

class _MetricPicker extends StatelessWidget {
  const new({required this.selected, required this.onSelected});

  final HeartMetric selected;
  final ValueChanged<HeartMetric> onSelected;

  @override
  Widget build(BuildContext context) {
    final format = MetricFormat.of(context);
    final colors = AppColors.of(context);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final metric in HeartMetric.values)
          ChoiceChip(
            key: HeartScreen.metricKey(metric),
            label: Text(metric.shortLabel(format.l10n)),
            selected: metric == selected,
            showCheckmark: false,
            materialTapTargetSize: MaterialTapTargetSize.padded,
            selectedColor: colors.track,
            backgroundColor: colors.surface,
            side: BorderSide(color: colors.surfaceBorder),
            labelStyle: TextStyle(
              color: metric == selected ? colors.textPrimary : colors.textLabel,
            ),
            onSelected: (_) => onSelected(metric),
          ),
      ],
    );
  }
}

class _DayChartCard extends StatelessWidget {
  const new({required this.view, required this.metric});

  final HeartDayView view;
  final HeartMetric metric;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final format = MetricFormat.of(context);
    final l10n = format.l10n;
    final series = metric.series(view);
    final accent = metric.accent(colors);
    final mean = series.mean;
    final min = series.min;
    final max = series.max;
    return MetricCard(
      key: HeartScreen.chartKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CaptionText(metric.title(l10n)),
          if (mean == null || min == null || max == null) ...[
            const SizedBox(height: 8),
            BodyText(l10n.heartNoReadingsToday),
          ],
          if (mean != null && min != null && max != null) ...[
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
                        format.integer(mean),
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
                    _Extreme(label: l10n.heartMin, value: format.integer(min)),
                    _Extreme(label: l10n.heartMax, value: format.integer(max)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 14),
            HourlyBars(
              values: series.hours,
              color: accent,
              semanticsLabel: l10n.heartChartSemantics(
                metric.title(l10n),
                format.integer(mean),
                format.integer(min),
                format.integer(max),
              ),
            ),
            const SizedBox(height: 6),
            TimeAxis(
              labels: [
                for (final hour in const [0, 6, 12, 18, 23])
                  format.clock(
                    view.dayStart.add(Duration(hours: hour)),
                    view.utcOffset,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
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

extension on HeartMetric {
  HourlySeries series(HeartDayView view) => switch (this) {
    HeartMetric.heartRate => view.heartRate,
    HeartMetric.hrv => view.hrv,
    HeartMetric.spo2 => view.spo2,
    HeartMetric.stress => view.stress,
  };
}

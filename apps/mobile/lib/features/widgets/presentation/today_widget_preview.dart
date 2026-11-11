import 'package:flutter/material.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/core/widgets/text_scale.dart';
import 'package:open_ring/features/widgets/domain/today_widget_config.dart';
import 'package:open_ring/features/widgets/domain/widget_snapshot.dart';
import 'package:open_ring/features/widgets/presentation/widget_labels.dart';

class TodayWidgetPreview extends StatelessWidget {
  const new({
    required this.config,
    required this.snapshot,
    required this.brightness,
    required this.now,
    super.key,
  });

  static const previewKey = Key('today_widget_preview');

  final TodayWidgetConfig config;
  final WidgetSnapshot? snapshot;
  final Brightness brightness;
  final DateTime now;

  AppColors get _colors =>
      brightness == Brightness.dark ? AppColors.dark : AppColors.light;

  @override
  Widget build(BuildContext context) {
    final format = MetricFormat.of(context);
    final colors = _colors;
    return Semantics(
      key: previewKey,
      container: true,
      label: _semantics(format),
      child: ExcludeSemantics(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.background,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.surface,
                border: Border.all(color: colors.surfaceBorder),
                borderRadius: BorderRadius.circular(28),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _header(context, format),
                    const SizedBox(height: 10),
                    _body(context, format),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _semantics(MetricFormat format) {
    final l10n = format.l10n;
    if (config.isEmpty) return l10n.widgetPreviewEmptySemantics;
    final parts = [
      for (final metric in config.metrics)
        '${metric.label(l10n)} ${metric.describe(format, snapshot).value}',
    ];
    return l10n.widgetPreviewSemantics(parts.join(', '));
  }

  Widget _header(BuildContext context, MetricFormat format) {
    final textTheme = Theme.of(context).textTheme;
    final colors = _colors;
    final status = widgetSyncStatus(format, snapshot, now);
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.end,
      spacing: 12,
      runSpacing: 4,
      children: [
        Text.rich(
          TextSpan(
            text: format.l10n.widgetTodayName,
            children: [
              TextSpan(
                text: ' · ${format.date(snapshot?.date ?? _today)}',
                style: textTheme.labelSmall?.copyWith(
                  color: colors.textLabel,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
          style: textTheme.titleSmall?.copyWith(
            color: colors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(
          status.text,
          style: textTheme.labelSmall?.copyWith(
            color: status.stale ? colors.stress : colors.textLabel,
          ),
        ),
      ],
    );
  }

  LocalDate get _today => LocalDate.fromInstant(now, now.timeZoneOffset);

  Widget _body(BuildContext context, MetricFormat format) {
    final l10n = format.l10n;
    final data = snapshot;
    if (config.isEmpty) return _message(context, l10n.widgetNoMetrics);
    if (data == null || !data.paired) {
      return _message(context, l10n.widgetUnpaired);
    }
    if (!data.hasHealthData) return _message(context, l10n.widgetNoData);
    final columns = [
      for (final metric in config.metrics)
        _MetricColumn(metric, format, data, _colors),
    ];
    if (context.prefersSingleColumn) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (index, column) in columns.indexed) ...[
            if (index > 0) const SizedBox(height: 10),
            column,
          ],
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (index, column) in columns.indexed) ...[
          if (index > 0) const SizedBox(width: 10),
          Expanded(child: column),
        ],
      ],
    );
  }

  Widget _message(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.bodyMedium
          ?.copyWith(color: _colors.textLabel, height: 1.45),
    ),
  );
}

class _MetricColumn extends StatelessWidget {
  const new(this.metric, this.format, this.snapshot, this.colors);

  final WidgetMetric metric;
  final MetricFormat format;
  final WidgetSnapshot snapshot;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final text = metric.describe(format, snapshot);
    final accent = metric.accent(colors);
    final progress = text.progress;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                metric.label(format.l10n),
                style: textTheme.labelSmall?.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          text.value,
          style: numberStyle(
            textTheme.headlineSmall,
            color: colors.textPrimary,
          ),
        ),
        if (progress != null) ...[
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 5,
              color: accent,
              backgroundColor: colors.track,
            ),
          ),
        ],
        const SizedBox(height: 6),
        Text(
          text.detail,
          style: textTheme.labelSmall?.copyWith(color: colors.textLabel),
        ),
      ],
    );
  }
}

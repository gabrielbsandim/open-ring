import 'package:flutter/material.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/core/widgets/text_scale.dart';
import 'package:open_ring/features/open_score/presentation/day_score_card.dart';
import 'package:open_ring/features/settings/domain/unit_system.dart';
import 'package:open_ring/features/widgets/domain/today_widget_config.dart';
import 'package:open_ring/features/widgets/domain/widget_snapshot.dart';
import 'package:open_ring/features/widgets/presentation/widget_labels.dart';
import 'package:open_ring/features/widgets/presentation/widget_previews.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

enum TodayPreviewSize {
  small(1),
  medium(3),
  large(6);

  new(this.maxFields);

  final int maxFields;
}

class TodayWidgetPreview extends StatelessWidget {
  const new({
    required this.config,
    required this.snapshot,
    required this.brightness,
    required this.now,
    this.size = TodayPreviewSize.medium,
    this.units = UnitSystem.metric,
    super.key,
  });

  static const previewKey = Key('today_widget_preview');

  final TodayWidgetConfig config;
  final WidgetSnapshot? snapshot;
  final Brightness brightness;
  final DateTime now;
  final TodayPreviewSize size;
  final UnitSystem units;

  AppColors get _colors =>
      brightness == Brightness.dark ? AppColors.dark : AppColors.light;

  List<WidgetMetric> get _visible =>
      config.metrics.take(size.maxFields).toList(growable: false);

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
                  children: _children(context, format),
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
    final visible = _visible;
    if (visible.isEmpty) return l10n.widgetPreviewEmptySemantics;
    final status = widgetSyncStatus(format, snapshot, now);
    final parts = [
      for (final metric in visible)
        '${metric.label(l10n)} ${metric.describe(format, snapshot, units: units, now: now, stale: status.stale).value}',
    ];
    return l10n.widgetPreviewSemantics(parts.join(', '));
  }

  List<Widget> _children(BuildContext context, MetricFormat format) {
    final l10n = format.l10n;
    final data = snapshot;
    final visible = _visible;
    final status = widgetSyncStatus(format, data, now);
    if (visible.isEmpty) {
      return [
        _titleOnlyHeader(context, l10n.widgetTodayName),
        _message(context, l10n.widgetNoMetrics),
      ];
    }
    if (data == null ||
        (!data.paired && visible.every((m) => m.requiresRing))) {
      final heading = size == TodayPreviewSize.small
          ? visible.first.label(l10n)
          : l10n.widgetTodayName;
      return [
        _titleOnlyHeader(context, heading),
        _message(context, l10n.widgetUnpaired),
        WidgetStatusLine(
          status: (text: l10n.todayNoRing, stale: false),
          colors: _colors,
        ),
      ];
    }
    final noRingData =
        !data.hasHealthData &&
        (data.dayScore == null || !visible.contains(WidgetMetric.dayScore));
    if (noRingData && visible.every((m) => m.requiresRing)) {
      return [
        _header(context, format, status),
        _message(context, l10n.widgetNoData),
      ];
    }
    if (size == TodayPreviewSize.small) {
      return [
        _MetricColumn(
          visible.first,
          format,
          data,
          _colors,
          units: units,
          now: now,
          stale: status.stale,
          headline: true,
        ),
        const SizedBox(height: 12),
        WidgetStatusLine(status: status, colors: _colors),
      ];
    }
    return [
      _header(context, format, status),
      const SizedBox(height: 10),
      if (size == TodayPreviewSize.medium)
        _mediumBody(context, visible, format, data, stale: status.stale)
      else
        _largeBody(context, visible, format, data, stale: status.stale),
    ];
  }

  Widget _titleOnlyHeader(BuildContext context, String title) => Text(
    title,
    style: Theme.of(context).textTheme.titleSmall
        ?.copyWith(color: _colors.textPrimary, fontWeight: FontWeight.w600),
  );

  Widget _header(
    BuildContext context,
    MetricFormat format,
    WidgetStatus status,
  ) {
    final textTheme = Theme.of(context).textTheme;
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
                  color: _colors.textLabel,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
          style: textTheme.titleSmall?.copyWith(
            color: _colors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        WidgetStatusLine(status: status, colors: _colors),
      ],
    );
  }

  LocalDate get _today => LocalDate.fromInstant(now, now.timeZoneOffset);

  Widget _mediumBody(
    BuildContext context,
    List<WidgetMetric> visible,
    MetricFormat format,
    WidgetSnapshot data, {
    required bool stale,
  }) {
    final columns = [
      for (final metric in visible)
        _MetricColumn(
          metric,
          format,
          data,
          _colors,
          units: units,
          now: now,
          stale: stale,
        ),
    ];
    if (context.prefersSingleColumn) return _singleColumnList(columns);
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

  Widget _largeBody(
    BuildContext context,
    List<WidgetMetric> visible,
    MetricFormat format,
    WidgetSnapshot data, {
    required bool stale,
  }) {
    final hasHero = visible.first == WidgetMetric.dayScore;
    final rest = hasHero ? visible.sublist(1) : visible;
    final restWidgets = [
      for (final metric in rest)
        _MetricColumn(
          metric,
          format,
          data,
          _colors,
          units: units,
          now: now,
          stale: stale,
        ),
    ];
    final showDivider = hasHero && restWidgets.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hasHero)
          _DayScoreHero(
            display: describeDayScore(format, data, now, stale: stale),
            format: format,
            colors: _colors,
          ),
        if (showDivider) ...[
          const SizedBox(height: 10),
          Divider(height: 1, color: _colors.track),
          const SizedBox(height: 10),
        ],
        if (restWidgets.isNotEmpty) _largeRest(context, restWidgets),
      ],
    );
  }

  Widget _largeRest(BuildContext context, List<Widget> restWidgets) {
    if (context.prefersSingleColumn) return _singleColumnList(restWidgets);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < restWidgets.length; i += 2) ...[
          if (i > 0) const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: restWidgets[i]),
              const SizedBox(width: 10),
              Expanded(
                child: i + 1 < restWidgets.length
                    ? restWidgets[i + 1]
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _singleColumnList(List<Widget> children) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final (index, child) in children.indexed) ...[
        if (index > 0) const SizedBox(height: 10),
        child,
      ],
    ],
  );

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

class _DayScoreHero extends StatelessWidget {
  const new({
    required this.display,
    required this.format,
    required this.colors,
  });

  final WidgetDayScoreView display;
  final MetricFormat format;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final l10n = format.l10n;
    if (display.messageTitle != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _HeadingRow(WidgetMetric.dayScore, l10n.dayScoreTitle, colors),
          const SizedBox(height: 6),
          Text(
            display.messageTitle!,
            style: textTheme.bodyMedium?.copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (display.messageDetail != null)
            Text(
              display.messageDetail!,
              style: textTheme.labelSmall?.copyWith(color: colors.textLabel),
            ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _HeadingRow(WidgetMetric.dayScore, l10n.dayScoreTitle, colors),
        const SizedBox(height: 4),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.end,
          spacing: 8,
          runSpacing: 2,
          children: [
            Text(
              display.value,
              style: numberStyle(
                textTheme.headlineLarge,
                color: colors.textPrimary,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                display.detail,
                style: textTheme.labelSmall?.copyWith(color: colors.textLabel),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        _PillarBar(pillarPoints: display.pillarPoints, colors: colors),
        const SizedBox(height: 4),
        Row(
          children: [
            for (final pillar in DayScorePillar.values)
              Expanded(
                child: Text(
                  dayScorePillarLabel(l10n, pillar),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.labelSmall?.copyWith(
                    fontSize: 10,
                    color: colors.textLabel,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _PillarBar extends StatelessWidget {
  const new({required this.pillarPoints, required this.colors});

  static const _maxWeights = [30.0, 35.0, 20.0, 10.0, 5.0];

  final List<double?>? pillarPoints;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < DayScorePillar.values.length; i++) ...[
          if (i > 0) const SizedBox(width: 3),
          Expanded(
            flex: _maxWeights[i].round(),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: _progress(i),
                minHeight: 5,
                color: dayScorePillarColor(colors, DayScorePillar.values[i]),
                backgroundColor: colors.track,
              ),
            ),
          ),
        ],
      ],
    );
  }

  double _progress(int index) {
    final points = pillarPoints;
    if (points == null || index >= points.length || points[index] == null) {
      return 0;
    }
    return (points[index]! / _maxWeights[index]).clamp(0, 1).toDouble();
  }
}

class _HeadingRow extends StatelessWidget {
  const new(this.metric, this.label, this.colors);

  final WidgetMetric metric;
  final String label;
  final AppColors colors;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: metric.accent(colors),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
      const SizedBox(width: 6),
      Flexible(
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall
              ?.copyWith(color: colors.textSecondary),
        ),
      ),
    ],
  );
}

class _MetricColumn extends StatelessWidget {
  const new(
    this.metric,
    this.format,
    this.snapshot,
    this.colors, {
    this.units = UnitSystem.metric,
    this.now,
    this.stale = false,
    this.headline = false,
  });

  final WidgetMetric metric;
  final MetricFormat format;
  final WidgetSnapshot snapshot;
  final AppColors colors;
  final UnitSystem units;
  final DateTime? now;
  final bool stale;
  final bool headline;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final l10n = format.l10n;
    if (metric == WidgetMetric.dayScore) return _buildDayScore(textTheme, l10n);
    final text = metric.describe(
      format,
      snapshot,
      units: units,
      now: now,
      stale: stale,
    );
    final accent = metric.accent(colors);
    final progress = text.progress;
    final valueStyle = headline
        ? textTheme.headlineLarge
        : textTheme.headlineSmall;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _HeadingRow(metric, metric.label(l10n), colors),
        const SizedBox(height: 6),
        Text(
          text.value,
          style: numberStyle(valueStyle, color: colors.textPrimary),
        ),
        if (progress != null) ...[
          const SizedBox(height: 6),
          WidgetPreviewBar(value: progress, color: accent, track: colors.track),
        ],
        const SizedBox(height: 6),
        Text(
          text.detail,
          style: textTheme.labelSmall?.copyWith(color: colors.textLabel),
        ),
      ],
    );
  }

  Widget _buildDayScore(TextTheme textTheme, AppLocalizations l10n) {
    final view = describeDayScore(
      format,
      snapshot,
      now ?? DateTime.now(),
      stale: stale,
    );
    if (view.messageTitle != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _HeadingRow(metric, metric.label(l10n), colors),
          const SizedBox(height: 6),
          Text(
            view.messageTitle!,
            style: textTheme.bodySmall?.copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (view.messageDetail != null) ...[
            const SizedBox(height: 2),
            Text(
              view.messageDetail!,
              style: textTheme.labelSmall?.copyWith(color: colors.textLabel),
            ),
          ],
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _HeadingRow(metric, metric.label(l10n), colors),
        const SizedBox(height: 6),
        Text(
          view.value,
          style: numberStyle(
            headline ? textTheme.headlineLarge : textTheme.headlineSmall,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        _PillarBar(pillarPoints: view.pillarPoints, colors: colors),
        const SizedBox(height: 6),
        Text(
          view.detail,
          style: textTheme.labelSmall?.copyWith(color: colors.textLabel),
        ),
      ],
    );
  }
}

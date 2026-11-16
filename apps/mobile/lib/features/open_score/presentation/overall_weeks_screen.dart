import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/core/widgets/app_page.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/open_score/application/overall_providers.dart';
import 'package:open_ring/features/open_score/domain/overall_trend.dart';
import 'package:open_ring/features/open_score/presentation/overall_screen.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

abstract final class OverallWeeksKeys {
  static const few = Key('overall_weeks_few');
  static const since = Key('overall_weeks_since');
  static const chart = Key('overall_weeks_chart');
  static const now = Key('overall_weeks_now');
  static const typical = Key('overall_weeks_typical');
  static const floor = Key('overall_weeks_floor');
  static const changed = Key('overall_weeks_changed');

  static Key change(OverallFactor factor) =>
      Key('overall_weeks_change_${factor.name}');
}

class OverallWeeksScreen extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final on = ref.watch(
      enabledModulesProvider.select(
        (modules) => modules.value?.contains(ModuleId.openScore) ?? false,
      ),
    );
    return AppPage(
      title: l10n.overallWeeksTitle,
      subtitle: on ? l10n.overallWeeksLead : null,
      children: on ? _content(ref, l10n) : [],
    );
  }

  List<Widget> _content(WidgetRef ref, AppLocalizations l10n) {
    final loaded = ref.watch(overallHistoryProvider);
    if (loaded.hasError) return [BodyText(l10n.metricLoadError)];
    final history = loaded.value;
    if (history == null) return const [SizedBox(height: 96)];
    final trend = OverallTrend.of(history.weeks);
    if (trend == null) {
      return [
        MetricCard(
          key: OverallWeeksKeys.few,
          child: BodyText(
            l10n.overallWeeksFew(
              overallTrendMinWeeks,
              history.weeks
                  .where((week) => week.result is Scored<OverallFactor>)
                  .length,
            ),
          ),
        ),
      ];
    }
    return [
      _Chart(trend: trend),
      const SizedBox(height: cardGap),
      _Numbers(trend: trend),
      const SizedBox(height: cardGap),
      _Changed(trend: trend),
      const SizedBox(height: cardGap),
      CaptionText(l10n.overallWeeksNoise(overallNoiseBelow)),
      const SizedBox(height: 6),
      CaptionText(l10n.overallWeeksHollow),
    ];
  }
}

class _Chart extends StatelessWidget {
  const new({required this.trend});

  final OverallTrend trend;

  @override
  Widget build(BuildContext context) {
    final format = MetricFormat.of(context);
    final l10n = format.l10n;
    final colors = AppColors.of(context);
    return MetricCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.overallWeeksSince(
              format.signed(trend.since.change.toDouble()),
              format.monthDay(trend.since.date),
            ),
            key: OverallWeeksKeys.since,
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),
          Semantics(
            label: l10n.overallWeeksChart(
              trend.points.length,
              format.monthDay(trend.points.first.date),
              format.monthDay(trend.points.last.date),
            ),
            child: SizedBox(
              key: OverallWeeksKeys.chart,
              height: 150,
              child: CustomPaint(
                painter: _ChartPainter(
                  points: trend.points,
                  line: colors.textPrimary,
                  grid: colors.surfaceBorder,
                  surface: colors.surface,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 12,
            children: [
              CaptionText(format.monthDay(trend.points.first.date)),
              CaptionText(format.monthDay(trend.points.last.date)),
            ],
          ),
        ],
      ),
    );
  }
}

class _ChartPainter extends CustomPainter {
  const new({
    required this.points,
    required this.line,
    required this.grid,
    required this.surface,
  });

  final List<OverallPoint> points;
  final Color line;
  final Color grid;
  final Color surface;

  static const _radius = 4.5;
  static const _margin = 6.0;

  @override
  void paint(Canvas canvas, Size size) {
    final scores = [for (final point in points) ?point.score];
    final low = scores.reduce((a, b) => a < b ? a : b) - _margin;
    final high = scores.reduce((a, b) => a > b ? a : b) + _margin;
    final step = points.length < 2
        ? 0.0
        : (size.width - 2 * _radius) / (points.length - 1);
    Offset at(int index, int score) => Offset(
      _radius + step * index,
      size.height * (1 - (score - low) / (high - low)),
    );
    canvas.drawLine(
      Offset(0, size.height),
      Offset(size.width, size.height),
      Paint()..color = grid,
    );
    final stroke = Paint()
      ..color = line
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    for (var index = 1; index < points.length; index++) {
      final from = points[index - 1];
      final to = points[index];
      final fromScore = from.score;
      final toScore = to.score;
      if (fromScore == null || toScore == null) continue;
      if (from.comparable != to.comparable) continue;
      canvas.drawLine(at(index - 1, fromScore), at(index, toScore), stroke);
    }
    for (var index = 0; index < points.length; index++) {
      final score = points[index].score;
      if (score == null) continue;
      final center = at(index, score);
      canvas
        ..drawCircle(
          center,
          _radius,
          Paint()..color = points[index].comparable ? line : surface,
        )
        ..drawCircle(center, _radius, stroke);
    }
  }

  @override
  bool shouldRepaint(_ChartPainter old) =>
      old.points != points || old.line != line || old.surface != surface;
}

class _Numbers extends StatelessWidget {
  const new({required this.trend});

  final OverallTrend trend;

  @override
  Widget build(BuildContext context) {
    final format = MetricFormat.of(context);
    final l10n = format.l10n;
    return MetricCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 16,
            runSpacing: 12,
            children: [
              _Number(
                key: OverallWeeksKeys.now,
                value: format.integer(trend.now),
                label: l10n.overallWeeksNow,
              ),
              _Number(
                key: OverallWeeksKeys.typical,
                value: format.integer(trend.typical),
                label: l10n.overallWeeksTypical,
              ),
              _Number(
                key: OverallWeeksKeys.floor,
                value: format.integer(trend.floor),
                label: l10n.overallWeeksFloor,
              ),
            ],
          ),
          const SizedBox(height: 12),
          CaptionText(l10n.overallWeeksFloorNote),
        ],
      ),
    );
  }
}

class _Number extends StatelessWidget {
  const new({required this.value, required this.label, super.key});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        value,
        style: Theme.of(context).textTheme.headlineSmall
            ?.copyWith(fontWeight: FontWeight.w600),
      ),
      CaptionText(label),
    ],
  );
}

class _Changed extends StatelessWidget {
  const new({required this.trend});

  final OverallTrend trend;

  @override
  Widget build(BuildContext context) {
    final format = MetricFormat.of(context);
    final l10n = format.l10n;
    return MetricCard(
      key: OverallWeeksKeys.changed,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.overallWeeksChangedTitle(format.monthDay(trend.since.date)),
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          for (final change in trend.changes)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                spacing: 12,
                children: [
                  BodyText(overallFactorLabel(l10n, change.factor)),
                  BodyText(
                    key: OverallWeeksKeys.change(change.factor),
                    _delta(format, change.points),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

String _delta(MetricFormat format, double points) {
  final text = format.signed(points, digits: 1);
  if (text == format.decimal(0, digits: 1)) return format.l10n.overallWeeksSame;
  return format.l10n.dayScoreReceiptPoints(text);
}

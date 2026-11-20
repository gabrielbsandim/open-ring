import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/core/widgets/charts.dart';
import 'package:open_ring/features/food/application/food_week.dart';

const foodTimingStartMinute = 360;
const foodTimingEndMinute = 1500;
const foodTimingMinBarWidth = 4.0;
const foodTimingGridMinutes = <double>[360, 720, 1080, 1440];
const foodTimingAxisHours = <int>[6, 12, 18, 0];

abstract final class FoodTimingChartKeys {
  static const paint = Key('food_timing_chart_paint');
  static const axis = Key('food_timing_chart_axis');

  static Key rowLabel(LocalDate day) => Key('food_timing_row_${day.iso}');
}

final class FoodTimingRowMark {
  const new({
    required this.windowStartMinute,
    required this.windowEndMinute,
    required this.complete,
    required this.mealMinutes,
    required this.sleepOnsetMinute,
  });

  final double? windowStartMinute;
  final double? windowEndMinute;
  final bool complete;
  final List<double> mealMinutes;
  final double? sleepOnsetMinute;
}

double foodTimingMinuteOfDay(LocalDate day, DateTime at) =>
    LocalDate(at.year, at.month, at.day).daysSince(day) *
        Duration.minutesPerDay.toDouble() +
    at.hour * 60.0 +
    at.minute +
    at.second / 60.0;

double _clamp(double v, double lo, double hi) =>
    v <= lo ? lo : (v >= hi ? hi : v);

double foodTimingX(double minute, double width) {
  if (width <= 0) return 0;
  final start = foodTimingStartMinute.toDouble();
  final span = (foodTimingEndMinute - foodTimingStartMinute).toDouble();
  final clamped = _clamp(minute, start, foodTimingEndMinute.toDouble());
  return ((clamped - start) / span) * width;
}

FoodTimingRowMark foodTimingRowOf(FoodWeekDayView day) {
  final opening = [
    for (final m in day.meals)
      if (opensWindow(m.entry)) foodTimingMinuteOfDay(day.date, m.entry.at),
  ]..sort();
  final onset = day.sleepOnset;
  return FoodTimingRowMark(
    windowStartMinute: opening.isEmpty ? null : opening.first,
    windowEndMinute: opening.isEmpty ? null : opening.last,
    complete: day.complete,
    mealMinutes: List.unmodifiable([
      for (final m in day.meals) foodTimingMinuteOfDay(day.date, m.entry.at),
    ]),
    sleepOnsetMinute: onset == null
        ? null
        : foodTimingMinuteOfDay(day.date, onset),
  );
}

class FoodTimingChart extends StatelessWidget {
  const new({required this.days, required this.completeDays, super.key});

  final List<FoodWeekDayView> days;
  final int completeDays;

  @override
  Widget build(BuildContext context) {
    if (days.isEmpty) return const SizedBox.shrink();
    final f = MetricFormat.of(context);
    final colors = AppColors.of(context);
    final style = Theme.of(context).textTheme.labelSmall
        ?.copyWith(color: colors.textLabel);
    final labels = [for (final d in days) '${f.weekday(d.date)} ${d.date.day}'];
    final rows = [for (final d in days) foodTimingRowOf(d)];
    final scaler = MediaQuery.textScalerOf(context);
    final dir = Directionality.of(context);
    return Semantics(
      container: true,
      image: true,
      label: f.l10n.foodTimingChartLabel(completeDays),
      child: ExcludeSemantics(
        child: LayoutBuilder(
          builder: (context, c) {
            final labelW = _labelWidth(labels, style, dir, scaler, c.maxWidth);
            final plotW = math.max<double>(0, c.maxWidth - labelW - 8);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: labelW,
                        child: Column(
                          children: [
                            for (var i = 0; i < days.length; i++)
                              Container(
                                constraints: const BoxConstraints(
                                  minHeight: 24,
                                ),
                                alignment: AlignmentDirectional.centerStart,
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: AlignmentDirectional.centerStart,
                                  child: Text(
                                    labels[i],
                                    key: FoodTimingChartKeys.rowLabel(
                                      days[i].date,
                                    ),
                                    style: style,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: CustomPaint(
                          key: FoodTimingChartKeys.paint,
                          painter: _TimingPainter(rows: rows, colors: colors),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Padding(
                  padding: EdgeInsetsDirectional.only(
                    start: labelW + 8,
                    end: plotW * (60 / 1140),
                  ),
                  child: TimeAxis(
                    key: FoodTimingChartKeys.axis,
                    labels: [
                      for (final h in foodTimingAxisHours)
                        f.clock(DateTime.utc(2026, 1, 1, h), Duration.zero),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

double _labelWidth(
  List<String> labels,
  TextStyle? style,
  TextDirection dir,
  TextScaler scaler,
  double maxWidth,
) {
  var widest = 0.0;
  for (final label in labels) {
    final p = TextPainter(
      text: TextSpan(text: label, style: style),
      textDirection: dir,
      textScaler: scaler,
    )..layout();
    widest = math.max(widest, p.width);
    p.dispose();
  }
  return math.min(widest.ceilToDouble() + 1, maxWidth * 0.34);
}

class _TimingPainter extends CustomPainter {
  const new({required this.rows, required this.colors});

  final List<FoodTimingRowMark> rows;
  final AppColors colors;

  static Paint _stroke(Color c, double w) => Paint()
    ..color = c
    ..style = PaintingStyle.stroke
    ..strokeWidth = w;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || rows.isEmpty) return;
    final grid = Paint()
      ..color = colors.surfaceBorder
      ..strokeWidth = 1;
    for (final m in foodTimingGridMinutes) {
      final x = foodTimingX(m, size.width);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    final fill = Paint()..color = colors.activity;
    final dash = _stroke(colors.activity, 1.5);
    final dotFill = Paint()..color = colors.surface;
    final dotStroke = _stroke(colors.activity, 1.75);
    final sleep = Paint()
      ..color = colors.sleep
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    final rowH = size.height / rows.length;
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      final y = rowH * (i + 0.5);
      _drawBar(canvas, size.width, y, row, fill, dash);
      for (final m in row.mealMinutes) {
        final cx = _clamp(
          foodTimingX(m, size.width),
          3.4,
          math.max(3.4, size.width - 3.4),
        );
        canvas
          ..drawCircle(Offset(cx, y), 3.4, dotFill)
          ..drawCircle(Offset(cx, y), 3.4, dotStroke);
      }
      final onset = row.sleepOnsetMinute;
      if (onset == null) continue;
      final sx = _clamp(
        foodTimingX(onset, size.width),
        1.25,
        math.max(1.25, size.width - 1.25),
      );
      canvas.drawLine(Offset(sx, y - 7), Offset(sx, y + 7), sleep);
    }
  }

  void _drawBar(
    Canvas canvas,
    double width,
    double y,
    FoodTimingRowMark row,
    Paint fill,
    Paint dash,
  ) {
    final s = row.windowStartMinute;
    final e = row.windowEndMinute;
    if (s == null || e == null) return;
    final x1 = foodTimingX(s, width);
    final x2 = foodTimingX(e, width);
    final w = math.max(foodTimingMinBarWidth, x2 - x1);
    final left = _clamp(x1, 0, math.max(0, width - w));
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(left, y - 3, w, 6),
      const Radius.circular(3),
    );
    if (row.complete) {
      canvas.drawRRect(rrect, fill);
      return;
    }
    for (final metric in (Path()..addRRect(rrect)).computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 6.0) {
        canvas.drawPath(
          metric.extractPath(d, math.min(metric.length, d + 3.0)),
          dash,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_TimingPainter old) =>
      old.colors != colors ||
      old.rows.length != rows.length ||
      Iterable<int>.generate(rows.length).any((i) {
        final a = old.rows[i];
        final b = rows[i];
        return a.windowStartMinute != b.windowStartMinute ||
            a.windowEndMinute != b.windowEndMinute ||
            a.complete != b.complete ||
            a.sleepOnsetMinute != b.sleepOnsetMinute ||
            !listEquals(a.mealMinutes, b.mealMinutes);
      });
}

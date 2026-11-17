import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/features/body/presentation/weight_chart.dart';
import 'package:open_ring/features/goals/application/goal_path_providers.dart';
import 'package:open_ring/features/settings/application/unit_format.dart';

const _daysBefore = 7;

/// The weigh-ins and the trend against the target band of the block, from a
/// week before the block to its end.
class GoalPathChart extends StatelessWidget {
  const new({
    required this.view,
    required this.block,
    required this.startKg,
    required this.units,
    required this.label,
    super.key,
  });

  static const _height = 176.0;

  final GoalPathView view;
  final GoalBlock block;
  final double startKg;
  final UnitFormat units;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final path = view.path;
    final first = block.start.addDays(-_daysBefore);
    final last = path.on.compareTo(block.end) > 0 ? path.on : block.end;
    final span = math.max(1, last.daysSince(first)).toDouble();
    double x(LocalDate date) => date.daysSince(first) / span;
    List<Offset> placed(List<DailyValue> days) => [
      for (final day in days)
        if (day.date.compareTo(first) >= 0)
          Offset(x(day.date), units.bodyWeightIn(day.value)),
    ];
    final dots = placed(view.daily);
    final trend = placed(view.line);
    final start = units.bodyWeightIn(startKg);
    final weeks = (block.end.daysSince(block.start) + 1) / 7;
    final weekly = units.bodyWeightIn(block.weeklyKg);
    final reference = path.referenceKg;
    final referenceShown = reference == null
        ? null
        : units.bodyWeightIn(reference);
    final usualEnd = start - weekly * weeks;
    final axis = weightAxis([
      start,
      usualEnd,
      ?referenceShown,
      for (final point in dots) point.dy,
      for (final point in trend) point.dy,
    ]);
    final digits = axis.step < 1 ? 1 : 0;
    return Semantics(
      container: true,
      image: true,
      label: label,
      child: SizedBox(
        height: _height,
        width: double.infinity,
        child: CustomPaint(
          painter: _PathPainter(
            dots: dots,
            trend: trend,
            axis: axis,
            blockStart: x(block.start),
            blockEnd: x(block.end),
            now: x(path.on),
            start: start,
            slowEnd: start - weekly * goalBandLow * weeks,
            fastEnd: start - weekly * goalBandHigh * weeks,
            usualEnd: usualEnd,
            reference: referenceShown,
            ticks: [
              for (var v = axis.low; v <= axis.high + 1e-9; v += axis.step)
                units.format.decimal(v, digits: digits),
            ],
            days: [
              units.format.monthDay(block.start),
              units.format.monthDay(block.end),
            ],
            style:
                Theme.of(context).textTheme.labelSmall
                    ?.copyWith(color: colors.textLabel) ??
                TextStyle(color: colors.textLabel),
            scaler: MediaQuery.textScalerOf(context),
            lineColor: colors.textPrimary,
            dotColor: colors.textLabel,
            grid: colors.track,
            bandColor: colors.textPrimary.withValues(alpha: 0.1),
          ),
        ),
      ),
    );
  }
}

class _PathPainter extends CustomPainter {
  const new({
    required this.dots,
    required this.trend,
    required this.axis,
    required this.blockStart,
    required this.blockEnd,
    required this.now,
    required this.start,
    required this.slowEnd,
    required this.fastEnd,
    required this.usualEnd,
    required this.reference,
    required this.ticks,
    required this.days,
    required this.style,
    required this.scaler,
    required this.lineColor,
    required this.dotColor,
    required this.grid,
    required this.bandColor,
  });

  static const _gutterGap = 6.0;
  static const _right = 8.0;
  static const _dotRadius = 2.2;
  static const _nowRadius = 4.5;
  static const _dash = 5.0;

  /// x as a fraction of the width, y in the shown unit.
  final List<Offset> dots;
  final List<Offset> trend;
  final WeightAxis axis;
  final double blockStart;
  final double blockEnd;
  final double now;
  final double start;
  final double slowEnd;
  final double fastEnd;
  final double usualEnd;
  final double? reference;
  final List<String> ticks;
  final List<String> days;
  final TextStyle style;
  final TextScaler scaler;
  final Color lineColor;
  final Color dotColor;
  final Color grid;
  final Color bandColor;

  TextPainter _text(String text) => TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    textScaler: scaler,
    maxLines: 1,
  )..layout();

  @override
  void paint(Canvas canvas, Size size) {
    final labels = [for (final tick in ticks) _text(tick)];
    final dayLabels = [for (final day in days) _text(day)];
    final rowHeight = dayLabels.first.height;
    final left =
        labels.map((label) => label.width).reduce(math.max) + _gutterGap;
    const top = 6.0;
    final bottom = size.height - rowHeight - 8;
    final width = size.width - left - _right;
    double x(double fraction) => left + fraction * width;
    double y(double value) =>
        top + (axis.high - value) / (axis.high - axis.low) * (bottom - top);
    Offset at(Offset point) => Offset(x(point.dx), y(point.dy));

    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var i = 0; i < labels.length; i++) {
      final value = axis.low + i * axis.step;
      canvas.drawLine(
        Offset(left, y(value)),
        Offset(x(1), y(value)),
        gridPaint,
      );
      labels[i].paint(
        canvas,
        Offset(
          left - _gutterGap - labels[i].width,
          y(value) - labels[i].height / 2,
        ),
      );
    }
    canvas
      ..save()
      ..clipRect(Rect.fromLTRB(left, top, x(1), bottom))
      ..drawPath(
        Path()..addPolygon([
          Offset(x(blockStart), y(start)),
          Offset(x(blockEnd), y(slowEnd)),
          Offset(x(blockEnd), y(fastEnd)),
        ], true),
        Paint()..color = bandColor,
      );
    final dashed = Paint()
      ..color = dotColor
      ..strokeWidth = 1.5;
    _dashed(
      canvas,
      Offset(x(blockStart), y(start)),
      Offset(x(blockEnd), y(usualEnd)),
      dashed,
    );
    final ref = reference;
    if (ref != null) {
      _dashed(
        canvas,
        Offset(left, y(ref)),
        Offset(x(1), y(ref)),
        dashed..color = lineColor,
      );
    }
    final dotPaint = Paint()..color = dotColor;
    for (final dot in dots) {
      canvas.drawCircle(at(dot), _dotRadius, dotPaint);
    }
    if (trend.isNotEmpty) {
      final line = Path()..moveTo(at(trend.first).dx, at(trend.first).dy);
      for (final point in trend.skip(1)) {
        line.lineTo(at(point).dx, at(point).dy);
      }
      canvas
        ..drawPath(
          line,
          Paint()
            ..color = lineColor
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.5
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round,
        )
        ..drawCircle(at(trend.last), _nowRadius, Paint()..color = lineColor);
    }
    canvas
      ..drawLine(Offset(x(now), top), Offset(x(now), bottom), gridPaint)
      ..restore();
    final labelTop = bottom + 6;
    dayLabels[0].paint(canvas, Offset(x(blockStart), labelTop));
    dayLabels[1].paint(
      canvas,
      Offset(
        math.max(x(blockStart), x(blockEnd) - dayLabels[1].width),
        labelTop,
      ),
    );
  }

  void _dashed(Canvas canvas, Offset from, Offset to, Paint paint) {
    final length = (to - from).distance;
    if (length == 0) return;
    final step = (to - from) / length;
    for (var d = 0.0; d < length; d += _dash * 2) {
      canvas.drawLine(
        from + step * d,
        from + step * math.min(d + _dash, length),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_PathPainter old) =>
      old.dots != dots ||
      old.trend != trend ||
      old.axis != axis ||
      old.now != now ||
      old.start != start ||
      old.reference != reference ||
      old.ticks != ticks ||
      old.days != days ||
      old.style != style ||
      old.scaler != scaler ||
      old.lineColor != lineColor ||
      old.dotColor != dotColor ||
      old.grid != grid ||
      old.bandColor != bandColor;
}

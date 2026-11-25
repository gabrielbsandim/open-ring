import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/features/body/presentation/weight_chart.dart';
import 'package:open_ring/features/settings/application/unit_format.dart';
import 'package:open_ring/features/trajectory/domain/trajectory_view.dart';

const _pastDays = 35;

typedef _Point = ({double day, double value});

class TrajectoryChart extends StatelessWidget {
  const new({
    required this.view,
    required this.daily,
    required this.line,
    required this.units,
    this.hidden = false,
    super.key,
  });

  static const _height = 200.0;

  final TrajectoryReady view;
  final List<DailyValue> daily;
  final List<DailyValue> line;
  final UnitFormat units;

  /// Hidden numbers keep the shape: no dots and no weight labels.
  final bool hidden;

  List<_Point> _past(List<DailyValue> days) => [
    for (final day in days)
      if (view.asOf.daysSince(day.date) case final age
          when age >= 0 && age <= _pastDays)
        (day: -age.toDouble(), value: units.bodyWeightIn(day.value)),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final l10n = units.l10n;
    final now = units.bodyWeightIn(view.trendKg);
    ({_Point at28, _Point at84}) edge(double Function(ScenarioBand) of) => (
      at28: (
        day: view.firm.days.toDouble(),
        value: units.bodyWeightIn(of(view.firm)),
      ),
      at84: (
        day: view.band.days.toDouble(),
        value: units.bodyWeightIn(of(view.band)),
      ),
    );
    final low = edge((band) => band.low);
    final mid = edge((band) => band.mid);
    final high = edge((band) => band.high);
    final dots = hidden ? const <_Point>[] : _past(daily);
    final trend = _past(line);
    final axis = weightAxis([
      now,
      for (final point in [...dots, ...trend]) point.value,
      low.at28.value,
      low.at84.value,
      high.at28.value,
      high.at84.value,
    ]);
    final start = (day: 0.0, value: now);
    return Semantics(
      container: true,
      image: true,
      label: hidden
          ? l10n.trajectoryChartHiddenLabel
          : l10n.trajectoryChartLabel(units.weightUnit),
      child: SizedBox(
        height: _height,
        width: double.infinity,
        child: CustomPaint(
          painter: _ScenarioPainter(
            dots: dots,
            trend: trend,
            firm: [start, high.at28, low.at28],
            band: [start, high.at28, high.at84, low.at84, low.at28],
            middle: [start, mid.at28, mid.at84],
            axis: axis,
            ticks: [
              if (!hidden)
                for (var v = axis.low; v <= axis.high + 1e-9; v += axis.step)
                  units.format.decimal(v, digits: axis.step < 1 ? 1 : 0),
            ],
            unit: hidden ? '' : units.weightUnit,
            days: [
              units.format.monthDay(view.asOf.addDays(-_pastDays)),
              l10n.bodyChartToday,
              units.format.monthDay(view.asOf.addDays(view.firm.days)),
              units.format.monthDay(view.asOf.addDays(view.band.days)),
            ],
            style:
                Theme.of(context).textTheme.labelSmall
                    ?.copyWith(color: colors.textLabel) ??
                TextStyle(color: colors.textLabel),
            scaler: MediaQuery.textScalerOf(context),
            line: colors.textPrimary,
            dot: colors.textLabel,
            grid: colors.track,
          ),
        ),
      ),
    );
  }
}

class _ScenarioPainter extends CustomPainter {
  const new({
    required this.dots,
    required this.trend,
    required this.firm,
    required this.band,
    required this.middle,
    required this.axis,
    required this.ticks,
    required this.unit,
    required this.days,
    required this.style,
    required this.scaler,
    required this.line,
    required this.dot,
    required this.grid,
  });

  static const _gap = 6.0;
  static const _right = 8.0;
  static const _dash = 5.0;

  final List<_Point> dots;
  final List<_Point> trend;
  final List<_Point> firm;
  final List<_Point> band;
  final List<_Point> middle;
  final WeightAxis axis;
  final List<String> ticks;
  final String unit;
  final List<String> days;
  final TextStyle style;
  final TextScaler scaler;
  final Color line;
  final Color dot;
  final Color grid;

  TextPainter _text(String text) => TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    textScaler: scaler,
    maxLines: 1,
  )..layout();

  @override
  void paint(Canvas canvas, Size size) {
    final labels = [for (final tick in ticks) _text(tick)];
    final unitLabel = _text(unit);
    final dayLabels = [for (final day in days) _text(day)];
    final row = unitLabel.height;
    final left =
        [unitLabel, ...labels].map((label) => label.width).reduce(math.max) +
        _gap;
    final top = row + 8;
    final bottom = size.height - row - 8;
    final width = size.width - left - _right;
    final span = (_pastDays + trajectoryBandDays).toDouble();
    Offset at(_Point point) => Offset(
      left + (point.day + _pastDays) / span * width,
      top + (axis.high - point.value) / (axis.high - axis.low) * (bottom - top),
    );
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    unitLabel.paint(canvas, Offset(left - _gap - unitLabel.width, 0));
    for (final (i, label) in labels.indexed) {
      final y = at((day: 0, value: axis.low + i * axis.step)).dy;
      canvas.drawLine(Offset(left, y), Offset(left + width, y), gridPaint);
      label.paint(
        canvas,
        Offset(left - _gap - label.width, y - label.height / 2),
      );
    }
    final today = at((day: 0, value: axis.low)).dx;
    canvas
      ..drawLine(Offset(today, top), Offset(today, bottom), gridPaint)
      ..drawPath(
        Path()..addPolygon([for (final p in band) at(p)], true),
        Paint()..color = line.withValues(alpha: 0.1),
      )
      ..drawPath(
        Path()..addPolygon([for (final p in firm) at(p)], true),
        Paint()..color = line.withValues(alpha: 0.18),
      );
    _dashed(canvas, [for (final p in middle) at(p)]);
    final dotPaint = Paint()..color = dot;
    for (final point in dots) {
      canvas.drawCircle(at(point), 2.4, dotPaint);
    }
    if (trend.length > 1) {
      final path = Path()..moveTo(at(trend.first).dx, at(trend.first).dy);
      for (final point in trend.skip(1)) {
        path.lineTo(at(point).dx, at(point).dy);
      }
      canvas.drawPath(path, _stroke(2.5));
    }
    final labelTop = size.height - row;
    dayLabels[0].paint(canvas, Offset(left, labelTop));
    final middleLeft = math.max(
      left + dayLabels[0].width + _gap,
      today - dayLabels[1].width / 2,
    );
    dayLabels[1].paint(canvas, Offset(middleLeft, labelTop));
    final endLeft = left + width - dayLabels[3].width;
    dayLabels[3].paint(canvas, Offset(endLeft, labelTop));
    // The 4 week date is dropped when large text leaves no room between its
    // neighbours, so labels never overlap.
    final firmLeft = math.max(
      middleLeft + dayLabels[1].width + _gap,
      at((day: trajectoryFirmDays.toDouble(), value: axis.low)).dx -
          dayLabels[2].width / 2,
    );
    if (firmLeft + dayLabels[2].width + _gap > endLeft) return;
    dayLabels[2].paint(canvas, Offset(firmLeft, labelTop));
  }

  Paint _stroke(double width) => Paint()
    ..color = line
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  void _dashed(Canvas canvas, List<Offset> points) {
    final paint = _stroke(1.5);
    for (var i = 1; i < points.length; i++) {
      final from = points[i - 1];
      final step = points[i] - from;
      final count = math.max(1, (step.distance / (2 * _dash)).floor());
      for (var k = 0; k < count; k++) {
        canvas.drawLine(
          from + step * (k / count),
          from + step * ((k + 0.5) / count),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_ScenarioPainter old) => true;
}

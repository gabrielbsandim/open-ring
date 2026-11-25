import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/features/settings/application/unit_format.dart';

enum WeightRange {
  month(30),
  quarter(90),
  all(null);

  new(this.days);

  final int? days;
}

typedef WeightAxis = ({double low, double high, double step});

typedef _Point = ({double x, double value});

const _allRangeMinDays = 7;
const _sparklineDays = 30;
const _axisSteps = [0.5, 1.0, 2.0, 5.0, 10.0, 20.0, 50.0, 100.0, 200.0];
const _axisPad = 0.15;
const _axisMaxLines = 4.2;

LocalDate weightRangeStart(
  WeightRange range, {
  required LocalDate today,
  required LocalDate first,
}) {
  final days = range.days;
  if (days != null) return today.addDays(1 - days);
  final shortest = today.addDays(1 - _allRangeMinDays);
  return first.compareTo(shortest) < 0 ? first : shortest;
}

WeightAxis weightAxis(Iterable<double> values) {
  final lowest = values.reduce(math.min);
  final highest = values.reduce(math.max);
  final spread = highest - lowest + 4 * _axisPad;
  final step = _axisSteps.firstWhere(
    (step) => spread / step <= _axisMaxLines,
    orElse: () => _axisSteps.last,
  );
  return (
    low: ((lowest - _axisPad) / step).floor() * step,
    high: ((highest + _axisPad) / step).ceil() * step,
    step: step,
  );
}

List<_Point> _placed(
  List<DailyValue> days,
  UnitFormat units, {
  required LocalDate start,
  required LocalDate today,
}) {
  final span = math.max(1, today.daysSince(start));
  return [
    for (final day in days)
      if (day.date.compareTo(start) >= 0 && day.date.compareTo(today) <= 0)
        (
          x: day.date.daysSince(start) / span,
          value: units.bodyWeightIn(day.value),
        ),
  ];
}

class WeightChart extends StatelessWidget {
  const new({
    required this.daily,
    required this.line,
    required this.today,
    required this.range,
    required this.units,
    this.band,
    super.key,
  });

  static const _height = 190.0;

  final List<DailyValue> daily;
  final List<DailyValue> line;
  final LocalDate today;
  final WeightRange range;
  final UnitFormat units;

  /// Day to day variation in kilograms. When set the chart hides every value:
  /// no axis numbers and no daily dots, only the trend inside this band.
  final double? band;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final l10n = units.l10n;
    final band = this.band;
    final margin = band == null ? null : units.bodyWeightIn(band);
    final start = weightRangeStart(
      range,
      today: today,
      first: daily.first.date,
    );
    final dots = _placed(daily, units, start: start, today: today);
    final trend = _placed(line, units, start: start, today: today);
    if (dots.isEmpty) {
      return SizedBox(
        height: _height,
        child: Center(child: BodyText(l10n.bodyChartEmpty)),
      );
    }
    final axis = weightAxis([
      if (margin == null)
        for (final point in dots) point.value,
      for (final point in trend) ...[
        point.value - (margin ?? 0),
        point.value + (margin ?? 0),
      ],
    ]);
    final digits = axis.step < 1 ? 1 : 0;
    final middle = start.addDays(today.daysSince(start) ~/ 2);
    return Semantics(
      container: true,
      image: true,
      label: margin == null
          ? l10n.bodyChartLabel(units.weightUnit)
          : l10n.bodyChartHiddenLabel,
      child: SizedBox(
        height: _height,
        width: double.infinity,
        child: CustomPaint(
          painter: _WeightPainter(
            dots: margin == null ? dots : const [],
            trend: trend,
            axis: axis,
            margin: margin,
            ticks: [
              if (margin == null)
                for (var v = axis.low; v <= axis.high + 1e-9; v += axis.step)
                  units.format.decimal(v, digits: digits),
            ],
            unit: margin == null ? units.weightUnit : '',
            days: [
              units.format.monthDay(start),
              units.format.monthDay(middle),
              l10n.bodyChartToday,
            ],
            style:
                Theme.of(context).textTheme.labelSmall
                    ?.copyWith(color: colors.textLabel) ??
                TextStyle(color: colors.textLabel),
            scaler: MediaQuery.textScalerOf(context),
            lineColor: colors.textPrimary,
            dotColor: colors.textLabel,
            grid: colors.track,
            bandColor: _bandColor(colors),
          ),
        ),
      ),
    );
  }
}

class _WeightPainter extends CustomPainter {
  const new({
    required this.dots,
    required this.trend,
    required this.axis,
    required this.margin,
    required this.ticks,
    required this.unit,
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
  static const _dotRadius = 2.6;
  static const _endRadius = 4.5;

  final List<_Point> dots;
  final List<_Point> trend;
  final WeightAxis axis;
  final double? margin;
  final List<String> ticks;
  final String unit;
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
    final unitLabel = _text(unit);
    final dayLabels = [for (final day in days) _text(day)];
    final rowHeight = unitLabel.height;
    final left =
        [unitLabel, ...labels].map((label) => label.width).reduce(math.max) +
        _gutterGap;
    final top = rowHeight + 8;
    final bottom = size.height - rowHeight - 8;
    final width = size.width - left - _right;
    double x(double fraction) => left + fraction * width;
    double y(double value) =>
        top + (axis.high - value) / (axis.high - axis.low) * (bottom - top);

    unitLabel.paint(canvas, Offset(left - _gutterGap - unitLabel.width, 0));
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var i = 0; i < labels.length; i++) {
      final at = y(axis.low + i * axis.step);
      canvas.drawLine(Offset(left, at), Offset(left + width, at), gridPaint);
      labels[i].paint(
        canvas,
        Offset(left - _gutterGap - labels[i].width, at - labels[i].height / 2),
      );
    }
    if (labels.isEmpty) {
      canvas.drawLine(
        Offset(left, bottom),
        Offset(left + width, bottom),
        gridPaint,
      );
    }
    final dotPaint = Paint()..color = dotColor;
    for (final dot in dots) {
      canvas.drawCircle(Offset(x(dot.x), y(dot.value)), _dotRadius, dotPaint);
    }
    final margin = this.margin;
    if (margin != null) {
      _paintBand(canvas, bandColor, [
        for (final point in trend) Offset(x(point.x), y(point.value + margin)),
        for (final point in trend.reversed)
          Offset(x(point.x), y(point.value - margin)),
      ]);
    }
    _paintTrend(canvas, [
      for (final point in trend) Offset(x(point.x), y(point.value)),
    ], lineColor);
    final labelTop = size.height - rowHeight;
    dayLabels[0].paint(canvas, Offset(left, labelTop));
    dayLabels[1].paint(
      canvas,
      Offset(x(0.5) - dayLabels[1].width / 2, labelTop),
    );
    dayLabels[2].paint(
      canvas,
      Offset(left + width - dayLabels[2].width, labelTop),
    );
  }

  @override
  bool shouldRepaint(_WeightPainter old) =>
      !listEquals(old.dots, dots) ||
      !listEquals(old.trend, trend) ||
      old.axis != axis ||
      old.margin != margin ||
      old.bandColor != bandColor ||
      !listEquals(old.days, days) ||
      old.unit != unit ||
      old.style != style ||
      old.scaler != scaler ||
      old.lineColor != lineColor ||
      old.dotColor != dotColor ||
      old.grid != grid;
}

Color _bandColor(AppColors colors) =>
    colors.textPrimary.withValues(alpha: 0.14);

void _paintBand(Canvas canvas, Color color, List<Offset> outline) {
  if (outline.length < 4) return;
  canvas.drawPath(Path()..addPolygon(outline, true), Paint()..color = color);
}

void _paintTrend(
  Canvas canvas,
  List<Offset> points,
  Color color, {
  double stroke = 2.5,
  double endRadius = _WeightPainter._endRadius,
}) {
  if (points.isEmpty) return;
  final path = Path()..moveTo(points.first.dx, points.first.dy);
  for (final point in points.skip(1)) {
    path.lineTo(point.dx, point.dy);
  }
  canvas
    ..drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    )
    ..drawCircle(points.last, endRadius, Paint()..color = color);
}

class WeightSparkline extends StatelessWidget {
  const new({required this.line, required this.today, this.band, super.key});

  static const _minSpread = 0.2;

  final List<DailyValue> line;
  final LocalDate today;
  final double? band;

  @override
  Widget build(BuildContext context) {
    final start = today.addDays(1 - _sparklineDays);
    final recent = [
      for (final day in line)
        if (day.date.compareTo(start) >= 0) day,
    ];
    if (recent.length < 2) return const SizedBox.shrink();
    final values = [for (final day in recent) day.value];
    final margin = band ?? 0;
    final low = values.reduce(math.min) - margin;
    final spread = math.max(_minSpread, values.reduce(math.max) + margin - low);
    final first = recent.first.date;
    final span = math.max(1, recent.last.date.daysSince(first));
    final colors = AppColors.of(context);
    return ExcludeSemantics(
      child: SizedBox(
        width: 104,
        height: 40,
        child: CustomPaint(
          painter: _SparkPainter(
            points: [
              for (final day in recent)
                (
                  x: day.date.daysSince(first) / span,
                  value: (day.value - low) / spread,
                ),
            ],
            margin: band == null ? null : margin / spread,
            color: colors.textPrimary,
            bandColor: _bandColor(colors),
          ),
        ),
      ),
    );
  }
}

class _SparkPainter extends CustomPainter {
  const new({
    required this.points,
    required this.margin,
    required this.color,
    required this.bandColor,
  });

  static const _inset = 5.0;

  final List<_Point> points;
  final double? margin;
  final Color color;
  final Color bandColor;

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width - 2 * _inset;
    final height = size.height - 2 * _inset;
    Offset at(_Point point, double shift) => Offset(
      _inset + point.x * width,
      _inset + (1 - point.value - shift) * height,
    );
    final margin = this.margin;
    if (margin != null) {
      _paintBand(canvas, bandColor, [
        for (final point in points) at(point, margin),
        for (final point in points.reversed) at(point, -margin),
      ]);
    }
    _paintTrend(
      canvas,
      [for (final point in points) at(point, 0)],
      color,
      stroke: 2,
      endRadius: 3.5,
    );
  }

  @override
  bool shouldRepaint(_SparkPainter old) =>
      !listEquals(old.points, points) ||
      old.margin != margin ||
      old.color != color ||
      old.bandColor != bandColor;
}

class WeightLegend extends StatelessWidget {
  const new({required this.trend, this.day, this.band, super.key});

  final String trend;
  final String? day;
  final String? band;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final day = this.day;
    final band = this.band;
    return Wrap(
      spacing: 16,
      runSpacing: 4,
      children: [
        _LegendItem(
          label: trend,
          mark: Container(width: 14, height: 3, color: colors.textPrimary),
        ),
        if (day != null)
          _LegendItem(
            label: day,
            mark: Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: colors.textLabel,
                shape: BoxShape.circle,
              ),
            ),
          ),
        if (band != null)
          _LegendItem(
            label: band,
            mark: Container(width: 14, height: 8, color: _bandColor(colors)),
          ),
      ],
    );
  }
}

class _LegendItem extends StatelessWidget {
  const new({required this.label, required this.mark});

  final String label;
  final Widget mark;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        mark,
        const SizedBox(width: 6),
        Flexible(child: CaptionText(label)),
      ],
    );
  }
}

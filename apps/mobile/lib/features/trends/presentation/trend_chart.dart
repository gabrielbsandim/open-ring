import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/features/trends/domain/trend_series.dart';

const _bandAlpha = 0.16;
const _pastAlpha = 0.55;

class TrendChart extends StatelessWidget {
  const new({
    required this.series,
    required this.color,
    required this.band,
    required this.semanticsLabel,
    this.height = 180,
    super.key,
  });

  final TrendSeries series;
  final Color color;
  final TrendBand? band;
  final String semanticsLabel;
  final double height;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Semantics(
      container: true,
      image: true,
      label: semanticsLabel,
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(
          painter: _TrendPainter(
            values: [for (final p in series.points) p.value],
            mean: series.mean,
            min: series.min,
            max: series.max,
            band: band,
            color: color,
            track: colors.track,
            axis: colors.strongBorder,
            extreme: colors.textLabel,
            average: colors.textPrimary,
          ),
        ),
      ),
    );
  }
}

class _TrendPainter extends CustomPainter {
  const new({
    required this.values,
    required this.mean,
    required this.min,
    required this.max,
    required this.band,
    required this.color,
    required this.track,
    required this.axis,
    required this.extreme,
    required this.average,
  });

  final List<double?> values;
  final double? mean;
  final double? min;
  final double? max;
  final TrendBand? band;
  final Color color;
  final Color track;
  final Color axis;
  final Color extreme;
  final Color average;

  static const _stub = 2.0;
  static const _minBar = 3.0;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = _Scale.of(values, band, size.height);
    final range = band;
    if (range != null) {
      canvas.drawRRect(
        RRect.fromLTRBR(
          0,
          scale.y(range.high),
          size.width,
          scale.y(range.low),
          const Radius.circular(4),
        ),
        Paint()..color = color.withValues(alpha: _bandAlpha),
      );
    }
    _paintBars(canvas, size, scale);
    canvas.drawLine(
      Offset(0, size.height - 0.5),
      Offset(size.width, size.height - 0.5),
      Paint()
        ..color = axis
        ..strokeWidth = 1,
    );
    final extremePaint = Paint()
      ..color = extreme
      ..strokeWidth = 1;
    for (final v in [min, max].whereType<double>()) {
      _dashed(canvas, size.width, scale.y(v), extremePaint, dash: 2, gap: 3);
    }
    final m = mean;
    if (m == null) return;
    _dashed(
      canvas,
      size.width,
      scale.y(m),
      Paint()
        ..color = average
        ..strokeWidth = 2,
      dash: 6,
      gap: 4,
    );
  }

  void _paintBars(Canvas canvas, Size size, _Scale scale) {
    if (values.isEmpty) return;
    final count = values.length;
    final gap = math.min(_gapFor(count), size.width / count / 2);
    final width = (size.width - gap * (count - 1)) / count;
    final radius = Radius.circular(math.min(_radiusFor(count), width / 2));
    for (var i = 0; i < count; i++) {
      final value = values[i];
      final left = i * (width + gap);
      final height = value == null
          ? _stub
          : math.max(_minBar, size.height - scale.y(value));
      final paint = Paint()
        ..color = switch (value) {
          null => track,
          _ when i == count - 1 => color,
          _ => color.withValues(alpha: _pastAlpha),
        };
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTWH(left, size.height - height, width, height),
          topLeft: radius,
          topRight: radius,
        ),
        paint,
      );
    }
  }

  static double _gapFor(int count) => switch (count) {
    <= 7 => 8,
    <= 30 => 2,
    _ => 1,
  };

  static double _radiusFor(int count) => switch (count) {
    <= 7 => 6,
    <= 30 => 2,
    _ => 1,
  };

  static void _dashed(
    Canvas canvas,
    double width,
    double y,
    Paint paint, {
    required double dash,
    required double gap,
  }) {
    for (var x = 0.0; x < width; x += dash + gap) {
      canvas.drawLine(
        Offset(x, y),
        Offset(math.min(x + dash, width), y),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_TrendPainter old) =>
      old.values != values ||
      old.mean != mean ||
      old.min != min ||
      old.max != max ||
      old.band != band ||
      old.color != color ||
      old.track != track ||
      old.axis != axis ||
      old.extreme != extreme ||
      old.average != average;
}

final class _Scale {
  const new(this.floor, this.top, this.height);

  factory of(List<double?> values, TrendBand? band, double height) {
    final points = [
      ...values.whereType<double>(),
      if (band != null) ...[band.low, band.high],
    ];
    if (points.isEmpty) return _Scale(0, 1, height);
    final low = points.reduce(math.min);
    final high = points.reduce(math.max);
    final spread = math.max(high - low, math.max(1, high.abs() * 0.05));
    return _Scale(math.max(0, low - spread * 0.5), high + spread * 0.1, height);
  }

  final double floor;
  final double top;
  final double height;

  double y(double value) => height - (value - floor) / (top - floor) * height;
}

enum LegendMark { average, extremes, band }

class LegendSwatch extends StatelessWidget {
  const new({required this.mark, required this.color, super.key});

  final LegendMark mark;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return CustomPaint(
      size: const Size(16, 10),
      painter: _SwatchPainter(
        mark: mark,
        color: switch (mark) {
          LegendMark.average => colors.textPrimary,
          LegendMark.extremes => colors.textLabel,
          LegendMark.band => color.withValues(alpha: _bandAlpha),
        },
      ),
    );
  }
}

class _SwatchPainter extends CustomPainter {
  const new({required this.mark, required this.color});

  final LegendMark mark;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    switch (mark) {
      case LegendMark.average:
        _TrendPainter._dashed(
          canvas,
          size.width,
          y,
          Paint()
            ..color = color
            ..strokeWidth = 2,
          dash: 6,
          gap: 4,
        );
      case LegendMark.extremes:
        _TrendPainter._dashed(
          canvas,
          size.width,
          y,
          Paint()
            ..color = color
            ..strokeWidth = 1,
          dash: 2,
          gap: 3,
        );
      case LegendMark.band:
        canvas.drawRRect(
          RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(3)),
          Paint()..color = color,
        );
    }
  }

  @override
  bool shouldRepaint(_SwatchPainter old) =>
      old.mark != mark || old.color != color;
}

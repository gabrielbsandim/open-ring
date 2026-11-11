import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:open_ring/app/theme/app_colors.dart';

class ProgressBar extends StatelessWidget {
  const new({
    required this.value,
    required this.color,
    this.height = 6,
    this.semanticsLabel,
    super.key,
  });

  final double value;
  final Color color;
  final double height;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final bar = SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _ProgressPainter(
          value: value.clamp(0, 1),
          color: color,
          track: AppColors.of(context).track,
        ),
      ),
    );
    final label = semanticsLabel;
    if (label == null) return ExcludeSemantics(child: bar);
    return Semantics(container: true, image: true, label: label, child: bar);
  }
}

class _ProgressPainter extends CustomPainter {
  const new({required this.value, required this.color, required this.track});

  final double value;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = Radius.circular(size.height / 2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, radius),
      Paint()..color = track,
    );
    if (value <= 0) return;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Offset.zero & Size(size.width * value, size.height),
        radius,
      ),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_ProgressPainter old) =>
      old.value != value || old.color != color || old.track != track;
}

class ScoreRing extends StatelessWidget {
  const new({
    required this.value,
    required this.caption,
    required this.color,
    required this.semanticsLabel,
    this.diameter = 112,
    super.key,
  });

  final int? value;
  final String caption;
  final Color color;
  final String semanticsLabel;
  final double diameter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final scale = MediaQuery.textScalerOf(context).scale(1);
    final score = value;
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = math.min(
          diameter * math.max(1, scale),
          constraints.maxWidth,
        );
        return Semantics(
          container: true,
          label: semanticsLabel,
          excludeSemantics: true,
          child: SizedBox.square(
            dimension: size,
            child: CustomPaint(
              painter: _RingPainter(
                progress: (score ?? 0) / 100,
                color: color,
                track: colors.track,
                stroke: size / 11,
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (score == null)
                      Icon(
                        Icons.hourglass_empty_rounded,
                        size: size / 4,
                        color: colors.textLabel,
                      ),
                    if (score != null)
                      Text(
                        '$score',
                        style: theme.textTheme.headlineLarge?.copyWith(
                          fontSize: diameter / 3.4,
                          fontWeight: FontWeight.w600,
                          color: colors.textPrimary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    Text(
                      caption,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colors.textLabel,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _RingPainter extends CustomPainter {
  const new({
    required this.progress,
    required this.color,
    required this.track,
    required this.stroke,
  });

  final double progress;
  final Color color;
  final Color track;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(stroke / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, math.pi * 2, false, paint..color = track);
    if (progress <= 0) return;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2 * progress.clamp(0, 1),
      false,
      paint..color = color,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress ||
      old.color != color ||
      old.track != track ||
      old.stroke != stroke;
}

typedef BarSegment = ({double weight, Color color});

class SegmentedBar extends StatelessWidget {
  const new({
    required this.segments,
    required this.semanticsLabel,
    this.height = 10,
    super.key,
  });

  final List<BarSegment> segments;
  final String semanticsLabel;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      image: true,
      label: semanticsLabel,
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(
          painter: _SegmentsPainter(
            segments: segments,
            track: AppColors.of(context).track,
          ),
        ),
      ),
    );
  }
}

class _SegmentsPainter extends CustomPainter {
  const new({required this.segments, required this.track});

  final List<BarSegment> segments;
  final Color track;

  static const _gap = 2.0;

  @override
  void paint(Canvas canvas, Size size) {
    final visible = segments.where((s) => s.weight > 0).toList();
    final total = visible.fold<double>(0, (sum, s) => sum + s.weight);
    final radius = Radius.circular(size.height / 2);
    canvas
      ..save()
      ..clipRRect(RRect.fromRectAndRadius(Offset.zero & size, radius));
    if (total <= 0) {
      canvas
        ..drawRect(Offset.zero & size, Paint()..color = track)
        ..restore();
      return;
    }
    final usable = size.width - _gap * (visible.length - 1);
    var x = 0.0;
    for (final s in visible) {
      final width = usable * s.weight / total;
      canvas.drawRect(
        Rect.fromLTWH(x, 0, width, size.height),
        Paint()..color = s.color,
      );
      x += width + _gap;
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SegmentsPainter old) =>
      old.segments != segments || old.track != track;
}

class HourlyBars extends StatelessWidget {
  const new({
    required this.values,
    required this.color,
    required this.semanticsLabel,
    this.height = 130,
    super.key,
  });

  final List<double?> values;
  final Color color;
  final String semanticsLabel;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      image: true,
      label: semanticsLabel,
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(
          painter: _HourlyBarsPainter(
            values: values,
            color: color,
            track: AppColors.of(context).track,
          ),
        ),
      ),
    );
  }
}

class _HourlyBarsPainter extends CustomPainter {
  const new({required this.values, required this.color, required this.track});

  final List<double?> values;
  final Color color;
  final Color track;

  static const _gap = 3.0;
  static const _stub = 2.0;
  static const _minBar = 4.0;

  @override
  void paint(Canvas canvas, Size size) {
    final present = values.whereType<double>().toList();
    canvas.drawLine(
      Offset(0, size.height - 0.5),
      Offset(size.width, size.height - 0.5),
      Paint()
        ..color = track
        ..strokeWidth = 1,
    );
    if (values.isEmpty) return;
    final high = present.isEmpty ? 1.0 : present.reduce(math.max);
    final low = present.isEmpty ? 0.0 : present.reduce(math.min);
    final floor = math.max(0, low - (high - low) * 0.5 - 1);
    final span = math.max(high - floor, 1);
    final barWidth = (size.width - _gap * (values.length - 1)) / values.length;
    final radius = Radius.circular(math.min(3, barWidth / 2));
    for (var i = 0; i < values.length; i++) {
      final value = values[i];
      final barHeight = value == null
          ? _stub
          : math.max(_minBar, (value - floor) / span * (size.height - 1));
      final left = i * (barWidth + _gap);
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTWH(left, size.height - barHeight, barWidth, barHeight),
          topLeft: radius,
          topRight: radius,
        ),
        Paint()..color = value == null ? track : color,
      );
    }
  }

  @override
  bool shouldRepaint(_HourlyBarsPainter old) =>
      old.values != values || old.color != color || old.track != track;
}

class TimeAxis extends StatelessWidget {
  const new({required this.labels, super.key});

  final List<String> labels;

  static const _labelGap = 12.0;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: AppColors.of(context).textLabel,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final widest = labels.fold<double>(0, (widest, label) {
          final painter = TextPainter(
            text: TextSpan(text: label, style: style),
            textDirection: direction,
            textScaler: scaler,
          )..layout();
          final width = painter.width;
          painter.dispose();
          return math.max(widest, width);
        });
        var step = 1;
        while (step < labels.length &&
            _needed(step, widest) > constraints.maxWidth) {
          step *= 2;
        }
        final shown = [for (var i = 0; i < labels.length; i += step) labels[i]];
        return ExcludeSemantics(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final label in shown)
                Flexible(child: Text(label, style: style)),
            ],
          ),
        );
      },
    );
  }

  double _needed(int step, double widest) =>
      ((labels.length - 1) ~/ step + 1) * (widest + _labelGap);
}

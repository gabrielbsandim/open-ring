import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:open_ring/app/theme/app_colors.dart';

class HourlyStepsChart extends StatelessWidget {
  const new({
    required this.steps,
    required this.color,
    required this.semanticsLabel,
    this.height = 100,
    super.key,
  });

  final List<int?> steps;
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
          painter: HourlyStepsPainter(
            steps: steps,
            color: color,
            track: AppColors.of(context).track,
          ),
        ),
      ),
    );
  }
}

class HourlyStepsPainter extends CustomPainter {
  const new({required this.steps, required this.color, required this.track});

  final List<int?> steps;
  final Color color;
  final Color track;

  static const _gap = 3.0;
  static const _stub = 2.0;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawLine(
      Offset(0, size.height - 0.5),
      Offset(size.width, size.height - 0.5),
      Paint()
        ..color = track
        ..strokeWidth = 1,
    );
    if (steps.isEmpty) return;
    final high = steps.fold<int>(0, (high, s) => math.max(high, s ?? 0));
    final barWidth = (size.width - _gap * (steps.length - 1)) / steps.length;
    final radius = Radius.circular(math.min(3, barWidth / 2));
    for (var i = 0; i < steps.length; i++) {
      final value = steps[i] ?? 0;
      final active = value > 0 && high > 0;
      final barHeight = active
          ? math.max(_stub, value / high * (size.height - 1))
          : _stub;
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTWH(
            i * (barWidth + _gap),
            size.height - barHeight,
            barWidth,
            barHeight,
          ),
          topLeft: radius,
          topRight: radius,
        ),
        Paint()..color = active ? color : track,
      );
    }
  }

  @override
  bool shouldRepaint(HourlyStepsPainter old) =>
      old.steps != steps || old.color != color || old.track != track;
}

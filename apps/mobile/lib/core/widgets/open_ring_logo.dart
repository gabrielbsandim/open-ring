import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:open_ring/app/theme/app_colors.dart';

class OpenRingLogo extends StatelessWidget {
  const new({this.size = 28, super.key});

  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return ExcludeSemantics(
      child: CustomPaint(
        size: Size.square(size),
        painter: _OpenRingLogoPainter(
          band: colors.textPrimary,
          dot: colors.sleep,
        ),
      ),
    );
  }
}

class OpenRingMark extends StatelessWidget {
  const new({required this.color, this.size = 24, super.key});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: CustomPaint(
        size: Size.square(size),
        painter: _OpenRingLogoPainter(band: color, dot: color),
      ),
    );
  }
}

class _OpenRingLogoPainter extends CustomPainter {
  const new({required this.band, required this.dot});

  final Color band;
  final Color dot;

  static double _radians(double degrees) => degrees * math.pi / 180;

  @override
  void paint(Canvas canvas, Size size) {
    final unit = size.width / 54;
    final center = size.center(Offset.zero);
    final stroke = Paint()
      ..color = band
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 10 * unit;
    canvas
      ..drawArc(
        Rect.fromCircle(center: center, radius: 22 * unit),
        _radians(-10),
        _radians(290),
        false,
        stroke,
      )
      ..drawCircle(
        center + Offset.fromDirection(_radians(-45), 22 * unit),
        4.5 * unit,
        Paint()..color = dot,
      );
  }

  @override
  bool shouldRepaint(_OpenRingLogoPainter oldDelegate) =>
      oldDelegate.band != band || oldDelegate.dot != dot;
}

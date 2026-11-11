import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/features/workout/domain/workout_route.dart';

const routeMapHeight = 160.0;
const _minSpanMeters = 60.0;
const _gridStep = 32.0;

List<List<Offset>> projectRoute(
  List<List<TrackPoint>> segments,
  Size size, {
  double padding = 16,
}) {
  final points = segments.expand((segment) => segment).toList();
  if (points.isEmpty) return const [];
  final latitude =
      points.map((p) => p.latitude).reduce((a, b) => a + b) / points.length;
  const metersPerDegree = earthMeanRadiusMeters * math.pi / 180;
  final eastScale = math.cos(latitude * math.pi / 180) * metersPerDegree;
  Offset local(TrackPoint p) =>
      Offset(p.longitude * eastScale, -p.latitude * metersPerDegree);
  final projected = [
    for (final segment in segments) [for (final p in segment) local(p)],
  ];
  final all = projected.expand((segment) => segment);
  final left = all.map((o) => o.dx).reduce(math.min);
  final right = all.map((o) => o.dx).reduce(math.max);
  final top = all.map((o) => o.dy).reduce(math.min);
  final bottom = all.map((o) => o.dy).reduce(math.max);
  final width = math.max(right - left, _minSpanMeters);
  final height = math.max(bottom - top, _minSpanMeters);
  final usable = Size(
    math.max(size.width - padding * 2, 1),
    math.max(size.height - padding * 2, 1),
  );
  final scale = math.min(usable.width / width, usable.height / height);
  final centre = Offset((left + right) / 2, (top + bottom) / 2);
  final middle = size.center(Offset.zero);
  return [
    for (final segment in projected)
      [for (final o in segment) middle + (o - centre) * scale],
  ];
}

class RouteMap extends StatelessWidget {
  const new({
    required this.segments,
    required this.semanticsLabel,
    this.live = false,
    super.key,
  });

  final List<List<TrackPoint>> segments;
  final String semanticsLabel;
  final bool live;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Semantics(
      container: true,
      image: true,
      label: semanticsLabel,
      child: SizedBox(
        height: routeMapHeight,
        width: double.infinity,
        child: CustomPaint(
          painter: RoutePainter(
            segments: segments,
            live: live,
            route: colors.activity,
            ground: colors.surfaceInner,
            grid: colors.surfaceBorder,
            halo: colors.activity.withValues(alpha: 0.18),
            marker: colors.textPrimary,
            outline: colors.background,
          ),
        ),
      ),
    );
  }
}

class RoutePainter extends CustomPainter {
  const new({
    required this.segments,
    required this.live,
    required this.route,
    required this.ground,
    required this.grid,
    required this.halo,
    required this.marker,
    required this.outline,
  });

  final List<List<TrackPoint>> segments;
  final bool live;
  final Color route;
  final Color ground;
  final Color grid;
  final Color halo;
  final Color marker;
  final Color outline;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = ground);
    _paintGrid(canvas, size);
    final lines = projectRoute(segments, size);
    if (lines.isEmpty) return;
    final stroke = Paint()
      ..color = route
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (final line in lines) {
      final path = Path()..moveTo(line.first.dx, line.first.dy);
      for (final point in line.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(path, stroke);
    }
    _paintStart(canvas, lines.first.first);
    final end = lines.last.last;
    if (live) {
      _paintPosition(canvas, end);
      return;
    }
    _paintEnd(canvas, end);
  }

  void _paintGrid(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var x = _gridStep; x < size.width; x += _gridStep) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = _gridStep; y < size.height; y += _gridStep) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  void _paintStart(Canvas canvas, Offset at) {
    canvas
      ..drawCircle(at, 5, Paint()..color = outline)
      ..drawCircle(
        at,
        5,
        Paint()
          ..color = route
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );
  }

  void _paintEnd(Canvas canvas, Offset at) {
    final square = RRect.fromRectAndRadius(
      Rect.fromCenter(center: at, width: 12, height: 12),
      const Radius.circular(2),
    );
    canvas
      ..drawRRect(square, Paint()..color = marker)
      ..drawRRect(
        square,
        Paint()
          ..color = outline
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
  }

  void _paintPosition(Canvas canvas, Offset at) {
    canvas
      ..drawCircle(at, 11, Paint()..color = halo)
      ..drawCircle(at, 5.5, Paint()..color = route)
      ..drawCircle(
        at,
        5.5,
        Paint()
          ..color = outline
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
  }

  @override
  bool shouldRepaint(RoutePainter old) =>
      !identical(old.segments, segments) ||
      old.live != live ||
      old.route != route ||
      old.ground != ground ||
      old.grid != grid ||
      old.halo != halo ||
      old.marker != marker ||
      old.outline != outline;
}

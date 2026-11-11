import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/workout/domain/workout_route.dart';
import 'package:open_ring/features/workout/presentation/route_map.dart';

import '../../../helpers/workout_fakes.dart';

TrackPoint _at(double north, double east) => TrackPoint(
  at: workoutStart,
  latitude: north / metersPerDegreeLatitude,
  longitude: east / metersPerDegreeLatitude,
);

void main() {
  const size = Size(320, 160);

  test('an empty route projects to nothing', () {
    expect(projectRoute(const [], size), isEmpty);
  });

  test('the route fits inside the padding and keeps its aspect', () {
    final lines = projectRoute([
      [_at(0, 0), _at(1000, 0)],
      [_at(1000, 500)],
    ], size);

    expect(lines, hasLength(2));
    final points = lines.expand((line) => line).toList();
    for (final point in points) {
      expect(point.dx, inInclusiveRange(16, size.width - 16));
      expect(point.dy, inInclusiveRange(16, size.height - 16));
    }
    final start = lines.first.first;
    final north = lines.first.last;
    final east = lines.last.single;
    expect(north.dy, lessThan(start.dy));
    expect(start.dy - north.dy, closeTo(128, 0.01));
    expect(east.dx - north.dx, closeTo(64, 0.5));
  });

  test('a single point sits in the middle', () {
    final lines = projectRoute([
      [_at(10, 10)],
    ], size);

    expect(lines.single.single, const Offset(160, 80));
  });
}

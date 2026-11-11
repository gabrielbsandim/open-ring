import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/workout/domain/workout_route.dart';

TrackPoint point(int second, double latitude, double longitude) => TrackPoint(
  at: DateTime.utc(2026, 11, 10, 7, 0, second),
  latitude: latitude,
  longitude: longitude,
);

void main() {
  test('haversine matches known distances', () {
    expect(
      haversineMeters(point(0, 0, 0), point(1, 1, 0)),
      closeTo(111195.08, 0.01),
    );
    expect(
      haversineMeters(point(0, 0, 179.5), point(1, 0, -179.5)),
      closeTo(111195.08, 0.01),
    );
    final paris = point(0, 48.8566, 2.3522);
    final london = point(1, 51.5074, -0.1278);
    expect(haversineMeters(paris, london), closeTo(343560, 500));
    expect(haversineMeters(paris, paris), 0);
  });

  test('route distance adds segments and skips the gaps between them', () {
    final route = WorkoutRoute(
      segments: [
        [point(0, 0, 0), point(1, 0.001, 0)],
        [point(5, 1, 0), point(6, 1.001, 0)],
      ],
    );

    expect(route.distanceMeters, closeTo(2 * 111.195, 0.001));
    expect(route.points, hasLength(4));
  });

  test('a track point keeps its accuracy and validates coordinates', () {
    final tracked = TrackPoint(
      at: DateTime.utc(2026),
      latitude: 1,
      longitude: 2,
      accuracyMeters: 4.5,
    );

    expect(tracked.accuracyMeters, 4.5);
    expect(TrackPoint.validLatitude(double.nan), isFalse);
    expect(TrackPoint.validLongitude(180), isFalse);
  });
}

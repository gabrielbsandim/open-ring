import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/features/settings/domain/unit_system.dart';
import 'package:open_ring/features/workout/domain/workout_analysis.dart';
import 'package:open_ring/features/workout/domain/workout_route.dart';
import 'package:open_ring/features/workout/domain/workout_session.dart';
import 'package:open_ring/features/workout/domain/workout_type.dart';

import '../../../helpers/workout_fakes.dart';

DateTime at(int seconds) => workoutStart.add(Duration(seconds: seconds));

TrackPoint point(int seconds, double northMeters, {double? elevation}) {
  final fix = fixAt(Duration(seconds: seconds), northMeters: northMeters);
  return TrackPoint(
    at: fix.at,
    latitude: fix.latitude,
    longitude: fix.longitude,
    elevationMeters: elevation,
    accuracyMeters: 5,
  );
}

FinishedWorkout workoutOf(
  List<List<TrackPoint>> segments, {
  List<BpmSample> heartRate = const [],
  List<WorkoutPause> pauses = const [],
  int endSeconds = 0,
}) {
  final route = WorkoutRoute(segments: segments);
  final last = route.points.lastOrNull?.at ?? workoutStart;
  return FinishedWorkout(
    type: WorkoutType.running,
    start: workoutStart,
    end: endSeconds > 0 ? at(endSeconds) : last,
    elapsed: last.difference(workoutStart),
    heartRate: heartRate,
    route: route,
    pauses: pauses,
    distanceMeters: route.distanceMeters,
  );
}

void main() {
  group('segmentsAtPauses', () {
    test('a fix at or after a pause end opens a new segment', () {
      final segments = segmentsAtPauses(
        [point(30, 90), point(0, 0), point(10, 30), point(25, 60)],
        [
          WorkoutPause(start: at(12), end: at(25)),
          WorkoutPause(start: at(26), end: at(28)),
        ],
      );

      expect(
        WorkoutRoute(segments: segments).segments
            .map((segment) => [for (final p in segment) p.at]),
        [
          [at(0), at(10)],
          [at(25)],
          [at(30)],
        ],
      );
    });

    test('without pauses all fixes stay in one segment', () {
      final segments = segmentsAtPauses([point(0, 0), point(5, 15)], const []);

      expect(segments, hasLength(1));
      expect(segments.single, hasLength(2));
    });
  });

  group('distanceSplits', () {
    test('cuts whole km with interpolated time and keeps the remainder', () {
      final workout = workoutOf([
        [for (var s = 0; s <= 500; s += 10) point(s, s * 5.0)],
      ]);

      final splits = distanceSplits(workout);

      expect(splits.map((s) => s.number), [1, 2, 3]);
      expect(splits[0].distanceMeters, kilometreSplitMeters);
      expect(splits[0].movingTime.inMilliseconds, closeTo(200000, 50));
      expect(splits[1].movingTime.inMilliseconds, closeTo(200000, 50));
      expect(splits[2].partial, isTrue);
      expect(splits[2].distanceMeters, closeTo(500, 0.5));
      expect(splits[2].pace.inMilliseconds, closeTo(200000, 100));
    });

    test('cuts whole miles when the split length is a mile', () {
      final workout = workoutOf([
        [for (var s = 0; s <= 500; s += 10) point(s, s * 5.0)],
      ]);

      final splits = distanceSplits(
        workout,
        splitMeters: ImperialUnits.metersPerMile,
      );

      expect(splits.map((s) => s.number), [1, 2]);
      expect(splits[0].distanceMeters, ImperialUnits.metersPerMile);
      expect(splits[0].partial, isFalse);
      expect(splits[0].movingTime.inMilliseconds, closeTo(321869, 50));
      expect(splits[1].partial, isTrue);
      expect(splits[1].distanceMeters, closeTo(890.656, 0.5));
      expect(splits[1].pace.inMilliseconds, closeTo(200000, 100));
    });

    test('a pause between segments adds neither time nor distance', () {
      final workout = workoutOf(
        [
          [for (var s = 0; s <= 100; s += 10) point(s, s * 5.0)],
          [for (var s = 400; s <= 500; s += 10) point(s, 500 + (s - 400) * 5)],
        ],
        pauses: [WorkoutPause(start: at(100), end: at(400))],
      );

      final splits = distanceSplits(workout);

      expect(splits, hasLength(1));
      expect(splits.single.movingTime.inMilliseconds, closeTo(200000, 50));
    });

    test('averages the HR samples inside each split', () {
      final workout = workoutOf(
        [
          [for (var s = 0; s <= 400; s += 10) point(s, s * 5.0)],
        ],
        heartRate: [
          for (var s = 0; s < 400; s++) (at: at(s), bpm: s < 200 ? 120 : 160),
        ],
      );

      expect(distanceSplits(workout).map((s) => s.averageHeartRate), [
        120,
        160,
      ]);
    });

    test('drops a remainder shorter than the minimum', () {
      final workout = workoutOf([
        [point(0, 0), point(200, 1000), point(206, 1030)],
      ]);

      expect(distanceSplits(workout), hasLength(1));
    });

    test('no route gives no splits', () {
      expect(distanceSplits(workoutOf(const [])), isEmpty);
    });
  });

  group('elevationGainMeters', () {
    test('ignores rises below the hysteresis and sums real climbs', () {
      final route = WorkoutRoute(
        segments: [
          [
            point(0, 0, elevation: 100),
            point(1, 3, elevation: 102),
            point(2, 6, elevation: 100),
            point(3, 9, elevation: 104),
            point(4, 12, elevation: 110),
            point(5, 15, elevation: 108),
          ],
        ],
      );

      expect(elevationGainMeters(route), closeTo(10, 1e-9));
    });

    test('a pause does not count the change across it', () {
      final route = WorkoutRoute(
        segments: [
          [point(0, 0, elevation: 100), point(1, 3, elevation: 100)],
          [point(50, 6, elevation: 150), point(51, 9, elevation: 150)],
        ],
      );

      expect(elevationGainMeters(route), 0);
    });

    test('is null without two fixes that carry an altitude', () {
      final route = WorkoutRoute(
        segments: [
          [point(0, 0, elevation: 100), point(1, 3)],
        ],
      );

      expect(elevationGainMeters(route), isNull);
    });
  });

  group('gpxRouteOf', () {
    test('attaches the latest HR sample at most 10 s old to each point', () {
      final workout = workoutOf(
        [
          [point(0, 0), point(5, 15), point(30, 90)],
        ],
        heartRate: [(at: at(1), bpm: 120), (at: at(4), bpm: 125)],
      );

      final route = gpxRouteOf(workout, name: 'Morning run');

      expect(route.name, 'Morning run');
      expect(route.activityType, 'running');
      expect(route.points.map((p) => p.heartRateBpm), [null, 125, null]);
    });

    test('keeps the segments of the workout', () {
      final workout = workoutOf([
        [point(0, 0)],
        [point(20, 10)],
      ]);

      expect(gpxRouteOf(workout).segments, hasLength(2));
    });
  });

  test('pausedTime sums every pause', () {
    expect(
      pausedTime([
        WorkoutPause(start: at(0), end: at(30)),
        WorkoutPause(start: at(60), end: at(75)),
      ]),
      const Duration(seconds: 45),
    );
  });
}

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/features/open_score/domain/fitness_efforts.dart';
import 'package:open_ring/features/workout/domain/workout_history.dart';
import 'package:open_ring/features/workout/domain/workout_route.dart';
import 'package:open_ring/features/workout/domain/workout_session.dart';
import 'package:open_ring/features/workout/domain/workout_type.dart';

final start = DateTime.utc(2026, 11, 10, 7);

DateTime at(int seconds) => start.add(Duration(seconds: seconds));

const double metersPerDegree = earthMeanRadiusMeters * math.pi / 180;

// One point every 5 seconds, moving north at [speed] meters per second.
List<TrackPoint> track(int from, int to, {double speed = 3}) => [
  for (var s = from; s <= to; s += 5)
    TrackPoint(at: at(s), latitude: speed * s / metersPerDegree, longitude: 0),
];

List<BpmSample> beats(int from, int to, {int bpm = 150, int every = 10}) => [
  for (var s = from; s <= to; s += every) (at: at(s), bpm: bpm),
];

SavedWorkout saved({
  required List<List<TrackPoint>> segments,
  required List<BpmSample> heartRate,
  WorkoutType type = WorkoutType.running,
  DateTime? startedAt,
  Duration utcOffset = Duration.zero,
}) => SavedWorkout(
  id: 1,
  utcOffset: utcOffset,
  workout: FinishedWorkout(
    type: type,
    start: startedAt ?? start,
    end: at(3600),
    elapsed: const Duration(hours: 1),
    distanceMeters: 1000,
    heartRate: heartRate,
    pauses: const [],
    route: WorkoutRoute(segments: segments),
  ),
);

void main() {
  test('a stretch loses its first 3 minutes and keeps the rest', () {
    final effort = fitnessEffortOf(
      saved(
        segments: [track(0, 1200)],
        heartRate: [...beats(0, 170, bpm: 110), ...beats(180, 1200)],
      ),
    )!;

    final stretch = effort.stretches.single;
    expect(effort.gait, FitnessGait.run);
    expect(effort.date, const LocalDate(2026, 11, 10));
    expect(stretch.duration, const Duration(minutes: 17));
    expect(stretch.meters, closeTo(3 * 17 * 60, 0.01));
    expect(stretch.meanBpm, 150);
  });

  test('each pause free segment is its own stretch', () {
    final effort = fitnessEffortOf(
      saved(
        segments: [track(0, 900), track(1000, 1900, speed: 2)],
        heartRate: beats(0, 1900),
      ),
    )!;

    expect(effort.stretches, hasLength(2));
    expect(effort.stretches.last.duration, const Duration(minutes: 12));
    expect(effort.stretches.last.meters, closeTo(2 * 12 * 60, 0.01));
  });

  test('a walk is a walk and other types give nothing', () {
    FitnessEffort? of(WorkoutType type) => fitnessEffortOf(
      saved(segments: [track(0, 1200)], heartRate: beats(0, 1200), type: type),
    );

    expect(of(WorkoutType.walking)!.gait, FitnessGait.walk);
    expect(of(WorkoutType.hiking), isNull);
    expect(of(WorkoutType.cycling), isNull);
    expect(of(WorkoutType.treadmill), isNull);
  });

  test('a segment that ends inside the first 3 minutes gives nothing', () {
    expect(
      fitnessEffortOf(
        saved(segments: [track(0, 180)], heartRate: beats(0, 180)),
      ),
      isNull,
    );
  });

  test('a stretch without heart rate is dropped', () {
    expect(
      fitnessEffortOf(
        saved(segments: [track(0, 1200)], heartRate: beats(0, 170)),
      ),
      isNull,
    );
  });

  test('a stretch with under one sample a minute is dropped', () {
    FitnessEffort? of(int every) => fitnessEffortOf(
      saved(
        segments: [track(0, 1200)],
        heartRate: beats(180, 1200, every: every),
      ),
    );

    expect(of(120), isNull);
    expect(of(60), isNotNull);
  });

  test('the date is the local day the workout started on', () {
    final effort = fitnessEffortOf(
      saved(
        segments: [track(0, 1200)],
        heartRate: beats(0, 1200),
        startedAt: DateTime.utc(2026, 11, 10, 1),
        utcOffset: const Duration(hours: -3),
      ),
    )!;

    expect(effort.date, const LocalDate(2026, 11, 9));
  });
}

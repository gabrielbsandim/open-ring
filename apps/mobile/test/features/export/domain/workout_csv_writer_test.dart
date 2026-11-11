import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/features/export/domain/workout_csv_writer.dart';
import 'package:open_ring/features/workout/domain/workout_route.dart';
import 'package:open_ring/features/workout/domain/workout_session.dart';
import 'package:open_ring/features/workout/domain/workout_type.dart';

final _start = DateTime.utc(2026, 11, 10, 12);

DateTime _at(int seconds) => _start.add(Duration(seconds: seconds));

FinishedWorkout _workout({
  List<BpmSample> heartRate = const [],
  List<TrackPoint> points = const [],
}) => FinishedWorkout(
  type: WorkoutType.running,
  start: _start,
  end: _at(60),
  elapsed: const Duration(minutes: 1),
  heartRate: heartRate,
  route: WorkoutRoute(segments: [points]),
  pauses: const [],
);

String _csv(FinishedWorkout workout, {Duration offset = Duration.zero}) {
  final buffer = StringBuffer();
  writeWorkoutCsv(workout, buffer, offset: offset);
  return buffer.toString();
}

const _header = 'time,bpm,latitude,longitude,elevation_m,accuracy_m\r\n';

void main() {
  test('a workout with no series is only the header', () {
    expect(_csv(_workout()), _header);
  });

  test('merges heart rate and route by instant without filling gaps', () {
    final csv = _csv(
      _workout(
        heartRate: [(at: _at(0), bpm: 120), (at: _at(2), bpm: 125)],
        points: [
          TrackPoint(
            at: _at(0),
            latitude: -23.5505199,
            longitude: -46.6333094,
            elevationMeters: 760.5,
            accuracyMeters: 4,
          ),
          TrackPoint(at: _at(1), latitude: 1, longitude: 2),
        ],
      ),
      offset: const Duration(hours: -3),
    );

    expect(
      csv,
      '$_header'
      '2026-11-10T09:00:00-03:00,120,-23.5505199,-46.6333094,760.5,4\r\n'
      '2026-11-10T09:00:01-03:00,,1,2,,\r\n'
      '2026-11-10T09:00:02-03:00,125,,,,\r\n',
    );
  });

  test('a track point keeps its own heart rate when no sample matches', () {
    final csv = _csv(
      _workout(
        points: [
          TrackPoint(at: _at(0), latitude: 1, longitude: 2, heartRateBpm: 90),
        ],
      ),
    );

    expect(csv, '${_header}2026-11-10T12:00:00+00:00,90,1,2,,\r\n');
  });
}

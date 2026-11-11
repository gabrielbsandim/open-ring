import 'package:meta/meta.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/features/workout/domain/workout_route.dart';
import 'package:open_ring/features/workout/domain/workout_session.dart';

const kilometreSplitMeters = 1000.0;
const minLastSplitMeters = 50.0;
const elevationHysteresisMeters = 3.0;

@immutable
final class WorkoutSplit {
  const new({
    required this.number,
    required this.distanceMeters,
    required this.movingTime,
    this.splitMeters = kilometreSplitMeters,
    this.averageHeartRate,
  });

  final int number;
  final double distanceMeters;
  final Duration movingTime;
  final double splitMeters;
  final int? averageHeartRate;

  bool get partial => distanceMeters < splitMeters;

  Duration get pace => Duration(
    microseconds: (movingTime.inMicroseconds * 1000 / distanceMeters).round(),
  );
}

List<List<TrackPoint>> segmentsAtPauses(
  Iterable<TrackPoint> points,
  Iterable<WorkoutPause> pauses,
) {
  final ends = [for (final pause in pauses) pause.end]..sort();
  final sorted = points.toList()..sort((a, b) => a.at.compareTo(b.at));
  final segments = <List<TrackPoint>>[[]];
  var next = 0;
  for (final point in sorted) {
    var crossed = false;
    while (next < ends.length && !point.at.isBefore(ends[next])) {
      next++;
      crossed = true;
    }
    if (crossed) segments.add([]);
    segments.last.add(point);
  }
  return segments;
}

WorkoutRoute gpxRouteOf(FinishedWorkout workout, {String? name}) {
  final samples = workout.heartRate.toList()
    ..sort((a, b) => a.at.compareTo(b.at));
  var index = 0;
  int? bpmAt(DateTime at) {
    while (index + 1 < samples.length && !samples[index + 1].at.isAfter(at)) {
      index++;
    }
    if (samples.isEmpty || samples[index].at.isAfter(at)) return null;
    if (at.difference(samples[index].at) > liveSampleMaxHold) return null;
    return samples[index].bpm;
  }

  return WorkoutRoute(
    name: name,
    activityType: workout.type.activityType,
    segments: [
      for (final segment in workout.route.segments)
        [
          for (final point in segment)
            TrackPoint(
              at: point.at,
              latitude: point.latitude,
              longitude: point.longitude,
              elevationMeters: point.elevationMeters,
              accuracyMeters: point.accuracyMeters,
              heartRateBpm: point.heartRateBpm ?? bpmAt(point.at),
            ),
        ],
    ],
  );
}

List<WorkoutSplit> distanceSplits(
  FinishedWorkout workout, {
  double splitMeters = kilometreSplitMeters,
}) {
  final splits = <WorkoutSplit>[];
  var covered = 0.0;
  var micros = 0.0;
  var from = workout.start;
  void close(double meters, DateTime until) {
    splits.add(
      WorkoutSplit(
        number: splits.length + 1,
        distanceMeters: meters,
        movingTime: Duration(microseconds: micros.round()),
        splitMeters: splitMeters,
        averageHeartRate: _averageBpm(workout.heartRate, from, until),
      ),
    );
    from = until;
    covered = 0;
    micros = 0;
  }

  for (final segment in workout.route.segments) {
    for (var i = 1; i < segment.length; i++) {
      var meters = haversineMeters(segment[i - 1], segment[i]);
      var span = segment[i].at
          .difference(segment[i - 1].at)
          .inMicroseconds
          .toDouble();
      var at = segment[i - 1].at;
      while (meters > 0 && covered + meters >= splitMeters) {
        final needed = splitMeters - covered;
        final part = span * needed / meters;
        at = at.add(Duration(microseconds: part.round()));
        micros += part;
        close(splitMeters, at);
        meters -= needed;
        span -= part;
      }
      covered += meters;
      micros += span;
    }
  }
  if (covered >= minLastSplitMeters) close(covered, workout.end);
  return splits;
}

int? _averageBpm(List<BpmSample> samples, DateTime from, DateTime until) {
  final inside = [
    for (final sample in samples)
      if (!sample.at.isBefore(from) && sample.at.isBefore(until)) sample.bpm,
  ];
  if (inside.isEmpty) return null;
  return (inside.reduce((a, b) => a + b) / inside.length).round();
}

double? elevationGainMeters(WorkoutRoute route) {
  var gain = 0.0;
  var known = 0;
  for (final segment in route.segments) {
    double? reference;
    for (final point in segment) {
      final elevation = point.elevationMeters;
      if (elevation == null || !elevation.isFinite) continue;
      known++;
      final base = reference;
      if (base == null || elevation < base) {
        reference = elevation;
        continue;
      }
      if (elevation - base < elevationHysteresisMeters) continue;
      gain += elevation - base;
      reference = elevation;
    }
  }
  return known < 2 ? null : gain;
}

Duration pausedTime(Iterable<WorkoutPause> pauses) =>
    pauses.fold(Duration.zero, (total, pause) => total + pause.duration);

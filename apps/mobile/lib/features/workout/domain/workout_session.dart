import 'package:meta/meta.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/features/workout/domain/location_fix.dart';
import 'package:open_ring/features/workout/domain/workout_route.dart';
import 'package:open_ring/features/workout/domain/workout_type.dart';

const maxFixAccuracyMeters = 25.0;
const maxPlausibleSpeedMetersPerSecond = 12.0;
const currentPaceWindow = Duration(seconds: 30);
const minPaceDistanceMeters = 5.0;
const minWorkoutHeartRate = 30;
const maxWorkoutHeartRate = 220;

enum WorkoutStatus { idle, running, paused, finished, discarded }

enum FixVerdict {
  accepted,
  notRunning,
  invalid,
  inaccurate,
  outOfOrder,
  tooFast,
}

@immutable
final class WorkoutProfile {
  const new({this.zones, this.weightKilograms});

  final HeartRateZones? zones;
  final double? weightKilograms;
}

@immutable
final class WorkoutPause {
  const new({required this.start, required this.end});

  final DateTime start;
  final DateTime end;

  Duration get duration => end.difference(start);
}

@immutable
final class WorkoutSnapshot {
  const new({
    required this.type,
    required this.status,
    required this.elapsed,
    this.gps = false,
    this.start,
    this.end,
    this.distanceMeters,
    this.currentPace,
    this.averagePace,
    this.currentHeartRate,
    this.averageHeartRate,
    this.maxHeartRate,
    this.currentZone,
    this.activeKilocalories,
    this.heartRateSamples = 0,
    this.trackPoints = 0,
  });

  final WorkoutType type;
  final WorkoutStatus status;
  final bool gps;
  final DateTime? start;
  final DateTime? end;
  final Duration elapsed;
  final double? distanceMeters;
  final Duration? currentPace;
  final Duration? averagePace;
  final int? currentHeartRate;
  final int? averageHeartRate;
  final int? maxHeartRate;
  final int? currentZone;
  final double? activeKilocalories;
  final int heartRateSamples;
  final int trackPoints;
}

@immutable
final class FinishedWorkout {
  new({
    required this.type,
    required this.start,
    required this.end,
    required this.elapsed,
    required List<BpmSample> heartRate,
    required this.route,
    required List<WorkoutPause> pauses,
    this.distanceMeters,
    this.activeKilocalories,
    this.averageHeartRate,
    this.maxHeartRate,
  }) : heartRate = List.unmodifiable(heartRate),
       pauses = List.unmodifiable(pauses);

  final WorkoutType type;
  final DateTime start;
  final DateTime end;
  final Duration elapsed;
  final double? distanceMeters;
  final double? activeKilocalories;
  final int? averageHeartRate;
  final int? maxHeartRate;
  final List<BpmSample> heartRate;
  final WorkoutRoute route;
  final List<WorkoutPause> pauses;

  bool get gps => distanceMeters != null;
}

final class _Tracked {
  const new(this.point, this.distance, this.moving);

  final TrackPoint point;
  final double distance;
  final Duration moving;
}

final class WorkoutSession {
  new({
    required this.type,
    this.profile = const WorkoutProfile(),
    bool? gps,
    this.heartRateHold = liveSampleMaxHold,
  }) : gps = type.allowsGps(requested: gps ?? type.gpsByDefault);

  final WorkoutType type;
  final WorkoutProfile profile;
  final bool gps;
  final Duration heartRateHold;
  DateTime? heartRateLinkStart;

  WorkoutStatus _status = WorkoutStatus.idle;
  DateTime? _start;
  DateTime? _end;
  DateTime? _pausedAt;
  DateTime? _lastEvent;
  Duration _paused = Duration.zero;
  double _distance = 0;
  int _heartRateSum = 0;
  int? _maxHeartRate;
  final _pauses = <WorkoutPause>[];
  final _heartRate = <BpmSample>[];
  final _segments = <List<_Tracked>>[];

  WorkoutStatus get status => _status;

  DateTime? get startedAt => _start;

  DateTime? get endedAt => _end;

  List<BpmSample> get heartRate => List.unmodifiable(_heartRate);

  List<WorkoutPause> get pauses => List.unmodifiable(_pauses);

  WorkoutRoute get route => WorkoutRoute(
    activityType: type.activityType,
    segments: [
      for (final segment in _segments) [for (final t in segment) t.point],
    ],
  );

  double get distanceMeters => _distance;

  void start(DateTime at) {
    _require(const {WorkoutStatus.idle}, 'start');
    _start = at;
    _lastEvent = at;
    _segments.add([]);
    _status = WorkoutStatus.running;
  }

  void pause(DateTime at) {
    _require(const {WorkoutStatus.running}, 'pause');
    _pausedAt = _notBeforeLast(at);
    _status = WorkoutStatus.paused;
  }

  void resume(DateTime at) {
    _require(const {WorkoutStatus.paused}, 'resume');
    _closePause(_notBeforeLast(at));
    _segments.add([]);
    _status = WorkoutStatus.running;
  }

  void finish(DateTime at) {
    _require(const {WorkoutStatus.running, WorkoutStatus.paused}, 'finish');
    _stop(at, WorkoutStatus.finished);
  }

  void discard(DateTime at) {
    _require(const {WorkoutStatus.running, WorkoutStatus.paused}, 'discard');
    _stop(at, WorkoutStatus.discarded);
  }

  bool addHeartRate(int bpm, DateTime at) {
    if (_status != WorkoutStatus.running) return false;
    if (bpm < minWorkoutHeartRate || bpm > maxWorkoutHeartRate) return false;
    _heartRate.add((at: at, bpm: bpm));
    _heartRateSum += bpm;
    final max = _maxHeartRate;
    _maxHeartRate = max == null || bpm > max ? bpm : max;
    return true;
  }

  FixVerdict addFix(LocationFix fix) {
    if (_status != WorkoutStatus.running || !gps) return FixVerdict.notRunning;
    if (!TrackPoint.validLatitude(fix.latitude) ||
        !TrackPoint.validLongitude(fix.longitude)) {
      return FixVerdict.invalid;
    }
    final accuracy = fix.accuracyMeters;
    if (accuracy.isNaN || accuracy < 0 || accuracy > maxFixAccuracyMeters) {
      return FixVerdict.inaccurate;
    }
    final lastEvent = _lastEvent;
    if (lastEvent == null || fix.at.isBefore(lastEvent)) {
      return FixVerdict.outOfOrder;
    }
    final point = TrackPoint(
      at: fix.at,
      latitude: fix.latitude,
      longitude: fix.longitude,
      elevationMeters: fix.altitudeMeters,
      accuracyMeters: accuracy,
    );
    final segment = _segments.last;
    final previous = segment.isEmpty ? null : segment.last;
    if (previous == null) {
      segment.add(_Tracked(point, _distance, _movingAt(fix.at)));
      return FixVerdict.accepted;
    }
    final seconds =
        fix.at.difference(previous.point.at).inMicroseconds /
        Duration.microsecondsPerSecond;
    if (seconds <= 0) return FixVerdict.outOfOrder;
    final meters = haversineMeters(previous.point, point);
    if (meters / seconds > maxPlausibleSpeedMetersPerSecond) {
      return FixVerdict.tooFast;
    }
    _distance += meters;
    segment.add(_Tracked(point, _distance, _movingAt(fix.at)));
    return FixVerdict.accepted;
  }

  Duration elapsedAt(DateTime now) {
    final start = _start;
    if (start == null) return Duration.zero;
    final until = _end ?? _pausedAt ?? now;
    final elapsed = until.difference(start) - _paused;
    return elapsed.isNegative ? Duration.zero : elapsed;
  }

  Duration? currentPaceAt(DateTime now) {
    if (_status != WorkoutStatus.running || _segments.isEmpty) return null;
    final segment = _segments.last;
    final from = _movingAt(now) - currentPaceWindow;
    var first = segment.length;
    while (first > 0 && segment[first - 1].moving >= from) {
      first--;
    }
    if (segment.length - first < 2) return null;
    final oldest = segment[first];
    final newest = segment.last;
    return _pace(
      newest.moving - oldest.moving,
      newest.distance - oldest.distance,
    );
  }

  Duration? averagePaceAt(DateTime now) => _pace(elapsedAt(now), _distance);

  int? currentHeartRateAt(DateTime now) {
    if (_status != WorkoutStatus.running || _heartRate.isEmpty) return null;
    final last = _heartRate.last;
    if (now.difference(last.at) > heartRateHold) return null;
    final linkStart = heartRateLinkStart;
    if (linkStart != null && last.at.isBefore(linkStart)) return null;
    return last.bpm;
  }

  int? get averageHeartRate =>
      _heartRate.isEmpty ? null : (_heartRateSum / _heartRate.length).round();

  int? get maxHeartRate => _maxHeartRate;

  double? activeKilocaloriesAt(DateTime now) {
    final weight = profile.weightKilograms;
    if (weight == null) return null;
    final hours = elapsedAt(now).inMicroseconds / Duration.microsecondsPerHour;
    return (type.met - 1) * weight * hours;
  }

  WorkoutSnapshot snapshotAt(DateTime now) {
    final current = currentHeartRateAt(now);
    final zones = profile.zones;
    return WorkoutSnapshot(
      type: type,
      status: _status,
      start: _start,
      end: _end,
      elapsed: elapsedAt(now),
      gps: gps,
      distanceMeters: gps ? _distance : null,
      currentPace: gps ? currentPaceAt(now) : null,
      averagePace: gps ? averagePaceAt(now) : null,
      currentHeartRate: current,
      averageHeartRate: averageHeartRate,
      maxHeartRate: _maxHeartRate,
      currentZone: current == null || zones == null
          ? null
          : zones.zoneOf(current),
      activeKilocalories: activeKilocaloriesAt(now),
      heartRateSamples: _heartRate.length,
      trackPoints: _segments.fold(0, (sum, s) => sum + s.length),
    );
  }

  FinishedWorkout finished() {
    final start = _start;
    final end = _end;
    if (_status != WorkoutStatus.finished || start == null || end == null) {
      throw StateError('The workout is ${_status.name}, not finished');
    }
    return FinishedWorkout(
      type: type,
      start: start,
      end: end,
      elapsed: elapsedAt(end),
      distanceMeters: gps ? _distance : null,
      activeKilocalories: activeKilocaloriesAt(end),
      averageHeartRate: averageHeartRate,
      maxHeartRate: _maxHeartRate,
      heartRate: _heartRate,
      route: route,
      pauses: _pauses,
    );
  }

  void _stop(DateTime at, WorkoutStatus status) {
    final end = _notBeforeLast(at);
    if (_status == WorkoutStatus.paused) _closePause(end);
    _end = end;
    _status = status;
  }

  void _closePause(DateTime at) {
    final pausedAt = _pausedAt;
    if (pausedAt == null) return;
    _pauses.add(WorkoutPause(start: pausedAt, end: at));
    _paused += at.difference(pausedAt);
    _pausedAt = null;
    _lastEvent = at;
  }

  // A clock that steps back must not make a pause or the workout negative.
  DateTime _notBeforeLast(DateTime at) {
    final last = _lastEvent ?? at;
    final clamped = at.isBefore(last) ? last : at;
    _lastEvent = clamped;
    return clamped;
  }

  Duration _movingAt(DateTime at) {
    final start = _start;
    if (start == null) return Duration.zero;
    return at.difference(start) - _paused;
  }

  void _require(Set<WorkoutStatus> allowed, String action) {
    if (allowed.contains(_status)) return;
    throw StateError('Cannot $action a workout that is ${_status.name}');
  }

  static Duration? _pace(Duration time, double meters) {
    if (meters < minPaceDistanceMeters) return null;
    return Duration(
      microseconds: (time.inMicroseconds * 1000 / meters).round(),
    );
  }
}

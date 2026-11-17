import 'package:open_ring/features/settings/domain/unit_system.dart';
import 'package:open_ring/features/workout/domain/location_source.dart';
import 'package:open_ring/features/workout/domain/workout_notifier.dart';
import 'package:open_ring/features/workout/domain/workout_session.dart';

const _metersPerKilometer = 1000.0;
const _fieldSeparator = ' · ';
const _noHeartRate = '-- bpm';

WorkoutNotice workoutNoticeOf(
  WorkoutSnapshot snapshot,
  LocationNotice notice,
  UnitSystem units, {
  bool ringLost = false,
  bool gpsLost = false,
  bool confirming = false,
}) {
  final labels = notice.live;
  final running = snapshot.status == WorkoutStatus.running;
  final type = labels.types[snapshot.type];
  final distance = _distance(snapshot, labels, units);
  final clock = _clock(snapshot.elapsed);
  if (confirming) {
    return WorkoutNotice(
      title: labels.confirmTitle,
      text: labels.confirmText(clock, distance),
      elapsed: snapshot.elapsed,
      running: false,
      confirming: true,
      ringLost: ringLost,
      labels: labels,
    );
  }
  return WorkoutNotice(
    title: _title(snapshot, notice.title, type, labels, running, ringLost),
    text: running
        ? _fields(snapshot, labels, units, distance, ringLost, gpsLost)
        : [labels.pausedAt(clock), ?distance].join(_fieldSeparator),
    elapsed: snapshot.elapsed,
    running: running,
    ringLost: ringLost,
    labels: labels,
  );
}

String _title(
  WorkoutSnapshot snapshot,
  String fallback,
  String? type,
  WorkoutNoticeLabels labels,
  bool running,
  bool ringLost,
) {
  if (type == null) return fallback;
  if (!running) return labels.pausedTitle(type);
  if (ringLost) return labels.ringLostTitle(type);
  final zone = snapshot.currentZone;
  if (zone == null || snapshot.currentHeartRate == null) return type;
  return labels.zoneTitle(type, zone);
}

String _fields(
  WorkoutSnapshot snapshot,
  WorkoutNoticeLabels labels,
  UnitSystem units,
  String? distance,
  bool ringLost,
  bool gpsLost,
) {
  final heartRate = snapshot.currentHeartRate;
  final fields = [
    if (ringLost) _noHeartRate,
    if (!ringLost && heartRate != null) '$heartRate bpm',
    if (snapshot.gps && gpsLost) labels.gpsLost,
    if (!gpsLost) ?distance,
    if (!gpsLost) ?_movement(snapshot, labels, units),
  ];
  if (fields.isEmpty) return labels.recording;
  return fields.join(_fieldSeparator);
}

String? _distance(
  WorkoutSnapshot snapshot,
  WorkoutNoticeLabels labels,
  UnitSystem units,
) {
  if (!snapshot.gps) return null;
  final imperial = units == UnitSystem.imperial;
  final meters = snapshot.distanceMeters ?? 0;
  final value = meters / _unitMeters(units);
  return '${_decimal(value, 2, labels)} ${imperial ? 'mi' : 'km'}';
}

String? _movement(
  WorkoutSnapshot snapshot,
  WorkoutNoticeLabels labels,
  UnitSystem units,
) {
  final pace = snapshot.currentPace;
  if (!snapshot.gps || pace == null || pace <= Duration.zero) return null;
  final imperial = units == UnitSystem.imperial;
  final perUnit = pace * (_unitMeters(units) / _metersPerKilometer);
  if (snapshot.type.showsSpeed) {
    final hours = perUnit.inMicroseconds / Duration.microsecondsPerHour;
    final unit = imperial ? labels.speedImperial : labels.speed;
    return '${_decimal(1 / hours, 1, labels)} $unit';
  }
  return '${_paceClock(perUnit)} /${imperial ? 'mi' : 'km'}';
}

double _unitMeters(UnitSystem units) => units == UnitSystem.imperial
    ? ImperialUnits.metersPerMile
    : _metersPerKilometer;

String _decimal(double value, int digits, WorkoutNoticeLabels labels) =>
    value.toStringAsFixed(digits).replaceFirst('.', labels.decimalSeparator);

String _paceClock(Duration pace) {
  final seconds = pace.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '${pace.inMinutes}:$seconds';
}

String _clock(Duration elapsed) {
  final total = elapsed.inSeconds;
  final seconds = (total % 60).toString().padLeft(2, '0');
  final minutes = total ~/ 60 % 60;
  if (total < 3600) return '$minutes:$seconds';
  return '${total ~/ 3600}:${minutes.toString().padLeft(2, '0')}:$seconds';
}

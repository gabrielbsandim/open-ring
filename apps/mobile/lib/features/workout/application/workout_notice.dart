import 'package:open_ring/features/settings/domain/unit_system.dart';
import 'package:open_ring/features/workout/domain/location_source.dart';
import 'package:open_ring/features/workout/domain/workout_notifier.dart';
import 'package:open_ring/features/workout/domain/workout_session.dart';

const _metersPerKilometer = 1000.0;
const _fieldSeparator = ' · ';

WorkoutNotice workoutNoticeOf(
  WorkoutSnapshot snapshot,
  LocationNotice notice,
  UnitSystem units,
) {
  final running = snapshot.status == WorkoutStatus.running;
  return WorkoutNotice(
    title: notice.title,
    text: running ? _fields(snapshot, notice.live, units) : notice.live.paused,
    elapsed: snapshot.elapsed,
    running: running,
    labels: notice.live,
  );
}

String _fields(
  WorkoutSnapshot snapshot,
  WorkoutNoticeLabels labels,
  UnitSystem units,
) {
  final imperial = units == UnitSystem.imperial;
  final unitMeters = imperial
      ? ImperialUnits.metersPerMile
      : _metersPerKilometer;
  final unit = imperial ? 'mi' : 'km';
  final heartRate = snapshot.currentHeartRate;
  final pace = snapshot.currentPace;
  return [
    if (heartRate != null) '$heartRate bpm',
    if (snapshot.gps)
      '${_decimal((snapshot.distanceMeters ?? 0) / unitMeters, labels)} $unit',
    if (snapshot.gps && pace != null)
      '${_clock(pace * (unitMeters / _metersPerKilometer))} /$unit',
  ].join(_fieldSeparator);
}

String _decimal(double value, WorkoutNoticeLabels labels) =>
    value.toStringAsFixed(2).replaceFirst('.', labels.decimalSeparator);

String _clock(Duration pace) {
  final seconds = pace.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '${pace.inMinutes}:$seconds';
}

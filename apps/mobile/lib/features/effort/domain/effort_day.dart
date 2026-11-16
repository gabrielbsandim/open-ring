import 'package:metrics/metrics.dart';
import 'package:open_ring/features/activity/domain/activity_history_reader.dart';
import 'package:open_ring/features/open_score/domain/day_score_history.dart';
import 'package:open_ring/features/workout/domain/workout_history.dart';
import 'package:open_ring/features/workout/domain/workout_type.dart';

// The seed of a load line weighs on it, so the window is fixed: a line read
// over another length would be another number.
const effortLoadDays = 42;

/// The load a minute of a workout with no heart rate and no rating.
double effortTypeDefault(WorkoutType type) => switch (type) {
  WorkoutType.running || WorkoutType.treadmill => 3,
  WorkoutType.strength ||
  WorkoutType.stationaryBike ||
  WorkoutType.cycling => 2.5,
  WorkoutType.hiking || WorkoutType.elliptical || WorkoutType.other => 2,
  WorkoutType.walking => 1.5,
  WorkoutType.yoga => 1,
};

typedef EffortSession = ({
  LocalDate date,
  DateTime start,
  DateTime end,
  Duration elapsed,
  WorkoutType type,
  IntensityMinutes points,
  SessionLoad load,
  bool strength,
});

/// One workout as Effort reads it. It counts whole on the day it started.
EffortSession effortSessionOf(
  WorkoutEntry entry, {
  List<BpmSample> heartRate = const [],
  HeartRateZones? zones,
}) => (
  date: LocalDate.fromInstant(entry.start, entry.utcOffset),
  start: entry.start,
  end: entry.end,
  elapsed: entry.elapsed,
  type: entry.type,
  points: workoutPoints(
    entry,
    heartRate: heartRate,
    maxHeartRate: zones?.maxHeartRate,
  ),
  load: sessionLoad(
    elapsed: entry.elapsed,
    typeDefault: effortTypeDefault(entry.type),
    timeInZones: zones?.timeInZones(heartRate) ?? const {},
  ),
  strength:
      entry.type == WorkoutType.strength && isStrengthSession(entry.elapsed),
);

/// The load of each day, oldest first, from the first day with data in the
/// [effortLoadDays] days before [today] to yesterday.
List<double> effortDailyLoad({
  required Iterable<EffortSession> sessions,
  required Iterable<ActivitySlot> slots,
  required LocalDate today,
}) {
  final from = today.addDays(-effortLoadDays);
  bool inWindow(LocalDate date) =>
      date.compareTo(from) >= 0 && date.compareTo(today) < 0;
  final spans = [for (final s in sessions) (start: s.start, end: s.end)];
  final bySession = <LocalDate, int>{};
  for (final session in sessions.where((s) => inWindow(s.date))) {
    bySession[session.date] =
        (bySession[session.date] ?? 0) + session.load.value;
  }
  final brisk = <LocalDate, double>{};
  for (final slot in slots.where((s) => s.steps > 0 && inWindow(s.date))) {
    final walked = walkingIntensity([
      (start: slot.start, duration: slot.duration, steps: slot.steps),
    ], workouts: spans);
    brisk[slot.date] = (brisk[slot.date] ?? 0) + _minutes(walked);
  }
  final dates = {...bySession.keys, ...brisk.keys};
  if (dates.isEmpty) return const [];
  final first = dates.reduce((a, b) => a.compareTo(b) <= 0 ? a : b);
  return [
    for (var day = first; day.compareTo(today) < 0; day = day.addDays(1))
      // Walking is rounded once for the day, never slot by slot.
      ((bySession[day] ?? 0) + walkingLoad(brisk[day] ?? 0)).toDouble(),
  ];
}

double _minutes(IntensityMinutes walked) => walked.moderate + walked.vigorous;

Set<LocalDate> effortStrengthDays(Iterable<EffortSession> sessions) => {
  for (final session in sessions)
    if (session.strength) session.date,
};

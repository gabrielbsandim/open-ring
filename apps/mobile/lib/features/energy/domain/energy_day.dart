import 'package:meta/meta.dart';
import 'package:metrics/metrics.dart';

enum EnergyField { sex, birthYear, height, weight }

typedef EnergyWorkout = ({
  DateTime start,
  DateTime end,
  Duration elapsed,
  double met,
  double? storedKilocalories,
});

sealed class EnergyDay {
  const new();
}

@immutable
final class EnergyDayEstimate extends EnergyDay {
  const new({
    required this.resting,
    required this.base,
    required this.steps,
    required this.workouts,
  });

  final double resting;
  final double base;
  final double steps;
  final double workouts;

  double get total => base + steps + workouts;

  EnergyRange get range => energyRange(total, energyDayMargin);
}

@immutable
final class EnergyDayMissing extends EnergyDay {
  const new(this.fields);

  final Set<EnergyField> fields;
}

final class EnergyDayUnderage extends EnergyDay {
  const new();
}

/// The estimate of the local day that runs from [from] to [to], as far as
/// [now]. [workouts] are already selected and may reach outside the day:
/// each one covers the steps it overlaps and adds kcal only when it starts
/// inside the day.
EnergyDay energyDay({
  required EnergySex? sex,
  required int? age,
  required double? kilograms,
  required double? centimeters,
  required Iterable<StepBucket> slots,
  required Iterable<EnergyWorkout> workouts,
  required DateTime from,
  required DateTime to,
  required DateTime now,
}) {
  if (age != null && age < energyAdultAge) return const EnergyDayUnderage();
  final resting = restingEnergy(
    sex: sex,
    age: age,
    kilograms: kilograms,
    centimeters: centimeters,
  );
  if (resting == null || kilograms == null || centimeters == null) {
    return EnergyDayMissing({
      if (sex == null) EnergyField.sex,
      if (age == null) EnergyField.birthYear,
      if (centimeters == null) EnergyField.height,
      if (kilograms == null) EnergyField.weight,
    });
  }
  final spans = [
    for (final workout in workouts)
      if (workout.end.isAfter(workout.start))
        (start: workout.start, end: workout.end),
  ]..sort((a, b) => a.start.compareTo(b.start));
  final walked = [
    for (final slot in slots)
      _freeShare(slot, spans) *
          stepEnergy(
            steps: slot.steps,
            kilograms: kilograms,
            centimeters: centimeters,
          ),
  ];
  final trained = [
    for (final workout in workouts)
      if (!workout.start.isBefore(from) && workout.start.isBefore(to))
        workout.storedKilocalories ??
            workoutEnergy(
              met: workout.met,
              kilograms: kilograms,
              elapsed: workout.elapsed,
            ),
  ];
  return EnergyDayEstimate(
    resting: resting,
    base: baseEnergy(resting, _elapsed(from, to, now)),
    steps: walked.fold(0, (sum, value) => sum + value),
    workouts: trained.fold(0, (sum, value) => sum + value),
  );
}

Duration _elapsed(DateTime from, DateTime to, DateTime now) {
  if (now.isBefore(from)) return Duration.zero;
  if (now.isAfter(to)) return to.difference(from);
  return now.difference(from);
}

// The share of the slot no workout covers; [spans] come sorted by start, so
// a cursor walks their union once.
double _freeShare(StepBucket slot, List<TimeSpan> spans) {
  final start = slot.start;
  if (slot.duration <= Duration.zero) {
    final inside = spans.any(
      (span) => !span.start.isAfter(start) && span.end.isAfter(start),
    );
    return inside ? 0 : 1;
  }
  final end = start.add(slot.duration);
  var covered = Duration.zero;
  var cursor = start;
  for (final span in spans) {
    final begin = span.start.isAfter(cursor) ? span.start : cursor;
    final finish = span.end.isBefore(end) ? span.end : end;
    if (!finish.isAfter(begin)) continue;
    covered += finish.difference(begin);
    cursor = finish;
  }
  return 1 - covered.inMicroseconds / slot.duration.inMicroseconds;
}

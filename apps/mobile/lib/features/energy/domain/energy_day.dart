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

// Fewer days than this say too little about what is usual for a person.
const energyUsualMinDays = 3;

const energyWeekDays = 7;

/// One day of the week view. The estimate is null when the day has none or
/// has nothing on record.
typedef EnergyWeekDay = ({LocalDate date, EnergyDayEstimate? day});

/// A past day with no steps and no workouts was most likely a day without
/// the ring, so it is no evidence of a day of Base alone.
bool energyDayOnRecord(EnergyDayEstimate day) =>
    day.steps > 0 || day.workouts > 0;

/// The mean total of [days], or null with fewer than [energyUsualMinDays].
double? energyUsual(Iterable<EnergyDayEstimate> days) {
  final totals = [for (final day in days) day.total];
  if (totals.length < energyUsualMinDays) return null;
  return totals.reduce((a, b) => a + b) / totals.length;
}

typedef EnergyPoint = ({DateTime at, EnergyDayEstimate day});

typedef EnergyCurve = ({DateTime from, DateTime to, List<EnergyPoint> points});

/// The same day as [energyDay] gives, as it stood at each full hour up to
/// [now] and at [now] itself. Empty when the day has no estimate.
EnergyCurve energyCurve({
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
  EnergyDay at(DateTime instant, {required bool whole}) => energyDay(
    sex: sex,
    age: age,
    kilograms: kilograms,
    centimeters: centimeters,
    slots: whole ? slots : slots.where((s) => _endedBy(s, instant)),
    workouts: whole
        ? workouts
        : workouts.where((w) => w.start.isBefore(instant)),
    from: from,
    to: to,
    now: instant,
  );

  final end = now.isAfter(to) ? to : now;
  final instants = [
    for (
      var hour = from;
      hour.isBefore(end);
      hour = hour.add(const Duration(hours: 1))
    )
      hour,
  ];
  final last = end.isBefore(from) ? null : at(end, whole: true);
  final points = <EnergyPoint>[
    for (final instant in instants)
      if (at(instant, whole: false) case final EnergyDayEstimate day)
        (at: instant, day: day),
    if (last case final EnergyDayEstimate day) (at: end, day: day),
  ];
  return (from: from, to: to, points: points);
}

// A slot counts at an hour only once it is over, so every workout that can
// cover it has already started and the total never falls at a later hour.
bool _endedBy(StepBucket slot, DateTime instant) =>
    slot.start.isBefore(instant) &&
    !slot.start.add(slot.duration).isAfter(instant);

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

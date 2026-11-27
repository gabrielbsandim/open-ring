import 'package:metrics/src/local_date.dart';

const fitnessWindowDays = 90;
const fitnessWarmUp = Duration(minutes: 3);
const fitnessMinSteady = Duration(minutes: 10);
const fitnessMinReserve = 0.6;
const fitnessMaxReserve = 0.9;
const fitnessMinAge = 20;
const fitnessMaxAge = 79;

const restingVo2 = 3.5;
const walkingVo2PerMeter = 0.1;
const runningVo2PerMeter = 0.2;
const walkingMinSpeed = 50.0;
const walkingMaxSpeed = 100.0;
const runningMinSpeed = 80.0;

enum FitnessSex { female, male }

enum FitnessGait { walk, run }

/// A pause free stretch of a recorded workout, after the warm up.
typedef FitnessStretch = ({Duration duration, double meters, double meanBpm});

typedef FitnessEffort = ({
  LocalDate date,
  FitnessGait gait,
  List<FitnessStretch> stretches,
});

const fitnessPercentiles = [5.0, 10.0, 25.0, 50.0, 75.0, 90.0, 95.0];

// VO2max in mL/kg/min at those percentiles, by decade from 20 to 29 up to
// 70 to 79: FRIEND registry, Kaminsky and colleagues, 2015, table 2.
const _men = [
  [29.0, 32.1, 40.1, 48.0, 55.2, 61.8, 66.3],
  [27.2, 30.2, 35.9, 42.4, 49.2, 56.5, 59.8],
  [24.2, 26.8, 31.9, 37.8, 45.0, 52.1, 55.6],
  [20.9, 22.8, 27.1, 32.6, 39.7, 45.6, 50.7],
  [17.4, 19.8, 23.7, 28.2, 34.5, 40.3, 43.0],
  [16.3, 17.1, 20.4, 24.4, 30.4, 36.6, 39.7],
];

const _women = [
  [21.7, 23.9, 30.5, 37.6, 44.7, 51.3, 56.0],
  [19.0, 20.9, 25.3, 30.2, 36.1, 41.4, 45.8],
  [17.0, 18.8, 22.1, 26.7, 32.4, 38.4, 41.7],
  [16.0, 17.3, 19.9, 23.4, 27.6, 32.0, 35.9],
  [13.4, 14.6, 17.2, 20.0, 23.8, 27.0, 29.4],
  [13.1, 13.6, 15.6, 18.3, 20.8, 23.1, 24.1],
];

/// The position of [vo2max] among 100 people of the same decade and sex,
/// between 5 and 95, or null outside the ages the table covers.
double? fitnessPercentile(
  double vo2max, {
  required int age,
  required FitnessSex sex,
}) {
  if (age < fitnessMinAge || age > fitnessMaxAge) return null;
  final table = switch (sex) {
    FitnessSex.male => _men,
    FitnessSex.female => _women,
  };
  final row = table[(age - fitnessMinAge) ~/ 10];
  if (vo2max <= row.first) return fitnessPercentiles.first;
  if (vo2max >= row.last) return fitnessPercentiles.last;
  final upper = row.indexWhere((value) => value >= vo2max);
  final share = (vo2max - row[upper - 1]) / (row[upper] - row[upper - 1]);
  return fitnessPercentiles[upper - 1] +
      share * (fitnessPercentiles[upper] - fitnessPercentiles[upper - 1]);
}

double? _steadyVo2(FitnessGait gait, double metersPerMinute) => switch (gait) {
  FitnessGait.walk
      when metersPerMinute >= walkingMinSpeed &&
          metersPerMinute <= walkingMaxSpeed =>
    restingVo2 + walkingVo2PerMeter * metersPerMinute,
  FitnessGait.run when metersPerMinute >= runningMinSpeed =>
    restingVo2 + runningVo2PerMeter * metersPerMinute,
  _ => null,
};

/// VO2max from a steady effort on flat ground: the oxygen cost of the speed,
/// scaled by the share of the heart rate reserve it took.
double? steadyVo2max({
  required FitnessGait gait,
  required double metersPerMinute,
  required double meanBpm,
  required double restingBpm,
  required double maxBpm,
}) {
  final reserve = maxBpm - restingBpm;
  if (reserve <= 0) return null;
  final used = (meanBpm - restingBpm) / reserve;
  if (used < fitnessMinReserve || used > fitnessMaxReserve) return null;
  final cost = _steadyVo2(gait, metersPerMinute);
  if (cost == null) return null;
  return restingVo2 + (cost - restingVo2) / used;
}

double? _stretchVo2max(
  FitnessGait gait,
  FitnessStretch stretch, {
  required double restingBpm,
  required double maxBpm,
}) {
  if (stretch.duration < fitnessMinSteady) return null;
  return steadyVo2max(
    gait: gait,
    metersPerMinute:
        stretch.meters *
        Duration.microsecondsPerMinute /
        stretch.duration.inMicroseconds,
    meanBpm: stretch.meanBpm,
    restingBpm: restingBpm,
    maxBpm: maxBpm,
  );
}

double _median(List<double> values) {
  final sorted = [...values]..sort();
  final middle = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[middle]
      : (sorted[middle - 1] + sorted[middle]) / 2;
}

/// The estimate of one workout: the median over its steady stretches.
double? effortVo2max(
  FitnessEffort effort, {
  required double restingBpm,
  required double maxBpm,
}) {
  final values = [
    for (final stretch in effort.stretches)
      ?_stretchVo2max(
        effort.gait,
        stretch,
        restingBpm: restingBpm,
        maxBpm: maxBpm,
      ),
  ];
  return values.isEmpty ? null : _median(values);
}

/// The best estimate among the efforts of the 90 days before [day].
double? bestVo2max(
  Iterable<FitnessEffort> efforts, {
  required LocalDate day,
  required double restingBpm,
  required double maxBpm,
}) {
  final values = [
    for (final effort in efforts)
      if (day.daysSince(effort.date) >= 1 &&
          day.daysSince(effort.date) <= fitnessWindowDays)
        ?effortVo2max(effort, restingBpm: restingBpm, maxBpm: maxBpm),
  ];
  return values.isEmpty ? null : values.reduce((a, b) => a > b ? a : b);
}

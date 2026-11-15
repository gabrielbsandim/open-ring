import 'package:metrics/src/baseline.dart';
import 'package:metrics/src/heart_rate_zones.dart';
import 'package:metrics/src/local_date.dart';
import 'package:metrics/src/resting_heart_rate.dart';

typedef StepBucket = ({DateTime start, Duration duration, int steps});

typedef TimeSpan = ({DateTime start, DateTime end});

const moderateFraction = 0.64;
const vigorousFraction = 0.77;
const moderateMet = 3.0;
const vigorousMet = 6.0;
const vigorousMinuteWeight = 2.0;
const briskStepsPerMinute = 100.0;
const intensityWindowDays = 7;
const intensityMinDays = 4;

final class IntensityMinutes {
  const new({this.moderate = 0, this.vigorous = 0});

  static const none = IntensityMinutes();

  final double moderate;
  final double vigorous;

  double get equivalent => moderate + vigorousMinuteWeight * vigorous;

  IntensityMinutes operator +(IntensityMinutes other) => IntensityMinutes(
    moderate: moderate + other.moderate,
    vigorous: vigorous + other.vigorous,
  );
}

double _minutes(Duration duration) =>
    duration.inMicroseconds / Duration.microsecondsPerMinute;

IntensityMinutes heartRateIntensity(
  Iterable<BpmSample> samples, {
  required int maxHeartRate,
  Duration maxHold = liveSampleMaxHold,
}) {
  if (maxHeartRate < 100 || maxHeartRate > 250) {
    throw ArgumentError.value(maxHeartRate, 'maxHeartRate', 'must be 100..250');
  }
  final valid = samples.where((s) => s.bpm > 0).toList()
    ..sort((a, b) => a.at.compareTo(b.at));
  final moderateFrom = maxHeartRate * moderateFraction;
  final vigorousFrom = maxHeartRate * vigorousFraction;
  var moderate = Duration.zero;
  var vigorous = Duration.zero;
  for (var i = 0; i + 1 < valid.length; i++) {
    final bpm = valid[i].bpm;
    if (bpm < moderateFrom) continue;
    final gap = valid[i + 1].at.difference(valid[i].at);
    final held = gap < maxHold ? gap : maxHold;
    if (bpm >= vigorousFrom) {
      vigorous += held;
      continue;
    }
    moderate += held;
  }
  return IntensityMinutes(
    moderate: _minutes(moderate),
    vigorous: _minutes(vigorous),
  );
}

IntensityMinutes metIntensity(double met, Duration elapsed) {
  if (elapsed <= Duration.zero || met < moderateMet) {
    return IntensityMinutes.none;
  }
  final minutes = _minutes(elapsed);
  if (met >= vigorousMet) return IntensityMinutes(vigorous: minutes);
  return IntensityMinutes(moderate: minutes);
}

// Heart rate understates resistance work, so a workout takes the larger credit.
IntensityMinutes workoutIntensity({
  required double met,
  required Duration elapsed,
  Iterable<BpmSample> heartRate = const [],
  int? maxHeartRate,
}) {
  final byType = metIntensity(met, elapsed);
  if (maxHeartRate == null) return byType;
  final byHeart = heartRateIntensity(heartRate, maxHeartRate: maxHeartRate);
  return byHeart.equivalent > byType.equivalent ? byHeart : byType;
}

bool _overlaps(StepBucket bucket, TimeSpan span) =>
    bucket.start.isBefore(span.end) &&
    bucket.start.add(bucket.duration).isAfter(span.start);

IntensityMinutes walkingIntensity(
  Iterable<StepBucket> buckets, {
  Iterable<TimeSpan> workouts = const [],
}) {
  var moderate = 0.0;
  for (final bucket in buckets) {
    if (bucket.duration <= Duration.zero) continue;
    final minutes = _minutes(bucket.duration);
    if (bucket.steps / minutes < briskStepsPerMinute) continue;
    if (workouts.any((span) => _overlaps(bucket, span))) continue;
    moderate += minutes;
  }
  return IntensityMinutes(moderate: moderate);
}

// One value per day the ring reported activity, zero included.
double? weeklyIntensityMinutes(
  Iterable<DailyValue> dailyEquivalent, {
  required LocalDate today,
  int windowDays = intensityWindowDays,
  int minDays = intensityMinDays,
}) {
  if (windowDays < 1) {
    throw ArgumentError.value(windowDays, 'windowDays', 'must be at least 1');
  }
  if (minDays < 1 || minDays > windowDays) {
    throw ArgumentError.value(minDays, 'minDays', 'must be in 1..windowDays');
  }
  final byDate = <LocalDate, double>{};
  for (final d in dailyEquivalent) {
    final age = today.daysSince(d.date);
    if (age < 0 || age >= windowDays) continue;
    if (!d.value.isFinite || d.value < 0) continue;
    byDate[d.date] = d.value;
  }
  if (byDate.length < minDays) return null;
  return byDate.values.fold<double>(0, (sum, v) => sum + v);
}

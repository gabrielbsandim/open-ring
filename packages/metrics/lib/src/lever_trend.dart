import 'dart:math' as math;

import 'package:metrics/src/baseline.dart';
import 'package:metrics/src/intensity_minutes.dart';
import 'package:metrics/src/local_date.dart';

const leverTrendWindowDays = 90;
const leverTrendMinValidDays = 54;
const leverTrendZ = 1.6448536269514722;
const validStepDayWaking = Duration(hours: 10);

/// The ring levers, each with the change over the window that counts as real:
/// steps a day, regularity points, bpm and minutes a night.
enum RingLever {
  steps(500),
  sleepRegularity(5),
  restingHeartRate(2),
  sleepDuration(20);

  new(this.minimumChange);

  final double minimumChange;
}

enum LeverDirection { rising, falling, stable }

final class LeverTrend {
  const new({
    required this.slopePerDay,
    required this.slopeLow,
    required this.slopeHigh,
    required this.typical,
    required this.centerDay,
    required this.validDays,
  });

  final double slopePerDay;
  final double slopeLow;
  final double slopeHigh;
  final double typical;
  final double centerDay;
  final int validDays;

  double get change => slopePerDay * leverTrendWindowDays;
  double get changeLow => slopeLow * leverTrendWindowDays;
  double get changeHigh => slopeHigh * leverTrendWindowDays;

  LeverDirection direction(RingLever lever) {
    if (slopeLow > 0 && change >= lever.minimumChange) {
      return LeverDirection.rising;
    }
    if (slopeHigh < 0 && -change >= lever.minimumChange) {
      return LeverDirection.falling;
    }
    return LeverDirection.stable;
  }

  /// Where steps would be in 90 days if the trend held, from the line through
  /// the median day and value, read at the last day of the window.
  ({double low, double high})? fan(RingLever lever) {
    if (lever != RingLever.steps) return null;
    final last = typical + slopePerDay * (leverTrendWindowDays - 1 - centerDay);
    return (low: last + changeLow, high: last + changeHigh);
  }
}

/// The Theil-Sen slope of the [leverTrendWindowDays] ending on [end], with
/// Sen's 90% interval, or null below [leverTrendMinValidDays] valid days.
LeverTrend? theilSen(List<DailyValue> days, {required LocalDate end}) {
  final byDay = <int, double>{};
  for (final day in days) {
    final age = end.daysSince(day.date);
    if (age < 0 || age >= leverTrendWindowDays) continue;
    if (!day.value.isFinite) continue;
    byDay[leverTrendWindowDays - 1 - age] = day.value;
  }
  final n = byDay.length;
  if (n < leverTrendMinValidDays) return null;
  final xs = byDay.keys.toList()..sort();
  final ys = [for (final x in xs) byDay[x]!];
  final slopes = <double>[
    for (var i = 0; i < n; i++)
      for (var j = i + 1; j < n; j++) (ys[j] - ys[i]) / (xs[j] - xs[i]),
  ]..sort();
  final slope = _median(slopes);
  final count = slopes.length;
  final spread = math.sqrt((n * (n - 1) * (2 * n + 5) - _tieTerm(ys)) / 18);
  final lower = math.max(((count - leverTrendZ * spread) / 2).round() - 1, 0);
  final upper = math.min(
    ((count + leverTrendZ * spread) / 2).round(),
    count - 1,
  );
  return LeverTrend(
    slopePerDay: slope,
    slopeLow: slopes[lower],
    slopeHigh: slopes[upper],
    typical: _median(ys),
    centerDay: _median([for (final x in xs) x.toDouble()]),
    validDays: n,
  );
}

// Equal values shrink the variance of the pairwise signs.
double _tieTerm(List<double> values) {
  final groups = <double, int>{};
  for (final value in values) {
    groups[value] = (groups[value] ?? 0) + 1;
  }
  return groups.values.fold<double>(
    0,
    (sum, k) => sum + k * (k - 1) * (2 * k + 5),
  );
}

double _median(List<double> values) {
  final sorted = [...values]..sort();
  final middle = sorted.length ~/ 2;
  if (sorted.length.isOdd) return sorted[middle];
  return (sorted[middle - 1] + sorted[middle]) / 2;
}

/// Whether the ring reported at least [validStepDayWaking] of buckets outside
/// [sleep], so a quiet day with the ring on still counts.
bool isValidStepDay(
  Iterable<StepBucket> buckets, {
  Iterable<TimeSpan> sleep = const [],
}) {
  final worn = _union([
    for (final bucket in buckets)
      (start: bucket.start, end: bucket.start.add(bucket.duration)),
  ]);
  final asleep = _union(sleep);
  var awake = Duration.zero;
  for (final span in worn) {
    awake += span.end.difference(span.start);
    for (final night in asleep) {
      awake -= _overlap(span, night);
    }
  }
  return awake >= validStepDayWaking;
}

List<TimeSpan> _union(Iterable<TimeSpan> spans) {
  final sorted = [
    for (final span in spans)
      if (span.end.isAfter(span.start)) span,
  ]..sort((a, b) => a.start.compareTo(b.start));
  final merged = <TimeSpan>[];
  for (final span in sorted) {
    if (merged.isEmpty || span.start.isAfter(merged.last.end)) {
      merged.add(span);
      continue;
    }
    final last = merged.removeLast();
    final end = span.end.isAfter(last.end) ? span.end : last.end;
    merged.add((start: last.start, end: end));
  }
  return merged;
}

Duration _overlap(TimeSpan a, TimeSpan b) {
  final start = a.start.isAfter(b.start) ? a.start : b.start;
  final end = a.end.isBefore(b.end) ? a.end : b.end;
  if (!end.isAfter(start)) return Duration.zero;
  return end.difference(start);
}

import 'package:metrics/src/goal_progress.dart';
import 'package:metrics/src/goal_review.dart';
import 'package:metrics/src/local_date.dart';

const goalBaselineDays = 14;
const goalBaselineMinDays = 7;
const goalBaselineWeeks = 4;

const _daysInWeek = 7;

/// The median rounded to a whole number, or null with fewer than [minCount]
/// values.
int? medianOf(Iterable<int> values, {int minCount = 1}) {
  final sorted = values.toList()..sort();
  if (sorted.isEmpty || sorted.length < minCount) return null;
  final middle = sorted.length ~/ 2;
  if (sorted.length.isOdd) return sorted[middle];
  return ((sorted[middle - 1] + sorted[middle]) / 2).round();
}

/// What a person usually does, read over the days that end on [end]: the
/// medians over [goalBaselineDays], the effort and strength over
/// [goalBaselineWeeks] weeks.
LeverBaseline leverBaseline(GoalWeekData data, {required LocalDate end}) {
  final short = _window(end, goalBaselineDays);
  final long = _window(end, goalBaselineWeeks * _daysInWeek);
  final nights = [for (final date in short) ?data.nights[date]];
  return LeverBaseline(
    stepsMedian14: medianOf([
      for (final date in short) ?data.steps[date],
    ], minCount: goalBaselineMinDays),
    bedMedian: medianOf([
      for (final night in nights)
        for (final span in night.spans.where((span) => span.isAsleep).take(1))
          minutesAfterNoon(span.start, span.utcOffset),
    ], minCount: goalBaselineMinDays),
    wakeMedian: medianOf([
      for (final night in nights)
        minutesAfterMidnight(night.end, night.spans.last.utcOffset),
    ], minCount: goalBaselineMinDays),
    effortMean4Weeks: _effortMean(data, long.first, end),
    strengthDaysUsual:
        data.strengthDays
            .where((date) => _within(date, long.first, end))
            .length ~/
        goalBaselineWeeks,
  );
}

/// Seven readiness values from [from], taken from a [trailing] run of daily
/// values whose last one is the day [last]. A day outside the run is null.
List<int?> weekReadiness(
  List<int?> trailing, {
  required LocalDate last,
  required LocalDate from,
}) => [
  for (var i = 0; i < _daysInWeek; i++)
    _at(trailing, trailing.length - 1 - last.daysSince(from.addDays(i))),
];

int? _at(List<int?> values, int index) {
  if (index < 0 || index >= values.length) return null;
  return values[index];
}

List<LocalDate> _window(LocalDate end, int days) => [
  for (var back = days - 1; back >= 0; back--) end.addDays(-back),
];

bool _within(LocalDate date, LocalDate first, LocalDate end) =>
    date.compareTo(first) >= 0 && date.compareTo(end) <= 0;

double? _effortMean(GoalWeekData data, LocalDate first, LocalDate end) {
  final dated = data.points.where((point) => _within(point.date, first, end));
  if (dated.isEmpty) return null;
  var sum = 0.0;
  for (final point in dated) {
    if (!point.value.isFinite || point.value < 0) continue;
    sum += point.value;
  }
  return sum / goalBaselineWeeks;
}

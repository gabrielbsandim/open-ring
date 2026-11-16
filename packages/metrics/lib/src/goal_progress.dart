import 'dart:math' as math;

import 'package:metrics/src/baseline.dart';
import 'package:metrics/src/goal_review.dart';
import 'package:metrics/src/level_goal.dart';
import 'package:metrics/src/local_date.dart';
import 'package:metrics/src/sleep_night.dart';

const _minutesInDay = 1440;
const _noonMinute = 720;
const _daysInWeek = 7;

/// How one day of the week stands for a daily lever. Today is open until it
/// meets the target, and a day after today is ahead.
enum LeverDayMark { met, missed, open, ahead }

/// What the levers of a goal are counted from, keyed by local date. A night
/// is keyed by the date it ended on.
final class GoalWeekData {
  const new({
    this.steps = const {},
    this.nights = const {},
    this.strengthDays = const {},
    this.points = const [],
  });

  final Map<LocalDate, int> steps;
  final Map<LocalDate, SleepNight> nights;
  final Set<LocalDate> strengthDays;
  final Iterable<DailyValue> points;
}

final class LeverProgress {
  const new({required this.lever, required this.achieved, required this.days});

  final Lever lever;
  final int achieved;

  /// Seven marks from Monday, or null for a lever counted over the week.
  final List<LeverDayMark>? days;

  LeverWeek get week => LeverWeek(lever: lever, achieved: achieved);
}

int minutesAfterMidnight(DateTime instant, Duration utcOffset) {
  final wall = instant.toUtc().add(utcOffset);
  return wall.hour * 60 + wall.minute;
}

int minutesAfterNoon(DateTime instant, Duration utcOffset) =>
    (minutesAfterMidnight(instant, utcOffset) - _noonMinute) % _minutesInDay;

bool bedtimeMet(SleepNight night, int target) {
  for (final span in night.spans) {
    if (span.isAsleep) {
      return minutesAfterNoon(span.start, span.utcOffset) <= target;
    }
  }
  return false;
}

bool wakeMet(SleepNight night, int target) {
  final wake = minutesAfterMidnight(night.end, night.spans.last.utcOffset);
  final apart = (wake - target).abs() % _minutesInDay;
  return math.min(apart, _minutesInDay - apart) <= goalWakeToleranceMinutes;
}

LeverProgress leverProgress(
  Lever lever,
  GoalWeekData data, {
  required LocalDate monday,
  required LocalDate today,
}) => switch (lever.kind) {
  LeverKind.steps => _daily(
    lever,
    monday,
    today,
    (date) => (data.steps[date] ?? -1) >= lever.target,
  ),
  LeverKind.sleepWindow => _daily(
    lever,
    monday,
    today,
    (date) => _night(data, date, (night) => bedtimeMet(night, lever.target)),
  ),
  LeverKind.wakeTime => _daily(
    lever,
    monday,
    today,
    (date) => _night(data, date, (night) => wakeMet(night, lever.target)),
  ),
  LeverKind.strengthDays => LeverProgress(
    lever: lever,
    achieved: data.strengthDays
        .where((date) => _counted(date, monday, today))
        .length,
    days: null,
  ),
  LeverKind.effortPoints => LeverProgress(
    lever: lever,
    achieved: _points(data.points, monday, today),
    days: null,
  ),
};

// The first week runs to the first Monday at least seven days after the start,
// so it is never shorter than a week.
int goalWeekNumber({required LocalDate start, required LocalDate today}) {
  final earliest = start.addDays(_daysInWeek);
  final monday = mondayOf(earliest);
  final first = monday == earliest ? monday : monday.addDays(_daysInWeek);
  if (today.compareTo(first) < 0) return 1;
  return 2 + mondayOf(today).daysSince(first) ~/ _daysInWeek;
}

bool _night(
  GoalWeekData data,
  LocalDate date,
  bool Function(SleepNight night) met,
) {
  final night = data.nights[date];
  return night != null && met(night);
}

LeverProgress _daily(
  Lever lever,
  LocalDate monday,
  LocalDate today,
  bool Function(LocalDate date) met,
) {
  final days = [
    for (var i = 0; i < _daysInWeek; i++) _mark(monday.addDays(i), today, met),
  ];
  return LeverProgress(
    lever: lever,
    achieved: days.where((mark) => mark == LeverDayMark.met).length,
    days: days,
  );
}

LeverDayMark _mark(
  LocalDate date,
  LocalDate today,
  bool Function(LocalDate date) met,
) {
  if (date.compareTo(today) > 0) return LeverDayMark.ahead;
  if (met(date)) return LeverDayMark.met;
  if (date == today) return LeverDayMark.open;
  return LeverDayMark.missed;
}

bool _counted(LocalDate date, LocalDate monday, LocalDate today) =>
    date.compareTo(monday) >= 0 &&
    date.compareTo(today) <= 0 &&
    date.daysSince(monday) < _daysInWeek;

int _points(Iterable<DailyValue> points, LocalDate monday, LocalDate today) {
  var sum = 0.0;
  for (final point in points) {
    if (!_counted(point.date, monday, today)) continue;
    if (!point.value.isFinite || point.value < 0) continue;
    sum += point.value;
  }
  return sum.round();
}

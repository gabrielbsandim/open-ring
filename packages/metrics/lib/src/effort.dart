import 'dart:math' as math;

import 'package:metrics/src/baseline.dart';
import 'package:metrics/src/level_goal.dart';
import 'package:metrics/src/local_date.dart';
import 'package:metrics/src/readiness.dart';

const effortWeekPoints = 150;
const effortWeekStrengthDays = 2;
const effortStrengthMinMinutes = 20;
const effortRatingDivisor = 2.0;
const effortWalkingLoadFactor = 1.5;
const effortAcuteDays = 7;
const effortChronicDays = 28;
const effortLineSeedDays = 7;
const effortMinLoadDays = 14;
const effortHardFloor = 120;
const effortHardFactor = 1.5;
const effortEasyFraction = 0.5;
const effortHardRunDays = 2;
const effortNoEasyDays = 6;
const effortSpikeFactor = 1.5;
const effortSpikeMinWeekly = 150.0;
const effortMinRating = 1;
const effortMaxRating = 10;

const _maxHardDays = 7;
const _maxDaysSinceEasy = 28;
const _minReadiness = 0;
const _maxReadiness = 100;

enum LoadSource { heartRate, rating, typeDefault }

final class SessionLoad {
  const new({
    required this.byHeartRate,
    required this.byRating,
    required this.byDefault,
    required this.value,
    required this.source,
  });

  final int? byHeartRate;
  final int? byRating;
  final int byDefault;
  final int value;
  final LoadSource source;
}

double _minutes(Duration duration) => duration.inSeconds / 60;

/// The load of one session: the higher of the heart rate figure and the
/// rating figure, or the type default when neither exists.
SessionLoad sessionLoad({
  required Duration elapsed,
  required double typeDefault,
  Map<int, Duration> timeInZones = const {},
  int? rating,
}) {
  if (elapsed.isNegative) throw ArgumentError.value(elapsed, 'elapsed');
  if (!typeDefault.isFinite || typeDefault < 0) {
    throw ArgumentError.value(typeDefault, 'typeDefault');
  }
  final minutes = _minutes(elapsed);
  final byHeartRate = _heartRateLoad(timeInZones);
  final byRating = _ratingLoad(minutes, rating);
  final byDefault = (minutes * typeDefault).round();
  SessionLoad from(int value, LoadSource source) => SessionLoad(
    byHeartRate: byHeartRate,
    byRating: byRating,
    byDefault: byDefault,
    value: value,
    source: source,
  );
  if (byRating != null && (byHeartRate == null || byRating > byHeartRate)) {
    return from(byRating, LoadSource.rating);
  }
  if (byHeartRate != null) return from(byHeartRate, LoadSource.heartRate);
  return from(byDefault, LoadSource.typeDefault);
}

int? _heartRateLoad(Map<int, Duration> timeInZones) {
  final timed = timeInZones.entries.where((e) => e.value > Duration.zero);
  if (timed.isEmpty) return null;
  return timed
      .fold<double>(0, (sum, e) => sum + _minutes(e.value) * e.key)
      .round();
}

int? _ratingLoad(double minutes, int? rating) {
  if (rating == null) return null;
  if (rating < effortMinRating || rating > effortMaxRating) {
    throw ArgumentError.value(rating, 'rating');
  }
  return (minutes * rating / effortRatingDivisor).round();
}

/// The load of [briskMinutes] of brisk walking outside any session.
int walkingLoad(double briskMinutes) {
  if (!briskMinutes.isFinite || briskMinutes < 0) {
    throw ArgumentError.value(briskMinutes, 'briskMinutes');
  }
  return (effortWalkingLoadFactor * briskMinutes).round();
}

bool isStrengthSession(Duration elapsed) =>
    elapsed >= const Duration(minutes: effortStrengthMinMinutes);

/// The exponential line of [dailyLoad] (oldest first) over [days], seeded
/// with the mean of its first days, or null under [effortMinLoadDays] values.
double? loadLine(List<double> dailyLoad, {required int days}) {
  if (days < 1) throw ArgumentError.value(days, 'days');
  if (dailyLoad.length < effortMinLoadDays) return null;
  final k = 2 / (days + 1);
  final seed = dailyLoad.take(effortLineSeedDays);
  var line = seed.reduce((a, b) => a + b) / effortLineSeedDays;
  for (final load in dailyLoad.skip(effortLineSeedDays)) {
    line = load * k + line * (1 - k);
  }
  return line;
}

/// The load from which a day counts as hard against a 28 day line.
int hardDayFrom(double chronic) {
  if (!chronic.isFinite) throw ArgumentError.value(chronic, 'chronic');
  return math.max(effortHardFloor, (effortHardFactor * chronic).round());
}

final class EffortWeek {
  const new({
    required this.monday,
    required this.points,
    required this.strengthDays,
  });

  final LocalDate monday;
  final double points;
  final int strengthDays;

  bool get covered =>
      points >= effortWeekPoints && strengthDays >= effortWeekStrengthDays;
}

/// The calendar week of [today], from its Monday to today, against the two
/// weekly targets.
EffortWeek effortWeek(
  Iterable<DailyValue> dailyPoints,
  Set<LocalDate> strengthDays, {
  required LocalDate today,
}) {
  final monday = mondayOf(today);
  bool inWeek(LocalDate date) =>
      date.compareTo(monday) >= 0 && date.compareTo(today) <= 0;
  final byDate = {for (final point in dailyPoints) point.date: point.value};
  final points = byDate.entries
      .where((e) => inWeek(e.key) && e.value.isFinite && e.value >= 0)
      .fold<double>(0, (sum, e) => sum + e.value);
  return EffortWeek(
    monday: monday,
    points: points,
    strengthDays: strengthDays.where(inWeek).length,
  );
}

enum CoachVerdict { push, maintain, recover }

enum CoachRule {
  sick(CoachVerdict.recover),
  lowReadiness(CoachVerdict.recover),
  hardRun(CoachVerdict.recover),
  noEasyDay(CoachVerdict.recover),
  fairReadiness(CoachVerdict.maintain),
  spike(CoachVerdict.maintain),
  hardYesterday(CoachVerdict.maintain),
  goodReadiness(CoachVerdict.push),
  noReadiness(CoachVerdict.maintain);

  new(this.verdict);

  final CoachVerdict verdict;

  int get number => index + 1;
}

final class CoachAdvice {
  const new({
    required this.rule,
    required this.acute,
    required this.chronic,
    required this.chronicWeekAgo,
    required this.yesterdayLoad,
    required this.hardFrom,
    required this.hardDays,
    required this.daysSinceEasy,
  });

  final CoachRule rule;
  final double? acute;
  final double? chronic;
  final double? chronicWeekAgo;
  final double? yesterdayLoad;
  final int? hardFrom;
  final int hardDays;
  final int daysSinceEasy;
}

/// Today's advice from [dailyLoad] (oldest first, its last value is
/// yesterday), the readiness of the morning and the sick tag.
CoachAdvice coachAdvice({
  required int? readiness,
  required bool sick,
  required List<double> dailyLoad,
}) {
  if (readiness != null && _outOfRange(readiness)) {
    throw ArgumentError.value(readiness, 'readiness');
  }
  final acute = loadLine(dailyLoad, days: effortAcuteDays);
  final chronic = loadLine(dailyLoad, days: effortChronicDays);
  final chronicWeekAgo = _lineBefore(
    dailyLoad,
    dailyLoad.length - DateTime.daysPerWeek,
  );
  final lineBeforeYesterday = _lineBefore(dailyLoad, dailyLoad.length - 1);
  final hardDays = _hardDays(dailyLoad);
  final daysSinceEasy = _daysSinceEasy(dailyLoad, chronic);
  return CoachAdvice(
    rule: _rule(
      readiness: readiness,
      sick: sick,
      acute: acute,
      chronicWeekAgo: chronicWeekAgo,
      hardDays: hardDays,
      daysSinceEasy: daysSinceEasy,
    ),
    acute: acute,
    chronic: chronic,
    chronicWeekAgo: chronicWeekAgo,
    yesterdayLoad: dailyLoad.lastOrNull,
    hardFrom: lineBeforeYesterday == null
        ? null
        : hardDayFrom(lineBeforeYesterday),
    hardDays: hardDays,
    daysSinceEasy: daysSinceEasy,
  );
}

bool _outOfRange(int readiness) =>
    readiness < _minReadiness || readiness > _maxReadiness;

double? _lineBefore(List<double> dailyLoad, int index) =>
    loadLine(dailyLoad.sublist(0, math.max(index, 0)), days: effortChronicDays);

// A day is tested against the line through the day before it, so a hard day
// never raises its own threshold.
bool _isHard(List<double> dailyLoad, int index) {
  final line = _lineBefore(dailyLoad, index);
  return line != null && dailyLoad[index] >= hardDayFrom(line);
}

int _hardDays(List<double> dailyLoad) {
  var count = 0;
  for (var i = dailyLoad.length - 1; i >= 0 && count < _maxHardDays; i--) {
    if (!_isHard(dailyLoad, i)) return count;
    count++;
  }
  return count;
}

int _daysSinceEasy(List<double> dailyLoad, double? chronic) {
  if (chronic == null || chronic <= 0) return 0;
  final easyUnder = effortEasyFraction * chronic;
  return dailyLoad.reversed
      .take(_maxDaysSinceEasy)
      .takeWhile((load) => load >= easyUnder)
      .length;
}

CoachRule _rule({
  required int? readiness,
  required bool sick,
  required double? acute,
  required double? chronicWeekAgo,
  required int hardDays,
  required int daysSinceEasy,
}) {
  if (sick) return CoachRule.sick;
  if (readiness != null && readiness < readinessFairFrom) {
    return CoachRule.lowReadiness;
  }
  if (hardDays >= effortHardRunDays) return CoachRule.hardRun;
  if (daysSinceEasy >= effortNoEasyDays) return CoachRule.noEasyDay;
  if (readiness != null && readiness < readinessGoodFrom) {
    return CoachRule.fairReadiness;
  }
  if (_isSpike(acute, chronicWeekAgo)) return CoachRule.spike;
  if (hardDays >= 1) return CoachRule.hardYesterday;
  if (readiness != null) return CoachRule.goodReadiness;
  return CoachRule.noReadiness;
}

bool _isSpike(double? acute, double? chronicWeekAgo) {
  if (acute == null || chronicWeekAgo == null) return false;
  return chronicWeekAgo * DateTime.daysPerWeek >= effortSpikeMinWeekly &&
      acute > effortSpikeFactor * chronicWeekAgo;
}

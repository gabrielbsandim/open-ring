import 'package:metrics/src/baseline.dart';
import 'package:metrics/src/level_goal.dart';
import 'package:metrics/src/local_date.dart';
import 'package:metrics/src/overall_score.dart';
import 'package:metrics/src/sleep_night.dart';
import 'package:metrics/src/sleep_regularity.dart';

const overallWindowDays = 28;
const overallMinDays = 14;
const overallWeeks = 12;

/// The Mondays whose Overall is shown, oldest first, ending at the last
/// Monday on or before [today].
List<LocalDate> overallMondays(LocalDate today, {int weeks = overallWeeks}) {
  final last = mondayOf(today);
  return [
    for (var back = weeks - 1; back >= 0; back--) last.addDays(-7 * back),
  ];
}

double? _mean(List<double> values) {
  if (values.length < overallMinDays) return null;
  return values.reduce((a, b) => a + b) / values.length;
}

/// The inputs of the Overall published on [monday]: every window is the 28
/// days that end the day before, without the [excluded] days.
OverallInputs overallInputsOn(
  LocalDate monday, {
  required Iterable<SleepNight> nights,
  required Iterable<SleepSpan> spans,
  required Set<LocalDate> wornDays,
  required Set<LocalDate> excluded,
  required Iterable<DailyValue> resting,
  required Iterable<DailyValue> steps,
  required Iterable<DailyValue> intensity,
  required Iterable<LocalDate> strengthDates,
  double? fitnessPercentile,
  double? waistToHeight,
  double? bmi,
  bool olderAdult = false,
}) {
  final window = {
    for (var back = 1; back <= overallWindowDays; back++)
      if (!excluded.contains(monday.addDays(-back))) monday.addDays(-back),
  };
  final worn = window.intersection(wornDays);
  final stepsOn = {for (final day in steps) day.date: day.value};
  final minutesOn = {for (final day in intensity) day.date: day.value};
  final enough = worn.length >= overallMinDays;
  final perWeek = enough ? 7 / worn.length : 0.0;
  return OverallInputs(
    fitnessPercentile: fitnessPercentile,
    restingHeartRate: _mean([
      for (final day in resting)
        if (window.contains(day.date)) day.value,
    ]),
    sleepHours: _mean([
      for (final night in nights)
        if (window.contains(night.date))
          night.asleep.inSeconds / Duration.secondsPerHour,
    ]),
    sleepRegularity: sleepRegularity(spans, days: worn)?.index,
    weeklyMinutes: enough
        ? perWeek * worn.fold<double>(0, (sum, d) => sum + (minutesOn[d] ?? 0))
        : null,
    strengthPerWeek: window.length < overallMinDays
        ? 0
        : 7 *
              strengthDates.where(window.contains).toSet().length /
              window.length,
    dailySteps: _mean([for (final day in worn) stepsOn[day] ?? 0]),
    olderAdult: olderAdult,
    waistToHeight: waistToHeight,
    bmi: bmi,
  );
}

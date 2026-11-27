import 'package:meta/meta.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/features/body/domain/weigh_in.dart';
import 'package:open_ring/features/open_score/domain/day_tag.dart';

// The first day of the oldest Monday's window: the last Monday can be up to
// six days before today, so the reach is not a constant.
LocalDate overallHistoryStart(LocalDate today) =>
    overallMondays(today).first.addDays(-overallWindowDays);
const olderAdultFromAge = 60;

/// The position of the best estimate of the 90 days before [day], for the age
/// the person reaches in the year of [day], or null when a part is missing.
double? overallFitnessOn(
  LocalDate day, {
  required Iterable<FitnessEffort> efforts,
  required double? restingBpm,
  required int? birthYear,
  required FitnessSex? sex,
  int? maxHeartRate,
}) {
  if (restingBpm == null || birthYear == null || sex == null) return null;
  final age = day.year - birthYear;
  if (age < fitnessMinAge || age > fitnessMaxAge) return null;
  final best = bestVo2max(
    efforts,
    day: day,
    restingBpm: restingBpm,
    maxBpm: (maxHeartRate ?? maxHeartRateForAge(age)).toDouble(),
  );
  if (best == null) return null;
  return fitnessPercentile(best, age: age, sex: sex);
}

typedef OverallWeek = ({
  LocalDate date,
  OverallInputs inputs,
  ScoreResult<OverallFactor> result,
});

// Rest is part of a routine, so only the days that are not leave the windows.
Set<LocalDate> overallExcluded(Map<LocalDate, DayTag> tags) => {
  for (final MapEntry(key: date, value: tag) in tags.entries)
    if (tag != DayTag.rest) date,
};

typedef OverallBody = ({double? waistToHeight, double? bmi});

LocalDate _dateOf(WeighIn entry) =>
    LocalDate.fromInstant(entry.at, Duration(minutes: entry.offsetMinutes));

// The last weight and the last waist logged before the Monday.
OverallBody overallBodyOn(
  LocalDate monday, {
  required Iterable<WeighIn> weighIns,
  required double? heightCentimeters,
}) {
  if (heightCentimeters == null || heightCentimeters <= 0) {
    return (waistToHeight: null, bmi: null);
  }
  final before = [
    for (final entry in weighIns)
      if (_dateOf(entry).compareTo(monday) < 0) entry,
  ]..sort((a, b) => a.at.compareTo(b.at));
  final meters = heightCentimeters / 100;
  final waist = before
      .map((entry) => entry.waistCentimeters)
      .nonNulls
      .lastOrNull;
  final kilograms = before.lastOrNull?.kilograms;
  return (
    waistToHeight: waist == null ? null : waist / heightCentimeters,
    bmi: kilograms == null ? null : kilograms / (meters * meters),
  );
}

@immutable
final class OverallHistory {
  new({
    required this.today,
    required Iterable<OverallWeek> weeks,
    required this.current,
    required this.nights,
  }) : weeks = List.unmodifiable(weeks);

  factory collect({
    required LocalDate today,
    required Iterable<SleepNight> sessions,
    required Iterable<BpmSample> heartRate,
    required Duration utcOffset,
    required Iterable<DailyValue> steps,
    required Iterable<DailyValue> intensity,
    required Iterable<LocalDate> strengthDates,
    required Map<LocalDate, DayTag> tags,
    Iterable<WeighIn> weighIns = const [],
    double? heightCentimeters,
    int? birthYear,
    Iterable<FitnessEffort> efforts = const [],
    FitnessSex? sex,
    int? maxHeartRate,
  }) {
    final nights = mainNightByDate(sessions).values.toList();
    final spans = [for (final session in sessions) ...session.spans];
    final wornDays = {
      for (final sample in heartRate)
        LocalDate.fromInstant(sample.at, utcOffset),
    };
    final resting = [
      for (final night in nights)
        if (restingHeartRate(
              heartRate.where(
                (s) => !s.at.isBefore(night.start) && s.at.isBefore(night.end),
              ),
            )
            case final value?)
          (date: night.date, value: value),
    ];
    final excluded = overallExcluded(tags);
    final age = birthYear == null ? null : today.year - birthYear;
    OverallWeek weekOf(LocalDate monday) {
      final body = overallBodyOn(
        monday,
        weighIns: weighIns,
        heightCentimeters: heightCentimeters,
      );
      OverallInputs inputsWith(double? fitness) => overallInputsOn(
        monday,
        nights: nights,
        spans: spans,
        wornDays: wornDays,
        excluded: excluded,
        resting: resting,
        steps: steps,
        intensity: intensity,
        strengthDates: strengthDates,
        fitnessPercentile: fitness,
        waistToHeight: body.waistToHeight,
        bmi: body.bmi,
        olderAdult: age != null && age >= olderAdultFromAge,
      );
      final base = inputsWith(null);
      final fitness = overallFitnessOn(
        monday,
        efforts: efforts,
        restingBpm: base.restingHeartRate,
        birthYear: birthYear,
        sex: sex,
        maxHeartRate: maxHeartRate,
      );
      final inputs = fitness == null ? base : inputsWith(fitness);
      return (date: monday, inputs: inputs, result: inputs.score);
    }

    final weeks = overallMondays(today).map(weekOf).toList();
    final last = weeks.last;
    // The first score does not wait for a Monday: it is the one of the first
    // day after the last Monday on which the minimum was met.
    final early = [
      for (
        var day = last.date.addDays(1);
        day.compareTo(today) <= 0;
        day = day.addDays(1)
      )
        weekOf(day),
    ].where((week) => week.result is Scored<OverallFactor>).firstOrNull;
    return OverallHistory(
      today: today,
      weeks: weeks,
      current: last.result is Scored<OverallFactor> ? last : early ?? last,
      nights: resting
          .where((night) => !excluded.contains(night.date))
          .where((night) => today.daysSince(night.date) >= 1)
          .where((night) => today.daysSince(night.date) <= overallWindowDays)
          .length,
    );
  }

  final LocalDate today;
  final List<OverallWeek> weeks;

  // The week on screen: the last Monday, or an earlier first score.
  final OverallWeek current;

  // Nights with a resting heart rate in the window a score would read today.
  final int nights;

  LocalDate get nextUpdate => mondayOf(today).addDays(7);

  // The Monday before the one on screen, only when both are scored Mondays.
  int? get previous {
    if (weeks.length < 2 || current.date != weeks.last.date) return null;
    return switch (weeks[weeks.length - 2].result) {
      final Scored<OverallFactor> before => before.value,
      InsufficientData() => null,
    };
  }

  Scored<OverallFactor>? get scored => switch (current.result) {
    final Scored<OverallFactor> scored => scored,
    InsufficientData() => null,
  };
}

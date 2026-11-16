import 'package:meta/meta.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/features/body/domain/weigh_in.dart';
import 'package:open_ring/features/open_score/domain/day_tag.dart';

// The first day of the oldest Monday's window: the last Monday can be up to
// six days before today, so the reach is not a constant.
LocalDate overallHistoryStart(LocalDate today) =>
    overallMondays(today).first.addDays(-overallWindowDays);
const olderAdultFromAge = 60;

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
  new({required this.today, required Iterable<OverallWeek> weeks})
    : weeks = List.unmodifiable(weeks);

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
      final inputs = overallInputsOn(
        monday,
        nights: nights,
        spans: spans,
        wornDays: wornDays,
        excluded: excluded,
        resting: resting,
        steps: steps,
        intensity: intensity,
        strengthDates: strengthDates,
        waistToHeight: body.waistToHeight,
        bmi: body.bmi,
        olderAdult: age != null && age >= olderAdultFromAge,
      );
      return (date: monday, inputs: inputs, result: inputs.score);
    }

    return OverallHistory(
      today: today,
      weeks: overallMondays(today).map(weekOf),
    );
  }

  final LocalDate today;
  final List<OverallWeek> weeks;

  OverallWeek get current => weeks.last;

  Scored<OverallFactor>? get scored => switch (current.result) {
    final Scored<OverallFactor> scored => scored,
    InsufficientData() => null,
  };
}

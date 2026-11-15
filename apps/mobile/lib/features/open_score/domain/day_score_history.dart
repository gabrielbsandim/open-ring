import 'package:meta/meta.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/features/activity/domain/activity_history_reader.dart';
import 'package:open_ring/features/heart/application/heart_view.dart';
import 'package:open_ring/features/trends/domain/trend_history.dart';
import 'package:open_ring/features/trends/domain/trend_metric.dart';

final int dayScoreHistoryDays = trendHistoryDays;
final int dayIntensityDays = dayScoreHistoryDays + intensityWindowDays - 1;
final int dayStressDays = dayScoreHistoryDays + baselineWindowDays;

typedef WorkoutCredit = ({
  LocalDate date,
  DateTime start,
  DateTime end,
  IntensityMinutes minutes,
});

List<DailyValue> _sorted(Map<LocalDate, double> byDate) =>
    [for (final entry in byDate.entries) (date: entry.key, value: entry.value)]
      ..sort((a, b) => a.date.compareTo(b.date));

// One value for each day with steps or a workout, so a day the ring was worn
// and nothing counted is a zero and a day without the ring is absent.
List<DailyValue> dailyIntensity({
  required Iterable<ActivitySlot> slots,
  required Iterable<WorkoutCredit> workouts,
}) {
  final spans = [for (final w in workouts) (start: w.start, end: w.end)];
  final totals = <LocalDate, double>{};
  for (final slot in slots) {
    if (slot.steps <= 0) continue;
    final walked = walkingIntensity([
      (start: slot.start, duration: slot.duration, steps: slot.steps),
    ], workouts: spans);
    totals[slot.date] = (totals[slot.date] ?? 0) + walked.equivalent;
  }
  for (final workout in workouts) {
    totals[workout.date] =
        (totals[workout.date] ?? 0) + workout.minutes.equivalent;
  }
  return _sorted(totals);
}

List<DailyValue> dailyStress(
  Iterable<StressReading> readings, {
  required Duration utcOffset,
}) {
  final byDate = <LocalDate, List<StressReading>>{};
  for (final reading in readings) {
    final date = LocalDate.fromInstant(reading.at, utcOffset);
    byDate.putIfAbsent(date, () => []).add(reading);
  }
  return _sorted({
    for (final entry in byDate.entries)
      entry.key: ?stressDaySummary(entry.value)?.mean,
  });
}

@immutable
final class DayScoreHistory {
  new({required this.today, required Map<LocalDate, DayScoreInputs> days})
    : _inputs = Map.unmodifiable(days),
      _days = Map.unmodifiable({
        for (final entry in days.entries) entry.key: entry.value.score,
      });

  factory collect({
    required LocalDate today,
    required TrendHistory history,
    required List<DailyValue> stress,
    required List<DailyValue> intensity,
    required int stepGoal,
  }) {
    final sleep = history.values(TrendMetric.sleepScore);
    final steps = history.values(TrendMetric.steps);
    final hrv = history.values(TrendMetric.hrv);
    final resting = history.values(TrendMetric.restingHeartRate);
    final spo2 = history.values(TrendMetric.spo2);
    DayScoreInputs inputsOn(LocalDate date) => DayScoreInputs(
      sleepScore: _valueOn(sleep, date)?.round(),
      steps: _valueOn(steps, date)?.round(),
      stepGoal: stepGoal,
      intensityMinutes: weeklyIntensityMinutes(intensity, today: date),
      hrv: BaselineInput(
        today: _valueOn(hrv, date),
        baseline: hrvBaseline(hrv, today: date),
      ).deviation,
      restingHeartRate: BaselineInput(
        today: _valueOn(resting, date),
        baseline: restingHeartRateBaseline(resting, today: date),
      ).deviation,
      stress: BaselineInput(
        today: _valueOn(stress, date),
        baseline: stressBaseline(stress, today: date),
      ).deviation,
      spo2Mean: _valueOn(spo2, date),
    );
    return DayScoreHistory(
      today: today,
      days: {
        for (var age = dayScoreHistoryDays - 1; age >= 0; age--)
          today.addDays(-age): inputsOn(today.addDays(-age)),
      },
    );
  }

  final LocalDate today;
  final Map<LocalDate, DayScoreInputs> _inputs;
  final Map<LocalDate, ScoreResult<DayScoreFactor>> _days;

  Iterable<LocalDate> get dates => _days.keys;

  ScoreResult<DayScoreFactor>? on(LocalDate date) => _days[date];

  DayScoreInputs? inputsOn(LocalDate date) => _inputs[date];

  Scored<DayScoreFactor>? scoredOn(LocalDate date) => switch (_days[date]) {
    final Scored<DayScoreFactor> scored => scored,
    _ => null,
  };

  LocalDate? get firstScored {
    for (final entry in _days.entries) {
      if (entry.value is Scored<DayScoreFactor>) return entry.key;
    }
    return null;
  }

  static double? _valueOn(List<DailyValue> values, LocalDate date) {
    double? found;
    for (final v in values) {
      if (v.date == date) found = v.value;
    }
    return found;
  }
}

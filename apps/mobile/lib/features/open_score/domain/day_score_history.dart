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

// How far today is from the two rules that keep a factor out in the first
// days: the active days of the week and the least advanced baseline.
typedef DayScoreProgress = ({
  int activeDays,
  int activeNeeded,
  int baselineDays,
  int baselineNeeded,
});

int _activeDays(Iterable<DailyValue> intensity, LocalDate today) => {
  for (final day in intensity)
    if (_countsAsActive(day, today)) day.date,
}.length;

bool _countsAsActive(DailyValue day, LocalDate today) {
  final age = today.daysSince(day.date);
  if (age < 0 || age >= intensityWindowDays) return false;
  return day.value.isFinite && day.value >= 0;
}

int _collected(BaselineResult baseline) => switch (baseline) {
  BaselineBuilding(:final daysCollected) => daysCollected,
  BaselineReady() => baselineMinDays,
};

@immutable
final class DayScoreHistory {
  new({
    required this.today,
    required Map<LocalDate, DayScoreInputs> days,
    this.progress,
  }) : _inputs = Map.unmodifiable(days),
       _days = Map.unmodifiable({
         for (final entry in days.entries) entry.key: entry.value.score,
       });

  factory collect({
    required LocalDate today,
    required TrendHistory history,
    required List<DailyValue> stress,
    required List<DailyValue> intensity,
    required int stepGoal,
    required List<DailyValue> activeLoad,
  }) {
    final sleep = history.values(TrendMetric.sleepScore);
    final steps = history.values(TrendMetric.steps);
    final hrv = history.withLead(TrendMetric.hrv);
    final resting = history.withLead(TrendMetric.restingHeartRate);
    final spo2 = history.values(TrendMetric.spo2);
    DayScoreInputs inputsOn(LocalDate date) {
      final sleepScore = _valueOn(sleep, date)?.round();
      final hrvDeviation = BaselineInput(
        today: _valueOn(hrv, date),
        baseline: hrvBaseline(hrv, today: date),
      ).deviation;
      final restingDeviation = BaselineInput(
        today: _valueOn(resting, date),
        baseline: restingHeartRateBaseline(resting, today: date),
      ).deviation;
      final ready = readiness(
        sleepScore: sleepScore,
        hrv: hrvDeviation,
        restingHeartRate: restingDeviation,
        activityLoad: activityLoad(activeLoad, today: date),
      );
      return DayScoreInputs(
        sleepScore: sleepScore,
        steps: _valueOn(steps, date)?.round(),
        stepGoal: stepGoal,
        intensityMinutes: weeklyIntensityMinutes(intensity, today: date),
        hrv: hrvDeviation,
        restingHeartRate: restingDeviation,
        stress: BaselineInput(
          today: _valueOn(stress, date),
          baseline: stressBaseline(stress, today: date),
        ).deviation,
        spo2Mean: _valueOn(spo2, date),
        readiness: switch (ready) {
          Scored(:final value) => value,
          InsufficientData() => null,
        },
      );
    }

    final baselines = [
      hrvBaseline(hrv, today: today),
      restingHeartRateBaseline(resting, today: today),
      stressBaseline(stress, today: today),
    ].map(_collected);
    return DayScoreHistory(
      today: today,
      progress: (
        activeDays: _activeDays(intensity, today),
        activeNeeded: intensityMinDays,
        baselineDays: baselines.reduce((a, b) => a < b ? a : b),
        baselineNeeded: baselineMinDays,
      ),
      days: {
        for (var age = dayScoreHistoryDays - 1; age >= 0; age--)
          today.addDays(-age): inputsOn(today.addDays(-age)),
      },
    );
  }

  final LocalDate today;
  final DayScoreProgress? progress;
  final Map<LocalDate, DayScoreInputs> _inputs;
  final Map<LocalDate, ScoreResult<DayScoreFactor>> _days;

  Iterable<LocalDate> get dates => _days.keys;

  ScoreResult<DayScoreFactor>? on(LocalDate date) => _days[date];

  DayScoreInputs? inputsOn(LocalDate date) => _inputs[date];

  Scored<DayScoreFactor>? scoredOn(LocalDate date) => switch (_days[date]) {
    final Scored<DayScoreFactor> scored => scored,
    _ => null,
  };

  // The mean of the closed days with full coverage: today is still moving and
  // a rescaled score does not compare with a full one.
  // [excluded] holds the days the user set aside; they enter no average.
  ({int value, int count})? fullAverage(
    int days, {
    Set<LocalDate> excluded = const {},
  }) {
    final values = [
      for (var age = 1; age < days; age++)
        ?_fullOn(today.addDays(-age), excluded),
    ];
    if (values.isEmpty) return null;
    final sum = values.fold(0, (total, value) => total + value);
    return (value: (sum / values.length).round(), count: values.length);
  }

  int? _fullOn(LocalDate date, Set<LocalDate> excluded) {
    if (excluded.contains(date)) return null;
    final scored = scoredOn(date);
    if (scored == null || !scored.isFull) return null;
    return scored.value;
  }

  List<DailyValue> get scores => scoresExcept(const {});

  // The scored days without the ones the user set aside.
  List<DailyValue> scoresExcept(Set<LocalDate> excluded) => [
    for (final entry in _days.entries)
      if (entry.value case Scored(:final value)
          when !excluded.contains(entry.key))
        (date: entry.key, value: value.toDouble()),
  ];

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

import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/features/activity/domain/activity_history_reader.dart';
import 'package:open_ring/features/open_score/domain/day_score_history.dart';
import 'package:open_ring/features/trends/domain/trend_history.dart';
import 'package:open_ring/features/trends/domain/trend_metric.dart';

const today = LocalDate(2026, 11, 15);

ActivitySlot slot(DateTime start, int steps) => ActivitySlot(
  start: start,
  utcOffset: Duration.zero,
  duration: const Duration(minutes: 15),
  steps: steps,
  activeKilocalories: 0,
  distanceMeters: 0,
);

List<DailyValue> flat(int days, double value, {int skipAge = -1}) => [
  for (var age = days - 1; age >= 0; age--)
    if (age != skipAge) (date: today.addDays(-age), value: value),
];

TrendHistory historyOf({
  required int days,
  double sleep = 80,
  double steps = 8000,
  int sleepMissingAge = -1,
}) => TrendHistory(
  today: today,
  values: {
    TrendMetric.sleepScore: flat(days, sleep, skipAge: sleepMissingAge),
    TrendMetric.steps: flat(days, steps),
    TrendMetric.hrv: flat(days, 45),
    TrendMetric.restingHeartRate: flat(days, 58),
    TrendMetric.spo2: flat(days, 96),
  },
  bands: const {},
);

void main() {
  group('daily intensity', () {
    final morning = DateTime.utc(2026, 11, 15, 8);

    test('brisk buckets count and slow ones leave a zero for the day', () {
      final result = dailyIntensity(
        slots: [
          slot(morning, 1600),
          slot(morning.add(const Duration(minutes: 15)), 1500),
          slot(morning.add(const Duration(minutes: 30)), 400),
          slot(morning.subtract(const Duration(days: 1)), 300),
          slot(morning.subtract(const Duration(days: 2)), 0),
        ],
        workouts: const [],
      );

      expect(result, [
        (date: today.addDays(-1), value: 0.0),
        (date: today, value: 30.0),
      ]);
    });

    test('a workout adds its credit and takes over the buckets it covers', () {
      final result = dailyIntensity(
        slots: [
          slot(morning, 1600),
          slot(morning.add(const Duration(hours: 2)), 1600),
        ],
        workouts: [
          (
            date: today,
            start: morning.add(const Duration(minutes: 5)),
            end: morning.add(const Duration(minutes: 35)),
            minutes: const IntensityMinutes(vigorous: 30),
          ),
        ],
      );

      expect(result, [(date: today, value: 75.0)]);
    });

    test('a workout alone makes its day a day with data', () {
      final result = dailyIntensity(
        slots: const [],
        workouts: [
          (
            date: today.addDays(-3),
            start: morning,
            end: morning,
            minutes: IntensityMinutes.none,
          ),
        ],
      );

      expect(result, [(date: today.addDays(-3), value: 0.0)]);
    });
  });

  group('daily stress', () {
    List<StressReading> readings(DateTime from, List<int> levels) => [
      for (var i = 0; i < levels.length; i++)
        (at: from.add(Duration(minutes: 30 * i)), level: levels[i]),
    ];

    test('is the mean of each local date with enough readings', () {
      final result = dailyStress([
        ...readings(DateTime.utc(2026, 11, 14, 9), [30, 40, 50]),
        ...readings(DateTime.utc(2026, 11, 15, 9), [20, 20]),
      ], utcOffset: Duration.zero);

      expect(result, [(date: today.addDays(-1), value: 40.0)]);
    });

    test('follows the offset, not the UTC date', () {
      final late = readings(DateTime.utc(2026, 11, 14, 23), [30, 40, 50]);

      final result = dailyStress(late, utcOffset: const Duration(hours: 3));

      expect(result.single.date, today);
    });
  });

  group('history', () {
    DayScoreHistory collect(
      TrendHistory history, {
      List<DailyValue>? stress,
      List<DailyValue>? intensity,
    }) => DayScoreHistory.collect(
      today: today,
      history: history,
      stress: stress ?? flat(40, 40),
      intensity: intensity ?? flat(40, 30),
      stepGoal: 8000,
      activeLoad: const [],
    );

    test('counts the active days of the week against the rule', () {
      final result = collect(historyOf(days: 30), intensity: flat(3, 30));

      expect(result.progress?.activeDays, 3);
      expect(result.progress?.activeNeeded, intensityMinDays);
    });

    test('an active day older than the week does not count', () {
      final result = collect(historyOf(days: 30), intensity: flat(40, 30));

      expect(result.progress?.activeDays, intensityWindowDays);
    });

    test('the baseline count is the least advanced of the three', () {
      final result = collect(historyOf(days: 30), stress: flat(3, 40));

      expect(result.progress?.baselineDays, 2);
      expect(result.progress?.baselineNeeded, baselineMinDays);
    });

    test('ready baselines count as the days they need', () {
      final result = collect(historyOf(days: 30));

      expect(result.progress?.baselineDays, baselineMinDays);
    });

    test('covers ninety days ending today', () {
      final history = collect(historyOf(days: 30));

      expect(history.dates, hasLength(dayScoreHistoryDays));
      expect(history.dates.last, today);
      expect(history.on(today.addDays(1)), isNull);
      expect(history.on(today.addDays(-dayScoreHistoryDays)), isNull);
    });

    test('a day with every input has full coverage and its points', () {
      final scored = collect(historyOf(days: 30)).scoredOn(today)!;

      expect(scored.isFull, isTrue);
      expect(scored.of(DayScoreFactor.sleep)!.points, closeTo(24, 1e-9));
      expect(scored.of(DayScoreFactor.steps)!.subscore, 1);
      expect(scored.of(DayScoreFactor.intensity)!.value, 210);
      expect(scored.of(DayScoreFactor.hrv)!.value, closeTo(0, 1e-9));
      expect(scored.of(DayScoreFactor.stress)!.value, closeTo(0, 1e-9));
      expect(scored.of(DayScoreFactor.spo2)!.subscore, 1);
    });

    test('a day without its night has no score and names what is missing', () {
      final history = collect(historyOf(days: 30, sleepMissingAge: 2));

      final result = history.on(today.addDays(-2));

      expect(history.scoredOn(today.addDays(-2)), isNull);
      expect((result! as InsufficientData<DayScoreFactor>).missing, [
        DayScoreFactor.sleep,
      ]);
    });

    test('the first score comes on the fourth day of data', () {
      final history = collect(
        historyOf(days: 10),
        stress: flat(10, 40),
        intensity: flat(10, 30),
      );
      final first = today.addDays(-9);

      expect(history.scoredOn(first), isNull);
      expect(history.scoredOn(first.addDays(2)), isNull);
      expect(history.firstScored, first.addDays(3));
      expect(history.scoredOn(first.addDays(3))!.coverage, 70);
    });

    test('baselines join the score once seven earlier days exist', () {
      final history = collect(
        historyOf(days: 10),
        stress: flat(10, 40),
        intensity: flat(10, 30),
      );
      final first = today.addDays(-9);

      expect(history.scoredOn(first.addDays(6))!.coverage, 70);
      expect(history.scoredOn(first.addDays(7))!.isFull, isTrue);
    });

    test('a rest day keeps the minutes of the week before it', () {
      final intensity = [
        for (var age = 6; age >= 1; age--)
          (date: today.addDays(-age), value: 25.0),
        (date: today, value: 0.0),
      ];

      final scored = collect(
        historyOf(days: 30),
        intensity: intensity,
      ).scoredOn(today)!;

      expect(scored.of(DayScoreFactor.intensity)!.value, 150);
      expect(scored.of(DayScoreFactor.intensity)!.subscore, 1);
    });
  });
}

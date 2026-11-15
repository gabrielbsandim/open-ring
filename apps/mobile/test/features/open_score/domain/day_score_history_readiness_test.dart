import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/features/activity/domain/activity_history_reader.dart';
import 'package:open_ring/features/open_score/domain/day_score_history.dart';
import 'package:open_ring/features/today/application/readiness_trend.dart';
import 'package:open_ring/features/trends/domain/trend_history.dart';
import 'package:open_ring/features/trends/domain/trend_metric.dart';

const today = LocalDate(2026, 11, 15);
const days = 40;

List<DailyValue> series(double Function(int age) valueAt) => [
  for (var age = days - 1; age >= 0; age--)
    (date: today.addDays(-age), value: valueAt(age)),
];

TrendHistory wavyHistory() => TrendHistory(
  today: today,
  values: {
    TrendMetric.sleepScore: series((age) => 40.0 + (age * 13) % 50),
    TrendMetric.steps: series((age) => 6000.0 + (age * 211) % 4000),
    TrendMetric.hrv: series((age) => 35.0 + (age * 7) % 20),
    TrendMetric.restingHeartRate: series((age) => 55.0 + (age * 5) % 9),
    TrendMetric.spo2: series((age) => 96),
  },
  bands: const {},
);

List<DailyActivity> wavyActivity() => [
  for (var age = days - 1; age >= 0; age--)
    DailyActivity(
      date: today.addDays(-age),
      steps: 8000,
      activeKilocalories: age < 4 ? 900.0 : 300.0 + (age * 37) % 200,
      distanceMeters: 5000,
    ),
];

void main() {
  test('every day takes the readiness the Readiness trend gives it', () {
    final history = wavyHistory();
    final activity = wavyActivity();
    final trend = ReadinessTrend.collect(
      today: today,
      history: history,
      activity: activity,
    );
    final collected = DayScoreHistory.collect(
      today: today,
      history: history,
      stress: series((age) => 40),
      intensity: series((age) => 30),
      stepGoal: 8000,
      activeLoad: [for (final day in activity) day.activeLoad],
    );

    expect(trend.values, hasLength(14));
    expect(trend.scored, isNotEmpty);
    for (var index = 0; index < trend.values.length; index++) {
      final date = trend.firstDate.addDays(index);
      expect(
        collected.inputsOn(date)!.readiness,
        trend.values[index],
        reason: '$date',
      );
    }
  });

  test('a day without an active load list can still have a null readiness', () {
    final collected = DayScoreHistory.collect(
      today: today,
      history: wavyHistory(),
      stress: series((age) => 40),
      intensity: series((age) => 30),
      stepGoal: 8000,
      activeLoad: const [],
    );
    final trend = ReadinessTrend.collect(
      today: today,
      history: wavyHistory(),
      activity: const [],
    );

    expect(collected.inputsOn(today)!.readiness, trend.values.last);
  });
}

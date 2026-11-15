import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/features/heart/application/heart_view.dart';
import 'package:open_ring/features/open_score/domain/day_score_history.dart';
import 'package:open_ring/features/trends/domain/trend_history.dart';
import 'package:open_ring/features/trends/domain/trend_metric.dart';

const today = LocalDate(2026, 11, 15);

List<DailyValue> span(int oldest, int newest, double Function(int age) at) => [
  for (var age = oldest; age >= newest; age--)
    (date: today.addDays(-age), value: at(age)),
];

double hrvAt(int age) => 35.0 + (age * 7) % 20;

double restingAt(int age) => 55.0 + (age * 5) % 9;

DayScoreHistory collect({required bool lead}) => DayScoreHistory.collect(
  today: today,
  history: TrendHistory(
    today: today,
    values: {
      TrendMetric.sleepScore: span(89, 0, (age) => 80),
      TrendMetric.steps: span(89, 0, (age) => 8000),
      TrendMetric.hrv: span(89, 0, hrvAt),
      TrendMetric.restingHeartRate: span(89, 0, restingAt),
    },
    bands: const {},
    lead: {
      if (lead) TrendMetric.hrv: span(117, 90, hrvAt),
      if (lead) TrendMetric.restingHeartRate: span(117, 90, restingAt),
    },
  ),
  stress: const [],
  intensity: const [],
  stepGoal: 8000,
  activeLoad: span(117, 0, (age) => 300),
);

void main() {
  test('the oldest day of the history has a readiness and a 28 day '
      'baseline', () {
    final oldest = collect(lead: true).inputsOn(today.addDays(-89))!;
    final full = hrvBaseline(span(117, 0, hrvAt), today: today.addDays(-89));

    expect(oldest.readiness, isNotNull);
    expect(
      oldest.hrv!.zScore,
      BaselineInput(today: hrvAt(89), baseline: full).deviation!.zScore,
    );
  });

  test('without the nights before the history the oldest day has none', () {
    final oldest = collect(lead: false).inputsOn(today.addDays(-89))!;

    expect(oldest.hrv, isNull);
    expect(oldest.readiness, isNull);
  });

  test('a recent day reads the same with and without those nights', () {
    final date = today.addDays(-20);

    expect(
      collect(lead: true).inputsOn(date)!.readiness,
      collect(lead: false).inputsOn(date)!.readiness,
    );
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/features/activity/domain/step_goal_history.dart';
import 'package:open_ring/features/open_score/domain/day_score_history.dart';
import 'package:open_ring/features/trends/domain/trend_history.dart';
import 'package:open_ring/features/trends/domain/trend_metric.dart';

const _today = LocalDate(2026, 12, 8);
const _dec3 = LocalDate(2026, 12, 3);
const _dec6 = LocalDate(2026, 12, 6);
const _dec7 = LocalDate(2026, 12, 7);

List<DailyValue> _span(int oldest, double value) => [
  for (var age = oldest; age >= 0; age--)
    (date: _today.addDays(-age), value: value),
];

DayScoreHistory _collect({
  required int stepGoal,
  List<StepGoalChange> stepGoalChanges = const [],
}) => DayScoreHistory.collect(
  today: _today,
  history: TrendHistory(
    today: _today,
    values: {
      TrendMetric.sleepScore: _span(89, 80),
      TrendMetric.steps: _span(89, 8000),
      TrendMetric.hrv: _span(89, 45),
      TrendMetric.restingHeartRate: _span(89, 58),
      TrendMetric.spo2: _span(89, 96),
    },
    bands: const {},
  ),
  stress: const [],
  intensity: const [],
  stepGoal: stepGoal,
  activeLoad: _span(117, 300),
  stepGoalChanges: stepGoalChanges,
);

void main() {
  final changes = <StepGoalChange>[
    (from: stepGoalBaselineDate, steps: 8000),
    (from: _dec7, steps: 10000),
  ];

  test('a goal change leaves the inputs of an earlier day untouched', () {
    final before = _collect(stepGoal: 8000);
    final after = _collect(stepGoal: 10000, stepGoalChanges: changes);

    expect(after.inputsOn(_dec3)!.stepGoal, before.inputsOn(_dec3)!.stepGoal);
    expect(after.inputsOn(_dec3)!.stepGoal, 8000);
    expect(after.inputsOn(_dec6)!.stepGoal, 8000);
  });

  test('a goal change leaves the score of an earlier day untouched', () {
    final before = _collect(stepGoal: 8000);
    final after = _collect(stepGoal: 10000, stepGoalChanges: changes);

    expect(after.scoredOn(_dec3)!.value, before.scoredOn(_dec3)!.value);
    expect(after.scoredOn(_dec3)!.total, before.scoredOn(_dec3)!.total);
  });

  test('the day of the change and the days after use the new goal', () {
    final after = _collect(stepGoal: 10000, stepGoalChanges: changes);

    expect(after.inputsOn(_dec7)!.stepGoal, 10000);
    expect(after.inputsOn(_today)!.stepGoal, 10000);
  });

  test('without changes every day uses the current goal', () {
    final history = _collect(stepGoal: 9000);

    expect(history.inputsOn(_dec3)!.stepGoal, 9000);
    expect(history.inputsOn(_today)!.stepGoal, 9000);
  });

  test('days before the first change use the current goal', () {
    final history = _collect(
      stepGoal: 7000,
      stepGoalChanges: [(from: _dec7, steps: 10000)],
    );

    expect(history.inputsOn(_dec6)!.stepGoal, 7000);
    expect(history.inputsOn(_dec7)!.stepGoal, 10000);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/features/activity/domain/step_goal_history.dart';
import 'package:open_ring/features/goals/domain/goal.dart';
import 'package:open_ring/features/goals/domain/goal_end.dart';

import '../goal_fixtures.dart';

Goal _goal({LocalDate? startedOn}) =>
    Goal.started(1, goalDraft(startedOn: startedOn ?? goalDay(11, 16)));

GoalWeek _week({
  LocalDate? monday,
  LeverChange? change,
  WeekAnswer? answer = WeekAnswer.accepted,
}) => GoalWeek(
  goalId: 1,
  monday: monday ?? goalDay(11, 30),
  inputs: f1,
  rule: ReviewRule.build,
  action: ReviewAction.nextStep,
  change: change,
  answer: answer,
);

const _stepsTo10000 = LeverChange(kind: LeverKind.steps, from: 9000, to: 10000);

final List<StepGoalChange> _raisedRows = [
  (from: stepGoalBaselineDate, steps: 8000),
  (from: goalDay(11, 23), steps: 10000),
];

void main() {
  group('criterion 2: the plan raised the step goal', () {
    test('returns from the goal before the start to the current one', () {
      final raise = planRaise(
        goal: _goal(),
        weeks: [_week(change: _stepsTo10000)],
        changes: _raisedRows,
        current: 10000,
      );

      expect(raise, (from: 8000, to: 10000));
    });

    test('a goal started today reads X from the day before', () {
      final raise = planRaise(
        goal: _goal(startedOn: goalDay(12, 7)),
        weeks: [_week(change: _stepsTo10000)],
        changes: [
          (from: stepGoalBaselineDate, steps: 8000),
          (from: goalDay(12, 7), steps: 10000),
        ],
        current: 10000,
      );

      expect(raise, (from: 8000, to: 10000));
    });

    test('a hand change during the goal is part of Y', () {
      final raise = planRaise(
        goal: _goal(),
        weeks: [_week(change: _stepsTo10000)],
        changes: [..._raisedRows, (from: goalDay(12, 1), steps: 12000)],
        current: 12000,
      );

      expect(raise, (from: 8000, to: 12000));
    });

    test('one accepted steps week among others is enough', () {
      final raise = planRaise(
        goal: _goal(),
        weeks: [
          _week(
            monday: goalDay(11, 23),
            change: const LeverChange(
              kind: LeverKind.strengthDays,
              from: 2,
              to: 3,
            ),
          ),
          _week(monday: goalDay(11, 30), change: _stepsTo10000),
          _week(monday: goalDay(12, 7), answer: WeekAnswer.declined),
        ],
        changes: _raisedRows,
        current: 10000,
      );

      expect(raise, (from: 8000, to: 10000));
    });
  });

  group('criterion 4: not raised returns null', () {
    test('no step goal change rows', () {
      final raise = planRaise(
        goal: _goal(),
        weeks: [_week(change: _stepsTo10000)],
        changes: const [],
        current: 10000,
      );

      expect(raise, isNull);
    });

    test('a start that predates every row falls back to the current goal', () {
      final raise = planRaise(
        goal: _goal(),
        weeks: [_week(change: _stepsTo10000)],
        changes: [(from: goalDay(12, 1), steps: 10000)],
        current: 10000,
      );

      expect(raise, isNull);
    });

    test('no weeks at all, a raise by hand only', () {
      final raise = planRaise(
        goal: _goal(),
        weeks: const [],
        changes: _raisedRows,
        current: 10000,
      );

      expect(raise, isNull);
    });

    test('a pending week is not an accepted one', () {
      final raise = planRaise(
        goal: _goal(),
        weeks: [_week(change: _stepsTo10000, answer: null)],
        changes: _raisedRows,
        current: 10000,
      );

      expect(raise, isNull);
    });

    test('a declined steps week is not an accepted one', () {
      final raise = planRaise(
        goal: _goal(),
        weeks: [_week(change: _stepsTo10000, answer: WeekAnswer.declined)],
        changes: _raisedRows,
        current: 10000,
      );

      expect(raise, isNull);
    });

    test('an accepted week of another lever is not a steps week', () {
      final raise = planRaise(
        goal: _goal(),
        weeks: [
          _week(
            change: const LeverChange(
              kind: LeverKind.effortPoints,
              from: 100,
              to: 120,
            ),
          ),
        ],
        changes: _raisedRows,
        current: 10000,
      );

      expect(raise, isNull);
    });

    test('an accepted week with no change is skipped', () {
      final raise = planRaise(
        goal: _goal(),
        weeks: [_week()],
        changes: _raisedRows,
        current: 10000,
      );

      expect(raise, isNull);
    });

    test('an accepted steps change that removes the lever is skipped', () {
      final raise = planRaise(
        goal: _goal(),
        weeks: [
          _week(
            change: const LeverChange(
              kind: LeverKind.steps,
              from: 9000,
              to: null,
            ),
          ),
        ],
        changes: _raisedRows,
        current: 10000,
      );

      expect(raise, isNull);
    });

    test('Y equal to X', () {
      final raise = planRaise(
        goal: _goal(),
        weeks: [_week(change: _stepsTo10000)],
        changes: [(from: stepGoalBaselineDate, steps: 8000)],
        current: 8000,
      );

      expect(raise, isNull);
    });

    test('Y below X', () {
      final raise = planRaise(
        goal: _goal(),
        weeks: [_week(change: _stepsTo10000)],
        changes: [(from: stepGoalBaselineDate, steps: 8000)],
        current: 7000,
      );

      expect(raise, isNull);
    });

    test('the accepted change does not rise above X', () {
      final raise = planRaise(
        goal: _goal(),
        weeks: [
          _week(
            change: const LeverChange(
              kind: LeverKind.steps,
              from: 7000,
              to: 8000,
            ),
          ),
        ],
        changes: _raisedRows,
        current: 10000,
      );

      expect(raise, isNull);
    });
  });
}

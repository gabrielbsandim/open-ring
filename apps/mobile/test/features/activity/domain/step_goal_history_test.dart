import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/features/activity/domain/step_goal_history.dart';

const _dec3 = LocalDate(2026, 12, 3);
const _dec6 = LocalDate(2026, 12, 6);
const _dec7 = LocalDate(2026, 12, 7);
const _dec8 = LocalDate(2026, 12, 8);

void main() {
  group('stepGoalBaselineDate', () {
    test('is the first of January 1970', () {
      expect(stepGoalBaselineDate, const LocalDate(1970, 1, 1));
    });
  });

  group('stepGoalOn', () {
    final changes = <StepGoalChange>[
      (from: stepGoalBaselineDate, steps: 8000),
      (from: _dec7, steps: 10000),
    ];

    test('days before the change keep the baseline goal', () {
      expect(stepGoalOn(_dec3, changes: changes, current: 10000), 8000);
      expect(stepGoalOn(_dec6, changes: changes, current: 10000), 8000);
    });

    test('the day of the change already uses the new goal', () {
      expect(stepGoalOn(_dec7, changes: changes, current: 10000), 10000);
    });

    test('days after the change keep the new goal', () {
      expect(stepGoalOn(_dec8, changes: changes, current: 10000), 10000);
    });

    test('no changes resolve to the current goal on any date', () {
      expect(stepGoalOn(_dec3, changes: const [], current: 9000), 9000);
      expect(stepGoalOn(_dec8, changes: const [], current: 9000), 9000);
      expect(
        stepGoalOn(stepGoalBaselineDate, changes: const [], current: 9000),
        9000,
      );
    });

    test('a date before the first change falls back to the current goal', () {
      final late = <StepGoalChange>[(from: _dec7, steps: 10000)];

      expect(stepGoalOn(_dec6, changes: late, current: 7000), 7000);
    });

    test('the last change on or before the date wins among many', () {
      final many = <StepGoalChange>[
        (from: stepGoalBaselineDate, steps: 8000),
        (from: _dec3, steps: 9000),
        (from: _dec7, steps: 10000),
      ];

      expect(stepGoalOn(_dec6, changes: many, current: 12000), 9000);
      expect(stepGoalOn(_dec3, changes: many, current: 12000), 9000);
    });

    test('the baseline date itself resolves to the baseline row', () {
      expect(
        stepGoalOn(stepGoalBaselineDate, changes: changes, current: 10000),
        8000,
      );
    });
  });
}

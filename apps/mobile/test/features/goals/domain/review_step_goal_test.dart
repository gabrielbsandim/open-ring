import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/features/goals/domain/review_step_goal.dart';

LeverChange _change(LeverKind kind, {int? from = 9000, int? to = 10000}) =>
    LeverChange(kind: kind, from: from, to: to);

void main() {
  group('stepGoalAfterAccept', () {
    test('gives the new steps when above the profile goal', () {
      final goal = stepGoalAfterAccept(
        _change(LeverKind.steps),
        profileGoal: 8000,
      );

      expect(goal, 10000);
    });

    test('gives one step above the profile goal', () {
      final goal = stepGoalAfterAccept(
        _change(LeverKind.steps, to: 8001),
        profileGoal: 8000,
      );

      expect(goal, 8001);
    });

    test('gives null when equal to the profile goal', () {
      final goal = stepGoalAfterAccept(
        _change(LeverKind.steps),
        profileGoal: 10000,
      );

      expect(goal, isNull);
    });

    test('gives null when below the profile goal', () {
      final goal = stepGoalAfterAccept(
        _change(LeverKind.steps),
        profileGoal: 12000,
      );

      expect(goal, isNull);
    });

    test('gives null when the change removes the lever', () {
      final goal = stepGoalAfterAccept(
        _change(LeverKind.steps, to: null),
        profileGoal: 8000,
      );

      expect(goal, isNull);
    });

    test('gives the new steps when the lever is added', () {
      final goal = stepGoalAfterAccept(
        _change(LeverKind.steps, from: null),
        profileGoal: 8000,
      );

      expect(goal, 10000);
    });

    for (final kind in LeverKind.values.where((k) => k != LeverKind.steps)) {
      test('gives null for ${kind.name} even when to is above', () {
        final goal = stepGoalAfterAccept(
          _change(kind, from: 1, to: 20000),
          profileGoal: 8000,
        );

        expect(goal, isNull);
      });
    }
  });
}

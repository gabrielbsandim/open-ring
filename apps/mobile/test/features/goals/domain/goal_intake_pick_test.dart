import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/features/goals/domain/goal_intake.dart';

const IntakeFacts _ready = (
  bodyOn: true,
  age: 34,
  heightCm: 178,
  trendKg: 78.4,
  softMode: null,
);

IntakeFacts _with({
  bool bodyOn = true,
  int? age = 34,
  double? heightCm = 178,
  double? trendKg = 78.4,
  bool? softMode,
}) => (
  bodyOn: bodyOn,
  age: age,
  heightCm: heightCm,
  trendKg: trendKg,
  softMode: softMode,
);

Matcher _blocked(IntakeBlock block) =>
    isA<PickBlocked>().having((step) => step.block, 'block', block);

void main() {
  group('1. pickStep', () {
    test('no choice gives NoGoal whatever the facts', () {
      expect(pickStep(null, _ready), isA<PickNoGoal>());
      expect(pickStep(null, _with(bodyOn: false)), isA<PickNoGoal>());
    });

    test('Get fitter and Sleep better give Start, even with Body off', () {
      for (final kind in [GoalKind.getFitter, GoalKind.sleepBetter]) {
        for (final facts in [_ready, _with(bodyOn: false, age: null)]) {
          expect(
            pickStep(kind, facts),
            isA<PickStart>().having((step) => step.kind, 'kind', kind),
          );
        }
      }
    });

    test('Lose fat with Body off is Blocked(bodyOff)', () {
      expect(
        pickStep(GoalKind.loseFat, _with(bodyOn: false)),
        _blocked(IntakeBlock.bodyOff),
      );
    });

    test('Lose fat carries every other block of weightGoalBlock', () {
      final cases = {
        IntakeBlock.softMode: _with(softMode: true),
        IntakeBlock.ageMissing: _with(age: null),
        IntakeBlock.under18: _with(age: 17),
        IntakeBlock.heightMissing: _with(heightCm: null),
        IntakeBlock.bmiUnderFloor: _with(trendKg: 57.9),
      };
      for (final MapEntry(key: block, value: facts) in cases.entries) {
        expect(pickStep(GoalKind.loseFat, facts), _blocked(block));
      }
    });

    test('Lose fat that passes asks the five questions first', () {
      expect(
        pickStep(GoalKind.loseFat, _ready),
        isA<PickWeight>().having(
          (step) => step.next,
          'next',
          IntakeNext.screening,
        ),
      );
    });

    test('Lose fat with soft mode answered false goes to the setup', () {
      expect(
        pickStep(GoalKind.loseFat, _with(softMode: false)),
        isA<PickWeight>().having((step) => step.next, 'next', IntakeNext.setup),
      );
    });

    test('Lose fat with no trend yet still passes', () {
      expect(
        pickStep(GoalKind.loseFat, _with(trendKg: null)),
        isA<PickWeight>(),
      );
    });
  });

  group('2. the opening year and the shown BMI', () {
    test('weightGoalsOpenYear(2008) is 2027', () {
      expect(weightGoalsOpenYear(2008), 2027);
    });

    test('weightGoalsOpenYear adds the minimum age and one', () {
      expect(weightGoalsOpenYear(2007), 2026);
      expect(weightGoalsOpenYear(1990), 2009);
    });

    test('shownBmi never shows 18.5 for a BMI under the floor', () {
      expect(shownBmi(18.4955), 18.4);
      expect(shownBmi(18.4999), 18.4);
    });

    test('shownBmi rounds to one decimal', () {
      expect(shownBmi(18.274), 18.3);
      expect(shownBmi(18.04), 18.0);
      expect(shownBmi(17.26), 17.3);
    });
  });
}

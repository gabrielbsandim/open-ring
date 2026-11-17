import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/goals/domain/goal.dart';
import 'package:open_ring/features/goals/domain/goal_intake.dart';

import '../goal_fixtures.dart';

IntakeFacts _facts({
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

GoalScreening _screening(
  int day, {
  bool? softMode,
  bool? pregnantOrBreastfeeding,
}) => GoalScreening(
  on: goalDay(12, day),
  softMode: softMode,
  pregnantOrBreastfeeding: pregnantOrBreastfeeding,
);

void main() {
  group('1. a clean profile with no screening yet', () {
    test('has no block and goes to the screening', () {
      final facts = _facts();

      expect(weightGoalBlock(facts), isNull);
      expect(weightGoalNext(facts), IntakeNext.screening);
    });
  });

  group('2. the stored soft mode answer', () {
    test('false goes to setup', () {
      final facts = _facts(softMode: false);

      expect(weightGoalBlock(facts), isNull);
      expect(weightGoalNext(facts), IntakeNext.setup);
    });

    test('true blocks with softMode', () {
      expect(weightGoalBlock(_facts(softMode: true)), IntakeBlock.softMode);
    });

    test('null and false differ in the next step', () {
      expect(weightGoalNext(_facts()), IntakeNext.screening);
      expect(weightGoalNext(_facts(softMode: false)), IntakeNext.setup);
    });
  });

  group('3. the age', () {
    test('null gives ageMissing', () {
      expect(weightGoalBlock(_facts(age: null)), IntakeBlock.ageMissing);
    });

    test('17 gives under18', () {
      expect(weightGoalBlock(_facts(age: 17)), IntakeBlock.under18);
    });

    test('18 gives no block', () {
      expect(weightGoalBlock(_facts(age: 18)), isNull);
    });
  });

  group('4. the height', () {
    test('null gives heightMissing', () {
      expect(
        weightGoalBlock(_facts(heightCm: null)),
        IntakeBlock.heightMissing,
      );
    });
  });

  group('5. the BMI floor', () {
    test('57.9 kg at 178 gives bmiUnderFloor', () {
      expect(weightGoalBlock(_facts(trendKg: 57.9)), IntakeBlock.bmiUnderFloor);
    });

    test('58.7 kg at 178 gives no block', () {
      expect(weightGoalBlock(_facts(trendKg: 58.7)), isNull);
    });

    test('a null trend gives no block', () {
      expect(weightGoalBlock(_facts(trendKg: null)), isNull);
    });

    test('a null trend still reaches the screening', () {
      expect(weightGoalNext(_facts(trendKg: null)), IntakeNext.screening);
    });
  });

  group('6. the order of the blocks', () {
    test('Body off with age 16 gives bodyOff', () {
      expect(
        weightGoalBlock(_facts(bodyOn: false, age: 16)),
        IntakeBlock.bodyOff,
      );
    });

    test('Body off comes before soft mode', () {
      expect(
        weightGoalBlock(_facts(bodyOn: false, softMode: true)),
        IntakeBlock.bodyOff,
      );
    });

    test('soft mode comes before a missing age', () {
      expect(
        weightGoalBlock(_facts(age: null, softMode: true)),
        IntakeBlock.softMode,
      );
    });

    test('soft mode comes before under18', () {
      expect(
        weightGoalBlock(_facts(age: 16, softMode: true)),
        IntakeBlock.softMode,
      );
    });

    test('a missing age comes before a missing height', () {
      expect(
        weightGoalBlock(_facts(age: null, heightCm: null)),
        IntakeBlock.ageMissing,
      );
    });

    test('under18 comes before a missing height', () {
      expect(
        weightGoalBlock(_facts(age: 16, heightCm: null)),
        IntakeBlock.under18,
      );
    });

    test('a missing height comes before the BMI floor', () {
      expect(
        weightGoalBlock(_facts(heightCm: null, trendKg: 40)),
        IntakeBlock.heightMissing,
      );
    });

    test('under18 comes before the BMI floor', () {
      expect(
        weightGoalBlock(_facts(age: 17, trendKg: 40)),
        IntakeBlock.under18,
      );
    });
  });

  group('10. the newest soft mode answer', () {
    test('a newer null with pregnancy true keeps the older true', () {
      final rows = [
        _screening(2, pregnantOrBreastfeeding: true),
        _screening(1, softMode: true),
      ];

      expect(newestSoftMode(rows), isTrue);
    });

    test('a newer false wins over an older true', () {
      final rows = [
        _screening(2, softMode: false),
        _screening(1, softMode: true),
      ];

      expect(newestSoftMode(rows), isFalse);
    });

    test('no rows give null', () {
      expect(newestSoftMode(const <GoalScreening>[]), isNull);
    });

    test('rows that never answered give null', () {
      final rows = [
        _screening(2, pregnantOrBreastfeeding: false),
        _screening(1),
      ];

      expect(newestSoftMode(rows), isNull);
    });
  });

  group('the number of questions', () {
    test('is five', () {
      expect(goalScreeningQuestions, 5);
    });
  });
}

import 'package:metrics/metrics.dart';
import 'package:test/test.dart';

import 'food_nights.dart';

const tight = 1e-6;

// prototype/food.html FIRST14: (offset from Monday 7 Sep 2026, first meal in
// minutes). Offsets 75, 82 and 89 are Saturdays; 76, 83 and 90 are Sundays.
const first14 = [
  (75, 590), (76, 610), (77, 450), (78, 465), (80, 470), (81, 475), //
  (82, 585), (83, 620), (84, 455), (85, 470), (87, 460), (88, 480),
  (89, 570), (90, 600),
];

List<MealEntry> mealDay(int o, int firstMinute, {bool complete = true}) => [
  MealEntry(
    at: clock(o, firstMinute),
    kind: MealKind.main,
    tags: const MealTags(protein: true),
  ),
  MealEntry(
    at: clock(o, 20 * 60),
    kind: MealKind.main,
    tags: const MealTags(protein: true),
    last: complete,
  ),
];

// Days 79 and 86 have meals but no last meal marked, as in the prototype.
final List<MealEntry> prototypeFirstMeals = [
  for (final (o, minute) in first14) ...mealDay(o, minute),
  ...mealDay(79, 12 * 60, complete: false),
  ...mealDay(86, 12 * 60, complete: false),
];

Matcher isRegularity({
  required int days,
  required double sd,
  required double? weekendLater,
}) => isA<MealRegularity>()
    .having((r) => r.completeDays, 'completeDays', days)
    .having(
      (r) => r.firstMealSdMinutes,
      'firstMealSdMinutes',
      closeTo(sd, tight),
    )
    .having(
      (r) => r.weekendLaterMinutes,
      'weekendLaterMinutes',
      weekendLater == null ? isNull : closeTo(weekendLater, tight),
    );

Matcher get prototypeResult =>
    isRegularity(days: 14, sd: 68.20299371, weekendLater: 130.20833333);

void main() {
  group('meal time regularity, descriptive only (decision 8)', () {
    test('first meal SD 68.2 min and weekend 130.2 min later over the last 14 '
        'complete days', () {
      final result = mealRegularity(meals: prototypeFirstMeals);
      expect(result, prototypeResult);
      expect(
        result,
        isA<MealRegularity>()
            .having((r) => r.firstMealSdMinutes, 'sd', closeTo(68.2, 0.05))
            .having(
              (r) => r.weekendLaterMinutes,
              'weekend',
              closeTo(130.2, 0.05),
            ),
      );
    });

    test('complete days older than the last 14 do not count', () {
      final meals = [
        for (var o = 50; o < 75; o++) ...mealDay(o, 5 * 60 + 30),
        ...prototypeFirstMeals,
      ];
      expect(mealRegularity(meals: meals), prototypeResult);
    });

    test('a newer day without its last meal marked does not count', () {
      final meals = [
        ...prototypeFirstMeals,
        ...mealDay(91, 15 * 60, complete: false),
      ];
      expect(mealRegularity(meals: meals), prototypeResult);
    });

    test('the first meal is the first that opens the window: an earlier '
        'plain coffee does not move it', () {
      final meals = [
        ...prototypeFirstMeals,
        for (final (o, _) in first14)
          MealEntry(
            at: clock(o, 6 * 60),
            kind: MealKind.drink,
            tags: const MealTags(caffeine: true),
          ),
      ];
      expect(mealRegularity(meals: meals), prototypeResult);
    });

    test('the weekend is Saturday and Sunday: Friday is a weekday, so ten '
        'Monday to Friday days have no weekend shift', () {
      final meals = [
        for (final o in [0, 1, 2, 3, 4, 7, 8, 9, 10, 11])
          ...mealDay(o, o % 7 == 4 ? 600 : 450),
      ];
      expect(
        mealRegularity(meals: meals),
        isA<MealRegularity>()
            .having((r) => r.completeDays, 'completeDays', 10)
            .having((r) => r.weekendLaterMinutes, 'weekendLater', isNull),
      );
    });

    test('9 complete days is collecting, 10 is enough', () {
      final days = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9];
      final nine = [for (final o in days.take(9)) ...mealDay(o, 480 + o)];
      expect(
        mealRegularity(meals: nine),
        isA<RegularityCollecting>()
            .having((r) => r.completeDays, 'completeDays', 9)
            .having((r) => r.minimum, 'minimum', 10),
      );
      final ten = [for (final o in days) ...mealDay(o, 480 + o)];
      expect(
        mealRegularity(meals: ten),
        isA<MealRegularity>().having((r) => r.completeDays, 'completeDays', 10),
      );
    });

    test('no meals is collecting at 0 of 10', () {
      expect(
        mealRegularity(meals: const <MealEntry>[]),
        isA<RegularityCollecting>()
            .having((r) => r.completeDays, 'completeDays', 0)
            .having((r) => r.minimum, 'minimum', 10),
      );
    });
  });
}

import 'package:metrics/metrics.dart';
import 'package:test/test.dart';

import 'food_nights.dart';

// Offsets from Monday 7 Sep 2026: o % 7 is 0 Monday, 4 Friday, 5 Saturday,
// 6 Sunday. The default window ends at night 89, so night 0 is its first.
List<(int, int)> pairsOf(FoodLink link, NightBook book, {int lastNight = 89}) =>
    [
      for (final pair in matchPairs(
        link: link,
        lastNight: day(lastNight),
        nights: book.nights,
        meals: book.meals,
      ))
        (dayOf(pair.exposed), dayOf(pair.control)),
    ];

NightBook nights(List<int> heavy, List<int> plain) {
  final book = NightBook();
  for (final o in heavy) {
    book.add(o, heavy: true);
  }
  plain.forEach(book.add);
  return book;
}

void main() {
  group('matched pairs (decision 6)', () {
    test('a night 10 days away is matched', () {
      expect(pairsOf(FoodLink.heavyDinner, nights([3], [13])), [(3, 13)]);
    });

    test('a pair 11 days apart is not matched', () {
      expect(pairsOf(FoodLink.heavyDinner, nights([2], [13])), isEmpty);
    });

    test('the nearest night wins over an earlier one further away', () {
      expect(pairsOf(FoodLink.heavyDinner, nights([9], [7, 10])), [(9, 10)]);
    });

    test('at the same distance the earlier night wins', () {
      expect(pairsOf(FoodLink.heavyDinner, nights([2], [1, 3])), [(2, 1)]);
    });

    test('a night is used once; the older exposed night claims it first', () {
      expect(pairsOf(FoodLink.heavyDinner, nights([1, 3], [2])), [(1, 2)]);
    });

    test('pairs come back oldest exposed night first', () {
      expect(pairsOf(FoodLink.heavyDinner, nights([8, 1], [0, 9])), [
        (1, 0),
        (8, 9),
      ]);
    });

    test('an exposed night is never a control', () {
      expect(pairsOf(FoodLink.heavyDinner, nights([1, 2], [])), isEmpty);
    });

    test('a day without its last meal marked is neither exposed nor '
        'control', () {
      final book = NightBook()
        ..add(1, heavy: true)
        ..add(2, complete: false)
        ..add(3)
        ..add(8, heavy: true, complete: false)
        ..add(9);
      expect(pairsOf(FoodLink.heavyDinner, book), [(1, 3)]);
    });
  });

  group('decision 5: an untagged meal leaves its night unknown', () {
    test('a night with an untagged meal is neither exposed nor control', () {
      final book = NightBook()
        ..add(1, heavy: true)
        ..add(2, extra: [MealEntry(at: clock(2, 13 * 60))])
        ..add(3)
        ..add(8, heavy: true, extra: [MealEntry(at: clock(8, 13 * 60))])
        ..add(9);
      expect(pairsOf(FoodLink.heavyDinner, book), [(1, 3)]);
      expect(pairsOf(FoodLink.alcoholThreeOrMore, book), isEmpty);
    });

    test('a meal with only a kind is tagged, so its night still counts', () {
      final book = NightBook()
        ..add(1, heavy: true)
        ..add(
          2,
          extra: [MealEntry(at: clock(2, 13 * 60), kind: MealKind.main)],
        );
      expect(pairsOf(FoodLink.heavyDinner, book), [(1, 2)]);
    });
  });

  group('FD5: a weekend night is a Friday or Saturday evening', () {
    test('a weekday night is never paired with a weekend night', () {
      expect(pairsOf(FoodLink.heavyDinner, nights([3], [4, 5])), isEmpty);
      expect(pairsOf(FoodLink.heavyDinner, nights([4], [3])), isEmpty);
    });

    test('a weekday night skips Friday and Saturday for Sunday', () {
      expect(pairsOf(FoodLink.heavyDinner, nights([3], [4, 5, 6])), [(3, 6)]);
    });

    test('Friday pairs with Saturday', () {
      expect(pairsOf(FoodLink.heavyDinner, nights([4], [5])), [(4, 5)]);
    });

    test('Sunday evening is a weekday night: Saturday does not pair with '
        'it', () {
      expect(pairsOf(FoodLink.heavyDinner, nights([5], [6])), isEmpty);
    });
  });

  group('window: the 90 nights ending at lastNight', () {
    test('a night 90 days before lastNight is outside', () {
      final book = nights([1], [0]);
      expect(pairsOf(FoodLink.heavyDinner, book, lastNight: 90), isEmpty);
      expect(pairsOf(FoodLink.heavyDinner, book), [(1, 0)]);
    });

    test('a night after lastNight is outside', () {
      final book = nights([85, 87], [86]);
      expect(pairsOf(FoodLink.heavyDinner, book, lastNight: 85), isEmpty);
    });

    test('the prototype window ignores a control before night 1', () {
      final book = NightBook()..add(0);
      final pairs = matchPairs(
        link: FoodLink.caffeineAfter14,
        lastNight: prototypeLastNight,
        nights: [...book.nights, ...prototypeNights],
        meals: [...book.meals, ...prototypeMeals],
      );
      expect((dayOf(pairs.first.exposed), dayOf(pairs.first.control)), (1, 3));
    });
  });

  group('alcohol free unless the link is alcohol', () {
    test('a heavy dinner with alcohol is not exposed', () {
      final book = NightBook()
        ..add(1, heavy: true, alcohol: MealAlcohol.oneToTwo)
        ..add(2);
      expect(pairsOf(FoodLink.heavyDinner, book), isEmpty);
    });

    test('a night with alcohol is not a control for heavy dinner', () {
      final book = NightBook()
        ..add(1, heavy: true)
        ..add(2, alcohol: MealAlcohol.oneToTwo)
        ..add(3);
      expect(pairsOf(FoodLink.heavyDinner, book), [(1, 3)]);
    });

    test('alcohol 3+ is paired with an alcohol free night, not a 1 to 2 '
        'night', () {
      final book = NightBook()
        ..add(1, alcohol: MealAlcohol.threeOrMore)
        ..add(2, alcohol: MealAlcohol.oneToTwo)
        ..add(3);
      expect(pairsOf(FoodLink.alcoholThreeOrMore, book), [(1, 3)]);
      expect(pairsOf(FoodLink.alcoholOneToTwo, book), [(2, 3)]);
    });

    test('a night with both doses tagged is a 3+ night', () {
      final book = NightBook()
        ..add(
          1,
          alcohol: MealAlcohol.oneToTwo,
          extra: [
            MealEntry(
              at: clock(1, 21 * 60),
              kind: MealKind.drink,
              tags: const MealTags(alcohol: MealAlcohol.threeOrMore),
            ),
          ],
        )
        ..add(2);
      expect(pairsOf(FoodLink.alcoholThreeOrMore, book), [(1, 2)]);
      expect(pairsOf(FoodLink.alcoholOneToTwo, book), isEmpty);
    });

    test('alcohol at 00:30 belongs to the night before (food day starts at '
        '05:00)', () {
      final book = NightBook()
        ..add(
          1,
          extra: [
            MealEntry(
              at: clock(1, 24 * 60 + 30),
              kind: MealKind.drink,
              tags: const MealTags(alcohol: MealAlcohol.threeOrMore),
            ),
          ],
        )
        ..add(2)
        ..add(3);
      expect(pairsOf(FoodLink.alcoholThreeOrMore, book), [(1, 2)]);
    });
  });

  group('late last meal: under 2 h before onset is exposed, 3 h or more is '
      'control, between is neither', () {
    // Onset 23:30, so a dinner at 21:31 is 119 min before it.
    test('119 min is exposed, 120 min is not', () {
      final exposed = NightBook()
        ..add(1, dinner: 21 * 60 + 31)
        ..add(2);
      expect(pairsOf(FoodLink.lateLastMeal, exposed), [(1, 2)]);
      final blocked = NightBook()
        ..add(1, dinner: 21 * 60 + 30)
        ..add(2);
      expect(pairsOf(FoodLink.lateLastMeal, blocked), isEmpty);
    });

    test('179 min is not a control, 180 min is', () {
      final book = NightBook()
        ..add(1, dinner: 22 * 60 + 30)
        ..add(2, dinner: 20 * 60 + 31)
        ..add(3, dinner: 20 * 60 + 30);
      expect(pairsOf(FoodLink.lateLastMeal, book), [(1, 3)]);
    });

    test('a drink with no sugar and no alcohol after dinner is not the last '
        'meal', () {
      final book = NightBook()
        ..add(
          1,
          extra: [MealEntry(at: clock(1, 23 * 60), kind: MealKind.drink)],
        )
        ..add(2);
      expect(pairsOf(FoodLink.lateLastMeal, book), isEmpty);
    });

    test('a snack with only its kind after dinner is the last meal', () {
      final book = NightBook()
        ..add(
          1,
          extra: [MealEntry(at: clock(1, 23 * 60), kind: MealKind.snack)],
        )
        ..add(2);
      expect(pairsOf(FoodLink.lateLastMeal, book), [(1, 2)]);
    });

    test('a meal after sleep onset is not the last meal before sleep', () {
      final book = NightBook()
        ..add(
          1,
          dinner: 20 * 60 + 30,
          extra: [MealEntry(at: clock(1, 24 * 60 + 270), kind: MealKind.snack)],
        )
        ..add(2, dinner: 22 * 60 + 30)
        ..add(3);
      expect(pairsOf(FoodLink.lateLastMeal, book), [(2, 1)]);
    });

    test('a meal at 00:30 is the last meal of the night before', () {
      final book = NightBook()
        ..add(
          1,
          onset: 25 * 60,
          extra: [MealEntry(at: clock(1, 24 * 60 + 30), kind: MealKind.snack)],
        )
        ..add(2);
      expect(pairsOf(FoodLink.lateLastMeal, book), [(1, 2)]);
    });

    test('a night with no onset is neither exposed nor control', () {
      final book = NightBook()
        ..add(1, dinner: 22 * 60 + 30)
        ..add(2, onset: null)
        ..add(3)
        ..add(8, dinner: 22 * 60 + 30, onset: null)
        ..add(9);
      expect(pairsOf(FoodLink.lateLastMeal, book), [(1, 3)]);
    });
  });

  group('caffeine after 14h: a caffeine tag at or after 14:00 of the food '
      'day', () {
    test('caffeine at 14:00 is exposed', () {
      final book = NightBook()
        ..add(1, extra: [caffeineAt(1, 14 * 60)])
        ..add(2, extra: [caffeineAt(2, 8 * 60)]);
      expect(pairsOf(FoodLink.caffeineAfter14, book), [(1, 2)]);
    });

    test('caffeine at 13:59 is not', () {
      final book = NightBook()
        ..add(1, extra: [caffeineAt(1, 13 * 60 + 59)])
        ..add(2);
      expect(pairsOf(FoodLink.caffeineAfter14, book), isEmpty);
    });

    test('caffeine at 01:00 counts for the night before', () {
      final book = NightBook()
        ..add(1, extra: [caffeineAt(1, 25 * 60)])
        ..add(2)
        ..add(3);
      expect(pairsOf(FoodLink.caffeineAfter14, book), [(1, 2)]);
    });
  });

  group('heavy dinner: a meal tagged heavy in the dinner or supper slot', () {
    MealEntry heavyAt(int o, int minutes) => MealEntry(
      at: clock(o, minutes),
      kind: MealKind.main,
      tags: const MealTags(heavy: true),
    );

    test('a heavy lunch is not a heavy dinner', () {
      final book = NightBook()
        ..add(1, extra: [heavyAt(1, 12 * 60 + 30)])
        ..add(2);
      expect(pairsOf(FoodLink.heavyDinner, book), isEmpty);
    });

    test('heavy at 17:59 is not, at 18:00 it is', () {
      final before = NightBook()
        ..add(1, extra: [heavyAt(1, 17 * 60 + 59)])
        ..add(2);
      expect(pairsOf(FoodLink.heavyDinner, before), isEmpty);
      final at = NightBook()
        ..add(1, extra: [heavyAt(1, 18 * 60)])
        ..add(2);
      expect(pairsOf(FoodLink.heavyDinner, at), [(1, 2)]);
    });

    test('a heavy supper at 23:30 is a heavy dinner', () {
      final book = NightBook()
        ..add(1, extra: [heavyAt(1, 23 * 60 + 30)])
        ..add(2);
      expect(pairsOf(FoodLink.heavyDinner, book), [(1, 2)]);
    });

    test('a night with a heavy lunch is still a control', () {
      final book = NightBook()
        ..add(1, heavy: true)
        ..add(2, extra: [heavyAt(2, 12 * 60 + 30)]);
      expect(pairsOf(FoodLink.heavyDinner, book), [(1, 2)]);
    });
  });
}

import 'package:metrics/metrics.dart';
import 'package:test/test.dart';

const monday = LocalDate(2026, 11, 30);
const tight = 1e-9;

DateTime at(int dayIndex, int minutes) {
  final day = monday.addDays(dayIndex);
  return DateTime(day.year, day.month, day.day, 0, minutes);
}

MealEntry meal(
  int dayIndex,
  int minutes,
  MealKind? kind, {
  MealTags tags = const MealTags(),
  bool last = false,
}) => MealEntry(at: at(dayIndex, minutes), kind: kind, tags: tags, last: last);

// The week of 30 Nov to 6 Dec 2026 from prototype/food.html (WEEK, o 84 to 90).
// Wednesday 2 Dec has no last meal marked, so it is the one open day.
final List<MealEntry> prototypeWeek = [
  meal(
    0,
    455,
    MealKind.main,
    tags: const MealTags(protein: true, veg: MealVeg.some),
  ),
  meal(
    0,
    760,
    MealKind.main,
    tags: const MealTags(
      protein: true,
      veg: MealVeg.halfOrMore,
      place: MealPlace.home,
    ),
  ),
  meal(
    0,
    970,
    MealKind.snack,
    tags: const MealTags(processed: MealProcessed.mostly),
  ),
  meal(
    0,
    1215,
    MealKind.main,
    tags: const MealTags(
      protein: true,
      veg: MealVeg.some,
      place: MealPlace.home,
    ),
    last: true,
  ),
  meal(1, 470, MealKind.main, tags: const MealTags(protein: true)),
  meal(
    1,
    785,
    MealKind.main,
    tags: const MealTags(
      protein: true,
      veg: MealVeg.halfOrMore,
      place: MealPlace.restaurant,
    ),
  ),
  meal(
    1,
    1195,
    MealKind.main,
    tags: const MealTags(
      protein: true,
      veg: MealVeg.halfOrMore,
      processed: MealProcessed.mostly,
      place: MealPlace.home,
    ),
    last: true,
  ),
  meal(
    2,
    750,
    MealKind.main,
    tags: const MealTags(
      protein: true,
      veg: MealVeg.halfOrMore,
      place: MealPlace.restaurant,
    ),
  ),
  meal(3, 460, MealKind.main, tags: const MealTags(veg: MealVeg.some)),
  meal(
    3,
    770,
    MealKind.main,
    tags: const MealTags(
      protein: true,
      veg: MealVeg.some,
      fried: true,
      place: MealPlace.restaurant,
    ),
  ),
  meal(3, 930, MealKind.drink, tags: const MealTags(sugar: true)),
  meal(
    3,
    1300,
    MealKind.main,
    tags: const MealTags(protein: true, heavy: true, place: MealPlace.home),
    last: true,
  ),
  meal(
    4,
    480,
    MealKind.main,
    tags: const MealTags(protein: true, veg: MealVeg.some),
  ),
  meal(
    4,
    765,
    MealKind.main,
    tags: const MealTags(
      protein: true,
      veg: MealVeg.halfOrMore,
      place: MealPlace.restaurant,
    ),
  ),
  meal(
    4,
    1230,
    MealKind.main,
    tags: const MealTags(
      protein: true,
      processed: MealProcessed.mostly,
      place: MealPlace.restaurant,
    ),
  ),
  meal(
    4,
    1330,
    MealKind.drink,
    tags: const MealTags(alcohol: MealAlcohol.threeOrMore),
    last: true,
  ),
  meal(5, 570, MealKind.main),
  meal(
    5,
    810,
    MealKind.main,
    tags: const MealTags(
      protein: true,
      veg: MealVeg.halfOrMore,
      place: MealPlace.restaurant,
    ),
  ),
  meal(5, 1020, MealKind.snack, tags: const MealTags(sugar: true)),
  meal(
    5,
    1260,
    MealKind.main,
    tags: const MealTags(
      protein: true,
      veg: MealVeg.some,
      place: MealPlace.home,
    ),
    last: true,
  ),
  meal(6, 600, MealKind.main, tags: const MealTags(protein: true)),
  meal(
    6,
    840,
    MealKind.main,
    tags: const MealTags(
      protein: true,
      veg: MealVeg.halfOrMore,
      place: MealPlace.home,
    ),
  ),
  meal(
    6,
    1200,
    MealKind.main,
    tags: const MealTags(
      veg: MealVeg.some,
      processed: MealProcessed.unsure,
      place: MealPlace.home,
    ),
    last: true,
  ),
];

// Sleep onset keyed by the food day whose evening it closes. Friday 4 Dec
// falls asleep at 00:20 on Saturday.
final Map<LocalDate, DateTime> prototypeOnsets = {
  for (final (index, minutes) in const [
    (0, 1400),
    (1, 1395),
    (2, 1420),
    (3, 1410),
    (4, 1460),
    (5, 1430),
    (6, 1390),
  ])
    monday.addDays(index): at(index, minutes),
};

FoodWeek week(List<MealEntry> meals, {Map<LocalDate, DateTime>? onsets}) =>
    foodWeek(
      monday: monday,
      meals: meals,
      sleepOnsets: onsets ?? prototypeOnsets,
    );

PlatePattern pattern(List<MealEntry> meals) {
  final result = platePattern(monday: monday, meals: meals);
  expect(result, isA<PlatePattern>());
  return result as PlatePattern;
}

PlateBuilding building(List<MealEntry> meals) {
  final result = platePattern(monday: monday, meals: meals);
  expect(result, isA<PlateBuilding>());
  return result as PlateBuilding;
}

List<MealEntry> unmarked(List<MealEntry> meals, Set<int> dayIndexes) => [
  for (final entry in meals)
    if (dayIndexes.contains(entry.at.difference(at(0, 0)).inDays))
      MealEntry(at: entry.at, kind: entry.kind, tags: entry.tags)
    else
      entry,
];

// One complete day per entry, each with that many mains tagged protein and
// half a plate of veg at 08:00, 13:00 and on, the last of them marked.
List<MealEntry> mainsWeek(List<int> mainsPerDay) => [
  for (final (index, mains) in mainsPerDay.indexed)
    for (var i = 0; i < mains; i++)
      meal(
        index,
        480 + 300 * i,
        MealKind.main,
        tags: const MealTags(protein: true, veg: MealVeg.halfOrMore),
        last: i == mains - 1,
      ),
];

void main() {
  group('foodDay: the food day starts at 05:00 local (FD3)', () {
    test('a meal at 00:30 belongs to the previous food day', () {
      expect(
        foodDay(DateTime(2026, 12, 1, 0, 30)),
        const LocalDate(2026, 11, 30),
      );
    });

    test('04:59 is still the previous day and 05:00 is the new one', () {
      expect(
        foodDay(DateTime(2026, 12, 1, 4, 59)),
        const LocalDate(2026, 11, 30),
      );
      expect(foodDay(DateTime(2026, 12, 1, 5)), const LocalDate(2026, 12, 1));
    });

    test('23:59 is the same calendar day', () {
      expect(
        foodDay(DateTime(2026, 12, 1, 23, 59)),
        const LocalDate(2026, 12, 1),
      );
    });

    test('03:00 on New Year goes back across the month and the year', () {
      expect(foodDay(DateTime(2027, 1, 1, 3)), const LocalDate(2026, 12, 31));
    });
  });

  group('mealSlot: the slot name comes from the capture time', () {
    test('each boundary of the prototype SLOTS table', () {
      final cases = {
        (4, 59): MealSlot.supper,
        (5, 0): MealSlot.breakfast,
        (10, 29): MealSlot.breakfast,
        (10, 30): MealSlot.lunch,
        (14, 59): MealSlot.lunch,
        (15, 0): MealSlot.afternoonSnack,
        (17, 59): MealSlot.afternoonSnack,
        (18, 0): MealSlot.dinner,
        (22, 59): MealSlot.dinner,
        (23, 0): MealSlot.supper,
        (0, 30): MealSlot.supper,
      };
      for (final MapEntry(key: (hour, minute), value: slot) in cases.entries) {
        expect(
          mealSlot(DateTime(2026, 12, 1, hour, minute)),
          slot,
          reason: '$hour:$minute',
        );
      }
    });
  });

  group('MealTags and MealEntry: the tagged notion (decision 5)', () {
    test('no tag tapped is empty, any one tag is not', () {
      expect(const MealTags().isEmpty, isTrue);
      expect(const MealTags(place: MealPlace.home).isEmpty, isFalse);
      expect(const MealTags(caffeine: true).isEmpty, isFalse);
      expect(const MealTags(processed: MealProcessed.unsure).isEmpty, isFalse);
    });

    test('an untapped yes/no tag reads as no', () {
      const tags = MealTags(veg: MealVeg.some);
      expect(tags.protein, isFalse);
      expect(tags.sugar, isFalse);
      expect(tags.caffeine, isFalse);
      expect(tags.heavy, isFalse);
      expect(tags.fried, isFalse);
      expect(tags.alcohol, isNull);
      expect(tags.processed, isNull);
    });

    test('a meal with no kind and no tags is untagged', () {
      expect(meal(0, 720, null).tagged, isFalse);
    });

    test('a meal with only a kind is tagged', () {
      expect(meal(0, 720, MealKind.main).tagged, isTrue);
    });

    test('a meal with a tag and no kind is tagged', () {
      final entry = meal(0, 720, null, tags: const MealTags(caffeine: true));
      expect(entry.tagged, isTrue);
    });

    test('the meal keeps its capture time and last meal flag', () {
      final entry = meal(0, 1215, MealKind.main, last: true);
      expect(entry.at, DateTime(2026, 11, 30, 20, 15));
      expect(entry.last, isTrue);
      expect(meal(0, 455, MealKind.main).last, isFalse);
    });
  });

  group('opensWindow (decision 4)', () {
    test('a plain coffee does not open the window', () {
      final coffee = meal(
        0,
        420,
        MealKind.drink,
        tags: const MealTags(caffeine: true),
      );
      expect(opensWindow(coffee), isFalse);
    });

    test('a drink with no tags but its kind does not open the window', () {
      expect(opensWindow(meal(0, 420, MealKind.drink)), isFalse);
    });

    test('a drink with sugar opens the window', () {
      final juice = meal(
        0,
        420,
        MealKind.drink,
        tags: const MealTags(sugar: true),
      );
      expect(opensWindow(juice), isTrue);
    });

    test('a drink with alcohol opens the window, at either dose', () {
      for (final dose in MealAlcohol.values) {
        final beer = meal(
          0,
          1330,
          MealKind.drink,
          tags: MealTags(alcohol: dose),
        );
        expect(opensWindow(beer), isTrue, reason: dose.name);
      }
    });

    test('a main, a snack and an untagged meal open the window', () {
      expect(opensWindow(meal(0, 420, MealKind.main)), isTrue);
      expect(opensWindow(meal(0, 420, MealKind.snack)), isTrue);
      expect(opensWindow(meal(0, 420, null)), isTrue);
    });
  });

  group('foodWeek: the week of 30 Nov to 6 Dec 2026', () {
    test('6 of 7 complete days and 23 records', () {
      final result = week(prototypeWeek);
      expect(result.completeDays, 6);
      expect(result.records, 23);
    });

    test('median eating window over complete days is 742.5 min', () {
      expect(week(prototypeWeek).windowMinutes, closeTo(742.5, tight));
    });

    test('median last meal to sleep over complete days is 177.5 min', () {
      expect(week(prototypeWeek).gapMinutes, closeTo(177.5, tight));
    });

    test('a plain coffee at 07:00 before the first meal leaves the window', () {
      final withCoffee = [
        ...prototypeWeek,
        meal(1, 420, MealKind.drink, tags: const MealTags(caffeine: true)),
      ];
      final result = week(withCoffee);
      expect(result.windowMinutes, closeTo(742.5, tight));
      expect(result.records, 24);
    });

    test('a plain coffee after the last meal does not close the window', () {
      final day = [
        meal(0, 480, MealKind.main, tags: const MealTags(protein: true)),
        meal(0, 1200, MealKind.main, last: true),
        meal(0, 1290, MealKind.drink, tags: const MealTags(caffeine: true)),
      ];
      final result = week(day, onsets: {monday: at(0, 1380)});
      expect(result.windowMinutes, closeTo(720, tight));
      expect(result.gapMinutes, closeTo(180, tight));
    });

    test('a meal at 00:30 closes the window of the previous food day', () {
      final day = [
        meal(0, 480, MealKind.main),
        meal(0, 1440 + 30, MealKind.snack, last: true),
      ];
      final result = week(day, onsets: {monday: at(0, 1440 + 90)});
      expect(result.completeDays, 1);
      expect(result.records, 2);
      expect(result.windowMinutes, closeTo(990, tight));
      expect(result.gapMinutes, closeTo(60, tight));
    });

    test('a meal at 00:30 after Sunday stays in the week', () {
      final late = [...prototypeWeek, meal(6, 1440 + 30, MealKind.snack)];
      expect(week(late).records, 24);
    });

    test('a meal at 04:59 on Monday belongs to the week before', () {
      final early = [...prototypeWeek, meal(0, 299, MealKind.snack)];
      expect(week(early).records, 23);
    });

    test('a meal on Monday 7 Dec after 05:00 belongs to the next week', () {
      final next = [...prototypeWeek, meal(7, 300, MealKind.main)];
      expect(week(next).records, 23);
    });

    test('an open day counts as a record but not in the medians', () {
      final onlyOpen = prototypeWeek.where((m) => m.at.day == 2).toList();
      final result = week(onlyOpen);
      expect(result.records, 1);
      expect(result.completeDays, 0);
      expect(result.windowMinutes, isNull);
      expect(result.gapMinutes, isNull);
    });

    test('an empty week has zero days, zero records and no medians', () {
      final result = week(const []);
      expect(result.completeDays, 0);
      expect(result.records, 0);
      expect(result.windowMinutes, isNull);
      expect(result.gapMinutes, isNull);
    });

    test('a complete day with no sleep onset leaves only the gap median', () {
      final onsets = {...prototypeOnsets}..remove(monday.addDays(4));
      final result = week(prototypeWeek, onsets: onsets);
      expect(result.completeDays, 6);
      expect(result.windowMinutes, closeTo(742.5, tight));
      expect(result.gapMinutes, closeTo(185, tight));
    });

    test('a complete day of plain drinks only has no window and no gap', () {
      final drinks = [
        meal(0, 420, MealKind.drink, tags: const MealTags(caffeine: true)),
        meal(0, 900, MealKind.drink, last: true),
      ];
      final result = week(drinks, onsets: {monday: at(0, 1380)});
      expect(result.completeDays, 1);
      expect(result.records, 2);
      expect(result.windowMinutes, isNull);
      expect(result.gapMinutes, isNull);
    });
  });

  group('platePattern: Plate pattern of 30 Nov to 6 Dec 2026', () {
    test('scores 8.3 of 10, one decimal', () {
      expect(pattern(prototypeWeek).score, 8.3);
    });

    test('its five points are 2.67, 2.61, 1.96, 0.42 and 0.67', () {
      final points = pattern(prototypeWeek).points;
      expect(points, hasLength(5));
      expect(
        [for (final point in points) point.toStringAsFixed(2)],
        ['2.67', '2.61', '1.96', '0.42', '0.67'],
      );
    });

    test('its five points are the exact ramps of the prototype', () {
      final points = pattern(prototypeWeek).points;
      expect(points[0], closeTo(3 * (15 / 18 - 0.3) / 0.6, tight));
      expect(points[1], closeTo(3 * (13 / 18 - 0.2) / 0.6, tight));
      expect(points[2], closeTo(2 * (1 - 2 / 18 - 0.4) / 0.5, tight));
      expect(points[3], closeTo((2 * 7 / 6 - 4) / -4, tight));
      expect(points[4], closeTo((4 * 7 / 6 - 10) / -8, tight));
    });

    test('its counts are 6 days, 18 mains, protein 15, veg 13, '
        'processed 2, sugary days 2, drinks 4', () {
      final result = pattern(prototypeWeek);
      expect(result.completeDays, 6);
      expect(result.mains, 18);
      expect(result.protein, 15);
      expect(result.veg, 13);
      expect(result.processed, 2);
      expect(result.sugaryDays, 2);
      expect(result.drinks, 4);
    });

    test('4 complete days gives PlateBuilding even with 12 mains', () {
      final result = building(unmarked(prototypeWeek, {5, 6}));
      expect(result.completeDays, 4);
      expect(result.mains, 12);
    });

    test('5 complete days is enough', () {
      final result = pattern(unmarked(prototypeWeek, {6}));
      expect(result.completeDays, 5);
      expect(result.mains, 15);
    });

    test('9 mains gives PlateBuilding even with 5 complete days', () {
      final result = building(mainsWeek([2, 2, 2, 2, 1]));
      expect(result.completeDays, 5);
      expect(result.mains, 9);
    });

    test('10 mains on 5 complete days is enough', () {
      final result = pattern(mainsWeek([2, 2, 2, 2, 2]));
      expect(result.completeDays, 5);
      expect(result.mains, 10);
    });

    test('an empty week gives PlateBuilding with zero days and mains', () {
      final result = building(const []);
      expect(result.completeDays, 0);
      expect(result.mains, 0);
    });

    test('mains of an open day are left out', () {
      final result = pattern(prototypeWeek);
      expect(result.mains, 18);
      expect(result.protein, 15);
    });

    test('an untagged meal leaves the denominator', () {
      final result = pattern([...prototypeWeek, meal(0, 600, null)]);
      expect(result.mains, 18);
      expect(result.score, 8.3);
    });

    test('a meal with only a kind counts as a main with every tag no', () {
      final result = pattern([...prototypeWeek, meal(0, 600, MealKind.main)]);
      expect(result.mains, 19);
      expect(result.protein, 15);
      expect(result.veg, 13);
      expect(result.processed, 2);
    });

    test('a meal tagged protein with no kind is not a main', () {
      final result = pattern([
        ...prototypeWeek,
        meal(0, 600, null, tags: const MealTags(protein: true)),
      ]);
      expect(result.mains, 18);
      expect(result.protein, 15);
    });

    test(
      'processed counts only "mostly" on mains, not "unsure" or a snack',
      () {
        final result = pattern(prototypeWeek);
        expect(result.processed, 2);
      },
    );

    test('a week with no sugar and no alcohol takes both points in full', () {
      final result = pattern(mainsWeek([2, 2, 2, 2, 2]));
      expect(result.sugaryDays, 0);
      expect(result.drinks, 0);
      expect(result.points[3], closeTo(1, tight));
      expect(result.points[4], closeTo(1, tight));
    });

    test('every main with protein and half a plate of veg scores 10.0', () {
      expect(pattern(mainsWeek([2, 2, 2, 2, 2])).score, 10.0);
    });

    test('two sugary meals on one day are one sugary day', () {
      final result = pattern([
        ...mainsWeek([2, 2, 2, 2, 2]),
        meal(0, 600, MealKind.snack, tags: const MealTags(sugar: true)),
        meal(0, 700, MealKind.drink, tags: const MealTags(sugar: true)),
      ]);
      expect(result.sugaryDays, 1);
      expect(result.points[3], closeTo((7 / 5 - 4) / -4, tight));
    });

    test('1 to 2 doses count 1.5 drinks and 3 or more count 4', () {
      const one = MealTags(alcohol: MealAlcohol.oneToTwo);
      const three = MealTags(alcohol: MealAlcohol.threeOrMore);
      final result = pattern([
        ...mainsWeek([2, 2, 2, 2, 2]),
        meal(0, 1000, MealKind.drink, tags: one),
        meal(1, 1000, MealKind.drink, tags: one),
        meal(2, 1000, MealKind.drink, tags: three),
      ]);
      expect(result.drinks, closeTo(7, tight));
      expect(result.points[4], closeTo((7 * 7 / 5 - 10) / -8, tight));
    });
  });
}

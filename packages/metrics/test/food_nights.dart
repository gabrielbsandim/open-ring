// Invented on purpose: the seeded nightly values of prototype/food.html, not
// anyone's real data. Recorded health data must never enter this file.
import 'dart:math' as math;

import 'package:metrics/metrics.dart';

/// Night 0 of the prototype calendar, Monday 7 Sep 2026, so offset % 7 is 4
/// on a Friday and 5 on a Saturday, as in the prototype's isWE.
const day0 = LocalDate(2026, 9, 7);

LocalDate day(int offset) => day0.addDays(offset);

int dayOf(LocalDate date) => date.daysSince(day0);

/// Local wall clock on the calendar day of [offset]. Minutes past 1440 land on
/// the next calendar day, which is still the same food day before 05:00.
DateTime clock(int offset, int minutes) {
  final date = day(offset);
  return DateTime(date.year, date.month, date.day, 0, minutes);
}

const alc3Nights = [5, 11, 21, 25, 34, 40, 48, 54, 62, 69, 75, 88];
const alc12Nights = [2, 16, 30, 47, 60, 74, 81];
const lateNights = [
  3, 8, 12, 17, 22, 27, 31, 36, 43, 50, 55, 59, 64, 71, 79, 87, //
];
const midLateNights = [4, 13, 26, 41, 57, 76, 89];
const caffeineNights = [
  1, 6, 9, 14, 20, 23, 29, 35, 38, 44, 49, 56, 63, 70, 77, 82, //
];
const heavyNights = [10, 24, 31, 45, 52, 66, 73, 80, 87];
const incompleteNights = [7, 18, 39, 58, 72, 86];
const fixedOnsets = {84: 20, 85: 15, 86: 40, 87: 30, 88: 80, 89: 50, 90: 10};

/// The prototype window is nights 1 to 90.
final LocalDate prototypeLastNight = day(90);

double _noise(int o, int seed) =>
    ((o * 7919 + seed * 104729 + 13) % 101) / 101 - 0.5;

int _flag(List<int> nights, int o) => nights.contains(o) ? 1 : 0;

int _weekend(int o) => o % 7 == 4 || o % 7 == 5 ? 1 : 0;

int prototypeHeartRate(int o) =>
    (53 +
            7.3 * _noise(o, 1) +
            4.5 * _flag(lateNights, o) +
            6 * _flag(alc3Nights, o) +
            2.5 * _flag(alc12Nights, o) +
            _flag(heavyNights, o) +
            0.8 * _weekend(o))
        .round();

int prototypeHrv(int o) =>
    (48 *
            math.exp(
              0.18 * _noise(o, 2) -
                  0.1 * _flag(lateNights, o) -
                  0.22 * _flag(alc3Nights, o) -
                  0.09 * _flag(alc12Nights, o),
            ))
        .round();

/// Sleep onset in minutes after 23:00 of the night's day.
int prototypeOnsetAfter23(int o) =>
    fixedOnsets[o] ??
    (20 +
            36 * _noise(o, 3) +
            5 * _flag(caffeineNights, o) +
            12 * _flag(alc3Nights, o) +
            10 * _weekend(o))
        .round();

int _onsetMinute(int o) => 23 * 60 + prototypeOnsetAfter23(o);

// Last meal to onset: under 2 h on late nights, 2 h 30 on the blocked band,
// 4 h on every other night.
int _gapToSleep(int o) {
  if (lateNights.contains(o)) return 60;
  if (midLateNights.contains(o)) return 150;
  return 240;
}

MealAlcohol? _alcohol(int o) {
  if (alc3Nights.contains(o)) return MealAlcohol.threeOrMore;
  if (alc12Nights.contains(o)) return MealAlcohol.oneToTwo;
  return null;
}

// Every day has a morning coffee, so caffeine before 14:00 is on all nights.
List<MealEntry> prototypeMealsOf(int o) => [
  MealEntry(
    at: clock(o, 7 * 60 + 30),
    kind: MealKind.drink,
    tags: const MealTags(caffeine: true),
  ),
  MealEntry(
    at: clock(o, 8 * 60),
    kind: MealKind.main,
    tags: const MealTags(protein: true),
  ),
  if (caffeineNights.contains(o))
    MealEntry(
      at: clock(o, 15 * 60),
      kind: MealKind.drink,
      tags: const MealTags(caffeine: true),
    ),
  MealEntry(
    at: clock(o, _onsetMinute(o) - _gapToSleep(o)),
    kind: MealKind.main,
    tags: MealTags(
      protein: true,
      heavy: heavyNights.contains(o),
      alcohol: _alcohol(o),
    ),
    last: !incompleteNights.contains(o),
  ),
];

FoodNight prototypeNight(int o) => FoodNight(
  day: day(o),
  heartRate: prototypeHeartRate(o).toDouble(),
  hrv: prototypeHrv(o).toDouble(),
  sleepOnset: clock(o, _onsetMinute(o)),
);

final List<FoodNight> prototypeNights = [
  for (var o = 1; o <= 90; o++) prototypeNight(o),
];

final List<MealEntry> prototypeMeals = [
  for (var o = 1; o <= 90; o++) ...prototypeMealsOf(o),
];

/// Pairs from the prototype's pairsFor, exposed night first, in its order.
const Map<FoodLink, List<(int, int)>> prototypePairs = {
  FoodLink.alcoholThreeOrMore: [
    (5, 4), (11, 12), (21, 20), (25, 26), (34, 35), (40, 46), //
    (48, 49), (54, 53), (62, 63), (69, 70), (75, 68), (88, 89),
  ],
  FoodLink.alcoholOneToTwo: [
    (2, 1), (16, 15), (30, 29), (47, 46), (60, 61), (74, 68), (81, 82), //
  ],
  FoodLink.lateLastMeal: [
    (3, 1), (8, 9), (12, 19), (17, 15), (22, 23), (27, 28), (31, 29), //
    (36, 35), (43, 42), (50, 49), (55, 56), (59, 63), (64, 65), (71, 70),
    (79, 78), (87, 85),
  ],
  FoodLink.caffeineAfter14: [
    (1, 3), (6, 8), (9, 10), (14, 13), (20, 22), (23, 24), (29, 28), //
    (35, 36), (38, 37), (44, 43), (49, 50), (56, 55), (63, 64), (70, 71),
    (77, 76), (82, 89),
  ],
  FoodLink.heavyDinner: [
    (10, 9), (24, 23), (31, 29), (45, 44), (52, 51), (66, 65), (73, 71), //
    (80, 79), (87, 85),
  ],
};

/// A small book of nights for the edge tests. Each night has an 08:00
/// breakfast and a dinner (19:00 unless told), the dinner marked last.
final class NightBook {
  final List<FoodNight> nights = [];
  final List<MealEntry> meals = [];

  void add(
    int o, {
    MealAlcohol? alcohol,
    bool heavy = false,
    int dinner = 19 * 60,
    int? onset = 23 * 60 + 30,
    bool complete = true,
    double? heartRate = 55,
    double? hrv = 50,
    List<MealEntry> extra = const [],
  }) {
    meals
      ..add(
        MealEntry(
          at: clock(o, 8 * 60),
          kind: MealKind.main,
          tags: const MealTags(protein: true),
        ),
      )
      ..add(
        MealEntry(
          at: clock(o, dinner),
          kind: MealKind.main,
          tags: MealTags(protein: true, heavy: heavy, alcohol: alcohol),
          last: complete,
        ),
      )
      ..addAll(extra);
    nights.add(
      FoodNight(
        day: day(o),
        heartRate: heartRate,
        hrv: hrv,
        sleepOnset: onset == null ? null : clock(o, onset),
      ),
    );
  }
}

MealEntry caffeineAt(int o, int minutes) => MealEntry(
  at: clock(o, minutes),
  kind: MealKind.drink,
  tags: const MealTags(caffeine: true),
);

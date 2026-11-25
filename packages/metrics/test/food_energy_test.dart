import 'package:metrics/metrics.dart';
import 'package:test/test.dart';

typedef _Row = ({
  double slope,
  double logMean,
  double weekMean,
  double previousMean,
  double ringMean,
  double balance,
  double expenditureLog,
  double factorLow,
  double factorHigh,
  int weekLow,
  int weekHigh,
  FoodEnergyGapDirection gap,
  double gapLow,
  double gapHigh,
  FoodEnergyShown? gapShown,
  FoodEnergyChangeDirection change,
  double changeLow,
  double changeHigh,
  FoodEnergyShown changeShown,
});

const _target = 'h|m|1|3';
const _sunday = LocalDate(2026, 12, 6);
const _start = LocalDate(2026, 11, 2);

void _expectRow(FoodEnergyFigures f, _Row row) {
  expect(f.slopeKgPerDay, closeTo(row.slope, 1e-6));
  expect(f.logMean, closeTo(row.logMean, 1e-6));
  expect(f.weekMean, closeTo(row.weekMean, 1e-6));
  expect(f.previousMean, closeTo(row.previousMean, 1e-6));
  expect(f.ringMean, closeTo(row.ringMean, 1e-6));
  expect(f.balance, closeTo(row.balance, 1e-6));
  expect(f.expenditureLog, closeTo(row.expenditureLog, 1e-6));
  expect(f.factorLow, closeTo(row.factorLow, 1e-6));
  expect(f.factorHigh, closeTo(row.factorHigh, 1e-6));
  expect(f.weekLow, row.weekLow);
  expect(f.weekHigh, row.weekHigh);
  expect(f.gapDirection, row.gap);
  expect(f.gapLow, closeTo(row.gapLow, 1e-6));
  expect(f.gapHigh, closeTo(row.gapHigh, 1e-6));
  expect(f.gapShown, row.gapShown);
  expect(f.changeDirection, row.change);
  expect(f.changeLow, closeTo(row.changeLow, 1e-6));
  expect(f.changeHigh, closeTo(row.changeHigh, 1e-6));
  expect(f.changeShown, row.changeShown);
}

FoodEnergyFigures _figures(_Row row) => foodEnergyFigures(
  slopeKgPerDay: row.slope,
  logMean: row.logMean,
  weekMean: row.weekMean,
  previousMean: row.previousMean,
  ringMean: row.ringMean,
);

final _rows = <String, _Row>{
  'F1': (
    slope: -0.03,
    logMean: 1780,
    weekMean: 1700,
    previousMean: 1800,
    ringMean: 2500,
    balance: -231,
    expenditureLog: 2011,
    factorLow: 1.0566882148,
    factorHigh: 1.4296369965,
    weekLow: 1800,
    weekHigh: 2450,
    gap: FoodEnergyGapDirection.under,
    gapLow: 5.3647058824,
    gapHigh: 30.0521739130,
    gapShown: (low: 5, high: 30),
    change: FoodEnergyChangeDirection.none,
    changeLow: -292.9636996519,
    changeHigh: 44.3311785182,
    changeShown: (low: -290, high: 40),
  ),
  'F2': (
    slope: -0.03,
    logMean: 1730,
    weekMean: 1450,
    previousMean: 1800,
    ringMean: 2500,
    balance: -231,
    expenditureLog: 1961,
    factorLow: 1.0836308006,
    factorHigh: 1.4660887302,
    weekLow: 1550,
    weekHigh: 2150,
    gap: FoodEnergyGapDirection.under,
    gapLow: 7.7176470588,
    gapHigh: 31.7913043478,
    gapShown: (low: 8, high: 32),
    change: FoodEnergyChangeDirection.less,
    changeLow: -663.1310555839,
    changeHigh: -229.2707802142,
    changeShown: (low: -660, high: -230),
  ),
  'F3': (
    slope: -0.0315,
    logMean: 1720,
    weekMean: 1680,
    previousMean: 1745,
    ringMean: 2560,
    balance: -242.55,
    expenditureLog: 1962.55,
    factorLow: 1.1087615602,
    factorHigh: 1.5000891697,
    weekLow: 1850,
    weekHigh: 2500,
    gap: FoodEnergyGapDirection.under,
    gapLow: 9.8092830882,
    gapHigh: 33.3372961957,
    gapShown: (low: 10, high: 33),
    change: FoodEnergyChangeDirection.none,
    changeLow: -247.5057960306,
    changeHigh: 77.9304985860,
    changeShown: (low: -250, high: 80),
  ),
  'F4': (
    slope: 0,
    logMean: 2600,
    weekMean: 2600,
    previousMean: 2600,
    ringMean: 2000,
    balance: 0,
    expenditureLog: 2600,
    factorLow: 0.6538461538,
    factorHigh: 0.8846153846,
    weekLow: 1700,
    weekHigh: 2300,
    gap: FoodEnergyGapDirection.over,
    gapLow: -52.9411764706,
    gapHigh: -13.0434782609,
    gapShown: (low: 13, high: 53),
    change: FoodEnergyChangeDirection.none,
    changeLow: -150,
    changeHigh: 150,
    changeShown: (low: -150, high: 150),
  ),
  'F5': (
    slope: 0,
    logMean: 2400,
    weekMean: 2400,
    previousMean: 2400,
    ringMean: 2400,
    balance: 0,
    expenditureLog: 2400,
    factorLow: 0.85,
    factorHigh: 1.15,
    weekLow: 2050,
    weekHigh: 2750,
    gap: FoodEnergyGapDirection.none,
    gapLow: -17.6470588235,
    gapHigh: 13.0434782609,
    gapShown: null,
    change: FoodEnergyChangeDirection.none,
    changeLow: -150,
    changeHigh: 150,
    changeShown: (low: -150, high: 150),
  ),
  'F6': (
    slope: 0,
    logMean: 2000,
    weekMean: 2100,
    previousMean: 1800,
    ringMean: 2400,
    balance: 0,
    expenditureLog: 2000,
    factorLow: 1.02,
    factorHigh: 1.38,
    weekLow: 2150,
    weekHigh: 2900,
    gap: FoodEnergyGapDirection.under,
    gapLow: 1.9607843137,
    gapHigh: 27.5362318841,
    gapShown: (low: 2, high: 28),
    change: FoodEnergyChangeDirection.more,
    changeLow: 156,
    changeHigh: 564,
    changeShown: (low: 160, high: 560),
  ),
};

FoodEnergyDay _day(LocalDate date, double log, [String target = _target]) =>
    (date: date, logKcal: log, targets: {target});

bool _w1Skips(int i) => i == 6 || i == 13 || i == 20 || i == 27 || i == 34;

List<FoodEnergyDay> _w1Days({double weeks = 1800, double shown = 1700}) => [
  for (var i = 0; i < 35; i++)
    if (!_w1Skips(i)) _day(_start.addDays(i), i < 28 ? weeks : shown),
];

List<DailyValue> _w1Weights({double slope = -0.03}) => [
  for (var i = 0; i < 35; i++)
    if (i % 5 != 4) (date: _start.addDays(i), value: 80.0 + slope * i),
];

List<DailyValue> _w1Ring({double value = 2500}) => [
  for (var i = 0; i < 35; i++) (date: _start.addDays(i), value: value),
];

FoodEnergyResult _week({
  List<FoodEnergyDay>? days,
  List<DailyValue>? weighIns,
  List<DailyValue>? ring,
  LocalDate? goalBlockStart,
}) => foodEnergyWeek(
  sunday: _sunday,
  days: days ?? _w1Days(),
  weighIns: weighIns ?? _w1Weights(),
  ring: ring ?? _w1Ring(),
  goalBlockStart: goalBlockStart,
);

FoodEnergyHoldReason? _reason(FoodEnergyResult result) =>
    result is FoodEnergyHold ? result.reason : null;

List<FoodEnergyDay> _retarget(List<FoodEnergyDay> days, LocalDate date) => [
  for (final day in days)
    if (day.date == date) _day(day.date, day.logKcal, 'h|m2|1|3') else day,
];

MealEntry _meal(
  int hour, {
  MealKind kind = MealKind.main,
  bool sugar = false,
  bool last = false,
}) => MealEntry(
  at: DateTime(2026, 12, 1, hour),
  kind: kind,
  tags: MealTags(sugar: sugar),
  last: last,
);

void main() {
  group('foodEnergyFigures', () {
    for (final MapEntry(:key, :value) in _rows.entries) {
      test('$key matches the pinned row', () {
        _expectRow(_figures(value), value);
      });
    }

    test('rejects a ring mean or expenditure log under 800', () {
      FoodEnergyFigures figures({double logMean = 2000, double ring = 2500}) =>
          foodEnergyFigures(
            slopeKgPerDay: 0,
            logMean: logMean,
            weekMean: 2000,
            previousMean: 2000,
            ringMean: ring,
          );
      expect(() => figures(ring: 0), throwsArgumentError);
      expect(() => figures(ring: 799), throwsArgumentError);
      expect(() => figures(logMean: 799), throwsArgumentError);
      expect(figures(logMean: 800, ring: 800).factorLow, closeTo(0.85, 1e-6));
    });

    test('stays finite for every expenditure log of 800 or more', () {
      for (final logMean in [800.0, 801.0, 1500.0, 4000.0]) {
        for (final slope in [-0.2, 0.0, 0.2]) {
          final f = foodEnergyFigures(
            slopeKgPerDay: slope,
            logMean: logMean + slope * foodEnergyKcalPerKg,
            weekMean: 0,
            previousMean: 4000,
            ringMean: 800,
          );
          final values = [
            f.factorLow,
            f.factorHigh,
            f.gapLow,
            f.gapHigh,
            f.changeLow,
            f.changeHigh,
          ];
          expect(values.every((v) => v.isFinite), isTrue);
        }
      }
    });
  });

  group('mealLogKcal', () {
    test('M1 is the prototype lunch with oil', () {
      final log = mealLogKcal(const [
        (group: FoodGroup.grainCooked, grams: 90),
        (group: FoodGroup.legumeCooked, grams: 80),
        (group: FoodGroup.poultry, grams: 100),
        (group: FoodGroup.leafySalad, grams: 30),
      ], oil: true);
      expect(log, closeTo(427.5, 1e-6));
    });

    test('each hidden chip adds its fixed log energy', () {
      expect(mealLogKcal(const []), 0);
      expect(mealLogKcal(const [], oil: true, sauce: true, sugar: true), 187);
      expect(mealLogKcal(const [(group: FoodGroup.plainDrink, grams: 300)]), 0);
    });

    test('sauce and sugar each add their own amount alone', () {
      expect(mealLogKcal(const [], sauce: true), 60);
      expect(mealLogKcal(const [], sugar: true), 39);
      expect(mealLogKcal(const [], oil: true), 88);
    });

    test('densities match the verified table', () {
      expect(
        {for (final g in FoodGroup.values) g.name: g.kcalPer100g},
        {
          'grainCooked': 128,
          'bread': 300,
          'legumeCooked': 76,
          'rootCooked': 77,
          'vegetable': 25,
          'leafySalad': 15,
          'fruit': 56,
          'poultry': 159,
          'redMeat': 219,
          'processedMeat': 296,
          'fish': 122,
          'egg': 146,
          'cheese': 330,
          'milkYogurt': 61,
          'friedSnack': 283,
          'mixedDish': 150,
          'pizzaSandwich': 260,
          'sweet': 400,
          'nutsSeeds': 606,
          'fatSauce': 400,
          'sugaryDrink': 40,
          'alcoholicDrink': 60,
          'plainDrink': 0,
          'other': 150,
        },
      );
    });
  });

  group('foodEnergyDay', () {
    const date = LocalDate(2026, 12, 1);
    final coffee = (
      entry: _meal(8, kind: MealKind.drink),
      logKcal: null,
      target: null,
    );
    final lunch = (entry: _meal(12), logKcal: 427.5, target: _target);
    FoodEnergyMeal dinner({double? log = 512.0, bool last = true}) =>
        (entry: _meal(19, last: last), logKcal: log, target: _target);

    test('D1 sums the window meals and plain drinks count 0', () {
      final day = foodEnergyDay(date, [coffee, lunch, dinner()]);
      expect(day!.date, date);
      expect(day.logKcal, closeTo(939.5, 1e-6));
      expect(day.targets, {_target});
    });

    test('an unconfirmed dinner leaves the day out', () {
      expect(foodEnergyDay(date, [coffee, lunch, dinner(log: null)]), isNull);
    });

    test('a day with no meal marked last is left out', () {
      expect(foodEnergyDay(date, [coffee, lunch, dinner(last: false)]), isNull);
    });

    test('a sweet drink without items leaves the day out', () {
      final soda = (
        entry: _meal(16, kind: MealKind.drink, sugar: true),
        logKcal: null,
        target: null,
      );
      expect(foodEnergyDay(date, [coffee, lunch, soda, dinner()]), isNull);
    });

    test('meals of another food day are ignored', () {
      expect(foodEnergyDay(date.addDays(1), [lunch, dinner()]), isNull);
    });
  });

  group('foodEnergyWeek', () {
    test('W1 is ready with the F1 figures and its counts', () {
      final result = _week();
      expect(result, isA<FoodEnergyReady>());
      _expectRow((result as FoodEnergyReady).figures, _rows['F1']!);
      expect(result.counts.sunday, _sunday);
      expect(result.counts.days, 30);
      expect(result.counts.weekDays, 6);
      expect(result.counts.weighIns, 28);
      expect(result.counts.ringDays, 35);
    });

    test('H1 a second target key holds as model changed', () {
      final days = _retarget(_w1Days(), _start.addDays(1));
      expect(_reason(_week(days: days)), FoodEnergyHoldReason.modelChanged);
    });

    test('H2 the first 14 days of a goal block hold', () {
      expect(
        _reason(_week(goalBlockStart: const LocalDate(2026, 11, 23))),
        FoodEnergyHoldReason.goalStart,
      );
      expect(
        _week(goalBlockStart: const LocalDate(2026, 11, 22)),
        isA<FoodEnergyReady>(),
      );
    });

    test('H3 19 weigh-in days hold', () {
      final result = _week(weighIns: _w1Weights().take(19).toList());
      expect(_reason(result), FoodEnergyHoldReason.weighIns);
      expect(result.counts.weighIns, 19);
    });

    test('H4 27 energy days hold', () {
      final result = _week(days: _w1Days().skip(3).toList());
      expect(_reason(result), FoodEnergyHoldReason.days);
      expect(result.counts.days, 27);
      expect(result.counts.weekDays, 6);
    });

    test('H5 4 days in the shown week hold', () {
      final days = [
        for (final day in _w1Days())
          if (day.date != const LocalDate(2026, 11, 30) &&
              day.date != const LocalDate(2026, 12, 1))
            day,
      ];
      final result = _week(days: days);
      expect(_reason(result), FoodEnergyHoldReason.days);
      expect(result.counts.days, 28);
      expect(result.counts.weekDays, 4);
    });

    test('H6 19 ring days hold', () {
      final result = _week(ring: _w1Ring().take(19).toList());
      expect(_reason(result), FoodEnergyHoldReason.ringDays);
      expect(result.counts.ringDays, 19);
    });

    test('a ring mean under 800 is implausible with expLog over 800', () {
      final result = _week(ring: _w1Ring(value: 799));
      expect(_reason(result), FoodEnergyHoldReason.implausible);
    });

    test('the slope is fitted on daily mean weights', () {
      final weighIns = [(date: _start, value: 79.0), ..._w1Weights()];
      final result = _week(weighIns: weighIns) as FoodEnergyReady;
      expect(result.counts.weighIns, 28);
      expect(result.figures.slopeKgPerDay, closeTo(-0.027089947090, 1e-9));
    });

    test('H7 an expenditure log under 800 is implausible', () {
      final result = _week(
        days: _w1Days(weeks: 600, shown: 600),
        weighIns: _w1Weights(slope: 0),
        ring: _w1Ring(value: 700),
      );
      expect(_reason(result), FoodEnergyHoldReason.implausible);
    });

    test('H1 and H3 together report model changed', () {
      final result = _week(
        days: _retarget(_w1Days(), _start),
        weighIns: _w1Weights().take(19).toList(),
      );
      expect(_reason(result), FoodEnergyHoldReason.modelChanged);
    });

    test('days, weigh-ins and ring outside the window are ignored', () {
      final early = _start.addDays(-1);
      final result = _week(
        days: [..._w1Days(), _day(early, 9000, 'h|m2|1|3')],
        weighIns: [..._w1Weights(), (date: early, value: 200)],
        ring: [..._w1Ring(), (date: _sunday.addDays(1), value: 9000)],
      );
      _expectRow((result as FoodEnergyReady).figures, _rows['F1']!);
    });
  });

  group('foodEnergyLatest', () {
    const first = LocalDate(2026, 10, 26);
    const earlierSunday = LocalDate(2026, 11, 29);
    final days = [
      for (var i = 0; i < 42; i++)
        if (i % 7 != 6)
          _day(
            first.addDays(i),
            i < 35 ? 1800 : 1700,
            i == 37 ? 'h|m2|1|3' : _target,
          ),
    ];
    final weighIns = [
      for (var i = 0; i < 42; i++)
        if (i % 5 != 4) (date: first.addDays(i), value: 80.2 - 0.03 * i),
    ];
    final ring = [
      for (var i = 0; i < 42; i++) (date: first.addDays(i), value: 2500.0),
    ];

    test('L1 a held week carries the last ready week', () {
      final result = foodEnergyLatest(
        latestSunday: _sunday,
        days: days,
        weighIns: weighIns,
        ring: ring,
      );
      expect(_reason(result), FoodEnergyHoldReason.modelChanged);
      expect(result.counts.sunday, _sunday);
      final last = (result as FoodEnergyHold).last!;
      expect(last.counts.sunday, earlierSunday);
      expect(last.counts.days, 30);
      expect(last.counts.weekDays, 6);
      expect(last.counts.weighIns, 28);
      expect(last.counts.ringDays, 35);
      final f = last.figures;
      expect(f.slopeKgPerDay, closeTo(-0.03, 1e-6));
      expect(f.logMean, closeTo(1800, 1e-6));
      expect(f.weekMean, closeTo(1800, 1e-6));
      expect(f.previousMean, closeTo(1800, 1e-6));
      expect(f.ringMean, closeTo(2500, 1e-6));
      expect(f.expenditureLog, closeTo(2031, 1e-6));
      expect(f.weekLow, 1900);
      expect(f.weekHigh, 2550);
      expect(f.changeShown, (low: -150, high: 150));
    });

    test('a ready latest week is returned as it is', () {
      final result = foodEnergyLatest(
        latestSunday: _sunday,
        days: _w1Days(),
        weighIns: _w1Weights(),
        ring: _w1Ring(),
      );
      expect(result, isA<FoodEnergyReady>());
      expect(result.counts.sunday, _sunday);
    });

    FoodEnergyResult latestWithW1Back(int weeks) {
      LocalDate moved(LocalDate date) => date.addDays(-7 * weeks);
      return foodEnergyLatest(
        latestSunday: _sunday,
        days: [for (final d in _w1Days()) _day(moved(d.date), d.logKcal)],
        weighIns: [
          for (final w in _w1Weights()) (date: moved(w.date), value: w.value),
        ],
        ring: [
          for (final r in _w1Ring()) (date: moved(r.date), value: r.value),
        ],
      );
    }

    test('the only ready week exactly 4 Sundays back is found', () {
      final result = latestWithW1Back(4) as FoodEnergyHold;
      expect(result.last!.counts.sunday, _sunday.addDays(-28));
      _expectRow(result.last!.figures, _rows['F1']!);
    });

    test('a ready week 5 Sundays back is out of reach', () {
      final result = latestWithW1Back(5) as FoodEnergyHold;
      expect(result.last, isNull);
    });

    test('with no ready week in the 4 before, last is null', () {
      final result = foodEnergyLatest(
        latestSunday: _sunday,
        days: _retarget(_w1Days(), _start),
        weighIns: _w1Weights(),
        ring: _w1Ring(),
      );
      expect(_reason(result), FoodEnergyHoldReason.modelChanged);
      expect((result as FoodEnergyHold).last, isNull);
    });
  });
}

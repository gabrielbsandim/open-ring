import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/core/widgets/charts.dart';
import 'package:open_ring/features/food/application/food_week.dart';
import 'package:open_ring/features/food/domain/meal.dart';
import 'package:open_ring/features/food/presentation/food_timing_chart.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

import '../../../helpers/layout_harness.dart';

const _monday = LocalDate(2026, 11, 9);
const _sunday = LocalDate(2026, 11, 15);

Meal _meal(
  int id,
  DateTime at, {
  MealKind kind = MealKind.main,
  MealTags? tags,
  bool last = false,
}) => Meal(
  id: id,
  at: at,
  offsetMinutes: 0,
  createdAt: at,
  kind: kind,
  tags: tags ?? const MealTags(),
  last: last,
);

FoodWeekDayView _day(
  LocalDate date, {
  List<Meal> meals = const [],
  bool complete = false,
  DateTime? sleepOnset,
  double? windowMinutes,
  double? gapMinutes,
}) => FoodWeekDayView(
  date: date,
  meals: meals,
  complete: complete,
  sleepOnset: sleepOnset,
  windowMinutes: windowMinutes,
  gapMinutes: gapMinutes,
);

void main() {
  group('foodTimingMinuteOfDay and foodTimingX', () {
    test('maps same-day and post-midnight wall-clock minutes accurately', () {
      expect(
        foodTimingMinuteOfDay(_sunday, DateTime.utc(2026, 11, 15, 6)),
        360,
      );
      expect(
        foodTimingMinuteOfDay(_sunday, DateTime.utc(2026, 11, 15, 12, 30)),
        750,
      );
      expect(
        foodTimingMinuteOfDay(_sunday, DateTime.utc(2026, 11, 16, 0, 30)),
        1470,
      );
      expect(
        foodTimingMinuteOfDay(_sunday, DateTime.utc(2026, 11, 16, 0, 30)),
        greaterThan(1440),
      );
    });

    test('maps ticks across [360..1500], clamps bounds, and guards <= 0', () {
      expect(foodTimingX(360, 114), 0);
      expect(foodTimingX(720, 114), closeTo(36, 0.001));
      expect(foodTimingX(1080, 114), closeTo(72, 0.001));
      expect(foodTimingX(1440, 114), closeTo(108, 0.001));
      expect(foodTimingX(1470, 114), closeTo(111, 0.001));
      expect(foodTimingX(1500, 114), closeTo(114, 0.001));
      expect(foodTimingX(300, 114), 0);
      expect(foodTimingX(1700, 114), closeTo(114, 0.001));
      expect(foodTimingX(720, 0), 0);
      expect(foodTimingX(720, -10), 0);
    });
  });

  group('foodTimingRowOf', () {
    test(
      'omits window bar on plain-drink-only day while keeping meal dots',
      () {
        final view = _day(
          _monday,
          meals: [
            _meal(1, DateTime.utc(2026, 11, 9, 8), kind: MealKind.drink),
            _meal(
              2,
              DateTime.utc(2026, 11, 9, 15, 30),
              kind: MealKind.drink,
              last: true,
            ),
          ],
          complete: true,
        );

        final row = foodTimingRowOf(view);

        expect(row.windowStartMinute, isNull);
        expect(row.windowEndMinute, isNull);
        expect(row.mealMinutes, [480, 930]);
        expect(row.complete, isTrue);
        expect(row.sleepOnsetMinute, isNull);
      },
    );

    test('includes sugary or alcoholic drinks in window endpoints', () {
      final view = _day(
        _monday,
        meals: [
          _meal(
            1,
            DateTime.utc(2026, 11, 9, 7, 30),
            kind: MealKind.drink,
            tags: const MealTags(sugar: true),
          ),
          _meal(2, DateTime.utc(2026, 11, 9, 20)),
          _meal(
            3,
            DateTime.utc(2026, 11, 9, 22),
            kind: MealKind.drink,
            tags: const MealTags(alcohol: MealAlcohol.oneToTwo),
            last: true,
          ),
        ],
        complete: true,
        sleepOnset: DateTime.utc(2026, 11, 10, 0, 15),
      );

      final row = foodTimingRowOf(view);

      expect(row.windowStartMinute, 450);
      expect(row.windowEndMinute, 1320);
      expect(row.mealMinutes, [450, 1200, 1320]);
      expect(row.sleepOnsetMinute, 1455);
    });
  });

  group('FoodTimingChart widget', () {
    testWidgets('returns empty box when days is empty', (tester) async {
      await pumpScaled(
        tester,
        screenHost(const FoodTimingChart(days: [], completeDays: 0)),
        textScaler: TextScaler.noScaling,
        brightness: Brightness.dark,
        locale: const Locale('en'),
      );

      expect(find.byKey(FoodTimingChartKeys.paint), findsNothing);
      expect(find.byKey(FoodTimingChartKeys.axis), findsNothing);
    });

    testWidgets('renders 7 rows, CustomPaint, TimeAxis, and semantics for mixed'
        ' complete, incomplete, plain-drink, single-meal, and post-midnight '
        'days', (tester) async {
      final l10n = lookupAppLocalizations(const Locale('en'));
      final days = [
        _day(
          _monday,
          meals: [
            _meal(1, DateTime.utc(2026, 11, 9, 8)),
            _meal(2, DateTime.utc(2026, 11, 9, 20), last: true),
          ],
          complete: true,
          sleepOnset: DateTime.utc(2026, 11, 9, 23, 20),
          windowMinutes: 720,
          gapMinutes: 200,
        ),
        _day(
          _monday.addDays(1),
          meals: [_meal(3, DateTime.utc(2026, 11, 10, 13))],
          sleepOnset: DateTime.utc(2026, 11, 10, 23, 45),
        ),
        _day(
          _monday.addDays(2),
          meals: [
            _meal(4, DateTime.utc(2026, 11, 11, 9), kind: MealKind.drink),
          ],
          complete: true,
        ),
        _day(_monday.addDays(3)),
        _day(_monday.addDays(4)),
        _day(_monday.addDays(5)),
        _day(
          _sunday,
          meals: [
            _meal(5, DateTime.utc(2026, 11, 15, 11)),
            _meal(
              6,
              DateTime.utc(2026, 11, 16, 0, 30),
              kind: MealKind.snack,
              last: true,
            ),
          ],
          complete: true,
          sleepOnset: DateTime.utc(2026, 11, 16, 1, 15),
          windowMinutes: 810,
          gapMinutes: 45,
        ),
      ];

      await pumpScaled(
        tester,
        screenHost(FoodTimingChart(days: days, completeDays: 3)),
        textScaler: TextScaler.noScaling,
        brightness: Brightness.dark,
        locale: const Locale('en'),
      );

      final chartFinder = find.byType(FoodTimingChart);
      final f = MetricFormat.of(tester.element(chartFinder));
      for (final d in days) {
        expect(
          find.byKey(FoodTimingChartKeys.rowLabel(d.date)),
          findsOneWidget,
        );
        expect(find.text('${f.weekday(d.date)} ${d.date.day}'), findsOneWidget);
      }
      expect(find.byKey(FoodTimingChartKeys.paint), findsOneWidget);
      expect(find.byKey(FoodTimingChartKeys.axis), findsOneWidget);
      expect(find.byType(TimeAxis), findsOneWidget);
      expect(
        tester.getSemantics(chartFinder).label,
        l10n.foodTimingChartLabel(3),
      );
      expect(tester.takeException(), isNull);
    });
  });
}

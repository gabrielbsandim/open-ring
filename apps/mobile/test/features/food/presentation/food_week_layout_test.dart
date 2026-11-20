import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/features/food/application/food_nights.dart';
import 'package:open_ring/features/food/application/meal_store_providers.dart';
import 'package:open_ring/features/food/domain/meal_camera.dart';
import 'package:open_ring/features/food/domain/photo_store.dart';
import 'package:open_ring/features/food/presentation/food_day_screen.dart';
import 'package:open_ring/features/food/presentation/food_week_screen.dart';
import 'package:open_ring/features/goals/application/goal_store_providers.dart';
import 'package:open_ring/features/goals/domain/goal.dart';
import 'package:open_ring/features/goals/domain/goal_store.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/modules/domain/module_store.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

import '../../../helpers/layout_harness.dart';
import '../food_fakes.dart';
import '../jpeg_fixture.dart';

// Tuesday 17 Nov 2026: closed Mon..Sun week is 2026-11-09 to 2026-11-15.
final _now = DateTime(2026, 11, 17, 21);
const _monday = LocalDate(2026, 11, 9);
const _sunday = LocalDate(2026, 11, 15);

Future<(TestMealStore, PhotoStore)> _populatedClosedWeek() async {
  final meals = TestMealStore();
  final photos = InMemoryPhotoStore();
  final bytes = strippedPlain();

  // Mon..Sat (6 days): 6 complete days, 12 mains + 1 snack, mixing photo and
  // no-photo thumbnails, leaving Sun empty.
  for (var i = 0; i < 6; i++) {
    final day = _monday.addDays(i);
    final lunch = meals.seed(
      DateTime(day.year, day.month, day.day, 12, 30),
      kind: MealKind.main,
      tags: MealTags(
        protein: true,
        veg: i.isEven ? MealVeg.halfOrMore : MealVeg.some,
      ),
    );
    if (i.isEven) {
      final name = 'meal_${lunch.id}.jpg';
      await photos.save(name, bytes);
      await meals.attachPhoto(lunch.id, name);
    }
    if (i == 2) {
      meals.seed(
        DateTime(day.year, day.month, day.day, 16),
        kind: MealKind.snack,
        tags: const MealTags(sugar: true),
      );
    }
    final dinner = meals.seed(
      DateTime(day.year, day.month, day.day, 19, 30),
      kind: MealKind.main,
      tags: MealTags(
        protein: i < 4,
        processed: i == 0 ? MealProcessed.mostly : null,
        alcohol: i == 4 ? MealAlcohol.oneToTwo : null,
      ),
      last: true,
    );
    if (i.isOdd) {
      final name = 'meal_${dinner.id}.jpg';
      await photos.save(name, bytes);
      await meals.attachPhoto(dinner.id, name);
    }
  }
  return (meals, photos);
}

Future<void> _pumpWeek(
  WidgetTester tester,
  LayoutCase c, {
  required TestMealStore meals,
  required PhotoStore photos,
  GoalStore? goals,
}) => pumpScaled(
  tester,
  screenHost(const FoodWeekScreen()),
  textScaler: c.textScaler,
  brightness: c.brightness,
  locale: c.locale,
  overrides: [
    moduleStoreProvider.overrideWithValue(
      InMemoryModuleStore(const {ModuleId.food}),
    ),
    clockProvider.overrideWithValue(() => _now),
    mealStoreProvider.overrideWithValue(meals),
    photoStoreProvider.overrideWithValue(photos),
    mealCameraProvider.overrideWithValue(FakeMealCamera()),
    foodNightsProvider.overrideWith((ref) async => const []),
    goalStoreProvider.overrideWithValue(goals ?? InMemoryGoalStore()),
  ],
);

Future<void> _pumpDay(
  WidgetTester tester,
  LayoutCase c, {
  required TestMealStore meals,
}) => pumpScaled(
  tester,
  screenHost(const FoodDayScreen()),
  textScaler: c.textScaler,
  brightness: c.brightness,
  locale: c.locale,
  overrides: foodOverrides(
    meals: meals,
    camera: FakeMealCamera(),
    clock: () => _now,
  ),
);

void main() {
  group('FoodWeekScreen and FoodSectionTabs layout matrix', () {
    for (final c in layoutMatrix()) {
      testWidgets('FoodWeekScreen populated week with PlatePattern fits '
          'without overflow at $c', (tester) async {
        final l10n = lookupAppLocalizations(c.locale);
        final (meals, photos) = await _populatedClosedWeek();

        await _pumpWeek(tester, c, meals: meals, photos: photos);

        final format = MetricFormat.of(
          tester.element(find.byType(FoodWeekScreen)),
        );
        final rangeText = l10n.metricTimeRange(
          format.monthDay(_monday),
          format.monthDay(_sunday),
        );

        expect(find.byKey(FoodWeekKeys.tabs), findsOneWidget);
        expect(find.byKey(FoodWeekKeys.contactSheet), findsOneWidget);
        expect(find.text(rangeText), findsOneWidget);
        expect(find.text(l10n.foodWeekLast), findsOneWidget);
        for (var i = 0; i < 7; i++) {
          expect(
            find.byKey(FoodWeekKeys.dayColumn(_monday.addDays(i))),
            findsOneWidget,
          );
        }
        expect(find.byKey(FoodWeekKeys.emptyDay(_sunday)), findsOneWidget);
        expect(find.byKey(FoodWeekKeys.plateCard), findsOneWidget);

        await expectNoLayoutOverflow(() async {
          await tester.scrollUntilVisible(
            find.text(l10n.foodPlateNote),
            120,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.pumpAndSettle();
        });

        expect(find.text(l10n.foodPlateNote), findsOneWidget);
      });

      testWidgets('FoodWeekScreen with softMode == true fits without overflow '
          'at $c', (tester) async {
        final l10n = lookupAppLocalizations(c.locale);
        final (meals, photos) = await _populatedClosedWeek();
        final goals = InMemoryGoalStore();
        await goals.addScreening(
          const GoalScreening(
            on: LocalDate(2026, 11, 1),
            softMode: true,
            pregnantOrBreastfeeding: null,
          ),
        );

        await _pumpWeek(tester, c, meals: meals, photos: photos, goals: goals);

        expect(find.byKey(FoodWeekKeys.plateCard), findsNothing);
        expect(find.byKey(FoodWeekKeys.softModeCard), findsOneWidget);

        await expectNoLayoutOverflow(() async {
          await tester.scrollUntilVisible(
            find.text(l10n.foodWeekSoftBody),
            120,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.pumpAndSettle();
        });

        expect(find.text(l10n.foodWeekSoftTitle), findsOneWidget);
        expect(find.text(l10n.foodWeekSoftBody), findsOneWidget);
      });

      testWidgets('FoodDayScreen with FoodSectionTabs fits without overflow '
          'at $c', (tester) async {
        final meals = TestMealStore()..seed(DateTime(2026, 11, 17, 12, 30));

        await _pumpDay(tester, c, meals: meals);

        expect(find.byKey(FoodWeekKeys.tabs), findsOneWidget);
        expect(find.byKey(FoodWeekKeys.tabDay), findsOneWidget);
        expect(find.byKey(FoodWeekKeys.tabWeek), findsOneWidget);
      });
    }
  });
}

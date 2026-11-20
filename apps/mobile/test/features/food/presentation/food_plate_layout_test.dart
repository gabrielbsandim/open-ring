import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/features/food/application/meal_store_providers.dart';
import 'package:open_ring/features/food/domain/meal_camera.dart';
import 'package:open_ring/features/food/domain/photo_store.dart';
import 'package:open_ring/features/food/presentation/food_plate_screen.dart';
import 'package:open_ring/features/goals/application/goal_store_providers.dart';
import 'package:open_ring/features/goals/domain/goal.dart';
import 'package:open_ring/features/goals/domain/goal_store.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/modules/domain/module_store.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

import '../../../helpers/layout_harness.dart';
import '../food_fakes.dart';

final _now = DateTime(2026, 11, 17, 21);
const _w1Monday = LocalDate(2026, 11, 9);

TestMealStore _qualifiedMeals() {
  final meals = TestMealStore();
  for (var d = 0; d < 6; d++) {
    final day = _w1Monday.addDays(d);
    meals
      ..seed(
        DateTime(day.year, day.month, day.day, 8),
        kind: MealKind.main,
        tags: const MealTags(protein: true, veg: MealVeg.halfOrMore),
      )
      ..seed(
        DateTime(day.year, day.month, day.day, 19),
        kind: MealKind.main,
        tags: MealTags(
          protein: d < 5,
          veg: d < 4 ? MealVeg.some : null,
          processed: d == 0 ? MealProcessed.mostly : null,
          sugar: d == 1,
          alcohol: d == 4 ? MealAlcohol.oneToTwo : null,
        ),
        last: true,
      );
  }
  return meals;
}

Future<void> _pumpPlateLayout(
  WidgetTester tester,
  LayoutCase c, {
  required TestMealStore meals,
  GoalStore? goals,
}) => pumpScaled(
  tester,
  screenHost(const FoodPlateScreen()),
  textScaler: c.textScaler,
  brightness: c.brightness,
  locale: c.locale,
  overrides: [
    moduleStoreProvider.overrideWithValue(
      InMemoryModuleStore(const {ModuleId.food}),
    ),
    clockProvider.overrideWithValue(() => _now),
    mealStoreProvider.overrideWithValue(meals),
    photoStoreProvider.overrideWithValue(InMemoryPhotoStore()),
    mealCameraProvider.overrideWithValue(FakeMealCamera()),
    goalStoreProvider.overrideWithValue(goals ?? InMemoryGoalStore()),
  ],
);

void main() {
  group('FoodPlateScreen layout matrix', () {
    for (final c in layoutMatrix()) {
      testWidgets('FoodPlateScreen PlatePattern fits without overflow at $c', (
        tester,
      ) async {
        final l10n = lookupAppLocalizations(c.locale);
        await _pumpPlateLayout(tester, c, meals: _qualifiedMeals());

        expect(find.byKey(FoodPlateKeys.lead), findsOneWidget);
        await expectNoLayoutOverflow(() async {
          final scrollable = find.byType(Scrollable).first;
          await tester.scrollUntilVisible(
            find.byKey(FoodPlateKeys.summaryCard),
            120,
            scrollable: scrollable,
          );
          await tester.scrollUntilVisible(
            find.byKey(FoodPlateKeys.weeksCard),
            120,
            scrollable: scrollable,
          );
          await tester.scrollUntilVisible(
            find.text(l10n.foodPlateOurs2),
            120,
            scrollable: scrollable,
          );
          await tester.pumpAndSettle();
        });
        expect(find.byKey(FoodPlateKeys.oursCard), findsOneWidget);
      });

      testWidgets('FoodPlateScreen PlateBuilding fits without overflow at $c', (
        tester,
      ) async {
        final l10n = lookupAppLocalizations(c.locale);
        await _pumpPlateLayout(tester, c, meals: TestMealStore());

        expect(find.byKey(FoodPlateKeys.lead), findsOneWidget);
        await expectNoLayoutOverflow(() async {
          final scrollable = find.byType(Scrollable).first;
          await tester.scrollUntilVisible(
            find.byKey(FoodPlateKeys.summaryCard),
            120,
            scrollable: scrollable,
          );
          await tester.scrollUntilVisible(
            find.text(l10n.foodPlateOurs2),
            120,
            scrollable: scrollable,
          );
          await tester.pumpAndSettle();
        });
        expect(find.byKey(FoodPlateKeys.oursCard), findsOneWidget);
      });

      testWidgets('FoodPlateScreen softMode fits without overflow at $c', (
        tester,
      ) async {
        final goals = InMemoryGoalStore();
        await goals.addScreening(
          const GoalScreening(
            on: LocalDate(2026, 11, 1),
            softMode: true,
            pregnantOrBreastfeeding: null,
          ),
        );
        await _pumpPlateLayout(
          tester,
          c,
          meals: _qualifiedMeals(),
          goals: goals,
        );
        expect(find.byKey(FoodPlateKeys.softModeCard), findsOneWidget);
      });
    }
  });
}

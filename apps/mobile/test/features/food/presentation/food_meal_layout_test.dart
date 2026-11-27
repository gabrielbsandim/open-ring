import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/features/food/domain/meal_camera.dart';
import 'package:open_ring/features/food/domain/photo_store.dart';
import 'package:open_ring/features/food/presentation/food_meal_screen.dart';
import 'package:open_ring/features/food/presentation/meal_saved_sheet.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

import '../../../helpers/layout_harness.dart';
import '../food_fakes.dart';
import '../jpeg_fixture.dart';

final _now = DateTime(2026, 11, 17, 21);

Future<(TestMealStore, PhotoStore, int)> _seededMeal() async {
  final meals = TestMealStore();
  final photos = InMemoryPhotoStore();
  await photos.save('meal_1.jpg', strippedPlain());
  final meal = meals.seed(
    DateTime(2026, 11, 17, 12, 30),
    kind: MealKind.main,
    tags: const MealTags(
      protein: true,
      caffeine: true,
      heavy: true,
      fried: true,
      sugar: true,
      veg: MealVeg.halfOrMore,
      alcohol: MealAlcohol.oneToTwo,
      processed: MealProcessed.mostly,
      place: MealPlace.restaurant,
    ),
    last: true,
  );
  await meals.attachPhoto(meal.id, 'meal_1.jpg');
  return (meals, photos, meal.id);
}

Future<void> _pumpMeal(
  WidgetTester tester,
  LayoutCase c, {
  required TestMealStore meals,
  required PhotoStore photos,
  required int mealId,
}) => pumpScaled(
  tester,
  screenHost(FoodMealScreen(mealId: mealId)),
  textScaler: c.textScaler,
  brightness: c.brightness,
  locale: c.locale,
  overrides: foodOverrides(
    meals: meals,
    camera: FakeMealCamera(),
    photos: photos,
    clock: () => _now,
  ),
);

Future<void> _scrollAndTap(WidgetTester tester, Key key) async {
  await tester.scrollUntilVisible(
    find.byKey(key),
    120,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(key));
  await tester.pumpAndSettle();
}

void main() {
  group('F8 FoodMealScreen layout matrix', () {
    for (final c in layoutMatrix()) {
      testWidgets(
        'FoodMealScreen, kcal sheet, and delete sheet fit without overflow '
        'at $c',
        (tester) async {
          final l10n = lookupAppLocalizations(c.locale);
          final (meals, photos, mealId) = await _seededMeal();

          await _pumpMeal(
            tester,
            c,
            meals: meals,
            photos: photos,
            mealId: mealId,
          );

          await expectNoLayoutOverflow(() async {
            final list = find.byType(Scrollable).first;
            expect(find.byKey(FoodMealKeys.photo), findsOneWidget);

            for (final key in [
              FoodMealKeys.timeTile,
              MealSavedSheetKeys.kind(MealKind.main),
              MealSavedSheetKeys.place(MealPlace.restaurant),
              FoodMealKeys.lastMeal,
              FoodMealKeys.kcalTile,
              FoodMealKeys.deleteTile,
            ]) {
              await tester.scrollUntilVisible(
                find.byKey(key),
                120,
                scrollable: list,
              );
              await tester.pumpAndSettle();
            }

            await tester.scrollUntilVisible(
              find.text(l10n.foodMealFoot),
              120,
              scrollable: list,
            );
            await tester.pumpAndSettle();

            await _scrollAndTap(tester, FoodMealKeys.kcalTile);
            expect(find.byKey(FoodMealKeys.kcalSheet), findsOneWidget);
            await tester.ensureVisible(find.byKey(FoodMealKeys.kcalClose));
            await tester.pumpAndSettle();
            await tester.tap(find.byKey(FoodMealKeys.kcalClose));
            await tester.pumpAndSettle();
            expect(find.byKey(FoodMealKeys.kcalSheet), findsNothing);

            await _scrollAndTap(tester, FoodMealKeys.deleteTile);
            expect(find.byKey(FoodMealKeys.deleteSheet), findsOneWidget);
            await tester.ensureVisible(find.byKey(FoodMealKeys.deleteConfirm));
            await tester.pumpAndSettle();
            await tester.ensureVisible(find.byKey(FoodMealKeys.deleteCancel));
            await tester.pumpAndSettle();
            await tester.tap(find.byKey(FoodMealKeys.deleteCancel));
            await tester.pumpAndSettle();
            expect(find.byKey(FoodMealKeys.deleteSheet), findsNothing);
          });
        },
      );
    }
  });
}

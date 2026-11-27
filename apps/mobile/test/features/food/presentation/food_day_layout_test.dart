import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/features/food/domain/meal.dart';
import 'package:open_ring/features/food/domain/meal_camera.dart';
import 'package:open_ring/features/food/domain/photo_store.dart';
import 'package:open_ring/features/food/presentation/food_day_screen.dart';
import 'package:open_ring/features/food/presentation/meal_saved_sheet.dart';

import '../../../helpers/layout_harness.dart';
import '../food_fakes.dart';
import '../jpeg_fixture.dart';

final _now = DateTime(2026, 11, 17, 23, 45);

Future<(TestMealStore, PhotoStore)> _sixMealsWithEveryTag() async {
  final meals = TestMealStore();
  final photos = InMemoryPhotoStore();
  await photos.save('present.jpg', strippedPlain());

  final m1 = meals.seed(
    DateTime(2026, 11, 17, 7, 30),
    kind: MealKind.main,
    tags: const MealTags(
      protein: true,
      caffeine: true,
      heavy: true,
      fried: true,
      sugar: true,
      veg: MealVeg.halfOrMore,
      alcohol: MealAlcohol.threeOrMore,
      processed: MealProcessed.mostly,
      place: MealPlace.restaurant,
    ),
  );
  await meals.attachPhoto(m1.id, 'present.jpg');

  meals
    ..seed(
      DateTime(2026, 11, 17, 10, 15),
      kind: MealKind.drink,
      tags: const MealTags(caffeine: true, sugar: true),
    )
    ..seed(
      DateTime(2026, 11, 17, 12, 30),
      kind: MealKind.main,
      tags: const MealTags(
        protein: true,
        veg: MealVeg.some,
        processed: MealProcessed.unsure,
        place: MealPlace.home,
      ),
    )
    ..seed(
      DateTime(2026, 11, 17, 16),
      kind: MealKind.snack,
      tags: const MealTags(fried: true, sugar: true, place: MealPlace.packaged),
    );

  final m5 = meals.seed(
    DateTime(2026, 11, 17, 19, 45),
    kind: MealKind.main,
    tags: const MealTags(
      heavy: true,
      alcohol: MealAlcohol.oneToTwo,
      place: MealPlace.restaurant,
    ),
  );
  await meals.attachPhoto(m5.id, 'missing.jpg');

  meals.seed(DateTime(2026, 11, 17, 23, 15), last: true);
  return (meals, photos);
}

Future<void> _pumpDay(
  WidgetTester tester,
  LayoutCase c, {
  required TestMealStore meals,
  PhotoStore? photos,
}) => pumpScaled(
  tester,
  screenHost(const FoodDayScreen()),
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

void main() {
  group('criterion 9 & review focus 1: layout matrix', () {
    for (final c in layoutMatrix()) {
      testWidgets('FoodDayScreen with 6 meals carrying every tag fits at $c', (
        tester,
      ) async {
        final (meals, photos) = await _sixMealsWithEveryTag();

        await _pumpDay(tester, c, meals: meals, photos: photos);

        expect(find.byKey(FoodDayKeys.window), findsOneWidget);
        await expectNoLayoutOverflow(() async {
          for (final meal in meals.rows) {
            await tester.scrollUntilVisible(
              find.byKey(FoodDayKeys.meal(meal.id)),
              120,
              scrollable: find.byType(Scrollable).first,
            );
            await tester.pumpAndSettle();
          }
        });
      });

      testWidgets('FoodDayScreen empty day state fits at $c', (tester) async {
        await _pumpDay(tester, c, meals: TestMealStore());

        expect(find.byKey(FoodDayKeys.empty), findsOneWidget);
      });

      testWidgets('MealSavedSheet.edit fits at $c', (tester) async {
        final meals = TestMealStore();
        final meal = meals.seed(
          DateTime(2026, 11, 17, 12, 30),
          kind: MealKind.main,
          tags: const MealTags(
            protein: true,
            veg: MealVeg.halfOrMore,
            place: MealPlace.restaurant,
          ),
        );
        final edit = ValueNotifier(MealEdit.of(meal));
        addTearDown(edit.dispose);
        await pumpScaled(
          tester,
          screenHost(
            Scaffold(
              body: MealSavedSheet.edit(
                meal: meal,
                today: foodDay(_now),
                edit: edit,
              ),
            ),
          ),
          textScaler: c.textScaler,
          brightness: c.brightness,
          locale: c.locale,
        );

        await expectNoLayoutOverflow(() async {
          final sheetScrollable = find
              .descendant(
                of: find.byType(MealSavedSheet),
                matching: find.byType(Scrollable),
              )
              .first;
          await tester.scrollUntilVisible(
            find.byKey(MealSavedSheetKeys.done),
            120,
            scrollable: sheetScrollable,
          );
          await tester.pumpAndSettle();
        });

        expect(find.byType(MealSavedSheet), findsOneWidget);
      });
    }
  });
}

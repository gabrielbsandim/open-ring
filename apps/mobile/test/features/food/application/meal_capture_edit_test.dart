import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/core/records/data_revision.dart';
import 'package:open_ring/features/food/application/meal_capture.dart';
import 'package:open_ring/features/food/application/meal_photo_saver.dart';
import 'package:open_ring/features/food/application/meal_recovery.dart';
import 'package:open_ring/features/food/domain/meal.dart';
import 'package:open_ring/features/food/domain/meal_camera.dart';
import 'package:open_ring/features/food/domain/photo_store.dart';

import '../food_fakes.dart';

void main() {
  final lunch = DateTime(2026, 11, 17, 12, 30);
  late TestMealStore meals;

  setUp(() => meals = TestMealStore());

  ProviderContainer containerWith(MealCamera camera, {PhotoStore? photos}) {
    final container = ProviderContainer(
      overrides: foodOverrides(
        meals: meals,
        photos: photos ?? InMemoryPhotoStore(),
        camera: camera,
        clock: () => lunch,
      ),
    );
    addTearDown(container.dispose);
    container
      ..listen(mealCaptureProvider, (_, _) {})
      ..listen(mealRecoveryProvider, (_, _) {});
    return container;
  }

  MealCapture captureOf(ProviderContainer container) =>
      container.read(mealCaptureProvider.notifier);

  int revisionOf(ProviderContainer container) =>
      container.read(dataRevisionProvider);

  Future<(ProviderContainer, Meal)> saved() async {
    final container = containerWith(FakeMealCamera(photo: returnedPhoto));
    await captureOf(container).capture();
    return (container, container.read(mealCaptureProvider).result!.meal!);
  }

  group('criterion 2: finish with kind and tags', () {
    test('drink, sugar, veg halfOrMore and last: one update, revision +1, '
        'and the row keeps its at, offset and photo', () async {
      final (container, meal) = await saved();
      final before = revisionOf(container);
      final row = meals.rows.single;

      await captureOf(container).finish(
        MealEdit.of(meal)
            .withKind(MealKind.drink)
            .withFlag(MealFlag.sugar, true)
            .withVeg(MealVeg.halfOrMore)
            .withLast(true),
      );

      final after = meals.rows.single;
      expect(meals.updates, 1);
      expect(revisionOf(container), before + 1);
      expect(after.id, row.id);
      expect(after.kind, MealKind.drink);
      expect(after.tags.sugar, isTrue);
      expect(after.tags.veg, MealVeg.halfOrMore);
      expect(after.tags.protein, isFalse);
      expect(after.tags.alcohol, isNull);
      expect(after.last, isTrue);
      expect(after.at, row.at);
      expect(after.at, lunch.toUtc());
      expect(after.offsetMinutes, row.offsetMinutes);
      expect(after.photo, row.photo);
      expect(after.photo, isNotNull);
      expect(after.createdAt, row.createdAt);
    });

    test('settles the capture state after writing', () async {
      final (container, meal) = await saved();

      await captureOf(container)
          .finish(MealEdit.of(meal).withKind(MealKind.main));

      expect(container.read(mealCaptureProvider).result, isNull);
      expect(container.read(mealCaptureProvider).saving, isFalse);
    });

    test('each nullable tag and each flag reaches the row', () async {
      final (container, meal) = await saved();

      await captureOf(container).finish(
        MealEdit.of(meal)
            .withKind(MealKind.snack)
            .withFlag(MealFlag.protein, true)
            .withFlag(MealFlag.caffeine, true)
            .withFlag(MealFlag.heavy, true)
            .withFlag(MealFlag.fried, true)
            .withAlcohol(MealAlcohol.threeOrMore)
            .withProcessed(MealProcessed.mostly)
            .withPlace(MealPlace.packaged),
      );

      final tags = meals.rows.single.tags;
      expect(meals.updates, 1);
      expect(meals.rows.single.kind, MealKind.snack);
      expect(
        (tags.protein, tags.caffeine, tags.heavy, tags.fried, tags.sugar),
        (true, true, true, true, false),
      );
      expect(tags.alcohol, MealAlcohol.threeOrMore);
      expect(tags.processed, MealProcessed.mostly);
      expect(tags.place, MealPlace.packaged);
      expect(meals.rows.single.last, isFalse);
    });
  });

  group('criterion 3: finish with nothing to write', () {
    test('finish() writes nothing and does not bump', () async {
      final (container, _) = await saved();
      final before = revisionOf(container);

      await captureOf(container).finish();

      expect(meals.updates, 0);
      expect(revisionOf(container), before);
      expect(container.read(mealCaptureProvider).result, isNull);
    });

    test('finish(MealEdit.of(m)) writes nothing and does not bump', () async {
      final (container, meal) = await saved();
      final before = revisionOf(container);

      await captureOf(container).finish(MealEdit.of(meal));

      expect(meals.updates, 0);
      expect(revisionOf(container), before);
      expect(container.read(mealCaptureProvider).result, isNull);
    });

    test('an edit set and then set back writes nothing', () async {
      final (container, meal) = await saved();
      final before = revisionOf(container);

      await captureOf(container).finish(
        MealEdit.of(meal)
            .withKind(MealKind.snack)
            .withKind(null)
            .withFlag(MealFlag.protein, true)
            .withFlag(MealFlag.protein, false)
            .withVeg(MealVeg.some)
            .withVeg(null),
      );

      expect(meals.updates, 0);
      expect(revisionOf(container), before);
    });

    test('an edit with no result held writes nothing', () async {
      final container = containerWith(FakeMealCamera());
      await captureOf(container).capture();
      final stray = meals.seed(lunch);

      await captureOf(container)
          .finish(MealEdit.of(stray).withKind(MealKind.main));

      expect(meals.updates, 0);
      expect(meals.rows.single.kind, isNull);
      expect(revisionOf(container), 0);
    });
  });

  group('review focus: a failed update', () {
    test('a throwing update is swallowed, does not bump and settles', () async {
      final (container, meal) = await saved();
      final before = revisionOf(container);
      meals.updateError = Exception('disk I/O error');

      await captureOf(container)
          .finish(MealEdit.of(meal).withKind(MealKind.main));

      expect(meals.updates, 1);
      expect(revisionOf(container), before);
      expect(meals.rows.single.kind, isNull);
      expect(container.read(mealCaptureProvider).result, isNull);
    });

    test('an update that finds no row does not bump', () async {
      final (container, meal) = await saved();
      await meals.delete(meal.id);
      final before = revisionOf(container);

      await captureOf(container).finish(MealEdit.of(meal).withLast(true));

      expect(meals.updates, 1);
      expect(revisionOf(container), before);
      expect(container.read(mealCaptureProvider).result, isNull);
    });
  });

  group('review focus: a retry that attached a photo, then the edit', () {
    test('the edit lands on the row and keeps the attached photo', () async {
      final full = FullPhotoStore();
      final container = containerWith(
        FakeMealCamera(photo: returnedPhoto),
        photos: full,
      );
      await captureOf(container).capture();
      full.full = false;
      await captureOf(container).retry();
      final state = container.read(mealCaptureProvider);
      expect(state.result?.outcome, SaveOutcome.saved);
      final photo = meals.rows.single.photo;
      expect(photo, isNotNull);
      final before = revisionOf(container);

      await captureOf(container).finish(
        MealEdit.of(state.result!.meal!)
            .withKind(MealKind.main)
            .withPlace(MealPlace.home),
      );

      final row = meals.rows.single;
      expect(meals.updates, 1);
      expect(revisionOf(container), before + 1);
      expect(row.kind, MealKind.main);
      expect(row.tags.place, MealPlace.home);
      expect(row.photo, photo);
      expect(await full.inner.read(photo!), isNotNull);
    });
  });

  group('review focus: a plain drink marked last', () {
    test('writes kind drink and last in one update', () async {
      final (container, meal) = await saved();
      final before = revisionOf(container);

      await captureOf(container)
          .finish(MealEdit.of(meal).withKind(MealKind.drink).withLast(true));

      final row = meals.rows.single;
      expect(meals.updates, 1);
      expect(revisionOf(container), before + 1);
      expect(row.kind, MealKind.drink);
      expect(row.last, isTrue);
      expect(row.tags.isEmpty, isTrue);
    });
  });
}

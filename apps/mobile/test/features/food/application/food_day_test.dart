import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/core/records/data_revision.dart';
import 'package:open_ring/features/food/application/food_day.dart';
import 'package:open_ring/features/food/domain/meal.dart';
import 'package:open_ring/features/food/domain/meal_camera.dart';
import 'package:open_ring/features/food/domain/photo_store.dart';

import '../food_fakes.dart';
import '../jpeg_fixture.dart';

const _day = LocalDate(2026, 11, 17);

// Offset 0 makes the capture instant and its wall clock the same value.
Meal _meal(
  int id,
  int hour,
  int minute, {
  int day = 17,
  MealKind? kind,
  MealTags tags = const MealTags(),
  bool last = false,
}) => Meal(
  id: id,
  at: DateTime.utc(2026, 11, day, hour, minute),
  offsetMinutes: 0,
  createdAt: DateTime.utc(2026, 11, day, hour, minute),
  kind: kind,
  tags: tags,
  last: last,
);

void main() {
  group('criterion 1: dayWindow', () {
    test('coffee at 07:10, lunch at 12:30, dinner at 20:05, now at 21:00 on '
        'the same food day gives open == true, from 12:30, to 21:00', () {
      final meals = [
        _meal(1, 7, 10, kind: MealKind.drink),
        _meal(2, 12, 30, kind: MealKind.main),
        _meal(3, 20, 5, kind: MealKind.main),
      ];

      final window = dayWindow(
        meals,
        day: _day,
        now: DateTime.utc(2026, 11, 17, 21),
      );

      expect(window, isNotNull);
      expect(window!.open, isTrue);
      expect(window.from, DateTime.utc(2026, 11, 17, 12, 30));
      expect(window.to, DateTime.utc(2026, 11, 17, 21));
    });

    test('dinner marked last: true gives open == false, from 12:30, '
        'to 20:05', () {
      final meals = [
        _meal(1, 7, 10, kind: MealKind.drink),
        _meal(2, 12, 30, kind: MealKind.main),
        _meal(3, 20, 5, kind: MealKind.main, last: true),
      ];

      final window = dayWindow(
        meals,
        day: _day,
        now: DateTime.utc(2026, 11, 17, 21),
      );

      expect(window, isNotNull);
      expect(window!.open, isFalse);
      expect(window.from, DateTime.utc(2026, 11, 17, 12, 30));
      expect(window.to, DateTime.utc(2026, 11, 17, 20, 5));
    });

    test('plain drinks only gives null', () {
      final meals = [
        _meal(1, 7, 10, kind: MealKind.drink),
        _meal(2, 15, 0, kind: MealKind.drink, last: true),
      ];

      expect(
        dayWindow(meals, day: _day, now: DateTime.utc(2026, 11, 17, 21)),
        isNull,
      );
      expect(
        dayWindow(
          const <Meal>[],
          day: _day,
          now: DateTime.utc(2026, 11, 17, 21),
        ),
        isNull,
      );
    });

    test('a 00:30 meal belongs to the food day of the evening before', () {
      final lunch = _meal(1, 12, 30, kind: MealKind.main);
      final lateSnack = _meal(2, 0, 30, day: 18, kind: MealKind.snack);

      expect(foodDay(lateSnack.entry.at), _day);

      final openAtOneAm = dayWindow(
        [lunch, lateSnack],
        day: _day,
        now: DateTime.utc(2026, 11, 18, 1),
      );
      expect(openAtOneAm, isNotNull);
      expect(openAtOneAm!.open, isTrue);
      expect(openAtOneAm.from, DateTime.utc(2026, 11, 17, 12, 30));
      expect(openAtOneAm.to, DateTime.utc(2026, 11, 18, 1));

      final closedByLateSnack = dayWindow(
        [lunch, _meal(2, 0, 30, day: 18, kind: MealKind.snack, last: true)],
        day: _day,
        now: DateTime.utc(2026, 11, 18, 1),
      );
      expect(closedByLateSnack, isNotNull);
      expect(closedByLateSnack!.open, isFalse);
      expect(closedByLateSnack.from, DateTime.utc(2026, 11, 17, 12, 30));
      expect(closedByLateSnack.to, DateTime.utc(2026, 11, 18, 0, 30));
    });

    test('a past day without last: true closes the window at the last opening '
        'meal', () {
      final meals = [
        _meal(1, 12, 30, day: 16, kind: MealKind.main),
        _meal(2, 20, 5, day: 16, kind: MealKind.main),
      ];

      final window = dayWindow(
        meals,
        day: const LocalDate(2026, 11, 16),
        now: DateTime.utc(2026, 11, 17, 10),
      );

      expect(window, isNotNull);
      expect(window!.open, isFalse);
      expect(window.from, DateTime.utc(2026, 11, 16, 12, 30));
      expect(window.to, DateTime.utc(2026, 11, 16, 20, 5));
    });

    test('DayWindow const constructor holds from, to and open', () {
      final from = DateTime.utc(2026, 11, 17, 12, 30);
      final to = DateTime.utc(2026, 11, 17, 20, 5);
      final window = DayWindow(from: from, to: to, open: false);

      expect(window.from, from);
      expect(window.to, to);
      expect(window.open, isFalse);
    });
  });

  group('review focus 3 & D5: foodDayMealsProvider and 04:59 vs 05:00', () {
    late TestMealStore meals;

    setUp(() => meals = TestMealStore());

    ProviderContainer container() {
      final c = ProviderContainer(
        overrides: foodOverrides(
          meals: meals,
          camera: FakeMealCamera(),
          clock: () => DateTime(2026, 11, 17, 12),
        ),
      );
      addTearDown(c.dispose);
      return c;
    }

    test('04:59 belongs to the previous food day and 05:00 to the new food '
        'day', () async {
      final beforeFive = meals.seed(
        DateTime(2026, 11, 17, 4, 59),
        kind: MealKind.snack,
      );
      final atFive = meals.seed(DateTime(2026, 11, 17, 5), kind: MealKind.main);
      final afterMidnight = meals.seed(
        DateTime(2026, 11, 18, 0, 30),
        kind: MealKind.snack,
      );
      final c = container();

      final previousDay = await c.read(
        foodDayMealsProvider(const LocalDate(2026, 11, 16)).future,
      );
      final currentDay = await c.read(foodDayMealsProvider(_day).future);

      expect([for (final m in previousDay) m.id], [beforeFive.id]);
      expect([for (final m in currentDay) m.id], [atFive.id, afterMidnight.id]);
    });

    test('reloads when dataRevisionProvider bumps', () async {
      final c = container()..listen(foodDayMealsProvider(_day), (_, _) {});
      expect(await c.read(foodDayMealsProvider(_day).future), isEmpty);

      meals.seed(DateTime(2026, 11, 17, 12, 30), kind: MealKind.main);
      c.read(dataRevisionProvider.notifier).bump();

      expect(await c.read(foodDayMealsProvider(_day).future), hasLength(1));
    });
  });

  group('D3: mealPhotoProvider', () {
    test('reads bytes from PhotoStore and returns null when missing', () async {
      final photos = InMemoryPhotoStore();
      final bytes = strippedPlain();
      await photos.save('meal_1.jpg', bytes);
      final c = ProviderContainer(
        overrides: foodOverrides(
          meals: TestMealStore(),
          camera: FakeMealCamera(),
          photos: photos,
          clock: () => DateTime(2026, 11, 17, 12),
        ),
      );
      addTearDown(c.dispose);

      expect(await c.read(mealPhotoProvider('meal_1.jpg').future), bytes);
      expect(await c.read(mealPhotoProvider('missing.jpg').future), isNull);
    });
  });

  group('D4 & D5: MealEditor.save', () {
    late TestMealStore meals;
    late ProviderContainer c;

    setUp(() {
      meals = TestMealStore();
      c = ProviderContainer(
        overrides: foodOverrides(
          meals: meals,
          camera: FakeMealCamera(),
          clock: () => DateTime(2026, 11, 17, 12, 30),
        ),
      );
      addTearDown(c.dispose);
    });

    test('saves a changed edit on a photoless meal in 1 update and bumps '
        'revision by 1', () async {
      final meal = meals.seed(DateTime(2026, 11, 17, 12, 30));
      final before = c.read(dataRevisionProvider);

      final saved = await c
          .read(mealEditorProvider)
          .save(
            meal,
            MealEdit.of(meal)
                .withKind(MealKind.main)
                .withFlag(MealFlag.protein, true)
                .withLast(true),
          );

      expect(saved, isTrue);
      expect(meals.updates, 1);
      expect(c.read(dataRevisionProvider), before + 1);
      final updated = meals.rows.single;
      expect(updated.kind, MealKind.main);
      expect(updated.tags.protein, isTrue);
      expect(updated.last, isTrue);
      expect(updated.photo, isNull);
    });

    test('preserves the photo of a meal with a photo', () async {
      final meal = await meals.add(
        MealDraft(at: DateTime.utc(2026, 11, 17, 12, 30), offsetMinutes: 0),
        now: DateTime.utc(2026, 11, 17, 12, 30),
        photo: 'meal_1.jpg',
      );

      final saved = await c
          .read(mealEditorProvider)
          .save(meal, MealEdit.of(meal).withKind(MealKind.snack));

      expect(saved, isTrue);
      expect(meals.updates, 1);
      expect(meals.rows.single.photo, 'meal_1.jpg');
      expect(meals.rows.single.kind, MealKind.snack);
    });

    test('unchanged edit performs 0 updates and 0 revision bumps', () async {
      final meal = meals.seed(
        DateTime(2026, 11, 17, 12, 30),
        kind: MealKind.main,
        tags: const MealTags(protein: true),
      );
      final before = c.read(dataRevisionProvider);

      final saved = await c
          .read(mealEditorProvider)
          .save(meal, MealEdit.of(meal));

      expect(saved, isTrue);
      expect(meals.updates, 0);
      expect(c.read(dataRevisionProvider), before);
    });

    test('returns false and does not bump when update throws or returns '
        'false', () async {
      final meal = meals.seed(DateTime(2026, 11, 17, 12, 30));
      final before = c.read(dataRevisionProvider);
      meals.updateError = Exception('disk I/O error');

      final onThrow = await c
          .read(mealEditorProvider)
          .save(meal, MealEdit.of(meal).withKind(MealKind.main));

      expect(onThrow, isFalse);
      expect(meals.updates, 1);
      expect(c.read(dataRevisionProvider), before);

      meals.updateError = null;
      await meals.delete(meal.id);

      final onMissing = await c
          .read(mealEditorProvider)
          .save(meal, MealEdit.of(meal).withKind(MealKind.main));

      expect(onMissing, isFalse);
      expect(meals.updates, 2);
      expect(c.read(dataRevisionProvider), before);
    });
  });
}

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/core/records/data_revision.dart';
import 'package:open_ring/features/food/application/food_gate.dart';
import 'package:open_ring/features/food/application/today_meals.dart';
import 'package:open_ring/features/food/domain/meal.dart';
import 'package:open_ring/features/food/domain/meal_camera.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/modules/domain/module_store.dart';

import '../food_fakes.dart';

// Offset 0 makes the capture instant and its wall clock the same value.
Meal _meal(int id, int hour, int minute, {MealKind? kind, MealTags? tags}) =>
    Meal(
      id: id,
      at: DateTime.utc(2026, 11, 17, hour, minute),
      offsetMinutes: 0,
      createdAt: DateTime.utc(2026, 11, 17, hour, minute),
      kind: kind,
      tags: tags ?? const MealTags(),
    );

void main() {
  group('criterion 2: foodToday', () {
    test('plain coffee 07:10 plus lunch 12:30 is 2 with the window from '
        '12:30', () {
      final today = foodToday([
        _meal(1, 7, 10, kind: MealKind.drink),
        _meal(2, 12, 30, kind: MealKind.main),
      ]);

      expect(today.count, 2);
      expect(today.windowFrom, DateTime.utc(2026, 11, 17, 12, 30));
    });

    test('no meals is 0 with no window', () {
      final today = foodToday(const <Meal>[]);

      expect(today.count, 0);
      expect(today.windowFrom, isNull);
    });

    test('only plain drinks count but open no window', () {
      final today = foodToday([
        _meal(1, 7, 10, kind: MealKind.drink),
        _meal(2, 15, 0, kind: MealKind.drink),
      ]);

      expect(today.count, 2);
      expect(today.windowFrom, isNull);
    });

    test('a sugary drink opens the window', () {
      final today = foodToday([
        _meal(
          1,
          7,
          10,
          kind: MealKind.drink,
          tags: const MealTags(sugar: true),
        ),
        _meal(2, 12, 30, kind: MealKind.main),
      ]);

      expect(today.windowFrom, DateTime.utc(2026, 11, 17, 7, 10));
    });

    test('an untagged meal opens the window', () {
      final today = foodToday([_meal(1, 9, 5)]);

      expect(today.count, 1);
      expect(today.windowFrom, DateTime.utc(2026, 11, 17, 9, 5));
    });
  });

  group('criterion 2: todayMealsProvider reads the food day of now', () {
    late TestMealStore meals;
    late DateTime now;

    setUp(() {
      meals = TestMealStore()
        ..seed(DateTime(2026, 11, 17, 4, 30), kind: MealKind.main)
        ..seed(DateTime(2026, 11, 17, 20), kind: MealKind.main)
        ..seed(DateTime(2026, 11, 18, 0, 30), kind: MealKind.snack);
    });

    ProviderContainer containerAt(DateTime Function() clock) {
      final container = ProviderContainer(
        overrides: foodOverrides(
          meals: meals,
          camera: FakeMealCamera(),
          clock: clock,
        ),
      );
      addTearDown(container.dispose);
      container.listen(todayMealsProvider, (_, _) {});
      return container;
    }

    test('a 00:30 meal counts in the evening before', () async {
      now = DateTime(2026, 11, 18, 0, 45);
      final container = containerAt(() => now);

      final today = await container.read(todayMealsProvider.future);

      expect([for (final meal in today) meal.id], [2, 3]);
    });

    test('after 05:00 the 00:30 meal is no longer today', () async {
      now = DateTime(2026, 11, 18, 9);
      final container = containerAt(() => now);

      final today = await container.read(todayMealsProvider.future);

      expect(today, isEmpty);
    });

    test('a bump of dataRevision reads the store again', () async {
      now = DateTime(2026, 11, 18, 9);
      final container = containerAt(() => now);
      expect(await container.read(todayMealsProvider.future), isEmpty);

      meals.seed(DateTime(2026, 11, 18, 8, 15), kind: MealKind.main);
      container.read(dataRevisionProvider.notifier).bump();

      expect(await container.read(todayMealsProvider.future), hasLength(1));
    });
  });

  group('D2: foodEnabledProvider follows the Food module', () {
    ProviderContainer containerWith(Set<ModuleId> modules) {
      final container = ProviderContainer(
        overrides: [
          moduleStoreProvider.overrideWithValue(InMemoryModuleStore(modules)),
        ],
      );
      addTearDown(container.dispose);
      container.listen(foodEnabledProvider, (_, _) {});
      return container;
    }

    test('off while the modules are still loading', () {
      final container = containerWith(const {ModuleId.food});

      expect(container.read(foodEnabledProvider), isFalse);
    });

    test('on once Food is among the loaded modules', () async {
      final container = containerWith(const {ModuleId.food});
      await container.read(enabledModulesProvider.future);

      expect(container.read(foodEnabledProvider), isTrue);
    });

    test('off when only other modules are on', () async {
      final container = containerWith(const {ModuleId.effort});
      await container.read(enabledModulesProvider.future);

      expect(container.read(foodEnabledProvider), isFalse);
    });
  });
}

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/core/records/data_revision.dart';
import 'package:open_ring/features/food/application/food_day.dart';
import 'package:open_ring/features/food/application/meal_store_providers.dart';
import 'package:open_ring/features/food/domain/meal.dart';
import 'package:open_ring/features/food/domain/meal_camera.dart';
import 'package:open_ring/features/food/domain/meal_store.dart';
import 'package:open_ring/features/food/domain/photo_store.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/modules/domain/module_store.dart';

import '../food_fakes.dart';

const _day = LocalDate(2026, 11, 17);

final class _ThrowingAddMealStore implements MealStore {
  final TestMealStore _inner = TestMealStore();

  List<Meal> get rows => _inner.rows;

  @override
  Future<Meal> add(MealDraft draft, {required DateTime now, String? photo}) =>
      Future.error(StateError('disk write failed'));

  @override
  Future<bool> attachPhoto(int id, String name) => _inner.attachPhoto(id, name);

  @override
  Future<List<Meal>> between(LocalDate from, LocalDate to) =>
      _inner.between(from, to);

  @override
  Future<int> clear() => _inner.clear();

  @override
  Future<int> count() => _inner.count();

  @override
  Future<Meal?> byId(int id) => _inner.byId(id);

  @override
  Future<Meal?> delete(int id) => _inner.delete(id);

  @override
  Future<List<MealPhotoRef>> photoRefs() => _inner.photoRefs();

  @override
  Future<List<String>> deletePhotosBefore(DateTime cutoff) =>
      _inner.deletePhotosBefore(cutoff);

  @override
  Future<List<String>> deleteAllPhotos() => _inner.deleteAllPhotos();

  @override
  Future<bool> update(int id, MealDraft draft) => _inner.update(id, draft);
}

void main() {
  group('criterion 1: mealTimeOnFoodDay', () {
    test('12:30 and 05:00 on 2026-11-17 stay on 2026-11-17', () {
      final lunch = mealTimeOnFoodDay(_day, hour: 12, minute: 30);
      final fiveAm = mealTimeOnFoodDay(_day, hour: 5, minute: 0);

      expect(lunch, DateTime(2026, 11, 17, 12, 30));
      expect(fiveAm, DateTime(2026, 11, 17, 5));
      expect(foodDay(lunch), _day);
      expect(foodDay(fiveAm), _day);
    });

    test('00:00, 00:30 and 04:59 on 2026-11-17 map to 2026-11-18 so foodDay '
        'stays 2026-11-17', () {
      final midnight = mealTimeOnFoodDay(_day, hour: 0, minute: 0);
      final halfPastMidnight = mealTimeOnFoodDay(_day, hour: 0, minute: 30);
      final beforeFive = mealTimeOnFoodDay(_day, hour: 4, minute: 59);

      expect(midnight, DateTime(2026, 11, 18));
      expect(halfPastMidnight, DateTime(2026, 11, 18, 0, 30));
      expect(beforeFive, DateTime(2026, 11, 18, 4, 59));
      expect(foodDay(midnight), _day);
      expect(foodDay(halfPastMidnight), _day);
      expect(foodDay(beforeFive), _day);
    });
  });

  group('criterion 1: MealEditor.addWithoutPhoto', () {
    ProviderContainer containerFor(
      MealStore meals, {
      required DateTime Function() clock,
    }) {
      final c = ProviderContainer(
        overrides: [
          moduleStoreProvider.overrideWithValue(
            InMemoryModuleStore(const {ModuleId.food}),
          ),
          clockProvider.overrideWithValue(clock),
          mealStoreProvider.overrideWithValue(meals),
          photoStoreProvider.overrideWithValue(InMemoryPhotoStore()),
          mealCameraProvider.overrideWithValue(FakeMealCamera()),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('valid time writes 1 photoless meal with matching offsetMinutes, '
        'bumps revision by 1, and returns AddMealSaved', () async {
      final meals = TestMealStore();
      final now = DateTime(2026, 11, 17, 21);
      final c = containerFor(meals, clock: () => now);
      final expectedAt = mealTimeOnFoodDay(_day, hour: 12, minute: 30);
      final before = c.read(dataRevisionProvider);

      final result = await c
          .read(mealEditorProvider)
          .addWithoutPhoto(_day, hour: 12, minute: 30);

      expect(result, isA<AddMealSaved>());
      final saved = (result as AddMealSaved).meal;
      expect(meals.rows, [saved]);
      expect(saved.photo, isNull);
      expect(saved.at, expectedAt.toUtc());
      expect(saved.offsetMinutes, expectedAt.timeZoneOffset.inMinutes);
      expect(foodDay(saved.entry.at), _day);
      expect(c.read(dataRevisionProvider), before + 1);
    });

    test('boundary: exact now succeeds while 1 minute later returns '
        'AddMealFuture with 0 rows and 0 bumps', () async {
      final meals = TestMealStore();
      final now = DateTime(2026, 11, 17, 21);
      final c = containerFor(meals, clock: () => now);
      final before = c.read(dataRevisionProvider);

      final futureResult = await c
          .read(mealEditorProvider)
          .addWithoutPhoto(_day, hour: 21, minute: 1);

      expect(futureResult, isA<AddMealFuture>());
      expect(meals.rows, isEmpty);
      expect(c.read(dataRevisionProvider), before);

      final exactResult = await c
          .read(mealEditorProvider)
          .addWithoutPhoto(_day, hour: 21, minute: 0);

      expect(exactResult, isA<AddMealSaved>());
      expect(meals.rows, hasLength(1));
      expect(c.read(dataRevisionProvider), before + 1);
    });

    test('00:30 picked on 2026-11-17 when now is 2026-11-17 21:00 returns '
        'AddMealFuture, writes 0 rows, and makes 0 bumps', () async {
      final meals = TestMealStore();
      final c = containerFor(meals, clock: () => DateTime(2026, 11, 17, 21));
      final before = c.read(dataRevisionProvider);

      final result = await c
          .read(mealEditorProvider)
          .addWithoutPhoto(_day, hour: 0, minute: 30);

      expect(result, isA<AddMealFuture>());
      expect(meals.rows, isEmpty);
      expect(c.read(dataRevisionProvider), before);
    });

    test('00:30 picked on 2026-11-17 when now is 2026-11-18 01:00 succeeds '
        'with AddMealSaved', () async {
      final meals = TestMealStore();
      final c = containerFor(meals, clock: () => DateTime(2026, 11, 18, 1));
      final before = c.read(dataRevisionProvider);

      final result = await c
          .read(mealEditorProvider)
          .addWithoutPhoto(_day, hour: 0, minute: 30);

      expect(result, isA<AddMealSaved>());
      final saved = (result as AddMealSaved).meal;
      expect(meals.rows, [saved]);
      expect(saved.photo, isNull);
      expect(foodDay(saved.entry.at), _day);
      expect(c.read(dataRevisionProvider), before + 1);
    });

    test('throwing MealStore.add returns AddMealFailed, writes 0 rows, and '
        'makes 0 bumps', () async {
      final meals = _ThrowingAddMealStore();
      final c = containerFor(meals, clock: () => DateTime(2026, 11, 17, 21));
      final before = c.read(dataRevisionProvider);

      final result = await c
          .read(mealEditorProvider)
          .addWithoutPhoto(_day, hour: 12, minute: 30);

      expect(result, isA<AddMealFailed>());
      expect(meals.rows, isEmpty);
      expect(c.read(dataRevisionProvider), before);
    });
  });
}

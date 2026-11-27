import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/core/records/data_revision.dart';
import 'package:open_ring/features/food/application/food_data.dart';
import 'package:open_ring/features/food/application/meal_store_providers.dart';
import 'package:open_ring/features/food/domain/meal.dart';
import 'package:open_ring/features/food/domain/meal_store.dart';
import 'package:open_ring/features/food/domain/photo_store.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/modules/domain/module_store.dart';

import '../food_fakes.dart';

final _now = DateTime.utc(2026, 11, 21, 15);

final class _SpyOrderPhotoStore implements PhotoStore {
  new(this.meals, {this.failDeleteAll = false});

  final MealStore meals;
  final bool failDeleteAll;
  final inner = InMemoryPhotoStore();
  int? mealCountAtDeleteAll;

  @override
  Future<void> save(String name, Uint8List bytes) => inner.save(name, bytes);

  @override
  Future<Uint8List?> read(String name) => inner.read(name);

  @override
  Future<bool> delete(String name) => inner.delete(name);

  @override
  Future<int> deleteAll() async {
    mealCountAtDeleteAll = await meals.count();
    if (failDeleteAll) throw const FileSystemException('dir locked');
    return await inner.deleteAll();
  }

  @override
  Future<Map<String, int>> fileBytes() => inner.fileBytes();

  @override
  Future<int> totalBytes() => inner.totalBytes();
}

final class _FailingClearMealStore implements MealStore {
  final inner = TestMealStore();

  @override
  Future<int> clear() async =>
      throw const FileSystemException('database locked');

  @override
  Future<int> count() => inner.count();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

void main() {
  group('foodDataCountProvider and FoodDataEraser', () {
    test('counts meals, photos, and bytes even when Food is off', () async {
      final meals = TestMealStore();
      final photos = InMemoryPhotoStore();
      await photos.save('a.jpg', Uint8List(500000));
      await meals.add(
        MealDraft(at: _now, offsetMinutes: 0),
        now: _now,
        photo: 'a.jpg',
      );
      await meals.add(
        MealDraft(at: _now.add(const Duration(hours: 2)), offsetMinutes: 0),
        now: _now,
      );

      final container = ProviderContainer(
        overrides: [
          moduleStoreProvider.overrideWithValue(InMemoryModuleStore()),
          mealStoreProvider.overrideWithValue(meals),
          photoStoreProvider.overrideWithValue(photos),
        ],
      );
      addTearDown(container.dispose);
      await container.read(enabledModulesProvider.future);

      final count = await container.read(foodDataCountProvider.future);
      expect(count.meals, 2);
      expect(count.photos, 1);
      expect(count.photoBytes, 500000);
      expect(count.hasData, isTrue);
    });

    test(
      'clear removes meal rows before deleting photos and bumps revision',
      () async {
        final meals = TestMealStore();
        final photos = _SpyOrderPhotoStore(meals);
        await photos.save('a.jpg', Uint8List(4000));
        await meals.add(
          MealDraft(at: _now, offsetMinutes: 0),
          now: _now,
          photo: 'a.jpg',
        );

        final container = ProviderContainer(
          overrides: [
            moduleStoreProvider.overrideWithValue(
              InMemoryModuleStore({ModuleId.food}),
            ),
            mealStoreProvider.overrideWithValue(meals),
            photoStoreProvider.overrideWithValue(photos),
          ],
        );
        addTearDown(container.dispose);
        final revBefore = container.read(dataRevisionProvider);

        expect(await container.read(foodDataEraserProvider).clear(), isTrue);
        expect(photos.mealCountAtDeleteAll, 0);
        expect(await meals.count(), 0);
        expect(await photos.totalBytes(), 0);
        expect(container.read(dataRevisionProvider), revBefore + 1);
        expect(
          await container.read(foodDataCountProvider.future),
          const FoodDataCount(meals: 0, photos: 0, photoBytes: 0),
        );
      },
    );

    test('DB clear error returns false without touching photos or bumping revision', () async {
      final meals = _FailingClearMealStore();
      final photos = _SpyOrderPhotoStore(meals);
      await photos.save('a.jpg', Uint8List(4000));
      await meals.inner.add(
        MealDraft(at: _now, offsetMinutes: 0),
        now: _now,
        photo: 'a.jpg',
      );

      final container = ProviderContainer(
        overrides: [
          moduleStoreProvider.overrideWithValue(InMemoryModuleStore()),
          mealStoreProvider.overrideWithValue(meals),
          photoStoreProvider.overrideWithValue(photos),
        ],
      );
      addTearDown(container.dispose);
      final revBefore = container.read(dataRevisionProvider);

      expect(await container.read(foodDataEraserProvider).clear(), isFalse);
      expect(photos.mealCountAtDeleteAll, isNull);
      expect(await photos.totalBytes(), 4000);
      expect(await meals.count(), 1);
      expect(container.read(dataRevisionProvider), revBefore);
    });

    test('photo deleteAll error after DB clear still bumps revision and returns false', () async {
      final meals = TestMealStore();
      final photos = _SpyOrderPhotoStore(meals, failDeleteAll: true);
      await photos.save('orphan.jpg', Uint8List(6000));
      await meals.add(
        MealDraft(at: _now, offsetMinutes: 0),
        now: _now,
        photo: 'orphan.jpg',
      );

      final container = ProviderContainer(
        overrides: [
          moduleStoreProvider.overrideWithValue(InMemoryModuleStore()),
          mealStoreProvider.overrideWithValue(meals),
          photoStoreProvider.overrideWithValue(photos),
        ],
      );
      addTearDown(container.dispose);
      final revBefore = container.read(dataRevisionProvider);

      expect(await container.read(foodDataEraserProvider).clear(), isFalse);
      expect(await meals.count(), 0);
      expect(await photos.totalBytes(), 6000);
      expect(container.read(dataRevisionProvider), revBefore + 1);
      final count = await container.read(foodDataCountProvider.future);
      expect(count.hasData, isTrue);
    });
  });
}

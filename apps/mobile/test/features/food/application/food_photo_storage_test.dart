import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/core/records/data_revision.dart';
import 'package:open_ring/features/food/application/food_photo_storage.dart';
import 'package:open_ring/features/food/application/meal_store_providers.dart';
import 'package:open_ring/features/food/domain/meal.dart';
import 'package:open_ring/features/food/domain/meal_store.dart';
import 'package:open_ring/features/food/domain/photo_store.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/modules/domain/module_store.dart';

import '../food_fakes.dart';

final _now = DateTime.utc(2026, 11, 21, 15);

final class _PartiallyFailingDeletePhotoStore implements PhotoStore {
  new(this.failingName);

  final String failingName;
  final inner = InMemoryPhotoStore();

  @override
  Future<void> save(String name, Uint8List bytes) => inner.save(name, bytes);

  @override
  Future<Uint8List?> read(String name) => inner.read(name);

  @override
  Future<bool> delete(String name) {
    if (name == failingName) throw const FileSystemException('busy', 'locked');
    return inner.delete(name);
  }

  @override
  Future<int> deleteAll() => inner.deleteAll();

  @override
  Future<Map<String, int>> fileBytes() => inner.fileBytes();

  @override
  Future<int> totalBytes() => inner.totalBytes();
}

Future<ProviderContainer> _container({
  required TestMealStore meals,
  required PhotoStore photos,
  DateTime? now,
  bool foodOn = true,
}) async {
  final container = ProviderContainer(
    overrides: [
      moduleStoreProvider.overrideWithValue(
        InMemoryModuleStore({if (foodOn) ModuleId.food}),
      ),
      clockProvider.overrideWithValue(() => now ?? _now),
      mealStoreProvider.overrideWithValue(meals),
      photoStoreProvider.overrideWithValue(photos),
    ],
  );
  addTearDown(container.dispose);
  await container.read(enabledModulesProvider.future);
  return container;
}

void main() {
  group('Food photo storage and purger', () {
    test('acceptance: 274 photos 45.2 MB, purging >3m removes 9 (1.5 MB) and keeps 274 meals', () async {
      final meals = TestMealStore();
      final photos = InMemoryPhotoStore();
      final payload = Uint8List(165000);
      // 9 photos strictly older than 90 days, spanning ~94 days.
      for (var i = 0; i < 9; i++) {
        final name = 'old_$i.jpg';
        final at = _now.subtract(Duration(days: 94, minutes: i));
        await photos.save(name, payload);
        await meals.add(
          MealDraft(
            at: at,
            offsetMinutes: 0,
            kind: MealKind.main,
            tags: const MealTags(protein: true),
          ),
          now: at,
          photo: name,
        );
      }
      // 265 photos within the last 90 days.
      for (var i = 0; i < 265; i++) {
        final name = 'cur_$i.jpg';
        final at = _now.subtract(Duration(days: i % 89, hours: 1));
        await photos.save(name, payload);
        await meals.add(
          MealDraft(
            at: at,
            offsetMinutes: 0,
            kind: MealKind.snack,
            tags: const MealTags(caffeine: true),
          ),
          now: at,
          photo: name,
        );
      }

      final container = await _container(meals: meals, photos: photos);
      final view = await container.read(foodPhotoStorageProvider.future);

      expect(view.photoCount, 274);
      expect(view.totalBytes, 274 * 165000);
      expect(view.averageBytes, 165000);
      expect(view.earliestDay, const LocalDate(2026, 8, 19));
      expect(view.projectedBytesPerYear, isNotNull);
      expect(
        view.previews[PhotoPurgeRange.olderThanThreeMonths],
        const PhotoPurgePreview(count: 9, bytes: 9 * 165000),
      );
      expect(
        view.previews[PhotoPurgeRange.olderThanOneYear],
        const PhotoPurgePreview(count: 0, bytes: 0),
      );
      expect(
        view.previews[PhotoPurgeRange.all],
        const PhotoPurgePreview(count: 274, bytes: 274 * 165000),
      );

      final result = await container
          .read(foodPhotoPurgerProvider)
          .purge(PhotoPurgeRange.olderThanThreeMonths, asOf: view.asOf);

      expect(result, isNotNull);
      expect(result!.removedPhotos, 9);
      expect(result.freedBytes, 9 * 165000);

      final updated = await container.read(foodPhotoStorageProvider.future);
      expect(updated.photoCount, 265);
      expect(updated.totalBytes, 265 * 165000);
      expect(await meals.count(), 274);
      final allMeals = await meals.between(
        const LocalDate(2020, 1, 1),
        const LocalDate(2030, 1, 1),
      );
      expect(allMeals, hasLength(274));
      for (var i = 0; i < 9; i++) {
        expect(await photos.read('old_$i.jpg'), isNull);
      }
      final purgedRows = allMeals
          .where((m) => m.kind == MealKind.main)
          .toList();
      expect(purgedRows, hasLength(9));
      for (final m in purgedRows) {
        expect(m.photo, isNull);
        expect(m.tags.protein, isTrue);
      }
    });

    test('works while Food module is off', () async {
      final meals = TestMealStore();
      final photos = InMemoryPhotoStore();
      await photos.save('a.jpg', Uint8List(5000));
      await meals.add(
        MealDraft(
          at: _now.subtract(const Duration(days: 400)),
          offsetMinutes: 0,
        ),
        now: _now,
        photo: 'a.jpg',
      );
      final container = await _container(
        meals: meals,
        photos: photos,
        foodOn: false,
      );

      final view = await container.read(foodPhotoStorageProvider.future);
      expect(view.photoCount, 1);
      expect(view.previews[PhotoPurgeRange.olderThanOneYear]?.count, 1);

      final result = await container
          .read(foodPhotoPurgerProvider)
          .purge(PhotoPurgeRange.olderThanOneYear, asOf: view.asOf);
      expect(result?.removedPhotos, 1);
      expect(result?.freedBytes, 5000);
      expect(await photos.totalBytes(), 0);
    });

    test('hides pace when span under 7 days or single photo', () async {
      final meals = TestMealStore();
      final photos = InMemoryPhotoStore();
      await photos.save('a.jpg', Uint8List(2000));
      await meals.add(
        MealDraft(at: _now.subtract(const Duration(days: 5)), offsetMinutes: 0),
        now: _now,
        photo: 'a.jpg',
      );
      await photos.save('b.jpg', Uint8List(4000));
      await meals.add(
        MealDraft(at: _now.subtract(const Duration(days: 1)), offsetMinutes: 0),
        now: _now,
        photo: 'b.jpg',
      );

      final container = await _container(meals: meals, photos: photos);
      final view = await container.read(foodPhotoStorageProvider.future);

      expect(view.averageBytes, 3000);
      expect(view.projectedBytesPerYear, isNull);
    });

    test('purge all removes both linked and orphan files', () async {
      final meals = TestMealStore();
      final photos = InMemoryPhotoStore();
      await photos.save('linked.jpg', Uint8List(4000));
      await photos.save('orphan.jpg', Uint8List(6000));
      await meals.add(
        MealDraft(at: _now.subtract(const Duration(days: 1)), offsetMinutes: 0),
        now: _now,
        photo: 'linked.jpg',
      );

      final container = await _container(meals: meals, photos: photos);
      final view = await container.read(foodPhotoStorageProvider.future);
      expect(view.photoCount, 1);
      expect(view.totalBytes, 10000);

      final result = await container
          .read(foodPhotoPurgerProvider)
          .purge(PhotoPurgeRange.all);
      expect(result?.removedPhotos, 1);
      expect(result?.freedBytes, 10000);
      expect(await photos.totalBytes(), 0);
      expect(await meals.count(), 1);
    });

    test('DB error aborts before touching files or bumping revision', () async {
      final meals = TestMealStore()
        ..deletePhotosError = const FileSystemException('db locked');
      final photos = InMemoryPhotoStore();
      await photos.save('old.jpg', Uint8List(4000));
      await meals.add(
        MealDraft(
          at: _now.subtract(const Duration(days: 120)),
          offsetMinutes: 0,
        ),
        now: _now,
        photo: 'old.jpg',
      );
      final container = await _container(meals: meals, photos: photos);
      final revBefore = container.read(dataRevisionProvider);

      final result = await container
          .read(foodPhotoPurgerProvider)
          .purge(PhotoPurgeRange.olderThanThreeMonths);

      expect(result, isNull);
      expect(await photos.read('old.jpg'), isNotNull);
      expect((await meals.photoRefs()).single.photo, 'old.jpg');
      expect(container.read(dataRevisionProvider), revBefore);
    });

    test(
      'per-file delete error still deletes remaining files and bumps revision',
      () async {
        final meals = TestMealStore();
        final photos = _PartiallyFailingDeletePhotoStore('bad.jpg');
        await photos.save('bad.jpg', Uint8List(3000));
        await photos.save('good.jpg', Uint8List(5000));
        await meals.add(
          MealDraft(
            at: _now.subtract(const Duration(days: 120)),
            offsetMinutes: 0,
          ),
          now: _now,
          photo: 'bad.jpg',
        );
        await meals.add(
          MealDraft(
            at: _now.subtract(const Duration(days: 110)),
            offsetMinutes: 0,
          ),
          now: _now,
          photo: 'good.jpg',
        );
        final container = await _container(meals: meals, photos: photos);
        final revBefore = container.read(dataRevisionProvider);

        final result = await container
            .read(foodPhotoPurgerProvider)
            .purge(PhotoPurgeRange.olderThanThreeMonths);

        expect(result?.removedPhotos, 2);
        expect(result?.freedBytes, 5000);
        expect(await photos.read('good.jpg'), isNull);
        expect(await photos.read('bad.jpg'), isNotNull);
        expect(await meals.photoRefs(), isEmpty);
        expect(container.read(dataRevisionProvider), revBefore + 1);
      },
    );

    test('missing disk files do not produce zero pace and throw during all purge reports zero freed', () async {
      final meals = TestMealStore();
      await meals.add(
        MealDraft(
          at: _now.subtract(const Duration(days: 30)),
          offsetMinutes: 0,
        ),
        now: _now,
        photo: 'ghost1.jpg',
      );
      await meals.add(
        MealDraft(at: _now.subtract(const Duration(days: 1)), offsetMinutes: 0),
        now: _now,
        photo: 'ghost2.jpg',
      );
      final emptyContainer = await _container(
        meals: meals,
        photos: InMemoryPhotoStore(),
      );
      final emptyView = await emptyContainer.read(
        foodPhotoStorageProvider.future,
      );
      expect(emptyView.photoCount, 2);
      expect(emptyView.averageBytes, isNull);
      expect(emptyView.projectedBytesPerYear, isNull);

      final throwingPhotos = _ThrowingDeleteAllPhotoStore();
      await throwingPhotos.inner.save('kept.jpg', Uint8List(5000));
      await meals.add(
        MealDraft(at: _now, offsetMinutes: 0),
        now: _now,
        photo: 'kept.jpg',
      );
      final container = await _container(meals: meals, photos: throwingPhotos);
      final result = await container
          .read(foodPhotoPurgerProvider)
          .purge(PhotoPurgeRange.all);
      expect(result?.removedPhotos, 3);
      expect(result?.freedBytes, 0);
    });

    test('oldest ref missing on disk does not leak 365-day span into pace for recent files', () {
      final oldMissing = _now.subtract(const Duration(days: 365));
      final refs = [
        MealPhotoRef(at: oldMissing, offsetMinutes: 0, photo: 'missing.jpg'),
        MealPhotoRef(at: _now, offsetMinutes: 0, photo: 'a.jpg'),
        MealPhotoRef(at: _now, offsetMinutes: 0, photo: 'b.jpg'),
      ];
      final view = buildFoodPhotoStorageView(
        now: _now,
        refs: refs,
        fileSizes: const {'a.jpg': 200000, 'b.jpg': 200000},
        totalBytes: 400000,
      );
      expect(view.photoCount, 3);
      expect(view.averageBytes, 200000);
      expect(view.earliestDay, foodDay(_now));
      expect(view.projectedBytesPerYear, isNull);
    });
  });
}

final class _ThrowingDeleteAllPhotoStore implements PhotoStore {
  final inner = InMemoryPhotoStore();

  @override
  Future<void> save(String name, Uint8List bytes) => inner.save(name, bytes);

  @override
  Future<Uint8List?> read(String name) => inner.read(name);

  @override
  Future<bool> delete(String name) => inner.delete(name);

  @override
  Future<int> deleteAll() async =>
      throw const FileSystemException('cannot empty dir');

  @override
  Future<Map<String, int>> fileBytes() => inner.fileBytes();

  @override
  Future<int> totalBytes() => inner.totalBytes();
}

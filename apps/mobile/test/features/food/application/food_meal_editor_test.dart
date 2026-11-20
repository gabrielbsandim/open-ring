import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/core/records/data_revision.dart';
import 'package:open_ring/features/food/application/food_day.dart';
import 'package:open_ring/features/food/domain/meal.dart';
import 'package:open_ring/features/food/domain/meal_camera.dart';
import 'package:open_ring/features/food/domain/meal_store.dart';
import 'package:open_ring/features/food/domain/photo_store.dart';
import 'package:open_ring/features/food/infrastructure/drift_meal_store.dart';

import '../../../helpers/database.dart';
import '../food_fakes.dart';
import '../jpeg_fixture.dart';

final _now = DateTime(2026, 11, 17, 21);

final class _SpyPhotoStore implements PhotoStore {
  final inner = InMemoryPhotoStore();
  final List<String> deleteCalls = [];
  final List<bool> rowStillPresentOnDelete = [];
  bool throwOnDelete = false;
  MealStore? mealsToCheck;
  int? idToCheck;

  @override
  Future<void> save(String name, Uint8List bytes) => inner.save(name, bytes);

  @override
  Future<Uint8List?> read(String name) => inner.read(name);

  @override
  Future<bool> delete(String name) async {
    deleteCalls.add(name);
    final store = mealsToCheck;
    final id = idToCheck;
    if (store != null && id != null) {
      rowStillPresentOnDelete.add(await store.byId(id) != null);
    }
    if (throwOnDelete) {
      throw FileSystemException('cannot delete photo', name);
    }
    return inner.delete(name);
  }

  @override
  Future<int> deleteAll() => inner.deleteAll();

  @override
  Future<int> totalBytes() => inner.totalBytes();
}

void main() {
  group('criterion 1: DriftMealStore.byId', () {
    late MealStore store;

    setUp(() => store = DriftMealStore(memoryDatabase()));

    test('returns full Meal for existing row and null when missing or deleted', () async {
      final createdAt = DateTime.utc(2026, 11, 17, 12, 30);
      final at = DateTime.utc(2026, 11, 17, 15, 30);
      final added = await store.add(
        MealDraft(
          at: at,
          offsetMinutes: -180,
          kind: MealKind.main,
          tags: const MealTags(
            protein: true,
            veg: MealVeg.halfOrMore,
            place: MealPlace.home,
          ),
          last: true,
        ),
        now: createdAt,
        photo: 'meal_1.jpg',
      );

      final found = await store.byId(added.id);
      expect(found, added);
      expect(await store.byId(added.id + 99), isNull);
      expect(await store.byId(0), isNull);
      expect(await store.byId(-1), isNull);

      await store.delete(added.id);
      expect(await store.byId(added.id), isNull);
    });
  });

  group('criterion 2: mealByIdProvider', () {
    late TestMealStore meals;
    late _SpyPhotoStore photos;

    setUp(() {
      meals = TestMealStore();
      photos = _SpyPhotoStore();
    });

    ProviderContainer container({DateTime Function()? clock}) {
      final c = ProviderContainer(
        overrides: foodOverrides(
          meals: meals,
          photos: photos,
          camera: FakeMealCamera(),
          clock: clock ?? () => _now,
        ),
      );
      addTearDown(c.dispose);
      return c;
    }

    test('returns Meal for known id, null for missing id, and reloads on '
        'dataRevisionProvider bump', () async {
      final meal = meals.seed(DateTime(2026, 11, 17, 12, 30));
      final c = container()..listen(mealByIdProvider(meal.id), (_, _) {});

      expect(await c.read(mealByIdProvider(meal.id).future), meal);
      expect(await c.read(mealByIdProvider(999).future), isNull);

      await meals.update(
        meal.id,
        MealDraft(
          at: meal.at,
          offsetMinutes: meal.offsetMinutes,
          kind: MealKind.snack,
          tags: const MealTags(sugar: true),
        ),
      );
      c.read(dataRevisionProvider.notifier).bump();

      final updated = await c.read(mealByIdProvider(meal.id).future);
      expect(updated?.kind, MealKind.snack);
      expect(updated?.tags.sugar, isTrue);

      await meals.delete(meal.id);
      c.read(dataRevisionProvider.notifier).bump();

      expect(await c.read(mealByIdProvider(meal.id).future), isNull);
    });

    test('is autoDispose and drops state when unlistened', () async {
      final meal = meals.seed(DateTime(2026, 11, 17, 12, 30));
      final c = container();
      final sub = c.listen(mealByIdProvider(meal.id), (_, _) {});

      expect(await c.read(mealByIdProvider(meal.id).future), meal);
      expect(c.exists(mealByIdProvider(meal.id)), isTrue);

      sub.close();
      await c.pump();

      expect(c.exists(mealByIdProvider(meal.id)), isFalse);
    });
  });

  group('criterion 2: MealEditor.setTime and EditTimeResult', () {
    late TestMealStore meals;
    late _SpyPhotoStore photos;

    setUp(() {
      meals = TestMealStore();
      photos = _SpyPhotoStore();
    });

    ProviderContainer container({DateTime Function()? clock}) {
      final c = ProviderContainer(
        overrides: foodOverrides(
          meals: meals,
          photos: photos,
          camera: FakeMealCamera(),
          clock: clock ?? () => _now,
        ),
      );
      addTearDown(c.dispose);
      return c;
    }

    String describeResult(EditTimeResult r) => switch (r) {
      EditTimeSaved() => 'saved',
      EditTimeFuture() => 'future',
      EditTimeFailed() => 'failed',
    };

    test('EditTimeResult is sealed with Saved, Future, Failed const '
        'subclasses', () {
      const results = <EditTimeResult>[
        EditTimeSaved(),
        EditTimeFuture(),
        EditTimeFailed(),
      ];
      expect([for (final r in results) describeResult(r)], [
        'saved',
        'future',
        'failed',
      ]);
    });

    test('valid time updates at and offsetMinutes, preserves kind/tags/last/'
        'photo, bumps revision once, and returns EditTimeSaved', () async {
      final meal = await meals.add(
        MealDraft(
          at: DateTime(2026, 11, 17, 12, 30).toUtc(),
          offsetMinutes: localOffset(DateTime(2026, 11, 17, 12, 30)),
          kind: MealKind.main,
          tags: const MealTags(protein: true, veg: MealVeg.some),
          last: true,
        ),
        now: _now.toUtc(),
        photo: 'meal_1.jpg',
      );
      final c = container();
      final before = c.read(dataRevisionProvider);
      final expectedLocal = mealTimeOnFoodDay(
        foodDay(meal.entry.at),
        hour: 14,
        minute: 15,
      );

      final result = await c
          .read(mealEditorProvider)
          .setTime(meal, hour: 14, minute: 15);

      expect(result, isA<EditTimeSaved>());
      expect(meals.updates, 1);
      expect(c.read(dataRevisionProvider), before + 1);
      final updated = meals.rows.single;
      expect(updated.at, expectedLocal.toUtc());
      expect(updated.offsetMinutes, expectedLocal.timeZoneOffset.inMinutes);
      expect(updated.kind, MealKind.main);
      expect(updated.tags.protein, isTrue);
      expect(updated.tags.veg, MealVeg.some);
      expect(updated.last, isTrue);
      expect(updated.photo, 'meal_1.jpg');
    });

    test('unchanged hour and minute returns EditTimeSaved with 0 updates and '
        '0 revision bumps', () async {
      final meal = meals.seed(DateTime(2026, 11, 17, 12, 30));
      final c = container(clock: () => DateTime(2026, 11, 17, 10));
      final before = c.read(dataRevisionProvider);

      final result = await c
          .read(mealEditorProvider)
          .setTime(meal, hour: 12, minute: 30);

      expect(result, isA<EditTimeSaved>());
      expect(meals.updates, 0);
      expect(c.read(dataRevisionProvider), before);
    });

    test('boundary: exact now succeeds while 1 minute after now returns '
        'EditTimeFuture with 0 updates and 0 bumps', () async {
      final meal = meals.seed(DateTime(2026, 11, 17, 12, 30));
      final c = container();
      final before = c.read(dataRevisionProvider);

      final futureResult = await c
          .read(mealEditorProvider)
          .setTime(meal, hour: 21, minute: 1);

      expect(futureResult, isA<EditTimeFuture>());
      expect(meals.updates, 0);
      expect(c.read(dataRevisionProvider), before);

      final exactResult = await c
          .read(mealEditorProvider)
          .setTime(meal, hour: 21, minute: 0);

      expect(exactResult, isA<EditTimeSaved>());
      expect(meals.updates, 1);
      expect(c.read(dataRevisionProvider), before + 1);
    });

    test('00:30 maps to the following morning of foodDay: EditTimeFuture at '
        '21:00 same evening, EditTimeSaved at 01:00 next morning', () async {
      final meal = meals.seed(DateTime(2026, 11, 17, 19, 30));
      final c1 = container(clock: () => DateTime(2026, 11, 17, 21));
      final before1 = c1.read(dataRevisionProvider);

      final futureResult = await c1
          .read(mealEditorProvider)
          .setTime(meal, hour: 0, minute: 30);

      expect(futureResult, isA<EditTimeFuture>());
      expect(meals.updates, 0);
      expect(c1.read(dataRevisionProvider), before1);

      final c2 = container(clock: () => DateTime(2026, 11, 18, 1));
      final before2 = c2.read(dataRevisionProvider);

      final savedResult = await c2
          .read(mealEditorProvider)
          .setTime(meal, hour: 0, minute: 30);

      expect(savedResult, isA<EditTimeSaved>());
      expect(meals.updates, 1);
      expect(c2.read(dataRevisionProvider), before2 + 1);
      expect(foodDay(meals.rows.single.entry.at), const LocalDate(2026, 11, 17));
      expect(meals.rows.single.entry.at, DateTime.utc(2026, 11, 18, 0, 30));
    });

    test('error path: MealStore.update returning false or throwing returns '
        'EditTimeFailed with 0 bumps', () async {
      final meal = meals.seed(DateTime(2026, 11, 17, 12, 30));
      final c = container();
      final before = c.read(dataRevisionProvider);

      meals.updateError = Exception('disk I/O error');
      final onThrow = await c
          .read(mealEditorProvider)
          .setTime(meal, hour: 13, minute: 0);

      expect(onThrow, isA<EditTimeFailed>());
      expect(meals.updates, 1);
      expect(c.read(dataRevisionProvider), before);

      meals.updateError = null;
      await meals.delete(meal.id);

      final onMissing = await c
          .read(mealEditorProvider)
          .setTime(meal, hour: 13, minute: 0);

      expect(onMissing, isA<EditTimeFailed>());
      expect(meals.updates, 2);
      expect(c.read(dataRevisionProvider), before);
    });
  });

  group('criterion 2: MealEditor.delete', () {
    late TestMealStore meals;
    late _SpyPhotoStore photos;

    setUp(() {
      meals = TestMealStore();
      photos = _SpyPhotoStore();
    });

    ProviderContainer container() {
      final c = ProviderContainer(
        overrides: foodOverrides(
          meals: meals,
          photos: photos,
          camera: FakeMealCamera(),
          clock: () => _now,
        ),
      );
      addTearDown(c.dispose);
      return c;
    }

    test('deletes row first, then photo file, bumps revision once, and '
        'returns true', () async {
      await photos.save('meal_1.jpg', strippedPlain());
      final meal = await meals.add(
        MealDraft(at: _now.toUtc(), offsetMinutes: 0),
        now: _now.toUtc(),
        photo: 'meal_1.jpg',
      );
      photos
        ..mealsToCheck = meals
        ..idToCheck = meal.id;
      final c = container();
      final before = c.read(dataRevisionProvider);

      final ok = await c.read(mealEditorProvider).delete(meal.id);

      expect(ok, isTrue);
      expect(meals.deletes, 1);
      expect(meals.rows, isEmpty);
      expect(photos.deleteCalls, ['meal_1.jpg']);
      expect(photos.rowStillPresentOnDelete, [false]);
      expect(await photos.read('meal_1.jpg'), isNull);
      expect(c.read(dataRevisionProvider), before + 1);
    });

    test('photoless meal deletes row without touching PhotoStore and bumps '
        'revision once', () async {
      final meal = meals.seed(DateTime(2026, 11, 17, 12, 30));
      final c = container();
      final before = c.read(dataRevisionProvider);

      final ok = await c.read(mealEditorProvider).delete(meal.id);

      expect(ok, isTrue);
      expect(meals.deletes, 1);
      expect(meals.rows, isEmpty);
      expect(photos.deleteCalls, isEmpty);
      expect(c.read(dataRevisionProvider), before + 1);
    });

    test('boundary: missing photo file (PhotoStore.delete returns false) still '
        'succeeds and bumps revision once', () async {
      final meal = await meals.add(
        MealDraft(at: _now.toUtc(), offsetMinutes: 0),
        now: _now.toUtc(),
        photo: 'missing.jpg',
      );
      final c = container();
      final before = c.read(dataRevisionProvider);

      final ok = await c.read(mealEditorProvider).delete(meal.id);

      expect(ok, isTrue);
      expect(meals.rows, isEmpty);
      expect(photos.deleteCalls, ['missing.jpg']);
      expect(c.read(dataRevisionProvider), before + 1);
    });

    test('error path: throwing PhotoStore.delete still succeeds and bumps '
        'revision once because row is already deleted', () async {
      await photos.save('meal_1.jpg', strippedPlain());
      final meal = await meals.add(
        MealDraft(at: _now.toUtc(), offsetMinutes: 0),
        now: _now.toUtc(),
        photo: 'meal_1.jpg',
      );
      photos.throwOnDelete = true;
      final c = container();
      final before = c.read(dataRevisionProvider);

      final ok = await c.read(mealEditorProvider).delete(meal.id);

      expect(ok, isTrue);
      expect(meals.rows, isEmpty);
      expect(photos.deleteCalls, ['meal_1.jpg']);
      expect(c.read(dataRevisionProvider), before + 1);
    });

    test('error path: unknown id or throwing MealStore.delete returns false '
        'with 0 photo deletes and 0 bumps', () async {
      await photos.save('meal_1.jpg', strippedPlain());
      final meal = await meals.add(
        MealDraft(at: _now.toUtc(), offsetMinutes: 0),
        now: _now.toUtc(),
        photo: 'meal_1.jpg',
      );
      final c = container();
      final before = c.read(dataRevisionProvider);

      final missingOk = await c.read(mealEditorProvider).delete(meal.id + 1);

      expect(missingOk, isFalse);
      expect(meals.deletes, 1);
      expect(meals.rows, hasLength(1));
      expect(photos.deleteCalls, isEmpty);
      expect(c.read(dataRevisionProvider), before);

      meals.deleteError = Exception('db locked');
      final throwOk = await c.read(mealEditorProvider).delete(meal.id);

      expect(throwOk, isFalse);
      expect(meals.deletes, 2);
      expect(meals.rows, hasLength(1));
      expect(photos.deleteCalls, isEmpty);
      expect(c.read(dataRevisionProvider), before);
    });
  });
}

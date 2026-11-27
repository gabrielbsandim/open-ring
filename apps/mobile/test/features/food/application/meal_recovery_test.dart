import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/features/food/application/meal_photo_saver.dart';
import 'package:open_ring/features/food/application/meal_recovery.dart';
import 'package:open_ring/features/food/application/meal_store_providers.dart';
import 'package:open_ring/features/food/domain/exif.dart';
import 'package:open_ring/features/food/domain/meal_camera.dart';
import 'package:open_ring/features/food/domain/meal_store.dart';
import 'package:open_ring/features/food/domain/photo_store.dart';
import 'package:open_ring/features/food/infrastructure/drift_meal_store.dart';

import '../../../helpers/database.dart';
import '../jpeg_fixture.dart';

// No capture time, so the saved meal never depends on the test host clock.
final Uint8List _lost = photoJpeg(
  exif: exifApp1(dateTimeOriginal: null, offsetTimeOriginal: null),
);

/// Hands back the same lost photo on every call, as a cache never cleared.
final class _StickyCamera implements MealCamera {
  new(this.lost);

  final Uint8List? lost;
  int retrievals = 0;

  @override
  Future<Uint8List?> takePhoto() async => null;

  @override
  Future<Uint8List?> retrieveLost() async {
    retrievals++;
    return lost;
  }
}

/// Fails every save with errno 28 until [full] is cleared.
final class _FullPhotoStore implements PhotoStore {
  bool full = true;
  final inner = InMemoryPhotoStore();

  @override
  Future<void> save(String name, Uint8List bytes) async {
    if (full) {
      throw const FileSystemException(
        'Cannot write file',
        'meal.jpg.tmp',
        OSError('No space left on device', 28),
      );
    }
    await inner.save(name, bytes);
  }

  @override
  Future<Uint8List?> read(String name) => inner.read(name);

  @override
  Future<bool> delete(String name) => inner.delete(name);

  @override
  Future<int> deleteAll() => inner.deleteAll();

  @override
  Future<Map<String, int>> fileBytes() => inner.fileBytes();

  @override
  Future<int> totalBytes() => inner.totalBytes();
}

void main() {
  late MealStore meals;
  late InMemoryPhotoStore photos;

  setUp(() {
    meals = DriftMealStore(memoryDatabase());
    photos = InMemoryPhotoStore();
  });

  ProviderContainer containerWith(MealCamera camera, {PhotoStore? store}) {
    final container = ProviderContainer(
      overrides: [
        mealCameraProvider.overrideWithValue(camera),
        mealStoreProvider.overrideWithValue(meals),
        photoStoreProvider.overrideWithValue(store ?? photos),
      ],
    );
    addTearDown(container.dispose);
    container.listen(mealRecoveryProvider, (_, _) {});
    return container;
  }

  Future<List<String?>> photoNames() async => [
    for (final meal in await meals.between(
      const LocalDate(2000, 1, 1),
      const LocalDate(2100, 1, 1),
    ))
      meal.photo,
  ];

  group('criterion 7: recovery of a photo lost by a killed activity', () {
    test('a lost photo becomes one row with its photo', () async {
      final container = containerWith(_StickyCamera(_lost));

      await container.read(mealRecoveryProvider.notifier).run();

      final result = container.read(mealRecoveryProvider);
      expect(result?.outcome, SaveOutcome.saved);
      expect(await meals.count(), 1);
      final name = (await photoNames()).single;
      expect(name, isNotNull);
      expect(name, result!.meal!.photo);
      expect(await photos.read(name!), stripExif(_lost));
    });

    test('nothing lost gives null and writes nothing', () async {
      final camera = _StickyCamera(null);
      final container = containerWith(camera);

      await container.read(mealRecoveryProvider.notifier).run();

      expect(
        camera.retrievals,
        greaterThan(0),
        reason: 'it must ask the camera',
      );
      expect(container.read(mealRecoveryProvider), isNull);
      expect(await meals.count(), 0);
      expect(await photos.totalBytes(), 0);
    });

    test('running it twice still gives one row', () async {
      final container = containerWith(_StickyCamera(_lost));
      final recovery = container.read(mealRecoveryProvider.notifier);

      await recovery.run();
      await recovery.run();

      expect(await meals.count(), 1);
      expect(await photos.totalBytes(), stripExif(_lost).length);
    });

    test(
      'a lost photo that is not a JPEG ends failed, without throwing',
      () async {
        final container = containerWith(
          _StickyCamera(Uint8List.fromList(pngBytes)),
        );

        await container.read(mealRecoveryProvider.notifier).run();

        expect(
          container.read(mealRecoveryProvider)?.outcome,
          SaveOutcome.failed,
        );
        expect(await photos.totalBytes(), 0);
      },
    );
  });

  group('review fix 2: a recovered photo kept off its row by a full disk', () {
    test('retry attaches it once there is space', () async {
      final full = _FullPhotoStore();
      final container = containerWith(_StickyCamera(_lost), store: full);
      final recovery = container.read(mealRecoveryProvider.notifier);

      await recovery.run();
      expect(
        container.read(mealRecoveryProvider)?.outcome,
        SaveOutcome.noSpace,
      );
      expect(await photoNames(), [null]);

      full.full = false;
      await recovery.retry();

      final result = container.read(mealRecoveryProvider);
      expect(result?.outcome, SaveOutcome.saved);
      final name = (await photoNames()).single;
      expect(name, result!.meal!.photo);
      expect(await full.inner.read(name!), stripExif(_lost));
      expect(await meals.count(), 1);
    });

    test('a second retry after success writes nothing more', () async {
      final full = _FullPhotoStore();
      final container = containerWith(_StickyCamera(_lost), store: full);
      final recovery = container.read(mealRecoveryProvider.notifier);
      await recovery.run();
      full.full = false;
      await recovery.retry();

      await recovery.retry();

      expect(await full.inner.totalBytes(), stripExif(_lost).length);
      expect(container.read(mealRecoveryProvider)?.outcome, SaveOutcome.saved);
    });

    test('retry while still full stays noSpace and keeps the row', () async {
      final full = _FullPhotoStore();
      final container = containerWith(_StickyCamera(_lost), store: full);
      final recovery = container.read(mealRecoveryProvider.notifier);
      await recovery.run();

      await recovery.retry();

      expect(
        container.read(mealRecoveryProvider)?.outcome,
        SaveOutcome.noSpace,
      );
      expect(await photoNames(), [null]);
    });
  });
}

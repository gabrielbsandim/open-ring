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

void main() {
  late MealStore meals;
  late InMemoryPhotoStore photos;

  setUp(() {
    meals = DriftMealStore(memoryDatabase());
    photos = InMemoryPhotoStore();
  });

  ProviderContainer containerWith(MealCamera camera) {
    final container = ProviderContainer(
      overrides: [
        mealCameraProvider.overrideWithValue(camera),
        mealStoreProvider.overrideWithValue(meals),
        photoStoreProvider.overrideWithValue(photos),
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
}

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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
  late InMemoryPhotoStore photos;

  setUp(() {
    meals = TestMealStore();
    photos = InMemoryPhotoStore();
  });

  ProviderContainer containerWith(MealCamera camera, {PhotoStore? store}) {
    final container = ProviderContainer(
      overrides: foodOverrides(
        meals: meals,
        photos: store ?? photos,
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

  CaptureState stateOf(ProviderContainer container) =>
      container.read(mealCaptureProvider);

  int revisionOf(ProviderContainer container) =>
      container.read(dataRevisionProvider);

  group('criterion 3: a photo that comes back is saved', () {
    test('one row with its photo, and the revision moves once', () async {
      final container = containerWith(FakeMealCamera(photo: returnedPhoto));

      await captureOf(container).capture();

      final row = meals.rows.single;
      expect(row.photo, isNotNull);
      expect(await photos.read(row.photo!), isNotNull);
      expect(revisionOf(container), 1);
      expect(stateOf(container).result?.outcome, SaveOutcome.saved);
      expect(stateOf(container).result?.meal?.id, row.id);
      expect(stateOf(container).saving, isFalse);
    });

    test('a photo with no capture time keeps the time it came back', () async {
      final container = containerWith(FakeMealCamera(photo: returnedPhoto));

      await captureOf(container).capture();

      expect(stateOf(container).result?.time, TimeSource.returned);
      expect(meals.rows.single.at, lunch.toUtc());
    });

    test('a photo with a capture time keeps that time', () async {
      final container = containerWith(
        FakeMealCamera(photo: photoTakenAt(lunch)),
      );

      await captureOf(container).capture();

      expect(stateOf(container).result?.time, TimeSource.photo);
    });
  });

  group('criterion 4: a cancelled capture', () {
    test('writes no row, does not bump and is not saving', () async {
      final container = containerWith(FakeMealCamera());

      await captureOf(container).capture();

      expect(meals.rows, isEmpty);
      expect(revisionOf(container), 0);
      expect(stateOf(container).saving, isFalse);
      expect(stateOf(container).result, isNull);
    });
  });

  group('criterion 5: a second capture while saving', () {
    test('calls takePhoto once and saves one row', () async {
      final camera = GatedMealCamera();
      final container = containerWith(camera);

      final first = captureOf(container).capture();
      expect(stateOf(container).saving, isTrue);
      final second = captureOf(container).capture();
      camera.open(returnedPhoto);
      await Future.wait<void>([first, second]);

      expect(camera.takes, 1);
      expect(meals.rows, hasLength(1));
      expect(stateOf(container).saving, isFalse);
    });
  });

  group('criterion 6: a full disk', () {
    late FullPhotoStore full;

    setUp(() => full = FullPhotoStore());

    Future<ProviderContainer> savedWithoutSpace() async {
      final container = containerWith(
        FakeMealCamera(photo: returnedPhoto),
        store: full,
      );
      await captureOf(container).capture();
      return container;
    }

    test('keeps the row without a photo and bumps', () async {
      final container = await savedWithoutSpace();

      expect(stateOf(container).result?.outcome, SaveOutcome.noSpace);
      expect(meals.rows.single.photo, isNull);
      expect(revisionOf(container), 1);
    });

    test('retry attaches the photo once there is space, and bumps', () async {
      final container = await savedWithoutSpace();
      final before = revisionOf(container);
      full.full = false;

      await captureOf(container).retry();

      final name = meals.rows.single.photo;
      expect(name, isNotNull);
      expect(await full.inner.read(name!), isNotNull);
      expect(revisionOf(container), greaterThan(before));
    });

    test('retry while still full keeps the row without a photo', () async {
      final container = await savedWithoutSpace();

      await captureOf(container).retry();

      expect(stateOf(container).result?.outcome, SaveOutcome.noSpace);
      expect(meals.rows.single.photo, isNull);
      expect(await full.inner.totalBytes(), 0);
    });

    test('discard deletes the photoless row and bumps', () async {
      final container = await savedWithoutSpace();
      final before = revisionOf(container);

      await captureOf(container).discard();

      expect(meals.rows, isEmpty);
      expect(revisionOf(container), greaterThan(before));
    });

    test('discard keeps a row whose photo already landed', () async {
      final container = await savedWithoutSpace();
      final id = meals.rows.single.id;
      const name = 'meal_1_0000000a.jpg';
      full.full = false;
      await full.save(name, returnedPhoto);
      await meals.attachPhoto(id, name);

      await captureOf(container).discard();

      expect(meals.rows.single.photo, name);
    });
  });

  group('criterion 7: a capture that fails', () {
    test('a camera that throws reports failed and writes nothing', () async {
      final container = containerWith(ThrowingMealCamera());

      await captureOf(container).capture();

      expect(stateOf(container).result?.outcome, SaveOutcome.failed);
      expect(stateOf(container).saving, isFalse);
      expect(meals.rows, isEmpty);
    });

    test('bytes that are not a JPEG report failed and write nothing', () async {
      final container = containerWith(FakeMealCamera(photo: notAJpeg));

      await captureOf(container).capture();

      expect(stateOf(container).result?.outcome, SaveOutcome.failed);
      expect(stateOf(container).saving, isFalse);
      expect(meals.rows, isEmpty);
      expect(await photos.totalBytes(), 0);
    });
  });

  group('criterion 8: finish', () {
    Future<ProviderContainer> saved() async {
      final container = containerWith(FakeMealCamera(photo: returnedPhoto));
      await captureOf(container).capture();
      return container;
    }

    test('with last on writes last=true once and bumps once', () async {
      final container = await saved();
      final before = revisionOf(container);
      final photo = meals.rows.single.photo;
      final meal = stateOf(container).result!.meal!;

      await captureOf(container).finish(MealEdit.of(meal).withLast(true));

      final row = meals.rows.single;
      expect(row.last, isTrue);
      expect(row.photo, photo);
      expect(row.at, lunch.toUtc());
      expect(meals.updates, 1);
      expect(revisionOf(container), before + 1);
    });

    test('untouched writes nothing and does not bump', () async {
      final container = await saved();
      final before = revisionOf(container);
      final meal = stateOf(container).result!.meal!;

      await captureOf(container).finish(MealEdit.of(meal));

      expect(meals.updates, 0);
      expect(meals.rows.single.last, isFalse);
      expect(revisionOf(container), before);
    });
  });

  group('criterion 9: a recovered photo', () {
    test('lands in the capture state as recovered, and bumps', () async {
      final container = containerWith(FakeMealCamera(lost: returnedPhoto));

      await container.read(mealRecoveryProvider.notifier).run();

      expect(stateOf(container).recovered, isTrue);
      expect(stateOf(container).result?.outcome, SaveOutcome.saved);
      expect(meals.rows, hasLength(1));
      expect(revisionOf(container), greaterThan(0));
    });

    test('retry on a full disk goes through the recovery', () async {
      final full = FullPhotoStore();
      final container = containerWith(
        FakeMealCamera(lost: returnedPhoto),
        store: full,
      );
      await container.read(mealRecoveryProvider.notifier).run();
      expect(stateOf(container).recovered, isTrue);
      expect(stateOf(container).result?.outcome, SaveOutcome.noSpace);
      full.full = false;

      await captureOf(container).retry();

      expect(meals.rows.single.photo, isNotNull);
      expect(container.read(mealRecoveryProvider)?.outcome, SaveOutcome.saved);
    });

    test('finish clears the recovery so it does not open again', () async {
      final container = containerWith(FakeMealCamera(lost: returnedPhoto));
      await container.read(mealRecoveryProvider.notifier).run();

      await captureOf(container).finish();

      expect(container.read(mealRecoveryProvider), isNull);
      expect(stateOf(container).recovered, isFalse);
      expect(meals.rows, hasLength(1));
    });
  });
}

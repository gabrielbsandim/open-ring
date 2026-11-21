import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/router/app_router.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/features/food/application/food_photo_storage.dart';
import 'package:open_ring/features/food/application/meal_store_providers.dart';
import 'package:open_ring/features/food/domain/meal.dart';
import 'package:open_ring/features/food/domain/meal_store.dart';
import 'package:open_ring/features/food/domain/photo_store.dart';
import 'package:open_ring/features/food/presentation/food_storage_screen.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/modules/domain/module_store.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

import '../../../helpers/ble_fakes.dart';
import '../../../helpers/layout_harness.dart';
import '../../../helpers/onboarding_app.dart';
import '../../../helpers/onboarding_fakes.dart';
import '../../../helpers/ring_fakes.dart';
import '../food_fakes.dart';

final _now = DateTime(2026, 11, 21, 15);

final class _GatedPhotoStore implements PhotoStore {
  new(this.inner, this.deleteGate);

  final InMemoryPhotoStore inner;
  final Completer<void> deleteGate;
  int deleteCalls = 0;

  @override
  Future<void> save(String name, Uint8List bytes) => inner.save(name, bytes);

  @override
  Future<Uint8List?> read(String name) => inner.read(name);

  @override
  Future<bool> delete(String name) async {
    deleteCalls++;
    await deleteGate.future;
    return await inner.delete(name);
  }

  @override
  Future<int> deleteAll() async {
    deleteCalls++;
    await deleteGate.future;
    return await inner.deleteAll();
  }

  @override
  Future<Map<String, int>> fileBytes() => inner.fileBytes();

  @override
  Future<int> totalBytes() => inner.totalBytes();
}

Future<void> _pumpStorage(
  WidgetTester tester, {
  MealStore? meals,
  PhotoStore? photos,
  bool foodOn = true,
}) async {
  final store = meals ?? TestMealStore();
  await pumpScaled(
    tester,
    screenHost(const FoodStorageScreen()),
    textScaler: TextScaler.noScaling,
    brightness: Brightness.dark,
    locale: const Locale('en'),
    overrides: [
      moduleStoreProvider.overrideWithValue(
        InMemoryModuleStore({if (foodOn) ModuleId.food}),
      ),
      clockProvider.overrideWithValue(() => _now),
      mealStoreProvider.overrideWithValue(store),
      photoStoreProvider.overrideWithValue(photos ?? InMemoryPhotoStore()),
      mealCameraProvider.overrideWithValue(GatedMealCamera()),
    ],
  );
}

Future<void> _seedSample(TestMealStore meals, PhotoStore photos) async {
  final bytes = Uint8List(500000);
  final oldAt = _now.subtract(const Duration(days: 120));
  final recentAt = _now.subtract(const Duration(days: 5));
  await photos.save('old.jpg', bytes);
  await meals.add(
    MealDraft(
      at: oldAt.toUtc(),
      offsetMinutes: localOffset(oldAt),
      kind: MealKind.main,
      tags: const MealTags(protein: true),
    ),
    now: oldAt.toUtc(),
    photo: 'old.jpg',
  );
  await photos.save('new.jpg', bytes);
  await photos.save('new2.jpg', bytes);
  await meals.add(
    MealDraft(at: recentAt.toUtc(), offsetMinutes: localOffset(recentAt)),
    now: recentAt.toUtc(),
    photo: 'new.jpg',
  );
  await meals.add(
    MealDraft(
      at: recentAt.add(const Duration(hours: 2)).toUtc(),
      offsetMinutes: localOffset(recentAt),
    ),
    now: recentAt.toUtc(),
    photo: 'new2.jpg',
  );
}

void main() {
  group('FoodStorageScreen', () {
    testWidgets(
      'shows total size, count, average, earliest, pace and no Export tile',
      (tester) async {
        final meals = TestMealStore();
        final photos = InMemoryPhotoStore();
        await _seedSample(meals, photos);
        await _pumpStorage(tester, meals: meals, photos: photos, foodOn: false);

        expect(find.byKey(FoodStorageKeys.totalSize), findsOneWidget);
        expect(find.text('1.5 MB'), findsOneWidget);
        expect(find.text('3 photos'), findsOneWidget);
        expect(find.byKey(FoodStorageKeys.average), findsOneWidget);
        expect(find.byKey(FoodStorageKeys.oldest), findsOneWidget);
        expect(find.byKey(FoodStorageKeys.pace), findsOneWidget);
        expect(find.byKey(FoodStorageKeys.footnote), findsOneWidget);
        expect(find.textContaining('Export'), findsNothing);
      },
    );

    testWidgets('disables delete button when no photos or bytes exist', (
      tester,
    ) async {
      await _pumpStorage(tester);

      final button = tester.widget<OutlinedButton>(
        find.byKey(FoodStorageKeys.deleteOldButton),
      );
      expect(button.onPressed, isNull);
      expect(find.text('0.0 MB'), findsOneWidget);
      expect(find.text('No meal photos'), findsOneWidget);
    });

    testWidgets(
      'opens sheet with 0-count options disabled, confirm cancel keeps photos',
      (tester) async {
        final meals = TestMealStore();
        final photos = InMemoryPhotoStore();
        await _seedSample(meals, photos);
        await _pumpStorage(tester, meals: meals, photos: photos);

        await tester.tap(find.byKey(FoodStorageKeys.deleteOldButton));
        await tester.pumpAndSettle();

        expect(find.byKey(FoodStorageKeys.purgeSheet), findsOneWidget);
        final tile1y = tester.widget<ListTile>(
          find.byKey(FoodStorageKeys.option(PhotoPurgeRange.olderThanOneYear)),
        );
        expect(tile1y.enabled, isFalse);

        await tester.tap(
          find.byKey(
            FoodStorageKeys.option(PhotoPurgeRange.olderThanThreeMonths),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(FoodStorageKeys.confirmDialog), findsOneWidget);
        await tester.tap(find.byKey(FoodStorageKeys.confirmCancel));
        await tester.pumpAndSettle();

        expect(await meals.photoRefs(), hasLength(3));
        expect(await photos.totalBytes(), 1500000);
      },
    );

    testWidgets(
      'confirming purge deletes old photos, shows SnackBar, guards double tap',
      (tester) async {
        final meals = TestMealStore();
        final inner = InMemoryPhotoStore();
        final gate = Completer<void>();
        final photos = _GatedPhotoStore(inner, gate);
        await _seedSample(meals, inner);
        await _pumpStorage(tester, meals: meals, photos: photos);

        await tester.tap(find.byKey(FoodStorageKeys.deleteOldButton));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(
            FoodStorageKeys.option(PhotoPurgeRange.olderThanThreeMonths),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(FoodStorageKeys.confirmDelete));
        await tester.pump();

        final buttonDuring = tester.widget<OutlinedButton>(
          find.byKey(FoodStorageKeys.deleteOldButton),
        );
        expect(buttonDuring.onPressed, isNull);
        expect(photos.deleteCalls, 1);

        gate.complete();
        await tester.pumpAndSettle();

        final l10n = lookupAppLocalizations(const Locale('en'));
        expect(find.text(l10n.foodPhotosDeleted(1, '500 KB')), findsOneWidget);
        expect(find.text('1.0 MB'), findsOneWidget);
        expect(find.text('2 photos'), findsOneWidget);
        expect(await meals.count(), 3);
      },
    );

    testWidgets('DB error on purge shows failure SnackBar and keeps photos', (
      tester,
    ) async {
      final meals = TestMealStore()
        ..deletePhotosError = const FileSystemException('db locked');
      final photos = InMemoryPhotoStore();
      await _seedSample(meals, photos);
      await _pumpStorage(tester, meals: meals, photos: photos);

      await tester.tap(find.byKey(FoodStorageKeys.deleteOldButton));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          FoodStorageKeys.option(PhotoPurgeRange.olderThanThreeMonths),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(FoodStorageKeys.confirmDelete));
      await tester.pumpAndSettle();

      final l10n = lookupAppLocalizations(const Locale('en'));
      expect(find.text(l10n.foodPhotosDeleteFailed), findsOneWidget);
      expect(await meals.photoRefs(), hasLength(3));
      expect(await photos.totalBytes(), 1500000);
    });

    testWidgets(
      'appRouterProvider routes /ring/settings/food-photos even with Food off',
      (tester) async {
        final container = await pumpOnboardingApp(
          tester,
          store: InMemoryOnboardingStore(completed: true),
          overrides: [
            ...bleOverrides(),
            ...ringOverrides(),
            ...onboardingOverrides(),
            ...foodOverrides(
              meals: TestMealStore(),
              camera: GatedMealCamera(),
              clock: () => _now,
              foodOn: false,
            ),
          ],
        );

        container.read(appRouterProvider).go(AppPaths.settingsFoodPhotos);
        await tester.pumpAndSettle();

        expect(AppPaths.settingsFoodPhotos, '/ring/settings/food-photos');
        expect(find.byType(FoodStorageScreen), findsOneWidget);
      },
    );
  });
}

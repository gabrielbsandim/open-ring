import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/features/food/application/meal_store_providers.dart';
import 'package:open_ring/features/food/domain/meal.dart';
import 'package:open_ring/features/food/domain/photo_store.dart';
import 'package:open_ring/features/food/presentation/food_storage_screen.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/modules/domain/module_store.dart';

import '../../../helpers/layout_harness.dart';
import '../food_fakes.dart';

final _now = DateTime(2026, 11, 21, 15);

void main() {
  group('FoodStorageScreen layout matrix', () {
    for (final c in layoutMatrix()) {
      testWidgets('FoodStorageScreen fits without overflow at $c', (
        tester,
      ) async {
        final meals = TestMealStore();
        final photos = InMemoryPhotoStore();
        final oldAt = _now.subtract(const Duration(days: 120));
        await photos.save('a.jpg', Uint8List(500000));
        await meals.add(
          MealDraft(at: oldAt.toUtc(), offsetMinutes: localOffset(oldAt)),
          now: oldAt.toUtc(),
          photo: 'a.jpg',
        );
        await photos.save('b.jpg', Uint8List(500000));
        await meals.add(
          MealDraft(at: _now.toUtc(), offsetMinutes: localOffset(_now)),
          now: _now.toUtc(),
          photo: 'b.jpg',
        );

        await pumpScaled(
          tester,
          screenHost(const FoodStorageScreen()),
          textScaler: c.textScaler,
          brightness: c.brightness,
          locale: c.locale,
          overrides: [
            moduleStoreProvider.overrideWithValue(
              InMemoryModuleStore({ModuleId.food}),
            ),
            clockProvider.overrideWithValue(() => _now),
            mealStoreProvider.overrideWithValue(meals),
            photoStoreProvider.overrideWithValue(photos),
            mealCameraProvider.overrideWithValue(GatedMealCamera()),
          ],
        );

        await expectNoLayoutOverflow(() async {
          final scrollable = find.byType(Scrollable).first;
          for (final key in const [
            FoodStorageKeys.summary,
            FoodStorageKeys.deleteOldButton,
            FoodStorageKeys.footnote,
          ]) {
            await tester.scrollUntilVisible(
              find.byKey(key),
              120,
              scrollable: scrollable,
            );
            await tester.pumpAndSettle();
            expect(find.byKey(key), findsOneWidget);
          }

          await tester.tap(find.byKey(FoodStorageKeys.deleteOldButton));
          await tester.pumpAndSettle();
          expect(find.byKey(FoodStorageKeys.purgeSheet), findsOneWidget);
        });
      });
    }
  });
}

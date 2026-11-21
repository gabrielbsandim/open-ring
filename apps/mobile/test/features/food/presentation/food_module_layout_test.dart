import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/features/food/application/meal_store_providers.dart';
import 'package:open_ring/features/food/domain/meal.dart';
import 'package:open_ring/features/food/domain/photo_store.dart';
import 'package:open_ring/features/food/presentation/food_module_screen.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';
import 'package:open_ring/features/modules/domain/module_store.dart';

import '../../../helpers/layout_harness.dart';
import '../food_fakes.dart';

final _now = DateTime(2026, 11, 21, 15);

void main() {
  group('FoodModuleScreen layout matrix', () {
    for (final c in layoutMatrix()) {
      testWidgets('FoodModuleScreen fits without overflow at $c', (
        tester,
      ) async {
        final meals = TestMealStore();
        final photos = InMemoryPhotoStore();
        await photos.save('a.jpg', Uint8List(500000));
        await meals.add(
          MealDraft(at: _now.toUtc(), offsetMinutes: localOffset(_now)),
          now: _now.toUtc(),
          photo: 'a.jpg',
        );

        await pumpScaled(
          tester,
          screenHost(const FoodModuleScreen()),
          textScaler: c.textScaler,
          brightness: c.brightness,
          locale: c.locale,
          overrides: [
            moduleStoreProvider.overrideWithValue(InMemoryModuleStore()),
            clockProvider.overrideWithValue(() => _now),
            mealStoreProvider.overrideWithValue(meals),
            photoStoreProvider.overrideWithValue(photos),
          ],
        );

        await expectNoLayoutOverflow(() async {
          final scrollable = find.byType(Scrollable).first;
          for (final key in const [
            FoodModuleKeys.state,
            FoodModuleKeys.kept,
            FoodModuleKeys.photos,
            FoodModuleKeys.formula,
            FoodModuleKeys.stored,
            FoodModuleKeys.delete,
            FoodModuleKeys.toggle,
          ]) {
            await tester.scrollUntilVisible(
              find.byKey(key),
              140,
              scrollable: scrollable,
            );
            await tester.pumpAndSettle();
            expect(find.byKey(key), findsOneWidget);
          }
        });
      });
    }
  });
}

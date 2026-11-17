import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/features/food/application/meal_recovery.dart';
import 'package:open_ring/features/food/domain/meal_camera.dart';
import 'package:open_ring/features/food/domain/photo_store.dart';
import 'package:open_ring/features/food/presentation/food_row.dart';
import 'package:open_ring/features/food/presentation/meal_saved_sheet.dart';

import '../../../helpers/layout_harness.dart';
import '../food_fakes.dart';

final _lunch = DateTime(2026, 11, 17, 12, 30);

Future<ProviderContainer> _pump(
  WidgetTester tester,
  LayoutCase c, {
  required TestMealStore meals,
  required MealCamera camera,
  PhotoStore? photos,
}) async {
  await pumpScaled(
    tester,
    screenHost(
      const Scaffold(body: SingleChildScrollView(child: FoodRowSlot())),
    ),
    textScaler: c.textScaler,
    brightness: c.brightness,
    locale: c.locale,
    overrides: foodOverrides(
      meals: meals,
      camera: camera,
      photos: photos,
      clock: () => _lunch,
    ),
  );
  return ProviderScope.containerOf(tester.element(find.byType(Scaffold)));
}

void main() {
  group('criterion 10: no overflow', () {
    for (final c in layoutMatrix()) {
      testWidgets('the row with a count and a window fits at $c', (
        tester,
      ) async {
        final meals = TestMealStore()
          ..seed(DateTime(2026, 11, 17, 7, 10), kind: MealKind.drink)
          ..seed(DateTime(2026, 11, 17, 12, 5), kind: MealKind.main);

        await _pump(tester, c, meals: meals, camera: FakeMealCamera());

        expect(find.byKey(FoodRowKeys.row), findsOneWidget);
      });

      testWidgets('the saving row fits at $c', (tester) async {
        final camera = GatedMealCamera();
        await _pump(tester, c, meals: TestMealStore(), camera: camera);

        await expectNoLayoutOverflow(() async {
          await tester.tap(find.byKey(FoodRowKeys.camera));
          await tester.pump();
        });

        expect(find.byKey(FoodRowKeys.saving), findsOneWidget);
        camera.open(null);
        await tester.pumpAndSettle();
      });

      testWidgets('the saved sheet with every line fits at $c', (tester) async {
        final container = await _pump(
          tester,
          c,
          meals: TestMealStore(),
          camera: FakeMealCamera(lost: returnedPhoto),
        );

        await expectNoLayoutOverflow(() async {
          await container.read(mealRecoveryProvider.notifier).run();
          await tester.pumpAndSettle();
        });

        expect(find.byType(MealSavedSheet), findsOneWidget);
        expect(find.byKey(MealSavedSheetKeys.last), findsOneWidget);
        expect(find.byKey(MealSavedSheetKeys.done), findsOneWidget);
      });

      testWidgets('the no space sheet fits at $c', (tester) async {
        await _pump(
          tester,
          c,
          meals: TestMealStore(),
          camera: FakeMealCamera(photo: returnedPhoto),
          photos: FullPhotoStore(),
        );

        await expectNoLayoutOverflow(() async {
          await tester.tap(find.byKey(FoodRowKeys.camera));
          await tester.pumpAndSettle();
        });

        expect(find.byType(MealNoSpaceSheet), findsOneWidget);
        expect(find.byKey(MealSavedSheetKeys.retry), findsOneWidget);
        expect(find.byKey(MealSavedSheetKeys.withoutPhoto), findsOneWidget);
        expect(find.byKey(MealSavedSheetKeys.discard), findsOneWidget);
      });
    }
  });
}

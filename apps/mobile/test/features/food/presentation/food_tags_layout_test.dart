import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/features/food/application/meal_recovery.dart';
import 'package:open_ring/features/food/domain/meal.dart';
import 'package:open_ring/features/food/domain/meal_camera.dart';
import 'package:open_ring/features/food/presentation/food_row.dart';
import 'package:open_ring/features/food/presentation/meal_saved_sheet.dart';

import '../../../helpers/layout_harness.dart';
import '../food_fakes.dart';

final _lunch = DateTime(2026, 11, 17, 12, 30);

// A selected chip grows by its check mark, so one chip per group is chosen.
final List<Key> _onePerGroup = [
  MealSavedSheetKeys.kind(MealKind.values.last),
  for (final flag in MealFlag.values) MealSavedSheetKeys.flag(flag),
  MealSavedSheetKeys.veg(MealVeg.values.last),
  MealSavedSheetKeys.alcohol(MealAlcohol.values.last),
  MealSavedSheetKeys.processed(MealProcessed.values.last),
  MealSavedSheetKeys.place(MealPlace.values.last),
];

final List<Key> _allChips = [
  for (final kind in MealKind.values) MealSavedSheetKeys.kind(kind),
  for (final flag in MealFlag.values) MealSavedSheetKeys.flag(flag),
  for (final veg in MealVeg.values) MealSavedSheetKeys.veg(veg),
  for (final a in MealAlcohol.values) MealSavedSheetKeys.alcohol(a),
  for (final p in MealProcessed.values) MealSavedSheetKeys.processed(p),
  for (final place in MealPlace.values) MealSavedSheetKeys.place(place),
];

Future<ProviderContainer> _pump(WidgetTester tester, LayoutCase c) async {
  await pumpScaled(
    tester,
    screenHost(
      const Scaffold(body: SingleChildScrollView(child: FoodRowSlot())),
    ),
    textScaler: c.textScaler,
    brightness: c.brightness,
    locale: c.locale,
    overrides: foodOverrides(
      meals: TestMealStore(),
      camera: FakeMealCamera(lost: returnedPhoto),
      clock: () => _lunch,
    ),
  );
  return ProviderScope.containerOf(tester.element(find.byType(Scaffold)));
}

Future<void> _openRecovered(
  WidgetTester tester,
  ProviderContainer container,
) async {
  await container.read(mealRecoveryProvider.notifier).run();
  await tester.pumpAndSettle();
}

Finder get _sheetScrollable => find
    .descendant(
      of: find.byType(MealSavedSheet),
      matching: find.byType(Scrollable),
    )
    .first;

void main() {
  group('criterion 8: the saved sheet with the 10 groups', () {
    for (final c in layoutMatrix()) {
      testWidgets('fits, holds every chip, and scrolls to Done at $c', (
        tester,
      ) async {
        final container = await _pump(tester, c);

        await expectNoLayoutOverflow(() => _openRecovered(tester, container));

        expect(find.byType(MealSavedSheet), findsOneWidget);
        for (final key in _allChips) {
          expect(find.byKey(key), findsOneWidget, reason: '$key');
        }
        await tester.scrollUntilVisible(
          find.byKey(MealSavedSheetKeys.done),
          120,
          scrollable: _sheetScrollable,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(MealSavedSheetKeys.done));
        await tester.pumpAndSettle();
        expect(find.byType(MealSavedSheet), findsNothing);
      });

      testWidgets('fits with a chip chosen in every group at $c', (
        tester,
      ) async {
        final container = await _pump(tester, c);
        await _openRecovered(tester, container);

        await expectNoLayoutOverflow(() async {
          for (final key in _onePerGroup) {
            await tester.ensureVisible(find.byKey(key));
            await tester.pumpAndSettle();
            await tester.tap(find.byKey(key));
            await tester.pumpAndSettle();
          }
          await tester.ensureVisible(find.byKey(MealSavedSheetKeys.last));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(MealSavedSheetKeys.last));
          await tester.pumpAndSettle();
        });

        await tester.scrollUntilVisible(
          find.byKey(MealSavedSheetKeys.done),
          120,
          scrollable: _sheetScrollable,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(MealSavedSheetKeys.done));
        await tester.pumpAndSettle();
        expect(find.byType(MealSavedSheet), findsNothing);
      });
    }
  });
}

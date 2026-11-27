import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/food/application/meal_store_providers.dart';
import 'package:open_ring/features/food/domain/meal_camera.dart';
import 'package:open_ring/features/food/domain/meal_gallery.dart';
import 'package:open_ring/features/food/presentation/food_day_screen.dart';
import 'package:open_ring/features/food/presentation/food_gallery_screen.dart';

import '../../../helpers/layout_harness.dart';
import '../food_fakes.dart';
import '../jpeg_fixture.dart';

final _now = DateTime(2026, 11, 17, 21);

Uint8List _jpegUtc(DateTime utcWall) => photoJpeg(
  exif: exifApp1(
    dateTimeOriginal: exifDate(utcWall),
    offsetTimeOriginal: '+00:00',
  ),
);

List<Uint8List> _mixedBatch() => [
  photoTakenAt(DateTime(2026, 11, 17, 8)),
  photoTakenAt(DateTime(2026, 11, 17, 12, 31)),
  returnedPhoto,
  _jpegUtc(_now.toUtc().subtract(const Duration(days: 400))),
  notAJpeg,
  returnedPhoto,
];

Future<void> _pumpGallery(
  WidgetTester tester,
  LayoutCase c, {
  required TestMealStore meals,
  required MealGallery gallery,
}) => pumpScaled(
  tester,
  screenHost(const FoodGalleryScreen()),
  textScaler: c.textScaler,
  brightness: c.brightness,
  locale: c.locale,
  overrides: [
    ...foodOverrides(meals: meals, camera: FakeMealCamera(), clock: () => _now),
    mealGalleryProvider.overrideWithValue(gallery),
  ],
);

Future<void> _pumpDay(
  WidgetTester tester,
  LayoutCase c, {
  required TestMealStore meals,
}) => pumpScaled(
  tester,
  screenHost(const FoodDayScreen()),
  textScaler: c.textScaler,
  brightness: c.brightness,
  locale: c.locale,
  overrides: foodOverrides(
    meals: meals,
    camera: FakeMealCamera(),
    clock: () => _now,
  ),
);

void main() {
  group('F7b gallery and add-row layout matrix', () {
    for (final c in layoutMatrix()) {
      testWidgets('FoodGalleryScreen mixed batch with skipped item scrolls '
          'without overflow at $c', (tester) async {
        final meals = TestMealStore()..seed(DateTime(2026, 11, 17, 12, 30));
        final gallery = FakeMealGallery(photos: _mixedBatch());

        await _pumpGallery(tester, c, meals: meals, gallery: gallery);

        await expectNoLayoutOverflow(() async {
          final list = find.byType(Scrollable).first;
          for (var i = 0; i < 6; i++) {
            await tester.scrollUntilVisible(
              find.byKey(FoodGalleryKeys.item(i)),
              120,
              scrollable: list,
            );
            await tester.pumpAndSettle();
          }
          await tester.ensureVisible(find.byKey(FoodGalleryKeys.skip(5)));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(FoodGalleryKeys.skip(5)));
          await tester.pumpAndSettle();

          await tester.scrollUntilVisible(
            find.byKey(FoodGalleryKeys.save),
            120,
            scrollable: list,
          );
          await tester.pumpAndSettle();
        });

        expect(find.byKey(FoodGalleryKeys.save), findsOneWidget);
      });

      testWidgets('FoodDayScreen empty today add row fits 3 buttons without '
          'overflow at $c', (tester) async {
        await _pumpDay(tester, c, meals: TestMealStore());

        await expectNoLayoutOverflow(() async {
          await tester.scrollUntilVisible(
            find.byKey(FoodDayKeys.addWithoutPhoto),
            120,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.pumpAndSettle();
        });

        expect(find.byKey(FoodDayKeys.empty), findsOneWidget);
        expect(find.byKey(FoodDayKeys.addPhoto), findsOneWidget);
        expect(find.byKey(FoodDayKeys.addFromGallery), findsOneWidget);
        expect(find.byKey(FoodDayKeys.addWithoutPhoto), findsOneWidget);
      });

      testWidgets('FoodDayScreen empty yesterday add row fits 2 buttons '
          'without overflow at $c', (tester) async {
        await _pumpDay(tester, c, meals: TestMealStore());

        await expectNoLayoutOverflow(() async {
          await tester.tap(find.byKey(FoodDayKeys.previous));
          await tester.pumpAndSettle();
          await tester.scrollUntilVisible(
            find.byKey(FoodDayKeys.addWithoutPhoto),
            120,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.pumpAndSettle();
        });

        expect(find.byKey(FoodDayKeys.empty), findsOneWidget);
        expect(find.byKey(FoodDayKeys.addPhoto), findsNothing);
        expect(find.byKey(FoodDayKeys.addFromGallery), findsOneWidget);
        expect(find.byKey(FoodDayKeys.addWithoutPhoto), findsOneWidget);
      });
    }
  });
}

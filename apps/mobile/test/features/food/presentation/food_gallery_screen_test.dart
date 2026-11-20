import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/router/app_router.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/core/records/data_revision.dart';
import 'package:open_ring/features/food/application/gallery_backfill.dart';
import 'package:open_ring/features/food/application/meal_store_providers.dart';
import 'package:open_ring/features/food/domain/meal.dart';
import 'package:open_ring/features/food/domain/meal_camera.dart';
import 'package:open_ring/features/food/domain/meal_gallery.dart';
import 'package:open_ring/features/food/domain/photo_store.dart';
import 'package:open_ring/features/food/presentation/food_day_screen.dart';
import 'package:open_ring/features/food/presentation/food_gallery_screen.dart';
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
import '../jpeg_fixture.dart';

final _now = DateTime(2026, 11, 17, 21);
const _today = LocalDate(2026, 11, 17);
const _yesterday = LocalDate(2026, 11, 16);

Uint8List _jpegUtc(DateTime utcWall, {String offset = '+00:00'}) => photoJpeg(
  exif: exifApp1(
    dateTimeOriginal: exifDate(utcWall),
    offsetTimeOriginal: offset,
  ),
);

Uint8List _corruptReadyJpeg(DateTime local) => bytesOf([
  soi,
  exifApp1(dateTimeOriginal: exifDate(local), offsetTimeOriginal: null),
  eoi,
]);

final class _GatedMealGallery implements MealGallery {
  final _picked = Completer<List<Uint8List>>();
  int calls = 0;

  void complete(List<Uint8List> photos) => _picked.complete(photos);

  @override
  Future<List<Uint8List>> pickPhotos({int limit = galleryPickLimit}) {
    calls++;
    return _picked.future;
  }
}

final class _FailingSavePhotoStore implements PhotoStore {
  final inner = InMemoryPhotoStore();

  @override
  Future<void> save(String name, Uint8List bytes) async {
    throw const FileSystemException(
      'Cannot write file',
      'meal.jpg.tmp',
      OSError('Permission denied', 13),
    );
  }

  @override
  Future<Uint8List?> read(String name) => inner.read(name);

  @override
  Future<bool> delete(String name) => inner.delete(name);

  @override
  Future<int> deleteAll() => inner.deleteAll();

  @override
  Future<int> totalBytes() => inner.totalBytes();
}

Future<ProviderContainer> _pumpGallery(
  WidgetTester tester, {
  required TestMealStore meals,
  required MealGallery gallery,
  PhotoStore? photos,
  LocalDate? initialDay,
  bool autoPick = true,
  DateTime Function()? clock,
  GalleryDateTimePicker? picker,
  List<Override>? overrides,
}) async {
  await pumpScaled(
    tester,
    screenHost(FoodGalleryScreen(initialDay: initialDay, autoPick: autoPick)),
    textScaler: TextScaler.noScaling,
    brightness: Brightness.dark,
    locale: const Locale('en'),
    size: const Size(360, 2000),
    overrides:
        overrides ??
        [
          ...foodOverrides(
            meals: meals,
            camera: FakeMealCamera(),
            photos: photos,
            clock: clock ?? () => _now,
          ),
          mealGalleryProvider.overrideWithValue(gallery),
          if (picker != null)
            galleryDateTimePickerProvider.overrideWithValue(picker),
        ],
  );
  return ProviderScope.containerOf(
    tester.element(find.byType(FoodGalleryScreen)),
  );
}

Future<ProviderContainer> _pumpRouterAtFood(
  WidgetTester tester, {
  required TestMealStore meals,
  required MealGallery gallery,
  PhotoStore? photos,
  DateTime Function()? clock,
  GalleryDateTimePicker? picker,
}) => pumpOnboardingApp(
  tester,
  store: InMemoryOnboardingStore(completed: true),
  at: AppPaths.food,
  overrides: [
    ...bleOverrides(),
    ...ringOverrides(),
    ...onboardingOverrides(),
    ...foodOverrides(
      meals: meals,
      camera: FakeMealCamera(),
      photos: photos,
      clock: clock ?? () => _now,
    ),
    mealGalleryProvider.overrideWithValue(gallery),
    if (picker != null) galleryDateTimePickerProvider.overrideWithValue(picker),
  ],
);

Future<void> _tapKey(WidgetTester tester, Key key) async {
  await tester.ensureVisible(find.byKey(key));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(key));
  await tester.pumpAndSettle();
}

bool _buttonEnabled(WidgetTester tester, Key key) {
  final button = find.descendant(
    of: find.byKey(key),
    matching: find.bySubtype<ButtonStyleButton>(),
    matchRoot: true,
  );
  if (button.evaluate().isNotEmpty) {
    return tester.widget<ButtonStyleButton>(button.first).onPressed != null;
  }
  return switch (tester.widget(find.byKey(key))) {
    final IconButton b => b.onPressed != null,
    final InkWell w => w.onTap != null,
    final other => throw StateError('not a button: ${other.runtimeType}'),
  };
}

Finder _inItem(int index, Finder matching) => find.descendant(
  of: find.byKey(FoodGalleryKeys.item(index)),
  matching: matching,
);

Finder _snackText(String text) =>
    find.descendant(of: find.byType(SnackBar), matching: find.text(text));

void main() {
  group('Food off', () {
    testWidgets('renders empty FoodGalleryScreen and never reads MealGallery, '
        'MealStore, PhotoStore, or MealCamera', (tester) async {
      final l10n = lookupAppLocalizations(const Locale('en'));
      final reads = StoreReads();
      var galleryRead = false;

      await _pumpGallery(
        tester,
        meals: TestMealStore(),
        gallery: FakeMealGallery(),
        overrides: [
          moduleStoreProvider.overrideWithValue(InMemoryModuleStore()),
          clockProvider.overrideWithValue(() => _now),
          ...reads.overrides(),
          mealGalleryProvider.overrideWith((ref) {
            galleryRead = true;
            throw UnimplementedError('Override mealGalleryProvider.');
          }),
        ],
      );

      expect(find.text(l10n.foodGalleryTitle), findsOneWidget);
      expect(find.text(l10n.foodGallerySubtitle), findsNothing);
      expect(find.byKey(FoodGalleryKeys.save), findsNothing);
      expect(find.byKey(FoodGalleryKeys.pickAgain), findsNothing);
      expect(reads.any, isFalse);
      expect(galleryRead, isFalse);
      expect(tester.takeException(), isNull);
    });
  });

  group('Routing and FoodDayScreen entry', () {
    test(
      'AppPaths.foodGallery and foodGalleryOn follow the route contract',
      () {
        expect(AppPaths.foodGallery, '/today/food/gallery');
        expect(
          AppPaths.foodGalleryOn(const LocalDate(2026, 11, 16)),
          '/today/food/gallery?day=2026-11-16',
        );
      },
    );

    testWidgets('FoodDayScreen shows From gallery on today and past days', (
      tester,
    ) async {
      final l10n = lookupAppLocalizations(const Locale('en'));
      final meals = TestMealStore();

      await pumpScaled(
        tester,
        screenHost(const FoodDayScreen()),
        textScaler: TextScaler.noScaling,
        brightness: Brightness.dark,
        locale: const Locale('en'),
        size: const Size(360, 2000),
        overrides: foodOverrides(
          meals: meals,
          camera: FakeMealCamera(),
          clock: () => _now,
        ),
      );

      expect(find.byKey(FoodDayKeys.addFromGallery), findsOneWidget);
      expect(find.text(l10n.foodGalleryTitle), findsOneWidget);

      await _tapKey(tester, FoodDayKeys.previous);

      expect(find.byKey(FoodDayKeys.addPhoto), findsNothing);
      expect(find.byKey(FoodDayKeys.addFromGallery), findsOneWidget);
      expect(find.byKey(FoodDayKeys.addWithoutPhoto), findsOneWidget);
    });

    testWidgets('tapping addFromGallery on today pushes '
        '/today/food/gallery?day=today and popping returns to FoodDayScreen', (
      tester,
    ) async {
      final meals = TestMealStore();
      final gallery = FakeMealGallery(
        photos: [photoTakenAt(DateTime(2026, 11, 17, 12, 30))],
      );
      final container = await _pumpRouterAtFood(
        tester,
        meals: meals,
        gallery: gallery,
      );

      await _tapKey(tester, FoodDayKeys.addFromGallery);

      final router = container.read(appRouterProvider);
      expect(router.state.uri.toString(), AppPaths.foodGalleryOn(_today));
      final screen = tester.widget<FoodGalleryScreen>(
        find.byType(FoodGalleryScreen),
      );
      expect(screen.initialDay, _today);
      expect(find.byKey(FoodGalleryKeys.item(0)), findsOneWidget);

      router.pop();
      await tester.pumpAndSettle();

      expect(find.byType(FoodGalleryScreen), findsNothing);
      expect(find.byType(FoodDayScreen), findsOneWidget);
      expect(router.state.uri.path, AppPaths.food);
    });

    testWidgets('tapping addFromGallery on yesterday passes initialDay of '
        'yesterday', (tester) async {
      final meals = TestMealStore();
      final gallery = FakeMealGallery(
        photos: [photoTakenAt(DateTime(2026, 11, 16, 12, 30))],
      );
      final container = await _pumpRouterAtFood(
        tester,
        meals: meals,
        gallery: gallery,
      );

      await _tapKey(tester, FoodDayKeys.previous);
      await _tapKey(tester, FoodDayKeys.addFromGallery);

      final router = container.read(appRouterProvider);
      expect(router.state.uri.toString(), AppPaths.foodGalleryOn(_yesterday));
      final screen = tester.widget<FoodGalleryScreen>(
        find.byType(FoodGalleryScreen),
      );
      expect(screen.initialDay, _yesterday);
    });

    testWidgets('direct gallery routes parse valid day query parameter and '
        'treat missing or invalid day as null', (tester) async {
      final meals = TestMealStore();
      final gallery = FakeMealGallery(
        photos: [photoTakenAt(DateTime(2026, 11, 15, 12, 30))],
      );
      final container = await _pumpRouterAtFood(
        tester,
        meals: meals,
        gallery: gallery,
      );
      final router = container.read(appRouterProvider);

      unawaited(router.push(AppPaths.foodGallery));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FoodGalleryScreen>(find.byType(FoodGalleryScreen))
            .initialDay,
        isNull,
      );

      router.go(AppPaths.foodGalleryOn(const LocalDate(2026, 11, 15)));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FoodGalleryScreen>(find.byType(FoodGalleryScreen))
            .initialDay,
        const LocalDate(2026, 11, 15),
      );

      router.go('${AppPaths.foodGallery}?day=not-a-date');
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FoodGalleryScreen>(find.byType(FoodGalleryScreen))
            .initialDay,
        isNull,
      );
    });

    testWidgets('empty pick inside GoRouter pops cleanly back to FoodDayScreen '
        'without SnackBar', (tester) async {
      final meals = TestMealStore();
      final gallery = FakeMealGallery();
      final container = await _pumpRouterAtFood(
        tester,
        meals: meals,
        gallery: gallery,
      );

      await _tapKey(tester, FoodDayKeys.addFromGallery);

      expect(gallery.calls, 1);
      expect(find.byType(FoodGalleryScreen), findsNothing);
      expect(find.byType(FoodDayScreen), findsOneWidget);
      expect(container.read(appRouterProvider).state.uri.path, AppPaths.food);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('saving inside GoRouter persists meals, shows saved SnackBar, '
        'resets, and pops back to FoodDayScreen', (tester) async {
      final l10n = lookupAppLocalizations(const Locale('en'));
      final meals = TestMealStore();
      final gallery = FakeMealGallery(
        photos: [photoTakenAt(DateTime(2026, 11, 17, 12, 30))],
      );
      final container = await _pumpRouterAtFood(
        tester,
        meals: meals,
        gallery: gallery,
      );
      final before = container.read(dataRevisionProvider);

      await _tapKey(tester, FoodDayKeys.addFromGallery);
      await _tapKey(tester, FoodGalleryKeys.save);

      expect(meals.rows, hasLength(1));
      expect(container.read(dataRevisionProvider), before + 1);
      expect(find.byType(FoodGalleryScreen), findsNothing);
      expect(find.byType(FoodDayScreen), findsOneWidget);
      expect(
        find.byKey(FoodDayKeys.meal(meals.rows.single.id)),
        findsOneWidget,
      );
      expect(_snackText(l10n.foodGallerySavedCount(1)), findsOneWidget);
      expect(
        container.read(galleryBackfillProvider).phase,
        GalleryImportPhase.idle,
      );
    });
  });

  group('Pick failure and empty pick on standalone screen', () {
    testWidgets('pick failure shows foodGalleryPickFailed SnackBar and '
        'renders pickAgain on standalone screen', (tester) async {
      final l10n = lookupAppLocalizations(const Locale('en'));
      final gallery = FakeMealGallery(error: StateError('picker unavailable'));

      await _pumpGallery(tester, meals: TestMealStore(), gallery: gallery);

      expect(_snackText(l10n.foodGalleryPickFailed), findsOneWidget);
      expect(find.byKey(FoodGalleryKeys.pickAgain), findsOneWidget);

      gallery.error = null;
      gallery.photos = [photoTakenAt(DateTime(2026, 11, 17, 12, 30))];
      await _tapKey(tester, FoodGalleryKeys.pickAgain);

      expect(gallery.calls, 2);
      expect(find.byKey(FoodGalleryKeys.item(0)), findsOneWidget);
    });

    testWidgets('pick failure inside GoRouter shows SnackBar and pops back', (
      tester,
    ) async {
      final l10n = lookupAppLocalizations(const Locale('en'));
      final gallery = FakeMealGallery(error: StateError('picker unavailable'));

      await _pumpRouterAtFood(tester, meals: TestMealStore(), gallery: gallery);

      await _tapKey(tester, FoodDayKeys.addFromGallery);

      expect(find.byType(FoodGalleryScreen), findsNothing);
      expect(find.byType(FoodDayScreen), findsOneWidget);
      expect(_snackText(l10n.foodGalleryPickFailed), findsOneWidget);
    });

    testWidgets('empty pick on standalone screen renders pickAgain without '
        'error SnackBar', (tester) async {
      final gallery = FakeMealGallery();

      await _pumpGallery(tester, meals: TestMealStore(), gallery: gallery);

      expect(gallery.calls, 1);
      expect(find.byKey(FoodGalleryKeys.pickAgain), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets(
      'autoPick false waits for pickAgain tap before calling picker',
      (tester) async {
        final gallery = FakeMealGallery(
          photos: [photoTakenAt(DateTime(2026, 11, 17, 12, 30))],
        );

        await _pumpGallery(
          tester,
          meals: TestMealStore(),
          gallery: gallery,
          autoPick: false,
        );

        expect(gallery.calls, 0);
        expect(find.byKey(FoodGalleryKeys.pickAgain), findsOneWidget);

        await _tapKey(tester, FoodGalleryKeys.pickAgain);

        expect(gallery.calls, 1);
        expect(find.byKey(FoodGalleryKeys.item(0)), findsOneWidget);
      },
    );
  });

  group('Review states and thumbnails', () {
    testWidgets('ready item shows 48 dp Image with cacheWidth 96, slot from '
        'photo, and subtitle/footer notes', (tester) async {
      final l10n = lookupAppLocalizations(const Locale('en'));
      final gallery = FakeMealGallery(
        photos: [photoTakenAt(DateTime(2026, 11, 17, 12, 30))],
      );

      await _pumpGallery(tester, meals: TestMealStore(), gallery: gallery);

      expect(find.text(l10n.foodGallerySubtitle), findsOneWidget);
      expect(find.text(l10n.foodGalleryPickerNote), findsOneWidget);
      expect(find.byKey(FoodGalleryKeys.item(0)), findsOneWidget);
      expect(
        _inItem(0, find.text(l10n.foodGalleryFromPhoto(l10n.foodSlotLunch))),
        findsOneWidget,
      );
      expect(_inItem(0, find.text('12:30')), findsOneWidget);
      expect(find.byKey(FoodGalleryKeys.anotherMeal(0)), findsNothing);
      expect(find.byKey(FoodGalleryKeys.pickTime(0)), findsNothing);
      expect(find.byKey(FoodGalleryKeys.saveOld(0)), findsNothing);

      final imageFinder = _inItem(0, find.byType(Image));
      expect(imageFinder, findsOneWidget);
      final image = tester.widget<Image>(imageFinder);
      expect(image.width, 48);
      expect(image.height, 48);
      expect(
        image.image,
        isA<ResizeImage>().having((r) => r.width, 'cacheWidth', 96),
      );
    });

    testWidgets(
      'corrupt JPEG bytes fall back to placeholder without crashing',
      (tester) async {
        final gallery = FakeMealGallery(
          photos: [_corruptReadyJpeg(DateTime(2026, 11, 17, 12, 30))],
        );

        await _pumpGallery(tester, meals: TestMealStore(), gallery: gallery);
        await tester.pumpAndSettle();

        expect(find.byKey(FoodGalleryKeys.item(0)), findsOneWidget);
        expect(_inItem(0, find.byType(Image)), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('nearDuplicate shows duplicate copy and resolves via '
        'anotherMeal or skip', (tester) async {
      final l10n = lookupAppLocalizations(const Locale('en'));
      final meals = TestMealStore()..seed(DateTime(2026, 11, 17, 12, 30));
      final dupPhoto = photoTakenAt(DateTime(2026, 11, 17, 12, 31));
      final gallery = FakeMealGallery(photos: [dupPhoto, dupPhoto]);

      await _pumpGallery(tester, meals: meals, gallery: gallery);

      expect(
        _inItem(0, find.text(l10n.foodGalleryDuplicateBody('12:30'))),
        findsOneWidget,
      );
      expect(find.byKey(FoodGalleryKeys.anotherMeal(0)), findsOneWidget);
      expect(find.byKey(FoodGalleryKeys.skip(0)), findsOneWidget);

      await _tapKey(tester, FoodGalleryKeys.anotherMeal(0));
      expect(find.byKey(FoodGalleryKeys.anotherMeal(0)), findsNothing);
      expect(
        _inItem(0, find.text(l10n.foodGalleryFromPhoto(l10n.foodSlotLunch))),
        findsOneWidget,
      );

      await _tapKey(tester, FoodGalleryKeys.skip(1));
      expect(find.byKey(FoodGalleryKeys.anotherMeal(1)), findsNothing);
      expect(find.byKey(FoodGalleryKeys.skip(1)), findsNothing);
      expect(_inItem(1, find.text(l10n.foodGallerySkipped)), findsOneWidget);
    });

    testWidgets('needsTime shows no-time copy, keeps needsTime on cancel, '
        'refuses future time with SnackBar, and accepts valid time', (
      tester,
    ) async {
      final l10n = lookupAppLocalizations(const Locale('en'));
      DateTime? pickedResponse;
      final recorded = <({DateTime initial, DateTime lastDate})>[];
      final gallery = FakeMealGallery(photos: [returnedPhoto, returnedPhoto]);

      await _pumpGallery(
        tester,
        meals: TestMealStore(),
        gallery: gallery,
        picker: (_, {required initial, required lastDate}) async {
          recorded.add((initial: initial, lastDate: lastDate));
          return pickedResponse;
        },
      );

      expect(
        _inItem(0, find.text(l10n.foodGalleryNoTimeTitle)),
        findsOneWidget,
      );
      expect(_inItem(0, find.text(l10n.foodGalleryNoTimeBody)), findsOneWidget);
      expect(find.byKey(FoodGalleryKeys.pickTime(0)), findsOneWidget);
      expect(find.byKey(FoodGalleryKeys.skip(0)), findsOneWidget);

      // Cancel keeps needsTime.
      pickedResponse = null;
      await _tapKey(tester, FoodGalleryKeys.pickTime(0));
      expect(recorded.single.initial, _now);
      expect(recorded.single.lastDate, _now);
      expect(find.byKey(FoodGalleryKeys.pickTime(0)), findsOneWidget);

      // Future DateTime refuses with SnackBar and keeps needsTime.
      pickedResponse = _now.add(const Duration(minutes: 1));
      await _tapKey(tester, FoodGalleryKeys.pickTime(0));
      expect(_snackText(l10n.foodAddFutureError), findsOneWidget);
      expect(find.byKey(FoodGalleryKeys.pickTime(0)), findsOneWidget);

      // Valid non-future DateTime becomes ready with chosen time copy.
      pickedResponse = DateTime(2026, 11, 17, 12, 30);
      await _tapKey(tester, FoodGalleryKeys.pickTime(0));
      expect(find.byKey(FoodGalleryKeys.pickTime(0)), findsNothing);
      expect(
        _inItem(0, find.text(l10n.foodGalleryChosenTime('12:30'))),
        findsOneWidget,
      );

      // Skip on item 1.
      await _tapKey(tester, FoodGalleryKeys.skip(1));
      expect(_inItem(1, find.text(l10n.foodGallerySkipped)), findsOneWidget);
    });

    testWidgets('pickTime passes initial = 12:00 on past initialDay and '
        'initial = now when initialDay is today or null', (tester) async {
      final recorded = <({DateTime initial, DateTime lastDate})>[];
      final gallery = FakeMealGallery(photos: [returnedPhoto]);

      await _pumpGallery(
        tester,
        meals: TestMealStore(),
        gallery: gallery,
        initialDay: _yesterday,
        picker: (_, {required initial, required lastDate}) async {
          recorded.add((initial: initial, lastDate: lastDate));
          return null;
        },
      );
      await _tapKey(tester, FoodGalleryKeys.pickTime(0));

      expect(recorded.single.initial, DateTime(2026, 11, 16, 12));
      expect(recorded.single.lastDate, _now);
    });

    testWidgets('tooOld shows old copy and resolves via saveOld or skip', (
      tester,
    ) async {
      final l10n = lookupAppLocalizations(const Locale('en'));
      final oldUtc = _now.toUtc().subtract(const Duration(days: 400));
      final gallery = FakeMealGallery(
        photos: [_jpegUtc(oldUtc), _jpegUtc(oldUtc)],
      );

      await _pumpGallery(tester, meals: TestMealStore(), gallery: gallery);

      expect(_inItem(0, find.text(l10n.foodGalleryOldBody)), findsOneWidget);
      expect(find.byKey(FoodGalleryKeys.saveOld(0)), findsOneWidget);
      expect(find.byKey(FoodGalleryKeys.skip(0)), findsOneWidget);

      await _tapKey(tester, FoodGalleryKeys.saveOld(0));
      expect(find.byKey(FoodGalleryKeys.saveOld(0)), findsNothing);

      await _tapKey(tester, FoodGalleryKeys.skip(1));
      expect(_inItem(1, find.text(l10n.foodGallerySkipped)), findsOneWidget);
    });

    testWidgets('dual nearDuplicate and tooOld item requires both '
        'confirmations before becoming ready', (tester) async {
      final ancientAt = _now.toUtc().subtract(const Duration(days: 400));
      final meals = TestMealStore();
      await meals.add(
        MealDraft(at: ancientAt, offsetMinutes: 0),
        now: _now.toUtc(),
      );
      final gallery = FakeMealGallery(
        photos: [_jpegUtc(ancientAt.add(const Duration(minutes: 1)))],
      );

      final container = await _pumpGallery(
        tester,
        meals: meals,
        gallery: gallery,
      );

      expect(find.byKey(FoodGalleryKeys.anotherMeal(0)), findsOneWidget);
      expect(find.byKey(FoodGalleryKeys.saveOld(0)), findsNothing);
      expect(container.read(galleryBackfillProvider).readyCount, 0);

      await _tapKey(tester, FoodGalleryKeys.anotherMeal(0));

      expect(find.byKey(FoodGalleryKeys.saveOld(0)), findsOneWidget);
      expect(container.read(galleryBackfillProvider).readyCount, 0);

      await _tapKey(tester, FoodGalleryKeys.saveOld(0));

      expect(find.byKey(FoodGalleryKeys.saveOld(0)), findsNothing);
      expect(container.read(galleryBackfillProvider).readyCount, 1);
    });

    testWidgets('unreadable item renders placeholder and foodGalleryUnreadable '
        'with no action buttons', (tester) async {
      final l10n = lookupAppLocalizations(const Locale('en'));
      final gallery = FakeMealGallery(photos: [notAJpeg]);

      await _pumpGallery(tester, meals: TestMealStore(), gallery: gallery);

      expect(find.byKey(FoodGalleryKeys.item(0)), findsOneWidget);
      expect(_inItem(0, find.byType(Image)), findsNothing);
      expect(_inItem(0, find.text(l10n.foodGalleryUnreadable)), findsOneWidget);
      expect(find.byKey(FoodGalleryKeys.anotherMeal(0)), findsNothing);
      expect(find.byKey(FoodGalleryKeys.pickTime(0)), findsNothing);
      expect(find.byKey(FoodGalleryKeys.saveOld(0)), findsNothing);
      expect(find.byKey(FoodGalleryKeys.skip(0)), findsNothing);
    });
  });

  group('Save button, captions, and error SnackBars', () {
    testWidgets('save button enabled state, plural label, and openChoices vs '
        'stripNote caption update as items are resolved', (tester) async {
      final l10n = lookupAppLocalizations(const Locale('en'));
      final gallery = FakeMealGallery(
        photos: [photoTakenAt(DateTime(2026, 11, 17, 8)), returnedPhoto],
      );

      await _pumpGallery(tester, meals: TestMealStore(), gallery: gallery);

      expect(_buttonEnabled(tester, FoodGalleryKeys.save), isTrue);
      expect(find.text(l10n.foodGallerySaveButton(1)), findsOneWidget);
      expect(find.text(l10n.foodGalleryOpenChoices(1)), findsOneWidget);
      expect(find.text(l10n.foodGalleryStripNote), findsNothing);

      await _tapKey(tester, FoodGalleryKeys.skip(1));

      expect(find.text(l10n.foodGallerySaveButton(1)), findsOneWidget);
      expect(find.text(l10n.foodGalleryOpenChoices(1)), findsNothing);
      expect(find.text(l10n.foodGalleryStripNote), findsOneWidget);
    });

    testWidgets('save button is disabled when readyCount is 0 and shows '
        'Save 0 meals', (tester) async {
      final l10n = lookupAppLocalizations(const Locale('en'));
      final gallery = FakeMealGallery(photos: [returnedPhoto]);

      await _pumpGallery(tester, meals: TestMealStore(), gallery: gallery);

      expect(_buttonEnabled(tester, FoodGalleryKeys.save), isFalse);
      expect(find.text(l10n.foodGallerySaveButton(0)), findsOneWidget);
      expect(find.text(l10n.foodGalleryOpenChoices(1)), findsOneWidget);
    });

    testWidgets('saving 2 ready items persists both, bumps revision once, and '
        'shows foodGallerySavedCount(2)', (tester) async {
      final l10n = lookupAppLocalizations(const Locale('en'));
      final meals = TestMealStore();
      final photos = InMemoryPhotoStore();
      final gallery = FakeMealGallery(
        photos: [
          photoTakenAt(DateTime(2026, 11, 17, 8)),
          photoTakenAt(DateTime(2026, 11, 17, 13)),
        ],
      );

      final container = await _pumpGallery(
        tester,
        meals: meals,
        photos: photos,
        gallery: gallery,
      );
      final before = container.read(dataRevisionProvider);

      await _tapKey(tester, FoodGalleryKeys.save);

      expect(meals.rows, hasLength(2));
      expect(container.read(dataRevisionProvider), before + 1);
      expect(_snackText(l10n.foodGallerySavedCount(2)), findsOneWidget);
    });

    testWidgets('noSpace during save shows foodNoSpaceTitle SnackBar and '
        'leaves zero photoless rows', (tester) async {
      final l10n = lookupAppLocalizations(const Locale('en'));
      final meals = TestMealStore();
      final gallery = FakeMealGallery(
        photos: [photoTakenAt(DateTime(2026, 11, 17, 8))],
      );

      await _pumpGallery(
        tester,
        meals: meals,
        photos: FullPhotoStore(),
        gallery: gallery,
      );

      await _tapKey(tester, FoodGalleryKeys.save);

      expect(meals.rows, isEmpty);
      expect(_snackText(l10n.foodNoSpaceTitle), findsOneWidget);
    });

    testWidgets('save failure with 0 saved shows foodAddFailed SnackBar', (
      tester,
    ) async {
      final l10n = lookupAppLocalizations(const Locale('en'));
      final meals = TestMealStore();
      final gallery = FakeMealGallery(
        photos: [photoTakenAt(DateTime(2026, 11, 17, 8))],
      );

      await _pumpGallery(
        tester,
        meals: meals,
        photos: _FailingSavePhotoStore(),
        gallery: gallery,
      );

      await _tapKey(tester, FoodGalleryKeys.save);

      expect(meals.rows, isEmpty);
      expect(_snackText(l10n.foodAddFailed), findsOneWidget);
    });
  });

  group('Unmount safety while async pickers are in flight', () {
    testWidgets('unmounting while galleryDateTimePickerProvider is awaiting '
        'throws no exception on disposed WidgetRef', (tester) async {
      final pickerCompleter = Completer<DateTime?>();
      final show = ValueNotifier(true);
      addTearDown(show.dispose);

      await pumpScaled(
        tester,
        screenHost(
          ValueListenableBuilder<bool>(
            valueListenable: show,
            builder: (_, visible, _) => visible
                ? const FoodGalleryScreen()
                : const Scaffold(body: SizedBox.shrink()),
          ),
        ),
        textScaler: TextScaler.noScaling,
        brightness: Brightness.dark,
        locale: const Locale('en'),
        size: const Size(360, 2000),
        overrides: [
          ...foodOverrides(
            meals: TestMealStore(),
            camera: FakeMealCamera(),
            clock: () => _now,
          ),
          mealGalleryProvider.overrideWithValue(
            FakeMealGallery(photos: [returnedPhoto]),
          ),
          galleryDateTimePickerProvider.overrideWithValue(
            (_, {required initial, required lastDate}) =>
                pickerCompleter.future,
          ),
        ],
      );

      await tester.tap(find.byKey(FoodGalleryKeys.pickTime(0)));
      await tester.pump();

      show.value = false;
      await tester.pump();

      pickerCompleter.complete(DateTime(2026, 11, 17, 12, 30));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('unmounting while MealGallery.pickPhotos is awaiting throws '
        'no exception', (tester) async {
      final gallery = _GatedMealGallery();
      final show = ValueNotifier(true);
      addTearDown(show.dispose);

      await pumpScaled(
        tester,
        screenHost(
          ValueListenableBuilder<bool>(
            valueListenable: show,
            builder: (_, visible, _) => visible
                ? const FoodGalleryScreen()
                : const Scaffold(body: SizedBox.shrink()),
          ),
        ),
        textScaler: TextScaler.noScaling,
        brightness: Brightness.dark,
        locale: const Locale('en'),
        size: const Size(360, 2000),
        overrides: [
          ...foodOverrides(
            meals: TestMealStore(),
            camera: FakeMealCamera(),
            clock: () => _now,
          ),
          mealGalleryProvider.overrideWithValue(gallery),
        ],
      );

      expect(gallery.calls, 1);

      show.value = false;
      await tester.pump();

      gallery.complete([photoTakenAt(DateTime(2026, 11, 17, 12, 30))]);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });
}

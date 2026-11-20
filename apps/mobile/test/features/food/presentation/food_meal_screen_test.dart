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
import 'package:open_ring/features/food/application/meal_store_providers.dart';
import 'package:open_ring/features/food/domain/meal.dart';
import 'package:open_ring/features/food/domain/meal_camera.dart';
import 'package:open_ring/features/food/domain/meal_store.dart';
import 'package:open_ring/features/food/domain/photo_store.dart';
import 'package:open_ring/features/food/presentation/food_day_screen.dart';
import 'package:open_ring/features/food/presentation/food_meal_screen.dart';
import 'package:open_ring/features/food/presentation/meal_saved_sheet.dart';
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

final class _ThrowingPhotoStore implements PhotoStore {
  const new();

  @override
  Future<void> save(String name, Uint8List bytes) async {}

  @override
  Future<Uint8List?> read(String name) async =>
      throw const FileSystemException('read failed', 'broken.jpg');

  @override
  Future<bool> delete(String name) async => false;

  @override
  Future<int> deleteAll() async => 0;

  @override
  Future<int> totalBytes() async => 0;
}

final class _SpyPhotoStore implements PhotoStore {
  final inner = InMemoryPhotoStore();
  final List<String> deleteCalls = [];
  final List<bool> rowGoneBeforePhotoDelete = [];
  MealStore? meals;
  int? mealId;

  @override
  Future<void> save(String name, Uint8List bytes) => inner.save(name, bytes);

  @override
  Future<Uint8List?> read(String name) => inner.read(name);

  @override
  Future<bool> delete(String name) async {
    deleteCalls.add(name);
    final store = meals;
    final id = mealId;
    if (store != null && id != null) {
      rowGoneBeforePhotoDelete.add(await store.byId(id) == null);
    }
    return await inner.delete(name);
  }

  @override
  Future<int> deleteAll() => inner.deleteAll();

  @override
  Future<int> totalBytes() => inner.totalBytes();
}

final class _GatedMealStore implements MealStore {
  new(this.inner, {this.gateUpdates = false, this.deleteGate});

  final TestMealStore inner;
  final bool gateUpdates;
  final Completer<void>? deleteGate;
  final List<Completer<void>> updateGates = [];

  @override
  Future<Meal> add(MealDraft draft, {required DateTime now, String? photo}) =>
      inner.add(draft, now: now, photo: photo);

  @override
  Future<bool> update(int id, MealDraft draft) async {
    if (gateUpdates) {
      final gate = Completer<void>();
      updateGates.add(gate);
      await gate.future;
    }
    return await inner.update(id, draft);
  }

  @override
  Future<bool> attachPhoto(int id, String name) => inner.attachPhoto(id, name);

  @override
  Future<Meal?> byId(int id) => inner.byId(id);

  @override
  Future<Meal?> delete(int id) async {
    final gate = deleteGate;
    if (gate != null) await gate.future;
    return await inner.delete(id);
  }

  @override
  Future<List<Meal>> between(LocalDate from, LocalDate to) =>
      inner.between(from, to);

  @override
  Future<int> count() => inner.count();

  @override
  Future<int> clear() => inner.clear();

  @override
  Future<List<String>> deletePhotosBefore(DateTime cutoff) =>
      inner.deletePhotosBefore(cutoff);
}

Future<ProviderContainer> _pumpMealScreen(
  WidgetTester tester, {
  required int? mealId,
  required MealStore meals,
  PhotoStore? photos,
  DateTime Function()? clock,
  MealTimePicker? picker,
  List<Override>? overrides,
}) async {
  await pumpScaled(
    tester,
    screenHost(FoodMealScreen(mealId: mealId)),
    textScaler: TextScaler.noScaling,
    brightness: Brightness.dark,
    locale: const Locale('en'),
    size: const Size(360, 2000),
    overrides:
        overrides ??
        [
          moduleStoreProvider.overrideWithValue(
            InMemoryModuleStore(const {ModuleId.food}),
          ),
          clockProvider.overrideWithValue(clock ?? () => _now),
          mealStoreProvider.overrideWithValue(meals),
          photoStoreProvider.overrideWithValue(photos ?? InMemoryPhotoStore()),
          mealCameraProvider.overrideWithValue(FakeMealCamera()),
          if (picker != null) mealTimePickerProvider.overrideWithValue(picker),
        ],
  );
  return ProviderScope.containerOf(tester.element(find.byType(FoodMealScreen)));
}

Future<void> _tapKey(WidgetTester tester, Key key) async {
  await tester.ensureVisible(find.byKey(key));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(key));
  await tester.pumpAndSettle();
}

Finder _snackText(String text) =>
    find.descendant(of: find.byType(SnackBar), matching: find.text(text));

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));

  group('routes and appRouterProvider', () {
    test('AppPaths.foodMeal and foodMealOf follow the route contract', () {
      expect(AppPaths.foodMeal, '/today/food/meal');
      expect(AppPaths.foodMealOf(42), '/today/food/meal/42');
    });

    testWidgets('appRouterProvider routes /today/food/meal/:id and handles '
        'non-numeric ids as notFound', (tester) async {
      final meals = TestMealStore();
      final meal = meals.seed(DateTime(2026, 11, 17, 12, 30));
      final container = await pumpOnboardingApp(
        tester,
        store: InMemoryOnboardingStore(completed: true),
        at: AppPaths.foodMealOf(meal.id),
        overrides: [
          ...bleOverrides(),
          ...ringOverrides(),
          ...onboardingOverrides(),
          ...foodOverrides(
            meals: meals,
            camera: FakeMealCamera(),
            clock: () => _now,
          ),
        ],
      );

      expect(find.byType(FoodMealScreen), findsOneWidget);
      expect(find.byKey(FoodMealKeys.timeTile), findsOneWidget);
      expect(find.byKey(FoodMealKeys.notFound), findsNothing);

      container.read(appRouterProvider).go('/today/food/meal/not-a-number');
      await tester.pumpAndSettle();

      expect(find.byType(FoodMealScreen), findsOneWidget);
      expect(find.byKey(FoodMealKeys.notFound), findsOneWidget);
    });
  });

  group('MealTagsEditor', () {
    testWidgets('calls onChanged when enabled and disables chips when '
        'onChanged is null', (tester) async {
      final meal = Meal(
        id: 1,
        at: DateTime.utc(2026, 11, 17, 12, 30),
        offsetMinutes: 0,
        createdAt: DateTime.utc(2026, 11, 17, 12, 30),
      );
      MealEdit? changed;

      await pumpScaled(
        tester,
        screenHost(
          Scaffold(
            body: SingleChildScrollView(
              child: MealTagsEditor(
                value: MealEdit.of(meal),
                onChanged: (next) => changed = next,
              ),
            ),
          ),
        ),
        textScaler: TextScaler.noScaling,
        brightness: Brightness.dark,
        locale: const Locale('en'),
      );

      await _tapKey(tester, MealSavedSheetKeys.kind(MealKind.main));
      expect(changed?.kind, MealKind.main);

      changed = null;
      await pumpScaled(
        tester,
        screenHost(
          Scaffold(
            body: SingleChildScrollView(
              child: MealTagsEditor(value: MealEdit.of(meal), onChanged: null),
            ),
          ),
        ),
        textScaler: TextScaler.noScaling,
        brightness: Brightness.dark,
        locale: const Locale('en'),
      );

      final kindChip = tester.widget<ChoiceChip>(
        find.descendant(
          of: find.byKey(MealSavedSheetKeys.kind(MealKind.main)),
          matching: find.byType(ChoiceChip),
        ),
      );
      final flagChip = tester.widget<FilterChip>(
        find.descendant(
          of: find.byKey(MealSavedSheetKeys.flag(MealFlag.protein)),
          matching: find.byType(FilterChip),
        ),
      );
      expect(kindChip.onSelected, isNull);
      expect(flagChip.onSelected, isNull);

      await tester.tap(find.byKey(MealSavedSheetKeys.kind(MealKind.main)));
      await tester.pumpAndSettle();
      expect(changed, isNull);
    });
  });

  group('Food off and missing meal', () {
    testWidgets('off-gate renders empty AppPage and never reads MealStore or '
        'PhotoStore', (tester) async {
      final reads = StoreReads();

      await _pumpMealScreen(
        tester,
        mealId: 1,
        meals: TestMealStore(),
        overrides: [
          moduleStoreProvider.overrideWithValue(InMemoryModuleStore()),
          clockProvider.overrideWithValue(() => _now),
          ...reads.overrides(),
        ],
      );

      expect(find.text(l10n.foodTitle), findsOneWidget);
      expect(find.byKey(FoodMealKeys.notFound), findsNothing);
      expect(find.byKey(FoodMealKeys.timeTile), findsNothing);
      expect(find.byKey(FoodMealKeys.lastMeal), findsNothing);
      expect(find.byKey(FoodMealKeys.kcalTile), findsNothing);
      expect(find.byKey(FoodMealKeys.deleteTile), findsNothing);
      expect(reads.meals, isFalse);
      expect(reads.photos, isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'mealId null or unknown meal id renders FoodMealKeys.notFound',
      (tester) async {
        await _pumpMealScreen(tester, mealId: null, meals: TestMealStore());
        expect(find.byKey(FoodMealKeys.notFound), findsOneWidget);
        expect(find.text(l10n.foodMealNotFound), findsOneWidget);

        await _pumpMealScreen(tester, mealId: 999, meals: TestMealStore());
        expect(find.byKey(FoodMealKeys.notFound), findsOneWidget);
        expect(find.text(l10n.foodMealNotFound), findsOneWidget);
      },
    );
  });

  group('photo card', () {
    testWidgets('null photo shows FoodMealKeys.noPhoto', (tester) async {
      final meals = TestMealStore();
      final meal = meals.seed(DateTime(2026, 11, 17, 12, 30));

      await _pumpMealScreen(tester, mealId: meal.id, meals: meals);

      expect(find.byKey(FoodMealKeys.noPhoto), findsOneWidget);
      expect(find.text(l10n.foodNoPhoto), findsOneWidget);
      expect(find.byKey(FoodMealKeys.photo), findsNothing);
    });

    testWidgets(
      'valid JPEG renders Image with ResizeImage 1024 and cover fit',
      (tester) async {
        final meals = TestMealStore();
        final photos = InMemoryPhotoStore();
        await photos.save('meal_1.jpg', strippedPlain());
        final meal = meals.seed(DateTime(2026, 11, 17, 12, 30));
        await meals.attachPhoto(meal.id, 'meal_1.jpg');

        await _pumpMealScreen(
          tester,
          mealId: meal.id,
          meals: meals,
          photos: photos,
        );

        final image = tester.widget<Image>(find.byKey(FoodMealKeys.photo));
        expect(image.fit, BoxFit.cover);
        expect(
          image.image,
          isA<ResizeImage>().having((r) => r.width, 'width', 1024),
        );
        expect(find.byKey(FoodMealKeys.missingPhoto), findsNothing);
      },
    );

    testWidgets('missing, throwing read, or corrupt photo bytes fall back to '
        'FoodMealKeys.missingPhoto with Image unmounted', (tester) async {
      final meals = TestMealStore();
      final missing = meals.seed(DateTime(2026, 11, 17, 12, 30));
      await meals.attachPhoto(missing.id, 'missing.jpg');

      await _pumpMealScreen(tester, mealId: missing.id, meals: meals);
      expect(find.byKey(FoodMealKeys.missingPhoto), findsOneWidget);
      expect(find.text(l10n.foodPhotoMissing), findsOneWidget);
      expect(find.byKey(FoodMealKeys.photo), findsNothing);
      expect(tester.takeException(), isNull);

      await _pumpMealScreen(
        tester,
        mealId: missing.id,
        meals: meals,
        photos: const _ThrowingPhotoStore(),
      );
      expect(find.byKey(FoodMealKeys.missingPhoto), findsOneWidget);
      expect(find.byKey(FoodMealKeys.photo), findsNothing);
      expect(tester.takeException(), isNull);

      final corruptPhotos = InMemoryPhotoStore();
      await corruptPhotos.save(
        'corrupt.jpg',
        Uint8List.fromList(const [0, 1, 2, 3]),
      );
      final corrupt = meals.seed(DateTime(2026, 11, 17, 14));
      await meals.attachPhoto(corrupt.id, 'corrupt.jpg');

      await _pumpMealScreen(
        tester,
        mealId: corrupt.id,
        meals: meals,
        photos: corruptPhotos,
      );
      await tester.pumpAndSettle();

      expect(find.byKey(FoodMealKeys.missingPhoto), findsOneWidget);
      expect(find.byKey(FoodMealKeys.photo), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('time tile', () {
    testWidgets('shows clock, hint, footer; cancel or unchanged writes 0 '
        'updates; valid updates time and bumps revision once', (tester) async {
      final meals = TestMealStore();
      final meal = meals.seed(DateTime(2026, 11, 17, 12, 30));
      TimeOfDay? picked;
      TimeOfDay? capturedInitial;

      final container = await _pumpMealScreen(
        tester,
        mealId: meal.id,
        meals: meals,
        picker: (_, initial) async {
          capturedInitial = initial;
          return picked;
        },
      );
      final before = container.read(dataRevisionProvider);

      expect(find.text('12:30'), findsOneWidget);
      expect(find.text(l10n.foodMealTimeHint), findsOneWidget);
      expect(find.text(l10n.foodMealFoot), findsOneWidget);

      await _tapKey(tester, FoodMealKeys.timeTile);
      expect(capturedInitial, const TimeOfDay(hour: 12, minute: 30));
      expect(meals.updates, 0);
      expect(container.read(dataRevisionProvider), before);

      picked = const TimeOfDay(hour: 12, minute: 30);
      await _tapKey(tester, FoodMealKeys.timeTile);
      expect(meals.updates, 0);
      expect(container.read(dataRevisionProvider), before);

      picked = const TimeOfDay(hour: 14, minute: 15);
      await _tapKey(tester, FoodMealKeys.timeTile);
      expect(meals.updates, 1);
      expect(container.read(dataRevisionProvider), before + 1);
      expect(find.text('14:15'), findsOneWidget);
    });

    testWidgets('time before 05:00 stays on the meal food day', (tester) async {
      final meals = TestMealStore();
      final meal = meals.seed(DateTime(2026, 11, 17, 19, 30));
      final container = await _pumpMealScreen(
        tester,
        mealId: meal.id,
        meals: meals,
        clock: () => DateTime(2026, 11, 18, 1),
        picker: (_, _) async => const TimeOfDay(hour: 0, minute: 30),
      );
      final before = container.read(dataRevisionProvider);

      await _tapKey(tester, FoodMealKeys.timeTile);

      expect(meals.updates, 1);
      expect(container.read(dataRevisionProvider), before + 1);
      expect(
        foodDay(meals.rows.single.entry.at),
        const LocalDate(2026, 11, 17),
      );
      expect(meals.rows.single.entry.at, DateTime.utc(2026, 11, 18, 0, 30));
      expect(find.text('00:30'), findsOneWidget);
    });

    testWidgets('future time and update failure show SnackBars without bumping '
        'revision', (tester) async {
      final meals = TestMealStore();
      final meal = meals.seed(DateTime(2026, 11, 17, 12, 30));
      var picked = const TimeOfDay(hour: 21, minute: 5);
      final container = await _pumpMealScreen(
        tester,
        mealId: meal.id,
        meals: meals,
        picker: (_, _) async => picked,
      );
      final before = container.read(dataRevisionProvider);

      await _tapKey(tester, FoodMealKeys.timeTile);
      expect(_snackText(l10n.foodAddFutureError), findsOneWidget);
      expect(meals.updates, 0);
      expect(container.read(dataRevisionProvider), before);

      picked = const TimeOfDay(hour: 13, minute: 0);
      meals.updateError = Exception('disk error');
      await _tapKey(tester, FoodMealKeys.timeTile);
      expect(_snackText(l10n.foodMealTimeFailed), findsOneWidget);
      expect(meals.updates, 1);
      expect(container.read(dataRevisionProvider), before);
    });
  });

  group('live tags and last meal switch', () {
    testWidgets('rapid sequential taps coalesce cleanly and preserve all '
        'edits', (tester) async {
      final inner = TestMealStore();
      final meal = inner.seed(DateTime(2026, 11, 17, 12, 30));
      final gated = _GatedMealStore(inner, gateUpdates: true);

      final container = await _pumpMealScreen(
        tester,
        mealId: meal.id,
        meals: gated,
      );
      final before = container.read(dataRevisionProvider);

      expect(find.text(l10n.foodMealTagsTitle), findsOneWidget);
      expect(find.text(l10n.foodMealTagsHint), findsOneWidget);
      expect(find.text(l10n.foodLastTitle), findsOneWidget);
      expect(find.text(l10n.foodLastHint), findsOneWidget);

      await tester.ensureVisible(
        find.byKey(MealSavedSheetKeys.kind(MealKind.main)),
      );
      await tester.tap(find.byKey(MealSavedSheetKeys.kind(MealKind.main)));
      await tester.pump();
      await tester.ensureVisible(
        find.byKey(MealSavedSheetKeys.flag(MealFlag.protein)),
      );
      await tester.tap(find.byKey(MealSavedSheetKeys.flag(MealFlag.protein)));
      await tester.pump();
      await tester.ensureVisible(find.byKey(FoodMealKeys.lastMeal));
      await tester.tap(find.byKey(FoodMealKeys.lastMeal));
      await tester.pump();

      var completed = 0;
      while (completed < gated.updateGates.length) {
        gated.updateGates[completed++].complete();
        await tester.pumpAndSettle();
      }

      expect(inner.rows.single.kind, MealKind.main);
      expect(inner.rows.single.tags.protein, isTrue);
      expect(inner.rows.single.last, isTrue);
      expect(container.read(dataRevisionProvider), greaterThan(before));
    });

    testWidgets('failed tag or switch write shows foodTagsFailed SnackBar and '
        'reverts UI without bumping revision', (tester) async {
      final meals = TestMealStore();
      final meal = meals.seed(DateTime(2026, 11, 17, 12, 30));
      final container = await _pumpMealScreen(
        tester,
        mealId: meal.id,
        meals: meals,
      );
      final before = container.read(dataRevisionProvider);

      meals.updateError = Exception('write failed');
      await _tapKey(tester, MealSavedSheetKeys.kind(MealKind.main));

      expect(_snackText(l10n.foodTagsFailed), findsOneWidget);
      expect(container.read(dataRevisionProvider), before);
      expect(
        tester
            .widget<ChoiceChip>(
              find.descendant(
                of: find.byKey(MealSavedSheetKeys.kind(MealKind.main)),
                matching: find.byType(ChoiceChip),
              ),
            )
            .selected,
        isFalse,
      );

      await _tapKey(tester, FoodMealKeys.lastMeal);

      expect(_snackText(l10n.foodTagsFailed), findsOneWidget);
      expect(container.read(dataRevisionProvider), before);
      expect(
        tester.widget<SwitchListTile>(find.byKey(FoodMealKeys.lastMeal)).value,
        isFalse,
      );
    });
  });

  group('kcal refusal tile and sheet', () {
    testWidgets('opens refusal copy sheet with zero kcal or calorie digits '
        'and dismisses on Close', (tester) async {
      final meals = TestMealStore();
      final meal = meals.seed(DateTime(2026, 11, 17, 12, 30));
      await _pumpMealScreen(tester, mealId: meal.id, meals: meals);

      expect(find.text(l10n.foodMealKcalTile), findsOneWidget);
      expect(find.text(l10n.foodMealKcalTileHint), findsOneWidget);

      await _tapKey(tester, FoodMealKeys.kcalTile);

      expect(find.byKey(FoodMealKeys.kcalSheet), findsOneWidget);
      expect(find.text(l10n.foodMealKcalTitle), findsOneWidget);
      expect(find.text(l10n.foodMealKcalBody), findsOneWidget);
      expect(find.text(l10n.foodMealKcalNoCount), findsOneWidget);
      expect(find.text(l10n.foodMealKcalInstead), findsOneWidget);

      final renderedTexts = [
        for (final text in tester.widgetList<Text>(find.byType(Text)))
          text.data ?? '',
      ];
      final sheetTexts = [
        for (final text in tester.widgetList<Text>(
          find.descendant(
            of: find.byKey(FoodMealKeys.kcalSheet),
            matching: find.byType(Text),
          ),
        ))
          text.data ?? '',
      ];
      expect(
        renderedTexts.any((t) => t.toLowerCase().contains('kcal')),
        isFalse,
      );
      expect(sheetTexts.where((t) => RegExp(r'\d').hasMatch(t)), isEmpty);
      expect(renderedTexts.where((t) => RegExp(r'\d').hasMatch(t)), [
        '12:30',
        l10n.foodAlcoholOneToTwo,
        l10n.foodAlcoholThreeOrMore,
      ]);

      await _tapKey(tester, FoodMealKeys.kcalClose);
      expect(find.byKey(FoodMealKeys.kcalSheet), findsNothing);
    });
  });

  group('delete tile and sheet', () {
    testWidgets('cancel deletes nothing; confirm deletes row first then '
        'photo, pops back to FoodDayScreen in GoRouter', (tester) async {
      final meals = TestMealStore();
      final photos = _SpyPhotoStore();
      await photos.save('meal_1.jpg', strippedPlain());
      final meal = meals.seed(DateTime(2026, 11, 17, 12, 30));
      await meals.attachPhoto(meal.id, 'meal_1.jpg');
      photos
        ..meals = meals
        ..mealId = meal.id;

      final container = await pumpOnboardingApp(
        tester,
        store: InMemoryOnboardingStore(completed: true),
        at: AppPaths.food,
        overrides: [
          ...bleOverrides(),
          ...ringOverrides(),
          ...onboardingOverrides(),
          ...foodOverrides(
            meals: meals,
            photos: photos,
            camera: FakeMealCamera(),
            clock: () => _now,
          ),
        ],
      );
      await _tapKey(tester, FoodDayKeys.meal(meal.id));
      expect(find.byType(FoodMealScreen), findsOneWidget);

      await _tapKey(tester, FoodMealKeys.deleteTile);
      expect(find.byKey(FoodMealKeys.deleteSheet), findsOneWidget);
      expect(find.text(l10n.foodMealDeleteTitle), findsOneWidget);
      expect(find.text(l10n.foodMealDeleteBody), findsOneWidget);

      await _tapKey(tester, FoodMealKeys.deleteCancel);
      expect(find.byKey(FoodMealKeys.deleteSheet), findsNothing);
      expect(meals.deletes, 0);
      expect(meals.rows, hasLength(1));

      final before = container.read(dataRevisionProvider);
      await _tapKey(tester, FoodMealKeys.deleteTile);
      await _tapKey(tester, FoodMealKeys.deleteConfirm);

      expect(meals.deletes, 1);
      expect(meals.rows, isEmpty);
      expect(photos.deleteCalls, ['meal_1.jpg']);
      expect(photos.rowGoneBeforePhotoDelete, [true]);
      expect(await photos.read('meal_1.jpg'), isNull);
      expect(container.read(dataRevisionProvider), before + 1);
      expect(find.byType(FoodMealScreen), findsNothing);
      expect(find.byType(FoodDayScreen), findsOneWidget);
      expect(find.byKey(FoodDayKeys.meal(meal.id)), findsNothing);
    });

    testWidgets('double-tap guard allows only one delete while in flight', (
      tester,
    ) async {
      final inner = TestMealStore();
      final meal = inner.seed(DateTime(2026, 11, 17, 12, 30));
      final gate = Completer<void>();
      final gated = _GatedMealStore(inner, deleteGate: gate);

      await _pumpMealScreen(tester, mealId: meal.id, meals: gated);
      await _tapKey(tester, FoodMealKeys.deleteTile);

      await tester.ensureVisible(find.byKey(FoodMealKeys.deleteConfirm));
      await tester.tap(find.byKey(FoodMealKeys.deleteConfirm));
      await tester.pump();
      await tester.tap(
        find.byKey(FoodMealKeys.deleteConfirm),
        warnIfMissed: false,
      );
      await tester.pump();

      gate.complete();
      await tester.pumpAndSettle();

      expect(inner.deletes, 1);
      expect(find.byKey(FoodMealKeys.notFound), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('delete failure shows foodMealDeleteFailed SnackBar and keeps '
        'screen open', (tester) async {
      final meals = TestMealStore();
      final meal = meals.seed(DateTime(2026, 11, 17, 12, 30));
      final container = await _pumpMealScreen(
        tester,
        mealId: meal.id,
        meals: meals,
      );
      final before = container.read(dataRevisionProvider);

      meals.deleteError = Exception('db locked');
      await _tapKey(tester, FoodMealKeys.deleteTile);
      await _tapKey(tester, FoodMealKeys.deleteConfirm);

      expect(find.byType(FoodMealScreen), findsOneWidget);
      expect(find.byKey(FoodMealKeys.deleteTile), findsOneWidget);
      expect(_snackText(l10n.foodMealDeleteFailed), findsOneWidget);
      expect(container.read(dataRevisionProvider), before);
    });
  });

  group('unmount safety', () {
    testWidgets('unmounting while picker, update, or delete awaits throws no '
        'exception', (tester) async {
      Future<void> runUnmount(
        WidgetTester tester, {
        required Future<void> Function(ValueNotifier<bool> show) action,
      }) async {
        final inner = TestMealStore();
        final meal = inner.seed(DateTime(2026, 11, 17, 12, 30));
        final pickerGate = Completer<TimeOfDay?>();
        final deleteGate = Completer<void>();
        final gated = _GatedMealStore(
          inner,
          gateUpdates: true,
          deleteGate: deleteGate,
        );
        final show = ValueNotifier(true);
        addTearDown(show.dispose);

        await pumpScaled(
          tester,
          screenHost(
            ValueListenableBuilder<bool>(
              valueListenable: show,
              builder: (_, visible, _) => visible
                  ? FoodMealScreen(mealId: meal.id)
                  : const Scaffold(body: SizedBox.shrink()),
            ),
          ),
          textScaler: TextScaler.noScaling,
          brightness: Brightness.dark,
          locale: const Locale('en'),
          size: const Size(360, 2000),
          overrides: [
            moduleStoreProvider.overrideWithValue(
              InMemoryModuleStore(const {ModuleId.food}),
            ),
            clockProvider.overrideWithValue(() => _now),
            mealStoreProvider.overrideWithValue(gated),
            photoStoreProvider.overrideWithValue(InMemoryPhotoStore()),
            mealCameraProvider.overrideWithValue(FakeMealCamera()),
            mealTimePickerProvider.overrideWithValue(
              (_, _) => pickerGate.future,
            ),
          ],
        );

        await action(show);

        if (!pickerGate.isCompleted) {
          pickerGate.complete(const TimeOfDay(hour: 13, minute: 0));
        }
        for (final gate in gated.updateGates) {
          if (!gate.isCompleted) gate.complete();
        }
        if (!deleteGate.isCompleted) deleteGate.complete();
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      }

      await runUnmount(
        tester,
        action: (show) async {
          await tester.ensureVisible(find.byKey(FoodMealKeys.timeTile));
          await tester.tap(find.byKey(FoodMealKeys.timeTile));
          await tester.pump();
          show.value = false;
          await tester.pump();
        },
      );

      await runUnmount(
        tester,
        action: (show) async {
          await tester.ensureVisible(
            find.byKey(MealSavedSheetKeys.kind(MealKind.main)),
          );
          await tester.tap(find.byKey(MealSavedSheetKeys.kind(MealKind.main)));
          await tester.pump();
          show.value = false;
          await tester.pump();
        },
      );

      await runUnmount(
        tester,
        action: (show) async {
          await _tapKey(tester, FoodMealKeys.deleteTile);
          await tester.ensureVisible(find.byKey(FoodMealKeys.deleteConfirm));
          await tester.tap(find.byKey(FoodMealKeys.deleteConfirm));
          await tester.pump();
          show.value = false;
          await tester.pump();
        },
      );
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/core/records/data_revision.dart';
import 'package:open_ring/features/food/application/meal_recovery.dart';
import 'package:open_ring/features/food/domain/meal_camera.dart';
import 'package:open_ring/features/food/domain/photo_store.dart';
import 'package:open_ring/features/food/presentation/food_row.dart';
import 'package:open_ring/features/food/presentation/meal_saved_sheet.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';
import 'package:open_ring/features/modules/domain/module_store.dart';

import '../../../helpers/layout_harness.dart';
import '../food_fakes.dart';

final _lunch = DateTime(2026, 11, 17, 12, 30);

Widget _rowHost() => screenHost(
  const Scaffold(body: SingleChildScrollView(child: FoodRowSlot())),
);

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required List<Override> overrides,
  Widget? host,
}) async {
  await pumpScaled(
    tester,
    host ?? _rowHost(),
    textScaler: TextScaler.noScaling,
    brightness: Brightness.dark,
    locale: const Locale('en'),
    overrides: overrides,
  );
  return ProviderScope.containerOf(tester.element(find.byType(Scaffold)));
}

Future<ProviderContainer> _pumpRow(
  WidgetTester tester,
  TestMealStore meals, {
  MealCamera? camera,
  PhotoStore? photos,
  DateTime Function()? clock,
}) => _pump(
  tester,
  overrides: foodOverrides(
    meals: meals,
    camera: camera ?? FakeMealCamera(photo: returnedPhoto),
    photos: photos,
    clock: clock ?? () => _lunch,
  ),
);

Future<void> _tapCamera(WidgetTester tester) async {
  await tester.tap(find.byKey(FoodRowKeys.camera));
  await tester.pumpAndSettle();
}

Future<void> _tapKey(WidgetTester tester, Key key) async {
  await tester.ensureVisible(find.byKey(key));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(key));
  await tester.pumpAndSettle();
}

Future<void> _back(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
}

Finder _inRow(Finder matching) =>
    find.descendant(of: find.byKey(FoodRowKeys.row), matching: matching);

Finder _inSavedSheet(Finder matching) =>
    find.descendant(of: find.byType(MealSavedSheet), matching: matching);

Set<String> _savedSheetTexts(WidgetTester tester) => {
  for (final text in tester.widgetList<RichText>(
    _inSavedSheet(find.byType(RichText)),
  ))
    text.text.toPlainText(),
};

int _revision(ProviderContainer container) =>
    container.read(dataRevisionProvider);

void main() {
  group('criterion 1: Food off', () {
    testWidgets('shows no row and builds no meal store', (tester) async {
      final reads = StoreReads();

      await _pump(
        tester,
        overrides: [
          moduleStoreProvider.overrideWithValue(InMemoryModuleStore()),
          clockProvider.overrideWithValue(() => _lunch),
          ...reads.overrides(),
        ],
      );

      expect(find.byKey(FoodRowKeys.row), findsNothing);
      expect(find.byKey(FoodRowKeys.camera), findsNothing);
      expect(reads.any, isFalse, reason: 'the row must not read the stores');
      expect(tester.takeException(), isNull);
    });
  });

  group('D3: the row', () {
    testWidgets('with Food on shows the row and its camera button', (
      tester,
    ) async {
      await _pumpRow(tester, TestMealStore());

      expect(find.byKey(FoodRowKeys.row), findsOneWidget);
      expect(find.byKey(FoodRowKeys.camera), findsOneWidget);
      expect(find.byKey(FoodRowKeys.saving), findsNothing);
    });

    testWidgets('with no meal says so', (tester) async {
      await _pumpRow(tester, TestMealStore());

      expect(_inRow(find.text('No meals today')), findsOneWidget);
    });

    testWidgets('counts the meals and names the window start', (tester) async {
      final meals = TestMealStore()
        ..seed(DateTime(2026, 11, 17, 7, 10), kind: MealKind.drink)
        ..seed(DateTime(2026, 11, 17, 12, 30), kind: MealKind.main);

      await _pumpRow(tester, meals, clock: () => DateTime(2026, 11, 17, 13));

      expect(_inRow(find.textContaining('2 today')), findsOneWidget);
      expect(_inRow(find.textContaining('12:30')), findsOneWidget);
      expect(_inRow(find.textContaining('07:10')), findsNothing);
    });

    testWidgets('with only plain drinks shows the count and no window', (
      tester,
    ) async {
      final meals = TestMealStore()
        ..seed(DateTime(2026, 11, 17, 7, 10), kind: MealKind.drink);

      await _pumpRow(tester, meals, clock: () => DateTime(2026, 11, 17, 13));

      expect(_inRow(find.textContaining('1 today')), findsOneWidget);
      expect(_inRow(find.textContaining('07:10')), findsNothing);
    });

    testWidgets('a bump of dataRevision refreshes the count', (tester) async {
      final meals = TestMealStore();
      final container = await _pumpRow(tester, meals);

      meals.seed(DateTime(2026, 11, 17, 12), kind: MealKind.main);
      container.read(dataRevisionProvider.notifier).bump();
      await tester.pumpAndSettle();

      expect(_inRow(find.textContaining('1 today')), findsOneWidget);
    });

    testWidgets('rolls at 05:00 with no resume', (tester) async {
      var now = DateTime(2026, 11, 18, 4, 50);
      final meals = TestMealStore()
        ..seed(DateTime(2026, 11, 17, 21), kind: MealKind.main);
      await _pumpRow(tester, meals, clock: () => now);
      expect(_inRow(find.textContaining('1 today')), findsOneWidget);

      now = DateTime(2026, 11, 18, 5, 10);
      await tester.pump(const Duration(minutes: 21));
      await tester.pumpAndSettle();

      expect(_inRow(find.text('No meals today')), findsOneWidget);
    });

    testWidgets('a resume after 05:00 refreshes the day', (tester) async {
      var now = DateTime(2026, 11, 18, 4, 50);
      final meals = TestMealStore()
        ..seed(DateTime(2026, 11, 17, 21), kind: MealKind.main);
      await _pumpRow(tester, meals, clock: () => now);
      // AppLifecycleListener asserts each step, so walk them as Android does.
      tester.binding
        ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
        ..handleAppLifecycleStateChanged(AppLifecycleState.hidden)
        ..handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();

      now = DateTime(2026, 11, 18, 5, 10);
      tester.binding
        ..handleAppLifecycleStateChanged(AppLifecycleState.hidden)
        ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
        ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(_inRow(find.text('No meals today')), findsOneWidget);
    });
  });

  group('criterion 3: a saved photo', () {
    testWidgets('writes 1 row, bumps once and the sheet shows the time', (
      tester,
    ) async {
      final meals = TestMealStore();
      final container = await _pumpRow(tester, meals);

      await _tapCamera(tester);

      expect(find.byType(MealSavedSheet), findsOneWidget);
      expect(_inSavedSheet(find.textContaining('12:30')), findsWidgets);
      expect(meals.rows, hasLength(1));
      expect(meals.rows.single.photo, isNotNull);
      expect(_revision(container), 1);
    });

    testWidgets('the returned time adds a line the photo time does not', (
      tester,
    ) async {
      final camera = FakeMealCamera(photo: photoTakenAt(_lunch));
      await _pumpRow(tester, TestMealStore(), camera: camera);
      await _tapCamera(tester);
      final fromPhoto = _savedSheetTexts(tester);
      await _tapKey(tester, MealSavedSheetKeys.done);

      camera.photo = returnedPhoto;
      await _tapCamera(tester);
      final returned = _savedSheetTexts(tester);

      expect(fromPhoto, isNotEmpty);
      expect(returned.difference(fromPhoto), isNotEmpty);
      expect(fromPhoto.difference(returned), isEmpty);
    });

    testWidgets('the row counts the saved meal', (tester) async {
      await _pumpRow(tester, TestMealStore());

      await _tapCamera(tester);
      await _tapKey(tester, MealSavedSheetKeys.done);

      expect(_inRow(find.textContaining('1 today')), findsOneWidget);
    });
  });

  group('criterion 4: a cancelled capture', () {
    testWidgets('leaves 0 rows, no bump, no sheet and is not saving', (
      tester,
    ) async {
      final meals = TestMealStore();
      final container = await _pumpRow(tester, meals, camera: FakeMealCamera());

      await _tapCamera(tester);

      expect(meals.rows, isEmpty);
      expect(_revision(container), 0);
      expect(find.byType(MealSavedSheet), findsNothing);
      expect(find.byType(MealNoSpaceSheet), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.byKey(FoodRowKeys.saving), findsNothing);
    });
  });

  group('criterion 5: a second tap while saving', () {
    testWidgets('calls takePhoto once', (tester) async {
      final camera = GatedMealCamera();
      final meals = TestMealStore();
      await _pumpRow(tester, meals, camera: camera);

      await tester.tap(find.byKey(FoodRowKeys.camera));
      await tester.pump();
      expect(find.byKey(FoodRowKeys.saving), findsOneWidget);
      await tester.tap(find.byKey(FoodRowKeys.camera), warnIfMissed: false);
      await tester.pump();
      camera.open(returnedPhoto);
      await tester.pumpAndSettle();

      expect(camera.takes, 1);
      expect(meals.rows, hasLength(1));
      expect(find.byKey(FoodRowKeys.saving), findsNothing);
    });
  });

  group('criterion 6: a full disk', () {
    late TestMealStore meals;
    late FullPhotoStore full;

    setUp(() {
      meals = TestMealStore();
      full = FullPhotoStore();
    });

    Future<ProviderContainer> openNoSpace(WidgetTester tester) async {
      final container = await _pumpRow(tester, meals, photos: full);
      await _tapCamera(tester);
      expect(find.byType(MealNoSpaceSheet), findsOneWidget);
      expect(meals.rows.single.photo, isNull);
      return container;
    }

    testWidgets('Retry attaches the photo and bumps', (tester) async {
      final container = await openNoSpace(tester);
      final before = _revision(container);
      full.full = false;

      await _tapKey(tester, MealSavedSheetKeys.retry);

      final name = meals.rows.single.photo;
      expect(name, isNotNull);
      expect(await full.inner.read(name!), isNotNull);
      expect(_revision(container), greaterThan(before));
      expect(find.byType(MealNoSpaceSheet), findsNothing);
    });

    testWidgets('Without photo keeps the row photoless, bumped by the save', (
      tester,
    ) async {
      final container = await openNoSpace(tester);

      await _tapKey(tester, MealSavedSheetKeys.withoutPhoto);

      expect(meals.rows, hasLength(1));
      expect(meals.rows.single.photo, isNull);
      expect(await full.inner.totalBytes(), 0);
      expect(_revision(container), greaterThan(0));
      expect(find.byType(MealNoSpaceSheet), findsNothing);
    });

    testWidgets('Discard leaves 0 rows and bumps', (tester) async {
      final container = await openNoSpace(tester);
      final before = _revision(container);

      await _tapKey(tester, MealSavedSheetKeys.discard);

      expect(meals.rows, isEmpty);
      expect(_revision(container), greaterThan(before));
      expect(find.byType(MealNoSpaceSheet), findsNothing);
      expect(find.byType(MealSavedSheet), findsNothing);
    });
  });

  group('criterion 7: a capture that fails', () {
    final cases = <String, MealCamera Function()>{
      'a camera that throws': ThrowingMealCamera.new,
      'a photo that is not a JPEG': () => FakeMealCamera(photo: notAJpeg),
    };
    for (final MapEntry(key: name, value: camera) in cases.entries) {
      testWidgets('$name shows a SnackBar and leaves 0 rows', (tester) async {
        final meals = TestMealStore();
        await _pumpRow(tester, meals, camera: camera());

        await tester.tap(find.byKey(FoodRowKeys.camera));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 750));

        expect(find.byType(SnackBar), findsOneWidget);
        expect(meals.rows, isEmpty);
        expect(find.byType(MealSavedSheet), findsNothing);
        expect(find.byType(MealNoSpaceSheet), findsNothing);
        expect(find.byKey(FoodRowKeys.saving), findsNothing);
      });
    }

    testWidgets('a camera that throws twice shows a SnackBar both times', (
      tester,
    ) async {
      final meals = TestMealStore();
      await _pumpRow(tester, meals, camera: ThrowingMealCamera());

      for (var tap = 1; tap <= 2; tap++) {
        await tester.tap(find.byKey(FoodRowKeys.camera));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 750));

        expect(find.byType(SnackBar), findsOneWidget, reason: 'tap $tap');
        tester
            .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger))
            .hideCurrentSnackBar();
        await tester.pumpAndSettle();
        expect(find.byType(SnackBar), findsNothing, reason: 'tap $tap');
      }
      expect(meals.rows, isEmpty);
    });
  });

  group('criterion 8: the last meal switch', () {
    final dismissals = <String, Future<void> Function(WidgetTester)>{
      'back': _back,
      'Done': (tester) => _tapKey(tester, MealSavedSheetKeys.done),
    };
    for (final MapEntry(key: name, value: dismiss) in dismissals.entries) {
      testWidgets('switch on, then $name: last=true, one write, one bump', (
        tester,
      ) async {
        final meals = TestMealStore();
        final container = await _pumpRow(tester, meals);
        await _tapCamera(tester);
        final before = _revision(container);

        await _tapKey(tester, MealSavedSheetKeys.last);
        await dismiss(tester);

        expect(find.byType(MealSavedSheet), findsNothing);
        expect(meals.rows.single.last, isTrue);
        expect(meals.updates, 1);
        expect(_revision(container), before + 1);
      });

      testWidgets('untouched, then $name: no write and no bump', (
        tester,
      ) async {
        final meals = TestMealStore();
        final container = await _pumpRow(tester, meals);
        await _tapCamera(tester);
        final before = _revision(container);

        await dismiss(tester);

        expect(find.byType(MealSavedSheet), findsNothing);
        expect(meals.rows.single.last, isFalse);
        expect(meals.updates, 0);
        expect(_revision(container), before);
      });
    }

    testWidgets('the switch starts off', (tester) async {
      await _pumpRow(tester, TestMealStore());
      await _tapCamera(tester);

      expect(
        tester
            .widget<Switch>(
              find.descendant(
                of: find.byKey(MealSavedSheetKeys.last),
                matching: find.byType(Switch),
                matchRoot: true,
              ),
            )
            .value,
        isFalse,
      );
    });
  });

  group('criterion 9: a recovered photo', () {
    testWidgets('opens the saved sheet with the recovered note', (
      tester,
    ) async {
      final camera = FakeMealCamera(photo: returnedPhoto);
      final container = await _pumpRow(tester, TestMealStore(), camera: camera);
      await _tapCamera(tester);
      final taken = _savedSheetTexts(tester);
      await _tapKey(tester, MealSavedSheetKeys.done);

      camera.lost = returnedPhoto;
      await container.read(mealRecoveryProvider.notifier).run();
      await tester.pumpAndSettle();

      expect(find.byType(MealSavedSheet), findsOneWidget);
      expect(_savedSheetTexts(tester).difference(taken), isNotEmpty);
    });

    testWidgets('a recovery that lands before the row is shown opens the '
        'sheet when it appears', (tester) async {
      final show = ValueNotifier(false);
      addTearDown(show.dispose);
      final meals = TestMealStore();
      final container = await _pump(
        tester,
        overrides: foodOverrides(
          meals: meals,
          camera: FakeMealCamera(lost: returnedPhoto),
          clock: () => _lunch,
        ),
        host: screenHost(
          Scaffold(
            body: ValueListenableBuilder<bool>(
              valueListenable: show,
              builder: (_, visible, _) => visible
                  ? const SingleChildScrollView(child: FoodRowSlot())
                  : const SizedBox.shrink(),
            ),
          ),
        ),
      );

      await container.read(mealRecoveryProvider.notifier).run();
      await tester.pumpAndSettle();
      show.value = true;
      await tester.pumpAndSettle();

      expect(meals.rows, hasLength(1));
      expect(find.byType(MealSavedSheet), findsOneWidget);
    });

    testWidgets('a remounted row opens the recovered sheet only once', (
      tester,
    ) async {
      final mount = ValueNotifier(0);
      addTearDown(mount.dispose);
      final meals = TestMealStore();
      final container = await _pump(
        tester,
        overrides: foodOverrides(
          meals: meals,
          camera: FakeMealCamera(lost: returnedPhoto),
          clock: () => _lunch,
        ),
        host: screenHost(
          Scaffold(
            body: ValueListenableBuilder<int>(
              valueListenable: mount,
              builder: (_, generation, _) => SingleChildScrollView(
                child: FoodRowSlot(key: ValueKey(generation)),
              ),
            ),
          ),
        ),
      );
      await container.read(mealRecoveryProvider.notifier).run();
      await tester.pumpAndSettle();
      expect(find.byType(MealSavedSheet), findsOneWidget);

      mount.value++;
      container.read(dataRevisionProvider.notifier).bump();
      await tester.pumpAndSettle();
      expect(find.byType(MealSavedSheet), findsOneWidget);

      await _tapKey(tester, MealSavedSheetKeys.done);
      mount.value++;
      await tester.pumpAndSettle();

      expect(find.byType(MealSavedSheet), findsNothing);
      expect(meals.rows, hasLength(1));
    });

    testWidgets('a recovery on a full disk opens the no space sheet', (
      tester,
    ) async {
      final meals = TestMealStore();
      final container = await _pumpRow(
        tester,
        meals,
        camera: FakeMealCamera(lost: returnedPhoto),
        photos: FullPhotoStore(),
      );

      await container.read(mealRecoveryProvider.notifier).run();
      await tester.pumpAndSettle();

      expect(find.byType(MealNoSpaceSheet), findsOneWidget);
      expect(meals.rows.single.photo, isNull);
    });
  });
}

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/l10n/app_locales.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/theme/app_theme.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/core/records/data_revision.dart';
import 'package:open_ring/features/food/application/meal_photo_saver.dart';
import 'package:open_ring/features/food/application/meal_store_providers.dart';
import 'package:open_ring/features/food/domain/meal.dart';
import 'package:open_ring/features/food/domain/meal_camera.dart';
import 'package:open_ring/features/food/domain/meal_store.dart';
import 'package:open_ring/features/food/domain/photo_store.dart';
import 'package:open_ring/features/food/presentation/food_day_screen.dart';
import 'package:open_ring/features/food/presentation/food_row.dart';
import 'package:open_ring/features/food/presentation/meal_capture_presenter.dart';
import 'package:open_ring/features/food/presentation/meal_saved_sheet.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/modules/domain/module_store.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

import '../../../helpers/layout_harness.dart';
import '../food_fakes.dart';

final _now = DateTime(2026, 11, 17, 21);

List<Override> _customStoreOverrides(
  MealStore meals, {
  required DateTime Function() clock,
}) => [
  moduleStoreProvider.overrideWithValue(
    InMemoryModuleStore(const {ModuleId.food}),
  ),
  clockProvider.overrideWithValue(clock),
  mealStoreProvider.overrideWithValue(meals),
  photoStoreProvider.overrideWithValue(InMemoryPhotoStore()),
  mealCameraProvider.overrideWithValue(FakeMealCamera()),
];

final class _ThrowingAddMealStore implements MealStore {
  final TestMealStore _inner = TestMealStore();

  List<Meal> get rows => _inner.rows;

  @override
  Future<Meal> add(MealDraft draft, {required DateTime now, String? photo}) =>
      Future.error(StateError('disk write failed'));

  @override
  Future<bool> attachPhoto(int id, String name) => _inner.attachPhoto(id, name);

  @override
  Future<List<Meal>> between(LocalDate from, LocalDate to) =>
      _inner.between(from, to);

  @override
  Future<int> clear() => _inner.clear();

  @override
  Future<int> count() => _inner.count();

  @override
  Future<Meal?> delete(int id) => _inner.delete(id);

  @override
  Future<List<String>> deletePhotosBefore(DateTime cutoff) =>
      _inner.deletePhotosBefore(cutoff);

  @override
  Future<bool> update(int id, MealDraft draft) => _inner.update(id, draft);
}

final class _GatedAddMealStore implements MealStore {
  final TestMealStore _inner = TestMealStore();
  Completer<Meal>? gate;

  @override
  Future<Meal> add(MealDraft draft, {required DateTime now, String? photo}) {
    final current = gate;
    if (current != null) return current.future;
    return _inner.add(draft, now: now, photo: photo);
  }

  @override
  Future<bool> attachPhoto(int id, String name) => _inner.attachPhoto(id, name);

  @override
  Future<List<Meal>> between(LocalDate from, LocalDate to) =>
      _inner.between(from, to);

  @override
  Future<int> clear() => _inner.clear();

  @override
  Future<int> count() => _inner.count();

  @override
  Future<Meal?> delete(int id) => _inner.delete(id);

  @override
  Future<List<String>> deletePhotosBefore(DateTime cutoff) =>
      _inner.deletePhotosBefore(cutoff);

  @override
  Future<bool> update(int id, MealDraft draft) => _inner.update(id, draft);
}

final class _CountingMealCamera implements MealCamera {
  new(this.photo);

  final Uint8List photo;
  int takes = 0;

  @override
  Future<Uint8List?> takePhoto() async {
    takes++;
    return photo;
  }

  @override
  Future<Uint8List?> retrieveLost() async => null;
}

Future<ProviderContainer> _pumpScreen(
  WidgetTester tester,
  TestMealStore meals, {
  MealCamera? camera,
  PhotoStore? photos,
  DateTime Function()? clock,
  LocalDate? day,
  List<Override>? overrides,
}) async {
  await pumpScaled(
    tester,
    screenHost(FoodDayScreen(day: day)),
    textScaler: TextScaler.noScaling,
    brightness: Brightness.dark,
    locale: const Locale('en'),
    size: const Size(360, 2000),
    overrides:
        overrides ??
        foodOverrides(
          meals: meals,
          camera: camera ?? FakeMealCamera(),
          photos: photos,
          clock: clock ?? () => _now,
        ),
  );
  return ProviderScope.containerOf(tester.element(find.byType(FoodDayScreen)));
}

Finder _inMeal(int id, Finder matching) =>
    find.descendant(of: find.byKey(FoodDayKeys.meal(id)), matching: matching);

Finder _inSheet(Finder matching) =>
    find.descendant(of: find.byType(MealSavedSheet), matching: matching);

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

class _PresenterProbe extends ConsumerWidget {
  const new({required this.token, required this.result});

  final Object token;
  final SaveResult result;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    body: TextButton(
      key: const Key('present_probe'),
      onPressed: () => unawaited(
        presentMealCapture(
          context: context,
          ref: ref,
          hostToken: token,
          result: result,
          recovered: false,
        ),
      ),
      child: const Text('present'),
    ),
  );
}

void main() {
  group('criterion 2: Food off', () {
    testWidgets('renders neither addPhoto nor addWithoutPhoto and never reads '
        'MealStore, PhotoStore, or MealCamera', (tester) async {
      final reads = StoreReads();

      await _pumpScreen(
        tester,
        TestMealStore(),
        overrides: [
          moduleStoreProvider.overrideWithValue(InMemoryModuleStore()),
          clockProvider.overrideWithValue(() => _now),
          ...reads.overrides(),
        ],
      );

      expect(find.byKey(FoodDayKeys.addPhoto), findsNothing);
      expect(find.byKey(FoodDayKeys.addWithoutPhoto), findsNothing);
      expect(reads.any, isFalse, reason: 'Food off must not read the stores');
      expect(tester.takeException(), isNull);
    });
  });

  group('criterion 3: add row visibility', () {
    testWidgets('on empty today shows both Photo and Without photo', (
      tester,
    ) async {
      await _pumpScreen(tester, TestMealStore());

      expect(find.byKey(FoodDayKeys.empty), findsOneWidget);
      expect(find.byKey(FoodDayKeys.addPhoto), findsOneWidget);
      expect(find.byKey(FoodDayKeys.addWithoutPhoto), findsOneWidget);
    });

    testWidgets('on today with meals shows both Photo and Without photo', (
      tester,
    ) async {
      final meals = TestMealStore()
        ..seed(DateTime(2026, 11, 17, 12, 30), kind: MealKind.main);

      await _pumpScreen(tester, meals);

      expect(find.byKey(FoodDayKeys.addPhoto), findsOneWidget);
      expect(find.byKey(FoodDayKeys.addWithoutPhoto), findsOneWidget);
    });

    testWidgets('stepping to yesterday hides Photo and keeps Without photo; '
        'returning to today restores Photo', (tester) async {
      final meals = TestMealStore()
        ..seed(DateTime(2026, 11, 16, 12, 30), kind: MealKind.main);

      await _pumpScreen(tester, meals);

      await _tapKey(tester, FoodDayKeys.previous);

      expect(find.byKey(FoodDayKeys.addPhoto), findsNothing);
      expect(find.byKey(FoodDayKeys.addWithoutPhoto), findsOneWidget);

      await _tapKey(tester, FoodDayKeys.next);

      expect(find.byKey(FoodDayKeys.addPhoto), findsOneWidget);
      expect(find.byKey(FoodDayKeys.addWithoutPhoto), findsOneWidget);
    });

    testWidgets('empty today shows foodDayEmptyBody and empty yesterday shows '
        'foodDayEmptyPastBody with updated blank note', (tester) async {
      final l10n = lookupAppLocalizations(const Locale('en'));

      await _pumpScreen(tester, TestMealStore());

      expect(find.byKey(FoodDayKeys.empty), findsOneWidget);
      expect(find.text(l10n.foodDayEmptyBody), findsOneWidget);
      expect(find.text(l10n.foodDayEmptyPastBody), findsNothing);
      expect(find.text(l10n.foodDayBlankNote), findsOneWidget);

      await _tapKey(tester, FoodDayKeys.previous);

      expect(find.byKey(FoodDayKeys.empty), findsOneWidget);
      expect(find.text(l10n.foodDayEmptyPastBody), findsOneWidget);
      expect(find.text(l10n.foodDayEmptyBody), findsNothing);
      expect(find.text(l10n.foodDayBlankNote), findsOneWidget);
    });
  });

  group('criterion 4: MealCaptureHosts & presentMealCapture', () {
    test('attach, detach, and claim enforce single active host and once-only '
        'claim per SaveResult', () {
      final hosts = MealCaptureHosts();
      final todayHost = Object();
      final foodDayHost = Object();
      final missingHost = Object();
      final first = SaveResult(
        SaveOutcome.saved,
        TimeSource.returned,
        Meal(
          id: 1,
          at: DateTime.utc(2026, 11, 17, 12),
          offsetMinutes: 0,
          createdAt: DateTime.utc(2026, 11, 17, 12),
        ),
      );
      final second = SaveResult(
        SaveOutcome.saved,
        TimeSource.returned,
        Meal(
          id: 2,
          at: DateTime.utc(2026, 11, 17, 13),
          offsetMinutes: 0,
          createdAt: DateTime.utc(2026, 11, 17, 13),
        ),
      );

      expect(hosts.claim(first, todayHost), isFalse);

      hosts
        ..detach(missingHost)
        ..attach(todayHost)
        ..attach(foodDayHost);
      expect(hosts.claim(first, todayHost), isFalse);
      expect(hosts.claim(first, foodDayHost), isTrue);
      expect(hosts.claim(first, foodDayHost), isFalse);

      hosts.detach(foodDayHost);
      expect(hosts.claim(second, foodDayHost), isFalse);
      expect(hosts.claim(second, todayHost), isTrue);
      expect(hosts.claim(second, todayHost), isFalse);
    });

    testWidgets('presentMealCapture only opens a sheet for the active host '
        'and opens once per result', (tester) async {
      final meals = TestMealStore();
      final meal = meals.seed(DateTime(2026, 11, 17, 12, 30));
      final result = SaveResult(SaveOutcome.saved, TimeSource.returned, meal);
      final bottomHost = Object();
      final topHost = Object();

      await pumpScaled(
        tester,
        screenHost(_PresenterProbe(token: topHost, result: result)),
        textScaler: TextScaler.noScaling,
        brightness: Brightness.dark,
        locale: const Locale('en'),
        overrides: foodOverrides(
          meals: meals,
          camera: FakeMealCamera(),
          clock: () => _now,
        ),
      );

      final container = ProviderScope.containerOf(
        tester.element(find.byType(_PresenterProbe)),
      );
      container.read<MealCaptureHosts>(mealCaptureHostsProvider)
        ..attach(bottomHost)
        ..attach(topHost);

      await tester.tap(find.byKey(const Key('present_probe')));
      await tester.pumpAndSettle();

      expect(find.byType(MealSavedSheet), findsOneWidget);
      await _tapKey(tester, MealSavedSheetKeys.done);
      expect(find.byType(MealSavedSheet), findsNothing);

      await tester.tap(find.byKey(const Key('present_probe')));
      await tester.pumpAndSettle();
      expect(find.byType(MealSavedSheet), findsNothing);
    });
  });

  group('criterion 4: Photo on today & single-sheet invariant', () {
    testWidgets('standalone FoodDayScreen: tapping Photo disables while '
        'saving, calls takePhoto once on double-tap, opens MealSavedSheet once, '
        'and saves tags into the day list', (tester) async {
      final l10n = lookupAppLocalizations(const Locale('en'));
      final meals = TestMealStore();
      final camera = GatedMealCamera();

      final container = await _pumpScreen(tester, meals, camera: camera);
      final before = container.read(dataRevisionProvider);

      await tester.tap(find.byKey(FoodDayKeys.addPhoto));
      await tester.pump();
      expect(_buttonEnabled(tester, FoodDayKeys.addPhoto), isFalse);

      await tester.tap(find.byKey(FoodDayKeys.addPhoto), warnIfMissed: false);
      await tester.pump();

      camera.open(returnedPhoto);
      await tester.pumpAndSettle();

      expect(camera.takes, 1);
      expect(find.byType(MealSavedSheet), findsOneWidget);
      expect(meals.rows, hasLength(1));
      expect(meals.rows.single.photo, isNotNull);
      expect(container.read(dataRevisionProvider), before + 1);

      await _tapKey(tester, MealSavedSheetKeys.kind(MealKind.main));
      await _tapKey(tester, MealSavedSheetKeys.flag(MealFlag.protein));
      await _tapKey(tester, MealSavedSheetKeys.done);

      expect(find.byType(MealSavedSheet), findsNothing);
      expect(meals.rows.single.kind, MealKind.main);
      expect(meals.rows.single.tags.protein, isTrue);
      expect(
        _inMeal(meals.rows.single.id, find.textContaining(l10n.foodProtein)),
        findsOneWidget,
      );
      expect(_buttonEnabled(tester, FoodDayKeys.addPhoto), isTrue);
    });

    testWidgets('cancelled photo capture leaves 0 rows, 0 bumps, no sheet, '
        'and no SnackBar', (tester) async {
      final meals = TestMealStore();
      final container = await _pumpScreen(
        tester,
        meals,
        camera: FakeMealCamera(),
      );
      final before = container.read(dataRevisionProvider);

      await _tapKey(tester, FoodDayKeys.addPhoto);

      expect(meals.rows, isEmpty);
      expect(container.read(dataRevisionProvider), before);
      expect(find.byType(MealSavedSheet), findsNothing);
      expect(find.byType(MealNoSpaceSheet), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('failed photo capture shows a SnackBar and leaves 0 rows', (
      tester,
    ) async {
      final meals = TestMealStore();
      final container = await _pumpScreen(
        tester,
        meals,
        camera: ThrowingMealCamera(),
      );
      final before = container.read(dataRevisionProvider);

      await tester.tap(find.byKey(FoodDayKeys.addPhoto));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 750));

      expect(find.byType(SnackBar), findsOneWidget);
      expect(meals.rows, isEmpty);
      expect(container.read(dataRevisionProvider), before);
      expect(find.byType(MealSavedSheet), findsNothing);
      expect(find.byType(MealNoSpaceSheet), findsNothing);
    });

    testWidgets('full disk opens MealNoSpaceSheet and Retry attaches photo '
        'and bumps revision', (tester) async {
      final meals = TestMealStore();
      final full = FullPhotoStore();
      final container = await _pumpScreen(
        tester,
        meals,
        camera: FakeMealCamera(photo: returnedPhoto),
        photos: full,
      );

      await _tapKey(tester, FoodDayKeys.addPhoto);

      expect(find.byType(MealNoSpaceSheet), findsOneWidget);
      expect(meals.rows, hasLength(1));
      expect(meals.rows.single.photo, isNull);
      final beforeRetry = container.read(dataRevisionProvider);

      full.full = false;
      await _tapKey(tester, MealSavedSheetKeys.retry);

      expect(find.byType(MealNoSpaceSheet), findsNothing);
      final photoName = meals.rows.single.photo;
      expect(photoName, isNotNull);
      expect(await full.inner.read(photoName!), isNotNull);
      expect(container.read(dataRevisionProvider), greaterThan(beforeRetry));
    });

    testWidgets('GoRouter StatefulShellRoute: navigating /today -> /today/food '
        'keeps FoodRowSlot mounted, tapping Photo opens MealSavedSheet '
        'exactly once, and returning to /today keeps camera working', (
      tester,
    ) async {
      final meals = TestMealStore();
      final camera = _CountingMealCamera(returnedPhoto);
      final router = GoRouter(
        initialLocation: AppTab.today.path,
        routes: [
          StatefulShellRoute.indexedStack(
            builder: (_, _, shell) => Scaffold(body: shell),
            branches: [
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: AppTab.today.path,
                    builder: (_, _) => const Scaffold(
                      body: SingleChildScrollView(child: FoodRowSlot()),
                    ),
                    routes: [
                      GoRoute(
                        path: 'food',
                        builder: (_, _) => const FoodDayScreen(),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ],
      );
      addTearDown(router.dispose);

      await pumpScaled(
        tester,
        MaterialApp.router(
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          localeListResolutionCallback: AppLocales.resolve,
          supportedLocales: AppLocales.supported,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          routerConfig: router,
        ),
        textScaler: TextScaler.noScaling,
        brightness: Brightness.dark,
        locale: const Locale('en'),
        size: const Size(360, 2000),
        overrides: foodOverrides(
          meals: meals,
          camera: camera,
          clock: () => _now,
        ),
      );

      await _tapKey(tester, FoodRowKeys.row);
      expect(router.state.uri.path, AppPaths.food);
      expect(find.byType(FoodDayScreen), findsOneWidget);
      expect(find.byType(FoodRowSlot, skipOffstage: false), findsOneWidget);

      await _tapKey(tester, FoodDayKeys.addPhoto);

      expect(find.byType(MealSavedSheet), findsOneWidget);
      expect(camera.takes, 1);
      expect(meals.rows, hasLength(1));

      await _tapKey(tester, MealSavedSheetKeys.kind(MealKind.main));
      await _tapKey(tester, MealSavedSheetKeys.flag(MealFlag.protein));
      await _tapKey(tester, MealSavedSheetKeys.done);

      expect(find.byType(MealSavedSheet), findsNothing);
      expect(meals.rows.single.kind, MealKind.main);
      expect(meals.rows.single.tags.protein, isTrue);

      await _back(tester);
      expect(router.state.uri.path, AppTab.today.path);
      expect(find.byKey(FoodRowKeys.camera), findsOneWidget);

      await _tapKey(tester, FoodRowKeys.camera);

      expect(find.byType(MealSavedSheet), findsOneWidget);
      expect(camera.takes, 2);
      expect(meals.rows, hasLength(2));

      await _tapKey(tester, MealSavedSheetKeys.done);
      expect(find.byType(MealSavedSheet), findsNothing);
    });
  });

  group('criterion 5 & review focus 5: Without photo flow', () {
    testWidgets('initial time passed to mealTimePickerProvider is '
        'TimeOfDay.fromDateTime(now) on today and 12:00 on a past day', (
      tester,
    ) async {
      final recorded = <TimeOfDay>[];
      final meals = TestMealStore();

      await _pumpScreen(
        tester,
        meals,
        overrides: [
          ...foodOverrides(
            meals: meals,
            camera: FakeMealCamera(),
            clock: () => _now,
          ),
          mealTimePickerProvider.overrideWithValue((_, initial) async {
            recorded.add(initial);
            return null;
          }),
        ],
      );

      await _tapKey(tester, FoodDayKeys.addWithoutPhoto);
      await _tapKey(tester, FoodDayKeys.previous);
      await _tapKey(tester, FoodDayKeys.addWithoutPhoto);

      expect(recorded, [
        TimeOfDay.fromDateTime(_now),
        const TimeOfDay(hour: 12, minute: 0),
      ]);
    });

    testWidgets('real showTimePicker dialog opens and Cancel writes 0 rows', (
      tester,
    ) async {
      final meals = TestMealStore();
      final container = await _pumpScreen(tester, meals);
      final before = container.read(dataRevisionProvider);

      await _tapKey(tester, FoodDayKeys.addWithoutPhoto);

      expect(find.byType(TimePickerDialog), findsOneWidget);
      final cancel = MaterialLocalizations.of(
        tester.element(find.byType(TimePickerDialog)),
      ).cancelButtonLabel;
      await tester.tap(find.text(cancel));
      await tester.pumpAndSettle();

      expect(find.byType(TimePickerDialog), findsNothing);
      expect(meals.rows, isEmpty);
      expect(container.read(dataRevisionProvider), before);
      expect(find.byType(MealSavedSheet), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('cancelled picker writes 0 rows, 0 bumps, no edit sheet, and '
        'no SnackBar', (tester) async {
      final meals = TestMealStore();
      final container = await _pumpScreen(
        tester,
        meals,
        overrides: [
          ...foodOverrides(
            meals: meals,
            camera: FakeMealCamera(),
            clock: () => _now,
          ),
          mealTimePickerProvider.overrideWithValue((_, _) async => null),
        ],
      );
      final before = container.read(dataRevisionProvider);

      await _tapKey(tester, FoodDayKeys.addWithoutPhoto);

      expect(meals.rows, isEmpty);
      expect(container.read(dataRevisionProvider), before);
      expect(find.byType(MealSavedSheet), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
    });

    final futurePicks = <String, TimeOfDay>{
      '21:01 on the same calendar day': const TimeOfDay(hour: 21, minute: 1),
      '00:30 mapped to the next calendar morning': const TimeOfDay(
        hour: 0,
        minute: 30,
      ),
    };
    for (final MapEntry(key: label, value: picked) in futurePicks.entries) {
      testWidgets('future time ($label) writes 0 rows, 0 bumps, no sheet, and '
          'shows future error SnackBar', (tester) async {
        final meals = TestMealStore();
        final container = await _pumpScreen(
          tester,
          meals,
          overrides: [
            ...foodOverrides(
              meals: meals,
              camera: FakeMealCamera(),
              clock: () => _now,
            ),
            mealTimePickerProvider.overrideWithValue((_, _) async => picked),
          ],
        );
        final before = container.read(dataRevisionProvider);

        await _tapKey(tester, FoodDayKeys.addWithoutPhoto);

        expect(meals.rows, isEmpty);
        expect(container.read(dataRevisionProvider), before);
        expect(find.byType(MealSavedSheet), findsNothing);
        expect(
          find.descendant(
            of: find.byType(SnackBar),
            matching: find.text('The meal time cannot be in the future'),
          ),
          findsOneWidget,
        );
      });
    }

    testWidgets('valid time on today adds 1 photoless meal, bumps revision, '
        'opens MealSavedSheet.edit, and closing untouched performs 0 updates', (
      tester,
    ) async {
      final l10n = lookupAppLocalizations(const Locale('en'));
      final meals = TestMealStore();
      final container = await _pumpScreen(
        tester,
        meals,
        overrides: [
          ...foodOverrides(
            meals: meals,
            camera: FakeMealCamera(),
            clock: () => _now,
          ),
          mealTimePickerProvider.overrideWithValue(
            (_, _) async => const TimeOfDay(hour: 12, minute: 30),
          ),
        ],
      );
      final before = container.read(dataRevisionProvider);

      await _tapKey(tester, FoodDayKeys.addWithoutPhoto);

      expect(meals.rows, hasLength(1));
      final added = meals.rows.single;
      expect(added.photo, isNull);
      expect(foodDay(added.entry.at), const LocalDate(2026, 11, 17));
      expect(container.read(dataRevisionProvider), before + 1);
      expect(find.byType(MealSavedSheet), findsOneWidget);
      final sheet = tester.widget<MealSavedSheet>(find.byType(MealSavedSheet));
      expect(sheet.time, isNull);
      expect(_inSheet(find.text(l10n.foodSlotLunch)), findsOneWidget);
      expect(_inSheet(find.text('12:30')), findsOneWidget);
      expect(_inSheet(find.text(l10n.foodSavedTitle)), findsNothing);

      await _tapKey(tester, MealSavedSheetKeys.done);

      expect(find.byType(MealSavedSheet), findsNothing);
      expect(meals.updates, 0);
      expect(container.read(dataRevisionProvider), before + 1);
      expect(find.byKey(FoodDayKeys.meal(added.id)), findsOneWidget);
      expect(_inMeal(added.id, find.text('no tags')), findsOneWidget);
    });

    testWidgets('valid time on today followed by tag selection performs 1 '
        'update and displays the new tags on the day screen', (tester) async {
      final l10n = lookupAppLocalizations(const Locale('en'));
      final meals = TestMealStore();
      final container = await _pumpScreen(
        tester,
        meals,
        overrides: [
          ...foodOverrides(
            meals: meals,
            camera: FakeMealCamera(),
            clock: () => _now,
          ),
          mealTimePickerProvider.overrideWithValue(
            (_, _) async => const TimeOfDay(hour: 12, minute: 30),
          ),
        ],
      );
      final before = container.read(dataRevisionProvider);

      await _tapKey(tester, FoodDayKeys.addWithoutPhoto);
      await _tapKey(tester, MealSavedSheetKeys.kind(MealKind.main));
      await _tapKey(tester, MealSavedSheetKeys.flag(MealFlag.protein));
      await _tapKey(tester, MealSavedSheetKeys.done);

      expect(find.byType(MealSavedSheet), findsNothing);
      expect(meals.updates, 1);
      expect(container.read(dataRevisionProvider), before + 2);
      expect(meals.rows.single.kind, MealKind.main);
      expect(meals.rows.single.tags.protein, isTrue);
      expect(
        _inMeal(meals.rows.single.id, find.textContaining(l10n.foodProtein)),
        findsOneWidget,
      );
    });

    testWidgets('00:30 on yesterday adds 1 photoless meal to yesterday, opens '
        'MealSavedSheet.edit, and shows it on yesterday', (tester) async {
      final l10n = lookupAppLocalizations(const Locale('en'));
      final meals = TestMealStore();
      final container = await _pumpScreen(
        tester,
        meals,
        overrides: [
          ...foodOverrides(
            meals: meals,
            camera: FakeMealCamera(),
            clock: () => _now,
          ),
          mealTimePickerProvider.overrideWithValue(
            (_, _) async => const TimeOfDay(hour: 0, minute: 30),
          ),
        ],
      );
      final before = container.read(dataRevisionProvider);

      await _tapKey(tester, FoodDayKeys.previous);
      await _tapKey(tester, FoodDayKeys.addWithoutPhoto);

      expect(meals.rows, hasLength(1));
      final added = meals.rows.single;
      expect(added.photo, isNull);
      expect(foodDay(added.entry.at), const LocalDate(2026, 11, 16));
      expect(added.entry.at, DateTime.utc(2026, 11, 17, 0, 30));
      expect(container.read(dataRevisionProvider), before + 1);
      expect(find.byType(MealSavedSheet), findsOneWidget);
      expect(_inSheet(find.text(l10n.foodSlotSupper)), findsOneWidget);

      await _tapKey(tester, MealSavedSheetKeys.done);

      expect(find.byKey(FoodDayKeys.meal(added.id)), findsOneWidget);
      expect(_inMeal(added.id, find.text('00:30')), findsOneWidget);
    });

    testWidgets(
      'throwing MealStore.add shows Could not save the meal SnackBar, '
      '0 bumps, and no edit sheet',
      (tester) async {
        final meals = _ThrowingAddMealStore();
        final container = await _pumpScreen(
          tester,
          TestMealStore(),
          overrides: [
            ..._customStoreOverrides(meals, clock: () => _now),
            mealTimePickerProvider.overrideWithValue(
              (_, _) async => const TimeOfDay(hour: 12, minute: 30),
            ),
          ],
        );
        final before = container.read(dataRevisionProvider);

        await _tapKey(tester, FoodDayKeys.addWithoutPhoto);

        expect(meals.rows, isEmpty);
        expect(container.read(dataRevisionProvider), before);
        expect(find.byType(MealSavedSheet), findsNothing);
        expect(
          find.descendant(
            of: find.byType(SnackBar),
            matching: find.text('Could not save the meal'),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets('review focus 5: unmounting FoodDayScreen while time picker '
        'is in flight does not throw', (tester) async {
      final meals = TestMealStore();
      final picker = Completer<TimeOfDay?>();
      final show = ValueNotifier(true);
      addTearDown(show.dispose);

      await pumpScaled(
        tester,
        screenHost(
          ValueListenableBuilder<bool>(
            valueListenable: show,
            builder: (_, visible, _) => visible
                ? const FoodDayScreen()
                : const Scaffold(body: SizedBox.shrink()),
          ),
        ),
        textScaler: TextScaler.noScaling,
        brightness: Brightness.dark,
        locale: const Locale('en'),
        overrides: [
          ...foodOverrides(
            meals: meals,
            camera: FakeMealCamera(),
            clock: () => _now,
          ),
          mealTimePickerProvider.overrideWithValue((_, _) => picker.future),
        ],
      );

      await tester.tap(find.byKey(FoodDayKeys.addWithoutPhoto));
      await tester.pump();

      show.value = false;
      await tester.pump();

      picker.complete(const TimeOfDay(hour: 12, minute: 30));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('review focus 5: unmounting FoodDayScreen while '
        'addWithoutPhoto is in flight does not throw when save succeeds', (
      tester,
    ) async {
      final gate = Completer<Meal>();
      final meals = _GatedAddMealStore()..gate = gate;
      final show = ValueNotifier(true);
      addTearDown(show.dispose);

      await pumpScaled(
        tester,
        screenHost(
          ValueListenableBuilder<bool>(
            valueListenable: show,
            builder: (_, visible, _) => visible
                ? const FoodDayScreen()
                : const Scaffold(body: SizedBox.shrink()),
          ),
        ),
        textScaler: TextScaler.noScaling,
        brightness: Brightness.dark,
        locale: const Locale('en'),
        overrides: [
          ..._customStoreOverrides(meals, clock: () => _now),
          mealTimePickerProvider.overrideWithValue(
            (_, _) async => const TimeOfDay(hour: 12, minute: 30),
          ),
        ],
      );

      await tester.tap(find.byKey(FoodDayKeys.addWithoutPhoto));
      await tester.pump();

      show.value = false;
      await tester.pump();

      gate.complete(
        Meal(
          id: 1,
          at: DateTime.utc(2026, 11, 17, 12, 30),
          offsetMinutes: 0,
          createdAt: _now.toUtc(),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('review focus 5: unmounting FoodDayScreen while '
        'addWithoutPhoto is in flight does not throw when save fails', (
      tester,
    ) async {
      final gate = Completer<Meal>();
      final meals = _GatedAddMealStore()..gate = gate;
      final show = ValueNotifier(true);
      addTearDown(show.dispose);

      await pumpScaled(
        tester,
        screenHost(
          ValueListenableBuilder<bool>(
            valueListenable: show,
            builder: (_, visible, _) => visible
                ? const FoodDayScreen()
                : const Scaffold(body: SizedBox.shrink()),
          ),
        ),
        textScaler: TextScaler.noScaling,
        brightness: Brightness.dark,
        locale: const Locale('en'),
        overrides: [
          ..._customStoreOverrides(meals, clock: () => _now),
          mealTimePickerProvider.overrideWithValue(
            (_, _) async => const TimeOfDay(hour: 12, minute: 30),
          ),
        ],
      );

      await tester.tap(find.byKey(FoodDayKeys.addWithoutPhoto));
      await tester.pump();

      show.value = false;
      await tester.pump();

      gate.completeError(StateError('disk write failed'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });
}

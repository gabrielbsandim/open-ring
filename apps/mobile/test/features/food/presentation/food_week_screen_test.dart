import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/router/app_router.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/core/records/data_revision.dart';
import 'package:open_ring/features/food/application/food_energy.dart';
import 'package:open_ring/features/food/application/food_energy_gate.dart';
import 'package:open_ring/features/food/application/food_nights.dart';
import 'package:open_ring/features/food/application/meal_store_providers.dart';
import 'package:open_ring/features/food/domain/meal.dart';
import 'package:open_ring/features/food/domain/meal_camera.dart';
import 'package:open_ring/features/food/domain/meal_store.dart';
import 'package:open_ring/features/food/domain/photo_store.dart';
import 'package:open_ring/features/food/presentation/food_day_screen.dart';
import 'package:open_ring/features/food/presentation/food_meal_screen.dart';
import 'package:open_ring/features/food/presentation/food_timing_chart.dart';
import 'package:open_ring/features/food/presentation/food_week_evidence_sheet.dart';
import 'package:open_ring/features/food/presentation/food_week_screen.dart';
import 'package:open_ring/features/goals/application/goal_store_providers.dart';
import 'package:open_ring/features/goals/domain/goal.dart';
import 'package:open_ring/features/goals/domain/goal_store.dart';
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

// Tuesday 17 Nov 2026: closed Mon..Sun week is 2026-11-09 to 2026-11-15.
final _now = DateTime(2026, 11, 17, 21);
const _monday = LocalDate(2026, 11, 9);
const _sunday = LocalDate(2026, 11, 15);

final class _ControllableMealStore implements MealStore {
  new(this.inner);

  final TestMealStore inner;
  bool throwOnBetween = false;
  Completer<void>? betweenGate;

  @override
  Future<List<Meal>> between(LocalDate from, LocalDate to) async {
    final gate = betweenGate;
    if (gate != null && !gate.isCompleted) {
      await gate.future;
    }
    if (throwOnBetween) {
      throw StateError('meal read error');
    }
    return await inner.between(from, to);
  }

  @override
  Future<Meal> add(MealDraft draft, {required DateTime now, String? photo}) =>
      inner.add(draft, now: now, photo: photo);

  @override
  Future<bool> attachPhoto(int id, String name) => inner.attachPhoto(id, name);

  @override
  Future<Meal?> byId(int id) => inner.byId(id);

  @override
  Future<int> clear() => inner.clear();

  @override
  Future<int> count() => inner.count();

  @override
  Future<Meal?> delete(int id) => inner.delete(id);

  @override
  Future<List<MealPhotoRef>> photoRefs() => inner.photoRefs();

  @override
  Future<List<String>> deletePhotosBefore(DateTime cutoff) =>
      inner.deletePhotosBefore(cutoff);

  @override
  Future<List<String>> deleteAllPhotos() => inner.deleteAllPhotos();

  @override
  Future<bool> update(int id, MealDraft draft) => inner.update(id, draft);
}

final class _ThrowingGoalStore implements GoalStore {
  const new();

  @override
  Future<List<GoalScreening>> screenings() async =>
      throw StateError('goal read error');

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('unexpected: ${invocation.memberName}');
}

List<Override> _weekOverrides({
  required MealStore meals,
  PhotoStore? photos,
  GoalStore? goals,
  List<FoodNight> nights = const [],
  DateTime Function()? clock,
  bool foodOn = true,
}) => [
  moduleStoreProvider.overrideWithValue(
    InMemoryModuleStore({if (foodOn) ModuleId.food}),
  ),
  clockProvider.overrideWithValue(clock ?? () => _now),
  mealStoreProvider.overrideWithValue(meals),
  photoStoreProvider.overrideWithValue(photos ?? InMemoryPhotoStore()),
  mealCameraProvider.overrideWithValue(FakeMealCamera()),
  foodNightsProvider.overrideWith((ref) async => nights),
  goalStoreProvider.overrideWithValue(goals ?? InMemoryGoalStore()),
];

Future<ProviderContainer> _pumpWeekScreen(
  WidgetTester tester, {
  MealStore? meals,
  PhotoStore? photos,
  GoalStore? goals,
  List<FoodNight> nights = const [],
  List<Override>? overrides,
  double scale = 1,
}) async {
  await pumpScaled(
    tester,
    screenHost(const FoodWeekScreen()),
    textScaler: TextScaler.linear(scale),
    brightness: Brightness.dark,
    locale: const Locale('en'),
    size: const Size(360, 2000),
    overrides:
        overrides ??
        _weekOverrides(
          meals: meals ?? TestMealStore(),
          photos: photos,
          goals: goals,
          nights: nights,
        ),
  );
  return ProviderScope.containerOf(tester.element(find.byType(FoodWeekScreen)));
}

BoxDecoration _dotDecoration(WidgetTester tester, LocalDate day) {
  final dotFinder = find.byKey(FoodWeekKeys.dayDot(day));
  expect(dotFinder, findsOneWidget);
  final widget = tester.widget(dotFinder);
  if (widget is DecoratedBox) {
    return widget.decoration as BoxDecoration;
  }
  final box = tester.widget<DecoratedBox>(
    find.descendant(of: dotFinder, matching: find.byType(DecoratedBox)).first,
  );
  return box.decoration as BoxDecoration;
}

Image _thumbImage(WidgetTester tester, int mealId) {
  final photoFinder = find.byKey(FoodWeekKeys.thumbPhoto(mealId));
  expect(photoFinder, findsOneWidget);
  final widget = tester.widget(photoFinder);
  if (widget is Image) return widget;
  return tester.widget<Image>(
    find.descendant(of: photoFinder, matching: find.byType(Image)),
  );
}

void _seedFullPlateWeek(
  TestMealStore meals, {
  MealAlcohol alcohol = MealAlcohol.oneToTwo,
}) {
  // 5 complete days (Mon 9..Fri 13), 2 mains per day = 10 mains:
  // 8 protein, 7 veg, 2 processed, 1 sugary day, 1 alcohol meal.
  for (var i = 0; i < 5; i++) {
    final day = _monday.addDays(i);
    meals
      ..seed(
        DateTime(day.year, day.month, day.day, 12, 30),
        kind: MealKind.main,
        tags: MealTags(
          protein: i < 4,
          veg: i < 4 ? MealVeg.halfOrMore : null,
          processed: i == 0 ? MealProcessed.mostly : null,
        ),
      )
      ..seed(
        DateTime(day.year, day.month, day.day, 19, 30),
        kind: MealKind.main,
        tags: MealTags(
          protein: i < 4,
          veg: i < 3 ? MealVeg.some : null,
          processed: i == 1 ? MealProcessed.mostly : null,
          sugar: i == 2,
          alcohol: i == 4 ? alcohol : null,
        ),
        last: true,
      );
  }
}

List<String> _allTextStrings(WidgetTester tester, {Finder? within}) {
  final finder = within == null
      ? find.byType(Text)
      : find.descendant(of: within, matching: find.byType(Text));
  return [
    for (final text in tester.widgetList<Text>(finder))
      text.data ?? text.textSpan?.toPlainText() ?? '',
  ];
}

void main() {
  group('off-gate', () {
    testWidgets('FoodWeekScreen when Food is off renders no FoodWeekKeys '
        'and never reads mealStoreProvider, foodNightsProvider, or '
        'goalStoreProvider', (tester) async {
      final l10n = lookupAppLocalizations(const Locale('en'));
      final reads = StoreReads();
      var nightsRead = false;
      var goalsRead = false;

      await _pumpWeekScreen(
        tester,
        overrides: [
          moduleStoreProvider.overrideWithValue(InMemoryModuleStore()),
          clockProvider.overrideWithValue(() => _now),
          ...reads.overrides(),
          foodNightsProvider.overrideWith((ref) async {
            nightsRead = true;
            return const [];
          }),
          goalStoreProvider.overrideWith((ref) {
            goalsRead = true;
            throw UnimplementedError('goalStoreProvider should not be read');
          }),
        ],
      );

      expect(find.text(l10n.foodTitle), findsOneWidget);
      expect(find.byKey(FoodWeekKeys.tabs), findsNothing);
      expect(find.byKey(FoodWeekKeys.tabDay), findsNothing);
      expect(find.byKey(FoodWeekKeys.tabWeek), findsNothing);
      expect(find.byKey(FoodWeekKeys.contactSheet), findsNothing);
      expect(find.byKey(FoodWeekKeys.empty), findsNothing);
      expect(find.byKey(FoodWeekKeys.plateCard), findsNothing);
      expect(find.byKey(FoodWeekKeys.softModeCard), findsNothing);
      expect(reads.any, isFalse);
      expect(nightsRead, isFalse);
      expect(goalsRead, isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('FoodDayScreen when Food is off mounts no FoodSectionTabs', (
      tester,
    ) async {
      final reads = StoreReads();

      await pumpScaled(
        tester,
        screenHost(const FoodDayScreen()),
        textScaler: TextScaler.noScaling,
        brightness: Brightness.dark,
        locale: const Locale('en'),
        overrides: [
          moduleStoreProvider.overrideWithValue(InMemoryModuleStore()),
          clockProvider.overrideWithValue(() => _now),
          ...reads.overrides(),
        ],
      );

      expect(find.byKey(FoodWeekKeys.tabs), findsNothing);
      expect(reads.any, isFalse);
      expect(tester.takeException(), isNull);
    });
  });

  group('route and FoodSectionTabs', () {
    test('AppPaths.foodWeek is /today/food/week', () {
      expect(AppPaths.foodWeek, '/today/food/week');
    });

    testWidgets('appRouterProvider routes /today/food/week to FoodWeekScreen', (
      tester,
    ) async {
      final meals = TestMealStore();
      final container = await pumpOnboardingApp(
        tester,
        store: InMemoryOnboardingStore(completed: true),
        overrides: [
          ...bleOverrides(),
          ...ringOverrides(),
          ...onboardingOverrides(),
          ..._weekOverrides(meals: meals),
        ],
      );

      container.read(appRouterProvider).go(AppPaths.foodWeek);
      await tester.pumpAndSettle();

      expect(find.byType(FoodWeekScreen), findsOneWidget);
    });

    testWidgets('FoodSectionTabs switches between FoodDayScreen and '
        'FoodWeekScreen and ignores tapping the already-selected tab', (
      tester,
    ) async {
      final meals = TestMealStore();
      final container = await pumpOnboardingApp(
        tester,
        at: AppPaths.food,
        store: InMemoryOnboardingStore(completed: true),
        overrides: [
          ...bleOverrides(),
          ...ringOverrides(),
          ...onboardingOverrides(),
          ..._weekOverrides(meals: meals),
        ],
      );

      expect(find.byType(FoodDayScreen), findsOneWidget);
      expect(find.byKey(FoodWeekKeys.tabs), findsOneWidget);
      expect(find.byKey(FoodWeekKeys.tabDay), findsOneWidget);
      expect(find.byKey(FoodWeekKeys.tabWeek), findsOneWidget);
      expect(
        tester
            .widget<SegmentedButton<FoodSection>>(find.byKey(FoodWeekKeys.tabs))
            .selected,
        {FoodSection.day},
      );

      await tester.tap(find.byKey(FoodWeekKeys.tabDay));
      await tester.pumpAndSettle();
      expect(container.read(appRouterProvider).state.uri.path, AppPaths.food);
      expect(find.byType(FoodDayScreen), findsOneWidget);

      await tester.tap(find.byKey(FoodWeekKeys.tabWeek));
      await tester.pumpAndSettle();
      expect(
        container.read(appRouterProvider).state.uri.path,
        AppPaths.foodWeek,
      );
      expect(find.byType(FoodWeekScreen), findsOneWidget);
      expect(
        tester
            .widget<SegmentedButton<FoodSection>>(find.byKey(FoodWeekKeys.tabs))
            .selected,
        {FoodSection.week},
      );

      await tester.tap(find.byKey(FoodWeekKeys.tabWeek));
      await tester.pumpAndSettle();
      expect(
        container.read(appRouterProvider).state.uri.path,
        AppPaths.foodWeek,
      );
      expect(find.byType(FoodWeekScreen), findsOneWidget);

      await tester.tap(find.byKey(FoodWeekKeys.tabDay));
      await tester.pumpAndSettle();
      expect(container.read(appRouterProvider).state.uri.path, AppPaths.food);
      expect(find.byType(FoodDayScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('standalone without GoRouter: tapping tabs and thumbnails does '
        'not throw', (tester) async {
      final meals = TestMealStore();
      final meal = meals.seed(DateTime(2026, 11, 10, 12, 30));

      await _pumpWeekScreen(tester, meals: meals);

      await tester.tap(find.byKey(FoodWeekKeys.tabDay));
      await tester.pumpAndSettle();
      expect(find.byType(FoodWeekScreen), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(FoodWeekKeys.thumb(meal.id)));
      await tester.pumpAndSettle();
      expect(find.byType(FoodWeekScreen), findsOneWidget);
      expect(find.byType(FoodMealScreen), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('contact sheet, thumbnails, boundaries, and navigation', () {
    testWidgets('contact sheet displays Mon..Sun range, foodWeekLast, 7 '
        'columns, complete vs incomplete dots, empty days, and legend', (
      tester,
    ) async {
      final l10n = lookupAppLocalizations(const Locale('en'));
      // Mon Nov 9 complete, Tue Nov 10 incomplete, Wed..Sun empty.
      final meals = TestMealStore()
        ..seed(DateTime(2026, 11, 9, 12, 30), last: true)
        ..seed(DateTime(2026, 11, 10, 13));

      await _pumpWeekScreen(tester, meals: meals);

      final format = MetricFormat.of(
        tester.element(find.byType(FoodWeekScreen)),
      );
      final rangeText = l10n.metricTimeRange(
        format.monthDay(_monday),
        format.monthDay(_sunday),
      );
      expect(find.byKey(FoodWeekKeys.contactSheet), findsOneWidget);
      expect(find.text(rangeText), findsOneWidget);
      expect(find.text(l10n.foodWeekLast), findsOneWidget);

      for (var i = 0; i < 7; i++) {
        expect(
          find.byKey(FoodWeekKeys.dayColumn(_monday.addDays(i))),
          findsOneWidget,
        );
      }

      final completeDot = _dotDecoration(tester, _monday);
      expect(completeDot.color, AppColors.dark.activity);

      final incompleteDot = _dotDecoration(tester, _monday.addDays(1));
      expect(incompleteDot.color, isNull);
      expect(incompleteDot.border, isNotNull);

      expect(find.byKey(FoodWeekKeys.emptyDay(_monday)), findsNothing);
      expect(
        find.byKey(FoodWeekKeys.emptyDay(_monday.addDays(1))),
        findsNothing,
      );
      for (var i = 2; i < 7; i++) {
        expect(
          find.byKey(FoodWeekKeys.emptyDay(_monday.addDays(i))),
          findsOneWidget,
        );
      }

      expect(find.text(l10n.foodWeekCompleteLegend), findsOneWidget);
      expect(find.text(l10n.foodWeekIncompleteLegend), findsOneWidget);
    });

    testWidgets('renders valid photo (ResizeImage 96), no photo, missing '
        'photo, and corrupt bytes post-frame fallback', (tester) async {
      final meals = TestMealStore();
      final photos = InMemoryPhotoStore();
      await photos.save('valid.jpg', strippedPlain());
      await photos.save('corrupt.jpg', notAJpeg);

      final withPhoto = meals.seed(DateTime(2026, 11, 9, 8));
      await meals.attachPhoto(withPhoto.id, 'valid.jpg');
      final noPhoto = meals.seed(DateTime(2026, 11, 9, 12, 30));
      final missingPhoto = meals.seed(DateTime(2026, 11, 10, 12, 30));
      await meals.attachPhoto(missingPhoto.id, 'missing.jpg');
      final corruptPhoto = meals.seed(DateTime(2026, 11, 11, 19));
      await meals.attachPhoto(corruptPhoto.id, 'corrupt.jpg');

      await _pumpWeekScreen(tester, meals: meals, photos: photos);

      final image = _thumbImage(tester, withPhoto.id);
      expect(
        image.image,
        isA<ResizeImage>().having((r) => r.width, 'cacheWidth', 96),
      );
      expect(find.byKey(FoodWeekKeys.thumbNoPhoto(withPhoto.id)), findsNothing);
      expect(
        find.byKey(FoodWeekKeys.thumbMissingPhoto(withPhoto.id)),
        findsNothing,
      );

      expect(find.byKey(FoodWeekKeys.thumbNoPhoto(noPhoto.id)), findsOneWidget);
      expect(find.byKey(FoodWeekKeys.thumbPhoto(noPhoto.id)), findsNothing);
      expect(
        find.byKey(FoodWeekKeys.thumbMissingPhoto(noPhoto.id)),
        findsNothing,
      );

      expect(
        find.byKey(FoodWeekKeys.thumbMissingPhoto(missingPhoto.id)),
        findsOneWidget,
      );
      expect(
        find.byKey(FoodWeekKeys.thumbPhoto(missingPhoto.id)),
        findsNothing,
      );

      expect(
        find.byKey(FoodWeekKeys.thumbPhoto(corruptPhoto.id)),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byKey(FoodWeekKeys.thumb(corruptPhoto.id)),
          matching: find.byType(Image),
        ),
        findsNothing,
      );
      expect(
        find.byKey(FoodWeekKeys.thumbMissingPhoto(corruptPhoto.id)),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('05:00 food day boundary maps 04:59 Monday to prior week and '
        '04:59 next Monday to closed Sunday', (tester) async {
      final meals = TestMealStore();
      final priorWeek = meals.seed(DateTime(2026, 11, 9, 4, 59));
      final closedSundayLate = meals.seed(DateTime(2026, 11, 16, 4, 59));
      final currentWeekStart = meals.seed(DateTime(2026, 11, 16, 5));

      await _pumpWeekScreen(tester, meals: meals);

      expect(find.byKey(FoodWeekKeys.thumb(priorWeek.id)), findsNothing);
      expect(find.byKey(FoodWeekKeys.thumb(currentWeekStart.id)), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(FoodWeekKeys.dayColumn(_sunday)),
          matching: find.byKey(FoodWeekKeys.thumb(closedSundayLate.id)),
        ),
        findsOneWidget,
      );
    });

    testWidgets('empty week shows FoodWeekKeys.empty, single-record week uses '
        'singular "1 record", and multi-record week shows exact summary', (
      tester,
    ) async {
      final l10n = lookupAppLocalizations(const Locale('en'));
      final meals = TestMealStore()
        // Meal in the current open week must not count in the closed week.
        ..seed(DateTime(2026, 11, 17, 12), last: true);

      final container = await _pumpWeekScreen(tester, meals: meals);

      expect(find.byKey(FoodWeekKeys.empty), findsOneWidget);
      expect(find.text(l10n.foodWeekEmpty), findsOneWidget);

      meals.seed(DateTime(2026, 11, 9, 12));
      container.read(dataRevisionProvider.notifier).bump();
      await tester.pumpAndSettle();

      expect(find.byKey(FoodWeekKeys.empty), findsNothing);
      final singleSummary = l10n.foodWeekSummary(0, 1);
      expect(singleSummary, contains('1 record'));
      expect(singleSummary, isNot(contains('1 records')));
      expect(find.text(singleSummary), findsOneWidget);

      meals
        ..seed(DateTime(2026, 11, 9, 19), last: true)
        ..seed(DateTime(2026, 11, 10, 9))
        ..seed(DateTime(2026, 11, 10, 20), last: true)
        ..seed(DateTime(2026, 11, 11, 13));
      container.read(dataRevisionProvider.notifier).bump();
      await tester.pumpAndSettle();

      expect(find.text(l10n.foodWeekSummary(2, 5)), findsOneWidget);
    });

    testWidgets('tapping a thumbnail in GoRouter pushes /today/food/meal/:id '
        'and pop returns to FoodWeekScreen', (tester) async {
      final meals = TestMealStore();
      final meal = meals.seed(DateTime(2026, 11, 10, 12, 30));
      final container = await pumpOnboardingApp(
        tester,
        at: AppPaths.foodWeek,
        store: InMemoryOnboardingStore(completed: true),
        overrides: [
          ...bleOverrides(),
          ...ringOverrides(),
          ...onboardingOverrides(),
          ..._weekOverrides(meals: meals),
        ],
      );

      await tester.tap(find.byKey(FoodWeekKeys.thumb(meal.id)));
      await tester.pumpAndSettle();

      expect(
        container.read(appRouterProvider).state.uri.path,
        AppPaths.foodMealOf(meal.id),
      );
      expect(find.byType(FoodMealScreen), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.byType(FoodMealScreen), findsNothing);
      expect(find.byType(FoodWeekScreen), findsOneWidget);
      expect(
        container.read(appRouterProvider).state.uri.path,
        AppPaths.foodWeek,
      );
    });
  });

  group('Plate pattern card and soft mode', () {
    testWidgets('PlateBuilding renders when fewer than 5 complete days', (
      tester,
    ) async {
      final l10n = lookupAppLocalizations(const Locale('en'));
      final meals = TestMealStore();
      for (var i = 0; i < 4; i++) {
        final day = _monday.addDays(i);
        meals
          ..seed(DateTime(day.year, day.month, day.day, 8), kind: MealKind.main)
          ..seed(
            DateTime(day.year, day.month, day.day, 13),
            kind: MealKind.main,
          )
          ..seed(
            DateTime(day.year, day.month, day.day, 19),
            kind: MealKind.main,
            last: true,
          );
      }

      await _pumpWeekScreen(tester, meals: meals);

      expect(find.byKey(FoodWeekKeys.plateCard), findsOneWidget);
      expect(find.byKey(FoodWeekKeys.softModeCard), findsNothing);
      expect(find.text(l10n.foodPlateTitle), findsOneWidget);
      expect(find.text(l10n.foodPlateTag), findsOneWidget);
      expect(
        find.text(
          l10n.foodPlateBuilding(plateMinCompleteDays, plateMinMains, 4, 12),
        ),
        findsOneWidget,
      );
      expect(find.text(l10n.foodPlateNote), findsOneWidget);
    });

    testWidgets('PlateBuilding boundary: 5 complete days with 9 mains stays '
        'in building state', (tester) async {
      final l10n = lookupAppLocalizations(const Locale('en'));
      final meals = TestMealStore();
      for (var i = 0; i < 5; i++) {
        final day = _monday.addDays(i);
        if (i < 4) {
          meals.seed(
            DateTime(day.year, day.month, day.day, 12),
            kind: MealKind.main,
          );
        }
        meals.seed(
          DateTime(day.year, day.month, day.day, 19),
          kind: MealKind.main,
          last: true,
        );
      }

      await _pumpWeekScreen(tester, meals: meals);

      expect(
        find.text(
          l10n.foodPlateBuilding(plateMinCompleteDays, plateMinMains, 5, 9),
        ),
        findsOneWidget,
      );
    });

    testWidgets('PlatePattern renders 1-decimal score, counts with 1.5 '
        'alcohol drinks, note, zero calorie strings, and zero band words', (
      tester,
    ) async {
      final l10n = lookupAppLocalizations(const Locale('en'));
      final meals = TestMealStore();
      _seedFullPlateWeek(meals);
      final expected = platePattern(
        monday: _monday,
        meals: [for (final meal in meals.rows) meal.entry],
      ) as PlatePattern;

      await _pumpWeekScreen(tester, meals: meals);

      final format = MetricFormat.of(
        tester.element(find.byType(FoodWeekScreen)),
      );
      expect(find.byKey(FoodWeekKeys.plateCard), findsOneWidget);
      expect(find.text(l10n.foodPlateTitle), findsOneWidget);
      expect(find.text(l10n.foodPlateTag), findsOneWidget);
      expect(
        find.text(
          l10n.foodPlateSummary(
            format.decimal(expected.score, digits: 1),
            10,
            5,
          ),
        ),
        findsOneWidget,
      );
      expect(format.points(expected.drinks), '1.5');
      expect(
        find.text(
          l10n.foodPlateCounts(
            8,
            7,
            2,
            1,
            l10n.foodPlateDrinks(format.points(expected.drinks)),
          ),
        ),
        findsOneWidget,
      );
      expect(find.text(l10n.foodPlateNote), findsOneWidget);

      final allTexts = _allTextStrings(tester).join('\n').toLowerCase();
      expect(allTexts, isNot(contains('kcal')));
      expect(allTexts, isNot(contains('calor')));

      final plateTexts = _allTextStrings(
        tester,
        within: find.byKey(FoodWeekKeys.plateCard),
      ).join('\n').toLowerCase();
      for (final word in const [
        'optimal',
        'great',
        'good',
        'mixed',
        'fair',
        'low',
        'poor',
        'strong',
        'solid',
        'pay attention',
      ]) {
        expect(plateTexts, isNot(contains(word)));
      }
    });

    testWidgets('PlatePattern formats 4 alcohol drinks via format.points '
        'without trailing .0', (tester) async {
      final l10n = lookupAppLocalizations(const Locale('en'));
      final meals = TestMealStore();
      _seedFullPlateWeek(meals, alcohol: MealAlcohol.threeOrMore);

      await _pumpWeekScreen(tester, meals: meals);

      final format = MetricFormat.of(
        tester.element(find.byType(FoodWeekScreen)),
      );
      expect(format.points(4), '4');
      expect(
        find.text(l10n.foodPlateCounts(8, 7, 2, 1, l10n.foodPlateDrinks('4'))),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(FoodWeekKeys.plateCard),
          matching: find.textContaining('4.0'),
        ),
        findsNothing,
      );
    });

    testWidgets('softMode == true hides plateCard, renders softModeCard, and '
        'shows no calorie or weekly energy text', (tester) async {
      final l10n = lookupAppLocalizations(const Locale('en'));
      final meals = TestMealStore();
      _seedFullPlateWeek(meals);
      final goals = InMemoryGoalStore();
      await goals.addScreening(
        const GoalScreening(
          on: LocalDate(2026, 11, 1),
          softMode: true,
          pregnantOrBreastfeeding: null,
        ),
      );

      await _pumpWeekScreen(tester, meals: meals, goals: goals);

      expect(find.byKey(FoodWeekKeys.plateCard), findsNothing);
      expect(find.byKey(FoodWeekKeys.softModeCard), findsOneWidget);
      expect(find.text(l10n.foodWeekSoftTitle), findsOneWidget);
      expect(find.text(l10n.foodWeekSoftBody), findsOneWidget);

      final allTexts = _allTextStrings(tester).join('\n').toLowerCase();
      expect(allTexts, isNot(contains('kcal')));
      expect(allTexts, isNot(contains('calor')));
      expect(allTexts, isNot(contains('weekly energy')));
    });

    testWidgets('latest screening softMode == false shows plateCard instead of '
        'softModeCard', (tester) async {
      final meals = TestMealStore();
      _seedFullPlateWeek(meals);
      final goals = InMemoryGoalStore();
      await goals.addScreening(
        const GoalScreening(
          on: LocalDate(2026, 11, 1),
          softMode: true,
          pregnantOrBreastfeeding: null,
        ),
      );
      await goals.addScreening(
        const GoalScreening(
          on: LocalDate(2026, 11, 5),
          softMode: false,
          pregnantOrBreastfeeding: null,
        ),
      );

      await _pumpWeekScreen(tester, meals: meals, goals: goals);

      expect(find.byKey(FoodWeekKeys.plateCard), findsOneWidget);
      expect(find.byKey(FoodWeekKeys.softModeCard), findsNothing);
    });
  });

  group('errors and revision reload', () {
    testWidgets('throwing MealStore.between shows l10n.metricLoadError while '
        'keeping FoodSectionTabs', (tester) async {
      final l10n = lookupAppLocalizations(const Locale('en'));
      final meals = _ControllableMealStore(TestMealStore())
        ..throwOnBetween = true;

      await _pumpWeekScreen(tester, meals: meals);

      expect(find.text(l10n.metricLoadError), findsOneWidget);
      expect(find.byKey(FoodWeekKeys.tabs), findsOneWidget);
      expect(
        tester
            .widget<SegmentedButton<FoodSection>>(find.byKey(FoodWeekKeys.tabs))
            .selected,
        {FoodSection.week},
      );
      expect(find.byKey(FoodWeekKeys.contactSheet), findsNothing);
      expect(find.byKey(FoodWeekKeys.timingCard), findsNothing);
      expect(find.byKey(FoodWeekKeys.plateCard), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('throwing GoalStore.screenings() shows l10n.metricLoadError '
        'and hides plateCard', (tester) async {
      final l10n = lookupAppLocalizations(const Locale('en'));
      final meals = TestMealStore();
      _seedFullPlateWeek(meals);

      await _pumpWeekScreen(
        tester,
        meals: meals,
        goals: const _ThrowingGoalStore(),
      );

      expect(find.text(l10n.metricLoadError), findsOneWidget);
      expect(find.byKey(FoodWeekKeys.tabs), findsOneWidget);
      expect(find.byKey(FoodWeekKeys.timingCard), findsNothing);
      expect(find.byKey(FoodWeekKeys.plateCard), findsNothing);
      expect(find.byKey(FoodWeekKeys.softModeCard), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('dataRevisionProvider bump keeps content mounted while '
        'reloading and updates counts cleanly', (tester) async {
      final l10n = lookupAppLocalizations(const Locale('en'));
      final inner = TestMealStore()..seed(DateTime(2026, 11, 9, 12, 30));
      final meals = _ControllableMealStore(inner);

      final container = await _pumpWeekScreen(tester, meals: meals);

      expect(find.byKey(FoodWeekKeys.contactSheet), findsOneWidget);
      expect(find.byKey(FoodWeekKeys.timingCard), findsOneWidget);
      expect(find.byKey(FoodWeekKeys.plateCard), findsOneWidget);
      expect(find.text(l10n.foodWeekSummary(0, 1)), findsOneWidget);

      final reloadGate = Completer<void>();
      meals.betweenGate = reloadGate;
      inner.seed(DateTime(2026, 11, 9, 19, 30), last: true);

      container.read(dataRevisionProvider.notifier).bump();
      await tester.pump();

      expect(find.byKey(FoodWeekKeys.contactSheet), findsOneWidget);
      expect(find.byKey(FoodWeekKeys.timingCard), findsOneWidget);
      expect(find.byKey(FoodWeekKeys.plateCard), findsOneWidget);

      reloadGate.complete();
      await tester.pumpAndSettle();

      expect(find.text(l10n.foodWeekSummary(1, 2)), findsOneWidget);
    });
  });

  group('timing card and evidence sheets', () {
    testWidgets('renders timing card between contact sheet and plate card, '
        'stays visible in soft mode, and opens Window/Gap sheets', (
      tester,
    ) async {
      final l10n = lookupAppLocalizations(const Locale('en'));
      final meals = TestMealStore()
        ..seed(DateTime(2026, 11, 9, 8))
        ..seed(DateTime(2026, 11, 9, 19), last: true)
        ..seed(DateTime(2026, 11, 10, 9))
        ..seed(DateTime(2026, 11, 10, 21), last: true);
      final nights = [
        FoodNight(day: _monday, sleepOnset: DateTime.utc(2026, 11, 9, 23)),
        FoodNight(
          day: _monday.addDays(1),
          sleepOnset: DateTime.utc(2026, 11, 10, 23),
        ),
      ];

      await _pumpWeekScreen(tester, meals: meals, nights: nights);

      expect(find.byKey(FoodWeekKeys.timingCard), findsOneWidget);
      expect(find.byKey(FoodWeekKeys.timingChart), findsOneWidget);
      expect(find.text(l10n.foodTimingTitle), findsOneWidget);
      expect(find.text(l10n.foodTimingCompleteDays(2)), findsOneWidget);
      expect(find.text('11 h 30 min'), findsOneWidget);
      expect(find.text('3 h'), findsOneWidget);

      final contactY = tester
          .getTopLeft(find.byKey(FoodWeekKeys.contactSheet))
          .dy;
      final timingY = tester.getTopLeft(find.byKey(FoodWeekKeys.timingCard)).dy;
      final plateY = tester.getTopLeft(find.byKey(FoodWeekKeys.plateCard)).dy;
      expect(timingY, greaterThan(contactY));
      expect(plateY, greaterThan(timingY));

      await tester.tap(find.byKey(FoodWeekKeys.windowRow));
      await tester.pumpAndSettle();

      expect(find.byKey(FoodWeekEvidenceKeys.sheet), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(FoodWeekEvidenceKeys.title)).data,
        l10n.foodWindowTitle,
      );
      expect(
        tester.widget<Text>(find.byKey(FoodWeekEvidenceKeys.value)).data,
        '11 h 30 min',
      );

      await tester.ensureVisible(find.byKey(FoodWeekEvidenceKeys.close));
      await tester.tap(find.byKey(FoodWeekEvidenceKeys.close));
      await tester.pumpAndSettle();
      expect(find.byKey(FoodWeekEvidenceKeys.sheet), findsNothing);

      await tester.tap(find.byKey(FoodWeekKeys.gapRow));
      await tester.pumpAndSettle();

      expect(find.byKey(FoodWeekEvidenceKeys.sheet), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(FoodWeekEvidenceKeys.title)).data,
        l10n.foodWeekGapTitle,
      );
      expect(
        tester.widget<Text>(find.byKey(FoodWeekEvidenceKeys.value)).data,
        '3 h',
      );
    });

    testWidgets('stays visible between contact sheet and soft mode card', (
      tester,
    ) async {
      final meals = TestMealStore()
        ..seed(DateTime(2026, 11, 9, 12), last: true);
      final goals = InMemoryGoalStore();
      await goals.addScreening(
        const GoalScreening(
          on: LocalDate(2026, 11, 1),
          softMode: true,
          pregnantOrBreastfeeding: null,
        ),
      );

      await _pumpWeekScreen(tester, meals: meals, goals: goals);

      expect(find.byKey(FoodWeekKeys.timingCard), findsOneWidget);
      expect(find.byKey(FoodWeekKeys.softModeCard), findsOneWidget);
      final timingY = tester.getTopLeft(find.byKey(FoodWeekKeys.timingCard)).dy;
      final softY = tester.getTopLeft(find.byKey(FoodWeekKeys.softModeCard)).dy;
      expect(softY, greaterThan(timingY));
    });

    testWidgets('plain-drink-only day keeps thumbnail, shows metricNoReading '
        'for window and gap, and disables evidence taps', (tester) async {
      final l10n = lookupAppLocalizations(const Locale('en'));
      final drink = TestMealStore();
      final drinkMeal = drink.seed(
        DateTime(2026, 11, 9, 9),
        kind: MealKind.drink,
        last: true,
      );
      final drinkId = drinkMeal.id;
      final nights = [
        FoodNight(day: _monday, sleepOnset: DateTime.utc(2026, 11, 9, 23)),
      ];

      await _pumpWeekScreen(tester, meals: drink, nights: nights);

      expect(find.byKey(FoodWeekKeys.thumb(drinkId)), findsOneWidget);
      expect(find.byType(FoodTimingChart), findsOneWidget);
      expect(find.text(l10n.metricNoReading), findsNWidgets(2));
      expect(
        find.descendant(
          of: find.byKey(FoodWeekKeys.windowRow),
          matching: find.byIcon(Icons.chevron_right_rounded),
        ),
        findsNothing,
      );

      await tester.tap(find.byKey(FoodWeekKeys.windowRow));
      await tester.pumpAndSettle();
      expect(find.byKey(FoodWeekEvidenceKeys.sheet), findsNothing);
    });

    testWidgets('all meals after sleepOnset leave window interactive and drop '
        'gap with no sheet', (tester) async {
      final l10n = lookupAppLocalizations(const Locale('en'));
      final lateMeal = TestMealStore()
        ..seed(DateTime(2026, 11, 15, 23, 45))
        ..seed(DateTime(2026, 11, 16, 0, 30), kind: MealKind.snack, last: true);
      final nights = [
        FoodNight(day: _sunday, sleepOnset: DateTime.utc(2026, 11, 15, 23, 30)),
      ];

      await _pumpWeekScreen(tester, meals: lateMeal, nights: nights);

      expect(find.text('45 min'), findsOneWidget);
      expect(find.text(l10n.metricNoReading), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(FoodWeekKeys.gapRow),
          matching: find.byIcon(Icons.chevron_right_rounded),
        ),
        findsNothing,
      );

      await tester.tap(find.byKey(FoodWeekKeys.gapRow));
      await tester.pumpAndSettle();
      expect(find.byKey(FoodWeekEvidenceKeys.sheet), findsNothing);

      await tester.tap(find.byKey(FoodWeekKeys.windowRow));
      await tester.pumpAndSettle();
      expect(find.byKey(FoodWeekEvidenceKeys.sheet), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(FoodWeekEvidenceKeys.title)).data,
        l10n.foodWindowTitle,
      );
    });

    testWidgets('mixed post-onset day computes gapCount < windowCount across '
        'sheets', (tester) async {
      final l10n = lookupAppLocalizations(const Locale('en'));
      final mixed = TestMealStore()
        ..seed(DateTime(2026, 11, 9, 8))
        ..seed(DateTime(2026, 11, 9, 19), last: true)
        ..seed(DateTime(2026, 11, 15, 23, 45), last: true);
      final mixedNights = [
        FoodNight(day: _monday, sleepOnset: DateTime.utc(2026, 11, 9, 23)),
        FoodNight(day: _sunday, sleepOnset: DateTime.utc(2026, 11, 15, 23, 30)),
      ];

      await _pumpWeekScreen(tester, meals: mixed, nights: mixedNights);

      expect(find.text('5 h 30 min'), findsOneWidget);
      expect(find.text('4 h'), findsOneWidget);

      await tester.tap(find.byKey(FoodWeekKeys.windowRow));
      await tester.pumpAndSettle();
      expect(
        find.text(l10n.foodSheetDaysYours(2, '0 min, 11 h', '5 h 30 min')),
        findsOneWidget,
      );

      await tester.ensureVisible(find.byKey(FoodWeekEvidenceKeys.close));
      await tester.tap(find.byKey(FoodWeekEvidenceKeys.close));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(FoodWeekKeys.gapRow));
      await tester.pumpAndSettle();
      expect(
        find.text(l10n.foodSheetDaysYours(1, '4 h', '4 h')),
        findsOneWidget,
      );
    });

    testWidgets(
      'missing sleepOnset leaves window interactive and gap disabled',
      (tester) async {
        final l10n = lookupAppLocalizations(const Locale('en'));
        final wornOff = TestMealStore()
          ..seed(DateTime(2026, 11, 9, 8))
          ..seed(DateTime(2026, 11, 9, 18), last: true);

        await _pumpWeekScreen(tester, meals: wornOff);

        expect(find.text('10 h'), findsOneWidget);
        expect(find.text(l10n.metricNoReading), findsOneWidget);

        await tester.tap(find.byKey(FoodWeekKeys.gapRow));
        await tester.pumpAndSettle();
        expect(find.byKey(FoodWeekEvidenceKeys.sheet), findsNothing);

        await tester.tap(find.byKey(FoodWeekKeys.windowRow));
        await tester.pumpAndSettle();
        expect(find.byKey(FoodWeekEvidenceKeys.sheet), findsOneWidget);
      },
    );
  });

  group('Weekly energy tile', () {
    const off = 'Off. One range a week, never per meal.';
    const on = FoodEnergyOn(LocalDate(2026, 11, 1));
    const counts = FoodEnergyCounts(
      sunday: LocalDate(2026, 12, 6),
      days: 12,
      weekDays: 4,
      weighIns: 9,
      ringDays: 30,
    );
    final ready = FoodEnergyReady(
      const FoodEnergyCounts(
        sunday: LocalDate(2026, 11, 29),
        days: 30,
        weekDays: 6,
        weighIns: 28,
        ringDays: 35,
      ),
      foodEnergyFigures(
        slopeKgPerDay: -0.03,
        logMean: 1780,
        weekMean: 1700,
        previousMean: 1800,
        ringMean: 2500,
      ),
    );

    Future<void> pumpWith(
      WidgetTester tester,
      FoodEnergyGate gate, {
      FoodEnergyResult? result,
      double scale = 1,
    }) async {
      await _pumpWeekScreen(
        tester,
        scale: scale,
        overrides: [
          ..._weekOverrides(meals: TestMealStore()),
          foodEnergyGateProvider.overrideWith((ref) async => gate),
          if (result != null)
            foodEnergyProvider.overrideWith(
              (ref) async => FoodEnergyView(gate: gate, result: result),
            ),
        ],
      );
      await tester.pumpAndSettle();
    }

    for (final gate in const <FoodEnergyGate>[
      FoodEnergyOffered(LocalDate(2026, 11, 1)),
      FoodEnergyNeedsScreening(),
      FoodEnergyBlocked(FoodEnergyBlock.bodyOff),
    ]) {
      testWidgets('${gate.runtimeType} shows the title and the off line', (
        tester,
      ) async {
        await pumpWith(tester, gate);

        expect(find.byKey(FoodWeekKeys.energyTile), findsOneWidget);
        expect(find.text('Weekly energy'), findsOneWidget);
        expect(find.text(off), findsOneWidget);
      });
    }

    testWidgets('on with a failed read shows the title without the off '
        'line', (tester) async {
      await pumpWith(tester, on);

      expect(find.byKey(FoodWeekKeys.energyTile), findsOneWidget);
      expect(find.text(off), findsNothing);
    });

    // Each card renders at 1x and 2x text with no overflow: the layout golden.
    for (final scale in [1.0, 2.0]) {
      testWidgets('demo shows the labelled sample range at ${scale}x', (
        tester,
      ) async {
        await pumpWith(tester, const FoodEnergyDemo(), scale: scale);

        final tile = find.byKey(FoodWeekKeys.energyTile);
        for (final text in [
          'Weekly energy',
          'range',
          'Sample with invented numbers. Nothing of yours was used.',
          '1,800 to 2,450 kcal a day, on average',
          '5% to 30% under',
        ]) {
          expect(
            find.descendant(of: tile, matching: find.text(text)),
            findsOneWidget,
            reason: text,
          );
        }
        expect(find.text(off), findsNothing);
      });

      testWidgets('on with a range shows the range and the gap at ${scale}x', (
        tester,
      ) async {
        await pumpWith(tester, on, result: ready, scale: scale);

        expect(find.text('range'), findsOneWidget);
        expect(find.text('1,800 to 2,450 kcal a day, on average'), findsOne);
        expect(find.text('5% to 30% under'), findsOneWidget);
        expect(
          find.text('Sample with invented numbers. Nothing of yours was used.'),
          findsNothing,
        );
      });

      testWidgets('on and holding shows the last range at ${scale}x', (
        tester,
      ) async {
        await pumpWith(
          tester,
          on,
          result: FoodEnergyHold(
            counts,
            FoodEnergyHoldReason.weighIns,
            last: ready,
          ),
          scale: scale,
        );

        expect(find.text('holding'), findsOneWidget);
        expect(find.text('Last range, Nov 23 to Nov 29'), findsOneWidget);
        expect(find.text('1,800 to 2,450 kcal a day, on average'), findsOne);
      });

      testWidgets('on and building shows the days count at ${scale}x', (
        tester,
      ) async {
        await pumpWith(
          tester,
          on,
          result: const FoodEnergyHold(counts, FoodEnergyHoldReason.days),
          scale: scale,
        );

        expect(find.text('building'), findsOneWidget);
        expect(
          find.text('Days with checked items in the last 35 days'),
          findsOneWidget,
        );
        expect(find.text('12 of 28'), findsOneWidget);
        expect(find.textContaining('kcal'), findsNothing);
      });
    }

    for (final gate in const <FoodEnergyGate>[
      FoodEnergyHidden(),
      FoodEnergyBlocked(FoodEnergyBlock.softMode),
    ]) {
      testWidgets('${gate.runtimeType} shows no tile', (tester) async {
        await pumpWith(tester, gate);

        expect(find.byKey(FoodWeekKeys.energyTile), findsNothing);
        expect(find.byKey(FoodWeekKeys.plateCard), findsOneWidget);
      });
    }

    testWidgets('AI off gives no tile from the real gate', (tester) async {
      await _pumpWeekScreen(tester);
      await tester.pumpAndSettle();

      expect(find.byKey(FoodWeekKeys.energyTile), findsNothing);
    });
  });
}

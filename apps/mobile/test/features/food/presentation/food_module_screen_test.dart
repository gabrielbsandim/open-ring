import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/app/router/app_router.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/core/widgets/state_views.dart';
import 'package:open_ring/features/ai/application/ai_config_providers.dart';
import 'package:open_ring/features/ai/application/analysis_run_controller.dart';
import 'package:open_ring/features/ai/domain/ai_config.dart';
import 'package:open_ring/features/ai/domain/secret_store.dart';
import 'package:open_ring/features/food/application/meal_photo_saver.dart';
import 'package:open_ring/features/food/application/meal_store_providers.dart';
import 'package:open_ring/features/food/domain/meal.dart';
import 'package:open_ring/features/food/domain/meal_store.dart';
import 'package:open_ring/features/food/domain/photo_store.dart';
import 'package:open_ring/features/food/presentation/food_energy_screen.dart';
import 'package:open_ring/features/food/presentation/food_formula_screen.dart';
import 'package:open_ring/features/food/presentation/food_module_screen.dart';
import 'package:open_ring/features/food/presentation/food_storage_screen.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/modules/domain/module_store.dart';
import 'package:open_ring/features/modules/presentation/module_widgets.dart';
import 'package:open_ring/features/settings/presentation/settings_widgets.dart';
import 'package:open_ring/features/today/presentation/today_screen.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

import '../../../helpers/ai_fakes.dart';
import '../../../helpers/ble_fakes.dart';
import '../../../helpers/layout_harness.dart';
import '../../../helpers/onboarding_app.dart';
import '../../../helpers/onboarding_fakes.dart';
import '../../../helpers/ring_fakes.dart';
import '../food_fakes.dart';

final _now = DateTime(2026, 11, 21, 15);

final class _GatedClearMealStore implements MealStore {
  final inner = TestMealStore();
  final gate = Completer<void>();
  int clearCalls = 0;

  @override
  Future<int> clear() async {
    clearCalls++;
    await gate.future;
    return await inner.clear();
  }

  @override
  Future<int> count() => inner.count();

  @override
  Future<List<MealPhotoRef>> photoRefs() => inner.photoRefs();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

final class _FailingClearMealStore implements MealStore {
  final inner = TestMealStore();

  @override
  Future<int> clear() async => throw const FileSystemException('locked');

  @override
  Future<int> count() => inner.count();

  @override
  Future<List<MealPhotoRef>> photoRefs() => inner.photoRefs();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

final class _ErrorCountMealStore implements MealStore {
  @override
  Future<List<MealPhotoRef>> photoRefs() async =>
      throw const FileSystemException('corrupt');

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

final class _GatedModuleStore implements ModuleStore {
  new({this.gate, this.fail = false});

  final Completer<void>? gate;
  final bool fail;
  Set<ModuleId> _enabled = {};
  int writeCalls = 0;

  @override
  Future<Set<ModuleId>> read() async => {..._enabled};

  @override
  Future<void> write(Set<ModuleId> enabled) async {
    writeCalls++;
    await gate?.future;
    if (fail) throw const FileSystemException('disk full');
    _enabled = {...enabled};
  }

  @override
  Future<bool> shortcutDismissed() async => false;

  @override
  Future<void> dismissShortcut({required bool dismissed}) async {}
}

Future<dynamic> _pumpModule(
  WidgetTester tester, {
  bool foodOn = false,
  MealStore? meals,
  PhotoStore? photos,
  ModuleStore? moduleStore,
  List<Override> extra = const [],
}) async {
  final store = moduleStore ?? InMemoryModuleStore({if (foodOn) ModuleId.food});
  final mealStore = meals ?? TestMealStore();
  final photoStore = photos ?? InMemoryPhotoStore();
  final container = await pumpOnboardingApp(
    tester,
    store: InMemoryOnboardingStore(completed: true),
    overrides: [
      ...bleOverrides(),
      ...ringOverrides(),
      ...onboardingOverrides(),
      clockProvider.overrideWithValue(() => _now),
      mealStoreProvider.overrideWithValue(mealStore),
      photoStoreProvider.overrideWithValue(photoStore),
      mealCameraProvider.overrideWithValue(GatedMealCamera()),
      mealPhotoSaverProvider.overrideWith(
        (ref) => MealPhotoSaver(
          ref.watch(mealStoreProvider),
          ref.watch(photoStoreProvider),
          now: () => _now,
          random: Random(7),
          offsetAt: localOffset,
        ),
      ),
      moduleStoreProvider.overrideWithValue(store),
      ...extra,
    ],
  );
  container.read(appRouterProvider).go(AppPaths.settingsModuleFood);
  await tester.pumpAndSettle();
  expect(find.byType(FoodModuleScreen), findsOneWidget);
  return container;
}

Future<void> _seedOneMeal(TestMealStore meals, PhotoStore photos) async {
  await photos.save('a.jpg', Uint8List(500000));
  await meals.add(
    MealDraft(at: _now.toUtc(), offsetMinutes: localOffset(_now)),
    now: _now.toUtc(),
    photo: 'a.jpg',
  );
}

void main() {
  group('FoodModuleScreen', () {
    test('route path matches /ring/settings/modules/food', () {
      expect(AppPaths.settingsModuleFood, '/ring/settings/modules/food');
    });

    testWidgets(
      'off with kept data shows kept card, facts without AI/energy, and turns on',
      (tester) async {
        final meals = TestMealStore();
        final photos = InMemoryPhotoStore();
        await _seedOneMeal(meals, photos);
        final modules = InMemoryModuleStore();
        await _pumpModule(
          tester,
          meals: meals,
          photos: photos,
          moduleStore: modules,
        );

        final l10n = lookupAppLocalizations(const Locale('en'));
        final pill = tester.widget<ModuleStatePill>(
          find.byKey(FoodModuleKeys.state),
        );
        expect(pill.on, isFalse);
        expect(pill.label, l10n.modulesOff);
        expect(find.byKey(FoodModuleKeys.kept), findsOneWidget);
        expect(find.text(l10n.moduleFoodStoresAi), findsNothing);
        expect(find.byKey(FoodModuleKeys.aiPhotos), findsNothing);
        expect(find.textContaining('Weekly energy'), findsNothing);

        await tester.scrollUntilVisible(
          find.byKey(FoodModuleKeys.toggle),
          150,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.ensureVisible(find.byKey(FoodModuleKeys.toggle));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(FoodModuleKeys.toggle));
        await tester.pumpAndSettle();

        expect(await modules.read(), {ModuleId.food});
        expect(find.byKey(FoodModuleKeys.kept), findsNothing);
        expect(
          find.text(l10n.moduleFoodTurnedOn(l10n.tabToday)),
          findsOneWidget,
        );
        await tester.scrollUntilVisible(
          find.byKey(FoodModuleKeys.state),
          -150,
          scrollable: find.byType(Scrollable).first,
        );
        final pillOn = tester.widget<ModuleStatePill>(
          find.byKey(FoodModuleKeys.state),
        );
        expect(pillOn.on, isTrue);
        expect(pillOn.label, l10n.modulesOn);

        await tester.tap(find.text(l10n.modulesView));
        await tester.pumpAndSettle();
        expect(find.byType(TodayScreen), findsOneWidget);
      },
    );

    testWidgets('turning off preserves data and hides kept card when empty', (
      tester,
    ) async {
      await _pumpModule(tester);
      expect(find.byKey(FoodModuleKeys.kept), findsNothing);

      final meals = TestMealStore();
      final photos = InMemoryPhotoStore();
      await _seedOneMeal(meals, photos);
      final modules = InMemoryModuleStore({ModuleId.food});
      await _pumpModule(
        tester,
        foodOn: true,
        meals: meals,
        photos: photos,
        moduleStore: modules,
      );

      final l10n = lookupAppLocalizations(const Locale('en'));
      final pill = tester.widget<ModuleStatePill>(
        find.byKey(FoodModuleKeys.state),
      );
      expect(pill.on, isTrue);
      expect(pill.label, l10n.modulesOn);
      expect(find.byKey(FoodModuleKeys.kept), findsNothing);
      await tester.scrollUntilVisible(
        find.byKey(FoodModuleKeys.toggle),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.byKey(FoodModuleKeys.toggle));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(FoodModuleKeys.toggle));
      await tester.pumpAndSettle();

      expect(await modules.read(), isEmpty);
      expect(await meals.count(), 1);
      expect(await photos.totalBytes(), 500000);
    });

    testWidgets('links push FoodStorageScreen and FoodFormulaScreen', (
      tester,
    ) async {
      final meals = TestMealStore();
      final photos = InMemoryPhotoStore();
      await _seedOneMeal(meals, photos);
      await _pumpModule(tester, meals: meals, photos: photos);

      await tester.scrollUntilVisible(
        find.byKey(FoodModuleKeys.photos),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(FoodModuleKeys.photos));
      await tester.pumpAndSettle();
      expect(find.byType(FoodStorageScreen), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.byKey(FoodModuleKeys.formula),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(FoodModuleKeys.formula));
      await tester.pumpAndSettle();
      expect(find.byType(FoodFormulaScreen), findsOneWidget);
    });

    testWidgets(
      'delete cancel keeps data; confirm clears with double-tap guard',
      (tester) async {
        final meals = _GatedClearMealStore();
        final photos = InMemoryPhotoStore();
        await _seedOneMeal(meals.inner, photos);
        await _pumpModule(tester, meals: meals, photos: photos);

        await tester.scrollUntilVisible(
          find.byKey(FoodModuleKeys.delete),
          150,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(find.byKey(FoodModuleKeys.delete));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(FoodModuleKeys.deleteCancel));
        await tester.pumpAndSettle();
        expect(await meals.count(), 1);

        await tester.tap(find.byKey(FoodModuleKeys.delete));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(FoodModuleKeys.deleteConfirm));
        await tester.pump();

        final buttonDuring = tester.widget<OutlinedButton>(
          find.byKey(FoodModuleKeys.delete),
        );
        expect(buttonDuring.onPressed, isNull);
        expect(meals.clearCalls, 1);

        meals.gate.complete();
        await tester.pumpAndSettle();

        final l10n = lookupAppLocalizations(const Locale('en'));
        expect(find.text(l10n.moduleFoodDeleted), findsOneWidget);
        expect(find.byKey(FoodModuleKeys.kept), findsNothing);
        expect(find.byKey(FoodModuleKeys.delete), findsNothing);
        expect(find.text(l10n.moduleFoodDataEmpty), findsOneWidget);
        expect(await photos.totalBytes(), 0);
      },
    );

    testWidgets(
      'delete failure shows error SnackBar and store count error shows metricLoadError',
      (tester) async {
        final meals = _FailingClearMealStore();
        final photos = InMemoryPhotoStore();
        await _seedOneMeal(meals.inner, photos);
        await _pumpModule(tester, meals: meals, photos: photos);

        await tester.scrollUntilVisible(
          find.byKey(FoodModuleKeys.delete),
          150,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(find.byKey(FoodModuleKeys.delete));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(FoodModuleKeys.deleteConfirm));
        await tester.pumpAndSettle();

        final l10n = lookupAppLocalizations(const Locale('en'));
        expect(find.text(l10n.moduleFoodDeleteFailed), findsOneWidget);
        expect(await meals.count(), 1);

        await _pumpModule(tester, meals: _ErrorCountMealStore());
        await tester.scrollUntilVisible(
          find.byKey(FoodModuleKeys.stored),
          150,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text(l10n.metricLoadError), findsWidgets);
      },
    );

    testWidgets(
      'toggle guards double-tap while pending and shows error on write failure',
      (tester) async {
        final gate = Completer<void>();
        final gated = _GatedModuleStore(gate: gate);
        await _pumpModule(tester, moduleStore: gated);

        await tester.scrollUntilVisible(
          find.byKey(FoodModuleKeys.toggle),
          150,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.ensureVisible(find.byKey(FoodModuleKeys.toggle));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(FoodModuleKeys.toggle));
        await tester.pump();

        expect(
          tester
              .widget<ActionButton>(find.byKey(FoodModuleKeys.toggle))
              .onPressed,
          isNull,
        );
        await tester.tap(
          find.byKey(FoodModuleKeys.toggle),
          warnIfMissed: false,
        );
        expect(gated.writeCalls, 1);

        gate.complete();
        await tester.pumpAndSettle();
        expect(await gated.read(), {ModuleId.food});

        await _pumpModule(tester, moduleStore: _GatedModuleStore(fail: true));
        await tester.scrollUntilVisible(
          find.byKey(FoodModuleKeys.toggle),
          150,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.ensureVisible(find.byKey(FoodModuleKeys.toggle));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(FoodModuleKeys.toggle));
        await tester.pumpAndSettle();
        final l10n = lookupAppLocalizations(const Locale('en'));
        expect(find.text(l10n.syncErrorSaving), findsOneWidget);
      },
    );

    testWidgets('toggle works without GoRouter ancestor', (tester) async {
      await pumpScaled(
        tester,
        screenHost(const FoodModuleScreen()),
        textScaler: TextScaler.noScaling,
        brightness: Brightness.dark,
        locale: const Locale('en'),
        overrides: [
          moduleStoreProvider.overrideWithValue(InMemoryModuleStore()),
          clockProvider.overrideWithValue(() => _now),
          mealStoreProvider.overrideWithValue(TestMealStore()),
          photoStoreProvider.overrideWithValue(InMemoryPhotoStore()),
        ],
      );
      await tester.scrollUntilVisible(
        find.byKey(FoodModuleKeys.toggle),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.byKey(FoodModuleKeys.toggle));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(FoodModuleKeys.toggle));
      await tester.pumpAndSettle();
      final l10n = lookupAppLocalizations(const Locale('en'));
      expect(find.text(l10n.moduleFoodTurnedOn(l10n.tabToday)), findsOneWidget);
    });

    group('with AI analysis', () {
      const hostKey = 'https://api.example.com:443';
      late InMemoryAiConfigStore configs;
      late InMemorySecretStore secrets;
      late int built;
      final l10n = lookupAppLocalizations(const Locale('en'));

      setUp(() {
        built = 0;
        configs = InMemoryAiConfigStore()
          ..config = const AiConfig(
            baseUrl: 'https://api.example.com/v1',
            model: 'vision-m',
            keyLastFour: 'ab3X',
          )
          ..mealPhotoConsent = const AiMealPhotoConsent(
            consentedAtUtcMs: 0,
            policyEffectiveDate: aiCurrentPolicyEffectiveDate,
            hostKey: hostKey,
          );
        secrets = InMemorySecretStore()..values[aiApiKeySecretName] = 'sk-ab3X';
      });

      List<Override> aiOverrides() => [
        aiConfigStoreProvider.overrideWithValue(configs),
        secretStoreProvider.overrideWithValue(secrets),
        keyedAnalysisModelFactoryProvider.overrideWithValue(
          (config, key) => throw StateError('built ${++built}'),
        ),
      ];

      Future<void> pumpScreen(
        WidgetTester tester, {
        required Set<ModuleId> modules,
        double scale = 1,
      }) => pumpScaled(
        tester,
        screenHost(const FoodModuleScreen()),
        textScaler: TextScaler.linear(scale),
        brightness: Brightness.light,
        locale: const Locale('en'),
        overrides: [
          moduleStoreProvider.overrideWithValue(InMemoryModuleStore(modules)),
          clockProvider.overrideWithValue(() => _now),
          mealStoreProvider.overrideWithValue(TestMealStore()),
          photoStoreProvider.overrideWithValue(InMemoryPhotoStore()),
          ...aiOverrides(),
        ],
      );

      Future<void> reach(WidgetTester tester, Finder finder) =>
          expectNoLayoutOverflow(
            () => tester.scrollUntilVisible(
              finder,
              200,
              scrollable: find.byType(Scrollable).first,
            ),
          );

      String? detail(WidgetTester tester, Key key) =>
          tester.widget<SettingsTile>(find.byKey(key)).detail;

      for (final scale in const [1.0, 2.0]) {
        testWidgets('AI and Food on at ${scale}x: facts, photo card, Weekly '
            'energy row and the AI formula caption', (tester) async {
          await pumpScreen(
            tester,
            modules: {ModuleId.ai, ModuleId.food},
            scale: scale,
          );

          for (final finder in [
            find.text(l10n.moduleFoodAddsAi('on')),
            find.text(l10n.moduleFoodStoresAi),
            find.text(l10n.moduleFoodNeverCalories),
            find.byKey(FoodModuleKeys.aiPhotos),
            find.byKey(FoodModuleKeys.aiWithdraw),
            find.byKey(FoodModuleKeys.energy),
            find.text(l10n.moduleFoodFormulaCaptionAi),
          ]) {
            await reach(tester, finder);
            expect(finder, findsOneWidget);
          }
          expect(
            detail(tester, FoodModuleKeys.aiPhotos),
            startsWith(
              '${l10n.moduleFoodAiPhotos('api.example.com')} '
              'Consent given for api.example.com on ',
            ),
          );
          expect(built, 0);
        });
      }

      testWidgets('AI off renders as before: no AI fact, card or caption', (
        tester,
      ) async {
        await pumpScreen(tester, modules: {ModuleId.food});

        await reach(tester, find.byKey(FoodModuleKeys.toggle));
        for (final finder in [
          find.text(l10n.moduleFoodAddsAi('on')),
          find.text(l10n.moduleFoodStoresAi),
          find.byKey(FoodModuleKeys.aiPhotos),
          find.byKey(FoodModuleKeys.energy),
          find.text(l10n.moduleFoodFormulaCaptionAi),
        ]) {
          expect(finder, findsNothing);
        }
        expect(find.text(l10n.moduleFoodFormulaCaption), findsOneWidget);
      });

      testWidgets('withdraw clears the photo consent and sends nothing', (
        tester,
      ) async {
        await pumpScreen(tester, modules: {ModuleId.ai, ModuleId.food});
        await reach(tester, find.byKey(FoodModuleKeys.energy));
        await tester.ensureVisible(find.byKey(FoodModuleKeys.aiWithdraw));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(FoodModuleKeys.aiWithdraw));
        await tester.pumpAndSettle();

        expect(configs.mealPhotoConsent, isNull);
        expect(find.byKey(FoodModuleKeys.aiWithdraw), findsNothing);
        expect(
          detail(tester, FoodModuleKeys.aiPhotos),
          '${l10n.moduleFoodAiPhotos('api.example.com')} '
          '${l10n.aiPhotosConsentNone}',
        );
        expect(configs.config.keyLastFour, 'ab3X');
        expect(built, 0);
      });

      testWidgets('no address reads Not connected', (tester) async {
        configs.config = AiConfig.defaults;
        await pumpScreen(tester, modules: {ModuleId.ai, ModuleId.food});
        await reach(tester, find.byKey(FoodModuleKeys.aiPhotos));

        expect(detail(tester, FoodModuleKeys.aiPhotos), 'Not connected');
        expect(find.byKey(FoodModuleKeys.aiWithdraw), findsNothing);
      });

      testWidgets('the Weekly energy row opens the energy screen', (
        tester,
      ) async {
        await _pumpModule(
          tester,
          moduleStore: InMemoryModuleStore({ModuleId.ai, ModuleId.food}),
          extra: aiOverrides(),
        );
        await tester.scrollUntilVisible(
          find.byKey(FoodModuleKeys.energy),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(detail(tester, FoodModuleKeys.energy), l10n.foodEnergyTileOff);

        await tester.tap(find.byKey(FoodModuleKeys.energy));
        await tester.pumpAndSettle();

        expect(find.byType(FoodEnergyScreen), findsOneWidget);
        expect(built, 0);
      });
    });
  });
}

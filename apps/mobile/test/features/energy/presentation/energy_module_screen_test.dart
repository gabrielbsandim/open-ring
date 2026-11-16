import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/l10n/app_locales.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/theme/app_theme.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/features/body/application/hide_numbers_controller.dart';
import 'package:open_ring/features/body/domain/hide_numbers_store.dart';
import 'package:open_ring/features/energy/presentation/energy_module_screen.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/modules/domain/module_store.dart';
import 'package:open_ring/features/settings/application/user_profile_providers.dart';
import 'package:open_ring/features/settings/domain/user_profile.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

import '../../../helpers/layout_harness.dart';
import '../../../helpers/settings_fakes.dart';

final DateTime _now = DateTime.utc(2026, 11, 10, 12);

UserProfile _aged(int age) => UserProfile(
  birthYear: UserProfile.birthYearFor(age, year: _now.year),
  sex: Sex.male,
  heightCentimeters: 175,
  weightKilograms: 70,
);

List<Override> _overrides({
  required InMemoryModuleStore modules,
  UserProfile? profile,
  bool hidden = false,
}) => [
  clockProvider.overrideWithValue(() => _now),
  moduleStoreProvider.overrideWithValue(modules),
  userProfileStoreProvider.overrideWithValue(InMemoryUserProfileStore(profile)),
  hideNumbersStoreProvider.overrideWithValue(
    InMemoryHideNumbersStore(hidden: hidden),
  ),
];

Future<GoRouter> _pump(
  WidgetTester tester, {
  Set<ModuleId> stored = const {},
  UserProfile? profile,
  bool hidden = false,
  InMemoryModuleStore? store,
  Locale locale = const Locale('en'),
  TextScaler textScaler = TextScaler.noScaling,
  Brightness brightness = Brightness.dark,
}) async {
  final router = GoRouter(
    initialLocation: AppPaths.settingsModuleEnergy,
    routes: [
      GoRoute(
        path: AppPaths.settingsModuleEnergy,
        builder: (_, _) => const EnergyModuleScreen(),
      ),
      GoRoute(
        path: AppPaths.settingsModuleBody,
        builder: (_, _) => const Scaffold(body: Text('body module')),
      ),
      GoRoute(
        path: AppPaths.energyFormula,
        builder: (_, _) => const Scaffold(body: Text('formula')),
      ),
    ],
  );
  addTearDown(router.dispose);
  await pumpScaled(
    tester,
    MaterialApp.router(
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      supportedLocales: AppLocales.supported,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      routerConfig: router,
    ),
    textScaler: textScaler,
    brightness: brightness,
    locale: locale,
    overrides: _overrides(
      modules: store ?? InMemoryModuleStore(stored),
      profile: profile,
      hidden: hidden,
    ),
  );
  return router;
}

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(EnergyModuleScreen)));

Future<void> _reveal(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    300,
    scrollable: find.byType(Scrollable).first,
    maxScrolls: 300,
  );
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

Finder _within(Key key, String text) =>
    find.descendant(of: find.byKey(key), matching: find.text(text));

Future<void> _tap(WidgetTester tester, Key key) async {
  final finder = find.byKey(key);
  await _reveal(tester, finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  group('the state text', () {
    testWidgets('says Off when Energy is off', (tester) async {
      await _pump(tester, profile: _aged(30));

      expect(
        _within(EnergyModuleKeys.state, _l10n(tester).modulesOff),
        findsOneWidget,
      );
    });

    testWidgets('says On when the gate is on', (tester) async {
      await _pump(tester, stored: {ModuleId.energy}, profile: _aged(30));

      expect(
        _within(EnergyModuleKeys.state, _l10n(tester).modulesOn),
        findsOneWidget,
      );
    });

    testWidgets('says On with no profile at all', (tester) async {
      await _pump(tester, stored: {ModuleId.energy});

      expect(
        _within(EnergyModuleKeys.state, _l10n(tester).modulesOn),
        findsOneWidget,
      );
    });

    testWidgets('says Not available at 17 with Energy stored on', (
      tester,
    ) async {
      await _pump(
        tester,
        stored: {ModuleId.energy},
        profile: _aged(energyAdultAge - 1),
      );

      expect(
        _within(EnergyModuleKeys.state, _l10n(tester).moduleEnergyUnavailable),
        findsOneWidget,
      );
    });

    testWidgets('says Not available at 17 with Energy stored off', (
      tester,
    ) async {
      await _pump(tester, profile: _aged(energyAdultAge - 1));

      expect(
        _within(EnergyModuleKeys.state, _l10n(tester).moduleEnergyUnavailable),
        findsOneWidget,
      );
    });

    testWidgets('says On with numbers hidden when stored on and hidden', (
      tester,
    ) async {
      await _pump(
        tester,
        stored: {ModuleId.energy, ModuleId.body},
        profile: _aged(30),
        hidden: true,
      );

      expect(
        _within(EnergyModuleKeys.state, _l10n(tester).moduleEnergyOnHidden),
        findsOneWidget,
      );
    });
  });

  group('the under 18 notice', () {
    testWidgets('shows the title and the body and has no button', (
      tester,
    ) async {
      await _pump(
        tester,
        stored: {ModuleId.energy},
        profile: _aged(energyAdultAge - 1),
      );
      final l10n = _l10n(tester);
      await _reveal(tester, find.byKey(EnergyModuleKeys.underage));

      expect(find.byKey(EnergyModuleKeys.underage), findsOneWidget);
      expect(
        _within(EnergyModuleKeys.underage, l10n.moduleEnergyUnderageTitle),
        findsOneWidget,
      );
      expect(
        _within(
          EnergyModuleKeys.underage,
          l10n.moduleEnergyUnderageBody('18', l10n.profileTitle),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(EnergyModuleKeys.toggle, skipOffstage: false),
        findsNothing,
      );
    });

    testWidgets('is absent for an adult, who has the button', (tester) async {
      await _pump(tester, profile: _aged(energyAdultAge));

      expect(
        find.byKey(EnergyModuleKeys.underage, skipOffstage: false),
        findsNothing,
      );
      await _reveal(tester, find.byKey(EnergyModuleKeys.toggle));
      expect(find.byKey(EnergyModuleKeys.toggle), findsOneWidget);
    });
  });

  group('numbers hidden', () {
    testWidgets('shows the notice and the way to Body', (tester) async {
      final router = await _pump(
        tester,
        stored: {ModuleId.energy, ModuleId.body},
        profile: _aged(30),
        hidden: true,
      );
      await _reveal(tester, find.byKey(EnergyModuleKeys.hidden));

      expect(find.byKey(EnergyModuleKeys.hidden), findsOneWidget);
      await _tap(tester, EnergyModuleKeys.openBody);

      expect(router.state.uri.path, AppPaths.settingsModuleBody);
    });

    testWidgets('is absent while the numbers are shown', (tester) async {
      await _pump(
        tester,
        stored: {ModuleId.energy, ModuleId.body},
        profile: _aged(30),
      );

      expect(
        find.byKey(EnergyModuleKeys.hidden, skipOffstage: false),
        findsNothing,
      );
      expect(
        find.byKey(EnergyModuleKeys.openBody, skipOffstage: false),
        findsNothing,
      );
    });
  });

  group('the toggle', () {
    testWidgets('reads Turn Energy on while off and turns it on', (
      tester,
    ) async {
      final store = InMemoryModuleStore();
      await _pump(tester, store: store, profile: _aged(30));
      await _reveal(tester, find.byKey(EnergyModuleKeys.toggle));

      expect(
        _within(EnergyModuleKeys.toggle, _l10n(tester).moduleEnergyTurnOn),
        findsOneWidget,
      );
      await _tap(tester, EnergyModuleKeys.toggle);

      expect(await store.read(), {ModuleId.energy});
    });

    testWidgets('shows the turned on message with the name of Today', (
      tester,
    ) async {
      await _pump(tester, profile: _aged(30));
      await _tap(tester, EnergyModuleKeys.toggle);
      final l10n = _l10n(tester);

      expect(
        find.text(l10n.moduleEnergyTurnedOn(l10n.tabToday)),
        findsOneWidget,
      );
    });

    testWidgets('reads Turn Energy off while on and turns it off in silence', (
      tester,
    ) async {
      final store = InMemoryModuleStore({ModuleId.energy});
      await _pump(tester, store: store, profile: _aged(30));
      await _reveal(tester, find.byKey(EnergyModuleKeys.toggle));

      expect(
        _within(EnergyModuleKeys.toggle, _l10n(tester).moduleEnergyTurnOff),
        findsOneWidget,
      );
      await _tap(tester, EnergyModuleKeys.toggle);

      expect(await store.read(), isEmpty);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('turns on in silence while the numbers are hidden', (
      tester,
    ) async {
      final store = InMemoryModuleStore({ModuleId.body});
      await _pump(tester, store: store, profile: _aged(30), hidden: true);
      await _tap(tester, EnergyModuleKeys.toggle);

      expect(await store.read(), {ModuleId.body, ModuleId.energy});
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('turns on with no profile', (tester) async {
      final store = InMemoryModuleStore();
      await _pump(tester, store: store);
      await _tap(tester, EnergyModuleKeys.toggle);

      expect(await store.read(), {ModuleId.energy});
    });
  });

  testWidgets('the formula link opens the formula', (tester) async {
    final router = await _pump(tester, profile: _aged(30));
    await _tap(tester, EnergyModuleKeys.formula);

    expect(router.state.uri.path, AppPaths.energyFormula);
  });

  testWidgets('the formula link is there at 17 too', (tester) async {
    final router = await _pump(tester, profile: _aged(energyAdultAge - 1));
    await _tap(tester, EnergyModuleKeys.formula);

    expect(router.state.uri.path, AppPaths.energyFormula);
  });

  group('layout', () {
    final states = {
      'off': (<ModuleId>{}, 30),
      'underage': ({ModuleId.energy}, energyAdultAge - 1),
    };

    for (final MapEntry(key: name, value: (stored, age)) in states.entries) {
      for (final layout in layoutMatrix()) {
        testWidgets('fits $layout, $name', (tester) async {
          await _pump(
            tester,
            stored: stored,
            profile: _aged(age),
            locale: layout.locale,
            textScaler: layout.textScaler,
            brightness: layout.brightness,
          );
          await scrollThrough(tester);

          expect(tester.takeException(), isNull);
          expect(find.byType(EnergyModuleScreen), findsOneWidget);
        });
      }

      for (final locale in AppLocales.supported) {
        testWidgets('fits 2.0x in $locale, $name', (tester) async {
          await _pump(
            tester,
            stored: stored,
            profile: _aged(age),
            locale: locale,
            textScaler: const TextScaler.linear(2),
            brightness: Brightness.light,
          );
          await scrollThrough(tester);

          expect(tester.takeException(), isNull);
          expect(find.byType(EnergyModuleScreen), findsOneWidget);
        });
      }
    }
  });
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/features/body/presentation/weight_card.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/modules/domain/module_store.dart';
import 'package:open_ring/features/modules/presentation/modules_offer_screen.dart';
import 'package:open_ring/features/modules/presentation/modules_screen.dart';
import 'package:open_ring/features/modules/presentation/modules_shortcut.dart';
import 'package:open_ring/features/modules/presentation/offered_module.dart';
import 'package:open_ring/features/settings/domain/user_profile.dart';
import 'package:open_ring/features/today/presentation/today_screen.dart';

import '../../../helpers/ble_fakes.dart';
import '../../../helpers/onboarding_app.dart';
import '../../../helpers/onboarding_fakes.dart';
import '../../../helpers/ring_fakes.dart';

final DateTime _now = DateTime.utc(2026, 11, 10, 12);

final class _PendingProfileStore implements UserProfileStore {
  final Completer<UserProfile?> release = Completer<UserProfile?>();

  @override
  Future<UserProfile?> read() => release.future;

  @override
  Future<void> save(UserProfile profile, {required DateTime at}) =>
      throw StateError('never saves');
}

UserProfile _aged(int age) => UserProfile(
  birthYear: UserProfile.birthYearFor(age, year: _now.year),
  sex: Sex.male,
  heightCentimeters: 175,
  weightKilograms: 70,
);

Future<InMemoryModuleStore> _pump(
  WidgetTester tester, {
  String? at,
  InMemoryModuleStore? modules,
  UserProfileStore? profile,
}) async {
  final store = modules ?? InMemoryModuleStore();
  await pumpOnboardingApp(
    tester,
    at: at,
    store: InMemoryOnboardingStore(completed: true),
    overrides: [
      ...bleOverrides(),
      ...ringOverrides(),
      ...onboardingOverrides(profileStore: profile),
      clockProvider.overrideWithValue(() => _now),
      moduleStoreProvider.overrideWithValue(store),
    ],
  );
  return store;
}

final class _FailingOnceStore implements ModuleStore {
  final _inner = InMemoryModuleStore();
  bool failing = true;

  @override
  Future<Set<ModuleId>> read() => _inner.read();

  @override
  Future<void> write(Set<ModuleId> enabled) async {
    if (failing) throw StateError('disk');
    await _inner.write(enabled);
  }

  @override
  Future<bool> shortcutDismissed() => _inner.shortcutDismissed();

  @override
  Future<void> dismissShortcut({required bool dismissed}) =>
      _inner.dismissShortcut(dismissed: dismissed);
}

bool _switchOn(WidgetTester tester, [Key key = ModulesOfferKeys.body]) =>
    tester.widget<SwitchListTile>(find.byKey(key)).value;

void main() {
  group('the modules step of onboarding', () {
    testWidgets('starts with Body off and can be skipped', (tester) async {
      final store = await _pump(tester, at: AppPaths.onboardingModules);

      expect(find.text('Step 5 of 5'), findsOneWidget);
      expect(find.text('Make it yours'), findsOneWidget);
      expect(_switchOn(tester), isFalse);
      expect(find.text('Skip for now'), findsOneWidget);

      await tapAndSettle(tester, find.byKey(ModulesOfferKeys.done));

      expect(find.byType(TodayScreen), findsOneWidget);
      expect(find.text('All set. No module is on.'), findsOneWidget);
      expect(await store.read(), isEmpty);
      expect(find.byKey(WeightCardKeys.card), findsNothing);
    });

    testWidgets('a failed save keeps the step and can be retried', (
      tester,
    ) async {
      final store = _FailingOnceStore();
      await pumpOnboardingApp(
        tester,
        at: AppPaths.onboardingModules,
        store: InMemoryOnboardingStore(completed: true),
        overrides: [
          ...bleOverrides(),
          ...ringOverrides(),
          ...onboardingOverrides(),
          moduleStoreProvider.overrideWithValue(store),
        ],
      );

      await tapAndSettle(tester, find.byKey(ModulesOfferKeys.body));
      await tapAndSettle(tester, find.byKey(ModulesOfferKeys.done));

      expect(find.byType(ModulesOfferScreen), findsOneWidget);
      expect(
        find.text('The data could not be saved on this phone. Try again.'),
        findsOneWidget,
      );

      store.failing = false;
      await tapAndSettle(tester, find.byKey(ModulesOfferKeys.done));

      expect(find.byType(TodayScreen), findsOneWidget);
      expect(await store.read(), {ModuleId.body});
    });

    testWidgets('with Body picked it turns Body on and opens Today', (
      tester,
    ) async {
      final store = await _pump(tester, at: AppPaths.onboardingModules);

      await tapAndSettle(tester, find.byKey(ModulesOfferKeys.body));

      expect(_switchOn(tester), isTrue);
      expect(find.text('Continue with 1 module'), findsOneWidget);
      expect(await store.read(), isEmpty);

      await tapAndSettle(tester, find.byKey(ModulesOfferKeys.done));

      expect(find.byType(TodayScreen), findsOneWidget);
      expect(await store.read(), {ModuleId.body});
      expect(
        find.text('Body is on. The Weight card is on Today.'),
        findsOneWidget,
      );
      expect(find.byKey(WeightCardKeys.card), findsOneWidget);
    });

    testWidgets('with Open Score picked it turns Open Score on', (
      tester,
    ) async {
      final store = await _pump(tester, at: AppPaths.onboardingModules);

      expect(_switchOn(tester, ModulesOfferKeys.openScore), isFalse);
      await tapAndSettle(tester, find.byKey(ModulesOfferKeys.openScore));

      expect(find.text('Continue with 1 module'), findsOneWidget);
      await tapAndSettle(tester, find.byKey(ModulesOfferKeys.done));

      expect(await store.read(), {ModuleId.openScore});
      expect(
        find.text(
          'Open Score is on. The Day Score shows on Today once your ring has synced.',
        ),
        findsOneWidget,
      );
      expect(find.byType(TodayScreen), findsOneWidget);
      expect(find.byKey(WeightCardKeys.card), findsNothing);
    });

    testWidgets('with both picked it turns both on', (tester) async {
      final store = await _pump(tester, at: AppPaths.onboardingModules);

      await tapAndSettle(tester, find.byKey(ModulesOfferKeys.body));
      await tapAndSettle(tester, find.byKey(ModulesOfferKeys.openScore));

      expect(find.text('Continue with 2 modules'), findsOneWidget);
      await tapAndSettle(tester, find.byKey(ModulesOfferKeys.done));

      expect(await store.read(), {ModuleId.body, ModuleId.openScore});
      expect(find.text('Your modules are on.'), findsOneWidget);
      expect(find.byKey(WeightCardKeys.card), findsOneWidget);
    });

    testWidgets('unpicking a module that was on turns it off', (tester) async {
      final store = await _pump(
        tester,
        at: AppPaths.onboardingModules,
        modules: InMemoryModuleStore({ModuleId.body, ModuleId.openScore}),
      );

      expect(find.text('Continue with 2 modules'), findsOneWidget);
      await tapAndSettle(tester, find.byKey(ModulesOfferKeys.openScore));
      await tapAndSettle(tester, find.byKey(ModulesOfferKeys.done));

      expect(await store.read(), {ModuleId.body});
    });

    testWidgets('offers Energy to an adult', (tester) async {
      await _pump(
        tester,
        at: AppPaths.onboardingModules,
        profile: InMemoryUserProfileStore(_aged(30)),
      );

      expect(find.byKey(ModulesOfferKeys.energy), findsOneWidget);
      expect(_switchOn(tester, ModulesOfferKeys.energy), isFalse);
      expect(find.text('Energy'), findsOneWidget);
    });

    testWidgets('offers Energy with no profile', (tester) async {
      await _pump(tester, at: AppPaths.onboardingModules);

      expect(find.byKey(ModulesOfferKeys.energy), findsOneWidget);
    });

    testWidgets('offers Energy at the adult age', (tester) async {
      await _pump(
        tester,
        at: AppPaths.onboardingModules,
        profile: InMemoryUserProfileStore(_aged(energyAdultAge)),
      );

      expect(find.byKey(ModulesOfferKeys.energy), findsOneWidget);
    });

    testWidgets('criterion 2: offers Effort with no profile', (tester) async {
      await _pump(tester, at: AppPaths.onboardingModules);

      expect(
        find.byKey(ModulesOfferKeys.module(OfferedModule.effort)),
        findsOneWidget,
      );
      expect(
        _switchOn(tester, ModulesOfferKeys.module(OfferedModule.effort)),
        isFalse,
      );
      expect(find.text('Effort'), findsOneWidget);
    });

    testWidgets('criterion 2: offers Effort to an adult, four in all', (
      tester,
    ) async {
      await _pump(
        tester,
        at: AppPaths.onboardingModules,
        profile: InMemoryUserProfileStore(_aged(30)),
      );

      expect(
        find.byKey(ModulesOfferKeys.module(OfferedModule.effort)),
        findsOneWidget,
      );
      expect(find.byType(SwitchListTile), findsNWidgets(4));
    });

    testWidgets('criterion 2: offers Effort at 17, with Energy left out', (
      tester,
    ) async {
      await _pump(
        tester,
        at: AppPaths.onboardingModules,
        profile: InMemoryUserProfileStore(_aged(17)),
      );

      expect(
        find.byKey(ModulesOfferKeys.module(OfferedModule.effort)),
        findsOneWidget,
      );
      expect(find.byKey(ModulesOfferKeys.energy), findsNothing);
      expect(find.byType(SwitchListTile), findsNWidgets(3));
    });

    testWidgets('criterion 2: offers Effort while the profile loads', (
      tester,
    ) async {
      await _pump(
        tester,
        at: AppPaths.onboardingModules,
        profile: _PendingProfileStore(),
      );

      expect(
        find.byKey(ModulesOfferKeys.module(OfferedModule.effort)),
        findsOneWidget,
      );
    });

    testWidgets('criterion 2: with Effort picked it turns Effort on', (
      tester,
    ) async {
      final store = await _pump(tester, at: AppPaths.onboardingModules);

      await tapAndSettle(
        tester,
        find.byKey(ModulesOfferKeys.module(OfferedModule.effort)),
      );

      expect(find.text('Continue with 1 module'), findsOneWidget);
      await tapAndSettle(tester, find.byKey(ModulesOfferKeys.done));

      expect(await store.read(), {ModuleId.effort});
      expect(find.byType(TodayScreen), findsOneWidget);
      expect(
        find.text('Effort is on. The Effort tile is on Today.'),
        findsOneWidget,
      );
    });

    testWidgets('criterion 2: Effort at 17 is stored on and Energy is kept', (
      tester,
    ) async {
      final store = await _pump(
        tester,
        at: AppPaths.onboardingModules,
        modules: InMemoryModuleStore({ModuleId.energy}),
        profile: InMemoryUserProfileStore(_aged(17)),
      );

      await tapAndSettle(
        tester,
        find.byKey(ModulesOfferKeys.module(OfferedModule.effort)),
      );
      await tapAndSettle(tester, find.byKey(ModulesOfferKeys.done));

      expect(await store.read(), {ModuleId.energy, ModuleId.effort});
    });

    testWidgets('with Energy picked it turns Energy on and opens Today', (
      tester,
    ) async {
      final store = await _pump(
        tester,
        at: AppPaths.onboardingModules,
        profile: InMemoryUserProfileStore(_aged(30)),
      );

      await tapAndSettle(tester, find.byKey(ModulesOfferKeys.energy));

      expect(find.text('Continue with 1 module'), findsOneWidget);
      await tapAndSettle(tester, find.byKey(ModulesOfferKeys.done));

      expect(await store.read(), {ModuleId.energy});
      expect(find.byType(TodayScreen), findsOneWidget);
      expect(
        find.text('Energy is on. The Energy row is on Today.'),
        findsOneWidget,
      );
    });

    testWidgets('leaves Energy out at 17', (tester) async {
      await _pump(
        tester,
        at: AppPaths.onboardingModules,
        profile: InMemoryUserProfileStore(_aged(energyAdultAge - 1)),
      );

      expect(find.byKey(ModulesOfferKeys.energy), findsNothing);
      expect(find.byKey(ModulesOfferKeys.body), findsOneWidget);
      expect(find.byKey(ModulesOfferKeys.openScore), findsOneWidget);
    });

    testWidgets('leaves Energy out while the profile loads', (tester) async {
      await _pump(
        tester,
        at: AppPaths.onboardingModules,
        profile: _PendingProfileStore(),
      );

      expect(find.byKey(ModulesOfferKeys.energy), findsNothing);
      expect(find.byKey(ModulesOfferKeys.body), findsOneWidget);
    });

    testWidgets('finishing at 17 keeps a stored Energy', (tester) async {
      final store = await _pump(
        tester,
        at: AppPaths.onboardingModules,
        modules: InMemoryModuleStore({ModuleId.energy}),
        profile: InMemoryUserProfileStore(_aged(energyAdultAge - 1)),
      );

      await tapAndSettle(tester, find.byKey(ModulesOfferKeys.done));

      expect(await store.read(), {ModuleId.energy});
    });

    testWidgets('finishing at 17 with Body picked keeps a stored Energy', (
      tester,
    ) async {
      final store = await _pump(
        tester,
        at: AppPaths.onboardingModules,
        modules: InMemoryModuleStore({ModuleId.energy}),
        profile: InMemoryUserProfileStore(_aged(energyAdultAge - 1)),
      );

      await tapAndSettle(tester, find.byKey(ModulesOfferKeys.body));
      await tapAndSettle(tester, find.byKey(ModulesOfferKeys.done));

      expect(await store.read(), {ModuleId.body, ModuleId.energy});
    });

    testWidgets('finishing while the profile loads keeps a stored Energy', (
      tester,
    ) async {
      final store = await _pump(
        tester,
        at: AppPaths.onboardingModules,
        modules: InMemoryModuleStore({ModuleId.energy}),
        profile: _PendingProfileStore(),
      );

      await tapAndSettle(tester, find.byKey(ModulesOfferKeys.done));

      expect(await store.read(), {ModuleId.energy});
    });

    testWidgets('a stored Energy at 17 does not count in the button', (
      tester,
    ) async {
      await _pump(
        tester,
        at: AppPaths.onboardingModules,
        modules: InMemoryModuleStore({ModuleId.energy}),
        profile: InMemoryUserProfileStore(_aged(energyAdultAge - 1)),
      );

      expect(find.text('Skip for now'), findsOneWidget);
    });

    testWidgets('with Body already on the switch starts on', (tester) async {
      await _pump(
        tester,
        at: AppPaths.onboardingModules,
        modules: InMemoryModuleStore({ModuleId.body}),
      );

      expect(_switchOn(tester), isTrue);
      expect(find.text('Continue with 1 module'), findsOneWidget);
    });
  });

  group('the modules shortcut on Today', () {
    testWidgets('opens the Modules screen', (tester) async {
      await _pump(tester);

      await tapAndSettle(tester, find.byKey(ModulesShortcutKeys.open));

      expect(find.byType(ModulesScreen), findsOneWidget);
    });

    testWidgets('can be dismissed for good, with Undo', (tester) async {
      final store = await _pump(tester);

      await tapAndSettle(tester, find.byKey(ModulesShortcutKeys.dismiss));

      expect(find.byKey(ModulesShortcutKeys.open), findsNothing);
      expect(store.dismissed, isTrue);
      expect(find.text('Modules stay in Ring, Settings.'), findsOneWidget);

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();

      expect(find.byKey(ModulesShortcutKeys.open), findsOneWidget);
      expect(store.dismissed, isFalse);
    });

    testWidgets('stays out once dismissed', (tester) async {
      await _pump(tester, modules: InMemoryModuleStore()..dismissed = true);

      expect(find.byType(TodayScreen), findsOneWidget);
      expect(find.byKey(ModulesShortcutKeys.open), findsNothing);
    });
  });
}

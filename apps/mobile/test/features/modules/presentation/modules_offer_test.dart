import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/features/body/presentation/weight_card.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/modules/domain/module_store.dart';
import 'package:open_ring/features/modules/presentation/modules_offer_screen.dart';
import 'package:open_ring/features/modules/presentation/modules_screen.dart';
import 'package:open_ring/features/modules/presentation/modules_shortcut.dart';
import 'package:open_ring/features/today/presentation/today_screen.dart';

import '../../../helpers/ble_fakes.dart';
import '../../../helpers/onboarding_app.dart';
import '../../../helpers/onboarding_fakes.dart';
import '../../../helpers/ring_fakes.dart';

Future<InMemoryModuleStore> _pump(
  WidgetTester tester, {
  String? at,
  InMemoryModuleStore? modules,
}) async {
  final store = modules ?? InMemoryModuleStore();
  await pumpOnboardingApp(
    tester,
    at: at,
    store: InMemoryOnboardingStore(completed: true),
    overrides: [
      ...bleOverrides(),
      ...ringOverrides(),
      ...onboardingOverrides(),
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
        find.text('Open Score is on. The Day Score card is on Today.'),
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
      expect(
        find.text('Your modules are on. Their cards are on Today.'),
        findsOneWidget,
      );
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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/app/app.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/shell/app_navigation_bar.dart';
import 'package:open_ring/features/body/application/weigh_in_providers.dart';
import 'package:open_ring/features/body/domain/weigh_in_store.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/modules/domain/module_store.dart';
import 'package:open_ring/features/modules/presentation/module_change.dart';
import 'package:open_ring/features/modules/presentation/modules_screen.dart';
import 'package:open_ring/features/ring/presentation/ring_screen.dart';
import 'package:open_ring/features/settings/presentation/settings_screen.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

import '../../../helpers/ble_fakes.dart';
import '../../../helpers/layout_harness.dart';
import '../../../helpers/ring_fakes.dart';
import '../../../helpers/settings_fakes.dart';
import '../../food/food_fakes.dart';
import 'module_change_fakes.dart';

const _hostButton = Key('host_button');

Future<void> _pump(WidgetTester tester, ModuleStore modules) => pumpScaled(
  tester,
  const OpenRingApp(),
  textScaler: TextScaler.noScaling,
  brightness: Brightness.dark,
  locale: const Locale('en'),
  overrides: [
    ...bleOverrides(),
    ...ringOverrides(),
    ...settingsOverrides(),
    ...foodStoreOverrides(
      meals: TestMealStore(),
      camera: GatedMealCamera(),
      clock: () => settingsNow,
    ),
    moduleStoreProvider.overrideWithValue(modules),
    weighInStoreProvider.overrideWithValue(InMemoryWeighInStore()),
  ],
);

Future<void> _tap(WidgetTester tester, Key key) async {
  await reveal(tester, find.byKey(key));
  await tester.tap(find.byKey(key));
  await tester.pumpAndSettle();
}

Future<void> _openModules(WidgetTester tester) async {
  await tester.tap(find.byKey(AppNavigationBar.destinationKey(AppTab.ring)));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(RingScreen.settingsKey));
  await tester.pumpAndSettle();
  await _tap(tester, SettingsScreen.modulesKey);
}

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(Scaffold).first));

bool _on(WidgetTester tester, Key key) =>
    tester.widget<Switch>(find.byKey(key)).value;

Finder _bothOffDone(WidgetTester tester) {
  final l10n = _l10n(tester);
  final body = moduleName(ModuleId.body, l10n);
  final trajectory = moduleName(ModuleId.trajectory, l10n);
  return find.byWidgetPredicate(
    (widget) =>
        widget is Text &&
        (widget.data == l10n.moduleBothOffDone(trajectory, body) ||
            widget.data == l10n.moduleBothOffDone(body, trajectory)),
  );
}

Future<void> _openBodyOffDialog(
  WidgetTester tester,
  SpyModuleStore store,
) async {
  await _pump(tester, store);
  await _openModules(tester);
  await _tap(tester, ModulesKeys.bodySwitch);
}

final _bothOn = {ModuleId.body, ModuleId.trajectory};

Future<void> _pumpHost(
  WidgetTester tester,
  ModuleStore store, {
  required void Function(ModuleChange) onResult,
  required void Function(Object) onError,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [moduleStoreProvider.overrideWithValue(store)],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, _) => TextButton(
              key: _hostButton,
              onPressed: () async {
                try {
                  onResult(
                    await changeModule(
                      context,
                      ref,
                      ModuleId.trajectory,
                      on: true,
                    ),
                  );
                } on Object catch (error) {
                  onError(error);
                }
              },
              child: const Text('go'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openOnDialog(WidgetTester tester) async {
  await tester.tap(find.byKey(_hostButton));
  await tester.pumpAndSettle();
}

void main() {
  group('Modules screen, turning Body off with Trajectory on', () {
    testWidgets('opens the off dialog and cancel leaves both on', (
      tester,
    ) async {
      final store = SpyModuleStore(_bothOn);
      await _openBodyOffDialog(tester, store);
      final l10n = _l10n(tester);

      expect(find.byKey(ModuleChangeKeys.confirm), findsOneWidget);
      expect(
        find.text(l10n.moduleBothOffTitle(moduleName(ModuleId.body, l10n))),
        findsOneWidget,
      );
      expect(find.text(l10n.moduleBothOffConfirm), findsOneWidget);

      await tester.tap(find.byKey(ModuleChangeKeys.cancel));
      await tester.pumpAndSettle();

      expect(await store.read(), _bothOn);
      expect(store.writes, isEmpty);
      expect(_on(tester, ModulesKeys.bodySwitch), isTrue);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('confirm turns Trajectory off before Body and says so', (
      tester,
    ) async {
      final store = SpyModuleStore(_bothOn);
      await _openBodyOffDialog(tester, store);

      await tester.tap(find.byKey(ModuleChangeKeys.confirm));
      await tester.pumpAndSettle();

      expect(await store.read(), isEmpty);
      expect(store.writes, [
        {ModuleId.body},
        <ModuleId>{},
      ]);
      expect(_on(tester, ModulesKeys.bodySwitch), isFalse);
      expect(_bothOffDone(tester), findsOneWidget);
    });

    testWidgets('a write failing mid cascade shows the save error only', (
      tester,
    ) async {
      final store = SpyModuleStore(_bothOn)..failOnWrite = 2;
      await _openBodyOffDialog(tester, store);

      await tester.tap(find.byKey(ModuleChangeKeys.confirm));
      await tester.pumpAndSettle();

      expect(find.text(_l10n(tester).syncErrorSaving), findsOneWidget);
      expect(_bothOffDone(tester), findsNothing);
      expect(_on(tester, ModulesKeys.bodySwitch), isTrue);
    });
  });

  group('changeModule turning Trajectory on with an empty store', () {
    testWidgets('opens the on dialog and confirm writes Body first', (
      tester,
    ) async {
      final store = SpyModuleStore();
      ModuleChange? result;
      await _pumpHost(
        tester,
        store,
        onResult: (value) => result = value,
        onError: (_) {},
      );

      await _openOnDialog(tester);
      final l10n = _l10n(tester);

      expect(
        find.text(l10n.moduleBothOnTitle(moduleName(ModuleId.body, l10n))),
        findsOneWidget,
      );
      expect(find.text(l10n.moduleBothOnConfirm), findsOneWidget);

      await tester.tap(find.byKey(ModuleChangeKeys.confirm));
      await tester.pumpAndSettle();

      expect(await store.read(), _bothOn);
      expect(store.writes, [
        {ModuleId.body},
        _bothOn,
      ]);
      expect(result, ModuleChange.both);
    });

    testWidgets('cancel leaves the store empty and reports cancelled', (
      tester,
    ) async {
      final store = SpyModuleStore();
      ModuleChange? result;
      await _pumpHost(
        tester,
        store,
        onResult: (value) => result = value,
        onError: (_) {},
      );

      await _openOnDialog(tester);
      await tester.tap(find.byKey(ModuleChangeKeys.cancel));
      await tester.pumpAndSettle();

      expect(await store.read(), isEmpty);
      expect(store.writes, isEmpty);
      expect(result, ModuleChange.cancelled);
    });

    testWidgets('a store write throwing is rethrown to the caller', (
      tester,
    ) async {
      final store = SpyModuleStore()..failOnWrite = 2;
      Object? thrown;
      ModuleChange? result;
      await _pumpHost(
        tester,
        store,
        onResult: (value) => result = value,
        onError: (error) => thrown = error,
      );

      await _openOnDialog(tester);
      await tester.tap(find.byKey(ModuleChangeKeys.confirm));
      await tester.pumpAndSettle();

      expect(thrown, isA<StateError>());
      expect(result, isNull);
    });
  });
}

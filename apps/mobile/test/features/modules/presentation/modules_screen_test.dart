import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/app/app.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/shell/app_navigation_bar.dart';
import 'package:open_ring/features/body/application/weigh_in_providers.dart';
import 'package:open_ring/features/body/domain/weigh_in.dart';
import 'package:open_ring/features/body/domain/weigh_in_store.dart';
import 'package:open_ring/features/body/presentation/body_module_screen.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/modules/domain/module_store.dart';
import 'package:open_ring/features/modules/presentation/modules_screen.dart';
import 'package:open_ring/features/ring/presentation/ring_screen.dart';
import 'package:open_ring/features/settings/presentation/settings_screen.dart';
import 'package:open_ring/features/today/presentation/today_screen.dart';

import '../../../helpers/ble_fakes.dart';
import '../../../helpers/layout_harness.dart';
import '../../../helpers/ring_fakes.dart';
import '../../../helpers/settings_fakes.dart';

Future<InMemoryWeighInStore> _twoWeighIns() async {
  final store = InMemoryWeighInStore();
  for (final day in [9, 10]) {
    await store.add(
      WeighInDraft(
        at: DateTime.utc(2026, 11, day, 8),
        offsetMinutes: 0,
        kilograms: 80,
      ),
    );
  }
  return store;
}

Future<void> _pump(
  WidgetTester tester, {
  required ModuleStore modules,
  WeighInStore? weighIns,
}) => pumpScaled(
  tester,
  const OpenRingApp(),
  textScaler: TextScaler.noScaling,
  brightness: Brightness.dark,
  locale: const Locale('en'),
  overrides: [
    ...bleOverrides(),
    ...ringOverrides(),
    ...settingsOverrides(),
    moduleStoreProvider.overrideWithValue(modules),
    weighInStoreProvider.overrideWithValue(weighIns ?? InMemoryWeighInStore()),
  ],
);

Future<void> _openSettings(WidgetTester tester) async {
  await tester.tap(find.byKey(AppNavigationBar.destinationKey(AppTab.ring)));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(RingScreen.settingsKey));
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Key key) async {
  await reveal(tester, find.byKey(key));
  await tester.tap(find.byKey(key));
  await tester.pumpAndSettle();
}

Future<void> _openModules(WidgetTester tester) async {
  await _openSettings(tester);
  await _tap(tester, SettingsScreen.modulesKey);
}

Future<void> _openBody(WidgetTester tester) async {
  await _openModules(tester);
  await _tap(tester, ModulesKeys.bodyRow);
}

void main() {
  testWidgets('Settings says no module is on', (tester) async {
    await _pump(tester, modules: InMemoryModuleStore());
    await _openSettings(tester);
    await reveal(tester, find.byKey(SettingsScreen.modulesKey));

    expect(find.text('None on. The base app stays as it is.'), findsOneWidget);
  });

  testWidgets('Settings counts the modules that are on', (tester) async {
    await _pump(tester, modules: InMemoryModuleStore({ModuleId.body}));
    await _openSettings(tester);
    await reveal(tester, find.byKey(SettingsScreen.modulesKey));

    expect(find.text('On: 1'), findsOneWidget);
  });

  testWidgets('the switch turns Body on and offers the way to Today', (
    tester,
  ) async {
    final modules = InMemoryModuleStore();
    await _pump(tester, modules: modules);
    await _openModules(tester);

    expect(find.byType(ModulesScreen), findsOneWidget);
    expect(find.text('Off'), findsOneWidget);
    await _tap(tester, ModulesKeys.bodySwitch);

    expect(await modules.read(), {ModuleId.body});
    expect(find.text('On'), findsOneWidget);
    expect(
      find.text('Body is on. The Weight card is on Today.'),
      findsOneWidget,
    );
    await tester.tap(find.text('View'));
    await tester.pumpAndSettle();

    expect(find.byType(TodayScreen), findsOneWidget);
  });

  testWidgets('the switch turns Body off without a message', (tester) async {
    final modules = InMemoryModuleStore({ModuleId.body});
    await _pump(tester, modules: modules);
    await _openModules(tester);
    await _tap(tester, ModulesKeys.bodySwitch);

    expect(await modules.read(), isEmpty);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('the Body row opens its detail with nothing stored', (
    tester,
  ) async {
    await _pump(tester, modules: InMemoryModuleStore());
    await _openBody(tester);

    expect(find.byType(BodyModuleScreen), findsOneWidget);
    expect(find.byKey(BodyModuleKeys.kept), findsNothing);
    final texts = await shownTexts(tester);
    expect(texts, contains('No weigh-ins stored on this phone.'));
    expect(texts, contains('Turn Body on'));
    expect(find.byKey(BodyModuleKeys.delete), findsNothing);
  });

  testWidgets('Body off with weigh-ins says they are kept', (tester) async {
    await _pump(
      tester,
      modules: InMemoryModuleStore(),
      weighIns: await _twoWeighIns(),
    );
    await _openBody(tester);

    expect(find.byKey(BodyModuleKeys.kept), findsOneWidget);
    expect(
      find.textContaining('Weigh-ins kept on this phone: 2.'),
      findsOneWidget,
    );
    await reveal(tester, find.byKey(BodyModuleKeys.stored));
    final stored = tester.widget<Text>(
      find.descendant(
        of: find.byKey(BodyModuleKeys.stored),
        matching: find.byType(Text),
      ),
    );
    expect(stored.data, startsWith('Weigh-ins on this phone: 2, from '));
    expect(stored.data, contains('Nov 9 to '));
    expect(stored.data, endsWith('Nov 10.'));
  });

  testWidgets('cancelling the delete keeps the weigh-ins', (tester) async {
    final weighIns = await _twoWeighIns();
    await _pump(tester, modules: InMemoryModuleStore(), weighIns: weighIns);
    await _openBody(tester);
    await _tap(tester, BodyModuleKeys.delete);

    expect(find.textContaining('Weigh-ins to delete: 2.'), findsOneWidget);
    await tester.tap(find.byKey(BodyModuleKeys.deleteCancel));
    await tester.pumpAndSettle();

    expect(await weighIns.count(), 2);
  });

  testWidgets('confirming the delete empties Body and leaves it on', (
    tester,
  ) async {
    final modules = InMemoryModuleStore({ModuleId.body});
    final weighIns = await _twoWeighIns();
    await _pump(tester, modules: modules, weighIns: weighIns);
    await _openBody(tester);
    await _tap(tester, BodyModuleKeys.delete);
    await tester.tap(find.byKey(BodyModuleKeys.deleteConfirm));
    await tester.pumpAndSettle();

    expect(await weighIns.count(), 0);
    expect(await modules.read(), {ModuleId.body});
    expect(find.text('Body data deleted.'), findsOneWidget);
    expect(find.text('No weigh-ins stored on this phone.'), findsOneWidget);
    expect(find.byKey(BodyModuleKeys.delete), findsNothing);
  });

  testWidgets('the detail button turns Body on and off, keeping the data', (
    tester,
  ) async {
    final modules = InMemoryModuleStore();
    final weighIns = await _twoWeighIns();
    await _pump(tester, modules: modules, weighIns: weighIns);
    await _openBody(tester);
    await _tap(tester, BodyModuleKeys.toggle);

    expect(await modules.read(), {ModuleId.body});
    expect(find.text('Turn Body off'), findsOneWidget);
    tester
        .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger).first)
        .clearSnackBars();
    await tester.pumpAndSettle();
    await _tap(tester, BodyModuleKeys.toggle);

    expect(await modules.read(), isEmpty);
    expect(await weighIns.count(), 2);
    await reveal(tester, find.byKey(BodyModuleKeys.toggle));
    expect(find.text('Turn Body on'), findsOneWidget);
  });
}

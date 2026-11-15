import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
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
import 'package:open_ring/features/open_score/presentation/day_score_formula_screen.dart';
import 'package:open_ring/features/open_score/presentation/open_score_module_screen.dart';
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

bool _on(WidgetTester tester, Key key) =>
    tester.widget<Switch>(find.byKey(key)).value;

Future<void> _openModules(WidgetTester tester) async {
  await _openSettings(tester);
  await _tap(tester, SettingsScreen.modulesKey);
}

Future<void> _openOpenScore(WidgetTester tester) async {
  await _openModules(tester);
  await _tap(tester, ModulesKeys.openScoreRow);
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
    expect(_on(tester, ModulesKeys.bodySwitch), isFalse);
    await _tap(tester, ModulesKeys.bodySwitch);

    expect(await modules.read(), {ModuleId.body});
    expect(_on(tester, ModulesKeys.bodySwitch), isTrue);
    expect(_on(tester, ModulesKeys.openScoreSwitch), isFalse);
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

  testWidgets('a screen reader gets the switch and the row separately', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, modules: InMemoryModuleStore());
    await _openModules(tester);

    final toggle = tester.getSemantics(find.byKey(ModulesKeys.bodySwitch));
    final row = tester.getSemantics(find.byKey(ModulesKeys.bodyRow));

    expect(toggle.id, isNot(row.id));
    expect(toggle.label, 'Body');
    expect(toggle.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    expect(row.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    handle.dispose();
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

  testWidgets('the switch turns Open Score on and offers the way to Today', (
    tester,
  ) async {
    final modules = InMemoryModuleStore();
    await _pump(tester, modules: modules);
    await _openModules(tester);
    await _tap(tester, ModulesKeys.openScoreSwitch);

    expect(await modules.read(), {ModuleId.openScore});
    expect(_on(tester, ModulesKeys.openScoreSwitch), isTrue);
    expect(_on(tester, ModulesKeys.bodySwitch), isFalse);
    expect(
      find.text(
        'Open Score is on. The Day Score shows on Today once your ring has synced.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('View'));
    await tester.pumpAndSettle();

    expect(find.byType(TodayScreen), findsOneWidget);
  });

  testWidgets('the Open Score switch is announced by its name', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, modules: InMemoryModuleStore());
    await _openModules(tester);

    final toggle = tester.getSemantics(find.byKey(ModulesKeys.openScoreSwitch));
    final row = tester.getSemantics(find.byKey(ModulesKeys.openScoreRow));

    expect(toggle.id, isNot(row.id));
    expect(toggle.label, 'Open Score');
    handle.dispose();
  });

  testWidgets('the Open Score row opens its detail, off', (tester) async {
    await _pump(tester, modules: InMemoryModuleStore());
    await _openOpenScore(tester);

    expect(find.byType(OpenScoreModuleScreen), findsOneWidget);
    final texts = await shownTexts(tester);
    expect(texts, contains('Off'));
    expect(texts, contains('The Day Score as a metric in History.'));
    expect(texts, contains('It asks for no new permission and sends nothing.'));
    expect(
      texts,
      contains('It does not estimate biological age or life expectancy.'),
    );
    expect(texts, contains('Body weight, calories and age never enter.'));
    expect(texts, contains('Turn Open Score on'));
    expect(texts, contains('You can turn it off whenever you want.'));
  });

  testWidgets('the detail button turns Open Score on and off', (tester) async {
    final modules = InMemoryModuleStore();
    await _pump(tester, modules: modules);
    await _openOpenScore(tester);
    await _tap(tester, OpenScoreModuleKeys.toggle);

    expect(await modules.read(), {ModuleId.openScore});
    expect(find.text('Turn Open Score off'), findsOneWidget);
    expect(find.text('Nothing is deleted.'), findsOneWidget);
    tester
        .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger).first)
        .clearSnackBars();
    await tester.pumpAndSettle();
    await _tap(tester, OpenScoreModuleKeys.toggle);

    expect(await modules.read(), isEmpty);
    expect(find.byType(SnackBar), findsNothing);
    await reveal(tester, find.byKey(OpenScoreModuleKeys.toggle));
    expect(find.text('Turn Open Score on'), findsOneWidget);
  });

  testWidgets('the detail links to the formula while the module is off', (
    tester,
  ) async {
    await _pump(tester, modules: InMemoryModuleStore());
    await _openOpenScore(tester);
    await _tap(tester, OpenScoreModuleKeys.formula);

    expect(find.byType(DayScoreFormulaScreen), findsOneWidget);
  });
}

import 'dart:async';

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
import 'package:open_ring/features/effort/presentation/effort_module_screen.dart';
import 'package:open_ring/features/energy/presentation/energy_module_screen.dart';
import 'package:open_ring/features/food/presentation/food_module_screen.dart';
import 'package:open_ring/features/goals/presentation/goal_screen.dart';
import 'package:open_ring/features/goals/presentation/goals_module_screen.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/modules/domain/module_store.dart';
import 'package:open_ring/features/modules/presentation/modules_screen.dart';
import 'package:open_ring/features/modules/presentation/offered_module.dart';
import 'package:open_ring/features/open_score/presentation/day_score_formula_screen.dart';
import 'package:open_ring/features/open_score/presentation/open_score_module_screen.dart';
import 'package:open_ring/features/ring/presentation/ring_screen.dart';
import 'package:open_ring/features/settings/domain/user_profile.dart';
import 'package:open_ring/features/settings/presentation/settings_screen.dart';
import 'package:open_ring/features/today/presentation/today_screen.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

import '../../../helpers/ble_fakes.dart';
import '../../../helpers/layout_harness.dart';
import '../../../helpers/ring_fakes.dart';
import '../../../helpers/settings_fakes.dart';
import '../../food/food_fakes.dart';

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

final class _PendingProfileStore implements UserProfileStore {
  final Completer<UserProfile?> release = Completer<UserProfile?>();

  @override
  Future<UserProfile?> read() => release.future;

  @override
  Future<void> save(UserProfile profile, {required DateTime at}) =>
      throw StateError('never saves');
}

UserProfile _aged(int age) => UserProfile(
  birthYear: UserProfile.birthYearFor(age, year: settingsNow.year),
  sex: Sex.male,
  heightCentimeters: 175,
  weightKilograms: 70,
);

Future<void> _pump(
  WidgetTester tester, {
  required ModuleStore modules,
  WeighInStore? weighIns,
  UserProfileStore? profiles,
}) => pumpScaled(
  tester,
  const OpenRingApp(),
  textScaler: TextScaler.noScaling,
  brightness: Brightness.dark,
  locale: const Locale('en'),
  overrides: [
    ...bleOverrides(),
    ...ringOverrides(),
    ...settingsOverrides(profiles: profiles),
    ...foodStoreOverrides(
      meals: TestMealStore(),
      camera: GatedMealCamera(),
      clock: () => settingsNow,
    ),
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

  testWidgets('Settings counts Energy for an adult', (tester) async {
    await _pump(
      tester,
      modules: InMemoryModuleStore({ModuleId.body, ModuleId.energy}),
      profiles: InMemoryUserProfileStore(_aged(30)),
    );
    await _openSettings(tester);
    await reveal(tester, find.byKey(SettingsScreen.modulesKey));

    expect(find.text('On: 2'), findsOneWidget);
  });

  testWidgets('Settings does not count Energy stored on at 17', (tester) async {
    await _pump(
      tester,
      modules: InMemoryModuleStore({ModuleId.body, ModuleId.energy}),
      profiles: InMemoryUserProfileStore(_aged(17)),
    );
    await _openSettings(tester);
    await reveal(tester, find.byKey(SettingsScreen.modulesKey));

    expect(find.text('On: 1'), findsOneWidget);
  });

  testWidgets('Settings says no module is on with only Energy stored at 17', (
    tester,
  ) async {
    await _pump(
      tester,
      modules: InMemoryModuleStore({ModuleId.energy}),
      profiles: InMemoryUserProfileStore(_aged(17)),
    );
    await _openSettings(tester);
    await reveal(tester, find.byKey(SettingsScreen.modulesKey));

    expect(find.text('None on. The base app stays as it is.'), findsOneWidget);
  });

  testWidgets('the Energy row shows its title', (tester) async {
    await _pump(tester, modules: InMemoryModuleStore());
    await _openModules(tester);
    await reveal(tester, find.byKey(ModulesKeys.energyRow));

    expect(
      find.descendant(
        of: find.byKey(ModulesKeys.energyRow),
        matching: find.text('Energy'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('the Energy switch turns Energy on and off for an adult', (
    tester,
  ) async {
    final modules = InMemoryModuleStore();
    await _pump(
      tester,
      modules: modules,
      profiles: InMemoryUserProfileStore(_aged(30)),
    );
    await _openModules(tester);
    await reveal(tester, find.byKey(ModulesKeys.energySwitch));

    expect(_on(tester, ModulesKeys.energySwitch), isFalse);
    expect(
      tester.widget<Switch>(find.byKey(ModulesKeys.energySwitch)).onChanged,
      isNotNull,
    );
    await _tap(tester, ModulesKeys.energySwitch);

    expect(await modules.read(), {ModuleId.energy});
    expect(_on(tester, ModulesKeys.energySwitch), isTrue);
    expect(
      find.text('Energy is on. The Energy row is on Today.'),
      findsOneWidget,
    );
    await _tap(tester, ModulesKeys.energySwitch);

    expect(await modules.read(), isEmpty);
    expect(_on(tester, ModulesKeys.energySwitch), isFalse);
  });

  testWidgets('the Energy switch turns on with no profile and no birth year', (
    tester,
  ) async {
    final modules = InMemoryModuleStore();
    await _pump(
      tester,
      modules: modules,
      profiles: InMemoryUserProfileStore(const UserProfile(sex: Sex.female)),
    );
    await _openModules(tester);
    await _tap(tester, ModulesKeys.energySwitch);

    expect(await modules.read(), {ModuleId.energy});
  });

  testWidgets('the Energy row opens its module screen', (tester) async {
    await _pump(tester, modules: InMemoryModuleStore());
    await _openModules(tester);
    await _tap(tester, ModulesKeys.energyRow);

    expect(find.byType(EnergyModuleScreen), findsOneWidget);
  });

  testWidgets('the Energy switch is off and disabled at 17', (tester) async {
    final modules = InMemoryModuleStore();
    await _pump(
      tester,
      modules: modules,
      profiles: InMemoryUserProfileStore(_aged(17)),
    );
    await _openModules(tester);
    await reveal(tester, find.byKey(ModulesKeys.energySwitch));

    expect(_on(tester, ModulesKeys.energySwitch), isFalse);
    expect(
      tester.widget<Switch>(find.byKey(ModulesKeys.energySwitch)).onChanged,
      isNull,
    );
    await tester.tap(find.byKey(ModulesKeys.energySwitch));
    await tester.pumpAndSettle();

    expect(await modules.read(), isEmpty);
  });

  testWidgets('the Energy switch stays off and disabled with Energy stored on '
      'at 17', (tester) async {
    final modules = InMemoryModuleStore({ModuleId.body, ModuleId.energy});
    await _pump(
      tester,
      modules: modules,
      profiles: InMemoryUserProfileStore(_aged(17)),
    );
    await _openModules(tester);
    await reveal(tester, find.byKey(ModulesKeys.energySwitch));

    expect(_on(tester, ModulesKeys.energySwitch), isFalse);
    expect(
      tester.widget<Switch>(find.byKey(ModulesKeys.energySwitch)).onChanged,
      isNull,
    );
    expect(_on(tester, ModulesKeys.bodySwitch), isTrue);
    expect(await modules.read(), {ModuleId.body, ModuleId.energy});
  });

  testWidgets('the Energy switch is off and disabled while the profile loads', (
    tester,
  ) async {
    await _pump(
      tester,
      modules: InMemoryModuleStore({ModuleId.energy}),
      profiles: _PendingProfileStore(),
    );
    await _openModules(tester);
    await reveal(tester, find.byKey(ModulesKeys.energySwitch));

    expect(_on(tester, ModulesKeys.energySwitch), isFalse);
    expect(
      tester.widget<Switch>(find.byKey(ModulesKeys.energySwitch)).onChanged,
      isNull,
    );
  });

  testWidgets('the Energy row of an under 18 still opens its module screen', (
    tester,
  ) async {
    await _pump(
      tester,
      modules: InMemoryModuleStore(),
      profiles: InMemoryUserProfileStore(_aged(17)),
    );
    await _openModules(tester);
    await _tap(tester, ModulesKeys.energyRow);

    expect(find.byType(EnergyModuleScreen), findsOneWidget);
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
    expect(
      texts,
      contains(
        'No factor reads body weight or calories. Active energy only enters '
        'through readiness, which can lower the step goal of a day. Age only '
        'sets the heart rate zones of a workout when you gave no maximum '
        'heart rate.',
      ),
    );
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

  testWidgets('criterion 1: the Modules screen lists six rows', (tester) async {
    await _pump(tester, modules: InMemoryModuleStore());
    await _openModules(tester);

    expect(OfferedModule.values, hasLength(6));
    for (final module in OfferedModule.values) {
      await reveal(tester, find.byKey(ModulesKeys.row(module)));
      expect(find.byKey(ModulesKeys.row(module)), findsOneWidget);
    }
    expect(find.byType(Switch), findsNWidgets(6));
    expect(
      find.descendant(
        of: find.byKey(ModulesKeys.row(OfferedModule.effort)),
        matching: find.text('Effort'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('criterion 1: the Effort switch stores ModuleId.effort', (
    tester,
  ) async {
    final modules = InMemoryModuleStore();
    await _pump(tester, modules: modules);
    await _openModules(tester);
    final toggle = ModulesKeys.toggle(OfferedModule.effort);
    await reveal(tester, find.byKey(toggle));

    expect(_on(tester, toggle), isFalse);
    await _tap(tester, toggle);

    expect(await modules.read(), {ModuleId.effort});
    expect(_on(tester, toggle), isTrue);
    expect(
      find.text('Effort is on. The Effort tile is on Today.'),
      findsOneWidget,
    );
    await _tap(tester, toggle);

    expect(await modules.read(), isEmpty);
    expect(_on(tester, toggle), isFalse);
  });

  testWidgets('criterion 1: the Goals row names Goals', (tester) async {
    await _pump(tester, modules: InMemoryModuleStore());
    await _openModules(tester);
    final row = ModulesKeys.row(OfferedModule.goals);
    await reveal(tester, find.byKey(row));

    expect(find.byKey(row), findsOneWidget);
    expect(
      find.descendant(of: find.byKey(row), matching: find.text('Goals')),
      findsOneWidget,
    );
  });

  testWidgets('criterion 1: the Goals switch stores ModuleId.goals', (
    tester,
  ) async {
    final modules = InMemoryModuleStore();
    await _pump(tester, modules: modules);
    await _openModules(tester);
    final toggle = ModulesKeys.toggle(OfferedModule.goals);
    await reveal(tester, find.byKey(toggle));

    expect(_on(tester, toggle), isFalse);
    await _tap(tester, toggle);

    expect(await modules.read(), {ModuleId.goals});
    expect(_on(tester, toggle), isTrue);
    await _tap(tester, toggle);

    expect(await modules.read(), isEmpty);
    expect(_on(tester, toggle), isFalse);
  });

  testWidgets('criterion 4: the Goals turned on View opens the goal', (
    tester,
  ) async {
    await _pump(tester, modules: InMemoryModuleStore());
    await _openModules(tester);
    await _tap(tester, ModulesKeys.toggle(OfferedModule.goals));

    await tester.tap(find.text('View'));
    await tester.pumpAndSettle();

    expect(find.byType(GoalScreen), findsOneWidget);
    expect(find.byKey(GoalScreenKeys.noGoal), findsOneWidget);
    expect(find.byType(TodayScreen), findsNothing);
  });

  testWidgets('criterion 3: the Goals row opens its module screen', (
    tester,
  ) async {
    await _pump(tester, modules: InMemoryModuleStore());
    await _openModules(tester);
    await _tap(tester, ModulesKeys.row(OfferedModule.goals));

    expect(find.byType(GoalsModuleScreen), findsOneWidget);
  });

  testWidgets('criterion 1: Settings counts Goals with five modules', (
    tester,
  ) async {
    await _pump(
      tester,
      modules: InMemoryModuleStore({
        ModuleId.body,
        ModuleId.openScore,
        ModuleId.energy,
        ModuleId.effort,
        ModuleId.goals,
      }),
      profiles: InMemoryUserProfileStore(_aged(30)),
    );
    await _openSettings(tester);
    await reveal(tester, find.byKey(SettingsScreen.modulesKey));

    expect(find.text('On: 5'), findsOneWidget);
  });

  testWidgets('criterion 1: the Effort switch is enabled at 17', (
    tester,
  ) async {
    await _pump(
      tester,
      modules: InMemoryModuleStore(),
      profiles: InMemoryUserProfileStore(_aged(17)),
    );
    await _openModules(tester);
    final toggle = ModulesKeys.toggle(OfferedModule.effort);
    await reveal(tester, find.byKey(toggle));

    expect(tester.widget<Switch>(find.byKey(toggle)).onChanged, isNotNull);
  });

  testWidgets('criterion 3: the Effort row opens its module screen', (
    tester,
  ) async {
    await _pump(tester, modules: InMemoryModuleStore());
    await _openModules(tester);
    await _tap(tester, ModulesKeys.row(OfferedModule.effort));

    expect(find.byType(EffortModuleScreen), findsOneWidget);
  });

  testWidgets('criterion 1: Settings counts Effort with four modules', (
    tester,
  ) async {
    await _pump(
      tester,
      modules: InMemoryModuleStore({
        ModuleId.body,
        ModuleId.openScore,
        ModuleId.energy,
        ModuleId.effort,
      }),
      profiles: InMemoryUserProfileStore(_aged(30)),
    );
    await _openSettings(tester);
    await reveal(tester, find.byKey(SettingsScreen.modulesKey));

    expect(find.text('On: 4'), findsOneWidget);
  });

  testWidgets('criterion 1: Settings counts Effort stored on at 17', (
    tester,
  ) async {
    await _pump(
      tester,
      modules: InMemoryModuleStore({ModuleId.energy, ModuleId.effort}),
      profiles: InMemoryUserProfileStore(_aged(17)),
    );
    await _openSettings(tester);
    await reveal(tester, find.byKey(SettingsScreen.modulesKey));

    expect(find.text('On: 1'), findsOneWidget);
  });

  testWidgets('the Food row names Food and opens FoodModuleScreen', (
    tester,
  ) async {
    await _pump(tester, modules: InMemoryModuleStore());
    await _openModules(tester);
    final row = ModulesKeys.row(OfferedModule.food);
    await reveal(tester, find.byKey(row));

    expect(find.byKey(row), findsOneWidget);
    expect(
      find.descendant(of: find.byKey(row), matching: find.text('Food')),
      findsOneWidget,
    );

    await _tap(tester, row);
    expect(find.byType(FoodModuleScreen), findsOneWidget);
  });

  testWidgets('the Food switch stores ModuleId.food and View opens Today', (
    tester,
  ) async {
    final modules = InMemoryModuleStore();
    await _pump(tester, modules: modules);
    await _openModules(tester);
    final toggle = ModulesKeys.toggle(OfferedModule.food);
    await reveal(tester, find.byKey(toggle));

    expect(_on(tester, toggle), isFalse);
    await _tap(tester, toggle);

    expect(await modules.read(), {ModuleId.food});
    expect(_on(tester, toggle), isTrue);
    final l10n = lookupAppLocalizations(const Locale('en'));
    expect(find.text(l10n.moduleFoodTurnedOn(l10n.tabToday)), findsOneWidget);

    await _tap(tester, toggle);
    expect(await modules.read(), isEmpty);
    expect(_on(tester, toggle), isFalse);

    await _tap(tester, toggle);
    await tester.tap(find.text('View'));
    await tester.pumpAndSettle();

    expect(find.byType(TodayScreen), findsOneWidget);
  });

  testWidgets('Settings counts all six modules when on', (tester) async {
    await _pump(
      tester,
      modules: InMemoryModuleStore({
        ModuleId.body,
        ModuleId.openScore,
        ModuleId.energy,
        ModuleId.effort,
        ModuleId.goals,
        ModuleId.food,
      }),
      profiles: InMemoryUserProfileStore(_aged(30)),
    );
    await _openSettings(tester);
    await reveal(tester, find.byKey(SettingsScreen.modulesKey));

    expect(find.text('On: 6'), findsOneWidget);
  });
}

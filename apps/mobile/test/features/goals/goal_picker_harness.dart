import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/l10n/app_locales.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/theme/app_theme.dart';
import 'package:open_ring/features/body/application/hide_numbers_controller.dart';
import 'package:open_ring/features/body/application/weight_summary.dart';
import 'package:open_ring/features/body/domain/hide_numbers_store.dart';
import 'package:open_ring/features/body/domain/weigh_in.dart';
import 'package:open_ring/features/demo/application/demo_mode_controller.dart';
import 'package:open_ring/features/demo/domain/demo_mode_store.dart';
import 'package:open_ring/features/goals/domain/goal.dart';
import 'package:open_ring/features/goals/domain/goal_intake.dart';
import 'package:open_ring/features/goals/domain/goal_store.dart';
import 'package:open_ring/features/goals/presentation/goal_pick_screen.dart';
import 'package:open_ring/features/goals/presentation/goal_refusal_screen.dart';
import 'package:open_ring/features/goals/presentation/goal_screening_screen.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/settings/application/unit_system_controller.dart';
import 'package:open_ring/features/settings/application/user_profile_providers.dart';
import 'package:open_ring/features/settings/domain/unit_system.dart';
import 'package:open_ring/features/settings/domain/user_profile.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

import '../../helpers/layout_harness.dart';
import 'goal_fixtures.dart';

const todayStub = 'today stub';
const settingsStub = 'settings stub';
const bodyModuleStub = 'body module stub';

// Born in 1990 and 178 cm: every intake check passes at a trend of 70 kg.
const okProfile = UserProfile(birthYear: 1990, heightCentimeters: 178);

WeightSummary trendOf(double kilograms) => WeightSummary(
  last: WeighIn(
    id: 1,
    at: DateTime.utc(2026, 12, 6, 7),
    offsetMinutes: 0,
    kilograms: kilograms,
    source: WeighInSource.manual,
  ),
  daily: [(date: goalDay(12, 6), value: kilograms)],
  line: [(date: goalDay(12, 6), value: kilograms)],
  rate: const WeightRateBuilding(daysMissing: 1, spanMissing: 1),
  noise: 0.5,
);

/// A store whose start can wait on [gate], come back null or throw, and whose
/// active goal can fail to read. [screeningGate] holds the screening write and
/// [screeningFailures] makes that many writes throw before one goes through.
final class ProbeGoalStore implements GoalStore {
  new(
    this.inner, {
    this.gate,
    this.startsNull = false,
    this.startError,
    this.activeError,
    this.screeningGate,
    this.screeningFailures = 0,
    this.readAfterWriteGate,
  });

  final InMemoryGoalStore inner;
  final Completer<void>? gate;
  final bool startsNull;
  final Error? startError;
  final Error? activeError;
  final Completer<void>? screeningGate;
  int screeningFailures;
  final Completer<void>? readAfterWriteGate;
  var _wrote = false;

  @override
  Future<Goal?> active() async {
    final error = activeError;
    if (error != null) throw error;
    return await inner.active();
  }

  @override
  Future<List<Goal>> goals() => inner.goals();

  @override
  Future<List<GoalScreening>> screenings() async {
    if (_wrote) await readAfterWriteGate?.future;
    return await inner.screenings();
  }

  @override
  Future<void> addScreening(GoalScreening screening) async {
    await screeningGate?.future;
    if (screeningFailures > 0) {
      screeningFailures -= 1;
      throw StateError('disk full');
    }
    await inner.addScreening(screening);
    _wrote = true;
  }

  @override
  Future<Goal?> start(GoalDraft draft) async {
    await gate?.future;
    final error = startError;
    if (error != null) throw error;
    if (startsNull) return null;
    return await inner.start(draft);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('unexpected: ${invocation.memberName}');
}

Future<GoalSetup> setupPicker({
  Set<ModuleId> modules = goalModules,
  UserProfile? profile = okProfile,
  double trendKg = 70,
  bool trendFails = false,
  bool hidden = false,
  UnitSystem units = UnitSystem.metric,
  HideNumbersStore? hideStore,
  GoalDraft? draft,
  InMemoryGoalStore? store,
  GoalStore Function(InMemoryGoalStore memory)? readStoreOf,
  bool demo = false,
}) {
  final memory = store ?? InMemoryGoalStore();
  return setupGoals(
    modules: modules,
    draft: draft,
    store: memory,
    readStore: readStoreOf?.call(memory),
    profileOverride: userProfileStoreProvider.overrideWithValue(
      InMemoryUserProfileStore(profile),
    ),
    weightOverride: weightSummaryProvider.overrideWith((ref) async {
      if (trendFails) throw StateError('weight');
      return trendOf(trendKg);
    }),
    extraOverrides: [
      hideNumbersStoreProvider.overrideWithValue(
        hideStore ?? InMemoryHideNumbersStore(hidden: hidden),
      ),
      unitSystemStoreProvider.overrideWithValue(InMemoryUnitSystemStore(units)),
      demoModeStoreProvider.overrideWithValue(
        InMemoryDemoModeStore(enabled: demo),
      ),
    ],
  );
}

GoRouter goalsRouter(String initial) => GoRouter(
  initialLocation: initial,
  routes: [
    GoRoute(
      path: AppTab.today.path,
      builder: (_, _) => const Scaffold(body: Text(todayStub)),
    ),
    GoRoute(
      path: AppPaths.settings,
      builder: (_, _) => const Scaffold(body: Text(settingsStub)),
    ),
    GoRoute(
      path: AppPaths.settingsModuleBody,
      builder: (_, _) => const Scaffold(body: Text(bodyModuleStub)),
    ),
    GoRoute(
      path: AppPaths.goalsPick,
      builder: (_, state) => GoalPickScreen(
        initial: GoalKind.values.asNameMap()[state.uri.queryParameters['goal']],
      ),
    ),
    GoRoute(
      path: AppPaths.goalsScreening,
      builder: (_, _) => const GoalScreeningScreen(),
    ),
    GoRoute(
      path: '${AppPaths.goalsRefused}/:block',
      builder: (_, state) => GoalRefusalScreen(
        block: IntakeBlock.values.asNameMap()[state.pathParameters['block']],
      ),
    ),
  ],
);

String whereIs(GoRouter router) =>
    router.routeInformationProvider.value.uri.toString();

Future<GoRouter> pumpGoals(
  WidgetTester tester,
  GoalSetup setup, {
  required String at,
  double scale = 1,
  Brightness brightness = Brightness.dark,
}) async {
  final router = goalsRouter(at);
  await pumpScaled(
    tester,
    UncontrolledProviderScope(
      container: setup.container,
      child: MaterialApp.router(
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        localeListResolutionCallback: AppLocales.resolve,
        supportedLocales: AppLocales.supported,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        routerConfig: router,
      ),
    ),
    textScaler: TextScaler.linear(scale),
    brightness: brightness,
    locale: const Locale('en'),
    overrides: const [],
  );
  return router;
}

AppLocalizations l10nOf(WidgetTester tester, Type screen) =>
    AppLocalizations.of(tester.element(find.byType(screen)));

ButtonStyleButton buttonOf(WidgetTester tester, Key key) =>
    tester.widget<ButtonStyleButton>(find.byKey(key));

Future<void> tapKey(WidgetTester tester, Key key) async {
  await tester.ensureVisible(find.byKey(key));
  await tester.pump();
  await tester.tap(find.byKey(key));
  await tester.pumpAndSettle();
}

String allText(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((text) => text.data ?? text.textSpan?.toPlainText() ?? '')
    .join('\n');

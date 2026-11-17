import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/l10n/app_locales.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/theme/app_theme.dart';
import 'package:open_ring/features/goals/domain/goal.dart';
import 'package:open_ring/features/goals/domain/goal_intake.dart';
import 'package:open_ring/features/goals/domain/goal_store.dart';
import 'package:open_ring/features/goals/presentation/goal_pick_screen.dart';
import 'package:open_ring/features/goals/presentation/goal_refusal_screen.dart';
import 'package:open_ring/features/goals/presentation/goal_screening_screen.dart';
import 'package:open_ring/features/goals/presentation/goal_setup_screen.dart';
import 'package:open_ring/features/settings/domain/user_profile.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

import '../../helpers/layout_harness.dart';
import 'goal_fixtures.dart';
import 'goal_picker_harness.dart';

const bodyStub = 'body stub';

const maleProfile = UserProfile(
  birthYear: 1990,
  heightCentimeters: 178,
  sex: Sex.male,
);

const femaleProfile = UserProfile(
  birthYear: 1990,
  heightCentimeters: 178,
  sex: Sex.female,
);

/// Counts the writes the setup makes. [startGate] holds the start and
/// [screeningGate] holds the pregnancy write; [readAfterWriteGate] holds the
/// first read of the screenings that follows a screening write.
class CountingGoalStore implements GoalStore {
  new(
    this.inner, {
    this.startGate,
    this.screeningGate,
    this.readAfterWriteGate,
    this.startError,
    this.startsNull = false,
  });

  final InMemoryGoalStore inner;
  final Completer<void>? startGate;
  final Completer<void>? screeningGate;
  final Completer<void>? readAfterWriteGate;
  final Error? startError;
  final bool startsNull;
  int starts = 0;
  int screeningWrites = 0;
  var _wrote = false;

  @override
  Future<Goal?> active() => inner.active();

  @override
  Future<List<Goal>> goals() => inner.goals();

  @override
  Future<List<GoalScreening>> screenings() async {
    if (_wrote) await readAfterWriteGate?.future;
    return await inner.screenings();
  }

  @override
  Future<void> addScreening(GoalScreening screening) async {
    screeningWrites += 1;
    await screeningGate?.future;
    await inner.addScreening(screening);
    _wrote = true;
  }

  @override
  Future<Goal?> start(GoalDraft draft) async {
    starts += 1;
    await startGate?.future;
    final error = startError;
    if (error != null) throw error;
    if (startsNull) return null;
    return await inner.start(draft);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('unexpected: ${invocation.memberName}');
}

GoRouter setupRouter(String initial) => GoRouter(
  initialLocation: initial,
  routes: [
    GoRoute(
      path: AppTab.today.path,
      builder: (_, _) => const Scaffold(body: Text(todayStub)),
    ),
    GoRoute(
      path: AppPaths.body,
      builder: (_, _) => const Scaffold(body: Text(bodyStub)),
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
      path: AppPaths.goalsSetup,
      builder: (_, _) => const GoalSetupScreen(),
    ),
    GoRoute(
      path: AppPaths.goalsRefusedPregnancy,
      builder: (_, _) => const GoalRefusalScreen.pregnancy(),
    ),
    GoRoute(
      path: '${AppPaths.goalsRefused}/:block',
      builder: (_, state) => GoalRefusalScreen(
        block: IntakeBlock.values.asNameMap()[state.pathParameters['block']],
      ),
    ),
  ],
);

/// Opens [at] on a phone tall enough to build the whole page unless [tall]
/// is false, which the layout tests use to scroll like a person.
Future<GoRouter> pumpSetup(
  WidgetTester tester,
  GoalSetup setup, {
  String at = AppPaths.goalsSetup,
  double scale = 1,
  Brightness brightness = Brightness.dark,
  bool tall = true,
}) async {
  final router = setupRouter(at);
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
  if (!tall) return router;
  tester.view.physicalSize = const Size(360, 6000) * 3;
  await tester.pumpAndSettle();
  return router;
}

Future<void> storeScreening(
  GoalSetup setup, {
  bool? soft,
  bool? pregnant,
  int day = 1,
}) => setup.store.addScreening(
  GoalScreening(
    on: goalDay(12, day),
    softMode: soft,
    pregnantOrBreastfeeding: pregnant,
  ),
);

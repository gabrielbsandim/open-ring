import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:open_ring/app/l10n/app_locales.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/theme/app_theme.dart';
import 'package:open_ring/features/goals/application/goal_ender.dart';
import 'package:open_ring/features/goals/application/goal_providers.dart';
import 'package:open_ring/features/goals/application/goal_store_providers.dart';
import 'package:open_ring/features/goals/application/goals_gate.dart';
import 'package:open_ring/features/goals/domain/goal.dart';
import 'package:open_ring/features/goals/domain/goal_store.dart';
import 'package:open_ring/features/goals/presentation/goal_end_screen.dart';
import 'package:open_ring/features/goals/presentation/goals_module_screen.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/modules/domain/module_store.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

import '../../../helpers/layout_harness.dart';
import '../../../helpers/settings_fakes.dart';
import '../goal_fixtures.dart';
import '../goals_data_harness.dart';

const _goalStub = 'goal stub';

Future<GoRouter> _pump(
  WidgetTester tester, {
  required InMemoryGoalStore store,
  double scale = 1,
  Locale locale = const Locale('en'),
  Brightness brightness = Brightness.light,
  Size size = const Size(400, 2400),
}) async {
  final goal = Goal.started(1, goalDraft());
  final router = GoRouter(
    initialLocation: AppPaths.goalsEnd,
    routes: [
      GoRoute(
        path: AppPaths.goals,
        builder: (_, _) => const Scaffold(body: Text(_goalStub)),
        routes: [
          GoRoute(path: 'end', builder: (_, _) => const GoalEndScreen()),
        ],
      ),
      GoRoute(
        path: AppPaths.settingsModuleGoals,
        builder: (_, _) => const GoalsModuleScreen(),
      ),
    ],
  );
  addTearDown(router.dispose);
  await pumpScaled(
    tester,
    MaterialApp.router(
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      localeListResolutionCallback: AppLocales.resolve,
      supportedLocales: AppLocales.supported,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      routerConfig: router,
    ),
    textScaler: TextScaler.linear(scale),
    brightness: brightness,
    locale: locale,
    size: size,
    overrides: [
      goalsEnabledProvider.overrideWithValue(true),
      moduleStoreProvider.overrideWithValue(InMemoryModuleStore(goalModules)),
      goalStoreProvider.overrideWithValue(store),
      activeGoalProvider.overrideWith((ref) async => goal),
      goalEndRaiseProvider.overrideWith((ref) async => null),
    ],
  );
  return router;
}

void main() {
  group('10. the end screen tile', () {
    testWidgets('opens the Goals module screen', (tester) async {
      final store = InMemoryGoalStore();
      await seedGoalsData(store);
      await _pump(tester, store: store);

      await tester.ensureVisible(find.byKey(GoalEndKeys.deleteData));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(GoalEndKeys.deleteData));
      await tester.pumpAndSettle();

      expect(find.byType(GoalsModuleScreen), findsOneWidget);
      expect(find.byType(GoalEndScreen), findsNothing);
    });

    testWidgets('is not a second delete flow: nothing is asked or deleted', (
      tester,
    ) async {
      final store = InMemoryGoalStore();
      await seedGoalsData(store);
      await _pump(tester, store: store);

      await tester.ensureVisible(find.byKey(GoalEndKeys.deleteData));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      await tester.tap(find.byKey(GoalEndKeys.deleteData));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(await store.count(), 5);
    });

    testWidgets('sits with the switch and end choices', (tester) async {
      final store = InMemoryGoalStore();
      await seedGoalsData(store);
      await _pump(tester, store: store);

      expect(find.byKey(GoalEndKeys.switchGoal), findsOneWidget);
      expect(find.byKey(GoalEndKeys.endGoal), findsOneWidget);
      expect(find.byKey(GoalEndKeys.deleteData), findsOneWidget);
    });
  });

  group('12. layout of the end screen', () {
    for (final c in layoutMatrix()) {
      testWidgets('shows the tile at $c', (tester) async {
        final store = InMemoryGoalStore();
        await seedGoalsData(store);
        await _pump(
          tester,
          store: store,
          scale: c.scale,
          brightness: c.brightness,
          locale: c.locale,
          size: phoneSize,
        );

        await scrollThrough(tester);
        await reveal(tester, find.byKey(GoalEndKeys.deleteData));

        expect(find.byKey(GoalEndKeys.deleteData), findsOneWidget);
      });
    }
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:open_ring/app/l10n/app_locales.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/theme/app_theme.dart';
import 'package:open_ring/features/demo/application/demo_mode_controller.dart';
import 'package:open_ring/features/demo/domain/demo_mode_store.dart';
import 'package:open_ring/features/goals/application/goal_ender.dart';
import 'package:open_ring/features/goals/application/goal_providers.dart';
import 'package:open_ring/features/goals/application/goal_week_view.dart';
import 'package:open_ring/features/goals/application/goals_gate.dart';
import 'package:open_ring/features/goals/domain/goal.dart';
import 'package:open_ring/features/goals/domain/goal_end.dart';
import 'package:open_ring/features/goals/presentation/goal_end_screen.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

import '../../../helpers/layout_harness.dart';
import '../goal_fixtures.dart';

const _goalStub = 'goal stub';
const _pickStub = 'pick stub';
const StepGoalRaise _raised = (from: 8000, to: 10000);

Goal? _active;

class _Ender extends GoalEnder {
  new(this.outcome);

  final GoalEndOutcome outcome;
  bool retryDone = true;
  final ends = <(GoalEndReason, int?)>[];
  final retries = <int>[];

  @override
  Future<GoalEndOutcome> end(GoalEndReason reason, {int? stepGoalBack}) async {
    ends.add((reason, stepGoalBack));
    if (outcome != GoalEndOutcome.refused) _active = null;
    ref.invalidate(activeGoalProvider);
    return outcome;
  }

  @override
  Future<bool> retryStepGoalBack(int steps) async {
    retries.add(steps);
    return retryDone;
  }
}

Future<void> _pump(
  WidgetTester tester, {
  _Ender? ender,
  StepGoalRaise? raise = _raised,
  bool on = true,
  double scale = 1,
  Locale locale = const Locale('en'),
  Size size = const Size(400, 2400),
  Brightness brightness = Brightness.light,
}) async {
  _active = Goal.started(1, goalDraft());
  final router = GoRouter(
    initialLocation: AppPaths.goalsEnd,
    routes: [
      GoRoute(
        path: AppPaths.goals,
        builder: (_, _) => const Scaffold(body: Text(_goalStub)),
        routes: [
          GoRoute(path: 'end', builder: (_, _) => const GoalEndScreen()),
          GoRoute(
            path: 'pick',
            builder: (_, _) => const Scaffold(body: Text(_pickStub)),
          ),
        ],
      ),
    ],
  );
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
      goalsEnabledProvider.overrideWithValue(on),
      activeGoalProvider.overrideWith((ref) async => _active),
      goalEndRaiseProvider.overrideWith((ref) async => raise),
      goalEnderProvider.overrideWith(
        () => ender ?? _Ender(GoalEndOutcome.ended),
      ),
    ],
  );
}

Future<void> _tap(WidgetTester tester, Key key) async {
  await tester.ensureVisible(find.byKey(key));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(key));
  await tester.pumpAndSettle();
}

String _text(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((text) => text.data ?? text.textSpan?.toPlainText() ?? '')
    .join('\n');

void main() {
  testWidgets('offers switch and end, and says what the plan raised', (
    tester,
  ) async {
    await _pump(tester);
    expect(find.byKey(GoalEndKeys.switchGoal), findsOneWidget);
    expect(find.byKey(GoalEndKeys.endGoal), findsOneWidget);
    expect(_text(tester), contains('Lose fat. None of these options deletes'));
    expect(
      _text(tester),
      contains('since the goal started it went from 8,000 to 10,000'),
    );
  });

  testWidgets('without a plan raise there is no step goal notice', (
    tester,
  ) async {
    await _pump(tester, raise: null);
    expect(find.byKey(GoalEndKeys.notice), findsNothing);
  });

  testWidgets('ending and keeping the raised goal ends with no step goal', (
    tester,
  ) async {
    final ender = _Ender(GoalEndOutcome.ended);
    await _pump(tester, ender: ender);
    await _tap(tester, GoalEndKeys.endGoal);
    expect(find.text('Keep 10,000 steps'), findsOneWidget);
    expect(find.text('Go back to 8,000 steps'), findsOneWidget);
    expect(find.byKey(GoalEndKeys.confirm), findsNothing);
    await _tap(tester, GoalEndKeys.keep);
    expect(ender.ends, [(GoalEndReason.person, null)]);
    expect(find.text(_goalStub), findsOneWidget);
  });

  testWidgets('going back asks the ender for the starting goal', (
    tester,
  ) async {
    final ender = _Ender(GoalEndOutcome.ended);
    await _pump(tester, ender: ender);
    await _tap(tester, GoalEndKeys.endGoal);
    await _tap(tester, GoalEndKeys.goBack);
    expect(ender.ends, [(GoalEndReason.person, 8000)]);
    expect(find.text(_goalStub), findsOneWidget);
  });

  testWidgets('switching without a raise has one button and opens the picker', (
    tester,
  ) async {
    final ender = _Ender(GoalEndOutcome.ended);
    await _pump(tester, ender: ender, raise: null);
    await _tap(tester, GoalEndKeys.switchGoal);
    expect(find.text('Switch goal?'), findsOneWidget);
    expect(find.byKey(GoalEndKeys.keep), findsNothing);
    expect(find.byKey(GoalEndKeys.goBack), findsNothing);
    await _tap(tester, GoalEndKeys.confirm);
    expect(ender.ends, [(GoalEndReason.switched, null)]);
    expect(find.text(_pickStub), findsOneWidget);
  });

  testWidgets('cancel goes back to the two choices', (tester) async {
    final ender = _Ender(GoalEndOutcome.ended);
    await _pump(tester, ender: ender);
    await _tap(tester, GoalEndKeys.endGoal);
    await _tap(tester, GoalEndKeys.cancel);
    expect(find.byKey(GoalEndKeys.switchGoal), findsOneWidget);
    expect(ender.ends, isEmpty);
  });

  testWidgets('a failed step goal keeps the retry after the goal ended', (
    tester,
  ) async {
    final ender = _Ender(GoalEndOutcome.stepGoalFailed)..retryDone = false;
    await _pump(tester, ender: ender);
    await _tap(tester, GoalEndKeys.endGoal);
    await _tap(tester, GoalEndKeys.goBack);
    expect(_active, isNull);
    expect(
      _text(tester),
      contains(
        'The goal ended, but your step goal could not go back to 8,000.',
      ),
    );
    await _tap(tester, GoalEndKeys.retry);
    expect(ender.retries, [8000]);
    expect(find.byKey(GoalEndKeys.retry), findsOneWidget);
    ender.retryDone = true;
    await _tap(tester, GoalEndKeys.retry);
    expect(ender.retries, [8000, 8000]);
    expect(find.text(_goalStub), findsOneWidget);
  });

  testWidgets('a refused end leaves the goal and shows the choices', (
    tester,
  ) async {
    final ender = _Ender(GoalEndOutcome.refused);
    await _pump(tester, ender: ender);
    await _tap(tester, GoalEndKeys.endGoal);
    await _tap(tester, GoalEndKeys.keep);
    expect(find.byKey(GoalEndKeys.switchGoal), findsOneWidget);
    expect(find.text(_goalStub), findsNothing);
    expect(find.text('The goal did not end. Nothing changed.'), findsOneWidget);
  });

  testWidgets('Goals off shows nothing to choose', (tester) async {
    await _pump(tester, on: false);
    expect(find.byKey(GoalEndKeys.switchGoal), findsNothing);
  });

  test('the This week card has nothing to show after an end', () async {
    final setup = await setupGoals(
      draft: goalDraft(),
      extraOverrides: [
        demoModeStoreProvider.overrideWithValue(InMemoryDemoModeStore()),
      ],
    );
    setup.container.listen(demoModeProvider, (_, _) {});
    final before = await setup.container.read(goalWeekProvider.future);
    expect(before, isNot(isA<GoalWeekNoGoal>()));
    final outcome = await setup.container
        .read(goalEnderProvider.notifier)
        .end(GoalEndReason.person);
    expect(outcome, GoalEndOutcome.ended);
    final after = await setup.container.read(goalWeekProvider.future);
    expect(after, isA<GoalWeekNoGoal>());
  });

  for (final brightness in Brightness.values) {
    for (final locale in const [Locale('en'), Locale('de')]) {
      for (final scale in const [1.0, 1.3, 2.0]) {
        testWidgets('lays out in $locale at ${scale}x, ${brightness.name}', (
          tester,
        ) async {
          await _pump(
            tester,
            scale: scale,
            locale: locale,
            size: phoneSize,
            brightness: brightness,
          );
          await tester.scrollUntilVisible(find.byKey(GoalEndKeys.endGoal), 200);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await _tap(tester, GoalEndKeys.endGoal);
          await tester.scrollUntilVisible(find.byKey(GoalEndKeys.cancel), 200);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/l10n/app_locales.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/theme/app_theme.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/features/body/application/hide_numbers_controller.dart';
import 'package:open_ring/features/body/domain/hide_numbers_store.dart';
import 'package:open_ring/features/goals/application/goal_ender.dart';
import 'package:open_ring/features/goals/application/goal_path_providers.dart';
import 'package:open_ring/features/goals/application/goal_providers.dart';
import 'package:open_ring/features/goals/application/goal_week_view.dart';
import 'package:open_ring/features/goals/application/goals_gate.dart';
import 'package:open_ring/features/goals/domain/goal.dart';
import 'package:open_ring/features/goals/presentation/goal_end_screen.dart';
import 'package:open_ring/features/goals/presentation/goal_screen.dart';
import 'package:open_ring/features/settings/application/unit_system_controller.dart';
import 'package:open_ring/features/settings/domain/unit_system.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

import '../../../helpers/layout_harness.dart';
import '../goal_fixtures.dart';

const _today = LocalDate(2026, 12, 10);
const _until = LocalDate(2027, 1, 6);

GoalWeekView _view = const GoalWeekNoGoal();

GoalWeekView _running(Goal goal, {GoalMaintenance? maintenance}) =>
    GoalWeekRunning(
      goal: goal,
      monday: const LocalDate(2026, 12, 7),
      week: 4,
      levers: const [],
      review: null,
      maintenance: maintenance,
    );

class _Ender extends GoalEnder {
  new({this.done = true, this.gate});

  final bool done;
  final Completer<bool>? gate;
  int maintains = 0;

  @override
  Future<bool> maintainNow() async {
    maintains++;
    final result = gate == null ? done : await gate!.future;
    if (!result) return false;
    _view = _running(
      Goal.started(
        1,
        goalDraft(),
      ).inPhase(GoalPhase.maintenance, since: _today, until: _until),
      maintenance: const GoalMaintenance(until: _until, over: false),
    );
    ref.invalidate(goalWeekProvider);
    return true;
  }
}

Future<void> _pump(
  WidgetTester tester, {
  required GoalWeekView view,
  _Ender? ender,
  double scale = 1,
  Locale locale = const Locale('en'),
  Size size = const Size(400, 2400),
  Brightness brightness = Brightness.light,
}) async {
  _view = view;
  final router = GoRouter(
    initialLocation: AppPaths.goalsEnd,
    routes: [
      GoRoute(
        path: AppPaths.goals,
        builder: (_, _) => const GoalScreen(),
        routes: [
          GoRoute(path: 'end', builder: (_, _) => const GoalEndScreen()),
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
      goalsEnabledProvider.overrideWithValue(true),
      activeGoalProvider.overrideWith(
        (ref) async => Goal.started(1, goalDraft()),
      ),
      goalEndRaiseProvider.overrideWith((ref) async => null),
      goalWeekProvider.overrideWith((ref) async => _view),
      goalPathProvider.overrideWith((ref) async => null),
      currentDateProvider.overrideWithValue(_today),
      hideNumbersStoreProvider.overrideWithValue(InMemoryHideNumbersStore()),
      unitSystemStoreProvider.overrideWithValue(
        InMemoryUnitSystemStore(UnitSystem.metric),
      ),
      goalEnderProvider.overrideWith(() => ender ?? _Ender()),
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

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(GoalEndScreen)));

void main() {
  group('G11b2 criterion 8: the maintenance tile', () {
    testWidgets('shows for a running lose fat block', (tester) async {
      await _pump(tester, view: _running(Goal.started(1, goalDraft())));

      expect(find.byKey(GoalEndKeys.maintain), findsOneWidget);
      expect(find.text(_l10n(tester).goalsEndMaintain), findsOneWidget);
      expect(find.byKey(GoalEndKeys.switchGoal), findsOneWidget);
      expect(find.byKey(GoalEndKeys.endGoal), findsOneWidget);
    });

    for (final (name, view) in <(String, GoalWeekView)>[
      (
        'a goal already in maintenance',
        _running(
          Goal.started(1, goalDraft()),
          maintenance: const GoalMaintenance(until: _until, over: false),
        ),
      ),
      (
        'a getFitter goal',
        _running(Goal.started(1, goalDraft(kind: GoalKind.getFitter))),
      ),
      (
        'a sleepBetter goal',
        _running(Goal.started(1, goalDraft(kind: GoalKind.sleepBetter))),
      ),
      ('Body off', GoalWeekHold(goal: Goal.started(1, goalDraft()))),
      (
        'a pause',
        GoalWeekPaused(
          goal: Goal.started(1, goalDraft()),
          until: _until,
          rule: null,
          over: false,
        ),
      ),
    ]) {
      testWidgets('is absent for $name', (tester) async {
        await _pump(tester, view: view);

        expect(find.byKey(GoalEndKeys.maintain), findsNothing);
        expect(find.byKey(GoalEndKeys.endGoal), findsOneWidget);
      });
    }

    testWidgets('asks to confirm and names the day it lasts until', (
      tester,
    ) async {
      final ender = _Ender();
      await _pump(
        tester,
        view: _running(Goal.started(1, goalDraft())),
        ender: ender,
      );

      await _tap(tester, GoalEndKeys.maintain);

      final l10n = _l10n(tester);
      expect(find.text(l10n.goalsEndConfirmMaintainTitle), findsOneWidget);
      expect(_text(tester), contains('Jan 6'));
      expect(find.byKey(GoalEndKeys.confirm), findsOneWidget);
      expect(find.byKey(GoalEndKeys.cancel), findsOneWidget);
      expect(ender.maintains, 0);
    });

    testWidgets('confirming moves to the goal screen with the keeping line', (
      tester,
    ) async {
      final ender = _Ender();
      await _pump(
        tester,
        view: _running(Goal.started(1, goalDraft())),
        ender: ender,
      );

      await _tap(tester, GoalEndKeys.maintain);
      await _tap(tester, GoalEndKeys.confirm);

      expect(ender.maintains, 1);
      expect(find.byType(GoalEndScreen), findsNothing);
      expect(find.byType(GoalScreen), findsOneWidget);
      expect(find.byKey(GoalScreenKeys.maintenance), findsOneWidget);
    });

    testWidgets('cancel writes nothing and shows the tiles again', (
      tester,
    ) async {
      final ender = _Ender();
      await _pump(
        tester,
        view: _running(Goal.started(1, goalDraft())),
        ender: ender,
      );

      await _tap(tester, GoalEndKeys.maintain);
      await _tap(tester, GoalEndKeys.cancel);

      expect(ender.maintains, 0);
      expect(find.byKey(GoalEndKeys.maintain), findsOneWidget);
      expect(find.byKey(GoalEndKeys.confirm), findsNothing);
    });

    testWidgets('a refusal shows the caption and stays on the screen', (
      tester,
    ) async {
      final ender = _Ender(done: false);
      await _pump(
        tester,
        view: _running(Goal.started(1, goalDraft())),
        ender: ender,
      );

      await _tap(tester, GoalEndKeys.maintain);
      await _tap(tester, GoalEndKeys.confirm);

      final l10n = _l10n(tester);
      expect(ender.maintains, 1);
      expect(find.byType(GoalEndScreen), findsOneWidget);
      expect(find.byKey(GoalEndKeys.refused), findsOneWidget);
      expect(find.text(l10n.goalsEndMaintainRefused), findsOneWidget);
      expect(find.text(l10n.goalsEndRefused), findsNothing);
      expect(find.byKey(GoalEndKeys.maintain), findsOneWidget);
    });

    testWidgets('a double tap writes once', (tester) async {
      final gate = Completer<bool>();
      final ender = _Ender(gate: gate);
      await _pump(
        tester,
        view: _running(Goal.started(1, goalDraft())),
        ender: ender,
      );
      await _tap(tester, GoalEndKeys.maintain);

      await tester.tap(find.byKey(GoalEndKeys.confirm));
      await tester.pump();
      await tester.tap(find.byKey(GoalEndKeys.confirm), warnIfMissed: false);
      await tester.pump();
      gate.complete(true);
      await tester.pumpAndSettle();

      expect(ender.maintains, 1);
    });
  });

  group('G11b2 criterion 9: the end screen lays out with three tiles', () {
    for (final layout in layoutMatrix()) {
      testWidgets('tiles and confirm at $layout', (tester) async {
        await _pump(
          tester,
          view: _running(Goal.started(1, goalDraft())),
          scale: layout.scale,
          locale: layout.locale,
          size: phoneSize,
          brightness: layout.brightness,
        );
        await tester.scrollUntilVisible(find.byKey(GoalEndKeys.maintain), 200);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        await _tap(tester, GoalEndKeys.maintain);
        await tester.scrollUntilVisible(find.byKey(GoalEndKeys.cancel), 200);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });
}

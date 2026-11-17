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
import 'package:open_ring/features/goals/application/goal_path_providers.dart';
import 'package:open_ring/features/goals/application/goal_providers.dart';
import 'package:open_ring/features/goals/application/goal_week_view.dart';
import 'package:open_ring/features/goals/domain/goal.dart';
import 'package:open_ring/features/goals/domain/goal_path.dart';
import 'package:open_ring/features/goals/presentation/goal_screen.dart';
import 'package:open_ring/features/settings/application/unit_system_controller.dart';
import 'package:open_ring/features/settings/domain/unit_system.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

import '../../../helpers/layout_harness.dart';

const _start = LocalDate(2026, 11, 16);
const _today = LocalDate(2027, 2, 24);
const _until = LocalDate(2027, 3, 7);
const _steps = Lever(kind: LeverKind.steps, target: 9000);

Goal _goal({GoalPhase phase = GoalPhase.block, double? reference = 74}) => Goal(
  id: 1,
  kind: GoalKind.loseFat,
  pace: GoalPace.standard,
  startedOn: _start,
  anchorKg: 78.4,
  referenceKg: reference,
  blockStartedOn: _start,
  blockAnchorKg: 78.4,
  phase: phase,
  phaseSince: _today.addDays(-14),
  phaseUntil: phase == GoalPhase.maintenance ? _until : null,
  levers: const [_steps],
  endedOn: null,
  endReason: null,
);

GoalWeekView _keeping({required bool over}) => GoalWeekRunning(
  goal: _goal(phase: GoalPhase.maintenance),
  monday: const LocalDate(2027, 2, 22),
  week: 15,
  levers: const [],
  review: null,
  maintenance: GoalMaintenance(until: _until, over: over),
);

GoalPathView _path({double? reference = 74}) {
  final goal = _goal(reference: reference);
  final daily = [
    for (var d = 0; d <= 20; d += 2)
      (date: _start.addDays(d), value: 78.4 - d * 0.03),
  ];
  return (
    path: goalPath(
      goal: goal,
      snapshot: (
        rate: const WeightRateReady(
          perWeek: -0.2958,
          low: -0.3881,
          high: -0.2034,
        ),
        trendKg: 77.782,
      ),
      heightCm: 178,
      on: const LocalDate(2027, 2, 21),
    ),
    daily: daily,
    line: weightTrend(daily),
  );
}

Future<void> _pump(
  WidgetTester tester, {
  required GoalWeekView week,
  double? reference = 74,
  bool hidden = false,
  double scale = 1,
  Locale locale = const Locale('en'),
  Brightness brightness = Brightness.light,
}) async {
  final router = GoRouter(
    initialLocation: AppPaths.goals,
    routes: [
      GoRoute(path: AppPaths.goals, builder: (_, _) => const GoalScreen()),
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
    overrides: [
      goalWeekProvider.overrideWith((ref) async => week),
      goalPathProvider.overrideWith((ref) async => _path(reference: reference)),
      currentDateProvider.overrideWithValue(_today),
      hideNumbersStoreProvider.overrideWithValue(
        InMemoryHideNumbersStore(hidden: hidden),
      ),
      unitSystemStoreProvider.overrideWithValue(
        InMemoryUnitSystemStore(UnitSystem.metric),
      ),
    ],
  );
}

String _text(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((text) => text.data ?? text.textSpan?.toPlainText() ?? '')
    .join('\n');

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(GoalScreen)));

GoalWeekView _running() => GoalWeekRunning(
  goal: _goal(),
  monday: const LocalDate(2027, 2, 22),
  week: 15,
  levers: const [],
  review: null,
);

void main() {
  group('no rate target in maintenance', () {
    testWidgets('the rate row drops the target and says why', (tester) async {
      await _pump(tester, week: _keeping(over: false));

      final text = _text(tester);
      expect(text, contains('Maintenance has no rate target.'));
      expect(text, isNot(contains('Target:')));
    });

    testWidgets('the pace tile reads none without a reference', (tester) async {
      await _pump(tester, week: _keeping(over: false), reference: null);

      final tile = find.byKey(GoalScreenKeys.reference);
      expect(
        find.descendant(
          of: tile,
          matching: find.text(_l10n(tester).goalsPathPaceKeeping),
        ),
        findsOneWidget,
      );
    });

    testWidgets('the rate sheet names no target', (tester) async {
      await _pump(tester, week: _keeping(over: false));
      await tester.ensureVisible(find.byKey(GoalScreenKeys.rate));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(GoalScreenKeys.rate));
      await tester.pumpAndSettle();

      final text = _text(tester);
      expect(text, contains('Maintenance has no rate target.'));
      expect(text, isNot(contains('The target is')));
    });

    testWidgets('hidden numbers give no band word', (tester) async {
      await _pump(tester, week: _keeping(over: false), hidden: true);

      final l10n = _l10n(tester);
      final text = _text(tester);
      expect(find.byKey(GoalScreenKeys.hidden), findsOneWidget);
      for (final word in [
        l10n.goalsPathStateAbove,
        l10n.goalsPathStateOnTrack,
        l10n.goalsPathStateBelow,
      ]) {
        expect(text, isNot(contains(word)), reason: word);
      }
    });

    testWidgets('a running block still reads its target', (tester) async {
      await _pump(tester, week: _running(), reference: null);

      final text = _text(tester);
      expect(text, contains('Target:'));
      expect(text, isNot(contains('Maintenance has no rate target.')));
      expect(text, isNot(contains(_l10n(tester).goalsPathPaceKeeping)));
    });
  });

  group('G11b2 criterion 7: the goal screen in maintenance', () {
    testWidgets('the subtitle is the keeping line', (tester) async {
      await _pump(tester, week: _keeping(over: false));

      final line = _l10n(tester).goalsScreenKeepingUntil('Sun, Mar 7');
      expect(find.byKey(GoalScreenKeys.maintenance), findsOneWidget);
      expect(_text(tester), contains(line));
    });

    testWidgets('never reads Week 15 of 12', (tester) async {
      await _pump(tester, week: _keeping(over: false));

      final text = _text(tester);
      expect(text, isNot(contains('Week 15')));
      expect(text, isNot(contains('of 12')));
    });

    testWidgets('over reads the F5 line and no keeping line', (tester) async {
      await _pump(tester, week: _keeping(over: true));

      final l10n = _l10n(tester);
      final text = _text(tester);
      expect(find.byKey(GoalScreenKeys.maintenance), findsOneWidget);
      expect(text, contains(l10n.goalsScreenMaintenanceOver('Sun, Mar 7')));
      expect(text, isNot(contains(l10n.goalsScreenKeepingUntil('Sun, Mar 7'))));
      expect(text, isNot(contains('Week 15')));
    });

    testWidgets('a running block keeps its week line and no maintenance', (
      tester,
    ) async {
      await _pump(
        tester,
        week: GoalWeekRunning(
          goal: _goal(),
          monday: const LocalDate(2026, 12, 7),
          week: 4,
          levers: const [],
          review: null,
        ),
      );

      expect(find.byKey(GoalScreenKeys.maintenance), findsNothing);
      expect(_text(tester), contains('Week 4 of 12'));
    });
  });

  group('G11b2 criterion 9: the screen lays out in maintenance', () {
    for (final layout in layoutMatrix()) {
      for (final over in [false, true]) {
        testWidgets('${over ? 'over' : 'keeping'} at $layout', (tester) async {
          await _pump(
            tester,
            week: _keeping(over: over),
            scale: layout.scale,
            locale: layout.locale,
            brightness: layout.brightness,
          );

          expect(find.byKey(GoalScreenKeys.maintenance), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      }
    }
  });
}

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
import 'package:open_ring/features/goals/presentation/goal_evidence_sheet.dart';
import 'package:open_ring/features/goals/presentation/goal_screen.dart';
import 'package:open_ring/features/settings/application/unit_system_controller.dart';
import 'package:open_ring/features/settings/domain/unit_system.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

import '../../../helpers/layout_harness.dart';

const _pickStub = 'pick stub';
const _formulaStub = 'formula stub';
const _today = LocalDate(2026, 12, 10);
const _on = LocalDate(2026, 12, 6);

Goal _goal({
  GoalKind kind = GoalKind.loseFat,
  double? referenceKg = 74.0,
  GoalPhase phase = GoalPhase.block,
  LocalDate? until,
}) {
  const start = LocalDate(2026, 11, 16);
  final weighed = kind == GoalKind.loseFat;
  return Goal(
    id: 1,
    kind: kind,
    pace: weighed ? GoalPace.standard : null,
    startedOn: start,
    anchorKg: weighed ? 78.4 : null,
    referenceKg: weighed ? referenceKg : null,
    blockStartedOn: start,
    blockAnchorKg: weighed ? 78.4 : null,
    phase: phase,
    phaseSince: start,
    phaseUntil: until,
    levers: const [],
    endedOn: null,
    endReason: null,
  );
}

GoalPathView _view(
  Goal goal, {
  WeightRate rate = const WeightRateReady(
    perWeek: -0.2958,
    low: -0.3881,
    high: -0.2034,
  ),
  double? trendKg = 77.782,
}) {
  final daily = [
    for (var d = 0; d <= 20; d += 2)
      (date: const LocalDate(2026, 11, 16).addDays(d), value: 78.4 - d * 0.03),
  ];
  return (
    path: goalPath(
      goal: goal,
      snapshot: (rate: rate, trendKg: trendKg),
      heightCm: 178,
      on: _on,
    ),
    daily: daily,
    line: weightTrend(daily),
  );
}

GoalWeekView _running(Goal goal) => GoalWeekRunning(
  goal: goal,
  monday: const LocalDate(2026, 12, 7),
  week: 4,
  levers: const [],
  review: null,
);

Future<GoRouter> _pump(
  WidgetTester tester, {
  required GoalWeekView week,
  GoalPathView? path,
  bool hidden = false,
  UnitSystem units = UnitSystem.metric,
  double scale = 1,
  Locale locale = const Locale('en'),
}) async {
  final router = GoRouter(
    initialLocation: AppPaths.goals,
    routes: [
      GoRoute(path: AppPaths.goals, builder: (_, _) => const GoalScreen()),
      GoRoute(
        path: AppPaths.goalsPick,
        builder: (_, _) => const Scaffold(body: Text(_pickStub)),
      ),
      GoRoute(
        path: AppPaths.goalsFormula,
        builder: (_, _) => const Scaffold(body: Text(_formulaStub)),
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
    brightness: Brightness.light,
    locale: locale,
    overrides: [
      goalWeekProvider.overrideWith((ref) async => week),
      goalPathProvider.overrideWith((ref) async => path),
      currentDateProvider.overrideWithValue(_today),
      hideNumbersStoreProvider.overrideWithValue(
        InMemoryHideNumbersStore(hidden: hidden),
      ),
      unitSystemStoreProvider.overrideWithValue(InMemoryUnitSystemStore(units)),
    ],
  );
  return router;
}

String _text(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((text) => text.data ?? text.textSpan?.toPlainText() ?? '')
    .join('\n');

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(GoalScreen)));

void main() {
  testWidgets('off shows one line and nothing else', (tester) async {
    await _pump(tester, week: const GoalWeekOff());
    expect(find.byKey(GoalScreenKeys.off), findsOneWidget);
    expect(find.byKey(GoalScreenKeys.path), findsNothing);
  });

  for (final (name, week) in [
    ('no goal', const GoalWeekNoGoal()),
    ('a running goal', _running(_goal())),
  ]) {
    testWidgets('$name links to how we calculate', (tester) async {
      await _pump(tester, week: week, path: _view(_goal()));
      await tester.ensureVisible(find.byKey(GoalScreenKeys.formula));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(GoalScreenKeys.formula));
      await tester.pumpAndSettle();
      expect(find.text(_formulaStub), findsOneWidget);
    });
  }

  testWidgets('no goal offers the picker', (tester) async {
    await _pump(tester, week: const GoalWeekNoGoal());
    expect(find.byKey(GoalScreenKeys.noGoal), findsOneWidget);
    await tester.tap(find.byKey(GoalScreenKeys.pick));
    await tester.pumpAndSettle();
    expect(find.text(_pickStub), findsOneWidget);
  });

  testWidgets('running with a reference shows the path, rate and arrival', (
    tester,
  ) async {
    final goal = _goal();
    await _pump(tester, week: _running(goal), path: _view(goal));
    final text = _text(tester);
    final l10n = _l10n(tester);
    expect(find.byKey(GoalScreenKeys.chart), findsOneWidget);
    expect(text, contains('78.4 kg'));
    expect(text, contains('77.8 kg'));
    expect(text, contains('74.0 kg'));
    expect(text, contains('0.30 kg a week'));
    expect(text, contains(l10n.goalsPathStateOnTrack));
    expect(text, contains('March to May 2027'));
    expect(text, contains('Week 4 of 12'));
  });

  testWidgets('running without a reference shows the pace target', (
    tester,
  ) async {
    final goal = _goal(referenceKg: null);
    await _pump(tester, week: _running(goal), path: _view(goal));
    final l10n = _l10n(tester);
    expect(find.byKey(GoalScreenKeys.arrival), findsNothing);
    expect(_text(tester), contains(l10n.goalsPathPace));
    expect(_text(tester), contains('0.5% a week'));
  });

  testWidgets('paused shows the pause and no arrival range', (tester) async {
    final goal = _goal(
      phase: GoalPhase.paused,
      until: const LocalDate(2027, 1, 3),
    );
    await _pump(
      tester,
      week: GoalWeekPaused(
        goal: goal,
        until: goal.phaseUntil,
        rule: null,
        over: false,
      ),
      path: _view(goal),
    );
    final l10n = _l10n(tester);
    final text = _text(tester);
    expect(text, contains(l10n.goalsPathArrivalPaused));
    expect(text, isNot(contains('March to May 2027')));
  });

  testWidgets('base shows the base note and no chart', (tester) async {
    final goal = _goal();
    await _pump(
      tester,
      week: GoalWeekBase(
        goal: goal,
        rate: const WeightRateBuilding(daysMissing: 3, spanMissing: 0),
      ),
      path: _view(
        goal,
        rate: const WeightRateBuilding(daysMissing: 3, spanMissing: 0),
      ),
    );
    final l10n = _l10n(tester);
    expect(find.byKey(GoalScreenKeys.baseNote), findsOneWidget);
    expect(find.byKey(GoalScreenKeys.chart), findsNothing);
    expect(find.byKey(GoalScreenKeys.arrival), findsNothing);
    expect(_text(tester), contains(l10n.goalsPathRateNotYet));
  });

  testWidgets('hold with Body off shows no weight', (tester) async {
    final goal = _goal();
    await _pump(
      tester,
      week: GoalWeekHold(goal: goal),
      path: _view(goal),
    );
    expect(find.byKey(GoalScreenKeys.hold), findsOneWidget);
    expect(find.byKey(GoalScreenKeys.path), findsNothing);
    expect(_text(tester), isNot(contains('kg')));
  });

  testWidgets('get fitter reads no weight', (tester) async {
    final goal = _goal(kind: GoalKind.getFitter);
    await _pump(tester, week: _running(goal));
    final l10n = _l10n(tester);
    expect(find.byKey(GoalScreenKeys.noWeight), findsOneWidget);
    expect(find.byKey(GoalScreenKeys.path), findsNothing);
    expect(_text(tester), contains(l10n.goalsPickGetFitter));
    expect(_text(tester), contains('Week 4'));
  });

  testWidgets('hidden numbers show no number of weight anywhere', (
    tester,
  ) async {
    final goal = _goal();
    await _pump(tester, week: _running(goal), path: _view(goal), hidden: true);
    final l10n = _l10n(tester);
    expect(find.byKey(GoalScreenKeys.hidden), findsOneWidget);
    expect(find.byKey(GoalScreenKeys.chart), findsNothing);
    expect(find.byKey(GoalScreenKeys.arrival), findsNothing);
    final text = _text(tester);
    expect(text, isNot(contains('kg')));
    expect(text, isNot(contains('%')));
    expect(text, isNot(contains('2027')));
    expect(text, contains(l10n.bodyDirectionDown));
    await tester.tap(find.byKey(GoalScreenKeys.rate));
    await tester.pumpAndSettle();
    final yours = tester.widget<Text>(
      find.descendant(
        of: find.byKey(GoalEvidenceKeys.yours),
        matching: find.text(l10n.bodyHiddenNote),
      ),
    );
    expect(yours.data, l10n.bodyHiddenNote);
    final sheet = tester
        .widgetList<Text>(
          find.descendant(
            of: find.byKey(GoalEvidenceKeys.sheet),
            matching: find.byType(Text),
          ),
        )
        .map((text) => text.data ?? '')
        .join('\n');
    expect(sheet, isNot(contains('kg')));
  });

  testWidgets('the rate sheet carries the numbers of the path', (tester) async {
    final goal = _goal();
    await _pump(tester, week: _running(goal), path: _view(goal));
    await tester.ensureVisible(find.byKey(GoalScreenKeys.rate));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(GoalScreenKeys.rate));
    await tester.pumpAndSettle();
    final yours = tester
        .widgetList<Text>(
          find.descendant(
            of: find.byKey(GoalEvidenceKeys.yours),
            matching: find.byType(Text),
          ),
        )
        .map((text) => text.data ?? '')
        .join('\n');
    expect(yours, contains('0.30 kg'));
    expect(yours, contains('0.38%'));
    expect(yours, contains('0.5%'));
  });

  testWidgets('the arrival sheet counts both ends', (tester) async {
    final goal = _goal();
    await _pump(tester, week: _running(goal), path: _view(goal));
    await tester.ensureVisible(find.byKey(GoalScreenKeys.arrival));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(GoalScreenKeys.arrival));
    await tester.pumpAndSettle();
    final yours = tester
        .widgetList<Text>(
          find.descendant(
            of: find.byKey(GoalEvidenceKeys.yours),
            matching: find.byType(Text),
          ),
        )
        .map((text) => text.data ?? '')
        .join('\n');
    expect(yours, contains('3.8 kg'));
    expect(yours, contains('March to May 2027'));
  });

  testWidgets('imperial shows pounds on the tiles and the rate', (
    tester,
  ) async {
    final goal = _goal();
    await _pump(
      tester,
      week: _running(goal),
      path: _view(goal),
      units: UnitSystem.imperial,
    );
    final text = _text(tester);
    expect(text, contains('lb'));
    expect(text, isNot(contains(' kg')));
  });

  for (final locale in layoutLocales) {
    for (final scale in layoutScales) {
      testWidgets('lays out at $scale in $locale', (tester) async {
        final goal = _goal();
        await _pump(
          tester,
          week: _running(goal),
          path: _view(goal),
          scale: scale,
          locale: locale,
        );
        expect(find.byKey(GoalScreenKeys.path), findsOneWidget);
      });
    }
  }
}

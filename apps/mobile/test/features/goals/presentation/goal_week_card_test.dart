import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/l10n/app_locales.dart';
import 'package:open_ring/app/theme/app_theme.dart';
import 'package:open_ring/features/goals/application/goal_path_providers.dart';
import 'package:open_ring/features/goals/application/goal_providers.dart';
import 'package:open_ring/features/goals/application/goal_week_view.dart';
import 'package:open_ring/features/goals/domain/goal.dart';
import 'package:open_ring/features/goals/domain/goal_path.dart';
import 'package:open_ring/features/goals/presentation/goal_evidence_sheet.dart';
import 'package:open_ring/features/goals/presentation/goal_week_card.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

import '../../../helpers/layout_harness.dart';

const _goalStub = 'goal stub';
const _start = LocalDate(2026, 11, 16);
const _monday = LocalDate(2026, 12, 7);

const _steps = Lever(kind: LeverKind.steps, target: 9000);
const _sleep = Lever(kind: LeverKind.sleepWindow, target: 690);
const _strength = Lever(kind: LeverKind.strengthDays, target: 2);
const _points = Lever(kind: LeverKind.effortPoints, target: 165);

const List<LeverDayMark> _marks = [
  LeverDayMark.met,
  LeverDayMark.missed,
  LeverDayMark.met,
  LeverDayMark.open,
  LeverDayMark.ahead,
  LeverDayMark.ahead,
  LeverDayMark.ahead,
];

Goal _goal({
  GoalKind kind = GoalKind.loseFat,
  List<Lever> levers = const [_strength, _sleep, _steps, _points],
}) {
  final weighed = kind == GoalKind.loseFat;
  return Goal(
    id: 1,
    kind: kind,
    pace: weighed ? GoalPace.standard : null,
    startedOn: _start,
    anchorKg: weighed ? 78.4 : null,
    referenceKg: weighed ? 74.0 : null,
    blockStartedOn: _start,
    blockAnchorKg: weighed ? 78.4 : null,
    phase: GoalPhase.block,
    phaseSince: _start,
    phaseUntil: null,
    levers: levers,
    endedOn: null,
    endReason: null,
  );
}

GoalWeekView _running(Goal goal) => GoalWeekRunning(
  goal: goal,
  monday: _monday,
  week: 4,
  levers: const [
    LeverProgress(lever: _strength, achieved: 1, days: null),
    LeverProgress(lever: _sleep, achieved: 2, days: _marks),
    LeverProgress(lever: _steps, achieved: 2, days: _marks),
    LeverProgress(lever: _points, achieved: 140, days: null),
  ],
  review: null,
);

GoalPathView _path(Goal goal) => (
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
    on: const LocalDate(2026, 12, 6),
  ),
  daily: const [],
  line: const [],
);

Future<void> _pump(
  WidgetTester tester, {
  required GoalWeekView week,
  GoalPathView? path,
  double scale = 1,
  Locale locale = const Locale('en'),
  bool onToday = true,
}) async {
  final router = GoRouter(
    initialLocation: '/today',
    routes: [
      GoRoute(
        path: '/today',
        builder: (_, _) => Scaffold(
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (onToday)
                const GoalWeekCardSlot()
              else
                const GoalWeekCard(onToday: false),
            ],
          ),
        ),
        routes: [
          GoRoute(
            path: 'goals',
            builder: (_, _) => const Scaffold(body: Text(_goalStub)),
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
    brightness: Brightness.light,
    locale: locale,
    overrides: [
      goalWeekProvider.overrideWith((ref) async => week),
      goalPathProvider.overrideWith((ref) async => path),
    ],
  );
}

String _text(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((text) => text.data ?? text.textSpan?.toPlainText() ?? '')
    .join('\n');

String _count(WidgetTester tester, LeverKind kind) =>
    tester.widget<Text>(find.byKey(GoalWeekCardKeys.count(kind))).data!;

void main() {
  testWidgets('running shows each lever with its target and count', (
    tester,
  ) async {
    final goal = _goal();
    await _pump(tester, week: _running(goal), path: _path(goal));
    final text = _text(tester);
    expect(text, contains('week 4 of 12'));
    expect(text, contains('Plan of the goal Lose fat · Dec 7 to Dec 13'));
    expect(text, contains('2 in the week'));
    expect(text, contains('in bed by 23:30'));
    expect(text, contains('9,000 a day, on 5 of 7 days'));
    expect(text, contains('165 in the week'));
    expect(_count(tester, LeverKind.strengthDays), '1 of 2');
    expect(_count(tester, LeverKind.sleepWindow), '2 of 5');
    expect(_count(tester, LeverKind.steps), '2 of 5');
    expect(_count(tester, LeverKind.effortPoints), '140 of 165');
    expect(text, contains('day that did not fit'));
  });

  testWidgets('on the goal screen a lever opens its sheet', (tester) async {
    final goal = _goal();
    await _pump(tester, week: _running(goal), onToday: false);
    await tester.tap(find.byKey(GoalWeekCardKeys.lever(LeverKind.steps)));
    await tester.pumpAndSettle();
    expect(find.byKey(GoalEvidenceKeys.sheet), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(GoalEvidenceKeys.title)).data,
      'Steps',
    );
    expect(
      _text(tester),
      contains(
        'Target: 9,000 a day, on 5 of 7 days. This week so far: 2 of 5.',
      ),
    );
  });

  testWidgets('a paused lever opens its sheet with nothing counted', (
    tester,
  ) async {
    final goal = _goal();
    await _pump(
      tester,
      week: GoalWeekPaused(
        goal: goal,
        until: _monday.addDays(14),
        rule: ReviewRule.pauseCheckIn,
        over: false,
      ),
      onToday: false,
    );
    await tester.tap(find.byKey(GoalWeekCardKeys.lever(LeverKind.steps)));
    await tester.pumpAndSettle();
    expect(_text(tester), contains('The plan holds this week'));
  });

  testWidgets('on Today a lever opens the goal screen, not a sheet', (
    tester,
  ) async {
    final goal = _goal();
    await _pump(tester, week: _running(goal), path: _path(goal));
    await tester.tap(find.byKey(GoalWeekCardKeys.lever(LeverKind.steps)));
    await tester.pumpAndSettle();
    expect(find.byKey(GoalEvidenceKeys.sheet), findsNothing);
    expect(find.text(_goalStub), findsOneWidget);
  });

  testWidgets('another kind shows the week with no block length', (
    tester,
  ) async {
    final goal = _goal(kind: GoalKind.getFitter);
    await _pump(tester, week: _running(goal));
    expect(_text(tester), contains('week 4'));
    expect(_text(tester), isNot(contains('week 4 of')));
  });

  testWidgets('See the goal opens the goal screen', (tester) async {
    await _pump(tester, week: _running(_goal()));
    await tester.ensureVisible(find.byKey(GoalWeekCardKeys.open));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(GoalWeekCardKeys.open));
    await tester.pumpAndSettle();
    expect(find.text(_goalStub), findsOneWidget);
  });

  testWidgets('a running goal with no lever shows no legend', (tester) async {
    final goal = _goal(levers: const []);
    await _pump(
      tester,
      week: GoalWeekRunning(
        goal: goal,
        monday: _monday,
        week: 1,
        levers: const [],
        review: null,
      ),
    );
    expect(find.byKey(GoalWeekCardKeys.card), findsOneWidget);
    expect(_text(tester), isNot(contains('day that fit')));
  });

  testWidgets('base phase counts the weigh-ins', (tester) async {
    await _pump(
      tester,
      week: GoalWeekBase(
        goal: _goal(levers: const []),
        rate: const WeightRateBuilding(daysMissing: 5, spanMissing: 6),
      ),
    );
    expect(find.byKey(GoalWeekCardKeys.base), findsOneWidget);
    expect(_text(tester), contains('3 of 8 weigh-ins in 14 days'));
    expect(find.byKey(GoalWeekCardKeys.open), findsOneWidget);
  });

  testWidgets('base phase says the spread is short with enough weigh-ins', (
    tester,
  ) async {
    await _pump(
      tester,
      week: GoalWeekBase(
        goal: _goal(levers: const []),
        rate: const WeightRateBuilding(daysMissing: 0, spanMissing: 4),
      ),
    );
    expect(_text(tester), contains('8 of 8 weigh-ins in 14 days'));
    expect(_text(tester), contains('They cover 10 of the 14 days so far.'));
    final bar = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(bar.value, closeTo(10 / 14, 1e-9));
  });

  testWidgets('base phase of another kind waits for days of data', (
    tester,
  ) async {
    await _pump(
      tester,
      week: GoalWeekBase(
        goal: _goal(kind: GoalKind.sleepBetter, levers: const []),
        rate: null,
      ),
    );
    expect(_text(tester), contains('The plan starts after 7 days of data.'));
  });

  testWidgets('paused shows the levers with no count', (tester) async {
    final goal = _goal();
    await _pump(
      tester,
      week: GoalWeekPaused(
        goal: goal,
        until: const LocalDate(2027, 1, 3),
        rule: null,
        over: false,
      ),
    );
    expect(_text(tester), contains('Holding until Jan 3'));
    expect(find.byKey(GoalWeekCardKeys.lever(LeverKind.steps)), findsOneWidget);
    expect(find.byKey(GoalWeekCardKeys.count(LeverKind.steps)), findsNothing);
  });

  testWidgets('a pause that ran out says so', (tester) async {
    await _pump(
      tester,
      week: GoalWeekPaused(
        goal: _goal(),
        until: const LocalDate(2026, 12, 1),
        rule: null,
        over: true,
      ),
    );
    expect(_text(tester), contains('The pause is over'));
  });

  testWidgets('recovery asks nothing', (tester) async {
    await _pump(
      tester,
      week: GoalWeekRecovery(goal: _goal(), monday: _monday, week: 5),
    );
    expect(find.byKey(GoalWeekCardKeys.recovery), findsOneWidget);
    expect(find.byKey(GoalWeekCardKeys.count(LeverKind.steps)), findsNothing);
  });

  testWidgets('hold says Body is off', (tester) async {
    await _pump(tester, week: GoalWeekHold(goal: _goal()));
    expect(find.byKey(GoalWeekCardKeys.hold), findsOneWidget);
  });

  testWidgets('off and no goal render nothing', (tester) async {
    await _pump(tester, week: const GoalWeekOff());
    expect(find.byKey(GoalWeekCardKeys.card), findsNothing);
    await _pump(tester, week: const GoalWeekNoGoal());
    expect(find.byKey(GoalWeekCardKeys.card), findsNothing);
  });

  for (final locale in const [Locale('en'), Locale('de')]) {
    for (final scale in const [1.0, 1.3, 2.0]) {
      testWidgets('lays out in $locale at ${scale}x', (tester) async {
        final goal = _goal();
        await _pump(
          tester,
          week: _running(goal),
          path: _path(goal),
          scale: scale,
          locale: locale,
        );
        expect(tester.takeException(), isNull);
        expect(find.byKey(GoalWeekCardKeys.card), findsOneWidget);
      });
    }
  }
}

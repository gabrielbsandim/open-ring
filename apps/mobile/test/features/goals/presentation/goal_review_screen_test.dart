import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/l10n/app_locales.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/theme/app_theme.dart';
import 'package:open_ring/features/activity/application/activity_providers.dart';
import 'package:open_ring/features/activity/application/step_goal_history_providers.dart';
import 'package:open_ring/features/activity/domain/step_goal_history.dart';
import 'package:open_ring/features/body/application/hide_numbers_controller.dart';
import 'package:open_ring/features/body/domain/hide_numbers_store.dart';
import 'package:open_ring/features/demo/application/demo_mode_controller.dart';
import 'package:open_ring/features/demo/domain/demo_mode_store.dart';
import 'package:open_ring/features/goals/application/goal_path_providers.dart';
import 'package:open_ring/features/goals/application/goal_providers.dart';
import 'package:open_ring/features/goals/application/goal_reviewer.dart';
import 'package:open_ring/features/goals/application/goal_week_view.dart';
import 'package:open_ring/features/goals/domain/goal.dart';
import 'package:open_ring/features/goals/presentation/goal_evidence_sheet.dart';
import 'package:open_ring/features/goals/presentation/goal_review_screen.dart';
import 'package:open_ring/features/goals/presentation/goal_week_card.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

import '../../../helpers/layout_harness.dart';
import '../goal_fixtures.dart';

const _monday = LocalDate(2026, 12, 7);
const _reviewStub = 'review stub';

const _steps = Lever(kind: LeverKind.steps, target: 9000);
const _strength = Lever(kind: LeverKind.strengthDays, target: 2);

const _rate = LossRate(
  kg: 0.3,
  kgLow: 0.2,
  kgHigh: 0.4,
  percent: 0.38,
  percentLow: 0.26,
  percentHigh: 0.5,
);

ReviewInputs _inputs({LossRate? rate = _rate}) => ReviewInputs(
  kind: GoalKind.loseFat,
  week: 4,
  levers: const [
    LeverWeek(lever: _steps, achieved: 6),
    LeverWeek(lever: _strength, achieved: 1),
  ],
  adherencePrevious: f1.adherencePrevious,
  baseline: f1.baseline,
  effortRaisesInRow: f1.effortRaisesInRow,
  rate: rate,
  targetPercent: 0.5,
  capPercent: f1.capPercent,
  previousPercentLow: f1.previousPercentLow,
  bmi: f1.bmi,
  pregnantOrBreastfeeding: false,
  screeningPositive: false,
  bodyOn: true,
  readiness: f1.readiness,
  recoveryPrevious: false,
  energy: null,
  energyPrevious: null,
  foodOrWeight: null,
  foodOrWeightPrevious: null,
);

GoalWeek _week({
  ReviewRule rule = ReviewRule.build,
  ReviewAction action = ReviewAction.nextStep,
  LeverChange? change = const LeverChange(
    kind: LeverKind.steps,
    from: 9000,
    to: 10000,
  ),
  WeekAnswer? answer,
  LossRate? rate = _rate,
}) => GoalWeek(
  goalId: 1,
  monday: _monday,
  inputs: _inputs(rate: rate),
  rule: rule,
  action: action,
  change: change,
  answer: answer,
);

Goal _goal() => const Goal(
  id: 1,
  kind: GoalKind.loseFat,
  pace: GoalPace.standard,
  startedOn: LocalDate(2026, 11, 2),
  anchorKg: 78.4,
  referenceKg: null,
  blockStartedOn: LocalDate(2026, 11, 2),
  blockAnchorKg: 78.4,
  phase: GoalPhase.block,
  phaseSince: LocalDate(2026, 11, 2),
  phaseUntil: null,
  levers: [_steps, _strength],
  endedOn: null,
  endReason: null,
);

GoalWeekView _running(GoalWeek week) => GoalWeekRunning(
  goal: _goal(),
  monday: _monday,
  week: 5,
  levers: const [],
  review: week.pending ? week : null,
);

GoalWeek? _held;

final class _Reviewer extends GoalReviewer {
  new(this.outcome);

  final ReviewAnswerOutcome outcome;
  final answers = <WeekAnswer>[];
  final retries = <int>[];

  @override
  Future<ReviewAnswerOutcome> answer(
    LocalDate monday,
    WeekAnswer choice, {
    CheckInEnergy? energy,
    bool? foodOrWeight,
  }) async {
    answers.add(choice);
    final held = _held;
    if (outcome != ReviewAnswerOutcome.refused && held != null) {
      _held = held.answered(choice);
      ref
        ..invalidate(goalReviewProvider)
        ..invalidate(goalWeekProvider);
    }
    return outcome;
  }

  @override
  Future<bool> retryStepGoal(int steps) async {
    retries.add(steps);
    return true;
  }
}

Future<void> _pump(
  WidgetTester tester, {
  required GoalWeek week,
  GoalWeekView? state,
  _Reviewer? reviewer,
  bool demo = false,
  bool hidden = false,
  int stepGoal = 8000,
  double scale = 1,
  Locale locale = const Locale('en'),
  Size size = const Size(400, 2400),
  Brightness brightness = Brightness.light,
  List<StepGoalChange> changes = const [],
}) async {
  _held = week;
  await pumpScaled(
    tester,
    screenHost(const GoalReviewScreen()),
    textScaler: TextScaler.linear(scale),
    brightness: brightness,
    locale: locale,
    size: size,
    overrides: [
      goalWeekProvider.overrideWith(
        (ref) async => state ?? _running(_held ?? week),
      ),
      goalReviewProvider.overrideWith((ref) async {
        final held = _held ?? week;
        return GoalReviewView(week: held, review: reviewWeek(held.inputs));
      }),
      stepGoalProvider.overrideWithValue(stepGoal),
      stepGoalChangesProvider.overrideWith((ref) async => changes),
      demoModeStoreProvider.overrideWithValue(
        InMemoryDemoModeStore(enabled: demo),
      ),
      hideNumbersStoreProvider.overrideWithValue(
        InMemoryHideNumbersStore(hidden: hidden),
      ),
      goalReviewerProvider.overrideWith(
        () => reviewer ?? _Reviewer(ReviewAnswerOutcome.accepted),
      ),
    ],
  );
}

String _text(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((text) => text.data ?? text.textSpan?.toPlainText() ?? '')
    .join('\n');

Future<void> _tap(WidgetTester tester, Key key) async {
  await tester.ensureVisible(find.byKey(key));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(key));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a steps proposal shows the week, the change and its effect', (
    tester,
  ) async {
    await _pump(tester, week: _week());
    final text = _text(tester);
    expect(text, contains('Week 3 of the plan, Nov 30 to Dec 6'));
    expect(text, contains('6 of 5'));
    expect(text, contains('1 of 2'));
    expect(text, contains('0.38% a week'));
    expect(text, contains('from 9,000 to 10,000'));
    expect(
      text,
      contains(
        'The step goal of your profile becomes 10,000 a day from today.',
      ),
    );
    expect(find.byKey(GoalReviewScreenKeys.accept), findsOneWidget);
    expect(find.byKey(GoalReviewScreenKeys.keep), findsOneWidget);
  });

  testWidgets('a steps proposal under the profile goal keeps the profile', (
    tester,
  ) async {
    await _pump(tester, week: _week(), stepGoal: 12000);
    expect(_text(tester), contains('Your profile step goal stays at 12,000'));
  });

  for (final (key, choice, word) in const [
    (GoalReviewScreenKeys.accept, WeekAnswer.accepted, 'Accepted.'),
    (GoalReviewScreenKeys.keep, WeekAnswer.declined, 'Kept as it was.'),
  ]) {
    testWidgets('${choice.name} answers through the reviewer', (tester) async {
      final reviewer = _Reviewer(ReviewAnswerOutcome.accepted);
      await _pump(tester, week: _week(), reviewer: reviewer);
      await _tap(tester, key);
      expect(reviewer.answers, [choice]);
      expect(_text(tester), contains(word));
      expect(find.byKey(GoalReviewScreenKeys.accept), findsNothing);
    });
  }

  testWidgets('a failed step goal offers a retry', (tester) async {
    final reviewer = _Reviewer(ReviewAnswerOutcome.stepGoalFailed);
    await _pump(tester, week: _week(), reviewer: reviewer);
    await _tap(tester, GoalReviewScreenKeys.accept);
    expect(find.byKey(GoalReviewScreenKeys.failed), findsOneWidget);
    await _tap(tester, GoalReviewScreenKeys.retry);
    expect(reviewer.retries, [10000]);
    expect(find.byKey(GoalReviewScreenKeys.failed), findsNothing);
  });

  testWidgets('a refused answer says so', (tester) async {
    await _pump(
      tester,
      week: _week(),
      reviewer: _Reviewer(ReviewAnswerOutcome.refused),
    );
    await _tap(tester, GoalReviewScreenKeys.accept);
    expect(find.byKey(GoalReviewScreenKeys.refused), findsOneWidget);
  });

  testWidgets('an answered week shows the answer and the next review', (
    tester,
  ) async {
    await _pump(tester, week: _week(answer: WeekAnswer.accepted));
    expect(find.byKey(GoalReviewScreenKeys.answered), findsOneWidget);
    expect(_text(tester), contains('Next review: Dec 14.'));
    expect(find.byKey(GoalReviewScreenKeys.accept), findsNothing);
  });

  for (final (rule, action) in const [
    (ReviewRule.pauseFastLoss, ReviewAction.pause),
    (ReviewRule.recoveryWeek, ReviewAction.recoveryWeek),
    (ReviewRule.ease, ReviewAction.ease),
    (ReviewRule.holdOnTrack, ReviewAction.hold),
  ]) {
    testWidgets('${action.name} shows no buttons', (tester) async {
      await _pump(
        tester,
        week: _week(rule: rule, action: action, change: null),
      );
      expect(find.byKey(GoalReviewScreenKeys.accept), findsNothing);
      expect(find.byKey(GoalReviewScreenKeys.keep), findsNothing);
    });
  }

  testWidgets('Body off under a weight goal holds with no buttons', (
    tester,
  ) async {
    await _pump(
      tester,
      week: _week(),
      state: GoalWeekHold(goal: _goal()),
    );
    expect(find.byKey(GoalReviewScreenKeys.hold), findsOneWidget);
    expect(find.byKey(GoalReviewScreenKeys.accept), findsNothing);
  });

  testWidgets('demo mode hides the buttons and the questions', (tester) async {
    await _pump(tester, week: _week(), demo: true);
    expect(find.byKey(GoalReviewScreenKeys.demo), findsOneWidget);
    expect(find.byKey(GoalReviewScreenKeys.accept), findsNothing);
    expect(find.byKey(GoalReviewScreenKeys.checkIn), findsNothing);
  });

  testWidgets('hidden numbers hide the rate figures', (tester) async {
    await _pump(tester, week: _week(), hidden: true);
    expect(find.byKey(GoalReviewScreenKeys.rate), findsNothing);
    expect(_text(tester), isNot(contains('0.38')));
  });

  testWidgets('a shrink proposal names the lever that leaves', (tester) async {
    await _pump(
      tester,
      week: _week(
        rule: ReviewRule.shrink,
        action: ReviewAction.shrink,
        change: const LeverChange(
          kind: LeverKind.strengthDays,
          from: 2,
          to: null,
        ),
      ),
    );
    expect(_text(tester), contains('This lever leaves the plan for now.'));
    expect(find.byKey(GoalReviewScreenKeys.steps), findsNothing);
  });

  group('the week card', () {
    Future<void> pumpCard(WidgetTester tester) async {
      final router = GoRouter(
        initialLocation: '/today',
        routes: [
          GoRoute(
            path: '/today',
            builder: (_, _) =>
                Scaffold(body: ListView(children: const [GoalWeekCardSlot()])),
            routes: [
              GoRoute(
                path: 'goals/review',
                builder: (_, _) => const Scaffold(body: Text(_reviewStub)),
              ),
            ],
          ),
        ],
      );
      await pumpScaled(
        tester,
        MaterialApp.router(
          theme: AppTheme.light(),
          localeListResolutionCallback: AppLocales.resolve,
          supportedLocales: AppLocales.supported,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          routerConfig: router,
        ),
        textScaler: TextScaler.noScaling,
        brightness: Brightness.light,
        locale: const Locale('en'),
        overrides: [
          goalWeekProvider.overrideWith((ref) async => _running(_week())),
          goalPathProvider.overrideWith((ref) async => null),
        ],
      );
    }

    testWidgets('a waiting review opens the review screen', (tester) async {
      await pumpCard(tester);
      expect(find.byKey(GoalWeekCardKeys.review), findsOneWidget);
      expect(_text(tester), contains('1 of 2 levers fit last week'));
      await _tap(tester, GoalWeekCardKeys.openReview);
      expect(find.text(_reviewStub), findsOneWidget);
      expect(AppPaths.goalsReview, '/today/goals/review');
    });
  });

  testWidgets('a save that failed earlier offers the retry on reopen', (
    tester,
  ) async {
    final reviewer = _Reviewer(ReviewAnswerOutcome.accepted);
    await _pump(
      tester,
      week: _week(answer: WeekAnswer.accepted),
      reviewer: reviewer,
      changes: [(from: _monday, steps: 10000)],
    );
    expect(find.byKey(GoalReviewScreenKeys.failed), findsOneWidget);
    await _tap(tester, GoalReviewScreenKeys.retry);
    expect(reviewer.retries, [10000]);
  });

  testWidgets('a saved step goal offers no retry on reopen', (tester) async {
    await _pump(
      tester,
      week: _week(answer: WeekAnswer.accepted),
      stepGoal: 10000,
      changes: [(from: _monday, steps: 10000)],
    );
    expect(find.byKey(GoalReviewScreenKeys.retry), findsNothing);
  });

  for (final changes in const [
    <StepGoalChange>[],
    [(from: stepGoalBaselineDate, steps: 8000)],
  ]) {
    testWidgets('a goal lowered by hand later is no failed save, $changes', (
      tester,
    ) async {
      await _pump(
        tester,
        week: _week(answer: WeekAnswer.accepted),
        changes: changes,
      );
      expect(find.byKey(GoalReviewScreenKeys.failed), findsNothing);
      expect(find.byKey(GoalReviewScreenKeys.retry), findsNothing);
    });
  }

  testWidgets('why this rule opens the rule sheet', (tester) async {
    await _pump(tester, week: _week());
    await _tap(tester, GoalReviewScreenKeys.why);
    expect(find.byKey(GoalEvidenceKeys.sheet), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(GoalEvidenceKeys.title)).data,
      'Rule 6 of 11',
    );
    expect(_text(tester), contains('Week of the plan:'));
  });

  testWidgets('the rule sheet leaves the rate out with numbers hidden', (
    tester,
  ) async {
    await _pump(tester, week: _week(), hidden: true);
    await _tap(tester, GoalReviewScreenKeys.why);
    expect(_text(tester), isNot(contains('Rate:')));
  });

  testWidgets('a steps removal says nothing about the profile goal', (
    tester,
  ) async {
    await _pump(
      tester,
      week: _week(
        rule: ReviewRule.shrink,
        action: ReviewAction.shrink,
        change: const LeverChange(kind: LeverKind.steps, from: 9000, to: null),
      ),
    );
    expect(find.byKey(GoalReviewScreenKeys.steps), findsNothing);
    expect(_text(tester), contains('This lever leaves the plan for now.'));
  });

  for (final brightness in Brightness.values) {
    for (final locale in const [Locale('en'), Locale('de')]) {
      for (final scale in const [1.0, 1.3, 2.0]) {
        testWidgets('lays out in $locale at ${scale}x, ${brightness.name}', (
          tester,
        ) async {
          await _pump(
            tester,
            week: _week(),
            scale: scale,
            locale: locale,
            size: phoneSize,
            brightness: brightness,
          );
          await tester.scrollUntilVisible(
            find.byKey(GoalReviewScreenKeys.keep),
            200,
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}

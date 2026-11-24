import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/features/activity/application/activity_providers.dart';
import 'package:open_ring/features/activity/application/step_goal_history_providers.dart';
import 'package:open_ring/features/ai/application/ai_config_providers.dart';
import 'package:open_ring/features/ai/application/ai_gate.dart';
import 'package:open_ring/features/ai/application/analysis_run_controller.dart';
import 'package:open_ring/features/ai/domain/ai_config.dart';
import 'package:open_ring/features/ai/domain/ai_prompt.dart';
import 'package:open_ring/features/ai/domain/ai_wire_types.dart';
import 'package:open_ring/features/ai/domain/analysis_model.dart';
import 'package:open_ring/features/ai/domain/health_context_models.dart';
import 'package:open_ring/features/ai/domain/openai_wire_codec.dart';
import 'package:open_ring/features/ai/presentation/ai_consent_sheet.dart';
import 'package:open_ring/features/ai/presentation/goal_reword_card.dart';
import 'package:open_ring/features/body/application/hide_numbers_controller.dart';
import 'package:open_ring/features/body/domain/hide_numbers_store.dart';
import 'package:open_ring/features/demo/application/demo_mode_controller.dart';
import 'package:open_ring/features/demo/domain/demo_mode_store.dart';
import 'package:open_ring/features/goals/application/goal_providers.dart';
import 'package:open_ring/features/goals/application/goal_week_view.dart';
import 'package:open_ring/features/goals/domain/goal.dart';
import 'package:open_ring/features/goals/presentation/goal_review_screen.dart';

import '../../../helpers/ai_fakes.dart';
import '../../../helpers/layout_harness.dart';
import '../goal_fixtures.dart';

const _monday = LocalDate(2026, 12, 7);
const _steps = Lever(kind: LeverKind.steps, target: 9000);
const _stepsUp = LeverChange(kind: LeverKind.steps, from: 9000, to: 10000);

ReviewInputs _inputs() => ReviewInputs(
  kind: GoalKind.loseFat,
  week: 4,
  levers: const [LeverWeek(lever: _steps, achieved: 6)],
  adherencePrevious: f1.adherencePrevious,
  baseline: f1.baseline,
  effortRaisesInRow: f1.effortRaisesInRow,
  rate: null,
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

GoalWeek _week({LeverChange change = _stepsUp}) => GoalWeek(
  goalId: 1,
  monday: _monday,
  inputs: _inputs(),
  rule: ReviewRule.build,
  action: ReviewAction.nextStep,
  change: change,
  answer: null,
);

const _goal = Goal(
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
  levers: [_steps],
  endedOn: null,
  endReason: null,
);

String _answer(String insight) => jsonEncode({
  'summary': '',
  'cards': [
    {
      'family': 'overall',
      'title': '',
      'insight': insight,
      'evidence': ['plan.fit'],
      'action': '',
      'confidence': 'high',
    },
  ],
});

AiConsent _consent(Set<AiDataCategory> categories) => AiConsent(
  consentedAtUtcMs: 0,
  policyEffectiveDate: aiCurrentPolicyEffectiveDate,
  hostKey: 'https://api.example.com:443',
  detailLevel: AiDetailLevel.standard,
  contextSchemaVersion: aiContextSchemaVersion,
  categories: categories,
);

final class _Model implements AnalysisModel {
  new(this.text);

  final String text;
  int calls = 0;
  AnalysisRequest? last;

  @override
  Stream<AnalysisEvent> generate(
    AnalysisRequest request, {
    required Future<void> cancel,
  }) {
    calls++;
    last = request;
    return Stream.value(AnalysisCompleted(text: text, finishReason: 'stop'));
  }

  @override
  Future<List<String>> listModels() => throw UnimplementedError();

  @override
  Future<ConnectionProbe> probe({
    Future<void>? cancel,
    void Function()? onReached,
  }) => throw UnimplementedError();
}

GoalWeek? _held;
Review? _review;

Map<String, Object?> _sent(_Model model) {
  final text = (model.last!.userContent as AiTextContent).text;
  return jsonDecode(text.split('DATA:\n').last) as Map<String, Object?>;
}

Future<void> _show(WidgetTester tester, GoalWeek week) async {
  _held = week;
  ProviderScope.containerOf(tester.element(find.byType(GoalReviewScreen)))
    ..invalidate(goalWeekProvider)
    ..invalidate(goalReviewProvider);
  await tester.pumpAndSettle();
}

Future<_Model> _pump(
  WidgetTester tester, {
  GoalWeek? week,
  Review? review,
  String answer = 'Your steps go from 9,000 to 10,000 a day.',
  AiAvailability availability = AiAvailability.ready,
  Set<AiDataCategory> categories = const {AiDataCategory.goals},
  bool demo = false,
}) async {
  _held = week ?? _week();
  _review = review;
  final model = _Model(_answer(answer));
  final store = InMemoryAiConfigStore()
    ..config = const AiConfig(baseUrl: 'https://api.example.com/v1', model: 'm')
    ..consent = _consent(categories);
  await pumpScaled(
    tester,
    screenHost(const GoalReviewScreen()),
    textScaler: TextScaler.noScaling,
    brightness: Brightness.light,
    locale: const Locale('en'),
    size: const Size(400, 2400),
    overrides: [
      goalWeekProvider.overrideWith(
        (ref) async => GoalWeekRunning(
          goal: _goal,
          monday: _monday,
          week: 5,
          levers: const [],
          review: _held,
        ),
      ),
      goalReviewProvider.overrideWith(
        (ref) async => GoalReviewView(
          week: _held!,
          review: _review ?? reviewWeek(_held!.inputs),
        ),
      ),
      stepGoalProvider.overrideWithValue(8000),
      stepGoalChangesProvider.overrideWith((ref) async => const []),
      demoModeStoreProvider.overrideWithValue(
        InMemoryDemoModeStore(enabled: demo),
      ),
      hideNumbersStoreProvider.overrideWithValue(InMemoryHideNumbersStore()),
      aiEnabledProvider.overrideWith((ref) => true),
      aiAvailabilityProvider.overrideWith((ref) async => availability),
      aiConfigStoreProvider.overrideWithValue(store),
      aiRunMarkerStoreProvider.overrideWithValue(InMemoryAiRunMarkerStore()),
      clockProvider.overrideWithValue(() => DateTime.utc(2026, 12, 7, 8)),
      analysisModelFactoryProvider.overrideWithValue((_) async => model),
    ],
  );
  await tester.pumpAndSettle();
  return model;
}

Future<void> _tap(WidgetTester tester, Key key) async {
  await tester.ensureVisible(find.byKey(key));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(key));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the rewording comes only on a tap, under the rule text', (
    tester,
  ) async {
    final model = await _pump(tester);
    expect(find.text('Reword with AI'), findsNWidgets(2));
    expect(model.calls, 0);
    await _tap(tester, GoalRewordKeys.send);
    expect(model.calls, 1);
    expect(find.text('Reworded by m'), findsOneWidget);
    expect(
      find.text('Your steps go from 9,000 to 10,000 a day.'),
      findsOneWidget,
    );
    final rule = tester.getTopLeft(find.byKey(GoalReviewScreenKeys.decision));
    final reword = tester.getTopLeft(find.byKey(GoalRewordKeys.shown));
    expect(rule.dy, lessThan(reword.dy));
    expect(find.text('from 9,000 to 10,000'), findsOneWidget);
    expect(find.byKey(GoalRewordKeys.record), findsNothing);
    await _tap(tester, GoalRewordKeys.rule);
    expect(find.byKey(GoalRewordKeys.record), findsOneWidget);
  });

  testWidgets('the request holds the decision as shown and its numbers', (
    tester,
  ) async {
    final model = await _pump(tester);
    await _tap(tester, GoalRewordKeys.send);
    final sent = _sent(model);
    final plan = sent['plan']! as Map<String, Object?>;
    Finder shown(String text) => find.descendant(
      of: find.byKey(GoalReviewScreenKeys.decision),
      matching: find.text(text),
    );
    expect(shown(plan['decision']! as String), findsOneWidget);
    expect(shown(plan['line']! as String), findsOneWidget);
    final change = (plan['change']! as String).split(': ');
    expect(shown(change.first), findsOneWidget);
    expect(shown(change.last), findsOneWidget);
    expect(plan['rule'], ReviewRule.build.number);
    expect(sent['reply_language'], 'en');
    expect(
      {
        for (final f in sent['facts']! as List<Object?>)
          (f! as Map<String, Object?>)['id']: (f as Map<String, Object?>)['v'],
      },
      {'plan.fit': 1, 'plan.levers': 1, 'plan.from': 9000, 'plan.to': 10000},
    );
  });

  testWidgets('only a pause week sends its pause length', (tester) async {
    final model = await _pump(
      tester,
      answer: 'The plan rests for 14 days.',
      week: GoalWeek(
        goalId: 1,
        monday: _monday,
        inputs: _inputs(),
        rule: ReviewRule.pauseCheckIn,
        action: ReviewAction.pause,
        change: null,
        answer: null,
      ),
      review: const Review(
        rule: ReviewRule.pauseCheckIn,
        action: ReviewAction.pause,
        adherence: 1,
        pauseDays: 14,
      ),
    );
    await _tap(tester, GoalRewordKeys.send);
    final facts = [
      for (final f in _sent(model)['facts']! as List<Object?>)
        (f! as Map<String, Object?>)['id'],
    ];
    expect(facts, ['plan.fit', 'plan.levers', 'plan.pause']);
    expect(find.byKey(GoalRewordKeys.shown), findsOneWidget);
  });

  testWidgets('a rewording belongs to its decision for the screen session', (
    tester,
  ) async {
    final model = await _pump(tester);
    await _tap(tester, GoalRewordKeys.send);
    expect(find.byKey(GoalRewordKeys.shown), findsOneWidget);
    await _show(
      tester,
      _week(
        change: const LeverChange(kind: LeverKind.steps, from: 9000, to: 9500),
      ),
    );
    expect(find.byKey(GoalRewordKeys.shown), findsNothing);
    expect(find.byKey(GoalRewordKeys.send), findsOneWidget);
    await _show(tester, _week());
    expect(find.byKey(GoalRewordKeys.shown), findsOneWidget);
    expect(model.calls, 1);
  });

  testWidgets('a number outside the rule leaves the rule text alone', (
    tester,
  ) async {
    await _pump(tester, answer: 'Your steps go up to 11,000 a day.');
    await _tap(tester, GoalRewordKeys.send);
    expect(find.byKey(GoalRewordKeys.dropped), findsOneWidget);
    expect(find.text('Rewording dropped'), findsOneWidget);
    expect(
      find.textContaining('used a number that is not in the rule'),
      findsOneWidget,
    );
    expect(find.textContaining('11,000'), findsNothing);
    expect(find.byKey(GoalRewordKeys.shown), findsNothing);
    expect(find.text('from 9,000 to 10,000'), findsOneWidget);
  });

  testWidgets('a consent without goals opens the sheet and sends nothing', (
    tester,
  ) async {
    final model = await _pump(tester, categories: const {});
    await _tap(tester, GoalRewordKeys.send);
    expect(find.byKey(AiConsentKeys.sheet), findsOneWidget);
    expect(find.byKey(AiConsentKeys.added), findsOneWidget);
    expect(model.calls, 0);
  });

  for (final availability in [
    AiAvailability.off,
    AiAvailability.notConfigured,
    AiAvailability.notTested,
    AiAvailability.consentNeeded,
  ]) {
    testWidgets('AI ${availability.name} shows no button', (tester) async {
      await _pump(tester, availability: availability);
      expect(find.byKey(GoalRewordKeys.send), findsNothing);
      expect(find.byKey(GoalReviewScreenKeys.decision), findsOneWidget);
    });
  }

  testWidgets('demo mode shows no button', (tester) async {
    final model = await _pump(tester, demo: true);
    expect(find.byKey(GoalRewordKeys.send), findsNothing);
    expect(model.calls, 0);
  });

  testWidgets('a bedtime change shows no button', (tester) async {
    await _pump(
      tester,
      week: _week(
        change: const LeverChange(
          kind: LeverKind.sleepWindow,
          from: 660,
          to: 630,
        ),
      ),
    );
    expect(find.byKey(GoalRewordKeys.send), findsNothing);
  });
}

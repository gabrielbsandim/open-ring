import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/features/ai/application/ai_config_providers.dart';
import 'package:open_ring/features/ai/application/ai_gate.dart';
import 'package:open_ring/features/ai/application/analysis_run_controller.dart';
import 'package:open_ring/features/ai/application/goal_reword_controller.dart';
import 'package:open_ring/features/ai/domain/ai_config.dart';
import 'package:open_ring/features/ai/domain/ai_prompt.dart';
import 'package:open_ring/features/ai/domain/ai_report_models.dart';
import 'package:open_ring/features/ai/domain/ai_wire_types.dart';
import 'package:open_ring/features/ai/domain/analysis_model.dart';
import 'package:open_ring/features/ai/domain/analysis_run_state.dart';
import 'package:open_ring/features/ai/domain/goal_reword.dart';
import 'package:open_ring/features/ai/domain/health_context_models.dart';
import 'package:open_ring/features/ai/domain/openai_wire_codec.dart';
import 'package:open_ring/features/demo/application/demo_mode_controller.dart';
import 'package:open_ring/features/demo/domain/demo_mode_store.dart';

import '../../../helpers/ai_fakes.dart';

final _now = DateTime.utc(2026, 12, 7, 8, 20);

final BuiltAiPayload _payload = buildGoalRewordPayload(
  replyLanguage: 'en',
  rule: 8,
  head: 'A proposed change',
  line: 'The week fit. This is the next step in the order of the plan.',
  change: const LeverChange(kind: LeverKind.steps, from: 9000, to: 10000),
  changeText: 'Steps per day: from 9,000 to 10,000',
  fit: 3,
  levers: 3,
)!;

String _answer(String insight) => jsonEncode({
  'summary': '',
  'cards': [
    {
      'family': 'overall',
      'title': '',
      'insight': insight,
      'evidence': ['plan.to'],
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

final class _FakeModel implements AnalysisModel {
  new(this.script);

  Stream<AnalysisEvent> Function() script;
  AnalysisRequest? lastRequest;
  bool cancelSeen = false;

  @override
  Stream<AnalysisEvent> generate(
    AnalysisRequest request, {
    required Future<void> cancel,
  }) {
    lastRequest = request;
    unawaited(cancel.then((_) => cancelSeen = true));
    return script();
  }

  @override
  Future<List<String>> listModels() => throw UnimplementedError();

  @override
  Future<ConnectionProbe> probe({
    Future<void>? cancel,
    void Function()? onReached,
  }) => throw UnimplementedError();
}

Stream<AnalysisEvent> Function() _says(String text) =>
    () => Stream.fromIterable([
      AnalysisCompleted(
        text: text,
        finishReason: 'stop',
        usage: const AiTokenUsage(promptTokens: 80, completionTokens: 20),
      ),
    ]);

void main() {
  late InMemoryAiConfigStore configStore;
  late InMemoryAiRunMarkerStore markers;
  late _FakeModel model;
  late int factoryCalls;
  late bool enabled;
  late bool demo;

  setUp(() {
    configStore = InMemoryAiConfigStore()
      ..config = const AiConfig(
        baseUrl: 'https://api.example.com/v1',
        model: 'm',
      )
      ..consent = _consent({AiDataCategory.goals});
    markers = InMemoryAiRunMarkerStore();
    model = _FakeModel(_says(_answer('Steps go from 9,000 to 10,000 a day.')));
    factoryCalls = 0;
    enabled = true;
    demo = false;
  });

  ProviderContainer container() {
    final c = ProviderContainer(
      overrides: [
        aiEnabledProvider.overrideWith((ref) => enabled),
        aiConfigStoreProvider.overrideWithValue(configStore),
        aiRunMarkerStoreProvider.overrideWithValue(markers),
        demoModeStoreProvider.overrideWithValue(
          InMemoryDemoModeStore(enabled: demo),
        ),
        clockProvider.overrideWithValue(() => _now),
        analysisModelFactoryProvider.overrideWithValue((config) async {
          factoryCalls++;
          return model;
        }),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  Future<GoalRewordState> send(ProviderContainer c) {
    c.listen(goalRewordControllerProvider, (_, _) {});
    return c
        .read(goalRewordControllerProvider.notifier)
        .send(_payload)
        .then((_) => c.read(goalRewordControllerProvider));
  }

  test('a rewording with the rule numbers is shown with its model', () async {
    final state = await send(container());
    expect(state, isA<GoalRewordShown>());
    state as GoalRewordShown;
    expect(state.text, 'Steps go from 9,000 to 10,000 a day.');
    expect(state.model, 'm');
    expect(state.key, _payload.cacheKey);
    final request = model.lastRequest!;
    expect(request.systemPrompt, aiGoalRewordPromptV1);
    expect((request.userContent as AiTextContent).text, _payload.userMessage);
    expect(await markers.monthTokens('2026-12'), 100);
  });

  test('a number outside the rule drops the rewording', () async {
    model.script = _says(_answer('Steps go up to 11,000 a day.'));
    final state = await send(container());
    expect(state, isA<GoalRewordDropped>());
    expect(
      (state as GoalRewordDropped).reason,
      AiCardDropReason.unverifiedNumber,
    );
  });

  test('an answer with no card is an unreadable failure', () async {
    model.script = _says('I cannot help with that.');
    final state = await send(container());
    final failure = (state as GoalRewordFailed).failure as RunModelFailure;
    expect(failure.failure.kind, AnalysisFailureKind.unreadable);
  });

  test('a consent without the goals category sends nothing', () async {
    configStore.consent = _consent(const {});
    final state = await send(container());
    expect((state as GoalRewordFailed).failure, isA<RunConsentNeeded>());
    expect(factoryCalls, 0);
  });

  test('no consent at all sends nothing', () async {
    configStore.consent = null;
    final state = await send(container());
    expect((state as GoalRewordFailed).failure, isA<RunConsentNeeded>());
    expect(factoryCalls, 0);
  });

  test('demo mode never builds a model', () async {
    demo = true;
    final state = await send(container());
    expect(state, isA<GoalRewordIdle>());
    expect(factoryCalls, 0);
  });

  test('AI off never builds a model', () async {
    enabled = false;
    final state = await send(container());
    expect(state, isA<GoalRewordIdle>());
    expect(factoryCalls, 0);
  });

  test('the monthly ceiling stops the send before a model', () async {
    configStore.config = configStore.config.copyWith(monthlyTokenCap: 50);
    await markers.addMonthTokens('2026-12', 50);
    final state = await send(container());
    expect((state as GoalRewordFailed).failure, isA<RunCeilingReached>());
    expect(factoryCalls, 0);
  });

  test('a model failure is kept for the error line', () async {
    model.script = () =>
        Stream.error(const AnalysisFailure(kind: AnalysisFailureKind.noCredit));
    final state = await send(container());
    final failure = (state as GoalRewordFailed).failure as RunModelFailure;
    expect(failure.failure.kind, AnalysisFailureKind.noCredit);
  });

  test('cancel aborts the request and reads as cancelled', () async {
    model.script = () => StreamController<AnalysisEvent>().stream;
    final c = container()..listen(goalRewordControllerProvider, (_, _) {});
    final notifier = c.read(goalRewordControllerProvider.notifier);
    final run = notifier.send(_payload);
    await pumpEventQueue();
    expect(c.read(goalRewordControllerProvider), isA<GoalRewordSending>());
    notifier.cancel();
    await run;
    final state = c.read(goalRewordControllerProvider) as GoalRewordFailed;
    final failure = state.failure as RunModelFailure;
    expect(failure.failure.kind, AnalysisFailureKind.cancelled);
    expect(model.cancelSeen, isTrue);
  });

  test('leaving the screen disposes the run and aborts the send', () async {
    model.script = () => StreamController<AnalysisEvent>().stream;
    final c = container();
    final sub = c.listen(goalRewordControllerProvider, (_, _) {});
    final run = c.read(goalRewordControllerProvider.notifier).send(_payload);
    await pumpEventQueue();
    expect(c.read(goalRewordControllerProvider), isA<GoalRewordSending>());
    sub.close();
    await pumpEventQueue();
    await run;
    expect(model.cancelSeen, isTrue);
  });
}

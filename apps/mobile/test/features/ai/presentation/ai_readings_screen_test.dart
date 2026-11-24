import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/app/theme/app_theme.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/features/ai/application/ai_config_providers.dart';
import 'package:open_ring/features/ai/application/ai_gate.dart';
import 'package:open_ring/features/ai/application/ai_report_providers.dart';
import 'package:open_ring/features/ai/application/analysis_run_controller.dart';
import 'package:open_ring/features/ai/application/health_context_providers.dart';
import 'package:open_ring/features/ai/domain/ai_config.dart';
import 'package:open_ring/features/ai/domain/ai_prompt.dart';
import 'package:open_ring/features/ai/domain/ai_report.dart';
import 'package:open_ring/features/ai/domain/ai_wire_types.dart';
import 'package:open_ring/features/ai/domain/analysis_model.dart';
import 'package:open_ring/features/ai/domain/health_context_assembly.dart';
import 'package:open_ring/features/ai/domain/health_context_models.dart';
import 'package:open_ring/features/ai/domain/openai_wire_codec.dart';
import 'package:open_ring/features/ai/presentation/ai_consent_sheet.dart';
import 'package:open_ring/features/ai/presentation/ai_reading_card.dart';
import 'package:open_ring/features/ai/presentation/ai_readings_screen.dart';
import 'package:open_ring/features/demo/application/demo_mode_controller.dart';
import 'package:open_ring/features/demo/domain/demo_mode_store.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

import '../../../helpers/ai_fakes.dart';

const _url = 'https://api.example.com/v1';
const _hostKey = 'https://api.example.com:443';
final _now = DateTime.utc(2026, 11, 24, 9);

BuiltAiPayload _payload(AiAnalysisKind kind, {double sleep = 300}) {
  final context = <String, Object?>{
    'schema': aiContextSchemaVersion,
    'facts': [
      {'id': 'f.sleepMin.avg', 'v': sleep, 'u': 'min'},
    ],
  };
  final json = canonicalJsonEncode(context);
  return BuiltAiPayload(
    contextMap: context,
    canonicalContextJson: json,
    systemPrompt: aiSystemPromptV1,
    userMessage: buildAnalysisUserMessage(
      kind: kind,
      canonicalContextJson: json,
    ),
    facts: [
      HealthFact(
        id: 'f.sleepMin.avg',
        label: 'Sleep duration, window mean',
        value: sleep,
        unit: AiFactUnit.min,
        family: AiMetricFamily.sleep,
        days: 7,
      ),
    ],
    estimatedTokens: 900,
    contextTokens: 400,
    cacheKey: 'sha-${kind.wireName}-$sleep',
    droppedCount: 0,
  );
}

Map<String, Object?> _card(String title) => {
  'family': 'sleep',
  'title': title,
  'insight': 'Sleep stayed close to your usual amount.',
  'evidence': ['f.sleepMin.avg'],
  'action': 'Keep a regular bedtime.',
  'confidence': 'high',
};

final String _answer = jsonEncode({
  'summary': 'A calm week.',
  'cards': [
    _card('Steady sleep'),
    {
      ..._card('Invented'),
      'evidence': ['f.unknown.avg'],
    },
  ],
});

AiReport _stored({
  String? cardsJson,
  String model = 'gpt-test',
  int dropped = 1,
}) => AiReport(
  createdAtUtc: _now.subtract(const Duration(days: 1)),
  offsetMin: 0,
  kind: AiAnalysisKind.weeklyReview.wireName,
  contextSchema: aiContextSchemaVersion,
  contextSha256: 'old',
  detailLevel: 'standard',
  promptVersion: 'v$aiPromptVersion',
  providerHost: _hostKey,
  model: model,
  status: AiReportStatus.done,
  droppedCards: dropped,
  cardsJson:
      cardsJson ??
      jsonEncode({
        'summary': 'Stored summary.',
        'cards': [
          {
            'family': 'sleep',
            'title': 'Stored card',
            'insight': 'Sleep was long.',
            'evidenceIds': ['f.sleepMin.avg'],
            'action': 'Keep it.',
            'modelConfidence': 'high',
            'coverageConfidence': 'medium',
            'shownConfidence': 'medium',
            'minEvidenceDays': 7,
          },
        ],
        'facts': [
          {
            'id': 'f.sleepMin.avg',
            'label': 'Sleep duration, window mean',
            'value': 431,
            'unit': 'min',
            'days': 7,
            'family': 'sleep',
          },
        ],
      }),
);

final class _Model implements AnalysisModel {
  final List<AnalysisRequest> requests = [];
  final List<StreamController<AnalysisEvent>> streams = [];
  bool cancelSeen = false;

  @override
  Stream<AnalysisEvent> generate(
    AnalysisRequest request, {
    required Future<void> cancel,
  }) {
    unawaited(cancel.then((_) => cancelSeen = true));
    requests.add(request);
    final stream = StreamController<AnalysisEvent>();
    streams.add(stream);
    return stream.stream;
  }

  void answer() => streams.last
    ..add(
      AnalysisCompleted(
        text: _answer,
        finishReason: 'stop',
        usage: const AiTokenUsage(promptTokens: 10, completionTokens: 5),
      ),
    );

  @override
  Future<List<String>> listModels() => throw UnimplementedError();

  @override
  Future<ConnectionProbe> probe({
    Future<void>? cancel,
    void Function()? onReached,
  }) => throw UnimplementedError();
}

final class _GatedStore implements AiReportStore {
  final InMemoryAiReportStore _inner = InMemoryAiReportStore();
  Completer<void>? gate;

  List<AiReport> get reports => _inner.reports;

  @override
  Future<int> insert(AiReport report) async {
    await gate?.future;
    return await _inner.insert(report);
  }

  @override
  Future<AiReport?> newestDone(AiReportCacheKey key) => _inner.newestDone(key);

  @override
  Future<List<AiReport>> recent({int limit = aiReportKeepCount}) =>
      _inner.recent(limit: limit);

  @override
  Future<void> deleteAll() => _inner.deleteAll();

  @override
  Future<void> applyRetention(DateTime nowUtc) => _inner.applyRetention(nowUtc);
}

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));
  late InMemoryAiConfigStore configs;
  late _GatedStore reports;
  late _Model model;
  late int factoryCalls;
  late bool food;
  late bool notEnough;
  late Completer<void>? payloadGate;
  late ValueNotifier<bool> visible;

  setUp(() {
    configs = InMemoryAiConfigStore()
      ..config = AiConfig(
        baseUrl: _url,
        model: 'gpt-test',
        keyLastFour: 'ab3X',
        testedAtUtcMs: 1,
        testedHostKey: const AiConfig(baseUrl: _url).hostKey,
        testedModel: 'gpt-test',
      )
      ..consent = const AiConsent(
        consentedAtUtcMs: 0,
        policyEffectiveDate: aiCurrentPolicyEffectiveDate,
        hostKey: _hostKey,
        detailLevel: AiDetailLevel.standard,
        contextSchemaVersion: aiContextSchemaVersion,
      );
    reports = _GatedStore();
    model = _Model();
    factoryCalls = 0;
    food = false;
    notEnough = false;
    payloadGate = null;
    visible = ValueNotifier(true);
    addTearDown(visible.dispose);
  });

  List<Override> overrides() => [
    aiConfigStoreProvider.overrideWithValue(configs),
    secretStoreProvider.overrideWithValue(InMemorySecretStore()),
    demoModeStoreProvider.overrideWithValue(InMemoryDemoModeStore()),
    aiEnabledProvider.overrideWith((ref) => true),
    aiPayloadProvider.overrideWith((ref, kind) async {
      await payloadGate?.future;
      if (notEnough) return const AiPayloadNotEnoughData(3);
      final base = _payload(kind);
      if (!food) return AiPayloadReady(base, kind: kind);
      final map = {
        ...base.contextMap,
        'food': const {'complete_days': 3},
      };
      return AiPayloadReady(
        BuiltAiPayload(
          contextMap: map,
          canonicalContextJson: base.canonicalContextJson,
          systemPrompt: base.systemPrompt,
          userMessage: base.userMessage,
          facts: base.facts,
          estimatedTokens: base.estimatedTokens,
          contextTokens: base.contextTokens,
          cacheKey: '${base.cacheKey}-food',
          droppedCount: 0,
        ),
        kind: kind,
      );
    }),
    aiReportStoreProvider.overrideWithValue(reports),
    aiRunMarkerStoreProvider.overrideWithValue(InMemoryAiRunMarkerStore()),
    clockProvider.overrideWithValue(() => _now),
    analysisModelFactoryProvider.overrideWithValue((config) async {
      factoryCalls++;
      return model;
    }),
  ];

  Future<void> pump(WidgetTester tester, {bool pushed = false}) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(800, 3000);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides(),
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: pushed
              ? Builder(
                  builder: (context) => TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const AiReadingsScreen(),
                      ),
                    ),
                    child: const Text('open'),
                  ),
                )
              : ValueListenableBuilder<bool>(
                  valueListenable: visible,
                  builder: (_, on, _) =>
                      TickerMode(enabled: on, child: const AiReadingsScreen()),
                ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    if (!pushed) return;
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<void> tapKind(WidgetTester tester, Key key) async {
    await tester.tap(find.byKey(key));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> answer(WidgetTester tester) async {
    model.answer();
    await tester.pumpAndSettle();
  }

  String user(AnalysisRequest request) =>
      (request.userContent as AiTextContent).text;

  testWidgets('opening shows the stored reading and sends nothing', (
    tester,
  ) async {
    await reports.insert(_stored());
    await reports.insert(
      _stored(model: 'other-model', cardsJson: '{"summary": "Other model."}'),
    );
    await pump(tester);

    expect(factoryCalls, 0);
    expect(model.requests, isEmpty);
    expect(find.text('Stored summary.'), findsOneWidget);
    expect(find.text('Other model.'), findsNothing);
    expect(find.text('Stored card'), findsOneWidget);
    expect(find.byKey(AiReadingKeys.dashed), findsOneWidget);
    expect(find.text(l10n.aiReadingWrittenBy('gpt-test')), findsOneWidget);
    expect(
      find.text(l10n.aiReadingByLine('gpt-test', 'api.example.com')),
      findsOneWidget,
    );
    expect(find.text(l10n.aiReadingDropped(1, 2)), findsOneWidget);
    expect(find.text(l10n.aiReadingFooter), findsOneWidget);
  });

  testWidgets('chips show the stored snapshot, not the current payload', (
    tester,
  ) async {
    await reports.insert(_stored());
    await pump(tester);

    final chip = find.byKey(AiReadingKeys.chip('f.sleepMin.avg'));
    final label = l10n.aiFactLabel('avg', l10n.trendsMetricSleep, 7);
    expect(find.descendant(of: chip, matching: find.text(label)), findsOne);
    expect(
      find.descendant(of: chip, matching: find.text('7 h 11 min')),
      findsOne,
    );
    expect(find.text('5 h'), findsNothing);
  });

  testWidgets('a report stored before the snapshot shows the fact id', (
    tester,
  ) async {
    await reports.insert(
      _stored(
        cardsJson: jsonEncode({
          'summary': 'Old.',
          'cards': [
            {
              'family': 'sleep',
              'title': 'Old card',
              'insight': 'Old insight.',
              'evidenceIds': ['f.sleepMin.avg'],
              'action': 'Old action.',
              'modelConfidence': 'low',
              'coverageConfidence': 'low',
              'shownConfidence': 'low',
              'minEvidenceDays': 4,
            },
          ],
        }),
      ),
    );
    await pump(tester);

    expect(find.text('f.sleepMin.avg'), findsOneWidget);
    expect(find.text(l10n.aiReadingConfidence('low', 4)), findsOneWidget);
  });

  testWidgets('weekly and daily send their own payload', (tester) async {
    await pump(tester);

    await tapKind(tester, AiReadingKeys.daily);
    expect(user(model.requests.single), contains('Task: daily_review.'));
    await answer(tester);

    await tapKind(tester, AiReadingKeys.weekly);
    expect(user(model.requests.last), contains('Task: weekly_review.'));
    await answer(tester);

    expect(model.requests, hasLength(2));
    expect(reports.reports.map((r) => r.kind), {
      'daily_review',
      'weekly_review',
    });
    expect(find.text(l10n.aiReadingKind('weekly')), findsNWidgets(2));
    expect(find.text('Steady sleep'), findsOneWidget);
    expect(find.text('Invented'), findsNothing);
    expect(find.text(l10n.aiReadingDropped(1, 2)), findsOneWidget);
    expect(find.text('5 h'), findsOneWidget);
  });

  testWidgets('a payload with a new category opens the consent sheet even when '
      'the connection is ready, and Allow sends exactly once', (tester) async {
    food = true;
    await pump(tester);

    await tester.tap(find.byKey(AiReadingKeys.weekly));
    await tester.pumpAndSettle();
    expect(find.byKey(AiConsentKeys.sheet), findsOneWidget);
    expect(factoryCalls, 0);

    await tester.tap(find.byKey(AiConsentKeys.tick));
    await tester.pump();
    await tester.tap(find.byKey(AiConsentKeys.allow));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await answer(tester);

    expect(model.requests, hasLength(1));
    expect(configs.consent!.categories, {AiDataCategory.food});
    expect(find.text('Steady sleep'), findsOneWidget);
  });

  testWidgets('dismissing or not ticking the consent sends nothing', (
    tester,
  ) async {
    food = true;
    await pump(tester);

    await tester.tap(find.byKey(AiReadingKeys.daily));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(AiConsentKeys.allow));
    await tester.pumpAndSettle();
    expect(find.byKey(AiConsentKeys.sheet), findsOneWidget);
    await tester.tap(find.byKey(AiConsentKeys.cancel));
    await tester.pumpAndSettle();

    expect(find.byKey(AiConsentKeys.sheet), findsNothing);
    expect(factoryCalls, 0);
    expect(model.requests, isEmpty);
    expect(reports.reports, isEmpty);
  });

  testWidgets('the sending card shows progress and Cancel cancels', (
    tester,
  ) async {
    await pump(tester);
    await tapKind(tester, AiReadingKeys.weekly);
    model.streams.last.add(const AnalysisProgress(1200));
    await tester.pump();

    expect(
      find.text(l10n.aiReadingReceiving('api.example.com', '1,200')),
      findsOneWidget,
    );
    final bar = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(bar.value, closeTo(1200 / (aiDefaultOutputTokens * 4), 1e-9));
    expect(find.text(l10n.aiReadingSendingNote), findsOneWidget);

    await tester.tap(find.byKey(AiReadingKeys.cancel));
    await tester.pumpAndSettle();

    expect(model.cancelSeen, isTrue);
    expect(find.text(l10n.aiReadingCancelled), findsOneWidget);
    expect(reports.reports.single.status, AiReportStatus.cancelled);
  });

  testWidgets('progress is capped below full while receiving', (tester) async {
    await pump(tester);
    await tapKind(tester, AiReadingKeys.weekly);
    model.streams.last.add(const AnalysisProgress(900000));
    await tester.pump();

    final bar = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(bar.value, 0.95);
    await tester.tap(find.byKey(AiReadingKeys.cancel));
    await tester.pumpAndSettle();
  });

  testWidgets('Cancel is disabled while the numbers are checked', (
    tester,
  ) async {
    reports.gate = Completer<void>();
    await pump(tester);
    await tapKind(tester, AiReadingKeys.weekly);
    model.answer();
    await tester.pump();
    await tester.pump();

    expect(find.text(l10n.aiReadingChecking), findsOneWidget);
    final cancel = tester.widget<OutlinedButton>(
      find.byKey(AiReadingKeys.cancel),
    );
    expect(cancel.onPressed, isNull);
    expect(find.text('Steady sleep'), findsNothing);

    reports.gate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Steady sleep'), findsOneWidget);
  });

  testWidgets('leaving the screen cancels the request', (tester) async {
    await pump(tester, pushed: true);
    await tapKind(tester, AiReadingKeys.weekly);
    expect(model.requests, hasLength(1));

    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();

    expect(model.cancelSeen, isTrue);
    expect(reports.reports.single.status, AiReportStatus.cancelled);
  });

  testWidgets('a tab switch cancels the run in flight', (tester) async {
    await pump(tester);
    await tapKind(tester, AiReadingKeys.weekly);
    expect(model.requests, hasLength(1));

    visible.value = false;
    await tester.pumpAndSettle();

    expect(model.cancelSeen, isTrue);
    expect(reports.reports.single.status, AiReportStatus.cancelled);
  });

  for (final withFood in [false, true]) {
    testWidgets('a tab switch while the payload loads sends nothing '
        '(new category: $withFood)', (tester) async {
      food = withFood;
      await pump(tester);
      payloadGate = Completer<void>();
      await tester.tap(find.byKey(AiReadingKeys.weekly));
      await tester.pump();

      visible.value = false;
      await tester.pump();
      payloadGate!.complete();
      await tester.pumpAndSettle();

      expect(find.byKey(AiConsentKeys.sheet), findsNothing);
      expect(factoryCalls, 0);
      expect(model.requests, isEmpty);
      expect(reports.reports, isEmpty);
    });
  }

  testWidgets('a reading with nothing dropped has no dropped banner', (
    tester,
  ) async {
    await reports.insert(_stored(dropped: 0));
    await pump(tester);

    expect(find.text('Stored card'), findsOneWidget);
    expect(find.byKey(AiReadingKeys.dropped), findsNothing);
  });

  testWidgets('a consent that lapses mid tap opens the sheet again', (
    tester,
  ) async {
    await pump(tester);
    configs.consent = null;

    await tester.tap(find.byKey(AiReadingKeys.weekly));
    await tester.pumpAndSettle();

    expect(find.byKey(AiConsentKeys.sheet), findsOneWidget);
    expect(factoryCalls, 0);
  });

  testWidgets('not enough data shows the day count and sends nothing', (
    tester,
  ) async {
    notEnough = true;
    await pump(tester);
    await tester.tap(find.byKey(AiReadingKeys.daily));
    await tester.pumpAndSettle();

    expect(find.text(l10n.aiPreviewNotEnough(3)), findsOneWidget);
    expect(factoryCalls, 0);
    expect(find.byKey(AiConsentKeys.sheet), findsNothing);
  });

  testWidgets('no em or en dash in rendered text', (tester) async {
    await reports.insert(_stored());
    await pump(tester);
    await tapKind(tester, AiReadingKeys.weekly);
    final texts = [
      for (final t in tester.widgetList<Text>(find.byType(Text)))
        t.data ?? t.textSpan?.toPlainText() ?? '',
    ];
    for (final text in texts) {
      for (final dash in [0x2013, 0x2014]) {
        expect(text, isNot(contains(String.fromCharCode(dash))));
      }
    }
    await tester.tap(find.byKey(AiReadingKeys.cancel));
    await tester.pumpAndSettle();
  });
}

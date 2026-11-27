import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:open_ring/app/theme/app_theme.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/features/ai/application/ai_config_providers.dart';
import 'package:open_ring/features/ai/application/ai_gate.dart';
import 'package:open_ring/features/ai/application/ai_report_providers.dart';
import 'package:open_ring/features/ai/application/analysis_run_controller.dart';
import 'package:open_ring/features/ai/application/health_context_providers.dart';
import 'package:open_ring/features/ai/domain/ai_config.dart';
import 'package:open_ring/features/ai/domain/ai_prompt.dart';
import 'package:open_ring/features/ai/domain/health_context_assembly.dart';
import 'package:open_ring/features/ai/domain/health_context_models.dart';
import 'package:open_ring/features/ai/infrastructure/http_analysis_model.dart';
import 'package:open_ring/features/ai/presentation/ai_consent_sheet.dart';
import 'package:open_ring/features/ai/presentation/ai_context_preview_screen.dart';
import 'package:open_ring/features/demo/application/demo_mode_controller.dart';
import 'package:open_ring/features/demo/domain/demo_mode_store.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

import '../../../helpers/ai_fakes.dart';

const _https = 'https://api.example.com/v1';
const _httpsHost = 'https://api.example.com:443';
const _lan = 'http://192.168.1.10:11434/v1';
final _now = DateTime.utc(2026, 11, 24, 9);

BuiltAiPayload _payload({bool food = false, bool goals = false}) {
  final context = <String, Object?>{
    'schema': aiContextSchemaVersion,
    'reply_language': 'pt-BR',
    'profile': {'age_band': '30-34', 'step_goal': 9000},
    'days': {
      'd': ['D-1', 'D0'],
      'sleep_min': [431, null],
    },
    'facts': [
      {'id': 'f.sleep', 'label': 'Sleep "avg", média', 'v': 431, 'u': 'min'},
    ],
    if (food) 'food': {'complete_days': 3},
    if (goals) 'goal': {'type': 'lose_fat'},
  };
  final json = canonicalJsonEncode(context);
  return BuiltAiPayload(
    contextMap: context,
    canonicalContextJson: json,
    systemPrompt: aiSystemPromptV1,
    userMessage: buildAnalysisUserMessage(
      kind: AiAnalysisKind.dailyReview,
      canonicalContextJson: json,
    ),
    facts: const [],
    estimatedTokens: 4600,
    contextTokens: 900,
    cacheKey: food ? 'sha-food' : 'sha',
    droppedCount: 0,
  );
}

AiConfig _config(
  String url, {
  AiDetailLevel detail = AiDetailLevel.standard,
  String? keyLastFour = 'ab3X',
}) {
  final host = AiConfig(baseUrl: url).hostKey;
  return AiConfig(
    baseUrl: url,
    model: 'gpt-test',
    detailLevel: detail,
    keyLastFour: keyLastFour,
    testedAtUtcMs: 1,
    testedHostKey: host,
    testedModel: 'gpt-test',
  );
}

AiConsent _consent({
  AiDetailLevel detail = AiDetailLevel.standard,
  Set<AiDataCategory> categories = const {},
}) => AiConsent(
  consentedAtUtcMs: _now.millisecondsSinceEpoch,
  policyEffectiveDate: aiCurrentPolicyEffectiveDate,
  hostKey: _httpsHost,
  detailLevel: detail,
  contextSchemaVersion: aiContextSchemaVersion,
  categories: categories,
);

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));
  late InMemoryAiConfigStore store;
  late BuiltAiPayload payload;

  setUp(() {
    store = InMemoryAiConfigStore()..config = _config(_https);
    payload = _payload();
  });

  List<Override> overrides() => [
    aiConfigStoreProvider.overrideWithValue(store),
    secretStoreProvider.overrideWithValue(InMemorySecretStore()),
    demoModeStoreProvider.overrideWithValue(InMemoryDemoModeStore()),
    aiEnabledProvider.overrideWith((ref) => true),
    aiPayloadProvider.overrideWith((ref, _) async => AiPayloadReady(payload)),
    clockProvider.overrideWithValue(() => _now),
  ];

  Future<void> pump(WidgetTester tester) async {
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
          home: const AiContextPreviewScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  String shown(WidgetTester tester, Key key) =>
      tester.widget<SelectableText>(find.byKey(key)).data!;

  Future<void> openSheet(WidgetTester tester) async {
    await tester.tap(find.byKey(AiPreviewKeys.ask));
    await tester.pumpAndSettle();
  }

  group('preview', () {
    testWidgets('readable renders each payload section', (tester) async {
      await pump(tester);

      for (final name in ['schema', 'profile', 'days', 'facts']) {
        expect(find.byKey(AiPreviewKeys.section(name)), findsOneWidget);
      }
      expect(find.text(l10n.profileTitle), findsOneWidget);
      expect(find.byType(DataTable), findsOneWidget);
      expect(find.text('431'), findsOneWidget);
      expect(find.text(l10n.aiPreviewTokens(4600)), findsOneWidget);
      expect(find.text(l10n.aiPreviewNotSent('api.example.com')), findsOne);
      expect(find.byKey(AiPreviewKeys.notEncrypted), findsNothing);
    });

    testWidgets('exact text is byte for byte the HTTP body the model sends', (
      tester,
    ) async {
      await pump(tester);
      await tester.tap(find.byKey(AiPreviewKeys.exact));
      await tester.pumpAndSettle();
      final system = shown(tester, AiPreviewKeys.system);
      final user = shown(tester, AiPreviewKeys.user);
      expect(system, payload.systemPrompt);
      expect(user, payload.userMessage);

      store.consent = _consent();
      final bodies = <String>[];
      await tester.runAsync(() async {
        final c = ProviderContainer(
          overrides: [
            ...overrides(),
            aiReportStoreProvider.overrideWithValue(InMemoryAiReportStore()),
            aiRunMarkerStoreProvider.overrideWithValue(
              InMemoryAiRunMarkerStore(),
            ),
            analysisModelFactoryProvider.overrideWithValue(
              (config) async => HttpAnalysisModel(
                baseUrl: config.normalizedUrl!,
                model: config.trimmedModel,
                apiKey: 'sk-test',
                lookup: (_) async => ['93.184.216.34'],
                clientFactory: (_, _) => MockClient((request) async {
                  bodies.add(utf8.decode(request.bodyBytes));
                  return http.Response('{}', 500);
                }),
              ),
            ),
          ],
        );
        addTearDown(c.dispose);
        c.listen(analysisRunControllerProvider, (_, _) {});
        await c.read(analysisRunControllerProvider.notifier).send();
      });

      expect(bodies, isNotEmpty);
      final messages = jsonEncode([
        {'role': 'system', 'content': system},
        {'role': 'user', 'content': user},
      ]);
      for (final body in bodies) {
        expect(body, contains('"messages":$messages'));
        final decoded = jsonDecode(body) as Map<String, Object?>;
        expect(jsonEncode(decoded['messages']), messages);
      }
    });

    testWidgets('a local http address shows the open lock warning', (
      tester,
    ) async {
      store.config = _config(_lan);
      await pump(tester);
      expect(find.byKey(AiPreviewKeys.notEncrypted), findsOneWidget);

      await openSheet(tester);
      expect(find.byKey(AiConsentKeys.unencrypted), findsOneWidget);
      expect(find.text(l10n.aiConsentWhere('192.168.1.10')), findsOneWidget);
    });

    testWidgets('with no key stored the Where line does not name a key', (
      tester,
    ) async {
      store.config = _config(_lan, keyLastFour: null);
      await pump(tester);
      await openSheet(tester);

      expect(
        find.text(l10n.aiConsentWhereNoKey('192.168.1.10')),
        findsOneWidget,
      );
      expect(find.text(l10n.aiConsentWhere('192.168.1.10')), findsNothing);
    });
  });

  group('consent sheet', () {
    testWidgets('nothing is ticked and Allow stays off until ticked', (
      tester,
    ) async {
      await pump(tester);
      await openSheet(tester);

      expect(
        find.text(l10n.aiConsentTitle('first', 'api.example.com')),
        findsOne,
      );
      expect(find.byKey(AiConsentKeys.unencrypted), findsNothing);
      expect(find.byKey(AiConsentKeys.added), findsNothing);
      final tick = tester.widget<CheckboxListTile>(
        find.byKey(AiConsentKeys.tick),
      );
      expect(tick.value, isFalse);
      final allow = find.byKey(AiConsentKeys.allow);
      expect(tester.widget<FilledButton>(allow).onPressed, isNull);

      await tester.tap(allow);
      await tester.pumpAndSettle();
      expect(store.consent, isNull);

      await tester.tap(find.byKey(AiConsentKeys.cancel));
      await tester.pumpAndSettle();
      expect(store.consent, isNull);
      expect(find.byKey(AiPreviewKeys.ask), findsOneWidget);
    });

    testWidgets('granting stores a consent bound to the host and payload', (
      tester,
    ) async {
      payload = _payload(food: true);
      await pump(tester);
      await openSheet(tester);
      await tester.tap(find.byKey(AiConsentKeys.tick));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(AiConsentKeys.allow));
      await tester.pumpAndSettle();

      expect(store.consent, _consent(categories: {AiDataCategory.food}));
      expect(find.byKey(AiConsentKeys.sheet), findsNothing);
      expect(find.byKey(AiPreviewKeys.given), findsOneWidget);
    });

    testWidgets('withdrawing clears the consent and asks again', (
      tester,
    ) async {
      store.consent = _consent();
      await pump(tester);
      expect(find.byKey(AiPreviewKeys.ask), findsNothing);

      await tester.tap(find.byKey(AiPreviewKeys.withdraw));
      await tester.pumpAndSettle();

      expect(store.consent, isNull);
      expect(find.byKey(AiPreviewKeys.ask), findsOneWidget);
    });

    testWidgets('a stored consent that no longer covers can be withdrawn', (
      tester,
    ) async {
      store
        ..consent = _consent()
        ..config = _config(_https, detail: AiDetailLevel.full);
      await pump(tester);
      expect(find.byKey(AiPreviewKeys.ask), findsOneWidget);
      expect(find.byKey(AiPreviewKeys.given), findsNothing);

      await tester.tap(find.byKey(AiPreviewKeys.withdraw));
      await tester.pumpAndSettle();

      expect(store.consent, isNull);
      expect(find.byKey(AiPreviewKeys.withdraw), findsNothing);
      expect(find.byKey(AiPreviewKeys.ask), findsOneWidget);
    });

    testWidgets('granting again keeps the categories consented before', (
      tester,
    ) async {
      store.consent = _consent(categories: {AiDataCategory.food});
      payload = _payload(goals: true);
      await pump(tester);
      await openSheet(tester);
      await tester.tap(find.byKey(AiConsentKeys.tick));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(AiConsentKeys.allow));
      await tester.pumpAndSettle();

      expect(store.consent!.categories, {
        AiDataCategory.food,
        AiDataCategory.goals,
      });
    });

    testWidgets('a new data category asks again and lists it', (tester) async {
      store.consent = _consent();
      payload = _payload(food: true);
      await pump(tester);
      await openSheet(tester);

      expect(
        find.text(l10n.aiConsentTitle('added', 'api.example.com')),
        findsOne,
      );
      expect(
        find.descendant(
          of: find.byKey(AiConsentKeys.added),
          matching: find.text(l10n.foodTitle),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a raised detail level asks again', (tester) async {
      store
        ..consent = _consent()
        ..config = _config(_https, detail: AiDetailLevel.full);
      await pump(tester);
      expect(find.byKey(AiPreviewKeys.ask), findsOneWidget);
    });

    testWidgets('a lowered detail level keeps the consent', (tester) async {
      store
        ..consent = _consent()
        ..config = _config(_https, detail: AiDetailLevel.minimal);
      await pump(tester);
      expect(find.byKey(AiPreviewKeys.ask), findsNothing);
      expect(find.byKey(AiPreviewKeys.given), findsOneWidget);
    });
  });
}

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:open_ring/app/router/app_routes.dart';
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
import 'package:open_ring/features/ai/domain/health_context_assembly.dart';
import 'package:open_ring/features/ai/domain/health_context_models.dart';
import 'package:open_ring/features/ai/presentation/ai_context_preview_screen.dart';
import 'package:open_ring/features/ai/presentation/ai_formula_screen.dart';
import 'package:open_ring/features/ai/presentation/ai_reading_card.dart';
import 'package:open_ring/features/ai/presentation/ai_reading_sheets.dart';
import 'package:open_ring/features/ai/presentation/ai_readings_screen.dart';
import 'package:open_ring/features/demo/application/demo_mode_controller.dart';
import 'package:open_ring/features/demo/domain/demo_mode_store.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

import '../../../helpers/ai_fakes.dart';

const _url = 'https://api.example.com/v1';
const _hostKey = 'https://api.example.com:443';
final _now = DateTime.utc(2026, 11, 24, 9);

const _livePayload = BuiltAiPayload(
  contextMap: {'schema': aiContextSchemaVersion},
  canonicalContextJson: '{}',
  systemPrompt: 'live system',
  userMessage: 'live user message',
  facts: [],
  estimatedTokens: 5,
  contextTokens: 2,
  cacheKey: 'live',
  droppedCount: 0,
);

Map<String, Object?> _card({
  String title = 'Stored card',
  String model = 'high',
  String coverage = 'low',
  String shown = 'high',
  List<String> evidence = const ['f.sleepMin.avg'],
}) => {
  'family': 'sleep',
  'title': title,
  'insight': 'Sleep was long.',
  'evidenceIds': evidence,
  'action': 'Keep it.',
  'modelConfidence': model,
  'coverageConfidence': coverage,
  'shownConfidence': shown,
  'minEvidenceDays': 3,
};

AiReport _report({
  String summary = 'Stored summary.',
  int hoursAgo = 1,
  AiReportStatus status = AiReportStatus.done,
  List<Map<String, Object?>>? cards,
  List<Map<String, Object?>> dropped = const [],
  String? payloadJson = '{"system":"stored system","user":"stored user"}',
  int? input = 4612,
  int? output = 1180,
  int? thinking = 640,
  double? cost,
  String? currency,
  AiCostSource source = AiCostSource.none,
  String kind = 'weekly_review',
}) => AiReport(
  createdAtUtc: _now.subtract(Duration(hours: hoursAgo)),
  offsetMin: 0,
  kind: kind,
  contextSchema: aiContextSchemaVersion,
  contextSha256: 'sha-$hoursAgo',
  detailLevel: 'standard',
  promptVersion: 'v$aiPromptVersion',
  providerHost: _hostKey,
  model: 'gpt-test',
  status: status,
  droppedCards: dropped.length,
  payloadJson: payloadJson,
  promptTokens: input,
  completionTokens: output,
  reasoningTokens: thinking,
  cost: cost,
  costCurrency: currency,
  costSource: source,
  cardsJson: status == AiReportStatus.done
      ? jsonEncode({
          'summary': summary,
          'cards': cards ?? [_card()],
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
          'dropped': dropped,
        })
      : null,
);

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));
  late InMemoryAiConfigStore configs;
  late InMemoryAiReportStore reports;
  late int factoryCalls;

  setUp(() {
    configs = InMemoryAiConfigStore()
      ..config = AiConfig(
        baseUrl: _url,
        model: 'gpt-test',
        keyLastFour: 'ab3X',
        testedAtUtcMs: 1,
        testedHostKey: const AiConfig(baseUrl: _url).hostKey,
        testedModel: 'gpt-test',
        monthlyTokenCap: 200000,
      );
    reports = InMemoryAiReportStore();
    factoryCalls = 0;
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(800, 3000);
    addTearDown(tester.view.reset);
    final router = GoRouter(
      initialLocation: AppPaths.aiReadings,
      routes: [
        GoRoute(
          path: AppPaths.aiReadings,
          builder: (_, _) => const AiReadingsScreen(),
          routes: [
            GoRoute(
              path: 'preview',
              builder: (_, state) => AiContextPreviewScreen(
                kind: state.uri.queryParameters['kind'],
                report: state.extra as AiReport?,
              ),
            ),
            GoRoute(
              path: 'formula',
              builder: (_, _) => const AiFormulaScreen(),
            ),
          ],
        ),
        GoRoute(
          path: AppTab.sleep.path,
          builder: (_, _) => const Text('sleep screen'),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          aiConfigStoreProvider.overrideWithValue(configs),
          secretStoreProvider.overrideWithValue(InMemorySecretStore()),
          demoModeStoreProvider.overrideWithValue(InMemoryDemoModeStore()),
          aiEnabledProvider.overrideWith((ref) => true),
          aiPayloadProvider.overrideWith(
            (ref, kind) async => AiPayloadReady(_livePayload, kind: kind),
          ),
          aiReportStoreProvider.overrideWithValue(reports),
          aiRunMarkerStoreProvider.overrideWithValue(
            InMemoryAiRunMarkerStore(),
          ),
          clockProvider.overrideWithValue(() => _now),
          analysisModelFactoryProvider.overrideWithValue((config) async {
            factoryCalls++;
            throw StateError('no model in this test');
          }),
        ],
        child: MaterialApp.router(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> open(WidgetTester tester, Key key) async {
    await tester.tap(find.byKey(key));
    await tester.pumpAndSettle();
  }

  Finder inSheet(Key sheet, String text) =>
      find.descendant(of: find.byKey(sheet), matching: find.text(text));

  testWidgets('confidence shows the lower of the model and the coverage', (
    tester,
  ) async {
    await reports.insert(_report());
    await pump(tester);

    expect(find.text(l10n.aiReadingConfidence('low', 3)), findsOneWidget);
    expect(find.text(l10n.aiReadingConfidence('high', 3)), findsNothing);
    await open(tester, AiReadingKeys.confidence);

    const sheet = AiSheetKeys.confidence;
    expect(inSheet(sheet, l10n.aiConfidenceTitle), findsOne);
    expect(inSheet(sheet, l10n.aiConfidenceModel), findsOne);
    expect(inSheet(sheet, l10n.aiConfidenceCoverage), findsOne);
    expect(inSheet(sheet, l10n.aiConfidenceLevel('high')), findsOne);
    expect(inSheet(sheet, l10n.aiConfidenceLevel('low')), findsNWidgets(2));
    expect(inSheet(sheet, l10n.aiConfidenceFewest(3)), findsOne);
    expect(inSheet(sheet, l10n.aiConfidenceRule), findsOne);
  });

  testWidgets(
    'the confidence sheet opens the formula screen and back returns',
    (tester) async {
      await reports.insert(_report());
      await pump(tester);
      await open(tester, AiReadingKeys.confidence);

      expect(inSheet(AiSheetKeys.confidence, l10n.formulaLink), findsOne);
      await open(tester, AiSheetKeys.formula);
      expect(find.byKey(AiFormulaKeys.intro), findsOneWidget);
      expect(find.byType(AiReadingsScreen), findsNothing);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byKey(AiFormulaKeys.intro), findsNothing);
      expect(find.byType(AiReadingsScreen), findsOneWidget);
    },
  );

  testWidgets('a low model word under high coverage shows low', (tester) async {
    await reports.insert(
      _report(
        cards: [_card(model: 'low', coverage: 'high')],
      ),
    );
    await pump(tester);

    expect(find.text(l10n.aiReadingConfidence('low', 3)), findsOneWidget);
    await open(tester, AiReadingKeys.confidence);

    const sheet = AiSheetKeys.confidence;
    expect(inSheet(sheet, l10n.aiConfidenceLevel('low')), findsNWidgets(2));
    expect(inSheet(sheet, l10n.aiConfidenceLevel('high')), findsOne);
  });

  testWidgets('the dropped sheet lists stored titles and localized reasons', (
    tester,
  ) async {
    await reports.insert(
      _report(
        dropped: [
          {'title': 'Invented fact', 'reason': 'unknownFactId'},
          {'title': 'Seventh card', 'reason': 'excessCardCap'},
        ],
      ),
    );
    await pump(tester);
    await open(tester, AiReadingKeys.dropped);

    const sheet = AiSheetKeys.dropped;
    expect(inSheet(sheet, l10n.aiDroppedTitle(2)), findsOne);
    expect(inSheet(sheet, l10n.aiDroppedLead(3)), findsOne);
    expect(inSheet(sheet, '“Invented fact”'), findsOne);
    expect(inSheet(sheet, '“Seventh card”'), findsOne);
    expect(inSheet(sheet, 'Cites data that was not sent'), findsOne);
    expect(inSheet(sheet, 'More than 6 cards'), findsOne);
  });

  group('usage of this reading', () {
    testWidgets('shows the estimate, the reported tokens and thinking', (
      tester,
    ) async {
      await reports.insert(_report());
      await pump(tester);
      await open(tester, AiReadingKeys.usage);

      const sheet = AiSheetKeys.usage;
      final estimate = estimateAiTokens('stored systemstored user');
      expect(inSheet(sheet, l10n.aiPreviewTokens(estimate)), findsOne);
      expect(inSheet(sheet, '4,612 in, 1,180 out (640 thinking)'), findsOne);
      expect(find.byKey(AiSheetKeys.cost), findsNothing);
    });

    testWidgets('missing usage says so and never shows 0', (tester) async {
      await reports.insert(_report(input: null, output: null, thinking: null));
      await pump(tester);
      await open(tester, AiReadingKeys.usage);

      expect(inSheet(AiSheetKeys.usage, l10n.aiUsageNotReported), findsOne);
      expect(find.textContaining('0 in'), findsNothing);
    });

    testWidgets('no thinking count leaves the bracket out', (tester) async {
      await reports.insert(_report(thinking: null));
      await pump(tester);
      await open(tester, AiReadingKeys.usage);

      expect(inSheet(AiSheetKeys.usage, '4,612 in, 1,180 out'), findsOne);
    });

    testWidgets('a provider cost names the host', (tester) async {
      await reports.insert(
        _report(
          cost: 0.0031,
          currency: 'credits',
          source: AiCostSource.provider,
        ),
      );
      await pump(tester);
      await open(tester, AiReadingKeys.usage);

      expect(
        find.text('0.0031 credits, reported by api.example.com'),
        findsOne,
      );
    });

    testWidgets('an entered price cost is an estimate', (tester) async {
      await reports.insert(
        _report(cost: 0.023, currency: 'USD', source: AiCostSource.userPrice),
      );
      await pump(tester);
      await open(tester, AiReadingKeys.usage);

      expect(
        find.text('about 0.02 USD, from the prices you entered'),
        findsOne,
      );
    });
  });

  testWidgets('the 30 day sheet sums stored reports in the window', (
    tester,
  ) async {
    await reports.insert(
      _report(cost: 0.02, currency: 'USD', source: AiCostSource.userPrice),
    );
    await reports.insert(
      _report(
        hoursAgo: 48,
        input: 1000,
        output: 500,
        cost: 0.01,
        currency: 'USD',
        source: AiCostSource.userPrice,
      ),
    );
    await reports.insert(_report(hoursAgo: 24 * 31, input: 99999));
    await pump(tester);
    await open(tester, AiReadingKeys.usage30);

    const sheet = AiSheetKeys.usage30;
    expect(inSheet(sheet, l10n.aiUsage30Title(2)), findsOne);
    expect(inSheet(sheet, '5,612 in, 1,680 out'), findsOne);
    expect(
      inSheet(sheet, 'about 0.03 USD, from the prices you entered'),
      findsOne,
    );
    expect(inSheet(sheet, l10n.aiAdvancedTokenCap), findsOne);
    expect(inSheet(sheet, '200,000'), findsOne);
    expect(inSheet(sheet, l10n.aiUsage30Note), findsOne);
  });

  testWidgets('an earlier reading opens read only and sends nothing', (
    tester,
  ) async {
    await reports.insert(_report(summary: 'Newest.'));
    await reports.insert(
      _report(summary: 'Older.', hoursAgo: 30, kind: 'daily_review'),
    );
    final failed = _report(hoursAgo: 40, status: AiReportStatus.failed);
    await reports.insert(failed);
    await pump(tester);

    expect(find.text('Newest.'), findsOneWidget);
    expect(find.text('Older.'), findsNothing);
    expect(find.text(l10n.aiReadingsEarlier), findsOneWidget);
    final failedRow = find.byKey(AiReadingKeys.earlier(failed.createdAtUtc));
    expect(
      find.descendant(
        of: failedRow,
        matching: find.byIcon(Icons.error_outline_rounded),
      ),
      findsOne,
    );

    await tester.tap(find.text(l10n.aiReadingKind('daily')).last);
    await tester.pumpAndSettle();

    expect(find.text('Older.'), findsOneWidget);
    expect(find.text('Newest.'), findsNothing);
    expect(factoryCalls, 0);
    expect(reports.reports, hasLength(3));
  });

  testWidgets('what was sent shows the stored text, not the live payload', (
    tester,
  ) async {
    await reports.insert(_report());
    await pump(tester);
    await open(tester, AiReadingKeys.sent);

    expect(find.text(l10n.aiReadingSent), findsOneWidget);
    expect(find.text('stored user'), findsOneWidget);
    expect(find.text('stored system'), findsOneWidget);
    expect(find.text('live user message'), findsNothing);
    expect(find.byKey(AiPreviewKeys.readable), findsNothing);
  });

  testWidgets('what was sent is hidden once retention cleared the payload', (
    tester,
  ) async {
    await reports.insert(_report(payloadJson: null));
    await pump(tester);

    expect(find.byKey(AiReadingKeys.sent), findsNothing);
    expect(find.byKey(AiReadingKeys.usage), findsOneWidget);
  });

  testWidgets('a chip opens its metric, a chip without one opens nothing', (
    tester,
  ) async {
    await reports.insert(
      _report(
        cards: [
          _card(evidence: ['f.sleepMin.avg', 'f.workouts.count']),
        ],
      ),
    );
    await pump(tester);

    await tester.tap(find.byKey(AiReadingKeys.chip('f.workouts.count')));
    await tester.pumpAndSettle();
    expect(find.text('sleep screen'), findsNothing);
    expect(find.text('Stored summary.'), findsOneWidget);

    await tester.tap(find.byKey(AiReadingKeys.chip('f.sleepMin.avg')));
    await tester.pumpAndSettle();
    expect(find.text('sleep screen'), findsOneWidget);
  });

  test('every daily metric has a route and workout facts have none', () {
    final expected = {
      AiDailyMetric.sleepMin: AppTab.sleep.path,
      AiDailyMetric.sleepScore: AppTab.sleep.path,
      AiDailyMetric.rhr: AppTab.heart.path,
      AiDailyMetric.hrv: AppTab.heart.path,
      AiDailyMetric.stress: AppTab.heart.path,
      AiDailyMetric.spo2: AppTab.heart.path,
      AiDailyMetric.steps: AppTab.activity.path,
      AiDailyMetric.activeKcal: AppTab.activity.path,
      AiDailyMetric.load: AppPaths.effort,
      AiDailyMetric.readiness: AppPaths.readiness,
      AiDailyMetric.dayScore: AppPaths.dayScore,
      AiDailyMetric.weight: AppPaths.body,
    };
    expect(expected.keys, unorderedEquals(AiDailyMetric.values));
    for (final MapEntry(:key, :value) in expected.entries) {
      expect(aiFactRoute('f.${key.name}.avg'), value, reason: key.name);
      expect(aiFactRoute('f.${key.name}.last'), value, reason: key.name);
    }
    expect(aiFactRoute('f.workouts.count'), isNull);
    expect(aiFactRoute('sleep_avg'), isNull);
  });
}

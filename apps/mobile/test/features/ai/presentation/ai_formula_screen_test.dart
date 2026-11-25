import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/ai/application/ai_gate.dart';
import 'package:open_ring/features/ai/domain/ai_cost.dart';
import 'package:open_ring/features/ai/domain/ai_prompt.dart';
import 'package:open_ring/features/ai/domain/ai_report_models.dart';
import 'package:open_ring/features/ai/domain/ai_report_validator.dart';
import 'package:open_ring/features/ai/domain/health_context_assembly.dart';
import 'package:open_ring/features/ai/domain/health_context_models.dart';
import 'package:open_ring/features/ai/domain/health_context_v2.dart';
import 'package:open_ring/features/ai/presentation/ai_formula_screen.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

import '../../../helpers/layout_harness.dart';

const List<Key> _keys = [
  AiFormulaKeys.summary,
  AiFormulaKeys.facts,
  AiFormulaKeys.check,
  AiFormulaKeys.confidence,
  AiFormulaKeys.tokens,
  AiFormulaKeys.ours,
  AiFormulaKeys.unchecked,
  AiFormulaKeys.estimate,
];

Future<void> _pump(
  WidgetTester tester, {
  Locale locale = const Locale('en'),
  double scale = 1,
  bool aiOn = false,
  Size size = const Size(400, 9000),
  AiFormulaScreen screen = const AiFormulaScreen(),
}) => pumpScaled(
  tester,
  screenHost(screen),
  textScaler: TextScaler.linear(scale),
  brightness: Brightness.light,
  locale: locale,
  size: size,
  overrides: [aiEnabledProvider.overrideWith((ref) => aiOn)],
);

List<String> _allTexts(AppLocalizations l, String periods) => [
  l.formulaLink,
  l.aiFormulaIntro,
  l.aiFormulaSummaryTitle,
  l.aiFormulaSummaryBody(
    AiContextWindow.standard.maxDays,
    AiContextWindow.standard.maxWeeks,
  ),
  for (final level in AiDetailLevel.values) ...[
    l.aiDetailLevel(level.name),
    l.aiFormulaLevel(
      level.name,
      AiContextWindow.extended.maxDays,
      AiContextWindow.extended.maxWeeks,
    ),
  ],
  l.aiFormulaNever,
  l.aiFormulaFactsTitle,
  l.aiFormulaFactsBody(aiMinFactDays),
  l.aiFormulaCheckTitle,
  for (final rule in const [
    'cited',
    'theme',
    'numbers',
    'action',
    'words',
    'links',
  ])
    l.aiFormulaRule(rule, periods, aiMaxEvidenceIds),
  l.aiFormulaThousands,
  l.aiConfidenceTitle,
  l.aiFormulaConfidenceExpr(
    aiCoverageHighDays,
    aiCoverageMediumDays,
    aiCoverageHighDays - 1,
  ),
  l.aiConfidenceRule,
  l.aiFormulaTokensTitle,
  l.aiFormulaTokensNote,
  l.dayScoreFormulaSourceOursTitle,
  l.aiFormulaOurs(
    aiCoverageMediumDays,
    aiCoverageHighDays,
    aiBytesPerToken,
    aiMinDaysWithData,
    aiMaxReportCards,
  ),
  l.effortFormulaUncheckedTitle,
  for (final item in const ['keystore', 'cleartext', 'play'])
    l.aiFormulaUnchecked(item),
  l.metricEstimateNote,
];

void main() {
  test('promoted constants keep their values', () {
    expect(aiCoverageHighDays, 10);
    expect(aiCoverageMediumDays, 5);
    expect(aiCitablePeriods, [7, 12, 14, 28]);
    expect(aiMinFactDays, 3);
    expect(aiBytesPerToken, 3);
    expect(aiPriceTokens, 1000000);
    expect(estimateAiTokens(''), 0);
    expect(estimateAiTokens('abc'), 1);
    expect(estimateAiTokens('abcd'), 2);
    expect(estimateAiTokens('ção'), 2);
  });

  for (final aiOn in const [false, true]) {
    for (final locale in const [Locale('en'), Locale('pt')]) {
      testWidgets('every string renders in $locale with AI on: $aiOn', (
        tester,
      ) async {
        await _pump(tester, locale: locale, aiOn: aiOn);
        final l = lookupAppLocalizations(locale);

        for (final text in _allTexts(l, '7, 12, 14, 28')) {
          expect(find.text(text), findsOneWidget, reason: text);
        }
        expect(
          find.text(
            l.aiFormulaTokensExpr(
              aiBytesPerToken,
              locale.languageCode == 'en' ? '1,000,000' : '1.000.000',
            ),
          ),
          findsOneWidget,
        );
      });
    }
  }

  testWidgets('the period list follows the ideographic comma in ja', (
    tester,
  ) async {
    const locale = Locale('ja');
    await _pump(tester, locale: locale);
    final l = lookupAppLocalizations(locale);

    expect(
      find.text(l.aiFormulaRule('numbers', '7、12、14、28', aiMaxEvidenceIds)),
      findsOneWidget,
    );
  });

  testWidgets('every printed number follows the numbers it is given', (
    tester,
  ) async {
    const numbers = AiFormulaNumbers(
      coverageHighDays: 12,
      coverageMediumDays: 4,
      citablePeriods: [9, 30],
      minFactDays: 2,
      maxCited: 8,
      bytesPerToken: 4,
      priceTokens: 1000,
      minDaysWithData: 6,
      maxCards: 7,
      window: AiContextWindow.compact,
    );
    await _pump(tester, screen: const AiFormulaScreen(numbers: numbers));
    final l = lookupAppLocalizations(const Locale('en'));

    for (final text in [
      l.aiFormulaConfidenceExpr(12, 4, 11),
      l.aiFormulaOurs(4, 12, 4, 6, 7),
      l.aiFormulaFactsBody(2),
      l.aiFormulaRule('numbers', '9, 30', 8),
      l.aiFormulaRule('cited', '9, 30', 8),
      l.aiFormulaTokensExpr(4, '1,000'),
      l.aiFormulaSummaryBody(7, 4),
    ]) {
      expect(find.text(text), findsOneWidget, reason: text);
    }
    expect(find.text(l.aiFormulaConfidenceExpr(10, 5, 9)), findsNothing);
  });

  group('AiFormulaScreen layout', () {
    for (final scale in const [1.0, 2.0]) {
      for (final locale in const [
        Locale('en'),
        Locale('pt'),
        Locale('de'),
        Locale('ru'),
      ]) {
        testWidgets('fits without overflow at ${scale}x $locale', (
          tester,
        ) async {
          await _pump(tester, locale: locale, scale: scale, size: phoneSize);
          expect(find.byKey(AiFormulaKeys.intro), findsOneWidget);
          await expectNoLayoutOverflow(() async {
            final scrollable = find.byType(Scrollable).first;
            for (final key in _keys) {
              await tester.scrollUntilVisible(
                find.byKey(key),
                140,
                scrollable: scrollable,
              );
              await tester.pumpAndSettle();
            }
          });
        });
      }
    }
  });
}

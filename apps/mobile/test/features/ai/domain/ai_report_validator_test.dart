import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/features/ai/domain/ai_report_models.dart';
import 'package:open_ring/features/ai/domain/ai_report_validator.dart';
import 'package:open_ring/features/ai/domain/ai_safety_lexicon.dart';
import 'package:open_ring/features/ai/domain/health_context_models.dart';
import 'package:open_ring/features/ai/domain/health_context_v2.dart';

HealthFact _fact(
  String id,
  double value, {
  AiFactUnit unit = AiFactUnit.score,
  AiMetricFamily family = AiMetricFamily.sleep,
  int days = 14,
}) => HealthFact(
  id: id,
  label: id,
  value: value,
  unit: unit,
  family: family,
  days: days,
);

RawAiCard _card({
  AiMetricFamily family = AiMetricFamily.sleep,
  String title = 'Sleep note',
  String insight = 'Readiness stayed 75 vs 63.',
  List<String> evidence = const ['f1', 'f2'],
  String action = 'Try a 20 min walk.',
  AiConfidence confidence = AiConfidence.high,
}) => RawAiCard(
  family: family,
  title: title,
  insight: insight,
  evidence: evidence,
  action: action,
  confidence: confidence,
);

void main() {
  group('AiSafetyLexicon', () {
    test('maps every aiAllowedReplyLanguages entry and comma decimals', () {
      final seen = <String>{};
      for (final tag in aiAllowedReplyLanguages) {
        final base = AiSafetyLexicon.baseLocale(tag);
        seen.add(base);
        expect(
          AiSafetyLexicon.supportedBaseLocales,
          contains(base),
          reason: tag,
        );
      }
      expect(seen, AiSafetyLexicon.supportedBaseLocales);
      expect(AiSafetyLexicon.baseLocale('pt_BR'), 'pt');
      expect(AiSafetyLexicon.baseLocale('xx-BAD'), 'en');
      expect(AiSafetyLexicon.usesCommaDecimal('pt-BR'), isTrue);
      expect(AiSafetyLexicon.usesCommaDecimal('de'), isTrue);
      expect(AiSafetyLexicon.usesCommaDecimal('en'), isFalse);
      expect(AiSafetyLexicon.usesCommaDecimal('ja'), isFalse);
    });

    test('detects medical stems with English fallback and resists false '
        'positives', () {
      final cases = <(String, String, String)>[
        ('en', 'Sleep apnea risk', 'apnea'),
        ('pt-BR', 'Possível apneia.', 'apneia'),
        ('es', 'Una arritmia clara', 'arritmia'),
        ('fr', 'Prendre médicament', 'médicament'),
        ('de', 'Schlafapnoe möglich', 'apnoe'),
        ('id', 'Gangguan tidur', 'gangguan'),
        ('it', 'Possibile aritmia', 'aritmia'),
        ('ja', '睡眠時無呼吸の可能性', '無呼吸'),
        ('ru', 'Возможно апноэ сна', 'апноэ'),
        ('zh', '可能是睡眠呼吸暂停', '呼吸暂停'),
      ];
      for (final (lang, text, expected) in cases) {
        expect(
          AiSafetyLexicon.findMedicalTerm(text, lang),
          expected,
          reason: lang,
        );
      }
      expect(AiSafetyLexicon.findMedicalTerm('Take 500 mg daily', 'en'), 'mg');
      expect(AiSafetyLexicon.findMedicalTerm('Dose of 500mg', 'en'), 'mg');
      expect(
        AiSafetyLexicon.findMedicalTerm('Among healthy images', 'en'),
        isNull,
      );
      expect(
        AiSafetyLexicon.findMedicalTerm('Signs of arrhythmia noted', 'pt-BR'),
        'arrhythmia',
      );
      // Culinary/numeral false-positive guards.
      expect(
        AiSafetyLexicon.findMedicalTerm('Dos noches seguidas bien', 'es'),
        isNull,
      );
      expect(
        AiSafetyLexicon.findMedicalTerm('Boa receita caseira hoje', 'pt-BR'),
        isNull,
      );
      expect(
        AiSafetyLexicon.findMedicalTerm('Ricetta leggera per cena', 'it'),
        isNull,
      );
      expect(
        AiSafetyLexicon.findMedicalTerm('Resep makan malam ringan', 'id'),
        isNull,
      );
      expect(
        AiSafetyLexicon.findMedicalTerm('Рецепт ужина без сахара', 'ru'),
        isNull,
      );
    });

    test('detects causal phrases, units, forbidden vitals, and links', () {
      final causalCases = <(String, String, String)>[
        ('en', 'Readiness dropped because late.', 'because'),
        ('pt-BR', 'Noites tarde causaram queda.', 'causaram'),
        ('es', 'Dormir poco provocó caída.', 'provocó'),
        ('fr', 'Baisse en raison de fatigue.', 'en raison de'),
        ('de', 'Niedriger weil zu spät.', 'weil'),
        ('id', 'Turun karena tidur larut.', 'karena'),
        ('it', 'Calato perché tardi.', 'perché'),
        ('ja', '遅寝のため低下しました。', 'のため'),
        ('ru', 'Снижение потому что поздно.', 'потому что'),
        ('zh', '因为睡得晚所以分数低。', '因为'),
      ];
      for (final (lang, text, expected) in causalCases) {
        expect(
          AiSafetyLexicon.findCausalPhrase(text, lang),
          expected,
          reason: lang,
        );
      }
      expect(
        AiSafetyLexicon.findCausalPhrase('Kurze Zeit verweilen.', 'de'),
        isNull,
      );
      expect(
        AiSafetyLexicon.findCausalPhrase('Noites tardias e média menor.', 'pt'),
        isNull,
      );

      expect(AiSafetyLexicon.hasPeriodUnitAfter(' days', 'en'), isTrue);
      expect(AiSafetyLexicon.hasPeriodUnitAfter(' noites', 'pt'), isTrue);
      expect(AiSafetyLexicon.hasPeriodUnitAfter('週間', 'ja'), isTrue);
      expect(AiSafetyLexicon.hasPeriodUnitAfter(' дней', 'ru'), isTrue);
      expect(AiSafetyLexicon.hasPeriodUnitAfter(' 天', 'zh'), isTrue);
      expect(AiSafetyLexicon.hasPeriodUnitAfter(' bpm', 'en'), isFalse);

      expect(AiSafetyLexicon.hasAllowedActionUnitAfter(' min', 'en'), isTrue);
      expect(
        AiSafetyLexicon.hasAllowedActionUnitAfter(' minutos', 'pt'),
        isTrue,
      );
      expect(
        AiSafetyLexicon.hasAllowedActionUnitAfter(' Schritte', 'de'),
        isTrue,
      );
      expect(AiSafetyLexicon.hasAllowedActionUnitAfter(' шаг', 'ru'), isTrue);
      expect(AiSafetyLexicon.hasAllowedActionUnitAfter(' 分間', 'ja'), isTrue);
      expect(AiSafetyLexicon.hasAllowedActionUnitAfter(' 小时', 'zh'), isTrue);
      expect(AiSafetyLexicon.hasAllowedActionUnitAfter(' m', 'en'), isFalse);
      expect(AiSafetyLexicon.hasAllowedActionUnitAfter(' hr', 'en'), isFalse);
      expect(AiSafetyLexicon.hasAllowedActionUnitAfter(' ms', 'en'), isFalse);
      expect(AiSafetyLexicon.hasAllowedActionUnitAfter(' mg', 'en'), isFalse);

      for (final vital in const [
        ' bpm',
        ' ms',
        '%',
        ' kg',
        ' lb',
        ' lbs',
        ' kcal',
        ' mg',
        ' mcg',
        ' ml',
        ' mmHg',
        ' SpO2',
        ' мг',
        ' кг',
        ' カロリー',
        ' 千卡',
      ]) {
        expect(
          AiSafetyLexicon.findForbiddenVitalUnitAfter(vital),
          isNotNull,
          reason: vital,
        );
      }
      expect(AiSafetyLexicon.findForbiddenVitalUnitAfter(' min'), isNull);
      expect(
        AiSafetyLexicon.findForbiddenVitalUnitAfter(' good steps'),
        isNull,
      );

      expect(
        AiSafetyLexicon.containsUrlOrMarkdownLink('https://example.com'),
        isTrue,
      );
      expect(
        AiSafetyLexicon.containsUrlOrMarkdownLink('Visit www.example.com'),
        isTrue,
      );
      expect(
        AiSafetyLexicon.containsUrlOrMarkdownLink('Read [more](ref)'),
        isTrue,
      );
      expect(AiSafetyLexicon.containsUrlOrMarkdownLink('Plain text'), isFalse);
    });
  });

  group('AiReportValidator', () {
    test('matches prototype ai.html weekly report and Goals rewording '
        'fixture', () {
      final facts = [
        _fact('f1', 63, days: 3),
        _fact('f2', 74.9, days: 11),
        _fact('f3', 23.8, unit: AiFactUnit.hours, days: 3),
        _fact(
          'f4',
          54.3,
          unit: AiFactUnit.bpm,
          family: AiMetricFamily.heart,
          days: 7,
        ),
        _fact('f5', 55.4, unit: AiFactUnit.bpm, family: AiMetricFamily.heart),
        _fact(
          'f6',
          9316,
          unit: AiFactUnit.steps,
          family: AiMetricFamily.activity,
          days: 9,
        ),
        _fact(
          'f7',
          6050,
          unit: AiFactUnit.steps,
          family: AiMetricFamily.activity,
          days: 4,
        ),
        _fact(
          'f8',
          48,
          unit: AiFactUnit.ms,
          family: AiMetricFamily.heart,
          days: 7,
        ),
        _fact('f9', 46.1, unit: AiFactUnit.ms, family: AiMetricFamily.heart),
        _fact('f10', 42, unit: AiFactUnit.min, days: 7),
        _fact('f11', 21, unit: AiFactUnit.min),
      ];
      const report = RawAiReport(
        summary:
            'Semana estável. Nas manhãs seguintes às noites mais tardias, '
            'a prontidão foi mais baixa.',
        cards: [
          RawAiCard(
            family: AiMetricFamily.sleep,
            title: 'Noites tardias, manhãs mais baixas',
            insight:
                'Nas 3 noites mais tardias das últimas duas semanas, '
                'a prontidão ficou em 63, contra 75 nas outras manhãs.',
            evidence: ['f1', 'f2', 'f3'],
            action: 'Tente deitar no mesmo horário das outras noites.',
            confidence: AiConfidence.medium,
          ),
          RawAiCard(
            family: AiMetricFamily.heart,
            title: 'Sua VFC caiu 12% na semana',
            insight: 'A VFC dos últimos 7 dias ficou 12% abaixo da sua base.',
            evidence: ['f8', 'f9'],
            action: 'Durma mais nos próximos dias.',
            confidence: AiConfidence.high,
          ),
          RawAiCard(
            family: AiMetricFamily.heart,
            title: 'FC de repouso um pouco abaixo da base',
            insight:
                'Nos últimos 7 dias a sua FC de repouso ficou 1 bpm abaixo '
                'da sua base de 14 dias.',
            evidence: ['f4', 'f5'],
            action: 'Mantenha os dias leves entre os treinos fortes.',
            confidence: AiConfidence.medium,
          ),
          RawAiCard(
            family: AiMetricFamily.sleep,
            title: 'Despertares na madrugada',
            insight: 'Os despertares mais longos podem indicar apneia do sono.',
            evidence: ['f10', 'f11'],
            action: 'Converse com um profissional de saúde sobre isso.',
            confidence: AiConfidence.low,
          ),
          RawAiCard(
            family: AiMetricFamily.activity,
            title: 'Fins de semana mais parados',
            insight:
                'Nos dias de semana você andou 9.316 passos, e 6.050 nos '
                'fins de semana.',
            evidence: ['f6', 'f7'],
            action: 'Tente uma caminhada de 20 minutos no sábado e domingo.',
            confidence: AiConfidence.high,
          ),
        ],
      );

      final validated = AiReportValidator.validateReport(
        report,
        facts: facts,
        replyLanguage: 'pt-BR',
      );
      expect(validated.summary, report.summary);
      expect(validated.summaryStripped, isFalse);
      expect(validated.totalModelCards, 5);
      expect(validated.keptCount, 3);
      expect(validated.droppedCount, 2);
      expect(validated.cards[0].shownConfidence, AiConfidence.low);
      expect(validated.cards[0].minEvidenceDays, 3);
      expect(validated.cards[1].shownConfidence, AiConfidence.medium);
      expect(validated.cards[1].minEvidenceDays, 7);
      expect(validated.cards[2].coverageConfidence, AiConfidence.low);
      expect(validated.cards[2].shownConfidence, AiConfidence.low);
      expect(validated.cards[2].minEvidenceDays, 4);
      expect(validated.droppedCards.map((d) => d.reason), [
        AiCardDropReason.unverifiedNumber,
        AiCardDropReason.medicalBlocklist,
      ]);

      final ruleFacts = [
        _fact(
          'p1',
          9000,
          unit: AiFactUnit.steps,
          family: AiMetricFamily.activity,
          days: 7,
        ),
        _fact(
          'p2',
          10000,
          unit: AiFactUnit.steps,
          family: AiMetricFamily.activity,
          days: 7,
        ),
        _fact(
          'p3',
          3,
          unit: AiFactUnit.levers,
          family: AiMetricFamily.overall,
          days: 7,
        ),
      ];
      // COACH_OK uses "porque"; causal filter applies to summary only.
      const coachOk = RawAiCard(
        family: AiMetricFamily.activity,
        title: '',
        insight:
            'As três alavancas couberam na semana 3. A proposta desta segunda '
            'é subir de 9.000 para 10.000 passos por dia, porque a semana '
            'inteira coube.',
        evidence: ['p1', 'p2', 'p3'],
        action: '',
        confidence: AiConfidence.medium,
      );
      const coachBad = RawAiCard(
        family: AiMetricFamily.activity,
        title: '',
        insight: 'Você foi muito bem. Subir para 11.000 passos por dia.',
        evidence: ['p1', 'p2'],
        action: '',
        confidence: AiConfidence.medium,
      );
      expect(
        AiReportValidator.validateReword(
          coachOk,
          ruleFacts: ruleFacts,
          replyLanguage: 'pt-BR',
        ),
        AiRewordAccepted(
          text: coachOk.insight,
          evidenceIds: const ['p1', 'p2', 'p3'],
        ),
      );
      expect(
        AiReportValidator.validateReword(
          coachBad,
          ruleFacts: ruleFacts,
          replyLanguage: 'pt-BR',
        ),
        const AiRewordDropped(
          reason: AiCardDropReason.unverifiedNumber,
          detail: '11.000',
        ),
      );
    });

    test('handles locale numbers, clock times, glued letters, negatives, and '
        'duplicate IDs', () {
      final facts = [
        _fact(
          'f1',
          9316,
          unit: AiFactUnit.steps,
          family: AiMetricFamily.activity,
        ),
        _fact(
          'f2',
          0.125,
          unit: AiFactUnit.kgPerWeek,
          family: AiMetricFamily.body,
        ),
        _fact(
          'f3',
          1234.5,
          unit: AiFactUnit.kcal,
          family: AiMetricFamily.overall,
        ),
        _fact('f4', -0.3, unit: AiFactUnit.kg, family: AiMetricFamily.body),
        _fact('f5', 54.3, unit: AiFactUnit.bpm, family: AiMetricFamily.heart),
        _fact('f6', 74.87),
      ];

      // pt-BR: 9.316 is 9316, 0.125 is 0.125, SpO2 skipped, 23:45 skipped, 0,3 matches -0.3.
      final ptGood = _card(
        family: AiMetricFamily.overall,
        title: 'SpO2 e horário 23:45 estáveis',
        insight:
            'Média 9.316 passos, perda de 0.125 kg/sem e recuo de 0,3 kg '
            'após meta f6 de 74.9.',
        evidence: ['f1', 'f2', 'f4', 'f6'],
      );
      final ptRes = AiReportValidator.validateReport(
        RawAiReport(summary: '', cards: [ptGood]),
        facts: facts,
        replyLanguage: 'pt-BR',
      );
      expect(ptRes.keptCount, 1);

      // French/Russian NBSP thousands: 9\u00a0316 matches 9316.
      final frGood = _card(
        family: AiMetricFamily.activity,
        title: 'Pas moyens',
        insight: 'Moyenne de 9\u00a0316 pas.',
        evidence: ['f1'],
      );
      expect(
        AiReportValidator.validateReport(
          RawAiReport(summary: '', cards: [frGood]),
          facts: facts,
          replyLanguage: 'fr',
        ).keptCount,
        1,
      );

      // English comma thousands and mixed separators: 9,316 + 1,234.5 + 0,125.
      final enGood = _card(
        family: AiMetricFamily.overall,
        title: 'Steps and rate',
        insight: 'Averaged 9,316 steps, 1,234.5 kcal, and 0,125 rate.',
        evidence: ['f1', 'f2', 'f3'],
      );
      expect(
        AiReportValidator.validateReport(
          RawAiReport(summary: '', cards: [enGood]),
          facts: facts,
          replyLanguage: 'en',
        ).keptCount,
        1,
      );

      // Invalid clock/date/off-by-one attempts must be rejected.
      for (final text in const [
        'Ratio stayed 30:70.',
        'Date 2026.12.07 changed.',
        'HR was 55 bpm.',
        'Clock 12:34:56 failed.',
      ]) {
        final badCard = _card(
          family: AiMetricFamily.heart,
          title: 'Check',
          insight: text,
          evidence: const ['f5'],
        );
        final res = AiReportValidator.validateReport(
          RawAiReport(summary: '', cards: [badCard]),
          facts: facts,
          replyLanguage: 'pt-BR',
        );
        expect(
          res.droppedCards.single.reason,
          AiCardDropReason.unverifiedNumber,
          reason: text,
        );
      }

      // Duplicate ID ['f5', 'f5'] must deduplicate and not fabricate derived 0.
      final dupZero = _card(
        family: AiMetricFamily.heart,
        title: 'Check',
        insight: 'Change was 0 bpm.',
        evidence: const ['f5', 'f5'],
      );
      final dupRes = AiReportValidator.validateReport(
        RawAiReport(summary: '', cards: [dupZero]),
        facts: facts,
        replyLanguage: 'en',
      );
      expect(
        dupRes.droppedCards.single.reason,
        AiCardDropReason.unverifiedNumber,
      );
    });

    test(
      'enforces all 10 drop reasons, cap isolation, and confidence tiers',
      () {
        final facts = [
          _fact('s1', 70, days: 4),
          _fact('s2', 80, days: 7),
          _fact('s3', 85, days: 10),
          _fact('h1', 60, family: AiMetricFamily.heart, days: 12),
        ];

        final report = RawAiReport(
          summary: '',
          cards: [
            _card(title: '   ', evidence: const ['s3']),
            _card(evidence: const []),
            _card(evidence: List.filled(7, 's3')),
            _card(evidence: const ['missing']),
            _card(family: AiMetricFamily.heart, evidence: const ['s3']),
            _card(insight: 'Was 99 today.', evidence: const ['s3']),
            _card(
              insight: 'Sleep hit 85.',
              action: 'Keep HR at 60 bpm.',
              evidence: const ['s3'],
            ),
            _card(
              insight: 'Sleep hit 85.',
              action: 'Walk 10 m today.',
              evidence: const ['s3'],
            ),
            _card(insight: 'Avoid diabetes signs.', evidence: const ['s3']),
            _card(insight: 'See https://x.test now.', evidence: const ['s3']),
            // Valid cards #1..#6 fill the cap after the invalid cards above.
            for (var i = 1; i <= aiMaxReportCards; i++)
              _card(
                title: 'Valid card',
                insight: 'Sleep hit 85.',
                evidence: const ['s3'],
                confidence: i == 1 ? AiConfidence.low : AiConfidence.high,
              ),
            // 7th valid card triggers excessCardCap.
            _card(
              title: 'Overflow',
              insight: 'Sleep hit 85.',
              evidence: const ['s3'],
            ),
          ],
        );

        final res = AiReportValidator.validateReport(
          report,
          facts: facts,
          replyLanguage: 'en',
        );
        expect(res.keptCount, aiMaxReportCards);
        expect(res.droppedCards.map((d) => d.reason).toList(), [
          AiCardDropReason.emptyText,
          AiCardDropReason.evidenceEmptyOrTooMany,
          AiCardDropReason.evidenceEmptyOrTooMany,
          AiCardDropReason.unknownFactId,
          AiCardDropReason.familyMismatch,
          AiCardDropReason.unverifiedNumber,
          AiCardDropReason.vitalUnitInAction,
          AiCardDropReason.disallowedActionNumber,
          AiCardDropReason.medicalBlocklist,
          AiCardDropReason.urlOrMarkdown,
          AiCardDropReason.excessCardCap,
        ]);
        expect(res.cards.first.coverageConfidence, AiConfidence.high);
        expect(res.cards.first.shownConfidence, AiConfidence.low);

        // Reword permits empty title/action but rejects empty insight.
        expect(
          AiReportValidator.validateReword(
            _card(
              title: '',
              insight: '   ',
              action: '',
              evidence: const ['s3'],
            ),
            ruleFacts: facts,
            replyLanguage: 'en',
          ),
          const AiRewordDropped(
            reason: AiCardDropReason.emptyText,
            detail: 'insight',
          ),
        );
        // Window weeks exception accepts 4 weeks when windowWeeks == 4.
        expect(
          AiReportValidator.validateReport(
            RawAiReport(
              summary: 'Pattern across 4 weeks and 85 score.',
              cards: [
                _card(
                  title: 'Four weeks',
                  insight: 'Over 4 weeks sleep was 85.',
                  evidence: const ['s3'],
                ),
              ],
            ),
            facts: facts,
            replyLanguage: 'en',
            windowWeeks: 4,
          ).keptCount,
          1,
        );
      },
    );

    test('filters summary causality/medical/URL/numbers and finds unverified '
        'raw spans', () {
      final facts = [_fact('f1', 75), _fact('f2', 63, days: 3)];
      for (final badSummary in const [
        'Scores dropped because of late nights.',
        'Possible sleep apnea pattern.',
        'Check https://openring.app for more.',
        'Average climbed by 42 points.',
      ]) {
        final r = AiReportValidator.validateReport(
          RawAiReport(summary: badSummary, cards: const []),
          facts: facts,
          replyLanguage: 'en',
        );
        expect(r.summary, '', reason: badSummary);
        expect(r.summaryStripped, isTrue, reason: badSummary);
      }

      final emptySum = AiReportValidator.validateReport(
        const RawAiReport(summary: '   ', cards: []),
        facts: facts,
        replyLanguage: 'en',
      );
      expect(emptySum.summary, '');
      expect(emptySum.summaryStripped, isFalse);

      // validateForPayload integrates directly with HealthContextBuilder output.
      final built = HealthContextBuilder.build(
        HealthContextInput(
          kind: AiAnalysisKind.weeklyReview,
          replyLanguage: 'pt-BR',
          detail: AiDetailLevel.standard,
          window: AiContextWindow.standard,
          units: const AiUnits(),
          profile: const AiProfileInput(age: 34, stepGoal: 10000),
          coverage: const AiCoverageInput(
            hasRing: true,
            sleepSource: AiSleepSource.ring,
            daysWithRingData: 14,
          ),
          days: const [
            AiDayRow(
              date: LocalDate(2026, 12, 1),
              weekday: AiWeekday.tue,
              steps: 8000,
            ),
          ],
          facts: facts,
        ),
      );
      final payloadRes = AiReportValidator.validateForPayload(
        RawAiReport(
          summary: 'Score médio de 75 em 14 dias.',
          cards: [
            _card(title: 'Pontuação 75', insight: 'Média de 75 contra 63.'),
          ],
        ),
        built,
      );
      expect(payloadRes.summaryStripped, isFalse);
      expect(payloadRes.keptCount, 1);

      final sparsePayload = BuiltAiPayload(
        contextMap: const {},
        canonicalContextJson: '{}',
        systemPrompt: '',
        userMessage: '',
        facts: facts,
        estimatedTokens: 1,
        contextTokens: 1,
        cacheKey: 'k',
        droppedCount: 0,
      );
      final fallbackRes = AiReportValidator.validateForPayload(
        RawAiReport(
          summary: 'Score 75 across 14 days.',
          cards: [_card(title: 'Score 75', insight: 'Average 75 vs 63.')],
        ),
        sparsePayload,
      );
      expect(fallbackRes.summaryStripped, isFalse);
      expect(fallbackRes.keptCount, 1);

      const rawText =
          'SpO2 stayed ok at 23:45, score 75 over 14 days, vs 99 and 37.5.';
      final spans = AiReportValidator.findUnverifiedSpans(
        rawText,
        facts: facts,
        replyLanguage: 'en',
      );
      expect(spans.map((s) => s.raw).toList(), ['99', '37.5']);
      for (final s in spans) {
        expect(rawText.substring(s.start, s.end), s.raw);
      }
    });
  });
}

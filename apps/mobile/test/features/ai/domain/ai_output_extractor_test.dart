import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/ai/domain/ai_output_extractor.dart';
import 'package:open_ring/features/ai/domain/ai_report_models.dart';
import 'package:open_ring/features/ai/domain/health_context_models.dart';

String _cardJson({
  String family = 'sleep',
  String title = 'T',
  String insight = 'I',
  String evidence = '["f1"]',
  String action = 'A',
  String confidence = 'medium',
}) =>
    '{"family":"$family","title":"$title","insight":"$insight",'
    '"evidence":$evidence,"action":"$action","confidence":"$confidence"}';

void main() {
  group('ai_report_models', () {
    test('parseAiMetricFamily parses all enum values and rejects invalid', () {
      for (final family in AiMetricFamily.values) {
        expect(parseAiMetricFamily(family.name), family);
        expect(parseAiMetricFamily(' ${family.name.toUpperCase()} '), family);
      }
      expect(parseAiMetricFamily('unknown'), isNull);
      expect(parseAiMetricFamily(42), isNull);
      expect(AiCardDropReason.values, contains(AiCardDropReason.emptyText));
    });

    test('AiConfidence rank, minOf, and parseWire obey lattice order', () {
      expect(AiConfidence.low.rank, 0);
      expect(AiConfidence.medium.rank, 1);
      expect(AiConfidence.high.rank, 2);
      expect(
        AiConfidence.minOf(AiConfidence.high, AiConfidence.medium),
        AiConfidence.medium,
      );
      expect(
        AiConfidence.minOf(AiConfidence.low, AiConfidence.high),
        AiConfidence.low,
      );
      expect(AiConfidence.parseWire(' HIGH '), AiConfidence.high);
      expect(AiConfidence.parseWire('unknown'), isNull);
      expect(AiConfidence.parseWire(42), isNull);
    });

    test('ValidatedAiCard JSON round-trip validates all fields safely', () {
      const card = ValidatedAiCard(
        family: AiMetricFamily.sleep,
        title: 'Late bedtimes, lower readiness',
        insight: 'On late nights readiness averaged 63 vs 75.',
        evidenceIds: ['f1', 'f2'],
        action: 'Keep a steady bedtime for 7 days.',
        modelConfidence: AiConfidence.high,
        coverageConfidence: AiConfidence.low,
        shownConfidence: AiConfidence.low,
        minEvidenceDays: 3,
      );
      final encoded = card.toJson();
      final decoded = ValidatedAiCard.fromJson(encoded);
      expect(decoded, card);
      expect(decoded.hashCode, card.hashCode);

      for (final badKey in const [
        'family',
        'title',
        'insight',
        'evidenceIds',
        'action',
        'modelConfidence',
        'coverageConfidence',
        'shownConfidence',
        'minEvidenceDays',
      ]) {
        final copy = Map<String, Object?>.of(encoded)..remove(badKey);
        expect(ValidatedAiCard.fromJson(copy), isNull, reason: badKey);
      }
      expect(
        ValidatedAiCard.fromJson({...encoded, 'family': 'invalid'}),
        isNull,
      );
      expect(
        ValidatedAiCard.fromJson({...encoded, 'evidenceIds': const []}),
        isNull,
      );
      expect(
        ValidatedAiCard.fromJson({
          ...encoded,
          'evidenceIds': const ['f1', 'f2', 'f3', 'f4', 'f5', 'f6', 'f7'],
        }),
        isNull,
      );
      expect(
        ValidatedAiCard.fromJson({
          ...encoded,
          'evidenceIds': const [' '],
        }),
        isNull,
      );
      expect(
        ValidatedAiCard.fromJson({
          ...encoded,
          'evidenceIds': const [1],
        }),
        isNull,
      );
      expect(
        ValidatedAiCard.fromJson({...encoded, 'minEvidenceDays': -1}),
        isNull,
      );
      expect(
        ValidatedAiCard.fromJson({...encoded, 'shownConfidence': 'ultra'}),
        isNull,
      );
    });

    test('value equality holds and distinguishes field diffs across DTOs', () {
      const rawCardA = RawAiCard(
        family: AiMetricFamily.heart,
        title: 'T',
        insight: 'I',
        evidence: ['f1'],
        action: 'A',
        confidence: AiConfidence.medium,
      );
      const rawCardB = RawAiCard(
        family: AiMetricFamily.heart,
        title: 'T',
        insight: 'I',
        evidence: ['f1'],
        action: 'A',
        confidence: AiConfidence.medium,
      );
      const rawCardDiff = RawAiCard(
        family: AiMetricFamily.sleep,
        title: 'T',
        insight: 'I',
        evidence: ['f1'],
        action: 'A',
        confidence: AiConfidence.medium,
      );
      expect(rawCardA, rawCardB);
      expect(rawCardA.hashCode, rawCardB.hashCode);
      expect(rawCardA, isNot(rawCardDiff));

      const rptA = RawAiReport(summary: 'S', cards: [rawCardA]);
      const rptB = RawAiReport(summary: 'S', cards: [rawCardB]);
      expect(rptA, rptB);
      expect(rptA.hashCode, rptB.hashCode);
      expect(rptA, isNot(const RawAiReport(summary: 'X', cards: [rawCardA])));

      const dropA = DroppedAiCard(
        card: rawCardA,
        reason: AiCardDropReason.medicalBlocklist,
        detail: 'apnea',
      );
      const dropB = DroppedAiCard(
        card: rawCardB,
        reason: AiCardDropReason.medicalBlocklist,
        detail: 'apnea',
      );
      expect(dropA, dropB);
      expect(dropA.hashCode, dropB.hashCode);
      expect(
        dropA,
        isNot(
          const DroppedAiCard(
            card: rawCardA,
            reason: AiCardDropReason.urlOrMarkdown,
            detail: 'apnea',
          ),
        ),
      );

      const vCard = ValidatedAiCard(
        family: AiMetricFamily.heart,
        title: 'T',
        insight: 'I',
        evidenceIds: ['f1'],
        action: 'A',
        modelConfidence: AiConfidence.medium,
        coverageConfidence: AiConfidence.low,
        shownConfidence: AiConfidence.low,
        minEvidenceDays: 4,
      );
      const vCardDiff = ValidatedAiCard(
        family: AiMetricFamily.heart,
        title: 'T',
        insight: 'I',
        evidenceIds: ['f1'],
        action: 'A',
        modelConfidence: AiConfidence.medium,
        coverageConfidence: AiConfidence.low,
        shownConfidence: AiConfidence.low,
        minEvidenceDays: 5,
      );
      expect(vCard, isNot(vCardDiff));

      const valA = ValidatedAiReport(
        summary: 'S',
        summaryStripped: true,
        cards: [vCard],
        droppedCards: [dropA],
        totalModelCards: 2,
      );
      const valB = ValidatedAiReport(
        summary: 'S',
        summaryStripped: true,
        cards: [vCard],
        droppedCards: [dropB],
        totalModelCards: 2,
      );
      const valDiff = ValidatedAiReport(
        summary: 'S',
        summaryStripped: false,
        cards: [vCard],
        droppedCards: [dropB],
        totalModelCards: 2,
      );
      expect(valA, valB);
      expect(valA.hashCode, valB.hashCode);
      expect(valA, isNot(valDiff));
      expect(valA.keptCount, 1);
      expect(valA.droppedCount, 1);

      const spanA = AiUnverifiedSpan(start: 3, end: 7, raw: '12.5');
      const spanB = AiUnverifiedSpan(start: 3, end: 7, raw: '12.5');
      expect(spanA, spanB);
      expect(spanA.hashCode, spanB.hashCode);
      expect(
        spanA,
        isNot(const AiUnverifiedSpan(start: 4, end: 7, raw: '12.5')),
      );

      const accA = AiRewordAccepted(text: 'Keep 9.000', evidenceIds: ['p1']);
      const accB = AiRewordAccepted(text: 'Keep 9.000', evidenceIds: ['p1']);
      const drpA = AiRewordDropped(
        reason: AiCardDropReason.unverifiedNumber,
        detail: '11.000',
      );
      const drpB = AiRewordDropped(
        reason: AiCardDropReason.unverifiedNumber,
        detail: '11.000',
      );
      expect(accA, accB);
      expect(accA.hashCode, accB.hashCode);
      expect(drpA, drpB);
      expect(drpA.hashCode, drpB.hashCode);
      expect(accA, isNot(drpA));
    });
  });

  group('AiOutputExtractor', () {
    test('extractFirstJsonObject handles strings, escapes, braces, and '
        'depth caps', () {
      expect(
        AiOutputExtractor.extractFirstJsonObject(r'prefix {"a":"{x}\"}"} tail'),
        r'{"a":"{x}\"}"}',
      );
      expect(
        AiOutputExtractor.extractFirstJsonObject('} garbage {"b":[1,2]} more'),
        '{"b":[1,2]}',
      );
      expect(AiOutputExtractor.extractFirstJsonObject('no json'), isNull);
      expect(AiOutputExtractor.extractFirstJsonObject('{"a": 1'), isNull);
      expect(
        AiOutputExtractor.extractFirstJsonObject('{"a": "unclosed'),
        isNull,
      );
      expect(AiOutputExtractor.extractFirstJsonObject('{"a":[1]]}'), isNull);
      expect(AiOutputExtractor.extractFirstJsonObject('{"a":[1}'), isNull);
      expect(AiOutputExtractor.extractFirstJsonObject('{"a":[{]}]}'), isNull);

      expect(
        AiOutputExtractor.extractFirstJsonObject('{"a":1}', maxDepth: 0),
        isNull,
      );
      expect(
        AiOutputExtractor.extractFirstJsonObject('{"a":1}', maxDepth: 1),
        '{"a":1}',
      );
      expect(
        AiOutputExtractor.extractFirstJsonObject('{"a":{"b":1}}', maxDepth: 1),
        isNull,
      );

      final tooDeepObj = '${'{"k":' * 17}1${'}' * 17}';
      expect(AiOutputExtractor.extractFirstJsonObject(tooDeepObj), isNull);
      final tooDeepArr = '{"k":${'[' * 16}1${']' * 16}}';
      expect(AiOutputExtractor.extractFirstJsonObject(tooDeepArr), isNull);
    });

    test('extractReport strips think blocks/fences and validates schema '
        'strictly', () {
      const validRaw = '''
<think>internal reasoning with {fake json}</think>
Sure {ignore}! Here is the result:
```json
{
  "summary": "Stable week.",
  "cards": [
    {
      "family": "sleep",
      "title": "Late nights",
      "insight": "Readiness stayed lower after late bedtimes.",
      "evidence": ["f1", " f2 "],
      "action": "Keep a steady bedtime for 7 days.",
      "confidence": "medium"
    }
  ]
}
```
Hope this helps!
''';
      final parsed = AiOutputExtractor.extractReport(validRaw);
      expect(
        parsed,
        const RawAiReport(
          summary: 'Stable week.',
          cards: [
            RawAiCard(
              family: AiMetricFamily.sleep,
              title: 'Late nights',
              insight: 'Readiness stayed lower after late bedtimes.',
              evidence: ['f1', 'f2'],
              action: 'Keep a steady bedtime for 7 days.',
              confidence: AiConfidence.medium,
            ),
          ],
        ),
      );

      const crlfRaw = '```json\r\n{"summary":"CRLF ok.","cards":[]}\r\n```';
      expect(
        AiOutputExtractor.extractReport(crlfRaw),
        const RawAiReport(summary: 'CRLF ok.', cards: []),
      );

      const twoFences = '''
```text
{not valid json}
```
```json
{"summary":"Second fence.","cards":[]}
```
''';
      expect(
        AiOutputExtractor.extractReport(twoFences),
        const RawAiReport(summary: 'Second fence.', cards: []),
      );

      const strayOpenFence = '```json\n{"summary":"Ok","cards":[]}';
      expect(
        AiOutputExtractor.extractReport(strayOpenFence),
        const RawAiReport(summary: 'Ok', cards: []),
      );

      final unclosedThink = AiOutputExtractor.extractReport(
        '<think>none{"summary":"Nothing stood out.","cards":[]}',
      );
      expect(unclosedThink, isNull);
      final validEmpty = AiOutputExtractor.extractReport(
        '{"summary":"Nothing stood out.","cards":[]}',
      );
      expect(
        validEmpty,
        const RawAiReport(summary: 'Nothing stood out.', cards: []),
      );

      const missingConf =
          '{"summary":"Ok","cards":[{"family":"sleep",'
          '"title":"T","insight":"I","evidence":["f1"],"action":"A"}]}';
      const extraCardKey =
          '{"summary":"Ok","cards":[{"family":"sleep",'
          '"title":"T","insight":"I","evidence":["f1"],"action":"A",'
          '"confidence":"medium","extra":1}]}';
      const badFamily =
          '{"summary":"Ok","cards":[{"family":"bogus",'
          '"title":"T","insight":"I","evidence":["f1"],"action":"A",'
          '"confidence":"medium"}]}';
      const badEvidence =
          '{"summary":"Ok","cards":[{"family":"sleep",'
          '"title":"T","insight":"I","evidence":[42],"action":"A",'
          '"confidence":"medium"}]}';
      const badConf =
          '{"summary":"Ok","cards":[{"family":"sleep",'
          '"title":"T","insight":"I","evidence":[],"action":"A",'
          '"confidence":"ultra"}]}';

      for (final bad in [
        '{"summary":"Only summary"}',
        '{"summary":"Ok","cards":[],"extra":1}',
        '{"summary":123,"cards":[]}',
        '[1,2]',
        missingConf,
        extraCardKey,
        badFamily,
        badEvidence,
        badConf,
        '{"summary": "broken',
      ]) {
        expect(AiOutputExtractor.extractReport(bad), isNull, reason: bad);
      }

      final cardStr = _cardJson(family: 'overall', evidence: '[]');
      final exactMax =
          '{"summary":"Ok","cards":[${List.filled(aiMaxRawCards, cardStr).join(',')}]}';
      expect(AiOutputExtractor.extractReport(exactMax)?.cards.length, 64);

      final tooManyCards =
          '{"summary":"Ok","cards":[${List.filled(aiMaxRawCards + 1, cardStr).join(',')}]}';
      expect(AiOutputExtractor.extractReport(tooManyCards), isNull);

      expect(
        AiOutputExtractor.extractReport(
          '{"summary":"Ok","cards":[]}',
          maxBytes: 10,
        ),
        isNull,
      );
      // Multi-byte UTF-8 exceeds byte limit even when char count is smaller.
      expect(
        AiOutputExtractor.extractReport(
          '{"summary":"ááááá","cards":[]}',
          maxBytes: 31,
        ),
        isNull,
      );
    });

    test('clampAtSentence preserves decimals/thousands, CJK, words, and '
        'surrogates', () {
      expect(AiOutputExtractor.clampAtSentence('  short  ', 10), 'short');
      expect(AiOutputExtractor.clampAtSentence('text', 0), '');

      // Does not break inside "9.316" even when index 60 lands after '.'.
      const decText =
          'Sua media subiu para 9.316 ontem em diante com passos estaveis hoje';
      final decCut = AiOutputExtractor.clampAtSentence(decText, 24);
      expect(decCut.endsWith('9.'), isFalse);

      // Cuts cleanly at real sentence boundary without losing it.
      const sentText =
          'Primeiro fato foi 55.4 bpm. Segundo bloco continua longo demais.';
      expect(
        AiOutputExtractor.clampAtSentence(sentText, 40),
        'Primeiro fato foi 55.4 bpm.',
      );

      // CJK terminator and UTF-16 surrogate pair safety.
      const cjkText = '先週より睡眠スコアが安定しています。今日も同じ時間に就寝しましょう。とても長い追加文です。';
      expect(
        AiOutputExtractor.clampAtSentence(cjkText, 30),
        '先週より睡眠スコアが安定しています。',
      );

      final emojiStr = '${'a' * 19}\u{1F600}bbbbb';
      final safeEmoji = AiOutputExtractor.clampAtSentence(emojiStr, 20);
      expect(safeEmoji.length, lessThanOrEqualTo(20));
      expect(() => safeEmoji.runes.toList(), returnsNormally);
    });

    test('extractRewordCard parses standalone card or single-card report', () {
      const standalone = '''
```json
{
  "family": "activity",
  "title": "",
  "insight": "Subir de 9.000 para 10.000 passos na semana.",
  "evidence": ["p1", "p2"],
  "action": "",
  "confidence": "medium"
}
```
''';
      final card = AiOutputExtractor.extractRewordCard(standalone);
      expect(card, isNotNull);
      expect(card!.family, AiMetricFamily.activity);
      expect(card.evidence, const ['p1', 'p2']);

      final wrappedOne =
          '{"summary":"Ok","cards":[${_cardJson(evidence: '["p1"]')}]}';
      expect(AiOutputExtractor.extractRewordCard(wrappedOne)?.evidence, ['p1']);

      const wrappedZero = '{"summary":"Ok","cards":[]}';
      final wrappedTwo =
          '{"summary":"Ok","cards":[${_cardJson(evidence: '["p1"]')},'
          '${_cardJson(evidence: '["p2"]')}]}';
      final wrappedExtraKey =
          '{"summary":"Ok","cards":[${_cardJson()}],"extra":1}';
      final badCardType = _cardJson().replaceFirst('"title":"T"', '"title":1');
      expect(AiOutputExtractor.extractRewordCard(wrappedZero), isNull);
      expect(AiOutputExtractor.extractRewordCard(wrappedTwo), isNull);
      expect(AiOutputExtractor.extractRewordCard(wrappedExtraKey), isNull);
      expect(AiOutputExtractor.extractRewordCard('[1,2]'), isNull);
      expect(AiOutputExtractor.extractRewordCard(badCardType), isNull);

      final longReport = AiOutputExtractor.extractReport(
        '{"summary":"${'word ' * 80}","cards":[${_cardJson(family: 'overall', title: 'T ' * 40, insight: 'I ' * 250, action: 'A ' * 120, confidence: 'high')}]}',
      );
      expect(longReport, isNotNull);
      expect(longReport!.summary.length, lessThanOrEqualTo(aiMaxSummaryChars));
      expect(
        longReport.cards.single.title.length,
        lessThanOrEqualTo(aiMaxTitleChars),
      );
      expect(
        longReport.cards.single.insight.length,
        lessThanOrEqualTo(aiMaxInsightChars),
      );
      expect(
        longReport.cards.single.action.length,
        lessThanOrEqualTo(aiMaxActionChars),
      );
    });
  });
}

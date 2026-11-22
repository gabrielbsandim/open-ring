import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/ai/domain/ai_output_extractor.dart';
import 'package:open_ring/features/ai/domain/ai_report_models.dart';
import 'package:open_ring/features/ai/domain/health_context_models.dart';

String _rt(String v) => String.fromCharCodes(v.codeUnits);

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
      for (final override in <String, Object?>{
        'family': 'invalid',
        'title': 12,
        'insight': false,
        'action': 99,
        'evidenceIds': const <String>[],
        'minEvidenceDays': -1,
        'modelConfidence': 'ultra',
        'coverageConfidence': 'max',
        'shownConfidence': 'ultra',
      }.entries) {
        expect(
          ValidatedAiCard.fromJson({...encoded, override.key: override.value}),
          isNull,
          reason: override.key,
        );
      }
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
    });

    test('non-const value equality and field diffs hold across all DTOs', () {
      RawAiCard mkRaw({
        AiMetricFamily fam = AiMetricFamily.heart,
        String ev = 'f1',
      }) => RawAiCard(
        family: fam,
        title: _rt('T'),
        insight: _rt('I'),
        evidence: [_rt(ev)],
        action: _rt('A'),
        confidence: AiConfidence.medium,
      );
      final rawCardA = mkRaw();
      final rawCardB = mkRaw();
      expect(identical(rawCardA, rawCardB), isFalse);
      expect(rawCardA, rawCardB);
      expect(rawCardA.hashCode, rawCardB.hashCode);
      expect(rawCardA, isNot(mkRaw(fam: AiMetricFamily.sleep)));
      expect(rawCardA, isNot(mkRaw(ev: 'f2')));

      final rptA = RawAiReport(summary: _rt('S'), cards: [rawCardA]);
      final rptB = RawAiReport(summary: _rt('S'), cards: [rawCardB]);
      expect(identical(rptA, rptB), isFalse);
      expect(rptA, rptB);
      expect(rptA.hashCode, rptB.hashCode);
      expect(rptA, isNot(RawAiReport(summary: _rt('X'), cards: [rawCardA])));
      expect(
        rptA,
        isNot(
          RawAiReport(
            summary: _rt('S'),
            cards: [mkRaw(ev: 'f2')],
          ),
        ),
      );

      final dropA = DroppedAiCard(
        card: rawCardA,
        reason: AiCardDropReason.medicalBlocklist,
        detail: _rt('apnea'),
      );
      final dropB = DroppedAiCard(
        card: rawCardB,
        reason: AiCardDropReason.medicalBlocklist,
        detail: _rt('apnea'),
      );
      expect(identical(dropA, dropB), isFalse);
      expect(dropA, dropB);
      expect(dropA.hashCode, dropB.hashCode);
      expect(
        dropA,
        isNot(
          DroppedAiCard(
            card: rawCardA,
            reason: AiCardDropReason.urlOrMarkdown,
            detail: _rt('apnea'),
          ),
        ),
      );
      expect(
        dropA,
        isNot(
          DroppedAiCard(
            card: mkRaw(ev: 'f2'),
            reason: AiCardDropReason.medicalBlocklist,
            detail: _rt('apnea'),
          ),
        ),
      );

      ValidatedAiCard mkVal({int days = 4, String ev = 'f1'}) =>
          ValidatedAiCard(
            family: AiMetricFamily.heart,
            title: _rt('T'),
            insight: _rt('I'),
            evidenceIds: [_rt(ev)],
            action: _rt('A'),
            modelConfidence: AiConfidence.medium,
            coverageConfidence: AiConfidence.low,
            shownConfidence: AiConfidence.low,
            minEvidenceDays: days,
          );
      final vCardA = mkVal();
      final vCardB = mkVal();
      expect(identical(vCardA, vCardB), isFalse);
      expect(vCardA, vCardB);
      expect(vCardA.hashCode, vCardB.hashCode);
      expect(vCardA, isNot(mkVal(days: 5)));
      expect(vCardA, isNot(mkVal(ev: 'f2')));

      final valA = ValidatedAiReport(
        summary: _rt('S'),
        summaryStripped: true,
        cards: [vCardA],
        droppedCards: [dropA],
        totalModelCards: 2,
      );
      final valB = ValidatedAiReport(
        summary: _rt('S'),
        summaryStripped: true,
        cards: [vCardB],
        droppedCards: [dropB],
        totalModelCards: 2,
      );
      expect(identical(valA, valB), isFalse);
      expect(valA, valB);
      expect(valA.hashCode, valB.hashCode);
      expect(valA.keptCount, 1);
      expect(valA.droppedCount, 1);
      expect(
        valA,
        isNot(
          ValidatedAiReport(
            summary: _rt('S'),
            summaryStripped: false,
            cards: [vCardA],
            droppedCards: [dropA],
            totalModelCards: 2,
          ),
        ),
      );
      expect(
        valA,
        isNot(
          ValidatedAiReport(
            summary: _rt('S'),
            summaryStripped: true,
            cards: [mkVal(ev: 'f2')],
            droppedCards: [dropA],
            totalModelCards: 2,
          ),
        ),
      );
      expect(
        valA,
        isNot(
          ValidatedAiReport(
            summary: _rt('S'),
            summaryStripped: true,
            cards: [vCardA],
            droppedCards: [
              DroppedAiCard(
                card: rawCardA,
                reason: AiCardDropReason.emptyText,
                detail: _rt('title'),
              ),
            ],
            totalModelCards: 2,
          ),
        ),
      );

      final spanA = AiUnverifiedSpan(start: 3, end: 7, raw: _rt('12.5'));
      final spanB = AiUnverifiedSpan(start: 3, end: 7, raw: _rt('12.5'));
      expect(identical(spanA, spanB), isFalse);
      expect(spanA, spanB);
      expect(spanA.hashCode, spanB.hashCode);
      expect(
        spanA,
        isNot(AiUnverifiedSpan(start: 4, end: 7, raw: _rt('12.5'))),
      );
      expect(
        spanA,
        isNot(AiUnverifiedSpan(start: 3, end: 7, raw: _rt('13.0'))),
      );

      final accA = AiRewordAccepted(
        text: _rt('Keep 9.000'),
        evidenceIds: [_rt('p1')],
      );
      final accB = AiRewordAccepted(
        text: _rt('Keep 9.000'),
        evidenceIds: [_rt('p1')],
      );
      expect(identical(accA, accB), isFalse);
      expect(accA, accB);
      expect(accA.hashCode, accB.hashCode);
      expect(
        accA,
        isNot(AiRewordAccepted(text: _rt('Other'), evidenceIds: [_rt('p1')])),
      );
      expect(
        accA,
        isNot(
          AiRewordAccepted(text: _rt('Keep 9.000'), evidenceIds: [_rt('p2')]),
        ),
      );

      final drpA = AiRewordDropped(
        reason: AiCardDropReason.unverifiedNumber,
        detail: _rt('11.000'),
      );
      final drpB = AiRewordDropped(
        reason: AiCardDropReason.unverifiedNumber,
        detail: _rt('11.000'),
      );
      expect(identical(drpA, drpB), isFalse);
      expect(drpA, drpB);
      expect(drpA.hashCode, drpB.hashCode);
      expect(
        drpA,
        isNot(
          AiRewordDropped(
            reason: AiCardDropReason.medicalBlocklist,
            detail: _rt('11.000'),
          ),
        ),
      );
      expect(
        drpA,
        isNot(
          AiRewordDropped(
            reason: AiCardDropReason.unverifiedNumber,
            detail: _rt('12.000'),
          ),
        ),
      );
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

      final okObj = '${'{"k":' * 16}1${'}' * 16}';
      expect(AiOutputExtractor.extractFirstJsonObject(okObj), okObj);
      final okArr = '{"k":${'[' * 15}1${']' * 15}}';
      expect(AiOutputExtractor.extractFirstJsonObject(okArr), okArr);

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

      const fencedInThink =
          '<think>\n```json\n{"summary":"Leaked","cards":[]}\n```\n</think>\n'
          '{"summary":"Real","cards":[]}';
      expect(
        AiOutputExtractor.extractReport(fencedInThink),
        const RawAiReport(summary: 'Real', cards: []),
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

      // Does not break inside "9.316" when index 24 falls mid-number.
      const decText =
          'Sua media subiu para 9.316 ontem em diante com passos estaveis hoje';
      final decCut = AiOutputExtractor.clampAtSentence(decText, 24);
      expect(decCut, 'Sua media subiu para');

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
      expect(safeEmoji, 'a' * 19);
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

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/features/ai/domain/ai_config.dart';
import 'package:open_ring/features/ai/domain/ai_consent_scope.dart';
import 'package:open_ring/features/ai/domain/ai_report_models.dart';
import 'package:open_ring/features/ai/domain/goal_reword.dart';
import 'package:open_ring/features/ai/domain/health_context_models.dart';

const _steps = LeverChange(kind: LeverKind.steps, from: 9000, to: 10000);

BuiltAiPayload _payload({
  String lang = 'pt-BR',
  LeverChange? change = _steps,
  int? fit = 3,
  int? levers = 3,
  int? pauseDays,
}) => buildGoalRewordPayload(
  replyLanguage: lang,
  rule: 8,
  head: 'Uma mudança proposta',
  line: 'A semana coube. Este é o próximo passo na ordem do plano.',
  change: change,
  changeText: change == null ? null : 'Passos por dia: de 9.000 para 10.000',
  fit: fit,
  levers: levers,
  pauseDays: pauseDays,
)!;

String _answer(
  String insight, {
  List<String>? evidence,
  String family = 'overall',
}) => jsonEncode({
  'summary': '',
  'cards': [
    {
      'family': family,
      'title': '',
      'insight': insight,
      'evidence': evidence ?? ['plan.from', 'plan.to', 'plan.fit'],
      'action': '',
      'confidence': 'high',
    },
  ],
});

void main() {
  group('buildGoalRewordPayload', () {
    test('sends only the decision, its numbers and the reply language', () {
      final payload = _payload();
      expect(payload.contextMap.keys, {'reply_language', 'plan', 'facts'});
      expect(payload.contextMap['plan'], {
        'rule': 8,
        'decision': 'Uma mudança proposta',
        'line': 'A semana coube. Este é o próximo passo na ordem do plano.',
        'change': 'Passos por dia: de 9.000 para 10.000',
      });
      expect(
        {for (final f in payload.facts) f.id: f.value},
        {'plan.fit': 3, 'plan.levers': 3, 'plan.from': 9000, 'plan.to': 10000},
      );
      expect(payload.facts.map((f) => f.unit).toSet(), {
        AiFactUnit.levers,
        AiFactUnit.steps,
      });
      expect(payload.systemPrompt, aiGoalRewordPromptV1);
      expect(payload.userMessage, startsWith('Task: goal_review_reword.\n'));
      expect(payload.userMessage, endsWith(payload.canonicalContextJson));
    });

    test('the goals category is what a consent must cover', () {
      expect(aiPayloadCategories(_payload().contextMap), {
        AiDataCategory.goals,
      });
    });

    test('a clock lever change gets no payload', () {
      for (final kind in [LeverKind.sleepWindow, LeverKind.wakeTime]) {
        final payload = buildGoalRewordPayload(
          replyLanguage: 'en',
          rule: 8,
          head: 'h',
          line: 'l',
          change: LeverChange(kind: kind, from: 600, to: 630),
          fit: 3,
          levers: 3,
        );
        expect(payload, isNull, reason: kind.name);
      }
    });

    test('no fact to cite gets no payload', () {
      final payload = buildGoalRewordPayload(
        replyLanguage: 'en',
        rule: 1,
        head: 'The goal ends',
        line: 'A protection fired.',
      );
      expect(payload, isNull);
    });

    test('a pause sends its days, a new lever only its target', () {
      final pause = _payload(change: null, pauseDays: 14);
      expect(pause.facts.map((f) => f.id), [
        'plan.fit',
        'plan.levers',
        'plan.pause',
      ]);
      final added = _payload(
        change: const LeverChange(
          kind: LeverKind.strengthDays,
          from: null,
          to: 2,
        ),
      );
      expect(
        added.facts.where((f) => f.id.startsWith('plan.t')).single.unit,
        AiFactUnit.days,
      );
      expect(added.facts.any((f) => f.id == 'plan.from'), isFalse);
    });

    test('the cache key follows the decision and the language', () {
      expect(_payload().cacheKey, _payload().cacheKey);
      expect(_payload().cacheKey, isNot(_payload(lang: 'en').cacheKey));
      expect(_payload().cacheKey, isNot(_payload(fit: 2).cacheKey));
    });
  });

  group('readGoalReword', () {
    test('keeps a rewording whose numbers are the rule facts', () {
      const text =
          'As 3 alavancas couberam. Os passos sobem de 9.000 para 10.000 por dia.';
      expect(
        readGoalReword(_answer(text), _payload()),
        const AiRewordAccepted(
          text: text,
          evidenceIds: ['plan.from', 'plan.to', 'plan.fit', 'plan.levers'],
        ),
      );
    });

    test('drops a rewording with a number not in the rule', () {
      final result = readGoalReword(
        _answer('Os passos sobem para 11.000 por dia.'),
        _payload(),
      );
      expect(
        result,
        const AiRewordDropped(
          reason: AiCardDropReason.unverifiedNumber,
          detail: '11.000',
        ),
      );
    });

    test('a rule number may be written without being cited', () {
      final result = readGoalReword(
        _answer('Os passos sobem para 10.000.', evidence: ['plan.fit']),
        _payload(),
      );
      expect(result, isA<AiRewordAccepted>());
    });

    test('drops a rewording citing a fact the rule does not have', () {
      final result = readGoalReword(
        _answer('Os passos sobem.', evidence: ['sleep_avg']),
        _payload(),
      );
      expect(result, isA<AiRewordDropped>());
    });

    test('any model family reads as overall', () {
      final result = readGoalReword(
        _answer('Os passos sobem de 9.000 para 10.000.', family: 'sleep'),
        _payload(),
      );
      expect(result, isA<AiRewordAccepted>());
    });

    test('an answer with no card is unreadable', () {
      expect(readGoalReword('not json', _payload()), isNull);
    });
  });
}

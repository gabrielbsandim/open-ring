import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/ai/domain/ai_reading.dart';
import 'package:open_ring/features/ai/domain/ai_report_models.dart';
import 'package:open_ring/features/ai/domain/health_context_models.dart';

const _card = ValidatedAiCard(
  family: AiMetricFamily.sleep,
  title: 'Steady sleep',
  insight: 'Sleep stayed close to your usual amount.',
  evidenceIds: ['f.sleepMin.avg'],
  action: 'Keep a regular bedtime.',
  modelConfidence: AiConfidence.high,
  coverageConfidence: AiConfidence.medium,
  shownConfidence: AiConfidence.medium,
  minEvidenceDays: 7,
);

void main() {
  test('parses summary, cards and the facts snapshot', () {
    final reading = AiReading.parse(
      jsonEncode({
        'summary': 'A calm week.',
        'cards': [_card.toJson()],
        'facts': [
          {
            'id': 'f.sleepMin.avg',
            'label': 'Sleep duration, window mean',
            'value': 431.5,
            'unit': 'min',
            'days': 7,
            'family': 'sleep',
          },
          {'id': 'f.broken', 'value': 'x'},
        ],
      }),
    );

    expect(reading.summary, 'A calm week.');
    expect(reading.cards, [_card]);
    expect(reading.facts.keys, ['f.sleepMin.avg']);
    expect(reading.facts['f.sleepMin.avg'], (
      label: 'Sleep duration, window mean',
      value: 431.5,
      unit: 'min',
      days: 7,
    ));
  });

  test('a report stored before the snapshot parses with no facts', () {
    final reading = AiReading.parse(
      jsonEncode({
        'summary': 'Old shape.',
        'cards': [_card.toJson()],
      }),
    );

    expect(reading.cards, [_card]);
    expect(reading.facts, isEmpty);
  });

  test('null, bad JSON or a non object give an empty reading', () {
    for (final raw in [null, '{not json', '[1, 2]', '"text"']) {
      final reading = AiReading.parse(raw);
      expect(reading.summary, isEmpty, reason: '$raw');
      expect(reading.cards, isEmpty, reason: '$raw');
      expect(reading.facts, isEmpty, reason: '$raw');
    }
  });

  test('a malformed card is skipped and the rest are kept', () {
    final reading = AiReading.parse(
      jsonEncode({
        'cards': [
          {'title': 'no family'},
          _card.toJson(),
          'text',
        ],
      }),
    );

    expect(reading.cards, [_card]);
  });
}

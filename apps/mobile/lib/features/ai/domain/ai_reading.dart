import 'dart:convert';

import 'package:meta/meta.dart';
import 'package:open_ring/features/ai/domain/ai_report.dart';
import 'package:open_ring/features/ai/domain/ai_report_models.dart';

typedef AiFactSnapshot = ({String label, double value, String unit, int days});

/// The stored `cardsJson` of a report. Reports written before the facts
/// snapshot existed parse with no facts, and their chips show the id.
@immutable
final class AiReading {
  const new({this.summary = '', this.cards = const [], this.facts = const {}});

  factory fromReport(AiReport report) => AiReading.parse(report.cardsJson);

  factory parse(String? json) {
    final Object? map;
    try {
      map = jsonDecode(json ?? '');
    } on FormatException {
      return const AiReading();
    }
    if (map is! Map<String, Object?>) return const AiReading();
    final summary = map['summary'];
    return AiReading(
      summary: summary is String ? summary : '',
      cards: [
        for (final raw in _list(map['cards']))
          if (raw is Map<String, Object?>) ?ValidatedAiCard.fromJson(raw),
      ],
      facts: {
        for (final raw in _list(map['facts']))
          if (raw case {
            'id': final String id,
            'label': final String label,
            'value': final num value,
            'unit': final String unit,
            'days': final int days,
          })
            id: (label: label, value: value.toDouble(), unit: unit, days: days),
      },
    );
  }

  final String summary;
  final List<ValidatedAiCard> cards;
  final Map<String, AiFactSnapshot> facts;
}

List<Object?> _list(Object? raw) => raw is List<Object?> ? raw : const [];

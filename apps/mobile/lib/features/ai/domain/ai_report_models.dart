import 'package:meta/meta.dart';
import 'package:open_ring/features/ai/domain/health_context_models.dart';

const int aiMaxReportCards = 6;
const int aiMaxEvidenceIds = 6;
const int aiMaxSummaryChars = 300;
const int aiMaxTitleChars = 60;
const int aiMaxInsightChars = 400;
const int aiMaxActionChars = 200;
const int aiMaxRawCards = 64;
const int aiMaxJsonDepth = 16;

enum AiConfidence {
  low(0),
  medium(1),
  high(2);

  new(this.rank);
  final int rank;

  static AiConfidence minOf(AiConfidence a, AiConfidence b) =>
      a.rank <= b.rank ? a : b;

  static AiConfidence? parseWire(Object? raw) {
    if (raw is! String) return null;
    final norm = raw.trim().toLowerCase();
    for (final v in values) {
      if (v.name == norm) return v;
    }
    return null;
  }
}

enum AiCardDropReason {
  evidenceEmptyOrTooMany,
  unknownFactId,
  familyMismatch,
  unverifiedNumber,
  vitalUnitInAction,
  disallowedActionNumber,
  medicalBlocklist,
  urlOrMarkdown,
  emptyText,
  excessCardCap,
}

@immutable
final class RawAiCard {
  const new({
    required this.family,
    required this.title,
    required this.insight,
    required this.evidence,
    required this.action,
    required this.confidence,
  });

  final AiMetricFamily family;
  final String title;
  final String insight;
  final List<String> evidence;
  final String action;
  final AiConfidence confidence;

  @override
  bool operator ==(Object other) =>
      other is RawAiCard &&
      family == other.family &&
      title == other.title &&
      insight == other.insight &&
      _listEquals(evidence, other.evidence) &&
      action == other.action &&
      confidence == other.confidence;

  @override
  int get hashCode => Object.hash(
    family,
    title,
    insight,
    Object.hashAll(evidence),
    action,
    confidence,
  );
}

@immutable
final class RawAiReport {
  const new({required this.summary, required this.cards});

  final String summary;
  final List<RawAiCard> cards;

  @override
  bool operator ==(Object other) =>
      other is RawAiReport &&
      summary == other.summary &&
      _listEquals(cards, other.cards);

  @override
  int get hashCode => Object.hash(summary, Object.hashAll(cards));
}

@immutable
final class ValidatedAiCard {
  const new({
    required this.family,
    required this.title,
    required this.insight,
    required this.evidenceIds,
    required this.action,
    required this.modelConfidence,
    required this.coverageConfidence,
    required this.shownConfidence,
    required this.minEvidenceDays,
  });

  final AiMetricFamily family;
  final String title;
  final String insight;
  final List<String> evidenceIds;
  final String action;
  final AiConfidence modelConfidence;
  final AiConfidence coverageConfidence;
  final AiConfidence shownConfidence;
  final int minEvidenceDays;

  Map<String, Object?> toJson() => {
    'family': family.name,
    'title': title,
    'insight': insight,
    'evidenceIds': evidenceIds,
    'action': action,
    'modelConfidence': modelConfidence.name,
    'coverageConfidence': coverageConfidence.name,
    'shownConfidence': shownConfidence.name,
    'minEvidenceDays': minEvidenceDays,
  };

  static ValidatedAiCard? fromJson(Map<String, Object?> map) {
    final fam = parseAiMetricFamily(map['family']);
    final title = map['title'];
    final insight = map['insight'];
    final ev = _parseEvidence(map['evidenceIds']);
    final action = map['action'];
    final mc = AiConfidence.parseWire(map['modelConfidence']);
    final cc = AiConfidence.parseWire(map['coverageConfidence']);
    final sc = AiConfidence.parseWire(map['shownConfidence']);
    final days = map['minEvidenceDays'];
    if (fam == null || title is! String || insight is! String || ev == null) {
      return null;
    }
    if (action is! String || mc == null || cc == null || sc == null) {
      return null;
    }
    if (days is! int || days < 0) return null;
    return ValidatedAiCard(
      family: fam,
      title: title,
      insight: insight,
      evidenceIds: ev,
      action: action,
      modelConfidence: mc,
      coverageConfidence: cc,
      shownConfidence: sc,
      minEvidenceDays: days,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ValidatedAiCard &&
      family == other.family &&
      title == other.title &&
      insight == other.insight &&
      _listEquals(evidenceIds, other.evidenceIds) &&
      action == other.action &&
      modelConfidence == other.modelConfidence &&
      coverageConfidence == other.coverageConfidence &&
      shownConfidence == other.shownConfidence &&
      minEvidenceDays == other.minEvidenceDays;

  @override
  int get hashCode => Object.hash(
    family,
    title,
    insight,
    Object.hashAll(evidenceIds),
    action,
    modelConfidence,
    coverageConfidence,
    shownConfidence,
    minEvidenceDays,
  );
}

@immutable
final class DroppedAiCard {
  const new({required this.card, required this.reason, required this.detail});

  final RawAiCard card;
  final AiCardDropReason reason;
  final String detail;

  @override
  bool operator ==(Object other) =>
      other is DroppedAiCard &&
      card == other.card &&
      reason == other.reason &&
      detail == other.detail;

  @override
  int get hashCode => Object.hash(card, reason, detail);
}

@immutable
final class ValidatedAiReport {
  const new({
    required this.summary,
    required this.summaryStripped,
    required this.cards,
    required this.droppedCards,
    required this.totalModelCards,
  });

  final String summary;
  final bool summaryStripped;
  final List<ValidatedAiCard> cards;
  final List<DroppedAiCard> droppedCards;
  final int totalModelCards;

  int get keptCount => cards.length;
  int get droppedCount => droppedCards.length;

  @override
  bool operator ==(Object other) =>
      other is ValidatedAiReport &&
      summary == other.summary &&
      summaryStripped == other.summaryStripped &&
      _listEquals(cards, other.cards) &&
      _listEquals(droppedCards, other.droppedCards) &&
      totalModelCards == other.totalModelCards;

  @override
  int get hashCode => Object.hash(
    summary,
    summaryStripped,
    Object.hashAll(cards),
    Object.hashAll(droppedCards),
    totalModelCards,
  );
}

@immutable
final class AiUnverifiedSpan {
  const new({required this.start, required this.end, required this.raw});

  final int start;
  final int end;
  final String raw;

  @override
  bool operator ==(Object other) =>
      other is AiUnverifiedSpan &&
      start == other.start &&
      end == other.end &&
      raw == other.raw;

  @override
  int get hashCode => Object.hash(start, end, raw);
}

sealed class AiRewordResult {
  const new();
}

@immutable
final class AiRewordAccepted extends AiRewordResult {
  const new({required this.text, required this.evidenceIds});

  final String text;
  final List<String> evidenceIds;

  @override
  bool operator ==(Object other) =>
      other is AiRewordAccepted &&
      text == other.text &&
      _listEquals(evidenceIds, other.evidenceIds);

  @override
  int get hashCode => Object.hash(text, Object.hashAll(evidenceIds));
}

@immutable
final class AiRewordDropped extends AiRewordResult {
  const new({required this.reason, required this.detail});

  final AiCardDropReason reason;
  final String detail;

  @override
  bool operator ==(Object other) =>
      other is AiRewordDropped &&
      reason == other.reason &&
      detail == other.detail;

  @override
  int get hashCode => Object.hash(reason, detail);
}

AiMetricFamily? parseAiMetricFamily(Object? raw) {
  if (raw is! String) return null;
  final norm = raw.trim().toLowerCase();
  for (final v in AiMetricFamily.values) {
    if (v.name == norm) return v;
  }
  return null;
}

List<String>? _parseEvidence(Object? raw) {
  if (raw is! List<Object?>) return null;
  if (raw.isEmpty || raw.length > aiMaxEvidenceIds) return null;
  final out = <String>[];
  for (final item in raw) {
    if (item is! String) return null;
    final trimmed = item.trim();
    if (trimmed.isEmpty) return null;
    out.add(trimmed);
  }
  return List.unmodifiable(out);
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

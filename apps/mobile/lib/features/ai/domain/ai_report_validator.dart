import 'dart:math' as math;

import 'package:open_ring/features/ai/domain/ai_report_models.dart';
import 'package:open_ring/features/ai/domain/ai_safety_lexicon.dart';
import 'package:open_ring/features/ai/domain/health_context_models.dart';

typedef _NumTok = ({int s, int e, String raw, String after, double? val});
typedef _Drop = (AiCardDropReason reason, String detail);

const _pow10 = [1.0, 10.0, 100.0, 1000.0, 10000.0];
const _alpha = r'\p{sc=Latin}\p{sc=Cyrillic}';

final _numOrClock = RegExp(
  r'(?:(?<![\d.:,])(?:[01]?\d|2[0-3]):[0-5]\d(?![\d:])'
  '|(?<![\\d$_alpha])[$_alpha]+\\d+(?:[.,]\\d+)*(?!\\d|:[0-5]\\d(?![\\d:]))'
  r'|(\d+(?:[.,\u00a0\u202f]\d+)*))',
  unicode: true,
);
final _spaceThous = RegExp(
  r'^[1-9]\d{0,2}(?:[\u00a0\u202f]\d{3})+(?:[.,]\d+)?$',
);
final _spaceChar = RegExp(r'[\u00a0\u202f]');
final _dotThousComma = RegExp(r'^[1-9]\d{0,2}(?:\.\d{3})+,\d+$');
final _commaThousDot = RegExp(r'^[1-9]\d{0,2}(?:,\d{3})+\.\d+$');

abstract final class AiReportValidator {
  static ValidatedAiReport validateReport(
    RawAiReport report, {
    required List<HealthFact> facts,
    required String replyLanguage,
    int windowDays = 14,
    int windowWeeks = 0,
  }) =>
      _Validator(facts, replyLanguage, windowDays, windowWeeks).report(report);

  static ValidatedAiReport validateForPayload(
    RawAiReport report,
    BuiltAiPayload payload,
  ) {
    final langRaw = payload.contextMap['reply_language'];
    final win = payload.contextMap['window'];
    final days = win is Map<Object?, Object?> ? win['days'] : null;
    final weeks = win is Map<Object?, Object?> ? win['weeks'] : null;
    return validateReport(
      report,
      facts: payload.facts,
      replyLanguage: langRaw is String ? langRaw : 'en',
      windowDays: days is int ? days : 14,
      windowWeeks: weeks is int ? weeks : 0,
    );
  }

  static AiRewordResult validateReword(
    RawAiCard card, {
    required List<HealthFact> ruleFacts,
    required String replyLanguage,
    int windowDays = 14,
    int windowWeeks = 0,
    bool exactNumbers = false,
  }) => _Validator(
    ruleFacts,
    replyLanguage,
    windowDays,
    windowWeeks,
    exact: exactNumbers,
  ).reword(card);

  static List<AiUnverifiedSpan> findUnverifiedSpans(
    String rawText, {
    required List<HealthFact> facts,
    required String replyLanguage,
    int windowDays = 14,
    int windowWeeks = 0,
  }) =>
      _Validator(facts, replyLanguage, windowDays, windowWeeks).spans(rawText);
}

final class _Validator {
  new(
    this.facts,
    this.replyLanguage,
    this.windowDays,
    this.windowWeeks, {
    this.exact = false,
  }) : commaDec = AiSafetyLexicon.usesCommaDecimal(replyLanguage);

  final List<HealthFact> facts;
  final String replyLanguage;
  final bool commaDec;
  final int windowDays;
  final int windowWeeks;

  /// Only a value equal to a fact passes: no rounding, derived or period
  /// allowance.
  final bool exact;

  static bool _near(double a, double b) => (a - b).abs() <= 1e-9;

  ValidatedAiReport report(RawAiReport report) {
    final factById = {for (final f in facts) f.id: f};
    final kept = <ValidatedAiCard>[];
    final dropped = <DroppedAiCard>[];
    for (final card in report.cards) {
      final (validated, drop) = _validateCard(
        card,
        factById,
        requireTitle: true,
      );
      if (drop != null) {
        dropped.add(
          DroppedAiCard(card: card, reason: drop.$1, detail: drop.$2),
        );
        continue;
      }
      if (kept.length >= aiMaxReportCards) {
        dropped.add(
          DroppedAiCard(
            card: card,
            reason: AiCardDropReason.excessCardCap,
            detail: '${kept.length + 1}/$aiMaxReportCards',
          ),
        );
        continue;
      }
      kept.add(validated!);
    }
    final summary = report.summary.trim();
    final strip = summary.isNotEmpty && _summaryShouldStrip(summary);
    return ValidatedAiReport(
      summary: strip ? '' : summary,
      summaryStripped: strip,
      cards: List.unmodifiable(kept),
      droppedCards: List.unmodifiable(dropped),
      totalModelCards: report.cards.length,
    );
  }

  AiRewordResult reword(RawAiCard card) {
    final factById = {for (final f in facts) f.id: f};
    final (validated, drop) = _validateCard(
      card,
      factById,
      requireTitle: false,
    );
    if (drop != null) return AiRewordDropped(reason: drop.$1, detail: drop.$2);
    return AiRewordAccepted(
      text: validated!.insight,
      evidenceIds: validated.evidenceIds,
    );
  }

  List<AiUnverifiedSpan> spans(String rawText) => List.unmodifiable([
    for (final n in _scanNumbers(rawText))
      if (!_isNumberVerified(n, facts))
        AiUnverifiedSpan(start: n.s, end: n.e, raw: n.raw),
  ]);

  (ValidatedAiCard?, _Drop?) _validateCard(
    RawAiCard card,
    Map<String, HealthFact> factById, {
    required bool requireTitle,
  }) {
    final title = card.title.trim();
    final insight = card.insight.trim();
    final action = card.action.trim();
    if (requireTitle && title.isEmpty) {
      return (null, const (AiCardDropReason.emptyText, 'title'));
    }
    if (insight.isEmpty) {
      return (null, const (AiCardDropReason.emptyText, 'insight'));
    }
    if (card.evidence.isEmpty || card.evidence.length > aiMaxEvidenceIds) {
      return (
        null,
        (AiCardDropReason.evidenceEmptyOrTooMany, '${card.evidence.length}'),
      );
    }

    final cited = <HealthFact>[];
    final evidenceIds = <String>[];
    final seenIds = <String>{};
    for (final rawId in card.evidence) {
      final id = rawId.trim();
      final fact = factById[id];
      if (fact == null) return (null, (AiCardDropReason.unknownFactId, id));
      if (!seenIds.add(id)) continue;
      cited.add(fact);
      evidenceIds.add(id);
    }

    final famOk =
        card.family == AiMetricFamily.overall ||
        cited.any((f) => f.family == card.family);
    if (!famOk) {
      return (null, (AiCardDropReason.familyMismatch, card.family.name));
    }

    final drop =
        _checkTextNumbers([title, insight], cited) ??
        _checkActionNumbers(action) ??
        _checkSafety([title, insight, action]);
    if (drop != null) return (null, drop);

    final rawMin = cited.map((f) => f.days).reduce(math.min);
    final minDays = rawMin < 0 ? 0 : rawMin;
    final cov = _coverageConfidence(minDays);
    return (
      ValidatedAiCard(
        family: card.family,
        title: title,
        insight: insight,
        evidenceIds: List.unmodifiable(evidenceIds),
        action: action,
        modelConfidence: card.confidence,
        coverageConfidence: cov,
        shownConfidence: AiConfidence.minOf(card.confidence, cov),
        minEvidenceDays: minDays,
      ),
      null,
    );
  }

  _Drop? _checkTextNumbers(List<String> fields, List<HealthFact> cited) {
    for (final field in fields) {
      for (final n in _scanNumbers(field)) {
        if (!_isNumberVerified(n, cited)) {
          return (AiCardDropReason.unverifiedNumber, n.raw);
        }
      }
    }
    return null;
  }

  _Drop? _checkActionNumbers(String action) {
    for (final n in _scanNumbers(action)) {
      final bad = AiSafetyLexicon.findForbiddenVitalUnitAfter(n.after);
      if (bad != null) {
        return (AiCardDropReason.vitalUnitInAction, '${n.raw} $bad');
      }
      final unitOk =
          n.val != null &&
          AiSafetyLexicon.hasAllowedActionUnitAfter(n.after, replyLanguage);
      if (!unitOk) return (AiCardDropReason.disallowedActionNumber, n.raw);
    }
    return null;
  }

  _Drop? _checkSafety(List<String> fields) {
    for (final field in fields) {
      final term = AiSafetyLexicon.findMedicalTerm(field, replyLanguage);
      if (term != null) return (AiCardDropReason.medicalBlocklist, term);
      if (AiSafetyLexicon.containsUrlOrMarkdownLink(field)) {
        return const (AiCardDropReason.urlOrMarkdown, 'url_or_markdown');
      }
    }
    return null;
  }

  bool _summaryShouldStrip(String summary) {
    if (AiSafetyLexicon.findCausalPhrase(summary, replyLanguage) != null ||
        AiSafetyLexicon.findMedicalTerm(summary, replyLanguage) != null ||
        AiSafetyLexicon.containsUrlOrMarkdownLink(summary)) {
      return true;
    }
    for (final n in _scanNumbers(summary)) {
      if (!_isNumberVerified(n, facts)) return true;
    }
    return false;
  }

  static AiConfidence _coverageConfidence(int minDays) {
    if (minDays >= 10) return AiConfidence.high;
    if (minDays >= 5) return AiConfidence.medium;
    return AiConfidence.low;
  }

  Iterable<_NumTok> _scanNumbers(String text) sync* {
    for (final m in _numOrClock.allMatches(text)) {
      final raw = m.group(1);
      if (raw == null) continue;
      final after = text.substring(m.end, math.min(text.length, m.end + 32));
      yield (s: m.start, e: m.end, raw: raw, after: after, val: _parseNum(raw));
    }
  }

  double? _parseNum(String raw) {
    if (_spaceChar.hasMatch(raw)) {
      return _spaceThous.hasMatch(raw)
          ? double.tryParse(raw.replaceAll(_spaceChar, '').replaceAll(',', '.'))
          : null;
    }
    final hasDot = raw.contains('.');
    final hasComma = raw.contains(',');
    if (!hasDot && !hasComma) return double.tryParse(raw);
    if (hasDot && hasComma) return _parseMixedSep(raw);
    return hasDot
        ? _parseSingleSep(raw, '.', thousands: commaDec)
        : _parseSingleSep(raw, ',', thousands: !commaDec);
  }

  static double? _parseMixedSep(String raw) {
    if (_dotThousComma.hasMatch(raw)) {
      return double.tryParse(raw.replaceAll('.', '').replaceFirst(',', '.'));
    }
    if (_commaThousDot.hasMatch(raw)) {
      return double.tryParse(raw.replaceAll(',', ''));
    }
    return null;
  }

  static double? _parseSingleSep(
    String raw,
    String sep, {
    required bool thousands,
  }) {
    final parts = raw.split(sep);
    final leadOk =
        parts[0].isNotEmpty &&
        parts[0].length <= 3 &&
        parts[0].codeUnitAt(0) != 0x30;
    if (parts.length > 2) {
      final tailOk = parts.skip(1).every((p) => p.length == 3);
      return thousands && leadOk && tailOk
          ? double.tryParse(raw.replaceAll(sep, ''))
          : null;
    }
    if (thousands && leadOk && parts[1].length == 3) {
      return double.tryParse(parts[0] + parts[1]);
    }
    return double.tryParse(sep == ',' ? '${parts[0]}.${parts[1]}' : raw);
  }

  bool _isNumberVerified(_NumTok n, List<HealthFact> pool) {
    final x = n.val;
    if (x == null || !x.isFinite) return false;
    if (exact) return pool.any((f) => _near(x, f.value));
    for (final f in pool) {
      if (_matchesFact(x, f.value)) return true;
    }
    if (_matchesDerived(x, pool)) return true;
    final whole = x.roundToDouble();
    if (!_near(x, whole)) return false;
    if (!AiSafetyLexicon.hasPeriodUnitAfter(n.after, replyLanguage)) {
      return false;
    }
    final v = whole.toInt();
    if (v >= 1 && v <= math.max(windowDays, 0)) return true;
    if (const [7, 12, 14, 28].contains(v)) return true;
    return windowWeeks > 0 && v == windowWeeks;
  }

  static bool _matchesFact(double x, double rawValue) {
    if (!rawValue.isFinite) return false;
    final fv = rawValue.abs();
    final dp = _decimalPlaces(fv);
    return _near(x, fv) ||
        _near(x, _roundDp(fv, dp)) ||
        _near(x, fv.roundToDouble()) ||
        (dp >= 2 && _near(x, _roundDp(fv, 1)));
  }

  static bool _matchesDerived(double x, List<HealthFact> pool) {
    for (var i = 0; i < pool.length; i++) {
      final a = pool[i].value;
      if (!a.isFinite) continue;
      final dpA = _decimalPlaces(a);
      for (var j = 0; j < pool.length; j++) {
        if (i == j || pool[i].id == pool[j].id) continue;
        final b = pool[j].value;
        if (!b.isFinite) continue;
        final d = (a - b).abs();
        final unit = 1 / _pow10[math.max(dpA, _decimalPlaces(b))];
        if (_closeOrRound(x, d, math.max(unit, 0.02 * d))) return true;
        if (b.abs() <= 1e-9) continue;
        final pc = (d / b.abs()) * 100;
        if (_closeOrRound(x, pc, math.max<num>(1, 0.02 * pc))) return true;
      }
    }
    return false;
  }

  static bool _closeOrRound(double x, double target, num relTol) =>
      (x - target).abs() <= relTol + 1e-9 || _near(x, target.roundToDouble());

  static int _decimalPlaces(double v) {
    final abs = v.abs();
    for (var dp = 0; dp < _pow10.length; dp++) {
      if ((abs - _roundDp(abs, dp)).abs() <= 1e-6) return dp;
    }
    return _pow10.length - 1;
  }

  static double _roundDp(double v, int dp) => dp == 0
      ? v.roundToDouble()
      : (v * _pow10[dp]).roundToDouble() / _pow10[dp];
}

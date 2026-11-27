import 'dart:convert';

import 'package:open_ring/features/ai/domain/ai_report_models.dart';
import 'package:open_ring/features/ai/domain/ai_wire_types.dart';
import 'package:open_ring/features/ai/domain/openai_wire_codec.dart';

abstract final class AiOutputExtractor {
  static final RegExp _fencePattern = RegExp(r'```[^\r\n]*\r?\n([\s\S]*?)```');
  static final RegExp _strayFenceLine = RegExp(
    r'^\s*```[^\r\n]*$',
    multiLine: true,
  );

  static RawAiReport? extractReport(
    String raw, {
    int maxBytes = aiMaxResponseBytes,
  }) {
    final decoded = _decodeRootObject(raw, maxBytes: maxBytes);
    if (decoded == null || decoded.length != 2) return null;
    final summary = decoded['summary'];
    final rawCards = decoded['cards'];
    if (summary is! String || rawCards is! List<Object?>) return null;
    if (rawCards.length > aiMaxRawCards) return null;
    final cards = <RawAiCard>[];
    for (final entry in rawCards) {
      final parsed = _parseCard(entry);
      if (parsed == null) return null;
      cards.add(parsed);
    }
    return RawAiReport(
      summary: clampAtSentence(summary, aiMaxSummaryChars),
      cards: List.unmodifiable(cards),
    );
  }

  static RawAiCard? extractRewordCard(
    String raw, {
    int maxBytes = aiMaxResponseBytes,
  }) {
    final decoded = _decodeRootObject(raw, maxBytes: maxBytes);
    if (decoded == null) return null;
    final direct = _parseCard(decoded);
    if (direct != null) return direct;
    if (decoded.length != 2) return null;
    final summary = decoded['summary'];
    final rawCards = decoded['cards'];
    if (summary is! String || rawCards is! List<Object?>) return null;
    if (rawCards.length != 1) return null;
    return _parseCard(rawCards.single);
  }

  static String? extractFirstJsonObject(
    String text, {
    int maxDepth = aiMaxJsonDepth,
  }) {
    final start = text.indexOf('{');
    if (start < 0 || maxDepth < 1) return null;
    final stack = <int>[];
    var inStr = false;
    var esc = false;
    for (var i = start; i < text.length; i++) {
      final ch = text.codeUnitAt(i);
      if (esc) {
        esc = false;
        continue;
      }
      if (inStr && ch == 0x5c) {
        esc = true;
        continue;
      }
      if (inStr && ch == 0x22) {
        inStr = false;
        continue;
      }
      if (inStr) continue;
      if (ch == 0x22) {
        inStr = true;
        continue;
      }
      if (ch == 0x7b) stack.add(0x7d);
      if (ch == 0x5b) stack.add(0x5d);
      final isClose = ch == 0x7d || ch == 0x5d;
      if (isClose && (stack.isEmpty || stack.removeLast() != ch)) return null;
      if (stack.length > maxDepth) return null;
      if (stack.isEmpty) return text.substring(start, i + 1);
    }
    return null;
  }

  static String clampAtSentence(String text, int maxChars) {
    final trimmed = text.trim();
    if (maxChars <= 0) return '';
    if (trimmed.length <= maxChars) return trimmed;
    final end = _safeEnd(trimmed, maxChars);
    final minSent = maxChars ~/ 3;
    for (var i = end - 1; i >= minSent; i--) {
      if (_isSentenceEnd(trimmed, i)) {
        return trimmed.substring(0, i + 1).trimRight();
      }
    }
    final minWord = maxChars ~/ 2;
    for (var i = end; i >= minWord; i--) {
      if (_isSpace(trimmed.codeUnitAt(i))) {
        return trimmed.substring(0, i).trimRight();
      }
    }
    return trimmed.substring(0, end).trimRight();
  }

  static Map<String, Object?>? _decodeRootObject(
    String raw, {
    required int maxBytes,
  }) {
    if (utf8.encode(raw).length > maxBytes) return null;
    final noThink = OpenAiWireCodec.stripThinkBlocks(raw);
    for (final match in _fencePattern.allMatches(noThink)) {
      final decoded = _tryDecodeObject(match.group(1) ?? '');
      if (decoded != null) return decoded;
    }
    final cleaned = noThink.replaceAll(_strayFenceLine, '').trim();
    return _tryDecodeObject(cleaned);
  }

  static Map<String, Object?>? _tryDecodeObject(String text) {
    final jsonStr = extractFirstJsonObject(text);
    if (jsonStr == null) return null;
    try {
      final decoded = jsonDecode(jsonStr);
      return decoded is Map<String, Object?> ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  static RawAiCard? _parseCard(Object? entry) {
    if (entry is! Map<String, Object?> || entry.length != 6) return null;
    final family = parseAiMetricFamily(entry['family']);
    final title = entry['title'];
    final insight = entry['insight'];
    final evRaw = entry['evidence'];
    final action = entry['action'];
    final confidence = AiConfidence.parseWire(entry['confidence']);
    if (family == null || title is! String || insight is! String) return null;
    if (action is! String || confidence == null) return null;
    if (evRaw is! List<Object?>) return null;
    final evidence = <String>[];
    for (final item in evRaw) {
      if (item is! String) return null;
      evidence.add(item.trim());
    }
    return RawAiCard(
      family: family,
      title: clampAtSentence(title, aiMaxTitleChars),
      insight: clampAtSentence(insight, aiMaxInsightChars),
      evidence: List.unmodifiable(evidence),
      action: clampAtSentence(action, aiMaxActionChars),
      confidence: confidence,
    );
  }

  static int _safeEnd(String s, int limit) {
    final cu = s.codeUnitAt(limit - 1);
    return cu >= 0xd800 && cu <= 0xdbff ? limit - 1 : limit;
  }

  static bool _isSentenceEnd(String s, int i) {
    final cu = s.codeUnitAt(i);
    if (cu == 0x3002 || cu == 0xff01 || cu == 0xff1f) return true;
    if (cu != 0x2e && cu != 0x21 && cu != 0x3f) return false;
    return i + 1 == s.length || _isSpace(s.codeUnitAt(i + 1));
  }

  static bool _isSpace(int cu) =>
      cu == 0x20 || cu == 0x09 || cu == 0x0a || cu == 0x0d;
}

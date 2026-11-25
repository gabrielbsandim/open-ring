import 'dart:convert';

import 'package:meta/meta.dart';
import 'package:metrics/metrics.dart' show FoodGroup;
import 'package:open_ring/features/ai/domain/ai_output_extractor.dart';
import 'package:open_ring/features/ai/domain/ai_safety_lexicon.dart';
import 'package:open_ring/features/ai/domain/ai_wire_types.dart';
import 'package:open_ring/features/ai/domain/meal_photo_prompt.dart';
import 'package:open_ring/features/ai/domain/meal_photo_result.dart';
import 'package:open_ring/features/ai/domain/openai_wire_codec.dart';

enum MealPhotoRejectReason { notJson, offSchema, noSignal }

@immutable
sealed class MealPhotoOutcome {
  const new();
}

@immutable
final class MealPhotoDone extends MealPhotoOutcome {
  const new({
    required this.suggestion,
    required this.confidence,
    required this.droppedItems,
  });

  final MealPhotoSuggestion suggestion;

  /// Already capped for display; never above medium.
  final MealPhotoConfidence confidence;
  final int droppedItems;
}

@immutable
final class MealPhotoNotFood extends MealPhotoOutcome {
  const new();
}

@immutable
final class MealPhotoRejected extends MealPhotoOutcome {
  const new(this.reason);

  final MealPhotoRejectReason reason;
}

typedef _RawItem = ({
  String name,
  MealPhotoMeasure measure,
  num count,
  int grams,
  FoodGroup group,
});

typedef _Sifted = ({List<MealPhotoItem> kept, int dropped, bool implausible});

abstract final class MealPhotoValidator {
  static const int maxItems = 8;
  static const int maxItemGrams = 1500;
  static const int maxTotalGrams = 2500;
  static const int maxCount = 6;
  static const int lowShortEdgePx = 400;

  static final RegExp _itemName = RegExp(
    r"^\p{L}[\p{L}\p{M} '\-]{0,31}$",
    unicode: true,
  );
  // Invisible joiners, variation selectors and letter lookalikes (dotless i,
  // long s, IPA, small caps, letterlike, fullwidth, math alphanumerics).
  static final RegExp _hiddenOrLookalike = RegExp(
    r'[\u034F\u200B-\u200F\u2060-\u2064\uFEFF\uFE00-\uFE0F\u{E0100}-\u{E01EF}'
    r'\u0131\u017F\u0250-\u02AF\u1D00-\u1DBF\u2100-\u214F\uFF00-\uFFEF'
    r'\u{1D400}-\u{1D7FF}]|(?<![\p{L}\p{M}])\p{M}',
    unicode: true,
  );
  static final RegExp _latin = RegExp(r'\p{Script=Latin}', unicode: true);

  // Latin names must be precomposed and single script, so a mark or a
  // homoglyph cannot split a stem that findMedicalTerm looks for.
  static final RegExp _latinTrap = RegExp(
    r'\p{M}|(?!\p{Script=Latin})\p{L}',
    unicode: true,
  );
  static const Set<String> _itemKeys = {
    'name',
    'measure',
    'count',
    'grams',
    'group',
  };
  static const _offSchema = MealPhotoRejected(MealPhotoRejectReason.offSchema);

  static MealPhotoOutcome read(
    String text, {
    required int shortEdgePx,
    required bool withItems,
    required String replyLanguage,
  }) {
    final root = _decode(text);
    if (root == null) {
      return const MealPhotoRejected(MealPhotoRejectReason.notJson);
    }
    final isFood = mealEnumFromWire(MealPhotoFlag.values, root['is_food']);
    if (isFood == null) return _offSchema;
    if (isFood == MealPhotoFlag.no) return const MealPhotoNotFood();
    if (!_hasKeys(root, mealPhotoKeys(withItems: withItems))) {
      return _offSchema;
    }
    final tags = MealPhotoSuggestion.readTags(root);
    final model = mealEnumFromWire(
      MealPhotoConfidence.values,
      root['confidence'],
    );
    final raw = withItems ? _readItems(root['items']) : const <_RawItem>[];
    if (tags == null || model == null || raw == null) return _offSchema;
    final sifted = isFood == MealPhotoFlag.unsure
        ? (
            kept: const <MealPhotoItem>[],
            dropped: raw.length,
            implausible: false,
          )
        : _sift(raw, replyLanguage);
    final suggestion = tags.withItems(sifted.kept);
    if (isFood == MealPhotoFlag.yes && suggestion.noSignal) {
      return const MealPhotoRejected(MealPhotoRejectReason.noSignal);
    }
    final low =
        suggestion.anyUnsure ||
        sifted.implausible ||
        shortEdgePx < lowShortEdgePx;
    return MealPhotoDone(
      suggestion: suggestion,
      confidence: low ? MealPhotoConfidence.low : _capped(model),
      droppedItems: sifted.dropped,
    );
  }

  static MealPhotoConfidence _capped(MealPhotoConfidence model) =>
      model == MealPhotoConfidence.high ? MealPhotoConfidence.medium : model;

  static Map<String, Object?>? _decode(String text) {
    if (utf8.encode(text).length > aiMaxResponseBytes) return null;
    final json = AiOutputExtractor.extractFirstJsonObject(
      OpenAiWireCodec.stripThinkBlocks(text),
    );
    if (json == null) return null;
    try {
      final decoded = jsonDecode(json);
      return decoded is Map<String, Object?> ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  static bool _hasKeys(Map<String, Object?> map, Iterable<String> keys) {
    final expected = keys.toSet();
    return map.length == expected.length && expected.containsAll(map.keys);
  }

  static List<_RawItem>? _readItems(Object? value) {
    if (value is! List<Object?>) return null;
    final items = <_RawItem>[];
    for (final entry in value) {
      final item = _readItem(entry);
      if (item == null) return null;
      items.add(item);
    }
    return items;
  }

  static _RawItem? _readItem(Object? entry) {
    if (entry is! Map<String, Object?> || !_hasKeys(entry, _itemKeys)) {
      return null;
    }
    final name = entry['name'];
    final measure = mealEnumFromWire(MealPhotoMeasure.values, entry['measure']);
    final count = entry['count'];
    final grams = entry['grams'];
    final group = mealEnumFromWire(FoodGroup.values, entry['group']);
    if (name is! String || measure == null || group == null) return null;
    if (count is! num || grams is! int) return null;
    return (
      name: name,
      measure: measure,
      count: count,
      grams: grams,
      group: group,
    );
  }

  static _Sifted _sift(List<_RawItem> raw, String replyLanguage) {
    final merged = <String, MealPhotoItem>{};
    var dropped = 0;
    var implausible = false;
    for (final item in raw) {
      final plausible = _plausible(item);
      final name = item.name.trim();
      implausible = implausible || !plausible;
      if (!plausible || !isCleanItemName(name, replyLanguage)) {
        dropped++;
        continue;
      }
      final next = MealPhotoItem(
        name: name,
        measure: item.measure,
        countX2: (item.count * 2).round(),
        grams: item.grams,
        group: item.group,
      );
      final key = '${name.toLowerCase()}|${item.measure.name}';
      merged[key] = merged[key]?.plus(next) ?? next;
    }
    final inRange = merged.values.where(_plausibleMerged).toList();
    implausible = implausible || inRange.length < merged.length;
    final kept = inRange.take(maxItems).toList();
    dropped += merged.length - kept.length;
    final total = kept.fold(0, (sum, i) => sum + i.grams);
    if (total > maxTotalGrams) {
      return (
        kept: const [],
        dropped: dropped + kept.length,
        implausible: true,
      );
    }
    return (kept: kept, dropped: dropped, implausible: implausible);
  }

  static bool _plausible(_RawItem item) {
    final twice = item.count * 2;
    final halves = twice == twice.roundToDouble();
    final inRange = item.count >= 0.5 && item.count <= maxCount;
    return halves && inRange && item.grams >= 1 && item.grams <= maxItemGrams;
  }

  static bool _plausibleMerged(MealPhotoItem item) =>
      item.countX2 <= maxCount * 2 && item.grams <= maxItemGrams;

  /// The only guard on free text the model writes in the reply language.
  static bool isCleanItemName(String name, String replyLanguage) {
    if (!_itemName.hasMatch(name) || _hiddenOrLookalike.hasMatch(name)) {
      return false;
    }
    if (_latin.hasMatch(name) && _latinTrap.hasMatch(name)) return false;
    final folded = name.toLowerCase().replaceAll('i\u0307', 'i');
    return AiSafetyLexicon.findMedicalTerm(folded, replyLanguage) == null;
  }
}

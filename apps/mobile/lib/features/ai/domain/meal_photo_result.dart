import 'package:meta/meta.dart';

enum MealPhotoFlag { yes, no, unsure }

enum MealPhotoKind { main, snack, drink, unsure }

enum MealPhotoVeg { none, some, halfOrMore, unsure }

enum MealPhotoAlcohol { none, oneToTwo, threeOrMore, unsure }

enum MealPhotoProcessed { mostly, notMostly, unsure }

enum MealPhotoConfidence { low, medium, high }

enum MealPhotoMeasure {
  unit,
  slice,
  teaspoon,
  tablespoon,
  servingSpoon,
  ladle,
  tongs,
  cup,
  glass,
  bowl,
  handful,
  fillet,
}

final RegExp _upper = RegExp('[A-Z]');

String mealWireName(Enum value) =>
    value.name.replaceAllMapped(_upper, (m) => '_${m[0]!.toLowerCase()}');

T? mealEnumFromWire<T extends Enum>(List<T> values, Object? wire) {
  if (wire is! String) return null;
  for (final v in values) {
    if (mealWireName(v) == wire) return v;
  }
  return null;
}

@immutable
final class MealPhotoItem {
  const new({
    required this.name,
    required this.measure,
    required this.countX2,
    required this.grams,
  });

  final String name;
  final MealPhotoMeasure measure;

  /// Halves of [measure], so 3 means one and a half.
  final int countX2;
  final int grams;

  static MealPhotoItem? fromJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final name = json['name'];
    final measure = mealEnumFromWire(MealPhotoMeasure.values, json['measure']);
    final countX2 = json['count_x2'];
    final grams = json['grams'];
    if (name is! String || measure == null) return null;
    if (countX2 is! int || grams is! int) return null;
    return MealPhotoItem(
      name: name,
      measure: measure,
      countX2: countX2,
      grams: grams,
    );
  }

  Map<String, Object?> toJson() => {
    'name': name,
    'measure': mealWireName(measure),
    'count_x2': countX2,
    'grams': grams,
  };

  MealPhotoItem plus(MealPhotoItem other) => MealPhotoItem(
    name: name,
    measure: measure,
    countX2: countX2 + other.countX2,
    grams: grams + other.grams,
  );

  @override
  bool operator ==(Object other) =>
      other is MealPhotoItem &&
      other.name == name &&
      other.measure == measure &&
      other.countX2 == countX2 &&
      other.grams == grams;

  @override
  int get hashCode => Object.hash(name, measure, countX2, grams);
}

/// The model's labels as suggestions; none of them is a user tag until the
/// person confirms it.
@immutable
final class MealPhotoSuggestion {
  const new({
    required this.isFood,
    required this.kind,
    required this.protein,
    required this.caffeine,
    required this.fried,
    required this.sugaryDrink,
    required this.veg,
    required this.alcohol,
    required this.processed,
    this.items = const [],
  });

  final MealPhotoFlag isFood;
  final MealPhotoKind kind;
  final MealPhotoFlag protein;
  final MealPhotoFlag caffeine;
  final MealPhotoFlag fried;
  final MealPhotoFlag sugaryDrink;
  final MealPhotoVeg veg;
  final MealPhotoAlcohol alcohol;
  final MealPhotoProcessed processed;
  final List<MealPhotoItem> items;

  List<Enum> get tags => [
    kind,
    protein,
    caffeine,
    fried,
    sugaryDrink,
    veg,
    alcohol,
    processed,
  ];

  bool get anyUnsure =>
      isFood == MealPhotoFlag.unsure || tags.any((t) => t.name == 'unsure');

  bool get noSignal =>
      tags.every((t) => t.name == 'unsure' || t.name == 'none') &&
      items.isEmpty;

  MealPhotoSuggestion withItems(List<MealPhotoItem> items) =>
      MealPhotoSuggestion(
        isFood: isFood,
        kind: kind,
        protein: protein,
        caffeine: caffeine,
        fried: fried,
        sugaryDrink: sugaryDrink,
        veg: veg,
        alcohol: alcohol,
        processed: processed,
        items: List.unmodifiable(items),
      );

  /// Null when [json] is not a stored suggestion; extra keys are ignored.
  static MealPhotoSuggestion? fromJson(Map<String, Object?> json) {
    final tags = readTags(json);
    final rawItems = json['items'] ?? const <Object?>[];
    if (tags == null || rawItems is! List<Object?>) return null;
    final items = rawItems.map(MealPhotoItem.fromJson).toList();
    if (items.contains(null)) return null;
    return tags.withItems(items.cast<MealPhotoItem>());
  }

  /// Reads the tag keys in their wire form, without items.
  static MealPhotoSuggestion? readTags(Map<String, Object?> json) {
    MealPhotoFlag? flag(String key) =>
        mealEnumFromWire(MealPhotoFlag.values, json[key]);
    final isFood = flag('is_food');
    final kind = mealEnumFromWire(MealPhotoKind.values, json['kind']);
    final protein = flag('protein');
    final caffeine = flag('caffeine');
    final fried = flag('fried');
    final sugaryDrink = flag('sugary_drink');
    final veg = mealEnumFromWire(MealPhotoVeg.values, json['veg']);
    final alcohol = mealEnumFromWire(MealPhotoAlcohol.values, json['alcohol']);
    final processed = mealEnumFromWire(
      MealPhotoProcessed.values,
      json['processed'],
    );
    final all = [isFood, kind, protein, caffeine, fried, sugaryDrink];
    if (all.contains(null) || veg == null || alcohol == null) return null;
    if (processed == null) return null;
    return MealPhotoSuggestion(
      isFood: isFood!,
      kind: kind!,
      protein: protein!,
      caffeine: caffeine!,
      fried: fried!,
      sugaryDrink: sugaryDrink!,
      veg: veg,
      alcohol: alcohol,
      processed: processed,
    );
  }

  Map<String, Object?> toJson() => {
    'is_food': mealWireName(isFood),
    'kind': mealWireName(kind),
    'protein': mealWireName(protein),
    'caffeine': mealWireName(caffeine),
    'fried': mealWireName(fried),
    'sugary_drink': mealWireName(sugaryDrink),
    'veg': mealWireName(veg),
    'alcohol': mealWireName(alcohol),
    'processed': mealWireName(processed),
    'items': [for (final i in items) i.toJson()],
  };

  @override
  bool operator ==(Object other) =>
      other is MealPhotoSuggestion &&
      other.isFood == isFood &&
      other.kind == kind &&
      other.protein == protein &&
      other.caffeine == caffeine &&
      other.fried == fried &&
      other.sugaryDrink == sugaryDrink &&
      other.veg == veg &&
      other.alcohol == alcohol &&
      other.processed == processed &&
      _sameItems(other.items, items);

  @override
  int get hashCode => Object.hash(
    isFood,
    kind,
    protein,
    caffeine,
    fried,
    sugaryDrink,
    veg,
    alcohol,
    processed,
    Object.hashAll(items),
  );
}

bool _sameItems(List<MealPhotoItem> a, List<MealPhotoItem> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

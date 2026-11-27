import 'package:metrics/metrics.dart';
import 'package:open_ring/features/ai/domain/meal_photo_result.dart';
import 'package:open_ring/features/food/domain/meal.dart';

const Map<MealPhotoKind, MealKind> _kinds = {
  MealPhotoKind.main: MealKind.main,
  MealPhotoKind.snack: MealKind.snack,
  MealPhotoKind.drink: MealKind.drink,
};

const Map<MealPhotoVeg, MealVeg> _veg = {
  MealPhotoVeg.some: MealVeg.some,
  MealPhotoVeg.halfOrMore: MealVeg.halfOrMore,
};

const Map<MealPhotoAlcohol, MealAlcohol> _alcohol = {
  MealPhotoAlcohol.oneToTwo: MealAlcohol.oneToTwo,
  MealPhotoAlcohol.threeOrMore: MealAlcohol.threeOrMore,
};

/// The model's tags the person has not set yet, as app tag values. Its unsure
/// is never the person's Not sure chip, and heavy and place never come.
Set<Object> suggestedTags(MealPhotoSuggestion suggestion, MealEdit current) {
  final tags = current.tags;
  final flags = {
    MealFlag.protein: suggestion.protein,
    MealFlag.caffeine: suggestion.caffeine,
    MealFlag.fried: suggestion.fried,
    MealFlag.sugar: suggestion.sugaryDrink,
  };
  final processed = suggestion.processed == MealPhotoProcessed.mostly;
  return {
    if (current.kind == null) ?_kinds[suggestion.kind],
    for (final MapEntry(:key, :value) in flags.entries)
      if (value == MealPhotoFlag.yes && !current.flag(key)) key,
    if (tags.veg == null) ?_veg[suggestion.veg],
    if (tags.alcohol == null) ?_alcohol[suggestion.alcohol],
    if (tags.processed == null && processed) MealProcessed.mostly,
  };
}

/// [edit] with every value of [values] set, as the person's own tags.
MealEdit applySuggested(MealEdit edit, Set<Object> values) =>
    values.fold(edit, _apply);

MealEdit _apply(MealEdit edit, Object value) => switch (value) {
  final MealKind kind => edit.withKind(kind),
  final MealFlag flag => edit.withFlag(flag, true),
  final MealVeg veg => edit.withVeg(veg),
  final MealAlcohol alcohol => edit.withAlcohol(alcohol),
  final MealProcessed processed => edit.withProcessed(processed),
  _ => edit,
};

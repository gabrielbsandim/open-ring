import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/features/ai/domain/meal_photo_result.dart';
import 'package:open_ring/features/food/domain/meal.dart';
import 'package:open_ring/features/food/domain/meal_suggestion.dart';

MealPhotoSuggestion _suggestion({
  MealPhotoKind kind = MealPhotoKind.unsure,
  MealPhotoFlag protein = MealPhotoFlag.no,
  MealPhotoFlag caffeine = MealPhotoFlag.no,
  MealPhotoFlag fried = MealPhotoFlag.no,
  MealPhotoFlag sugaryDrink = MealPhotoFlag.no,
  MealPhotoVeg veg = MealPhotoVeg.none,
  MealPhotoAlcohol alcohol = MealPhotoAlcohol.none,
  MealPhotoProcessed processed = MealPhotoProcessed.notMostly,
}) => MealPhotoSuggestion(
  isFood: MealPhotoFlag.yes,
  kind: kind,
  protein: protein,
  caffeine: caffeine,
  fried: fried,
  sugaryDrink: sugaryDrink,
  veg: veg,
  alcohol: alcohol,
  processed: processed,
);

const _blank = MealEdit();

void main() {
  group('mapping table', () {
    test('kind main, snack and drink map to MealKind; unsure gives none', () {
      expect(suggestedTags(_suggestion(kind: MealPhotoKind.main), _blank), {
        MealKind.main,
      });
      expect(suggestedTags(_suggestion(kind: MealPhotoKind.snack), _blank), {
        MealKind.snack,
      });
      expect(suggestedTags(_suggestion(kind: MealPhotoKind.drink), _blank), {
        MealKind.drink,
      });
      expect(suggestedTags(_suggestion(), _blank), isEmpty);
    });

    test('a yes maps to its flag, sugary_drink to the sugar flag', () {
      const yes = MealPhotoFlag.yes;
      final all = _suggestion(
        protein: yes,
        caffeine: yes,
        fried: yes,
        sugaryDrink: yes,
      );
      expect(suggestedTags(all, _blank), {
        MealFlag.protein,
        MealFlag.caffeine,
        MealFlag.fried,
        MealFlag.sugar,
      });
    });

    test('each flag alone maps only to its own chip', () {
      const yes = MealPhotoFlag.yes;
      final cases = {
        _suggestion(protein: yes): MealFlag.protein,
        _suggestion(caffeine: yes): MealFlag.caffeine,
        _suggestion(fried: yes): MealFlag.fried,
        _suggestion(sugaryDrink: yes): MealFlag.sugar,
      };
      for (final MapEntry(key: s, value: flag) in cases.entries) {
        expect(suggestedTags(s, _blank), {flag}, reason: flag.name);
      }
    });

    test('no and unsure flags give no chip', () {
      for (final flag in [MealPhotoFlag.no, MealPhotoFlag.unsure]) {
        final s = _suggestion(
          protein: flag,
          caffeine: flag,
          fried: flag,
          sugaryDrink: flag,
        );
        expect(suggestedTags(s, _blank), isEmpty, reason: flag.name);
      }
    });

    test('veg, alcohol and processed mostly map to their enums', () {
      expect(suggestedTags(_suggestion(veg: MealPhotoVeg.some), _blank), {
        MealVeg.some,
      });
      expect(suggestedTags(_suggestion(veg: MealPhotoVeg.halfOrMore), _blank), {
        MealVeg.halfOrMore,
      });
      expect(
        suggestedTags(_suggestion(alcohol: MealPhotoAlcohol.oneToTwo), _blank),
        {MealAlcohol.oneToTwo},
      );
      expect(
        suggestedTags(
          _suggestion(alcohol: MealPhotoAlcohol.threeOrMore),
          _blank,
        ),
        {MealAlcohol.threeOrMore},
      );
      expect(
        suggestedTags(
          _suggestion(processed: MealPhotoProcessed.mostly),
          _blank,
        ),
        {MealProcessed.mostly},
      );
    });

    test('none, not_mostly and unsure give no chip', () {
      final quiet = _suggestion(
        veg: MealPhotoVeg.unsure,
        alcohol: MealPhotoAlcohol.unsure,
      );
      expect(suggestedTags(quiet, _blank), isEmpty);
      expect(suggestedTags(_suggestion(), _blank), isEmpty);
    });

    test("the model's unsure never maps to the person's Not sure chip", () {
      final unsure = _suggestion(processed: MealPhotoProcessed.unsure);
      expect(suggestedTags(unsure, _blank), isEmpty);
      expect(
        suggestedTags(unsure, _blank),
        isNot(contains(MealProcessed.unsure)),
      );
    });

    test('heavy and place are never suggested', () {
      const yes = MealPhotoFlag.yes;
      final full = _suggestion(
        kind: MealPhotoKind.main,
        protein: yes,
        caffeine: yes,
        fried: yes,
        sugaryDrink: yes,
        veg: MealPhotoVeg.some,
        alcohol: MealPhotoAlcohol.oneToTwo,
        processed: MealPhotoProcessed.mostly,
      );
      final tags = suggestedTags(full, _blank);
      expect(tags, hasLength(8));
      expect(tags, isNot(contains(MealFlag.heavy)));
      expect(tags.whereType<MealPlace>(), isEmpty);
    });
  });

  group('what the person set', () {
    final full = _suggestion(
      kind: MealPhotoKind.main,
      protein: MealPhotoFlag.yes,
      veg: MealPhotoVeg.some,
      alcohol: MealPhotoAlcohol.oneToTwo,
      processed: MealPhotoProcessed.mostly,
    );

    test('a group the person already set shows no suggestion', () {
      final edit = _blank
          .withKind(MealKind.snack)
          .withVeg(MealVeg.halfOrMore)
          .withAlcohol(MealAlcohol.threeOrMore)
          .withProcessed(MealProcessed.unsure);
      expect(suggestedTags(full, edit), {MealFlag.protein});
    });

    test('a flag already on shows none', () {
      final edit = _blank.withFlag(MealFlag.protein, true);
      expect(suggestedTags(full, edit), isNot(contains(MealFlag.protein)));
    });
  });

  test('applySuggested sets every value as a tag and keeps the rest', () {
    final start = _blank.withPlace(MealPlace.home).withLast(true);
    final edit = applySuggested(start, {
      MealKind.main,
      MealFlag.protein,
      MealVeg.some,
      MealAlcohol.oneToTwo,
      MealProcessed.mostly,
    });

    expect(edit.kind, MealKind.main);
    expect(edit.flag(MealFlag.protein), isTrue);
    expect(edit.flag(MealFlag.heavy), isFalse);
    expect(edit.tags.veg, MealVeg.some);
    expect(edit.tags.alcohol, MealAlcohol.oneToTwo);
    expect(edit.tags.processed, MealProcessed.mostly);
    expect(edit.tags.place, MealPlace.home);
    expect(edit.last, isTrue);
  });

  test('applySuggested with nothing returns the edit as is', () {
    expect(applySuggested(_blank, const {}), same(_blank));
  });
}

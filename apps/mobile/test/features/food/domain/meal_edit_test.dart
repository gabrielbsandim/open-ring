import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/features/food/domain/meal.dart';

final _untagged = Meal(
  id: 4,
  at: DateTime.utc(2026, 11, 17, 15, 30),
  offsetMinutes: -180,
  createdAt: DateTime.utc(2026, 11, 17, 15, 31),
  photo: 'meal_4_0000000a.jpg',
);

final _tagged = Meal(
  id: 5,
  at: DateTime.utc(2026, 11, 17, 22, 10),
  offsetMinutes: 330,
  createdAt: DateTime.utc(2026, 11, 17, 22, 11),
  kind: MealKind.main,
  tags: const MealTags(
    protein: true,
    sugar: true,
    veg: MealVeg.some,
    alcohol: MealAlcohol.oneToTwo,
    processed: MealProcessed.unsure,
    place: MealPlace.restaurant,
  ),
  last: true,
  photo: 'meal_5_0000000b.jpg',
);

Object _tagsOf(MealTags t) => (
  t.protein,
  t.caffeine,
  t.heavy,
  t.fried,
  t.sugar,
  t.veg,
  t.alcohol,
  t.processed,
  t.place,
);

typedef _Change = ({
  String name,
  MealEdit Function(MealEdit) set,
  MealEdit Function(MealEdit) back,
});

List<_Change> _changesFrom(Meal meal) => [
  (
    name: 'withKind',
    set: (e) => e.withKind(
      meal.kind == MealKind.snack ? MealKind.drink : MealKind.snack,
    ),
    back: (e) => e.withKind(meal.kind),
  ),
  for (final flag in MealFlag.values)
    (
      name: 'withFlag ${flag.name}',
      set: (e) => e.withFlag(flag, !MealEdit.of(meal).flag(flag)),
      back: (e) => e.withFlag(flag, MealEdit.of(meal).flag(flag)),
    ),
  (
    name: 'withVeg',
    set: (e) => e.withVeg(
      meal.tags.veg == MealVeg.halfOrMore ? MealVeg.some : MealVeg.halfOrMore,
    ),
    back: (e) => e.withVeg(meal.tags.veg),
  ),
  (
    name: 'withAlcohol',
    set: (e) => e.withAlcohol(
      meal.tags.alcohol == MealAlcohol.threeOrMore
          ? MealAlcohol.oneToTwo
          : MealAlcohol.threeOrMore,
    ),
    back: (e) => e.withAlcohol(meal.tags.alcohol),
  ),
  (
    name: 'withProcessed',
    set: (e) => e.withProcessed(
      meal.tags.processed == MealProcessed.mostly
          ? MealProcessed.unsure
          : MealProcessed.mostly,
    ),
    back: (e) => e.withProcessed(meal.tags.processed),
  ),
  (
    name: 'withPlace',
    set: (e) => e.withPlace(
      meal.tags.place == MealPlace.packaged
          ? MealPlace.home
          : MealPlace.packaged,
    ),
    back: (e) => e.withPlace(meal.tags.place),
  ),
  (
    name: 'withLast',
    set: (e) => e.withLast(!meal.last),
    back: (e) => e.withLast(meal.last),
  ),
];

void main() {
  group('criterion 1: MealEdit', () {
    final meals = {'an untagged meal': _untagged, 'a tagged meal': _tagged};
    for (final MapEntry(key: label, value: meal) in meals.entries) {
      test('MealEdit.of is the same as $label', () {
        expect(MealEdit.of(meal).sameAs(meal), isTrue);
      });

      for (final change in _changesFrom(meal)) {
        test('${change.name} on $label breaks sameAs, and setting it back '
            'restores it', () {
          final changed = change.set(MealEdit.of(meal));
          expect(changed.sameAs(meal), isFalse);
          expect(change.back(changed).sameAs(meal), isTrue);
        });
      }

      test('MealEdit.of $label carries its kind, tags and last', () {
        final draft = MealEdit.of(meal).draftOf(meal);

        expect(draft.kind, meal.kind);
        expect(_tagsOf(draft.tags), _tagsOf(meal.tags));
        expect(draft.last, meal.last);
      });
    }

    test('the default edit is the same as an untagged meal', () {
      expect(const MealEdit().sameAs(_untagged), isTrue);
      expect(const MealEdit().sameAs(_tagged), isFalse);
    });

    test('withVeg(null) clears the veg tag', () {
      final cleared = MealEdit.of(_tagged).withVeg(null);

      expect(cleared.draftOf(_tagged).tags.veg, isNull);
      expect(cleared.sameAs(_tagged), isFalse);
    });

    test('a nullable tag set to null clears it, each one', () {
      final cleared = MealEdit.of(_tagged)
          .withKind(null)
          .withAlcohol(null)
          .withProcessed(null)
          .withPlace(null)
          .draftOf(_tagged);

      expect(cleared.kind, isNull);
      expect(cleared.tags.alcohol, isNull);
      expect(cleared.tags.processed, isNull);
      expect(cleared.tags.place, isNull);
    });

    test('flag reads each bool tag of the meal', () {
      final edit = MealEdit.of(_tagged);

      expect(edit.flag(MealFlag.protein), isTrue);
      expect(edit.flag(MealFlag.sugar), isTrue);
      expect(edit.flag(MealFlag.caffeine), isFalse);
      expect(edit.flag(MealFlag.heavy), isFalse);
      expect(edit.flag(MealFlag.fried), isFalse);
    });

    test('withFlag sets only the flag it names', () {
      for (final flag in MealFlag.values) {
        final edit = MealEdit.of(_untagged).withFlag(flag, true);
        for (final other in MealFlag.values) {
          expect(edit.flag(other), other == flag, reason: '$flag, $other');
        }
      }
    });

    test('withFlag writes each flag to its own MealTags field', () {
      final fields = <MealFlag, bool Function(MealTags)>{
        MealFlag.protein: (t) => t.protein,
        MealFlag.caffeine: (t) => t.caffeine,
        MealFlag.heavy: (t) => t.heavy,
        MealFlag.fried: (t) => t.fried,
        MealFlag.sugar: (t) => t.sugar,
      };
      for (final MapEntry(key: flag, value: field) in fields.entries) {
        final tags = MealEdit.of(_untagged)
            .withFlag(flag, true)
            .draftOf(_untagged)
            .tags;
        expect(field(tags), isTrue, reason: '$flag');
        expect(tags.isEmpty, isFalse, reason: '$flag');
      }
    });

    test('draftOf keeps at and offsetMinutes and carries the edit', () {
      final draft = MealEdit.of(_untagged)
          .withKind(MealKind.drink)
          .withFlag(MealFlag.sugar, true)
          .withVeg(MealVeg.halfOrMore)
          .withLast(true)
          .draftOf(_untagged);

      expect(draft.at, _untagged.at);
      expect(draft.offsetMinutes, _untagged.offsetMinutes);
      expect(draft.kind, MealKind.drink);
      expect(draft.tags.sugar, isTrue);
      expect(draft.tags.veg, MealVeg.halfOrMore);
      expect(draft.tags.protein, isFalse);
      expect(draft.last, isTrue);
    });

    test('a with call leaves the edit it came from unchanged', () {
      final base = MealEdit.of(_untagged)
        ..withKind(MealKind.main)
        ..withFlag(MealFlag.protein, true)
        ..withPlace(MealPlace.home)
        ..withLast(true);

      expect(base.sameAs(_untagged), isTrue);
    });
  });
}

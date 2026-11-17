import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/features/food/domain/meal.dart';
import 'package:open_ring/features/food/domain/meal_store.dart';
import 'package:open_ring/features/food/infrastructure/drift_meal_store.dart';

import '../../../helpers/database.dart';

final _now = DateTime.utc(2026, 12, 1, 9, 15, 0, 250);

const _badNames = ['../a.jpg', '/data/a.jpg', 'a/b.jpg', '', 'a.png'];

const _d1 = LocalDate(2026, 12, 1);
const _d2 = LocalDate(2026, 12, 3);

const _allTags = MealTags(
  protein: true,
  caffeine: true,
  heavy: true,
  fried: true,
  sugar: true,
  veg: MealVeg.halfOrMore,
  alcohol: MealAlcohol.oneToTwo,
  processed: MealProcessed.mostly,
  place: MealPlace.home,
);

/// A draft whose local wall clock is [wall] (read as fields) at [offset].
MealDraft _atWall(
  DateTime wall, {
  int offset = -180,
  MealKind? kind,
  MealTags tags = const MealTags(),
  bool last = false,
}) => MealDraft(
  at: wall.subtract(Duration(minutes: offset)),
  offsetMinutes: offset,
  kind: kind,
  tags: tags,
  last: last,
);

// MealTags has no ==, so tags are compared as a record of their fields.
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

Object _fieldsOf(Meal m) => (
  id: m.id,
  at: m.at,
  offsetMinutes: m.offsetMinutes,
  kind: m.kind,
  tags: _tagsOf(m.tags),
  last: m.last,
  photo: m.photo,
  createdAt: m.createdAt,
);

void main() {
  late MealStore store;

  setUp(() => store = DriftMealStore(memoryDatabase()));

  Future<List<Meal>> all() =>
      store.between(const LocalDate(2000, 1, 1), const LocalDate(2100, 1, 1));

  Future<Meal> addAt(DateTime wall, {int offset = -180, String? photo}) =>
      store.add(
        _atWall(wall, offset: offset),
        photo: photo,
        now: _now,
      );

  group('criterion 3: add round trips every field', () {
    test('kind null and each kind', () async {
      final kinds = <MealKind?>[null, ...MealKind.values];
      for (final (i, kind) in kinds.indexed) {
        await store.add(
          _atWall(DateTime.utc(2026, 12, 1, 8 + i), kind: kind),
          now: _now,
        );
      }

      expect([for (final meal in await all()) meal.kind], kinds);
    });

    test('all five yes/no tags', () async {
      await store.add(
        _atWall(
          DateTime.utc(2026, 12, 1, 8),
          tags: const MealTags(
            protein: true,
            caffeine: true,
            heavy: true,
            fried: true,
            sugar: true,
          ),
        ),
        now: _now,
      );

      expect(_tagsOf((await all()).single.tags), (
        true,
        true,
        true,
        true,
        true,
        null,
        null,
        null,
        null,
      ));
    });

    test('each value of veg, alcohol, processed and place', () async {
      final tags = [
        for (final veg in MealVeg.values) MealTags(veg: veg),
        for (final alcohol in MealAlcohol.values) MealTags(alcohol: alcohol),
        for (final processed in MealProcessed.values)
          MealTags(processed: processed),
        for (final place in MealPlace.values) MealTags(place: place),
      ];
      for (final (i, tag) in tags.indexed) {
        await store.add(
          _atWall(DateTime.utc(2026, 12, 1, 6 + i), tags: tag),
          now: _now,
        );
      }

      expect(
        [for (final meal in await all()) _tagsOf(meal.tags)],
        [for (final tag in tags) _tagsOf(tag)],
      );
    });

    test('last true and false', () async {
      await store.add(
        _atWall(DateTime.utc(2026, 12, 1, 8), last: true),
        now: _now,
      );
      await store.add(_atWall(DateTime.utc(2026, 12, 1, 9)), now: _now);

      expect([for (final meal in await all()) meal.last], [true, false]);
    });

    test('photo null and set', () async {
      await addAt(DateTime.utc(2026, 12, 1, 8));
      await addAt(DateTime.utc(2026, 12, 1, 9), photo: 'a.jpg');

      expect([for (final meal in await all()) meal.photo], [null, 'a.jpg']);
    });

    test(
      'the instant to the millisecond, the offset and createdAt = now',
      () async {
        await store.add(
          MealDraft(
            at: DateTime.utc(2026, 12, 1, 7, 12, 34, 567),
            offsetMinutes: 330,
          ),
          now: _now,
        );

        final meal = (await all()).single;
        expect(meal.at, DateTime.utc(2026, 12, 1, 7, 12, 34, 567));
        expect(meal.offsetMinutes, 330);
        expect(meal.createdAt, _now);
      },
    );

    test('the meal add returns is the stored row', () async {
      final added = await store.add(
        _atWall(
          DateTime.utc(2026, 12, 1, 13),
          kind: MealKind.main,
          tags: _allTags,
          last: true,
        ),
        photo: 'lunch_1.jpg',
        now: _now,
      );

      expect(_fieldsOf((await all()).single), _fieldsOf(added));
    });

    test('a default draft reads back untagged', () async {
      await store.add(
        MealDraft(at: DateTime.utc(2026, 12, 1, 12), offsetMinutes: 0),
        now: _now,
      );

      final meal = (await all()).single;
      expect(meal.kind, isNull);
      expect(meal.tags.isEmpty, isTrue);
      expect(meal.last, isFalse);
      expect(meal.photo, isNull);
      expect(meal.entry.tagged, isFalse);
    });
  });

  group('criterion 4: entry is the capture wall clock', () {
    test(
      '03:30Z at -180 is 00:30 on 1 December, food day 30 November',
      () async {
        final added = await store.add(
          MealDraft(at: DateTime.utc(2026, 12, 1, 3, 30), offsetMinutes: -180),
          now: _now,
        );
        final read = (await all()).single;

        for (final entry in [added.entry, read.entry]) {
          // UTC flagged, so its fields do not depend on the test host's zone.
          expect(entry.at.isUtc, isTrue);
          expect(
            (
              entry.at.year,
              entry.at.month,
              entry.at.day,
              entry.at.hour,
              entry.at.minute,
            ),
            (2026, 12, 1, 0, 30),
          );
          expect(foodDay(entry.at), const LocalDate(2026, 11, 30));
        }
      },
    );

    test('a positive offset moves the wall clock to the next day', () async {
      await store.add(
        MealDraft(at: DateTime.utc(2026, 12, 1, 23, 30), offsetMinutes: 60),
        now: _now,
      );

      final at = (await all()).single.entry.at;
      expect((at.day, at.hour, at.minute), (2, 0, 30));
      expect(foodDay(at), const LocalDate(2026, 12, 1));
    });

    test('carries kind, tags and last', () async {
      await store.add(
        _atWall(
          DateTime.utc(2026, 12, 1, 21),
          kind: MealKind.drink,
          tags: _allTags,
          last: true,
        ),
        now: _now,
      );

      final entry = (await all()).single.entry;
      expect(entry.kind, MealKind.drink);
      expect(_tagsOf(entry.tags), _tagsOf(_allTags));
      expect(entry.last, isTrue);
    });

    test('difference across a clock change is wall clock time', () async {
      await store.add(
        MealDraft(at: DateTime.utc(2026, 3, 29, 0, 30), offsetMinutes: 60),
        now: _now,
      );
      await store.add(
        MealDraft(at: DateTime.utc(2026, 3, 29, 1, 30), offsetMinutes: 120),
        now: _now,
      );

      final [before, after] = await all();
      expect(
        after.entry.at.difference(before.entry.at),
        const Duration(hours: 2),
      );
    });
  });

  group('criterion 5: between returns whole food days', () {
    test(
      '05:00 on the first day and 04:59 after the last day are in',
      () async {
        final in1 = await addAt(DateTime.utc(2026, 12, 1, 5));
        await addAt(DateTime.utc(2026, 12, 1, 4, 59));
        final in2 = await addAt(DateTime.utc(2026, 12, 4, 4, 59));
        await addAt(DateTime.utc(2026, 12, 4, 5));

        final meals = await store.between(_d1, _d2);

        expect([for (final meal in meals) meal.id], [in1.id, in2.id]);
      },
    );

    test('one millisecond before 05:00 belongs to the day before', () async {
      await addAt(DateTime.utc(2026, 12, 1, 4, 59, 59, 999));
      final first = await addAt(DateTime.utc(2026, 12, 2, 4, 59, 59, 999));

      final meals = await store.between(_d1, _d1);

      expect([for (final meal in meals) meal.id], [first.id]);
    });

    test(
      'rows at one instant land on the food days of their own offsets',
      () async {
        final instant = DateTime.utc(2026, 12, 2, 7);
        final west = await store.add(
          MealDraft(at: instant, offsetMinutes: -180),
          now: _now,
        );
        final east = await store.add(
          MealDraft(at: instant, offsetMinutes: 60),
          now: _now,
        );

        final first = await store.between(_d1, _d1);
        final second = await store.between(
          const LocalDate(2026, 12, 2),
          const LocalDate(2026, 12, 2),
        );

        expect([for (final meal in first) meal.id], [west.id]);
        expect([for (final meal in second) meal.id], [east.id]);
      },
    );

    test('oldest wall clock first, not oldest instant', () async {
      final laterWall = await addAt(DateTime.utc(2026, 12, 2, 11), offset: 180);
      final earlierWall = await addAt(
        DateTime.utc(2026, 12, 2, 8),
        offset: -60,
      );

      final meals = await store.between(_d1, _d2);

      expect(laterWall.at.isBefore(earlierWall.at), isTrue);
      expect(
        [for (final meal in meals) meal.id],
        [earlierWall.id, laterWall.id],
      );
    });

    test('ties on wall clock go by id', () async {
      final first = await addAt(DateTime.utc(2026, 12, 2, 12));
      final second = await addAt(DateTime.utc(2026, 12, 2, 12), offset: 0);

      final meals = await store.between(_d1, _d2);

      expect(second.at.isBefore(first.at), isTrue);
      expect([for (final meal in meals) meal.id], [first.id, second.id]);
    });

    test('from after to is empty', () async {
      await addAt(DateTime.utc(2026, 12, 2, 12));

      expect(await store.between(_d2, _d1), isEmpty);
    });
  });

  group('criterion 6: update', () {
    test('writes time, offset, kind, tags and last, keeps photo and '
        'createdAt', () async {
      final added = await addAt(DateTime.utc(2026, 12, 1, 12), photo: 'a.jpg');
      final draft = MealDraft(
        at: DateTime.utc(2026, 12, 2, 18, 45, 0, 7),
        offsetMinutes: 60,
        kind: MealKind.drink,
        tags: const MealTags(caffeine: true, place: MealPlace.restaurant),
        last: true,
      );

      expect(await store.update(added.id, draft), isTrue);

      final meal = (await all()).single;
      expect(meal.id, added.id);
      expect(meal.at, DateTime.utc(2026, 12, 2, 18, 45, 0, 7));
      expect(meal.offsetMinutes, 60);
      expect(meal.kind, MealKind.drink);
      expect(
        _tagsOf(meal.tags),
        _tagsOf(const MealTags(caffeine: true, place: MealPlace.restaurant)),
      );
      expect(meal.last, isTrue);
      expect(meal.photo, 'a.jpg');
      expect(meal.createdAt, _now);
    });

    test('a default draft clears kind, tags and last', () async {
      final added = await store.add(
        _atWall(
          DateTime.utc(2026, 12, 1, 12),
          kind: MealKind.main,
          tags: _allTags,
          last: true,
        ),
        now: _now,
      );

      await store.update(
        added.id,
        MealDraft(at: added.at, offsetMinutes: added.offsetMinutes),
      );

      final meal = (await all()).single;
      expect(meal.kind, isNull);
      expect(meal.tags.isEmpty, isTrue);
      expect(meal.last, isFalse);
    });

    test('an unknown id returns false and writes nothing', () async {
      final added = await addAt(DateTime.utc(2026, 12, 1, 12), photo: 'a.jpg');
      final before = [for (final meal in await all()) _fieldsOf(meal)];

      final updated = await store.update(
        added.id + 1,
        MealDraft(at: DateTime.utc(2026, 12, 5), offsetMinutes: 0),
      );

      expect(updated, isFalse);
      expect(await store.count(), 1);
      expect([for (final meal in await all()) _fieldsOf(meal)], before);
    });
  });

  group('criterion 7: delete', () {
    test(
      'returns the removed meal with its photo and count drops by 1',
      () async {
        final kept = await addAt(
          DateTime.utc(2026, 12, 1, 8),
          photo: 'kept.jpg',
        );
        final gone = await store.add(
          _atWall(
            DateTime.utc(2026, 12, 1, 13),
            kind: MealKind.snack,
            tags: _allTags,
            last: true,
          ),
          photo: 'gone.jpg',
          now: _now,
        );

        final removed = await store.delete(gone.id);

        expect(removed, isNotNull);
        expect(_fieldsOf(removed!), _fieldsOf(gone));
        expect(await store.count(), 1);
        expect([for (final meal in await all()) meal.id], [kept.id]);
      },
    );

    test('an unknown id returns null and removes nothing', () async {
      final added = await addAt(DateTime.utc(2026, 12, 1, 8));

      expect(await store.delete(added.id + 1), isNull);
      expect(await store.count(), 1);
    });
  });

  group('criterion 8: count and clear', () {
    test('count is 0 on an empty table and counts every row', () async {
      expect(await store.count(), 0);

      await addAt(DateTime.utc(2026, 12, 1, 8));
      await addAt(DateTime.utc(2026, 12, 1, 8));

      expect(await store.count(), 2);
    });

    test('clear returns the rows removed and leaves none', () async {
      for (var hour = 8; hour < 11; hour++) {
        await addAt(DateTime.utc(2026, 12, 1, hour), photo: 'p$hour.jpg');
      }

      expect(await store.clear(), 3);
      expect(await store.count(), 0);
      expect(await store.clear(), 0);
    });
  });

  group('criterion 9: deletePhotosBefore', () {
    final cutoff = DateTime.utc(2026, 12, 10, 12);
    late Meal old1;
    late Meal old2;
    late Meal edge;
    late Meal fresh;

    Future<Meal> addInstant(DateTime at, String? photo) => store.add(
      MealDraft(
        at: at,
        offsetMinutes: -180,
        kind: MealKind.main,
        tags: _allTags,
      ),
      photo: photo,
      now: _now,
    );

    setUp(() async {
      old2 = await addInstant(
        cutoff.subtract(const Duration(days: 1)),
        'o2.jpg',
      );
      old1 = await addInstant(
        cutoff.subtract(const Duration(days: 2)),
        'o1.jpg',
      );
      await addInstant(cutoff.subtract(const Duration(hours: 3)), null);
      edge = await addInstant(cutoff, 'edge.jpg');
      fresh = await addInstant(cutoff.add(const Duration(days: 1)), 'new.jpg');
    });

    test('releases the photos before the cutoff, oldest first', () async {
      expect(await store.deletePhotosBefore(cutoff), ['o1.jpg', 'o2.jpg']);
    });

    test('nulls those photos and keeps the one at the cutoff', () async {
      await store.deletePhotosBefore(cutoff);

      final photos = {for (final meal in await all()) meal.id: meal.photo};
      expect(photos[old1.id], isNull);
      expect(photos[old2.id], isNull);
      expect(photos[edge.id], 'edge.jpg');
      expect(photos[fresh.id], 'new.jpg');
    });

    test('every row stays with its tags', () async {
      await store.deletePhotosBefore(cutoff);

      final meals = await all();
      expect(await store.count(), 5);
      expect(meals, hasLength(5));
      for (final meal in meals) {
        expect(_tagsOf(meal.tags), _tagsOf(_allTags));
        expect(meal.kind, MealKind.main);
      }
    });

    test('a second call returns nothing', () async {
      await store.deletePhotosBefore(cutoff);

      expect(await store.deletePhotosBefore(cutoff), isEmpty);
    });
  });

  group('criterion 10: photo names', () {
    for (final name in _badNames) {
      test(
        'add with "$name" throws ArgumentError and stores nothing',
        () async {
          await expectLater(
            () => addAt(DateTime.utc(2026, 12, 1, 8), photo: name),
            throwsArgumentError,
          );

          expect(await store.count(), 0);
        },
      );
    }

    test('a photo name already stored is refused', () async {
      await addAt(DateTime.utc(2026, 12, 1, 8), photo: 'a.jpg');

      await expectLater(
        () => addAt(DateTime.utc(2026, 12, 1, 9), photo: 'a.jpg'),
        throwsA(anything),
      );

      expect(await store.count(), 1);
      expect((await all()).single.photo, 'a.jpg');
    });

    test('two rows without a photo are accepted', () async {
      await addAt(DateTime.utc(2026, 12, 1, 8));
      await addAt(DateTime.utc(2026, 12, 1, 9));

      expect(await store.count(), 2);
    });
  });
}

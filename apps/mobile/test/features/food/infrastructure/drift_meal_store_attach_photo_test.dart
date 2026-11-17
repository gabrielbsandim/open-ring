import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/features/food/domain/meal.dart';
import 'package:open_ring/features/food/domain/meal_store.dart';
import 'package:open_ring/features/food/infrastructure/drift_meal_store.dart';

import '../../../helpers/database.dart';

final _now = DateTime.utc(2026, 12, 10, 23);

const _badNames = ['../a.jpg', '/data/a.jpg', 'a/b.jpg', '', 'a.png'];

final _draft = MealDraft(
  at: DateTime.utc(2026, 12, 10, 22, 32, 5),
  offsetMinutes: -180,
  kind: MealKind.main,
);

void main() {
  late MealStore store;

  setUp(() => store = DriftMealStore(memoryDatabase()));

  Future<List<Meal>> all() =>
      store.between(const LocalDate(2000, 1, 1), const LocalDate(2100, 1, 1));

  group('criterion 5: attachPhoto', () {
    test('sets the photo on the row and returns true', () async {
      final meal = await store.add(_draft, now: _now);

      expect(await store.attachPhoto(meal.id, 'meal_1_0a1b2c3d.jpg'), isTrue);

      final stored = (await all()).single;
      expect(stored.photo, 'meal_1_0a1b2c3d.jpg');
      expect(stored.at, meal.at);
      expect(stored.createdAt, meal.createdAt);
      expect(stored.kind, MealKind.main);
    });

    for (final name in _badNames) {
      test('"$name" throws ArgumentError and writes nothing', () async {
        final meal = await store.add(_draft, now: _now);

        await expectLater(
          () => store.attachPhoto(meal.id, name),
          throwsArgumentError,
        );
        expect((await all()).single.photo, isNull);
      });
    }

    test('a bad name throws before the id is looked up', () async {
      await expectLater(
        () => store.attachPhoto(999, '../a.jpg'),
        throwsArgumentError,
      );
    });

    test('an unknown id returns false and writes nothing', () async {
      final meal = await store.add(_draft, now: _now);

      expect(
        await store.attachPhoto(meal.id + 1, 'meal_1_0a1b2c3d.jpg'),
        isFalse,
      );

      expect(await store.count(), 1);
      expect((await all()).single.photo, isNull);
    });

    test('a name another row holds throws and leaves both rows', () async {
      final first = await store.add(
        _draft,
        now: _now,
        photo: 'meal_1_aaaa.jpg',
      );
      final second = await store.add(_draft, now: _now);

      await expectLater(
        () => store.attachPhoto(second.id, 'meal_1_aaaa.jpg'),
        throwsA(anything),
      );

      final rows = await all();
      expect(
        [for (final m in rows) (m.id, m.photo)],
        [(first.id, 'meal_1_aaaa.jpg'), (second.id, null)],
      );
    });
  });
}

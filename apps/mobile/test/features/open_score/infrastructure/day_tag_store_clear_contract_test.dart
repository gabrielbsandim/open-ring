import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/core/database/app_database.dart';
import 'package:open_ring/features/open_score/domain/day_tag.dart';
import 'package:open_ring/features/open_score/domain/day_tag_store.dart';
import 'package:open_ring/features/open_score/infrastructure/drift_day_tag_store.dart';

import '../../../helpers/database.dart';

const _monday = LocalDate(2026, 11, 9);
const _tuesday = LocalDate(2026, 11, 10);
final _now = DateTime.utc(2026, 11, 14, 12);

void main() {
  final stores = <String, DayTagStore Function()>{
    'InMemoryDayTagStore': InMemoryDayTagStore.new,
    'DriftDayTagStore': () => DriftDayTagStore(memoryDatabase()),
  };

  for (final MapEntry(key: name, value: create) in stores.entries) {
    group('criterion 7: count and clear on $name', () {
      late DayTagStore store;

      setUp(() => store = create());

      test('count is 0 on a fresh store', () async {
        expect(await store.count(), 0);
      });

      test('clear on an empty store removes nothing and returns 0', () async {
        expect(await store.clear(), 0);
        expect(await store.count(), 0);
      });

      test('count follows put and remove', () async {
        await store.put(_monday, DayTag.sick, now: _now);
        await store.put(_tuesday, DayTag.rest, now: _now);
        expect(await store.count(), 2);

        await store.remove(_monday);
        expect(await store.count(), 1);
      });

      test('count of one tag is 1', () async {
        await store.put(_monday, DayTag.travel, now: _now);

        expect(await store.count(), 1);
      });

      test('clear returns the rows removed and leaves none', () async {
        await store.put(_monday, DayTag.sick, now: _now);
        await store.put(_tuesday, DayTag.rest, now: _now);

        expect(await store.clear(), 2);

        expect(await store.count(), 0);
        expect(await store.all(), isEmpty);
      });

      test('clear twice returns 0 the second time', () async {
        await store.put(_monday, DayTag.sick, now: _now);
        await store.clear();

        expect(await store.clear(), 0);
      });

      test('a cleared date can be tagged again', () async {
        await store.put(_monday, DayTag.sick, now: _now);
        await store.clear();

        expect(await store.put(_monday, DayTag.sick, now: _now), isTrue);
        expect(await store.count(), 1);
      });
    });
  }

  group('criterion 7: a row whose tag does not parse', () {
    late AppDatabase db;
    late DriftDayTagStore store;

    setUp(() async {
      db = memoryDatabase();
      store = DriftDayTagStore(db);
      await store.put(_monday, DayTag.sick, now: _now);
      await db
          .into(db.dayTags)
          .insert(
            DayTagsCompanion.insert(
              date: _tuesday.iso,
              tag: 'no_such_tag',
              updatedAtUtcMs: _now.millisecondsSinceEpoch,
            ),
          );
    });

    test('all drops it but count counts the raw rows', () async {
      expect(await store.all(), {_monday: DayTag.sick});
      expect(await store.count(), 2);
    });

    test('a row with an unparseable date is counted too', () async {
      await db
          .into(db.dayTags)
          .insert(
            DayTagsCompanion.insert(
              date: 'not-a-date',
              tag: DayTag.rest.name,
              updatedAtUtcMs: _now.millisecondsSinceEpoch,
            ),
          );

      expect(await store.count(), 3);
    });

    test('clear removes it and counts it as removed', () async {
      expect(await store.clear(), 2);

      expect(await store.count(), 0);
      expect(await rowCount(db, 'day_tags'), 0);
    });
  });
}

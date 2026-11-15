import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
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
    group(name, () {
      late DayTagStore store;

      setUp(() => store = create());

      test('all is empty on a fresh store', () async {
        expect(await store.all(), isEmpty);
      });

      test('put on a new date writes it and returns true', () async {
        expect(await store.put(_monday, DayTag.sick, now: _now), isTrue);

        expect(await store.all(), {_monday: DayTag.sick});
      });

      test('put with another tag overwrites and returns true', () async {
        await store.put(_monday, DayTag.sick, now: _now);

        expect(await store.put(_monday, DayTag.travel, now: _now), isTrue);

        expect(await store.all(), {_monday: DayTag.travel});
      });

      test('put of the same tag returns false and keeps the row', () async {
        await store.put(_monday, DayTag.rest, now: _now);

        expect(await store.put(_monday, DayTag.rest, now: _now), isFalse);

        expect(await store.all(), {_monday: DayTag.rest});
      });

      test('each date holds its own tag', () async {
        await store.put(_monday, DayTag.sick, now: _now);
        await store.put(_tuesday, DayTag.rest, now: _now);

        expect(await store.all(), {
          _monday: DayTag.sick,
          _tuesday: DayTag.rest,
        });
      });

      test('remove deletes the row and returns true', () async {
        await store.put(_monday, DayTag.sick, now: _now);
        await store.put(_tuesday, DayTag.rest, now: _now);

        expect(await store.remove(_monday), isTrue);

        expect(await store.all(), {_tuesday: DayTag.rest});
      });

      test('remove of a missing date returns false', () async {
        await store.put(_monday, DayTag.sick, now: _now);

        expect(await store.remove(_tuesday), isFalse);

        expect(await store.all(), {_monday: DayTag.sick});
      });

      test('a removed date can be tagged again', () async {
        await store.put(_monday, DayTag.sick, now: _now);
        await store.remove(_monday);

        expect(await store.put(_monday, DayTag.sick, now: _now), isTrue);
      });
    });
  }

  test('the in-memory store starts from its initial map', () async {
    final store = InMemoryDayTagStore({_monday: DayTag.travel});

    expect(await store.all(), {_monday: DayTag.travel});
  });
}

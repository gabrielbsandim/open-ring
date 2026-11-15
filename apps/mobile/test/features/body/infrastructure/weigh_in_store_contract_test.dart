import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/body/domain/weigh_in.dart';
import 'package:open_ring/features/body/domain/weigh_in_store.dart';
import 'package:open_ring/features/body/infrastructure/drift_weigh_in_store.dart';
import 'package:open_ring/features/settings/domain/unit_system.dart';

import '../../../helpers/database.dart';

WeighInDraft draft({
  DateTime? at,
  int offsetMinutes = -180,
  double kilograms = 78.2,
  double? bodyFatPercent,
  double? waistCentimeters,
  WeighInSource source = WeighInSource.manual,
}) => WeighInDraft(
  at: at ?? DateTime.utc(2026, 11, 14, 12),
  offsetMinutes: offsetMinutes,
  kilograms: kilograms,
  bodyFatPercent: bodyFatPercent,
  waistCentimeters: waistCentimeters,
  source: source,
);

void main() {
  final stores = <String, WeighInStore Function()>{
    'InMemoryWeighInStore': InMemoryWeighInStore.new,
    'DriftWeighInStore': () => DriftWeighInStore(memoryDatabase()),
  };

  for (final MapEntry(key: name, value: create) in stores.entries) {
    group(name, () {
      late WeighInStore store;

      setUp(() => store = create());

      test('add returns the row with its id and every field', () async {
        final added = await store.add(
          draft(
            bodyFatPercent: 18.5,
            waistCentimeters: 82.4,
            source: WeighInSource.demo,
          ),
        );

        expect(added.id, isPositive);
        expect(added.at, DateTime.utc(2026, 11, 14, 12));
        expect(added.at.isUtc, isTrue);
        expect(added.offsetMinutes, -180);
        expect(added.kilograms, closeTo(78.2, 1e-9));
        expect(added.bodyFatPercent, 18.5);
        expect(added.waistCentimeters, 82.4);
        expect(added.source, WeighInSource.demo);
        expect(await store.all(), [added]);
      });

      test('a stored row round-trips nulls', () async {
        final added = await store.add(draft());

        final read = (await store.all()).single;

        expect(read, added);
        expect(read.bodyFatPercent, isNull);
        expect(read.waistCentimeters, isNull);
        expect(read.source, WeighInSource.manual);
      });

      test('all is empty on a fresh store and count is zero', () async {
        expect(await store.all(), isEmpty);
        expect(await store.count(), 0);
      });

      test('all orders newest first', () async {
        final older = await store.add(draft(at: DateTime.utc(2026, 11, 10)));
        final newest = await store.add(draft(at: DateTime.utc(2026, 11, 14)));
        final middle = await store.add(draft(at: DateTime.utc(2026, 11, 12)));

        expect(await store.all(), [newest, middle, older]);
        expect(await store.count(), 3);
      });

      test('two weigh-ins in the same minute are both kept', () async {
        final first = await store.add(
          draft(at: DateTime.utc(2026, 11, 14, 7, 30)),
        );
        final second = await store.add(
          draft(at: DateTime.utc(2026, 11, 14, 7, 30), kilograms: 78.4),
        );

        expect(await store.count(), 2);
        expect(await store.all(), [second, first]);
      });

      test('update changes the row and returns true', () async {
        final added = await store.add(draft());

        final changed = await store.update(
          added.id,
          draft(kilograms: 80, bodyFatPercent: 20),
        );

        expect(changed, isTrue);
        final read = (await store.all()).single;
        expect(read.id, added.id);
        expect(read.kilograms, 80);
        expect(read.bodyFatPercent, 20);
      });

      test(
        'update on a missing id returns false and changes nothing',
        () async {
          final added = await store.add(draft());

          final changed = await store.update(
            added.id + 100,
            draft(kilograms: 99),
          );

          expect(changed, isFalse);
          expect(await store.all(), [added]);
        },
      );

      test('delete removes the row and returns true', () async {
        final added = await store.add(draft());

        expect(await store.delete(added.id), isTrue);
        expect(await store.all(), isEmpty);
      });

      test('delete on a missing id returns false', () async {
        final added = await store.add(draft());

        expect(await store.delete(added.id + 100), isFalse);
        expect(await store.count(), 1);
      });

      test('deleteAll returns the count and leaves none', () async {
        await store.add(draft());
        await store.add(draft(at: DateTime.utc(2026, 11, 13)));

        expect(await store.deleteAll(), 2);
        expect(await store.count(), 0);
      });

      test('deleteAll on an empty store returns 0', () async {
        expect(await store.deleteAll(), 0);
      });

      test('kilograms 78.204 reads back as 78.2', () async {
        await store.add(draft(kilograms: 78.204));

        expect((await store.all()).single.kilograms, closeTo(78.2, 1e-9));
      });

      test('kilograms 78.206 reads back as 78.21', () async {
        await store.add(draft(kilograms: 78.206));

        expect((await store.all()).single.kilograms, closeTo(78.21, 1e-9));
      });

      test('update also rounds kilograms to 0.01', () async {
        final added = await store.add(draft());

        await store.update(added.id, draft(kilograms: 78.206));

        expect((await store.all()).single.kilograms, closeTo(78.21, 1e-9));
      });

      test('172.4 lb survives a store round trip at one decimal', () async {
        final kilograms = ImperialUnits.kilograms(172.4);

        await store.add(draft(kilograms: kilograms));

        final pounds = ImperialUnits.pounds(
          (await store.all()).single.kilograms,
        );
        expect((pounds * 10).round() / 10, 172.4);
      });

      test('each entry keeps the offset it was given', () async {
        final instant = DateTime.utc(2026, 11, 14, 2, 50);
        final west = await store.add(draft(at: instant, offsetMinutes: -180));
        final utc = await store.add(draft(at: instant, offsetMinutes: 0));

        final read = {for (final w in await store.all()) w.id: w};

        expect(read[west.id]!.offsetMinutes, -180);
        expect(read[utc.id]!.offsetMinutes, 0);
        expect(read[west.id]!.at, instant);
        expect(read[utc.id]!.at, instant);
      });

      test('same instant ties order by id descending', () async {
        final instant = DateTime.utc(2026, 11, 14, 2, 50);
        final first = await store.add(draft(at: instant));
        final second = await store.add(draft(at: instant));

        expect((await store.all()).map((w) => w.id), [second.id, first.id]);
      });
    });
  }
}

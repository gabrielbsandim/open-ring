import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/features/open_score/application/day_tag_providers.dart';
import 'package:open_ring/features/open_score/domain/day_tag.dart';
import 'package:open_ring/features/open_score/domain/day_tag_store.dart';

const _today = LocalDate(2026, 11, 14);

LocalDate _ago(int age) => _today.addDays(-age);

void main() {
  late DateTime now;
  late InMemoryDayTagStore store;
  late ProviderContainer container;

  setUp(() {
    now = DateTime.utc(2026, 11, 14, 12);
    store = InMemoryDayTagStore();
    container = ProviderContainer.test(
      overrides: [
        dayTagStoreProvider.overrideWithValue(store),
        clockProvider.overrideWithValue(() => now),
      ],
    )..listen(dayTagsProvider, (_, _) {});
  });

  Future<bool> set(LocalDate date, DayTag? tag) =>
      container.read(dayTagLogProvider.notifier).set(date, tag);

  Future<Map<LocalDate, DayTag>> tags() =>
      container.read(dayTagsProvider.future);

  test('the default store provider is an in-memory store', () {
    final fresh = ProviderContainer.test();

    expect(fresh.read(dayTagStoreProvider), isA<InMemoryDayTagStore>());
  });

  for (var age = 0; age <= 6; age++) {
    test(
      'a tag for a date $age days old is accepted and then visible',
      () async {
        expect(await tags(), isEmpty);

        expect(await set(_ago(age), DayTag.sick), isTrue);

        expect(await tags(), {_ago(age): DayTag.sick});
        expect(await store.all(), {_ago(age): DayTag.sick});
      },
    );
  }

  test(
    'a date 7 days old returns false and leaves the store untouched',
    () async {
      await store.put(_ago(7), DayTag.rest, now: now);

      expect(await set(_ago(7), DayTag.sick), isFalse);
      expect(await set(_ago(7), null), isFalse);

      expect(await store.all(), {_ago(7): DayTag.rest});
    },
  );

  test('a future date returns false and leaves the store untouched', () async {
    expect(await set(_today.addDays(1), DayTag.travel), isFalse);

    expect(await store.all(), isEmpty);
    expect(await tags(), isEmpty);
  });

  test('null removes the tag and the read follows', () async {
    await set(_ago(2), DayTag.rest);
    expect(await tags(), {_ago(2): DayTag.rest});

    expect(await set(_ago(2), null), isTrue);

    expect(await tags(), isEmpty);
    expect(await store.all(), isEmpty);
  });

  test('null on an untagged date in the window writes nothing', () async {
    expect(await set(_ago(2), null), isFalse);

    expect(await store.all(), isEmpty);
  });

  test('the same tag again returns false', () async {
    await set(_ago(1), DayTag.sick);

    expect(await set(_ago(1), DayTag.sick), isFalse);
  });

  test('another tag overwrites and the read follows', () async {
    await set(_ago(1), DayTag.sick);
    expect(await tags(), {_ago(1): DayTag.sick});

    expect(await set(_ago(1), DayTag.travel), isTrue);

    expect(await tags(), {_ago(1): DayTag.travel});
  });

  test('age 6 tagged before midnight stays readable after midnight', () async {
    now = DateTime.utc(2026, 11, 14, 23, 59);
    expect(await set(_ago(6), DayTag.sick), isTrue);

    now = DateTime.utc(2026, 11, 15, 0, 1);

    expect(await tags(), {_ago(6): DayTag.sick});
    expect(await set(_ago(6), DayTag.rest), isFalse);
    expect(await set(_ago(6), null), isFalse);
    expect(await store.all(), {_ago(6): DayTag.sick});
  });

  test('the window follows the clock when it moves forward', () async {
    expect(await set(_today.addDays(1), DayTag.rest), isFalse);

    now = DateTime.utc(2026, 11, 15, 8);

    expect(await set(_today.addDays(1), DayTag.rest), isTrue);
  });
}

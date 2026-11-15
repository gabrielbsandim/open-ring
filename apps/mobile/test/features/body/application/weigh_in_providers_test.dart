import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/core/records/data_revision.dart';
import 'package:open_ring/features/body/application/weigh_in_providers.dart';
import 'package:open_ring/features/body/domain/weigh_in.dart';
import 'package:open_ring/features/body/domain/weigh_in_store.dart';

void main() {
  final now = DateTime.utc(2026, 11, 14, 12);

  late InMemoryWeighInStore store;
  late ProviderContainer container;

  WeighInDraft draft({double kilograms = 78.2, DateTime? at}) =>
      WeighInDraft(at: at ?? now, offsetMinutes: -180, kilograms: kilograms);

  setUp(() {
    store = InMemoryWeighInStore();
    container = ProviderContainer.test(
      overrides: [
        weighInStoreProvider.overrideWithValue(store),
        clockProvider.overrideWithValue(() => now),
      ],
    );
  });

  WeighInLog log() => container.read(weighInLogProvider.notifier);
  int revision() => container.read(dataRevisionProvider);

  test('the default store provider is an in-memory store', () {
    final fresh = ProviderContainer.test();

    expect(fresh.read(weighInStoreProvider), isA<InMemoryWeighInStore>());
  });

  test('a valid add stores the row and bumps the revision once', () async {
    final issues = await log().add(draft());

    expect(issues, isEmpty);
    expect(await store.count(), 1);
    expect(revision(), 1);
  });

  test(
    'an invalid add stores nothing, bumps nothing and returns issues',
    () async {
      final issues = await log().add(draft(kilograms: 5));

      expect(issues, {WeighInIssue.kilograms});
      expect(await store.count(), 0);
      expect(revision(), 0);
    },
  );

  test('an add 61 seconds ahead of the clock is rejected as future', () async {
    final issues = await log().add(
      draft(at: now.add(const Duration(seconds: 61))),
    );

    expect(issues, {WeighInIssue.future});
    expect(await store.count(), 0);
  });

  test('a valid update changes the row and bumps once', () async {
    final added = await store.add(draft());

    final issues = await log().update(added.id, draft(kilograms: 80));

    expect(issues, isEmpty);
    expect((await store.all()).single.kilograms, 80);
    expect(revision(), 1);
  });

  test('an invalid update writes nothing and bumps nothing', () async {
    final added = await store.add(draft());

    final issues = await log().update(added.id, draft(kilograms: 500));

    expect(issues, {WeighInIssue.kilograms});
    expect((await store.all()).single.kilograms, 78.2);
    expect(revision(), 0);
  });

  test('an update on a missing id bumps nothing', () async {
    await log().update(42, draft());

    expect(revision(), 0);
    expect(await store.count(), 0);
  });

  test('delete on an existing id bumps once', () async {
    final added = await store.add(draft());

    await log().delete(added.id);

    expect(await store.count(), 0);
    expect(revision(), 1);
  });

  test('delete on a missing id bumps nothing', () async {
    await log().delete(42);

    expect(revision(), 0);
  });

  test('deleteAll on an empty store bumps nothing', () async {
    await log().deleteAll();

    expect(revision(), 0);
  });

  test('deleteAll on a non-empty store bumps once', () async {
    await store.add(draft());
    await store.add(draft(kilograms: 79));

    await log().deleteAll();

    expect(await store.count(), 0);
    expect(revision(), 1);
  });

  test('weighInsProvider returns the new list after an add', () async {
    expect(await container.read(weighInsProvider.future), isEmpty);

    await log().add(draft());

    final list = await container.read(weighInsProvider.future);
    expect(list, hasLength(1));
    expect(list.single.kilograms, 78.2);
  });

  test('weighInsProvider lists newest first', () async {
    await log().add(draft(at: DateTime.utc(2026, 11, 10)));
    await log().add(draft(at: DateTime.utc(2026, 11, 13)));

    final list = await container.read(weighInsProvider.future);

    expect(list.map((w) => w.at), [
      DateTime.utc(2026, 11, 13),
      DateTime.utc(2026, 11, 10),
    ]);
  });

  test('rows written through the log have source manual', () async {
    await log().add(draft());

    expect((await store.all()).single.source, WeighInSource.manual);
  });
}

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/core/records/data_revision.dart';
import 'package:open_ring/core/records/health_record_kind.dart';
import 'package:open_ring/core/records/source_priority.dart';
import 'package:open_ring/features/health_sync/application/health_read_controller.dart';
import 'package:open_ring/features/health_sync/domain/health_read_store.dart';
import 'package:open_ring/features/health_sync/domain/health_writer.dart';

import '../../../helpers/fake_health_reader.dart';

void main() {
  const watch = 'com.garmin.android.apps.connectmobile';
  final now = DateTime.utc(2026, 11, 10, 9);

  late FakeHealthReader reader;
  late InMemoryHealthReadStore store;

  ProviderContainer container() => ProviderContainer.test(
    overrides: [
      clockProvider.overrideWithValue(() => now),
      healthReaderProvider.overrideWithValue(reader),
      healthReadStoreProvider.overrideWithValue(store),
    ],
  );

  setUp(() {
    reader = FakeHealthReader(
      nights: [externalNight(watch, DateTime.utc(2026, 11, 9, 23))],
    );
    store = InMemoryHealthReadStore();
  });

  test('starts off with the ring as the only source', () async {
    final view = await container().read(healthReadProvider.future);

    expect(view.enabled, isFalse);
    expect(view.priority, [ringSource]);
    expect(view.single, isTrue);
  });

  test('turning sleep on asks for sleep read access and imports', () async {
    final c = container();
    await c.read(healthReadProvider.future);
    final revision = c.read(dataRevisionProvider);

    await c.read(healthReadProvider.notifier).setEnabled(enabled: true);

    final view = c.read(healthReadProvider).requireValue;
    expect(reader.requests, [HealthRecordKind.sleep]);
    expect(view.enabled, isTrue);
    expect(view.access, HealthAccess.granted);
    expect(view.priority, [ringSource, watch]);
    expect(view.sources.single.records, 1);
    expect(c.read(dataRevisionProvider), greaterThan(revision));
  });

  test('a declined request keeps reading off and offers settings', () async {
    reader.grantOnRequest = false;
    final c = container();
    await c.read(healthReadProvider.future);

    await c.read(healthReadProvider.notifier).setEnabled(enabled: true);

    final view = c.read(healthReadProvider).requireValue;
    expect(view.enabled, isFalse);
    expect(view.declined, isTrue);
    expect(reader.reads, isEmpty);
    expect((await store.settings(HealthRecordKind.sleep)).enabled, isFalse);
  });

  test('moving a source saves the new order', () async {
    final c = container();
    await c.read(healthReadProvider.future);
    await c.read(healthReadProvider.notifier).setEnabled(enabled: true);

    await c.read(healthReadProvider.notifier).move(1, 0);

    expect(c.read(healthReadProvider).requireValue.priority, [
      watch,
      ringSource,
    ]);
    expect(await store.storedPriority(HealthRecordKind.sleep), [
      watch,
      ringSource,
    ]);
  });

  test('turning sleep off leaves the ring alone in the order', () async {
    final c = container();
    await c.read(healthReadProvider.future);
    await c.read(healthReadProvider.notifier).setEnabled(enabled: true);

    await c.read(healthReadProvider.notifier).setEnabled(enabled: false);

    final view = c.read(healthReadProvider).requireValue;
    expect(view.enabled, isFalse);
    expect(view.priority, [ringSource]);
    expect(store.nights, hasLength(1));
  });

  test('workouts have their own switch, order and import', () async {
    reader.sessions = [externalWorkout(watch, DateTime.utc(2026, 11, 9, 18))];
    final c = container();
    await c.read(workoutReadProvider.future);
    await c.read(healthReadProvider.future);

    await c.read(workoutReadProvider.notifier).setEnabled(enabled: true);

    expect(reader.requests, [HealthRecordKind.workout]);
    final workouts = c.read(workoutReadProvider).requireValue;
    expect(workouts.enabled, isTrue);
    expect(workouts.priority, [ringSource, watch]);
    expect(store.workouts, hasLength(1));
    expect(store.nights, isEmpty);
    expect(c.read(healthReadProvider).requireValue.enabled, isFalse);
  });
}

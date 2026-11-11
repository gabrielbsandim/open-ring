import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/ring/domain/sync_store.dart';
import 'package:open_ring/features/workout/domain/live_heart_rate_source.dart';
import 'package:open_ring/features/workout/infrastructure/ring_live_heart_rate_source.dart';
import 'package:ring_driver/ring_driver.dart';

import '../../../helpers/fake_ring_driver.dart';
import '../../../helpers/ring_fakes.dart';

final now = DateTime.utc(2026, 11, 10, 7);

LiveReading reading(int bpm) =>
    LiveReading(kind: LiveKind.heartRate, value: bpm, at: now);

void main() {
  late FakeRingDriver driver;
  late FakeSyncStore store;
  late InMemorySyncLock lock;
  late StreamController<void> renewals;

  setUp(() {
    driver = FakeRingDriver();
    store = FakeSyncStore(ring: const PairedRing(deviceId: fakeRingId));
    lock = InMemorySyncLock();
    renewals = StreamController<void>.broadcast(sync: true);
  });

  RingLiveHeartRateSource source() => RingLiveHeartRateSource(
    driver: driver,
    store: store,
    lock: lock,
    clock: () => now,
    renewals: () => renewals.stream,
    newOwner: () => 'workout',
  );

  test(
    'streams 0x1E HR from the paired ring, not the 0x69 spot measure',
    () async {
      final values = <int>[];
      final subscription = source().bpm().listen(values.add);
      await pumpEventQueue();

      expect(driver.calls, ['connect', 'startHeartRateStream']);
      expect(driver.liveKind, isNull);
      expect(lock.holder, 'workout');

      driver
        ..emitLive(reading(121))
        ..emitLive(reading(124));
      await pumpEventQueue();
      expect(values, [121, 124]);

      await subscription.cancel();
      expect(driver.calls, [
        'connect',
        'startHeartRateStream',
        'stopHeartRateStream',
        'disconnect',
      ]);
      expect(lock.holder, isNull);
    },
  );

  test('gives the lock back and takes it again on every renewal', () async {
    final subscription = source().bpm().listen((_) {});
    await pumpEventQueue();

    renewals.add(null);
    await pumpEventQueue();
    renewals.add(null);
    await pumpEventQueue();

    expect(lock.releases, 2);
    expect(lock.holder, 'workout');
    await subscription.cancel();
    expect(lock.releases, 3);
    expect(renewals.hasListener, isFalse);
  });

  Future<HeartRateProblem?> problemOf(RingLiveHeartRateSource source) async {
    HeartRateProblem? problem;
    final subscription = source.bpm().listen(
      (_) {},
      onError: (Object error) =>
          problem = (error as HeartRateUnavailable).problem,
    );
    await pumpEventQueue();
    await subscription.cancel();
    return problem;
  }

  test('reports a missing ring without touching the radio', () async {
    store.ring = null;

    expect(await problemOf(source()), HeartRateProblem.noRing);
    expect(driver.calls, isEmpty);
  });

  test('reports a busy ring when a sync holds the lock', () async {
    lock.holder = 'sync';

    expect(await problemOf(source()), HeartRateProblem.busy);
    expect(driver.calls, isEmpty);
    expect(lock.holder, 'sync');
  });

  test('reports an unreachable ring and still releases the lock', () async {
    driver.connectError = StateError('out of range');

    expect(await problemOf(source()), HeartRateProblem.unreachable);
    expect(driver.calls, ['connect', 'disconnect']);
    expect(lock.holder, isNull);
  });

  test('a live stream error is reported as unreachable', () async {
    driver.liveError = StateError('notify failed');

    expect(await problemOf(source()), HeartRateProblem.unreachable);
    expect(driver.calls, [
      'connect',
      'startHeartRateStream',
      'stopHeartRateStream',
      'disconnect',
    ]);
  });

  test('a cancel before the lock is taken never touches the radio', () async {
    final subscription = source().bpm().listen((_) {});
    await subscription.cancel();
    await pumpEventQueue();

    expect(driver.calls, isEmpty);
    expect(lock.holder, isNull);
  });
}

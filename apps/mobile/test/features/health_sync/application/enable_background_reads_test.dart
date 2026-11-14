import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/core/records/health_record_kind.dart';
import 'package:open_ring/features/demo/application/demo_mode_controller.dart';
import 'package:open_ring/features/demo/domain/demo_mode_store.dart';
import 'package:open_ring/features/health_sync/application/enable_background_reads.dart';
import 'package:open_ring/features/health_sync/application/health_read_controller.dart';
import 'package:open_ring/features/health_sync/domain/health_read_store.dart';
import 'package:open_ring/features/ring/application/ring_sync_controller.dart';
import 'package:open_ring/features/ring/application/sync_interval_controller.dart';
import 'package:open_ring/features/ring/domain/sync_interval.dart';
import 'package:open_ring/features/ring/domain/sync_scheduler.dart';
import 'package:open_ring/features/ring/domain/sync_store.dart';

import '../../../helpers/fake_health_reader.dart';
import '../../../helpers/fake_sync_scheduler.dart';
import '../../../helpers/in_memory_sync_interval_store.dart';
import '../../../helpers/ring_fakes.dart' show FakeSyncStore, fakeRingId;

void main() {
  late FakeHealthReader reader;
  late InMemoryHealthReadStore reads;
  late FakeSyncScheduler scheduler;

  setUp(() {
    reader = FakeHealthReader();
    reads = InMemoryHealthReadStore();
    scheduler = FakeSyncScheduler();
  });

  group('wantsBackgroundSync', () {
    const ring = PairedRing(deviceId: fakeRingId);

    Future<bool> wants({PairedRing? paired}) => wantsBackgroundSync(
      rings: FakeSyncStore(ring: paired),
      reads: reads,
      reader: reader,
    );

    test('a paired ring wants it without calling the reader', () async {
      expect(await wants(paired: ring), isTrue);
      expect(reader.backgroundChecks, 0);
    });

    test('no ring, a sleep read on and the grant wants it', () async {
      await reads.setEnabled(HealthRecordKind.sleep, enabled: true);
      reader.backgroundAllowed = true;

      expect(await wants(), isTrue);
    });

    test('no ring, a workout read on and the grant wants it', () async {
      await reads.setEnabled(HealthRecordKind.workout, enabled: true);
      reader.backgroundAllowed = true;

      expect(await wants(), isTrue);
    });

    test('no ring and a read on without the grant does not', () async {
      await reads.setEnabled(HealthRecordKind.sleep, enabled: true);

      expect(await wants(), isFalse);
    });

    test('no ring, no read on and the grant does not', () async {
      reader.backgroundAllowed = true;

      expect(await wants(), isFalse);
    });

    test('a reader that throws does not', () async {
      await reads.setEnabled(HealthRecordKind.sleep, enabled: true);
      reader.backgroundCheck = () async => throw StateError('no plugin');

      expect(await wants(), isFalse);
    });

    testWidgets('a reader that hangs ends false at the import limit', (
      tester,
    ) async {
      await reads.setEnabled(HealthRecordKind.sleep, enabled: true);
      reader.backgroundCheck = () => Completer<bool>().future;
      bool? answer;

      unawaited(wants().then((value) => answer = value));
      await tester.pump(ringlessImportLimit - const Duration(seconds: 1));
      expect(answer, isNull);
      await tester.pump(const Duration(seconds: 2));

      expect(answer, isFalse);
    });
  });

  group('enableBackgroundReadsProvider', () {
    ProviderContainer containerWith({PairedRing? ring, bool demo = false}) =>
        ProviderContainer.test(
          overrides: [
            syncStoreProvider.overrideWithValue(FakeSyncStore(ring: ring)),
            syncSchedulerProvider.overrideWithValue(scheduler),
            syncIntervalStoreProvider.overrideWithValue(
              InMemorySyncIntervalStore(SyncInterval.minutes30),
            ),
            healthReaderProvider.overrideWithValue(reader),
            healthReadStoreProvider.overrideWithValue(reads),
            demoModeStoreProvider.overrideWithValue(
              InMemoryDemoModeStore(enabled: demo),
            ),
          ],
        );

    test('a paired ring is a no-op', () async {
      await reads.setEnabled(HealthRecordKind.sleep, enabled: true);
      final container = containerWith(
        ring: const PairedRing(deviceId: fakeRingId),
      );

      final allowed = await container.read(enableBackgroundReadsProvider)();

      expect(allowed, isFalse);
      expect(reader.backgroundRequests, 0);
      expect(scheduler.calls, isEmpty);
      expect(scheduler.cancels, 0);
    });

    test('the demo is a no-op', () async {
      await reads.setEnabled(HealthRecordKind.sleep, enabled: true);
      final container = containerWith(demo: true);

      final allowed = await container.read(enableBackgroundReadsProvider)();

      expect(allowed, isFalse);
      expect(reader.backgroundRequests, 0);
      expect(scheduler.calls, isEmpty);
      expect(scheduler.cancels, 0);
    });

    test('no read on is a no-op', () async {
      final container = containerWith();

      final allowed = await container.read(enableBackgroundReadsProvider)();

      expect(allowed, isFalse);
      expect(reader.backgroundRequests, 0);
      expect(scheduler.calls, isEmpty);
      expect(scheduler.cancels, 0);
    });

    test('an access already allowed skips the request and schedules', () async {
      await reads.setEnabled(HealthRecordKind.workout, enabled: true);
      reader.backgroundAllowed = true;
      final container = containerWith();

      final allowed = await container.read(enableBackgroundReadsProvider)();

      expect(allowed, isTrue);
      expect(reader.backgroundRequests, 0);
      expect(scheduler.calls, [
        (interval: SyncInterval.minutes30, existing: ExistingSchedule.keep),
      ]);
    });

    test(
      'no ring, a read on and no access asks once, then schedules',
      () async {
        await reads.setEnabled(HealthRecordKind.sleep, enabled: true);
        final container = containerWith();

        final allowed = await container.read(enableBackgroundReadsProvider)();

        expect(allowed, isTrue);
        expect(reader.backgroundRequests, 1);
        expect(scheduler.calls, [
          (interval: SyncInterval.minutes30, existing: ExistingSchedule.keep),
        ]);
      },
    );

    test('a declined request returns false and leaves no job', () async {
      await reads.setEnabled(HealthRecordKind.sleep, enabled: true);
      reader.grantBackgroundOnRequest = false;
      final container = containerWith();

      final allowed = await container.read(enableBackgroundReadsProvider)();

      expect(allowed, isFalse);
      expect(reader.backgroundRequests, 1);
      expect(scheduler.calls, isEmpty);
      expect(scheduler.cancels, 1);
    });
  });
}

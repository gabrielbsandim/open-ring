import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/core/database/app_database.dart';
import 'package:open_ring/core/records/record_kind.dart';
import 'package:open_ring/features/health_sync/infrastructure/health_outbox_dao.dart';
import 'package:open_ring/features/ring/application/ring_sync_state.dart';
import 'package:open_ring/features/ring/application/sync_ring.dart';
import 'package:open_ring/features/ring/domain/auto_measurements.dart';
import 'package:open_ring/features/ring/infrastructure/drift_sync_store.dart';
import 'package:open_ring/features/ring/infrastructure/ring_devices_dao.dart';
import 'package:open_ring/features/ring/infrastructure/sleep_dao.dart';
import 'package:open_ring/features/ring/infrastructure/sync_cursors_dao.dart';
import 'package:open_ring/features/ring/infrastructure/write_summary.dart';
import 'package:ring_driver/ring_driver.dart';
import 'package:ring_driver/testing.dart';

import '../../../helpers/colmi_frames.dart';
import '../../../helpers/database.dart';
import '../../../helpers/fake_ring_driver.dart';
import '../../../helpers/sync_fixtures.dart';

class ThrowingSleepDao extends SleepDao {
  new(super.attachedDatabase);

  @override
  Future<WriteSummary> replaceNights(
    String deviceId,
    List<SleepSegment> segments,
  ) => throw StateError('disk full');
}

void main() {
  late AppDatabase db;
  late FakeRingDriver driver;
  late DateTime now;

  setUp(() async {
    db = await pairedDatabase();
    driver = loadedDriver();
    now = syncNow;
  });

  SyncRing syncWith({
    DriftSyncStore? store,
    AutoMeasurements measurements = AutoMeasurements.allOn,
  }) => SyncRing(
    driver: driver,
    store: store ?? DriftSyncStore(db),
    clock: () => now,
    measurements: measurements,
  );

  Future<Map<RecordKind, DateTime>> cursors() =>
      SyncCursorsDao(db).cursorsFor(ringId);

  Future<List<RecordKind>> outboxKinds() async => [
    for (final entry in await HealthOutboxDao(db).pending())
      RecordKind.values.byName(entry.kind.name),
  ];

  Matcher abortedAt(SyncStep step) =>
      throwsA(isA<SyncAbortedException>().having((e) => e.step, 'step', step));

  group('first sync', () {
    test('writes every kind, enqueues each and sets the cursors', () async {
      final progress = <SyncProgress>[];

      final report = await syncWith()(ringId, onProgress: progress.add);

      expect(report.failures, isEmpty);
      expect(report.battery?.percent, 80);
      expect(report.written, {
        RecordKind.activity: 2,
        RecordKind.heartRate: 3,
        RecordKind.spo2: 1,
        RecordKind.stress: 1,
        RecordKind.hrv: 1,
        RecordKind.sleep: 5,
      });
      expect(await rowCount(db, 'hr_samples'), 3);
      expect(await rowCount(db, 'sleep_segments'), 4);
      expect(await rowCount(db, 'sleep_sessions'), 1);
      expect(await outboxKinds(), RecordKind.values);
      expect(await cursors(), {
        RecordKind.activity: eveningActivity.last.start,
        RecordKind.heartRate: nightHeartRate.last.at,
        RecordKind.spo2: DateTime(2026, 11, 10, 3),
        RecordKind.stress: DateTime(2026, 11, 9, 21, 30),
        RecordKind.hrv: DateTime(2026, 11, 10, 2),
        RecordKind.sleep: nightStart,
      });
      final ring = await RingDevicesDao(db).find(ringId);
      expect(ring?.lastSyncAtUtcMs, now.millisecondsSinceEpoch);
      expect(ring?.batteryPercent, 80);
      expect(progress.first, const SyncProgress(SyncStep.connecting));
      expect(
        progress,
        containsAllInOrder([
          const SyncProgress(SyncStep.settingTime),
          const SyncProgress(SyncStep.readingBattery),
          const SyncProgress(SyncStep.pulling, kind: RecordKind.activity),
          const SyncProgress(SyncStep.pulling, kind: RecordKind.sleep),
          const SyncProgress(SyncStep.saving),
        ]),
      );
      expect(progress.last, const SyncProgress(SyncStep.disconnecting));
    });

    test('pulls from the backfill window when there is no cursor', () async {
      await syncWith()(ringId);

      final window = now.subtract(const Duration(days: 7));
      for (final since in driver.sinces.values) {
        expect(since, [window]);
      }
      expect(driver.sinces.keys, hasLength(6));
    });

    test('skips capabilities the driver does not declare', () async {
      driver.capabilities = {RingCapability.heartRateLog};

      final report = await syncWith()(ringId);

      expect(report.written.keys, [RecordKind.heartRate]);
      expect(report.battery, isNull);
      expect(driver.calls, isNot(contains('battery')));
      expect(await cursors(), {RecordKind.heartRate: nightHeartRate.last.at});
    });
  });

  group('second sync', () {
    test('only pulls after each cursor and writes what is new', () async {
      await syncWith()(ringId);
      final first = await cursors();
      final newSample = HeartRateSample(
        at: DateTime(2026, 11, 10, 8, 5),
        bpm: 66,
      );
      driver.heartRate = [...driver.heartRate, newSample];
      now = DateTime(2026, 11, 10, 8, 10);

      final report = await syncWith()(ringId);

      for (final MapEntry(key: kind, value: cursor) in first.entries) {
        final capability = SyncRing.capabilityOf(kind);
        expect(driver.sinces[capability]?.last, cursor, reason: kind.name);
      }
      expect(report.written[RecordKind.heartRate], 1);
      expect(report.written[RecordKind.sleep], 0);
      expect(await rowCount(db, 'hr_samples'), 4);
      expect(await outboxKinds(), [...RecordKind.values, RecordKind.heartRate]);
      expect((await cursors())[RecordKind.heartRate], newSample.at);
    });

    test('duplicate samples write no rows and enqueue nothing', () async {
      await syncWith()(ringId);
      now = now.add(const Duration(minutes: 30));

      final report = await syncWith()(ringId);

      expect(report.written.values, everyElement(0));
      expect(await rowCount(db, 'hr_samples'), 3);
      expect(await rowCount(db, 'activity_buckets'), 2);
      expect(await rowCount(db, 'sleep_segments'), 4);
      expect(await outboxKinds(), RecordKind.values);
    });
  });

  group('partial failure', () {
    test('a failing capability keeps the others and its own cursor', () async {
      final failure = StateError('spo2 timed out');
      driver.failing[RingCapability.spo2] = failure;

      final report = await syncWith()(ringId);

      expect(report.failures, {RingCapability.spo2: failure});
      expect(report.written.keys, isNot(contains(RecordKind.spo2)));
      expect(await rowCount(db, 'spo2_samples'), 0);
      expect(await rowCount(db, 'hr_samples'), 3);
      expect(await outboxKinds(), isNot(contains(RecordKind.spo2)));
      expect((await cursors()).keys, isNot(contains(RecordKind.spo2)));
      expect(driver.disconnects, 1);

      driver.failing.clear();
      await syncWith()(ringId);

      expect(
        driver.sinces[RingCapability.spo2]?.last,
        now.subtract(const Duration(days: 7)),
      );
      expect(await rowCount(db, 'spo2_samples'), 1);
    });

    test('reports the battery as soon as it is read', () async {
      final percents = <int>[];

      await syncWith()(
        ringId,
        onBattery: (battery) => percents.add(battery.percent),
      );

      expect(percents, [driver.battery.percent]);
    });

    test('a failing battery read still saves the history', () async {
      driver.failing[RingCapability.battery] = StateError('no reply');

      final report = await syncWith()(ringId);

      expect(report.failures.keys, [RingCapability.battery]);
      expect(report.battery, isNull);
      expect(await rowCount(db, 'hr_samples'), 3);
    });
  });

  group('disconnect', () {
    test('runs after a successful sync', () async {
      await syncWith()(ringId);

      expect(driver.calls.first, 'connect');
      expect(driver.calls.last, 'disconnect');
      expect(driver.disconnects, 1);
    });

    test('runs when connect fails', () async {
      driver.connectError = const BleTransportException('out of range');

      await expectLater(syncWith()(ringId), abortedAt(SyncStep.connecting));

      expect(driver.disconnects, 1);
      expect(await rowCount(db, 'hr_samples'), 0);
    });

    test('runs when setting the time fails', () async {
      driver.syncTimeError = StateError('no reply');

      await expectLater(syncWith()(ringId), abortedAt(SyncStep.settingTime));

      expect(driver.disconnects, 1);
      expect(driver.calls, isNot(contains(RingCapability.heartRateLog.name)));
    });

    test('a failing disconnect does not hide a successful sync', () async {
      driver.disconnectError = const BleTransportException('already gone');

      final report = await syncWith()(ringId);

      expect(report.written[RecordKind.heartRate], 3);
      expect(driver.disconnects, 1);
    });
  });

  group('heart rate interval', () {
    test('sets the ring to five minutes after the time', () async {
      await syncWith()(ringId);

      expect(driver.heartRateInterval, const Duration(minutes: 5));
      final calls = driver.calls;
      expect(
        calls.indexOf('setHeartRateInterval'),
        greaterThan(calls.indexOf('syncTime')),
      );
    });

    test('reports the interval the ring had before the sync', () async {
      final report = await syncWith()(ringId);

      expect(report.heartRateIntervalSeen, const Duration(minutes: 30));
    });

    test('reports a ring found with heart rate off as zero', () async {
      driver.heartRateInterval = null;

      final report = await syncWith()(ringId);

      expect(report.heartRateIntervalSeen, Duration.zero);
    });

    test('leaves a ring already at five minutes alone', () async {
      driver.heartRateInterval = const Duration(minutes: 5);

      await syncWith()(ringId);

      expect(driver.calls, isNot(contains('setHeartRateInterval')));
    });

    test('a failed read is reported and the sync goes on', () async {
      driver.failing[RingCapability.heartRateInterval] = StateError('nope');

      final report = await syncWith()(ringId);

      expect(report.failures.keys, contains(RingCapability.heartRateInterval));
      expect(report.written[RecordKind.heartRate], 3);
    });

    test('turns the log off when the user turned heart rate off', () async {
      driver.heartRateInterval = const Duration(minutes: 5);

      await syncWith(
        measurements: const AutoMeasurements(off: {AutoMeasurement.heartRate}),
      )(ringId);

      expect(driver.calls, contains('setHeartRateInterval'));
      expect(driver.heartRateInterval, isNull);
    });

    test('leaves a ring already off alone when heart rate is off', () async {
      driver.heartRateInterval = null;

      await syncWith(
        measurements: const AutoMeasurements(off: {AutoMeasurement.heartRate}),
      )(ringId);

      expect(driver.calls, isNot(contains('setHeartRateInterval')));
    });
  });

  group('automatic monitors', () {
    test('writes only the monitors that differ from the choice', () async {
      driver.monitors[RingMonitor.hrv] = false;

      await syncWith(
        measurements: const AutoMeasurements(off: {AutoMeasurement.stress}),
      )(ringId);

      expect(driver.monitors, {
        RingMonitor.spo2: true,
        RingMonitor.stress: false,
        RingMonitor.hrv: true,
      });
      expect(driver.calls.where((c) => c == 'setMonitor'), hasLength(2));
    });

    test('a failed read is reported and the sync goes on', () async {
      driver.failing[RingCapability.autoMonitors] = StateError('nope');

      final report = await syncWith()(ringId);

      expect(report.failures.keys, contains(RingCapability.autoMonitors));
      expect(report.written[RecordKind.stress], 1);
    });

    test('a ring without the capability is never asked', () async {
      driver.capabilities = {
        ...RingCapability.values.where((c) => c != RingCapability.autoMonitors),
      };

      await syncWith()(ringId);

      expect(driver.calls, isNot(contains('readMonitor')));
    });
  });

  group('transaction', () {
    test('a failed save rolls back and leaves the cursors untouched', () async {
      await syncWith()(ringId);
      final before = await cursors();
      final lastSync = (await RingDevicesDao(db).find(ringId))?.lastSyncAtUtcMs;
      driver.heartRate = [
        ...driver.heartRate,
        HeartRateSample(at: DateTime(2026, 11, 10, 8, 5), bpm: 66),
      ];
      now = DateTime(2026, 11, 10, 9);
      final failing = DriftSyncStore(db, sleep: ThrowingSleepDao(db));

      await expectLater(
        syncWith(store: failing)(ringId),
        abortedAt(SyncStep.saving),
      );

      expect(await cursors(), before);
      expect(await rowCount(db, 'hr_samples'), 3);
      expect(await outboxKinds(), RecordKind.values);
      expect(
        (await RingDevicesDao(db).find(ringId))?.lastSyncAtUtcMs,
        lastSync,
      );
      expect(driver.disconnects, 2);
    });
  });

  group('ColmiDriver over FakeBleTransport', () {
    test('a first sync stores the tahnok heart rate capture', () async {
      final transport = FakeBleTransport(responder: tahnokRing);
      final colmi = ColmiDriver(
        transport: transport,
        clock: () => DateTime(2024, 8, 10, 23, 59),
        responseTimeout: const Duration(seconds: 2),
      );
      addTearDown(() async {
        await colmi.close();
        await transport.close();
      });

      final report = await SyncRing(
        driver: colmi,
        store: DriftSyncStore(db),
        clock: () => DateTime(2024, 8, 10, 23, 59),
      )(ringId);

      expect(report.failures, isEmpty);
      expect(report.battery?.percent, 64);
      expect(report.written[RecordKind.heartRate], 6);
      final rows = await db.select(db.hrSamples).get();
      expect(rows.map((r) => r.bpm), [89, 107, 96, 107, 80, 70]);
      expect(
        (await cursors())[RecordKind.heartRate],
        DateTime(2024, 8, 10, 21),
      );
      expect(await outboxKinds(), [RecordKind.heartRate]);
      expect(transport.current, TransportState.disconnected);
    });
  });
}

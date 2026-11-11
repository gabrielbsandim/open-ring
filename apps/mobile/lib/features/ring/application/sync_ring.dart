import 'package:meta/meta.dart';
import 'package:open_ring/core/records/record_kind.dart';
import 'package:open_ring/features/ring/application/ring_sync_state.dart';
import 'package:open_ring/features/ring/domain/auto_measurements.dart';
import 'package:open_ring/features/ring/domain/ring_sync_batch.dart';
import 'package:open_ring/features/ring/domain/sync_store.dart';
import 'package:ring_driver/ring_driver.dart';

typedef SyncProgressListener = void Function(SyncProgress progress);
typedef SyncBatteryListener = void Function(BatteryStatus battery);

final class SyncAbortedException implements Exception {
  const new(this.step, this.cause);

  final SyncStep step;
  final Object cause;

  @override
  String toString() => 'SyncAbortedException($step): $cause';
}

@immutable
final class SyncReport {
  new({
    required this.syncedAt,
    required Map<RecordKind, int> written,
    required Map<RingCapability, Object> failures,
    this.battery,
    this.heartRateIntervalSeen,
  }) : written = Map.unmodifiable(written),
       failures = Map.unmodifiable(failures);

  final DateTime syncedAt;
  final BatteryStatus? battery;
  final Duration? heartRateIntervalSeen;
  final Map<RecordKind, int> written;
  final Map<RingCapability, Object> failures;
}

final class SyncRing {
  const new({
    required this.driver,
    required this.store,
    required this.clock,
    this.backfill = const Duration(days: 7),
    this.heartRateInterval = defaultHeartRateInterval,
    this.measurements = AutoMeasurements.allOn,
  });

  static const defaultHeartRateInterval = Duration(minutes: 5);

  final SmartRingDriver driver;
  final SyncStore store;
  final DateTime Function() clock;
  final Duration backfill;
  final Duration heartRateInterval;
  final AutoMeasurements measurements;

  static RingCapability capabilityOf(RecordKind kind) => switch (kind) {
    RecordKind.activity => RingCapability.activity,
    RecordKind.heartRate => RingCapability.heartRateLog,
    RecordKind.spo2 => RingCapability.spo2,
    RecordKind.stress => RingCapability.stress,
    RecordKind.hrv => RingCapability.hrv,
    RecordKind.sleep => RingCapability.sleep,
  };

  static AutoMeasurement measurementOf(RingMonitor monitor) =>
      switch (monitor) {
        RingMonitor.spo2 => AutoMeasurement.spo2,
        RingMonitor.stress => AutoMeasurement.stress,
        RingMonitor.hrv => AutoMeasurement.hrv,
      };

  Future<SyncReport> call(
    String deviceId, {
    SyncProgressListener? onProgress,
    SyncBatteryListener? onBattery,
  }) async {
    final report = onProgress ?? (_) {};
    try {
      return await _SyncRun(this, deviceId, report, onBattery ?? (_) {}).run();
    } finally {
      report(const SyncProgress(SyncStep.disconnecting));
      await _disconnect();
    }
  }

  Future<void> _disconnect() async {
    try {
      await driver.disconnect();
    } on Object {
      // A failed disconnect cannot lose data, so it must not mask the outcome.
    }
  }
}

final class _SyncRun {
  new(this.sync, this.deviceId, this.report, this.batteryRead);

  final SyncRing sync;
  final String deviceId;
  final SyncProgressListener report;
  final SyncBatteryListener batteryRead;
  final failures = <RingCapability, Object>{};
  Map<RecordKind, DateTime> cursors = const {};
  Duration? heartRateIntervalSeen;

  SmartRingDriver get driver => sync.driver;

  Future<SyncReport> run() async {
    report(const SyncProgress(SyncStep.connecting));
    cursors = await _fatal(
      SyncStep.connecting,
      () => sync.store.cursors(deviceId),
    );
    await _fatal(SyncStep.connecting, () => driver.connect(deviceId));
    report(const SyncProgress(SyncStep.settingTime));
    await _fatal(SyncStep.settingTime, () => driver.syncTime(sync.clock()));
    await _alignHeartRateInterval();
    await _alignMonitors();
    final battery = await _readBattery();
    final batch = RingSyncBatch(
      deviceId: deviceId,
      identity: driver.identity,
      syncedAt: sync.clock(),
      battery: battery,
      activity: await _pull(RecordKind.activity, driver.pullActivity),
      heartRate: await _pull(RecordKind.heartRate, driver.pullHeartRate),
      spo2: await _pull(RecordKind.spo2, driver.pullSpo2),
      stress: await _pull(RecordKind.stress, driver.pullStress),
      hrv: await _pull(RecordKind.hrv, driver.pullHrv),
      sleep: await _pull(RecordKind.sleep, driver.pullSleep),
    );
    report(const SyncProgress(SyncStep.saving));
    final written = await _fatal(SyncStep.saving, () => sync.store.save(batch));
    await _fatal(
      SyncStep.saving,
      () => sync.store.advanceCursors(
        deviceId,
        batch.resumePoints(),
        at: batch.syncedAt,
      ),
    );
    return SyncReport(
      syncedAt: batch.syncedAt,
      battery: battery,
      heartRateIntervalSeen: heartRateIntervalSeen,
      written: written,
      failures: failures,
    );
  }

  Future<void> _alignHeartRateInterval() async {
    if (!driver.capabilities.contains(RingCapability.heartRateInterval)) return;
    final on = sync.measurements.isOn(AutoMeasurement.heartRate);
    final wanted = on ? sync.heartRateInterval : null;
    try {
      final current = await driver.readHeartRateInterval();
      heartRateIntervalSeen = current ?? Duration.zero;
      if (current == wanted) return;
      await driver.setHeartRateInterval(sync.heartRateInterval, enabled: on);
    } on Object catch (error) {
      failures[RingCapability.heartRateInterval] = error;
    }
  }

  Future<void> _alignMonitors() async {
    if (!driver.capabilities.contains(RingCapability.autoMonitors)) return;
    try {
      for (final monitor in RingMonitor.values) {
        final on = sync.measurements.isOn(SyncRing.measurementOf(monitor));
        if (await driver.readMonitor(monitor) == on) continue;
        await driver.setMonitor(monitor, enabled: on);
      }
    } on Object catch (error) {
      failures[RingCapability.autoMonitors] = error;
    }
  }

  Future<BatteryStatus?> _readBattery() async {
    if (!driver.capabilities.contains(RingCapability.battery)) return null;
    report(const SyncProgress(SyncStep.readingBattery));
    try {
      final battery = await driver.readBattery();
      batteryRead(battery);
      return battery;
    } on Object catch (error) {
      failures[RingCapability.battery] = error;
      return null;
    }
  }

  Future<List<T>?> _pull<T>(
    RecordKind kind,
    Future<List<T>> Function(DateTime since) pull,
  ) async {
    final capability = SyncRing.capabilityOf(kind);
    if (!driver.capabilities.contains(capability)) return null;
    report(SyncProgress(SyncStep.pulling, kind: kind));
    final since = cursors[kind] ?? sync.clock().subtract(sync.backfill);
    try {
      return await pull(since);
    } on Object catch (error) {
      failures[capability] = error;
      return null;
    }
  }

  static Future<T> _fatal<T>(SyncStep step, Future<T> Function() action) async {
    try {
      return await action();
    } on Object catch (error, stackTrace) {
      Error.throwWithStackTrace(SyncAbortedException(step, error), stackTrace);
    }
  }
}

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_ring/core/records/data_revision.dart';
import 'package:open_ring/features/demo/application/demo_mode_controller.dart';
import 'package:open_ring/features/health_sync/application/health_read_controller.dart';
import 'package:open_ring/features/health_sync/application/health_sync_controller.dart';
import 'package:open_ring/features/ring/application/ring_alert_providers.dart';
import 'package:open_ring/features/ring/application/ring_link_providers.dart';
import 'package:open_ring/features/ring/application/ring_sync_state.dart';
import 'package:open_ring/features/ring/application/sync_alerts.dart';
import 'package:open_ring/features/ring/application/sync_paired_ring.dart';
import 'package:open_ring/features/ring/domain/sync_lock.dart';
import 'package:open_ring/features/ring/domain/sync_store.dart';
import 'package:ring_driver/ring_driver.dart';

final syncStoreProvider = Provider<SyncStore>(
  (ref) => throw UnimplementedError('Override syncStoreProvider.'),
);

final syncLockProvider = Provider<SyncLock>(
  (ref) => throw UnimplementedError('Override syncLockProvider.'),
);

final smartRingDriverProvider = Provider<SmartRingDriver>((ref) {
  final driver = ColmiDriver(transport: ref.watch(bleTransportProvider));
  ref.onDispose(() => unawaited(driver.close()));
  return driver;
});

final syncClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

final syncPairedRingProvider = Provider<SyncPairedRing>(
  (ref) => SyncPairedRing(
    driver: ref.watch(smartRingDriverProvider),
    store: ref.watch(syncStoreProvider),
    lock: ref.watch(syncLockProvider),
    clock: ref.watch(syncClockProvider),
  ),
);

final syncAlertsProvider = Provider<SyncAlerts>(
  (ref) => SyncAlerts(
    store: ref.watch(syncStoreProvider),
    preferences: ref.watch(ringAlertPreferencesProvider),
    notifier: ref.watch(ringNotifierProvider),
    strings: ringAlertStrings(),
  ),
);

final backgroundSyncFinishedProvider = Provider<Stream<void>>(
  (ref) => const Stream.empty(),
);

final ringSyncProvider = NotifierProvider<RingSyncController, RingSyncState>(
  RingSyncController.new,
);

class RingSyncController extends Notifier<RingSyncState> {
  Future<void>? _running;

  @override
  RingSyncState build() {
    final finished = ref
        .watch(backgroundSyncFinishedProvider)
        .listen((_) => unawaited(_adoptBackgroundSync()));
    ref.onDispose(finished.cancel);
    unawaited(_restoreLastSuccess());
    return const RingSyncState();
  }

  Future<void> sync() => _join(automatic: false);

  Future<void> autoSync() => _join(automatic: true);

  Future<void> refresh() => sync();

  // The demo ring is not a device: a sync there only renews the sample data.
  Future<void> _join({required bool automatic}) {
    if (ref.read(demoModeProvider)) {
      return ref.read(demoModeProvider.notifier).refresh();
    }
    return _running ??= _sync(automatic: automatic)
        .whenComplete(() => _running = null);
  }

  Future<void> _sync({required bool automatic}) async {
    if (await _importWithoutRing()) return;
    if (!ref.mounted) return;
    state = state.at(const SyncProgress(SyncStep.connecting));
    final syncPairedRing = ref.read(syncPairedRingProvider);
    final outcome = await syncPairedRing(
      onProgress: _onProgress,
      onBattery: _onBattery,
    );
    if (!ref.mounted) return;
    if (outcome is SyncCompleted) {
      ref.read(dataRevisionProvider.notifier).bump();
    }
    state = switch (outcome) {
      NothingPaired() => state.failed(const NoPairedRing()),
      AlreadySyncing() when automatic => state.idle(),
      AlreadySyncing() => state.failed(const AnotherSyncRunning()),
      SyncFailed(:final error) => state.failed(
        SyncAborted(error.step, '${error.cause}'),
      ),
      SyncCompleted(:final report) => state.succeeded(
        report.syncedAt,
        partial: report.failures.isEmpty
            ? null
            : CapabilitiesFailed(report.failures.keys),
        written: report.written,
      ),
    };
    unawaited(_sendAlerts(outcome));
    unawaited(ref.read(healthReadProvider.notifier).importNow());
    unawaited(ref.read(workoutReadProvider.notifier).importNow());
    if (outcome is! SyncCompleted) return;
    unawaited(ref.read(healthSyncProvider.notifier).process());
  }

  // Without a ring the reads are the only source, so a sync is just the import
  // and the last ring sync time stays as it was.
  Future<bool> _importWithoutRing() async {
    final ring = await ref.read(syncStoreProvider).pairedRing();
    if (ring != null || !ref.mounted) return false;
    if (!await ref.read(anyHealthReadEnabledProvider.future)) return false;
    if (!ref.mounted) return true;
    await (
      ref.read(healthReadProvider.notifier).importNow(),
      ref.read(workoutReadProvider.notifier).importNow(),
    ).wait;
    if (!ref.mounted) return true;
    state = RingSyncState(
      lastSuccessAt: state.lastSuccessAt,
      lastWritten: state.lastWritten,
      batteryPercent: state.batteryPercent,
    );
    return true;
  }

  // An alert is best effort: it must never change how a sync is reported.
  Future<void> _sendAlerts(SyncOutcome outcome) async {
    try {
      await ref.read(syncAlertsProvider).afterSync(outcome);
    } on Object {
      return;
    }
  }

  void _onProgress(SyncProgress progress) {
    if (!ref.mounted) return;
    state = state.at(progress);
  }

  void _onBattery(BatteryStatus battery) {
    if (!ref.mounted) return;
    state = state.withBattery(battery.percent);
  }

  Future<void> _restoreLastSuccess() async {
    final ring = await ref.read(syncStoreProvider).pairedRing();
    if (!ref.mounted || state.lastSuccessAt != null) return;
    state = state.withLastSuccess(ring?.lastSyncAt);
  }

  Future<void> _adoptBackgroundSync() async {
    final ring = await ref.read(syncStoreProvider).pairedRing();
    if (!ref.mounted) return;
    ref.read(dataRevisionProvider.notifier).bump();
    state = state.afterBackgroundSync(ring?.lastSyncAt);
  }
}

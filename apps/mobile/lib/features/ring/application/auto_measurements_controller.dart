import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_ring/core/records/data_revision.dart';
import 'package:open_ring/features/ring/application/ring_sync_controller.dart';
import 'package:open_ring/features/ring/domain/auto_measurements.dart';
import 'package:open_ring/features/ring/domain/battery_settings.dart';
import 'package:open_ring/features/ring/domain/sync_run.dart';
import 'package:open_ring/features/ring/infrastructure/method_channel_battery_settings.dart';

final autoMeasurementsProvider =
    AsyncNotifierProvider<AutoMeasurementsController, AutoMeasurements?>(
      AutoMeasurementsController.new,
    );

class AutoMeasurementsController extends AsyncNotifier<AutoMeasurements?> {
  @override
  Future<AutoMeasurements?> build() async {
    ref.watch(dataRevisionProvider);
    final ring = await ref.watch(syncStoreProvider).pairedRing();
    return ring?.measurements;
  }

  Future<void> turn(AutoMeasurement measurement, {required bool on}) async {
    final store = ref.read(syncStoreProvider);
    final ring = await store.pairedRing();
    if (ring == null) return;
    final next = ring.measurements.turned(measurement, on: on);
    state = AsyncData(next);
    try {
      await store.saveMeasurements(ring.deviceId, next);
    } on Object {
      if (!ref.mounted) return;
      state = AsyncData(ring.measurements);
    }
  }
}

final syncLogProvider = FutureProvider<List<SyncRun>>((ref) async {
  ref
    ..watch(dataRevisionProvider)
    ..watch(ringSyncProvider.select((sync) => sync.syncing));
  final store = ref.watch(syncStoreProvider);
  final ring = await store.pairedRing();
  if (ring == null) return const [];
  return await store.recentRuns(ring.deviceId);
});

final batterySettingsProvider = Provider<BatterySettings>(
  (ref) => const MethodChannelBatterySettings(),
);

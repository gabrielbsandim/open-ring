import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/core/records/data_revision.dart';
import 'package:open_ring/features/onboarding/application/onboarding_controller.dart';
import 'package:open_ring/features/onboarding/domain/app_permissions.dart';
import 'package:open_ring/features/ring/application/pair_state.dart';
import 'package:open_ring/features/ring/application/protocol_lab_controller.dart';
import 'package:open_ring/features/ring/application/sync_interval_controller.dart';
import 'package:open_ring/features/ring/domain/discovered_device.dart';
import 'package:open_ring/features/ring/domain/ring_pairing.dart';
import 'package:open_ring/features/ring/domain/ring_scanner.dart';
import 'package:ring_driver/ring_driver.dart';

final pairedRingStoreProvider = Provider<PairedRingStore>(
  (ref) => throw UnimplementedError('Override pairedRingStoreProvider.'),
);

final bluetoothRadioProvider = Provider<BluetoothRadio>(
  (ref) => throw UnimplementedError('Override bluetoothRadioProvider.'),
);

final NotifierProvider<PairController, PairState> pairProvider =
    NotifierProvider.autoDispose(PairController.new);

class PairController extends Notifier<PairState> {
  static const scanTimeout = Duration(seconds: 30);

  bool _scanning = false;

  RingScanner get _scanner => ref.read(ringScannerProvider);

  @override
  PairState build() {
    final scanner = ref.watch(ringScannerProvider);
    final subscriptions = [
      scanner.results.listen(_onDevices),
      scanner.isScanning.listen(_onScanning),
    ];
    ref.onDispose(() {
      for (final subscription in subscriptions) {
        unawaited(subscription.cancel());
      }
      if (_scanning) unawaited(_stopScan(scanner));
    });
    return const PairState();
  }

  Future<void> scan() async {
    if (state.phase == PairPhase.connecting) return;
    state = const PairState(phase: PairPhase.scanning, scanActive: true);
    final permission = await ref
        .read(appPermissionsProvider)
        .request(AppPermission.bluetooth);
    if (!ref.mounted) return;
    if (!permission.isGranted) return _fail(PairFailure.permissionDenied);
    final radioOn = await ref.read(bluetoothRadioProvider).ensureOn();
    if (!ref.mounted) return;
    if (!radioOn) return _fail(PairFailure.bluetoothOff);
    _scanning = true;
    try {
      await _scanner.start(scanTimeout);
    } on BleTransportException {
      if (!ref.mounted) return;
      _fail(PairFailure.bluetoothOff);
    }
  }

  Future<void> pair(DiscoveredDevice device) async {
    if (state.phase == PairPhase.connecting) return;
    if (state.phase == PairPhase.paired) return;
    final revision = ref.read(dataRevisionProvider.notifier);
    final transport = ref.read(bleTransportProvider);
    final store = ref.read(pairedRingStoreProvider);
    final now = ref.read(clockProvider);
    state = state.connecting(device);
    await _stopScan(_scanner);
    try {
      await transport.connect(device.id);
    } on BleTransportException {
      if (!ref.mounted) return;
      state = state.connectionFailed();
      return;
    }
    await _disconnect(transport);
    final saved = await _save(store, identityOf(device), now());
    if (saved) revision.bump();
    if (!ref.mounted) return;
    if (saved) unawaited(_schedule());
    state = saved ? state.paired() : state.savingFailed();
  }

  static Future<bool> _save(
    PairedRingStore store,
    RingIdentity identity,
    DateTime at,
  ) async {
    try {
      await store.save(identity, at: at);
      return true;
    } on Object {
      return false;
    }
  }

  // Unpairing cancels the background sync, so a new pairing starts it again;
  // a failure here is retried by the schedule check at every launch.
  Future<void> _schedule() async {
    try {
      await ref.read(syncIntervalProvider.notifier).ensureScheduled();
    } on Object {
      return;
    }
  }

  static RingIdentity identityOf(DiscoveredDevice device) {
    final model = device.colmiModel;
    final name = device.name.trim();
    return RingIdentity(
      deviceId: device.id,
      name: name.isEmpty ? 'COLMI ${model ?? ''}'.trim() : name,
      model: model,
    );
  }

  void _fail(PairFailure failure) {
    _scanning = false;
    state = PairState.failed(failure);
  }

  void _onDevices(List<DiscoveredDevice> devices) {
    if (!_scanning) return;
    final rings = devices.where((device) => device.isColmiRing);
    state = state.withDevices(DiscoveredDevice.rank(rings));
  }

  void _onScanning(bool scanning) {
    if (scanning || !_scanning) return;
    _scanning = false;
    if (state.phase != PairPhase.scanning) return;
    if (state.devices.isEmpty) return _fail(PairFailure.notFound);
    state = state.scanEnded();
  }

  Future<void> _stopScan(RingScanner scanner) async {
    _scanning = false;
    try {
      await scanner.stop();
    } on BleTransportException {
      // A scan that already ended cannot be stopped; nothing to undo.
    }
  }

  static Future<void> _disconnect(BleTransport transport) async {
    try {
      await transport.disconnect();
    } on BleTransportException {
      // The link only proved the ring answers; a failed hang-up loses nothing.
    }
  }
}

import 'package:meta/meta.dart';
import 'package:open_ring/features/ring/domain/discovered_device.dart';

enum PairPhase { idle, scanning, connecting, paired }

enum PairFailure { notFound, permissionDenied, bluetoothOff }

@immutable
final class PairState {
  const new({
    this.phase = PairPhase.idle,
    this.devices = const [],
    this.scanActive = false,
    this.target,
    this.connectFailed = false,
    this.saveFailed = false,
    this.failure,
  });

  const new failed(PairFailure this.failure)
    : phase = PairPhase.idle,
      devices = const [],
      scanActive = false,
      target = null,
      connectFailed = false,
      saveFailed = false;

  final PairPhase phase;
  final List<DiscoveredDevice> devices;
  final bool scanActive;
  final DiscoveredDevice? target;
  final bool connectFailed;
  final bool saveFailed;
  final PairFailure? failure;

  PairState withDevices(List<DiscoveredDevice> devices) => PairState(
    phase: phase,
    devices: devices,
    scanActive: scanActive,
    target: target,
    connectFailed: connectFailed,
    saveFailed: saveFailed,
  );

  PairState scanEnded() => PairState(
    phase: phase,
    devices: devices,
    target: target,
    connectFailed: connectFailed,
    saveFailed: saveFailed,
  );

  PairState connecting(DiscoveredDevice device) =>
      PairState(phase: PairPhase.connecting, devices: devices, target: device);

  PairState connectionFailed() => PairState(
    phase: PairPhase.scanning,
    devices: devices,
    target: target,
    connectFailed: true,
  );

  PairState savingFailed() => PairState(
    phase: PairPhase.scanning,
    devices: devices,
    target: target,
    saveFailed: true,
  );

  PairState paired() =>
      PairState(phase: PairPhase.paired, devices: devices, target: target);
}

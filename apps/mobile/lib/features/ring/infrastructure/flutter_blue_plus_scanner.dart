import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:open_ring/features/ring/domain/discovered_device.dart';
import 'package:open_ring/features/ring/domain/ring_scanner.dart';
import 'package:open_ring/features/ring/infrastructure/flutter_blue_plus_guard.dart';
import 'package:ring_driver/ring_driver.dart';
import 'package:ring_protocol/ring_protocol.dart';

// On Android, startScan asks for BLUETOOTH_SCAN and BLUETOOTH_CONNECT (or
// location on Android 11 and lower) at runtime; iOS prompts on first use.
final class FlutterBluePlusScanner implements RingScanner {
  new();

  static const _adapterWait = Duration(seconds: 3);

  // A ring bonded and held by the OS or another app stops advertising, so it
  // only shows up through the system device list.
  var _systemDevices = const <DiscoveredDevice>[];

  @override
  Stream<List<DiscoveredDevice>> get results => FlutterBluePlus.scanResults.map(
    (results) => _merge(results.map(_toDevice)),
  );

  @override
  Stream<bool> get isScanning => FlutterBluePlus.isScanning;

  @override
  Future<void> start(Duration timeout) async {
    if (!await FlutterBluePlus.isSupported) {
      throw const BleTransportException(
        'Bluetooth LE is not supported on this device',
      );
    }
    await _ensureAdapterOn();
    _systemDevices = await _loadSystemDevices();
    await guardBle(() => FlutterBluePlus.startScan(timeout: timeout));
  }

  @override
  Future<void> stop() => guardBle(FlutterBluePlus.stopScan);

  Future<void> _ensureAdapterOn() async {
    final adapter = await FlutterBluePlus.adapterState
        .where((state) => state != BluetoothAdapterState.unknown)
        .first
        .timeout(_adapterWait, onTimeout: () => BluetoothAdapterState.unknown);
    if (adapter == BluetoothAdapterState.on) return;
    if (defaultTargetPlatform != TargetPlatform.android) {
      throw BleTransportException('Bluetooth adapter is ${adapter.name}');
    }
    await guardBle(FlutterBluePlus.turnOn);
  }

  List<DiscoveredDevice> _merge(Iterable<DiscoveredDevice> scanned) {
    final seen = {for (final device in scanned) device.id: device};
    for (final device in _systemDevices) {
      seen.putIfAbsent(device.id, () => device);
    }
    return seen.values.toList();
  }

  static Future<List<DiscoveredDevice>> _loadSystemDevices() async {
    final connected = await guardBle(
      () => FlutterBluePlus.systemDevices([Guid(ColmiGatt.v1Service)]),
    );
    final bonded = defaultTargetPlatform == TargetPlatform.android
        ? await guardBle(() => FlutterBluePlus.bondedDevices)
        : const <BluetoothDevice>[];
    return [
      for (final device in [...connected, ...bonded])
        DiscoveredDevice(
          id: device.remoteId.str,
          name: device.platformName,
          rssi: 0,
        ),
    ];
  }

  static DiscoveredDevice _toDevice(ScanResult result) {
    final advertised = result.advertisementData.advName;
    return DiscoveredDevice(
      id: result.device.remoteId.str,
      name: advertised.isEmpty ? result.device.platformName : advertised,
      rssi: result.rssi,
      serviceUuids: [
        for (final uuid in result.advertisementData.serviceUuids) uuid.str128,
      ],
    );
  }
}

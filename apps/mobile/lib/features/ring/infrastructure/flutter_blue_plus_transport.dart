import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:open_ring/features/ring/infrastructure/flutter_blue_plus_guard.dart';
import 'package:ring_driver/ring_driver.dart';
import 'package:ring_protocol/ring_protocol.dart';

final class FlutterBluePlusTransport implements BleTransport {
  static const v1Write = GattCharacteristic(
    service: ColmiGatt.v1Service,
    characteristic: ColmiGatt.v1Write,
  );
  static const v1Notify = GattCharacteristic(
    service: ColmiGatt.v1Service,
    characteristic: ColmiGatt.v1Notify,
  );
  static const bigDataWrite = GattCharacteristic(
    service: ColmiGatt.bigDataService,
    characteristic: ColmiGatt.bigDataWrite,
  );
  static const bigDataNotify = GattCharacteristic(
    service: ColmiGatt.bigDataService,
    characteristic: ColmiGatt.bigDataNotify,
  );

  static final Set<GattCharacteristic> _wanted = {
    v1Write,
    v1Notify,
    bigDataWrite,
    bigDataNotify,
  };
  static const List<GattCharacteristic> _subscribed = [v1Notify, bigDataNotify];

  // CoreBluetooth reads the restore identifier only when the first call creates
  // its central manager, so this must run before any other Bluetooth call.
  static Future<void> enableStateRestoration() =>
      guardBle(() => FlutterBluePlus.setOptions(restoreState: true));

  final _state = StreamController<TransportState>.broadcast();
  final _characteristics = <GattCharacteristic, BluetoothCharacteristic>{};

  BluetoothDevice? _device;
  StreamSubscription<BluetoothConnectionState>? _link;

  @override
  Stream<TransportState> get state => _state.stream;

  @override
  Future<void> connect(String deviceId) async {
    await disconnect();
    final device = BluetoothDevice.fromId(deviceId);
    _device = device;
    _state.add(TransportState.connecting);
    try {
      await guardBle(() => device.connect(license: License.nonprofit));
      await guardBle(() => _discover(device));
      await guardBle(_subscribe);
    } on BleTransportException {
      await _drop(device);
      rethrow;
    }
    _link = device.connectionState
        .where((link) => link == BluetoothConnectionState.disconnected)
        .listen((_) => _lost());
    _state.add(TransportState.connected);
  }

  @override
  Future<void> disconnect() async {
    final device = _device;
    if (device == null) return;
    await _release();
    await guardBle(device.disconnect);
    _state.add(TransportState.disconnected);
  }

  @override
  Future<void> write(GattCharacteristic target, List<int> bytes) async {
    final characteristic = _characteristics[target];
    if (characteristic == null) {
      throw BleTransportException(
        '${target.characteristic} is not available, connect first',
      );
    }
    final properties = characteristic.properties;
    await guardBle(
      () => characteristic.write(
        bytes,
        withoutResponse: properties.writeWithoutResponse && !properties.write,
      ),
    );
  }

  // Read from the global event stream so a subscription made before connect
  // keeps working across reconnects.
  @override
  Stream<List<int>> notifications(GattCharacteristic source) => FlutterBluePlus
      .events
      .onCharacteristicReceived
      .where((event) => event.error == null)
      .where((event) => event.device.remoteId == _device?.remoteId)
      .where((event) => _keyOf(event.characteristic) == source)
      .map((event) => event.value);

  Future<void> _discover(BluetoothDevice device) async {
    final services = await device.discoverServices();
    final found = {
      for (final service in services)
        for (final characteristic in service.characteristics)
          _keyOf(characteristic): characteristic,
    };
    _characteristics
      ..clear()
      ..addEntries(found.entries.where((entry) => _wanted.contains(entry.key)));
    if (_characteristics.containsKey(v1Write) &&
        _characteristics.containsKey(v1Notify)) {
      return;
    }
    throw BleTransportException(
      'service ${ColmiGatt.v1Service} not found on ${device.remoteId}',
    );
  }

  Future<void> _subscribe() async {
    for (final key in _subscribed) {
      await _characteristics[key]?.setNotifyValue(true);
    }
  }

  Future<void> _drop(BluetoothDevice device) async {
    await _release();
    try {
      await guardBle(device.disconnect);
    } on BleTransportException {
      // The link is already gone; the original failure is what matters.
    }
    _state.add(TransportState.disconnected);
  }

  Future<void> _release() async {
    await _link?.cancel();
    _link = null;
    _device = null;
    _characteristics.clear();
  }

  void _lost() {
    unawaited(_release());
    _state.add(TransportState.disconnected);
  }

  static GattCharacteristic _keyOf(BluetoothCharacteristic characteristic) =>
      GattCharacteristic(
        service: characteristic.serviceUuid.str128,
        characteristic: characteristic.characteristicUuid.str128,
      );
}

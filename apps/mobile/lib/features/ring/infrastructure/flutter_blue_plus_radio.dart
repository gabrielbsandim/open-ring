import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:open_ring/features/ring/domain/ring_pairing.dart';
import 'package:open_ring/features/ring/infrastructure/flutter_blue_plus_guard.dart';
import 'package:ring_driver/ring_driver.dart';

final class FlutterBluePlusRadio implements BluetoothRadio {
  const new();

  static const _adapterWait = Duration(seconds: 3);

  @override
  Future<bool> ensureOn() async {
    if (!await FlutterBluePlus.isSupported) return false;
    if (await _isOn()) return true;
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      await guardBle(FlutterBluePlus.turnOn);
    } on BleTransportException {
      return false;
    }
    return await _isOn();
  }

  static Future<bool> _isOn() async {
    final adapter = await FlutterBluePlus.adapterState
        .where((state) => state != BluetoothAdapterState.unknown)
        .first
        .timeout(_adapterWait, onTimeout: () => BluetoothAdapterState.unknown);
    return adapter == BluetoothAdapterState.on;
  }
}

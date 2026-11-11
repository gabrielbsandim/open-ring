import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/ring/domain/discovered_device.dart';
import 'package:ring_protocol/ring_protocol.dart';

DiscoveredDevice named(String name, {int rssi = -60}) =>
    DiscoveredDevice(id: name, name: name, rssi: rssi);

void main() {
  test('COLMI R0x names and the R10 are rings with a model', () {
    final models = {
      for (final name in [
        'R09_F800',
        'COLMI R09',
        'colmi_r02',
        'R06',
        'R10_ABCD',
      ])
        name: named(name).colmiModel,
    };

    expect(models, {
      'R09_F800': 'R09',
      'COLMI R09': 'R09',
      'colmi_r02': 'R02',
      'R06': 'R06',
      'R10_ABCD': 'R10',
    });
  });

  test('an R09 that names itself COLMI Ring is a ring without a model', () {
    final ring = named('COLMI Ring 2');

    expect(ring.isColmiRing, isTrue);
    expect(ring.colmiModel, isNull);
  });

  test('the V1 service marks a ring whatever its name', () {
    final ring = DiscoveredDevice(
      id: 'x',
      name: 'Unknown',
      rssi: -60,
      serviceUuids: [ColmiGatt.v1Service.toUpperCase()],
    );

    expect(ring.isColmiRing, isTrue);
  });

  test('other devices are not rings', () {
    for (final name in [
      'Mi Band 8',
      'R091',
      'Kitchen speaker',
      '',
      'XR09',
      'COLMI P71',
    ]) {
      expect(named(name).isColmiRing, isFalse, reason: name);
    }
  });

  test('an RSSI of 0 marks a ring the system already holds', () {
    expect(named('R09_F800', rssi: 0).heldBySystem, isTrue);
    expect(named('R09_F800', rssi: -71).heldBySystem, isFalse);
  });
}

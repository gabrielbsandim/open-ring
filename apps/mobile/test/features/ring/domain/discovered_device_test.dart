import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/ring/domain/discovered_device.dart';
import 'package:ring_protocol/ring_protocol.dart';

void main() {
  group('DiscoveredDevice', () {
    test('a R0x name or the V1 service marks a Colmi ring', () {
      expect(
        const DiscoveredDevice(
          id: 'a',
          name: 'R02_A1B2',
          rssi: -50,
        ).looksLikeColmi,
        isTrue,
      );
      expect(
        const DiscoveredDevice(
          id: 'a',
          name: 'r09_c0fe',
          rssi: -50,
        ).looksLikeColmi,
        isTrue,
      );
      expect(
        const DiscoveredDevice(
          id: 'a',
          name: 'COLMI R09',
          rssi: -50,
        ).looksLikeColmi,
        isTrue,
      );
      expect(
        const DiscoveredDevice(
          id: 'a',
          name: '',
          rssi: -50,
          serviceUuids: ['6E40FFF0-B5A3-F393-E0A9-E50E24DCCA9E'],
        ).looksLikeColmi,
        isTrue,
      );
      expect(
        const DiscoveredDevice(
          id: 'a',
          name: 'R10 speaker',
          rssi: -50,
        ).looksLikeColmi,
        isFalse,
      );
    });

    test('ranks Colmi devices first, then by signal strength', () {
      final ranked = DiscoveredDevice.rank(const [
        DiscoveredDevice(id: 'tv', name: 'TV', rssi: -30),
        DiscoveredDevice(id: 'far', name: 'R09_0001', rssi: -90),
        DiscoveredDevice(id: 'watch', name: 'Watch', rssi: -60),
        DiscoveredDevice(
          id: 'near',
          name: '',
          rssi: -45,
          serviceUuids: [ColmiGatt.v1Service],
        ),
      ]);

      expect(ranked.map((d) => d.id), ['near', 'far', 'tv', 'watch']);
    });
  });
}

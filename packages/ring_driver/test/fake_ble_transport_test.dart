import 'package:ring_driver/ring_driver.dart';
import 'package:ring_driver/testing.dart';
import 'package:test/test.dart';

const write = GattCharacteristic(
  service: '6e40fff0-b5a3-f393-e0a9-e50e24dcca9e',
  characteristic: '6e400002-b5a3-f393-e0a9-e50e24dcca9e',
);
const notify = GattCharacteristic(
  service: '6e40fff0-b5a3-f393-e0a9-e50e24dcca9e',
  characteristic: '6e400003-b5a3-f393-e0a9-e50e24dcca9e',
);
const bigData = GattCharacteristic(
  service: 'de5bf728-d711-4e47-af26-65e3012a5dc7',
  characteristic: 'de5bf729-d711-4e47-af26-65e3012a5dc7',
);

void main() {
  group('FakeBleTransport', () {
    test('connect moves through connecting to connected', () async {
      final transport = FakeBleTransport();
      addTearDown(transport.close);

      final states = transport.state.take(2).toList();
      await transport.connect('R09_ABCD');

      expect(await states, [
        TransportState.connecting,
        TransportState.connected,
      ]);
      expect(transport.current, TransportState.connected);
      expect(transport.deviceId, 'R09_ABCD');
    });

    test('an unreachable ring throws and stays disconnected', () async {
      final transport = FakeBleTransport(unreachable: true);
      addTearDown(transport.close);

      await expectLater(
        transport.connect('R09_ABCD'),
        throwsA(isA<BleTransportException>()),
      );
      expect(transport.current, TransportState.disconnected);
      expect(transport.deviceId, isNull);
    });

    test('a write before connect throws and is not recorded', () async {
      final transport = FakeBleTransport();
      addTearDown(transport.close);

      await expectLater(
        transport.write(write, [0x03]),
        throwsA(isA<BleTransportException>()),
      );
      expect(transport.writes, isEmpty);
    });

    test('records writes and replays the scripted reply on its characteristic only', () async {
      final transport = FakeBleTransport(
        responder: (packet) => [
          GattPacket(notify, [packet.bytes.first, 80, 1]),
        ],
      );
      addTearDown(transport.close);
      await transport.connect('R09_ABCD');

      final onNotify = transport.notifications(notify).first;
      final onBigData = transport.notifications(bigData).toList();
      await transport.write(write, [0x03]);

      expect(await onNotify, [0x03, 80, 1]);
      expect(transport.writes, [
        GattPacket(write, const [0x03]),
      ]);
      await transport.close();
      expect(await onBigData, isEmpty);
    });

    test('emit pushes a notification the ring sent on its own', () async {
      final transport = FakeBleTransport();
      addTearDown(transport.close);

      final next = transport.notifications(bigData).first;
      transport.emit(GattPacket(bigData, const [0xBC, 0x27]));

      expect(await next, [0xBC, 0x27]);
    });

    test('disconnect clears the device and reports disconnected', () async {
      final transport = FakeBleTransport();
      addTearDown(transport.close);
      await transport.connect('R09_ABCD');

      await transport.disconnect();

      expect(transport.current, TransportState.disconnected);
      expect(transport.deviceId, isNull);
    });
  });

  test('characteristics compare without regard to UUID case', () {
    expect(
      GattCharacteristic(
        service: write.service.toUpperCase(),
        characteristic: write.characteristic.toUpperCase(),
      ),
      write,
    );
    expect(write, isNot(notify));
  });
}

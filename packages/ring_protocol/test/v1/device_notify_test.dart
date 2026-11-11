import 'package:ring_protocol/ring_protocol.dart';
import 'package:test/test.dart';

import '../helpers.dart';

void main() {
  group('parseDeviceNotification', () {
    test('battery pushes from tahnok MYSTERIES.md', () {
      expect(
        codec.parse(
          hex('73 0c 15 00 00 00 00 00 00 00 00 00 00 00 00 94'),
          parseDeviceNotification,
        ),
        const Parsed<DeviceNotification>(
          BatteryNotification(percent: 21, charging: false),
        ),
      );
      expect(
        codec.parse(
          hex('73 0c 64 01 00 00 00 00 00 00 00 00 00 00 00 e4'),
          parseDeviceNotification,
        ),
        const Parsed<DeviceNotification>(
          BatteryNotification(percent: 100, charging: true),
        ),
      );
    });

    test('a battery percent above 100 is out of range', () {
      expect(
        parseDeviceNotification(frame([0x73, 0x0C, 101])),
        const ParseFailure<DeviceNotification>(
          ByteOutOfRange(index: 2, value: 101),
        ),
      );
    });

    test('new data types 1, 3 and 4 (Gadgetbridge NOTIFICATION_NEW_*)', () {
      for (final type in [1, 3, 4]) {
        expect(
          parseDeviceNotification(frame([0x73, type])),
          Parsed<DeviceNotification>(NewDataAvailable(type)),
        );
      }
    });

    test('live activity reads big endian 24 bit counters (Gadgetbridge liveActivity)', () {
      expect(
        parseDeviceNotification(
          frame([
            0x73,
            0x12,
            0x00,
            0x1F,
            0x40,
            0x00,
            0x04,
            0xD2,
            0x00,
            0x0F,
            0xA0,
          ]),
        ),
        const Parsed<DeviceNotification>(
          LiveActivityNotification(
            steps: 8000,
            calories: 1234,
            distanceMeters: 4000,
          ),
        ),
      );
    });

    test('temperature type 5 (Puxtril NotifyType) keeps the raw payload', () {
      final result = parseDeviceNotification(frame([0x73, 0x05, 0x96, 0x01]));
      final notification =
          (result as Parsed<DeviceNotification>).value
              as TemperatureNotification;
      expect(notification.type, NotifyType.temperature);
      expect(notification.raw.take(2), [0x96, 0x01]);
      expect(notification.raw.length, 13);
      expect(notification.provisionalCelsius, closeTo(35.0, 1e-9));
    });

    test('temperature type 5 with a zero first byte has no reading', () {
      final result = parseDeviceNotification(frame([0x73, 0x05]));
      final notification =
          (result as Parsed<DeviceNotification>).value
              as TemperatureNotification;
      expect(notification.provisionalCelsius, isNull);
    });

    test('an unknown type is kept with its payload', () {
      final result = parseDeviceNotification(frame([0x73, 0x42, 0x07]));
      expect(
        result,
        Parsed<DeviceNotification>(
          UnknownNotification(0x42, [0x07, ...List.filled(12, 0)]),
        ),
      );
    });

    sharedFailures(0x73, parseDeviceNotification);
  });
}

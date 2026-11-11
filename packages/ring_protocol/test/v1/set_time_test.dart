import 'package:ring_protocol/ring_protocol.dart';
import 'package:test/test.dart';

import '../helpers.dart';

void main() {
  group('setTimeRequest', () {
    test('2024-01-01 00:00:00 matches tahnok tests/test_set_time.py', () {
      expect(
        setTimeRequest(DateTime.utc(2024)),
        hex('01 24 01 01 00 00 00 01 00 00 00 00 00 00 00 28'),
      );
    });

    test('hour 4 is BCD like tahnok test_set_time_with_timezone', () {
      expect(
        setTimeRequest(DateTime.utc(2024, 1, 1, 4)),
        hex('01 24 01 01 04 00 00 01 00 00 00 00 00 00 00 2c'),
      );
    });

    test('two digit fields are BCD, not binary (Gadgetbridge setDateTime)', () {
      final bytes = setTimeRequest(
        DateTime(2026, 11, 10, 23, 59, 58),
        language: RingLanguage.chinese,
      );
      expect(bytes.sublist(0, 8), [
        0x01,
        0x26,
        0x11,
        0x10,
        0x23,
        0x59,
        0x58,
        0,
      ]);
    });

    test('rejects a year outside 2000..2099', () {
      expect(() => setTimeRequest(DateTime(1999)), throwsArgumentError);
      expect(() => setTimeRequest(DateTime(2100)), throwsArgumentError);
    });
  });

  group('parseSetTime', () {
    test('reads capability flags from tahnok test_parse_set_time_response', () {
      final bytes = hex('01 00 01 00 22 00 00 00 00 01 00 30 01 00 10 66');
      expect(
        codec.parse(bytes, parseSetTime),
        const Parsed(
          DeviceCapabilities(
            supportsTemperature: false,
            supportsBloodOxygen: true,
            supportsBloodPressure: false,
            newSleepProtocol: true,
            supportsManualHeartRate: true,
            supportsBloodSugar: false,
            supportsPressure: true,
            supportsHrv: false,
          ),
        ),
      );
    });

    sharedFailures(0x01, parseSetTime);
  });
}

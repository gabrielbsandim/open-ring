import 'package:ring_protocol/ring_protocol.dart';
import 'package:test/test.dart';

import '../helpers.dart';

void main() {
  group('find device 0x50', () {
    test('request carries 0x55 0xAA (Gadgetbridge onFindDevice, Puxtril)', () {
      expect(findDeviceRequest(), padded([0x50, 0x55, 0xAA]));
    });

    test('accepts the echo as an acknowledgement', () {
      expect(parseFindDevice(frame([0x50])), isA<Parsed<V1Frame>>());
    });

    sharedFailures(0x50, parseFindDevice);
  });

  group('real time 0x69', () {
    test('start heart rate matches tahnok get_start_packet', () {
      expect(
        realTimeRequest(RealTimeType.heartRate, RealTimeAction.start),
        padded([0x69, 0x01, 0x01]),
      );
    });

    test('start SpO2 is type 3 (Puxtril DataType, tahnok RealTimeReading)', () {
      expect(
        realTimeRequest(RealTimeType.spo2, RealTimeAction.start),
        padded([0x69, 0x03, 0x01]),
      );
    });

    test('stop with action 4 on 0x69 (Puxtril DataAction)', () {
      expect(
        realTimeRequest(RealTimeType.heartRate, RealTimeAction.stop),
        padded([0x69, 0x01, 0x04]),
      );
    });

    test('stop with 0x6A, type and two zeros (tahnok get_stop_packet)', () {
      expect(
        realTimeStopRequest(RealTimeType.heartRate),
        padded([0x6A, 0x01, 0x00, 0x00]),
      );
    });

    test('parses 78 bpm from tahnok test_parse_real_time_reading_success', () {
      expect(
        codec.parse(
          hex('69 01 00 4e 00 00 00 00 00 00 00 00 00 00 00 b8'),
          parseRealTimeReading,
        ),
        const Parsed(
          RealTimeReading(
            type: RealTimeType.heartRate,
            errorCode: 0,
            value: 78,
          ),
        ),
      );
    });

    test(
      'keeps the error code from tahnok test_parse_real_time_reading_fail',
      () {
        final result = codec.parse(
          hex('69 01 01 00 00 00 00 00 00 00 00 00 00 00 00 6b'),
          parseRealTimeReading,
        );
        final reading = (result as Parsed<RealTimeReading>).value;
        expect(reading.isError, isTrue);
        expect(reading.errorCode, 1);
      },
    );

    test('an unknown type is out of range', () {
      expect(
        parseRealTimeReading(frame([0x69, 0x0B])),
        const ParseFailure<RealTimeReading>(
          ByteOutOfRange(index: 1, value: 11),
        ),
      );
    });

    sharedFailures(0x69, parseRealTimeReading);
  });

  group('stop real time 0x6A', () {
    test('accepts the echo', () {
      expect(parseRealTimeStop(frame([0x6A, 1])), isA<Parsed<V1Frame>>());
    });

    sharedFailures(0x6A, parseRealTimeStop);
  });
}

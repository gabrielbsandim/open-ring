import 'package:ring_protocol/ring_protocol.dart';
import 'package:test/test.dart';

import '../helpers.dart';

void main() {
  group('continuous heart rate 0x1E', () {
    test('enable is 0x1E 0x01 (Gadgetbridge enableRealtimeHRMRequest)', () {
      expect(
        continuousHeartRateRequest(ContinuousHeartRateAction.enable),
        hex('1e 01 00 00 00 00 00 00 00 00 00 00 00 00 00 1f'),
      );
    });

    test('disable is 0x1E 0x02', () {
      expect(
        continuousHeartRateRequest(ContinuousHeartRateAction.disable),
        hex('1e 02 00 00 00 00 00 00 00 00 00 00 00 00 00 20'),
      );
    });

    test('continue is 0x1E 0x03 (Gadgetbridge continueRealtimeHRMRequest)', () {
      expect(
        continuousHeartRateRequest(ContinuousHeartRateAction.keepAlive),
        hex('1e 03 00 00 00 00 00 00 00 00 00 00 00 00 00 21'),
      );
    });

    test('the ring stops without a continue inside 60 s', () {
      expect(continuousHeartRateTimeout, const Duration(seconds: 60));
    });

    test('reads bpm from byte 1 (Gadgetbridge realtimeHeartRate)', () {
      expect(
        codec.parse(
          hex('1e 50 00 00 00 00 00 00 00 00 00 00 00 00 00 6e'),
          parseContinuousHeartRate,
        ),
        const Parsed(80),
      );
    });

    test('ignores the bytes after the bpm', () {
      expect(
        codec.parse(
          hex('1e 9c 07 01 00 00 00 00 00 00 00 00 00 00 00 c2'),
          parseContinuousHeartRate,
        ),
        const Parsed(156),
      );
    });

    test('keeps a zero reading for the caller to drop', () {
      expect(
        codec.parse(
          hex('1e 00 00 00 00 00 00 00 00 00 00 00 00 00 00 1e'),
          parseContinuousHeartRate,
        ),
        const Parsed(0),
      );
    });

    test('a 0x69 one-shot reply is not a stream reading', () {
      expect(
        codec.parse(
          hex('69 01 00 4e 00 00 00 00 00 00 00 00 00 00 00 b8'),
          parseContinuousHeartRate,
        ),
        const ParseFailure<int>(
          UnexpectedCommand(expected: 0x1E, actual: 0x69),
        ),
      );
    });

    sharedFailures(0x1E, parseContinuousHeartRate);
  });
}

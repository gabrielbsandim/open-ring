import 'package:ring_protocol/ring_protocol.dart';
import 'package:test/test.dart';

import '../helpers.dart' as helpers;

V1Frame decoded(List<int> head) {
  final body = [...head, ...List.filled(15 - head.length, 0)];
  final checksum = const MaskedSumChecksum().compute(body);
  return (const V1FrameCodec().decode([
    ...body,
    checksum,
  ]) as Parsed<V1Frame>).value;
}

void main() {
  test('reads percent and the charging flag', () {
    expect(
      parseBattery(decoded([0x03, 80, 1])),
      const Parsed(BatteryReading(percent: 80, charging: true)),
    );
    expect(
      parseBattery(decoded([0x03, 15, 0])),
      const Parsed(BatteryReading(percent: 15, charging: false)),
    );
  });

  test('rejects a percent above 100', () {
    expect(
      parseBattery(decoded([0x03, 101, 0])),
      const ParseFailure<BatteryReading>(ByteOutOfRange(index: 1, value: 101)),
    );
  });

  test('rejects a frame for another command', () {
    expect(
      parseBattery(decoded([0x48, 80, 1])),
      const ParseFailure<BatteryReading>(
        UnexpectedCommand(expected: 0x03, actual: 0x48),
      ),
    );
  });

  group('shared failures', () {
    helpers.sharedFailures(0x03, parseBattery);
  });
}

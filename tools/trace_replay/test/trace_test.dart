import 'package:ring_protocol/ring_protocol.dart';
import 'package:test/test.dart';
import 'package:trace_replay/trace_replay.dart';

import 'helpers.dart';

void main() {
  test('reads the exporter fields and lower cases the characteristic', () {
    final lines = Trace.parse(
      '{"t":"2024-08-10T12:00:00.000Z","dir":"rx",'
      '"char":"6E400003-B5A3-F393-E0A9-E50E24DCCA9E","hex":"0350"}\n',
    );

    final entry = lines.single as TraceEntry;
    expect(entry.lineNumber, 1);
    expect(entry.at, DateTime.utc(2024, 8, 10, 12));
    expect(entry.direction, TraceDirection.rx);
    expect(entry.characteristic, ColmiGatt.v1Notify);
    expect(entry.channel, TraceChannel.v1Notify);
    expect(entry.bytes, [0x03, 0x50]);
  });

  test('skips blank lines and keeps the source line numbers', () {
    final lines = Trace.parse(
      '\n${rx(padded([0x03]))}\n\n${tx(padded([0x03]))}\n',
    );

    expect(lines.map((l) => l.lineNumber), [2, 4]);
  });

  test('an unknown characteristic still parses but has no channel', () {
    final entry =
        Trace.parse(
              line(TraceDirection.rx, '00002a19-0000-1000-8000-00805f9b34fb', [
                0x40,
              ]),
            ).single
            as TraceEntry;

    expect(entry.channel, isNull);
  });

  group('malformed lines', () {
    String reasonOf(String source) =>
        (Trace.parse(source).single as MalformedLine).reason;

    test('not JSON', () {
      expect(reasonOf('not json'), startsWith('not JSON'));
    });

    test('not an object', () {
      expect(reasonOf('[1, 2]'), 'a line must be a JSON object');
    });

    test('a missing or non string field', () {
      expect(
        reasonOf('{"t":"2024-08-10T12:00:00Z","dir":"rx","hex":"03"}'),
        't, dir, char and hex must all be strings',
      );
      expect(
        reasonOf('{"t":1,"dir":"rx","char":"x","hex":"03"}'),
        't, dir, char and hex must all be strings',
      );
    });

    test('a bad time, direction or hex', () {
      String lineWith(String t, String dir, String hex) =>
          '{"t":"$t","dir":"$dir","char":"x","hex":"$hex"}';
      expect(reasonOf(lineWith('yesterday', 'rx', '03')), contains('ISO-8601'));
      expect(
        reasonOf(lineWith('2024-08-10T12:00:00Z', 'up', '03')),
        contains('tx or rx'),
      );
      expect(
        reasonOf(lineWith('2024-08-10T12:00:00Z', 'rx', '0')),
        contains('not hex'),
      );
    });

    test('the fixture with broken lines reports both of them', () {
      final malformed = Trace.parse(fixture('checksum_cases.jsonl'))
          .whereType<MalformedLine>();

      expect(malformed.map((m) => m.lineNumber), [9, 12]);
    });
  });
}

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/ring/domain/frame_log_entry.dart';
import 'package:ring_protocol/ring_protocol.dart';

void main() {
  final tx = FrameLogEntry(
    at: DateTime.utc(2026, 11, 10, 12, 0, 0, 125),
    direction: FrameDirection.tx,
    characteristic: ColmiGatt.v1Write,
    bytes: [0x03, ...List.filled(14, 0), 0x03],
  );
  final rx = FrameLogEntry(
    at: DateTime.utc(2026, 11, 10, 12, 0, 0, 250),
    direction: FrameDirection.rx,
    characteristic: ColmiGatt.v1Notify,
    bytes: [0x03, 80, 1, ...List.filled(12, 0), 84],
  );

  group('FrameLogEntry.toJson', () {
    test('writes the replay format with keys in a stable order', () {
      expect(
        jsonEncode(tx.toJson()),
        '{"t":"2026-11-10T12:00:00.125Z",'
        '"dir":"tx",'
        '"char":"6e400002-b5a3-f393-e0a9-e50e24dcca9e",'
        '"hex":"03000000000000000000000000000003"}',
      );
    });

    test('stores the time in UTC even for a local timestamp', () {
      final local = FrameLogEntry(
        at: DateTime(2026, 11, 10, 9),
        direction: FrameDirection.rx,
        characteristic: ColmiGatt.v1Notify.toUpperCase(),
        bytes: const [0xAB],
      );

      final json = local.toJson();
      expect(json['t'], endsWith('Z'));
      expect(DateTime.parse(json['t']!), DateTime(2026, 11, 10, 9).toUtc());
      expect(json['char'], ColmiGatt.v1Notify);
    });
  });

  group('SessionLog', () {
    test('encodes one JSON object per line, newline terminated', () {
      final text = SessionLog.encode([tx, rx]);

      final lines = text.split('\n');
      expect(lines, hasLength(3));
      expect(lines.last, isEmpty);
      expect(jsonDecode(lines[1]), {
        't': '2026-11-10T12:00:00.250Z',
        'dir': 'rx',
        'char': ColmiGatt.v1Notify,
        'hex': '03500100000000000000000000000054',
      });
    });

    test('decodes what it encodes', () {
      expect(SessionLog.decode(SessionLog.encode([tx, rx])), [tx, rx]);
    });

    test('decodes a hand written fixture with blank lines and CRLF', () {
      const fixture =
          '{"t":"2026-11-10T12:00:00.125Z","dir":"tx",'
          '"char":"6E400002-B5A3-F393-E0A9-E50E24DCCA9E",'
          '"hex":"03 00 00 00 00 00 00 00 00 00 00 00 00 00 00 03"}\r\n'
          '\r\n';

      expect(SessionLog.decode(fixture), [tx]);
    });

    test('decodes an empty log', () {
      expect(SessionLog.decode(''), isEmpty);
      expect(SessionLog.encode(const []), isEmpty);
    });

    for (final MapEntry(key: problem, value: line) in {
      'not an object': '[1, 2]',
      'missing hex': '{"t":"2026-11-10T12:00:00Z","dir":"tx","char":"x"}',
      'bad direction':
          '{"t":"2026-11-10T12:00:00Z","dir":"up","char":"x","hex":"00"}',
      'bad time': '{"t":"yesterday","dir":"tx","char":"x","hex":"00"}',
      'bad hex': '{"t":"2026-11-10T12:00:00Z","dir":"rx","char":"x","hex":"0"}',
    }.entries) {
      test('rejects a line with $problem', () {
        expect(() => SessionLog.decode(line), throwsFormatException);
      });
    }
  });
}

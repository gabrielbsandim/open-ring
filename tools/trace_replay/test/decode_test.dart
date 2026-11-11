import 'package:test/test.dart';
import 'package:trace_replay/trace_replay.dart';

import 'helpers.dart';

List<DecodedFrame> decodeFixture(String name) {
  final decoder = TraceDecoder();
  return fixtureEntries(name).map(decoder.decode).toList();
}

DecodedFrame atLine(List<DecodedFrame> frames, int lineNumber) =>
    frames.singleWhere((f) => f.entry.lineNumber == lineNumber);

void main() {
  group('checksum_cases.jsonl', () {
    final frames = decodeFixture('checksum_cases.jsonl');

    test('decodes a frame that passes both rules', () {
      final frame = atLine(frames, 1);
      expect(frame.checksum?.match, ChecksumMatch.both);
      expect(frame.meaning, 'battery 80%, charging');
    });

    test('a frame that passes one rule still decodes and names the rule', () {
      expect(atLine(frames, 2).checksum?.match, ChecksumMatch.maskedOnly);
      expect(atLine(frames, 2).meaning, 'findDevice request');
      expect(atLine(frames, 3).checksum?.match, ChecksumMatch.modulo255Only);
      expect(atLine(frames, 3).meaning, 'findDevice request');
    });

    test('a frame no rule accepts is flagged and not decoded', () {
      final frame = atLine(frames, 4);
      expect(frame.checksum?.match, ChecksumMatch.neither);
      expect(frame.meaning, isNull);
      expect(frame.failure, contains('both rules'));
    });

    test('bit 7 on a known command reads as an error response', () {
      expect(atLine(frames, 6).failure, 'error response for battery (0x83)');
    });

    test('unknown commands, lengths and characteristics give the reason', () {
      expect(atLine(frames, 7).failure, 'no parser for command 0x2f');
      expect(
        atLine(frames, 8).failure,
        'wrong length: expected 16 bytes, got 2',
      );
      expect(atLine(frames, 8).checksum, isNull);
      expect(atLine(frames, 10).failure, startsWith('unknown characteristic'));
    });

    test('a big data crc mismatch is flagged', () {
      expect(
        atLine(frames, 11).failure,
        startsWith('big data checksum mismatch: expected 0x'),
      );
    });
  });

  group('heart_rate_sync.jsonl', () {
    final frames = decodeFixture('heart_rate_sync.jsonl');

    test('requests are described from their payload', () {
      expect(
        atLine(frames, 1).meaning,
        'setDateTime request 2024-08-10 23:58:00, language 1',
      );
      expect(
        atLine(frames, 6).meaning,
        'heartRateLog request for the day starting 2024-08-10 00:00 '
        '(ring wall clock)',
      );
    });

    test('a device notify push between request and reply is decoded', () {
      expect(atLine(frames, 4).meaning, 'battery push 43%, charging');
      expect(atLine(frames, 5).meaning, 'battery 64%, not charging');
    });

    test('the heart rate log assembles over 24 frames', () {
      expect(atLine(frames, 8).meaning, 'heartRateLog part 1');
      expect(
        atLine(frames, 30).meaning,
        'heartRateLog complete: 295 slots every 5 min, day 2024-08-10, '
        '6 set: 15:00=89 16:00=107 17:00=96 18:00=107 20:00=80 21:00=70',
      );
    });

    test('no frame fails', () {
      expect(frames.where((f) => f.failed), isEmpty);
    });
  });

  group('activity_big_data.jsonl', () {
    final frames = decodeFixture('activity_big_data.jsonl');

    test('the activity log completes on the record after the header', () {
      expect(
        atLine(frames, 2).meaning,
        'activityLog part, waiting for more frames',
      );
      expect(
        atLine(frames, 3).meaning,
        'activityLog complete: 2024-10-15 23:00 21 steps, 16 m, 1210 cal',
      );
    });

    test('big data is reassembled across notifications', () {
      expect(atLine(frames, 4).meaning, 'big data request spo2, payload [ff]');
      expect(atLine(frames, 5).meaning, contains('waiting for more'));
      expect(
        atLine(frames, 7).meaning,
        startsWith('big data spo2: days ago 1: 24 hours'),
      );
      expect(
        atLine(frames, 11).meaning,
        'big data sleep: days ago 0: 23:00 to 07:00, light 120 min, '
        'error 30 min, deep 90 min, rem 60 min',
      );
      expect(
        atLine(frames, 13).meaning,
        'big data temperature: days ago 0: 2 slots with data: '
        '00:00=33.0C 01:00=33.2C',
      );
    });

    test('big data frames carry no V1 checksum', () {
      expect(atLine(frames, 5).checksum, isNull);
    });
  });

  group('decode command', () {
    test('prints raw hex, reasons and the checksum verdict', () async {
      final result = await cli(['decode', fixturePath('checksum_cases.jsonl')]);

      expect(result.code, 0);
      expect(
        result.out,
        contains('03 40 00 00 00 00 00 00 00 00 00 00 00 00 00 44\n'),
      );
      expect(result.out, contains('MISMATCH under both rules'));
      expect(result.out, contains('line 12 MALFORMED: not JSON'));
      expect(
        result.out,
        contains(
          'v1 checksum over 7 frames: 2 both, 3 masked only, '
          '1 modulo 255 only, 1 neither',
        ),
      );
      expect(result.out, endsWith('rule satisfied by every v1 frame: none\n'));
    });

    test('a clean masked trace names the masked rule', () async {
      final result = await cli([
        'decode',
        fixturePath('heart_rate_sync.jsonl'),
      ]);

      expect(
        result.out,
        endsWith('rule satisfied by every v1 frame: masked (& 0xFF)\n'),
      );
    });

    test('usage errors and missing files', () async {
      expect((await cli([])).code, ExitCodes.usage);
      expect((await cli(['help'])).code, ExitCodes.ok);
      expect((await cli(['explode', 'x'])).code, ExitCodes.usage);
      expect((await cli(['decode'])).code, ExitCodes.usage);
      final withOption = await cli([
        'decode',
        fixturePath('heart_rate_sync.jsonl'),
        '--now',
        '2024-08-10T23:59',
      ]);
      expect(withOption.code, ExitCodes.usage);
      expect(withOption.err, contains('Unknown option --now for decode'));
      final missing = await cli(['decode', fixturePath('nope.jsonl')]);
      expect(missing.code, ExitCodes.noInput);
      expect(missing.err, startsWith('Cannot read'));
    });
  });
}

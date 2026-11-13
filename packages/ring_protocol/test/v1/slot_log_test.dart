import 'package:ring_protocol/ring_protocol.dart';
import 'package:test/test.dart';

import '../helpers.dart';

// tahnok tests/test_hr.py HEART_RATE_PACKETS, a capture for 2024-08-10.
final List<V1Frame> tahnokHeartRate = [
  '15 00 18 05 00 00 00 00 00 00 00 00 00 00 00 32',
  '15 01 80 ad b6 66 00 00 00 00 00 00 00 00 00 5f',
  for (var i = 2; i <= 0x0e; i++)
    '15 ${byteHex(i)} 00 00 00 00 00 00 00 00 00 00 00 00 00 ${byteHex(0x15 + i)}',
  '15 0f 00 00 59 00 00 00 00 00 00 00 00 00 00 7d',
  '15 10 00 6b 00 00 00 00 00 00 00 00 00 00 00 90',
  '15 11 60 00 00 00 00 00 00 00 00 00 00 00 6b f1',
  '15 12 00 00 00 00 00 00 00 00 00 00 00 00 00 27',
  '15 13 00 00 00 00 00 00 00 00 00 00 50 00 00 78',
  '15 14 00 00 00 00 00 00 00 00 00 46 00 00 00 6f',
  '15 15 00 00 00 00 00 00 00 00 00 00 00 00 00 2a',
  '15 16 00 00 00 00 00 00 00 00 00 00 00 00 00 2b',
  '15 17 00 00 00 00 00 00 00 00 00 00 00 00 00 2c',
].map((line) => frame(hex(line))).toList();

// COLMI R09 capture for 2026-11-13, taken after the app wrote a 10 minute
// automatic heart rate interval. Captured verbatim: header 0, frames 8 and 9,
// frames 10..23. Synthesized for privacy (sleep readings): frames 1..7 carry
// zero values with valid checksums, frame 1 keeps its captured day start.
final List<V1Frame> r09TenMinuteHeartRate = [
  '15 00 18 05 00 00 00 00 00 00 00 00 00 00 00 32',
  '15 01 00 53 f6 6a 00 00 00 00 00 00 00 00 00 c9',
  for (var i = 2; i <= 7; i++)
    '15 ${byteHex(i)} 00 00 00 00 00 00 00 00 00 00 00 00 00 ${byteHex(0x15 + i)}',
  '15 08 51 56 54 5f 55 62 59 62 67 4d 00 5a 00 f7',
  '15 09 4e 00 49 00 5c 00 52 00 00 00 00 00 00 63',
  for (var i = 0x0a; i <= 0x17; i++)
    '15 ${byteHex(i)} 00 00 00 00 00 00 00 00 00 00 00 00 00 ${byteHex(0x15 + i)}',
].map((line) => frame(hex(line))).toList();

String byteHex(int value) => value.toRadixString(16).padLeft(2, '0');

ParseResult<SlotLog>? feed(SlotLogAssembler assembler, List<V1Frame> frames) {
  ParseResult<SlotLog>? last;
  for (final f in frames) {
    last = assembler.add(f);
  }
  return last;
}

void main() {
  group('requests', () {
    test(
      'heart rate log carries the day start as uint32 LE (tahnok hr.py)',
      () {
        expect(
          heartRateLogRequest(1723248000),
          padded([0x15, 0x80, 0xAD, 0xB6, 0x66]),
        );
      },
    );

    test(
      'stress log for today is the bare id (Gadgetbridge fetchHistoryStress)',
      () {
        expect(stressLogRequest(), padded([0x37]));
      },
    );

    test('hrv log puts days ago in byte 1 (Gadgetbridge fetchHistoryHRV)', () {
      expect(hrvLogRequest(daysAgo: 3), padded([0x39, 3]));
    });

    test('rejects values that do not fit', () {
      expect(() => heartRateLogRequest(-1), throwsArgumentError);
      expect(() => hrvLogRequest(daysAgo: 256), throwsArgumentError);
    });
  });

  group('heart rate log 0x15', () {
    test('reassembles the tahnok capture into 295 five minute slots', () {
      final assembler = SlotLogAssembler.heartRate();
      for (final f in tahnokHeartRate.take(tahnokHeartRate.length - 1)) {
        expect(assembler.add(f), isNull);
      }
      final result = assembler.add(tahnokHeartRate.last)! as Parsed<SlotLog>;
      final log = result.value;
      expect(log.intervalMinutes, 5);
      expect(log.reportedSeconds, 1723248000);
      expect(log.values.length, 9 + 22 * 13);
      final readings = {
        for (var i = 0; i < log.values.length; i++)
          if (log.values[i] != 0) i: log.values[i],
      };
      expect(readings, {
        180: 89,
        192: 107,
        204: 96,
        216: 107,
        240: 80,
        252: 70,
      });
      expect(assembler.inProgress, isFalse);
    });

    test('R09 log after a 10 minute write keeps the 5 minute grid', () {
      final result =
          feed(SlotLogAssembler.heartRate(), r09TenMinuteHeartRate)!
              as Parsed<SlotLog>;
      final log = result.value;
      expect(log.intervalMinutes, 5);
      expect(log.reportedSeconds, 0x6af65300);
      expect(log.values.length, 295);
      expect(log.values.sublist(96, 112), [
        77,
        0,
        90,
        0,
        78,
        0,
        73,
        0,
        92,
        0,
        82,
        0,
        0,
        0,
        0,
        0,
      ]);
      expect(log.values.sublist(87, 96).every((v) => v != 0), isTrue);
    });

    test('a stream that stops early stays in progress (truncated)', () {
      final assembler = SlotLogAssembler.heartRate();
      expect(feed(assembler, tahnokHeartRate.take(10).toList()), isNull);
      expect(assembler.inProgress, isTrue);
    });

    test('index 0xFF means no data (tahnok test_parse_no_data)', () {
      final noData = frame(
        hex('15 ff 00 00 00 00 00 00 00 00 00 00 00 00 00 14'),
      );
      expect(
        SlotLogAssembler.heartRate().add(noData),
        Parsed(SlotLog(intervalMinutes: 0, values: const [])),
      );
    });

    test('a packet out of order fails and resets', () {
      final assembler = SlotLogAssembler.heartRate()..add(tahnokHeartRate[0]);
      expect(
        assembler.add(tahnokHeartRate[2]),
        const ParseFailure<SlotLog>(ByteOutOfRange(index: 1, value: 2)),
      );
      expect(assembler.inProgress, isFalse);
    });

    test('data before the header fails', () {
      expect(
        SlotLogAssembler.heartRate().add(tahnokHeartRate[1]),
        const ParseFailure<SlotLog>(ByteOutOfRange(index: 1, value: 1)),
      );
    });

    sharedFailures(0x15, (f) => SlotLogAssembler.heartRate().add(f)!);
  });

  group('stress 0x37 and hrv 0x39', () {
    // Gadgetbridge historicalStress / historicalHRV: header, then packet 1
    // with values from byte 3, then 13 values per packet from byte 2.
    List<V1Frame> halfHourly(int id) => [
      frame([id, 0, 5, 30]),
      frame([id, 1, 0x00, 40, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 41]),
      frame([id, 2, 42]),
      frame([id, 3]),
      frame([id, 4, ...List.filled(12, 0), 43]),
    ];

    for (final (id, make) in [
      (0x37, SlotLogAssembler.stress),
      (0x39, SlotLogAssembler.hrv),
    ]) {
      test(
        '0x${id.toRadixString(16)} lays out 12 then 13 values per packet',
        () {
          final result = feed(make(), halfHourly(id))! as Parsed<SlotLog>;
          final log = result.value;
          expect(log.intervalMinutes, 30);
          expect(log.values.length, 12 + 3 * 13);
          expect(log.values[0], 40);
          expect(log.values[11], 41);
          expect(log.values[12], 42);
          expect(log.values[50], 43);
          expect(log.reportedSeconds, isNull);
        },
      );

      test('0x${id.toRadixString(16)} stays in progress when cut short', () {
        final assembler = make();
        expect(feed(assembler, halfHourly(id).take(3).toList()), isNull);
        expect(assembler.inProgress, isTrue);
      });

      test(
        '0x${id.toRadixString(16)} header with a zero range falls back to 30',
        () {
          final assembler = make()..add(frame([id, 0, 2, 0]));
          final result =
              assembler.add(frame([id, 1, 0, 7]))! as Parsed<SlotLog>;
          expect(result.value.intervalMinutes, 30);
        },
      );

      test(
        '0x${id.toRadixString(16)} header announcing one packet is an empty log',
        () {
          expect(
            make().add(frame([id, 0, 1, 30])),
            Parsed(SlotLog(intervalMinutes: 30, values: const [])),
          );
        },
      );

      sharedFailures(id, (f) => make().add(f)!);
    }
  });
}

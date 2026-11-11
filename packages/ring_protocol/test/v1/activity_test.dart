import 'dart:typed_data';

import 'package:ring_protocol/ring_protocol.dart';
import 'package:test/test.dart';

import '../helpers.dart';

// tahnok tests/test_steps.py, a capture of five quarter hours on 2023-08-13.
final List<V1Frame> tahnokSteps = [
  '43 f0 05 01 00 00 00 00 00 00 00 00 00 00 00 39',
  '43 23 08 13 10 00 05 c8 00 30 00 1b 00 00 00 a9',
  '43 23 08 13 14 01 05 b6 18 aa 04 69 03 00 00 83',
  '43 23 08 13 18 02 05 38 04 e1 00 95 00 00 00 52',
  '43 23 08 13 1c 03 05 05 02 6c 00 48 00 00 00 60',
  '43 23 08 13 4c 04 05 ef 01 63 00 44 00 00 00 6d',
].map((line) => frame(hex(line))).toList();

void main() {
  group('activityLogRequest', () {
    test('carries the day offset and the constant tail (tahnok steps.py)', () {
      expect(
        activityLogRequest(daysAgo: 2),
        padded([0x43, 2, 0x0F, 0x00, 0x5F, 0x01]),
      );
    });

    test('rejects a day offset that does not fit', () {
      expect(() => activityLogRequest(daysAgo: -1), throwsArgumentError);
    });
  });

  group('ActivityLogAssembler', () {
    test(
      'reassembles the tahnok capture, calories x10 under the new protocol',
      () {
        final assembler = ActivityLogAssembler();
        for (final f in tahnokSteps.take(5)) {
          expect(assembler.add(f), isNull);
        }
        final result = assembler.add(tahnokSteps.last)! as Parsed;
        final records = result.value as List<ActivityRecord>;
        expect(records.length, 5);
        expect(
          records[0],
          const ActivityRecord(
            year: 2023,
            month: 8,
            day: 13,
            quarterOfDay: 16,
            calories: 2000,
            steps: 48,
            distanceMeters: 27,
          ),
        );
        expect(records[1].steps, 1194);
        expect(records[1].calories, 63260);
        expect(records[1].distanceMeters, 873);
        expect(records.last.minuteOfDay, 0x4C * 15);
      },
    );

    test('single record capture from tahnok test_steps.py', () {
      final assembler = ActivityLogAssembler()
        ..add(frame(hex('43 f0 01 01 00 00 00 00 00 00 00 00 00 00 00 35')));
      final result = assembler.add(
        frame(hex('43 24 10 15 5c 00 01 79 00 15 00 10 00 00 00 87')),
      );
      expect(
        result,
        parsed(const [
          ActivityRecord(
            year: 2024,
            month: 10,
            day: 15,
            quarterOfDay: 92,
            calories: 1210,
            steps: 21,
            distanceMeters: 16,
          ),
        ]),
      );
    });

    test('0xFF in byte 1 means no data (tahnok test_steps.py)', () {
      expect(
        ActivityLogAssembler().add(
          frame(hex('43 ff 00 00 00 00 00 00 00 00 00 00 00 00 00 42')),
        ),
        parsed(isEmpty),
      );
    });

    test('a stream cut short returns null (truncated)', () {
      final assembler = ActivityLogAssembler();
      for (final f in tahnokSteps.take(3)) {
        expect(assembler.add(f), isNull);
      }
    });

    test('a date byte that is not BCD is out of range', () {
      expect(
        ActivityLogAssembler().add(frame([0x43, 0x2A, 0x08, 0x13, 0, 0, 1])),
        const ParseFailure<List<ActivityRecord>>(
          ByteOutOfRange(index: 1, value: 0x2A),
        ),
      );
    });

    test('a quarter past 95 is out of range', () {
      expect(
        ActivityLogAssembler().add(frame([0x43, 0x24, 0x08, 0x13, 96, 0, 1])),
        const ParseFailure<List<ActivityRecord>>(
          ByteOutOfRange(index: 4, value: 96),
        ),
      );
    });

    sharedFailures(0x43, (f) => ActivityLogAssembler().add(f)!);
  });

  group('today totals 0x48', () {
    test("request is the bare id (Puxtril Today's Sports)", () {
      expect(todayTotalsRequest(), padded([0x48]));
    });

    test('reads five fields laid out as in Puxtril TodaySportsResponse', () {
      expect(
        parseTodayTotals(
          frame([
            0x48,
            0x00,
            0x1F,
            0x40,
            0x00,
            0x01,
            0xF4,
            0x00,
            0x30,
            0x39,
            0x00,
            0x13,
            0x88,
            0x00,
            0x5A,
          ]),
        ),
        const Parsed(
          TodayTotals(
            totalSteps: 8000,
            runningSteps: 500,
            calories: 12345,
            walkingDistanceMeters: 5000,
            activeMinutes: 90,
          ),
        ),
      );
    });

    test('reads the same five fields little endian when asked', () {
      final littleEndian = frame([
        0x48,
        0x40,
        0x1F,
        0x00,
        0xF4,
        0x01,
        0x00,
        0x39,
        0x30,
        0x00,
        0x88,
        0x13,
        0x00,
        0x5A,
        0x00,
      ]);

      expect(
        parseTodayTotals(littleEndian, order: Endian.little),
        const Parsed(
          TodayTotals(
            totalSteps: 8000,
            runningSteps: 500,
            calories: 12345,
            walkingDistanceMeters: 5000,
            activeMinutes: 90,
          ),
        ),
      );
      expect(
        parseTodayTotals(littleEndian),
        const Parsed(
          TodayTotals(
            totalSteps: 0x401F00,
            runningSteps: 0xF40100,
            calories: 0x393000,
            walkingDistanceMeters: 0x881300,
            activeMinutes: 0x5A00,
          ),
        ),
      );
    });

    sharedFailures(0x48, (f) => parseTodayTotals(f, order: Endian.little));
    sharedFailures(0x48, parseTodayTotals);
  });
}

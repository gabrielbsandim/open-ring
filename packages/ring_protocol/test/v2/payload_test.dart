import 'package:ring_protocol/ring_protocol.dart';
import 'package:test/test.dart';

import '../helpers.dart';

void main() {
  group('parseSleep 0x27', () {
    // Gadgetbridge historicalSleep: day count, then per day days ago, byte
    // count, start and end as LE minutes after midnight, then stage pairs.
    final twoNights = [
      2,
      1,
      10,
      0x64,
      0x05,
      0xA4,
      0x01,
      2,
      120,
      3,
      90,
      5,
      15,
      0,
      8,
      0x1E,
      0x00,
      0x90,
      0x01,
      4,
      60,
      2,
      200,
    ];

    test('parses two nights laid out as in Gadgetbridge and Puxtril', () {
      expect(
        parseSleep(BigDataPacket(BigDataId.sleep, twoNights)),
        parsed([
          SleepDay(
            daysAgo: 1,
            startMinute: 1380,
            endMinute: 420,
            periods: const [
              SleepPeriod(stage: SleepStageCode.light, minutes: 120),
              SleepPeriod(stage: SleepStageCode.deep, minutes: 90),
              SleepPeriod(stage: SleepStageCode.awake, minutes: 15),
            ],
          ),
          SleepDay(
            daysAgo: 0,
            startMinute: 30,
            endMinute: 400,
            periods: const [
              SleepPeriod(stage: SleepStageCode.rem, minutes: 60),
              SleepPeriod(stage: SleepStageCode.light, minutes: 200),
            ],
          ),
        ]),
      );
    });

    test('reads start as signed, which Puxtril int16 allows', () {
      final result = parseSleep(
        BigDataPacket(BigDataId.sleep, const [1, 0, 4, 0xC4, 0xFF, 0xA4, 0x01]),
      );
      final day = (result as Parsed<List<SleepDay>>).value.single;
      expect(day.startMinute, -60);
      expect(day.periods, isEmpty);
    });

    test('an empty payload or zero days is no sleep', () {
      expect(
        parseSleep(BigDataPacket(BigDataId.sleep, const [])),
        parsed(isEmpty),
      );
      expect(
        parseSleep(BigDataPacket(BigDataId.sleep, const [0])),
        parsed(isEmpty),
      );
    });

    test('a truncated day header is reported', () {
      expect(
        parseSleep(BigDataPacket(BigDataId.sleep, const [1, 0, 8, 0x1E])),
        const ParseFailure<List<SleepDay>>(WrongLength(expected: 7, actual: 4)),
      );
    });

    test('stage pairs cut short are reported', () {
      expect(
        parseSleep(BigDataPacket(BigDataId.sleep, twoNights.sublist(0, 20))),
        const ParseFailure<List<SleepDay>>(
          WrongLength(expected: 23, actual: 20),
        ),
      );
    });

    test('a day byte count below 4 is out of range', () {
      expect(
        parseSleep(BigDataPacket(BigDataId.sleep, const [1, 0, 2, 0, 0, 0, 0])),
        const ParseFailure<List<SleepDay>>(ByteOutOfRange(index: 2, value: 2)),
      );
    });

    test('another data id is rejected', () {
      expect(
        parseSleep(BigDataPacket(BigDataId.spo2, twoNights)),
        const ParseFailure<List<SleepDay>>(
          UnexpectedCommand(expected: 0x27, actual: 0x2A),
        ),
      );
    });
  });

  group('parseSpo2 0x2A', () {
    // Gadgetbridge historicalSpo2: days ago, then 24 {min, max} hour pairs.
    final yesterday = [
      1,
      for (var h = 0; h < 24; h++) ...[95, 98],
    ];
    final todaySoFar = [0, 96, 99, 0, 0, 94, 97];

    test('parses a full day and a partial day', () {
      final result = parseSpo2(
        BigDataPacket(BigDataId.spo2, [...yesterday, ...todaySoFar]),
      );
      final days = (result as Parsed<List<Spo2Day>>).value;
      expect(days.length, 2);
      expect(days[0].daysAgo, 1);
      expect(days[0].hourly.length, 24);
      expect(days[0].hourly.first, const Spo2Range(min: 95, max: 98));
      expect(days[1].daysAgo, 0);
      expect(days[1].hourly, const [
        Spo2Range(min: 96, max: 99),
        Spo2Range(min: 0, max: 0),
        Spo2Range(min: 94, max: 97),
      ]);
      expect(days[1].hourly[1].hasData, isFalse);
    });

    test('an hour pair cut in half is reported', () {
      expect(
        parseSpo2(BigDataPacket(BigDataId.spo2, const [0, 96, 99, 95])),
        const ParseFailure<List<Spo2Day>>(WrongLength(expected: 5, actual: 4)),
      );
    });

    test('another data id is rejected', () {
      expect(
        parseSpo2(BigDataPacket(BigDataId.sleep, yesterday)),
        const ParseFailure<List<Spo2Day>>(
          UnexpectedCommand(expected: 0x2A, actual: 0x27),
        ),
      );
    });
  });

  group('parseTemperature 0x25', () {
    // Gadgetbridge historicalTemperature: days ago, an unknown byte (0x1e),
    // then two slots per hour, each byte / 10 + 20 degrees C.
    test('parses half hourly slots and skips zeros', () {
      final payload = [0, 0x1E, 0x96, 0x00, 0x8C, ...List.filled(45, 0)];
      final result = parseTemperature(
        BigDataPacket(BigDataId.temperature, payload),
      );
      final day = (result as Parsed<List<TemperatureDay>>).value.single;
      expect(day.daysAgo, 0);
      expect(day.halfHourly.length, 48);
      expect(day.halfHourly[0], closeTo(35.0, 1e-9));
      expect(day.halfHourly[1], isNull);
      expect(day.halfHourly[2], closeTo(34.0, 1e-9));
    });

    test('a day with only its days ago byte is truncated', () {
      expect(
        parseTemperature(BigDataPacket(BigDataId.temperature, const [0])),
        const ParseFailure<List<TemperatureDay>>(
          WrongLength(expected: 2, actual: 1),
        ),
      );
    });

    test('another data id is rejected', () {
      expect(
        parseTemperature(BigDataPacket(BigDataId.sleep, const [0, 0x1E])),
        const ParseFailure<List<TemperatureDay>>(
          UnexpectedCommand(expected: 0x25, actual: 0x27),
        ),
      );
    });
  });
}

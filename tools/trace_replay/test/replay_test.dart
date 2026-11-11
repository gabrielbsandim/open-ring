import 'package:ring_driver/ring_driver.dart';
import 'package:ring_driver/testing.dart';
import 'package:ring_protocol/ring_protocol.dart';
import 'package:test/test.dart';
import 'package:trace_replay/trace_replay.dart';

import 'helpers.dart';

List<int> halfHourly(int id, int frame) => switch (frame) {
  0 => padded([id, 0, 5, 30]),
  1 => padded([id, 1, 0, 40, ...List.filled(10, 0), 41]),
  2 => padded([id, 2, 42]),
  3 => padded([id, 3]),
  _ => padded([id, 4, ...List.filled(12, 0), 43]),
};

void main() {
  group('heart_rate_sync.jsonl', () {
    late ReplayResult result;

    setUpAll(() async {
      result = await TraceReplayer(now: DateTime(2024, 8, 10, 23, 59))
          .replay(fixtureEntries('heart_rate_sync.jsonl'));
    });

    test('one driver call per recorded request, in order', () {
      expect(result.steps.map((s) => s.call), [
        ReplayCall.syncTime,
        ReplayCall.readBattery,
        ReplayCall.pullHeartRate,
        ReplayCall.pullStress,
        ReplayCall.findDevice,
      ]);
      expect(result.steps.where((s) => s.failed), isEmpty);
      expect(result.skipped, isEmpty);
    });

    test('detects the masked rule from the rx frames', () {
      expect(result.rule, ChecksumRule.masked);
      expect(result.ruleDetected, isTrue);
    });

    test('syncTime keeps the capability reply', () {
      final capabilities = result.steps[0].records.single as DeviceCapabilities;
      expect(capabilities.supportsBloodOxygen, isTrue);
      expect(capabilities.supportsTemperature, isFalse);
    });

    test('readBattery skips the device notify push', () {
      final battery = result.steps[1].records.single as BatteryStatus;
      expect(battery.percent, 64);
      expect(battery.charging, isFalse);
    });

    test('pullHeartRate maps the tahnok capture', () {
      final samples = result.steps[2].records.cast<HeartRateSample>();
      expect(samples.map((s) => (s.at, s.bpm)), [
        (DateTime(2024, 8, 10, 15), 89),
        (DateTime(2024, 8, 10, 16), 107),
        (DateTime(2024, 8, 10, 17), 96),
        (DateTime(2024, 8, 10, 18), 107),
        (DateTime(2024, 8, 10, 20), 80),
        (DateTime(2024, 8, 10, 21), 70),
      ]);
    });

    test('pullStress drops slots past midnight', () {
      final samples = result.steps[3].records.cast<StressSample>();
      expect(samples.map((s) => (s.at, s.level)), [
        (DateTime(2024, 8, 10), 40),
        (DateTime(2024, 8, 10, 5, 30), 41),
        (DateTime(2024, 8, 10, 6), 42),
      ]);
    });
  });

  group('activity_big_data.jsonl', () {
    late ReplayResult result;

    setUpAll(() async {
      result = await TraceReplayer(now: DateTime(2024, 10, 15, 23, 59))
          .replay(fixtureEntries('activity_big_data.jsonl'));
    });

    test('activity, spo2 and sleep replay; temperature has no driver call', () {
      expect(result.steps.map((s) => s.call), [
        ReplayCall.pullActivity,
        ReplayCall.pullSpo2,
        ReplayCall.pullSleep,
      ]);
      expect(result.steps.where((s) => s.failed), isEmpty);
      expect(result.skipped.single.lineNumber, 12);
    });

    test('pullActivity maps the tahnok single record capture', () {
      final bucket = result.steps[0].records.single as ActivityBucket;
      expect(bucket.start, DateTime(2024, 10, 15, 23));
      expect(bucket.steps, 21);
      expect(bucket.activeKilocalories, closeTo(1.21, 1e-9));
    });

    test('pullSpo2 reassembles 20 byte chunks into hourly samples', () {
      final samples = result.steps[1].records.cast<Spo2Sample>().toList();
      expect(samples, hasLength(25));
      expect(samples.first.at, DateTime(2024, 10, 14));
      expect(samples.last.at, DateTime(2024, 10, 15));
      expect(samples.map((s) => s.percent).toSet(), {97});
    });

    test('pullSleep builds segments that start before midnight', () {
      final segments = result.steps[2].records.cast<SleepSegment>();
      expect(segments.map((s) => (s.start, s.end, s.stage)), [
        (
          DateTime(2024, 10, 14, 23),
          DateTime(2024, 10, 15, 1),
          SleepStage.light,
        ),
        (
          DateTime(2024, 10, 15, 1, 30),
          DateTime(2024, 10, 15, 3),
          SleepStage.deep,
        ),
        (DateTime(2024, 10, 15, 3), DateTime(2024, 10, 15, 4), SleepStage.rem),
      ]);
    });
  });

  group('checksum rule', () {
    final moduloTrace = entriesOf([
      tx(padded([0x03], ChecksumRule.modulo255)),
      rx(padded([0x03, 80, 200], ChecksumRule.modulo255)),
    ]);

    test(
      'a modulo 255 trace is detected and replays with that codec',
      () async {
        final result = await const TraceReplayer().replay(moduloTrace);

        expect(result.rule, ChecksumRule.modulo255);
        final battery = result.steps.single.records.single as BatteryStatus;
        expect(battery.percent, 80);
        expect(battery.charging, isTrue);
      },
    );

    test('forcing the other rule fails the step with the mismatch', () async {
      final result = await const TraceReplayer(rule: ChecksumRule.masked)
          .replay(moduloTrace);

      expect(result.ruleDetected, isFalse);
      expect(
        result.steps.single.error,
        'checksum mismatch: expected 0x001b, got 0x001c',
      );
    });
  });

  group('exchanges', () {
    test('consecutive per day requests become one multi day call', () async {
      final result = await TraceReplayer(now: DateTime(2024, 8, 10, 23, 59))
          .replay(
            entriesOf([
              tx(padded([0x39, 0])),
              rx(padded([0x39, 0xFF])),
              tx(padded([0x39, 1])),
              for (var i = 0; i < 5; i++) rx(halfHourly(0x39, i)),
            ]),
          );

      final step = result.steps.single;
      expect(step.call, ReplayCall.pullHrv);
      expect(step.requests, hasLength(2));
      final samples = step.records.cast<HrvSample>();
      expect(samples.first.at, DateTime(2024, 8, 9));
      expect(samples.map((s) => s.milliseconds), [40, 41, 42]);
    });

    test('a request with no recorded reply times out', () async {
      final result =
          await const TraceReplayer(timeout: Duration(milliseconds: 20)).replay(
            entriesOf([
              tx(padded([0x03])),
            ]),
          );

      expect(result.steps.single.error, 'no complete reply within 20 ms');
    });

    test('a write nobody recorded is refused by the script', () {
      final script = ReplayScript(
        entriesOf([
          tx(padded([0x03])),
        ]),
      );

      expect(
        () => script.respond(GattPacket(ColmiDriver.write, padded([0x48]))),
        throwsA(isA<BleTransportException>()),
      );
    });

    test('the same command matches when the body differs', () {
      final script = ReplayScript(
        entriesOf([
          tx(padded([0x15, 1, 2, 3, 4])),
          rx(padded([0x15, 0xFF])),
        ]),
      );

      final replies = script.respond(
        GattPacket(ColmiDriver.write, padded([0x15, 9, 9, 9, 9])),
      );

      expect(replies.single.bytes, padded([0x15, 0xFF]));
      expect(
        () => script.respond(GattPacket(ColmiDriver.write, padded([0x15]))),
        throwsA(isA<BleTransportException>()),
      );
    });
  });

  group('replay command', () {
    test('prints every record of the replayed sync', () async {
      final result = await cli([
        'replay',
        fixturePath('heart_rate_sync.jsonl'),
        '--now=2024-08-10T23:59',
      ]);

      expect(result.code, ExitCodes.ok);
      expect(
        result.out,
        startsWith(
          'replay: 5 steps, checksum rule masked (& 0xFF), '
          'detected from the trace\n',
        ),
      );
      expect(result.out, contains('step 3 pullHeartRate (tx line 6, 1 day)\n'));
      expect(result.out, contains('  2024-08-10 15:00  heart rate 89 bpm\n'));
      expect(result.out, contains('  battery 64%, not charging\n'));
    });

    test('lists requests it cannot replay', () async {
      final result = await cli([
        'replay',
        fixturePath('activity_big_data.jsonl'),
        '--now',
        '2024-10-15T23:59',
        '--checksum',
        'masked',
      ]);

      expect(result.out, contains('checksum rule masked (& 0xFF), forced'));
      expect(
        result.out,
        endsWith(
          'not replayed: line 12 bc 25 01 00 3e 81 02 '
          '(no driver call sends it)\n',
        ),
      );
    });

    test('rejects bad option values', () async {
      final path = fixturePath('heart_rate_sync.jsonl');
      for (final args in [
        ['--checksum', 'crc'],
        ['--now', 'tomorrow'],
        ['--timeout', '0'],
        ['--timeout'],
        ['--verbose', 'yes'],
        ['stray'],
      ]) {
        expect((await cli(['replay', path, ...args])).code, ExitCodes.usage);
      }
    });
  });
}

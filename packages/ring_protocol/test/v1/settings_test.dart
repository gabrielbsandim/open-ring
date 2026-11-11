import 'package:ring_protocol/ring_protocol.dart';
import 'package:test/test.dart';

import '../helpers.dart';

void main() {
  group('auto heart rate 0x16', () {
    test('read request is the id and action 1 (tahnok hr_settings.py)', () {
      expect(autoHeartRateReadRequest(), padded([0x16, 0x01]));
    });

    test('write request carries 1 for on and the interval (tahnok)', () {
      expect(
        autoHeartRateWriteRequest(
          const AutoHeartRateSetting(enabled: true, intervalMinutes: 30),
        ),
        padded([0x16, 0x02, 0x01, 30]),
      );
    });

    test(
      'write request carries 2 for off (Gadgetbridge onSendConfiguration)',
      () {
        expect(
          autoHeartRateWriteRequest(
            const AutoHeartRateSetting(enabled: false, intervalMinutes: 0),
          ),
          padded([0x16, 0x02, 0x02, 0]),
        );
      },
    );

    test('rejects an interval that does not fit in one byte', () {
      expect(
        () => autoHeartRateWriteRequest(
          const AutoHeartRateSetting(enabled: true, intervalMinutes: 300),
        ),
        throwsArgumentError,
      );
    });

    test('parses enabled every 60 min from tahnok test_hr_settings.py', () {
      expect(
        codec.parse(
          hex('16 01 01 3c 00 00 00 00 00 00 00 00 00 00 00 54'),
          parseAutoHeartRateSetting,
        ),
        const Parsed(AutoHeartRateSetting(enabled: true, intervalMinutes: 60)),
      );
    });

    test('parses disabled from tahnok test_hr_settings.py', () {
      expect(
        codec.parse(
          hex('16 01 02 3c 00 00 00 00 00 00 00 00 00 00 00 55'),
          parseAutoHeartRateSetting,
        ),
        const Parsed(AutoHeartRateSetting(enabled: false, intervalMinutes: 60)),
      );
    });

    test('an enabled byte other than 1 or 2 is out of range', () {
      expect(
        parseAutoHeartRateSetting(frame([0x16, 0x01, 0x07, 60])),
        const ParseFailure<AutoHeartRateSetting>(
          ByteOutOfRange(index: 2, value: 7),
        ),
      );
    });

    test('a write acknowledgement is not a read response', () {
      expect(
        parseAutoHeartRateSetting(frame([0x16, 0x02])),
        const ParseFailure<AutoHeartRateSetting>(
          ByteOutOfRange(index: 1, value: 2),
        ),
      );
      expect(
        parseSettingAck(frame([0x16, 0x02]), V1Command.autoHeartRateSetting),
        const Parsed(SettingAction.write),
      );
    });

    sharedFailures(0x16, parseAutoHeartRateSetting);
  });

  for (final monitor in AutoMonitor.values) {
    final id = monitor.command.id;
    group('auto ${monitor.name} 0x${id.toRadixString(16)}', () {
      test('read request is the id and action 1 (Gadgetbridge requestSettingsFromRing)', () {
        expect(autoMonitorReadRequest(monitor), padded([id, 0x01]));
      });

      test('write request is action 2 then 1 or 0 (Gadgetbridge onSendConfiguration)', () {
        expect(
          autoMonitorWriteRequest(monitor, enabled: true),
          padded([id, 0x02, 0x01]),
        );
        expect(
          autoMonitorWriteRequest(monitor, enabled: false),
          padded([id, 0x02, 0x00]),
        );
      });

      test('reads byte 2 as the enabled flag (Gadgetbridge PacketHandler)', () {
        expect(
          parseAutoMonitor(frame([id, 0x01, 0x01]), monitor),
          const Parsed(true),
        );
        expect(
          parseAutoMonitor(frame([id, 0x01, 0x00]), monitor),
          const Parsed(false),
        );
      });

      test('an enabled byte above 2 is out of range', () {
        expect(
          parseAutoMonitor(frame([id, 0x01, 0x09]), monitor),
          const ParseFailure<bool>(ByteOutOfRange(index: 2, value: 9)),
        );
      });

      sharedFailures(id, (f) => parseAutoMonitor(f, monitor));
    });
  }

  group('parseSettingAck', () {
    test('an unknown action byte is out of range', () {
      expect(
        parseSettingAck(frame([0x2C, 0x09]), V1Command.autoSpo2Setting),
        const ParseFailure<SettingAction>(ByteOutOfRange(index: 1, value: 9)),
      );
    });

    sharedFailures(0x38, (f) => parseSettingAck(f, V1Command.autoHrvSetting));
  });
}

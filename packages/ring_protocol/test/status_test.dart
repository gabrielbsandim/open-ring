import 'package:ring_protocol/ring_protocol.dart';
import 'package:test/test.dart';

void main() {
  test('only entries checked on a real R09 are verified', () {
    final verified = [
      ...v1CommandStatus.values,
      ...bigDataStatus.values,
      ...framingStatus.values,
    ].where((e) => e.verified).map((e) => e.name);
    expect(
      verified,
      unorderedEquals([
        'battery',
        'heartRateLog',
        'stressLog',
        'hrvLog',
        'activityLog',
        'spo2',
        'autoHeartRateSetting',
        'sleep',
        'V2 crc16 (CRC-16/MODBUS over the payload, little endian)',
        'V2 request payload',
        'findDevice',
        'V1 checksum rule',
        'realTimeData',
        'continuousHeartRate',
        'setDateTime',
        'autoSpo2Setting',
        'autoStressSetting',
        'autoHrvSetting',
        'todayActivity',
        'stopRealTime',
        'deviceNotify',
      ]),
    );
  });

  test('the codec defaults to the verified masked checksum', () {
    final reply = const V1FrameCodec().encodeRaw(0x15, [
      0x01,
      0x80,
      0x5E,
      0xF2,
      0x6A,
      0x49,
    ]);
    expect(reply.last, 0x99);
  });

  test('every implemented V1 command has a status row', () {
    final implemented = {
      V1Command.setDateTime,
      V1Command.battery,
      V1Command.heartRateLog,
      V1Command.autoHeartRateSetting,
      V1Command.continuousHeartRate,
      V1Command.autoSpo2Setting,
      V1Command.autoStressSetting,
      V1Command.stressLog,
      V1Command.autoHrvSetting,
      V1Command.hrvLog,
      V1Command.activityLog,
      V1Command.todayActivity,
      V1Command.findDevice,
      V1Command.realTimeData,
      V1Command.deviceNotify,
    }.map((c) => c.id);
    expect(v1CommandStatus.keys, containsAll(implemented));
    expect(v1CommandStatus.keys, contains(V1ExtraCommandId.stopRealTime));
  });

  test('power off and factory reset stay out of the table', () {
    expect(v1CommandStatus.containsKey(V1Command.powerOff.id), isFalse);
    expect(v1CommandStatus.containsKey(V1Command.factoryReset.id), isFalse);
  });

  test('every big data id has a status row', () {
    expect(
      bigDataStatus.keys,
      unorderedEquals([BigDataId.temperature, BigDataId.sleep, BigDataId.spo2]),
    );
  });
}

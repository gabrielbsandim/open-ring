import 'package:ring_protocol/ring_protocol.dart';
import 'package:test/test.dart';

void main() {
  test('every command id is unique and fits in one byte', () {
    final ids = V1Command.values.map((c) => c.id).toList();
    expect(ids.toSet().length, ids.length);
    expect(ids.every((id) => id >= 0 && id <= 0xFF), isTrue);
  });

  test('fromId finds a known command and returns null otherwise', () {
    expect(V1Command.fromId(0x15), V1Command.heartRateLog);
    expect(V1Command.fromId(0x07), isNull);
  });

  test('ids match the protocol doc', () {
    expect(V1Command.battery.id, 0x03);
    expect(V1Command.realTimeData.id, 0x69);
    expect(V1Command.bigData.id, 0xBC);
    expect(BigDataId.sleep, 0x27);
    expect(BigDataId.spo2, 0x2A);
    expect(SettingAction.values.map((a) => a.id), [1, 2, 3]);
  });
}

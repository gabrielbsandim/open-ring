import 'package:meta/meta.dart';

enum ProtocolSource { gadgetbridge, tahnok, puxtril }

@immutable
final class ProtocolEntry {
  const new({
    required this.name,
    required this.verified,
    required this.sources,
    this.note = '',
  });

  final String name;
  final bool verified;
  final Set<ProtocolSource> sources;
  final String note;
}

const Set<ProtocolSource> _all = {
  ProtocolSource.gadgetbridge,
  ProtocolSource.tahnok,
  ProtocolSource.puxtril,
};
const Set<ProtocolSource> _gbPux = {
  ProtocolSource.gadgetbridge,
  ProtocolSource.puxtril,
};

const Map<int, ProtocolEntry> v1CommandStatus = {
  0x01: ProtocolEntry(
    name: 'setDateTime',
    verified: true,
    sources: _all,
    note: 'an R09 replied with capability flags; its HR slots align with QRing',
  ),
  0x03: ProtocolEntry(name: 'battery', verified: true, sources: _all),
  0x15: ProtocolEntry(
    name: 'heartRateLog',
    verified: true,
    sources: _all,
    note: 'request time is local wall clock encoded as UTC, checked on an R09',
  ),
  0x16: ProtocolEntry(
    name: 'autoHeartRateSetting',
    verified: true,
    sources: _all,
    note: 'enabled byte 1 on, 2 off; 5 min write gave 5 min slots on an R09',
  ),
  0x1E: ProtocolEntry(
    name: 'continuousHeartRate',
    verified: true,
    sources: {ProtocolSource.gadgetbridge},
    note: 'continue every 20 s kept an R09 at 1 Hz: 121 readings in 120 s',
  ),
  0x2C: ProtocolEntry(
    name: 'autoSpo2Setting',
    verified: true,
    sources: _gbPux,
    note: 'enabled byte 1 on, 0 off; an R09 read back on',
  ),
  0x36: ProtocolEntry(
    name: 'autoStressSetting',
    verified: true,
    sources: _gbPux,
    note: 'an R09 read back on',
  ),
  0x37: ProtocolEntry(
    name: 'stressLog',
    verified: true,
    sources: _gbPux,
    note: 'an R09 day matched QRing: latest 43, range 30 to 65, mean 42',
  ),
  0x38: ProtocolEntry(
    name: 'autoHrvSetting',
    verified: true,
    sources: _gbPux,
    note: 'an R09 read back on',
  ),
  0x39: ProtocolEntry(
    name: 'hrvLog',
    verified: true,
    sources: _gbPux,
    note: 'byte 1 days ago; an R09 latest value matched QRing (44 ms)',
  ),
  0x43: ProtocolEntry(
    name: 'activityLog',
    verified: true,
    sources: _all,
    note: 'calories x10 when header byte 3 is 1, in cal; R09 day matched QRing',
  ),
  0x48: ProtocolEntry(
    name: 'todayActivity',
    verified: true,
    sources: {ProtocolSource.puxtril},
    note: 'big endian, calories in cal; an R09 led the 0x43 sum by 19 min',
  ),
  0x50: ProtocolEntry(
    name: 'findDevice',
    verified: true,
    sources: _all,
    note: 'the ring accepts it under either checksum rule',
  ),
  0x69: ProtocolEntry(
    name: 'realTimeData',
    verified: true,
    sources: _all,
    note: 'one-shot: an R09 gave HR 81 and SpO2 98, then stops',
  ),
  0x6A: ProtocolEntry(
    name: 'stopRealTime',
    verified: true,
    sources: {ProtocolSource.tahnok, ProtocolSource.puxtril},
    note: 'an R09 acknowledged 0x6A and sent no reading after it',
  ),
  0x73: ProtocolEntry(
    name: 'deviceNotify',
    verified: true,
    sources: _all,
    note:
        'an R09 pushed type 1 (new HR data); type 5 payload still provisional',
  ),
};

const Map<int, ProtocolEntry> bigDataStatus = {
  0x25: ProtocolEntry(
    name: 'temperature',
    verified: false,
    sources: {ProtocolSource.gadgetbridge},
    note: 'byte / 10 + 20 degrees C, two slots per hour',
  ),
  0x27: ProtocolEntry(
    name: 'sleep',
    verified: true,
    sources: _gbPux,
    note: 'an R09 night matched the bounds QRing wrote to Health Connect',
  ),
  0x2A: ProtocolEntry(
    name: 'spo2',
    verified: true,
    sources: _gbPux,
    note: 'Gadgetbridge layout; an R09 day range matched QRing (96 to 99)',
  ),
};

const Map<String, ProtocolEntry> framingStatus = {
  'v1Checksum': ProtocolEntry(
    name: 'V1 checksum rule',
    verified: true,
    sources: _all,
    note: 'masked sum: an R09 reply summing to 665 carries 0x99',
  ),
  'v2Crc16': ProtocolEntry(
    name: 'V2 crc16 (CRC-16/MODBUS over the payload, little endian)',
    verified: true,
    sources: {ProtocolSource.gadgetbridge},
    note: 'the R09 fills it; sleep and SpO2 replies pass the check',
  ),
  'v2Request': ProtocolEntry(
    name: 'V2 request payload',
    verified: true,
    sources: _gbPux,
    note: 'Gadgetbridge one 0xFF byte works on an R09; Puxtril empty untried',
  ),
};

import 'package:ring_driver/ring_driver.dart';
import 'package:ring_driver/testing.dart';
import 'package:ring_protocol/ring_protocol.dart';

List<int> hex(String text) => [
  for (final byte in text.trim().split(RegExp(r'\s+')))
    int.parse(byte, radix: 16),
];

GattPacket v1(List<int> head) {
  if (head.length == 16) return GattPacket(ColmiDriver.notify, head);
  final body = [...head, ...List.filled(15 - head.length, 0)];
  return GattPacket(ColmiDriver.notify, [
    ...body,
    const MaskedSumChecksum().compute(body),
  ]);
}

List<GattPacket> bigData(int id, List<int> payload) {
  final crc = crc16Modbus(payload);
  return [
    GattPacket(ColmiDriver.bigDataNotify, [
      0xBC,
      id,
      payload.length & 0xFF,
      payload.length >> 8,
      crc & 0xFF,
      crc >> 8,
      ...payload,
    ]),
  ];
}

String _byte(int value) => value.toRadixString(16).padLeft(2, '0');

// tahnok tests/test_hr.py HEART_RATE_PACKETS, a capture for 2024-08-10.
final List<GattPacket> tahnokHeartRate = [
  for (final line in [
    '15 00 18 05 00 00 00 00 00 00 00 00 00 00 00 32',
    '15 01 80 ad b6 66 00 00 00 00 00 00 00 00 00 5f',
    for (var i = 2; i <= 0x0e; i++)
      '15 ${_byte(i)} 00 00 00 00 00 00 00 00 00 00 00 00 00 ${_byte(0x15 + i)}',
    '15 0f 00 00 59 00 00 00 00 00 00 00 00 00 00 7d',
    '15 10 00 6b 00 00 00 00 00 00 00 00 00 00 00 90',
    '15 11 60 00 00 00 00 00 00 00 00 00 00 00 6b f1',
    '15 12 00 00 00 00 00 00 00 00 00 00 00 00 00 27',
    '15 13 00 00 00 00 00 00 00 00 00 00 50 00 00 78',
    '15 14 00 00 00 00 00 00 00 00 00 46 00 00 00 6f',
    '15 15 00 00 00 00 00 00 00 00 00 00 00 00 00 2a',
    '15 16 00 00 00 00 00 00 00 00 00 00 00 00 00 2b',
    '15 17 00 00 00 00 00 00 00 00 00 00 00 00 00 2c',
  ])
    v1(hex(line)),
];

final List<int> _tahnokDay = [0x80, 0xAD, 0xB6, 0x66];

// Answers every sync request; only 2024-08-10 has heart rate history.
Iterable<GattPacket> tahnokRing(GattPacket write) {
  final bytes = write.bytes;
  if (write.characteristic == ColmiDriver.bigDataWrite) {
    return bigData(bytes[1], const [0]);
  }
  return switch (bytes.first) {
    0x01 => [v1(hex('01 00 01 00 22 00 00 00 00 01 00 30 01 00 10 66'))],
    0x03 => [v1(hex('03 40 00 00 00 00 00 00 00 00 00 00 00 00 00 43'))],
    0x15 when _sameDay(bytes) => tahnokHeartRate,
    0x16 => [
      v1([0x16, bytes[1], 0x01, 0x1E]),
    ],
    0x2C || 0x36 || 0x38 => [
      v1([bytes.first, bytes[1], 0x01]),
    ],
    final command => [
      v1([command, 0xFF]),
    ],
  };
}

bool _sameDay(List<int> bytes) {
  for (var i = 0; i < _tahnokDay.length; i++) {
    if (bytes[i + 1] != _tahnokDay[i]) return false;
  }
  return true;
}

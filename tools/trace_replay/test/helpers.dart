import 'dart:convert';
import 'dart:io';

import 'package:ring_protocol/ring_protocol.dart';
import 'package:trace_replay/trace_replay.dart';

String fixturePath(String name) => 'test/fixtures/$name';

String fixture(String name) => File(fixturePath(name)).readAsStringSync();

List<TraceEntry> fixtureEntries(String name) =>
    Trace.entries(Trace.parse(fixture(name)));

List<int> hex(String text) => [
  for (final byte in text.trim().split(RegExp(r'\s+')))
    int.parse(byte, radix: 16),
];

List<int> padded(List<int> head, [ChecksumRule rule = ChecksumRule.masked]) {
  final body = [...head, ...List.filled(15 - head.length, 0)];
  return [...body, rule.strategy.compute(body)];
}

String line(
  TraceDirection direction,
  String characteristic,
  List<int> bytes, {
  String t = '2024-08-10T12:00:00.000Z',
}) => jsonEncode({
  't': t,
  'dir': direction.name,
  'char': characteristic,
  'hex': Hex.encode(bytes),
});

String tx(List<int> bytes) => line(TraceDirection.tx, ColmiGatt.v1Write, bytes);

String rx(List<int> bytes) =>
    line(TraceDirection.rx, ColmiGatt.v1Notify, bytes);

List<TraceEntry> entriesOf(List<String> lines) =>
    Trace.entries(Trace.parse(lines.join('\n')));

Future<({int code, String out, String err})> cli(List<String> args) async {
  final out = StringBuffer();
  final err = StringBuffer();
  final code = await runCli(args, out: out, err: err);
  return (code: code, out: out.toString(), err: err.toString());
}

import 'dart:convert';

import 'package:meta/meta.dart';
import 'package:ring_protocol/ring_protocol.dart';
import 'package:trace_replay/src/hex.dart';

enum TraceDirection { tx, rx }

enum TraceChannel {
  v1Write(ColmiGatt.v1Write, 'v1 write'),
  v1Notify(ColmiGatt.v1Notify, 'v1 notify'),
  bigDataWrite(ColmiGatt.bigDataWrite, 'big data write'),
  bigDataNotify(ColmiGatt.bigDataNotify, 'big data notify');

  new(this.uuid, this.label);

  final String uuid;
  final String label;

  bool get isBigData => this == bigDataWrite || this == bigDataNotify;

  static TraceChannel? of(String uuid) {
    final wanted = uuid.toLowerCase();
    for (final channel in values) {
      if (channel.uuid == wanted) return channel;
    }
    return null;
  }
}

@immutable
sealed class TraceLine {
  const new(this.lineNumber);

  final int lineNumber;
}

final class TraceEntry extends TraceLine {
  new(
    super.lineNumber, {
    required this.at,
    required this.direction,
    required this.characteristic,
    required List<int> bytes,
  }) : bytes = List.unmodifiable(bytes);

  final DateTime at;
  final TraceDirection direction;
  final String characteristic;
  final List<int> bytes;

  TraceChannel? get channel => TraceChannel.of(characteristic);

  bool get isTx => direction == TraceDirection.tx;
}

final class MalformedLine extends TraceLine {
  const new(super.lineNumber, {required this.reason, required this.source});

  final String reason;
  final String source;
}

abstract final class Trace {
  static List<TraceLine> parse(String source) {
    final lines = const LineSplitter().convert(source);
    return [
      for (var i = 0; i < lines.length; i++)
        if (lines[i].trim().isNotEmpty) parseLine(i + 1, lines[i]),
    ];
  }

  static List<TraceEntry> entries(List<TraceLine> lines) =>
      lines.whereType<TraceEntry>().toList();

  static TraceLine parseLine(int lineNumber, String line) {
    MalformedLine malformed(String reason) =>
        MalformedLine(lineNumber, reason: reason, source: line);

    final Object? json;
    try {
      json = jsonDecode(line);
    } on FormatException catch (error) {
      return malformed('not JSON: ${error.message}');
    }
    if (json is! Map<String, Object?>) {
      return malformed('a line must be a JSON object');
    }
    final fields = (json['t'], json['dir'], json['char'], json['hex']);
    if (fields case (
      final String t,
      final String dir,
      final String char,
      final String hex,
    )) {
      return _entry(lineNumber, t, dir, char, hex, malformed);
    }
    return malformed('t, dir, char and hex must all be strings');
  }

  static TraceLine _entry(
    int lineNumber,
    String t,
    String dir,
    String char,
    String hex,
    MalformedLine Function(String reason) malformed,
  ) {
    final at = DateTime.tryParse(t);
    if (at == null) return malformed('t is not an ISO-8601 time: "$t"');
    final direction = TraceDirection.values.asNameMap()[dir];
    if (direction == null) return malformed('dir must be tx or rx: "$dir"');
    final bytes = Hex.tryDecode(hex);
    if (bytes == null) return malformed('hex is not hex: "$hex"');
    return TraceEntry(
      lineNumber,
      at: at,
      direction: direction,
      characteristic: char.toLowerCase(),
      bytes: bytes,
    );
  }
}

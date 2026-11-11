import 'dart:convert';

import 'package:meta/meta.dart';
import 'package:open_ring/features/ring/domain/hex_bytes.dart';

enum FrameDirection { tx, rx }

@immutable
final class FrameLogEntry {
  new({
    required this.at,
    required this.direction,
    required this.characteristic,
    required List<int> bytes,
  }) : bytes = List.unmodifiable(bytes);

  factory fromJson(Object? json) {
    if (json is! Map<String, Object?>) {
      throw FormatException('A log line must be a JSON object', json);
    }
    final at = DateTime.tryParse(_field(json, 't'));
    final direction = FrameDirection.values.asNameMap()[_field(json, 'dir')];
    final bytes = HexBytes.tryDecode(_field(json, 'hex'));
    if (at == null || direction == null || bytes == null) {
      throw FormatException('Malformed log line', json);
    }
    return FrameLogEntry(
      at: at,
      direction: direction,
      characteristic: _field(json, 'char').toLowerCase(),
      bytes: bytes,
    );
  }

  final DateTime at;
  final FrameDirection direction;
  final String characteristic;
  final List<int> bytes;

  Map<String, String> toJson() => {
    't': at.toUtc().toIso8601String(),
    'dir': direction.name,
    'char': characteristic.toLowerCase(),
    'hex': HexBytes.encode(bytes),
  };

  static String _field(Map<String, Object?> json, String key) =>
      switch (json[key]) {
        final String value => value,
        _ => throw FormatException('Missing string field "$key"', json),
      };

  @override
  bool operator ==(Object other) =>
      other is FrameLogEntry &&
      other.at.isAtSameMomentAs(at) &&
      other.direction == direction &&
      other.characteristic.toLowerCase() == characteristic.toLowerCase() &&
      HexBytes.encode(other.bytes) == HexBytes.encode(bytes);

  @override
  int get hashCode => Object.hash(
    at.microsecondsSinceEpoch,
    direction,
    characteristic.toLowerCase(),
    Object.hashAll(bytes),
  );

  @override
  String toString() => 'FrameLogEntry(${jsonEncode(toJson())})';
}

abstract final class SessionLog {
  static String encode(Iterable<FrameLogEntry> entries) =>
      entries.map((entry) => '${jsonEncode(entry.toJson())}\n').join();

  static List<FrameLogEntry> decode(String source) => const LineSplitter()
      .convert(source)
      .where((line) => line.trim().isNotEmpty)
      .map((line) => FrameLogEntry.fromJson(jsonDecode(line)))
      .toList();
}

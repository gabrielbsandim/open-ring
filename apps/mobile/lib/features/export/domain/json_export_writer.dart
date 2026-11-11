import 'dart:convert';

import 'package:open_ring/features/export/domain/export_kind.dart';
import 'package:open_ring/features/export/domain/export_records.dart';
import 'package:open_ring/features/export/domain/export_values.dart';

Map<String, Object?> exportRecordJson(ExportKind kind, ExportRecord record) {
  final values = exportValues(kind, record);
  return {
    for (final (index, column) in kind.columns.indexed)
      column: exportJson(values[index]),
  };
}

final class JsonExportWriter {
  new(this._sink);

  final StringSink _sink;
  var _begun = false;
  ExportKind? _kind;
  var _records = 0;

  void begin(ExportHeader header) {
    if (_begun) throw StateError('begin was already called');
    _begun = true;
    _sink
      ..write('{\n')
      ..write('  "schema_version": ${jsonEncode(exportSchemaVersion)},\n')
      ..write(
        '  "exported_at": ${jsonEncode(header.exportedAt.toIso8601())},\n',
      )
      ..write('  "range": ')
      ..write(
        jsonEncode({
          'from': header.from.toIso8601(),
          'to': header.to.toIso8601(),
        }),
      )
      ..write(',\n')
      ..write('  "device": ${jsonEncode(header.device?.toJson())}');
  }

  void beginKind(ExportKind kind) {
    if (!_begun) throw StateError('call begin before beginKind');
    if (_kind != null) throw StateError('${_kind!.key} is still open');
    _kind = kind;
    _records = 0;
    _sink.write(',\n  ${jsonEncode(kind.key)}: [');
  }

  void write(ExportRecord record) {
    final kind = _kind;
    if (kind == null) throw StateError('call beginKind before write');
    _sink
      ..write(_records == 0 ? '\n    ' : ',\n    ')
      ..write(jsonEncode(exportRecordJson(kind, record)));
    _records++;
  }

  void endKind() {
    if (_kind == null) throw StateError('no kind is open');
    _sink.write(_records == 0 ? ']' : '\n  ]');
    _kind = null;
  }

  void end() {
    if (!_begun) throw StateError('call begin before end');
    if (_kind != null) throw StateError('${_kind!.key} is still open');
    _sink.write('\n}\n');
  }
}

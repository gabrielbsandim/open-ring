import 'package:open_ring/features/export/domain/export_kind.dart';
import 'package:open_ring/features/export/domain/export_records.dart';
import 'package:open_ring/features/export/domain/export_values.dart';

const csvLineBreak = '\r\n';

final _needsQuotes = RegExp('[",\r\n]');

String csvField(String value) {
  if (!_needsQuotes.hasMatch(value)) return value;
  return '"${value.replaceAll('"', '""')}"';
}

String csvLine(Iterable<String> fields) =>
    '${fields.map(csvField).join(',')}$csvLineBreak';

final class CsvExportWriter {
  new(this.kind, this._sink);

  final ExportKind kind;
  final StringSink _sink;

  void writeHeader() => _sink.write(csvLine(kind.columns));

  void write(ExportRecord record) =>
      _sink.write(csvLine(exportValues(kind, record).map(exportText)));
}

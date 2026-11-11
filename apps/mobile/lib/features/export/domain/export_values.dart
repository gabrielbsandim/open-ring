import 'package:open_ring/features/export/domain/export_kind.dart';
import 'package:open_ring/features/export/domain/export_records.dart';
import 'package:open_ring/features/export/domain/offset_time.dart';

const exportDecimals = 2;
const coordinateDecimals = 7;

List<Object?> exportValues(ExportKind kind, ExportRecord record) {
  final values = record.values;
  if (values.length != kind.columns.length) {
    throw ArgumentError.value(
      record,
      'record',
      'has ${values.length} values, ${kind.key} has ${kind.columns.length} columns',
    );
  }
  return values;
}

String exportText(Object? value) => switch (value) {
  null => '',
  final OffsetTime time => time.toIso8601(),
  final double number => formatDecimal(number),
  final int number => '$number',
  final String text => text,
  _ => throw ArgumentError.value(value, 'value', 'is not exportable'),
};

Object? exportJson(Object? value) => switch (value) {
  final OffsetTime time => time.toIso8601(),
  final double number when !number.isFinite => null,
  final double number => num.parse(formatDecimal(number)),
  _ => value,
};

String formatDecimal(double value, {int digits = exportDecimals}) {
  if (!value.isFinite) return '';
  final fixed = value.toStringAsFixed(digits);
  if (!fixed.contains('.')) return fixed;
  final trimmed = fixed
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
  if (trimmed == '-0') return '0';
  return trimmed;
}

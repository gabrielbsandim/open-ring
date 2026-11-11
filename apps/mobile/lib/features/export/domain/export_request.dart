import 'package:meta/meta.dart';
import 'package:open_ring/features/export/domain/export_kind.dart';

@immutable
final class ExportRequest {
  new({
    required this.from,
    required this.to,
    required Iterable<ExportKind> kinds,
    required this.format,
  }) : kinds = Set.unmodifiable([
         for (final kind in ExportKind.values)
           if (kinds.contains(kind)) kind,
       ]) {
    if (!to.isAfter(from)) {
      throw ArgumentError.value(to, 'to', 'must be after from ($from)');
    }
    if (this.kinds.isEmpty) {
      throw ArgumentError.value(kinds, 'kinds', 'must not be empty');
    }
  }

  final DateTime from;
  final DateTime to;
  final Set<ExportKind> kinds;
  final ExportFormat format;
}

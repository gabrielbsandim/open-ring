import 'package:open_ring/features/export/domain/data_exporter.dart';

final class FileShareException implements Exception {
  const new(this.message);

  final String message;

  @override
  String toString() => 'FileShareException: $message';
}

abstract interface class FileSharer {
  Future<void> share(List<ExportFile> files, {required String subject});
}

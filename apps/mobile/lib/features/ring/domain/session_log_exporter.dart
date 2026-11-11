abstract interface class SessionLogExporter {
  Future<void> export({required String fileName, required String contents});
}

final class SessionLogExportException implements Exception {
  const new(this.message);

  final String message;

  @override
  String toString() => 'SessionLogExportException: $message';
}

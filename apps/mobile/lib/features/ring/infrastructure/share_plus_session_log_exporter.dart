import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:open_ring/features/ring/domain/session_log_exporter.dart';
import 'package:share_plus/share_plus.dart';

final class SharePlusSessionLogExporter implements SessionLogExporter {
  const new();

  @override
  Future<void> export({
    required String fileName,
    required String contents,
  }) async {
    final file = XFile.fromData(
      utf8.encode(contents),
      mimeType: 'text/plain',
      name: fileName,
    );
    try {
      await SharePlus.instance.share(
        ShareParams(
          files: [file],
          fileNameOverrides: [fileName],
          subject: fileName,
        ),
      );
    } on PlatformException catch (error) {
      throw SessionLogExportException(error.message ?? error.code);
    }
  }
}

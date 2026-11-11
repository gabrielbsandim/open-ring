import 'package:flutter/services.dart';
import 'package:open_ring/features/export/domain/data_exporter.dart';
import 'package:open_ring/features/export/domain/file_sharer.dart';
import 'package:share_plus/share_plus.dart';

final class SharePlusFileSharer implements FileSharer {
  const new();

  @override
  Future<void> share(List<ExportFile> files, {required String subject}) async {
    try {
      await SharePlus.instance.share(
        ShareParams(
          files: [
            for (final file in files) XFile(file.path, mimeType: file.mimeType),
          ],
          subject: subject,
        ),
      );
    } on PlatformException catch (error) {
      throw FileShareException(error.message ?? error.code);
    }
  }
}

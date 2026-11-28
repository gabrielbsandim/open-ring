import 'dart:io';

import 'package:file_selector/file_selector.dart';

abstract interface class BackupFilePicker {
  Future<File?> pick();
}

final class FileSelectorBackupPicker implements BackupFilePicker {
  const new();

  // Some file managers report a zip as a generic binary, so both are offered.
  static const _types = XTypeGroup(
    label: 'zip',
    extensions: ['zip'],
    mimeTypes: ['application/zip', 'application/octet-stream'],
  );

  @override
  Future<File?> pick() async {
    final picked = await openFile(acceptedTypeGroups: const [_types]);
    if (picked == null) return null;
    return File(picked.path);
  }
}

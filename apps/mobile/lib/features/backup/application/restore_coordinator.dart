import 'dart:io';

import 'package:open_ring/features/backup/application/backup_archive.dart';
import 'package:open_ring/features/backup/domain/backup_check.dart';

abstract interface class BackgroundWork {
  Future<void> stopAll();
}

abstract interface class AppRestarter {
  Future<void> restart();
}

final class RestoreCoordinator {
  new({
    required this._archive,
    required this._background,
    required this._closeDatabase,
    required this._restarter,
  });

  final BackupArchive _archive;
  final BackgroundWork _background;
  final Future<void> Function() _closeDatabase;
  final AppRestarter _restarter;

  Future<RestoreOutcome> restore(File archive) async {
    final check = await _archive.check(archive);
    if (!check.ok) return Rejected(check);
    await _background.stopAll();
    await _closeDatabase();
    // Once the database is closed the app must reopen it, whatever happened.
    try {
      return await _archive.restore(archive);
    } finally {
      await _restarter.restart();
    }
  }
}

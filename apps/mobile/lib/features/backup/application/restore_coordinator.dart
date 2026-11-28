import 'dart:io';

import 'package:open_ring/features/backup/application/backup_archive.dart';
import 'package:open_ring/features/backup/application/pending_restore.dart';
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
    required this._restarter,
    required this._pending,
  });

  final BackupArchive _archive;
  final BackgroundWork _background;
  final AppRestarter _restarter;
  final PendingRestore _pending;

  // The swap itself runs on the next start, before anything opens the
  // database, so no isolate holds the file that gets replaced.
  Future<RestoreOutcome> restore(File archive) async {
    final check = await _archive.check(archive);
    if (!check.ok) return Rejected(check);
    await _pending.stage(archive);
    await _background.stopAll();
    await _restarter.restart();
    return Restored(check.schemaVersion!);
  }
}

import 'dart:io';

import 'package:open_ring/features/backup/application/backup_archive.dart';
import 'package:open_ring/features/backup/domain/backup_check.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

const _pendingName = 'pending_restore.zip';
const _liveDatabaseName = 'open_ring.sqlite';

final class PendingRestore {
  new(this._documents);

  final Directory _documents;

  File get _pending => File(p.join(_documents.path, _pendingName));

  File get _applying => File('${_pending.path}.applying');

  File get _liveDatabase => File(p.join(_documents.path, _liveDatabaseName));

  bool get hasPending => _pending.existsSync();

  Future<void> discard() => _deleteIfPresent(_pending);

  Future<void> stage(File source) async {
    _documents.createSync(recursive: true);
    final part = File('${_pending.path}.part');
    source.copySync(part.path);
    part.renameSync(_pending.path);
  }

  // The file is moved aside before anything else, so an apply that kills the
  // process is never tried again on the next start.
  Future<RestoreOutcome?> applyIfPending(BackupArchive archive) async {
    await _deleteIfPresent(_applying);
    if (!hasPending) return null;
    await _pending.rename(_applying.path);
    try {
      _settle();
      final outcome = await archive.restore(_applying);
      if (outcome is! Restored) return outcome;
      _releaseLocks();
      await _dropPreRestoreCopies();
      return outcome;
    } on Object {
      return const Rejected(BackupCheck.rejected(BackupProblem.corrupt));
    } finally {
      await _deleteIfPresent(_applying);
    }
  }

  // Opening and closing the live database rolls back a hot journal left by the
  // killed process, so the swap never deletes a journal it still needs.
  void _settle() {
    if (!_liveDatabase.existsSync()) return;
    final db = sqlite3.open(_liveDatabase.path);
    try {
      db.select('PRAGMA schema_version');
    } finally {
      db.close();
    }
  }

  // Locks held by the phone the backup came from would block every sync here.
  void _releaseLocks() {
    final db = sqlite3.open(_liveDatabase.path);
    try {
      final table = db.select(
        "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'sync_locks'",
      );
      if (table.isEmpty) return;
      db.execute('DELETE FROM sync_locks');
    } finally {
      db.close();
    }
  }

  // The replaced data would otherwise outlive every delete action in the app.
  Future<void> _dropPreRestoreCopies() async {
    await _deleteIfPresent(File('${_liveDatabase.path}.pre-restore'));
    final photos = Directory(
      p.join(_documents.path, 'meal_photos.pre-restore'),
    );
    if (photos.existsSync()) await photos.delete(recursive: true);
  }
}

Future<void> _deleteIfPresent(File file) async {
  if (file.existsSync()) await file.delete();
}

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:open_ring/core/database/app_database.dart';
import 'package:open_ring/features/backup/domain/backup_check.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

const backupAppId = 'open_ring';
const backupFormat = 1;

const _databaseName = 'open_ring.sqlite';
const _photosName = 'meal_photos';
const _manifestName = 'manifest.json';
const _preRestore = '.pre-restore';
const _restoring = '.restoring';
const _sidecars = ['-wal', '-shm', '-journal'];
const _sqliteHeader = 'SQLite format 3\u0000';

final class BackupArchive {
  new({
    required this._documents,
    required this._appSchemaVersion,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final Directory _documents;
  final int _appSchemaVersion;
  final DateTime Function() _clock;

  File get _liveDatabase => File(p.join(_documents.path, _databaseName));

  Directory get _livePhotos => Directory(p.join(_documents.path, _photosName));

  Future<File> export(AppDatabase db, Directory outDirectory) async {
    await outDirectory.create(recursive: true);
    final now = _clock().toUtc();
    final target = File(
      p.join(outDirectory.path, 'open-ring-backup-${_stamp(now)}.zip'),
    );
    final copy = File('${target.path}.sqlite');
    final partial = File('${target.path}.part');
    await _deleteFile(copy);
    await _deleteFile(partial);
    try {
      // VACUUM INTO reads through the open connection, so rows still in the
      // WAL are included and the copy needs no sidecar files.
      await db.customStatement('VACUUM INTO ?', [copy.path]);
      final encoder = ZipFileEncoder()
        ..create(partial.path)
        ..addArchiveFile(
          ArchiveFile.bytes(_manifestName, _manifest(db.schemaVersion, now)),
        );
      await encoder.addFile(copy, _databaseName);
      for (final photo in await _photoFiles()) {
        await encoder.addFile(photo, '$_photosName/${p.basename(photo.path)}');
      }
      await encoder.close();
      return await partial.rename(target.path);
    } finally {
      await _deleteFile(copy);
      await _deleteFile(partial);
    }
  }

  Future<BackupCheck> check(File archive) async {
    final inspection = await _inspect(archive);
    await inspection.dispose();
    return inspection.check;
  }

  Future<RestoreOutcome> restore(File archive) async {
    final inspection = await _inspect(archive);
    try {
      final check = inspection.check;
      if (!check.ok) return Rejected(check);
      await _documents.create(recursive: true);
      final stagedDatabase = File('${_liveDatabase.path}$_restoring');
      final stagedPhotos = Directory('${_livePhotos.path}$_restoring');
      await _deleteFile(stagedDatabase);
      await _deleteDirectory(stagedPhotos);
      await inspection.database!.copy(stagedDatabase.path);
      await stagedPhotos.create();
      for (final entry in inspection.photos) {
        _extract(entry, p.join(stagedPhotos.path, _photoName(entry.name)));
      }
      await _retireDatabase();
      await _retirePhotos();
      await stagedDatabase.rename(_liveDatabase.path);
      await stagedPhotos.rename(_livePhotos.path);
      return Restored(check.schemaVersion!);
    } finally {
      await inspection.dispose();
    }
  }

  Future<_Inspection> _inspect(File archive) async {
    final scratch = await Directory.systemTemp.createTemp('open_ring_backup');
    final inspection = _Inspection(scratch);
    final check = await _validate(archive, inspection);
    return inspection..check = check;
  }

  Future<BackupCheck> _validate(File archive, _Inspection inspection) async {
    final zip = _decode(archive, inspection);
    if (zip == null || zip.files.isEmpty) {
      return const BackupCheck.rejected(BackupProblem.notZip);
    }
    final files = zip.files.where((f) => f.isFile).toList();
    if (zip.files.any((f) => !_isSafeName(f.name))) {
      return const BackupCheck.rejected(BackupProblem.unsafePath);
    }
    final manifest = _manifestOf(files);
    if (manifest == null) {
      return const BackupCheck.rejected(BackupProblem.missingManifest);
    }
    final manifestProblem = _manifestProblem(manifest);
    if (manifestProblem != null) return manifestProblem;
    final databaseEntry = files.where((f) => f.name == _databaseName);
    if (databaseEntry.isEmpty) {
      return const BackupCheck.rejected(BackupProblem.notSqlite);
    }
    final database = File(p.join(inspection.scratch.path, _databaseName));
    _extract(databaseEntry.first, database.path);
    inspection
      ..database = database
      ..photos = files.where((f) => _isPhotoEntry(f.name)).toList();
    return _checkDatabase(database);
  }

  Archive? _decode(File archive, _Inspection inspection) {
    try {
      final input = InputFileStream(archive.path);
      inspection.input = input;
      return ZipDecoder().decodeStream(input);
    } on Object {
      return null;
    }
  }

  Map<String, Object?>? _manifestOf(List<ArchiveFile> files) {
    final entries = files.where((f) => f.name == _manifestName);
    if (entries.isEmpty) return null;
    try {
      final decoded = jsonDecode(utf8.decode(entries.first.readBytes()!));
      return decoded is Map<String, Object?> ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  BackupCheck? _manifestProblem(Map<String, Object?> manifest) {
    if (manifest['app'] != backupAppId) {
      return const BackupCheck.rejected(BackupProblem.foreignApp);
    }
    final version = manifest['schemaVersion'];
    if (manifest['format'] != backupFormat || version is! int) {
      return const BackupCheck.rejected(BackupProblem.unsupportedFormat);
    }
    if (version > _appSchemaVersion) {
      return BackupCheck.rejected(
        BackupProblem.newerSchema,
        schemaVersion: version,
      );
    }
    return null;
  }

  BackupCheck _checkDatabase(File database) {
    if (!_hasSqliteHeader(database)) {
      return const BackupCheck.rejected(BackupProblem.notSqlite);
    }
    Database? sqlite;
    try {
      sqlite = sqlite3.open(database.path, mode: OpenMode.readWrite);
      final version = sqlite.select('PRAGMA user_version').first.values.first;
      if (version is! int || version < 1) {
        return const BackupCheck.rejected(BackupProblem.foreignApp);
      }
      if (version > _appSchemaVersion) {
        return BackupCheck.rejected(
          BackupProblem.newerSchema,
          schemaVersion: version,
        );
      }
      final integrity = sqlite.select('PRAGMA integrity_check');
      final healthy =
          integrity.length == 1 && integrity.first.values.first == 'ok';
      if (!healthy) return const BackupCheck.rejected(BackupProblem.corrupt);
      return BackupCheck.ok(version);
    } on SqliteException {
      return const BackupCheck.rejected(BackupProblem.corrupt);
    } finally {
      sqlite?.close();
    }
  }

  Future<void> _retireDatabase() async {
    final retired = File('${_liveDatabase.path}$_preRestore');
    await _deleteFile(retired);
    for (final suffix in _sidecars) {
      await _deleteFile(File('${retired.path}$suffix'));
    }
    if (_liveDatabase.existsSync()) await _liveDatabase.rename(retired.path);
    // The caller closed every connection, which checkpoints the WAL, so any
    // sidecar left is stale and would be replayed into the restored file.
    for (final suffix in _sidecars) {
      await _deleteFile(File('${_liveDatabase.path}$suffix'));
    }
  }

  Future<void> _retirePhotos() async {
    final retired = Directory('${_livePhotos.path}$_preRestore');
    await _deleteDirectory(retired);
    if (_livePhotos.existsSync()) await _livePhotos.rename(retired.path);
  }

  Future<List<File>> _photoFiles() async {
    if (!_livePhotos.existsSync()) return const [];
    final files = await _livePhotos
        .list()
        .where((e) => e is File && !e.path.endsWith('.tmp'))
        .cast<File>()
        .toList();
    return files..sort((a, b) => a.path.compareTo(b.path));
  }

  List<int> _manifest(int schemaVersion, DateTime createdAt) => utf8.encode(
    jsonEncode({
      'app': backupAppId,
      'format': backupFormat,
      'schemaVersion': schemaVersion,
      'createdAtUtc': createdAt.toIso8601String(),
    }),
  );
}

final class _Inspection {
  new(this.scratch);

  final Directory scratch;
  late BackupCheck check;
  InputFileStream? input;
  File? database;
  List<ArchiveFile> photos = const [];

  Future<void> dispose() async {
    await input?.close();
    await _deleteDirectory(scratch);
  }
}

bool _isSafeName(String name) {
  if (name.isEmpty || name.contains(r'\') || p.posix.isAbsolute(name)) {
    return false;
  }
  final segments = name.split('/').where((s) => s.isNotEmpty);
  return segments.every((s) => s != '..' && s != '.');
}

bool _isPhotoEntry(String name) =>
    name.startsWith('$_photosName/') && _photoName(name).isNotEmpty;

String _photoName(String entryName) {
  final rest = entryName.substring(_photosName.length + 1);
  return rest.contains('/') ? '' : rest;
}

void _extract(ArchiveFile entry, String path) {
  final output = OutputFileStream(path);
  try {
    entry.writeContent(output);
  } finally {
    output.closeSync();
  }
}

bool _hasSqliteHeader(File file) {
  final handle = file.openSync();
  try {
    return utf8.decode(handle.readSync(16), allowMalformed: true) ==
        _sqliteHeader;
  } finally {
    handle.closeSync();
  }
}

String _stamp(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}${two(t.month)}${two(t.day)}-'
      '${two(t.hour)}${two(t.minute)}${two(t.second)}';
}

Future<void> _deleteFile(File file) async {
  if (file.existsSync()) await file.delete();
}

Future<void> _deleteDirectory(Directory dir) async {
  if (dir.existsSync()) await dir.delete(recursive: true);
}

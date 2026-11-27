import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:open_ring/core/database/app_database.dart';
import 'package:path/path.dart' as p;

import '../../drift/app/generated/schema_v20.dart' as v20;

const dbName = 'open_ring.sqlite';
const photosName = 'meal_photos';
final fixedInstant = DateTime.utc(2026, 11, 27, 13, 5, 9);

Directory newTempDir(String label) =>
    Directory.systemTemp.createTempSync('backup_$label');

Future<void> cleanUp(Directory dir) async {
  if (dir.existsSync()) await dir.delete(recursive: true);
}

int get currentSchemaVersion {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  return AppDatabase(NativeDatabase.memory()).schemaVersion;
}

AppDatabase openAppDatabase(File file, {bool wal = false}) {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  return AppDatabase(
    NativeDatabase(
      file,
      setup: (raw) {
        if (wal) raw.execute('PRAGMA journal_mode=WAL');
      },
    ),
  );
}

Future<void> insertRing(GeneratedDatabase db, String id) {
  return db.customStatement(
    'INSERT INTO ring_devices (device_id, name, paired_at_utc_ms) '
    "VALUES ('$id', 'Ring $id', 1)",
  );
}

Future<List<String>> ringIds(GeneratedDatabase db) async {
  final rows = await db
      .customSelect('SELECT device_id FROM ring_devices ORDER BY device_id')
      .get();
  return [for (final r in rows) r.read<String>('device_id')];
}

Future<Uint8List> appDatabaseBytes(
  Directory scratch,
  String name, {
  List<String> rings = const [],
  int padRows = 0,
}) async {
  final file = File(p.join(scratch.path, name));
  final db = openAppDatabase(file);
  await db.transaction(() async {
    for (final id in rings) {
      await insertRing(db, id);
    }
    for (var i = 0; i < padRows; i++) {
      await insertRing(db, 'PAD${i.toString().padLeft(5, '0')}${'x' * 200}');
    }
  });
  await db.close();
  return file.readAsBytes();
}

Future<Uint8List> v20DatabaseBytes(
  Directory scratch,
  String name, {
  List<String> rings = const [],
}) async {
  final file = File(p.join(scratch.path, name));
  final db = v20.DatabaseAtV20(NativeDatabase(file));
  for (final id in rings) {
    await insertRing(db, id);
  }
  await db.close();
  return file.readAsBytes();
}

Future<Uint8List> plainSqliteBytes(
  Directory scratch,
  String name, {
  required int userVersion,
}) async {
  final file = File(p.join(scratch.path, name));
  final db = _PlainDb(NativeDatabase(file));
  await db.customStatement('PRAGMA user_version = $userVersion');
  await db.close();
  return file.readAsBytes();
}

class _PlainDb extends GeneratedDatabase {
  _PlainDb(super.e);

  @override
  Iterable<TableInfo<Table, dynamic>> get allTables => const [];

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy();
}

Uint8List manifestBytes({
  String app = 'open_ring',
  Object? format = 1,
  Object? schemaVersion,
  DateTime? createdAt,
}) {
  final map = <String, Object?>{
    'app': app,
    'format': format,
    'schemaVersion': schemaVersion ?? currentSchemaVersion,
    'createdAtUtc': (createdAt ?? fixedInstant).toIso8601String(),
  };
  return Uint8List.fromList(utf8.encode(jsonEncode(map)));
}

File writeZip(Directory dir, String name, Map<String, List<int>> entries) {
  final archive = Archive();
  for (final e in entries.entries) {
    archive.add(ArchiveFile.bytes(e.key, e.value));
  }
  final file = File(p.join(dir.path, name));
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(ZipEncoder().encode(archive));
  return file;
}

Map<String, List<int>> readZip(File zip) {
  final archive = ZipDecoder().decodeBytes(zip.readAsBytesSync());
  return {
    for (final f in archive.files.where((f) => f.isFile))
      f.name: List<int>.from(f.content as List<int>),
  };
}

Future<void> seedDocuments(
  Directory documents, {
  required String ring,
  Map<String, List<int>> photos = const {
    'old.jpg': [9, 9, 9],
  },
  bool staleSidecars = true,
}) async {
  documents.createSync(recursive: true);
  final db = openAppDatabase(File(p.join(documents.path, dbName)));
  await insertRing(db, ring);
  await db.close();
  final photoDir = Directory(p.join(documents.path, photosName))
    ..createSync(recursive: true);
  for (final e in photos.entries) {
    File(p.join(photoDir.path, e.key)).writeAsBytesSync(e.value);
  }
  if (!staleSidecars) return;
  for (final suffix in ['-wal', '-shm', '-journal']) {
    File(p.join(documents.path, '$dbName$suffix')).writeAsBytesSync([7, 7]);
  }
}

Map<String, String> hashTree(Directory root) {
  if (!root.existsSync()) return {};
  return {
    for (final f in root.listSync(recursive: true).whereType<File>())
      p.relative(f.path, from: root.path): sha256
          .convert(f.readAsBytesSync())
          .toString(),
  };
}

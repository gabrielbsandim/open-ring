import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/backup/application/backup_archive.dart';
import 'package:open_ring/features/backup/domain/backup_check.dart';
import 'package:path/path.dart' as p;

import 'backup_fixtures.dart';

void main() {
  late Directory root;
  late Directory source;
  late Directory target;
  late Directory out;

  setUp(() {
    root = newTempDir('export');
    source = Directory(p.join(root.path, 'source'))..createSync();
    target = Directory(p.join(root.path, 'target'))..createSync();
    out = Directory(p.join(root.path, 'out'))..createSync();
  });
  tearDown(() => cleanUp(root));

  BackupArchive archiveOf(Directory documents) => BackupArchive(
    documents: documents,
    appSchemaVersion: currentSchemaVersion,
    clock: () => fixedInstant,
  );

  test(
    'criterion 1: export then restore brings rows and photos back',
    () async {
      final db = openAppDatabase(File(p.join(source.path, dbName)));
      await insertRing(db, 'R1');
      await insertRing(db, 'R2');
      final photos = Directory(p.join(source.path, photosName))..createSync();
      File(p.join(photos.path, 'a.jpg')).writeAsBytesSync([1, 2, 3]);
      File(p.join(photos.path, 'b.jpg')).writeAsBytesSync([4, 5, 6, 7]);

      final zip = await archiveOf(source).export(db, out);
      await db.close();
      final outcome = await archiveOf(target).restore(zip);

      expect(outcome, isA<Restored>());
      expect((outcome as Restored).fromSchemaVersion, currentSchemaVersion);
      final restored = openAppDatabase(File(p.join(target.path, dbName)));
      addTearDown(restored.close);
      expect(await ringIds(restored), ['R1', 'R2']);
      final restoredPhotos = p.join(target.path, photosName);
      expect(File(p.join(restoredPhotos, 'a.jpg')).readAsBytesSync(), [
        1,
        2,
        3,
      ]);
      expect(File(p.join(restoredPhotos, 'b.jpg')).readAsBytesSync(), [
        4,
        5,
        6,
        7,
      ]);
    },
  );

  test('criterion 1: the file name is stamped from the UTC clock', () async {
    final db = openAppDatabase(File(p.join(source.path, dbName)));
    addTearDown(db.close);

    final zip = await archiveOf(source).export(db, out);

    expect(p.basename(zip.path), 'open-ring-backup-20261127-130509.zip');
    expect(p.dirname(zip.path), out.path);
  });

  test('criterion 1: the manifest names the app, format and schema', () async {
    final db = openAppDatabase(File(p.join(source.path, dbName)));
    addTearDown(db.close);

    final zip = await archiveOf(source).export(db, out);

    final manifest = jsonDecode(
      utf8.decode(readZip(zip)['manifest.json']!),
    ) as Map<String, dynamic>;
    expect(manifest['app'], 'open_ring');
    expect(manifest['format'], 1);
    expect(manifest['schemaVersion'], db.schemaVersion);
    expect(
      DateTime.parse(manifest['createdAtUtc'] as String).toUtc(),
      fixedInstant,
    );
  });

  test('criterion 1: a zero-photo install exports and restores', () async {
    final db = openAppDatabase(File(p.join(source.path, dbName)));
    await insertRing(db, 'R1');

    final zip = await archiveOf(source).export(db, out);
    await db.close();
    final outcome = await archiveOf(target).restore(zip);

    expect(outcome, isA<Restored>());
    expect(readZip(zip).keys, containsAll(['manifest.json', dbName]));
  });

  test('criterion 2: rows still in the WAL are exported', () async {
    final db = openAppDatabase(File(p.join(source.path, dbName)), wal: true);
    addTearDown(db.close);
    await insertRing(db, 'IN_WAL');
    final wal = File(p.join(source.path, '$dbName-wal'));
    expect(wal.existsSync() && wal.lengthSync() > 0, isTrue);

    final zip = await archiveOf(source).export(db, out);
    await archiveOf(target).restore(zip);

    final restored = openAppDatabase(File(p.join(target.path, dbName)));
    addTearDown(restored.close);
    expect(await ringIds(restored), ['IN_WAL']);
  });

  test('criterion 2: the exported database is a single file', () async {
    final db = openAppDatabase(File(p.join(source.path, dbName)), wal: true);
    addTearDown(db.close);
    await insertRing(db, 'IN_WAL');

    final zip = await archiveOf(source).export(db, out);

    final names = readZip(zip).keys;
    expect(
      names.where((n) => n.contains('-wal') || n.contains('-shm')),
      isEmpty,
    );
  });

  test(
    'criterion 7: only manifest, database and photos are archived',
    () async {
      final db = openAppDatabase(File(p.join(source.path, dbName)));
      await insertRing(db, 'R1');
      Directory(p.join(source.path, photosName)).createSync();
      File(p.join(source.path, photosName, 'a.jpg')).writeAsBytesSync([1]);
      File(p.join(source.path, 'FlutterSharedPreferences.xml'))
          .writeAsStringSync('<string name="token">SECRET</string>');
      Directory(p.join(source.path, 'shared_prefs')).createSync();
      File(p.join(source.path, 'shared_prefs', 'prefs.xml'))
          .writeAsStringSync('SECRET');
      File(p.join(source.path, '$dbName.pre-restore')).writeAsBytesSync([5]);

      final zip = await archiveOf(source).export(db, out);
      await db.close();

      expect(readZip(zip).keys.toSet(), {
        'manifest.json',
        dbName,
        '$photosName/a.jpg',
      });
      expect(
        utf8.decode(zip.readAsBytesSync(), allowMalformed: true),
        isNot(contains('SECRET')),
      );
    },
  );
}

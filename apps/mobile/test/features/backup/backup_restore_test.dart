import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/backup/application/backup_archive.dart';
import 'package:open_ring/features/backup/domain/backup_check.dart';
import 'package:path/path.dart' as p;

import 'backup_fixtures.dart';

void main() {
  late Directory root;
  late Directory documents;
  late Directory scratch;
  late int appVersion;

  setUp(() {
    root = newTempDir('restore');
    documents = Directory(p.join(root.path, 'documents'));
    scratch = Directory(p.join(root.path, 'scratch'))..createSync();
    appVersion = currentSchemaVersion;
  });
  tearDown(() => cleanUp(root));

  BackupArchive archiveOf() =>
      BackupArchive(documents: documents, appSchemaVersion: appVersion);

  Future<File> zipOf(
    String name,
    List<int> database, {
    Map<String, List<int>> photos = const {},
    int? schemaVersion,
  }) async {
    return writeZip(scratch, 'in/$name.zip', {
      'manifest.json': manifestBytes(schemaVersion: schemaVersion),
      dbName: database,
      for (final e in photos.entries) '$photosName/${e.key}': e.value,
    });
  }

  String live(String name) => p.join(documents.path, name);

  Future<List<String>> liveRings() async {
    final db = openAppDatabase(File(live(dbName)));
    final ids = await ringIds(db);
    await db.close();
    return ids;
  }

  test('criterion 4: an older schema restores and migrates on open', () async {
    final older = appVersion - 1;
    final bytes = await v20DatabaseBytes(scratch, 'v20.db', rings: ['OLD']);
    final zip = await zipOf('older', bytes, schemaVersion: older);
    await seedDocuments(documents, ring: 'KEEP');

    final check = await archiveOf().check(zip);
    final outcome = await archiveOf().restore(zip);

    expect(check.ok, isTrue);
    expect(check.schemaVersion, older);
    expect(outcome, isA<Restored>());
    expect((outcome as Restored).fromSchemaVersion, older);
    final db = openAppDatabase(File(live(dbName)));
    addTearDown(db.close);
    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.read<int>('user_version'), db.schemaVersion);
    expect(db.schemaVersion, appVersion);
    expect(await ringIds(db), ['OLD']);
  });

  test('criterion 5: the previous database is kept as pre-restore', () async {
    await seedDocuments(documents, ring: 'OLD');
    final oldBytes = File(live(dbName)).readAsBytesSync();
    final bytes = await appDatabaseBytes(scratch, 'new.db', rings: ['NEW']);
    final zip = await zipOf('new', bytes);

    final outcome = await archiveOf().restore(zip);

    expect(outcome, isA<Restored>());
    expect(File(live('$dbName.pre-restore')).readAsBytesSync(), oldBytes);
    expect(await liveRings(), ['NEW']);
  });

  test(
    'criterion 5: the previous photos are kept, new photos replace them',
    () async {
      await seedDocuments(
        documents,
        ring: 'OLD',
        photos: {
          'old.jpg': [9, 9, 9],
        },
      );
      final bytes = await appDatabaseBytes(scratch, 'new.db', rings: ['NEW']);
      final zip = await zipOf(
        'new',
        bytes,
        photos: {
          'new.jpg': [1, 2],
        },
      );

      await archiveOf().restore(zip);

      final photos = Directory(live(photosName));
      expect(photos.listSync().map((e) => p.basename(e.path)), ['new.jpg']);
      final kept = File(live('$photosName.pre-restore/old.jpg'));
      expect(kept.readAsBytesSync(), [9, 9, 9]);
    },
  );

  test('criterion 5: stale wal, shm and journal files are deleted', () async {
    await seedDocuments(documents, ring: 'OLD');
    final bytes = await appDatabaseBytes(scratch, 'new.db', rings: ['NEW']);
    final zip = await zipOf('new', bytes);

    await archiveOf().restore(zip);

    for (final suffix in ['-wal', '-shm', '-journal']) {
      expect(
        File(live('$dbName$suffix')).existsSync(),
        isFalse,
        reason: suffix,
      );
    }
    expect(await liveRings(), ['NEW']);
  });

  test(
    'criterion 5: a second restore replaces the earlier pre-restore copies',
    () async {
      await seedDocuments(documents, ring: 'FIRST');
      final first = await zipOf(
        'one',
        await appDatabaseBytes(scratch, 'one.db', rings: ['SECOND']),
        photos: {
          'two.jpg': [2],
        },
      );
      final second = await zipOf(
        'two',
        await appDatabaseBytes(scratch, 'two.db', rings: ['THIRD']),
        photos: {
          'three.jpg': [3],
        },
      );
      await archiveOf().restore(first);
      final afterFirst = File(live(dbName)).readAsBytesSync();

      await archiveOf().restore(second);

      expect(File(live('$dbName.pre-restore')).readAsBytesSync(), afterFirst);
      final keptPhotos = Directory(live('$photosName.pre-restore'))
          .listSync()
          .map((e) => p.basename(e.path));
      expect(keptPhotos, ['two.jpg']);
      expect(await liveRings(), ['THIRD']);
    },
  );

  test('criterion 5: no staging file is left behind', () async {
    await seedDocuments(documents, ring: 'OLD');
    final bytes = await appDatabaseBytes(scratch, 'new.db', rings: ['NEW']);
    final zip = await zipOf('new', bytes);

    await archiveOf().restore(zip);

    final names = documents.listSync().map((e) => p.basename(e.path)).toSet();
    expect(names, {
      dbName,
      '$dbName.pre-restore',
      photosName,
      '$photosName.pre-restore',
    });
  });

  test(
    'criterion 5: restoring into a fresh install keeps nothing to undo',
    () async {
      documents.createSync();
      final bytes = await appDatabaseBytes(scratch, 'new.db', rings: ['NEW']);
      final zip = await zipOf(
        'new',
        bytes,
        photos: {
          'n.jpg': [1],
        },
      );

      final outcome = await archiveOf().restore(zip);

      expect(outcome, isA<Restored>());
      expect(await liveRings(), ['NEW']);
      expect(File(live('$photosName/n.jpg')).readAsBytesSync(), [1]);
    },
  );
}

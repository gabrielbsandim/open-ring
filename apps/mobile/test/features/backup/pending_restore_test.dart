import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/backup/application/backup_archive.dart';
import 'package:open_ring/features/backup/application/pending_restore.dart';
import 'package:open_ring/features/backup/domain/backup_check.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'backup_fixtures.dart';

void main() {
  late Directory root;
  late Directory documents;
  late Directory scratch;

  setUp(() async {
    root = newTempDir('pending');
    documents = Directory(p.join(root.path, 'documents'));
    scratch = Directory(p.join(root.path, 'scratch'))..createSync();
    await seedDocuments(documents, ring: 'OLD');
  });
  tearDown(() => cleanUp(root));

  BackupArchive archiveOf(Directory dir) =>
      BackupArchive(documents: dir, appSchemaVersion: currentSchemaVersion);

  File pendingFile(Directory dir) =>
      File(p.join(dir.path, 'pending_restore.zip'));

  File applyingFile(Directory dir) =>
      File(p.join(dir.path, 'pending_restore.zip.applying'));

  File partFile(Directory dir) =>
      File(p.join(dir.path, 'pending_restore.zip.part'));

  File liveDb(Directory dir) => File(p.join(dir.path, dbName));

  File oldPhoto() => File(p.join(documents.path, photosName, 'old.jpg'));

  Future<List<String>> liveRings(Directory dir) async {
    final db = openAppDatabase(liveDb(dir));
    try {
      return await ringIds(db);
    } finally {
      await db.close();
    }
  }

  Future<int> liveLockCount(Directory dir) async {
    final db = openAppDatabase(liveDb(dir));
    try {
      final rows = await db
          .customSelect('SELECT COUNT(*) AS n FROM sync_locks')
          .get();
      return rows.single.read<int>('n');
    } finally {
      await db.close();
    }
  }

  Future<File> validZip({
    Map<String, List<int>> photos = const {},
    Uint8List? database,
  }) async {
    final db =
        database ?? await appDatabaseBytes(scratch, 'new.db', rings: ['NEW']);
    return writeZip(scratch, 'in/ok.zip', {
      'manifest.json': manifestBytes(),
      dbName: db,
      for (final e in photos.entries) '$photosName/${e.key}': e.value,
    });
  }

  BackupArchive brokenArchive() {
    final notADirectory = File(p.join(root.path, 'file'))
      ..writeAsBytesSync([1]);
    return archiveOf(Directory(notADirectory.path));
  }

  test('criterion 4: stage copies the zip to pending_restore.zip', () async {
    final zip = await validZip();
    final pending = PendingRestore(documents);
    final before = liveDb(documents).readAsBytesSync();
    expect(pending.hasPending, isFalse);

    await pending.stage(zip);

    expect(pending.hasPending, isTrue);
    expect(pendingFile(documents).readAsBytesSync(), zip.readAsBytesSync());
    expect(partFile(documents).existsSync(), isFalse);
    expect(liveDb(documents).readAsBytesSync(), before);
  });

  test(
    'criterion 4: nothing pending returns null and changes nothing',
    () async {
      final before = hashTree(documents);

      final outcome = await PendingRestore(documents)
          .applyIfPending(archiveOf(documents));

      expect(outcome, isNull);
      expect(hashTree(documents), before);
    },
  );

  test(
    'criterion 4: a pending zip swaps the database and the photos',
    () async {
      final zip = await validZip(
        photos: {
          'new.jpg': [4, 5, 6],
        },
      );
      final pending = PendingRestore(documents);
      await pending.stage(zip);

      final outcome = await pending.applyIfPending(archiveOf(documents));

      expect(outcome, isA<Restored>());
      expect(await liveRings(documents), ['NEW']);
      final photos = p.join(documents.path, photosName);
      expect(File(p.join(photos, 'new.jpg')).readAsBytesSync(), [4, 5, 6]);
      expect(oldPhoto().existsSync(), isFalse);
    },
  );

  test(
    'criterion 4: the pending file is gone after a successful apply',
    () async {
      final pending = PendingRestore(documents);
      await pending.stage(await validZip());

      await pending.applyIfPending(archiveOf(documents));

      expect(pending.hasPending, isFalse);
      expect(pendingFile(documents).existsSync(), isFalse);
      expect(applyingFile(documents).existsSync(), isFalse);
      expect(partFile(documents).existsSync(), isFalse);
    },
  );

  test(
    'criterion 4: a rejected pending zip is deleted and live data stays',
    () async {
      final bad = File(p.join(scratch.path, 'bad.zip'))
        ..writeAsBytesSync(List.filled(64, 3));
      final pending = PendingRestore(documents);
      await pending.stage(bad);

      final outcome = await pending.applyIfPending(archiveOf(documents));

      expect(outcome, isA<Rejected>());
      expect(pending.hasPending, isFalse);
      expect(applyingFile(documents).existsSync(), isFalse);
      expect(await liveRings(documents), ['OLD']);
      expect(oldPhoto().readAsBytesSync(), [9, 9, 9]);
    },
  );

  test('criterion 4: a throwing apply returns Rejected corrupt, deletes the pending file, keeps live data', () async {
    final pending = PendingRestore(documents);
    await pending.stage(await validZip());

    final outcome = await pending.applyIfPending(brokenArchive());

    expect(outcome, isA<Rejected>());
    expect((outcome as Rejected).check.problem, BackupProblem.corrupt);
    expect(pending.hasPending, isFalse);
    expect(pendingFile(documents).existsSync(), isFalse);
    expect(applyingFile(documents).existsSync(), isFalse);
    expect(await liveRings(documents), ['OLD']);
    expect(oldPhoto().readAsBytesSync(), [9, 9, 9]);
  });

  test(
    'criterion 4: after a failed apply the next start applies nothing',
    () async {
      final pending = PendingRestore(documents);
      await pending.stage(await validZip());
      await pending.applyIfPending(brokenArchive());

      final again = await pending.applyIfPending(archiveOf(documents));

      expect(again, isNull);
      expect(await liveRings(documents), ['OLD']);
    },
  );

  test('criterion 6: sync_locks is empty after the apply', () async {
    final file = File(p.join(scratch.path, 'locked.db'));
    final seeded = openAppDatabase(file);
    await insertRing(seeded, 'NEW');
    await seeded.customStatement(
      'INSERT INTO sync_locks (name, owner, acquired_at_utc_ms, '
      "expires_at_utc_ms) VALUES ('sync', 'old-phone', 1, 2)",
    );
    await seeded.close();
    final pending = PendingRestore(documents);
    await pending.stage(await validZip(database: file.readAsBytesSync()));

    final outcome = await pending.applyIfPending(archiveOf(documents));

    expect(outcome, isA<Restored>());
    expect(await liveLockCount(documents), 0);
    expect(await liveRings(documents), ['NEW']);
  });

  test(
    'review focus 2: a WAL left by a killed process does not break the apply',
    () async {
      final killed = Directory(p.join(root.path, 'killed'));
      await seedDocuments(killed, ring: 'OLD', staleSidecars: false);
      final raw = sqlite3.open(liveDb(killed).path);
      raw.execute('PRAGMA journal_mode=WAL');
      raw.execute('PRAGMA wal_autocheckpoint=0');
      raw.execute(
        'INSERT INTO ring_devices (device_id, name, paired_at_utc_ms) '
        "VALUES ('WALROW', 'Ring WALROW', 1)",
      );
      final copy = Directory(p.join(root.path, 'copy'))..createSync();
      for (final suffix in ['', '-wal']) {
        File('${liveDb(killed).path}$suffix')
            .copySync(p.join(copy.path, '$dbName$suffix'));
      }
      raw.dispose();
      final pending = PendingRestore(copy);
      await pending.stage(await validZip());

      final outcome = await pending.applyIfPending(archiveOf(copy));

      expect(outcome, isA<Restored>());
      expect(await liveRings(copy), ['NEW']);
      expect(pending.hasPending, isFalse);
    },
  );
}

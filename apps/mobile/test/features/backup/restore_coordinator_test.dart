import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/backup/application/backup_archive.dart';
import 'package:open_ring/features/backup/application/restore_coordinator.dart';
import 'package:open_ring/features/backup/domain/backup_check.dart';
import 'package:path/path.dart' as p;

import 'backup_fixtures.dart';

class _Background implements BackgroundWork {
  new(this.log);

  final List<String> log;

  @override
  Future<void> stopAll() async => log.add('stop');
}

class _Restarter implements AppRestarter {
  new(this.log, [this.onRestart]);

  final List<String> log;
  final void Function()? onRestart;

  @override
  Future<void> restart() async {
    log.add('restart');
    onRestart?.call();
  }
}

void main() {
  late Directory root;
  late Directory documents;
  late Directory scratch;
  late List<String> log;
  late List<int> archivedDatabase;

  setUp(() async {
    root = newTempDir('coordinator');
    documents = Directory(p.join(root.path, 'documents'));
    scratch = Directory(p.join(root.path, 'scratch'))..createSync();
    log = [];
    await seedDocuments(documents, ring: 'OLD');
    archivedDatabase = await appDatabaseBytes(
      scratch,
      'new.db',
      rings: ['NEW'],
    );
  });
  tearDown(() => cleanUp(root));

  BackupArchive archiveOf(Directory dir) =>
      BackupArchive(documents: dir, appSchemaVersion: currentSchemaVersion);

  File validZip() => writeZip(scratch, 'in/ok.zip', {
    'manifest.json': manifestBytes(),
    dbName: archivedDatabase,
  });

  File liveDb() => File(p.join(documents.path, dbName));

  test('criterion 6: stop, close, restore, restart in that order', () async {
    final before = hashTree(documents);
    Map<String, String>? atStop;
    Map<String, String>? atClose;
    List<int>? atRestart;
    final coordinator = RestoreCoordinator(
      archive: archiveOf(documents),
      background: _CapturingBackground(log, () => atStop = hashTree(documents)),
      closeDatabase: () async {
        log.add('close');
        atClose = hashTree(documents);
      },
      restarter: _Restarter(log, () => atRestart = liveDb().readAsBytesSync()),
    );

    final outcome = await coordinator.restore(validZip());

    expect(outcome, isA<Restored>());
    expect(log, ['stop', 'close', 'restart']);
    expect(atStop, before);
    expect(atClose, before);
    expect(atRestart, archivedDatabase);
  });

  test('criterion 6: a rejected archive touches nothing', () async {
    final bad = File(p.join(scratch.path, 'bad.zip'))
      ..writeAsBytesSync(List.filled(64, 3));
    final before = hashTree(documents);
    final coordinator = RestoreCoordinator(
      archive: archiveOf(documents),
      background: _Background(log),
      closeDatabase: () async => log.add('close'),
      restarter: _Restarter(log),
    );

    final outcome = await coordinator.restore(bad);

    expect(outcome, isA<Rejected>());
    expect((outcome as Rejected).check.problem, BackupProblem.notZip);
    expect(log, isEmpty);
    expect(hashTree(documents), before);
  });

  test('criterion 6: a failing restore still restarts and rethrows', () async {
    final notADirectory = File(p.join(root.path, 'not-a-directory'))
      ..writeAsBytesSync([1]);
    final coordinator = RestoreCoordinator(
      archive: archiveOf(Directory(notADirectory.path)),
      background: _Background(log),
      closeDatabase: () async => log.add('close'),
      restarter: _Restarter(log),
    );

    await expectLater(
      coordinator.restore(validZip()),
      throwsA(isA<Exception>()),
    );

    expect(log, ['stop', 'close', 'restart']);
  });

  test(
    'criterion 6: an error in closing the database is not swallowed',
    () async {
      final coordinator = RestoreCoordinator(
        archive: archiveOf(documents),
        background: _Background(log),
        closeDatabase: () async => throw StateError('close failed'),
        restarter: _Restarter(log),
      );
      final before = hashTree(documents);

      await expectLater(
        coordinator.restore(validZip()),
        throwsA(isA<StateError>()),
      );

      expect(hashTree(documents), before);
    },
  );
}

class _CapturingBackground implements BackgroundWork {
  new(this.log, this.onStop);

  final List<String> log;
  final void Function() onStop;

  @override
  Future<void> stopAll() async {
    log.add('stop');
    onStop();
  }
}

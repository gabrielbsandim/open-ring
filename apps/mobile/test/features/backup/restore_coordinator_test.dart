import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/backup/application/backup_archive.dart';
import 'package:open_ring/features/backup/application/pending_restore.dart';
import 'package:open_ring/features/backup/application/restore_coordinator.dart';
import 'package:open_ring/features/backup/domain/backup_check.dart';
import 'package:path/path.dart' as p;

import 'backup_fixtures.dart';

class _Background implements BackgroundWork {
  new(this.log, [this.onStop]);

  final List<String> log;
  final void Function()? onStop;

  @override
  Future<void> stopAll() async {
    log.add('stop');
    onStop?.call();
  }
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

  File pendingFile() => File(p.join(documents.path, 'pending_restore.zip'));

  RestoreCoordinator coordinatorOf({
    BackgroundWork? background,
    AppRestarter? restarter,
    Directory? pendingDir,
  }) => RestoreCoordinator(
    archive: archiveOf(documents),
    background: background ?? _Background(log),
    restarter: restarter ?? _Restarter(log),
    pending: PendingRestore(pendingDir ?? documents),
  );

  test(
    'criterion 3: stage, then stopAll, then restart, in that order',
    () async {
      final liveBefore = liveDb().readAsBytesSync();
      final zip = validZip();
      final stagedAtStop = <bool>[];
      final atRestart = <bool>[];
      final coordinator = coordinatorOf(
        background: _Background(log, () {
          stagedAtStop.add(pendingFile().existsSync());
        }),
        restarter: _Restarter(log, () {
          atRestart
            ..add(pendingFile().existsSync())
            ..add(log.contains('stop'));
        }),
      );

      final outcome = await coordinator.restore(zip);

      expect(outcome, isA<Restored>());
      expect(log, ['stop', 'restart']);
      expect(stagedAtStop, [true]);
      expect(atRestart, [true, true]);
      expect(pendingFile().readAsBytesSync(), zip.readAsBytesSync());
      expect(liveDb().readAsBytesSync(), liveBefore);
    },
  );

  test('criterion 3: a valid restore reports the archive schema', () async {
    final outcome = await coordinatorOf().restore(validZip());

    expect((outcome as Restored).fromSchemaVersion, currentSchemaVersion);
  });

  test('criterion 2: a rejected archive stages and calls nothing', () async {
    final bad = File(p.join(scratch.path, 'bad.zip'))
      ..writeAsBytesSync(List.filled(64, 3));
    final before = hashTree(documents);

    final outcome = await coordinatorOf().restore(bad);

    expect(outcome, isA<Rejected>());
    expect((outcome as Rejected).check.problem, BackupProblem.notZip);
    expect(log, isEmpty);
    expect(pendingFile().existsSync(), isFalse);
    expect(hashTree(documents), before);
  });

  test('criterion 3: a failing stage stops and restarts nothing', () async {
    final notADirectory = Directory(p.join(root.path, 'not-a-directory'));
    File(notADirectory.path).writeAsBytesSync([1]);
    final coordinator = coordinatorOf(pendingDir: notADirectory);

    await expectLater(
      coordinator.restore(validZip()),
      throwsA(isA<Exception>()),
    );

    expect(log, isEmpty);
  });
}

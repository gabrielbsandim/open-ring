import 'dart:convert';
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

  setUp(() async {
    root = newTempDir('manifest_cap');
    documents = Directory(p.join(root.path, 'documents'));
    scratch = Directory(p.join(root.path, 'scratch'))..createSync();
    await seedDocuments(documents, ring: 'OLD');
  });
  tearDown(() => cleanUp(root));

  test('an oversized manifest is rejected before it is inflated', () async {
    final padded = '${utf8.decode(manifestBytes())}${' ' * (1024 * 1024)}';
    final zip = writeZip(scratch, 'in/bomb.zip', {
      'manifest.json': utf8.encode(padded),
      dbName: await appDatabaseBytes(scratch, 'good.db'),
    });
    final before = hashTree(documents);
    final archive = BackupArchive(
      documents: documents,
      appSchemaVersion: currentSchemaVersion,
    );

    final check = await archive.check(zip);
    final outcome = await archive.restore(zip);

    expect(check.problem, BackupProblem.missingManifest);
    expect(outcome, isA<Rejected>());
    expect(hashTree(documents), before);
  });
}

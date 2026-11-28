import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/backup/application/backup_archive.dart';
import 'package:open_ring/features/backup/domain/backup_check.dart';
import 'package:path/path.dart' as p;

import 'backup_fixtures.dart';

typedef _Build = Future<File> Function(Directory scratch);

class _Case {
  const new(this.name, this.problem, this.build);

  final String name;
  final BackupProblem problem;
  final _Build build;
}

Future<File> _zipWith(
  Directory scratch, {
  Uint8List? manifest,
  Uint8List? database,
  Map<String, List<int>> extra = const {},
}) async {
  final db = database ?? await appDatabaseBytes(scratch, 'good.db');
  return writeZip(scratch, 'in/backup.zip', {
    'manifest.json': manifest ?? manifestBytes(),
    dbName: db,
    ...extra,
  });
}

Future<Uint8List> _bigDatabase(Directory scratch) =>
    appDatabaseBytes(scratch, 'big.db', rings: ['R1'], padRows: 1500);

void main() {
  late Directory root;
  late Directory documents;
  late int appVersion;

  setUp(() async {
    root = newTempDir('reject');
    documents = Directory(p.join(root.path, 'documents'));
    await seedDocuments(documents, ring: 'KEEP');
    appVersion = currentSchemaVersion;
  });
  tearDown(() => cleanUp(root));

  BackupArchive archiveOf() =>
      BackupArchive(documents: documents, appSchemaVersion: appVersion);

  final cases = <_Case>[
    _Case('random bytes are not a zip', BackupProblem.notZip, (s) async {
      final bytes = Uint8List.fromList(
        List.generate(2048, (_) => Random(7).nextInt(256)),
      );
      final file = File(p.join(s.path, 'in/random.zip'))
        ..parent.createSync(recursive: true)
        ..writeAsBytesSync(bytes);
      return file;
    }),
    _Case('a zip without manifest', BackupProblem.missingManifest, (s) async {
      final db = await appDatabaseBytes(s, 'good.db');
      return writeZip(s, 'in/backup.zip', {dbName: db});
    }),
    _Case('manifest of another app', BackupProblem.foreignApp, (s) async {
      return await _zipWith(s, manifest: manifestBytes(app: 'other'));
    }),
    _Case('manifest format 2', BackupProblem.unsupportedFormat, (s) async {
      return await _zipWith(s, manifest: manifestBytes(format: 2));
    }),
    _Case('manifest newer than the app', BackupProblem.newerSchema, (s) async {
      return await _zipWith(s, manifest: manifestBytes(schemaVersion: 9999));
    }),
    _Case(
      'database user_version newer than the app',
      BackupProblem.newerSchema,
      (s) async {
        final db = await plainSqliteBytes(s, 'newer.db', userVersion: 9999);
        return await _zipWith(s, database: db);
      },
    ),
    _Case('database entry is not SQLite', BackupProblem.notSqlite, (s) async {
      final db = Uint8List.fromList('definitely not a database'.codeUnits);
      return await _zipWith(s, database: db);
    }),
    _Case('truncated SQLite file', BackupProblem.corrupt, (s) async {
      final full = await _bigDatabase(s);
      final cut = (full.length ~/ 8192) * 4096;
      return await _zipWith(s, database: full.sublist(0, cut));
    }),
    _Case('SQLite file with a damaged page', BackupProblem.corrupt, (s) async {
      final bytes = Uint8List.fromList(await _bigDatabase(s));
      final start = (bytes.length ~/ 8192) * 4096;
      bytes.fillRange(start, start + 4096, 0xAB);
      return await _zipWith(s, database: bytes);
    }),
    _Case('entry name with ../', BackupProblem.unsafePath, (s) async {
      return await _zipWith(
        s,
        extra: {
          '../evil.txt': [1],
        },
      );
    }),
    _Case('photo entry escaping the photos dir', BackupProblem.unsafePath, (
      s,
    ) async {
      return await _zipWith(
        s,
        extra: {
          'meal_photos/../../evil.jpg': [1],
        },
      );
    }),
    _Case('absolute entry name', BackupProblem.unsafePath, (s) async {
      return await _zipWith(
        s,
        extra: {
          '/tmp/evil.txt': [1],
        },
      );
    }),
  ];

  for (final c in cases) {
    test('criterion 3: check rejects ${c.name} as ${c.problem.name}', () async {
      final scratch = Directory(p.join(root.path, 'scratch'))..createSync();
      final zip = await c.build(scratch);
      final before = hashTree(documents);

      final check = await archiveOf().check(zip);

      expect(check.ok, isFalse);
      expect(check.problem, c.problem);
      expect(hashTree(documents), before);
    });

    test(
      'criterion 3: restore of ${c.name} leaves documents byte-identical',
      () async {
        final scratch = Directory(p.join(root.path, 'scratch'))..createSync();
        final zip = await c.build(scratch);
        final before = hashTree(documents);

        final outcome = await archiveOf().restore(zip);

        expect(outcome, isA<Rejected>());
        expect((outcome as Rejected).check.problem, c.problem);
        expect(hashTree(documents), before);
        expect(File(p.join(root.path, 'evil.txt')).existsSync(), isFalse);
        expect(File(p.join(root.path, 'evil.jpg')).existsSync(), isFalse);
      },
    );
  }

  test('criterion 3: a newer manifest reports the schema it saw', () async {
    final scratch = Directory(p.join(root.path, 'scratch'))..createSync();
    final zip = await _zipWith(
      scratch,
      manifest: manifestBytes(schemaVersion: appVersion + 1),
    );

    final check = await archiveOf().check(zip);

    expect(check.problem, BackupProblem.newerSchema);
    expect(check.schemaVersion, appVersion + 1);
  });

  test('criterion 3: a valid archive is accepted without a change', () async {
    final scratch = Directory(p.join(root.path, 'scratch'))..createSync();
    final zip = await _zipWith(scratch);
    final before = hashTree(documents);

    final check = await archiveOf().check(zip);

    expect(check.ok, isTrue);
    expect(check.problem, isNull);
    expect(check.schemaVersion, appVersion);
    expect(hashTree(documents), before);
  });
}

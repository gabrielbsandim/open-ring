import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/core/database/app_database_provider.dart';
import 'package:open_ring/features/backup/application/backup_archive.dart';
import 'package:open_ring/features/backup/application/backup_providers.dart';
import 'package:open_ring/features/backup/application/pending_restore.dart';
import 'package:open_ring/features/backup/application/restore_coordinator.dart';
import 'package:open_ring/features/backup/presentation/backup_file_picker.dart';
import 'package:open_ring/features/backup/presentation/backup_tiles.dart';
import 'package:open_ring/features/export/domain/data_exporter.dart';
import 'package:open_ring/features/settings/presentation/settings_screen.dart';
import 'package:open_ring/features/workout/application/workout_controller.dart';
import 'package:open_ring/features/workout/application/workout_state.dart';
import 'package:open_ring/features/workout/domain/workout_session.dart';
import 'package:open_ring/features/workout/domain/workout_type.dart';
import 'package:path/path.dart' as p;

import '../../../helpers/ble_fakes.dart';
import '../../../helpers/layout_harness.dart';
import '../../../helpers/ring_fakes.dart';
import '../../../helpers/settings_fakes.dart';
import '../backup_fixtures.dart';

class _Picker implements BackupFilePicker {
  new(this.file);

  final File? file;
  int calls = 0;

  @override
  Future<File?> pick() async {
    calls++;
    return file;
  }
}

class _Background implements BackgroundWork {
  new(this.log);

  final List<String> log;

  @override
  Future<void> stopAll() async => log.add('stop');
}

class _Restarter implements AppRestarter {
  new(this.log);

  final List<String> log;

  @override
  Future<void> restart() async => log.add('restart');
}

class _LiveWorkout extends WorkoutController {
  @override
  WorkoutState build() => const WorkoutState(
    snapshot: WorkoutSnapshot(
      type: WorkoutType.running,
      status: WorkoutStatus.running,
      elapsed: Duration(minutes: 3),
    ),
  );
}

void main() {
  late Directory root;
  late Directory documents;
  late Directory scratch;
  late List<String> log;
  late FakeFileSharer sharer;

  setUp(() async {
    root = newTempDir('tiles');
    documents = Directory(p.join(root.path, 'documents'));
    scratch = Directory(p.join(root.path, 'scratch'))..createSync();
    log = [];
    sharer = FakeFileSharer();
    await seedDocuments(documents, ring: 'OLD', staleSidecars: false);
  });
  tearDown(() => cleanUp(root));

  BackupArchive archiveOf() => BackupArchive(
    documents: documents,
    appSchemaVersion: currentSchemaVersion,
  );

  Future<File> validZip() async => writeZip(scratch, 'in/ok.zip', {
    'manifest.json': manifestBytes(),
    dbName: await appDatabaseBytes(scratch, 'new.db', rings: ['NEW']),
  });

  File badZip() =>
      File(p.join(scratch.path, 'bad.zip'))
        ..writeAsBytesSync(List.filled(64, 3));

  File pendingFile() => File(p.join(documents.path, 'pending_restore.zip'));

  Future<void> pumpSettings(
    WidgetTester tester, {
    File? picked,
    _Picker? picker,
    List<Override> extra = const [],
  }) async {
    final database = openAppDatabase(File(p.join(documents.path, dbName)));
    addTearDown(database.close);
    await pumpScaled(
      tester,
      screenHost(const SettingsScreen()),
      textScaler: TextScaler.noScaling,
      brightness: Brightness.dark,
      locale: const Locale('en'),
      overrides: [
        ...bleOverrides(),
        ...ringOverrides(),
        ...settingsOverrides(sharer: sharer),
        appDatabaseProvider.overrideWithValue(database),
        backupArchiveProvider.overrideWithValue(archiveOf()),
        backupExportDirectoryProvider.overrideWith(
          (ref) async => Directory(p.join(root.path, 'export')),
        ),
        backupFilePickerProvider.overrideWithValue(picker ?? _Picker(picked)),
        restoreCoordinatorProvider.overrideWithValue(
          RestoreCoordinator(
            archive: archiveOf(),
            background: _Background(log),
            restarter: _Restarter(log),
            pending: PendingRestore(documents),
          ),
        ),
        ...extra,
      ],
    );
  }

  Future<void> tapTile(WidgetTester tester, Key key) async {
    await reveal(tester, find.byKey(key));
    await tester.tap(find.byKey(key));
    await tester.pumpAndSettle();
  }

  Future<void> tapDialog(WidgetTester tester, Key key) async {
    await tester.tap(find.byKey(key));
    await tester.pumpAndSettle();
  }

  testWidgets('criterion 1: export shares exactly one zip with the zip MIME', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await pumpSettings(tester);
      await tapTile(tester, BackupTiles.exportKey);
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
    });

    expect(sharer.shared, hasLength(1));
    expect(sharer.shared.single, hasLength(1));
    expect(sharer.shared.single.single.mimeType, ExportFile.zipMimeType);
    expect(sharer.shared.single.single.path, endsWith('.zip'));
  });

  testWidgets('criterion 2: cancelling the confirmation leaves everything', (
    tester,
  ) async {
    final picker = _Picker(null);
    await pumpSettings(tester, picker: picker);
    final before = hashTree(documents);

    await tapTile(tester, BackupTiles.restoreKey);
    await tapDialog(tester, BackupTiles.restoreCancelKey);

    expect(picker.calls, 0);
    expect(log, isEmpty);
    expect(pendingFile().existsSync(), isFalse);
    expect(hashTree(documents), before);
  });

  testWidgets('criterion 2: a null pick leaves everything', (tester) async {
    final picker = _Picker(null);
    await pumpSettings(tester, picker: picker);
    final before = hashTree(documents);

    await tapTile(tester, BackupTiles.restoreKey);
    await tapDialog(tester, BackupTiles.restoreConfirmKey);

    expect(picker.calls, 1);
    expect(log, isEmpty);
    expect(find.byType(SnackBar), findsNothing);
    expect(hashTree(documents), before);
  });

  testWidgets('criterion 2: a rejected check says so and leaves everything', (
    tester,
  ) async {
    await pumpSettings(tester, picked: badZip());
    final before = hashTree(documents);

    await tapTile(tester, BackupTiles.restoreKey);
    await tapDialog(tester, BackupTiles.restoreConfirmKey);

    expect(log, isEmpty);
    expect(find.byType(SnackBar), findsOneWidget);
    expect(pendingFile().existsSync(), isFalse);
    expect(hashTree(documents), before);
  });

  testWidgets('criterion 3: a valid pick stages, stops and restarts', (
    tester,
  ) async {
    final zip = await tester.runAsync(validZip);
    await pumpSettings(tester, picked: zip);

    await tapTile(tester, BackupTiles.restoreKey);
    await tester.runAsync(() async {
      await tapDialog(tester, BackupTiles.restoreConfirmKey);
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    await tester.pumpAndSettle();

    expect(log, ['stop', 'restart']);
    expect(pendingFile().existsSync(), isTrue);
  });

  testWidgets('criterion 7: restore is refused while a workout is live', (
    tester,
  ) async {
    final picker = _Picker(badZip());
    await pumpSettings(
      tester,
      picker: picker,
      extra: [workoutProvider.overrideWith(_LiveWorkout.new)],
    );
    final before = hashTree(documents);

    await tapTile(tester, BackupTiles.restoreKey);

    expect(find.byKey(BackupTiles.restoreConfirmKey), findsNothing);
    expect(find.byType(SnackBar), findsOneWidget);
    expect(picker.calls, 0);
    expect(log, isEmpty);
    expect(hashTree(documents), before);
  });
}

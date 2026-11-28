import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_ring/core/database/app_database_provider.dart';
import 'package:open_ring/features/backup/application/backup_archive.dart';
import 'package:open_ring/features/backup/application/pending_restore.dart';
import 'package:open_ring/features/backup/application/restore_coordinator.dart';
import 'package:open_ring/features/backup/infrastructure/android_background_work.dart';
import 'package:open_ring/features/backup/infrastructure/method_channel_app_restarter.dart';
import 'package:open_ring/features/backup/presentation/backup_file_picker.dart';
import 'package:open_ring/features/ring/application/sync_interval_controller.dart';
import 'package:open_ring/features/ring/infrastructure/method_channel_sync_service.dart';

final backupDocumentsProvider = Provider<Directory>(
  (ref) => throw UnimplementedError('Override backupDocumentsProvider.'),
);

final backupArchiveProvider = Provider<BackupArchive>(
  (ref) => BackupArchive(
    documents: ref.watch(backupDocumentsProvider),
    appSchemaVersion: ref.watch(appDatabaseProvider).schemaVersion,
  ),
);

final backupExportDirectoryProvider = FutureProvider<Directory>(
  (ref) => Directory.systemTemp.createTemp('openring-export-'),
);

final backupFilePickerProvider = Provider<BackupFilePicker>(
  (ref) => const FileSelectorBackupPicker(),
);

final restoreCoordinatorProvider = Provider<RestoreCoordinator>(
  (ref) => RestoreCoordinator(
    archive: ref.watch(backupArchiveProvider),
    background: AndroidBackgroundWork(
      scheduler: ref.watch(syncSchedulerProvider),
      syncService: const MethodChannelSyncService(),
    ),
    restarter: const MethodChannelAppRestarter(),
    pending: PendingRestore(ref.watch(backupDocumentsProvider)),
  ),
);

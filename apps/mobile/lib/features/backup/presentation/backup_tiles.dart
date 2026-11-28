import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/database/app_database_provider.dart';
import 'package:open_ring/features/backup/application/backup_providers.dart';
import 'package:open_ring/features/backup/domain/backup_check.dart';
import 'package:open_ring/features/export/application/export_controller.dart';
import 'package:open_ring/features/export/domain/data_exporter.dart';
import 'package:open_ring/features/settings/presentation/settings_widgets.dart';
import 'package:open_ring/features/workout/application/workout_controller.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

class BackupTiles extends ConsumerStatefulWidget {
  const new({super.key});

  static const exportKey = Key('settings_backup_export');
  static const restoreKey = Key('settings_backup_restore');
  static const restoreConfirmKey = Key('settings_backup_restore_confirm');
  static const restoreCancelKey = Key('settings_backup_restore_cancel');

  @override
  ConsumerState<BackupTiles> createState() => _BackupTilesState();
}

class _BackupTilesState extends ConsumerState<BackupTiles> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsTile(
          key: BackupTiles.exportKey,
          leading: Icon(Icons.archive_rounded, color: colors.oxygen),
          title: l10n.backupExportTitle,
          detail: l10n.backupExportDetail,
          onTap: _busy ? null : () => unawaited(_export()),
        ),
        Divider(height: 1, color: colors.surfaceBorder),
        SettingsTile(
          key: BackupTiles.restoreKey,
          leading: Icon(
            Icons.settings_backup_restore_rounded,
            color: colors.oxygen,
          ),
          title: l10n.backupRestoreTitle,
          detail: l10n.backupRestoreDetail,
          onTap: _busy ? null : () => unawaited(_restore()),
        ),
      ],
    );
  }

  Future<void> _export() async {
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      final directory = await ref.read(backupExportDirectoryProvider.future);
      final file = await ref
          .read(backupArchiveProvider)
          .export(ref.read(appDatabaseProvider), directory);
      await ref.read(fileSharerProvider).share([
        ExportFile(path: file.path, mimeType: ExportFile.zipMimeType),
      ], subject: l10n.backupShareSubject);
    } on Object {
      _say(l10n.backupExportFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    final l10n = AppLocalizations.of(context);
    if (ref.read(workoutProvider).live) {
      _say(l10n.backupRestoreWorkoutLive);
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => const _RestoreDialog(),
    );
    if (confirmed != true || !mounted) return;
    final file = await ref.read(backupFilePickerProvider).pick();
    if (file == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final outcome = await ref.read(restoreCoordinatorProvider).restore(file);
      if (outcome case Rejected(:final check)) {
        _say(_problemText(l10n, check.problem));
      }
    } on Object {
      _say(l10n.backupRestoreFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _say(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }
}

String _problemText(AppLocalizations l10n, BackupProblem? problem) =>
    switch (problem) {
      BackupProblem.newerSchema => l10n.backupProblemNewer,
      BackupProblem.corrupt => l10n.backupProblemCorrupt,
      BackupProblem.notZip ||
      BackupProblem.missingManifest ||
      BackupProblem.foreignApp ||
      BackupProblem.unsupportedFormat ||
      BackupProblem.notSqlite ||
      BackupProblem.unsafePath ||
      null => l10n.backupProblemNotBackup,
    };

class _RestoreDialog extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    return AlertDialog(
      scrollable: true,
      title: Text(l10n.backupRestoreDialogTitle),
      content: Text(l10n.backupRestoreDialogBody),
      actions: [
        TextButton(
          key: BackupTiles.restoreCancelKey,
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.settingsDeleteCancel),
        ),
        FilledButton(
          key: BackupTiles.restoreConfirmKey,
          style: FilledButton.styleFrom(
            backgroundColor: colors.heart,
            foregroundColor: colors.onAccent,
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.backupRestoreConfirm),
        ),
      ],
    );
  }
}

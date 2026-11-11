import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/features/onboarding/presentation/onboarding_page.dart';
import 'package:open_ring/features/settings/application/delete_all_data_controller.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

class DeleteDataTile extends ConsumerWidget {
  const new({super.key});

  static const buttonKey = Key('settings_delete_all');
  static const confirmKey = Key('settings_delete_confirm');
  static const cancelKey = Key('settings_delete_cancel');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final deleting =
        ref.watch(deleteAllDataProvider) == DeletionStatus.deleting;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: OutlinedButton(
        key: buttonKey,
        style: OutlinedButton.styleFrom(
          foregroundColor: colors.heart,
          minimumSize: const Size.fromHeight(48),
        ),
        onPressed: deleting ? null : () => unawaited(_confirm(context, ref)),
        child: Text(l10n.settingsDeleteAll, textAlign: TextAlign.center),
      ),
    );
  }

  Future<void> _confirm(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => const _DeleteDialog(),
    );
    if (confirmed != true || !context.mounted) return;
    final deleted = await ref.read(deleteAllDataProvider.notifier).delete();
    if (!context.mounted) return;
    if (!deleted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).settingsDeleteFailed),
        ),
      );
      return;
    }
    context.go(AppPaths.onboarding);
  }
}

class _DeleteDialog extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    return AlertDialog(
      scrollable: true,
      title: Text(l10n.settingsDeleteTitle),
      content: Text(l10n.settingsDeleteBody(healthPlatformName())),
      actions: [
        TextButton(
          key: DeleteDataTile.cancelKey,
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.settingsDeleteCancel),
        ),
        FilledButton(
          key: DeleteDataTile.confirmKey,
          style: FilledButton.styleFrom(
            backgroundColor: colors.heart,
            foregroundColor: colors.onAccent,
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.settingsDeleteConfirm),
        ),
      ],
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/features/demo/application/demo_mode_controller.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

abstract final class DemoKeys {
  static const banner = Key('demo_banner');
  static const leave = Key('demo_leave');
  static const ringLeave = Key('demo_ring_leave');
  static const leaveCancel = Key('demo_leave_cancel');
  static const leaveConfirm = Key('demo_leave_confirm');
}

class DemoBanner extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(demoModeProvider)) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final theme = Theme.of(context);
    return Material(
      key: DemoKeys.banner,
      color: colors.surfaceInner,
      shape: Border(top: BorderSide(color: colors.surfaceBorder)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
        child: Row(
          children: [
            Icon(Icons.science_outlined, size: 20, color: colors.oxygen),
            const SizedBox(width: 12),
            Expanded(
              child: Semantics(
                liveRegion: true,
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '${l10n.demoBannerTitle} ',
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      TextSpan(text: l10n.demoBannerBody),
                    ],
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              key: DemoKeys.leave,
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: () => unawaited(leaveDemo(context, ref)),
              child: Text(l10n.demoLeave),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> leaveDemo(BuildContext context, WidgetRef ref) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (_) => const _LeaveDialog(),
  );
  if (confirmed != true || !context.mounted) return;
  // The banner hides as soon as the flag drops, so these are taken first.
  final router = GoRouter.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final l10n = AppLocalizations.of(context);
  final left = await ref.read(demoModeProvider.notifier).leave();
  if (!left) {
    messenger.showSnackBar(SnackBar(content: Text(l10n.demoLeaveFailed)));
    return;
  }
  router.go(AppPaths.onboarding);
}

class _LeaveDialog extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      scrollable: true,
      title: Text(l10n.demoLeaveTitle),
      content: Text(l10n.demoLeaveBody),
      actions: [
        TextButton(
          key: DemoKeys.leaveCancel,
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.demoLeaveCancel),
        ),
        FilledButton(
          key: DemoKeys.leaveConfirm,
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.demoLeave),
        ),
      ],
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

abstract final class ModulesShortcutKeys {
  static const open = Key('today_modules_open');
  static const dismiss = Key('today_modules_dismiss');
}

class ModulesShortcutSlot extends ConsumerWidget {
  const new({super.key});

  // Until the choice is read the shortcut stays out, so a dismissed one never
  // shows for a frame.
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dismissed = ref.watch(modulesShortcutProvider).value ?? true;
    if (dismissed) return const SizedBox.shrink();
    return const Padding(
      padding: EdgeInsets.only(top: 16),
      child: _ModulesShortcut(),
    );
  }
}

class _ModulesShortcut extends ConsumerWidget {
  const new();

  void _dismiss(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final shortcut = ref.read(modulesShortcutProvider.notifier);
    unawaited(shortcut.set(dismissed: true));
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(l10n.todayModulesDismissed),
          action: SnackBarAction(
            label: l10n.bodyEntryUndo,
            onPressed: () => unawaited(shortcut.set(dismissed: false)),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final l10n = AppLocalizations.of(context);
    return MetricCard(
      padding: EdgeInsets.zero,
      child: Row(
        children: [
          Expanded(
            child: MergeSemantics(
              child: Semantics(
                button: true,
                child: InkWell(
                  key: ModulesShortcutKeys.open,
                  onTap: () => context.go(AppPaths.settingsModules),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 48),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 4, 10),
                      child: Row(
                        children: [
                          Icon(
                            Icons.grid_view_rounded,
                            size: 20,
                            color: colors.textPrimary,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              l10n.todayModulesShortcut,
                              style: theme.textTheme.bodyMedium,
                            ),
                          ),
                          Icon(
                            Icons.chevron_right_rounded,
                            color: colors.textLabel,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            key: ModulesShortcutKeys.dismiss,
            tooltip: l10n.todayModulesDismiss,
            onPressed: () => _dismiss(context, ref),
            icon: Icon(Icons.close_rounded, size: 20, color: colors.textLabel),
          ),
        ],
      ),
    );
  }
}

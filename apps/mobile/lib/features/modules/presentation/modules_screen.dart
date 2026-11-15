import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/core/widgets/app_page.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';
import 'package:open_ring/features/modules/presentation/module_widgets.dart';
import 'package:open_ring/features/modules/presentation/offered_module.dart';
import 'package:open_ring/features/settings/presentation/settings_widgets.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

abstract final class ModulesKeys {
  static const bodyRow = Key('modules_body_row');
  static const bodySwitch = Key('modules_body_switch');
  static const openScoreRow = Key('modules_openScore_row');
  static const openScoreSwitch = Key('modules_openScore_switch');

  static Key row(OfferedModule module) => Key('modules_${module.name}_row');
  static Key toggle(OfferedModule module) =>
      Key('modules_${module.name}_switch');
}

Future<void> setModule(
  BuildContext context,
  WidgetRef ref,
  OfferedModule module, {
  required bool on,
}) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final router = GoRouter.of(context);
  final modules = ref.read(enabledModulesProvider.notifier);
  if (!on) {
    await modules.disable(module.id);
    return;
  }
  await modules.enable(module.id);
  messenger
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        content: Text(module.turnedOn(l10n)),
        action: SnackBarAction(
          label: l10n.modulesView,
          onPressed: () => router.go(AppTab.today.path),
        ),
      ),
    );
}

class ModulesScreen extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final enabled = ref.watch(enabledModulesProvider).value ?? const {};
    return AppPage(
      title: l10n.modulesTitle,
      subtitle: l10n.modulesIntro,
      children: [
        TileGroup(
          children: [
            for (final module in OfferedModule.values)
              _ModuleRow(module: module, on: enabled.contains(module.id)),
          ],
        ),
        const SizedBox(height: cardGap),
        ModuleFactsCard(
          title: l10n.modulesHowTitle,
          icon: Icons.check_rounded,
          facts: [
            l10n.modulesHowOff,
            l10n.modulesHowKeeps,
            l10n.modulesHowDelete,
          ],
        ),
      ],
    );
  }
}

class _ModuleRow extends ConsumerWidget {
  const new({required this.module, required this.on});

  final OfferedModule module;
  final bool on;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return Row(
      children: [
        Expanded(
          child: SettingsTile(
            key: ModulesKeys.row(module),
            title: module.title(l10n),
            detail: module.detail(l10n),
            chevron: true,
            onTap: () => context.go(module.path),
          ),
        ),
        const SizedBox(width: 8),
        // Outside the tile so a screen reader gets the toggle and the
        // row as two separate actions.
        Semantics(
          label: module.title(l10n),
          child: Switch(
            key: ModulesKeys.toggle(module),
            value: on,
            onChanged: (value) =>
                unawaited(setModule(context, ref, module, on: value)),
          ),
        ),
      ],
    );
  }
}

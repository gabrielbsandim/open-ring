import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/core/widgets/app_page.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/modules/presentation/module_widgets.dart';
import 'package:open_ring/features/settings/presentation/settings_widgets.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

abstract final class ModulesKeys {
  static const bodyRow = Key('modules_body_row');
  static const bodySwitch = Key('modules_body_switch');
}

Future<void> setBodyModule(
  BuildContext context,
  WidgetRef ref, {
  required bool on,
}) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final router = GoRouter.of(context);
  final modules = ref.read(enabledModulesProvider.notifier);
  if (!on) {
    await modules.disable(ModuleId.body);
    return;
  }
  await modules.enable(ModuleId.body);
  messenger
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        content: Text(l10n.moduleBodyTurnedOn),
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
    final bodyOn =
        ref.watch(enabledModulesProvider).value?.contains(ModuleId.body) ??
        false;
    return AppPage(
      title: l10n.modulesTitle,
      subtitle: l10n.modulesIntro,
      children: [
        TileGroup(
          children: [
            SettingsTile(
              key: ModulesKeys.bodyRow,
              title: l10n.moduleBodyName,
              detail: l10n.moduleBodyDetail,
              value: bodyOn ? l10n.modulesOn : l10n.modulesOff,
              trailing: Switch(
                key: ModulesKeys.bodySwitch,
                value: bodyOn,
                onChanged: (on) =>
                    unawaited(setBodyModule(context, ref, on: on)),
              ),
              onTap: () => context.go(AppPaths.settingsModuleBody),
            ),
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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

enum ModuleChange { done, both, cancelled }

abstract final class ModuleChangeKeys {
  static const confirm = Key('module_change_confirm');
  static const cancel = Key('module_change_cancel');
}

String moduleName(ModuleId id, AppLocalizations l10n) => switch (id) {
  ModuleId.body => l10n.moduleBodyName,
  ModuleId.openScore => l10n.moduleOpenScoreName,
  ModuleId.energy => l10n.energyTitle,
  ModuleId.effort => l10n.effortTitle,
  ModuleId.goals => l10n.moduleGoalsName,
  ModuleId.food => l10n.foodTitle,
  ModuleId.ai => l10n.moduleAiName,
  ModuleId.trajectory => l10n.moduleTrajectoryName,
};

// A module that needs another, or that another needs, changes only after the
// person confirms both; the cascade is never silent.
Future<ModuleChange> changeModule(
  BuildContext context,
  WidgetRef ref,
  ModuleId id, {
  required bool on,
}) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final modules = ref.read(enabledModulesProvider.notifier);
  final enabled = await ref.read(enabledModulesProvider.future);
  if (enabled.contains(id) == on) return ModuleChange.done;
  final blockers = await _step(modules, id, on: on);
  if (blockers.isEmpty) return ModuleChange.done;
  if (!context.mounted) return ModuleChange.cancelled;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (_) => _BothDialog(id: id, others: blockers, on: on),
  );
  if (confirmed != true) return ModuleChange.cancelled;
  for (final step in [...blockers, id]) {
    final left = await _step(modules, step, on: on);
    if (left.isNotEmpty) throw StateError('modules changed during confirm');
  }
  final first = moduleName(id, l10n);
  final second = _names(blockers, l10n);
  messenger
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        content: Text(
          on
              ? l10n.moduleBothOnDone(first, second)
              : l10n.moduleBothOffDone(first, second),
        ),
      ),
    );
  return ModuleChange.both;
}

Future<Set<ModuleId>> _step(
  EnabledModulesController modules,
  ModuleId id, {
  required bool on,
}) => on ? modules.enable(id) : modules.disable(id);

String _names(Set<ModuleId> ids, AppLocalizations l10n) =>
    ids.map((id) => moduleName(id, l10n)).join(', ');

class _BothDialog extends StatelessWidget {
  const new({required this.id, required this.others, required this.on});

  final ModuleId id;
  final Set<ModuleId> others;
  final bool on;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final module = moduleName(id, l10n);
    final other = _names(others, l10n);
    return AlertDialog(
      scrollable: true,
      title: Text(
        on ? l10n.moduleBothOnTitle(other) : l10n.moduleBothOffTitle(module),
      ),
      content: Text(
        on
            ? l10n.moduleBothOnBody(module, other)
            : l10n.moduleBothOffBody(other, module),
      ),
      actions: [
        TextButton(
          key: ModuleChangeKeys.cancel,
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(on ? l10n.moduleBothOnCancel : l10n.moduleBothOffCancel),
        ),
        FilledButton(
          key: ModuleChangeKeys.confirm,
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(
            on ? l10n.moduleBothOnConfirm : l10n.moduleBothOffConfirm,
          ),
        ),
      ],
    );
  }
}

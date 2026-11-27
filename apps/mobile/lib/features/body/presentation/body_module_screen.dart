import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/core/widgets/app_page.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/core/widgets/state_views.dart';
import 'package:open_ring/features/body/application/hide_numbers_controller.dart';
import 'package:open_ring/features/body/application/weigh_in_providers.dart';
import 'package:open_ring/features/body/domain/weigh_in.dart';
import 'package:open_ring/features/energy/application/energy_gate.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/modules/presentation/module_widgets.dart';
import 'package:open_ring/features/modules/presentation/modules_screen.dart';
import 'package:open_ring/features/modules/presentation/offered_module.dart';
import 'package:open_ring/features/settings/presentation/settings_widgets.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

abstract final class BodyModuleKeys {
  static const state = Key('body_module_state');
  static const kept = Key('body_module_kept');
  static const stored = Key('body_module_stored');
  static const delete = Key('body_module_delete');
  static const deleteConfirm = Key('body_module_delete_confirm');
  static const deleteCancel = Key('body_module_delete_cancel');
  static const toggle = Key('body_module_toggle');
  static const hide = Key('body_module_hide');
}

LocalDate _day(WeighIn entry) =>
    LocalDate.fromInstant(entry.at, Duration(minutes: entry.offsetMinutes));

class BodyModuleScreen extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final format = MetricFormat.of(context);
    final l10n = format.l10n;
    final colors = AppColors.of(context);
    final on =
        ref.watch(enabledModulesProvider).value?.contains(ModuleId.body) ??
        false;
    final entries = ref.watch(weighInsProvider).value ?? const <WeighIn>[];
    final hidden = ref.watch(hideNumbersProvider).value ?? false;
    void toggle() =>
        unawaited(setModule(context, ref, OfferedModule.body, on: !on));
    return AppPage(
      title: l10n.moduleBodyName,
      subtitle: l10n.moduleBodyDetail,
      children: [
        ModuleStatePill(
          key: BodyModuleKeys.state,
          on: on,
          label: on ? l10n.modulesOn : l10n.modulesOff,
        ),
        const SizedBox(height: 16),
        if (!on && entries.isNotEmpty) ...[
          MetricCard(
            key: BodyModuleKeys.kept,
            color: colors.surfaceInner,
            child: BodyText(l10n.moduleBodyKept(entries.length)),
          ),
          const SizedBox(height: cardGap),
        ],
        ModuleFactsCard(
          title: l10n.moduleBodyAddsTitle,
          icon: Icons.check_rounded,
          facts: [
            l10n.moduleBodyAddsCard,
            l10n.moduleBodyAddsLog,
            l10n.moduleBodyAddsScreen,
          ],
        ),
        const SizedBox(height: cardGap),
        ModuleFactsCard(
          title: l10n.moduleBodyStoresTitle,
          icon: Icons.smartphone_rounded,
          facts: [
            l10n.moduleBodyStoresWeight,
            l10n.moduleBodyStoresExtras,
            l10n.moduleBodyStoresLocal,
          ],
        ),
        const SizedBox(height: cardGap),
        ModuleFactsCard(
          title: l10n.moduleBodyNeverTitle,
          icon: Icons.block_rounded,
          facts: [
            l10n.moduleBodyNeverColour,
            l10n.moduleBodyNeverStreak,
            l10n.moduleBodyNeverScore,
          ],
        ),
        const SizedBox(height: cardGap),
        MetricCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: SwitchListTile(
            key: BodyModuleKeys.hide,
            value: hidden,
            onChanged: (value) => unawaited(_hide(context, ref, hidden: value)),
            contentPadding: EdgeInsets.zero,
            secondary: Icon(
              Icons.visibility_off_outlined,
              color: colors.textPrimary,
            ),
            title: Text(l10n.bodyHideTitle),
            subtitle: CaptionText(_hideDetail(l10n, ref)),
            activeThumbColor: colors.background,
            activeTrackColor: colors.activity,
            inactiveThumbColor: colors.textSecondary,
            inactiveTrackColor: colors.surfaceInner,
          ),
        ),
        SectionHeader(l10n.moduleBodyDataTitle),
        BodyText(key: BodyModuleKeys.stored, _stored(format, entries)),
        if (entries.isNotEmpty) ...[
          const SizedBox(height: 12),
          OutlinedButton(
            key: BodyModuleKeys.delete,
            style: OutlinedButton.styleFrom(
              foregroundColor: colors.heart,
              minimumSize: const Size.fromHeight(48),
            ),
            onPressed: () => unawaited(_delete(context, ref, entries.length)),
            child: Text(l10n.moduleBodyDelete, textAlign: TextAlign.center),
          ),
        ],
        const SizedBox(height: 12),
        CaptionText(l10n.moduleBodyFoot),
        const SizedBox(height: 24),
        if (on)
          SecondaryButton(
            key: BodyModuleKeys.toggle,
            label: l10n.moduleBodyTurnOff,
            onPressed: toggle,
          ),
        if (!on)
          ActionButton(
            key: BodyModuleKeys.toggle,
            label: l10n.moduleBodyTurnOn,
            onPressed: toggle,
          ),
        const SizedBox(height: 8),
        CaptionText(
          on ? l10n.moduleBodyTurnOffNote : l10n.moduleBodyTurnOnNote,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  String _stored(MetricFormat format, List<WeighIn> entries) {
    if (entries.isEmpty) return format.l10n.moduleBodyDataEmpty;
    return format.l10n.moduleBodyDataCount(
      entries.length,
      format.date(_day(entries.last)),
      format.date(_day(entries.first)),
    );
  }

  Future<void> _hide(
    BuildContext context,
    WidgetRef ref, {
    required bool hidden,
  }) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    await ref.read(hideNumbersProvider.notifier).set(hidden: hidden);
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(content: Text(hidden ? l10n.bodyHideOn : l10n.bodyHideOff)),
      );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, int count) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _DeleteDialog(count: count),
    );
    if (confirmed != true) return;
    final deleted = await _deleteAll(ref);
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(
            deleted ? l10n.moduleBodyDeleted : l10n.moduleBodyDeleteFailed,
          ),
        ),
      );
  }

  Future<bool> _deleteAll(WidgetRef ref) async {
    try {
      await ref.read(weighInLogProvider.notifier).deleteAll();
      return true;
    } on Exception {
      return false;
    }
  }
}

// The energy estimate is named only for a person for whom it counts as on.
String _hideDetail(AppLocalizations l10n, WidgetRef ref) {
  final modules = ref.watch(activeModulesProvider);
  if (!modules.contains(ModuleId.energy)) return l10n.bodyHideDetail;
  return '${l10n.bodyHideDetail} ${l10n.bodyHideEnergy}';
}

class _DeleteDialog extends StatelessWidget {
  const new({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    return AlertDialog(
      scrollable: true,
      title: Text(l10n.moduleBodyDeleteTitle),
      content: Text(l10n.moduleBodyDeleteBody(count)),
      actions: [
        TextButton(
          key: BodyModuleKeys.deleteCancel,
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.settingsDeleteCancel),
        ),
        FilledButton(
          key: BodyModuleKeys.deleteConfirm,
          style: FilledButton.styleFrom(
            backgroundColor: colors.heart,
            foregroundColor: colors.onAccent,
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.moduleBodyDelete),
        ),
      ],
    );
  }
}

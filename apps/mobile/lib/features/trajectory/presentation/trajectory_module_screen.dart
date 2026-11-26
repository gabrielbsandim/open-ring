import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/core/widgets/app_page.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/core/widgets/state_views.dart';
import 'package:open_ring/features/energy/application/energy_gate.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/modules/presentation/module_widgets.dart';
import 'package:open_ring/features/modules/presentation/modules_screen.dart';
import 'package:open_ring/features/modules/presentation/offered_module.dart';
import 'package:open_ring/features/open_score/presentation/day_score_receipt_screen.dart';
import 'package:open_ring/features/settings/presentation/settings_widgets.dart';
import 'package:open_ring/features/trajectory/application/trajectory_data.dart';
import 'package:open_ring/features/trajectory/domain/trajectory_projection.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

abstract final class TrajectoryModuleKeys {
  static const state = Key('trajectory_module_state');
  static const underage = Key('trajectory_module_underage');
  static const needsBody = Key('trajectory_module_needs_body');
  static const view = Key('trajectory_module_view');
  static const formula = Key('trajectory_module_formula');
  static const stored = Key('trajectory_module_stored');
  static const delete = Key('trajectory_module_delete');
  static const deleteConfirm = Key('trajectory_module_delete_confirm');
  static const deleteCancel = Key('trajectory_module_delete_cancel');
  static const toggle = Key('trajectory_module_toggle');
}

class TrajectoryModuleScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<TrajectoryModuleScreen> createState() =>
      _TrajectoryModuleScreenState();
}

class _TrajectoryModuleScreenState
    extends ConsumerState<TrajectoryModuleScreen> {
  var _deleting = false;

  @override
  Widget build(BuildContext context) {
    final format = MetricFormat.of(context);
    final l10n = format.l10n;
    final colors = AppColors.of(context);
    final modules = ref.watch(activeModulesProvider);
    final on = modules.contains(ModuleId.trajectory);
    final body = modules.contains(ModuleId.body);
    final underage = ref.watch(energyUnderageProvider);
    final data = ref.watch(trajectoryDataProvider);
    final stored = data.value ?? const <TrajectoryProjection>[];
    final bodyName = l10n.moduleBodyName;
    String weeks(int days) => format.integer(days ~/ DateTime.daysPerWeek);
    return AppPage(
      title: l10n.moduleTrajectoryName,
      subtitle: l10n.moduleTrajectoryDetail,
      children: [
        ModuleStatePill(
          key: TrajectoryModuleKeys.state,
          on: on,
          label: _stateLabel(l10n, on: on, underage: underage ?? false),
        ),
        const SizedBox(height: 16),
        if (underage ?? false)
          _Notice(
            key: TrajectoryModuleKeys.underage,
            icon: Icons.person_outline,
            text: l10n.trajectoryRefusedUnderage,
          ),
        if (underage == false && !body)
          _Notice(
            key: TrajectoryModuleKeys.needsBody,
            icon: Icons.monitor_weight_outlined,
            text: l10n.moduleTrajectoryNeedsBody(bodyName),
          ),
        ModuleFactsCard(
          title: l10n.moduleBodyAddsTitle,
          icon: Icons.check_rounded,
          facts: [
            l10n.moduleTrajectoryAdds1(
              weeks(trajectoryFirmDays),
              weeks(trajectoryBandDays),
            ),
            l10n.moduleTrajectoryAdds2(
              l10n.energyTitle,
              format.integer(weightRateWindowDays),
            ),
            l10n.moduleTrajectoryAdds3(format.integer(leverTrendWindowDays)),
            l10n.moduleTrajectoryAdds4,
            l10n.moduleTrajectoryAdds5(bodyName, l10n.tabToday),
          ],
        ),
        const SizedBox(height: cardGap),
        ModuleFactsCard(
          title: l10n.moduleOpenScoreUsesTitle,
          icon: Icons.smartphone_rounded,
          facts: [
            l10n.moduleTrajectoryUses1(bodyName),
            l10n.moduleTrajectoryUses2,
            l10n.moduleTrajectoryUses3(l10n.profileTitle),
            l10n.moduleTrajectoryUses4,
          ],
        ),
        const SizedBox(height: cardGap),
        ModuleFactsCard(
          title: l10n.moduleBodyStoresTitle,
          icon: Icons.receipt_long_outlined,
          facts: [
            l10n.moduleTrajectoryStores1(weeks(trajectoryFirmDays)),
            l10n.moduleTrajectoryStores2,
            l10n.moduleTrajectoryStores3,
          ],
        ),
        const SizedBox(height: cardGap),
        ModuleFactsCard(
          title: l10n.moduleBodyNeverTitle,
          icon: Icons.block_rounded,
          facts: [
            l10n.moduleTrajectoryNever1,
            l10n.moduleTrajectoryNever2,
            l10n.moduleTrajectoryNever3,
            l10n.moduleTrajectoryNever4,
          ],
        ),
        const SizedBox(height: cardGap),
        if (on)
          DayScoreLink(
            key: TrajectoryModuleKeys.view,
            title: l10n.moduleTrajectoryView,
            caption: l10n.moduleTrajectoryViewCaption,
            path: AppPaths.trajectory,
            push: true,
          ),
        DayScoreLink(
          key: TrajectoryModuleKeys.formula,
          title: l10n.formulaLink,
          caption: l10n.moduleTrajectoryFormulaCaption,
          path: AppPaths.trajectoryFormula,
          push: true,
        ),
        SectionHeader(l10n.moduleTrajectoryDataTitle),
        BodyText(key: TrajectoryModuleKeys.stored, _storedLine(format, data)),
        if (stored.isNotEmpty) ...[
          const SizedBox(height: 12),
          OutlinedButton(
            key: TrajectoryModuleKeys.delete,
            style: OutlinedButton.styleFrom(
              foregroundColor: colors.heart,
              minimumSize: const Size.fromHeight(48),
            ),
            onPressed: _deleting
                ? null
                : () => unawaited(_delete(stored.length)),
            child: Text(
              l10n.moduleTrajectoryDelete,
              textAlign: TextAlign.center,
            ),
          ),
        ],
        const SizedBox(height: 12),
        CaptionText(l10n.moduleBodyFoot),
        const SizedBox(height: 24),
        // A known adult gets the button; turning off stays open to anyone.
        if (on || underage == false)
          _Toggle(
            on: on,
            body: body,
            onPressed: () => unawaited(
              setModule(context, ref, OfferedModule.trajectory, on: !on),
            ),
          ),
      ],
    );
  }

  // A list that cannot be read is not shown as empty, since that would say
  // nothing is stored when projections may be there.
  String _storedLine(
    MetricFormat format,
    AsyncValue<List<TrajectoryProjection>> data,
  ) {
    final l10n = format.l10n;
    if (data.hasError) return l10n.metricLoadError;
    final rows = data.value;
    if (rows == null) return '';
    if (rows.isEmpty) return l10n.moduleTrajectoryDataEmpty;
    return l10n.moduleTrajectoryDataCount(
      rows.length,
      format.date(rows.first.monday),
      format.date(rows.last.monday),
    );
  }

  // Delete stays disabled until the clear returns, so a second tap cannot
  // open a second dialog while the first delete runs.
  Future<void> _delete(int count) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _deleting = true);
    final deleted = await _confirmAndClear(count);
    if (mounted) setState(() => _deleting = false);
    if (deleted == null) return;
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(
            deleted
                ? l10n.moduleTrajectoryDeleted
                : l10n.moduleTrajectoryDeleteFailed,
          ),
        ),
      );
  }

  Future<bool?> _confirmAndClear(int count) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _DeleteDialog(count: count),
    );
    if (confirmed != true || !mounted) return null;
    return await ref.read(trajectoryDataEraserProvider).clear();
  }
}

String _stateLabel(
  AppLocalizations l10n, {
  required bool on,
  required bool underage,
}) {
  if (on) return l10n.modulesOn;
  if (underage) return l10n.moduleEnergyUnavailable;
  return l10n.modulesOff;
}

class _Notice extends StatelessWidget {
  const new({required this.icon, required this.text, super.key});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: cardGap),
      child: MetricCard(
        color: colors.surfaceInner,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(child: Icon(icon, size: 20)),
            const SizedBox(width: 10),
            Expanded(child: BodyText(text)),
          ],
        ),
      ),
    );
  }
}

class _Toggle extends StatelessWidget {
  const new({required this.on, required this.body, required this.onPressed});

  final bool on;
  final bool body;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final bodyName = l10n.moduleBodyName;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (on)
          SecondaryButton(
            key: TrajectoryModuleKeys.toggle,
            label: l10n.moduleTrajectoryTurnOff,
            onPressed: onPressed,
          ),
        if (!on)
          ActionButton(
            key: TrajectoryModuleKeys.toggle,
            label: body
                ? l10n.moduleTrajectoryTurnOn
                : l10n.moduleTrajectoryTurnOnBoth(bodyName),
            onPressed: onPressed,
          ),
        const SizedBox(height: 8),
        CaptionText(_note(l10n, bodyName), textAlign: TextAlign.center),
      ],
    );
  }

  String _note(AppLocalizations l10n, String bodyName) {
    if (on) return l10n.moduleTrajectoryTurnOffNote(bodyName);
    if (body) return l10n.moduleTrajectoryTurnOnNote;
    return l10n.moduleTrajectoryTurnOnBothNote(bodyName);
  }
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
      title: Text(l10n.moduleTrajectoryDeleteTitle),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l10n.moduleTrajectoryDeleteBody(count)),
          for (final fact in [
            l10n.moduleTrajectoryDeleteFact1(l10n.moduleBodyName),
            l10n.moduleTrajectoryDeleteFact2,
            l10n.moduleTrajectoryDeleteFact3,
          ]) ...[const SizedBox(height: 8), Text(fact)],
        ],
      ),
      actions: [
        TextButton(
          key: TrajectoryModuleKeys.deleteCancel,
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.settingsDeleteCancel),
        ),
        FilledButton(
          key: TrajectoryModuleKeys.deleteConfirm,
          style: FilledButton.styleFrom(
            backgroundColor: colors.heart,
            foregroundColor: colors.onAccent,
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.moduleTrajectoryDelete),
        ),
      ],
    );
  }
}

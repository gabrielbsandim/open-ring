import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/widgets/app_page.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/core/widgets/state_views.dart';
import 'package:open_ring/features/goals/application/goals_data.dart';
import 'package:open_ring/features/goals/presentation/soft_mode_exit_card.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/modules/presentation/module_widgets.dart';
import 'package:open_ring/features/modules/presentation/modules_screen.dart';
import 'package:open_ring/features/modules/presentation/offered_module.dart';
import 'package:open_ring/features/open_score/presentation/day_score_receipt_screen.dart';
import 'package:open_ring/features/settings/presentation/settings_widgets.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

abstract final class GoalsModuleKeys {
  static const state = Key('goals_module_state');
  static const kept = Key('goals_module_kept');
  static const stored = Key('goals_module_stored');
  static const goal = Key('goals_module_goal');
  static const formula = Key('goals_module_formula');
  static const delete = Key('goals_module_delete');
  static const deleteConfirm = Key('goals_module_delete_confirm');
  static const deleteCancel = Key('goals_module_delete_cancel');
  static const toggle = Key('goals_module_toggle');
}

class GoalsModuleScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<GoalsModuleScreen> createState() => _GoalsModuleScreenState();
}

class _GoalsModuleScreenState extends ConsumerState<GoalsModuleScreen> {
  var _deleting = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final on =
        ref.watch(enabledModulesProvider).value?.contains(ModuleId.goals) ??
        false;
    final count = ref.watch(goalsDataCountProvider);
    final total = count.value?.total ?? 0;
    void toggle() =>
        unawaited(setModule(context, ref, OfferedModule.goals, on: !on));
    return AppPage(
      title: l10n.moduleGoalsName,
      subtitle: l10n.moduleGoalsDetail,
      children: [
        ModuleStatePill(
          key: GoalsModuleKeys.state,
          on: on,
          label: on ? l10n.modulesOn : l10n.modulesOff,
        ),
        const SizedBox(height: 16),
        if (!on && total > 0) ...[
          MetricCard(
            key: GoalsModuleKeys.kept,
            color: colors.surfaceInner,
            child: BodyText(l10n.moduleGoalsKept),
          ),
          const SizedBox(height: cardGap),
        ],
        ModuleFactsCard(
          title: l10n.moduleBodyAddsTitle,
          icon: Icons.check_rounded,
          facts: [
            l10n.moduleGoalsAddsCard,
            l10n.moduleGoalsAddsReview,
            l10n.moduleGoalsAddsScreen,
          ],
        ),
        const SizedBox(height: cardGap),
        ModuleFactsCard(
          title: l10n.moduleBodyStoresTitle,
          icon: Icons.smartphone_rounded,
          facts: [
            l10n.moduleGoalsStoresGoal,
            l10n.moduleGoalsStoresScreening,
            l10n.moduleBodyStoresLocal,
          ],
        ),
        const SizedBox(height: cardGap),
        ModuleFactsCard(
          title: l10n.moduleBodyNeverTitle,
          icon: Icons.block_rounded,
          facts: [l10n.moduleGoalsNeverDiet, l10n.moduleGoalsNeverDiagnosis],
        ),
        const SizedBox(height: cardGap),
        if (on)
          DayScoreLink(
            key: GoalsModuleKeys.goal,
            title: l10n.moduleGoalsGoal,
            caption: l10n.moduleGoalsGoalCaption,
            path: AppPaths.goals,
            push: true,
          ),
        DayScoreLink(
          key: GoalsModuleKeys.formula,
          title: l10n.formulaLink,
          caption: l10n.moduleGoalsFormulaCaption,
          path: AppPaths.goalsFormula,
          push: true,
        ),
        const SoftModeExitCard(),
        SectionHeader(l10n.moduleGoalsDataTitle),
        BodyText(key: GoalsModuleKeys.stored, _storedLine(l10n, count)),
        if (total > 0) ...[
          const SizedBox(height: 12),
          OutlinedButton(
            key: GoalsModuleKeys.delete,
            style: OutlinedButton.styleFrom(
              foregroundColor: colors.heart,
              minimumSize: const Size.fromHeight(48),
            ),
            onPressed: _deleting ? null : () => unawaited(_delete()),
            child: Text(l10n.moduleGoalsDelete, textAlign: TextAlign.center),
          ),
        ],
        const SizedBox(height: 12),
        CaptionText(l10n.moduleBodyFoot),
        const SizedBox(height: 24),
        if (on)
          SecondaryButton(
            key: GoalsModuleKeys.toggle,
            label: l10n.moduleGoalsTurnOff,
            onPressed: toggle,
          ),
        if (!on)
          ActionButton(
            key: GoalsModuleKeys.toggle,
            label: l10n.moduleGoalsTurnOn,
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

  // A count that cannot be read is not shown as empty, since that would hide
  // the delete of data that may be there.
  String _storedLine(AppLocalizations l10n, AsyncValue<GoalsDataCount> count) {
    if (count.hasError) return l10n.metricLoadError;
    final value = count.value;
    if (value == null) return '';
    return goalsDataLine(l10n, value);
  }

  // Delete stays disabled until the clear returns, so a second tap cannot
  // open a second dialog while the first delete runs.
  Future<void> _delete() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _deleting = true);
    final deleted = await _confirmAndClear();
    if (mounted) setState(() => _deleting = false);
    if (deleted == null) return;
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(
            deleted ? l10n.moduleGoalsDeleted : l10n.moduleGoalsDeleteFailed,
          ),
        ),
      );
  }

  Future<bool?> _confirmAndClear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => const _DeleteDialog(),
    );
    if (confirmed != true || !mounted) return null;
    return await ref.read(goalsDataEraserProvider).clear();
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
      title: Text(l10n.moduleGoalsDeleteTitle),
      content: Text(l10n.moduleGoalsDeleteBody),
      actions: [
        TextButton(
          key: GoalsModuleKeys.deleteCancel,
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.settingsDeleteCancel),
        ),
        FilledButton(
          key: GoalsModuleKeys.deleteConfirm,
          style: FilledButton.styleFrom(
            backgroundColor: colors.heart,
            foregroundColor: colors.onAccent,
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.moduleGoalsDelete),
        ),
      ],
    );
  }
}

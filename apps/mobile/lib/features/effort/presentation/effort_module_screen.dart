import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/widgets/app_page.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/core/widgets/state_views.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/modules/presentation/module_widgets.dart';
import 'package:open_ring/features/modules/presentation/modules_screen.dart';
import 'package:open_ring/features/modules/presentation/offered_module.dart';
import 'package:open_ring/features/open_score/presentation/day_score_receipt_screen.dart';
import 'package:open_ring/features/settings/presentation/settings_widgets.dart';
import 'package:open_ring/features/workout/application/workout_history_providers.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

abstract final class EffortModuleKeys {
  static const state = Key('effort_module_state');
  static const kept = Key('effort_module_kept');
  static const stored = Key('effort_module_stored');
  static const formula = Key('effort_module_formula');
  static const delete = Key('effort_module_delete');
  static const deleteConfirm = Key('effort_module_delete_confirm');
  static const deleteCancel = Key('effort_module_delete_cancel');
  static const toggle = Key('effort_module_toggle');
}

class EffortModuleScreen extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final on =
        ref.watch(enabledModulesProvider).value?.contains(ModuleId.effort) ??
        false;
    final ratings = ref.watch(effortRatingCountProvider).value ?? 0;
    void toggle() =>
        unawaited(setModule(context, ref, OfferedModule.effort, on: !on));
    return AppPage(
      title: l10n.effortTitle,
      subtitle: l10n.moduleEffortDetail,
      children: [
        ModuleStatePill(
          key: EffortModuleKeys.state,
          on: on,
          label: on ? l10n.modulesOn : l10n.modulesOff,
        ),
        const SizedBox(height: 16),
        if (!on && ratings > 0) ...[
          MetricCard(
            key: EffortModuleKeys.kept,
            color: colors.surfaceInner,
            child: BodyText(l10n.moduleEffortKept(ratings)),
          ),
          const SizedBox(height: cardGap),
        ],
        ModuleFactsCard(
          title: l10n.moduleBodyAddsTitle,
          icon: Icons.check_rounded,
          facts: [
            l10n.moduleEffortAddsTile,
            l10n.moduleEffortAddsCoach,
            l10n.moduleEffortAddsRating,
          ],
        ),
        const SizedBox(height: cardGap),
        ModuleFactsCard(
          title: l10n.moduleBodyStoresTitle,
          icon: Icons.smartphone_rounded,
          facts: [l10n.moduleEffortStoresRating, l10n.moduleBodyStoresLocal],
        ),
        const SizedBox(height: cardGap),
        ModuleFactsCard(
          title: l10n.moduleBodyNeverTitle,
          icon: Icons.block_rounded,
          facts: [
            l10n.moduleEffortNeverStreak,
            l10n.moduleEffortNeverDiagnosis,
          ],
        ),
        const SizedBox(height: cardGap),
        DayScoreLink(
          key: EffortModuleKeys.formula,
          title: l10n.formulaLink,
          caption: l10n.moduleEffortFormulaCaption,
          path: AppPaths.effortFormula,
          push: true,
        ),
        SectionHeader(l10n.moduleEffortDataTitle),
        BodyText(
          key: EffortModuleKeys.stored,
          ratings > 0
              ? l10n.moduleEffortDataCount(ratings)
              : l10n.moduleEffortDataEmpty,
        ),
        if (ratings > 0) ...[
          const SizedBox(height: 12),
          OutlinedButton(
            key: EffortModuleKeys.delete,
            style: OutlinedButton.styleFrom(
              foregroundColor: colors.heart,
              minimumSize: const Size.fromHeight(48),
            ),
            onPressed: () => unawaited(_delete(context, ref, ratings)),
            child: Text(l10n.moduleEffortDelete, textAlign: TextAlign.center),
          ),
        ],
        const SizedBox(height: 12),
        CaptionText(l10n.moduleBodyFoot),
        const SizedBox(height: 24),
        if (on)
          SecondaryButton(
            key: EffortModuleKeys.toggle,
            label: l10n.moduleEffortTurnOff,
            onPressed: toggle,
          ),
        if (!on)
          ActionButton(
            key: EffortModuleKeys.toggle,
            label: l10n.moduleEffortTurnOn,
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

  Future<void> _delete(BuildContext context, WidgetRef ref, int count) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _DeleteDialog(count: count),
    );
    if (confirmed != true || !context.mounted) return;
    final deleted = await _clear(ref);
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(
            deleted ? l10n.moduleEffortDeleted : l10n.moduleEffortDeleteFailed,
          ),
        ),
      );
  }

  Future<bool> _clear(WidgetRef ref) async {
    try {
      return await clearWorkoutRatings(ref);
    } on Object {
      return false;
    }
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
      title: Text(l10n.moduleEffortDeleteTitle),
      content: Text(l10n.moduleEffortDeleteBody(count)),
      actions: [
        TextButton(
          key: EffortModuleKeys.deleteCancel,
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.settingsDeleteCancel),
        ),
        FilledButton(
          key: EffortModuleKeys.deleteConfirm,
          style: FilledButton.styleFrom(
            backgroundColor: colors.heart,
            foregroundColor: colors.onAccent,
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.moduleEffortDelete),
        ),
      ],
    );
  }
}

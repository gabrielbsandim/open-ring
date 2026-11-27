import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metrics/metrics.dart';
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
import 'package:open_ring/features/open_score/application/open_score_data_providers.dart';
import 'package:open_ring/features/open_score/application/week_goal_providers.dart';
import 'package:open_ring/features/open_score/presentation/day_score_receipt_screen.dart';
import 'package:open_ring/features/settings/presentation/settings_widgets.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

abstract final class OpenScoreModuleKeys {
  static const state = Key('open_score_module_state');
  static const formula = Key('open_score_module_formula');
  static const toggle = Key('open_score_module_toggle');
  static const kept = Key('open_score_module_kept');
  static const stored = Key('open_score_module_stored');
  static const goal = Key('open_score_module_goal');
  static const delete = Key('open_score_module_delete');
  static const deleteConfirm = Key('open_score_module_delete_confirm');
  static const deleteCancel = Key('open_score_module_delete_cancel');
}

class OpenScoreModuleScreen extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final on = ref.watch(
      enabledModulesProvider.select(
        (modules) => modules.value?.contains(ModuleId.openScore) ?? false,
      ),
    );
    final colors = AppColors.of(context);
    final count = ref.watch(openScoreTagCountProvider);
    // A count that could not be read is not "nothing stored".
    final unread = count.hasError && !count.hasValue;
    final tags = count.value ?? 0;
    final goal = ref.watch(weekGoalProvider).value ?? weekGoalDefault;
    final customGoal = goal != weekGoalDefault;
    final deletable = !unread && (tags > 0 || customGoal);
    void toggle() =>
        unawaited(setModule(context, ref, OfferedModule.openScore, on: !on));
    return AppPage(
      title: l10n.moduleOpenScoreName,
      subtitle: l10n.moduleOpenScoreDetail,
      children: [
        ModuleStatePill(
          key: OpenScoreModuleKeys.state,
          on: on,
          label: on ? l10n.modulesOn : l10n.modulesOff,
        ),
        const SizedBox(height: 16),
        if (!on && tags > 0) ...[
          MetricCard(
            key: OpenScoreModuleKeys.kept,
            color: colors.surfaceInner,
            child: BodyText(l10n.moduleOpenScoreKept(tags)),
          ),
          const SizedBox(height: cardGap),
        ],
        ModuleFactsCard(
          title: l10n.moduleBodyAddsTitle,
          icon: Icons.check_rounded,
          facts: [
            l10n.moduleOpenScoreAddsCard,
            l10n.moduleOpenScoreAddsReceipt,
            l10n.moduleOpenScoreAddsHistory,
            l10n.moduleOpenScoreAddsTrends,
            l10n.moduleOpenScoreAddsLevel,
            l10n.moduleOpenScoreAddsOverall,
          ],
        ),
        const SizedBox(height: cardGap),
        ModuleFactsCard(
          title: l10n.moduleOpenScoreUsesTitle,
          icon: Icons.smartphone_rounded,
          facts: [
            l10n.moduleOpenScoreUsesData,
            l10n.moduleOpenScoreUsesNoPermission,
            l10n.moduleOpenScoreUsesStore,
            l10n.moduleOpenScoreUsesOverall,
          ],
        ),
        const SizedBox(height: cardGap),
        ModuleFactsCard(
          title: l10n.moduleBodyNeverTitle,
          icon: Icons.block_rounded,
          facts: [
            l10n.moduleOpenScoreNeverAge,
            l10n.moduleOpenScoreNeverStreak,
            l10n.moduleOpenScoreNeverMissing,
            l10n.dayScoreReceiptNever1,
            l10n.dayScoreReceiptNever2,
          ],
        ),
        const SizedBox(height: cardGap),
        DayScoreLink(
          key: OpenScoreModuleKeys.formula,
          title: l10n.formulaLink,
          caption: l10n.dayScoreFormulaLinkCaption,
          path: AppPaths.dayScoreFormula,
          push: true,
        ),
        SectionHeader(l10n.moduleOpenScoreDataTitle),
        BodyText(
          key: OpenScoreModuleKeys.stored,
          _storedText(l10n, tags: tags, unread: unread),
        ),
        if (customGoal) ...[
          const SizedBox(height: 4),
          BodyText(
            key: OpenScoreModuleKeys.goal,
            l10n.moduleOpenScoreDataGoal(goal),
          ),
        ],
        if (deletable) ...[
          const SizedBox(height: 12),
          OutlinedButton(
            key: OpenScoreModuleKeys.delete,
            style: OutlinedButton.styleFrom(
              foregroundColor: colors.heart,
              minimumSize: const Size.fromHeight(48),
            ),
            onPressed: () => unawaited(_delete(context, ref, tags)),
            child: Text(
              l10n.moduleOpenScoreDelete,
              textAlign: TextAlign.center,
            ),
          ),
        ],
        const SizedBox(height: 12),
        CaptionText(l10n.moduleOpenScoreFoot),
        const SizedBox(height: 24),
        if (on)
          SecondaryButton(
            key: OpenScoreModuleKeys.toggle,
            label: l10n.moduleOpenScoreTurnOff,
            onPressed: toggle,
          ),
        if (!on)
          ActionButton(
            key: OpenScoreModuleKeys.toggle,
            label: l10n.moduleOpenScoreTurnOn,
            onPressed: toggle,
          ),
        const SizedBox(height: 8),
        CaptionText(
          on ? l10n.moduleOpenScoreTurnOffNote : l10n.moduleBodyTurnOnNote,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  String _storedText(
    AppLocalizations l10n, {
    required int tags,
    required bool unread,
  }) {
    if (unread) return l10n.moduleOpenScoreDataUnread;
    if (tags > 0) return l10n.moduleOpenScoreDataCount(tags);
    return l10n.moduleOpenScoreDataEmpty;
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, int count) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _DeleteDialog(count: count),
    );
    if (confirmed != true || !context.mounted) return;
    final deleted = await clearOpenScoreData(ref);
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(
            deleted
                ? l10n.moduleOpenScoreDeleted
                : l10n.moduleOpenScoreDeleteFailed,
          ),
        ),
      );
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
      title: Text(l10n.moduleOpenScoreDeleteTitle),
      content: Text(l10n.moduleOpenScoreDeleteBody(count, weekGoalDefault)),
      actions: [
        TextButton(
          key: OpenScoreModuleKeys.deleteCancel,
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.settingsDeleteCancel),
        ),
        FilledButton(
          key: OpenScoreModuleKeys.deleteConfirm,
          style: FilledButton.styleFrom(
            backgroundColor: colors.heart,
            foregroundColor: colors.onAccent,
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.moduleOpenScoreDelete),
        ),
      ],
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/core/widgets/app_page.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/core/widgets/state_views.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/modules/presentation/module_widgets.dart';
import 'package:open_ring/features/modules/presentation/modules_screen.dart';
import 'package:open_ring/features/modules/presentation/offered_module.dart';
import 'package:open_ring/features/open_score/presentation/day_score_receipt_screen.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

abstract final class OpenScoreModuleKeys {
  static const state = Key('open_score_module_state');
  static const formula = Key('open_score_module_formula');
  static const toggle = Key('open_score_module_toggle');
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
}

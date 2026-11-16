import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/router/app_routes.dart';
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
import 'package:open_ring/l10n/generated/app_localizations.dart';

abstract final class EnergyModuleKeys {
  static const state = Key('energy_module_state');
  static const underage = Key('energy_module_underage');
  static const hidden = Key('energy_module_hidden');
  static const openBody = Key('energy_module_open_body');
  static const formula = Key('energy_module_formula');
  static const toggle = Key('energy_module_toggle');
}

enum _State { off, on, hidden, underage }

_State _stateOf({required bool? underage, required EnergyGate gate}) {
  if (underage ?? false) return _State.underage;
  return switch (gate) {
    EnergyGate.on => _State.on,
    EnergyGate.hidden => _State.hidden,
    EnergyGate.off || EnergyGate.underage => _State.off,
  };
}

String _stateLabel(AppLocalizations l10n, _State state) => switch (state) {
  _State.off => l10n.modulesOff,
  _State.on => l10n.modulesOn,
  _State.hidden => l10n.moduleEnergyOnHidden,
  _State.underage => l10n.moduleEnergyUnavailable,
};

class EnergyModuleScreen extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final format = MetricFormat.of(context);
    final l10n = format.l10n;
    final underage = ref.watch(energyUnderageProvider);
    final on = ref.watch(activeModulesProvider).contains(ModuleId.energy);
    final state = _stateOf(
      underage: underage,
      gate: ref.watch(energyGateProvider),
    );
    void toggle() =>
        unawaited(setModule(context, ref, OfferedModule.energy, on: !on));
    return AppPage(
      title: l10n.energyTitle,
      subtitle: l10n.moduleEnergyDetail,
      children: [
        ModuleStatePill(
          key: EnergyModuleKeys.state,
          on: state == _State.on,
          label: _stateLabel(l10n, state),
        ),
        const SizedBox(height: 16),
        if (state == _State.underage) ...[
          _Notice(
            key: EnergyModuleKeys.underage,
            icon: Icons.person_outline,
            title: l10n.moduleEnergyUnderageTitle,
            body: l10n.moduleEnergyUnderageBody(
              format.integer(energyAdultAge),
              l10n.profileTitle,
            ),
          ),
          const SizedBox(height: cardGap),
        ],
        if (state == _State.hidden) ...[
          _Notice(
            key: EnergyModuleKeys.hidden,
            icon: Icons.visibility_off_outlined,
            title: l10n.moduleEnergyHiddenTitle,
            body: l10n.moduleEnergyHiddenBody(
              l10n.moduleBodyName,
              l10n.tabToday,
            ),
            action: SecondaryButton(
              key: EnergyModuleKeys.openBody,
              label: l10n.moduleEnergyOpenBody(l10n.moduleBodyName),
              onPressed: () => context.go(AppPaths.settingsModuleBody),
            ),
          ),
          const SizedBox(height: cardGap),
        ],
        ModuleFactsCard(
          title: l10n.moduleBodyAddsTitle,
          icon: Icons.check_rounded,
          facts: [
            l10n.moduleEnergyAdds1(l10n.tabToday),
            l10n.moduleEnergyAdds2,
            l10n.moduleEnergyAdds3,
          ],
        ),
        const SizedBox(height: cardGap),
        ModuleFactsCard(
          title: l10n.moduleOpenScoreUsesTitle,
          icon: Icons.smartphone_rounded,
          facts: [
            l10n.moduleEnergyUses1(l10n.profileTitle),
            l10n.moduleEnergyUses2(l10n.moduleBodyName, l10n.profileTitle),
            l10n.moduleEnergyUses3,
            l10n.moduleEnergyUses4,
          ],
        ),
        const SizedBox(height: cardGap),
        ModuleFactsCard(
          title: l10n.moduleBodyNeverTitle,
          icon: Icons.block_rounded,
          facts: [
            l10n.energyNever1,
            l10n.energyNever2,
            l10n.energyNever3,
            l10n.energyNever4,
          ],
        ),
        const SizedBox(height: cardGap),
        DayScoreLink(
          key: EnergyModuleKeys.formula,
          title: l10n.formulaLink,
          caption: l10n.moduleEnergyFormulaCaption,
          path: AppPaths.energyFormula,
          push: true,
        ),
        const SizedBox(height: 12),
        CaptionText('${l10n.energyFixedNote} ${l10n.moduleEnergyAdultsOnly}'),
        const SizedBox(height: 24),
        // Only a known adult gets the button: not under 18, not while the
        // profile is still loading.
        if (underage == false) _Toggle(on: on, onPressed: toggle),
      ],
    );
  }
}

class _Toggle extends StatelessWidget {
  const new({required this.on, required this.onPressed});

  final bool on;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (on)
          SecondaryButton(
            key: EnergyModuleKeys.toggle,
            label: l10n.moduleEnergyTurnOff,
            onPressed: onPressed,
          ),
        if (!on)
          ActionButton(
            key: EnergyModuleKeys.toggle,
            label: l10n.moduleEnergyTurnOn,
            onPressed: onPressed,
          ),
        const SizedBox(height: 8),
        CaptionText(
          on ? l10n.moduleEnergyTurnOffNote : l10n.moduleBodyTurnOnNote,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _Notice extends StatelessWidget {
  const new({
    required this.icon,
    required this.title,
    required this.body,
    this.action,
    super.key,
  });

  final IconData icon;
  final String title;
  final String body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return MetricCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              ExcludeSemantics(child: Icon(icon, size: 20)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: theme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          BodyText(body),
          if (action case final action?) ...[
            const SizedBox(height: 12),
            action,
          ],
        ],
      ),
    );
  }
}

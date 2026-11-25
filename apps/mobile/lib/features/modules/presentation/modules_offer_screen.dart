import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/core/widgets/state_views.dart';
import 'package:open_ring/features/energy/application/energy_gate.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';
import 'package:open_ring/features/modules/presentation/offered_module.dart';
import 'package:open_ring/features/onboarding/presentation/onboarding_page.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

abstract final class ModulesOfferKeys {
  static const body = Key('modules_offer_body');
  static const openScore = Key('modules_offer_openScore');
  static const energy = Key('modules_offer_energy');
  static const done = Key('modules_offer_done');

  static Key module(OfferedModule module) =>
      Key('modules_offer_${module.name}');
}

class ModulesOfferScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<ModulesOfferScreen> createState() => _ModulesOfferScreenState();
}

class _ModulesOfferScreenState extends ConsumerState<ModulesOfferScreen> {
  final _picked = <OfferedModule, bool>{};
  bool _busy = false;

  // Energy is offered to a known adult only, and a module that is not
  // offered keeps whatever is stored for it. Goals waits for the Modules
  // screen, since Today shows nothing for it until a goal is chosen.
  List<OfferedModule> get _offered {
    final adult = ref.watch(energyUnderageProvider) == false;
    return [
      for (final module in OfferedModule.values)
        if (_offers(module, adult: adult)) module,
    ];
  }

  bool _offers(OfferedModule module, {required bool adult}) => switch (module) {
    OfferedModule.goals || OfferedModule.ai => false,
    OfferedModule.energy => adult,
    _ => true,
  };

  Future<void> _done(
    List<OfferedModule> offered,
    List<OfferedModule> on,
  ) async {
    setState(() => _busy = true);
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    final modules = ref.read(enabledModulesProvider.notifier);
    try {
      for (final module in offered) {
        await (on.contains(module)
            ? modules.enable(module.id)
            : modules.disable(module.id));
      }
    } on Object {
      if (mounted) setState(() => _busy = false);
      messenger
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(l10n.syncErrorSaving)));
      return;
    }
    router.go(AppTab.today.path);
    messenger
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(_message(l10n, on))));
  }

  String _message(AppLocalizations l10n, List<OfferedModule> on) =>
      switch (on) {
        [] => l10n.onboardingModulesNone,
        [final only] => only.turnedOn(l10n),
        _ => l10n.modulesTurnedOn,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final enabled = ref.watch(enabledModulesProvider).value ?? const {};
    final offered = _offered;
    final on = [
      for (final module in offered)
        if (_picked[module] ?? enabled.contains(module.id)) module,
    ];
    return OnboardingPage(
      step: onboardingSteps,
      title: l10n.onboardingModulesTitle,
      intro: l10n.onboardingModulesIntro,
      children: [
        for (final module in offered) ...[
          _Offer(
            module: module,
            on: on.contains(module),
            onChanged: (value) => setState(() => _picked[module] = value),
          ),
          const SizedBox(height: 12),
        ],
        CaptionText(l10n.onboardingModulesFoot),
        const SizedBox(height: 24),
        ActionButton(
          key: ModulesOfferKeys.done,
          label: on.isEmpty
              ? l10n.onboardingModulesSkip
              : l10n.onboardingModulesContinue(on.length),
          onPressed: _busy ? null : () => unawaited(_done(offered, on)),
        ),
        const SizedBox(height: 10),
        CaptionText(l10n.onboardingModulesLater, textAlign: TextAlign.center),
      ],
    );
  }
}

class _Offer extends StatelessWidget {
  const new({required this.module, required this.on, required this.onChanged});

  final OfferedModule module;
  final bool on;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final l10n = AppLocalizations.of(context);
    return MetricCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: SwitchListTile(
        key: ModulesOfferKeys.module(module),
        value: on,
        onChanged: onChanged,
        contentPadding: EdgeInsets.zero,
        secondary: Icon(module.icon, color: colors.textPrimary),
        title: Text(
          module.title(l10n),
          style: theme.textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: CaptionText(module.detail(l10n)),
        activeThumbColor: colors.background,
        activeTrackColor: colors.activity,
        inactiveThumbColor: colors.textSecondary,
        inactiveTrackColor: colors.surfaceInner,
      ),
    );
  }
}

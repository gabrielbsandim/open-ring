import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/core/widgets/state_views.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/onboarding/presentation/onboarding_page.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

abstract final class ModulesOfferKeys {
  static const body = Key('modules_offer_body');
  static const done = Key('modules_offer_done');
}

class ModulesOfferScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<ModulesOfferScreen> createState() => _ModulesOfferScreenState();
}

class _ModulesOfferScreenState extends ConsumerState<ModulesOfferScreen> {
  bool? _picked;
  bool _busy = false;

  Future<void> _done({required bool body}) async {
    setState(() => _busy = true);
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    final modules = ref.read(enabledModulesProvider.notifier);
    if (body) await modules.enable(ModuleId.body);
    if (!body) await modules.disable(ModuleId.body);
    router.go(AppTab.today.path);
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(
            body ? l10n.moduleBodyTurnedOn : l10n.onboardingModulesNone,
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final l10n = AppLocalizations.of(context);
    final on =
        ref.watch(enabledModulesProvider).value?.contains(ModuleId.body) ??
        false;
    final body = _picked ?? on;
    return OnboardingPage(
      step: onboardingSteps,
      title: l10n.onboardingModulesTitle,
      intro: l10n.onboardingModulesIntro,
      children: [
        MetricCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: SwitchListTile(
            key: ModulesOfferKeys.body,
            value: body,
            onChanged: (value) => setState(() => _picked = value),
            contentPadding: EdgeInsets.zero,
            secondary: Icon(
              Icons.monitor_weight_outlined,
              color: colors.textPrimary,
            ),
            title: Text(
              l10n.moduleBodyName,
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: CaptionText(l10n.moduleBodyDetail),
            activeThumbColor: colors.background,
            activeTrackColor: colors.activity,
            inactiveThumbColor: colors.textSecondary,
            inactiveTrackColor: colors.surfaceInner,
          ),
        ),
        const SizedBox(height: 12),
        CaptionText(l10n.onboardingModulesFoot),
        const SizedBox(height: 24),
        ActionButton(
          key: ModulesOfferKeys.done,
          label: body
              ? l10n.onboardingModulesWithBody
              : l10n.onboardingModulesSkip,
          onPressed: _busy ? null : () => unawaited(_done(body: body)),
        ),
        const SizedBox(height: 10),
        CaptionText(l10n.onboardingModulesLater, textAlign: TextAlign.center),
      ],
    );
  }
}

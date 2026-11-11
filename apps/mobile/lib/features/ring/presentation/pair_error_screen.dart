import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/core/widgets/state_views.dart';
import 'package:open_ring/features/onboarding/application/onboarding_controller.dart';
import 'package:open_ring/features/onboarding/presentation/onboarding_page.dart';
import 'package:open_ring/features/ring/application/pair_controller.dart';
import 'package:open_ring/features/ring/application/pair_state.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

abstract final class PairErrorKeys {
  static const retry = Key('pair_error_retry');
  static const openSettings = Key('pair_error_open_settings');
  static const modelToggle = Key('pair_error_model_toggle');
}

typedef _Tip = ({String title, String body});

class PairErrorScreen extends ConsumerWidget {
  const new({required this.failure, this.flow = PairFlow.ring, super.key});

  final PairFailure failure;
  final PairFlow flow;

  static PairFailure parse(String? reason) =>
      PairFailure.values.asNameMap()[reason] ?? PairFailure.notFound;

  void _retry(BuildContext context, WidgetRef ref) {
    if (!context.canPop()) return context.go(flow.path);
    final controller = ref.read(pairProvider.notifier);
    context.pop();
    unawaited(controller.scan());
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final retryStep = (
      title: l10n.pairRetryStepTitle,
      body: l10n.pairRetryStepBody,
    );
    final (
      IconData icon,
      String title,
      String intro,
      List<_Tip> tips,
    ) = switch (failure) {
      PairFailure.notFound => (
        Icons.search_off_rounded,
        l10n.pairNotFoundTitle,
        l10n.pairNotFoundBody,
        [
          (
            title: l10n.pairNotFoundChargeTitle,
            body: l10n.pairNotFoundChargeBody,
          ),
          (
            title: l10n.pairNotFoundUnpairTitle,
            body: l10n.pairNotFoundUnpairBody,
          ),
          (
            title: l10n.pairNotFoundCloseTitle,
            body: l10n.pairNotFoundCloseBody,
          ),
          (
            title: l10n.pairNotFoundBluetoothTitle,
            body: l10n.pairNotFoundBluetoothBody,
          ),
        ],
      ),
      PairFailure.permissionDenied => (
        Icons.block_rounded,
        l10n.pairDeniedTitle,
        l10n.pairDeniedBody,
        [
          (
            title: l10n.pairDeniedSettingsTitle,
            body: l10n.pairDeniedSettingsBody,
          ),
          (title: l10n.pairDeniedAllowTitle, body: l10n.pairDeniedAllowBody),
          retryStep,
        ],
      ),
      PairFailure.bluetoothOff => (
        Icons.bluetooth_disabled_rounded,
        l10n.pairOffTitle,
        l10n.pairOffBody,
        [
          (title: l10n.pairOffTurnOnTitle, body: l10n.pairOffTurnOnBody),
          retryStep,
        ],
      ),
    };
    final denied = failure == PairFailure.permissionDenied;
    return OnboardingPage(
      label: l10n.pairHeader,
      hero: HeroBadge(icon: icon, accent: colors.stress),
      title: title,
      intro: intro,
      children: [
        MetricCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (index, tip) in tips.indexed)
                NumberedTip(
                  number: index + 1,
                  title: tip.title,
                  body: tip.body,
                ),
            ],
          ),
        ),
        if (failure == PairFailure.notFound) ...[
          const SizedBox(height: cardGap),
          const _ModelNote(),
        ],
        const SizedBox(height: 24),
        if (denied) ...[
          PrimaryAction(
            key: PairErrorKeys.openSettings,
            label: l10n.permissionsOpenSettings,
            onPressed: () =>
                unawaited(ref.read(appPermissionsProvider).openSettings()),
          ),
          const SizedBox(height: cardGap),
          SecondaryButton(
            key: PairErrorKeys.retry,
            label: l10n.pairErrorRetry,
            onPressed: () => _retry(context, ref),
          ),
        ],
        if (!denied)
          PrimaryAction(
            key: PairErrorKeys.retry,
            label: l10n.pairErrorRetry,
            onPressed: () => _retry(context, ref),
          ),
      ],
    );
  }
}

class _ModelNote extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    return MetricCard(
      padding: EdgeInsets.zero,
      child: ExpansionTile(
        key: PairErrorKeys.modelToggle,
        shape: const Border(),
        collapsedShape: const Border(),
        iconColor: colors.textSecondary,
        collapsedIconColor: colors.textSecondary,
        title: Text(l10n.pairModelToggle),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BodyText(l10n.pairModelTested),
          const SizedBox(height: 8),
          BodyText(l10n.pairModelOthers),
          const SizedBox(height: 8),
          BodyText(l10n.pairModelBrands),
        ],
      ),
    );
  }
}

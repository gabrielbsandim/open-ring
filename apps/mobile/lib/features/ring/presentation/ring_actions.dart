import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/core/widgets/state_views.dart';
import 'package:open_ring/features/onboarding/presentation/onboarding_page.dart';
import 'package:open_ring/features/ring/application/find_ring.dart';
import 'package:open_ring/features/ring/application/ring_sync_controller.dart';
import 'package:open_ring/features/ring/application/unpair_ring.dart';
import 'package:open_ring/features/ring/presentation/ring_cards.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';
import 'package:ring_driver/ring_driver.dart';

class RingActions extends ConsumerWidget {
  const new({required this.name, this.offline = false, super.key});

  final String name;
  final bool offline;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = AppColors.of(context);
    final l10n = MetricFormat.of(context).l10n;
    final canFind =
        !offline &&
        ref
            .watch(smartRingDriverProvider)
            .capabilities
            .contains(RingCapability.findDevice);
    final find = ref.watch(findRingControllerProvider);
    final unpairing = ref.watch(unpairControllerProvider);
    final status = _findStatus(l10n, find);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (canFind) ...[
              Expanded(
                child: SecondaryButton(
                  key: RingKeys.find,
                  label: find == FindRingPhase.finding
                      ? l10n.ringFinding
                      : l10n.ringFind,
                  onPressed: find == FindRingPhase.finding
                      ? null
                      : () => unawaited(
                          ref.read(findRingControllerProvider.notifier).find(),
                        ),
                ),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: SecondaryButton(
                key: RingKeys.unpair,
                label: offline ? l10n.ringUnpairOffline : l10n.ringUnpair,
                color: colors.heart,
                onPressed: unpairing
                    ? null
                    : () => unawaited(_confirmUnpair(context, ref)),
              ),
            ),
          ],
        ),
        if (status != null)
          Semantics(
            liveRegion: true,
            child: Padding(
              key: RingKeys.findStatus,
              padding: const EdgeInsets.only(top: 8),
              child: CaptionText(status),
            ),
          ),
      ],
    );
  }

  static String? _findStatus(AppLocalizations l10n, FindRingPhase phase) =>
      switch (phase) {
        FindRingPhase.idle || FindRingPhase.finding => null,
        FindRingPhase.lit => l10n.ringFindLit,
        FindRingPhase.busy => l10n.ringFindBusy,
        FindRingPhase.failed => l10n.ringFindFailed,
      };

  Future<void> _confirmUnpair(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _UnpairDialog(name: name),
    );
    if (confirmed != true || !context.mounted) return;
    // The paired body unmounts once the ring is forgotten, so the router and
    // messenger are taken before the await.
    final router = GoRouter.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    final unpaired = await ref.read(unpairControllerProvider.notifier).unpair();
    if (!unpaired) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.ringUnpairFailed)));
      return;
    }
    messenger.showSnackBar(SnackBar(content: Text(l10n.ringUnpairedNote)));
    router.go(AppPaths.pair);
  }
}

class _UnpairDialog extends StatelessWidget {
  const new({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    return AlertDialog(
      scrollable: true,
      title: Text(l10n.ringUnpairTitle(name)),
      content: Text(l10n.ringUnpairBody(healthPlatformName())),
      actions: [
        TextButton(
          key: RingKeys.unpairCancel,
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.ringUnpairCancel),
        ),
        FilledButton(
          key: RingKeys.unpairConfirm,
          style: FilledButton.styleFrom(
            backgroundColor: colors.heart,
            foregroundColor: colors.onAccent,
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.ringUnpair),
        ),
      ],
    );
  }
}

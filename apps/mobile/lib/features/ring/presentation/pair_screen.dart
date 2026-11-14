import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/records/health_record_kind.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/core/widgets/state_views.dart';
import 'package:open_ring/features/health_sync/application/health_read_controller.dart';
import 'package:open_ring/features/onboarding/application/onboarding_controller.dart';
import 'package:open_ring/features/onboarding/presentation/onboarding_page.dart';
import 'package:open_ring/features/ring/application/pair_controller.dart';
import 'package:open_ring/features/ring/application/pair_state.dart';
import 'package:open_ring/features/ring/domain/discovered_device.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

abstract final class PairKeys {
  static const search = Key('pair_search');
  static const searchAgain = Key('pair_search_again');
  static const notFound = Key('pair_not_found');
  static const connectFailed = Key('pair_connect_failed');
  static const saveFailed = Key('pair_save_failed');
  static const paired = Key('pair_paired');
  static const continueAction = Key('pair_continue');
  static const withoutRing = Key('pair_without_ring');
  static const withoutRingRow = Key('pair_without_ring_row');

  static Key device(String id) => Key('pair_device_$id');
}

const testedModel = 'R09';

String ringTitle(String? model) => 'COLMI ${model ?? ''}'.trim();

// A ring that advertises no model (the R09 says "COLMI Ring 2") is named as it
// advertises; its model is only known after the first sync.
String deviceTitle(DiscoveredDevice device) => switch (device.colmiModel) {
  final model? => ringTitle(model),
  null => PairController.identityOf(device).name,
};

String supportLabel(AppLocalizations l10n, String? model) => switch (model) {
  null => l10n.pairModelAfterPairing,
  testedModel => l10n.pairCompatible,
  _ => l10n.pairUntested,
};

class PairScreen extends ConsumerWidget {
  const new({this.flow = PairFlow.ring, super.key});

  final PairFlow flow;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final state = ref.watch(pairProvider);
    final controller = ref.read(pairProvider.notifier);
    ref.listen(pairProvider, (previous, next) {
      final failure = next.failure;
      if (failure != null && failure != previous?.failure) {
        unawaited(context.push(flow.errorPath(failure.name)));
      }
      if (next.phase != PairPhase.paired) return;
      if (previous?.phase == PairPhase.paired) return;
      unawaited(ref.read(onboardingProvider.notifier).complete());
    });
    final (title, intro) = switch (state.phase) {
      PairPhase.idle => (l10n.pairIdleTitle, l10n.pairIdleBody),
      PairPhase.scanning when state.scanActive => (
        l10n.pairScanningTitle,
        l10n.pairScanningBody,
      ),
      PairPhase.scanning => (l10n.pairPickTitle, l10n.pairScanningBody),
      PairPhase.connecting => (
        l10n.pairConnectingTitle,
        l10n.pairConnectingBody,
      ),
      PairPhase.paired => (l10n.pairDoneTitle, l10n.pairDoneBody),
    };
    final done = state.phase == PairPhase.paired;
    final offerWithoutRing =
        flow == PairFlow.onboarding &&
        offersWithoutRing() &&
        state.phase != PairPhase.paired;
    return OnboardingPage(
      step: flow.step,
      label: l10n.pairHeader,
      hero: HeroBadge(
        icon: done ? Icons.check_rounded : Icons.bluetooth_searching_rounded,
        accent: done ? colors.activity : colors.oxygen,
      ),
      title: title,
      intro: intro,
      children: [
        ...switch (state.phase) {
          PairPhase.idle => _idle(l10n, () => unawaited(controller.scan())),
          PairPhase.scanning || PairPhase.connecting => [
            _DeviceList(
              state: state,
              onPair: (device) => unawaited(controller.pair(device)),
              onSearchAgain: () => unawaited(controller.scan()),
              onNotFound: () => unawaited(
                context.push(flow.errorPath(PairFailure.notFound.name)),
              ),
            ),
          ],
          PairPhase.paired => [
            _PairedCard(state: state),
            const SizedBox(height: 20),
            PrimaryAction(
              key: PairKeys.continueAction,
              label: l10n.onboardingContinue,
              onPressed: () => context.go(flow.syncPath),
            ),
          ],
        },
        // Keyed and kept through connecting, so a phase change mid-run moves
        // the action instead of replacing it and dropping the run.
        if (offerWithoutRing)
          _WithoutRingAction(
            key: PairKeys.withoutRingRow,
            connecting: state.phase == PairPhase.connecting,
          ),
      ],
    );
  }

  static List<Widget> _idle(AppLocalizations l10n, VoidCallback onSearch) => [
    NumberedTip(number: 1, body: l10n.pairTipCharge),
    NumberedTip(number: 2, body: l10n.pairTipUnpair),
    NumberedTip(number: 3, body: l10n.pairTipClose),
    const SizedBox(height: 20),
    PrimaryAction(
      key: PairKeys.search,
      label: l10n.pairSearch,
      onPressed: onSearch,
    ),
    const SizedBox(height: 10),
    CaptionText(l10n.pairSearchNote, textAlign: TextAlign.center),
    const SizedBox(height: 4),
    CaptionText(l10n.pairSupportNote, textAlign: TextAlign.center),
  ];
}

class _DeviceList extends StatelessWidget {
  const new({
    required this.state,
    required this.onPair,
    required this.onSearchAgain,
    required this.onNotFound,
  });

  final PairState state;
  final ValueChanged<DiscoveredDevice> onPair;
  final VoidCallback onSearchAgain;
  final VoidCallback onNotFound;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final connecting = state.phase == PairPhase.connecting;
    final target = state.target;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CaptionText(l10n.pairFoundNearby),
        const SizedBox(height: 8),
        if (state.devices.isEmpty)
          Semantics(liveRegion: true, child: BodyText(l10n.pairLooking)),
        for (final device in state.devices) ...[
          _RingTile(
            device: device,
            connecting: connecting && target?.id == device.id,
            onTap: connecting ? null : () => onPair(device),
          ),
          const SizedBox(height: cardGap),
        ],
        if (state.connectFailed && target != null) ...[
          InfoNote(
            key: PairKeys.connectFailed,
            icon: Icons.error_outline_rounded,
            accent: colors.heart,
            text: l10n.pairConnectFailed(target.name),
            live: true,
          ),
          const SizedBox(height: cardGap),
        ],
        if (state.saveFailed && target != null) ...[
          InfoNote(
            key: PairKeys.saveFailed,
            icon: Icons.error_outline_rounded,
            accent: colors.heart,
            text: l10n.pairSaveFailed(target.name),
            live: true,
          ),
          const SizedBox(height: cardGap),
        ],
        if (!state.scanActive && !connecting) ...[
          SecondaryButton(
            key: PairKeys.searchAgain,
            label: l10n.pairSearchAgain,
            onPressed: onSearchAgain,
          ),
          const SizedBox(height: 4),
        ],
        QuietAction(
          key: PairKeys.notFound,
          label: l10n.pairNotFoundLink,
          onPressed: connecting ? null : onNotFound,
        ),
      ],
    );
  }
}

class _RingTile extends StatelessWidget {
  const new({
    required this.device,
    required this.connecting,
    required this.onTap,
  });

  final DiscoveredDevice device;
  final bool connecting;
  final VoidCallback? onTap;

  static String signal(AppLocalizations l10n, DiscoveredDevice device) {
    if (device.heldBySystem) return l10n.pairAlreadyBonded;
    if (device.rssi >= -60) return l10n.pairSignalStrong;
    if (device.rssi >= -80) return l10n.pairSignalMedium;
    return l10n.pairSignalWeak;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final theme = Theme.of(context);
    final model = device.colmiModel;
    final support = supportLabel(l10n, model);
    final detail = model == null ? support : '${device.name} · $support';
    final status = connecting ? l10n.pairConnectingTitle : signal(l10n, device);
    return Semantics(
      button: true,
      enabled: onTap != null,
      child: MetricCard(
        key: PairKeys.device(device.id),
        onTap: onTap,
        child: Row(
          children: [
            Icon(Icons.radio_button_checked_rounded, color: colors.oxygen),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    deviceTitle(device),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  CaptionText(detail),
                  CaptionText(
                    status,
                    color: device.heldBySystem || connecting
                        ? colors.textSecondary
                        : colors.textLabel,
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: colors.textLabel),
          ],
        ),
      ),
    );
  }
}

class _PairedCard extends StatelessWidget {
  const new({required this.state});

  final PairState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final target = state.target;
    final name = target == null ? ringTitle(null) : deviceTitle(target);
    return Semantics(
      liveRegion: true,
      child: MetricCard(
        key: PairKeys.paired,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.check_circle_rounded, color: colors.activity),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.pairPaired(name),
                    style: Theme.of(context).textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  BodyText(l10n.pairPairedBody),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WithoutRingAction extends ConsumerStatefulWidget {
  const new({required this.connecting, super.key});

  final bool connecting;

  @override
  ConsumerState<_WithoutRingAction> createState() => _WithoutRingActionState();
}

class _WithoutRingActionState extends ConsumerState<_WithoutRingAction> {
  static const List<HealthRecordKind> _kinds = [
    HealthRecordKind.sleep,
    HealthRecordKind.workout,
  ];

  bool _busy = false;

  Future<void> _continue() async {
    setState(() => _busy = true);
    final router = GoRouter.of(context);
    for (final kind in _kinds) {
      await _enable(kind);
      if (!mounted) return;
    }
    await ref.read(onboardingProvider.notifier).complete();
    router.go(AppTab.today.path);
  }

  // A refused or failed read still finishes onboarding: reads can be turned
  // on later from the data sources settings.
  Future<void> _enable(HealthRecordKind kind) async {
    try {
      await ref
          .read(healthReadsProvider(kind).notifier)
          .setEnabled(enabled: true);
    } on Object catch (error) {
      debugPrint('Reading ${kind.name} was not turned on: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 20),
        SecondaryButton(
          key: PairKeys.withoutRing,
          label: l10n.pairWithoutRing,
          onPressed: _busy || widget.connecting
              ? null
              : () => unawaited(_continue()),
        ),
        const SizedBox(height: 4),
        CaptionText(l10n.pairWithoutRingNote, textAlign: TextAlign.center),
      ],
    );
  }
}

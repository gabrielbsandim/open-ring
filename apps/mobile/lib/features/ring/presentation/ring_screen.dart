import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/core/widgets/app_page.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/core/widgets/state_views.dart';
import 'package:open_ring/features/ring/application/auto_measurements_controller.dart';
import 'package:open_ring/features/ring/application/ring_sync_controller.dart';
import 'package:open_ring/features/ring/application/ring_sync_state.dart';
import 'package:open_ring/features/ring/presentation/auto_measurements_card.dart';
import 'package:open_ring/features/ring/presentation/ring_actions.dart';
import 'package:open_ring/features/ring/presentation/ring_cards.dart';
import 'package:open_ring/features/ring/presentation/sync_status_banner.dart';
import 'package:open_ring/features/today/application/today_providers.dart';
import 'package:open_ring/features/today/application/today_view.dart';
import 'package:open_ring/features/today/domain/ring_status_reader.dart';

class RingScreen extends ConsumerWidget {
  const new({super.key});

  static const settingsKey = Key('ring_settings');
  static const protocolLabKey = Key('ring_protocol_lab');
  static const pairKey = Key('ring_pair');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = MetricFormat.of(context).l10n;
    final status = ref.watch(ringStatusProvider);
    final paired = status.value?.paired ?? false;
    return AppPage(
      title: l10n.tabRing,
      onRefresh: paired ? () => refreshRing(ref) : null,
      actions: [
        if (kDebugMode)
          IconButton(
            key: protocolLabKey,
            tooltip: l10n.labOpen,
            icon: const Icon(Icons.science_rounded),
            onPressed: () => context.go(AppPaths.protocolLab),
          ),
        IconButton(
          key: settingsKey,
          tooltip: l10n.settingsTitle,
          icon: const Icon(Icons.settings_rounded),
          onPressed: () => context.go(AppPaths.settings),
        ),
      ],
      children: [
        AsyncBody(
          value: status,
          builder: (ring) =>
              ring.paired ? _PairedBody(ring: ring) : const _UnpairedBody(),
        ),
      ],
    );
  }
}

class _UnpairedBody extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final l10n = MetricFormat.of(context).l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        EmptyStateCard(
          icon: Icons.radio_button_unchecked_rounded,
          accent: colors.oxygen,
          title: l10n.ringUnpairedTitle,
          message: l10n.ringEmpty,
          actionLabel: l10n.todayPairAction,
          actionKey: RingScreen.pairKey,
          onAction: () => context.go(AppPaths.pair),
        ),
        const SizedBox(height: 16),
        CaptionText(l10n.ringSupportNote),
      ],
    );
  }
}

class _PairedBody extends ConsumerWidget {
  const new({required this.ring});

  final RingStatus ring;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = MetricFormat.of(context).l10n;
    final now = ref.watch(clockProvider)();
    final sync = ref.watch(ringSyncProvider);
    final freshness = freshnessOf(ring, now);
    final offline =
        !sync.syncing &&
        (freshness == SyncFreshness.stale ||
            freshness == SyncFreshness.neverSynced);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RingDeviceCard(
          ring: ring,
          now: now,
          connection: _connection(sync, offline: offline),
        ),
        const SizedBox(height: cardGap),
        if (offline) ...[
          RingOfflineCard(
            ring: ring,
            now: now,
            onSearchAgain: () => unawaited(refreshRing(ref)),
            onBatterySettings: defaultTargetPlatform == TargetPlatform.android
                ? () => unawaited(ref.read(batterySettingsProvider).open())
                : null,
          ),
          const SizedBox(height: cardGap),
        ],
        RingSyncCard(
          ring: ring,
          now: now,
          sync: sync,
          onSync: () => unawaited(refreshRing(ref)),
        ),
        const SizedBox(height: cardGap),
        const SyncIntervalCard(),
        const SizedBox(height: cardGap),
        const AutoMeasurementsCard(),
        const HealthLinkCard(),
        const SizedBox(height: cardGap),
        RingActions(name: ring.name ?? l10n.tabRing, offline: offline),
      ],
    );
  }

  static RingConnection _connection(
    RingSyncState sync, {
    required bool offline,
  }) {
    final step = sync.progress?.step;
    if (step == SyncStep.connecting) return RingConnection.connecting;
    if (step != null) return RingConnection.connected;
    if (offline) return RingConnection.offline;
    return RingConnection.idle;
  }
}

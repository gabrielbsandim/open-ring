import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/core/widgets/charts.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/core/widgets/state_views.dart';
import 'package:open_ring/features/ring/application/ring_sync_state.dart';
import 'package:open_ring/features/ring/application/sync_interval_controller.dart';
import 'package:open_ring/features/ring/domain/auto_measurements.dart';
import 'package:open_ring/features/ring/domain/sync_interval.dart';
import 'package:open_ring/features/ring/presentation/sync_status_banner.dart';
import 'package:open_ring/features/today/domain/ring_status_reader.dart';

const lowBatteryPercent = 20;

enum RingConnection { connecting, connected, idle, offline }

abstract final class RingKeys {
  static const device = Key('ring_device');
  static const connection = Key('ring_connection');
  static const offline = Key('ring_offline');
  static const sync = Key('ring_sync');
  static const syncNow = Key('ring_sync_now');
  static const lastSync = Key('ring_last_sync');
  static const interval = Key('ring_interval');
  static const searchAgain = Key('ring_search_again');
  static const batterySettings = Key('ring_battery_settings');
  static const measurements = Key('ring_measurements');
  static const find = Key('ring_find');
  static const findStatus = Key('ring_find_status');
  static const unpair = Key('ring_unpair');
  static const unpairConfirm = Key('ring_unpair_confirm');
  static const unpairCancel = Key('ring_unpair_cancel');

  static Key measurement(AutoMeasurement measurement) =>
      Key('ring_measurement_${measurement.name}');

  static Key intervalOption(SyncInterval interval) =>
      Key('ring_interval_${interval.minutes}');
}

class RingDeviceCard extends StatelessWidget {
  const new({
    required this.ring,
    required this.now,
    required this.connection,
    super.key,
  });

  final RingStatus ring;
  final DateTime now;
  final RingConnection connection;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final format = MetricFormat.of(context);
    final l10n = format.l10n;
    final (dot, state) = switch (connection) {
      RingConnection.connecting => (colors.oxygen, l10n.ringConnecting),
      RingConnection.connected => (colors.activity, l10n.ringConnected),
      RingConnection.idle => (colors.textLabel, l10n.ringIdle),
      RingConnection.offline => (colors.heart, l10n.ringDisconnected),
    };
    final seen = _lastSeen(format);
    return MetricCard(
      key: RingKeys.device,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.radio_button_checked_rounded,
            size: 40,
            color: colors.oxygen,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    ring.name ?? l10n.tabRing,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                MergeSemantics(
                  key: RingKeys.connection,
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: dot,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: CaptionText(state, color: colors.textSecondary),
                      ),
                    ],
                  ),
                ),
                if (seen != null) ...[
                  const SizedBox(height: 4),
                  CaptionText(seen),
                ],
                if (ring.batteryPercent case final percent?) ...[
                  const SizedBox(height: 10),
                  _Battery(percent: percent, charging: ring.batteryCharging),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String? _lastSeen(MetricFormat format) {
    if (connection != RingConnection.offline) return null;
    final last = ring.lastSyncAt;
    if (last == null) return format.l10n.ringNeverSynced;
    final time = format.clockOrDay(last, now);
    final percent = ring.batteryPercent;
    if (percent == null) return format.l10n.ringLastSeen(time);
    return format.l10n.ringLastSeenBattery(time, percent);
  }
}

class _Battery extends StatelessWidget {
  const new({required this.percent, required this.charging});

  final int percent;
  final bool? charging;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final format = MetricFormat.of(context);
    final l10n = format.l10n;
    final low = percent <= lowBatteryPercent;
    return Semantics(
      container: true,
      label: charging ?? false
          ? l10n.ringBatteryChargingSemantics(percent)
          : l10n.ringBatterySemantics(percent),
      excludeSemantics: true,
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 4,
        children: [
          SizedBox(
            width: 64,
            child: ProgressBar(
              value: percent / 100,
              height: 8,
              color: low ? colors.heart : colors.activity,
            ),
          ),
          Text(
            format.percent(percent.toDouble()),
            style: numberStyle(theme.textTheme.bodyMedium),
          ),
          if (charging ?? false) CaptionText(l10n.ringCharging),
        ],
      ),
    );
  }
}

class RingOfflineCard extends StatelessWidget {
  const new({
    required this.ring,
    required this.now,
    required this.onSearchAgain,
    this.onBatterySettings,
    super.key,
  });

  final RingStatus ring;
  final DateTime now;
  final VoidCallback onSearchAgain;
  final VoidCallback? onBatterySettings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final format = MetricFormat.of(context);
    final l10n = format.l10n;
    final last = ring.lastSyncAt;
    final percent = ring.batteryPercent;
    final battery = onBatterySettings;
    final steps = [
      (
        l10n.ringTryCharge,
        percent == null
            ? l10n.ringTryChargeDetail
            : l10n.ringTryChargeBattery(percent),
        null,
      ),
      (l10n.ringTryClose, l10n.ringTryCloseDetail, null),
      (
        l10n.ringTryBackground,
        l10n.ringTryBackgroundDetail,
        battery == null
            ? null
            : _LinkButton(
                key: RingKeys.batterySettings,
                label: l10n.ringBatterySettings,
                onPressed: battery,
              ),
      ),
      (l10n.ringTryOtherApp, l10n.ringTryOtherAppDetail, null),
    ];
    return Column(
      key: RingKeys.offline,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BodyText(
          last == null
              ? l10n.todayFirstSync
              : l10n.ringOfflineHistory(format.clockOrDay(last, now)),
        ),
        const SizedBox(height: cardGap),
        MetricCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: Text(
                  l10n.ringTryTitle,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              for (var i = 0; i < steps.length; i++)
                _TryStep(
                  number: format.integer(i + 1),
                  title: steps[i].$1,
                  detail: steps[i].$2,
                  action: steps[i].$3,
                ),
            ],
          ),
        ),
        const SizedBox(height: cardGap),
        ActionButton(
          key: RingKeys.searchAgain,
          label: l10n.ringSearchAgain,
          onPressed: onSearchAgain,
        ),
      ],
    );
  }
}

class _LinkButton extends StatelessWidget {
  const new({required this.label, required this.onPressed, super.key});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return TextButton(
      style: TextButton.styleFrom(
        foregroundColor: colors.sleep,
        minimumSize: const Size(48, 48),
        padding: EdgeInsets.zero,
        alignment: AlignmentDirectional.centerStart,
        textStyle: const TextStyle(
          fontWeight: FontWeight.w600,
          decoration: TextDecoration.underline,
        ),
      ),
      onPressed: onPressed,
      child: Text(label),
    );
  }
}

class _TryStep extends StatelessWidget {
  const new({
    required this.number,
    required this.title,
    required this.detail,
    this.action,
  });

  final String number;
  final String title;
  final String detail;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final step = MergeSemantics(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors.surfaceInner,
              shape: BoxShape.circle,
              border: Border.all(color: colors.strongBorder),
            ),
            child: Text(number, style: numberStyle(theme.textTheme.labelSmall)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                CaptionText(detail),
              ],
            ),
          ),
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          step,
          if (action case final action?)
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 36),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: action,
              ),
            ),
        ],
      ),
    );
  }
}

class RingSyncCard extends StatelessWidget {
  const new({
    required this.ring,
    required this.now,
    required this.sync,
    required this.onSync,
    super.key,
  });

  final RingStatus ring;
  final DateTime now;
  final RingSyncState sync;
  final VoidCallback onSync;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final format = MetricFormat.of(context);
    final l10n = format.l10n;
    final last = ring.lastSyncAt;
    final status = SyncStatusView(state: sync, onRetry: onSync);
    return MetricCard(
      key: RingKeys.sync,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AccentTitle(title: l10n.ringSyncTitle, accent: colors.oxygen),
          const SizedBox(height: 4),
          Text(
            last == null
                ? l10n.ringNeverSynced
                : l10n.todaySynced(format.clockOrDay(last, now)),
            key: RingKeys.lastSync,
            style: numberStyle(
              Theme.of(context).textTheme.bodyMedium,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: 14),
          ActionButton(
            key: RingKeys.syncNow,
            label: sync.syncing ? l10n.ringSyncing : l10n.ringSyncNow,
            onPressed: sync.syncing ? null : onSync,
          ),
          if (status.visible) ...[const SizedBox(height: 14), status],
          const SizedBox(height: 16),
          Divider(height: 1, color: colors.surfaceBorder),
          const SizedBox(height: 12),
          const _IntervalPicker(),
        ],
      ),
    );
  }
}

class _IntervalPicker extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = AppColors.of(context);
    final format = MetricFormat.of(context);
    final l10n = format.l10n;
    final selected = ref.watch(syncIntervalProvider);
    return Column(
      key: RingKeys.interval,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            l10n.ringIntervalTitle,
            style: Theme.of(context).textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final interval in SyncInterval.values)
              ChoiceChip(
                key: RingKeys.intervalOption(interval),
                label: Text(format.duration(interval.duration)),
                selected: interval == selected,
                showCheckmark: false,
                materialTapTargetSize: MaterialTapTargetSize.padded,
                selectedColor: colors.surfaceInner,
                backgroundColor: colors.surface,
                side: BorderSide(
                  color: interval == selected
                      ? colors.oxygen
                      : colors.surfaceBorder,
                ),
                labelStyle: TextStyle(
                  color: interval == selected
                      ? colors.textPrimary
                      : colors.textLabel,
                ),
                onSelected: (_) => unawaited(
                  ref.read(syncIntervalProvider.notifier).select(interval),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        CaptionText(l10n.ringIntervalNote),
      ],
    );
  }
}

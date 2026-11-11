import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/core/records/health_record_kind.dart';
import 'package:open_ring/core/widgets/app_page.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/core/widgets/state_views.dart';
import 'package:open_ring/features/health_sync/application/health_status_providers.dart';
import 'package:open_ring/features/health_sync/application/health_sync_controller.dart';
import 'package:open_ring/features/health_sync/domain/health_status.dart';
import 'package:open_ring/features/health_sync/domain/health_writer.dart';
import 'package:open_ring/features/onboarding/presentation/onboarding_page.dart';
import 'package:open_ring/features/settings/presentation/settings_widgets.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

abstract final class HealthStatusKeys {
  static const status = Key('health_status');
  static const open = Key('health_status_open');
  static const askAgain = Key('health_status_ask_again');
  static const queue = Key('health_status_queue');
  static const sendNow = Key('health_status_send_now');
  static const dead = Key('health_status_dead');
  static const deadCause = Key('health_status_dead_cause');
  static const retryDead = Key('health_status_retry_dead');
  static const fix = Key('health_status_fix');
  static const error = Key('health_status_error');
  static const export = Key('health_status_export');

  static Key kind(HealthRecordKind kind) => Key('health_status_${kind.name}');

  static Key toggle(HealthRecordKind kind) =>
      Key('health_status_toggle_${kind.name}');
}

String healthLinkDetail(MetricFormat format, HealthStatusView? status) {
  final l10n = format.l10n;
  if (status == null) return l10n.settingsHealthDetail;
  final connection = switch (status.connection) {
    HealthConnection.connected => l10n.healthStatusConnected,
    HealthConnection.partial => l10n.healthStatusPartial,
    HealthConnection.denied => l10n.healthStatusDenied,
    HealthConnection.unavailable => l10n.healthStatusUnavailable,
  };
  final count = status.outbox.pendingRecordCount;
  if (count == 0) return '$connection · ${l10n.healthStatusQueueEmpty}';
  final waiting = l10n.healthStatusWaiting(count, format.integer(count));
  return '$connection · $waiting';
}

const List<HealthRecordKind> _typeOrder = [
  HealthRecordKind.activity,
  HealthRecordKind.heartRate,
  HealthRecordKind.sleep,
  HealthRecordKind.workout,
  HealthRecordKind.spo2,
  HealthRecordKind.hrv,
  HealthRecordKind.stress,
];

class HealthStatusScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<HealthStatusScreen> createState() => _HealthStatusScreenState();
}

class _HealthStatusScreenState extends ConsumerState<HealthStatusScreen> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _refresh);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  // Coming back from the platform settings is the moment a grant shows up,
  // and the queue should go out without another tap.
  void _refresh() {
    ref
      ..invalidate(healthAccessProvider)
      ..invalidate(outboxSummaryProvider);
    unawaited(ref.read(healthSyncProvider.notifier).process());
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(healthGrantRetryProvider);
    final status = ref.watch(healthStatusProvider);
    final connected = status.value?.connection == HealthConnection.connected;
    return AppPage(
      title: connected
          ? AppLocalizations.of(context).healthDataTitle
          : healthPlatformName(),
      children: [
        AsyncBody(
          value: status,
          builder: (view) => _HealthBody(view: view),
        ),
      ],
    );
  }
}

class _HealthBody extends ConsumerWidget {
  const new({required this.view});

  final HealthStatusView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final sync = ref.watch(healthSyncProvider);
    final connection = view.connection;
    final blocked = connection != HealthConnection.connected;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StatusCard(connection: connection),
        if (sync.lastError != null) ...[
          const SizedBox(height: cardGap),
          InfoNote(
            key: HealthStatusKeys.error,
            icon: Icons.error_outline_rounded,
            accent: colors.heart,
            text: l10n.healthStatusError,
            live: true,
          ),
        ],
        const SizedBox(height: cardGap),
        _QueueCard(
          outbox: view.outbox,
          canSend: connection != HealthConnection.unavailable,
          sending: sync.running,
        ),
        if (view.outbox.deadRows > 0) ...[
          const SizedBox(height: cardGap),
          _DeadCard(outbox: view.outbox, sending: sync.running),
        ],
        if (blocked) ...[
          const SizedBox(height: cardGap),
          _FixCard(connection: connection),
        ],
        SectionHeader(l10n.healthStatusTypes),
        _TypesCard(
          access: view.access,
          disabled: view.disabled,
          held: view.outbox.disabledRecords,
        ),
        const SizedBox(height: 8),
        CaptionText(l10n.healthStatusWriteNote),
        const SizedBox(height: cardGap),
        const _ExportCard(),
      ],
    );
  }
}

class _StatusCard extends ConsumerWidget {
  const new({required this.connection});

  final HealthConnection connection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final theme = Theme.of(context);
    final platform = healthPlatformName();
    final (icon, accent, label, body) = switch (connection) {
      HealthConnection.connected => (
        Icons.check_circle_rounded,
        colors.activity,
        l10n.healthStatusConnected,
        l10n.healthStatusConnectedBody(platform),
      ),
      HealthConnection.partial => (
        Icons.remove_circle_rounded,
        colors.stress,
        l10n.healthStatusPartial,
        l10n.healthStatusPartialBody(platform),
      ),
      HealthConnection.denied => (
        Icons.block_rounded,
        colors.heart,
        l10n.healthStatusDenied,
        l10n.healthStatusDeniedBody(platform),
      ),
      HealthConnection.unavailable => (
        Icons.cloud_off_rounded,
        colors.heart,
        l10n.healthStatusUnavailable,
        l10n.healthStatusUnavailableBody(platform),
      ),
    };
    final canAsk =
        connection == HealthConnection.partial ||
        connection == HealthConnection.denied;
    final statusLabel = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: accent),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            label,
            style: theme.textTheme.titleMedium?.copyWith(
              color: accent,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
    return Semantics(
      container: true,
      liveRegion: true,
      child: MetricCard(
        key: HealthStatusKeys.status,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (connection == HealthConnection.connected)
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 4,
                children: [
                  Text(
                    platform,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  statusLabel,
                ],
              ),
            if (connection != HealthConnection.connected) statusLabel,
            const SizedBox(height: 8),
            BodyText(body),
            if (canAsk) ...[
              const SizedBox(height: 16),
              SecondaryButton(
                key: HealthStatusKeys.askAgain,
                label: l10n.healthStatusAskAgain,
                onPressed: () => unawaited(_ask(ref)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // A grant already processes the queue; anything else still refreshes the
  // status, since a partial grant changes it too.
  static Future<void> _ask(WidgetRef ref) async {
    final health = ref.read(healthSyncProvider.notifier);
    final granted = await health.requestAccess().catchError(
      (Object _) => false,
    );
    if (granted) return;
    await health.process();
  }
}

class _QueueCard extends ConsumerWidget {
  const new({
    required this.outbox,
    required this.canSend,
    required this.sending,
  });

  final OutboxSummary outbox;
  final bool canSend;
  final bool sending;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final format = MetricFormat.of(context);
    final l10n = format.l10n;
    final colors = AppColors.of(context);
    final theme = Theme.of(context);
    final now = ref.watch(clockProvider)();
    final oldest = outbox.oldestPendingAt;
    final lastSent = outbox.lastSentAt;
    final kinds = outbox.pendingRecords.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return MetricCard(
      key: HealthStatusKeys.queue,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AccentTitle(title: l10n.healthStatusQueue, accent: colors.oxygen),
          const SizedBox(height: 8),
          Text(
            l10n.healthStatusWaiting(
              outbox.pendingRecordCount,
              format.integer(outbox.pendingRecordCount),
            ),
            style: numberStyle(
              theme.textTheme.titleLarge,
              color: colors.textPrimary,
            ),
          ),
          for (final MapEntry(key: kind, value: count) in kinds) ...[
            const SizedBox(height: 6),
            MetricRow(label: kind.label(l10n), value: format.integer(count)),
          ],
          const SizedBox(height: 8),
          if (oldest != null)
            CaptionText(
              l10n.healthStatusOldest(format.clockOrDay(oldest, now)),
            ),
          CaptionText(
            lastSent == null
                ? l10n.healthStatusNeverSent
                : l10n.healthStatusLastSent(format.clockOrDay(lastSent, now)),
          ),
          if (canSend && outbox.pendingRows > 0) ...[
            const SizedBox(height: 12),
            SecondaryButton(
              key: HealthStatusKeys.sendNow,
              label: sending
                  ? l10n.healthStatusSending
                  : l10n.healthStatusSendNow,
              onPressed: sending
                  ? null
                  : () => unawaited(
                      ref.read(healthSyncProvider.notifier).process(),
                    ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DeadCard extends StatelessWidget {
  const new({required this.outbox, required this.sending});

  final OutboxSummary outbox;
  final bool sending;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    return MetricCard(
      key: HealthStatusKeys.dead,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.report_outlined, size: 20, color: colors.heart),
              const SizedBox(width: 12),
              Expanded(child: BodyText(l10n.healthStatusDead(outbox.deadRows))),
            ],
          ),
          const SizedBox(height: 8),
          CaptionText(
            key: HealthStatusKeys.deadCause,
            outbox.deadCause.label(l10n, healthPlatformName()),
          ),
          const SizedBox(height: 12),
          SecondaryButton(
            key: HealthStatusKeys.retryDead,
            label: sending
                ? l10n.healthStatusSending
                : l10n.healthStatusRetryDead,
            onPressed: sending ? null : () => unawaited(_retry(context)),
          ),
        ],
      ),
    );
  }

  // The container outlives this card, which the reset itself can remove.
  static Future<void> _retry(BuildContext context) async {
    final container = ProviderScope.containerOf(context, listen: false);
    await container
        .read(retryDeadHealthRowsProvider)
        .call()
        .catchError((Object _) => 0);
    container.invalidate(outboxSummaryProvider);
  }
}

class _FixCard extends ConsumerWidget {
  const new({required this.connection});

  final HealthConnection connection;

  static Future<void> _open(WidgetRef ref) =>
      ref.read(healthSettingsOpenerProvider).open().catchError((Object _) {});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final platform = healthPlatformName();
    final android = defaultTargetPlatform == TargetPlatform.android;
    final steps = [
      l10n.healthStatusFixOpen(platform),
      l10n.healthStatusFixPick,
      l10n.healthStatusFixAllow,
      l10n.healthStatusFixReturn,
    ];
    return MetricCard(
      key: HealthStatusKeys.fix,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AccentTitle(title: l10n.healthStatusFixTitle, accent: colors.stress),
          const SizedBox(height: 4),
          if (connection != HealthConnection.unavailable)
            for (final (index, step) in steps.indexed)
              NumberedTip(number: index + 1, body: step),
          if (android) ...[
            const SizedBox(height: 4),
            CaptionText(l10n.healthStatusInstallNote),
          ],
          const SizedBox(height: 12),
          ActionButton(
            key: HealthStatusKeys.open,
            label: l10n.healthStatusOpen(platform),
            onPressed: () => unawaited(_open(ref)),
          ),
        ],
      ),
    );
  }
}

class _TypesCard extends ConsumerWidget {
  const new({required this.access, required this.disabled, required this.held});

  final Map<HealthRecordKind, HealthAccess> access;
  final Set<HealthRecordKind> disabled;
  final Map<HealthRecordKind, int> held;

  Iterable<(HealthRecordKind, HealthAccess)> get _ordered => [
    for (final kind in _typeOrder)
      if (access[kind] case final state?) (kind, state),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final format = MetricFormat.of(context);
    final l10n = format.l10n;
    final colors = AppColors.of(context);
    return TileGroup(
      children: [
        for (final (kind, state) in _ordered)
          SettingsTile(
            key: HealthStatusKeys.kind(kind),
            leading: AccentDot(color: kind.accent(colors)),
            title: kind.label(l10n),
            detail: disabled.contains(kind)
                ? l10n.healthStatusTypeOff(
                    held[kind] ?? 0,
                    format.integer(held[kind] ?? 0),
                  )
                : kind.detail(l10n),
            value: _accessLabel(kind, state, l10n),
            valueColor: state == HealthAccess.granted
                ? colors.activity
                : colors.stress,
            trailing: Switch(
              key: HealthStatusKeys.toggle(kind),
              value: !disabled.contains(kind),
              onChanged: (enabled) => unawaited(_set(ref, kind, enabled)),
            ),
          ),
      ],
    );
  }

  String? _accessLabel(
    HealthRecordKind kind,
    HealthAccess state,
    AppLocalizations l10n,
  ) {
    if (disabled.contains(kind)) return null;
    if (state == HealthAccess.granted) return l10n.healthStatusAllowed;
    return l10n.healthStatusNotAllowed;
  }

  static Future<void> _set(
    WidgetRef ref,
    HealthRecordKind kind,
    bool enabled,
  ) => ref
      .read(healthWritesProvider.notifier)
      .setEnabled(kind, enabled: enabled)
      .catchError((Object _) {});
}

class _ExportCard extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    return MetricCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AccentTitle(title: l10n.exportTitle, accent: colors.oxygen),
          const SizedBox(height: 6),
          BodyText(l10n.healthStatusExport(healthPlatformName())),
          const SizedBox(height: 12),
          SecondaryButton(
            key: HealthStatusKeys.export,
            label: l10n.healthStatusExportAction,
            onPressed: () => context.go(AppPaths.settingsExport),
          ),
        ],
      ),
    );
  }
}

extension HealthKindLabels on HealthRecordKind {
  String label(AppLocalizations l10n) => switch (this) {
    HealthRecordKind.activity => l10n.healthStatusKindActivity,
    HealthRecordKind.heartRate => l10n.healthWriteHeartRate,
    HealthRecordKind.spo2 => l10n.healthWriteSpo2,
    HealthRecordKind.stress => l10n.sourcesStress,
    HealthRecordKind.hrv => l10n.healthWriteHrv,
    HealthRecordKind.sleep => l10n.healthWriteSleep,
    HealthRecordKind.workout => l10n.healthWriteWorkouts,
  };

  String? detail(AppLocalizations l10n) => switch (this) {
    HealthRecordKind.heartRate => l10n.healthKindDetailHeartRate,
    HealthRecordKind.sleep => l10n.healthKindDetailSleep,
    HealthRecordKind.workout => l10n.healthKindDetailWorkout,
    HealthRecordKind.activity ||
    HealthRecordKind.spo2 ||
    HealthRecordKind.stress ||
    HealthRecordKind.hrv => null,
  };

  Color accent(AppColors colors) => switch (this) {
    HealthRecordKind.activity || HealthRecordKind.workout => colors.activity,
    HealthRecordKind.heartRate || HealthRecordKind.hrv => colors.heart,
    HealthRecordKind.spo2 => colors.oxygen,
    HealthRecordKind.stress => colors.stress,
    HealthRecordKind.sleep => colors.sleep,
  };
}

extension OutboxFailureLabels on OutboxFailure {
  String label(AppLocalizations l10n, String platform) => switch (this) {
    OutboxFailure.permission => l10n.healthStatusDeadCausePermission(platform),
    OutboxFailure.unavailable => l10n.healthStatusDeadCauseUnavailable(
      platform,
    ),
    OutboxFailure.rejected => l10n.healthStatusDeadCauseRejected(platform),
    OutboxFailure.unknown => l10n.healthStatusDeadCauseUnknown,
  };
}

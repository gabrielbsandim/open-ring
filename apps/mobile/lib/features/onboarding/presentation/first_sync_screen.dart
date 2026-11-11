import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/core/records/record_kind.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/features/onboarding/presentation/onboarding_page.dart';
import 'package:open_ring/features/ring/application/ring_sync_controller.dart';
import 'package:open_ring/features/ring/application/ring_sync_state.dart';
import 'package:open_ring/features/ring/application/sync_interval_controller.dart';
import 'package:open_ring/features/ring/application/sync_ring.dart';
import 'package:open_ring/features/ring/presentation/sync_labels.dart';
import 'package:open_ring/features/today/application/today_providers.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

abstract final class FirstSyncKeys {
  static const progress = Key('first_sync_progress');
  static const ring = Key('first_sync_ring');
  static const done = Key('first_sync_done');
  static const failure = Key('first_sync_failure');
  static const viewDay = Key('first_sync_view_day');
  static const retry = Key('first_sync_retry');
  static const skip = Key('first_sync_skip');

  static Key kind(RecordKind kind) => Key('first_sync_kind_${kind.name}');
}

enum FirstSyncPhase { running, done, failed }

class FirstSyncScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<FirstSyncScreen> createState() => _FirstSyncScreenState();
}

class _FirstSyncScreenState extends ConsumerState<FirstSyncScreen> {
  FirstSyncPhase _phase = FirstSyncPhase.running;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_start()));
  }

  Future<void> _start() async {
    setState(() => _phase = FirstSyncPhase.running);
    await ref.read(ringSyncProvider.notifier).refresh();
    if (!mounted) return;
    final error = ref.read(ringSyncProvider).lastError;
    final ok = error == null || error.partial;
    setState(() => _phase = ok ? FirstSyncPhase.done : FirstSyncPhase.failed);
  }

  void _openToday() => context.go(AppTab.today.path);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final sync = ref.watch(ringSyncProvider);
    final error = sync.lastError;
    final (title, intro) = switch (_phase) {
      FirstSyncPhase.running => (
        l10n.firstSyncRunningTitle,
        l10n.firstSyncRunningBody,
      ),
      FirstSyncPhase.done => (l10n.firstSyncDoneTitle, l10n.firstSyncDoneBody),
      FirstSyncPhase.failed => (
        error?.title(l10n) ?? l10n.syncFailedTitle,
        error?.message(l10n) ?? l10n.syncErrorStopped,
      ),
    };
    final fraction = switch (_phase) {
      FirstSyncPhase.running => sync.progress?.fraction ?? 0,
      FirstSyncPhase.done => 1.0,
      FirstSyncPhase.failed => 0.0,
    };
    final minutes = ref.watch(syncIntervalProvider).minutes;
    return OnboardingPage(
      label: l10n.firstSyncHeader,
      trailing: _RingPill(phase: _phase),
      title: title,
      intro: intro,
      children: [
        _OverallProgress(fraction: fraction),
        const SizedBox(height: cardGap),
        _KindsCard(phase: _phase, sync: sync),
        const SizedBox(height: 20),
        ...switch (_phase) {
          FirstSyncPhase.running => [
            InfoNote(
              icon: Icons.phone_android_rounded,
              lead: l10n.firstSyncBackgroundLead,
              text: l10n.firstSyncBackground,
            ),
            const SizedBox(height: cardGap),
            CaptionText(l10n.firstSyncDuration, textAlign: TextAlign.center),
          ],
          FirstSyncPhase.done => [
            InfoNote(
              key: FirstSyncKeys.done,
              icon: Icons.check_circle_outline_rounded,
              accent: colors.activity,
              lead: l10n.firstSyncDoneLead,
              text: l10n.firstSyncDoneNote(healthPlatformName(), minutes),
              live: true,
            ),
            const SizedBox(height: 20),
            PrimaryAction(
              key: FirstSyncKeys.viewDay,
              label: l10n.firstSyncViewDay,
              onPressed: _openToday,
            ),
          ],
          FirstSyncPhase.failed => [
            InfoNote(
              key: FirstSyncKeys.failure,
              icon: Icons.error_outline_rounded,
              accent: colors.heart,
              text: l10n.firstSyncRetryHint,
              live: true,
            ),
            const SizedBox(height: 20),
            PrimaryAction(
              key: FirstSyncKeys.retry,
              label: l10n.pairErrorRetry,
              onPressed: () => unawaited(_start()),
            ),
            const SizedBox(height: 4),
            QuietAction(
              key: FirstSyncKeys.skip,
              label: l10n.firstSyncSkip,
              onPressed: _openToday,
            ),
          ],
        },
      ],
    );
  }
}

class _RingPill extends ConsumerWidget {
  const new({required this.phase});

  final FirstSyncPhase phase;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = AppColors.of(context);
    final format = MetricFormat.of(context);
    final ring = ref.watch(ringStatusProvider).value;
    if (ring == null || !ring.paired) return const SizedBox.shrink();
    final battery = ref.watch(
      ringSyncProvider.select((sync) => sync.batteryPercent),
    );
    final percent = battery ?? ring.batteryPercent;
    final parts = [
      ?ring.model ?? ring.name,
      if (percent != null) format.percent(percent.toDouble()),
    ];
    if (parts.isEmpty) return const SizedBox.shrink();
    return Container(
      key: FirstSyncKeys.ring,
      constraints: const BoxConstraints(minHeight: 32),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.surfaceBorder),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: phase == FirstSyncPhase.failed
                  ? colors.textLabel
                  : colors.activity,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              parts.join(' · '),
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: colors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

class _OverallProgress extends StatelessWidget {
  const new({required this.fraction});

  final double fraction;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final theme = Theme.of(context);
    final percent = (fraction * 100).round();
    return Semantics(
      key: FirstSyncKeys.progress,
      label: l10n.firstSyncProgress,
      value: l10n.firstSyncPercent(percent),
      child: ExcludeSemantics(
        child: Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(5),
                child: LinearProgressIndicator(
                  value: fraction,
                  minHeight: 10,
                  color: colors.textPrimary,
                  backgroundColor: colors.track,
                ),
              ),
            ),
            const SizedBox(width: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 48),
              child: Text(
                l10n.firstSyncPercent(percent),
                textAlign: TextAlign.end,
                style: numberStyle(
                  theme.textTheme.titleMedium,
                  color: colors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _KindsCard extends StatelessWidget {
  const new({required this.phase, required this.sync});

  final FirstSyncPhase phase;
  final RingSyncState sync;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    return Semantics(
      liveRegion: true,
      child: MetricCard(
        child: Column(
          children: [
            for (final (index, kind) in RecordKind.values.indexed) ...[
              if (index > 0) const Divider(height: 1),
              _KindRow(
                key: FirstSyncKeys.kind(kind),
                name: kindName(l10n, kind),
                accent: kindAccent(colors, kind),
                status: statusOf(l10n, kind),
                done: _isDone(kind),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String kindName(AppLocalizations l10n, RecordKind kind) =>
      switch (kind) {
        RecordKind.activity => l10n.firstSyncKindSteps,
        RecordKind.heartRate => l10n.firstSyncKindHeartRate,
        RecordKind.spo2 => l10n.firstSyncKindSpo2,
        RecordKind.stress => l10n.firstSyncKindStress,
        RecordKind.hrv => l10n.firstSyncKindHrv,
        RecordKind.sleep => l10n.firstSyncKindSleep,
      };

  static Color kindAccent(AppColors colors, RecordKind kind) => switch (kind) {
    RecordKind.activity => colors.activity,
    RecordKind.heartRate || RecordKind.hrv => colors.heart,
    RecordKind.spo2 => colors.oxygen,
    RecordKind.stress => colors.stress,
    RecordKind.sleep => colors.sleep,
  };

  bool _failed(RecordKind kind) => switch (sync.lastError) {
    CapabilitiesFailed(:final capabilities) => capabilities.contains(
      SyncRing.capabilityOf(kind),
    ),
    _ => false,
  };

  bool _isDone(RecordKind kind) =>
      phase == FirstSyncPhase.done && !_failed(kind);

  String statusOf(AppLocalizations l10n, RecordKind kind) => switch (phase) {
    FirstSyncPhase.failed => l10n.firstSyncKindNotRead,
    FirstSyncPhase.done when _failed(kind) => l10n.firstSyncKindNotRead,
    FirstSyncPhase.done => l10n.firstSyncKindCount(sync.lastWritten[kind] ?? 0),
    FirstSyncPhase.running => _running(l10n, kind),
  };

  String _running(AppLocalizations l10n, RecordKind kind) {
    final progress = sync.progress;
    if (progress == null) return l10n.firstSyncKindQueued;
    return switch (progress.step) {
      SyncStep.connecting ||
      SyncStep.settingTime ||
      SyncStep.readingBattery => l10n.firstSyncKindQueued,
      SyncStep.saving || SyncStep.disconnecting => l10n.firstSyncKindRead,
      SyncStep.pulling => _pulling(l10n, kind, progress.kind),
    };
  }

  static String _pulling(
    AppLocalizations l10n,
    RecordKind kind,
    RecordKind? current,
  ) {
    final position = current?.index ?? 0;
    if (kind.index < position) return l10n.firstSyncKindRead;
    if (kind.index == position) return l10n.firstSyncKindReading;
    return l10n.firstSyncKindQueued;
  }
}

class _KindRow extends StatelessWidget {
  const new({
    required this.name,
    required this.accent,
    required this.status,
    required this.done,
    super.key,
  });

  final String name;
  final Color accent;
  final String status;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final theme = Theme.of(context);
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                spacing: 12,
                children: [
                  Text(
                    name,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.textPrimary,
                    ),
                  ),
                  Text(
                    status,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: done ? colors.textSecondary : colors.textLabel,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Opacity(
              opacity: done ? 1 : 0,
              child: Icon(
                Icons.check_rounded,
                size: 18,
                color: colors.activity,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

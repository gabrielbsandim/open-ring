import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/widgets/charts.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/features/ring/application/ring_sync_controller.dart';
import 'package:open_ring/features/ring/application/ring_sync_state.dart';
import 'package:open_ring/features/ring/presentation/sync_labels.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

Future<void> refreshRing(WidgetRef ref) =>
    ref.read(ringSyncProvider.notifier).refresh();

abstract final class SyncKeys {
  static const progress = Key('sync_progress');
  static const error = Key('sync_error');
  static const retry = Key('sync_retry');
  static const pair = Key('sync_pair');
}

class SyncStatusBanner extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sync = ref.watch(ringSyncProvider);
    final status = SyncStatusView(
      state: sync,
      onRetry: () => unawaited(refreshRing(ref)),
    );
    if (!status.visible) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: cardGap),
      child: status,
    );
  }
}

class SyncStatusView extends StatelessWidget {
  const new({required this.state, required this.onRetry, super.key});

  final RingSyncState state;
  final VoidCallback onRetry;

  bool get visible => state.progress != null || state.lastError != null;

  @override
  Widget build(BuildContext context) {
    final progress = state.progress;
    if (progress != null) return SyncProgressView(progress: progress);
    final error = state.lastError;
    if (error == null) return const SizedBox.shrink();
    return SyncErrorView(error: error, onRetry: onRetry);
  }
}

class SyncProgressView extends StatelessWidget {
  const new({required this.progress, super.key});

  final SyncProgress progress;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final l10n = AppLocalizations.of(context);
    final label = progress.label(l10n);
    return Semantics(
      key: SyncKeys.progress,
      liveRegion: true,
      container: true,
      label: l10n.syncInProgress(label),
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.sync_rounded, size: 18, color: colors.oxygen),
              const SizedBox(width: 8),
              Expanded(child: CaptionText(label, color: colors.textSecondary)),
            ],
          ),
          const SizedBox(height: 8),
          ProgressBar(value: progress.fraction, color: colors.oxygen),
        ],
      ),
    );
  }
}

class SyncErrorView extends StatelessWidget {
  const new({required this.error, required this.onRetry, super.key});

  final SyncError error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final l10n = AppLocalizations.of(context);
    final accent = error.partial ? colors.stress : colors.heart;
    return Semantics(
      key: SyncKeys.error,
      liveRegion: true,
      child: MetricCard(
        color: colors.surfaceInner,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.sync_problem_rounded, size: 22, color: accent),
                const SizedBox(width: 10),
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      error.title(l10n),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            BodyText(error.message(l10n)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                if (error is NoPairedRing)
                  TextButton(
                    key: SyncKeys.pair,
                    onPressed: () => context.go(AppTab.ring.path),
                    child: Text(l10n.metricOpenRing),
                  ),
                if (error is! NoPairedRing)
                  TextButton(
                    key: SyncKeys.retry,
                    onPressed: onRetry,
                    child: Text(l10n.syncRetry),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

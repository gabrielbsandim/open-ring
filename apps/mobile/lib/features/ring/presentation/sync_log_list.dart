import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/features/ring/application/auto_measurements_controller.dart';
import 'package:open_ring/features/ring/application/sync_ring.dart';
import 'package:open_ring/features/ring/domain/sync_run.dart';
import 'package:open_ring/features/ring/presentation/ring_cards.dart';
import 'package:open_ring/features/ring/presentation/sync_labels.dart';

class SyncLogList extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final runs = ref.watch(syncLogProvider).value ?? const <SyncRun>[];
    final now = ref.watch(clockProvider)();
    final l10n = MetricFormat.of(context).l10n;
    return Column(
      key: RingKeys.log,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            l10n.ringLogTitle,
            style: Theme.of(context).textTheme.labelLarge
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        if (runs.isEmpty)
          Padding(
            key: RingKeys.logEmpty,
            padding: const EdgeInsets.only(top: 8),
            child: CaptionText(l10n.ringLogEmpty),
          ),
        for (final run in runs) _SyncRunTile(run: run, now: now),
      ],
    );
  }
}

class _SyncRunTile extends StatelessWidget {
  const new({required this.run, required this.now});

  final SyncRun run;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final format = MetricFormat.of(context);
    final l10n = format.l10n;
    final (dot, title) = switch (run.outcome) {
      SyncRunOutcome.completed => (colors.activity, l10n.ringLogCompleted),
      SyncRunOutcome.partial => (colors.stress, l10n.ringLogPartial),
      SyncRunOutcome.unreachable ||
      SyncRunOutcome.stopped => (colors.heart, l10n.ringLogFailed),
    };
    return MergeSemantics(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        margin: const EdgeInsets.only(top: 8),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: colors.surfaceBorder)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(top: 6),
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    spacing: 12,
                    children: [
                      Text(title, style: theme.textTheme.bodyMedium),
                      Text(
                        format.clockOrDay(run.at, now),
                        style: numberStyle(
                          theme.textTheme.bodyMedium,
                          color: colors.textLabel,
                        ),
                      ),
                    ],
                  ),
                  CaptionText(_detail(format)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _detail(MetricFormat format) {
    final l10n = format.l10n;
    switch (run.outcome) {
      case SyncRunOutcome.unreachable:
        return l10n.ringLogUnreachable;
      case SyncRunOutcome.stopped:
        return l10n.ringLogStopped;
      case SyncRunOutcome.completed || SyncRunOutcome.partial:
        final records = l10n.ringLogRecords(
          run.recordCount,
          format.integer(run.recordCount),
        );
        if (run.kinds.isEmpty) return records;
        final kinds = [
          for (final kind in run.kinds) SyncRing.capabilityOf(kind).label(l10n),
        ];
        return '$records · ${kinds.join(', ')}';
    }
  }
}

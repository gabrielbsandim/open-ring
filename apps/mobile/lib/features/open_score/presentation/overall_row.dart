import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/features/open_score/application/overall_providers.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

abstract final class OverallRowKeys {
  static const row = Key('today_overall_row');
  static const score = Key('today_overall_row_score');
  static const note = Key('today_overall_row_note');
}

String overallBandLabel(AppLocalizations l10n, OverallBand band) =>
    switch (band) {
      OverallBand.strong => l10n.overallBandStrong,
      OverallBand.solid => l10n.overallBandSolid,
      OverallBand.building => l10n.overallBandBuilding,
      OverallBand.start => l10n.overallBandStart,
    };

class OverallRow extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(overallHistoryProvider).value;
    if (history == null) return const SizedBox.shrink();
    final format = MetricFormat.of(context);
    final l10n = format.l10n;
    final scored = history.scored;
    final theme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: cardGap),
      child: MetricCard(
        key: OverallRowKeys.row,
        onTap: () => context.go(AppPaths.dayScoreOverall),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.overallTitle,
                    style: theme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  CaptionText(
                    key: OverallRowKeys.note,
                    scored == null
                        ? l10n.overallRowForming(
                            history.nights.clamp(0, overallMinDays),
                            overallMinDays,
                          )
                        : '${overallBandLabel(l10n, overallBand(scored.value))}'
                              ' · '
                              '${l10n.overallUpdated(format.monthDay(history.current.date))}',
                  ),
                ],
              ),
            ),
            if (scored != null) ...[
              const SizedBox(width: 12),
              Text(
                format.integer(scored.value),
                key: OverallRowKeys.score,
                style: theme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/features/effort/application/effort_gate.dart';
import 'package:open_ring/features/effort/application/effort_providers.dart';

abstract final class EffortWeekTileKeys {
  static const tile = Key('today_effort_tile');
  static const note = Key('today_effort_tile_note');
  static const points = Key('today_effort_tile_points');
  static const target = Key('today_effort_tile_target');
}

/// The Effort entry of Today: this week's points against the target. It shows
/// in every state of Today while the module is on, ring or no ring.
class EffortWeekTileSlot extends ConsumerWidget {
  const new({this.padding = const EdgeInsets.only(bottom: cardGap), super.key});

  final EdgeInsets padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(effortEnabledProvider)) return const SizedBox.shrink();
    final week = ref.watch(effortWeekProvider).value;
    if (week == null) return const SizedBox.shrink();
    return Padding(
      padding: padding,
      child: EffortWeekTile(
        week: week,
        onTap: () => context.go(AppPaths.effort),
      ),
    );
  }
}

class EffortWeekTile extends StatelessWidget {
  const new({required this.week, this.onTap, super.key});

  final EffortWeek week;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final format = MetricFormat.of(context);
    final l10n = format.l10n;
    final theme = Theme.of(context).textTheme;
    final points = format.integer(week.points.round());
    final target = l10n.effortWeekPoints(format.integer(effortWeekPoints));
    return Semantics(
      container: true,
      excludeSemantics: true,
      button: true,
      onTap: onTap,
      label: '${l10n.effortTitle}, ${l10n.effortWeekTitle}: $points $target',
      child: MetricCard(
        key: EffortWeekTileKeys.tile,
        onTap: onTap,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        // A Wrap and not a Row: at a large text scale the points drop under
        // the title instead of squeezing it.
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 6,
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.effortTitle,
                  style: theme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                CaptionText(l10n.effortWeekTitle, key: EffortWeekTileKeys.note),
              ],
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  points,
                  key: EffortWeekTileKeys.points,
                  style: theme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                CaptionText(target, key: EffortWeekTileKeys.target),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

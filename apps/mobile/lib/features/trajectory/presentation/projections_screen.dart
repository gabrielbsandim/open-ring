import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/core/widgets/app_page.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/features/body/application/hide_numbers_controller.dart';
import 'package:open_ring/features/settings/application/unit_format.dart';
import 'package:open_ring/features/trajectory/application/projections_providers.dart';
import 'package:open_ring/features/trajectory/presentation/trajectory_states.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

abstract final class ProjectionsKeys {
  static const card = Key('trajectory_projections_card');
  static const empty = Key('trajectory_projections_empty');
  static const note = Key('trajectory_projections_note');

  static Key row(LocalDate monday) =>
      Key('trajectory_projection_${monday.iso}');
}

({int inside, int below, int above, int waiting}) _counts(
  List<GradedProjection> rows,
  LocalDate today,
) {
  int count(ProjectionGrade grade) =>
      rows.where((row) => row.grade == grade).length;
  return (
    inside: count(ProjectionGrade.inside),
    below: count(ProjectionGrade.below),
    above: count(ProjectionGrade.above),
    waiting: rows.where((row) => row.due.compareTo(today) > 0).length,
  );
}

/// The Trajectory screen's summary of the stored Mondays; opens the list.
class TrajectoryProjectionsCard extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = ref.watch(projectionsProvider).value;
    if (rows == null) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final c = _counts(rows, ref.watch(currentDateProvider));
    final checked = c.inside + c.below + c.above;
    final parts = [
      if (c.inside > 0) l10n.trajectoryProjectionsInside('${c.inside}'),
      if (c.below > 0) l10n.trajectoryProjectionsBelow('${c.below}'),
      if (c.above > 0) l10n.trajectoryProjectionsAbove('${c.above}'),
    ];
    final title = Text(
      l10n.trajectoryProjectionsTitle,
      style: Theme.of(context).textTheme.titleSmall,
    );
    if (rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: MetricCard(
          key: ProjectionsKeys.empty,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              title,
              const SizedBox(height: 4),
              CaptionText(l10n.trajectoryProjectionsEmpty),
            ],
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: MetricCard(
        key: ProjectionsKeys.card,
        onTap: () => unawaited(context.push(AppPaths.trajectoryProjections)),
        child: MergeSemantics(
          child: Semantics(
            button: true,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      title,
                      const SizedBox(height: 2),
                      BodyText(l10n.trajectoryProjectionsChecked(checked)),
                      if (parts.isNotEmpty) CaptionText(parts.join(' · ')),
                      if (c.waiting > 0)
                        CaptionText(
                          l10n.trajectoryProjectionsWaiting(c.waiting),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.chevron_right_rounded, color: colors.textLabel),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ProjectionsScreen extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final units = UnitFormat.of(context, ref);
    final l10n = units.l10n;
    final view = ref.watch(projectionsProvider);
    return AppPage(
      title: l10n.trajectoryProjectionsTitle,
      children: [
        CaptionText(l10n.trajectoryProjectionsLead),
        const SizedBox(height: 16),
        ...switch (view) {
          AsyncValue(hasError: true) => [
            TrajectoryErrorCard(
              onRetry: () => ref.invalidate(projectionsProvider),
            ),
          ],
          AsyncValue(:final value?) => _list(
            context,
            units,
            value,
            today: ref.watch(currentDateProvider),
            hidden: ref.watch(numbersHiddenProvider),
          ),
          _ => const <Widget>[],
        },
      ],
    );
  }

  List<Widget> _list(
    BuildContext context,
    UnitFormat units,
    List<GradedProjection> rows, {
    required LocalDate today,
    required bool hidden,
  }) {
    final l10n = units.l10n;
    if (rows.isEmpty) return [BodyText(l10n.trajectoryProjectionsEmpty)];
    final c = _counts(rows, today);
    final outside = c.below + c.above > 0;
    final checked = c.inside + c.below + c.above > 0;
    return [
      MetricCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AccentTitle(
              title: l10n.trajectoryProjectionsHowTitle,
              accent: AppColors.of(context).textPrimary,
            ),
            for (final row in rows)
              _Row(row: row, units: units, today: today, hidden: hidden),
          ],
        ),
      ),
      if (checked) ...[
        const SizedBox(height: cardGap),
        MetricCard(
          key: ProjectionsKeys.note,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                outside
                    ? l10n.trajectoryProjectionsOutsideTitle
                    : l10n.trajectoryProjectionsInsideTitle,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              BodyText(
                outside
                    ? l10n.trajectoryProjectionsOutsideBody
                    : l10n.trajectoryProjectionsInsideBody,
              ),
            ],
          ),
        ),
      ],
      const SizedBox(height: 16),
      CaptionText(l10n.trajectoryProjectionsFoot),
    ];
  }
}

class _Row extends StatelessWidget {
  const new({
    required this.row,
    required this.units,
    required this.today,
    required this.hidden,
  });

  final GradedProjection row;
  final UnitFormat units;
  final LocalDate today;
  final bool hidden;

  @override
  Widget build(BuildContext context) {
    final l10n = units.l10n;
    final format = units.format;
    final due = format.monthDay(row.due);
    final projection = row.projection;
    final range = l10n.trajectoryRange(
      units.bodyWeightNumber(projection.lowKg),
      units.bodyWeightNumber(projection.highKg),
      units.weightUnit,
    );
    final actual = row.actualKg;
    final pending = row.due.compareTo(today) > 0;
    final text = switch (row.grade) {
      _ when hidden => l10n.trajectoryProjectionsRowHidden(due),
      null when !pending => l10n.trajectoryProjectionsRowUnchecked,
      null => l10n.trajectoryProjectionsRow(due, range),
      _ =>
        '${l10n.trajectoryProjectionsRow(due, range)} '
            '${l10n.trajectoryProjectionsRowTrend(units.bodyWeight(actual!))}',
    };
    final tag = switch (row.grade) {
      ProjectionGrade.inside => l10n.trajectoryProjectionsTagInside,
      ProjectionGrade.below => l10n.trajectoryProjectionsTagBelow,
      ProjectionGrade.above => l10n.trajectoryProjectionsTagAbove,
      null when pending => l10n.trajectoryProjectionsTagWaiting(due),
      null => l10n.trajectoryProjectionsTagUnchecked,
    };
    return MergeSemantics(
      key: ProjectionsKeys.row(projection.monday),
      child: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 64,
              child: CaptionText(format.monthDay(projection.monday)),
            ),
            const SizedBox(width: 8),
            Expanded(child: BodyText(text)),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                tag,
                textAlign: TextAlign.end,
                style: Theme.of(context).textTheme.labelMedium
                    ?.copyWith(color: AppColors.of(context).textLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

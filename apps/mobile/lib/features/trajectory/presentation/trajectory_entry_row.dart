import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/features/body/application/hide_numbers_controller.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/settings/application/unit_format.dart';
import 'package:open_ring/features/trajectory/application/trajectory_providers.dart';
import 'package:open_ring/features/trajectory/domain/trajectory_view.dart';

enum TrajectoryEntry { body, goal }

/// One row that opens the trajectory screen, with the 12 week range when it
/// is drawn. The view is never read while the module is off.
class TrajectoryEntryRow extends ConsumerWidget {
  const new({required this.from, super.key});

  static const rowKey = Key('trajectory_entry_row');

  final TrajectoryEntry from;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final modules = ref.watch(enabledModulesProvider).value ?? const {};
    if (!modules.contains(ModuleId.trajectory)) return const SizedBox.shrink();
    return const _Row();
  }
}

class _Row extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(trajectoryViewProvider);
    if (view.hasError || !view.hasValue) return const SizedBox.shrink();
    final loaded = view.requireValue;
    if (loaded is TrajectoryOff) return const SizedBox.shrink();
    final units = UnitFormat.of(context, ref);
    final l10n = units.l10n;
    final hidden = ref.watch(numbersHiddenProvider);
    final subtitle = switch (loaded) {
      TrajectoryReady(:final band) when !hidden => l10n.trajectoryRowReady(
        band.days ~/ 7,
        units.bodyWeightNumber(band.low),
        units.bodyWeightNumber(band.high),
        units.weightUnit,
      ),
      _ => l10n.trajectoryRowGeneric,
    };
    final colors = AppColors.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: cardGap),
      child: MetricCard(
        key: TrajectoryEntryRow.rowKey,
        padding: EdgeInsets.zero,
        child: MergeSemantics(
          child: Semantics(
            button: true,
            child: InkWell(
              onTap: () => unawaited(context.push(AppPaths.trajectory)),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                  child: Row(
                    children: [
                      Icon(
                        Icons.show_chart_rounded,
                        size: 20,
                        color: colors.textPrimary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n.trajectoryTitle,
                              style: theme.textTheme.titleSmall,
                            ),
                            const SizedBox(height: 2),
                            CaptionText(subtitle),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: colors.textLabel,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

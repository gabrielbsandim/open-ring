import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/core/widgets/app_page.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/core/widgets/state_views.dart';
import 'package:open_ring/features/export/application/export_controller.dart';
import 'package:open_ring/features/export/domain/data_exporter.dart';
import 'package:open_ring/features/export/domain/export_kind.dart';
import 'package:open_ring/features/onboarding/presentation/onboarding_page.dart';
import 'package:open_ring/features/settings/presentation/settings_widgets.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

abstract final class ExportKeys {
  static const run = Key('export_run');
  static const running = Key('export_running');
  static const done = Key('export_done');
  static const share = Key('export_share');
  static const shareFailed = Key('export_share_failed');
  static const failed = Key('export_failed');
  static const noKind = Key('export_no_kind');

  static Key range(ExportRange range) => Key('export_range_${range.name}');

  static Key format(ExportFormat format) => Key('export_format_${format.name}');

  static Key kind(ExportKind kind) => Key('export_kind_${kind.name}');
}

class ExportScreen extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final state = ref.watch(exportProvider);
    final export = ref.read(exportProvider.notifier);
    final editable = !state.running;
    return AppPage(
      title: l10n.exportTitle,
      subtitle: l10n.exportIntro,
      children: [
        SectionHeader(l10n.exportRange),
        ChoiceRow<ExportRange>(
          values: ExportRange.values,
          selected: state.range,
          keyOf: ExportKeys.range,
          label: (range) => range.label(l10n),
          onSelected: editable ? export.selectRange : null,
        ),
        SectionHeader(l10n.exportKinds),
        MetricCard(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              for (final kind in ExportKind.values)
                CheckboxListTile(
                  key: ExportKeys.kind(kind),
                  value: state.kinds.contains(kind),
                  title: Text(kind.label(l10n)),
                  activeColor: colors.textPrimary,
                  checkColor: colors.background,
                  onChanged: editable ? (_) => export.toggleKind(kind) : null,
                ),
            ],
          ),
        ),
        if (state.kinds.isEmpty) ...[
          const SizedBox(height: 8),
          CaptionText(
            key: ExportKeys.noKind,
            l10n.exportPickKind,
            color: colors.stress,
          ),
        ],
        SectionHeader(l10n.exportFormat),
        ChoiceRow<ExportFormat>(
          values: ExportFormat.values,
          selected: state.format,
          keyOf: ExportKeys.format,
          label: (format) => format.label,
          onSelected: editable ? export.selectFormat : null,
        ),
        const SizedBox(height: 8),
        CaptionText(state.format.note(l10n)),
        const SizedBox(height: 24),
        ActionButton(
          key: ExportKeys.run,
          label: state.running ? l10n.exportRunning : l10n.exportRun,
          onPressed: state.canRun ? () => unawaited(export.run()) : null,
        ),
        const SizedBox(height: cardGap),
        _Outcome(state: state),
      ],
    );
  }
}

class _Outcome extends ConsumerWidget {
  const new({required this.state});

  final ExportState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final result = state.result;
    return switch (state.phase) {
      ExportPhase.idle => const SizedBox.shrink(),
      ExportPhase.running => InfoNote(
        key: ExportKeys.running,
        icon: Icons.hourglass_top_rounded,
        text: l10n.exportRunningNote,
        live: true,
      ),
      ExportPhase.failed => InfoNote(
        key: ExportKeys.failed,
        icon: Icons.error_outline_rounded,
        accent: colors.heart,
        text: l10n.exportFailed,
        live: true,
      ),
      ExportPhase.done when result != null => _DoneCard(
        result: result,
        shareFailed: state.shareFailed,
      ),
      ExportPhase.done => const SizedBox.shrink(),
    };
  }
}

class _DoneCard extends ConsumerWidget {
  const new({required this.result, required this.shareFailed});

  final ExportResult result;
  final bool shareFailed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final format = MetricFormat.of(context);
    final l10n = format.l10n;
    final colors = AppColors.of(context);
    return Semantics(
      container: true,
      liveRegion: true,
      child: MetricCard(
        key: ExportKeys.done,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.check_circle_rounded, color: colors.activity),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.exportDone,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            for (final file in result.files) BodyText(exportFileName(file)),
            CaptionText(
              l10n.exportRecords(
                result.recordCount,
                format.integer(result.recordCount),
              ),
            ),
            const SizedBox(height: 12),
            ActionButton(
              key: ExportKeys.share,
              label: l10n.exportShare,
              onPressed: () =>
                  unawaited(ref.read(exportProvider.notifier).share()),
            ),
            if (shareFailed) ...[
              const SizedBox(height: 8),
              CaptionText(
                key: ExportKeys.shareFailed,
                l10n.exportShareFailed,
                color: colors.heart,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

extension on ExportRange {
  String label(AppLocalizations l10n) => switch (this) {
    ExportRange.week => l10n.exportRangeWeek,
    ExportRange.month => l10n.exportRangeMonth,
    ExportRange.all => l10n.exportRangeAll,
  };
}

extension on ExportFormat {
  String get label => switch (this) {
    ExportFormat.csv => 'CSV',
    ExportFormat.json => 'JSON',
  };

  String note(AppLocalizations l10n) => switch (this) {
    ExportFormat.csv => l10n.exportCsvNote,
    ExportFormat.json => l10n.exportJsonNote,
  };
}

extension on ExportKind {
  String label(AppLocalizations l10n) => switch (this) {
    ExportKind.sleep => l10n.exportKindSleep,
    ExportKind.heartRate => l10n.exportKindHeartRate,
    ExportKind.hrv => l10n.exportKindHrv,
    ExportKind.spo2 => l10n.exportKindSpo2,
    ExportKind.stress => l10n.exportKindStress,
    ExportKind.activity => l10n.exportKindActivity,
    ExportKind.workouts => l10n.exportKindWorkouts,
  };
}

import 'package:flutter/material.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/core/widgets/charts.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/features/sleep/presentation/sleep_labels.dart';

String stagesSemantics(
  MetricFormat format,
  SleepNight night, {
  bool rem = true,
}) {
  String time(SleepPhase phase) => format.duration(night.timeIn(phase));
  if (!rem) {
    return format.l10n.sleepStagesSemanticsNoRem(
      time(SleepPhase.light),
      time(SleepPhase.deep),
      time(SleepPhase.awake),
    );
  }
  return format.l10n.sleepStagesSemantics(
    time(SleepPhase.light),
    time(SleepPhase.deep),
    time(SleepPhase.rem),
    time(SleepPhase.awake),
  );
}

class SleepStageBar extends StatelessWidget {
  const new({required this.night, this.remMeasured = true, super.key});

  final SleepNight night;
  final bool remMeasured;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final format = MetricFormat.of(context);
    return SegmentedBar(
      semanticsLabel: stagesSemantics(
        format,
        night,
        rem: showsRem(night, remMeasured: remMeasured),
      ),
      segments: [
        for (final phase in stageSummaryOrder)
          (
            weight: night.timeIn(phase).inSeconds.toDouble(),
            color: phase.color(colors),
          ),
      ],
    );
  }
}

class SleepStageLegend extends StatelessWidget {
  const new({required this.night, this.remMeasured = true, super.key});

  final SleepNight night;
  final bool remMeasured;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final format = MetricFormat.of(context);
    final rem = showsRem(night, remMeasured: remMeasured);
    return ExcludeSemantics(
      child: Wrap(
        spacing: 16,
        runSpacing: 4,
        children: [
          for (final phase in phasesShown(stageSummaryOrder, rem: rem))
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: phase.color(colors),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: CaptionText(
                    format.l10n.sleepStageDuration(
                      phase.label(format),
                      format.duration(night.timeIn(phase)),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

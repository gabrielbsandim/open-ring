import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/core/widgets/charts.dart';
import 'package:open_ring/features/sleep/presentation/sleep_labels.dart';
import 'package:open_ring/features/sleep/presentation/sleep_stage_summary.dart';

class Hypnogram extends StatelessWidget {
  const new({required this.night, this.remMeasured = true, super.key});

  static const chartKey = Key('hypnogram_chart');

  static const _laneMinHeight = 32.0;
  static const _axisTicks = 5;

  final SleepNight night;
  final bool remMeasured;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final format = MetricFormat.of(context);
    final style = theme.textTheme.labelSmall?.copyWith(color: colors.textLabel);
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    final rem = showsRem(night, remMeasured: remMeasured);
    final lanes = phasesShown(hypnogramLanes, rem: rem);
    final labels = [for (final phase in lanes) phase.label(format)];
    final awakenings = night.awakenings.length;
    return Semantics(
      key: chartKey,
      container: true,
      image: true,
      label: format.l10n.sleepHypnogramSemantics(
        awakenings,
        stagesSemantics(format, night, rem: rem),
      ),
      child: ExcludeSemantics(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final widest = labels.fold<double>(0, (widest, label) {
              final painter = TextPainter(
                text: TextSpan(text: label, style: style),
                textDirection: direction,
                textScaler: scaler,
              )..layout();
              final width = painter.width;
              painter.dispose();
              return math.max(widest, width);
            });
            final labelWidth = math.min(
              widest.ceilToDouble() + 1,
              constraints.maxWidth * 0.3,
            );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: labelWidth,
                        child: Column(
                          children: [
                            for (final label in labels)
                              ConstrainedBox(
                                constraints: const BoxConstraints(
                                  minHeight: _laneMinHeight,
                                ),
                                child: Align(
                                  alignment: AlignmentDirectional.centerStart,
                                  child: Text(label, style: style),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: CustomPaint(
                          painter: _HypnogramPainter(
                            night: night,
                            lanes: lanes,
                            colors: colors,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Padding(
                  padding: EdgeInsetsDirectional.only(start: labelWidth + 8),
                  child: TimeAxis(labels: _axisLabels(format)),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  List<String> _axisLabels(MetricFormat format) {
    final step = night.timeInBed ~/ (_axisTicks - 1);
    final offset = night.spans.last.utcOffset;
    return [
      for (var i = 0; i < _axisTicks; i++)
        format.clock(night.start.add(step * i), offset),
    ];
  }
}

class _HypnogramPainter extends CustomPainter {
  const new({required this.night, required this.lanes, required this.colors});

  final SleepNight night;
  final List<SleepPhase> lanes;
  final AppColors colors;

  static const _barShare = 0.75;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawLine(
      Offset.zero,
      Offset(0, size.height),
      Paint()
        ..color = colors.track
        ..strokeWidth = 1,
    );
    final total = night.timeInBed.inSeconds;
    if (total <= 0) return;
    final laneHeight = size.height / lanes.length;
    final barHeight = laneHeight * _barShare;
    final radius = Radius.circular(math.min(4, barHeight / 2));

    Rect laneRect(SleepPhase phase, DateTime start, DateTime end) {
      final lane = lanes.indexOf(phase);
      final left = start.difference(night.start).inSeconds / total * size.width;
      final right = end.difference(night.start).inSeconds / total * size.width;
      final top = lane * laneHeight + (laneHeight - barHeight) / 2;
      return Rect.fromLTRB(
        left,
        top,
        math.max(left + 1, right - 1),
        top + barHeight,
      );
    }

    for (final gap in night.gaps) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          laneRect(SleepPhase.awake, gap.start, gap.start.add(gap.duration)),
          radius,
        ),
        Paint()..color = colors.track,
      );
    }
    for (final span in night.spans) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          laneRect(span.phase, span.start, span.end),
          radius,
        ),
        Paint()..color = span.phase.color(colors),
      );
    }
  }

  @override
  bool shouldRepaint(_HypnogramPainter old) =>
      old.night != night ||
      !listEquals(old.lanes, lanes) ||
      old.colors != colors;
}
